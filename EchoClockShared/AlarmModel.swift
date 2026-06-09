//
//  AlarmModel.swift
//  EchoClockShared
//
//  EchoClock 闹钟数据模型 — iPhone 与 Apple Watch 双端共享
//

import Foundation

// MARK: - 闹钟结构体

/// 智能浅睡眠唤醒闹钟的核心数据模型
struct Alarm: Identifiable, Codable, Hashable, Sendable {
    /// 唯一标识符
    let id: UUID
    /// 智能唤醒范围开始时间（仅使用其中的时、分分量）
    var wakeStartTime: Date
    /// 智能唤醒范围截止时间（仅使用其中的时、分分量）
    var wakeEndTime: Date
    /// 闹钟是否已开启
    var isOn: Bool
    /// 闹钟铃声
    var sound: AlarmSound
    /// 重复周期，使用 Calendar weekday：1 周日，2 周一 ... 7 周六。
    var repeatWeekdays: Set<Int>

    init(
        id: UUID = UUID(),
        wakeStartTime: Date = Alarm.defaultWakeStartTime(),
        wakeEndTime: Date = Alarm.defaultWakeEndTime(),
        isOn: Bool = false,
        sound: AlarmSound = .aurora,
        repeatWeekdays: Set<Int> = Alarm.defaultRepeatWeekdays
    ) {
        self.id = id
        self.wakeStartTime = wakeStartTime
        self.wakeEndTime = wakeEndTime
        self.isOn = isOn
        self.sound = sound
        self.repeatWeekdays = repeatWeekdays
    }

    enum CodingKeys: String, CodingKey {
        case id
        case wakeStartTime
        case wakeEndTime
        case isOn
        case sound
        case repeatWeekdays
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        wakeStartTime = try container.decode(Date.self, forKey: .wakeStartTime)
        wakeEndTime = try container.decode(Date.self, forKey: .wakeEndTime)
        isOn = try container.decode(Bool.self, forKey: .isOn)
        sound = try container.decodeIfPresent(AlarmSound.self, forKey: .sound) ?? .aurora
        repeatWeekdays = try container.decodeIfPresent(Set<Int>.self, forKey: .repeatWeekdays) ?? Alarm.defaultRepeatWeekdays
    }

    /// 默认智能唤醒开始时间：早上 7:00
    static func defaultWakeStartTime() -> Date {
        defaultClockTime(hour: 7, minute: 0)
    }

    /// 默认智能唤醒截止时间：早上 8:00
    static func defaultWakeEndTime() -> Date {
        defaultClockTime(hour: 8, minute: 0)
    }

    /// 默认重复：周一到周五。
    static let defaultRepeatWeekdays: Set<Int> = [2, 3, 4, 5, 6]

    private static func defaultClockTime(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        let today = Calendar.current.date(from: components) ?? Date()
        // 若当前时间已过该时间点，则设为明天，保证默认值面向下一次唤醒。
        if today <= Date() {
            return Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        }
        return today
    }
}

// MARK: - 预设铃声

enum AlarmSound: String, CaseIterable, Codable, Hashable, Sendable {
    case aurora
    case chime
    case pulse
    case rise
    case classic

    var displayName: String {
        switch self {
        case .aurora: return "晨雾 Aurora"
        case .chime: return "清铃 Chime"
        case .pulse: return "柔波 Pulse"
        case .rise: return "渐醒 Rise"
        case .classic: return "经典 Classic"
        }
    }

    var description: String {
        switch self {
        case .aurora: return "轻柔、适合浅睡眠唤醒"
        case .chime: return "清脆、适合普通早起"
        case .pulse: return "短促节奏、适合深睡兜底"
        case .rise: return "逐步增强、适合自然醒"
        case .classic: return "传统提示音、穿透力较强"
        }
    }

    var systemSoundID: UInt32 {
        switch self {
        case .aurora: return 1005
        case .chime: return 1007
        case .pulse: return 1016
        case .rise: return 1022
        case .classic: return 1000
        }
    }
}

// MARK: - 唤醒窗口计算

