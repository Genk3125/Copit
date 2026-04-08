// CopitPanelController.swift
// フローティングパネルの構築・表示・キー操作・ペースト実行を担当

import AppKit
import SwiftUI

// MARK: - CopitPanel

/// キーウィンドウになれるカスタム NSPanel
/// borderless スタイルでは canBecomeKey が false になるため明示的にオーバーライド
final class CopitPanel: NSPanel {
    override var canBecomeKey: Bool  { true  }
    override var canBecomeMain: Bool { false }
}

// MARK: - CopitPanelController

final class CopitPanelController {
    private static let syntheticEventTag: Int64 = 0x434F504954

    // MARK: - Properties

    private let clipboardManager: ClipboardManager
    let viewModel = CopitViewModel()

    private var panel: CopitPanel?
    private var previousApp: NSRunningApplication?  // ペースト先アプリ
    private var localMonitor: Any?                   // キーイベント監視
    private var resignObserver: NSObjectProtocol?    // フォーカス喪失監視

    // パネルサイズ定数
    private let panelWidth:  CGFloat = 384
    private let panelHeight: CGFloat = 274

    // MARK: - Init

    init(clipboardManager: ClipboardManager) {
        self.clipboardManager = clipboardManager
    }

    // MARK: - Show

    func show() {
        // ペースト先アプリを記憶（パネル表示前に保存）
        previousApp = NSWorkspace.shared.frontmostApplication

        // 最新の履歴をViewModelに同期
        viewModel.load(from: clipboardManager.items)

        // パネルを初回作成
        if panel == nil { buildPanel() }

        // マウスカーソル付近に配置
        positionPanel()

        // 表示 & フォーカス取得
        panel?.alphaValue = 0
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // フェードイン
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel?.animator().alphaValue = 1
        }

        // キーボード監視開始
        startKeyMonitor()

        // パネルがキーウィンドウを失ったとき（外クリックなど）に自動で閉じる
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

        // フェードアウト
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            self.panel?.animator().alphaValue = 0
        } completionHandler: {
            self.panel?.orderOut(nil)
            self.panel?.alphaValue = 1
        }
    }

    // MARK: - Paste Execution

    func pasteSelectedItem() {
        guard let text = viewModel.selectedItem?.text else { return }

        // 1. 選択テキストをシステムクリップボードにセット
        let pb = NSPasteboard.general
        ClipboardWatcher.shared.ignoreNextOwnWrite()
        pb.clearContents()
        pb.setString(text, forType: .string)

        // 2. UIを閉じる
        hide()

        // 2.5 ペースト音を鳴らす 🔊
        SoundManager.shared.playPaste()

        // 3. 元のアプリをアクティブ化してから ⌘V を送信
        let target = previousApp
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            target?.activate()
            // アプリのアクティブ化を少し待つ
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                self.postCmdV()
            }
        }
    }

    // MARK: - ⌘V シミュレート

    private func postCmdV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 0x09  // V キー

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags   = .maskCommand
        keyDown?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
        keyUp?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)

        // cghidEventTap: ハードウェアイベントとして注入（最も互換性が高い）
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    // MARK: - Keyboard Monitor

    private func startKeyMonitor() {
        // NSEvent ローカルモニター: パネルがキーウィンドウのとき有効
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            return self?.handleKeyEvent(event)
        }
    }

    private func stopKeyMonitor() {
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 49:       // Space   → 下に移動
            viewModel.moveDown()
            return nil

        case 125:      // ↓ Arrow → 下に移動
            viewModel.moveDown()
            return nil

        case 126:      // ↑ Arrow → 上に移動
            viewModel.moveUp()
            return nil

        case 36, 76:   // Return / Enter → ペースト実行
            pasteSelectedItem()
            return nil

        case 53:       // Escape → キャンセル
            hide()
            return nil

        case 51, 117:  // Delete / Forward Delete → 削除
            deleteSelectedItem()
            return nil

        case 7:        // X → 削除
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                deleteSelectedItem()
                return nil
            }
            return event

        case 3:        // F → お気に入り切り替え
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                toggleFavoriteForSelectedItem()
                return nil
            }
            return event

        default:
            return event
        }
    }

    // MARK: - Panel Construction

    private func buildPanel() {
        let panel = CopitPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isReleasedWhenClosed = false
        panel.level               = .floating        // 他のウィンドウより前面に表示
        panel.backgroundColor     = .clear
        panel.isOpaque            = false
        panel.hasShadow           = false             // 影はSwiftUI側で描画
        panel.animationBehavior   = .utilityWindow
        // 全スペース・フルスクリーンでも表示
        panel.collectionBehavior  = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // SwiftUI ビューを埋め込む
        let rootView = CopitListView(
            viewModel: viewModel,
            onPaste: { [weak self] in self?.pasteSelectedItem() },
            onHide:  { [weak self] in self?.hide() },
            onDeleteSelected: { [weak self] in self?.deleteSelectedItem() },
            onToggleFavoriteSelected: { [weak self] in self?.toggleFavoriteForSelectedItem() }
        )

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        panel.contentView = hosting

        self.panel = panel
    }

    // MARK: - Positioning

    private func positionPanel() {
        guard let panel else { return }

        // メインスクリーン（マウスがいるスクリーン）を取得
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let screen else { return }

        let mouse   = NSEvent.mouseLocation
        let size    = CGSize(width: panelWidth, height: panelHeight)
        let sf      = screen.visibleFrame

        // カーソルの少し上に表示（IME変換候補ウィンドウ風）
        var x = mouse.x - size.width  / 2
        var y = mouse.y + 20           // カーソルの上方向にオフセット

        // スクリーン境界を超えないようにクランプ
        x = max(sf.minX + 10, min(x, sf.maxX - size.width  - 10))
        y = max(sf.minY + 10, min(y, sf.maxY - size.height - 10))

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func deleteSelectedItem() {
        guard let id = viewModel.removeSelectedItem() else { return }
        clipboardManager.remove(id: id)

        if clipboardManager.items.isEmpty {
            hide()
        } else {
            viewModel.load(from: clipboardManager.items)
        }
    }

    private func toggleFavoriteForSelectedItem() {
        guard let id = viewModel.toggleFavoriteForSelectedItem() else { return }
        clipboardManager.toggleFavorite(id: id)
        viewModel.load(from: clipboardManager.items)
    }
}
