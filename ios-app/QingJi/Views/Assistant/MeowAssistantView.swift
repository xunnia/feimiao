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
    @State private var activeRequestID: UUID?
    @State private var recordLeases: [UUID: AIChatOperationFence.Lease] = [:]
    @State private var completionByTurn: [UUID: AIChatCompletionMetadata] = [:]
    @State private var attachments: [AIChatAttachment] = []
    @State private var showAddSheet = false
    @State private var reasoningByTurn: [UUID: String] = [:]
    @State private var sourcesByTurn: [UUID: [AIChatSource]] = [:]
    @State private var recordCards: [UUID: AIRecordCardState] = [:]
    @State private var runIDsByTurn: [UUID: UUID] = [:]
    @State private var recordSession = false
    @State private var confirmationMessage: String?
    @State private var pendingUndoTurnID: UUID?
    @State private var pendingConsentAccount: AIProviderAccount?
    @State private var followLatest = true
    @State private var userScrolling = false

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
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .liquidGlassCanvas()
            .navigationTitle(titleOverride ?? (requestedSessionID == nil ? "喵助手" : "新对话"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            modelMenu
                            NavigationLink {
                                AIChatsView()
                            } label: {
                                Image(systemName: "bubble.left.and.bubble.right")
                            }
                            .liquidGlassCircleControl(size: 44)
                            .accessibilityLabel("Chats")
                            NavigationLink {
                                AIProviderSettingsView()
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .liquidGlassCircleControl(size: 44)
                            .accessibilityLabel("AI 设置")
                        }
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
            .sheet(isPresented: $showAddSheet) {
                ChatAddSheet(existing: attachments) { added, message in
                    attachments.append(contentsOf: added)
                    if let message {
                        // 等面板收起再弹提示，避免和关面板的动画抢。
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            attachmentMessage = message
                        }
                    }
                }
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
            .liquidGlassChrome()
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
        .liquidGlassCircleControl(size: 44)
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
                    .glassEffect(.regular.tint(Color.accentColor.opacity(0.16)), in: .circle)

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
                    .liquidGlassPrimaryPillControl(horizontalPadding: 16, minHeight: 46)
                    .frame(maxWidth: .infinity)
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
                            isStreaming: isSending && turn.role == "assistant" && turn.id == turns.last?.id,
                            reasoningSummary: reasoningByTurn[turn.id] ?? "",
                            completion: completionByTurn[turn.id],
                            sources: sourcesByTurn[turn.id] ?? [],
                            onEdit: {
                                draft = turn.content
                                attachments = turn.attachments
                            },
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
                                categories.map { ($0.key, $0.name) },
                                uniquingKeysWith: { first, _ in first }
                            ),
                            categoryEmojis: Dictionary(
                                categories.map { ($0.key, $0.emoji) },
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
            .scrollEdgeEffectStyle(.soft, for: .all)
            .onScrollPhaseChange { _, phase in
                userScrolling = phase == .interacting || phase == .decelerating
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height + geometry.contentInsets.bottom -
                    geometry.contentOffset.y - geometry.containerSize.height < 64
            } action: { _, atBottom in
                if userScrolling { followLatest = atBottom }
            }
            .onChange(of: turns.count) {
                if followLatest, let last = turns.last {
                    withAnimation(.snappy) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: turns.last?.content) {
                if followLatest, let last = turns.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if !attachments.isEmpty {
                attachmentStrip
            }
            GlassEffectContainer(spacing: 10) {
                HStack(alignment: .bottom, spacing: 10) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.headline.weight(.semibold))
                }
                .liquidGlassCircleControl(size: 44)
                .accessibilityLabel("添加到聊天")

                TextField("问问你的账本", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
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
                }
                .liquidGlassPrimaryCircleControl(size: 48)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty && !isSending)
                .accessibilityLabel(isSending ? "停止生成" : "发送")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(
            .regular.tint(Color.accentColor.opacity(0.08)),
            in: .rect(cornerRadius: 26)
        )
        .padding(.horizontal, 12)
    }

    private var attachmentStrip: some View {
        AssistantAttachmentStrip(attachments: attachments) { id in
            attachments.removeAll { $0.id == id }
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

        let loadedSessionID = session.stableID
        let saved: [AIChatMessage]
        do {
            saved = try context.fetch(FetchDescriptor<AIChatMessage>(
                predicate: #Predicate { $0.sessionID == loadedSessionID },
                sortBy: [SortDescriptor(\.createdAt)]
            ))
        } catch {
            errorMessage = "对话记录读取失败，请重新进入：\(error.localizedDescription)"
            return
        }
        completionByTurn = Dictionary(uniqueKeysWithValues: saved.compactMap { message in
            guard let data = message.recordJSON.data(using: .utf8),
                  let metadata = try? JSONDecoder().decode(AIChatCompletionMetadata.self, from: data) else {
                return nil
            }
            return (message.stableID, metadata)
        })
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
        recordLeases = Dictionary(uniqueKeysWithValues: recordCards.map { id, card in
            (id, AIChatOperationFence.shared.capture(sessionID: loadedSessionID, bookID: card.bookID))
        })
        turns = saved.map { message in
            let restored = AIChatAttachmentStore.decode(message.attachmentsJSON)
                .compactMap(AIChatAttachmentStore.restore)
            return AIChatTurn(
                id: message.stableID,
                role: message.role,
                content: message.content,
                attachments: restored,
                createdAt: message.createdAt
            )
        }
    }

    private func send() {
        if isSending {
            requestTask?.cancel()
            return
        }
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty || !attachments.isEmpty else { return }
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
        let requestID = UUID()
        activeRequestID = requestID
        let bookID = (books.first { $0.stableID == router.selectedBookID }
            ?? books.first { $0.isDefault } ?? books.first)?.stableID
        let lease = AIChatOperationFence.shared.capture(sessionID: id, bookID: bookID)
        let startedAt = Date()
        let isRecordRequest = recordSession
        let userTurn = AIChatTurn(role: "user", content: prompt, attachments: attachments)
        followLatest = true
        turns.append(userTurn)
        guard persistMessage(userTurn, sessionID: id) else {
            turns.removeAll { $0.id == userTurn.id }
            activeRequestID = nil
            return
        }
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
            var firstOutputAt: Date?
            var summaryBuffer = AIStreamSummaryBuffer()
            var pendingText = ""
            var displayTask: Task<Void, Never>?
            func flushDisplay() {
                displayTask?.cancel()
                displayTask = nil
                guard activeRequestID == requestID,
                      AIChatOperationFence.shared.isCurrent(lease) else { return }
                if !pendingText.isEmpty {
                    updateAssistant(id: assistantID, append: pendingText)
                    pendingText = ""
                }
                if !summaryBuffer.text.isEmpty {
                    reasoningByTurn[assistantID] = summaryBuffer.text
                }
            }
            func scheduleDisplay() {
                guard displayTask == nil else { return }
                displayTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 32_000_000)
                    guard !Task.isCancelled else { return }
                    flushDisplay()
                }
            }
            defer {
                displayTask?.cancel()
                if activeRequestID == requestID {
                    isSending = false
                    requestTask = nil
                    activeRequestID = nil
                }
            }
            do {
                AIRequestRunStore.setStatus(runID, .thinking, in: context)
                let response = try await providerStore.stream(
                    account: account,
                    messages: Array(requestTurns),
                    onText: { delta in
                        guard activeRequestID == requestID,
                              AIChatOperationFence.shared.isCurrent(lease),
                              requestTask?.isCancelled != true else { return }
                        if firstOutputAt == nil, !delta.isEmpty { firstOutputAt = Date() }
                        // 记账会话的响应是 JSON 提案，不把原始 JSON 流直接展示
                        // 给用户；最终会变成可操作的原生卡片。
                        if !isRecordRequest {
                            pendingText += delta
                            scheduleDisplay()
                        }
                    },
                    onReasoning: { delta in
                        guard activeRequestID == requestID,
                              AIChatOperationFence.shared.isCurrent(lease),
                              requestTask?.isCancelled != true else { return }
                        summaryBuffer.append(delta)
                        scheduleDisplay()
                    },
                    onSources: { sources in
                        guard activeRequestID == requestID,
                              AIChatOperationFence.shared.isCurrent(lease),
                              requestTask?.isCancelled != true else { return }
                        sourcesByTurn[assistantID] = sources
                        AIRequestRunStore.append(
                            .source,
                            runID: runID,
                            count: sources.count,
                            in: context
                        )
                    },
                    structuredRecord: isRecordRequest,
                    webSearch: ChatWebSearchPreference.isEnabled
                )
                try Task.checkCancellation()
                guard activeRequestID == requestID,
                      AIChatOperationFence.shared.isCurrent(lease) else { return }
                flushDisplay()
                if !isRecordRequest {
                    updateAssistant(id: assistantID, replaceWith: response.text)
                }
                var recordCard: AIRecordCardState?
                if isRecordRequest,
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
                        bookID: lease.bookID,
                        categoryKeys: keys,
                        transactionIDs: Array(repeating: nil, count: normalizedEntries.count)
                    )
                    recordCards[assistantID] = recordCard
                    recordLeases[assistantID] = lease
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
                    let metadata = AIChatCompletionMetadata(
                        thinkingSeconds: Int((firstOutputAt ?? Date()).timeIntervalSince(startedAt)), interrupted: false)
                    completionByTurn[assistantID] = metadata
                    persistMessage(
                        assistant,
                        sessionID: id,
                        reasoningSummary: response.reasoningSummary,
                        sources: response.sources,
                        recordCard: recordCard,
                        completion: metadata
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
                guard activeRequestID == requestID,
                      AIChatOperationFence.shared.isCurrent(lease) else { return }
                flushDisplay()
                let partial = turns.first { $0.id == assistantID }
                let hasSummary = !(reasoningByTurn[assistantID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if let partial, !partial.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasSummary {
                    let metadata = AIChatCompletionMetadata(
                        thinkingSeconds: Int((firstOutputAt ?? Date()).timeIntervalSince(startedAt)), interrupted: true)
                    completionByTurn[assistantID] = metadata
                    persistMessage(partial, sessionID: id,
                        reasoningSummary: reasoningByTurn[assistantID] ?? "",
                        sources: sourcesByTurn[assistantID] ?? [], completion: metadata)
                } else {
                    turns.removeAll { $0.id == assistantID }
                }
                if AIProviderError.isCancellation(error) {
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
                    if partial?.content.isEmpty != false {
                        errorMessage = error.localizedDescription
                    }
                }
            }
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

    @discardableResult
    private func persistMessage(
        _ turn: AIChatTurn,
        sessionID: UUID,
        reasoningSummary: String = "",
        sources: [AIChatSource] = [],
        recordCard: AIRecordCardState? = nil,
        completion: AIChatCompletionMetadata? = nil
    ) -> Bool {
        let recordJSON: String = {
            let data: Data?
            if let recordCard { data = try? JSONEncoder().encode(recordCard) }
            else if let completion { data = try? JSONEncoder().encode(completion) }
            else { data = nil }
            guard let data else { return "" }
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
        message.createdAt = turn.createdAt
        context.insert(message)
        do {
            try context.save()
            return true
        } catch {
            context.delete(message)
            errorMessage = "对话记录保存失败：\(error.localizedDescription)"
            return false
        }
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
        turns[index] = AIChatTurn(id: id, role: current.role, content: current.content + text,
                                 attachments: current.attachments, createdAt: current.createdAt)
    }

    private func updateAssistant(id: UUID, replaceWith text: String) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        let current = turns[index]
        turns[index] = AIChatTurn(id: id, role: current.role, content: text,
                                 attachments: current.attachments, createdAt: current.createdAt)
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
        多笔金额必须拆成多条；没说日期用今天，没说时分不要猜；金额不确定用 null，不要把订单号、卡号或余额当金额。分类只能从以下列表选择，优先具体子类：\(options)
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
        guard recordCards[turnID]?.saved == false else { return }
        guard let account = accounts.first(where: {
            !$0.isDeleted && $0.status == .active
        }) else {
            errorMessage = "请先添加一个可用账户。"
            return
        }
        guard recordOperationIsCurrent(turnID), let lease = recordLeases[turnID] else { return }
        do {
            let card = try AIRecordCardStore.save(turnID: turnID, accountID: account.stableID,
                                                 lease: lease, in: context)
            let count = card.transactionIDs.compactMap { $0 }.count
            recordCards[turnID] = card
            let runID = runIDsByTurn[turnID]
            AIRequestRunStore.setStatus(
                runID,
                .completed,
                summary: "已写入 \(count) 笔",
                in: context
            )
            AIRequestRunStore.append(
                .committed,
                runID: runID,
                count: count,
                in: context
            )
            AIRequestRunStore.append(.completed, runID: runID, in: context)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func changeRecordCategory(turnID: UUID, index: Int, categoryKey: String) {
        guard recordOperationIsCurrent(turnID), let lease = recordLeases[turnID] else { return }
        do {
            recordCards[turnID] = try AIRecordCardStore.changeCategory(
                turnID: turnID, index: index, categoryKey: categoryKey, lease: lease, in: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteRecordEntry(turnID: UUID, index: Int) {
        guard recordOperationIsCurrent(turnID), let lease = recordLeases[turnID] else { return }
        do {
            recordCards[turnID] = try AIRecordCardStore.deleteEntry(
                turnID: turnID, index: index, lease: lease, in: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func undoRecord(turnID: UUID?) {
        guard let turnID, recordOperationIsCurrent(turnID), let lease = recordLeases[turnID] else { return }
        do {
            recordCards[turnID] = try AIRecordCardStore.undo(turnID: turnID, lease: lease, in: context)
            let runID = runIDsByTurn[turnID]
            AIRequestRunStore.setStatus(runID, .rolledBack, summary: "本次 AI 记账已撤销", in: context)
            AIRequestRunStore.append(.rolledBack, runID: runID, in: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recordOperationIsCurrent(_ turnID: UUID) -> Bool {
        guard let lease = recordLeases[turnID], AIChatOperationFence.shared.isCurrent(lease) else {
            errorMessage = "会话或账本已改变，请重新打开对话。"
            return false
        }
        return true
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
    let completion: AIChatCompletionMetadata?
    let sources: [AIChatSource]
    let onEdit: () -> Void
    let recordCard: AIRecordCardState?
    let onSaveRecord: (() -> Void)?
    let onUndoRecord: (() -> Void)?
    let onChangeRecordCategory: ((Int, String) -> Void)?
    let onDeleteRecordEntry: ((Int) -> Void)?
    let categoryLabels: [String: String]
    let categoryEmojis: [String: String]
    let categoryOptions: [String: [(key: String, name: String)]]
    @AppStorage("qingji.userMessageBubbleStyle") private var bubbleStyleRaw = UserMessageBubbleStyle.followCardOpacity.rawValue
    @State private var selectText = false
    @State private var feedback = 0

    var body: some View {
        if turn.role == "assistant" {
            answer.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .trailing, spacing: 8) {
                if !turn.attachments.isEmpty {
                    AssistantAttachmentStrip(attachments: turn.attachments)
                }
                if !turn.content.isEmpty {
                    HStack {
                        Spacer(minLength: 35)
                        Text(turn.content).font(.body).textSelection(.enabled)
                            .padding(.horizontal, 14).padding(.vertical, 11)
                            .background(userBubbleBackground, in: .rect(cornerRadius: 18))
                            .contextMenu {
                                Text(turn.createdAt.formatted(date: .abbreviated, time: .shortened))
                                Button("复制", systemImage: "doc.on.doc") {
                                    UIPasteboard.general.string = turn.content
                                }
                                Button("编辑", systemImage: "square.and.pencil", action: onEdit)
                                Button("选择文本", systemImage: "text.cursor") { selectText = true }
                            }
                    }
                }
            }
            .sheet(isPresented: $selectText) {
                NavigationStack {
                    ScrollView {
                        Text(turn.content).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                    }
                    .liquidGlassCanvas().navigationTitle("选择文本")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { selectText = false }
                    }}
                    .liquidGlassChrome()
                }
            }
        }
    }

    private var answer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if (isStreaming && turn.content.isEmpty) || !reasoningSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AssistantThinkingSummary(summary: reasoningSummary,
                    seconds: completion?.thinkingSeconds,
                    isThinking: isStreaming && turn.content.isEmpty)
            }
            if let recordCard {
                AIRecordCardView(card: recordCard, categoryLabels: categoryLabels,
                    categoryEmojis: categoryEmojis, categoryOptions: categoryOptions,
                    onSave: onSaveRecord, onUndo: onUndoRecord,
                    onChangeCategory: onChangeRecordCategory, onDeleteEntry: onDeleteRecordEntry)
            } else if !turn.content.isEmpty {
                AssistantMarkdownBody(text: turn.content)
            }
            if completion?.interrupted == true {
                Text("回复已中断").font(.caption).foregroundStyle(.secondary)
            }
            if !isStreaming && !turn.content.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) {
                        actions
                        Spacer(minLength: 8)
                        if !sources.isEmpty { AssistantSourcesButton(sources: sources) }
                    }
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 0) { actions; Spacer(minLength: 0) }
                        if !sources.isEmpty { AssistantSourcesButton(sources: sources) }
                    }
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 0) {
            action("复制", symbol: "doc.on.doc") { UIPasteboard.general.string = turn.content }
            action("赞同", symbol: "hand.thumbsup", selected: feedback == 1) { feedback = feedback == 1 ? 0 : 1 }
            action("不赞同", symbol: "hand.thumbsdown", selected: feedback == -1) { feedback = feedback == -1 ? 0 : -1 }
            ShareLink(item: turn.content) {
                Image(systemName: "square.and.arrow.up").frame(width: 36, height: 36)
            }.buttonStyle(.plain).accessibilityLabel("分享")
        }.foregroundStyle(.secondary).fixedSize()
    }

    private func action(_ label: String, symbol: String, selected: Bool = false,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol).frame(width: 36, height: 36)
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
        }.buttonStyle(.plain).accessibilityLabel(label)
    }

    private var userBubbleBackground: Color {
        switch UserMessageBubbleStyle(rawValue: bubbleStyleRaw) ?? .followCardOpacity {
        case .followCardOpacity: return Color.accentColor.opacity(0.14)
        case .fixedGray: return Color(.secondarySystemBackground)
        }
    }
}

/// 固定记账会话的原生提案/已保存卡。视觉上沿用 iOS 的分组卡和玻璃动作，
/// 业务上保留 Android 的“先确认、可改分类、可删单笔、可整批撤销”。
private struct AIRecordCardView: View {
    let card: AIRecordCardState
    let categoryLabels: [String: String]
    let categoryEmojis: [String: String]
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
                let label = categoryLabels[key] ?? (entry.kind == .income ? "其他收入" : "其他")
                let emoji = categoryEmojis[key] ?? (entry.kind == .income ? "💵" : "📦")
                let amount = entry.amount.map {
                    MoneyFormat.string($0, currencyCode: "CNY")
                } ?? "未识别金额"

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if card.saved {
                            CategoryIcon(
                                categoryKey: key,
                                emoji: emoji,
                                size: 30
                            )
                        }
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
                    .liquidGlassPrimaryPillControl()
                    .frame(maxWidth: .infinity)
            } else if card.saved {
                HStack {
                    if let onUndo, !card.rolledBack {
                        Button("撤销本次 AI 记账", action: onUndo)
                            .liquidGlassPillControl(horizontalPadding: 10, minHeight: 36)
                    }
                    ForEach(Array(card.entries.enumerated()), id: \.offset) { index, _ in
                        if !card.deletedIndices.contains(index), let onDeleteEntry {
                            Button {
                                onDeleteEntry(index)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .liquidGlassCircleControl(size: 36)
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
        .liquidGlassPillControl(horizontalPadding: 10, minHeight: 36)
    }
}

#Preview {
    MeowAssistantView()
        .modelContainer(AppModelContainer.shared)
        .environment(AppRouter())
        .environment(AIProviderStore())
}
