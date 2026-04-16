// CopitApp.swift
// アプリのエントリポイント
// Swift 6 / SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor 対応

import SwiftUI

@main
struct CopitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // メインウィンドウ不要。Settings シーンは SwiftUI が要求するため最小構成で定義
        Settings {
            EmptyView()
        }
    }
}
