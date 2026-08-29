import UIKit
import SwiftUI
import SwiftData
import PhotosUI
import Vision
import QingJiCore

/// AI 记一笔：一句话 / 语音 / 支付截图 OCR 三种方式入账。
///
/// 解析阶段只生成可编辑提案；用户确认后才写入账本。这样 iOS 与 Android
/// 都遵守“模型不能直接改财务数据”的安全边界，同时支持一句话拆成多笔。
struct AIQuickEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(AIProviderStore.self) private var providerStore

    private let initialText: String?
    private let sharedImageFileName: String?

    @Query(filter: #Predicate<TxCategory> { !$0.isArchived }, sort: \TxCategory.sortOrder)
    private var categories: [TxCategory]
    @Query(sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query(sort: \Book.sortOrder)
    private var books: [Book]
    @Query(sort: \MoneyTransaction.date, order: .reverse)
    private var transactions: [MoneyTransaction]

    @State private var text = ""
    @State private var entries: [ParsedEntry] = []
    @State private var matchedCategoryKeys: [String?] = []
    @State private var selectedAccountID: UUID?
    @State private var selectedBookID: UUID?
    @State private var photoItem: PhotosPickerItem?
    @State private var isRecognizingImage = false
    @State private var speech = SpeechDictation()
    @State private var isCloudParsing = false
    @State private var cloudTask: Task<Void, Never>?
    @State private var parseGeneration = 0
    @State private var imageAttachment: AIChatAttachment?
    @State private var saveError: String?
    @State private var didAppear = false
    @State private var pendingRefund: RefundMatchResult?
    @State private var refundNotice = ""
    @State private var pendingConsentAccount: AIProviderAccount?
    @State private var pendingCloudInput: String?
    @State private var pendingCloudAttachments: [AIChatAttachment] = []
    @State private var cloudRunID: UUID?

    init(initialText: String? = nil, sharedImageFileName: String? = nil) {
        self.initialText = initialText
        self.sharedImageFileName = sharedImageFileName
        _text = State(initialValue: initialText ?? "")
    }

    private var usableAccounts: [Account] {
        accounts.filter { !$0.isDeleted && $0.status == .active }
    }

    private var usableBooks: [Book] { books.sorted { $0.sortOrder < $1.sortOrder } }

    private var selectedAccount: Account? {
        usableAccounts.first(where: { $0.stableID == selectedAccountID }) ?? usableAccounts.first
    }

    private var selectedBook: Book? {
        usableBooks.first(where: { $0.stableID == selectedBookID })
            ?? usableBooks.first(where: { $0.stableID == router.selectedBookID })
            ?? usableBooks.first
    }

    private var validEntryCount: Int {
        entries.filter { $0.amount != nil && $0.amount! > 0 }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                inputSection
                if !refundNotice.isEmpty {
                    Section {
                        Label(refundNotice, systemImage: "arrow.uturn.backward.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("退款识别")
                    }
                }
                if let pendingRefund {
                    refundSection(pendingRefund)
                }
                if !entries.isEmpty {
                    destinationSection
                    resultSection
                }
            }
            .navigationTitle("AI 记账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        speech.stop()
                        dismiss()
                    }
                }
            }
            .alert("无法保存", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .onChange(of: speech.transcript) {
                guard !speech.transcript.isEmpty else { return }
                text = speech.transcript
                parseText()
            }
            .onChange(of: text) { oldValue, newValue in
                guard oldValue != newValue else { return }
                // 用户继续编辑时，旧提案不能被误保存；下一次点“解析”
                // 才生成与当前文字对应的新提案。
                guard !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    entries = []
                    matchedCategoryKeys = []
                    pendingRefund = nil
                    refundNotice = ""
                    return
                }
                if !isRecognizingImage {
                    entries = []
                    matchedCategoryKeys = []
                    pendingRefund = nil
                    refundNotice = ""
                    parseGeneration += 1
                    cloudTask?.cancel()
                }
            }
            .onChange(of: photoItem) {
                recognizeSelectedImage()
            }
            .onChange(of: accounts.count) {
                setDefaultDestinationIfNeeded()
            }
            .onChange(of: books.count) {
                setDefaultDestinationIfNeeded()
            }
            .onDisappear {
                speech.stop()
                cloudTask?.cancel()
            }
            .liquidGlassChrome()
            .sheet(item: $pendingConsentAccount) { account in
                AIPrivacyConsentSheet(
                    account: account,
                    includesAttachment: !pendingCloudAttachments.isEmpty
                ) {
                    AIPrivacyConsentStore.accept(for: account.id)
                    let input = pendingCloudInput
                    let attachments = pendingCloudAttachments
                    pendingConsentAccount = nil
                    pendingCloudInput = nil
                    pendingCloudAttachments = []
                    if let input {
                        DispatchQueue.main.async {
                            refineWithCloud(input, attachments: attachments)
                        }
                    }
                }
            }
            .onAppear {
                guard !didAppear else { return }
                didAppear = true
                setDefaultDestinationIfNeeded()
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parseText()
                }
                if let sharedImageFileName,
                   let data = ShareIntake.imageData(for: sharedImageFileName) {
                    recognizeImageData(data)
                }
            }
        }
    }

    private var inputSection: some View {
        Section {
            TextField("例如：昨天打车23块，午饭18块", text: $text, axis: .vertical)
                .lineLimit(2...4)
                .onSubmit(parseText)

            HStack(spacing: 12) {
                Button {
                    speech.toggle()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.fill")
                            .font(.title2)
                        Text(speech.isRecording ? "停止" : "语音")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                }
                .tint(speech.isRecording ? .red : Color.accentColor)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))

                PhotosPicker(selection: $photoItem, matching: .images) {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title2)
                        Text("支付截图")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                }
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
            }

            Button(action: parseText) {
                Label(isCloudParsing ? "解析中" : "解析", systemImage: isCloudParsing ? "hourglass" : "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCloudParsing)

            if isRecognizingImage {
                Label("正在识别截图…", systemImage: "wand.and.stars")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if isCloudParsing {
                Label("正在用当前模型校正，可拆分多笔", systemImage: "sparkles")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let message = speech.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.warning)
            }
        } header: {
            Text("一句话记账")
        } footer: {
            Text(providerStore.selectedAccount == nil
                 ? "未配置 AI 时使用本地规则；金额不确定会保留在确认卡里。"
                 : "AI 只生成提案，确认后才会写入账本。")
        }
    }

    private var destinationSection: some View {
        Section("入账位置") {
            Picker("账户", selection: $selectedAccountID) {
                Text("未选择账户").tag(nil as UUID?)
                ForEach(usableAccounts) { account in
                    Text(account.name).tag(Optional(account.stableID))
                }
            }
            Picker("账本", selection: $selectedBookID) {
                Text("总账本 / 自动").tag(nil as UUID?)
                ForEach(usableBooks) { book in
                    Text(book.name).tag(Optional(book.stableID))
                }
            }
        }
    }

    private var resultSection: some View {
        Section {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                entryRow(entry, index: index)
            }

            if validEntryCount == 0 {
                Label("至少需要一笔有效金额才能保存", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Color.warning)
            }

            Button {
                saveAll()
            } label: {
                Label(
                    entries.count > 1 ? "保存这 \(validEntryCount) 笔" : "保存这笔",
                    systemImage: "checkmark.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(validEntryCount == 0 || selectedAccount == nil)
        } header: {
            Text(entries.count > 1 ? "识别结果 · \(entries.count) 笔" : "识别结果")
        } footer: {
            Text("低置信度或未识别金额不会被静默保存；你可以先点分类重新选择。")
        }
    }

    private func entryRow(_ entry: ParsedEntry, index: Int) -> some View {
        let category = category(for: index, entry: entry)
        let amountText = entry.amount.map {
            MoneyFormat.string($0, currencyCode: selectedAccount?.currencyCode ?? "CNY")
        } ?? "未识别金额"

        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                if entries.count > 1 {
                    Text("\(index + 1)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .frame(width: 22, height: 22)
                        .background(Color.accentColor.opacity(0.12), in: .circle)
                }
                Text(entry.kind == .income ? "收入" : "支出")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(entry.kind == .income ? Color.income : .secondary)
                Spacer(minLength: 6)
                Text(entry.amount == nil ? amountText : (entry.kind == .income ? "+" : "-") + amountText)
                    .font(.headline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(entry.amount == nil ? Color.warning : (entry.kind == .income ? Color.income : .primary))
            }

            HStack(alignment: .center, spacing: 8) {
                Menu {
                    ForEach(categoryOptions(for: entry.kind)) { option in
                        Button {
                            guard index < matchedCategoryKeys.count else { return }
                            matchedCategoryKeys[index] = option.key
                        } label: {
                            if option.key == category?.key {
                                Label(option.name, systemImage: "checkmark")
                            } else {
                                Text(option.name)
                            }
                        }
                    }
                } label: {
                    Label(category?.name ?? "未分类", systemImage: category == nil ? "tag" : "tag.fill")
                        .font(.subheadline)
                }
                .buttonStyle(.glass)

                Text(entry.date, format: entry.timePrecision.carriesClock
                     ? .dateTime.month().day().hour().minute()
                     : .dateTime.month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            if !entry.note.isEmpty {
                Text(entry.note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if entry.confidence < 0.7 {
                Label("识别把握较低，请确认金额和分类", systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(Color.warning)
            }
        }
        .padding(.vertical, 5)
    }

    private func setDefaultDestinationIfNeeded() {
        if selectedAccountID == nil { selectedAccountID = usableAccounts.first?.stableID }
        if selectedBookID == nil, router.selectedBookID == nil {
            selectedBookID = usableBooks.first(where: { $0.isDefault })?.stableID ?? usableBooks.first?.stableID
        }
    }

    private func parseText() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        parseGeneration += 1
        cloudTask?.cancel()
        let refund = matchRefund(in: trimmed)
        if refund.isRefundMutation {
            pendingRefund = refund
            refundNotice = refundPrompt(refund)
            entries = []
            matchedCategoryKeys = []
            return
        }
        pendingRefund = nil
        refundNotice = ""
        entries = [NaturalLanguageEntryParser.parse(trimmed, at: AppClock.now)]
        matchedCategoryKeys = entries.map(resolveCategoryKey(for:))
        refineWithCloud(trimmed)
    }

    private func matchRefund(in text: String) -> RefundMatchResult {
        let scoped = LedgerScope.filter(transactions, selectedBookID: router.selectedBookID)
        let records = scoped.map(\.record)
        let refundTotals = LedgerPolicy.refundTotals(from: records)
        let candidates = scoped.compactMap { transaction -> RefundCandidate? in
            guard transaction.refundOfID == nil,
                  !transaction.isExcluded,
                  transaction.kind == .expense,
                  transaction.amount > 0 else { return nil }
            let refunded = -(refundTotals[transaction.stableID] ?? 0)
            return RefundCandidate(
                id: transaction.stableID,
                label: "\(transaction.note) \(transaction.category?.name ?? "")",
                amount: transaction.amount,
                refunded: refunded,
                date: transaction.date
            )
        }
        return RefundMatcher.match(
            text: text,
            candidates: candidates,
            amount: RefundMatcher.extractAmount(text),
            now: AppClock.now
        )
    }

    @ViewBuilder
    private func refundSection(_ result: RefundMatchResult) -> some View {
        Section {
            if let candidate = result.candidate, let amount = result.amount {
                LabeledContent("原账单") {
                    Text(candidate.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "原支出" : candidate.label)
                        .lineLimit(1)
                }
                LabeledContent("退款金额") {
                    Text("+\(MoneyFormat.string(amount, currencyCode: selectedAccount?.currencyCode ?? "CNY"))")
                        .foregroundStyle(Color.income)
                }
                LabeledContent("退款后剩余") {
                    Text(MoneyFormat.string(candidate.remaining - amount, currencyCode: selectedAccount?.currencyCode ?? "CNY"))
                }
                Button {
                    saveRefund(result)
                } label: {
                    Label("确认退款并挂回原账单", systemImage: "arrow.uturn.backward.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(selectedAccount == nil)
            } else if result.status == .ambiguous {
                Text("找到了多笔可能的原订单，请补充日期或商品；本次不会落账。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(refundPrompt(result))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("退款确认")
        } footer: {
            Text("退款会作为原账单的附着冲减，按原账单日期进入统计，不会新增一笔收入。")
        }
    }

    private func refundPrompt(_ result: RefundMatchResult) -> String {
        switch result.status {
        case .missingAmount:
            return "还缺退款金额，例如“8月20日淘宝键盘退款30”。"
        case .noMatch:
            return "没有找到唯一对应的原订单，请补充商户、商品或原订单日期。"
        case .ambiguous:
            return "找到了多笔可能的原订单，请补充日期或商品。"
        case .exceedsRemaining:
            return "这笔原订单只剩 \(MoneyFormat.string(result.candidate?.remaining ?? 0, currencyCode: selectedAccount?.currencyCode ?? "CNY")) 可退。"
        case .matched:
            return "已找到唯一原订单。"
        case .notRefundMutation:
            return ""
        }
    }

    private func saveRefund(_ result: RefundMatchResult) {
        guard result.status == .matched,
              let amount = result.amount,
              let candidate = result.candidate,
              let original = transactions.first(where: { $0.stableID == candidate.id }) else {
            refundNotice = "原账单刚刚发生变化，请重新解析。"
            pendingRefund = nil
            return
        }
        do {
            try LedgerStore.createOffset(
                for: original,
                amount: amount,
                note: "退款到账",
                eventType: .refund,
                settlementAccount: selectedAccount,
                settledAt: AppClock.now,
                in: context
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            speech.stop()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func refineWithCloud(_ input: String, attachments: [AIChatAttachment] = []) {
        guard let account = providerStore.selectedAccount,
              !providerStore.secret(for: account.id).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        guard AIPrivacyConsentStore.isAccepted(for: account.id) else {
            pendingCloudInput = input
            pendingCloudAttachments = attachments
            pendingConsentAccount = account
            return
        }

        let generation = parseGeneration
        let allowedKeys = Set(categories.map(\.key))
        let options = categories.map { "\($0.key)=\($0.name)" }.joined(separator: "、")
        isCloudParsing = true
        let runID = AIRequestRunStore.start(
            mode: .record,
            account: account,
            sessionID: nil,
            inputCharacters: input.count,
            attachmentCount: attachments.count,
            in: context
        )
        AIRequestRunStore.setStatus(runID, .preparing, in: context)
        AIRequestRunStore.append(
            .contextReady,
            runID: runID,
            summary: "record",
            count: 1,
            in: context
        )
        if !attachments.isEmpty {
            AIRequestRunStore.append(
                .attachmentReady,
                runID: runID,
                count: attachments.count,
                in: context
            )
        }
        cloudTask = Task { @MainActor in
            var finishedRun = false
            defer {
                if !finishedRun {
                    let status: AIRequestStatus = Task.isCancelled || generation != parseGeneration
                        ? .cancelled
                        : .failed
                    AIRequestRunStore.setStatus(
                        runID,
                        status,
                        errorMessage: status == .failed ? "模型没有返回可用提案" : "",
                        in: context
                    )
                }
                if generation == parseGeneration {
                    isCloudParsing = false
                    cloudTask = nil
                }
            }
            var output = ""
            do {
                AIRequestRunStore.setStatus(runID, .thinking, in: context)
                _ = try await providerStore.stream(
                    account: account,
                    messages: [
                        AIChatTurn(
                            role: "system",
                            content: """
                            你是肥喵记账的结构化解析器。只输出 JSON 对象，不要 Markdown。
                            intent 必须是 record，entries 是一笔或多笔记录；每笔包含 amount（数字或 null）、kind（expense/income）、categoryKey（只能从给定 key 选择）、date（YYYY-MM-DD 或带时分的 ISO 时间）、note、confidence（0 到 1）。
                            今天是 \(AppClock.now.formatted(.dateTime.year().month().day()))。没说日期用今天；没说时分不要猜。金额不确定用 null，不要把订单号、卡号或余额当金额。多个金额分别拆成多笔。分类优先选最具体子类。
                            可用分类：\(options)
                            """
                        ),
                        AIChatTurn(role: "user", content: input, attachments: attachments),
                    ],
                    onText: { output += $0 },
                    structuredRecord: true
                )
                guard !Task.isCancelled, generation == parseGeneration,
                      let result = AIRecordProposalCodec.decode(
                          output,
                          fallbackDate: AppClock.now,
                          allowedCategoryKeys: allowedKeys
                      ),
                      result.intent == .record,
                      !result.entries.isEmpty else { return }

                entries = result.entries.map { entry in
                    guard !entry.note.isEmpty else {
                        var copy = entry
                        copy.note = input
                        return copy
                    }
                    return entry
                }
                matchedCategoryKeys = entries.map(resolveCategoryKey(for:))
                finishedRun = true
                cloudRunID = runID
                AIRequestRunStore.setStatus(
                    runID,
                    .awaitingConfirmation,
                    summary: "已生成 \(entries.count) 笔提案",
                    in: context
                )
                AIRequestRunStore.append(
                    .proposalReady,
                    runID: runID,
                    count: entries.count,
                    in: context
                )
            } catch {
                // 本地规则结果仍可用，云端失败不阻断用户记账。
                if !(error is CancellationError) {
                    finishedRun = true
                    AIRequestRunStore.setStatus(
                        runID,
                        .failed,
                        errorMessage: error.localizedDescription,
                        in: context
                    )
                    AIRequestRunStore.append(
                        .failed,
                        runID: runID,
                        summary: error.localizedDescription,
                        in: context
                    )
                } else {
                    finishedRun = true
                    AIRequestRunStore.setStatus(runID, .cancelled, in: context)
                    AIRequestRunStore.append(.cancelled, runID: runID, in: context)
                }
            }
        }
    }

    private func resolveCategoryKey(for entry: ParsedEntry) -> String? {
        let valid = categories.filter { $0.kind == entry.kind && !$0.isArchived }
        if let key = entry.categoryKey, valid.contains(where: { $0.key == key }) {
            return key
        }
        if let guessed = NaturalLanguageEntryParser.guessCategory(entry.note, kind: entry.kind),
           valid.contains(where: { $0.key == guessed }) {
            return guessed
        }
        let fallback = entry.kind == .income ? "otherIncome" : CategorySeed.fallbackExpenseKey
        return valid.first(where: { $0.key == fallback })?.key ?? valid.first?.key
    }

    private func category(for index: Int, entry: ParsedEntry) -> TxCategory? {
        let key = index < matchedCategoryKeys.count ? matchedCategoryKeys[index] : nil
        return categories.first { $0.key == key && $0.kind == entry.kind && !$0.isArchived }
    }

    private func categoryOptions(for kind: TransactionKind) -> [TxCategory] {
        categories
            .filter { $0.kind == kind && !$0.isArchived }
            .sorted {
                if ($0.parentKey == nil) != ($1.parentKey == nil) {
                    return $0.parentKey == nil
                }
                return $0.sortOrder < $1.sortOrder
            }
    }

    private func saveAll() {
        guard let account = selectedAccount else {
            saveError = "请先选择一个可用账户。"
            return
        }
        let drafts = entries.enumerated().compactMap { index, entry -> LedgerStore.TransactionDraft? in
            guard let amount = entry.amount, amount > 0 else { return nil }
            return LedgerStore.TransactionDraft(
                amount: amount,
                kind: entry.kind,
                date: entry.date,
                note: entry.note,
                category: category(for: index, entry: entry),
                account: account,
                book: selectedBook,
                reimbursable: entry.kind == .expense && looksReimbursable(entry.note),
                timePrecision: entry.timePrecision
            )
        }
        guard !drafts.isEmpty else {
            saveError = "没有可保存的有效金额。"
            return
        }
        do {
            try LedgerStore.createTransactions(in: context, drafts: drafts)
            AIRequestRunStore.setStatus(
                cloudRunID,
                .completed,
                summary: "已写入 \(drafts.count) 笔",
                in: context
            )
            AIRequestRunStore.append(
                .committed,
                runID: cloudRunID,
                count: drafts.count,
                in: context
            )
            AIRequestRunStore.append(.completed, runID: cloudRunID, in: context)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            speech.stop()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func looksReimbursable(_ value: String) -> Bool {
        value.range(of: "报销|出差|差旅|垫付|公司报|帮公司|公司的|因公|客户招待|招待费", options: .regularExpression) != nil
    }

    /// 照片 → Vision OCR → 金额提取 + 文本回填，再交给当前 AI 做结构化校正。
    private func recognizeSelectedImage() {
        guard let photoItem else { return }
        Task {
            guard let data = try? await photoItem.loadTransferable(type: Data.self),
                  UIImage(data: data) != nil else { return }
            await MainActor.run { recognizeImageData(data) }
        }
    }

    private func recognizeImageData(_ data: Data) {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { return }
        isRecognizingImage = true
        Task { @MainActor in
            defer { isRecognizingImage = false }
            var request = RecognizeTextRequest()
            request.recognitionLanguages = [Locale.Language(identifier: "zh-Hans"), Locale.Language(identifier: "en-US")]
            guard let observations = try? await request.perform(on: cgImage) else { return }
            let ocrText = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            guard !ocrText.isEmpty else { return }

            var entry = NaturalLanguageEntryParser.parse(ocrText, at: AppClock.now)
            entry.amount = PaymentScreenshotParser.extractAmount(fromOCRText: ocrText) ?? entry.amount
            entry.note = ocrText.split(separator: "\n").prefix(2).joined(separator: " ")
            text = entry.note
            parseGeneration += 1
            entries = [entry]
            matchedCategoryKeys = [resolveCategoryKey(for: entry)]

            let uploadData = image.jpegData(compressionQuality: 0.88) ?? data
            imageAttachment = try? AIChatAttachmentStore.persist(
                data: uploadData,
                name: "支付截图.jpg",
                mimeType: "image/jpeg"
            )
            refineWithCloud(ocrText, attachments: imageAttachment.map { [$0] } ?? [])
        }
    }
}