extension Alarm {
    /// 今日（或明日）的实际智能唤醒范围。若截止时间早于开始时间，则视为跨午夜范围。
    func resolvedWakeWindow(from reference: Date = Date()) -> (start: Date, end: Date) {
        resolvedWakeWindow(from: reference, rollsPastDeadline: true)
    }

    private func resolvedWakeWindow(from reference: Date, rollsPastDeadline: Bool) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let startParts = calendar.dateComponents([.hour, .minute], from: wakeStartTime)
        let endParts = calendar.dateComponents([.hour, .minute], from: wakeEndTime)

        func date(on reference: Date, hour: Int?, minute: Int?) -> Date {
            var parts = calendar.dateComponents([.year, .month, .day], from: reference)
            parts.hour = hour
            parts.minute = minute
            parts.second = 0
            return calendar.date(from: parts) ?? reference
        }

        var start = date(on: reference, hour: startParts.hour, minute: startParts.minute)
        var end = date(on: reference, hour: endParts.hour, minute: endParts.minute)

        if end <= start {
            end = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        }

        if rollsPastDeadline && reference > end {
            start = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            end = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        }

        return (start, end)
    }

    /// 当前是否处于智能唤醒监测窗口内
    func isInWakeWindow(at date: Date = Date()) -> Bool {
        guard isOn, repeats(on: date) else { return false }
        let window = resolvedWakeWindow(from: date)
        return date >= window.start && date <= window.end
    }

    /// 是否已经超过本次智能唤醒范围的截止时间。
    func isPastWakeDeadline(at date: Date = Date()) -> Bool {
        guard isOn, repeats(on: date) else { return false }
        let window = resolvedWakeWindow(from: date, rollsPastDeadline: false)
        return date >= window.end
    }

    /// 当前日期是否匹配重复规则。空重复代表仅一次，仍允许本次窗口生效。
    func repeats(on date: Date = Date()) -> Bool {
        repeatWeekdays.isEmpty || repeatWeekdays.contains(Calendar.current.component(.weekday, from: date))
    }

    /// 智能唤醒范围分钟数。
    var windowMinutes: Int {
        let window = resolvedWakeWindow()
        return max(1, Calendar.current.dateComponents([.minute], from: window.start, to: window.end).minute ?? 1)
    }

    /// 格式化的开始时间字符串，如 "06:30"
    var formattedWakeStartTime: String {
        wakeStartTime.formatted(date: .omitted, time: .shortened)
    }

    /// 格式化的截止时间字符串，如 "07:00"
    var formattedWakeEndTime: String {
        wakeEndTime.formatted(date: .omitted, time: .shortened)
    }

    /// 兼容旧 UI 命名：范围截止时间。
    var formattedTargetTime: String {
        formattedWakeEndTime
    }

    /// 格式化的唤醒窗口字符串，如 "06:30 - 07:00"
    var formattedWakeWindow: String {
        let formatter = Date.FormatStyle(date: .omitted, time: .shortened)
        return "\(wakeStartTime.formatted(formatter)) - \(wakeEndTime.formatted(formatter))"
    }

    /// 格式化重复周期。
    var formattedRepeatText: String {
        let weekdays = repeatWeekdays.sorted()
        if weekdays == [2, 3, 4, 5, 6] { return "周一至周五" }
        if weekdays == [1, 2, 3, 4, 5, 6, 7] { return "每天" }
        if weekdays.isEmpty { return "仅一次" }
        let labels = [1: "周日", 2: "周一", 3: "周二", 4: "周三", 5: "周四", 6: "周五", 7: "周六"]
        return weekdays.compactMap { labels[$0] }.joined(separator: " ")
    }

    /// 今日（或明日）的实际截止唤醒时刻，供旧调用方兼容使用。
    func resolvedTargetDate(from reference: Date = Date()) -> Date {
        resolvedWakeWindow(from: reference).end
    }

    /// 今日（或明日）的实际唤醒窗口起始时间，供旧调用方兼容使用。
    func windowStartDate(from reference: Date = Date()) -> Date {
        resolvedWakeWindow(from: reference).start
    }

    /// 校验并修正常见的非法时间范围。允许跨午夜，因此只处理完全相同的开始/截止。
    func normalized() -> Alarm {
        guard formattedWakeStartTime == formattedWakeEndTime else { return self }
        var copy = self
        copy.wakeEndTime = Calendar.current.date(byAdding: .minute, value: 30, to: wakeStartTime) ?? wakeStartTime
        return copy
    }
}

