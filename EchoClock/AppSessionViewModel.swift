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

    private let authKey = "EchoClock.isAuthenticated"
    private let emailKey = "EchoClock.email"
    private let nameKey = "EchoClock.displayName"

    init() {
        let defaults = UserDefaults.standard
        isAuthenticated = defaults.bool(forKey: authKey)
        email = defaults.string(forKey: emailKey) ?? ""
        displayName = defaults.string(forKey: nameKey) ?? "晨醒用户"
    }

    func signIn(email: String, password: String) {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        self.email = trimmedEmail.isEmpty ? "demo@echoclock.app" : trimmedEmail
        displayName = self.email.components(separatedBy: "@").first ?? "晨醒用户"
        isAuthenticated = true
        persist()
    }

    func demoSignIn() {
        email = "demo@echoclock.app"
        displayName = "演示用户"
        isAuthenticated = true
        persist()
    }

    func signOut() {
        isAuthenticated = false
        persist()
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(isAuthenticated, forKey: authKey)
        defaults.set(email, forKey: emailKey)
        defaults.set(displayName, forKey: nameKey)
    }
}
