import Foundation
import SwiftUI
import UniformTypeIdentifiers

private struct AIProviderDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// AI 账号管理。非敏感配置进 UserDefaults，密钥由 AIProviderStore 写入 Keychain。
struct AIProviderSettingsView: View {
    @Environment(AIProviderStore.self) private var providerStore

    @State private var showNewAccount = false
    @State private var editingAccount: AIProviderAccount?
    @State private var testingID: UUID?
    @State private var refreshingID: UUID?
    @State private var message: String?
    @State private var showConfigurationExporter = false
    @State private var showConfigurationImporter = false
    @State private var configurationDocument = AIProviderDocument()

    var body: some View {
        List {
            Section {
                if providerStore.accounts.isEmpty {
                    ContentUnavailableView(
                        "还没有 AI 账号",
                        systemImage: "sparkles",
                        description: Text("添加一个服务商后，喵助手就能使用云端模型。")
                    )
                } else {
                    ForEach(providerStore.accounts) { account in
                        accountRow(account)
                    }
                    .onDelete(perform: deleteAccounts)
                }
            } header: {
                Text("服务商账号")
            } footer: {
                Text("API Key、OAuth access token 和 refresh token 只保存在本机钥匙串，不会写入账本备份。")
            }

            Section("当前默认") {
                if let selected = providerStore.selectedAccount {
                    LabeledContent("账号", value: selected.displayName)
                    LabeledContent("模型", value: selected.model)
                    LabeledContent("思考强度", value: selected.effort.label)
                } else {
                    Text("尚未选择可用账号")
                        .foregroundStyle(.secondary)
                }
            }

            Section("账号迁移") {
                Button {
                    exportConfiguration()
                } label: {
                    Label("导出账号配置", systemImage: "square.and.arrow.up")
                }
                Button {
                    showConfigurationImporter = true
                } label: {
                    Label("导入账号配置", systemImage: "square.and.arrow.down")
                }
            } footer: {
                Text("JSON 只包含服务商、模型和显示设置，不包含 API Key；导入新账号后需在本机重新填写密钥。")
            }

            Section("隐私与数据") {
                Button("重置所有服务商授权", role: .destructive) {
                    AIPrivacyConsentStore.reset()
                    message = "已重置。下次向服务商发送问题时会重新确认。"
                }
            } footer: {
                Text("授权按服务商保存；同一服务商切换模型不会重复确认，切换服务商会重新确认。")
            }

            Section("扩展能力") {
                NavigationLink {
                    AITaskCenterView()
                } label: {
                    Label("AI 任务中心", systemImage: "waveform")
                }
                NavigationLink {
                    AIExtensionSettingsView()
                } label: {
                    Label("技能与连接", systemImage: "link")
                }
                NavigationLink {
                    AIReportScheduleView()
                } label: {
                    Label("定时报表", systemImage: "calendar.badge.clock")
                }
                NavigationLink {
                    LocalModelCompanionView()
                } label: {
                    Label("本地模型伴侣", systemImage: "desktopcomputer")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("AI 与喵助手")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewAccount = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加 AI 账号")
            }
        }
        .sheet(isPresented: $showNewAccount) {
            AIProviderEditorView(account: nil)
        }
        .sheet(item: $editingAccount) { account in
            AIProviderEditorView(account: account)
        }
        .fileExporter(
            isPresented: $showConfigurationExporter,
            document: configurationDocument,
            contentType: .json,
            defaultFilename: "feimiao-ai-accounts"
        ) { result in
            if case .failure(let error) = result {
                message = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $showConfigurationImporter,
            allowedContentTypes: [.json]
        ) { result in
            importConfiguration(result)
        }
        .alert("AI 操作结果", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func accountRow(_ account: AIProviderAccount) -> some View {
        HStack(spacing: 12) {
            Button {
                providerStore.setSelected(account)
            } label: {
                HStack(spacing: 12) {
                Image(systemName: account.id == providerStore.selectedAccountID
                    ? "checkmark.circle.fill"
                    : "circle")
                    .foregroundStyle(account.id == providerStore.selectedAccountID ? Color.accentColor : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(account.displayName)
                            .foregroundStyle(.primary)
                            .font(.body.weight(.medium))
                        if !account.isEnabled {
                            Text("已停用")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("\(account.type.label) · \(account.model)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Menu {
                    Button {
                        editingAccount = account
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    Button {
                        test(account)
                    } label: {
                        Label("测试连接", systemImage: "bolt.horizontal")
                    }
                    Button {
                        refreshModels(account)
                    } label: {
                        Label("刷新模型", systemImage: "arrow.clockwise")
                    }
                    Button {
                        var toggled = account
                        toggled.isEnabled.toggle()
                        do {
                            try providerStore.upsert(toggled, secret: providerStore.secret(for: account.id))
                        } catch {
                            message = error.localizedDescription
                        }
                    } label: {
                        Label(account.isEnabled ? "停用" : "启用", systemImage: account.isEnabled ? "pause.circle" : "play.circle")
                    }
            } label: {
                if testingID == account.id || refreshingID == account.id {
                    ProgressView()
                } else {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("管理 \(account.displayName)")
        }
    }

    private func deleteAccounts(at offsets: IndexSet) {
        for index in offsets {
            providerStore.remove(providerStore.accounts[index])
        }
    }

    private func test(_ account: AIProviderAccount) {
        guard testingID == nil, refreshingID == nil else { return }
        testingID = account.id
        Task { @MainActor in
            defer { testingID = nil }
            do {
                let result = try await providerStore.testConnection(for: account)
                message = "连接成功：\(result.trimmingCharacters(in: .whitespacesAndNewlines))"
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func refreshModels(_ account: AIProviderAccount) {
        guard refreshingID == nil, testingID == nil else { return }
        refreshingID = account.id
        Task { @MainActor in
            defer { refreshingID = nil }
            do {
                let models = try await providerStore.refreshModels(for: account)
                message = "已刷新 \(models.count) 个模型。"
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func exportConfiguration() {
        guard let data = providerStore.exportConfiguration() else {
            message = "账号配置导出失败。"
            return
        }
        configurationDocument = AIProviderDocument(data: data)
        showConfigurationExporter = true
    }

    private func importConfiguration(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else {
                message = "无法读取所选配置文件。"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            let count = try providerStore.importConfiguration(Data(contentsOf: url))
            message = "已导入 \(count) 个账号；新账号需要重新填写 API Key。"
        } catch {
            message = "账号配置导入失败：\(error.localizedDescription)"
        }
    }
}

private struct AIProviderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AIProviderStore.self) private var providerStore

    let original: AIProviderAccount?

    @State private var type: AIProviderType
    @State private var name: String
    @State private var baseURL: String
    @State private var model: String
    @State private var endpoint: AIEndpointKind
    @State private var authMethod: AIAuthMethod
    @State private var effort: AIReasoningEffort
    @State private var webSearchEnabled: Bool
    @State private var secret = ""
    @State private var storedSecret = ""
    @State private var isAuthorizing = false
    @State private var errorMessage: String?

    init(account: AIProviderAccount?) {
        original = account
        _type = State(initialValue: account?.type ?? .deepSeek)
        _name = State(initialValue: account?.name ?? AIProviderType.deepSeek.label)
        _baseURL = State(initialValue: account?.baseURL ?? AIProviderType.deepSeek.defaultBaseURL)
        _model = State(initialValue: account?.model ?? AIProviderType.deepSeek.defaultModel)
        _endpoint = State(initialValue: account?.endpoint ?? .chatCompletions)
        _authMethod = State(initialValue: account?.authMethod ?? .apiKey)
        _effort = State(initialValue: account?.effort ?? .low)
        _webSearchEnabled = State(initialValue: account?.webSearchEnabled ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("服务商") {
                    Picker("类型", selection: $type) {
                        ForEach(AIProviderType.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    TextField("名称", text: $name)
                    TextField("基础地址", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("模型") {
                    TextField("模型名称", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let discoveredModels = original?.modelCandidates,
                       !discoveredModels.isEmpty {
                        Picker("已发现模型", selection: $model) {
                            ForEach(discoveredModels, id: \.self) { item in
                                Text(item).tag(item)
                            }
                        }
                    }
                    Picker("端点", selection: $endpoint) {
                        ForEach(AIEndpointKind.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    Picker("思考强度", selection: $effort) {
                        ForEach(AIReasoningEffort.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    Toggle("允许联网搜索", isOn: $webSearchEnabled)
                }

                Section("凭据") {
                    Picker("认证方式", selection: $authMethod) {
                        ForEach(AIAuthMethod.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    if authMethod == .oauth {
                        Label(
                            storedSecret.isEmpty ? "尚未登录 ChatGPT" : "ChatGPT 已授权",
                            systemImage: storedSecret.isEmpty ? "person.crop.circle.badge.questionmark" : "checkmark.seal.fill"
                        )
                        .foregroundStyle(storedSecret.isEmpty ? Color.secondary : Color.accentColor)
                        Button {
                            authorizeChatGPT()
                        } label: {
                            if isAuthorizing {
                                ProgressView()
                            } else {
                                Label(
                                    storedSecret.isEmpty ? "使用 ChatGPT 登录" : "重新登录 ChatGPT",
                                    systemImage: "person.badge.key"
                                )
                            }
                        }
                        .disabled(isAuthorizing)
                        Text("会打开系统安全浏览器完成授权。令牌仅保存在本机钥匙串。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        SecureField(
                            storedSecret.isEmpty ? "API Key" : "API Key（留空则保留原值）",
                            text: $secret
                        )
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Color.warning)
                    }
                }
            }
            .navigationTitle(original == nil ? "添加 AI 账号" : "编辑 AI 账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let original {
                    storedSecret = providerStore.secret(for: original.id)
                }
            }
            .onChange(of: authMethod) { _, value in
                guard value == .oauth else { return }
                type = .custom
                endpoint = .responses
                baseURL = OpenAIOAuth.codexBaseURL
                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name == AIProviderType.deepSeek.label {
                    name = "ChatGPT / Codex"
                }
                if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    model = "gpt-5"
                }
            }
        }
    }

    private func save() {
        let account = makeAccount()
        do {
            try providerStore.upsert(account, secret: secret.isEmpty ? storedSecret : secret)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func makeAccount() -> AIProviderAccount {
        AIProviderAccount(
            id: original?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            type: type,
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            models: original?.models ?? [],
            endpoint: endpoint,
            authMethod: authMethod,
            effort: effort,
            webSearchEnabled: webSearchEnabled,
            isEnabled: original?.isEnabled ?? true,
            oauthAccountID: original?.oauthAccountID ?? "",
            oauthExpiresAt: original?.oauthExpiresAt
        )
    }

    private func authorizeChatGPT() {
        let account = makeAccount()
        isAuthorizing = true
        Task { @MainActor in
            defer { isAuthorizing = false }
            do {
                _ = try await providerStore.authorizeOAuth(for: account)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
