// ClipboardWatcher.swift
// システムクリップボードの changeCount を監視してコピー音を鳴らす

import AppKit
import Foundation

final class ClipboardWatcher {

    static let shared = ClipboardWatcher()

    private let pasteboard = NSPasteboard.general
    private var timer: Timer?
    private var lastChangeCount: Int
    private var ignoredChangeCount: Int?

    private init() {
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }

        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.pollPasteboard()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Copit 自身の pasteboard 更新による次回 changeCount を無音化する
    func ignoreNextOwnWrite() {
        ignoredChangeCount = pasteboard.changeCount + 1
    }

    private func pollPasteboard() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }

        let previousChangeCount = lastChangeCount
        lastChangeCount = currentChangeCount

        if let ignoredChangeCount, currentChangeCount == ignoredChangeCount {
            self.ignoredChangeCount = nil
            return
        }

        if currentChangeCount > previousChangeCount {
            SoundManager.shared.playCopy()
        }
    }
}
