// CopitPanelController.swift
// フローティングパネルの構築・表示・キー操作・ペースト実行
// Swift 6 / SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor 対応

import AppKit
import SwiftUI

// MARK: - CopitPanel

/// borderless スタイルでもキーウィンドウになれるカスタム NSPanel
final class CopitPanel: NSPanel {
    override var canBecomeKey:  Bool { true  }
    override var canBecomeMain: Bool { false }
}

// MARK: - CopitPanelController

/// @MainActor: AppKit UI は全てメインスレッドで操作するため
@MainActor
final class CopitPanelController {

    // MARK: - 仮想キー送信タグ

    private static let syntheticTag: Int64 = 0x434F504954

    // MARK: - Properties

    private let clipboardManager: ClipboardManager
    let viewModel = CopitViewModel()

    private var panel: CopitPanel?
    private var previousApp: NSRunningApplication?
    private var localMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    private let panelWidth:  CGFloat = 384
    private let panelHeight: CGFloat = 274

    // MARK: - Init

    init(clipboardManager: ClipboardManager) {
        self.clipboardManager = clipboardManager
    }

    // MARK: - Show

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        viewModel.load(from: clipboardManager.items)

        if panel == nil { buildPanel() }
        positionPanel()

        panel?.alphaValue = 0
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel?.animator().alphaValue = 1
        }

        startKeyMonitor()

        if let panel {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                self?.hide()
            }
        }
    }

    // MARK: - Hide

    func hide() {
        stopKeyMonitor()

        if let obs = resignObserver {
            NotificationCenter.default.removeObserver(obs)
            resignObserver = nil
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            self.panel?.animator().alphaValue = 0
        } completionHandler: {
            self.panel?.orderOut(nil)
            self.panel?.alphaValue = 1
        }
    }

    // MARK: - Paste

    func pasteSelectedItem() {
        guard let text = viewModel.selectedItem?.text else { return }

        // 1. 選択テキストをクリップボードにセット
        ClipboardWatcher.shared.ignoreNextOwnWrite()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        // 2. パネルを閉じる
        hide()

        // 3. ペースト音
        SoundManager.shared.playPaste()

        // 4. 元アプリをアクティブ化してから ⌘V を送信
        let target = previousApp
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            target?.activate()
            try? await Task.sleep(for: .milliseconds(80))
            self.postCmdV()
        }
    }

    // MARK: - ⌘V 送信

    private func postCmdV() {
        let src  = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 0x09

        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)

        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
        up?.setIntegerValueField(.eventSourceUserData,   value: Self.syntheticTag)

        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - キーボード監視

    private func startKeyMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
    }

    private func stopKeyMonitor() {
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        let noMod = event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty

        switch event.keyCode {
        case 49, 125:    // Space / ↓ → 下へ
            viewModel.moveDown()
            return nil

        case 126:        // ↑ → 上へ
            viewModel.moveUp()
            return nil

        case 36, 76:     // Return / Enter → ペースト
            pasteSelectedItem()
            return nil

        case 53:         // Escape → キャンセル
            hide()
            return nil

        case 51, 117:    // Delete / Forward Delete → 削除
            deleteSelected()
            return nil

        case 7:          // X（修飾キーなし）→ 削除
            if noMod { deleteSelected(); return nil }
            return event

        case 3:          // F（修飾キーなし）→ お気に入りトグル
            if noMod { toggleFavoriteSelected(); return nil }
            return event

        default:
            return event
        }
    }

    // MARK: - アイテム操作

    private func deleteSelected() {
        guard let id = viewModel.removeSelectedItem() else { return }
        clipboardManager.remove(id: id)

        if clipboardManager.items.isEmpty {
            hide()
        } else {
            viewModel.load(from: clipboardManager.items)
        }
    }

    private func toggleFavoriteSelected() {
        guard let id = viewModel.toggleFavoriteForSelectedItem() else { return }
        clipboardManager.toggleFavorite(id: id)
        viewModel.load(from: clipboardManager.items)
    }

    // MARK: - パネル構築

    private func buildPanel() {
        let p = CopitPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.isReleasedWhenClosed = false
        p.level               = .floating
        p.backgroundColor     = .clear
        p.isOpaque            = false
        p.hasShadow           = false
        p.animationBehavior   = .utilityWindow
        p.collectionBehavior  = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let rootView = CopitListView(
            viewModel: viewModel,
            onPaste:                 { [weak self] in self?.pasteSelectedItem() },
            onHide:                  { [weak self] in self?.hide() },
            onDeleteSelected:        { [weak self] in self?.deleteSelected() },
            onToggleFavoriteSelected:{ [weak self] in self?.toggleFavoriteSelected() }
        )

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        p.contentView = hosting

        panel = p
    }

    // MARK: - パネル位置決め

    private func positionPanel() {
        guard let panel else { return }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else { return }

        let sf = screen.visibleFrame
        var x = mouse.x - panelWidth  / 2
        var y = mouse.y + 20

        x = max(sf.minX + 10, min(x, sf.maxX - panelWidth  - 10))
        y = max(sf.minY + 10, min(y, sf.maxY - panelHeight - 10))

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
