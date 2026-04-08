// GlobalShortcutManager.swift
// CGEventTap を使ってアプリが裏にいてもグローバルショートカットを検知する
// アクセシビリティ権限 (Accessibility) が必須

import AppKit

final class GlobalShortcutManager {

    // MARK: - Callbacks

    /// ⌘+Shift+C で取得できたテキストを渡すコールバック
    var onSpecialCopy: ((String) -> Void)?

    /// ⌘+Shift+V でペーストUIの表示を要求するコールバック
    var onShowPasteUI: (() -> Void)?

    // MARK: - Private

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Virtual key codes (macOS 標準)
    private static let kVK_C: Int64 = 0x08
    private static let kVK_V: Int64 = 0x09
    private static let syntheticEventTag: Int64 = 0x434F504954

    // MARK: - Start / Stop

    func start() {
        guard AXIsProcessTrusted() else {
            print("[Copit] CGEventTap を作成できません: アクセシビリティ権限が付与されていません。")
            return
        }

        let eventMask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        // self を C コールバックの userInfo として渡す (unretained: AppDelegate が保持するため安全)
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        // NOTE: CGEventTapCallBack は @convention(c) のため self をキャプチャ不可
        //       userInfo 経由で self を取得する
        let callback: CGEventTapCallBack = { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let mgr = Unmanaged<GlobalShortcutManager>.fromOpaque(refcon).takeUnretainedValue()
            return mgr.handleEvent(proxy: proxy, type: type, event: event)
        }

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,        // セッション全体を監視
            place: .headInsertEventTap,      // イベントチェーンの先頭に挿入
            options: .defaultTap,            // イベントを消費可能
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: selfPtr
        )

        guard let tap else {
            print("[Copit] CGEventTap の作成に失敗しました。アクセシビリティ権限を確認してください。")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("[Copit] グローバルショートカットを登録しました (⌘⇧C / ⌘⇧V)")
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

    // MARK: - Event Handling

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {

        // タイムアウトや無効化でタップが止まった場合に再有効化
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let flags   = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let userData = event.getIntegerValueField(.eventSourceUserData)

        let hasCmd   = flags.contains(.maskCommand)
        let hasShift = flags.contains(.maskShift)
        let hasAlt   = flags.contains(.maskAlternate)
        let hasCtrl  = flags.contains(.maskControl)

        // 自前で合成したキーは通常のショートカット判定から除外する
        if userData == Self.syntheticEventTag {
            return Unmanaged.passUnretained(event)
        }

        guard hasCmd, !hasAlt, !hasCtrl else {
            return Unmanaged.passUnretained(event)
        }

        if hasShift {
            // ─────────────────────────────────────────
            // ⌘ + Shift + C → 特殊コピー
            // ─────────────────────────────────────────
            if keyCode == Self.kVK_C {
                DispatchQueue.main.async { [weak self] in
                    self?.performSpecialCopy()
                }
                return nil
            }

            // ─────────────────────────────────────────
            // ⌘ + Shift + V → ペーストUI表示
            // ─────────────────────────────────────────
            if keyCode == Self.kVK_V {
                DispatchQueue.main.async { [weak self] in
                    self?.onShowPasteUI?()
                }
                return nil
            }

            return Unmanaged.passUnretained(event)
        }

        if keyCode == Self.kVK_C {
            return Unmanaged.passUnretained(event)
        }

        if keyCode == Self.kVK_V {
            DispatchQueue.main.async {
                SoundManager.shared.playPaste()
            }
            return Unmanaged.passUnretained(event)
        }

        return Unmanaged.passUnretained(event)
    }

    private func performSpecialCopy() {
        let pasteboard = NSPasteboard.general
        let previousSnapshot = PasteboardSnapshot(pasteboard: pasteboard)
        let previousChangeCount = pasteboard.changeCount

        postCommandKey(keyCode: CGKeyCode(Self.kVK_C))

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self else { return }

            let copiedText = pasteboard.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            defer {
                ClipboardWatcher.shared.ignoreNextOwnWrite()
                previousSnapshot.restore(to: pasteboard)
            }

            guard
                pasteboard.changeCount != previousChangeCount,
                let copiedText,
                !copiedText.isEmpty
            else {
                return
            }

            self.onSpecialCopy?(copiedText)
            SoundManager.shared.playSpecialCopy()
        }
    }

    private func postCommandKey(keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
        keyUp?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

private struct PasteboardSnapshot {
    private let contents: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        contents = pasteboard.pasteboardItems?.map { item in
            var snapshot: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    snapshot[type] = data
                }
            }
            return snapshot
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        guard !contents.isEmpty else { return }

        let items = contents.map { snapshot -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in snapshot {
                item.setData(data, forType: type)
            }
            return item
        }

        pasteboard.writeObjects(items)
    }
}
