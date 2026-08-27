import UIKit
import SwiftUI

/// 分类九宫格，按 CategoryRanker 排好的顺序展示。
struct CategoryGrid: View {
    let categories: [TxCategory]
    var childCategories: [TxCategory] = []
    @Binding var selected: TxCategory?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        VStack(spacing: 16) {
            GlassEffectContainer(spacing: 12) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(categories) { category in
                        let isSelected = selected?.persistentModelID == category.persistentModelID
                            || selected?.parentKey == category.key
                        Button {
                            selected = category
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            VStack(spacing: 4) {
                                Text(category.emoji)
                                    .font(.system(size: 25))
                                    .frame(width: 48, height: 48)
                                    .background(
                                        isSelected ? Color.accentColor.opacity(0.84) : Color(.secondarySystemBackground),
                                        in: .circle
                                    )
                                    .overlay {
                                        if isSelected {
                                            Circle().stroke(Color.accentColor, lineWidth: 2)
                                        }
                                    }
                                Text(category.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let selectedParentKey,
               !activeChildren.isEmpty {
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
                                selected = category
                                UISelectionFeedbackGenerator().selectionChanged()
                            } label: {
                                VStack(spacing: 4) {
                                    Text(category.emoji)
                                        .font(.system(size: 21))
                                        .frame(width: 40, height: 40)
                                        .background(
                                            isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground),
                                            in: .circle
                                        )
                                        .overlay {
                                            if isSelected {
                                                Circle().stroke(Color.accentColor, lineWidth: 1.5)
                                            }
                                        }
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
                .background(Color(.secondarySystemBackground).opacity(0.45), in: .rect(cornerRadius: 16))
            }
        }
        .padding(.horizontal, 16)
    }

    private var selectedParentKey: String? {
        selected?.parentKey ?? selected?.key
    }

    private var selectedParentName: String? {
        categories.first(where: { $0.key == selectedParentKey })?.name
    }

    private var activeChildren: [TxCategory] {
        guard let selectedParentKey else { return [] }
        return childCategories.filter { $0.parentKey == selectedParentKey }
    }
}
