//
//  AlarmViewModel.swift
//  EchoClock
//
//  iPhone 端闹钟业务协调器 — 整合各 Manager 状态
//

import Foundation
import Combine
import SwiftUI

// MARK: - iPhone 闹钟 ViewModel

@MainActor
final class AlarmViewModel: ObservableObject {
    /// 当前闹钟配置
    @Published var alarm: Alarm = Alarm()
    /// 实时时钟显示
    @Published var currentTime: Date = Date()
    /// 是否正在响铃
    @Published var isAlarmRinging: Bool = false
    /// HealthKit 授权状态描述
    @Published var healthAuthStatus: String = "未授权"
    /// Watch 连接状态
    @Published var watchStatus: String = "未连接"
    /// 最新心率显示
    @Published var latestHeartRate: Double = 0
    /// 睡眠监测状态
    @Published var monitoringStatus: String = "待机中"
    /// 最近一次收到 Watch 端信号的描述
    @Published var wearableSignalStatus: String = "等待手表信号"

    private var clockTimer: Timer?
    private let alarmStorageKey = "EchoClock.alarm"

    init() {
        loadAlarm()
        setupConnectivityCallbacks()
        startClock()
    }

    // MARK: - 初始化

    /// 申请 HealthKit 权限并更新状态
    func requestPermissions() async {
        let granted = await HealthKitManager.shared.requestHealthKitAuthorization()
        healthAuthStatus = granted ? "已授权" : "使用模拟数据"
    }

    // MARK: - 闹钟控制

    /// 切换闹钟开关
    func toggleAlarm() {
        alarm.isOn.toggle()
        saveAlarm()
        if alarm.isOn {
            activateAlarm()
        } else {
            deactivateAlarm()
        }
    }

    /// 更新目标唤醒时间
    func updateTargetTime(_ newTime: Date) {
        updateWakeEndTime(newTime)
    }

    /// 更新智能唤醒范围开始时间
    func updateWakeStartTime(_ newTime: Date) {
        alarm.wakeStartTime = newTime
        alarm = alarm.normalized()
        saveAlarm()
        if alarm.isOn {
            syncToWatch()
        }
    }

    /// 更新智能唤醒范围截止时间
    func updateWakeEndTime(_ newTime: Date) {
        alarm.wakeEndTime = newTime
        alarm = alarm.normalized()
        saveAlarm()
        if alarm.isOn {
            syncToWatch()
        }
    }

    /// 更新智能唤醒窗口（分钟）
    func updateWindowMinutes(_ minutes: Int) {
        alarm.wakeEndTime = Calendar.current.date(byAdding: .minute, value: minutes, to: alarm.wakeStartTime) ?? alarm.wakeEndTime
        saveAlarm()
        if alarm.isOn {
            syncToWatch()
        }
    }

    /// 更新预设铃声
    func updateSound(_ sound: AlarmSound) {
        alarm.sound = sound
        saveAlarm()
        if alarm.isOn {
            syncToWatch()
        }
    }

    /// 预览当前铃声
    func previewSelectedSound() {
        AlarmSoundService.shared.preview(sound: alarm.sound)
    }

    /// 主动探测 Watch App 是否在线。
    func connectWearable() {
        wearableSignalStatus = "正在连接 Watch..."
        WatchConnectivityManager.shared.sendWearablePing()
        if alarm.isOn {
            WatchConnectivityManager.shared.sendStartMonitoring(alarm: alarm)
        } else {
            syncToWatch()
        }
    }

    /// 关闭正在响铃的闹钟
    func dismissAlarm() {
        isAlarmRinging = false
        AlarmSoundService.shared.stopRinging()
        TTSService.shared.speakMorningGreeting()
        WatchConnectivityManager.shared.sendAlarmDismissed()
        SleepAnalyzer.shared.resetTriggerState()
    }

    // MARK: - 私有逻辑

    private func activateAlarm() {
        alarm = alarm.normalized()
        saveAlarm()
        syncToWatch()
        WatchConnectivityManager.shared.sendStartMonitoring(alarm: alarm)
        startHeartRateMonitoringIfNeeded()
    }

