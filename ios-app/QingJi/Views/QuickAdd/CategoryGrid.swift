import UIKit
import SwiftUI

/// 分类九宫格，按 CategoryRanker 排好的顺序展示。
struct CategoryGrid: View {
    let categories: [TxCategory]
    var childCategories: [TxCategory] = []
    @Binding var selected: TxCategory?
    @State private var expandedParentKey: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        VStack(spacing: 16) {
            GlassEffectContainer(spacing: 12) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(categories) { category in
                        let isSelected = selected?.persistentModelID == category.persistentModelID
                            || selected?.parentKey == category.key
                        let hasChildren = childCategories.contains { $0.parentKey == category.key }
                        Button {
                            withAnimation(.snappy(duration: 0.24)) {
                                selected = category
                                expandedParentKey = hasChildren
                                    ? (expandedParentKey == category.key ? nil : category.key)
                                    : nil
                            }
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    CategoryIcon(
                                        categoryKey: category.key,
                                        emoji: category.emoji,
                                        size: 48
                                    )
                                    if isSelected {
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .stroke(Color.secondary, lineWidth: 2)
                                    }
                                    if hasChildren {
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 8, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 17, height: 17)
                                            .background(Color(uiColor: .systemBackground), in: .circle)
                                            .overlay { Circle().stroke(Color(uiColor: .separator), lineWidth: 0.5) }
                                            .offset(x: 21, y: 21)
                                    }
                                }
                                .frame(width: 48, height: 48)
                                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                Text(category.name)
                                    .font(.caption.weight(isSelected ? .semibold : .regular))
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if expandedParentKey != nil, !activeChildren.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("细分分类")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(selectedParentName ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 4)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
                        ForEach(activeChildren) { category in
                            let isSelected = selected?.persistentModelID == category.persistentModelID
                            Button {
                                withAnimation(.snappy(duration: 0.20)) {
                                    selected = category
                                    expandedParentKey = nil
                                }
                                UISelectionFeedbackGenerator().selectionChanged()
                            } label: {
                                VStack(spacing: 4) {
                                    ZStack {
                                        CategoryIcon(
                                            categoryKey: category.key,
                                            emoji: category.emoji,
                                            size: 40
                                        )
                                        if isSelected {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(Color.accentColor, lineWidth: 1.5)
                                        }
                                    }
                                    .frame(width: 40, height: 40)
                                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    Text(category.name)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }
        }
        .padding(.horizontal, 16)
    }

    private var selectedParentName: String? {
        categories.first(where: { $0.key == expandedParentKey })?.name
    }

    private var activeChildren: [TxCategory] {
        guard let expandedParentKey else { return [] }
        return childCategories.filter { $0.parentKey == expandedParentKey }
    }
}
