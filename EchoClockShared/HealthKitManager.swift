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

/// 负责 HealthKit 权限申请与 Apple Watch 心率读取状态管理。
@MainActor
final class HealthKitManager: NSObject, ObservableObject {
    static let shared = HealthKitManager()

    /// 最新心率（BPM）
    @Published private(set) var latestHeartRate: Double = 0
    /// 当前心率是否不是 Apple Watch 真实来源。
    @Published private(set) var isUsingMockData: Bool = false
    /// HealthKit 是否可用
    @Published private(set) var isHealthKitAvailable: Bool = false
    /// 授权是否已完成
    @Published private(set) var isAuthorized: Bool = false
    /// 当前心率来源描述
    @Published private(set) var heartRateSourceDescription: String = "等待数据"

    private let healthStore = HKHealthStore()
    private var heartRateQuery: HKObserverQuery?
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
        isUsingMockData = false
        heartRateSourceDescription = "Apple Watch 回传"
    }

    // MARK: - 权限申请

    /// 异步申请 HealthKit 读取权限（心率 + 睡眠分析）
    func requestHealthKitAuthorization() async -> Bool {
        guard isHealthKitAvailable else {
            isUsingMockData = false
            heartRateSourceDescription = "等待 Apple Watch 心率"
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
            isUsingMockData = false
            heartRateSourceDescription = "等待 Apple Watch 心率"
            return false
        }
    }

    // MARK: - 心率监测

    /// 开始持续监测心率；iPhone 端等待 Apple Watch 回传，Watch 端启动实时采集。
    func startHeartRateMonitoring(onSample: @escaping (HeartRateSample) -> Void) {
        stopHeartRateMonitoring()
        onSampleHandler = onSample

        if isHealthKitAvailable && isAuthorized {
            #if os(watchOS)
            #if targetEnvironment(simulator)
            waitForRealWearableHeartRate()
            #else
            startWorkoutHeartRateSession(onSample: onSample)
            #endif
            #else
            waitForRealWearableHeartRate()
            #endif
        } else {
            waitForRealWearableHeartRate()
        }
    }

    /// 停止心率监测
    func stopHeartRateMonitoring() {
        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }
        onSampleHandler = nil

        #if os(watchOS)
        stopWorkoutHeartRateSession()
        #endif
    }

    private func waitForRealWearableHeartRate() {
        latestHeartRate = 0
        isUsingMockData = false
        heartRateSourceDescription = "等待 Apple Watch 心率"
    }

    #if os(watchOS)
    // MARK: - Watch 后台实时心率采集

    /// Apple Watch 真机后台持续采集心率需要依托 workout session。
    private func startWorkoutHeartRateSession(onSample: @escaping (HeartRateSample) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            waitForRealWearableHeartRate()
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
                        self.waitForRealWearableHeartRate()
                    }
                }
            }
        } catch {
            print("[HealthKitManager] Workout session 创建失败: \(error.localizedDescription)")
            waitForRealWearableHeartRate()
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
}
