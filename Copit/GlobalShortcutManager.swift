// GlobalShortcutManager.swift
// CGEventTap を使ったグローバルショートカット検知
//
// Swift 6 / SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor 対応
//
// ─── CGEventTap と MainActor の橋渡し ────────────────────────────
// CGEventTap のコールバックは @convention(c) のため Swift アクター隔離が
// 適用されない。ただし CFRunLoopGetMain() に追加しているので、
// コールバックは常にメインスレッド上で実行される。
//
// → MainActor.assumeIsolated を使うことで:
//     ① 型システムに「ここはメインアクター」と伝え、@MainActor メソッドを直接呼べる
//     ② Task のスケジューリング遅延・キャンセルリスクを排除できる
//     ③ 特殊コピーの DispatchQueue.main.asyncAfter も同じ理由で安全に使える
// ─────────────────────────────────────────────────────────────────

import AppKit

// MARK: - GlobalShortcutManager

final class GlobalShortcutManager {

    // MARK: - Callbacks（@MainActor コンテキストから設定する）

    var onSpecialCopy: ((String) -> Void)?
    var onShowPasteUI: (() -> Void)?

    // MARK: - EventTap（C コールバックからもアクセスするため nonisolated(unsafe)）

    nonisolated(unsafe) private var eventTap: CFMachPort?
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?

    // MARK: - Constants

    private static let kVK_C: CGKeyCode = 0x08
    private static let kVK_V: CGKeyCode = 0x09

    // 自前で合成したキーイベントを識別するタグ
    nonisolated(unsafe) static let syntheticTag: Int64 = 0x434F504954

    // MARK: - Start / Stop

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
            if let modified = mgr.handleFromTap(type: type, event: event) {
                // passUnretained: イベントはシステムが所有 → 余分な retain は不要
                return Unmanaged.passUnretained(modified)
            }
            return nil  // nil = イベント消費（後続に伝播させない）
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: selfPtr
        ) else {
            print("[Copit] CGEventTap の作成に失敗。アクセシビリティ権限を確認してください。")
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

    // MARK: - イベントハンドラ（nonisolated: @convention(c) から呼ばれる）

    /// CGEventTap コールバックから直接呼ばれる。
    /// タップは CFRunLoopGetMain() に登録済みなのでメインスレッド上で実行される。
    /// MainActor.assumeIsolated で @MainActor メソッドを安全・同期的に呼ぶ。
    nonisolated func handleFromTap(type: CGEventType, event: CGEvent) -> CGEvent? {

        // タップが無効化されたら即再有効化
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return event
        }

        guard type == .keyDown else { return event }

        let flags    = event.flags
        let keyCode  = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let userData = event.getIntegerValueField(.eventSourceUserData)

        // 自前で合成したキーは素通り（無限ループ防止）
        if userData == GlobalShortcutManager.syntheticTag { return event }

        let hasCmd   = flags.contains(.maskCommand)
        let hasShift = flags.contains(.maskShift)
        let hasAlt   = flags.contains(.maskAlternate)
        let hasCtrl  = flags.contains(.maskControl)

        guard hasCmd, !hasAlt, !hasCtrl else { return event }

        if hasShift {
            // ⌘⇧C → 特殊コピー
            // assumeIsolated: メインスレッド上なので安全。Task より同期的で確実。
            if keyCode == GlobalShortcutManager.kVK_C {
                MainActor.assumeIsolated { self.performSpecialCopy() }
                return nil  // イベント消費
            }
            // ⌘⇧V → ペーストUI表示
            if keyCode == GlobalShortcutManager.kVK_V {
                MainActor.assumeIsolated { self.onShowPasteUI?() }
                return nil  // イベント消費
            }
            return event
        }

        // ⌘V → ペースト音（イベント自体は通常通り伝播）
        if keyCode == GlobalShortcutManager.kVK_V {
            MainActor.assumeIsolated { SoundManager.shared.playPaste() }
            return event
        }

        return event
    }

    // MARK: - 特殊コピー処理（@MainActor）

    private func performSpecialCopy() {
        let pasteboard  = NSPasteboard.general
        let snapshot    = PasteboardSnapshot(pasteboard: pasteboard)
        let countBefore = pasteboard.changeCount

        // 仮想 ⌘C を送信してアクティブアプリにテキストをコピーさせる
        postSyntheticCmd(keyCode: GlobalShortcutManager.kVK_C)

        // クリップボードが更新されるまで 180ms 待ってから読み取る
        // Task.sleep はキャンセルで即時完了するリスクがあるため
        // 実績ある DispatchQueue.main.asyncAfter を使用
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            // asyncAfter はメインスレッドで実行される → assumeIsolated で安全
            MainActor.assumeIsolated {
                guard let self else { return }

                let pb     = NSPasteboard.general
                let copied = pb.string(forType: .string)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // クリップボードを元に戻す（成否に関わらず必ず実行）
                defer {
                    ClipboardWatcher.shared.ignoreNextOwnWrite()
                    snapshot.restore(to: pb)
                }

                guard
                    pb.changeCount != countBefore,
                    let copied,
                    !copied.isEmpty
                else { return }

                self.onSpecialCopy?(copied)
                SoundManager.shared.playSpecialCopy()
            }
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

/// クリップボード内容を丸ごとスナップショット化して復元するユーティリティ
/// Sendable: 非同期クロージャ境界を越えて安全に渡せる値型
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
