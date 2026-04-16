// GlobalShortcutManager.swift
// CGEventTap を使ったグローバルショートカット検知
//
// Swift 6 / SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor 対応
//
// ─── 問題の解説 ───────────────────────────────────────────────────
// SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor を有効にすると、
// モジュール内の全宣言が暗黙的に @MainActor になる。
// しかし CGEventTap のコールバックは @convention(c) であり、
// Swift の型システム上は "nonisolated" なコンテキスト。
// → @MainActor なメソッドを直接呼べずコンパイルエラーになる。
//
// ─── 解決策 ────────────────────────────────────────────────────────
// 1. EventTap の生ポインタ関連プロパティに nonisolated(unsafe) を付与
//    → nonisolated なコンテキストからでもアクセス可能にする
// 2. コールバックから呼ばれるメソッドに nonisolated を付与
// 3. @MainActor が必要な処理は Task { @MainActor in } で安全にディスパッチ
// ─────────────────────────────────────────────────────────────────

import AppKit

// MARK: - GlobalShortcutManager

/// モジュール全体が @MainActor でも、CGEventTap 関連は
/// nonisolated(unsafe) / nonisolated で明示的に管理する
final class GlobalShortcutManager {

    // MARK: - Callbacks（@MainActor コンテキストから設定する）

    /// ⌘⇧C で取得したテキストを渡すコールバック
    var onSpecialCopy: ((String) -> Void)?

    /// ⌘⇧V でパネル表示を要求するコールバック
    var onShowPasteUI: (() -> Void)?

    // MARK: - EventTap 関連（C コールバックからもアクセスするため nonisolated(unsafe)）

    nonisolated(unsafe) private var eventTap: CFMachPort?
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?

    // MARK: - Constants

    private static let kVK_C: Int64 = 0x08
    private static let kVK_V: Int64 = 0x09

    /// 自前で合成したキーイベントを識別するタグ
    nonisolated(unsafe) static let syntheticTag: Int64 = 0x434F504954

    // MARK: - Start / Stop

    /// @MainActor コンテキストから呼ぶこと
    func start() {
        guard AXIsProcessTrusted() else {
            print("[Copit] アクセシビリティ権限がありません。システム設定で許可してください。")
            return
        }

        let eventMask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        // @convention(c) クロージャ: self をキャプチャ不可 → refcon 経由で取得
        let callback: CGEventTapCallBack = { _, type, event, refcon -> Unmanaged<CGEvent>? in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let mgr = Unmanaged<GlobalShortcutManager>.fromOpaque(refcon).takeUnretainedValue()
            // nonisolated メソッドを呼ぶ（型システムが @convention(c) から許可する）
            if let modified = mgr.handleFromTap(type: type, event: event) {
                // passUnretained: 元イベントはシステムが所有する。
                // passRetained にするとキー入力ごとに retain count が増え、リークする。
                return Unmanaged.passUnretained(modified)
            }
            return nil  // nil = イベントを消費（伝播させない）
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: selfPtr
        ) else {
            print("[Copit] CGEventTap の作成に失敗しました。アクセシビリティ権限を確認してください。")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("[Copit] グローバルショートカット登録完了 (⌘⇧C / ⌘⇧V)")
    }

    func stop() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - EventTap コールバック（nonisolated: @convention(c) から呼ばれる）

    /// CGEventTap の C コールバックから直接呼ばれる。
    /// nonisolated にすることで @convention(c) コンテキストから呼び出し可能。
    /// @MainActor が必要な処理は Task { @MainActor in } に委ねる。
    nonisolated func handleFromTap(type: CGEventType, event: CGEvent) -> CGEvent? {

        // タップが止まった場合に再有効化
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return event
        }

        guard type == .keyDown else { return event }

        let flags    = event.flags
        let keyCode  = event.getIntegerValueField(.keyboardEventKeycode)
        let userData = event.getIntegerValueField(.eventSourceUserData)

        // 自前で合成したキーは素通り
        if userData == GlobalShortcutManager.syntheticTag { return event }

        let hasCmd   = flags.contains(.maskCommand)
        let hasShift = flags.contains(.maskShift)
        let hasAlt   = flags.contains(.maskAlternate)
        let hasCtrl  = flags.contains(.maskControl)

        guard hasCmd, !hasAlt, !hasCtrl else { return event }

        if hasShift {
            // ⌘⇧C → 特殊コピー
            if keyCode == GlobalShortcutManager.kVK_C {
                Task { @MainActor [weak self] in self?.performSpecialCopy() }
                return nil  // イベントを消費
            }
            // ⌘⇧V → ペーストUI表示
            if keyCode == GlobalShortcutManager.kVK_V {
                Task { @MainActor [weak self] in self?.onShowPasteUI?() }
                return nil  // イベントを消費
            }
            return event
        }

        // ⌘V → ペースト音
        if keyCode == GlobalShortcutManager.kVK_V {
            Task { @MainActor in SoundManager.shared.playPaste() }
            return event  // ⌘V 自体は通常通り伝播
        }

        return event
    }

    // MARK: - 特殊コピー処理（@MainActor）

    private func performSpecialCopy() {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        let countBefore = pasteboard.changeCount

        // 仮想 ⌘C を送信してテキストをコピーさせる
        postSyntheticCmd(keyCode: CGKeyCode(GlobalShortcutManager.kVK_C))

        // クリップボードが更新されるのを少し待つ
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(180))

            let copied = pasteboard.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // クリップボードを元に戻す（成否に関わらず必ず実行）
            defer {
                ClipboardWatcher.shared.ignoreNextOwnWrite()
                snapshot.restore(to: pasteboard)
            }

            guard
                pasteboard.changeCount != countBefore,
                let copied,
                !copied.isEmpty
            else { return }

            self.onSpecialCopy?(copied)
            SoundManager.shared.playSpecialCopy()
        }
    }

    // MARK: - 仮想キー送信（@MainActor）

    private func postSyntheticCmd(keyCode: CGKeyCode) {
        let src  = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)

        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.setIntegerValueField(.eventSourceUserData, value: GlobalShortcutManager.syntheticTag)
        up?.setIntegerValueField(.eventSourceUserData,   value: GlobalShortcutManager.syntheticTag)

        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

// MARK: - PasteboardSnapshot

/// クリップボードの内容を丸ごとスナップショット化して復元するユーティリティ
/// Sendable: Task 境界を越えて安全に渡せる
private struct PasteboardSnapshot: Sendable {

    private let contents: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        contents = pasteboard.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !contents.isEmpty else { return }
        let items = contents.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
