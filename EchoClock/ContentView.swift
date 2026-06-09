//
//  ContentView.swift
//  EchoClock
//
//  iPhone 主界面 — 暗黑轻奢风智能闹钟控制台
//

import SwiftUI

// MARK: - iPhone 主界面

struct ContentView: View {
    @StateObject private var session = AppSessionViewModel()
    @StateObject private var viewModel = AlarmViewModel()
    @State private var showRangePicker = false

    var body: some View {
        Group {
            if session.isAuthenticated {
                dashboard
            } else {
                LoginView(session: session)
            }
        }
    }

    private var dashboard: some View {
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
                    soundSection
                    monitoringActionSection
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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
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
                Text(session.displayName)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.32))
            }
            Spacer()
            Button {
                session.signOut()
            } label: {
                Image(systemName: "person.crop.circle.badge.xmark")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.white.opacity(0.06)))
            }
            .accessibilityLabel("退出登录")
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

                    Text("范围内 60-72 BPM 或心率上升会唤醒，否则在 \(viewModel.alarm.formattedWakeEndTime) 唤醒")
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

    // MARK: - 铃声设置

    private var soundSection: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("闹钟铃声")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.68))
                    Text(viewModel.alarm.sound.description)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.36))
                }
                Spacer()
                Button {
                    viewModel.previewSelectedSound()
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(.white.opacity(0.08)))
                }
                .accessibilityLabel("试听铃声")
            }

            Menu {
                ForEach(AlarmSound.allCases, id: \.self) { sound in
                    Button {
                        viewModel.updateSound(sound)
                    } label: {
                        Label(sound.displayName, systemImage: sound == viewModel.alarm.sound ? "checkmark" : "music.note")
                    }
                }
            } label: {
                HStack {
                    Text(viewModel.alarm.sound.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.black.opacity(0.2))
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - 智能监测开关

    private var monitoringActionSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(viewModel.alarm.isOn ? .green.opacity(0.18) : .white.opacity(0.07))
                        .frame(width: 48, height: 48)
                    Image(systemName: viewModel.alarm.isOn ? "waveform.path.ecg" : "applewatch")
                        .font(.title3)
                        .foregroundStyle(viewModel.alarm.isOn ? .green.opacity(0.9) : .purple.opacity(0.75))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.alarm.isOn ? "智能监测运行中" : "准备开始智能监测")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.9))
                    Text(viewModel.alarm.isOn ? viewModel.monitoringStatus : "同步 Apple Watch，并在唤醒范围内分析心率")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(2)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                monitorStep(icon: "applewatch", text: "连接 Watch", isActive: viewModel.alarm.isOn)
                monitorStep(icon: "heart.fill", text: "读取心率", isActive: viewModel.latestHeartRate > 0)
                monitorStep(icon: "bell.fill", text: "智能唤醒", isActive: viewModel.isAlarmRinging)
            }

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    viewModel.toggleAlarm()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: viewModel.alarm.isOn ? "stop.fill" : "play.fill")
                        .font(.headline)
                    Text(viewModel.alarm.isOn ? "停止智能监测" : "开始智能监测")
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            viewModel.alarm.isOn
                                ? LinearGradient(colors: [.red.opacity(0.8), .orange.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing)
                        )
                        .shadow(color: viewModel.alarm.isOn ? .red.opacity(0.26) : .purple.opacity(0.4), radius: 16, y: 6)
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func monitorStep(icon: String, text: String, isActive: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
                .lineLimit(1)
        }
        .foregroundStyle(isActive ? .white.opacity(0.9) : .white.opacity(0.36))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive ? .white.opacity(0.11) : .black.opacity(0.16))
        )
    }
    // MARK: - 状态信息

    private var statusSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("设备与数据")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                Spacer()
                Button {
                    viewModel.connectWearable()
                } label: {
                    Image(systemName: "applewatch.and.arrow.forward")
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.purple.opacity(0.22)))
                }
                .accessibilityLabel("连接 Apple Watch")
            }

            statusRow(icon: "heart.fill", label: "HealthKit", value: viewModel.healthAuthStatus)
            statusRow(icon: "applewatch", label: "Apple Watch", value: viewModel.watchStatus)
            statusRow(icon: "dot.radiowaves.left.and.right", label: "Watch 信号", value: viewModel.wearableSignalStatus)
            statusRow(icon: "waveform.path.ecg", label: "监测状态", value: viewModel.monitoringStatus)
            statusRow(icon: "heart.text.square.fill", label: "实时心率", value: heartRateText)
            statusRow(icon: "sensor.tag.radiowaves.forward.fill", label: "心率来源", value: viewModel.heartRateSourceStatus)
            statusRow(icon: "checkmark.seal.fill", label: "唤醒规则", value: viewModel.triggerReasonStatus)
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
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
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

                Menu {
                    ForEach(AlarmSound.allCases, id: \.self) { sound in
                        Button {
                            viewModel.updateSound(sound)
                        } label: {
                            Label(sound.displayName, systemImage: sound == viewModel.alarm.sound ? "checkmark" : "music.note")
                        }
                    }
                } label: {
                    Label(viewModel.alarm.sound.displayName, systemImage: "music.note")
                }
            }
            .padding(.horizontal, 24)
            .navigationTitle("设定闹钟")
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

// MARK: - 登录页面

private struct LoginView: View {
    @ObservedObject var session: AppSessionViewModel
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ZStack {
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

            VStack(spacing: 28) {
                Spacer(minLength: 24)

                VStack(spacing: 10) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(
                            LinearGradient(colors: [.purple, .indigo], startPoint: .top, endPoint: .bottom)
                        )

                    Text("EchoClock")
                        .font(.system(size: 30, weight: .light, design: .rounded))
                        .tracking(5)
                        .foregroundStyle(.white.opacity(0.92))

                    Text("登录后管理你的智能唤醒计划")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.42))
                }

                VStack(spacing: 14) {
                    authField(icon: "envelope.fill", placeholder: "邮箱", text: $email, isSecure: false)
                    authField(icon: "lock.fill", placeholder: "密码", text: $password, isSecure: true)

                    Button {
                        Task {
                            await session.signIn(email: email, password: password)
                        }
                    } label: {
                        Text(session.isLoading ? "处理中..." : "登录")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing))
                            )
                    }
                    .disabled(session.isLoading)
                    .padding(.top, 6)

                    Button {
                        Task {
                            await session.register(email: email, password: password)
                        }
                    } label: {
                        Text("注册")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.82))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.white.opacity(0.08))
                            )
                    }
                    .disabled(session.isLoading)

                    Button {
                        session.demoSignIn()
                    } label: {
                        Text("演示登录")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.65))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.white.opacity(0.06))
                            )
                    }

                    if let message = session.authMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.orange.opacity(0.9))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(.white.opacity(0.045))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        )
                )

                Text("账号系统已接入 EMAS Serverless，演示登录仅用于云函数未部署时预览")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.28))
                    .multilineTextAlignment(.center)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func authField(icon: String, placeholder: String, text: Binding<String>, isSecure: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.purple.opacity(0.7))
                .frame(width: 22)
            if isSecure {
                SecureField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else {
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.black.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}
