//
//  HealthKitManager.swift
//  EchoClockShared
//
//  HealthKit 健康数据管理 — 心率读取与模拟数据生成
//

import Foundation
import Combine
import HealthKit

// MARK: - 心率样本

/// 单次心率读数
struct HeartRateSample: Sendable {
    let beatsPerMinute: Double
    let timestamp: Date
}

#if os(watchOS)
extension HealthKitManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            switch toState {
            case .running:
                self.heartRateSourceDescription = "Apple Watch 实时心率"
            case .ended:
                self.heartRateSourceDescription = "Workout 已结束"
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("[HealthKitManager] Workout session 失败: \(error.localizedDescription)")
        Task { @MainActor in
            self.heartRateSourceDescription = "Workout 采集失败"
        }
    }
}

extension HealthKitManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(heartRateType) else { return }

        let statistics = workoutBuilder.statistics(for: heartRateType)
        Task { @MainActor in
            self.processWorkoutStatistics(statistics)
        }
    }
}
#endif

// MARK: - HealthKit 管理器

/// 负责 HealthKit 权限申请、心率实时查询，以及在模拟器上自动切换 Mock 数据
@MainActor
final class HealthKitManager: NSObject, ObservableObject {
    static let shared = HealthKitManager()

    /// 最新心率（BPM）
    @Published private(set) var latestHeartRate: Double = 0
    /// 是否正在使用模拟数据
    @Published private(set) var isUsingMockData: Bool = false
    /// HealthKit 是否可用
    @Published private(set) var isHealthKitAvailable: Bool = false
    /// 授权是否已完成
    @Published private(set) var isAuthorized: Bool = false
    /// 当前心率来源描述
    @Published private(set) var heartRateSourceDescription: String = "等待数据"

    private let healthStore = HKHealthStore()
    private var heartRateQuery: HKObserverQuery?
    private var mockTimer: Timer?
    private var mockBaseline: Double = 58
    private var mockElapsedSeconds: Int = 0
    private var onSampleHandler: ((HeartRateSample) -> Void)?

    #if os(watchOS)
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    #endif

    private override init() {
        isHealthKitAvailable = HKHealthStore.isHealthDataAvailable()
        super.init()
    }

    /// 由 WatchConnectivity 等外部模块更新显示用的心率值
    func updateLatestHeartRate(_ bpm: Double) {
        latestHeartRate = bpm
        heartRateSourceDescription = "Apple Watch 回传"
    }

    // MARK: - 权限申请

    /// 异步申请 HealthKit 读取权限（心率 + 睡眠分析）
    func requestHealthKitAuthorization() async -> Bool {
        guard isHealthKitAvailable else {
            isUsingMockData = true
            return false
        }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]
        var shareTypes: Set<HKSampleType> = []
        #if os(watchOS)
        shareTypes.insert(HKObjectType.workoutType())
        #endif

