// CopitViewModel.swift
// ペーストUIのリスト状態を管理する ObservableObject
// Swift 6 / SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor 対応

import Foundation

/// @MainActor: @Published プロパティを UI スレッドで安全に更新するため
@MainActor
final class CopitViewModel: ObservableObject {

    // MARK: - Published State

    @Published var items: [ClipItem] = []
    @Published var selectedIndex: Int = 0

    // MARK: - Computed

    var selectedItem: ClipItem? {
        guard !items.isEmpty, items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    // MARK: - Navigation

    /// Space / ↓: 選択を1つ下へ（末尾→先頭ループ）
    func moveDown() {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % items.count
    }

    /// ↑: 選択を1つ上へ（先頭→末尾ループ）
    func moveUp() {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + items.count) % items.count
    }

    /// 選択中アイテムを除去して ID を返す
    func removeSelectedItem() -> UUID? {
        guard let item = selectedItem else { return nil }
        items.removeAll { $0.id == item.id }
        clampSelection()
        return item.id
    }

    /// 選択中アイテムのお気に入りをトグルして ID を返す
    func toggleFavoriteForSelectedItem() -> UUID? {
        guard
            let item = selectedItem,
            let index = items.firstIndex(where: { $0.id == item.id })
        else { return nil }
        items[index].isFavorite.toggle()
        return item.id
    }

    // MARK: - Sync

    /// ClipboardManager の最新データを反映（選択位置を可能な限り維持）
    func load(from clipItems: [ClipItem]) {
        let prevID = selectedItem?.id
        items = clipItems
        if let prevID, let newIndex = items.firstIndex(where: { $0.id == prevID }) {
            selectedIndex = newIndex
        } else {
            clampSelection()
        }
    }

    // MARK: - Private

    private func clampSelection() {
        selectedIndex = items.isEmpty ? 0 : min(selectedIndex, items.count - 1)
    }
}
