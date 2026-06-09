//
//  AlarmSoundService.swift
//  EchoClock
//
//  闹钟铃声服务 — 智能唤醒触发后播放系统铃声
//

import AVFoundation
import AudioToolbox
import Combine

// MARK: - 闹钟铃声

@MainActor
final class AlarmSoundService: ObservableObject {
    static let shared = AlarmSoundService()

    @Published private(set) var isRinging: Bool = false

    private var ringTimer: Timer?

    private init() {}

    /// 开始响铃（循环播放系统闹钟音）
    func startRinging() {
        guard !isRinging else { return }
        isRinging = true
        configureAudioSession()
        playAlarmSound()
        ringTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.playAlarmSound()
            }
        }
    }

    /// 停止响铃
    func stopRinging() {
        ringTimer?.invalidate()
        ringTimer = nil
        isRinging = false
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("[AlarmSoundService] 音频会话配置失败: \(error.localizedDescription)")
        }
    }

    private func playAlarmSound() {
        // 系统闹钟提示音 ID
        AudioServicesPlaySystemSound(1005)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
}
