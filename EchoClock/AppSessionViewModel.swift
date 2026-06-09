//
//  AppSessionViewModel.swift
//  EchoClock
//
//  本地演示登录状态；后续可替换为 MemFire Cloud Auth。
//

import Foundation
import Combine

@MainActor
final class AppSessionViewModel: ObservableObject {
    @Published var isAuthenticated: Bool
    @Published var email: String
    @Published var phone: String
    @Published var displayName: String
    @Published var isLoading: Bool = false
    @Published var authMessage: String?
    @Published var smsCountdown: Int = 0

    private let authKey = "EchoClock.isAuthenticated"
    private let emailKey = "EchoClock.email"
    private let phoneKey = "EchoClock.phone"
    private let nameKey = "EchoClock.displayName"
    private let tokenKey = "EchoClock.emasToken"
    private var token: String?
    private var smsTimer: Timer?

    init() {
        let defaults = UserDefaults.standard
        isAuthenticated = defaults.bool(forKey: authKey)
        email = defaults.string(forKey: emailKey) ?? ""
        phone = defaults.string(forKey: phoneKey) ?? ""
        displayName = defaults.string(forKey: nameKey) ?? "晨醒用户"
        token = defaults.string(forKey: tokenKey)
    }

    func sendSMSCode(phone: String) async {
        let normalizedPhone = normalizedPhone(phone)
        guard isValidMainlandPhone(normalizedPhone) else {
            authMessage = "请输入 11 位手机号"
            return
        }
        guard smsCountdown == 0 else { return }

        isLoading = true
        authMessage = nil
        defer { isLoading = false }

        do {
            try await EMASServerlessClient.shared.sendSMSCode(phone: normalizedPhone)
            startSMSCountdown()
            authMessage = "验证码已发送"
        } catch {
            authMessage = error.localizedDescription
        }
    }

    func signInWithCode(phone: String, code: String) async {
        let normalizedPhone = normalizedPhone(phone)
        guard isValidMainlandPhone(normalizedPhone) else {
            authMessage = "请输入 11 位手机号"
            return
        }
        guard code.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4 else {
            authMessage = "请输入验证码"
            return
        }

        await authenticate {
            try await EMASServerlessClient.shared.loginWithCode(phone: normalizedPhone, code: code)
        }
    }

    func signInWithPassword(phone: String, password: String) async {
        let normalizedPhone = normalizedPhone(phone)
        guard validatePhoneAndPassword(phone: normalizedPhone, password: password) else { return }

        await authenticate {
            try await EMASServerlessClient.shared.loginWithPassword(phone: normalizedPhone, password: password)
        }
    }

    func registerWithPassword(phone: String, password: String, code: String?) async {
        let normalizedPhone = normalizedPhone(phone)
        guard validatePhoneAndPassword(phone: normalizedPhone, password: password) else { return }

        await authenticate {
            try await EMASServerlessClient.shared.registerWithPassword(phone: normalizedPhone, password: password, code: code)
        }
    }

    func signInWithWeChat() async {
        await authenticate {
            try await EMASServerlessClient.shared.loginWithWeChat()
        }
    }

    func demoSignIn() {
        email = "demo@echoclock.app"
        phone = "13800000000"
        displayName = "演示用户"
        token = nil
        isAuthenticated = true
        authMessage = nil
        persist()
    }

    func signOut() {
        isAuthenticated = false
        token = nil
        persist()
    }

    private func authenticate(operation: () async throws -> EMASAuthSession) async {
        isLoading = true
        authMessage = nil
        defer { isLoading = false }

        do {
            let session = try await operation()
            apply(session)
        } catch {
            authMessage = error.localizedDescription
        }
    }

    private func apply(_ session: EMASAuthSession, fallbackEmail: String? = nil) {
        email = session.user.email ?? fallbackEmail ?? email
        phone = session.user.phone ?? phone
        let fallbackName = !phone.isEmpty ? "用户 \(phone.suffix(4))" : (email.components(separatedBy: "@").first ?? "晨醒用户")
        displayName = session.user.displayName ?? fallbackName
        token = session.token
        isAuthenticated = true
        persist()
    }

    private func validatePhoneAndPassword(phone: String, password: String) -> Bool {
        guard isValidMainlandPhone(phone) else {
            authMessage = "请输入 11 位手机号"
            return false
        }
        guard password.count >= 6 else {
            authMessage = "密码不能低于 6 位"
            return false
        }
        return true
    }

    private func normalizedPhone(_ value: String) -> String {
        value.filter { $0.isNumber }
    }

    private func isValidMainlandPhone(_ value: String) -> Bool {
        value.count == 11 && value.first == "1"
    }

    private func startSMSCountdown() {
        smsTimer?.invalidate()
        smsCountdown = 60
        smsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.smsCountdown <= 1 {
                    self.smsCountdown = 0
                    self.smsTimer?.invalidate()
                    self.smsTimer = nil
                } else {
                    self.smsCountdown -= 1
                }
            }
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(isAuthenticated, forKey: authKey)
        defaults.set(email, forKey: emailKey)
        defaults.set(phone, forKey: phoneKey)
        defaults.set(displayName, forKey: nameKey)
        defaults.set(token, forKey: tokenKey)
    }
}
