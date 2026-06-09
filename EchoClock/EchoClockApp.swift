//
//  EchoClockApp.swift
//  EchoClock
//
//  Created by 沙飞 on 2026/6/2.
//

import SwiftUI

@main
struct EchoClockApp: App {
    init() {
        // 提前激活 WatchConnectivity Session
        _ = WatchConnectivityManager.shared
        // 初始化 EMAS Serverless 原生客户端配置。
        _ = EMASServerlessClient.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
