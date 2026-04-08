// ClipboardManager.swift
// コピット専用のクリップボード履歴を管理するシングルトン
// 通常の NSPasteboard 履歴とは完全に独立して動作する

import Foundation
import Combine

// MARK: - ClipItem

/// コピットの履歴アイテム
struct ClipItem: Identifiable, Equatable {
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

final class ClipboardManager: ObservableObject {

    static let shared = ClipboardManager()

    // 最新のアイテムが先頭に来るリスト
    @Published private(set) var items: [ClipItem] = []

    private let maxItems = 10  // 通常履歴として保持する最大件数

    private init() {}

    // MARK: - Public API

    /// テキストを履歴の先頭に追加する
    /// - 重複テキストが存在する場合は既存を削除して先頭に移動
    /// - 空白のみのテキストは無視
    func add(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let existingFavorite = items.first { $0.text == trimmed }?.isFavorite ?? false

        // 重複を除去（同一テキストを先頭に移動する挙動）
        items.removeAll { $0.text == trimmed }

        // 先頭に追加（最新が上）
        items.insert(ClipItem(text: trimmed, isFavorite: existingFavorite), at: 0)

        trimNonFavoriteItems()
    }

    /// 全履歴を削除
    func clear() {
        items.removeAll()
    }

    /// 特定のアイテムを削除
    func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// お気に入り状態を切り替える
    func toggleFavorite(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isFavorite.toggle()
        trimNonFavoriteItems()
    }

    private func trimNonFavoriteItems() {
        let nonFavoriteIndices = items.indices.filter { !items[$0].isFavorite }
        guard nonFavoriteIndices.count > maxItems else { return }

        let overflow = nonFavoriteIndices.count - maxItems
        let indicesToRemove = Array(nonFavoriteIndices.suffix(overflow)).sorted(by: >)
        for index in indicesToRemove {
            items.remove(at: index)
        }
    }
}
