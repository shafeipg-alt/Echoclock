//
//  SleepAnalyzer.swift
//  EchoClockShared
//
//  浅睡眠智能判定算法 — 基于心率基线对比与微动检测
//

import Foundation
import Combine
#if os(watchOS)
import CoreMotion
#endif

// MARK: - 监测状态

/// 睡眠分析器的运行状态
enum SleepMonitoringState: Sendable, Equatable {
    case idle
    case waitingForWindow
    case monitoring
    case triggered
}

// MARK: - 浅睡眠分析器

/// 在唤醒窗口期内分析心率趋势，判定是否进入浅睡眠并触发智能唤醒
@MainActor
final class SleepAnalyzer: ObservableObject {
    static let shared = SleepAnalyzer()

    /// 当前监测状态
    @Published private(set) var state: SleepMonitoringState = .idle
    /// 当前心率基线（BPM）
    @Published private(set) var baselineHeartRate: Double = 0
    /// 最近一次心率读数
    @Published private(set) var currentHeartRate: Double = 0
    /// 是否检测到身体微动
    @Published private(set) var motionDetected: Bool = false
    /// 最近一次智能唤醒触发原因
    @Published private(set) var lastTriggerReason: String = ""

    /// 心率上升触发阈值（相对基线的百分比，默认 10%）
    var heartRateRiseThreshold: Double = 0.10
    /// 浅睡眠常见静息心率区间；用于基线不足时的绝对判定。
    var lightSleepHeartRateRange: ClosedRange<Double> = 60...72
    /// 深睡低心率上限。低于该值时优先等待，不提前唤醒。
    var deepSleepHeartRateUpperBound: Double = 58
    /// 基线采样窗口（秒），默认 30 分钟
    var baselineWindowSeconds: TimeInterval = 30 * 60

    private var heartRateHistory: [HeartRateSample] = []
    private var currentAlarm: Alarm?
    private var windowCheckTimer: Timer?
    private var hasTriggered = false
    private var onSmartWakeUp: (() -> Void)?

    #if os(watchOS)
    private let motionManager = CMMotionManager()
    #endif

    private init() {}

    // MARK: - 公开 API

    /// 绑定闹钟并开始周期性窗口检查
    func startMonitoring(alarm: Alarm, onSmartWakeUp: @escaping () -> Void) {
        stopMonitoring()
        currentAlarm = alarm.normalized()
        self.onSmartWakeUp = onSmartWakeUp
        hasTriggered = false
        state = .waitingForWindow
        heartRateHistory.removeAll()
        baselineHeartRate = 0
        lastTriggerReason = ""
        motionDetected = false

        #if os(watchOS)
        startMotionDetection()
        #endif

        // 每 10 秒检查是否进入唤醒窗口
        windowCheckTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkWakeWindow()
            }
        }
        checkWakeWindow()
    }

    /// 停止监测
    func stopMonitoring() {
        windowCheckTimer?.invalidate()
        windowCheckTimer = nil
        currentAlarm = nil
        onSmartWakeUp = nil
        state = .idle
        heartRateHistory.removeAll()

        #if os(watchOS)
        stopMotionDetection()
        #endif
    }

    /// 接收新的心率样本并进行分析
    func processHeartRateSample(_ sample: HeartRateSample) {
        guard !hasTriggered else { return }

        currentHeartRate = sample.beatsPerMinute
        heartRateHistory.append(sample)
        trimHistory()

        guard state == .monitoring else { return }

        updateBaseline()
        evaluateLightSleep()
    }

    /// 重置触发状态（闹钟关闭后调用）
    func resetTriggerState() {
        hasTriggered = false
        if currentAlarm?.isOn == true {
            state = .waitingForWindow
        } else {
            state = .idle
        }
    }

    // MARK: - 窗口检查

    private func checkWakeWindow() {
        guard let alarm = currentAlarm, alarm.isOn, !hasTriggered else { return }

        if alarm.isInWakeWindow() {
            if state != .monitoring {
                state = .monitoring
                print("[SleepAnalyzer] 进入智能唤醒窗口: \(alarm.formattedWakeWindow)")
            }
        } else if alarm.isPastWakeDeadline() {
            // 已过范围截止时间且未检测到浅睡眠，按用户设定兜底唤醒。
            triggerSmartWakeUp(reason: "已达智能唤醒范围截止时间")
        }
    }

    // MARK: - 基线计算

    private func updateBaseline() {
        let cutoff = Date().addingTimeInterval(-baselineWindowSeconds)
        let baselineSamples = heartRateHistory.filter { $0.timestamp >= cutoff }

        guard !baselineSamples.isEmpty else { return }
        let sum = baselineSamples.reduce(0.0) { $0 + $1.beatsPerMinute }
        baselineHeartRate = sum / Double(baselineSamples.count)
    }

    private func trimHistory() {
        let cutoff = Date().addingTimeInterval(-baselineWindowSeconds - 60)
        heartRateHistory.removeAll { $0.timestamp < cutoff }
    }

    // MARK: - 浅睡眠判定

    private func evaluateLightSleep() {
        if lightSleepHeartRateRange.contains(currentHeartRate) {
            triggerSmartWakeUp(reason: String(
                format: "心率 %.0f BPM 处于浅睡眠唤醒区间 %.0f-%.0f BPM",
                currentHeartRate,
                lightSleepHeartRateRange.lowerBound,
                lightSleepHeartRateRange.upperBound
            ))
            return
        }

        if currentHeartRate <= deepSleepHeartRateUpperBound {
            return
        }

        guard baselineHeartRate > 0 else { return }

        let riseRatio = (currentHeartRate - baselineHeartRate) / baselineHeartRate

        // 条件 1：心率相对基线上升超过阈值（默认 10%）
        if riseRatio >= heartRateRiseThreshold {
            triggerSmartWakeUp(reason: String(
                format: "心率上升 %.1f%%（基线 %.0f → 当前 %.0f BPM）",
                riseRatio * 100, baselineHeartRate, currentHeartRate
            ))
            return
        }

        // 条件 2：检测到身体微动（watchOS CoreMotion）
        if motionDetected {
            triggerSmartWakeUp(reason: "检测到身体微动")
        }
    }

    /// 触发智能唤醒
    func triggerSmartWakeUp(reason: String) {
        guard !hasTriggered else { return }
        hasTriggered = true
        state = .triggered
        lastTriggerReason = reason
        print("[SleepAnalyzer] 智能唤醒触发 — \(reason)")
        onSmartWakeUp?()
    }

    // MARK: - 微动检测（watchOS）

    #if os(watchOS)
    private func startMotionDetection() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 1.0
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            Task { @MainActor [weak self] in
                guard let self, let data else { return }
                let magnitude = sqrt(
                    data.acceleration.x * data.acceleration.x +
                    data.acceleration.y * data.acceleration.y +
                    data.acceleration.z * data.acceleration.z
                )
                // 重力约 1g；显著偏离表示微动
                if abs(magnitude - 1.0) > 0.15 {
                    self.motionDetected = true
                }
            }
        }
    }

    private func stopMotionDetection() {
        motionManager.stopAccelerometerUpdates()
        motionDetected = false
    }
    #endif
}
