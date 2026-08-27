import UIKit
import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import QingJiCore

/// 原生喵助手：保留 Android 的对话能力，同时采用 iOS 的导航、玻璃输入栏、
/// 原生滚动与触觉反馈。账务上下文只在用户发送问题时拼入请求。
struct MeowAssistantView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(AIProviderStore.self) private var providerStore

    @Query(sort: \MoneyTransaction.date, order: .reverse)
    private var transactions: [MoneyTransaction]
    @Query(sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query(sort: \Book.sortOrder)
    private var books: [Book]
    @Query(filter: #Predicate<TxCategory> { !$0.isArchived }, sort: \TxCategory.sortOrder)
    private var categories: [TxCategory]
    @Query(sort: \AIMemoryRecord.updatedAt, order: .reverse)
    private var aiMemories: [AIMemoryRecord]

    private let requestedSessionID: UUID?
    private let titleOverride: String?

    @State private var turns: [AIChatTurn] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var attachmentMessage: String?
    @State private var sessionID: UUID?
    @State private var didLoad = false
    @State private var requestTask: Task<Void, Never>?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var attachments: [AIChatAttachment] = []
    @State private var showFileImporter = false
    @State private var reasoningByTurn: [UUID: String] = [:]
    @State private var sourcesByTurn: [UUID: [AIChatSource]] = [:]
    @State private var recordCards: [UUID: AIRecordCardState] = [:]
    @State private var runIDsByTurn: [UUID: UUID] = [:]
    @State private var recordSession = false
    @State private var confirmationMessage: String?
    @State private var pendingUndoTurnID: UUID?
    @State private var pendingConsentAccount: AIProviderAccount?

    init(sessionID: UUID? = nil, title: String? = nil) {
        requestedSessionID = sessionID
        titleOverride = title
    }

    private var usableRecords: [TransactionRecord] {
        let scoped = LedgerScope.filter(transactions, selectedBookID: router.selectedBookID)
            .map(\.record)
        return LedgerPolicy.userRecords(from: scoped)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if turns.isEmpty {
                    welcome
                } else {
                    conversation
                }
                composer
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(titleOverride ?? (requestedSessionID == nil ? "喵助手" : "新对话"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        modelMenu
                        NavigationLink {
                            AIChatsView()
                        } label: {
                            Image(systemName: "bubble.left.and.bubble.right")
                        }
                        .accessibilityLabel("Chats")
                        NavigationLink {
                            AIProviderSettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("AI 设置")
                    }
                }
            }
            .task {
                loadHistoryIfNeeded()
            }
            .alert("喵助手", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("附件", isPresented: Binding(
                get: { attachmentMessage != nil },
                set: { if !$0 { attachmentMessage = nil } }
            )) {
                Button("好") { attachmentMessage = nil }
            } message: {
                Text(attachmentMessage ?? "")
            }
            .alert("撤销 AI 记账", isPresented: Binding(
                get: { confirmationMessage != nil },
                set: { if !$0 { confirmationMessage = nil } }
            )) {
                Button("取消", role: .cancel) {
                    confirmationMessage = nil
                    pendingUndoTurnID = nil
                }
                Button("撤销", role: .destructive) {
                    let id = pendingUndoTurnID
                    confirmationMessage = nil
                    pendingUndoTurnID = nil
                    undoRecord(turnID: id)
                }
            } message: {
                Text(confirmationMessage ?? "")
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                importFiles(result)
            }
            .sheet(item: $pendingConsentAccount) { account in
                AIPrivacyConsentSheet(
                    account: account,
                    includesAttachment: !attachments.isEmpty
                ) {
                    AIPrivacyConsentStore.accept(for: account.id)
                    pendingConsentAccount = nil
                    DispatchQueue.main.async { send() }
                }
            }
            .onDisappear {
                requestTask?.cancel()
            }
        }
    }

    private var modelMenu: some View {
        Menu {
            ForEach(providerStore.enabledAccounts) { account in
                modelMenuSection(for: account)
            }
            if let current = providerStore.selectedAccount {
                effortMenuSection(for: current)
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .accessibilityLabel(providerStore.selectedAccount.map {
            "\($0.displayName) · \($0.model) · \($0.effort.label)"
        } ?? "选择 AI 模型")
    }

    @ViewBuilder
    private func modelMenuSection(for account: AIProviderAccount) -> some View {
        Section {
            ForEach(account.modelCandidates, id: \.self) { model in
                Button {
                    providerStore.setModel(model, for: account.id)
                } label: {
                    Label(
                        model,
                        systemImage: providerStore.selectedAccountID == account.id &&
                            providerStore.selectedAccount?.model == model
                            ? "checkmark"
                            : "circle"
                    )
                }
            }
        } header: {
            Text(account.displayName)
        }
    }

    @ViewBuilder
    private func effortMenuSection(for account: AIProviderAccount) -> some View {
        Section {
            ForEach(AIReasoningEffort.allCases) { effort in
                Button {
                    providerStore.setEffort(effort, for: account.id)
                } label: {
                    Label(
                        effort.label,
                        systemImage: account.effort == effort ? "checkmark" : "circle"
                    )
                }
            }
        } header: {
            Text("思考强度 · \(account.displayName)")
        }
    }

    private var welcome: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "cat.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 82, height: 82)
                    .background(Color.accentColor.opacity(0.12), in: .circle)

                VStack(spacing: 6) {
                    Text("你好，我是喵助手")
                        .font(.title2.weight(.semibold))
                    Text("可以帮你查账、看趋势，也可以聊聊今天的消费。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let account = providerStore.selectedAccount {
                    Label("当前使用：\(account.displayName) · \(account.model)", systemImage: "sparkles")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    NavigationLink {
                        AIProviderSettingsView()
                    } label: {
                        Label("先配置 AI 账号", systemImage: "gearshape")
                    }
                    .buttonStyle(.glassProminent)
                }

                Text("发送问题时，会把当前账本的月度汇总和近期账目发给你选择的服务商。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 70)
            .padding(.horizontal, 20)
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(turns) { turn in
                        AssistantMessageBubble(
                            turn: turn,
                            isStreaming: isSending && turn.role == "assistant" && turn.content.isEmpty,
                            reasoningSummary: reasoningByTurn[turn.id] ?? "",
                            sources: sourcesByTurn[turn.id] ?? [],
                            recordCard: recordCards[turn.id],
                            onSaveRecord: recordCards[turn.id]?.saved == false ? { saveRecord(turnID: turn.id) } : nil,
                            onUndoRecord: recordCards[turn.id]?.saved == true && recordCards[turn.id]?.rolledBack == false
                                ? {
                                    pendingUndoTurnID = turn.id
                                    confirmationMessage = "只会撤销这次 AI 实际写入的账单。"
                                }
                                : nil,
                            onChangeRecordCategory: { index, categoryKey in
                                changeRecordCategory(turnID: turn.id, index: index, categoryKey: categoryKey)
                            },
                            onDeleteRecordEntry: { index in
                                deleteRecordEntry(turnID: turn.id, index: index)
                            },
                            categoryLabels: Dictionary(
                                categories.map { ($0.key, "\($0.emoji) \($0.name)") },
                                uniquingKeysWith: { first, _ in first }
                            ),
                            categoryOptions: Dictionary(
                                grouping: categories.filter { !$0.isArchived },
                                by: { $0.kind.rawValue }
                            ).mapValues { values in
                                values.sorted { $0.sortOrder < $1.sortOrder }
                                    .map { (key: $0.key, name: $0.name) }
                            }
                        )
                            .id(turn.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: turns.count) {
                if let last = turns.last {
                    withAnimation(.snappy) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if !attachments.isEmpty {
                attachmentStrip
            }
            HStack(alignment: .bottom, spacing: 10) {
                Menu {
                    PhotosPicker(
                        selection: $photoItems,
                        maxSelectionCount: AIChatAttachmentStore.maxImages,
                        matching: .images
                    ) {
                        Label("选择照片", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("选择文件", systemImage: "doc")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.headline.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("添加附件")

                TextField("问问你的账本", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.background, in: .rect(cornerRadius: 18))
                    .onSubmit {
                        if !isSending { send() }
                    }

                Button {
                    if isSending {
                        requestTask?.cancel()
                    } else {
                        send()
                    }
                } label: {
                    Image(systemName: isSending ? "stop.fill" : "arrow.up")
                        .font(.headline.weight(.semibold))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.glassProminent)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty && !isSending)
                .accessibilityLabel(isSending ? "停止生成" : "发送")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            importPhotos(items)
            photoItems = []
        }
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 6) {
                        Image(systemName: attachment.isImage ? "photo" : "doc.fill")
                            .foregroundStyle(Color.accentColor)
                        Text(attachment.name)
                            .lineLimit(1)
                            .font(.caption)
                        Button {
                            attachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("移除 \(attachment.name)")
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.background, in: .capsule)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func loadHistoryIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        let sessions = (try? context.fetch(FetchDescriptor<AIChatSession>())) ?? []
        let session: AIChatSession
        if let requestedSessionID,
           let requested = sessions.first(where: { $0.stableID == requestedSessionID }) {
            session = requested
        } else if requestedSessionID == nil,
                  let record = sessions.first(where: { $0.isRecord }) {
            session = record
        } else {
            session = AIChatSession(
                stableID: requestedSessionID ?? UUID(),
                title: requestedSessionID == nil ? "记一记" : "新对话",
                isRecord: requestedSessionID == nil
            )
            context.insert(session)
            try? context.save()
        }
        sessionID = session.stableID
        recordSession = session.isRecord

        let saved = ((try? context.fetch(FetchDescriptor<AIChatMessage>())) ?? [])
            .filter { $0.sessionID == session.stableID }
            .sorted { $0.createdAt < $1.createdAt }
        reasoningByTurn = Dictionary(uniqueKeysWithValues: saved.compactMap { message in
            let value = message.reasoningSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : (message.stableID, value)
        })
        sourcesByTurn = Dictionary(uniqueKeysWithValues: saved.compactMap { message in
            let values = decodeSources(message.sourceJSON)
            return values.isEmpty ? nil : (message.stableID, values)
        })
        recordCards = Dictionary(uniqueKeysWithValues: saved.compactMap { message in
            guard !message.recordJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let data = message.recordJSON.data(using: .utf8),
                  let card = try? JSONDecoder().decode(AIRecordCardState.self, from: data) else {
                return nil
            }
            return (message.stableID, card)
        })
        turns = saved.map { message in
            let restored = AIChatAttachmentStore.decode(message.attachmentsJSON)
                .compactMap(AIChatAttachmentStore.restore)
            return AIChatTurn(
                id: message.stableID,
                role: message.role,
                content: message.content,
                attachments: restored
            )
        }
    }

    private func send() {
        if isSending {
            requestTask?.cancel()
            return
        }
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        guard let account = providerStore.selectedAccount else {
            errorMessage = "请先在 AI 设置中添加并启用一个账号。"
            return
        }
        guard !providerStore.secret(for: account.id).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = account.authMethod == .oauth
                ? "当前 ChatGPT 账号授权已失效，请到 AI 设置中重新登录。"
                : "当前账号没有 API Key，请到 AI 设置中补充。"
            return
        }
        guard AIPrivacyConsentStore.isAccepted(for: account.id) else {
            pendingConsentAccount = account
            return
        }

        let id = sessionID ?? createSession(for: account)
        sessionID = id
        let userTurn = AIChatTurn(role: "user", content: prompt, attachments: attachments)
        turns.append(userTurn)
        persistMessage(userTurn, sessionID: id)
        updateSessionTitleIfNeeded(prompt, sessionID: id)
        draft = ""
        attachments = []

        let assistantID = UUID()
        turns.append(AIChatTurn(id: assistantID, role: "assistant", content: ""))
        isSending = true

        let intent = recordSession
            ? ChatIntentKind.record
            : ChatIntent.classify(
                prompt,
                hasArabicAmount: prompt.range(of: #"\d"#, options: .regularExpression) != nil
            )
        let requestSystemPrompt: String
        switch intent {
        case .record:
            requestSystemPrompt = recordSession ? recordSystemPrompt : chatSystemPrompt
        case .query:
            requestSystemPrompt = systemPrompt(for: prompt)
            AIMemoryStore.markUsed(aiMemories, query: prompt, in: context)
        case .chat:
            requestSystemPrompt = chatSystemPrompt
        }
        let requestTurns = [AIChatTurn(role: "system", content: requestSystemPrompt)] + turns.dropLast()
        let runMode: AIRequestMode = recordSession
            ? .record
            : (intent == .query ? .query : .chat)
        let runID = AIRequestRunStore.start(
            mode: runMode,
            account: account,
            sessionID: id,
            inputCharacters: prompt.count,
            attachmentCount: userTurn.attachments.count,
            in: context
        )
        if let runID {
            runIDsByTurn[assistantID] = runID
            AIRequestRunStore.setStatus(
                runID,
                .preparing,
                in: context
            )
            AIRequestRunStore.append(
                .contextReady,
                runID: runID,
                summary: intent.rawValue,
                count: requestTurns.count,
                in: context
            )
            if !userTurn.attachments.isEmpty {
                AIRequestRunStore.append(
                    .attachmentReady,
                    runID: runID,
                    count: userTurn.attachments.count,
                    in: context
                )
            }
        }
        requestTask = Task { @MainActor in
            do {
                AIRequestRunStore.setStatus(runID, .thinking, in: context)
                let response = try await providerStore.stream(
                    account: account,
                    messages: Array(requestTurns),
                    onText: { delta in
                        // 记账会话的响应是 JSON 提案，不把原始 JSON 流直接展示
                        // 给用户；最终会变成可操作的原生卡片。
                        if !recordSession {
                            updateAssistant(id: assistantID, append: delta)
                        }
                    },
                    onReasoning: { delta in
                        reasoningByTurn[assistantID, default: ""] += delta
                    },
                    onSources: { sources in
                        sourcesByTurn[assistantID] = sources
                        AIRequestRunStore.append(
                            .source,
                            runID: runID,
                            count: sources.count,
                            in: context
                        )
                    },
                    structuredRecord: recordSession
                )
                var recordCard: AIRecordCardState?
                if recordSession,
                   let parsed = AIRecordProposalCodec.decode(
                       response.text,
                       fallbackDate: AppClock.now,
                       allowedCategoryKeys: Set(categories.map(\.key))
                   ),
                   parsed.intent == .record,
                   !parsed.entries.isEmpty {
                    let normalizedEntries = parsed.entries.map { entry in
                        guard !entry.note.isEmpty else {
                            var copy = entry
                            copy.note = prompt
                            return copy
                        }
                        return entry
                    }
                    let keys = normalizedEntries.map(resolveRecordCategoryKey(for:))
                    recordCard = AIRecordCardState(
                        entries: normalizedEntries,
                        categoryKeys: keys,
                        transactionIDs: Array(repeating: nil, count: normalizedEntries.count)
                    )
                    recordCards[assistantID] = recordCard
                    AIRequestRunStore.setStatus(
                        runID,
                        .awaitingConfirmation,
                        summary: "已生成 \(normalizedEntries.count) 笔提案",
                        in: context
                    )
                    AIRequestRunStore.append(
                        .proposalReady,
                        runID: runID,
                        count: normalizedEntries.count,
                        in: context
                    )
                    updateAssistant(
                        id: assistantID,
                        replaceWith: normalizedEntries.count > 1
                            ? "帮你拆成 \(normalizedEntries.count) 笔，看看对不对："
                            : "看看对不对："
                    )
                }
                if let assistant = turns.first(where: { $0.id == assistantID }) {
                    persistMessage(
                        assistant,
                        sessionID: id,
                        reasoningSummary: response.reasoningSummary,
                        sources: response.sources,
                        recordCard: recordCard
                    )
                }
                if recordCard == nil {
                    AIRequestRunStore.setStatus(
                        runID,
                        .completed,
                        summary: "已收到回复",
                        in: context
                    )
                    AIRequestRunStore.append(
                        .completed,
                        runID: runID,
                        in: context
                    )
                }
            } catch {
                turns.removeAll { $0.id == assistantID }
                if error is CancellationError {
                    AIRequestRunStore.setStatus(runID, .cancelled, in: context)
                    AIRequestRunStore.append(.cancelled, runID: runID, in: context)
                } else {
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
                    errorMessage = error.localizedDescription
                }
            }
            isSending = false
            requestTask = nil
        }
    }

    private func createSession(for account: AIProviderAccount) -> UUID {
        let session = AIChatSession(
            title: requestedSessionID == nil ? "记一记" : "新对话",
            isRecord: requestedSessionID == nil,
            providerID: account.id,
            model: account.model,
            effort: account.effort
        )
        context.insert(session)
        try? context.save()
        return session.stableID
    }

    private func persistMessage(
        _ turn: AIChatTurn,
        sessionID: UUID,
        reasoningSummary: String = "",
        sources: [AIChatSource] = [],
        recordCard: AIRecordCardState? = nil
    ) {
        let recordJSON: String = {
            guard let recordCard,
                  let data = try? JSONEncoder().encode(recordCard) else { return "" }
            return String(decoding: data, as: UTF8.self)
        }()
        let message = AIChatMessage(
            stableID: turn.id,
            sessionID: sessionID,
            role: turn.role,
            content: turn.content,
            reasoningSummary: reasoningSummary,
            sourceJSON: encodeSources(sources),
            attachmentsJSON: AIChatAttachmentStore.encode(turn.attachments),
            recordJSON: recordJSON
        )
        context.insert(message)
        try? context.save()
    }

    private func updateSessionTitleIfNeeded(_ prompt: String, sessionID: UUID) {
        guard let session = (try? context.fetch(FetchDescriptor<AIChatSession>()))?
            .first(where: { $0.stableID == sessionID }),
              !session.isRecord,
              session.title == "新对话" else { return }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        session.title = trimmed.count > 24 ? String(trimmed.prefix(24)) + "…" : trimmed
        session.updatedAt = Date()
        try? context.save()
    }

    private func updateAssistant(id: UUID, append text: String) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        let current = turns[index]
        turns[index] = AIChatTurn(id: id, role: current.role, content: current.content + text)
    }

    private func updateAssistant(id: UUID, replaceWith text: String) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        let current = turns[index]
        turns[index] = AIChatTurn(id: id, role: current.role, content: text)
    }

    private func encodeSources(_ sources: [AIChatSource]) -> String {
        guard let data = try? JSONEncoder().encode(sources) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    private func decodeSources(_ raw: String) -> [AIChatSource] {
        guard let data = raw.data(using: .utf8),
              let values = try? JSONDecoder().decode([AIChatSource].self, from: data) else {
            return []
        }
        return values
    }

    private var recordSystemPrompt: String {
        let options = categories.map { "\($0.key)=\($0.name)" }.joined(separator: "、")
        return """
        你是肥喵记账的记账入口。用户此处是在记录账目，不是聊天或查账。
        只输出 JSON 对象，不要 Markdown 或解释：
        {"intent":"record","entries":[{"amount":数字或null,"kind":"expense或income","categoryKey":"分类key","date":"YYYY-MM-DD或带时分的ISO时间","note":"简短备注","confidence":0到1}]}
        多笔金额必须拆成多条；没说日期用今天，没说时分不要猜；金额不确定用 null，不要把订单号、卡号或余额当金额。分类只能从以下列表选择，优先具体子类：(options)
        """
    }

    private func resolveRecordCategoryKey(for entry: ParsedEntry) -> String? {
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

    private func saveRecord(turnID: UUID) {
        guard var card = recordCards[turnID], !card.saved else { return }
        guard let account = accounts.first(where: {
            !$0.isDeleted && $0.status == .active
        }) else {
            errorMessage = "请先添加一个可用账户。"
            return
        }
        let book = books.first(where: { $0.stableID == router.selectedBookID })
            ?? books.first(where: { $0.isDefault })
            ?? books.first
        let drafts = card.entries.enumerated().compactMap { index, entry -> LedgerStore.TransactionDraft? in
            guard let amount = entry.amount, amount > 0 else { return nil }
            let key = card.categoryKey(at: index)
            let category = categories.first {
                $0.kind == entry.kind && $0.key == key && !$0.isArchived
            }
            return LedgerStore.TransactionDraft(
                amount: amount,
                kind: entry.kind,
                date: entry.date,
                note: entry.note,
                category: category,
                account: account,
                book: book,
                reimbursable: entry.kind == .expense && looksReimbursable(entry.note),
                timePrecision: entry.timePrecision
            )
        }
        guard !drafts.isEmpty else {
            errorMessage = "没有识别出可保存的金额。"
            return
        }
        do {
            let saved = try LedgerStore.createTransactions(in: context, drafts: drafts)
            var ids = Array(repeating: nil as UUID?, count: card.entries.count)
            var savedIndex = 0
            for index in card.entries.indices where card.entries[index].amount != nil {
                guard savedIndex < saved.count else { break }
                ids[index] = saved[savedIndex].stableID
                savedIndex += 1
            }
            card.transactionIDs = ids
            card.saved = true
            card.feedback = "已记下 \(saved.count) 笔，不对可点改分类或删除"
            recordCards[turnID] = card
            persistRecordCard(card, turnID: turnID)
            let runID = runIDsByTurn[turnID]
            AIRequestRunStore.setStatus(
                runID,
                .completed,
                summary: "已写入 \(saved.count) 笔",
                in: context
            )
            AIRequestRunStore.append(
                .committed,
                runID: runID,
                count: saved.count,
                in: context
            )
            AIRequestRunStore.append(.completed, runID: runID, in: context)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func changeRecordCategory(turnID: UUID, index: Int, categoryKey: String) {
        guard var card = recordCards[turnID], card.saved,
              index < card.entries.count,
              let transactionID = card.transactionID(at: index),
              let transaction = transactions.first(where: { $0.stableID == transactionID }) else { return }
        guard let next = categories.first(where: {
            $0.kind == card.entries[index].kind && $0.key == categoryKey && !$0.isArchived
        }) else { return }
        do {
            try LedgerStore.updateCategory(of: transaction, category: next, in: context)
            if index >= card.categoryKeys.count {
                card.categoryKeys += Array(repeating: nil, count: index - card.categoryKeys.count + 1)
            }
            card.categoryKeys[index] = next.key
            card.feedback = "已把第 \(index + 1) 笔改为「\(next.name)」"
            recordCards[turnID] = card
            persistRecordCard(card, turnID: turnID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteRecordEntry(turnID: UUID, index: Int) {
        guard var card = recordCards[turnID], card.saved,
              index < card.entries.count,
              let transactionID = card.transactionID(at: index),
              let transaction = transactions.first(where: { $0.stableID == transactionID }) else { return }
        do {
            try LedgerStore.delete(transaction, in: context)
            card.deletedIndices.insert(index)
            card.feedback = "已删除第 \(index + 1) 笔"
            recordCards[turnID] = card
            persistRecordCard(card, turnID: turnID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func undoRecord(turnID: UUID?) {
        guard let turnID, var card = recordCards[turnID], card.saved, !card.rolledBack else { return }
        do {
            for index in card.entries.indices {
                guard !card.deletedIndices.contains(index),
                      let transactionID = card.transactionID(at: index),
                      let transaction = transactions.first(where: { $0.stableID == transactionID }) else { continue }
                try LedgerStore.delete(transaction, in: context)
                card.deletedIndices.insert(index)
            }
            card.rolledBack = true
            card.feedback = "本次 AI 记账已撤销"
            recordCards[turnID] = card
            persistRecordCard(card, turnID: turnID)
            let runID = runIDsByTurn[turnID]
            AIRequestRunStore.setStatus(runID, .rolledBack, summary: "本次 AI 记账已撤销", in: context)
            AIRequestRunStore.append(.rolledBack, runID: runID, in: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistRecordCard(_ card: AIRecordCardState, turnID: UUID) {
        guard let data = try? JSONEncoder().encode(card),
              let message = (try? context.fetch(FetchDescriptor<AIChatMessage>()))?
                .first(where: { $0.stableID == turnID }) else { return }
        message.recordJSON = String(decoding: data, as: UTF8.self)
        message.content = card.feedback.isEmpty ? message.content : card.feedback
        try? context.save()
    }

    private func looksReimbursable(_ value: String) -> Bool {
        value.range(of: "报销|出差|差旅|垫付|公司报|帮公司|公司的|因公|客户招待|招待费", options: .regularExpression) != nil
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        Task { @MainActor in
            var added: [AIChatAttachment] = []
            for item in items.prefix(AIChatAttachmentStore.maxImages) {
                guard let raw = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: raw),
                      let data = image.jpegData(compressionQuality: 0.88) else { continue }
                if data.count > AIChatAttachmentStore.maxImageBytes {
                    attachmentMessage = "图片不能超过 20 MB。"
                    continue
                }
                if attachments.filter(\.isImage).count + added.count >= AIChatAttachmentStore.maxImages {
                    attachmentMessage = "一次最多发送 3 张图片。"
                    break
                }
                if let attachment = try? AIChatAttachmentStore.persist(
                    data: data,
                    name: "支付截图-\(added.count + 1).jpg",
                    mimeType: "image/jpeg"
                ) {
                    added.append(attachment)
                }
            }
            attachments.append(contentsOf: added)
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            var added: [AIChatAttachment] = []
            for url in urls.prefix(AIChatAttachmentStore.maxFiles) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                guard !data.isEmpty else { continue }
                if data.count > AIChatAttachmentStore.maxFileBytes {
                    attachmentMessage = "文件不能超过 50 MB：\(url.lastPathComponent)"
                    continue
                }
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                    ?? "application/octet-stream"
                if let attachment = try? AIChatAttachmentStore.persist(
                    data: data,
                    name: url.lastPathComponent,
                    mimeType: mime
                ) {
                    added.append(attachment)
                }
            }
            let existingFiles = attachments.filter { !$0.isImage }.count
            attachments.append(contentsOf: added.prefix(max(0, AIChatAttachmentStore.maxFiles - existingFiles)))
        } catch {
            attachmentMessage = "无法读取附件：\(error.localizedDescription)"
        }
    }

    private func systemPrompt(for query: String) -> String {
        let now = AppClock.now
        let components = Calendar.current.dateComponents([.year, .month], from: now)
        let summary = StatisticsEngine.monthlySummary(
            of: usableRecords,
            year: components.year ?? 2000,
            month: components.month ?? 1
        )
        let recent = usableRecords.prefix(16).map {
            let note = $0.note.isEmpty ? "未命名" : $0.note
            return "\($0.date.formatted(.dateTime.month().day())) \(note) \($0.amount)"
        }.joined(separator: "；")
        let memory = AIMemoryStore.promptBlock(
            memories: aiMemories,
            query: query
        )
        let memoryText = memory.isEmpty ? "暂无匹配的已授权记忆" : memory
        return """
        你是肥喵记账的亲切助手。只能根据提供的账务数据回答；数据不足时明确说不知道，不要编造金额。金额使用人民币，转账不算收入或支出，退款和报销按原账单净额理解。回答口语化、简洁，必要时使用少量 Markdown。
        当前月份：\(components.year ?? 2000)-\(components.month ?? 1)。本月收入 \(summary.totalIncome)，本月支出 \(summary.totalExpense)，结余 \(summary.balance)。近期记录：\(recent.isEmpty ? "暂无" : recent)
        与本次问题匹配的已授权记忆：
        \(memoryText)
        """
    }

    private var chatSystemPrompt: String {
        """
        你是肥喵记账的亲切助手。当前问题不是在查询或修改用户账本。
        只根据会话中用户明确提供的内容回答；不要猜测用户的金额、账户或历史消费，
        也不要声称读取了账本。回答自然、口语化，必要时使用少量 Markdown。
        """
    }
}

private struct AssistantMessageBubble: View {
    let turn: AIChatTurn
    let isStreaming: Bool
    let reasoningSummary: String
    let sources: [AIChatSource]
    let recordCard: AIRecordCardState?
    let onSaveRecord: (() -> Void)?
    let onUndoRecord: (() -> Void)?
    let onChangeRecordCategory: ((Int, String) -> Void)?
    let onDeleteRecordEntry: ((Int) -> Void)?
    let categoryLabels: [String: String]
    let categoryOptions: [String: [(key: String, name: String)]]
    @AppStorage("qingji.userMessageBubbleStyle") private var bubbleStyleRaw = UserMessageBubbleStyle.followCardOpacity.rawValue

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            if turn.role == "assistant" {
                Image(systemName: "cat.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor.opacity(0.12), in: .circle)
                bubble
                Spacer(minLength: 35)
            } else {
                Spacer(minLength: 35)
                bubble
                    .foregroundStyle(.primary)
            }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !turn.attachments.isEmpty {
                ForEach(turn.attachments) { attachment in
                    Label(attachment.name, systemImage: attachment.isImage ? "photo" : "doc.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !reasoningSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DisclosureGroup("已思考") {
                    Text(reasoningSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if isStreaming {
                ProgressView()
                    .controlSize(.small)
            } else if let recordCard {
                AIRecordCardView(
                    card: recordCard,
                    categoryLabels: categoryLabels,
                    categoryOptions: categoryOptions,
                    onSave: onSaveRecord,
                    onUndo: onUndoRecord,
                    onChangeCategory: onChangeRecordCategory,
                    onDeleteEntry: onDeleteRecordEntry
                )
            } else {
                Text(turn.content)
                    .textSelection(.enabled)
            }
            if !sources.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Label("来源 \(sources.count)", systemImage: "globe")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    ForEach(sources) { source in
                        if let url = URL(string: source.url) {
                            Link(destination: url) {
                                Text(source.title.isEmpty ? source.url : source.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
        .font(.body)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            turn.role == "assistant"
                ? AnyShapeStyle(.background)
                : AnyShapeStyle(userBubbleBackground)
        )
        .clipShape(.rect(cornerRadius: 18))
    }

    private var userBubbleBackground: Color {
        switch UserMessageBubbleStyle(rawValue: bubbleStyleRaw) ?? .followCardOpacity {
        case .followCardOpacity:
            return Color.accentColor.opacity(0.14)
        case .fixedGray:
            return Color(.secondarySystemBackground)
        }
    }
}

/// 固定记账会话的原生提案/已保存卡。视觉上沿用 iOS 的分组卡和玻璃动作，
/// 业务上保留 Android 的“先确认、可改分类、可删单笔、可整批撤销”。
private struct AIRecordCardView: View {
    let card: AIRecordCardState
    let categoryLabels: [String: String]
    let categoryOptions: [String: [(key: String, name: String)]]
    let onSave: (() -> Void)?
    let onUndo: (() -> Void)?
    let onChangeCategory: ((Int, String) -> Void)?
    let onDeleteEntry: ((Int) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(card.saved ? "已保存的记账明细" : "看看对不对")
                .font(.subheadline.weight(.medium))

            ForEach(Array(card.entries.enumerated()), id: \.offset) { index, entry in
                let deleted = card.deletedIndices.contains(index)
                let key = card.categoryKey(at: index) ?? ""
                let label = categoryLabels[key] ?? (entry.kind == .income ? "💵 其他收入" : "📦 其他")
                let amount = entry.amount.map {
                    MoneyFormat.string($0, currencyCode: "CNY")
                } ?? "未识别金额"

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(label)
                            .lineLimit(1)
                            .foregroundStyle(deleted ? .secondary : .primary)
                        Spacer(minLength: 6)
                        Text(entry.amount == nil ? amount : (entry.kind == .income ? "+" : "-") + amount)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(deleted ? .secondary : (entry.kind == .income ? Color.income : .primary))
                            .strikethrough(deleted)
                    }
                    HStack(spacing: 8) {
                        Text(entry.date, format: entry.timePrecision.carriesClock
                             ? .dateTime.month().day().hour().minute()
                             : .dateTime.month().day())
                        if !entry.note.isEmpty {
                            Text(entry.note)
                                .lineLimit(1)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if !deleted, card.saved, let onChangeCategory {
                        categoryMenu(
                            index: index,
                            selectedKey: key,
                            options: categoryOptions[entry.kind.rawValue] ?? [],
                            onChange: onChangeCategory
                        )
                    }
                }
                .opacity(deleted ? 0.55 : 1)
                if index < card.entries.count - 1 {
                    Divider()
                }
            }

            if !card.saved, let onSave {
                Button("确认保存 \(card.entries.count) 笔", action: onSave)
                    .buttonStyle(.glassProminent)
                    .frame(maxWidth: .infinity)
            } else if card.saved {
                HStack {
                    if let onUndo, !card.rolledBack {
                        Button("撤销本次 AI 记账", action: onUndo)
                            .buttonStyle(.bordered)
                    }
                    ForEach(Array(card.entries.enumerated()), id: \.offset) { index, _ in
                        if !card.deletedIndices.contains(index), let onDeleteEntry {
                            Button {
                                onDeleteEntry(index)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("删除第 \(index + 1) 笔")
                        }
                    }
                }
            }
            if !card.feedback.isEmpty {
                Text(card.feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.background, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.accentColor.opacity(0.16), lineWidth: 1)
        }
    }

    private func categoryMenu(
        index: Int,
        selectedKey: String,
        options: [(key: String, name: String)],
        onChange: @escaping (Int, String) -> Void
    ) -> some View {
        Menu {
            ForEach(options, id: \.key) { option in
                Button {
                    onChange(index, option.key)
                } label: {
                    Label(
                        option.name,
                        systemImage: option.key == selectedKey ? "checkmark" : "circle"
                    )
                }
            }
        } label: {
            Label("改分类", systemImage: "tag")
                .font(.caption)
        }
        .buttonStyle(.bordered)
    }
}

#Preview {
    MeowAssistantView()
        .modelContainer(AppModelContainer.shared)
        .environment(AppRouter())
        .environment(AIProviderStore())
}
