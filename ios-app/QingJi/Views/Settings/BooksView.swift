import SwiftUI
import SwiftData
import UIKit

/// 账本管理：与 Android 抽屉中的账本列表对应。
struct BooksView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Book.sortOrder)
    private var books: [Book]

    @State private var showAddSheet = false
    @State private var editingBook: Book?
    @State private var bookToDelete: Book?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(books) { book in
                    bookRow(book)
                        .contentShape(Rectangle())
                        .onTapGesture { editingBook = book }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                book.isStarred.toggle()
                                book.updatedAt = Date()
                                saveContext()
                            } label: {
                                Label(book.isStarred ? "取消加星" : "加星", systemImage: book.isStarred ? "star.slash" : "star")
                            }
                            .tint(.orange)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !book.isDefault {
                                Button(role: .destructive) {
                                    bookToDelete = book
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                }
                .onMove(perform: moveBooks)
            } header: {
                Text("我的账本")
            } footer: {
                Text("总账本用于汇总勾选了“计入总账”的账本，不能删除。")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .liquidGlassCanvas()
        .navigationTitle("账本管理")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
                    .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .liquidGlassCircleControl()
                .accessibilityLabel("新建账本")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            BookEditorSheet(
                book: nil,
                nextSortOrder: (books.map(\.sortOrder).max() ?? -1) + 1
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingBook) { book in
            BookEditorSheet(book: book, nextSortOrder: book.sortOrder)
                .presentationDetents([.medium, .large])
        }
        .bookDeleteFlow($bookToDelete)
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func bookRow(_ book: Book) -> some View {
        HStack(spacing: 12) {
            BookCoverView(cover: book.cover, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(book.name)
                        .font(.body.weight(.medium))
                    if book.isDefault {
                        statusLabel("总账本", color: .accentColor)
                    }
                    if book.isStarred {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                HStack(spacing: 5) {
                    if !book.remark.isEmpty {
                        Text(book.remark)
                            .lineLimit(1)
                    }
                    if book.includeInTotal && !book.isDefault {
                        Text(book.remark.isEmpty ? "计入总账" : "· 计入总账")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 3)
    }

    private func statusLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: .capsule)
    }

    private func moveBooks(from source: IndexSet, to destination: Int) {
        var ordered = books
        ordered.move(fromOffsets: source, toOffset: destination)
        if let defaultBook = ordered.first(where: { $0.isDefault }),
           let defaultIndex = ordered.firstIndex(where: { $0.persistentModelID == defaultBook.persistentModelID }),
           defaultIndex != 0 {
            ordered.remove(at: defaultIndex)
            ordered.insert(defaultBook, at: 0)
        }
        for (index, book) in ordered.enumerated() {
            book.sortOrder = index
            book.updatedAt = Date()
        }
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

/// 新建/编辑账本。抽屉底部「新建账本」、账本 ⋯ 菜单「编辑」和账本管理页共用。
struct BookEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let book: Book?
    let nextSortOrder: Int
    @State private var name: String
    @State private var remark: String
    @State private var cover: String
    @State private var isStarred: Bool
    @State private var includeInTotal: Bool
    @State private var errorMessage: String?

    init(book: Book?, nextSortOrder: Int) {
        self.book = book
        self.nextSortOrder = nextSortOrder
        _name = State(initialValue: book?.name ?? "")
        _remark = State(initialValue: book?.remark ?? "")
        _cover = State(initialValue: BookCoverCatalog.key(for: book?.cover ?? ""))
        _isStarred = State(initialValue: book?.isStarred ?? false)
        _includeInTotal = State(initialValue: book?.includeInTotal ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("账本名称", text: $name)
                        .textInputAutocapitalization(.never)
                    TextField("备注（可选）", text: $remark)
                        .onChange(of: remark) { _, newValue in
                            if newValue.count > 20 { remark = String(newValue.prefix(20)) }
                        }
                    Toggle("加星", isOn: $isStarred)
                    if book?.isDefault != true {
                        Toggle("计入总账", isOn: $includeInTotal)
                    }
                }

                Section("封面") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(BookCoverCatalog.choices, id: \.self) { choice in
                                Button {
                                    cover = choice
                                } label: {
                                    VStack(spacing: 5) {
                                        BookCoverView(cover: choice, height: 64)
                                            .overlay(alignment: .topTrailing) {
                                                if cover == choice {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundStyle(.white, Color.accentColor)
                                                        .font(.title3)
                                                        .padding(3)
                                                }
                                            }
                                        Text(BookCoverCatalog.name(choice))
                                            .font(.caption)
                                            .foregroundStyle(.primary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .navigationTitle(book == nil ? "新建账本" : "编辑账本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(book == nil ? "创建" : "保存") { save() }
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
        if let book {
            book.name = cleanName
            book.remark = remark.trimmingCharacters(in: .whitespacesAndNewlines)
            book.cover = BookCoverCatalog.storedValue(for: cover)
            book.isStarred = isStarred
            if !book.isDefault { book.includeInTotal = includeInTotal }
            book.updatedAt = Date()
        } else {
            context.insert(Book(
                name: cleanName,
                cover: BookCoverCatalog.storedValue(for: cover),
                remark: remark.trimmingCharacters(in: .whitespacesAndNewlines),
                sortOrder: nextSortOrder,
                isStarred: isStarred,
                includeInTotal: includeInTotal
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
