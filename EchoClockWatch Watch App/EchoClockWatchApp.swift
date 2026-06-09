//
//  EchoClockWatchApp.swift
//  EchoClockWatch Watch App
//
//  Created by 沙飞 on 2026/6/2.
//

import SwiftUI

@main
struct EchoClockWatch_Watch_AppApp: App {
    init() {
        _ = WatchConnectivityManager.shared
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
    }
}
