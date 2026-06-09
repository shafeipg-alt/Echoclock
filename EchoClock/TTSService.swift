//
//  TTSService.swift
//  EchoClock
//
//  语音播报服务 — 闹钟关闭后播放早安问候
//

import AVFoundation
import Combine

// MARK: - TTS 语音服务

/// 使用 AVSpeechSynthesizer 实现文字转语音，支持后台播放
@MainActor
final class TTSService: NSObject, ObservableObject {
    static let shared = TTSService()

    @Published private(set) var isSpeaking: Bool = false

    private let synthesizer = AVSpeechSynthesizer()
    private var audioSessionConfigured = false

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - 音频会话配置

    /// 配置 AVAudioSession 为 .playback 类别，允许后台播放
    func configureAudioSession() {
        guard !audioSessionConfigured else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            audioSessionConfigured = true
        } catch {
            print("[TTSService] 音频会话配置失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 语音播报

    /// 播放早安问候语（闹钟关闭后调用）
    func speakMorningGreeting() {
        configureAudioSession()
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting: String
        switch hour {
        case 5..<12:
            greeting = "早安！新的一天开始了，愿你今天精神饱满，事事顺利。"
        case 12..<18:
            greeting = "午安！希望你睡得很好，祝你今天愉快。"
        default:
            greeting = "你好！闹钟已关闭，祝你有个美好的一天。"
        }
        speak(text: greeting)
    }

    /// 通用文字转语音
    func speak(text: String, language: String = "zh-CN") {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        configureAudioSession()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// 停止播报
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TTSService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}
