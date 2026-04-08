// AppDelegate.swift
// アプリ全体のライフサイクル管理・メニューバー構築・各コンポーネントの統合

import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private let clipboardManager = ClipboardManager.shared
    private let clipboardWatcher = ClipboardWatcher.shared
    private var shortcutManager: GlobalShortcutManager?
    private var panelController: CopitPanelController?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dockアイコンを非表示にしてメニューバー常駐型に設定
        NSApp.setActivationPolicy(.accessory)

        checkAndRequestAccessibility()
        setupMenuBar()
        setupPanelController()
        setupGlobalShortcuts()
        clipboardWatcher.start()
    }

    // MARK: - アクセシビリティ権限

    private func checkAndRequestAccessibility() {
        // kAXTrustedCheckOptionPrompt: true = 未許可時にシステムダイアログを表示
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        let trusted = AXIsProcessTrustedWithOptions(options)

        if !trusted {
            // 初回起動時はシステム設定のダイアログが自動表示される
            // 許可後はアプリ再起動が必要
            print("[Copit] アクセシビリティ権限が必要です。システム設定 > プライバシーとセキュリティ > アクセシビリティ で許可してください。")
        }
    }

    // MARK: - メニューバー

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem?.button else { return }
        // クリップボードアイコン
        if let img = NSImage(systemSymbolName: "doc.on.clipboard.fill", accessibilityDescription: "コピット") {
            img.isTemplate = true  // ダーク/ライトモード自動対応
            button.image = img
        }

        let menu = NSMenu()

        // ヘッダー
        let header = NSMenuItem(title: "コピット (Copit)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // ログイン時自動起動トグル
        let loginItem = NSMenuItem(
            title: "ログイン時に自動起動",
            action: #selector(toggleLoginItem),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = isLoginItemEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        // 履歴クリア
        let clearItem = NSMenuItem(
            title: "履歴をクリア",
            action: #selector(clearHistory),
            keyEquivalent: ""
        )
        clearItem.target = self
        menu.addItem(clearItem)

        menu.addItem(.separator())

        // アクセシビリティ設定を開く
        let accessibilityItem = NSMenuItem(
            title: "アクセシビリティ設定を開く...",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        menu.addItem(.separator())

        // 終了
        let quit = NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem?.menu = menu
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            print("[Copit] ログイン項目の切り替えに失敗しました: \(error.localizedDescription)")
        }
        // メニューのチェック状態を更新
        if let menu = statusItem?.menu {
            for item in menu.items where item.action == #selector(toggleLoginItem) {
                item.state = isLoginItemEnabled ? .on : .off
            }
        }
    }

    @objc private func clearHistory() {
        clipboardManager.clear()
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private var isLoginItemEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    // MARK: - パネルコントローラー

    private func setupPanelController() {
        panelController = CopitPanelController(clipboardManager: clipboardManager)
    }

    // MARK: - グローバルショートカット

    private func setupGlobalShortcuts() {
        shortcutManager = GlobalShortcutManager()

        // ⌘+Shift+C: 取得したテキストを履歴に保存
        shortcutManager?.onSpecialCopy = { [weak self] text in
            self?.clipboardManager.add(text: text)
        }

        // ⌘+Shift+V: ペーストUIを表示
        shortcutManager?.onShowPasteUI = { [weak self] in
            self?.panelController?.show()
        }

        shortcutManager?.start()
    }
}
