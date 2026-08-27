import SwiftUI
import SwiftData
import UIKit

/// 标签管理：标签不参与收支计算，但必须能完整编辑、删除并维护交易快照。
struct TagsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Tag.sortOrder)
    private var tags: [Tag]
    @Query
    private var transactions: [MoneyTransaction]

    @State private var showAddSheet = false
    @State private var editingTag: Tag?
    @State private var deleteTarget: Tag?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if tags.isEmpty {
                ContentUnavailableView(
                    "还没有标签",
                    systemImage: "tag",
                    description: Text("给交易加上工作、旅行或待核对等标签")
                )
            } else {
                Section {
                    ForEach(tags) { tag in
                        tagRow(tag)
                            .contentShape(Rectangle())
                            .onTapGesture { editingTag = tag }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    editingTag = tag
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                .tint(.accentColor)
                                Button(role: .destructive) {
                                    deleteTarget = tag
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    }
                    .onMove(perform: moveTags)
                } header: {
                    Text("我的标签")
                } footer: {
                    Text("标签只作为账目筛选和备注维度，不会改变统计金额。")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("标签管理")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新建标签")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            TagEditorSheet(
                tag: nil,
                nextSortOrder: (tags.map(\.sortOrder).max() ?? -1) + 1
            )
            .presentationDetents([.medium])
        }
        .sheet(item: $editingTag) { tag in
            TagEditorSheet(tag: tag, nextSortOrder: tag.sortOrder)
                .presentationDetents([.medium])
        }
        .confirmationDialog(
            "删除标签？",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除标签并从账目移除", role: .destructive) {
                if let tag = deleteTarget { delete(tag) }
                deleteTarget = nil
            }
            Button("取消", role: .cancel) { deleteTarget = nil }
        } message: {
            if let tag = deleteTarget {
                Text("“\(tag.name)”被 \(referenceCount(for: tag)) 笔账目使用，账目本身会保留。")
            }
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

    private func tagRow(_ tag: Tag) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(tagColor(tag.colorValue))
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(tag.name)
                    .font(.body.weight(.medium))
                Text("\(referenceCount(for: tag)) 笔账目用到")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }

    private func referenceCount(for tag: Tag) -> Int {
        transactions.filter { $0.tags.contains(tag.name) }.count
    }

    private func moveTags(from source: IndexSet, to destination: Int) {
        var ordered = tags
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, tag) in ordered.enumerated() {
            tag.sortOrder = index
            tag.updatedAt = Date()
        }
        saveContext()
    }

    private func delete(_ tag: Tag) {
        for transaction in transactions where transaction.tags.contains(tag.name) {
            transaction.tags = transaction.tags.filter { $0 != tag.name }
            transaction.updatedAt = Date()
        }
        context.delete(tag)
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

    private func tagColor(_ value: Int) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

private struct TagEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var transactions: [MoneyTransaction]

    let tag: Tag?
    let nextSortOrder: Int
    @State private var name: String
    @State private var colorValue: Int
    @State private var errorMessage: String?

    private let palette = [
        0x7D8B9B, 0xF2B23C, 0xF4A9B8, 0xFF9F68,
        0x7FB069, 0x6FB3D2, 0xB088D9, 0xD94B3D,
    ]

    init(tag: Tag?, nextSortOrder: Int) {
        self.tag = tag
        self.nextSortOrder = nextSortOrder
        _name = State(initialValue: tag?.name ?? "")
        _colorValue = State(initialValue: tag?.colorValue ?? 0x7D8B9B)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("标签名称", text: $name)
                    .onChange(of: name) { _, newValue in
                        if newValue.count > 8 { name = String(newValue.prefix(8)) }
                    }
                Section("颜色") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
                        ForEach(palette, id: \.self) { value in
                            Button {
                                colorValue = value
                            } label: {
                                Circle()
                                    .fill(color(value))
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if colorValue == value {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(tag == nil ? "新建标签" : "编辑标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tag == nil ? "创建" : "保存") { save() }
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
        if let tag {
            let oldName = tag.name
            tag.name = cleanName
            tag.colorValue = colorValue
            tag.updatedAt = Date()
            if oldName != cleanName {
                for transaction in transactions where transaction.tags.contains(oldName) {
                    transaction.tags = transaction.tags.map { $0 == oldName ? cleanName : $0 }
                    transaction.updatedAt = Date()
                }
            }
        } else {
            context.insert(Tag(name: cleanName, colorValue: colorValue, sortOrder: nextSortOrder))
        }
        do {
            try context.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func color(_ value: Int) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
