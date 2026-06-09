//
//  ContentView.swift
//  EchoClock
//
//  iPhone 主界面 — 暗黑轻奢风智能闹钟控制台
//

import SwiftUI

// MARK: - iPhone 主界面

struct ContentView: View {
    @StateObject private var viewModel = AlarmViewModel()
    @State private var showRangePicker = false

    var body: some View {
        ZStack {
            // 背景渐变
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.08),
                    Color(red: 0.10, green: 0.08, blue: 0.14),
                    Color(red: 0.06, green: 0.06, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // 装饰性光晕
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.purple.opacity(0.15), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .offset(x: -80, y: -200)
                .blur(radius: 60)

            ScrollView {
                VStack(spacing: 32) {
                    headerSection
                    clockSection
                    wakeRangeSection
                    alarmToggleSection
                    statusSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
            }

            // 响铃全屏遮罩
            if viewModel.isAlarmRinging {
                ringingOverlay
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await viewModel.requestPermissions()
        }
        .sheet(isPresented: $showRangePicker) {
            rangePickerSheet
        }
    }

    // MARK: - 顶部标题

    private var headerSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(
                        LinearGradient(colors: [.purple, .indigo], startPoint: .top, endPoint: .bottom)
                    )
                Text("EchoClock")
                    .font(.system(size: 22, weight: .light, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(.white.opacity(0.9))
            }
            Text("智能浅睡眠唤醒")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
                .tracking(2)
        }
    }

    // MARK: - 实时时钟

    private var clockSection: some View {
        VStack(spacing: 4) {
            Text(viewModel.currentTime, format: .dateTime.hour().minute().second())
                .font(.system(size: 64, weight: .thin, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(viewModel.currentTime, format: .dateTime.weekday(.wide).month().day())
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.vertical, 8)
    }

    // MARK: - 智能唤醒范围

    private var wakeRangeSection: some View {
        VStack(spacing: 12) {
            Text("智能唤醒范围")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
                .tracking(1)

            Button {
                showRangePicker = true
            } label: {
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: "alarm.fill")
                            .foregroundStyle(.purple.opacity(0.8))
                        Text(viewModel.alarm.formattedWakeWindow)
                            .font(.system(size: 34, weight: .light, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .minimumScaleFactor(0.72)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.3))
                    }

                    Text("范围内检测到浅睡眠立即唤醒，否则在 \(viewModel.alarm.formattedWakeEndTime) 唤醒")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.38))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        )
                )
            }

            if viewModel.alarm.isOn {
                Text("Apple Watch 将在该范围内持续回传心率")
                    .font(.caption2)
                    .foregroundStyle(.purple.opacity(0.7))
            }
        }
    }

    // MARK: - 闹钟开关

    private var alarmToggleSection: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                viewModel.toggleAlarm()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: viewModel.alarm.isOn ? "bell.fill" : "bell.slash.fill")
                    .font(.title2)
                Text(viewModel.alarm.isOn ? "闹钟已开启" : "开启闹钟")
                    .font(.headline)
            }
            .foregroundStyle(viewModel.alarm.isOn ? .white : .white.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        viewModel.alarm.isOn
                            ? LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [.white.opacity(0.08), .white.opacity(0.05)], startPoint: .leading, endPoint: .trailing)
                    )
                    .shadow(color: viewModel.alarm.isOn ? .purple.opacity(0.4) : .clear, radius: 16, y: 6)
            )
        }
    }

    // MARK: - 状态信息

    private var statusSection: some View {
        VStack(spacing: 8) {
            statusRow(icon: "heart.fill", label: "HealthKit", value: viewModel.healthAuthStatus)
            statusRow(icon: "applewatch", label: "Apple Watch", value: viewModel.watchStatus)
            statusRow(icon: "waveform.path.ecg", label: "监测状态", value: viewModel.monitoringStatus)
            statusRow(icon: "heart.text.square.fill", label: "实时心率", value: heartRateText)
            if HealthKitManager.shared.isUsingMockData {
                statusRow(icon: "waveform.path.ecg", label: "心率模式", value: "模拟数据")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.03))
        )
    }

    private var heartRateText: String {
        guard viewModel.latestHeartRate > 0 else { return "等待数据" }
        return "\(Int(viewModel.latestHeartRate)) BPM"
    }

    private func statusRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.purple.opacity(0.6))
                .frame(width: 20)
            Text(label)
                .foregroundStyle(.white.opacity(0.4))
                .font(.caption)
            Spacer()
            Text(value)
                .foregroundStyle(.white.opacity(0.6))
                .font(.caption)
        }
    }

    // MARK: - 响铃遮罩

    private var ringingOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 32) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(
                        LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                    )
                    .symbolEffect(.pulse, options: .repeating)

                Text("浅睡眠唤醒")
                    .font(.title.weight(.light))
                    .foregroundStyle(.white)

                Text("检测到您已进入浅睡眠，祝您早安！")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)

                Button {
                    withAnimation {
                        viewModel.dismissAlarm()
                    }
                } label: {
                    Text("关闭闹钟")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 48)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(.white))
                }
                .padding(.top, 16)
            }
            .padding(32)
        }
        .transition(.opacity)
    }

    // MARK: - 范围选择器

    private var rangePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                DatePicker(
                    "开始",
                    selection: Binding(
                        get: { viewModel.alarm.wakeStartTime },
                        set: { viewModel.updateWakeStartTime($0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)

                DatePicker(
                    "截止",
                    selection: Binding(
                        get: { viewModel.alarm.wakeEndTime },
                        set: { viewModel.updateWakeEndTime($0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)

                Text("当前范围 \(viewModel.alarm.formattedWakeWindow)，共 \(viewModel.alarm.windowMinutes) 分钟")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .navigationTitle("设定唤醒时间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showRangePicker = false }
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }
}