        do {
            try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
            isAuthorized = true
            return true
        } catch {
            print("[HealthKitManager] 授权失败: \(error.localizedDescription)")
            isAuthorized = false
            isUsingMockData = true
            return false
        }
    }

    // MARK: - 心率监测

    /// 开始持续监测心率；若无法读取真实数据则自动启用 Mock 生成器
    func startHeartRateMonitoring(onSample: @escaping (HeartRateSample) -> Void) {
        stopHeartRateMonitoring()
        onSampleHandler = onSample

        if isHealthKitAvailable && isAuthorized {
            #if os(watchOS)
            #if targetEnvironment(simulator)
            startMockHeartRateGenerator(onSample: onSample)
            #else
            startWorkoutHeartRateSession(onSample: onSample)
            #endif
            #else
            startRealHeartRateQuery(onSample: onSample)
            #endif
        } else {
            startMockHeartRateGenerator(onSample: onSample)
        }
    }

    /// 停止心率监测
    func stopHeartRateMonitoring() {
        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }
        mockTimer?.invalidate()
        mockTimer = nil
        onSampleHandler = nil

        #if os(watchOS)
        stopWorkoutHeartRateSession()
        #endif
    }

    // MARK: - 真实心率查询

    private func startRealHeartRateQuery(onSample: @escaping (HeartRateSample) -> Void) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            startMockHeartRateGenerator(onSample: onSample)
            return
        }

        // 先尝试读取最近一条样本，验证是否有数据
        Task {
            let hasData = await fetchLatestHeartRateSample(type: heartRateType) != nil
            if hasData {
                isUsingMockData = false
                heartRateSourceDescription = "HealthKit 历史心率"
                enableBackgroundDelivery(for: heartRateType)
                setupObserverQuery(type: heartRateType, onSample: onSample)
                // 立即拉取一次最新值
                await pollLatestHeartRate(type: heartRateType, onSample: onSample)
            } else {
                // 无真实数据（常见于模拟器）→ 切换 Mock
                print("[HealthKitManager] 无真实心率数据，切换至 Mock 模式")
                isUsingMockData = true
                startMockHeartRateGenerator(onSample: onSample)
            }
        }
    }

    private func enableBackgroundDelivery(for type: HKQuantityType) {
        healthStore.enableBackgroundDelivery(for: type, frequency: .immediate) { _, error in
            if let error {
                print("[HealthKitManager] 后台交付启用失败: \(error.localizedDescription)")
            }
        }
    }

    private func setupObserverQuery(type: HKQuantityType, onSample: @escaping (HeartRateSample) -> Void) {
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, _, error in
            if let error {
                print("[HealthKitManager] Observer 错误: \(error.localizedDescription)")
                return
            }
            Task { @MainActor [weak self] in
                await self?.pollLatestHeartRate(type: type, onSample: onSample)
            }
        }
        heartRateQuery = query
        healthStore.execute(query)
    }

    private func fetchLatestHeartRateSample(type: HKQuantityType) async -> HeartRateSample? {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    print("[HealthKitManager] 查询失败: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                guard
                    let sample = samples?.first as? HKQuantitySample
                else {
                    continuation.resume(returning: nil)
                    return
                }
                let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: HeartRateSample(beatsPerMinute: bpm, timestamp: sample.startDate))
            }
            healthStore.execute(query)
        }
    }

    private func pollLatestHeartRate(type: HKQuantityType, onSample: @escaping (HeartRateSample) -> Void) async {
        guard let sample = await fetchLatestHeartRateSample(type: type) else {
            // 查询成功但无数据 → Mock
            if !isUsingMockData {
                isUsingMockData = true
                startMockHeartRateGenerator(onSample: onSample)
            }
            return
        }
        latestHeartRate = sample.beatsPerMinute
        heartRateSourceDescription = "HealthKit 历史心率"
        onSample(sample)
    }

    #if os(watchOS)
    // MARK: - Watch 后台实时心率采集

    /// Apple Watch 真机后台持续采集心率需要依托 workout session。
    private func startWorkoutHeartRateSession(onSample: @escaping (HeartRateSample) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            startMockHeartRateGenerator(onSample: onSample)
            return
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .mindAndBody
        configuration.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )
            session.delegate = self
            builder.delegate = self

            workoutSession = session
            workoutBuilder = builder
            isUsingMockData = false
            heartRateSourceDescription = "Apple Watch 实时心率"

            let startDate = Date()
            session.startActivity(with: startDate)
            builder.beginCollection(withStart: startDate) { [weak self] _, error in
                if let error {
                    print("[HealthKitManager] Workout 采集启动失败: \(error.localizedDescription)")
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.startRealHeartRateQuery(onSample: onSample)
                    }
                }
            }
        } catch {
            print("[HealthKitManager] Workout session 创建失败: \(error.localizedDescription)")
            startRealHeartRateQuery(onSample: onSample)
        }
    }

    private func stopWorkoutHeartRateSession() {
        let endDate = Date()
        workoutSession?.end()
        workoutBuilder?.endCollection(withEnd: endDate) { _, error in
            if let error {
                print("[HealthKitManager] Workout 采集结束失败: \(error.localizedDescription)")
            }
        }
        workoutSession = nil
        workoutBuilder = nil
    }

    private func processWorkoutStatistics(_ statistics: HKStatistics?) {
        guard
            let quantity = statistics?.mostRecentQuantity()
        else { return }

        let bpm = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        guard bpm > 0 else { return }

        let sample = HeartRateSample(beatsPerMinute: bpm, timestamp: Date())
        latestHeartRate = bpm
        isUsingMockData = false
        heartRateSourceDescription = "Apple Watch 实时心率"
        onSampleHandler?(sample)
    }
    #endif

    // MARK: - Mock 心率生成器（模拟器测试用）

    /// 模拟心率：前 2 分钟维持低基线，之后逐渐上升以触发浅睡眠判定
    private func startMockHeartRateGenerator(onSample: @escaping (HeartRateSample) -> Void) {
        isUsingMockData = true
        heartRateSourceDescription = "模拟心率"
        mockElapsedSeconds = 0
        mockBaseline = Double.random(in: 54...62)

        mockTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.mockElapsedSeconds += 5
                let bpm = self.generateMockBPM()
                let sample = HeartRateSample(beatsPerMinute: bpm, timestamp: Date())
                self.latestHeartRate = bpm
                onSample(sample)
            }
        }
        // 立即产生第一个样本
        let initial = HeartRateSample(beatsPerMinute: mockBaseline, timestamp: Date())
        latestHeartRate = mockBaseline
        onSample(initial)
    }

    private func generateMockBPM() -> Double {
        // 模拟睡眠周期：前 120 秒低心率，之后逐渐回升（模拟浅睡眠）
        if mockElapsedSeconds < 120 {
            return mockBaseline + Double.random(in: -2...3)
        } else {
            let progress = Double(mockElapsedSeconds - 120) / 60.0
            let rise = progress * 8.0 // 约 8 BPM 上升
            return mockBaseline + rise + Double.random(in: -1...4)
        }
    }
}
