import Foundation

enum AIProviderVerificationStatus: String, Codable, CaseIterable, Hashable, Identifiable {
    case available
    case needsProxy = "needs_proxy"
    case invalidCredential = "invalid_credential"
    case modelUnavailable = "model_unavailable"
    case networkError = "network_error"
    case configurationError = "configuration_error"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .available: return "可用"
        case .needsProxy: return "需要代理/VPN"
        case .invalidCredential: return "凭据失效"
        case .modelUnavailable: return "模型不可用"
        case .networkError: return "网络失败"
        case .configurationError: return "配置不完整"
        }
    }

    static func from(rawValue: String) -> Self? {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = Self(rawValue: normalized) { return exact }
        switch normalized {
        case "needsProxy": return .needsProxy
        case "invalidCredential": return .invalidCredential
        case "modelUnavailable": return .modelUnavailable
        case "networkError": return .networkError
        case "configurationError": return .configurationError
        default: return nil
        }
    }

    /// Maps transport failures to the same actionable states shown by Android.
    static func from(error: Error) -> Self {
        let text = "\(error.localizedDescription) \(error)".lowercased()
        if text.contains("unsupported_country") ||
            text.contains("unsupported country") ||
            text.contains("country, region") ||
            text.contains("proxy") ||
            text.contains("vpn") {
            return .needsProxy
        }

        if let providerError = error as? AIProviderError {
            switch providerError {
            case .invalidURL, .missingAPIKey:
                return .configurationError
            case .emptyResponse, .unsupportedModelCatalogue:
                return .modelUnavailable
            case .http(let status, let message):
                let lowerMessage = message.lowercased()
                if lowerMessage.contains("unsupported_country") ||
                    lowerMessage.contains("unsupported country") {
                    return .needsProxy
                }
                if lowerMessage.contains("invalid_token") ||
                    lowerMessage.contains("invalid token") ||
                    lowerMessage.contains("invalid_grant") ||
                    lowerMessage.contains("token expired") {
                    return .invalidCredential
                }
                if status == 401 || status == 403 { return .invalidCredential }
                if status == 400 || status == 404 || lowerMessage.contains("model") {
                    return .modelUnavailable
                }
            case .invalidResponse:
                break
            }
        }

        if let oauthError = error as? OpenAIOAuthError {
            switch oauthError {
            case .http(let status, let body):
                let lowerBody = body.lowercased()
                if lowerBody.contains("unsupported_country") ||
                    lowerBody.contains("unsupported country") ||
                    lowerBody.contains("country or region") {
                    return .needsProxy
                }
                if lowerBody.contains("invalid_token") ||
                    lowerBody.contains("invalid token") ||
                    lowerBody.contains("invalid_grant") ||
                    lowerBody.contains("token expired") {
                    return .invalidCredential
                }
                if status == 400 || status == 401 || status == 403 {
                    return .invalidCredential
                }
            case .invalidTokenResponse:
                return .invalidCredential
            case .authorizationFailed(let reason):
                let lowerReason = reason.lowercased()
                if lowerReason.contains("invalid_token") ||
                    lowerReason.contains("invalid token") ||
                    lowerReason.contains("invalid_grant") ||
                    lowerReason.contains("token expired") {
                    return .invalidCredential
                }
            case .invalidCallback, .loopbackUnavailable:
                break
            }
        }

        if let storeError = error as? AIProviderStoreError {
            switch storeError {
            case .missingSecret, .keychain(_):
                return .configurationError
            }
        }

        if text.contains("凭据") || text.contains("credential") || text.contains("unauthorized") {
            return .invalidCredential
        }
        if text.contains("model") || text.contains("模型") {
            return .modelUnavailable
        }
        if (error as NSError).domain == NSURLErrorDomain {
            return .networkError
        }
        return .networkError
    }
}

struct AIProviderVerificationResult: Equatable {
    let status: AIProviderVerificationStatus
    let models: [String]
    let message: String
    let latencyMs: Int

    init(
        status: AIProviderVerificationStatus,
        models: [String] = [],
        message: String = "",
        latencyMs: Int = 0
    ) {
        self.status = status
        self.models = models
        self.message = message
        self.latencyMs = max(0, latencyMs)
    }

    var isAvailable: Bool { status == .available }

    var summary: String {
        let suffix = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.isEmpty ? status.label : "\(status.label)：\(suffix)"
    }
}

struct AIProviderAuthorizationResult {
    let account: AIProviderAccount
    let verification: AIProviderVerificationResult
}

struct AIProviderHealth: Codable, Hashable, Identifiable {
    let providerID: UUID
    var successCount: Int
    var failureCount: Int
    var consecutiveFailures: Int
    var lastSuccessAt: Date?
    var lastFailureAt: Date?
    var cooldownUntil: Date?
    var averageLatencyMs: Int
    var lastError: String
    /// The latest explicit catalogue + minimal-ping verification result.
    var verificationStatus: String
    var updatedAt: Date

