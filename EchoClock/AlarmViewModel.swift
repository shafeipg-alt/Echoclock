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
    /// 用户创建的闹钟列表
    @Published private(set) var alarms: [Alarm] = []
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
    /// 心率数据来源
    @Published var heartRateSourceStatus: String = "等待数据"
    /// 最近一次唤醒判定原因
    @Published var triggerReasonStatus: String = "尚未触发"
    /// 基于真实心率数据估算的数据质量评分
    @Published var heartRateQualityScore: Int?
    /// 最近真实心率样本，用于首页动态波形。
    @Published var recentHeartRates: [Double] = []

    private var clockTimer: Timer?
    private let alarmStorageKey = "EchoClock.alarm"
    private let alarmsStorageKey = "EchoClock.alarms"
    private let didSeedDefaultAlarmKey = "EchoClock.didSeedDefaultAlarm"

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
        if alarm.isOn {
            alarms = alarms.map { item in
                var copy = item
                copy.isOn = item.id == alarm.id
                return copy
            }
        }
        saveAlarm()
        if alarm.isOn {
            activateAlarm()
        } else {
            deactivateAlarm()
        }
    }

    /// 选中一个闹钟用于编辑或控制。
    func selectAlarm(_ selectedAlarm: Alarm) {
        alarm = selectedAlarm.normalized()
    }

    /// 新增一个闹钟，并将其设为当前编辑对象。
    @discardableResult
    func addAlarm() -> Alarm {
        let offsetMinutes = min(alarms.count, 4) * 15
        let startTime = Calendar.current.date(byAdding: .minute, value: offsetMinutes, to: Alarm.defaultWakeStartTime()) ?? Alarm.defaultWakeStartTime()
        let endTime = Calendar.current.date(byAdding: .minute, value: offsetMinutes, to: Alarm.defaultWakeEndTime()) ?? Alarm.defaultWakeEndTime()
        let newAlarm = Alarm(wakeStartTime: startTime, wakeEndTime: endTime, isOn: false, sound: alarm.sound, repeatWeekdays: Alarm.defaultRepeatWeekdays).normalized()
        alarms.append(newAlarm)
        alarm = newAlarm
        persistAlarmState()
        return newAlarm
    }

    /// 删除一个闹钟。若删除的是正在监测的闹钟，会同步停止监测。
    func deleteAlarm(_ targetAlarm: Alarm) {
        let wasCurrent = alarm.id == targetAlarm.id
        let shouldStopMonitoring = targetAlarm.isOn
        alarms.removeAll { $0.id == targetAlarm.id }

        if shouldStopMonitoring {
            deactivateAlarm()
        }

        if wasCurrent {
            alarm = alarms.first ?? Alarm(isOn: false)
        }

        persistAlarmState()
    }

    /// 切换指定闹钟。
    func toggleAlarm(_ targetAlarm: Alarm) {
        selectAlarm(targetAlarm)
        toggleAlarm()
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

    /// 更新闹钟重复周期。
    func updateRepeatWeekdays(_ weekdays: Set<Int>) {
        alarm.repeatWeekdays = weekdays
        saveAlarm()
        if alarm.isOn {
            syncToWatch()
        }
    }

    /// 切换某一天是否重复。
    func toggleRepeatWeekday(_ weekday: Int) {
        var weekdays = alarm.repeatWeekdays
        if weekdays.contains(weekday) {
            weekdays.remove(weekday)
        } else {
            weekdays.insert(weekday)
        }
        updateRepeatWeekdays(weekdays)
    }

    /// 应用一个常用闹钟预设。
    func applyPresetWakeWindow(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int, turnOn: Bool = true) {
        alarm.wakeStartTime = Self.clockTime(hour: startHour, minute: startMinute)
        alarm.wakeEndTime = Self.clockTime(hour: endHour, minute: endMinute)
        alarm = alarm.normalized()
        saveAlarm()
        if turnOn && !alarm.isOn {
            alarm.isOn = true
            alarms = alarms.map { item in
                var copy = item
                copy.isOn = item.id == alarm.id
                return copy
            }
            saveAlarm()
            activateAlarm()
        } else if alarm.isOn {
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
                self?.saveAlarm()
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
                self.heartRateSourceStatus = HealthKitManager.shared.heartRateSourceDescription
                self.triggerReasonStatus = SleepAnalyzer.shared.lastTriggerReason.isEmpty ? "尚未触发" : SleepAnalyzer.shared.lastTriggerReason
                self.updateWearableSignalStatus()
                self.updateHeartRateQuality()
            }
        }
    }

    private static func statusText(for state: SleepMonitoringState) -> String {
        switch state {
        case .idle: return "待机中"
        case .waitingForWindow: return "已开启，等待进入范围"
        case .monitoring: return "范围内，正在分析心率"
        case .triggered: return "已触发唤醒"
        }
    }

    private static func clockTime(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        let today = Calendar.current.date(from: components) ?? Date()
        if today <= Date() {
            return Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        }
        return today
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
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: alarmsStorageKey),
           let savedAlarms = try? decoder.decode([Alarm].self, from: data) {
            alarms = savedAlarms.map { $0.normalized() }
            alarm = alarms.first(where: \.isOn) ?? alarms.first ?? Alarm()
            return
        }

        guard let data = UserDefaults.standard.data(forKey: alarmStorageKey),
              let savedAlarm = try? decoder.decode(Alarm.self, from: data) else {
            seedDefaultAlarmIfNeeded()
            return
        }
        alarm = savedAlarm.normalized()
        alarms = [alarm]
        persistAlarmState()
    }

    private func saveAlarm() {
        upsertCurrentAlarm()
        persistAlarmState()
    }

    private func upsertCurrentAlarm() {
        alarm = alarm.normalized()
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index] = alarm
        } else {
            alarms.append(alarm)
        }
    }

    private func persistAlarmState() {
        guard let data = try? JSONEncoder().encode(alarm) else { return }
        UserDefaults.standard.set(data, forKey: alarmStorageKey)
        guard let alarmsData = try? JSONEncoder().encode(alarms) else { return }
        UserDefaults.standard.set(alarmsData, forKey: alarmsStorageKey)
    }

    private func seedDefaultAlarmIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: didSeedDefaultAlarmKey) else { return }
        let defaultAlarm = Alarm(
            wakeStartTime: Alarm.defaultWakeStartTime(),
            wakeEndTime: Alarm.defaultWakeEndTime(),
            isOn: false,
            sound: .aurora,
            repeatWeekdays: Alarm.defaultRepeatWeekdays
        ).normalized()
        alarm = defaultAlarm
        alarms = [defaultAlarm]
        UserDefaults.standard.set(true, forKey: didSeedDefaultAlarmKey)
        persistAlarmState()
    }

    private func updateHeartRateQuality() {
        guard latestHeartRate > 0, !HealthKitManager.shared.isUsingMockData else {
            heartRateQualityScore = nil
            recentHeartRates.removeAll()
            return
        }

        if recentHeartRates.last != latestHeartRate {
            recentHeartRates.append(latestHeartRate)
            if recentHeartRates.count > 24 {
                recentHeartRates.removeFirst(recentHeartRates.count - 24)
            }
        }

        let sampleScore = min(40, recentHeartRates.count * 3)
        let sourceScore = heartRateSourceStatus.contains("Apple Watch") ? 35 : 25
        let stabilityScore: Int
        if recentHeartRates.count >= 3 {
            let average = recentHeartRates.reduce(0, +) / Double(recentHeartRates.count)
            let variance = recentHeartRates.reduce(0) { $0 + pow($1 - average, 2) } / Double(recentHeartRates.count)
            let standardDeviation = sqrt(variance)
            stabilityScore = max(10, 25 - Int(standardDeviation * 2))
        } else {
            stabilityScore = 12
        }
        heartRateQualityScore = min(99, sampleScore + sourceScore + stabilityScore)
    }
}
