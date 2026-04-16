// ClipboardWatcher.swift
// システムクリップボードの changeCount を監視してコピー音を鳴らす
// Swift 6 / SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor 対応

import AppKit
import Foundation

/// @MainActor: NSPasteboard / Timer はメインスレッドで使う前提のため
@MainActor
final class ClipboardWatcher {

    static let shared = ClipboardWatcher()

    private var timer: Timer?
    private var lastChangeCount: Int
    private var ignoredChangeCount: Int?

    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    // MARK: - Public API

    func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount

        // Timer ブロックは @Sendable だが RunLoop.main に追加するためメインスレッドで発火する。
        // assumeIsolated で @MainActor 隔離を明示し、actor 境界警告を解消する。
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Copit 自身の書き込みによる次回の変化音を抑制する
    func ignoreNextOwnWrite() {
        ignoredChangeCount = NSPasteboard.general.changeCount + 1
    }

    // MARK: - Private

    private func poll() {
        let current = NSPasteboard.general.changeCount
        guard current != lastChangeCount else { return }

        let previous = lastChangeCount
        lastChangeCount = current

        if let ignored = ignoredChangeCount, current == ignored {
            ignoredChangeCount = nil
            return
        }

        if current > previous {
            SoundManager.shared.playCopy()
        }
    }
}
