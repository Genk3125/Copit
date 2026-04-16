import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var shortcutManager: GlobalShortcutManager?
    private var panelController: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[Copit] ✅ App launched")
        NSApp.setActivationPolicy(.accessory)
        requestAccessibility()
        setupMenuBar()
        setupShortcuts()
        ClipboardManager.shared.startWatching()
    }

    // MARK: - Accessibility

    private func requestAccessibility() {
        let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        let trusted = AXIsProcessTrustedWithOptions(opts)
        print("[Copit] Accessibility trusted: \(trusted)")
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = statusItem?.button {
            let img = NSImage(systemSymbolName: "doc.on.clipboard.fill", accessibilityDescription: "コピット")
            img?.isTemplate = true
            btn.image = img
        }

        let menu = NSMenu()

        let title = NSMenuItem(title: "コピット (Copit)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let login = NSMenuItem(title: "ログイン時に自動起動", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state  = isLoginEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        let clear = NSMenuItem(title: "履歴をクリア", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        menu.addItem(.separator())

        let access = NSMenuItem(title: "アクセシビリティ設定を開く...", action: #selector(openAccessibility), keyEquivalent: "")
        access.target = self
        menu.addItem(access)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
        print("[Copit] ✅ Menu bar setup complete")
    }

    @objc private func toggleLogin() {
        let svc = SMAppService.mainApp
        try? svc.status == .enabled ? svc.unregister() : svc.register()
        statusItem?.menu?.items
            .filter { $0.action == #selector(toggleLogin) }
            .forEach { $0.state = isLoginEnabled ? .on : .off }
    }

    @objc private func clearHistory() { ClipboardManager.shared.clear() }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private var isLoginEnabled: Bool { SMAppService.mainApp.status == .enabled }

    // MARK: - Shortcuts

    private func setupShortcuts() {
        let pc  = PanelController()
        let mgr = GlobalShortcutManager()

        mgr.onSpecialCopy = { text in ClipboardManager.shared.add(text) }
        mgr.onShowPasteUI = { [weak pc] in pc?.show() }

        mgr.start()
        shortcutManager  = mgr
        panelController  = pc
    }
}