    var id: UUID { providerID }

    init(
        providerID: UUID,
        successCount: Int = 0,
        failureCount: Int = 0,
        consecutiveFailures: Int = 0,
        lastSuccessAt: Date? = nil,
        lastFailureAt: Date? = nil,
        cooldownUntil: Date? = nil,
        averageLatencyMs: Int = 0,
        lastError: String = "",
        verificationStatus: String = "",
        updatedAt: Date = Date()
    ) {
        self.providerID = providerID
        self.successCount = max(0, successCount)
        self.failureCount = max(0, failureCount)
        self.consecutiveFailures = max(0, consecutiveFailures)
        self.lastSuccessAt = lastSuccessAt
        self.lastFailureAt = lastFailureAt
        self.cooldownUntil = cooldownUntil
        self.averageLatencyMs = max(0, averageLatencyMs)
        self.lastError = Self.sanitizedError(lastError)
        self.verificationStatus = verificationStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        self.updatedAt = updatedAt
    }

    var isCoolingDown: Bool {
        guard let cooldownUntil else { return false }
        return cooldownUntil > Date()
    }

    var hasRecentFailure: Bool {
        guard let lastFailureAt else { return false }
        return Date().timeIntervalSince(lastFailureAt) < 10 * 60
    }

    var successRate: Double {
        let total = successCount + failureCount
        return total == 0 ? 0 : Double(successCount) / Double(total)
    }

    var statusLabel: String {
        if let status = AIProviderVerificationStatus.from(rawValue: verificationStatus) {
            return status.label
        }
        if !verificationStatus.isEmpty { return verificationStatus }
        if isCoolingDown { return "暂时冷却" }
        if hasRecentFailure { return "最近失败" }
        if successCount == 0 && failureCount == 0 { return "尚未测试" }
        return "可用"
    }

    func recordSuccess(latencyMs: Int, now: Date = Date()) -> Self {
        let latency = max(0, min(latencyMs, 3_600_000))
        let nextCount = successCount + 1
        let nextAverage = averageLatencyMs == 0
            ? latency
            : ((averageLatencyMs * successCount) + latency) / nextCount
        return Self(
            providerID: providerID,
            successCount: nextCount,
            failureCount: failureCount,
            consecutiveFailures: 0,
            lastSuccessAt: now,
            lastFailureAt: lastFailureAt,
            cooldownUntil: nil,
            averageLatencyMs: nextAverage,
            lastError: "",
            verificationStatus: AIProviderVerificationStatus.available.rawValue,
            updatedAt: now
        )
    }

    func recordFailure(_ error: String, now: Date = Date()) -> Self {
        let failures = consecutiveFailures + 1
        let cooldown = failures >= 3
            ? now.addingTimeInterval(2 * 60)
            : nil
        // A normal request failure invalidates a previous success marker, but
        // keeps an explicit verification diagnosis such as invalid credential.
        let nextVerificationStatus = verificationStatus == AIProviderVerificationStatus.available.rawValue
            ? ""
            : verificationStatus
        return Self(
            providerID: providerID,
            successCount: successCount,
            failureCount: failureCount + 1,
            consecutiveFailures: failures,
            lastSuccessAt: lastSuccessAt,
            lastFailureAt: now,
            cooldownUntil: cooldown,
            averageLatencyMs: averageLatencyMs,
            lastError: error,
            verificationStatus: nextVerificationStatus,
            updatedAt: now
        )
    }

    func recordVerification(
        status: AIProviderVerificationStatus,
        message: String,
        latencyMs: Int,
        now: Date = Date()
    ) -> Self {
        if status == .available {
            return recordSuccess(latencyMs: latencyMs, now: now)
        }
        var result = recordFailure(message, now: now)
        result.verificationStatus = status.rawValue
        return result
    }

    static func sanitizedError(_ raw: String) -> String {
        var compact = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        compact = compact.replacingOccurrences(
            of: #"(?i)(bearer\s+)[^\s]+"#,
            with: "$1[redacted]",
            options: .regularExpression
        )
        compact = compact.replacingOccurrences(
            of: #"(?i)((?:api[_ -]?key|access[_ -]?token|refresh[_ -]?token)\s*[:=]\s*)[^\s,;]+"#,
            with: "$1[redacted]",
            options: .regularExpression
        )
        compact = compact.replacingOccurrences(
            of: #"(?i)\b(?:sk|rk|at)-[A-Za-z0-9._-]+\b"#,
            with: "[redacted]",
            options: .regularExpression
        )
        if compact.count > 240 { return String(compact.prefix(237)) + "..." }
        return compact
    }
}
