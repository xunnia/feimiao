import UIKit
import SwiftUI
import SwiftData
import PhotosUI
import QingJiCore

/// 核心快记页：打开 App 即是键盘，目标 3 秒记完一笔。
struct QuickAddView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// 全局路由：qingji://ai 深链会把 router.showAISheet 置 true，触发 AI 记账 sheet。
    @Environment(AppRouter.self) private var router

    @Query(filter: #Predicate<TxCategory> { !$0.isArchived }, sort: \TxCategory.sortOrder)
    private var allCategories: [TxCategory]
    @Query(sort: \MoneyTransaction.date, order: .reverse)
    private var transactions: [MoneyTransaction]
    @Query(sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query(sort: \Book.sortOrder)
    private var books: [Book]
    @Query(sort: \Tag.sortOrder)
    private var tags: [Tag]

    @State private var kind: TransactionKind = .expense
    @State private var expression = AmountExpression()
    @State private var selectedCategory: TxCategory?
    @State private var selectedAccountID: UUID?
    @State private var selectedBook: Book?
    @State private var transferTargetID: UUID?
    @State private var date = AppClock.now
    @State private var note = ""
    @State private var showSavedToast = false
    @State private var budgetStatus: BudgetStatus?
    @State private var showMoreDetails = false
    @State private var isReimbursable = false
    @State private var isExcluded = false
    @State private var selectedTagNames: Set<String> = []
    @State private var attachmentPath = ""
    @State private var saveError: String?
    @State private var didApplyLaunchKind = false
    @State private var showDatePicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var attachmentError: String?

    private var visibleCategories: [TxCategory] {
        // 当前 Android 手动记账首屏只显示一级分类；二级分类点父级后展开。
        let matching = allCategories.filter {
            $0.kind == kind && !$0.isArchived && $0.parentKey == nil
        }
        // Android groups every transaction's category into its top-level
        // parent, then sorts by descending count and stable seed order.
        var usageCounts: [String: Int] = [:]
        for transaction in transactions where transaction.kind == kind {
            guard let category = transaction.category else { continue }
            usageCounts[category.parentKey ?? category.key, default: 0] += 1
        }
        return matching.sorted {
            let left = usageCounts[$0.key, default: 0]
            let right = usageCounts[$1.key, default: 0]
            return left == right ? $0.sortOrder < $1.sortOrder : left > right
        }
    }

    private var childCategories: [TxCategory] {
        allCategories.filter { $0.kind == kind && !$0.isArchived && $0.parentKey != nil }
    }

    private var usableAccounts: [Account] {
        accounts.filter { !$0.isDeleted && $0.status == .active }
    }

    /// 首次启动种子数据异步写入，account 选择要随查询结果就绪而兜底。
    private var effectiveAccount: Account? {
        usableAccounts.first(where: { $0.stableID == selectedAccountID }) ?? usableAccounts.first
    }

    private var effectiveTransferTarget: Account? {
        usableAccounts.first(where: { $0.stableID == transferTargetID })
    }

    private var currencyCode: String {
        effectiveAccount?.currencyCode ?? "CNY"
    }

    private var effectiveBook: Book? {
        selectedBook
            ?? books.first(where: { $0.stableID == router.selectedBookID })
            ?? books.first
    }

    var body: some View {
        VStack(spacing: 0) {
            manualHeader

            ScrollView(.vertical, showsIndicators: false) {
                if kind == .transfer {
                    transferPickers
                        .frame(minHeight: 174)
                } else {
                    CategoryGrid(
                        categories: visibleCategories,
                        childCategories: childCategories,
                        selected: $selectedCategory
                    )
                }
            }
            .frame(maxHeight: 184)

            chipsRow
                .padding(.top, 8)
            amountNoteCard
                .padding(.top, 8)
            AmountKeypad(
                expression: $expression,
                onSave: saveAndDismiss,
                onSaveAgain: saveAgain,
                saveLabel: "完成"
            )
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
            .background(Color(uiColor: .systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: Binding(
                get: { router.showAISheet },
                set: { router.showAISheet = $0 }
            ), onDismiss: {
                loadBudgetStatus()
                router.clearPendingShare()
            }) {
                AIQuickEntryView(
                    initialText: router.pendingShareText,
                    sharedImageFileName: router.pendingShareImageFileName
                )
            }
            .fullScreenCover(isPresented: Binding(
                get: { router.showChats },
                set: { router.showChats = $0 }
            )) {
                NavigationStack {
                    AIChatsView()
                }
            }
            .sheet(isPresented: $showMoreDetails) {
                QuickAddDetailsSheet(
                    kind: kind,
                    tags: tags,
                    isReimbursable: $isReimbursable,
                    isExcluded: $isExcluded,
                    selectedTagNames: $selectedTagNames,
                    attachmentPath: $attachmentPath
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showDatePicker) {
                ManualDatePickerSheet(date: $date)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showCamera) {
                CameraImagePicker { image in
                    persistImage(image)
                }
                .ignoresSafeArea()
            }
            .alert("无法保存", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .alert("无法添加照片", isPresented: Binding(
                get: { attachmentError != nil },
                set: { if !$0 { attachmentError = nil } }
            )) {
                Button("好") { attachmentError = nil }
            } message: {
                Text(attachmentError ?? "")
            }
            .overlay(alignment: .top) {
                if showSavedToast {
                    Label("已记一笔", systemImage: "checkmark.circle.fill")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular.tint(Color.accentColor.opacity(0.5)), in: .capsule)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onAppear {
                if !didApplyLaunchKind {
                    didApplyLaunchKind = true
                    if router.quickAddStartsWithIncome {
                        kind = .income
                    }
                }
                prepareDefaults()
            }
            .onChange(of: kind) { resetCategorySelection() }
            .onChange(of: accounts.count) {
                if selectedAccountID == nil { selectedAccountID = usableAccounts.first?.stableID }
                if transferTargetID == nil { resetCategorySelection() }
            }
            .onChange(of: allCategories.count) { resetCategorySelection() }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                importPhoto(item)
            }
    }

    private var manualHeader: some View {
        HStack(spacing: 8) {
            Picker("类型", selection: $kind) {
                Text("支出").tag(TransactionKind.expense)
                Text("收入").tag(TransactionKind.income)
                Text("转账").tag(TransactionKind.transfer)
            }
            .pickerStyle(.segmented)
            .frame(width: 190)

            Spacer(minLength: 0)

            Button {
                router.showAISheet = true
            } label: {
                Label("手动记账", systemImage: "pencil")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .liquidGlassPillControl(horizontalPadding: 9, minHeight: 44)
            .tint(.primary)
            .accessibilityLabel("切换到 AI 记账")

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.medium))
            }
            .liquidGlassCircleControl(size: 44)
            .tint(.primary)
            .accessibilityLabel("关闭手动记账")
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                manualChip(title: dateLabel, systemImage: "calendar") {
                    showDatePicker = true
                }
                if books.count > 1 {
                    Menu {
                        ForEach(books) { book in
                            Button(book.name) { selectedBook = book }
                        }
                    } label: {
                        chipLabel(effectiveBook?.name ?? "账本", systemImage: "book.closed")
                    }
                    .buttonStyle(.plain)
                }
                if kind != .transfer {
                    Menu {
                        ForEach(usableAccounts) { account in
                            Button(account.name) { selectedAccountID = account.stableID }
                        }
                    } label: {
                        chipLabel(effectiveAccount?.name ?? "账户", systemImage: "wallet.pass")
                    }
                    .buttonStyle(.plain)
                }
                manualChip(
                    title: selectedTagNames.isEmpty ? "标签" : "\(selectedTagNames.count) 个标签",
                    systemImage: "tag",
                    selected: !selectedTagNames.isEmpty
                ) {
                    showMoreDetails = true
                }
                if kind == .expense {
                    manualChip(title: "待报销", systemImage: "receipt", selected: isReimbursable, warning: true) {
                        isReimbursable.toggle()
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                }
                manualChip(title: "不计入", systemImage: "eye.slash", selected: isExcluded) {
                    isExcluded.toggle()
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 36)
    }

    private var amountNoteCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(currencyCode.uppercased() == "CNY" ? "¥" : MoneyFormat.symbol(of: currencyCode))
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                Text(expression.displayText)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer()
                if expression.isCompound {
                    Text("= \(expression.value.formatted())")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 11)
            .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 16)

            HStack(spacing: 4) {
                TextField("写备注", text: $note)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .submitLabel(.done)
                    .onSubmit(saveAndDismiss)

                if let attachmentImage {
                    Image(uiImage: attachmentImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 30, height: 30)
                        .clipShape(.rect(cornerRadius: 6))
                        .contextMenu {
                            Button("移除照片", role: .destructive) {
                                AttachmentStore.remove(attachmentPath)
                                attachmentPath = ""
                            }
                        }
                } else {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "photo")
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("从相册选择")

                    Button {
                        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                            attachmentError = "当前设备没有可用相机"
                            return
                        }
                        showCamera = true
                    } label: {
                        Image(systemName: "camera")
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("拍照")
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .frame(minHeight: 48)
        }
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(Color(uiColor: .separator).opacity(0.45), lineWidth: 0.6) }
        .padding(.horizontal, 12)
    }

    private var dateLabel: String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: AppClock.now) { return "今天" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: AppClock.now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "昨天" }
        return "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日"
    }

    private func manualChip(
        title: String,
        systemImage: String,
        selected: Bool = false,
        warning: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            chipLabel(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? (warning ? Color.warning : Color.accentColor) : .secondary)
        .background(
            selected
                ? (warning ? Color.warning.opacity(0.12) : Color.accentColor.opacity(0.12))
                : Color(uiColor: .secondarySystemBackground),
            in: .capsule
        )
        .overlay {
            Capsule().stroke(
                selected
                    ? (warning ? Color.warning.opacity(0.60) : Color.accentColor.opacity(0.60))
                    : Color(uiColor: .separator).opacity(0.42),
                lineWidth: 0.6
            )
        }
    }

    private func chipLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 32)
    }

    private var attachmentImage: UIImage? {
        guard let url = AttachmentStore.url(for: attachmentPath) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private var amountDisplay: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(MoneyFormat.symbol(of: currencyCode))
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(expression.displayText)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            if expression.isCompound {
                Text("= \(expression.value.formatted())")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    private var transferPickers: some View {
        VStack(spacing: 16) {
            Picker("从", selection: $selectedAccountID) {
                Text("请选择账户").tag(Optional<UUID>.none)
                ForEach(usableAccounts) { account in
                    Text(account.name).tag(Optional(account.stableID))
                }
            }
            Image(systemName: "arrow.down")
                .foregroundStyle(.secondary)
            Picker("到", selection: $transferTargetID) {
                Text("请选择账户").tag(Optional<UUID>.none)
                ForEach(usableAccounts) { account in
                    Text(account.name).tag(Optional(account.stableID))
                }
            }
        }
        .pickerStyle(.menu)
        .padding(.top, 24)
    }

    private var detailBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if kind != .transfer {
                    Menu {
                        ForEach(usableAccounts) { account in
                            Button(account.name) { selectedAccountID = account.stableID }
                        }
                    } label: {
                        Label(effectiveAccount?.name ?? String(localized: "账户"), systemImage: effectiveAccount?.kind.symbol ?? "wallet.pass")
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                    .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
                Menu {
                    ForEach(books) { book in
                        Button {
                            selectedBook = book
                        } label: {
                            if book.persistentModelID == effectiveBook?.persistentModelID {
                                Label(book.name, systemImage: "checkmark")
                            } else {
                                Text(book.name)
                            }
                        }
                    }
                } label: {
                    Label(effectiveBook?.name ?? "账本", systemImage: "book.closed")
                        .font(.subheadline)
                        .lineLimit(1)
                }
                .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                DatePicker("日期", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                TextField("备注…", text: $note)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
                    .frame(minWidth: 110)
                Button {
                    showMoreDetails = true
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                        .font(.subheadline)
                }
                .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func prepareDefaults() {
        if selectedAccountID == nil { selectedAccountID = usableAccounts.first?.stableID }
        resetCategorySelection()
        loadBudgetStatus()
    }

    private func todayAllowanceBar(_ status: BudgetStatus) -> some View {
        HStack(spacing: 6) {
            Image(systemName: status.todayAllowance >= 0 ? "gauge.with.needle" : "exclamationmark.triangle.fill")
            if status.todayAllowance >= 0 {
                Text("今日可花 \(MoneyFormat.string(status.todayAllowance, currencyCode: currencyCode))")
            } else {
                Text("今日已超支 \(MoneyFormat.string(-status.todayAllowance, currencyCode: currencyCode))")
            }
            Spacer()
            Text("本月剩 \(MoneyFormat.string(status.remaining, currencyCode: currencyCode))")
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(
            .regular.tint(status.todayAllowance >= 0 ? Color.accentColor.opacity(0.25) : Color.warning.opacity(0.35)),
            in: .capsule
        )
    }

    /// 设置过预算时计算「今日可花」。
    private func loadBudgetStatus() {
        let budgets = (try? context.fetch(FetchDescriptor<Budget>())) ?? []
        guard let budget = BudgetStore.effectiveTotalBudget(
            from: budgets,
            selectedBookID: router.selectedBookID,
            fallbackBookID: effectiveBook?.stableID
        ), budget.amount > 0 else {
            budgetStatus = nil
            return
        }
        let all = (try? context.fetch(FetchDescriptor<MoneyTransaction>())) ?? []
        let scoped = LedgerScope.filter(all, selectedBookID: router.selectedBookID)
        budgetStatus = BudgetStore.status(
            for: budget,
            transactions: scoped,
            referenceDate: AppClock.now
        )
    }

    private func resetCategorySelection() {
        if kind == .transfer {
            selectedCategory = nil
            if transferTargetID == nil {
                transferTargetID = usableAccounts.first { $0.stableID != selectedAccountID }?.stableID
            }
        } else if selectedCategory?.kind != kind {
            selectedCategory = visibleCategories.first
        }
    }

    private func saveAndDismiss() {
        if save() { dismiss() }
    }

    private func saveAgain() {
        _ = save()
    }

    @discardableResult
    private func save() -> Bool {
        let amount = expression.value
        guard amount > 0 else { return false }

        do {
            switch kind {
            case .transfer:
                guard let from = effectiveAccount, let to = effectiveTransferTarget,
                      from.persistentModelID != to.persistentModelID else {
                    saveError = LedgerStore.Error.invalidTransfer.localizedDescription
                    return false
                }
                try LedgerStore.createTransaction(
                    in: context,
                    amount: amount,
                    kind: .transfer,
                    date: date,
                    note: note,
                    account: from,
                    toAccount: to,
                    book: effectiveBook,
                    tags: Array(selectedTagNames),
                    isExcluded: isExcluded,
                    attachmentPath: attachmentPath
                )
            case .expense, .income:
                guard let category = selectedCategory else { return false }
                try LedgerStore.createTransaction(
                    in: context,
                    amount: amount,
                    kind: kind,
                    date: date,
                    note: note,
                    category: category,
                    account: effectiveAccount,
                    book: effectiveBook,
                    tags: Array(selectedTagNames),
                    reimbursable: kind == .expense && isReimbursable,
                    isExcluded: isExcluded,
                    attachmentPath: attachmentPath
                )
            }
        } catch {
            saveError = error.localizedDescription
            return false
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        expression.clear()
        note = ""
        date = AppClock.now
        isReimbursable = false
        isExcluded = false
        selectedTagNames.removeAll()
        attachmentPath = ""
        loadBudgetStatus()

        withAnimation(.spring) { showSavedToast = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showSavedToast = false }
        }
        return true
    }

    private func importPhoto(_ item: PhotosPickerItem) {
        Task { @MainActor in
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    throw ManualEntryImageError.invalidImage
                }
                persistImage(image)
                photoItem = nil
            } catch {
                attachmentError = error.localizedDescription
            }
        }
    }

    private func persistImage(_ image: UIImage) {
        do {
            guard let data = image.jpegData(compressionQuality: 0.88) else {
                throw ManualEntryImageError.invalidImage
            }
            let path = try AttachmentStore.save(data: data, fileExtension: "jpg")
            if !attachmentPath.isEmpty { AttachmentStore.remove(attachmentPath) }
            attachmentPath = path
        } catch {
            attachmentError = error.localizedDescription
        }
    }
}

private struct ManualDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var date: Date

    var body: some View {
        NavigationStack {
            DatePicker(
                "选择日期",
                selection: $date,
                in: Date(timeIntervalSince1970: 946_684_800)...AppClock.now,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle("选择日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
            }
        }
    }
}

private struct CameraImagePicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void

        init(onImage: @escaping (UIImage) -> Void) {
            self.onImage = onImage
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

private enum ManualEntryImageError: LocalizedError {
    case invalidImage

    var errorDescription: String? { "这张图片暂时不能用于记账" }
}

private struct QuickAddDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let kind: TransactionKind
    let tags: [Tag]
    @Binding var isReimbursable: Bool
    @Binding var isExcluded: Bool
    @Binding var selectedTagNames: Set<String>
    @Binding var attachmentPath: String
    @State private var photoItem: PhotosPickerItem?
    @State private var attachmentError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("收支选项") {
                    if kind == .expense {
                        Toggle("待报销", isOn: $isReimbursable)
                    }
                    Toggle("不计入收支统计", isOn: $isExcluded)
                }
                if !tags.isEmpty {
                    Section("标签") {
                        ForEach(tags) { tag in
                            Button {
                                if selectedTagNames.contains(tag.name) {
                                    selectedTagNames.remove(tag.name)
                                } else {
                                    selectedTagNames.insert(tag.name)
                                }
                            } label: {
                                HStack {
                                    Text(tag.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedTagNames.contains(tag.name) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }
                Section("附件") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(
                            attachmentPath.isEmpty ? "附加照片" : "更换照片",
                            systemImage: attachmentPath.isEmpty ? "camera" : "photo"
                        )
                    }
                    if !attachmentPath.isEmpty {
                        HStack {
                            Label("已附照片", systemImage: "paperclip")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("移除", role: .destructive) {
                                AttachmentStore.remove(attachmentPath)
                                attachmentPath = ""
                            }
                        }
                    }
                }
            }
            .navigationTitle("更多选项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { return }
                        let path = try AttachmentStore.save(data: data)
                        await MainActor.run {
                            if !attachmentPath.isEmpty { AttachmentStore.remove(attachmentPath) }
                            attachmentPath = path
                            photoItem = nil
                        }
                    } catch {
                        await MainActor.run { attachmentError = error.localizedDescription }
                    }
                }
            }
            .alert("无法添加照片", isPresented: Binding(
                get: { attachmentError != nil },
                set: { if !$0 { attachmentError = nil } }
            )) {
                Button("好") { attachmentError = nil }
            } message: {
                Text(attachmentError ?? "")
            }
        }
    }
}
