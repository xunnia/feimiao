import Foundation
import Observation
import Security

/// The provider/account shape mirrors the Android AI settings contract while
/// keeping credentials outside the Codable payload.
enum AIProviderType: String, Codable, CaseIterable, Hashable, Identifiable {
    case deepSeek
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .deepSeek: return "DeepSeek"
        case .custom: return "自定义服务商"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .deepSeek: return "https://api.deepseek.com"
        case .custom: return "https://api.openai.com/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .deepSeek: return "deepseek-v4-flash"
        case .custom: return "gpt-5-mini"
        }
    }
}

enum AIEndpointKind: String, Codable, CaseIterable, Hashable, Identifiable {
    case automatic
    case chatCompletions
    case responses
    case anthropicMessages

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "自动判断"
        case .chatCompletions: return "Chat Completions"
        case .responses: return "OpenAI Responses"
        case .anthropicMessages: return "Anthropic Messages"
        }
    }
}

enum AIAuthMethod: String, Codable, CaseIterable, Hashable, Identifiable {
    case apiKey
    case oauth

    var id: String { rawValue }

    var label: String {
        switch self {
        case .apiKey: return "API Key"
        case .oauth: return "ChatGPT / Codex OAuth"
        }
    }
}

enum AIReasoningEffort: String, Codable, CaseIterable, Hashable, Identifiable {
    case none
    case minimal
    case low
    case medium
    case high
    case extra
    case max
    case ultra

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "关闭"
        case .minimal: return "Minimal"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .extra: return "Extra"
        case .max: return "Max"
        case .ultra: return "Ultra"
        }
    }

    var responsesValue: String? {
        switch self {
        case .none: return nil
        case .minimal: return "minimal"
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        case .extra: return "xhigh"
        case .max, .ultra: return "xhigh"
        }
    }

    var maxOutputTokens: Int {
        switch self {
        case .none, .minimal, .low, .medium: return 4096
        case .high: return 8192
        case .extra: return 12288
        case .max, .ultra: return 16384
        }
    }

    var claudeBudgetTokens: Int? {
        switch self {
        case .none: return nil
        case .minimal: return 1024
        case .low: return 4096
        case .medium: return 8192
        case .high: return 16384
        case .extra: return 24576
        case .max: return 32768
        case .ultra: return 65536
        }
    }
}

struct AIProviderAccount: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var type: AIProviderType
    var baseURL: String
    var model: String
    var models: [String]
    var endpoint: AIEndpointKind
    var authMethod: AIAuthMethod
    var effort: AIReasoningEffort
    var webSearchEnabled: Bool
    var isEnabled: Bool
    /// ChatGPT workspace/account identity is not a credential, so it may be
    /// kept in the provider metadata. Tokens themselves stay in Keychain.
    var oauthAccountID: String
    var oauthExpiresAt: Date?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        type: AIProviderType,
        baseURL: String,
        model: String,
        models: [String] = [],
        endpoint: AIEndpointKind = .automatic,
        authMethod: AIAuthMethod = .apiKey,
        effort: AIReasoningEffort = .low,
        webSearchEnabled: Bool = false,
        isEnabled: Bool = true,
        oauthAccountID: String = "",
        oauthExpiresAt: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.baseURL = baseURL
        self.model = model
        self.models = models
        self.endpoint = endpoint
        self.authMethod = authMethod
        self.effort = effort
        self.webSearchEnabled = webSearchEnabled
        self.isEnabled = isEnabled
        self.oauthAccountID = oauthAccountID
        self.oauthExpiresAt = oauthExpiresAt
        self.updatedAt = updatedAt
    }

    static func deepSeek() -> Self {
        Self(
            name: "DeepSeek",
            type: .deepSeek,
            baseURL: AIProviderType.deepSeek.defaultBaseURL,
            model: AIProviderType.deepSeek.defaultModel,
            endpoint: .chatCompletions,
            effort: .low
        )
    }

    static func custom() -> Self {
        Self(
            name: "我的 AI 服务商",
            type: .custom,
            baseURL: AIProviderType.custom.defaultBaseURL,
            model: AIProviderType.custom.defaultModel
        )
    }

    static func chatGPT() -> Self {
        Self(
            name: "ChatGPT / Codex",
            type: .custom,
            baseURL: OpenAIOAuth.codexBaseURL,
            model: "gpt-5",
            endpoint: .responses,
            authMethod: .oauth,
            effort: .medium
        )
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? type.label : trimmed
    }

    var modelCandidates: [String] {
        let primary = model.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = models
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !primary.isEmpty && !result.contains(primary) {
            result.insert(primary, at: 0)
        }
        return result
    }

    var usesAnthropicMessages: Bool {
        if endpoint == .anthropicMessages { return true }
        if endpoint != .automatic { return false }
        let lowerURL = baseURL.lowercased()
        return lowerURL.contains("anthropic") || model.lowercased().contains("claude")
    }

    var usesResponses: Bool {
        if authMethod == .oauth { return true }
        if endpoint == .responses { return true }
        if endpoint == .chatCompletions || usesAnthropicMessages { return false }
        return baseURL.lowercased().contains("api.openai.com")
    }

    var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case id, name, type, baseURL, model, models, endpoint, authMethod
        case effort, webSearchEnabled, isEnabled, oauthAccountID, oauthExpiresAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        type = try container.decodeIfPresent(AIProviderType.self, forKey: .type) ?? .custom
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? type.defaultBaseURL
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? type.defaultModel
        models = try container.decodeIfPresent([String].self, forKey: .models) ?? []
        endpoint = try container.decodeIfPresent(AIEndpointKind.self, forKey: .endpoint) ?? .automatic
        authMethod = try container.decodeIfPresent(AIAuthMethod.self, forKey: .authMethod) ?? .apiKey
        effort = try container.decodeIfPresent(AIReasoningEffort.self, forKey: .effort) ?? .low
        webSearchEnabled = try container.decodeIfPresent(Bool.self, forKey: .webSearchEnabled) ?? false
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        oauthAccountID = try container.decodeIfPresent(String.self, forKey: .oauthAccountID) ?? ""
        oauthExpiresAt = try container.decodeIfPresent(Date.self, forKey: .oauthExpiresAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

enum AIProviderStoreError: LocalizedError {
    case missingSecret
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingSecret: return "请先配置 API Key。"
        case .keychain(let status): return "无法保存 AI 凭据（\(status)）。"
        }
    }
}

