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

// MARK: - HealthKit 管理器

/// 负责 HealthKit 权限申请、心率实时查询，以及在模拟器上自动切换 Mock 数据
@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    /// 最新心率（BPM）
    @Published private(set) var latestHeartRate: Double = 0
    /// 是否正在使用模拟数据
    @Published private(set) var isUsingMockData: Bool = false
    /// HealthKit 是否可用
    @Published private(set) var isHealthKitAvailable: Bool = false
    /// 授权是否已完成
    @Published private(set) var isAuthorized: Bool = false

    private let healthStore = HKHealthStore()
    private var heartRateQuery: HKObserverQuery?
    private var mockTimer: Timer?
    private var mockBaseline: Double = 58
    private var mockElapsedSeconds: Int = 0
    private var onSampleHandler: ((HeartRateSample) -> Void)?

    private init() {
        isHealthKitAvailable = HKHealthStore.isHealthDataAvailable()
    }

    /// 由 WatchConnectivity 等外部模块更新显示用的心率值
    func updateLatestHeartRate(_ bpm: Double) {
        latestHeartRate = bpm
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

        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
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
            startRealHeartRateQuery(onSample: onSample)
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
        onSample(sample)
    }

    // MARK: - Mock 心率生成器（模拟器测试用）

    /// 模拟心率：前 2 分钟维持低基线，之后逐渐上升以触发浅睡眠判定
    private func startMockHeartRateGenerator(onSample: @escaping (HeartRateSample) -> Void) {
        isUsingMockData = true
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
