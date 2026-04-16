// CopitListView.swift
// ペーストUIのSwiftUIビュー
// IME変換候補ウィンドウ風のシンプルなリスト
// Swift 6 / SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor 対応

import SwiftUI

// MARK: - CopitListView

struct CopitListView: View {

    @ObservedObject var viewModel: CopitViewModel

    let onPaste: () -> Void
    let onHide:  () -> Void
    let onDeleteSelected: () -> Void
    let onToggleFavoriteSelected: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // すりガラス背景
            VisualEffectBackground()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 8)

            VStack(spacing: 0) {
                header
                Divider().opacity(0.3)
                if viewModel.items.isEmpty {
                    emptyState
                } else {
                    listContent
                }
                Divider().opacity(0.3)
                footer
            }
        }
        .frame(width: 360)
        .frame(maxHeight: 250)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(12)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Text("コピット")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Spacer()
            Text("⌘⇧V")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.5))
            Text("履歴がありません")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Text("⌘ + Shift + C でテキストをコピーしてください")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - List

    private var listContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.items.indices, id: \.self) { index in
                        CopitItemRow(
                            item: viewModel.items[index],
                            index: index,
                            isSelected: index == viewModel.selectedIndex,
                            onToggleFavorite: {
                                viewModel.selectedIndex = index
                                onToggleFavoriteSelected()
                            }
                        )
                        .id(index)
                        .onTapGesture {
                            viewModel.selectedIndex = index
                            onPaste()
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 160)
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                withAnimation(.easeInOut(duration: 0.1)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            HintLabel(key: "Space/↑↓", desc: "移動")
            HintLabel(key: "Enter",    desc: "ペースト")
            HintLabel(key: "F",        desc: "星")
            HintLabel(key: "Del/X",    desc: "削除")
            HintLabel(key: "Esc",      desc: "閉じる")
            Spacer()
            Text("\(viewModel.items.filter { !$0.isFavorite }.count)/10")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }
}

// MARK: - CopitItemRow

struct CopitItemRow: View {

    private let maxPreviewChars = 22

    let item: ClipItem
    let index: Int
    let isSelected: Bool
    let onToggleFavorite: () -> Void

    private var displayText: String {
        let single = item.text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return single.count > maxPreviewChars
            ? String(single.prefix(maxPreviewChars)) + "..."
            : single
    }

    private var isMultiLine: Bool {
        item.text.components(separatedBy: .newlines).count > 1
    }

    var body: some View {
        HStack(spacing: 8) {
            // インデックスバッジ
            Text(index < 9 ? "\(index + 1)" : "•")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(isSelected ? .white.opacity(0.75) : .secondary.opacity(0.5))
                .frame(width: 16)

            // テキストプレビュー
            Text(displayText)
                .font(.system(size: 13))
                .foregroundColor(isSelected ? .white : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 複数行インジケーター
            if isMultiLine {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 9))
                    .foregroundColor(isSelected ? .white.opacity(0.6) : .secondary.opacity(0.4))
            }

            // お気に入りボタン
            Button(action: onToggleFavorite) {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(starColor)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.accentColor)
        } else {
            Color.clear
        }
    }

    private var starColor: Color {
        if item.isFavorite {
            return isSelected ? .white : Color.yellow.opacity(0.95)
        }
        return isSelected ? .white.opacity(0.72) : .secondary.opacity(0.42)
    }
}

// MARK: - VisualEffectBackground

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state        = .active
        v.material     = .hudWindow
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - HintLabel

struct HintLabel: View {
    let key:  String
    let desc: String

    var body: some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                )
                .foregroundColor(.secondary)
            Text(desc)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Preview

#Preview {
    let vm = CopitViewModel()
    vm.items = [
        ClipItem(text: "Hello, World!"),
        ClipItem(text: "SwiftUI で macOS アプリ開発", isFavorite: true),
        ClipItem(text: "Lorem ipsum dolor sit amet consectetur\nadipiscing elit"),
        ClipItem(text: "第四の文字列サンプルテキスト"),
        ClipItem(text: "Another clipboard entry for testing"),
    ]
    vm.selectedIndex = 0

    return CopitListView(
        viewModel: vm,
        onPaste: {},
        onHide: {},
        onDeleteSelected: {},
        onToggleFavoriteSelected: {}
    )
    .frame(width: 440, height: 420)
}
