//
//  WatchConnectivityManager.swift
//  EchoClockShared
//
//  WatchConnectivity 双端通信桥梁 — iPhone ↔ Apple Watch
//

import Foundation
import Combine
import WatchConnectivity

// MARK: - WatchConnectivity 管理器

/// 封装 WCSession，负责双端闹钟配置同步与唤醒指令传输
@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    /// Watch 是否已配对且可达
    @Published private(set) var isReachable: Bool = false
    /// Session 是否已激活
    @Published private(set) var isSessionActivated: Bool = false
    /// iPhone 端：是否已配对 Apple Watch
    @Published private(set) var isWatchPaired: Bool = false
    /// iPhone 端：Apple Watch 是否已安装配套 App
    @Published private(set) var isWatchAppInstalled: Bool = false
    /// 从对端接收到的最新闹钟配置
    @Published var receivedAlarm: Alarm?

    /// iPhone 端：收到 Watch 发来的智能唤醒通知
    var onSmartWakeTriggered: (() -> Void)?
    /// Watch 端：收到 iPhone 发来的闹钟配置
    var onAlarmConfigReceived: ((Alarm) -> Void)?
    /// Watch 端：收到 iPhone 发来的开始监测指令
    var onStartMonitoring: ((Alarm) -> Void)?
    /// Watch 端：收到 iPhone 发来的停止监测指令
    var onStopMonitoring: (() -> Void)?
    /// 任一端：收到闹钟关闭通知
    var onAlarmDismissed: (() -> Void)?

    private var sessionDelegateHandler: SessionDelegateHandler?

    private override init() {
        super.init()
        activateSession()
    }

    // MARK: - Session 激活

    private func activateSession() {
        guard WCSession.isSupported() else {
            print("[WatchConnectivity] 当前设备不支持 WCSession")
            return
        }
        let session = WCSession.default
        let delegateHandler = SessionDelegateHandler(manager: self)
        sessionDelegateHandler = delegateHandler
        session.delegate = delegateHandler
        session.activate()
        refreshWearableStatus(session: session)
    }

    /// 由 SessionDelegateHandler 回调，更新激活状态
    fileprivate func handleActivationCompleted(isActivated: Bool, isReachable: Bool) {
        isSessionActivated = isActivated
        self.isReachable = isReachable
        refreshWearableStatus(session: WCSession.default)
    }

    private func refreshWearableStatus(session: WCSession) {
        #if os(iOS)
        isWatchPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
        #else
        isWatchPaired = true
        isWatchAppInstalled = true
        #endif
    }

    // MARK: - 发送消息

    /// 发送闹钟配置到对端
    func sendAlarmConfig(_ alarm: Alarm) {
        var payload = alarm.toPayload()
        payload[AlarmPayloadKey.type.rawValue] = WCMessageType.alarmConfig.rawValue
        sendPayload(payload)
    }

    /// 通知对端开始后台监测
    func sendStartMonitoring(alarm: Alarm) {
        var payload = alarm.normalized().toPayload()
        payload[AlarmPayloadKey.type.rawValue] = WCMessageType.startMonitoring.rawValue
        sendPayload(payload)
    }

    /// 通知对端停止监测
    func sendStopMonitoring() {
        sendPayload([AlarmPayloadKey.type.rawValue: WCMessageType.stopMonitoring.rawValue])
    }

    /// Watch → iPhone：报告智能唤醒已触发
    func sendSmartWakeTriggered(alarmID: UUID) {
        sendPayload([
            AlarmPayloadKey.type.rawValue: WCMessageType.smartWakeTriggered.rawValue,
            AlarmPayloadKey.alarmID.rawValue: alarmID.uuidString
        ])
    }

    /// 通知对端闹钟已关闭
    func sendAlarmDismissed() {
        sendPayload([AlarmPayloadKey.type.rawValue: WCMessageType.alarmDismissed.rawValue])
    }

    /// 发送最新心率到 iPhone（Watch 端可选）
    func sendHeartRateUpdate(_ bpm: Double) {
        sendPayload([
            AlarmPayloadKey.type.rawValue: WCMessageType.heartRateUpdate.rawValue,
            "bpm": bpm
        ])
    }

    private func sendPayload(_ payload: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        // 优先使用实时消息（对端可达时）
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("[WatchConnectivity] sendMessage 失败: \(error.localizedDescription)")
            }
        }

        // 同时写入 ApplicationContext，确保对端稍后启动也能收到
        do {
            try session.updateApplicationContext(payload)
        } catch {
            print("[WatchConnectivity] updateApplicationContext 失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 接收消息处理

    fileprivate func handleReceivedPayload(_ payload: [String: Any]) {
        guard let typeRaw = payload[AlarmPayloadKey.type.rawValue] as? String,
              let type = WCMessageType(rawValue: typeRaw) else { return }

        switch type {
        case .alarmConfig:
            if let alarm = Alarm.fromPayload(payload) {
                receivedAlarm = alarm
                onAlarmConfigReceived?(alarm)
            }

        case .startMonitoring:
            if let alarm = Alarm.fromPayload(payload) ?? receivedAlarm {
                receivedAlarm = alarm
                onStartMonitoring?(alarm)
                onAlarmConfigReceived?(alarm)
            }

        case .stopMonitoring:
            onStopMonitoring?()

        case .smartWakeTriggered:
            onSmartWakeTriggered?()

        case .alarmDismissed:
            onAlarmDismissed?()

        case .heartRateUpdate:
            if let bpm = payload["bpm"] as? Double {
                HealthKitManager.shared.updateLatestHeartRate(bpm)
            }
        }
    }
}

// MARK: - WCSessionDelegate（非 MainActor 桥接）

/// WCSession 代理必须在非隔离上下文运行，通过此类桥接到 MainActor
private final class SessionDelegateHandler: NSObject, WCSessionDelegate {
    private nonisolated(unsafe) weak var manager: WatchConnectivityManager?

    init(manager: WatchConnectivityManager) {
        self.manager = manager
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            print("[WatchConnectivity] 激活失败: \(error.localizedDescription)")
        }
        Task { @MainActor [weak manager] in
            manager?.handleActivationCompleted(
                isActivated: activationState == .activated,
                isReachable: session.isReachable
            )
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak manager] in
            manager?.handleActivationCompleted(
                isActivated: session.activationState == .activated,
                isReachable: session.isReachable
            )
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor [weak manager] in
            manager?.handleReceivedPayload(message)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor [weak manager] in
            manager?.handleReceivedPayload(message)
            replyHandler(["status": "ok"])
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor [weak manager] in
            manager?.handleReceivedPayload(applicationContext)
        }
    }
}
