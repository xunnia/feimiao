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
        .confirmationDialog(
            "删除账本？",
            isPresented: Binding(
                get: { bookToDelete != nil },
                set: { if !$0 { bookToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除并移到账本总账", role: .destructive) {
                if let book = bookToDelete {
                    delete(book)
                }
                bookToDelete = nil
            }
            Button("取消", role: .cancel) { bookToDelete = nil }
        } message: {
            Text("该账本中的历史账单会保留，并转回总账本。")
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

    private func bookRow(_ book: Book) -> some View {
        HStack(spacing: 12) {
            BookCoverView(cover: book.cover, size: 48)
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

    private func delete(_ book: Book) {
        guard !book.isDefault,
              let fallback = books.first(where: { $0.isDefault })
                ?? books.first(where: { $0.persistentModelID != book.persistentModelID }) else {
            errorMessage = "至少需要保留一个总账本。"
            return
        }
        let transactions = (try? context.fetch(FetchDescriptor<MoneyTransaction>())) ?? []
        for transaction in transactions where transaction.book?.persistentModelID == book.persistentModelID {
            transaction.book = fallback
            transaction.updatedAt = Date()
        }
        context.delete(book)
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

enum BookCoverCatalog {
    static let choices = [
        "daily", "food", "shopping", "travel", "beauty", "business",
        "couple", "multi", "pet", "baby", "family"
    ]

    /// Android backups may store the source asset path while iOS-created
    /// books store the canonical key. Normalize both forms before rendering.
    static func normalized(_ cover: String) -> String {
        let portablePath = cover.replacingOccurrences(of: "\\", with: "/")
        let filename = portablePath.split(separator: "/").last.map(String.init) ?? portablePath
        let stem = filename.split(separator: ".").first.map(String.init) ?? filename
        switch stem {
        case "default": return "daily"
        case "dining": return "food"
        default: return stem
        }
    }

    static func name(_ cover: String) -> String {
        switch normalized(cover) {
        case "daily": return "日常"
        case "food": return "餐饮"
        case "shopping": return "网购"
        case "travel": return "旅行"
        case "beauty": return "美妆"
        case "pet": return "宠物"
        case "baby": return "母婴"
        case "family": return "家庭"
        case "business": return "生意"
        case "couple": return "情侣"
        case "multi": return "多人"
        default: return "默认"
        }
    }

    static func symbol(_ cover: String) -> String {
        switch normalized(cover) {
        case "daily": return "sun.max.fill"
        case "food": return "fork.knife"
        case "shopping": return "bag.fill"
        case "travel": return "airplane"
        case "beauty": return "sparkles"
        case "pet": return "pawprint.fill"
        case "baby": return "figure.and.child.holdinghands"
        case "family": return "house.fill"
        case "business": return "briefcase.fill"
        case "couple": return "heart.fill"
        case "multi": return "person.3.fill"
        default: return "book.closed.fill"
        }
    }

    static func color(_ cover: String) -> Color {
        switch normalized(cover) {
        case "daily": return Color(red: 0.36, green: 0.55, blue: 0.67)
        case "food": return Color(red: 0.78, green: 0.49, blue: 0.35)
        case "shopping": return Color(red: 0.46, green: 0.46, blue: 0.65)
        case "travel": return Color(red: 0.35, green: 0.60, blue: 0.58)
        case "beauty": return Color(red: 0.72, green: 0.48, blue: 0.64)
        case "pet": return Color(red: 0.68, green: 0.55, blue: 0.42)
        case "baby": return Color(red: 0.78, green: 0.56, blue: 0.62)
        case "family": return Color(red: 0.55, green: 0.48, blue: 0.63)
        case "business": return Color(red: 0.30, green: 0.39, blue: 0.50)
        case "couple": return Color(red: 0.75, green: 0.42, blue: 0.48)
        case "multi": return Color(red: 0.48, green: 0.57, blue: 0.50)
        default: return Color.accentColor
        }
    }

    static func assetName(_ cover: String) -> String {
        switch normalized(cover) {
        case "daily": return "BookCover-default"
        case "food": return "BookCover-dining"
        case "shopping": return "BookCover-shopping"
        case "travel": return "BookCover-travel"
        case "beauty": return "BookCover-beauty"
        case "business": return "BookCover-business"
        case "couple": return "BookCover-couple"
        case "multi": return "BookCover-multi"
        case "pet": return "BookCover-pet"
        case "baby": return "BookCover-baby"
        case "family": return "BookCover-family"
        default: return "BookCover-default"
        }
    }
}

struct BookCoverView: View {
    let cover: String
    let size: CGFloat

    var body: some View {
        Image(BookCoverCatalog.assetName(cover))
            .resizable()
            .scaledToFill()
            .frame(width: size * 0.78, height: size)
            .background(BookCoverCatalog.color(cover), in: .rect(cornerRadius: size * 0.14))
            .clipShape(.rect(cornerRadius: size * 0.14))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.14)
                    .stroke(Color.white.opacity(0.26), lineWidth: 0.6)
            }
            .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
            .accessibilityLabel(BookCoverCatalog.name(cover))
    }
}

private struct BookEditorSheet: View {
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
        _cover = State(initialValue: book?.cover ?? "daily")
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
                                        BookCoverView(cover: choice, size: 64)
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
            book.cover = cover
            book.isStarred = isStarred
            if !book.isDefault { book.includeInTotal = includeInTotal }
            book.updatedAt = Date()
        } else {
            context.insert(Book(
                name: cleanName,
                cover: cover,
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
