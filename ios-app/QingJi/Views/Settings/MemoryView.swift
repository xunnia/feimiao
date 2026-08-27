import SwiftUI
import QingJiCore

/// 管理“喵学到的分类”。只删除学习映射，不改历史流水。
struct MemoryView: View {
    @State private var items = CategoryMemoryStore.all()

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "还没学到东西",
                    systemImage: "brain.head.profile",
                    description: Text("在账单里改一次分类，喵就会记住决定性商户")
                )
            } else {
                List {
                    Section {
                        Text("你纠正过的分类会优先用于下一次 AI 记账；删掉只影响以后，不会改历史账单。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Section("已学习") {
                        ForEach(items) { item in
                            let category = CategorySeed.byKey(item.categoryKey)
                            HStack(spacing: 12) {
                                Text(category?.emoji ?? "🏷️")
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.merchant)
                                        .font(.body.weight(.medium))
                                    Text("→ \(category?.nameZh ?? item.categoryKey) · \(item.kind == .income ? "收入" : "支出")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    CategoryMemoryStore.forget(merchant: item.merchant, kind: item.kind)
                                    items = CategoryMemoryStore.all()
                                } label: {
                                    Label("忘掉", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("喵学到的分类")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { items = CategoryMemoryStore.all() }
    }
}