    private func deactivateAlarm() {
        WatchConnectivityManager.shared.sendStopMonitoring()
        HealthKitManager.shared.stopHeartRateMonitoring()
        AlarmSoundService.shared.stopRinging()
        isAlarmRinging = false
        SleepAnalyzer.shared.stopMonitoring()
    }

    private func syncToWatch() {
        WatchConnectivityManager.shared.sendAlarmConfig(alarm)
    }

    private func startHeartRateMonitoringIfNeeded() {
        SleepAnalyzer.shared.startMonitoring(alarm: alarm) { [weak self] in
            Task { @MainActor [weak self] in
                self?.triggerAlarmFromPhone()
            }
        }
        HealthKitManager.shared.startHeartRateMonitoring { sample in
            Task { @MainActor in
                SleepAnalyzer.shared.processHeartRateSample(sample)
            }
        }
    }

    private func triggerAlarmFromPhone() {
        guard !isAlarmRinging else { return }
        isAlarmRinging = true
        AlarmSoundService.shared.startRinging(sound: alarm.sound)
    }

    private func setupConnectivityCallbacks() {
        let wc = WatchConnectivityManager.shared
        wc.onSmartWakeTriggered = { [weak self] in
            Task { @MainActor [weak self] in
                self?.triggerAlarmFromPhone()
            }
        }
        wc.onAlarmDismissed = { [weak self] in
            Task { @MainActor [weak self] in
                self?.isAlarmRinging = false
                AlarmSoundService.shared.stopRinging()
            }
        }
        wc.onWearablePong = { [weak self] in
            Task { @MainActor [weak self] in
                self?.wearableSignalStatus = "Watch 已响应"
            }
        }
        wc.onStopMonitoring = { [weak self] in
            Task { @MainActor [weak self] in
                self?.alarm.isOn = false
                self?.deactivateAlarm()
            }
        }
        updateWatchStatus()
    }

    private func startClock() {
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = Date()
                self.updateWatchStatus()
                self.latestHeartRate = HealthKitManager.shared.latestHeartRate
                self.monitoringStatus = Self.statusText(for: SleepAnalyzer.shared.state)
                self.updateWearableSignalStatus()
            }
        }
    }

    private static func statusText(for state: SleepMonitoringState) -> String {
        switch state {
        case .idle: return "待机中"
        case .waitingForWindow: return "等待唤醒范围"
        case .monitoring: return "正在分析浅睡眠"
        case .triggered: return "已触发唤醒"
        }
    }

    private func updateWatchStatus() {
        let wc = WatchConnectivityManager.shared
        if !wc.isWatchPaired {
            watchStatus = "未配对 Apple Watch"
        } else if !wc.isWatchAppInstalled {
            watchStatus = "Watch App 未安装"
        } else if wc.isSessionActivated && (wc.isReachable || isRecentWearableSignal) {
            watchStatus = "Watch 已连接"
        } else if wc.isSessionActivated {
            watchStatus = "已配对，等待手表 App"
        } else {
            watchStatus = "等待 Watch 连接"
        }
    }

    private var isRecentWearableSignal: Bool {
        guard let date = WatchConnectivityManager.shared.lastWearableSignalAt else { return false }
        return Date().timeIntervalSince(date) < 120
    }

    private func updateWearableSignalStatus() {
        guard let date = WatchConnectivityManager.shared.lastWearableSignalAt else {
            wearableSignalStatus = "尚未收到 Watch 信号"
            return
        }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 3 {
            wearableSignalStatus = "刚收到 Watch 信号"
        } else if seconds < 120 {
            wearableSignalStatus = "\(seconds) 秒前收到 Watch 信号"
        } else {
            wearableSignalStatus = "Watch 信号已超时"
        }
    }

    private func loadAlarm() {
        guard let data = UserDefaults.standard.data(forKey: alarmStorageKey),
              let savedAlarm = try? JSONDecoder().decode(Alarm.self, from: data) else { return }
        alarm = savedAlarm.normalized()
    }

    private func saveAlarm() {
        guard let data = try? JSONEncoder().encode(alarm) else { return }
        UserDefaults.standard.set(data, forKey: alarmStorageKey)
    }
}
