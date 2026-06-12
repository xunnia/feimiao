import UIKit
import SwiftUI
import SwiftData
import QingJiCore

struct CategoriesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TxCategory.sortOrder)
    private var allCategories: [TxCategory]

    @State private var kind: TransactionKind = .expense
    @State private var showAddSheet = false

    private var visible: [TxCategory] {
        allCategories.filter { $0.kind == kind && !$0.isArchived }
    }
    private var archived: [TxCategory] {
        allCategories.filter { $0.kind == kind && $0.isArchived }
    }

    var body: some View {
        List {
            Picker("类型", selection: $kind) {
                Text("支出").tag(TransactionKind.expense)
                Text("收入").tag(TransactionKind.income)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            Section {
                ForEach(visible) { category in
                    Label(category.name, systemImage: category.symbol)
                        .swipeActions {
                            // 归档而非删除，避免历史流水丢失分类
                            Button("归档") {
                                category.isArchived = true
                                try? context.save()
                            }
                            .tint(.orange)
                        }
                }
            }

            if !archived.isEmpty {
                Section("已归档") {
                    ForEach(archived) { category in
                        Label(category.name, systemImage: category.symbol)
                            .foregroundStyle(.secondary)
                            .swipeActions {
                                Button("恢复") {
                                    category.isArchived = false
                                    try? context.save()
                                }
                                .tint(.green)
                            }
                    }
                }
            }
        }
        .navigationTitle("分类管理")
        .toolbar {
            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddCategorySheet(kind: kind, nextSortOrder: (allCategories.last?.sortOrder ?? -1) + 1)
                .presentationDetents([.medium])
        }
    }
}

private struct AddCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let kind: TransactionKind
    let nextSortOrder: Int
    @State private var name = ""
    @State private var symbol = "tag"

    private static let symbolChoices = [
        "tag", "fork.knife", "cart", "bus", "bag", "gamecontroller", "house",
        "bolt", "cross.case", "book", "airplane", "pawprint", "gift",
        "cup.and.saucer", "tshirt", "fuelpump", "dumbbell", "music.note",
        "phone", "wifi", "banknote", "star", "envelope", "ellipsis.circle",
    ]

    var body: some View {
        NavigationStack {
            Form {
                TextField("分类名称", text: $name)
                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Self.symbolChoices, id: \.self) { choice in
                            Button {
                                symbol = choice
                            } label: {
                                Image(systemName: choice)
                                    .frame(width: 40, height: 40)
                                    .background(symbol == choice ? Color.accentColor : Color(.secondarySystemBackground))
                                    .foregroundStyle(symbol == choice ? .white : .primary)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("新增分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        context.insert(TxCategory(
                            key: UUID().uuidString,
                            name: name,
                            symbol: symbol,
                            kind: kind,
                            sortOrder: nextSortOrder
                        ))
                        try? context.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