// MARK: - WatchConnectivity 传输载荷

/// 通过 WatchConnectivity 传输的闹钟配置字典键
enum AlarmPayloadKey: String {
    case type
    case alarmID
    case wakeStartTime
    case wakeEndTime
    case targetTime
    case isOn
    case sound
    case repeatWeekdays
}

extension Alarm {
    /// 序列化为 WatchConnectivity 可传输的字典
    func toPayload() -> [String: Any] {
        [
            AlarmPayloadKey.type.rawValue: WCMessageType.alarmConfig.rawValue,
            AlarmPayloadKey.alarmID.rawValue: id.uuidString,
            AlarmPayloadKey.wakeStartTime.rawValue: wakeStartTime.timeIntervalSince1970,
            AlarmPayloadKey.wakeEndTime.rawValue: wakeEndTime.timeIntervalSince1970,
            AlarmPayloadKey.targetTime.rawValue: wakeEndTime.timeIntervalSince1970,
            AlarmPayloadKey.isOn.rawValue: isOn,
            AlarmPayloadKey.sound.rawValue: sound.rawValue,
            AlarmPayloadKey.repeatWeekdays.rawValue: Array(repeatWeekdays)
        ]
    }

    /// 从 WatchConnectivity 字典反序列化
    static func fromPayload(_ payload: [String: Any]) -> Alarm? {
        guard
            let idString = payload[AlarmPayloadKey.alarmID.rawValue] as? String,
            let id = UUID(uuidString: idString),
            let isOn = payload[AlarmPayloadKey.isOn.rawValue] as? Bool
        else { return nil }

        let soundRaw = payload[AlarmPayloadKey.sound.rawValue] as? String
        let sound = soundRaw.flatMap(AlarmSound.init(rawValue:)) ?? .aurora
        let repeatWeekdays = payload[AlarmPayloadKey.repeatWeekdays.rawValue] as? [Int] ?? Array(Alarm.defaultRepeatWeekdays)

        if let startTimestamp = payload[AlarmPayloadKey.wakeStartTime.rawValue] as? TimeInterval,
           let endTimestamp = payload[AlarmPayloadKey.wakeEndTime.rawValue] as? TimeInterval {
            return Alarm(
                id: id,
                wakeStartTime: Date(timeIntervalSince1970: startTimestamp),
                wakeEndTime: Date(timeIntervalSince1970: endTimestamp),
                isOn: isOn,
                sound: sound,
                repeatWeekdays: Set(repeatWeekdays)
            ).normalized()
        }

        guard let targetTimestamp = payload[AlarmPayloadKey.targetTime.rawValue] as? TimeInterval else {
            return nil
        }
        let targetTime = Date(timeIntervalSince1970: targetTimestamp)
        let startTime = Calendar.current.date(byAdding: .minute, value: -30, to: targetTime) ?? targetTime
        return Alarm(
            id: id,
            wakeStartTime: startTime,
            wakeEndTime: targetTime,
            isOn: isOn,
            sound: sound,
            repeatWeekdays: Set(repeatWeekdays)
        ).normalized()
    }
}

// MARK: - 双端通信消息类型

enum WCMessageType: String, Sendable {
    case alarmConfig = "alarm_config"
    case startMonitoring = "start_monitoring"
    case stopMonitoring = "stop_monitoring"
    case smartWakeTriggered = "smart_wake_triggered"
    case alarmDismissed = "alarm_dismissed"
    case heartRateUpdate = "heart_rate_update"
    case wearablePing = "wearable_ping"
    case wearablePong = "wearable_pong"
}
