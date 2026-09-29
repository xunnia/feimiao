import SwiftUI
import SwiftData

/// 主页左侧推开式抽屉（对齐安卓 main.dart 抽屉）：
/// 顶部 Logo → 功能项（可长按拖动排序，折叠时只显示前 5 个）→「我的账本」→
/// 底部「头像 + 昵称」（进设置）和「新建账本」。
struct AppDrawerView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var context
    @Query(sort: \Book.sortOrder) private var books: [Book]

    @AppStorage("qingji.drawerOrder") private var storedOrder = ""
    @AppStorage("qingji.profileNickname") private var profileNickname = ""
    @AppStorage("qingji.profileAvatarPath") private var profileAvatarPath = ""

    @State private var expanded = false
    @State private var editorTarget: BookEditorTarget?
    @State private var bookToDelete: Book?
    @State private var errorMessage: String?

    let isOpen: Bool
    let onClose: () -> Void
    let onNavigate: (DrawerDestination) -> Void

    private var order: [DrawerLayout.Item] { DrawerLayout.order(from: storedOrder) }

    private var visibleItems: [DrawerLayout.Item] {
        expanded ? order : Array(order.prefix(DrawerLayout.collapsedCount))
    }

    private var orderedBooks: [Book] { DrawerLayout.orderedBooks(books) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleItems) { item in
                        functionRow(item)
                    }
                    if order.count > DrawerLayout.collapsedCount {
                        moreRow
                    }

                    Text("我的账本")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 6)

                    ForEach(orderedBooks) { book in
                        bookRow(book)
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)

            bottomBar
        }
        // 抽屉关上后「更多」自动收回，下次打开还是 5 项（同安卓）。
        .onChange(of: isOpen) { _, open in
            if !open { expanded = false }
        }
        // 当前选中的账本被删掉后回到总账本，避免主页筛到一个不存在的账本。
        .onChange(of: books.map(\.stableID)) { _, ids in
            if let selected = router.selectedBookID, !ids.contains(selected) {
                router.selectedBookID = nil
            }
        }
        .sheet(item: $editorTarget) { target in
            switch target {
            case .new:
                BookEditorSheet(book: nil, nextSortOrder: nextSortOrder)
                    .presentationDetents([.medium, .large])
            case .edit(let book):
                BookEditorSheet(book: book, nextSortOrder: book.sortOrder)
                    .presentationDetents([.medium, .large])
            }
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

    // MARK: - 顶部 Logo

    private var header: some View {
        Group {
            if colorScheme == .dark {
                // 深色模式 Logo 图不清楚，改用衬线字标（同安卓）。
                Text("肥喵记账")
                    .font(.system(size: 29, weight: .semibold, design: .serif))
                    .foregroundStyle(.primary)
            } else {
                Image("BrandLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 36)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("肥喵记账")
        .accessibilityAddTraits(.isHeader)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    // MARK: - 功能项

    private func functionRow(_ item: DrawerLayout.Item) -> some View {
        Button {
            onNavigate(destination(for: item))
        } label: {
            rowLabel(symbol: item.symbol, title: item.title)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        // 长按拖到另一项上即可换位置，顺序本机保存（同安卓长按排序）。
        .draggable(item.rawValue) {
            rowLabel(symbol: item.symbol, title: item.title)
                .frame(width: 220)
                .background(.regularMaterial, in: .rect(cornerRadius: 10))
        }
        .dropDestination(for: String.self) { keys, _ in
            guard let key = keys.first, let dragged = DrawerLayout.Item(rawValue: key) else { return false }
            withAnimation(.snappy) {
                storedOrder = DrawerLayout.storedValue(for: DrawerLayout.move(dragged, onto: item, in: order))
            }
            return true
        }
        .accessibilityAction(named: "上移") { shift(item, by: -1) }
        .accessibilityAction(named: "下移") { shift(item, by: 1) }
    }

    private func shift(_ item: DrawerLayout.Item, by delta: Int) {
        let current = order
        guard let index = current.firstIndex(of: item) else { return }
        let target = index + delta
        guard current.indices.contains(target) else { return }
        storedOrder = DrawerLayout.storedValue(for: DrawerLayout.move(item, onto: current[target], in: current))
    }

    private var moreRow: some View {
        Button {
            withAnimation(.snappy(duration: 0.24)) { expanded.toggle() }
        } label: {
            rowLabel(symbol: "ellipsis", title: expanded ? "收起" : "更多", secondaryTitle: true)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .accessibilityHint(expanded ? "只显示常用的 5 项" : "显示全部功能")
    }

    /// 细线图标 + 常规字重文字，行高舒展（安卓：图标 21、文字 15 w400、左右 8/12）。
    private func rowLabel(symbol: String, title: String, secondaryTitle: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3.weight(.regular))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(secondaryTitle ? .secondary : .primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .contentShape(.rect(cornerRadius: 10))
    }

    private func destination(for item: DrawerLayout.Item) -> DrawerDestination {
        switch item {
        case .stats: .statistics
        case .assets: .settingsDestination(.assets)
        case .budget: .settingsDestination(.budget)
        case .savings: .settingsDestination(.savings)
        case .assistant: .assistant
        case .categories: .settingsDestination(.categories)
        case .tags: .settingsDestination(.tags)
        case .importExport: .settingsDestination(.importExport)
        case .reimburse: .settingsDestination(.reimburse)
        case .recurring: .settingsDestination(.recurring)
        case .autorecord: .settingsDestination(.autoRecord)
        }
    }

    // MARK: - 我的账本

    /// 总账本（默认账本）在主页上用 selectedBookID == nil 表示。
    private func isSelected(_ book: Book) -> Bool {
        if let selected = router.selectedBookID { return selected == book.stableID }
        return book.isDefault
    }

    private func bookRow(_ book: Book) -> some View {
        let selected = isSelected(book)
        let deletable = books.count > 1 && !book.isDefault
        let remark = book.remark.trimmingCharacters(in: .whitespacesAndNewlines)

        return HStack(spacing: 0) {
            Button {
                router.selectedBookID = book.isDefault ? nil : book.stableID
                onClose()
            } label: {
                HStack(spacing: 12) {
                    BookCoverView(cover: book.cover, height: 54)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(book.name)
                                .font(.subheadline.weight(selected ? .semibold : .regular))
                                .foregroundStyle(selected ? Color.accentColor : .primary)
                                .lineLimit(1)
                            if book.isStarred {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.warning)
                                    .accessibilityLabel("已加星")
                            }
                        }
                        if !remark.isEmpty {
                            Text(remark)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 12)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityHint("切换到这个账本")

            Menu {
                Button {
                    book.isStarred.toggle()
                    book.updatedAt = Date()
                    save()
                } label: {
                    Label(book.isStarred ? "取消加星" : "加星", systemImage: book.isStarred ? "star.slash" : "star")
                }
                Button {
                    editorTarget = .edit(book)
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                if deletable {
                    Button(role: .destructive) {
                        bookToDelete = book
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            } label: {
                // 视觉是小点点，热区 48×48，避免点偏误切账本。
                Image(systemName: "ellipsis")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(book.name)更多操作")
        }
        .background(
            selected ? selectedCardColor : .clear,
            in: .rect(cornerRadius: 12)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    /// 与安卓 AppColors.selectedCard 同值：浅色白 36%，深色高层表面 46%。
    private var selectedCardColor: Color {
        colorScheme == .dark
            ? Color(uiColor: .systemGray4).opacity(0.46)
            : Color.white.opacity(0.36)
    }

    private var nextSortOrder: Int {
        (books.map(\.sortOrder).max() ?? -1) + 1
    }

    private func save() {
        do {
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 底部：头像 + 昵称（进设置）/ 新建账本

    private var displayName: String {
        let trimmed = profileNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "设置" : trimmed
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                onNavigate(.settings)
            } label: {
                HStack(spacing: 10) {
                    ProfileAvatar(
                        nickname: profileNickname,
                        relativePath: profileAvatarPath,
                        size: 36
                    )
                    Text(displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("设置")
            .accessibilityValue(displayName == "设置" ? "" : displayName)

            Spacer(minLength: 8)

            Button {
                editorTarget = .new
            } label: {
                Label("新建账本", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .liquidGlassPillControl(horizontalPadding: 18)
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

private enum BookEditorTarget: Identifiable {
    case new
    case edit(Book)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let book): book.stableID.uuidString
        }
    }
}
