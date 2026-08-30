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
    @State private var showIconStyle = false

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
                .liquidGlassCircleControl()
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
                .liquidGlassCircleControl()
                .accessibilityLabel("新建分类")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showIconStyle = true
                } label: {
                    Image(systemName: "paintpalette")
                }
                .liquidGlassCircleControl()
                .accessibilityLabel("图标样式")
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
        .sheet(isPresented: $showIconStyle) {
            CategoryIconStyleSheet()
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
            CategoryIcon(
                categoryKey: category.key,
                emoji: category.emoji,
                size: indented ? 28 : 36
            )
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
    @State private var errorMessage: String?

    init(kind: TransactionKind, parentKey: String?, editing: TxCategory?, nextSortOrder: Int) {
        self.kind = kind
        self.parentKey = parentKey
        self.editing = editing
        self.nextSortOrder = nextSortOrder
        _name = State(initialValue: editing?.name ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("分类名称", text: $name)
                } header: {
                    Text(editing == nil ? (parentKey == nil ? "新建一级分类" : "新建子分类") : "重命名分类")
                }

                Section {
                    Text("自建分类沿用 Android 同款 🏷️ 兜底图标；内置分类可在分类管理页切换面性或线性图标。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(editing == nil ? "新建分类" : "重命名")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "创建" : "保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
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
            editing.updatedAt = Date()
        } else {
            context.insert(TxCategory(
                key: "custom_\(UUID().uuidString)",
                name: cleanName,
                symbol: "tag",
                kind: kind,
                sortOrder: nextSortOrder,
                emoji: "🏷️",
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
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("合并") {
                        guard let target = targets.first(where: { $0.key == targetKey }) else { return }
                        onMerge(target)
                        dismiss()
                    }
                    .disabled(targetKey.isEmpty)
                    .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
            }
            .onAppear {
                targetKey = targets.first?.key ?? ""
            }
        }
    }
}

private struct CategoryIconStyleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRaw: String

    private let previewKeys = [
        "dining", "shopping", "transport", "car",
        "housing", "medical", "salary", "other",
    ]

    init() {
        _selectedRaw = State(
            initialValue: UserDefaults.standard.string(forKey: "qingji.categoryIconStyle")
                ?? CategoryIconStyle.filled.rawValue
        )
    }

    private var selectedStyle: CategoryIconStyle {
        CategoryIconStyle(rawValue: selectedRaw) ?? .filled
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Picker("风格", selection: $selectedRaw) {
                    ForEach(CategoryIconStyle.allCases) { style in
                        Text(style.title).tag(style.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Text("与 Android 共用同一套分类图标；面性和线性只改变图形笔画，不改变分类颜色和 key。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
                    ForEach(previewKeys, id: \.self) { key in
                        CategoryIcon(
                            categoryKey: key,
                            emoji: CategorySeed.emojiOf(key),
                            size: 42,
                            style: selectedStyle
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
            .padding(20)
            .liquidGlassCanvas()
            .navigationTitle("图标样式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        UserDefaults.standard.set(selectedRaw, forKey: "qingji.categoryIconStyle")
                        dismiss()
                    }
                    .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
            }
        }
    }
}
