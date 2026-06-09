//
//  WatchAlarmViewModel.swift
//  EchoClockWatch Watch App
//
//  Watch 端闹钟业务协调器
//

import Foundation
import Combine
import WatchKit

// MARK: - Watch 闹钟 ViewModel

@MainActor
final class WatchAlarmViewModel: ObservableObject {
    @Published var alarm: Alarm = Alarm()
    @Published var heartRate: Double = 0
    @Published var isMonitoring: Bool = false
    @Published var isWakeTriggered: Bool = false
    @Published var monitoringState: SleepMonitoringState = .idle
    @Published var isUsingMockData: Bool = false
    @Published var heartRateSource: String = "等待数据"

    init() {
        setupConnectivityCallbacks()
        observeHealthKit()
        WatchConnectivityManager.shared.sendWearablePong()
    }

    func requestPermissions() async {
        _ = await HealthKitManager.shared.requestHealthKitAuthorization()
        isUsingMockData = HealthKitManager.shared.isUsingMockData
        WatchConnectivityManager.shared.sendWearablePong()
    }

    private func setupConnectivityCallbacks() {
        let wc = WatchConnectivityManager.shared

        wc.onAlarmConfigReceived = { [weak self] receivedAlarm in
            Task { @MainActor [weak self] in
                self?.handleAlarmUpdate(receivedAlarm)
            }
        }

        wc.onStartMonitoring = { [weak self] receivedAlarm in
            Task { @MainActor [weak self] in
                self?.alarm = receivedAlarm.normalized()
                self?.startMonitoring()
            }
        }

        wc.onStopMonitoring = { [weak self] in
            Task { @MainActor [weak self] in
                self?.stopMonitoring()
            }
        }

        wc.onAlarmDismissed = { [weak self] in
            Task { @MainActor [weak self] in
                self?.dismissWake()
            }
        }

        // 读取上次同步的 ApplicationContext
        if let cached = wc.receivedAlarm {
            handleAlarmUpdate(cached)
        }
    }

    private func observeHealthKit() {
        // 通过 SleepAnalyzer 和 HealthKitManager 的 Published 属性驱动 UI
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                heartRate = HealthKitManager.shared.latestHeartRate
                monitoringState = SleepAnalyzer.shared.state
                isUsingMockData = HealthKitManager.shared.isUsingMockData
                heartRateSource = HealthKitManager.shared.heartRateSourceDescription
            }
        }
    }

    private func handleAlarmUpdate(_ receivedAlarm: Alarm) {
        WatchConnectivityManager.shared.sendWearablePong()
        alarm = receivedAlarm.normalized()
        if alarm.isOn {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    private func startMonitoring() {
        alarm = alarm.normalized()
        isMonitoring = true
        isWakeTriggered = false

        SleepAnalyzer.shared.startMonitoring(alarm: alarm) { [weak self] in
            Task { @MainActor [weak self] in
                self?.triggerWakeOnWatch()
            }
        }

        HealthKitManager.shared.startHeartRateMonitoring { sample in
            Task { @MainActor in
                SleepAnalyzer.shared.processHeartRateSample(sample)
                WatchConnectivityManager.shared.sendHeartRateUpdate(sample.beatsPerMinute)
            }
        }
    }

    private func stopMonitoring() {
        isMonitoring = false
        HealthKitManager.shared.stopHeartRateMonitoring()
        SleepAnalyzer.shared.stopMonitoring()
    }

    private func triggerWakeOnWatch() {
        guard !isWakeTriggered else { return }
        isWakeTriggered = true

        // Watch 原生触觉反馈，使用系统支持的强提醒类型循环播放。
        WKInterfaceDevice.current().play(.notification)

        // 持续震动直到用户关闭
        Task {
            while isWakeTriggered {
                try? await Task.sleep(for: .seconds(2))
                if isWakeTriggered {
                    WKInterfaceDevice.current().play(.directionUp)
                    WKInterfaceDevice.current().play(.notification)
                }
            }
        }

        // 通知 iPhone 协同响铃
        WatchConnectivityManager.shared.sendSmartWakeTriggered(alarmID: alarm.id)
    }

    func dismissWake() {
        isWakeTriggered = false
        SleepAnalyzer.shared.resetTriggerState()
    }
}
