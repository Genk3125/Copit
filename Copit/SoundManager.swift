// SoundManager.swift
// コピット専用のサウンドエフェクト管理

import AppKit

final class SoundManager {

    static let shared = SoundManager()
    private init() {}

    // macOS 標準サウンド。差し替えるならこの定数だけ変更すればよい。
    private let copySoundName = "Frog"
    private let specialCopySoundName = "Submarine"
    private let pasteSoundName = "Purr"

    // MARK: - Public API

    /// コピーしたときの音
    func playCopy() {
        playSound(named: copySoundName)
    }

    /// 特殊コピーしたときの音
    func playSpecialCopy() {
        playSound(named: specialCopySoundName)
    }

    /// ペーストしたときの音
    func playPaste() {
        playSound(named: pasteSoundName)
    }

    // MARK: - Private

    private func playSound(named name: String) {
        // /System/Library/Sounds/ から直接パスで読み込む
        let path = "/System/Library/Sounds/\(name).aiff"
        guard let sound = NSSound(contentsOfFile: path, byReference: false) else {
            print("[Copit] サウンドが見つかりません: \(path)")
            return
        }
        sound.play()
    }
}
