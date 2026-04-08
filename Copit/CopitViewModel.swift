// CopitViewModel.swift
// ペーストUIのリスト状態を管理する ObservableObject
// SwiftUI の CopitListView がこれを監視して再描画される

import Foundation
import Combine  // @Published に必要

final class CopitViewModel: ObservableObject {

    // MARK: - Published State

    /// 表示するテキスト一覧（ClipboardManager の items から同期）
    @Published var items: [ClipItem] = []

    /// 現在ハイライトされているインデックス
    @Published var selectedIndex: Int = 0

    // MARK: - Computed

    /// 現在選択中のテキスト（Enterで貼り付けるもの）
    var selectedItem: ClipItem? {
        guard !items.isEmpty, items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    // MARK: - Navigation

    /// Space / ↓ キー: 選択を1つ下へ（末尾で先頭へループ）
    func moveDown() {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % items.count
    }

    /// ↑ キー: 選択を1つ上へ（先頭で末尾へループ）
    func moveUp() {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + items.count) % items.count
    }

    func removeSelectedItem() -> UUID? {
        guard let item = selectedItem else { return nil }
        items.removeAll { $0.id == item.id }
        normalizeSelection()
        return item.id
    }

    func toggleFavoriteForSelectedItem() -> UUID? {
        guard let item = selectedItem, let index = items.firstIndex(where: { $0.id == item.id }) else { return nil }
        items[index].isFavorite.toggle()
        return item.id
    }

    // MARK: - Sync

    /// ClipboardManager の最新データをロード
    func load(from clipItems: [ClipItem]) {
        let previousSelectionID = selectedItem?.id
        items = clipItems

        if
            let previousSelectionID,
            let newIndex = items.firstIndex(where: { $0.id == previousSelectionID })
        {
            selectedIndex = newIndex
        } else {
            normalizeSelection()
        }
    }

    private func normalizeSelection() {
        if items.isEmpty {
            selectedIndex = 0
        } else {
            selectedIndex = min(selectedIndex, items.count - 1)
        }
    }
}
