// SoundManager.swift
// コピット専用サウンドエフェクト管理
// Swift 6 / SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor 対応

import AppKit

/// @MainActor: NSSound は UI スレッドで使う前提のため
@MainActor
final class SoundManager {

    static let shared = SoundManager()
    private init() {}

    // MARK: - Public API

    func playCopy()        { play("Frog")      }
    func playSpecialCopy() { play("Submarine") }
    func playPaste()       { play("Purr")      }

    // MARK: - Private

    private func play(_ name: String) {
        let path = "/System/Library/Sounds/\(name).aiff"
        guard let sound = NSSound(contentsOfFile: path, byReference: false) else { return }
        sound.play()
    }
}
