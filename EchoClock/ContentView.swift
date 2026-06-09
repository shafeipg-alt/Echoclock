//
//  ContentView.swift
//  EchoClock
//
//  iPhone 主界面 — 暗黑轻奢风智能闹钟控制台
//

import SwiftUI

private enum LumeColor {
    static let background = Color(red: 0.055, green: 0.075, blue: 0.133)
    static let surfaceLowest = Color(red: 0.035, green: 0.055, blue: 0.11)
    static let surfaceLow = Color(red: 0.086, green: 0.106, blue: 0.169)
    static let surfaceHigh = Color(red: 0.145, green: 0.161, blue: 0.227)
    static let text = Color(red: 0.871, green: 0.882, blue: 0.969)
    static let textMuted = Color(red: 0.725, green: 0.796, blue: 0.741)
    static let primary = Color(red: 0.0, green: 0.89, blue: 0.58)
    static let primaryBright = Color(red: 0.31, green: 1.0, blue: 0.69)
    static let secondary = Color(red: 0.0, green: 0.85, blue: 1.0)
}

// MARK: - iPhone 主界面

struct ContentView: View {
    private enum DashboardTab {
        case alarm
        case sleep
        case stats
        case profile
    }

    private enum ActiveSheet: Identifiable {
        case alarmEditor
        case device
        case sleepReminder
        case language
        case theme
        case soundLibrary
        case heartRateSettings
        case feedback
        case about

        var id: String {
            switch self {
            case .alarmEditor: return "alarmEditor"
            case .device: return "device"
            case .sleepReminder: return "sleepReminder"
            case .language: return "language"
            case .theme: return "theme"
            case .soundLibrary: return "soundLibrary"
            case .heartRateSettings: return "heartRateSettings"
            case .feedback: return "feedback"
            case .about: return "about"
            }
        }
    }

    private struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @StateObject private var session = AppSessionViewModel()
    @StateObject private var viewModel = AlarmViewModel()
    @State private var showRangePicker = false
    @State private var selectedDashboardTab: DashboardTab = .alarm
    @State private var isShowingLaunch = true
    @State private var activeSheet: ActiveSheet?
    @State private var notice: Notice?

    var body: some View {
        ZStack {
            Group {
                if session.isAuthenticated {
                    dashboard
                } else {
                    LoginView(session: session)
                }
            }
            .opacity(isShowingLaunch ? 0 : 1)

            if isShowingLaunch {
                AppLaunchView()
                    .transition(.opacity)
            }
        }
        .task {
            guard isShowingLaunch else { return }
            try? await Task.sleep(nanoseconds: 1_150_000_000)
            withAnimation(.easeOut(duration: 0.35)) {
                isShowingLaunch = false
            }
        }
    }