private enum AIKeychain {
    private static let accessService = "com.qingji.app.ai-provider"
    private static let refreshService = "com.qingji.app.ai-provider.refresh"

    static func read(for id: UUID, service: String = accessService) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ secret: String, for id: UUID, service: String = accessService) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(secret.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw AIProviderStoreError.keychain(status) }
    }

    static func delete(for id: UUID, service: String = accessService) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func readRefresh(for id: UUID) -> String? {
        read(for: id, service: refreshService)
    }

    static func writeRefresh(_ token: String, for id: UUID) throws {
        try write(token, for: id, service: refreshService)
    }

    static func deleteRefresh(for id: UUID) {
        delete(for: id, service: refreshService)
    }
}

@MainActor
@Observable
final class AIProviderStore {
    private static let defaultsKey = "qingji.ai.providers.v1"
    private static let healthDefaultsKey = "qingji.ai.provider-health.v1"

    private struct PersistedState: Codable {
        var accounts: [AIProviderAccount]
        var selectedAccountID: UUID?
    }

    private let defaults: UserDefaults
    private(set) var accounts: [AIProviderAccount] = []
    private(set) var providerHealth: [UUID: AIProviderHealth] = [:]
    var selectedAccountID: UUID?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let state = try? JSONDecoder().decode(PersistedState.self, from: data) {
            accounts = state.accounts
            selectedAccountID = state.selectedAccountID
        }
        if let data = defaults.data(forKey: Self.healthDefaultsKey),
           let entries = try? JSONDecoder().decode([AIProviderHealth].self, from: data) {
            providerHealth = entries.reduce(into: [:]) { result, entry in
                result[entry.providerID] = entry
            }
        }
        normalizeSelection()
    }

    var enabledAccounts: [AIProviderAccount] {
        accounts.filter { $0.isEnabled && $0.isConfigured && hasCredential(for: $0) }
    }

    var selectedAccount: AIProviderAccount? {
        if let selectedAccountID,
           let selected = enabledAccounts.first(where: { $0.id == selectedAccountID }) {
            return selected
        }
        return enabledAccounts.first
    }

    func secret(for accountID: UUID) -> String {
        AIKeychain.read(for: accountID) ?? ""
    }

    func oauthRefreshToken(for accountID: UUID) -> String {
        AIKeychain.readRefresh(for: accountID) ?? ""
    }

    func health(for accountID: UUID) -> AIProviderHealth {
        providerHealth[accountID] ?? AIProviderHealth(providerID: accountID)
    }

    @discardableResult
    func recordProviderSuccess(for accountID: UUID, latencyMs: Int) -> AIProviderHealth {
        let next = health(for: accountID).recordSuccess(latencyMs: latencyMs)
        providerHealth[accountID] = next
        persistHealth()
        return next
    }

    @discardableResult
    func recordProviderFailure(for accountID: UUID, error: Error) -> AIProviderHealth {
        let next = health(for: accountID).recordFailure(error.localizedDescription)
        providerHealth[accountID] = next
        persistHealth()
        return next
    }

    @discardableResult
    func recordProviderVerification(
        for accountID: UUID,
        status: AIProviderVerificationStatus,
        message: String = "",
        latencyMs: Int = 0
    ) -> AIProviderHealth {
        let next = health(for: accountID).recordVerification(
            status: status,
            message: message,
            latencyMs: latencyMs
        )
        providerHealth[accountID] = next
        persistHealth()
        return next
    }

    func resetProviderHealth(for accountID: UUID) {
        providerHealth.removeValue(forKey: accountID)
        persistHealth()
    }

    func upsert(_ account: AIProviderAccount, secret: String) throws {
        var updated = account
        updated.updatedAt = Date()
        let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousAuthMethod = accounts.first(where: { $0.id == account.id })?.authMethod
        if !trimmedSecret.isEmpty {
            try AIKeychain.write(trimmedSecret, for: account.id)
        } else if account.authMethod == .apiKey || previousAuthMethod == .apiKey {
            AIKeychain.delete(for: account.id)
        }
        if account.authMethod == .apiKey {
            AIKeychain.deleteRefresh(for: account.id)
            updated.oauthAccountID = ""
            updated.oauthExpiresAt = nil
        } else if previousAuthMethod == .apiKey {
            AIKeychain.deleteRefresh(for: account.id)
        }
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = updated
        } else {
            accounts.append(updated)
        }
        if selectedAccountID == nil { selectedAccountID = account.id }
        normalizeSelection()
        persist()
    }

    /// Starts a native iOS browser session, stores the resulting tokens in
    /// Keychain, and verifies the account without ledger data. A verification
    /// failure does not discard a successful OAuth login.
    @discardableResult
    func authorizeOAuth(for account: AIProviderAccount) async throws -> AIProviderAuthorizationResult {
        let tokens = try await OpenAIOAuth.authorize()
        var updated = account
        updated.authMethod = .oauth
        updated.endpoint = .responses
        updated.baseURL = OpenAIOAuth.codexBaseURL
        if updated.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.model = "gpt-5"
        }
        updated.oauthAccountID = tokens.accountID ?? updated.oauthAccountID
        updated.oauthExpiresAt = tokens.expiresAt
        try saveOAuthTokens(tokens, for: updated)
        let verification = await verify(account: updated)
        let persisted = accounts.first(where: { $0.id == updated.id }) ?? updated
        return AIProviderAuthorizationResult(account: persisted, verification: verification)
    }

    /// Refreshes a ChatGPT access token once. Callers retry their original
    /// request only after this method returns successfully.
    @discardableResult
    func refreshOAuth(for account: AIProviderAccount) async throws -> AIProviderAccount {
        let refreshToken = oauthRefreshToken(for: account.id)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !refreshToken.isEmpty else { throw AIProviderStoreError.missingSecret }
        let tokens = try await OpenAIOAuth.refresh(refreshToken: refreshToken)
        var updated = account
        updated.oauthAccountID = tokens.accountID ?? updated.oauthAccountID
        updated.oauthExpiresAt = tokens.expiresAt
        try saveOAuthTokens(tokens, for: updated)
        return updated
    }

    private func saveOAuthTokens(_ tokens: OpenAIOAuthTokens, for account: AIProviderAccount) throws {
        try AIKeychain.write(tokens.accessToken, for: account.id)
        if let refreshToken = tokens.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !refreshToken.isEmpty {
            try AIKeychain.writeRefresh(refreshToken, for: account.id)
        }
        var persisted = account
        persisted.updatedAt = Date()
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = persisted
        } else {
            accounts.append(persisted)
        }
        selectedAccountID = selectedAccountID ?? account.id
        normalizeSelection()
        persist()
    }

    func remove(_ account: AIProviderAccount) {
        accounts.removeAll { $0.id == account.id }
        providerHealth.removeValue(forKey: account.id)
        AIKeychain.delete(for: account.id)
        AIKeychain.deleteRefresh(for: account.id)
        normalizeSelection()
        persist()
        persistHealth()
    }

    func setSelected(_ account: AIProviderAccount) {
        selectedAccountID = account.id
        persist()
    }

    func setModel(_ model: String, for accountID: UUID) {
        let value = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        var account = accounts[index]
        guard account.modelCandidates.contains(value) else { return }
        account.model = value
        account.updatedAt = Date()
        accounts[index] = account
        selectedAccountID = accountID
        persist()
    }

    func setEffort(_ effort: AIReasoningEffort, for accountID: UUID) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        var account = accounts[index]
        account.effort = effort
        account.updatedAt = Date()
        accounts[index] = account
        selectedAccountID = accountID
        persist()
    }

    func replaceModels(for accountID: UUID, with models: [String]) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[index].models = Array(Set(models.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
            .sorted()
        accounts[index].updatedAt = Date()
        persist()
    }

    func refreshModels(for account: AIProviderAccount) async throws -> [String] {
        let started = Date()
        do {
            let request = try await requestWithOAuthRetry(for: account) { active, credential in
                try await AIProviderClient.fetchModels(account: active, secret: credential)
            }
            replaceModels(for: account.id, with: request.value)
            recordProviderSuccess(
                for: account.id,
                latencyMs: Date().milliseconds(since: started)
            )
            return request.value
        } catch {
            recordProviderFailure(for: account.id, error: error)
            throw error
        }
    }

    func testConnection(for account: AIProviderAccount) async throws -> String {
        let response = try await stream(
            account: account,
            messages: [AIChatTurn(role: "user", content: "请只回复 OK")],
            onText: { _ in }
        )
        return response.text
    }

    /// Verifies an account without sending ledger data, conversation history,
    /// attachments, or user content. The catalogue and minimal ping share the
    /// same OAuth refresh path and the result is retained for settings and
    /// diagnostics.
    func verify(account: AIProviderAccount) async -> AIProviderVerificationResult {
        let started = Date()

        func finish(
            _ status: AIProviderVerificationStatus,
            models: [String] = [],
            message: String = ""
        ) -> AIProviderVerificationResult {
            let result = AIProviderVerificationResult(
                status: status,
                models: models,
                message: AIProviderHealth.sanitizedError(message),
                latencyMs: Date().milliseconds(since: started)
            )
            recordProviderVerification(
                for: account.id,
                status: result.status,
                message: result.message,
                latencyMs: result.latencyMs
            )
            return result
        }

        guard !account.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return finish(.configurationError, message: "缺少基础地址")
        }
        guard hasCredential(for: account) else {
            return finish(.configurationError, message: "请先配置 API Key 或完成 OAuth 授权")
        }

        var discoveredModels: [String] = []
        do {
            let catalogue = try await requestWithOAuthRetry(for: account) { active, credential in
                try await AIProviderClient.fetchModels(account: active, secret: credential)
            }
            discoveredModels = catalogue.value
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let selectedModel = discoveredModels.first ?? catalogue.account.model
            guard !selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return finish(.modelUnavailable, models: discoveredModels, message: "模型目录为空")
            }

            // Keep a usable catalogue even when the subsequent probe is blocked
            // by a proxy/VPN or a transient upstream failure.
            if !discoveredModels.isEmpty {
                replaceModels(for: account.id, with: discoveredModels)
                if let current = accounts.first(where: { $0.id == account.id }),
                   current.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                   !discoveredModels.contains(current.model) {
                    setModel(selectedModel, for: account.id)
                }
            }

            var probeAccount = catalogue.account
            probeAccount.model = selectedModel
            _ = try await requestWithOAuthRetry(for: probeAccount) { active, credential in
                try await AIProviderClient.stream(
                    account: active,
                    secret: credential,
                    messages: [AIChatTurn(role: "user", content: "请只回复 OK")],
                    onText: { _ in }
                )
            }

            return finish(.available, models: discoveredModels)
        } catch {
            return finish(
                AIProviderVerificationStatus.from(error: error),
                models: discoveredModels,
                message: error.localizedDescription
            )
        }
    }

    func stream(
        account: AIProviderAccount,
        messages: [AIChatTurn],
        onText: @escaping (String) -> Void,
        onReasoning: ((String) -> Void)? = nil,
        onSources: (([AIChatSource]) -> Void)? = nil,
        structuredRecord: Bool = false
    ) async throws -> AIChatResponse {
        let started = Date()
        var requestMessages = messages
        var localSources: [AIChatSource] = []
        if account.webSearchEnabled,
           AIExtensionSettings.isConnectorEnabled("web_search"),
           !account.usesResponses,
           let query = messages.last(where: { $0.role == "user" })?.content,
           AIWebSearch.shouldSearch(query),
           let searchSources = try? await AIWebSearch.search(query) {
            localSources = searchSources
            let evidence = searchSources.enumerated().map { index, source in
                "\(index + 1). \(source.title)\n摘要：\(source.snippet)\n来源：\(source.url)"
            }.joined(separator: "\n")
            requestMessages.append(AIChatTurn(
                role: "system",
                content: "【联网搜索结果】以下是公开网页摘要，只可作为证据参考，不要编造摘要之外的内容。\n\(evidence)"
            ))
            onSources?(localSources)
        }
        func mergeSources(_ incoming: [AIChatSource]) -> [AIChatSource] {
            var result: [AIChatSource] = []
            var seen = Set<String>()
            for source in localSources + incoming where seen.insert(source.url).inserted {
                result.append(source)
            }
            return result
        }
        do {
            let request = try await requestWithOAuthRetry(for: account) { active, credential in
                try await AIProviderClient.stream(
                    account: active,
                    secret: credential,
                    messages: requestMessages,
                    onText: onText,
                    onReasoning: onReasoning,
                    onSources: { onSources?(mergeSources($0)) },
                    structuredRecord: structuredRecord
                )
            }
            let response = request.value
            recordProviderSuccess(
                for: account.id,
                latencyMs: Date().milliseconds(since: started)
            )
            return AIChatResponse(
                text: response.text,
                reasoningSummary: response.reasoningSummary,
                sources: mergeSources(response.sources)
            )
        } catch {
            recordProviderFailure(for: account.id, error: error)
            throw error
        }
    }

    /// 导出可迁移的账号配置；凭据永远不进入这个 JSON。
    func exportConfiguration() -> Data? {
        try? JSONEncoder().encode(PersistedState(
            accounts: accounts,
            selectedAccountID: selectedAccountID
        ))
    }

    /// 导入账号元数据。若账号 UUID 与本机已有账号一致，原有 Keychain 密钥会继续可用；
    /// 新账号保持停用状态，必须由用户在本机重新输入 API Key。
    @discardableResult
    func importConfiguration(_ data: Data) throws -> Int {
        let state = try JSONDecoder().decode(PersistedState.self, from: data)
        let existingIDs = Set(accounts.map(\.id))
        accounts = state.accounts.map { account in
            var imported = account
            if !existingIDs.contains(account.id) { imported.isEnabled = false }
            return imported
        }
        selectedAccountID = state.selectedAccountID
        normalizeSelection()
        persist()
        return accounts.count
    }

    private func hasCredential(for account: AIProviderAccount) -> Bool {
        if !secret(for: account.id).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return account.authMethod == .oauth &&
            !oauthRefreshToken(for: account.id).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func preparedCredential(
        for account: AIProviderAccount
    ) async throws -> (account: AIProviderAccount, credential: String) {
        var active = account
        var credential = secret(for: active.id).trimmingCharacters(in: .whitespacesAndNewlines)
        if credential.isEmpty, active.authMethod == .oauth,
           !oauthRefreshToken(for: active.id).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            active = try await refreshOAuth(for: active)
            credential = secret(for: active.id).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !credential.isEmpty else { throw AIProviderError.missingAPIKey }
        return (active, credential)
    }

    private func requestWithOAuthRetry<Value>(
        for account: AIProviderAccount,
        operation: (AIProviderAccount, String) async throws -> Value
    ) async throws -> (value: Value, account: AIProviderAccount) {
        var prepared = try await preparedCredential(for: account)
        do {
            let value = try await operation(prepared.account, prepared.credential)
            return (value, prepared.account)
        } catch {
            guard prepared.account.authMethod == .oauth, isUnauthorized(error) else {
                throw error
            }
            prepared.account = try await refreshOAuth(for: prepared.account)
            prepared.credential = secret(for: prepared.account.id)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prepared.credential.isEmpty else { throw AIProviderError.missingAPIKey }
            let value = try await operation(prepared.account, prepared.credential)
            return (value, prepared.account)
        }
    }

    private func isUnauthorized(_ error: Error) -> Bool {
        guard case AIProviderError.http(let status, _) = error else { return false }
        return status == 401
    }

    private func normalizeSelection() {
        if let selectedAccountID,
           accounts.contains(where: {
               $0.id == selectedAccountID &&
               $0.isEnabled &&
               $0.isConfigured &&
               hasCredential(for: $0)
           }) {
            return
        }
        selectedAccountID = accounts.first(where: {
            $0.isEnabled && $0.isConfigured && hasCredential(for: $0)
        })?.id
    }

    private func persist() {
        let state = PersistedState(accounts: accounts, selectedAccountID: selectedAccountID)
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private func persistHealth() {
        let entries = providerHealth.values.sorted {
            $0.providerID.uuidString < $1.providerID.uuidString
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.healthDefaultsKey)
    }
}

private extension Date {
    func milliseconds(since start: Date) -> Int {
        max(0, min(Int(timeIntervalSince(start) * 1000), 3_600_000))
    }
}
