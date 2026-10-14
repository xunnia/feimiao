import Foundation

struct AIChatTurn: Identifiable, Hashable {
    let id: UUID
    let role: String
    let content: String
    let attachments: [AIChatAttachment]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: String,
        content: String,
        attachments: [AIChatAttachment] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
        self.createdAt = createdAt
    }
}

struct AIChatResponse {
    let text: String
    let reasoningSummary: String
    let sources: [AIChatSource]

    init(text: String, reasoningSummary: String = "", sources: [AIChatSource] = []) {
        self.text = text
        self.reasoningSummary = reasoningSummary
        self.sources = sources
    }
}

enum AIProviderError: LocalizedError {
    case invalidURL
    case missingAPIKey
    case invalidResponse
    case http(Int, String)
    case emptyResponse
    case unsupportedModelCatalogue
    case interrupted

    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "服务商地址无效。"
        case .missingAPIKey: return "请先配置 API Key。"
        case .invalidResponse: return "服务商返回了无法识别的结果。"
        case .http(let status, let message):
            let suffix = message.isEmpty ? "" : "：\(message)"
            return "服务商请求失败（\(status)）\(suffix)"
        case .emptyResponse: return "服务商没有返回文字内容。"
        case .unsupportedModelCatalogue: return "该服务商暂不提供标准模型目录。"
        case .interrupted: return "回复未完整接收，已保留收到的内容。"
        }
    }
}

