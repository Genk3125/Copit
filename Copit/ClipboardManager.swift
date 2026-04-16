import AppKit

// MARK: - ClipItem

struct ClipItem: Identifiable, Equatable, Sendable {
    let id = UUID()
    let text: String
    var isFavorite = false
}

// MARK: - ClipboardManager

@MainActor
final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published private(set) var items: [ClipItem] = []

    private var timer: Timer?
    private var lastCount: Int
    private var skipCount: Int?

    private init() { lastCount = NSPasteboard.general.changeCount }

    // MARK: 監視

    func startWatching() {
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func ignoreNextWrite() { skipCount = NSPasteboard.general.changeCount + 1 }

    private func poll() {
        let c = NSPasteboard.general.changeCount
        guard c != lastCount else { return }
        let prev = lastCount
        lastCount = c
        if let s = skipCount, c == s { skipCount = nil; return }
        if c > prev { play("Frog") }
    }

    // MARK: 履歴操作

    func add(_ text: String) {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        let fav = items.first { $0.text == s }?.isFavorite ?? false
        items.removeAll { $0.text == s }
        items.insert(ClipItem(text: s, isFavorite: fav), at: 0)
        trim()
    }

    func clear() { items.removeAll() }
    func remove(_ id: UUID) { items.removeAll { $0.id == id } }

    func toggleFavorite(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].isFavorite.toggle()
        trim()
    }

    private func trim() {
        var count = 0
        items = items.filter { item in
            if item.isFavorite { return true }
            count += 1
            return count <= 10
        }
    }
}

// MARK: - サウンド

func play(_ name: String) {
    NSSound(contentsOfFile: "/System/Library/Sounds/\(name).aiff", byReference: false)?.play()
}