    private var dashboard: some View {
        ZStack {
            appBackground

            Group {
                switch selectedDashboardTab {
                case .alarm:
                    alarmHomePage
                case .sleep:
                    sleepMonitorPage
                case .stats:
                    statsPage
                case .profile:
                    profilePage
                }
            }

            VStack {
                Spacer()
                bottomNavigationBar
            }

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
        .sheet(item: $activeSheet) { sheet in
            interactiveSheet(sheet)
        }
        .alert(item: $notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("知道了")))
        }
    }

    private var appBackground: some View {
        ZStack {
            LumeColor.background
            LinearGradient(colors: [LumeColor.primary.opacity(0.18), .clear, .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: [.clear, LumeColor.secondary.opacity(0.14), .clear], startPoint: .topTrailing, endPoint: .bottomLeading)
        }
        .ignoresSafeArea()
    }

    private var alarmHomePage: some View {
        List {
            Section {
                pageTitle("闹钟", subtitle: "专注恢复，活力每一天")
                    .listRowInsets(EdgeInsets(top: 28, leading: 24, bottom: 8, trailing: 24))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                addAlarmEntry
                    .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 16, trailing: 24))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                ForEach(viewModel.alarms) { alarm in
                    alarmCard(alarm)
                        .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 14, trailing: 24))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.deleteAlarm(alarm)
                                }
                            } label: {
                                Label("删除", systemImage: "trash.fill")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.deleteAlarm(alarm)
                                }
                            } label: {
                                Label("删除", systemImage: "trash.fill")
                            }
                        }
                }
            }

            Section {
                sleepBentoGrid
                    .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 122, trailing: 24))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .background(appBackground)
    }

    private var alarmTopBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.currentTime, format: .dateTime.weekday(.wide).month().day())
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
                Text(viewModel.alarm.isOn ? "正在守候你的浅睡眠" : "设置今晚的唤醒计划")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.42))
            }
            Spacer()
            Button {
                viewModel.previewSelectedSound()
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.white.opacity(0.08)))
            }
            .accessibilityLabel("试听铃声")
        }
    }

    private var addAlarmEntry: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                _ = viewModel.addAlarm()
            }
            activeSheet = .alarmEditor
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(LumeColor.background)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(LumeColor.primary))

                VStack(alignment: .leading, spacing: 4) {
                    Text("添加智能闹钟")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(LumeColor.text)
                    Text("设置唤醒范围、铃声和 Apple Watch 心率监测")
                        .font(.caption)
                        .foregroundStyle(LumeColor.textMuted.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LumeColor.textMuted.opacity(0.48))
            }
            .padding(18)
            .glassCard(cornerRadius: 22)
        }
    }

    private func alarmCard(_ alarm: Alarm) -> some View {
        VStack(spacing: 15) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(alarm.formattedWakeEndTime)
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(LumeColor.text)
                            .monospacedDigit()
                        Text(dayPeriodText(for: alarm.wakeEndTime))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LumeColor.textMuted)
                    }

                    Text("智能唤醒: \(alarm.formattedWakeWindow)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(alarm.isOn ? LumeColor.primaryBright : LumeColor.textMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(alarm.isOn ? LumeColor.primary.opacity(0.16) : LumeColor.surfaceHigh.opacity(0.55)))
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.toggleAlarm(alarm)
                    }
                } label: {
                    toggleSwitch(isOn: alarm.isOn)
                }
                .accessibilityLabel(alarm.isOn ? "关闭智能闹钟" : "开启智能闹钟")
            }

            HStack {
                Text(alarm.formattedRepeatText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(alarm.isOn ? LumeColor.primary : LumeColor.textMuted)
                Spacer()
                Text(alarm.isOn ? activeAlarmStatus(for: alarm) : "点击卡片编辑")
                    .font(.caption2)
                    .foregroundStyle(LumeColor.textMuted.opacity(0.72))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(LumeColor.textMuted.opacity(0.45))
            }
        }
        .padding(24)
        .opacity(alarm.isOn ? 1 : 0.62)
        .glassCard(cornerRadius: 28)
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .onTapGesture {
            viewModel.selectAlarm(alarm)
            activeSheet = .alarmEditor
        }
    }

    private func dayPeriodText(for date: Date) -> String {
        Calendar.current.component(.hour, from: date) < 12 ? "AM" : "PM"
    }

    private func activeAlarmStatus(for alarm: Alarm) -> String {
        alarm.id == viewModel.alarm.id ? viewModel.monitoringStatus : "已开启，等待同步"
    }

    private func toggleSwitch(isOn: Bool) -> some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(
                    isOn
                    ? LinearGradient(colors: [LumeColor.primary, LumeColor.secondary], startPoint: .leading, endPoint: .trailing)
                    : LinearGradient(colors: [LumeColor.surfaceHigh.opacity(0.8), LumeColor.surfaceHigh.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                )
                .frame(width: 50, height: 28)
            Circle()
                .fill(.white)
                .frame(width: 22, height: 22)
                .padding(3)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        }
        .frame(width: 50, height: 28)
    }

    private var sleepBentoGrid: some View {
        Group {
            if let score = viewModel.heartRateQualityScore, viewModel.latestHeartRate > 0 {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    bentoMetricCard(icon: "checkmark.seal.fill", title: "数据质量", value: "\(score)", suffix: "分", accent: LumeColor.secondary, progress: Double(score) / 100.0)
                        .onTapGesture { activeSheet = .heartRateSettings }
                    heartRateBentoCard
                        .onTapGesture { selectedDashboardTab = .sleep }
                }
                .padding(.top, 12)
            }
        }
    }

    private func bentoMetricCard(icon: String, title: String, value: String, suffix: String, accent: Color, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(accent)
                Spacer()
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LumeColor.textMuted)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(LumeColor.text)
                    Text(suffix)
                        .font(.caption)
                        .foregroundStyle(LumeColor.textMuted)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(LumeColor.surfaceHigh.opacity(0.55))
                        Capsule()
                            .fill(accent)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 6)
            }
        }
        .frame(height: 126)
        .padding(18)
        .glassCard(cornerRadius: 24)
    }

    private var heartRateBentoCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red.opacity(0.86))
                Spacer()
                Text("心率")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LumeColor.textMuted)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(viewModel.latestHeartRate))")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(LumeColor.text)
                Text("BPM")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LumeColor.textMuted)
            }

            HeartRateSparkline(samples: viewModel.recentHeartRates)
                .frame(height: 34)
        }
        .frame(height: 126)
        .padding(18)
        .glassCard(cornerRadius: 24)
    }

    private var sleepMonitorPage: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 9) {
                    Text(viewModel.currentTime, format: .dateTime.hour().minute())
                        .font(.system(size: 78, weight: .bold, design: .rounded))
                        .foregroundStyle(LumeColor.primaryBright)
                        .monospacedDigit()
                        .shadow(color: LumeColor.primary.opacity(0.32), radius: 24)
                    Label(viewModel.alarm.isOn ? "正在监测您的睡眠阶段..." : "开启闹钟后开始监测", systemImage: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(LumeColor.textMuted)
                }
                .padding(.top, 44)

                monitoringHeartRateCard
                    .onTapGesture { activeSheet = .heartRateSettings }
                environmentGrid

                Button {
                    if viewModel.alarm.isOn {
                        viewModel.toggleAlarm()
                    } else {
                        selectedDashboardTab = .alarm
                    }
                } label: {
                    Label(viewModel.alarm.isOn ? "停止监测" : "去开启闹钟", systemImage: viewModel.alarm.isOn ? "stop.circle.fill" : "alarm.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(LumeColor.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .glassCard(cornerRadius: 30)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 122)
        }
        .scrollIndicators(.hidden)
        .background(appBackground)
    }

    private var monitoringHeartRateCard: some View {
        VStack(spacing: 14) {
            HStack {
                Label("心率", systemImage: "heart.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LumeColor.textMuted)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(viewModel.latestHeartRate > 0 ? "\(Int(viewModel.latestHeartRate))" : "57")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(LumeColor.primaryBright)
                    Text("BPM")
                        .font(.caption2)
                        .foregroundStyle(LumeColor.textMuted)
                }
            }

            ECGLine()
                .stroke(
                    LinearGradient(colors: [LumeColor.secondary.opacity(0.2), LumeColor.primary, LumeColor.primary], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )
                .frame(height: 86)

            HStack {
                metricColumn(title: "状态", value: viewModel.alarm.isOn ? sleepStageText : "待机中", valueColor: LumeColor.primary)
                Spacer()
                metricColumn(title: "呼吸频率", value: "14 次/分", valueColor: LumeColor.secondary)
            }
        }
        .padding(22)
        .glassCard(cornerRadius: 28)
    }

    private var sleepStageText: String {
        viewModel.latestHeartRate > 0 && viewModel.latestHeartRate <= 72 ? "浅睡候选" : "深度睡眠期"
    }

    private var environmentGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            smallEnvironmentCard(icon: "thermometer.medium", title: "室温", value: "22.5°C", accent: LumeColor.secondary)
                .onTapGesture {
                    notice = Notice(title: "室温数据", message: "当前为前端预留展示位。后续可接入 HomeKit、Matter 温湿度计或第三方 IoT 设备。")
                }
            smallEnvironmentCard(icon: "speaker.wave.1.fill", title: "环境音", value: "32 dB", accent: LumeColor.primary)
                .onTapGesture {
                    notice = Notice(title: "环境音数据", message: "当前为前端预留展示位。后续需要申请麦克风权限，并加入本地分贝采样逻辑。")
                }
        }
    }

    private func smallEnvironmentCard(icon: String, title: String, value: String, accent: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(accent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LumeColor.textMuted)
                Text(value)
                    .font(.headline)
                    .foregroundStyle(LumeColor.text)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glassCard(cornerRadius: 22)
    }

    private var statsPage: some View {
        ScrollView {
            VStack(spacing: 16) {
                pageTitle("昨晚睡眠报告", subtitle: "智能唤醒发生在浅睡窗口")
                sleepScoreCard
                sleepMetricGrid
                sleepStageChartCard
                heartRateTrendCard
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 122)
        }
        .scrollIndicators(.hidden)
        .background(appBackground)
    }

    private var sleepScoreCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.06), lineWidth: 9)
                    .frame(width: 168, height: 168)
                Circle()
                    .trim(from: 0, to: 0.88)
                    .stroke(LumeColor.primary, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 168, height: 168)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: LumeColor.primary.opacity(0.45), radius: 10)
                VStack(spacing: 3) {
                    Text("睡眠分数")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(LumeColor.textMuted)
                    Text("88")
                        .font(.system(size: 70, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            Text("睡眠质量优秀")
                .font(.title3.weight(.semibold))
                .foregroundStyle(LumeColor.primaryBright)
            Text("深睡比例超过同龄人平均水平，继续保持规律作息。")
                .font(.subheadline)
                .foregroundStyle(LumeColor.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 28)
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .onTapGesture {
            notice = Notice(title: "睡眠分数", message: "当前报告根据演示数据展示。接入 HealthKit 睡眠样本后，可按入睡时长、深睡比例、心率稳定度生成真实评分。")
        }
    }

    private var sleepMetricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            compactMetric(title: "入睡时间", value: "23:15")
                .onTapGesture { notice = Notice(title: "入睡时间", message: "后续将从 HealthKit 睡眠分析样本中读取。") }
            compactMetric(title: "醒来时间", value: viewModel.alarm.formattedWakeEndTime)
                .onTapGesture { activeSheet = .alarmEditor }
            compactMetric(title: "深睡时长", value: "2.5h")
                .onTapGesture { notice = Notice(title: "深睡时长", message: "后续将基于 Apple Watch 睡眠分期数据计算。") }
        }
    }

    private func compactMetric(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(LumeColor.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(LumeColor.text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 20)
    }

    private var sleepStageChartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("睡眠分期")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                legendDot(color: LumeColor.primary, text: "深睡")
                legendDot(color: LumeColor.secondary, text: "浅睡")
            }
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array([0.60, 0.55, 0.80, 0.85, 0.40, 0.30, 0.90, 0.10, 0.75, 0.50, 0.95, 1.00].enumerated()), id: \.offset) { item in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(item.offset == 7 ? Color.red.opacity(0.22) : (item.offset % 3 == 0 ? LumeColor.primary.opacity(0.42) : LumeColor.secondary.opacity(0.22)))
                        .frame(height: 150 * item.element)
                        .overlay(alignment: .top) {
                            if item.offset == 10 {
                                VStack(spacing: 3) {
                                    Text("智能唤醒")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(LumeColor.background)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(LumeColor.primaryBright))
                                    Rectangle()
                                        .fill(LumeColor.primaryBright)
                                        .frame(width: 1, height: 34)
                                }
                                .offset(y: -48)
                            }
                        }
                }
            }
            HStack {
                Text("23:00")
                Spacer()
                Text("02:00")
                Spacer()
                Text("05:00")
                Spacer()
                Text("08:00")
            }
            .font(.caption2)
            .foregroundStyle(LumeColor.textMuted)
        }
        .padding(20)
        .glassCard(cornerRadius: 24)
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture {
            notice = Notice(title: "睡眠分期", message: "这里展示智能唤醒在睡眠周期中的位置。后续接入真实睡眠分期后，可查看整晚深睡/浅睡/清醒区间。")
        }
    }

    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(.caption2)
                .foregroundStyle(LumeColor.textMuted)
        }
    }

    private var heartRateTrendCard: some View {
        VStack(spacing: 16) {
            HStack {
                Label("静息心率", systemImage: "heart.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text(viewModel.latestHeartRate > 0 ? "\(Int(viewModel.latestHeartRate)) BPM" : "58 BPM")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            ECGLine()
                .stroke(LinearGradient(colors: [LumeColor.secondary, LumeColor.primary], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .frame(height: 90)
        }
        .padding(20)
        .glassCard(cornerRadius: 24)
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture { selectedDashboardTab = .sleep }
    }

    private var bottomNavigationBar: some View {
        HStack {
            navButton(.alarm, icon: "alarm.fill", title: "闹钟")
            navButton(.sleep, icon: "moon.zzz.fill", title: "睡眠")
            navButton(.stats, icon: "chart.bar.fill", title: "统计")
            navButton(.profile, icon: "person.fill", title: "我的")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .background(
            Rectangle()
                .fill(LumeColor.surfaceLowest.opacity(0.72))
                .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func navButton(_ tab: DashboardTab, icon: String, title: String) -> some View {
        let isActive = selectedDashboardTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDashboardTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.headline)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(isActive ? LumeColor.primary : LumeColor.textMuted.opacity(0.62))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isActive ? .white.opacity(0.055) : .clear)
            )
            .shadow(color: isActive ? LumeColor.primary.opacity(0.28) : .clear, radius: 8)
        }
    }

    private func metricColumn(title: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(LumeColor.textMuted.opacity(0.62))
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(valueColor)
        }
    }

    @ViewBuilder
    private func interactiveSheet(_ sheet: ActiveSheet) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    switch sheet {
                    case .alarmEditor:
                        alarmEditorContent
                    case .device:
                        deviceSettingsContent
                    case .sleepReminder:
                        sleepReminderContent
                    case .language:
                        simpleSettingContent(
                            icon: "globe",
                            title: "界面语言",
                            message: "当前仅提供中文界面。后续接入本地化资源后，可在这里切换 English、繁体中文等语言。",
                            actionTitle: "知道了",
                            action: { activeSheet = nil }
                        )
                    case .theme:
                        simpleSettingContent(
                            icon: "paintpalette.fill",
                            title: "主题切换",
                            message: "当前已启用交互稿中的极光深色主题。浅色主题需要补齐同一套色彩变量后开放切换。",
                            actionTitle: "保持极光深色",
                            action: { activeSheet = nil }
                        )
                    case .soundLibrary:
                        soundLibraryContent
                    case .heartRateSettings:
                        heartRateSettingsContent
                    case .feedback:
                        simpleSettingContent(
                            icon: "bubble.left.and.bubble.right.fill",
                            title: "意见反馈",
                            message: "反馈入口已预留。后续接入 EMAS 云函数或 MemFire Cloud 后，可把用户建议写入反馈表。",
                            actionTitle: "我知道了",
                            action: { activeSheet = nil }
                        )
                    case .about:
                        simpleSettingContent(
                            icon: "moon.stars.fill",
                            title: "关于 Lume",
                            message: "Lume 是基于 Apple Watch 心率和智能唤醒窗口的浅睡眠闹钟。当前版本已接入 HealthKit、WatchConnectivity 与 EMAS 登录基础能力。",
                            actionTitle: "完成",
                            action: { activeSheet = nil }
                        )
                    }
                }
                .padding(24)
            }
            .background(appBackground)
            .navigationTitle(sheetTitle(sheet))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { activeSheet = nil }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }

    private func sheetTitle(_ sheet: ActiveSheet) -> String {
        switch sheet {
        case .alarmEditor: return "编辑闹钟"
        case .device: return "我的设备"
        case .sleepReminder: return "睡眠提醒"
        case .language: return "界面语言"
        case .theme: return "主题切换"
        case .soundLibrary: return "闹钟铃声库"
        case .heartRateSettings: return "心率监测设置"
        case .feedback: return "意见反馈"
        case .about: return "关于 Lume"
        }
    }

    private var alarmEditorContent: some View {
        VStack(spacing: 18) {
            VStack(spacing: 12) {
                DatePicker(
                    "开始",
                    selection: Binding(get: { viewModel.alarm.wakeStartTime }, set: { viewModel.updateWakeStartTime($0) }),
                    displayedComponents: .hourAndMinute
                )
                DatePicker(
                    "截止",
                    selection: Binding(get: { viewModel.alarm.wakeEndTime }, set: { viewModel.updateWakeEndTime($0) }),
                    displayedComponents: .hourAndMinute
                )
            }
            .datePickerStyle(.compact)
            .padding(18)
            .glassCard(cornerRadius: 22)

            repeatWeekdaySelector

            sheetActionButton(title: viewModel.alarm.isOn ? "停止智能闹钟" : "开启智能闹钟", icon: viewModel.alarm.isOn ? "stop.fill" : "play.fill") {
                viewModel.toggleAlarm()
            }
        }
    }

    private var repeatWeekdaySelector: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("重复", systemImage: "repeat")
                    .font(.headline)
                    .foregroundStyle(LumeColor.text)
                Spacer()
                Text(viewModel.alarm.formattedRepeatText)
                    .font(.caption)
                    .foregroundStyle(LumeColor.textMuted)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                ForEach(repeatWeekdayOptions, id: \.weekday) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            viewModel.toggleRepeatWeekday(option.weekday)
                        }
                    } label: {
                        Text(option.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(viewModel.alarm.repeatWeekdays.contains(option.weekday) ? LumeColor.background : LumeColor.textMuted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(
                                Capsule()
                                    .fill(viewModel.alarm.repeatWeekdays.contains(option.weekday) ? LumeColor.primary : LumeColor.surfaceHigh.opacity(0.58))
                            )
                    }
                }
            }
        }
        .padding(18)
        .glassCard(cornerRadius: 22)
    }

    private var repeatWeekdayOptions: [(weekday: Int, title: String)] {
        [(2, "一"), (3, "二"), (4, "三"), (5, "四"), (6, "五"), (7, "六"), (1, "日")]
    }

    private var deviceSettingsContent: some View {
        VStack(spacing: 14) {
            statusTile(icon: "applewatch", title: "Apple Watch", value: viewModel.watchStatus, accent: LumeColor.primary)
            statusTile(icon: "dot.radiowaves.left.and.right", title: "Watch 信号", value: viewModel.wearableSignalStatus, accent: LumeColor.secondary)
            statusTile(icon: "heart.fill", title: "HealthKit", value: viewModel.healthAuthStatus, accent: .red.opacity(0.86))
            sheetActionButton(title: "重新连接 Apple Watch", icon: "applewatch.and.arrow.forward") {
                viewModel.connectWearable()
            }
        }
    }

    private var sleepReminderContent: some View {
        VStack(spacing: 14) {
            statusTile(icon: "bell.badge.fill", title: "提醒状态", value: viewModel.alarm.isOn ? "已开启" : "未开启", accent: LumeColor.secondary)
            statusTile(icon: "clock.badge.checkmark.fill", title: "唤醒窗口", value: viewModel.alarm.formattedWakeWindow, accent: LumeColor.primary)
            sheetActionButton(title: "编辑唤醒窗口", icon: "clock") {
                activeSheet = .alarmEditor
            }
            sheetActionButton(title: viewModel.alarm.isOn ? "关闭睡眠提醒" : "开启睡眠提醒", icon: viewModel.alarm.isOn ? "bell.slash.fill" : "bell.fill") {
                viewModel.toggleAlarm()
            }
        }
    }

    private var soundLibraryContent: some View {
        VStack(spacing: 10) {
            ForEach(AlarmSound.allCases, id: \.self) { sound in
                Button {
                    viewModel.updateSound(sound)
                    viewModel.previewSelectedSound()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: sound == viewModel.alarm.sound ? "checkmark.circle.fill" : "music.note")
                            .foregroundStyle(sound == viewModel.alarm.sound ? LumeColor.primary : LumeColor.textMuted)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sound.displayName)
                                .font(.headline)
                                .foregroundStyle(LumeColor.text)
                            Text(sound.description)
                                .font(.caption)
                                .foregroundStyle(LumeColor.textMuted)
                        }
                        Spacer()
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(LumeColor.secondary)
                    }
                    .padding(16)
                    .glassCard(cornerRadius: 18)
                }
            }
        }
    }

    private var heartRateSettingsContent: some View {
        VStack(spacing: 14) {
            statusTile(icon: "heart.text.square.fill", title: "实时心率", value: heartRateText, accent: .red.opacity(0.86))
            statusTile(icon: "sensor.tag.radiowaves.forward.fill", title: "心率来源", value: viewModel.heartRateSourceStatus, accent: LumeColor.secondary)
            statusTile(icon: "checkmark.seal.fill", title: "唤醒判定", value: viewModel.triggerReasonStatus, accent: LumeColor.primary)
            sheetActionButton(title: "重新申请 HealthKit 权限", icon: "heart.fill") {
                Task {
                    await viewModel.requestPermissions()
                }
            }
        }
    }

    private func simpleSettingContent(icon: String, title: String, message: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 38))
                .foregroundStyle(LumeColor.primary)
                .frame(width: 82, height: 82)
                .glassCard(cornerRadius: 41)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(LumeColor.text)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(LumeColor.textMuted)
                .multilineTextAlignment(.center)
            sheetActionButton(title: actionTitle, icon: "checkmark") {
                action()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    private func statusTile(icon: String, title: String, value: String, accent: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(accent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LumeColor.textMuted)
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(LumeColor.text)
            }
            Spacer()
        }
        .padding(16)
        .glassCard(cornerRadius: 18)
    }

    private func sheetActionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(LumeColor.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Capsule().fill(LumeColor.primary))
        }
    }

    private var devicePage: some View {
        ScrollView {
            VStack(spacing: 18) {
                pageTitle("设备", subtitle: "Apple Watch 与 HealthKit")
                deviceSummaryCard
                compactStatusList
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(appBackground)
    }

    private var profilePage: some View {
        ScrollView {
            VStack(spacing: 18) {
                profileHeroSection
                profileStatsGrid
                profileMenuList
                Button {
                    session.signOut()
                } label: {
                    Text("退出登录")
                        .font(.headline)
                        .foregroundStyle(.red.opacity(0.82))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .glassCard(cornerRadius: 20)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 122)
        }
        .scrollIndicators(.hidden)
        .background(appBackground)
    }

    private var profileHeroSection: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [LumeColor.primary, LumeColor.secondary], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 98, height: 98)
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 84))
                        .foregroundStyle(LumeColor.background)
                }
                Text("Pro")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(LumeColor.background)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(LumeColor.primary))
                    .offset(x: 6, y: -2)
            }
            Text(session.displayName.isEmpty ? "极光探险者" : session.displayName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(LumeColor.text)
            Text("Lume Premium Member")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LumeColor.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var profileStatsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            profileStatCard(title: "累计睡眠", value: "1,248", suffix: "小时", accent: LumeColor.primary, isWide: true)
            profileStatCard(title: "早起天数", value: "156", suffix: "天", accent: LumeColor.secondary)
            profileStatCard(title: "心率达标", value: "98", suffix: "%", accent: LumeColor.primary)
        }
    }

    private func profileStatCard(title: String, value: String, suffix: String, accent: Color, isWide: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(LumeColor.textMuted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(accent)
                Text(suffix)
                    .font(.caption)
                    .foregroundStyle(LumeColor.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassCard(cornerRadius: 22)
        .gridCellColumns(isWide ? 2 : 1)
    }

    private var profileMenuList: some View {
        VStack(spacing: 0) {
            profileMenuRow(icon: "applewatch", title: "我的设备", value: shortWatchStatus, accent: LumeColor.primary) {
                viewModel.connectWearable()
                activeSheet = .device
            }
            dividerLine
            profileMenuRow(icon: "bell.badge.fill", title: "睡眠提醒", value: viewModel.alarm.isOn ? "已开启" : "未开启", accent: LumeColor.secondary) {
                activeSheet = .sleepReminder
            }
            dividerLine
            profileMenuRow(icon: "globe", title: "界面语言", value: "中文", accent: LumeColor.primary) {
                activeSheet = .language
            }
            dividerLine
            profileMenuRow(icon: "paintpalette.fill", title: "主题切换", value: "极光深色", accent: LumeColor.secondary) {
                activeSheet = .theme
            }
            dividerLine
            profileMenuRow(icon: "music.note.list", title: "闹钟铃声库", value: viewModel.alarm.sound.displayName, accent: Color(red: 0.82, green: 0.74, blue: 1.0)) {
                activeSheet = .soundLibrary
            }
            dividerLine
            profileMenuRow(icon: "heart.text.square.fill", title: "心率监测设置", value: viewModel.healthAuthStatus, accent: LumeColor.primary) {
                activeSheet = .heartRateSettings
            }
            dividerLine
            profileMenuRow(icon: "bubble.left.and.bubble.right.fill", title: "意见反馈", value: "提交建议", accent: LumeColor.textMuted) {
                activeSheet = .feedback
            }
            dividerLine
            profileMenuRow(icon: "info.circle.fill", title: "关于 Lume", value: "当前版本", accent: LumeColor.textMuted) {
                activeSheet = .about
            }
        }
        .glassCard(cornerRadius: 24)
    }

    private func profileMenuRow(icon: String, title: String, value: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .foregroundStyle(accent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(accent.opacity(0.12)))
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(LumeColor.text)
                Spacer()
                Text(value)
                    .font(.caption)
                    .foregroundStyle(LumeColor.textMuted.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(LumeColor.textMuted.opacity(0.5))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(.white.opacity(0.055))
            .frame(height: 1)
            .padding(.horizontal, 18)
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

    private func pageTitle(_ title: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.42))
            }
            Spacer()
        }
    }

    private var smartAlarmHero: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 16)
                    .frame(width: 210, height: 210)
                Circle()
                    .trim(from: 0, to: viewModel.alarm.isOn ? 0.78 : 0.52)
                    .stroke(
                        LinearGradient(colors: [.mint, .green], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .frame(width: 210, height: 210)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 8) {
                    Text(viewModel.alarm.isOn ? "智能监测中" : "今晚唤醒")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.46))
                    Text(viewModel.alarm.formattedWakeEndTime)
                        .font(.system(size: 48, weight: .light, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                    Text(viewModel.alarm.formattedWakeWindow)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.horizontal, 12)
            }
            .padding(.top, 8)

            HStack(spacing: 10) {
                intelligencePill(icon: "heart.fill", title: heartRateText, subtitle: "实时心率")
                intelligencePill(icon: "moon.zzz.fill", title: wakeDecisionText, subtitle: "唤醒策略")
            }

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                    viewModel.toggleAlarm()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: viewModel.alarm.isOn ? "stop.fill" : "play.fill")
                    Text(viewModel.alarm.isOn ? "停止监测" : "开启智能闹钟")
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            viewModel.alarm.isOn
                            ? LinearGradient(colors: [.red.opacity(0.82), .orange.opacity(0.72)], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [.mint, .green], startPoint: .leading, endPoint: .trailing)
                        )
                )
            }

            Text(viewModel.alarm.isOn ? viewModel.monitoringStatus : "到点前自动分析浅睡眠，未命中则按截止时间唤醒")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var wakeDecisionText: String {
        if viewModel.isAlarmRinging { return "已唤醒" }
        if viewModel.alarm.isOn { return "浅睡优先" }
        return "待开启"
    }

    private func intelligencePill(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.green.opacity(0.86))
                .frame(width: 30, height: 30)
                .background(Circle().fill(.white.opacity(0.08)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.36))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.black.opacity(0.18))
        )
    }

    private var compactSettingsSection: some View {
        VStack(spacing: 12) {
            Button {
                showRangePicker = true
            } label: {
                compactSettingRow(icon: "clock.badge.checkmark.fill", title: "唤醒范围", value: viewModel.alarm.formattedWakeWindow)
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
                compactSettingRow(icon: "speaker.wave.2.fill", title: "铃声", value: viewModel.alarm.sound.displayName)
            }
        }
    }

    private func compactSettingRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.green.opacity(0.86))
                .frame(width: 36, height: 36)
                .background(Circle().fill(.white.opacity(0.08)))

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.58))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.28))
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.04))
        )
    }

    private var smartSignalSection: some View {
        HStack(spacing: 10) {
            monitorStep(icon: "applewatch", text: shortWatchStatus, isActive: isWatchReady)
            monitorStep(icon: "heart.fill", text: viewModel.latestHeartRate > 0 ? "心率已同步" : "等待心率", isActive: viewModel.latestHeartRate > 0)
            monitorStep(icon: "bell.fill", text: viewModel.alarm.isOn ? "闹钟已开" : "未开启", isActive: viewModel.alarm.isOn)
        }
    }

    private var shortWatchStatus: String {
        viewModel.watchStatus.contains("已连接") ? "Watch 已连" : "连接 Watch"
    }

    private var isWatchReady: Bool {
        viewModel.watchStatus.contains("已连接") || viewModel.wearableSignalStatus.contains("收到") || viewModel.wearableSignalStatus.contains("响应")
    }

    private var deviceSummaryCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(shortWatchStatus)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(viewModel.wearableSignalStatus)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    viewModel.connectWearable()
                } label: {
                    Label("连接", systemImage: "applewatch.and.arrow.forward")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(.green.opacity(0.42)))
                }
            }

            HStack(spacing: 10) {
                intelligencePill(icon: "heart.text.square.fill", title: heartRateText, subtitle: "心率")
                intelligencePill(icon: "sensor.tag.radiowaves.forward.fill", title: viewModel.heartRateSourceStatus, subtitle: "来源")
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.white.opacity(0.05))
        )
    }

    private var compactStatusList: some View {
        VStack(spacing: 12) {
            statusRow(icon: "heart.fill", label: "HealthKit", value: viewModel.healthAuthStatus)
            statusRow(icon: "applewatch", label: "Apple Watch", value: viewModel.watchStatus)
            statusRow(icon: "waveform.path.ecg", label: "监测状态", value: viewModel.monitoringStatus)
            statusRow(icon: "checkmark.seal.fill", label: "最近判定", value: viewModel.triggerReasonStatus)
            if HealthKitManager.shared.isUsingMockData {
                statusRow(icon: "waveform.path.ecg", label: "心率模式", value: "模拟数据")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.035))
        )
    }

    private var profileCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.72))
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayName)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.9))
                    Text("智能闹钟账户")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.38))
                }
                Spacer()
            }

            Button {
                session.signOut()
            } label: {
                Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.white.opacity(0.07))
                    )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.white.opacity(0.045))
        )
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

private struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.15), .white.opacity(0.04)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
            )
    }
}

private extension View {
    func glassCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }
}

private struct ECGLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points: [CGPoint] = [
            CGPoint(x: 0.00, y: 0.58),
            CGPoint(x: 0.12, y: 0.58),
            CGPoint(x: 0.18, y: 0.40),
            CGPoint(x: 0.23, y: 0.78),
            CGPoint(x: 0.28, y: 0.14),
            CGPoint(x: 0.34, y: 0.58),
            CGPoint(x: 0.50, y: 0.58),
            CGPoint(x: 0.56, y: 0.42),
            CGPoint(x: 0.61, y: 0.78),
            CGPoint(x: 0.66, y: 0.12),
            CGPoint(x: 0.72, y: 0.58),
            CGPoint(x: 1.00, y: 0.58)
        ]

        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: rect.minX + first.x * rect.width, y: rect.minY + first.y * rect.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height))
        }
        return path
    }
}

private struct HeartRateSparkline: View {
    let samples: [Double]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let values = normalizedSamples
                guard values.count > 1 else { return }

                var path = Path()
                for index in values.indices {
                    let x = size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                    let wave = sin(timeline.date.timeIntervalSinceReferenceDate * 2.4 + Double(index) * 0.8) * 0.05
                    let yRatio = min(0.92, max(0.08, values[index] + wave))
                    let point = CGPoint(x: x, y: size.height * CGFloat(1 - yRatio))
                    if index == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }

                context.stroke(path, with: .linearGradient(
                    Gradient(colors: [LumeColor.secondary, LumeColor.primary]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: size.width, y: 0)
                ), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private var normalizedSamples: [Double] {
        let source = samples.isEmpty ? [58, 59, 57, 60, 61, 60] : samples
        guard let minValue = source.min(), let maxValue = source.max() else { return source }
        let range = max(1, maxValue - minValue)
        return source.map { ($0 - minValue) / range * 0.72 + 0.14 }
    }
}

// MARK: - App 启动页

private struct AppLaunchView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.06),
                    Color(red: 0.05, green: 0.11, blue: 0.08),
                    Color(red: 0.03, green: 0.04, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.07))
                        .frame(width: 96, height: 96)
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(
                            LinearGradient(colors: [.mint, .green], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }

                VStack(spacing: 8) {
                    Text("EchoClock")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.94))
                    Text("智能浅睡眠唤醒")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.46))
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - 登录页面

private struct LoginView: View {
    private enum AuthTab: String, CaseIterable {
        case password = "手机号登录"
        case code = "验证码登录"
        case register = "注册"
    }

    @ObservedObject var session: AppSessionViewModel
    @State private var selectedTab: AuthTab = .code
    @State private var phone = ""
    @State private var code = ""
    @State private var password = ""
    @State private var agreedToTerms = true
    @State private var isShowingWelcome = true