@MainActor
enum AIProviderClient {
    private static let recordJSONSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "properties": [
            "intent": ["type": "string", "enum": ["record", "query", "chat"]],
            "entries": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "properties": [
                        "amount": ["type": "number"],
                        "kind": ["type": "string", "enum": ["expense", "income"]],
                        "categoryKey": ["type": "string"],
                        "date": ["type": "string"],
                        "note": ["type": "string"],
                        "confidence": ["type": "number"],
                    ],
                    "required": ["amount", "kind", "categoryKey", "date", "note", "confidence"],
                ],
            ],
        ],
        "required": ["intent", "entries"],
    ]

    static func stream(
        account: AIProviderAccount,
        secret: String,
        messages: [AIChatTurn],
        onText: @escaping (String) -> Void,
        onReasoning: ((String) -> Void)? = nil,
        onSources: (([AIChatSource]) -> Void)? = nil,
        structuredRecord: Bool = false,
        session: URLSession = .shared
    ) async throws -> AIChatResponse {
        let key = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIProviderError.missingAPIKey }

        var preparedMessages: [AIChatTurn] = []
        for turn in messages {
            try Task.checkCancellation()
            var prepared: [AIChatAttachment] = []
            for attachment in turn.attachments {
                prepared.append(try await AIImagePreparation.shared.prepare(attachment))
            }
            preparedMessages.append(AIChatTurn(id: turn.id, role: turn.role,
                content: turn.content, attachments: prepared, createdAt: turn.createdAt))
        }
        try Task.checkCancellation()
        var request = try makeRequest(
            account: account,
            secret: key,
            messages: preparedMessages,
            structuredRecord: structuredRecord
        )
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIProviderError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            var errorBytes = Data()
            for try await byte in bytes.prefix(2048) {
                errorBytes.append(byte)
            }
            throw AIProviderError.http(http.statusCode,
                bodySnippet(String(decoding: errorBytes, as: UTF8.self)))
        }

        var output = ""
        var reasoning = AIStreamSummaryBuffer()
        var sourcesByURL: [String: AIChatSource] = [:]
        var completedText = ""
        var streamCompleted = false
        var anthropicStopReason: String?
        var frames = AISSEFrameDecoder()
        func receive(_ frame: AISSEFrameDecoder.Frame) throws {
            let payload = frame.data.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !payload.isEmpty else { return }
            if payload == "[DONE]" {
                guard !account.usesResponses && !account.usesAnthropicMessages else {
                    throw AIProviderError.interrupted
                }
                streamCompleted = true
                return
            }
            guard let data = payload.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AIProviderError.invalidResponse
            }
            let type = object["type"] as? String ?? frame.event
            if ["response.failed", "response.incomplete", "error"].contains(type)
                || (object["error"] != nil && !(object["error"] is NSNull)) {
                throw AIProviderError.interrupted
            }
            if let event = event(from: payload, account: account) {
                if !event.reasoning.isEmpty {
                    let accepted = reasoning.append(event.reasoning)
                    if !accepted.isEmpty { onReasoning?(accepted) }
                }
                if !event.sources.isEmpty {
                    for source in event.sources { sourcesByURL[source.url] = source }
                    onSources?(Array(sourcesByURL.values).sorted { $0.url < $1.url })
                }
                if !event.completedText.isEmpty { completedText = event.completedText }
                if let delta = event.text, !delta.isEmpty {
                    output += delta
                    onText(delta)
                }
            } else if let delta = delta(from: payload, account: account), !delta.isEmpty {
                output += delta
                onText(delta)
            }
            if account.usesResponses && type == "response.completed" {
                let response = object["response"] as? [String: Any]
                if let status = response?["status"] as? String, status != "completed" {
                    throw AIProviderError.interrupted
                }
                streamCompleted = true
            } else if account.usesAnthropicMessages {
                if type == "message_delta",
                   let delta = object["delta"] as? [String: Any],
                   let reason = delta["stop_reason"] as? String {
                    anthropicStopReason = reason
                }
                if type == "message_stop" {
                    guard let reason = anthropicStopReason,
                          ["end_turn", "stop_sequence", "refusal"].contains(reason) else {
                        throw AIProviderError.interrupted
                    }
                    streamCompleted = true
                }
            } else if let choices = object["choices"] as? [[String: Any]],
                      let reason = choices.first?["finish_reason"] as? String, !reason.isEmpty {
                guard reason == "stop" || reason == "end_turn" else { throw AIProviderError.interrupted }
                streamCompleted = true
            }
        }
        for try await byte in bytes {
            if let frame = try frames.append(byte) {
                try Task.checkCancellation()
                try receive(frame)
                if streamCompleted { break }
            }
        }

        try Task.checkCancellation()
        guard streamCompleted else { throw AIProviderError.interrupted }
        if !completedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Final server text is authoritative, even when it corrects deltas.
            let hadOutput = !output.isEmpty
            output = completedText
            if !hadOutput { onText(completedText) }
        }
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AIProviderError.emptyResponse
        }
        return AIChatResponse(
            text: output,
            reasoningSummary: reasoning.text,
            sources: Array(sourcesByURL.values).sorted { $0.url < $1.url }
        )
    }

    static func fetchModels(account: AIProviderAccount, secret: String) async throws -> [String] {
        guard !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIProviderError.missingAPIKey
        }
        guard !account.usesAnthropicMessages else { throw AIProviderError.unsupportedModelCatalogue }

        var request = try makeRequest(account: account, secret: secret, messages: [], method: "GET", modelsRequest: true)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIProviderError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIProviderError.http(http.statusCode, bodySnippet(String(data: data, encoding: .utf8) ?? ""))
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            throw AIProviderError.invalidResponse
        }
        let rawRows: [Any]
        if let object = object as? [String: Any] {
            rawRows = (object["data"] as? [Any]) ?? (object["models"] as? [Any]) ?? []
        } else if let rows = object as? [Any] {
            rawRows = rows
        } else {
            rawRows = []
        }
        let models = rawRows.compactMap { row -> String? in
            if let value = row as? String { return value }
            guard let row = row as? [String: Any] else { return nil }
            let visibility = (row["visibility"] as? String)?.lowercased()
            guard visibility != "hide", visibility != "hidden", visibility != "none" else { return nil }
            return (row["id"] as? String) ?? (row["slug"] as? String) ?? (row["name"] as? String)
        }
        guard !models.isEmpty else { throw AIProviderError.invalidResponse }
        return Array(Set(models)).sorted()
    }

    static func testConnection(account: AIProviderAccount, secret: String) async throws -> String {
        var result = ""
        _ = try await stream(
            account: account,
            secret: secret,
            messages: [AIChatTurn(role: "user", content: "请只回复 OK")],
            onText: { result += $0 }
        )
        return result
    }

    private static func makeRequest(
        account: AIProviderAccount,
        secret: String,
        messages: [AIChatTurn],
        method: String = "POST",
        modelsRequest: Bool = false,
        structuredRecord: Bool = false
    ) throws -> URLRequest {
        guard let url = try endpointURL(for: account, modelsRequest: modelsRequest) else {
            throw AIProviderError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if account.usesAnthropicMessages {
            request.setValue(secret, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            if account.authMethod == .oauth {
                if !account.oauthAccountID.isEmpty {
                    request.setValue(account.oauthAccountID, forHTTPHeaderField: "ChatGPT-Account-Id")
                }
                request.setValue("codex_vscode", forHTTPHeaderField: "originator")
                request.setValue("codex_vscode/0.146.0", forHTTPHeaderField: "User-Agent")
                request.setValue("responses=v1", forHTTPHeaderField: "OpenAI-Beta")
            }
        }

        guard method == "POST" else { return request }
        request.httpBody = try JSONSerialization.data(
            withJSONObject: requestBody(
                account: account,
                messages: messages,
                structuredRecord: structuredRecord
            )
        )
        return request
    }

    private static func requestBody(
        account: AIProviderAccount,
        messages: [AIChatTurn],
        structuredRecord: Bool = false
    ) -> [String: Any] {
        if account.usesAnthropicMessages {
            let system = messages.filter { $0.role == "system" }.map(\.content).joined(separator: "\n\n")
            let turns = messages.filter { $0.role != "system" }.map {
                [
                    "role": $0.role == "assistant" ? "assistant" : "user",
                    "content": anthropicContent(for: $0),
                ] as [String: Any]
            }
            var body: [String: Any] = [
                "model": account.model,
                "max_tokens": account.effort.claudeBudgetTokens.map { max(4096, $0 + 4096) } ?? 4096,
                "messages": turns,
                "stream": true,
            ]
            if !system.isEmpty { body["system"] = system }
            if let budgetTokens = account.effort.claudeBudgetTokens {
                body["thinking"] = ["type": "enabled", "budget_tokens": budgetTokens]
                body["temperature"] = 1
            }
            return body
        }

        if account.usesResponses {
            let system = messages.filter { $0.role == "system" }.map(\.content).joined(separator: "\n\n")
            let input = messages.filter { $0.role != "system" }.map {
                [
                    "type": "message",
                    "role": $0.role == "assistant" ? "assistant" : "user",
                    "content": responsesContent(for: $0),
                ] as [String: Any]
            }
            var body: [String: Any] = [
                "model": account.model,
                "instructions": system.isEmpty ? "你是肥喵记账的亲切助手。" : system,
                "input": input,
                "stream": true,
                "store": false,
                "max_output_tokens": account.effort.maxOutputTokens,
            ]
            if structuredRecord {
                body["text"] = [
                    "format": [
                        "type": "json_schema",
                        "name": "feimiao_record",
                        "strict": true,
                        "schema": recordJSONSchema,
                    ]
                ]
            }
            let effortValue: String? = account.authMethod == .oauth
                ? (account.effort == .max || account.effort == .ultra ? "max" : account.effort.responsesValue)
                : account.effort.responsesValue
            if let effort = effortValue {
                body["reasoning"] = ["effort": effort, "summary": "auto"]
            }
            if account.webSearchEnabled {
                if account.authMethod == .oauth {
                    body["tools"] = [[
                        "type": "web_search",
                        "external_web_access": true,
                        "search_context_size": "high",
                    ]]
                } else {
                    body["tools"] = [["type": "web_search_preview"]]
                }
            }
            return body
        }

        var body: [String: Any] = [
            "model": account.model,
            "messages": messages.map {
                ["role": $0.role, "content": openAIContent(for: $0)] as [String: Any]
            },
            "stream": true,
        ]
        if account.type == .deepSeek && account.effort != .none {
            body["thinking"] = ["type": "enabled"]
            body["reasoning_effort"] = account.effort == .max || account.effort == .extra || account.effort == .ultra ? "max" : "high"
        }
        if structuredRecord {
            // OpenAI-compatible providers generally support json_object. The
            // full schema is also sent for gateways that implement the same
            // extension used by the Android parser.
            body["response_format"] = ["type": "json_object"]
            body["response_schema"] = recordJSONSchema
        }
        return body
    }

    /// OpenAI-compatible gateways accept a text string for ordinary turns and
    /// a content-part array when an image or file is attached.
    private static func openAIContent(for turn: AIChatTurn) -> Any {
        guard !turn.attachments.isEmpty else { return turn.content }
        var parts: [[String: Any]] = []
        if !turn.content.isEmpty {
            parts.append(["type": "text", "text": turn.content])
        }
        for attachment in turn.attachments {
            guard let uri = dataURI(for: attachment) else {
                parts.append(["type": "text", "text": "[附件读取失败：\(attachment.name)]"])
                continue
            }
            if attachment.isImage {
                parts.append(["type": "image_url", "image_url": ["url": uri]])
            } else {
                parts.append([
                    "type": "file",
                    "file": [
                        "filename": attachment.name,
                        "file_data": uri,
                    ],
                ])
            }
        }
        return parts.isEmpty ? turn.content : parts
    }

    private static func responsesContent(for turn: AIChatTurn) -> [[String: Any]] {
        guard !turn.attachments.isEmpty else {
            return [[
                "type": turn.role == "assistant" ? "output_text" : "input_text",
                "text": turn.content,
            ]]
        }
        var parts: [[String: Any]] = []
        if !turn.content.isEmpty {
            parts.append([
                "type": turn.role == "assistant" ? "output_text" : "input_text",
                "text": turn.content,
            ])
        }
        for attachment in turn.attachments {
            guard let uri = dataURI(for: attachment) else {
                parts.append(["type": "input_text", "text": "[附件读取失败：\(attachment.name)]"])
                continue
            }
            if attachment.isImage {
                parts.append(["type": "input_image", "image_url": uri])
            } else {
                parts.append([
                    "type": "input_file",
                    "filename": attachment.name,
                    "file_data": uri,
                ])
            }
        }
        return parts
    }

    private static func anthropicContent(for turn: AIChatTurn) -> Any {
        guard !turn.attachments.isEmpty else { return turn.content }
        var parts: [[String: Any]] = []
        if !turn.content.isEmpty {
            parts.append(["type": "text", "text": turn.content])
        }
        for attachment in turn.attachments {
            guard let data = attachment.data() else {
                parts.append(["type": "text", "text": "[附件读取失败：\(attachment.name)]"])
                continue
            }
            let encoded = data.base64EncodedString()
            if attachment.isImage {
                parts.append([
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": attachment.mimeType,
                        "data": encoded,
                    ],
                ])
            } else if attachment.mimeType.lowercased() == "application/pdf" {
                parts.append([
                    "type": "document",
                    "source": [
                        "type": "base64",
                        "media_type": attachment.mimeType,
                        "data": encoded,
                    ],
                ])
            } else {
                parts.append(["type": "text", "text": "[文件附件：\(attachment.name)]\n\(encoded)"])
            }
        }
        return parts.isEmpty ? turn.content : parts
    }

    private static func dataURI(for attachment: AIChatAttachment) -> String? {
        guard let data = attachment.data(), !data.isEmpty else { return nil }
        return "data:\(attachment.mimeType);base64,\(data.base64EncodedString())"
    }

    private static func endpointURL(for account: AIProviderAccount, modelsRequest: Bool) throws -> URL? {
        if account.authMethod == .oauth {
            if modelsRequest {
                return URL(string: "\(OpenAIOAuth.codexModelsURL.absoluteString)")
            }
            return OpenAIOAuth.codexResponsesURL
        }
        var raw = account.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { raw = account.type.defaultBaseURL }
        guard var components = URLComponents(string: raw),
              let scheme = components.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              components.host != nil else { return nil }

        let originalPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let rootPath = stripKnownEndpoint(from: originalPath)
        var path: String
        if modelsRequest {
            path = joinEndpoint(rootPath, suffix: "models")
        } else if account.usesAnthropicMessages {
            path = joinEndpoint(rootPath, suffix: "messages")
        } else if account.usesResponses {
            path = joinEndpoint(rootPath, suffix: "responses")
        } else {
            path = joinEndpoint(rootPath, suffix: "chat/completions")
        }
        if path.hasPrefix("/") { path.removeFirst() }
        components.path = "/\(path)"
        components.query = nil
        return components.url
    }

    private struct StreamEvent {
        let text: String?
        let reasoning: String
        let sources: [AIChatSource]
        let completedText: String
    }

    private static func event(from payload: String, account: AIProviderAccount) -> StreamEvent? {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        if account.usesResponses {
            let type = (object["type"] as? String)?.lowercased() ?? ""
            let terminal = type.hasSuffix(".done") || type.contains("completed")
            let text: String? = {
                guard !terminal else { return nil }
                guard type == "response.output_text.delta" || type.isEmpty else { return nil }
                if let value = object["delta"] as? String,
                   type.contains("output_text") || type.contains("content_part") || type.isEmpty {
                    return value
                }
                return object["text"] as? String
            }()
            let reasoning: String = {
                guard type == "response.reasoning_summary_text.delta" else { return "" }
                if let value = object["delta"] as? String { return value }
                if let value = object["delta"] as? [String: Any] {
                    return (value["text"] as? String) ?? (value["content"] as? String) ?? ""
                }
                if let value = object["part"] as? [String: Any] {
                    return (value["text"] as? String) ?? (value["content"] as? String) ?? ""
                }
                return ""
            }()
            let completed: String = {
                guard type == "response.completed", let response = object["response"] as? [String: Any] else { return "" }
                return completedResponseText(response)
            }()
            return StreamEvent(
                text: text,
                reasoning: reasoning,
                sources: extractSources(from: object),
                completedText: completed
            )
        }
        if account.usesAnthropicMessages {
            let delta = object["delta"] as? [String: Any]
            let type = (delta?["type"] as? String)?.lowercased() ?? ""
            let thinking = type == "thinking_delta" ? (delta?["thinking"] as? String ?? "") : ""
            let text = type == "text_delta" ? delta?["text"] as? String : nil
            return StreamEvent(text: text, reasoning: thinking, sources: [], completedText: "")
        }
        guard let choices = object["choices"] as? [[String: Any]],
              let first = choices.first,
              let delta = first["delta"] as? [String: Any] else { return nil }
        return StreamEvent(
            text: delta["content"] as? String,
            // Compatibility fields do not prove this is a public summary.
            reasoning: "",
            sources: [],
            completedText: ""
        )
    }

    private static func delta(from payload: String, account: AIProviderAccount) -> String? {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if account.usesResponses {
            return object["delta"] as? String
        }
        if account.usesAnthropicMessages {
            return (object["delta"] as? [String: Any])?["text"] as? String
        }
        return ((object["choices"] as? [[String: Any]])?.first?["delta"] as? [String: Any])?["content"] as? String
    }

    private static func completedResponseText(_ response: [String: Any]) -> String {
        if let direct = response["output_text"] as? String, !direct.isEmpty { return direct }
        var parts: [String] = []
        func walk(_ value: Any?) {
            if let map = value as? [String: Any] {
                let type = (map["type"] as? String)?.lowercased() ?? ""
                if (type == "output_text" || type == "text"), let text = map["text"] as? String, !text.isEmpty {
                    parts.append(text)
                }
                walk(map["output"])
                walk(map["content"])
            } else if let list = value as? [Any] {
                list.forEach(walk)
            }
        }
        walk(response["output"])
        return parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractSources(from root: Any) -> [AIChatSource] {
        var result: [AIChatSource] = []
        var seen = Set<String>()
        func add(_ value: [String: Any], sourceContext: Bool) {
            let type = (value["type"] as? String)?.lowercased() ?? ""
            let citation = type.contains("url_citation") || type == "source" || type == "web_search_source"
            guard sourceContext || citation else { return }
            let url = ((value["url"] as? String) ?? (value["uri"] as? String) ?? (value["link"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard url.hasPrefix("http"), seen.insert(url).inserted else { return }
            let title = ((value["title"] as? String) ?? (value["name"] as? String) ?? (value["source_name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = ((value["snippet"] as? String) ?? (value["text"] as? String) ?? (value["description"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(AIChatSource(title: title.isEmpty ? URL(string: url)?.host ?? "网页来源" : title, url: url, snippet: snippet))
        }
        func walk(_ value: Any?, sourceContext: Bool = false) {
            if let map = value as? [String: Any] {
                let type = (map["type"] as? String)?.lowercased() ?? ""
                let isSearch = type.contains("web_search")
                add(map, sourceContext: sourceContext || isSearch)
                for key in ["annotations", "sources", "results", "action", "response", "output", "content", "item", "data"] {
                    walk(map[key], sourceContext: sourceContext || key == "annotations" || key == "sources" || key == "results" || key == "action")
                }
            } else if let list = value as? [Any] {
                list.forEach { walk($0, sourceContext: sourceContext) }
            }
        }
        walk(root)
        return result
    }

    static func endpointURLForTesting(account: AIProviderAccount, modelsRequest: Bool = false) -> URL? {
        try? endpointURL(for: account, modelsRequest: modelsRequest)
    }

    static func publicSummaryForTesting(payload: String, account: AIProviderAccount) -> String {
        event(from: payload, account: account)?.reasoning ?? ""
    }

    static func requestBodyForTesting(
        account: AIProviderAccount,
        messages: [AIChatTurn],
        structuredRecord: Bool = false
    ) -> [String: Any] {
        requestBody(account: account, messages: messages, structuredRecord: structuredRecord)
    }

    static func requestForTesting(
        account: AIProviderAccount,
        secret: String,
        messages: [AIChatTurn],
        method: String = "POST",
        modelsRequest: Bool = false
    ) -> URLRequest? {
        try? makeRequest(
            account: account,
            secret: secret,
            messages: messages,
            method: method,
            modelsRequest: modelsRequest
        )
    }

    private static func stripKnownEndpoint(from path: String) -> String {
        let known = ["chat/completions", "responses", "messages", "models"]
        for suffix in known {
            if path == suffix { return "" }
            if path.hasSuffix("/\(suffix)") {
                return String(path.dropLast(suffix.count + 1))
            }
        }
        return path
    }

    private static func joinEndpoint(_ root: String, suffix: String) -> String {
        var normalized = root.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalized.isEmpty { normalized = "v1" }
        if !normalized.hasSuffix("v1") { normalized += "/v1" }
        return "\(normalized)/\(suffix)"
    }

    private static func bodySnippet(_ body: String) -> String {
        let compact = body.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.count > 240 ? String(compact.prefix(240)) + "…" : compact
    }
}

private struct AISSEFrameDecoder {
    struct Frame {
        let event: String
        let data: String
    }
    private var event = ""
    private var lines: [String] = []
    private var byteCount = 0
    private var lineBytes = Data()
    private var afterCarriageReturn = false
    private var firstLine = true

    mutating func append(_ byte: UInt8) throws -> Frame? {
        if afterCarriageReturn && byte == 10 {
            afterCarriageReturn = false
            return nil
        }
        afterCarriageReturn = byte == 13
        guard byte == 10 || byte == 13 else {
            lineBytes.append(byte)
            guard lineBytes.count <= 1024 * 1024 else { throw AIProviderError.invalidResponse }
            return nil
        }
        guard var line = String(data: lineBytes, encoding: .utf8) else { throw AIProviderError.invalidResponse }
        lineBytes.removeAll(keepingCapacity: true)
        if firstLine {
            if line.hasPrefix("\u{FEFF}") { line.removeFirst() }
            firstLine = false
        }
        return try appendLine(line)
    }

    private mutating func appendLine(_ line: String) throws -> Frame? {
        if line.isEmpty {
            let frame = lines.isEmpty ? nil : Frame(event: event, data: lines.joined(separator: "\n"))
            event = ""
            lines.removeAll(keepingCapacity: true)
            byteCount = 0
            return frame
        }
        if line.hasPrefix("event:") {
            event = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if line == "data" || line.hasPrefix("data:") {
            var value = line == "data" ? "" : String(line.dropFirst(5))
            if value.hasPrefix(" ") { value.removeFirst() }
            byteCount += value.utf8.count + 1
            guard byteCount <= 1024 * 1024 else { throw AIProviderError.invalidResponse }
            lines.append(value)
        }
        return nil
    }
}
