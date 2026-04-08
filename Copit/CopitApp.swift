// CopitApp.swift
// コピット - メインエントリポイント
// @main アノテーションでアプリが起動し、AppDelegateへ処理を委譲する

import SwiftUI

@main
struct CopitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // メインウィンドウは不要。設定シーンのみ（Settingsシーン必須）
        Settings {
            EmptyView()
        }
    }
}