    var body: some View {
        ZStack {
            LumeColor.background.ignoresSafeArea()
            LinearGradient(colors: [LumeColor.primary.opacity(0.26), .clear, .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            LinearGradient(colors: [.clear, LumeColor.secondary.opacity(0.22), .clear], startPoint: .topTrailing, endPoint: .bottomLeading)
                .ignoresSafeArea()

            if isShowingWelcome {
                loginWelcomeContent
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                VStack(spacing: 28) {
                    brandHeader
                        .padding(.top, 70)

                    VStack(spacing: 14) {
                        tabSelector
                        formFields
                        primaryButton
                        secondaryActions

                        divider
                        quickLoginRow
                        termsRow

                        if let message = session.authMessage {
                            messageView(message)
                        }
                    }
                    .padding(22)
                    .glassCard(cornerRadius: 28)

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 24)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .preferredColorScheme(.dark)
    }

    private var loginWelcomeContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            Image(systemName: "moon.stars.fill")
                .font(.system(size: 46))
                .foregroundStyle(LinearGradient(colors: [LumeColor.primary, LumeColor.secondary], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 86, height: 86)
                .glassCard(cornerRadius: 43)

            VStack(alignment: .leading, spacing: 10) {
                Text("欢迎使用 EchoClock")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(LumeColor.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Text("登录后将同步你的智能闹钟配置，并请求网络连接与健康数据读取，用于 Apple Watch 心率监测和浅睡眠唤醒。")
                    .font(.subheadline)
                    .foregroundStyle(LumeColor.textMuted.opacity(0.82))
                    .lineSpacing(4)
            }

            VStack(spacing: 12) {
                permissionPreviewRow(icon: "wifi", title: "无线网与蜂窝数据", detail: "用于登录、云端同步和设备状态更新")
                permissionPreviewRow(icon: "heart.fill", title: "健康数据", detail: "读取心率与睡眠数据，评估唤醒时机")
            }

            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isShowingWelcome = false
                }
            } label: {
                Text("开始登录")
                    .font(.headline)
                    .foregroundStyle(LumeColor.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(LumeColor.primary))
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func permissionPreviewRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(LumeColor.primary)
                .frame(width: 38, height: 38)
                .background(Circle().fill(.white.opacity(0.06)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LumeColor.text)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(LumeColor.textMuted.opacity(0.74))
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(14)
        .glassCard(cornerRadius: 18)
    }

    private var brandHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("欢迎回来")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(LumeColor.text)
            Text("Lume 开启你的智愈晨间时光")
                .font(.subheadline)
                .foregroundStyle(LumeColor.textMuted.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var panelTitle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("登录 / 注册")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.92))
                Text("未注册手机号验证后自动创建账号")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.38))
            }
            Spacer()
        }
    }

    private var tabSelector: some View {
        HStack(spacing: 26) {
            ForEach(AuthTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 7) {
                        Text(tab.rawValue)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(selectedTab == tab ? LumeColor.text : LumeColor.textMuted.opacity(0.62))
                        Circle()
                            .fill(selectedTab == tab ? LumeColor.primary : .clear)
                            .frame(width: 4, height: 4)
                    }
                }
            }
            Spacer()
        }
    }

    private var formFields: some View {
        VStack(spacing: 12) {
            phoneField

            if selectedTab == .code {
                codeField
            } else if selectedTab == .register {
                authField(icon: "lock.fill", placeholder: "设置密码（至少 6 位）", text: $password, isSecure: true, keyboard: .default)
                codeField
            } else {
                authField(icon: "lock.fill", placeholder: "请输入密码", text: $password, isSecure: true, keyboard: .default)
            }
        }
    }

    private var phoneField: some View {
        authField(icon: "iphone", placeholder: "请输入手机号", text: $phone, isSecure: false, keyboard: .numberPad)
    }

    private var codeField: some View {
        HStack(spacing: 10) {
            authField(icon: "number", placeholder: "请输入验证码", text: $code, isSecure: false, keyboard: .numberPad)
            Button {
                Task {
                    await session.sendSMSCode(phone: phone)
                }
            } label: {
                Text(session.smsCountdown > 0 ? "\(session.smsCountdown)s" : "获取验证码")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(LumeColor.primary)
                    .frame(width: 92)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.white.opacity(session.smsCountdown > 0 ? 0.04 : 0.08))
                    )
            }
            .disabled(session.smsCountdown > 0 || session.isLoading)
        }
    }

    private var termsRow: some View {
        Button {
            agreedToTerms.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: agreedToTerms ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(agreedToTerms ? LumeColor.primary : LumeColor.textMuted.opacity(0.48))
                Text("我已阅读并同意《用户协议》《隐私政策》")
                    .font(.caption)
                    .foregroundStyle(LumeColor.textMuted.opacity(0.72))
                Spacer()
            }
        }
    }

    private var primaryButton: some View {
        Button {
            guard agreedToTerms else {
                session.authMessage = "请先同意用户协议与隐私政策"
                return
            }
            Task {
                switch selectedTab {
                case .code:
                    await session.signInWithCode(phone: phone, code: code)
                case .password:
                    await session.signInWithPassword(phone: phone, password: password)
                case .register:
                    await session.registerWithPassword(phone: phone, password: password, code: code)
                }
            }
        } label: {
            Text(session.isLoading ? "处理中..." : primaryButtonTitle)
                .font(.headline)
                .foregroundStyle(LumeColor.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    Capsule()
                        .fill(LumeColor.primary)
                        .shadow(color: LumeColor.primary.opacity(0.2), radius: 12, y: 4)
                )
        }
        .disabled(session.isLoading)
        .padding(.top, 4)
    }

    private var secondaryActions: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedTab = selectedTab == .password ? .code : .password
                }
            } label: {
                Text(selectedTab == .password ? "用验证码登录" : "用密码登录")
                    .font(.caption)
                    .foregroundStyle(LumeColor.secondary)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedTab = .register
                }
            } label: {
                Text("新用户注册")
                    .font(.caption)
                    .foregroundStyle(LumeColor.primary)
            }
        }
    }

    private var primaryButtonTitle: String {
        switch selectedTab {
        case .code: return "登录"
        case .password: return "密码登录"
        case .register: return "注册并登录"
        }
    }

    private var divider: some View {
        HStack {
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            Text("或者")
                .font(.caption2)
                .foregroundStyle(LumeColor.textMuted.opacity(0.48))
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
        }
        .padding(.vertical, 2)
    }

    private var quickLoginRow: some View {
        VStack(spacing: 10) {
            wechatButton
            demoButton
        }
    }

    private var wechatButton: some View {
        Button {
            guard agreedToTerms else {
                session.authMessage = "请先同意用户协议与隐私政策"
                return
            }
            Task {
                await session.signInWithWeChat()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "message.fill")
                    .foregroundStyle(Color(red: 0.03, green: 0.76, blue: 0.38))
                Text("使用微信一键登录")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(LumeColor.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(.white.opacity(0.055)).overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1)))
        }
        .disabled(session.isLoading)
    }

    private var demoButton: some View {
        Button {
            session.demoSignIn()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                Text("演示登录")
                    .font(.subheadline)
            }
            .foregroundStyle(LumeColor.textMuted.opacity(0.72))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    private func messageView(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.orange.opacity(0.92))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.orange.opacity(0.10))
            )
    }

    @ViewBuilder
    private func authField(icon: String, placeholder: String, text: Binding<String>, isSecure: Bool, keyboard: UIKeyboardType) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(LumeColor.textMuted.opacity(0.66))
                .frame(width: 22)
            if isSecure {
                SecureField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else {
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .keyboardType(keyboard)
                    .autocorrectionDisabled()
            }
        }
        .foregroundStyle(LumeColor.text)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}
