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
    @Published var displayName: String
    @Published var isLoading: Bool = false
    @Published var authMessage: String?

    private let authKey = "EchoClock.isAuthenticated"
    private let emailKey = "EchoClock.email"
    private let nameKey = "EchoClock.displayName"
    private let tokenKey = "EchoClock.emasToken"
    private var token: String?

    init() {
        let defaults = UserDefaults.standard
        isAuthenticated = defaults.bool(forKey: authKey)
        email = defaults.string(forKey: emailKey) ?? ""
        displayName = defaults.string(forKey: nameKey) ?? "晨醒用户"
        token = defaults.string(forKey: tokenKey)
    }

    func signIn(email: String, password: String) async {
        await authenticate(mode: .login, email: email, password: password)
    }

    func register(email: String, password: String) async {
        await authenticate(mode: .register, email: email, password: password)
    }

    func demoSignIn() {
        email = "demo@echoclock.app"
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

    private func authenticate(mode: EMASAuthMode, email: String, password: String) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            authMessage = "请输入邮箱和密码"
            return
        }

        isLoading = true
        authMessage = nil
        defer { isLoading = false }

        do {
            let session: EMASAuthSession
            switch mode {
            case .login:
                session = try await EMASServerlessClient.shared.login(email: trimmedEmail, password: password)
            case .register:
                session = try await EMASServerlessClient.shared.register(email: trimmedEmail, password: password)
            }
            self.email = session.user.email ?? trimmedEmail
            displayName = session.user.displayName ?? self.email.components(separatedBy: "@").first ?? "晨醒用户"
            token = session.token
            isAuthenticated = true
            persist()
        } catch {
            authMessage = error.localizedDescription
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(isAuthenticated, forKey: authKey)
        defaults.set(email, forKey: emailKey)
        defaults.set(displayName, forKey: nameKey)
        defaults.set(token, forKey: tokenKey)
    }
}
