//
//  WatchContentView.swift
//  EchoClockWatch Watch App
//
//  Watch 主界面 — 极简黑底睡眠监测面板
//

import SwiftUI

// MARK: - Watch 主界面

struct WatchContentView: View {
    @StateObject private var viewModel = WatchAlarmViewModel()
    @State private var ripplePhase: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isWakeTriggered {
                wakeFlashOverlay
            } else {
                monitoringView
            }
        }
        .task {
            await viewModel.requestPermissions()
        }
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                ripplePhase = 1
            }
        }
    }

    // MARK: - 正常监测界面

    private var monitoringView: some View {
        VStack(spacing: 10) {
            // 闹钟时间
            if viewModel.alarm.isOn {
                VStack(spacing: 2) {
                    Text("范围")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                    Text(viewModel.alarm.formattedWakeWindow)
                        .font(.system(size: 22, weight: .light, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .minimumScaleFactor(0.72)
                }
            } else {
                Text("等待同步")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            Spacer(minLength: 4)

            // 心率显示
            VStack(spacing: 4) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.8))
                        .symbolEffect(.pulse, options: .repeating)

                    if viewModel.heartRate > 0 {
                        Text("\(Int(viewModel.heartRate))")
                            .font(.system(size: 36, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("BPM")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                    } else {
                        Text("--")
                            .font(.system(size: 36, weight: .medium, design: .rounded))
                            .foregroundStyle(.gray)
                    }
                }

                if viewModel.isUsingMockData {
                    Text("模拟")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange.opacity(0.7))
                }
            }

            Spacer(minLength: 4)

            // 睡眠监测波纹动画
            if viewModel.isMonitoring {
                monitoringRipple
                Text(stateLabel)
                    .font(.caption2)
                    .foregroundStyle(.purple.opacity(0.8))
            }
        }
        .padding(.vertical, 8)
    }

    private var stateLabel: String {
        switch viewModel.monitoringState {
        case .idle: return "待机中"
        case .waitingForWindow: return "等待唤醒窗口"
        case .monitoring: return "睡眠监测中"
        case .triggered: return "已触发"
        }
    }

    // MARK: - 波纹动画

    private var monitoringRipple: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(Color.purple.opacity(0.3 - Double(index) * 0.08), lineWidth: 1.5)
                    .frame(width: 40 + CGFloat(index) * 16, height: 40 + CGFloat(index) * 16)
                    .scaleEffect(1 + ripplePhase * 0.3)
                    .opacity(1 - ripplePhase * 0.8)
                    .animation(
                        .easeOut(duration: 2)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.4),
                        value: ripplePhase
                    )
            }

            Circle()
                .fill(Color.purple.opacity(0.6))
                .frame(width: 8, height: 8)
        }
        .frame(height: 60)
    }

    // MARK: - 唤醒闪烁遮罩

    private var wakeFlashOverlay: some View {
        WakeFlashView(onDismiss: {
            viewModel.dismissWake()
            WatchConnectivityManager.shared.sendAlarmDismissed()
        })
    }
}

// MARK: - 唤醒闪烁视图

private struct WakeFlashView: View {
    let onDismiss: () -> Void
    @State private var flashOpacity: Double = 1.0

    var body: some View {
        ZStack {
            Color.orange.opacity(flashOpacity * 0.3)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.yellow)
                    .symbolEffect(.pulse, options: .repeating)

                Text("浅睡眠\n唤醒")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)

                Button("关闭") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.2))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                flashOpacity = 0.2
            }
        }
    }
}
