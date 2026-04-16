// ClipboardManager.swift
// コピット専用クリップボード履歴管理シングルトン
// Swift 6 / SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor 対応

import Foundation

// MARK: - ClipItem

/// クリップボード履歴の1件分のデータ
/// Sendable: Task/非同期境界を越えて安全に渡せる値型
struct ClipItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let createdAt: Date
    var isFavorite: Bool

    init(text: String, isFavorite: Bool = false) {
        self.id = UUID()
        self.text = text
        self.createdAt = Date()
        self.isFavorite = isFavorite
    }
}

// MARK: - ClipboardManager

/// @MainActor: UI スレッドで @Published を安全に更新するため
@MainActor
final class ClipboardManager: ObservableObject {

    static let shared = ClipboardManager()

    @Published private(set) var items: [ClipItem] = []

    private let maxNonFavorites = 10

    private init() {}

    // MARK: - Public API

    /// テキストを履歴の先頭に追加（重複は先頭へ移動、空白のみは無視）
    func add(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let wasFavorite = items.first(where: { $0.text == trimmed })?.isFavorite ?? false
        items.removeAll { $0.text == trimmed }
        items.insert(ClipItem(text: trimmed, isFavorite: wasFavorite), at: 0)
        trimOverflow()
    }

    /// 全履歴を削除
    func clear() {
        items.removeAll()
    }

    /// 指定IDのアイテムを削除
    func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// お気に入り状態をトグル
    func toggleFavorite(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isFavorite.toggle()
        trimOverflow()
    }

    // MARK: - Private

    private func trimOverflow() {
        let nonFavIdx = items.indices.filter { !items[$0].isFavorite }
        guard nonFavIdx.count > maxNonFavorites else { return }
        let overflow = nonFavIdx.count - maxNonFavorites
        for index in nonFavIdx.suffix(overflow).sorted(by: >) {
            items.remove(at: index)
        }
    }
}
