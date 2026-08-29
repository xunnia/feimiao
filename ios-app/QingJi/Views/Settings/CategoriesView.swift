import Foundation
import SwiftUI
import SwiftData
import UIKit
import QingJiCore

/// 分类管理：稳定 key、一级/二级层级、隐藏恢复、合并和删除保护与 Android 对齐。
struct CategoriesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TxCategory.sortOrder)
    private var allCategories: [TxCategory]

    @State private var kind: TransactionKind = .expense
    @State private var expandedKeys: Set<String> = []
    @State private var showEditor = false
    @State private var editorParentKey: String?
    @State private var editingCategory: TxCategory?
    @State private var mergeSource: TxCategory?
    @State private var errorMessage: String?

    private var activeTopLevel: [TxCategory] {
        allCategories
            .filter { $0.kind == kind && !$0.isArchived && $0.parentKey == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var archived: [TxCategory] {
        allCategories
            .filter { $0.kind == kind && $0.isArchived }
            .sorted { $0.sortOrder < $1.sortOrder }
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
                ForEach(activeTopLevel) { category in
                    categoryRow(category)
                    if expandedKeys.contains(category.key) {
                        ForEach(children(of: category)) { child in
                            categoryRow(child, indented: true)
                        }
                        Button {
                            editorParentKey = category.key
                            editingCategory = nil
                            showEditor = true
                        } label: {
                            Label("添加子分类", systemImage: "plus")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 34)
                        }
                    }
                }
            } header: {
                Text("启用分类")
            } footer: {
                Text("隐藏分类不会影响历史账单；稳定分类 key 会在备份和 Android/iOS 之间保持不变。")
            }

            if !archived.isEmpty {
                Section("已隐藏") {
                    ForEach(archived) { category in
                        categoryRow(category, isArchived: true)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .liquidGlassCanvas()
        .navigationTitle("分类管理")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button {
                        kind = .expense
                    } label: {
                        Label("支出分类", systemImage: kind == .expense ? "checkmark" : "minus")
                    }
                    Button {
                        kind = .income
                    } label: {
                        Label("收入分类", systemImage: kind == .income ? "checkmark" : "plus")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("切换收支类型")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorParentKey = nil
                    editingCategory = nil
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新建分类")
            }
        }
        .sheet(isPresented: $showEditor) {
            CategoryEditorSheet(
                kind: kind,
                parentKey: editorParentKey,
                editing: editingCategory,
                nextSortOrder: (allCategories.map(\.sortOrder).max() ?? -1) + 1
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $mergeSource) { source in
            CategoryMergeSheet(
                source: source,
                targets: mergeTargets(for: source)
            ) { target in
                merge(source, into: target)
            }
            .presentationDetents([.medium])
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func categoryRow(_ category: TxCategory, indented: Bool = false, isArchived: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(category.emoji)
                .font(indented ? .body : .title3)
                .frame(width: indented ? 28 : 36, height: indented ? 28 : 36)
                .background(Color.accentColor.opacity(isArchived ? 0.06 : 0.12), in: .circle)
                .opacity(isArchived ? 0.55 : 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(category.name)
                        .font(indented ? .subheadline : .body.weight(.medium))
                    if isArchived {
                        Text("已隐藏")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if !indented {
                    let childCount = children(of: category).count
                    Text(childCount == 0 ? "暂无子分类" : "\(childCount) 个子分类")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)

            if !isArchived && category.parentKey == nil {
                Image(systemName: expandedKeys.contains(category.key) ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Menu {
                if isArchived {
                    Button {
                        restore(category)
                    } label: {
                        Label("恢复显示", systemImage: "eye")
                    }
                } else {
                    Button {
                        editingCategory = category
                        editorParentKey = category.parentKey
                        showEditor = true
                    } label: {
                        Label("重命名", systemImage: "pencil")
                    }
                    Button {
                        editorParentKey = category.key
                        editingCategory = nil
                        showEditor = true
                    } label: {
                        Label("添加子分类", systemImage: "plus")
                    }
                    Button {
                        archive(category)
                    } label: {
                        Label("隐藏", systemImage: "eye.slash")
                    }
                    if !mergeTargets(for: category).isEmpty {
                        Button {
                            mergeSource = category
                        } label: {
                            Label("合并到…", systemImage: "arrow.triangle.merge")
                        }
                    }
                    Button(role: .destructive) {
                        deleteWithProtection(category)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 36)
                    .contentShape(Rectangle())
            }
            .menuOrder(.fixed)
        }
        .padding(.leading, indented ? 28 : 0)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isArchived && category.parentKey == nil {
                withAnimation(.snappy) {
                    if expandedKeys.contains(category.key) {
                        expandedKeys.remove(category.key)
                    } else {
                        expandedKeys.insert(category.key)
                    }
                }
            } else if isArchived {
                restore(category)
            } else {
                editingCategory = category
                editorParentKey = category.parentKey
                showEditor = true
            }
        }
        .foregroundStyle(isArchived ? .secondary : .primary)
    }

    private func children(of category: TxCategory) -> [TxCategory] {
        allCategories
            .filter { $0.parentKey == category.key && $0.kind == category.kind && !$0.isArchived }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func archive(_ category: TxCategory) {
        category.isArchived = true
        category.updatedAt = Date()
        for child in allCategories where child.parentKey == category.key {
            child.isArchived = true
            child.updatedAt = Date()
        }
        saveContext()
    }

    private func restore(_ category: TxCategory) {
        category.isArchived = false
        category.updatedAt = Date()
        if let parentKey = category.parentKey,
           let parent = allCategories.first(where: { $0.key == parentKey }) {
            parent.isArchived = false
            parent.updatedAt = Date()
        }
        saveContext()
    }

    private func deleteWithProtection(_ category: TxCategory) {
        let transactions = (try? context.fetch(FetchDescriptor<MoneyTransaction>())) ?? []
        let count = transactions.filter { $0.category?.key == category.key }.count
        if count > 0 {
            archive(category)
            return
        }
        for child in allCategories where child.parentKey == category.key {
            if transactions.contains(where: { $0.category?.key == child.key }) {
                archive(category)
                return
            }
        }
        for child in allCategories where child.parentKey == category.key {
            context.delete(child)
        }
        context.delete(category)
        saveContext()
    }

    private func mergeTargets(for source: TxCategory) -> [TxCategory] {
        let descendantKeys = Set(allCategories.filter { $0.parentKey == source.key }.map(\.key))
        return allCategories
            .filter {
                $0.kind == source.kind && !$0.isArchived &&
                $0.key != source.key && !descendantKeys.contains($0.key)
            }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func merge(_ source: TxCategory, into target: TxCategory) {
        let transactions = (try? context.fetch(FetchDescriptor<MoneyTransaction>())) ?? []
        for transaction in transactions where transaction.category?.key == source.key {
            transaction.category = target
            transaction.updatedAt = Date()
        }
        for child in allCategories where child.parentKey == source.key {
            child.parentKey = target.key
            child.updatedAt = Date()
        }
        context.delete(source)
        saveContext()
    }

    private func saveContext() {
        do {
            try context.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CategoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let kind: TransactionKind
    let parentKey: String?
    let editing: TxCategory?
    let nextSortOrder: Int
    @State private var name: String
    @State private var symbol: String
    @State private var emoji: String
    @State private var errorMessage: String?

    private static let symbolChoices = [
        ("tag", "🏷️"), ("fork.knife", "🍽️"), ("cart", "🛒"), ("bus", "🚌"),
        ("bag", "🛍️"), ("gamecontroller", "🎮"), ("house", "🏠"), ("bolt", "⚡"),
        ("cross.case", "🏥"), ("book", "📚"), ("airplane", "✈️"), ("pawprint", "🐾"),
        ("gift", "🎁"), ("cup.and.saucer", "☕"), ("tshirt", "👕"), ("fuelpump", "⛽"),
        ("music.note", "🎵"), ("phone", "📱"), ("wifi", "📶"), ("banknote", "💴"),
    ]

    init(kind: TransactionKind, parentKey: String?, editing: TxCategory?, nextSortOrder: Int) {
        self.kind = kind
        self.parentKey = parentKey
        self.editing = editing
        self.nextSortOrder = nextSortOrder
        _name = State(initialValue: editing?.name ?? "")
        _symbol = State(initialValue: editing?.symbol ?? "tag")
        _emoji = State(initialValue: editing?.emoji ?? "🏷️")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("分类名称", text: $name)
                } header: {
                    Text(editing == nil ? (parentKey == nil ? "新建一级分类" : "新建子分类") : "重命名分类")
                }

                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                        ForEach(Self.symbolChoices, id: \.0) { choice in
                            Button {
                                symbol = choice.0
                                emoji = choice.1
                            } label: {
                                VStack(spacing: 4) {
                                    Text(choice.1)
                                        .font(.title2)
                                    Image(systemName: choice.0)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(
                                    symbol == choice.0 ? Color.accentColor.opacity(0.15) : Color.clear,
                                    in: .rect(cornerRadius: 10)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "新建分类" : "重命名")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "创建" : "保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        if let editing {
            editing.name = cleanName
            editing.symbol = symbol
            editing.emoji = emoji
            editing.updatedAt = Date()
        } else {
            context.insert(TxCategory(
                key: "custom_\(UUID().uuidString)",
                name: cleanName,
                symbol: symbol,
                kind: kind,
                sortOrder: nextSortOrder,
                emoji: emoji,
                parentKey: parentKey
            ))
        }
        do {
            try context.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CategoryMergeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let source: TxCategory
    let targets: [TxCategory]
    let onMerge: (TxCategory) -> Void
    @State private var targetKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("来源", value: source.name)
                    Picker("目标", selection: $targetKey) {
                        Text("请选择").tag("")
                        ForEach(targets) { target in
                            Text(target.name).tag(target.key)
                        }
                    }
                } footer: {
                    Text("历史账单会改挂到目标分类，此操作不可撤销。")
                }
            }
            .navigationTitle("合并分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("合并") {
                        guard let target = targets.first(where: { $0.key == targetKey }) else { return }
                        onMerge(target)
                        dismiss()
                    }
                    .disabled(targetKey.isEmpty)
                }
            }
            .onAppear {
                targetKey = targets.first?.key ?? ""
            }
        }
    }
}
