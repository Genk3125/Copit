// AppDelegate.swift
// アプリライフサイクル管理・メニューバー構築・各コンポーネントの統合
// Swift 6 / SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor 対応

import AppKit
import ServiceManagement

/// @MainActor: AppKit デリゲートメソッドはメインスレッドで呼ばれるため
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private let clipboardManager = ClipboardManager.shared
    private let clipboardWatcher = ClipboardWatcher.shared
    private var shortcutManager: GlobalShortcutManager?
    private var panelController: CopitPanelController?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock アイコンを非表示にしてメニューバー常駐型に設定
        NSApp.setActivationPolicy(.accessory)

        requestAccessibilityIfNeeded()
        setupMenuBar()
        setupPanelController()
        setupGlobalShortcuts()
        clipboardWatcher.start()
    }

    // MARK: - アクセシビリティ権限

    private func requestAccessibilityIfNeeded() {
        let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        let trusted = AXIsProcessTrustedWithOptions(opts)
        if !trusted {
            print("[Copit] アクセシビリティ権限が必要です。システム設定 > プライバシーとセキュリティ > アクセシビリティ で許可してください。")
        }
    }

    // MARK: - メニューバー

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem?.button else { return }
        if let img = NSImage(systemSymbolName: "doc.on.clipboard.fill", accessibilityDescription: "コピット") {
            img.isTemplate = true
            button.image = img
        }

        let menu = NSMenu()

        let header = NSMenuItem(title: "コピット (Copit)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let loginItem = NSMenuItem(
            title: "ログイン時に自動起動",
            action: #selector(toggleLoginItem),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = isLoginItemEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let clearItem = NSMenuItem(
            title: "履歴をクリア",
            action: #selector(clearHistory),
            keyEquivalent: ""
        )
        clearItem.target = self
        menu.addItem(clearItem)

        menu.addItem(.separator())

        let accessItem = NSMenuItem(
            title: "アクセシビリティ設定を開く...",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        accessItem.target = self
        menu.addItem(accessItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "終了",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
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
            print("[Copit] ログイン項目の切り替えに失敗: \(error.localizedDescription)")
        }
        // チェック状態を更新
        statusItem?.menu?.items
            .filter { $0.action == #selector(toggleLoginItem) }
            .forEach { $0.state = isLoginItemEnabled ? .on : .off }
    }

    @objc private func clearHistory() {
        clipboardManager.clear()
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
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
        let mgr = GlobalShortcutManager()

        // ⌘⇧C: テキストを取得して履歴に追加
        mgr.onSpecialCopy = { [weak self] text in
            self?.clipboardManager.add(text: text)
        }

        // ⌘⇧V: ペーストパネルを表示
        mgr.onShowPasteUI = { [weak self] in
            self?.panelController?.show()
        }

        mgr.start()
        shortcutManager = mgr
    }
}
