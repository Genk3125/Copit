import AppKit
import Combine
import SwiftUI

// MARK: - PanelViewModel

@MainActor
final class PanelViewModel: ObservableObject {
    @Published var items: [ClipItem] = []
    @Published var selectedIndex: Int = 0

    var selectedItem: ClipItem? {
        guard items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    func moveDown() {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % items.count
    }

    func moveUp() {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + items.count) % items.count
    }

    func removeSelected() -> UUID? {
        guard let item = selectedItem else { return nil }
        items.removeAll { $0.id == item.id }
        selectedIndex = items.isEmpty ? 0 : min(selectedIndex, items.count - 1)
        return item.id
    }

    func toggleFavoriteSelected() -> UUID? {
        guard let item = selectedItem,
              let i = items.firstIndex(where: { $0.id == item.id }) else { return nil }
        items[i].isFavorite.toggle()
        return item.id
    }

    func sync(from source: [ClipItem]) {
        let prevID = selectedItem?.id
        items = source
        if let prevID, let i = items.firstIndex(where: { $0.id == prevID }) {
            selectedIndex = i
        } else {
            selectedIndex = items.isEmpty ? 0 : min(selectedIndex, items.count - 1)
        }
    }
}

// MARK: - FloatingPanel

final class FloatingPanel: NSPanel {
    override var canBecomeKey:  Bool { true  }
    override var canBecomeMain: Bool { false }
}

// MARK: - PanelController

@MainActor
final class PanelController {

    let vm = PanelViewModel()

    private var panel: FloatingPanel?
    private var previousApp: NSRunningApplication?
    private var localMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    private let W: CGFloat = 384
    private let H: CGFloat = 274

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        vm.sync(from: ClipboardManager.shared.items)

        if panel == nil { buildPanel() }
        positionPanel()

        panel?.alphaValue = 0
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { ctx in
            MainActor.assumeIsolated {
                ctx.duration = 0.12
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.panel?.animator().alphaValue = 1
            }
        }

        if localMonitor == nil { startKeys() }

        if resignObserver == nil, let panel {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
            ) { [weak self] _ in self?.hide() }
        }
    }

    func hide() {
        stopKeys()
        if let obs = resignObserver {
            NotificationCenter.default.removeObserver(obs)
            resignObserver = nil
        }
        NSAnimationContext.runAnimationGroup { ctx in
            MainActor.assumeIsolated {
                ctx.duration = 0.08
                self.panel?.animator().alphaValue = 0
            }
        } completionHandler: {
            MainActor.assumeIsolated {
                self.panel?.orderOut(nil)
                self.panel?.alphaValue = 1
            }
        }
    }

    func paste() {
        guard let text = vm.selectedItem?.text else { return }
        ClipboardManager.shared.suppressPolling(for: 0.5)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        hide()
        play("Purr")
        let target = previousApp
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            target?.activate()
            try? await Task.sleep(for: .milliseconds(80))
            self.postCmdV()
        }
    }

    private func postCmdV() {
        let src  = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 0x09
        let dn   = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        let tag  = GlobalShortcutManager.syntheticTag
        dn?.flags = .maskCommand; dn?.setIntegerValueField(.eventSourceUserData, value: tag)
        up?.flags = .maskCommand; up?.setIntegerValueField(.eventSourceUserData, value: tag)
        dn?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func startKeys() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.handleKey(e)
        }
    }

    private func stopKeys() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let noMod = event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
        switch event.keyCode {
        case 49, 125:        vm.moveDown();      return nil
        case 126:            vm.moveUp();        return nil
        case 36, 76:         paste();            return nil
        case 53:             hide();             return nil
        case 51, 117:        deleteSelected();   return nil
        case 7  where noMod: deleteSelected();   return nil
        case 3  where noMod: toggleFav();        return nil
        default:             return event
        }
    }

    private func deleteSelected() {
        guard let id = vm.removeSelected() else { return }
        ClipboardManager.shared.remove(id)
        if ClipboardManager.shared.items.isEmpty { hide() }
        else { vm.sync(from: ClipboardManager.shared.items) }
    }

    private func toggleFav() {
        guard let id = vm.toggleFavoriteSelected() else { return }
        ClipboardManager.shared.toggleFavorite(id)
        vm.sync(from: ClipboardManager.shared.items)
    }

    private func buildPanel() {
        let p = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: W, height: H),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.isReleasedWhenClosed = false
        p.level              = .floating
        p.backgroundColor    = .clear
        p.isOpaque           = false
        p.hasShadow          = false
        p.animationBehavior  = .utilityWindow
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = CopitListView(
            viewModel: vm,
            onPaste:                  { [weak self] in self?.paste() },
            onDeleteSelected:         { [weak self] in self?.deleteSelected() },
            onToggleFavoriteSelected: { [weak self] in self?.toggleFav() }
        )
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: W, height: H)
        p.contentView = host
        panel = p
    }

    private func positionPanel() {
        guard let panel else { return }
        let mouse  = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let sf = screen?.visibleFrame else { return }
        var x = mouse.x - W / 2
        var y = mouse.y + 20
        x = max(sf.minX + 10, min(x, sf.maxX - W - 10))
        y = max(sf.minY + 10, min(y, sf.maxY - H - 10))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
