import AppKit

final class GlobalShortcutManager {

    var onSpecialCopy: ((String) -> Void)?
    var onShowPasteUI: (() -> Void)?

    nonisolated(unsafe) private var eventTap: CFMachPort?
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?

    private static let kVK_C: CGKeyCode = 0x08
    private static let kVK_V: CGKeyCode = 0x09
    nonisolated(unsafe) static let syntheticTag: Int64 = 0x434F504954

    func start() {
        guard AXIsProcessTrusted() else {
            print("[Copit] ⚠️ Accessibility not trusted – shortcuts disabled")
            return
        }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let ptr  = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let cb: CGEventTapCallBack = { _, type, event, refcon -> Unmanaged<CGEvent>? in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let m = Unmanaged<GlobalShortcutManager>.fromOpaque(refcon).takeUnretainedValue()
            if let e = m.handle(type: type, event: event) { return Unmanaged.passUnretained(e) }
            return nil
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: cb, userInfo: ptr
        ) else {
            print("[Copit] ⚠️ CGEvent.tapCreate FAILED – check Sandbox and Accessibility settings")
            return
        }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[Copit] ✅ Event tap created – ⌘⇧C / ⌘⇧V active")
    }

    func stop() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        eventTap = nil; runLoopSource = nil
    }

    nonisolated func handle(type: CGEventType, event: CGEvent) -> CGEvent? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return event
        }
        guard type == .keyDown else { return event }

        let flags = event.flags
        let key   = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        // Skip our own synthetic events
        if event.getIntegerValueField(.eventSourceUserData) == GlobalShortcutManager.syntheticTag {
            return event
        }

        guard flags.contains(.maskCommand),
              !flags.contains(.maskAlternate),
              !flags.contains(.maskControl) else { return event }

        if flags.contains(.maskShift) {
            if key == GlobalShortcutManager.kVK_C {
                MainActor.assumeIsolated { self.performSpecialCopy() }
                return nil
            }
            if key == GlobalShortcutManager.kVK_V {
                MainActor.assumeIsolated { self.onShowPasteUI?() }
                return nil
            }
            return event
        }

        // Normal ⌘V → play paste sound
        if key == GlobalShortcutManager.kVK_V {
            MainActor.assumeIsolated { play("Purr") }
            return event
        }

        return event
    }

    private func performSpecialCopy() {
        print("[Copit] ⌘⇧C detected – starting special copy")
        ClipboardManager.shared.suppressPolling(for: 0.6)

        let pb       = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pb)
        let before   = pb.changeCount

        postCmd(GlobalShortcutManager.kVK_C)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let pb   = NSPasteboard.general
                let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)

                // Restore original clipboard
                snapshot.restore(to: pb)

                guard pb.changeCount != before, let text, !text.isEmpty else {
                    print("[Copit] ⚠️ Special copy: no text captured")
                    return
                }
                self.onSpecialCopy?(text)
                play("Submarine")
                print("[Copit] ✅ Special copy: \"\(text.prefix(40))\"")
            }
        }
    }

    private func postCmd(_ key: CGKeyCode) {
        guard let src = CGEventSource(stateID: .hidSystemState) else {
            print("[Copit] ⚠️ CGEventSource creation failed")
            return
        }
        let dn  = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        let up  = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        let tag = GlobalShortcutManager.syntheticTag
        dn?.flags = .maskCommand; dn?.setIntegerValueField(.eventSourceUserData, value: tag)
        up?.flags = .maskCommand; up?.setIntegerValueField(.eventSourceUserData, value: tag)
        dn?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

private struct PasteboardSnapshot: Sendable {
    private let contents: [[NSPasteboard.PasteboardType: Data]]

    init(_ pb: NSPasteboard) {
        contents = pb.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { t in
                item.data(forType: t).map { (t, $0) }
            })
        } ?? []
    }

    func restore(to pb: NSPasteboard) {
        pb.clearContents()
        guard !contents.isEmpty else { return }
        let items = contents.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (t, d) in dict { item.setData(d, forType: t) }
            return item
        }
        pb.writeObjects(items)
    }
}
