import UIKit
import SwiftUI

/// 分类九宫格，按 CategoryRanker 排好的顺序展示。
struct CategoryGrid: View {
    let categories: [TxCategory]
    @Binding var selected: TxCategory?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(categories) { category in
                    let isSelected = selected?.persistentModelID == category.persistentModelID
                    Button {
                        selected = category
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: category.symbol)
                                .font(.system(size: 20))
                                .frame(width: 48, height: 48)
                                .foregroundStyle(isSelected ? .white : .primary)
                                .glassEffect(
                                    isSelected ? .regular.tint(Color.accentColor).interactive() : .regular.interactive(),
                                    in: .circle
                                )
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
        .padding(.horizontal)
    }
}
