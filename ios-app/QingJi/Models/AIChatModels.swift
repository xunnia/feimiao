import Foundation
import SwiftData

struct AIChatSource: Identifiable, Codable, Hashable, Sendable {
    let title: String
    let url: String
    let snippet: String

    var id: String { url }
}

/// Persisted conversation metadata. Credentials are deliberately unrelated to
/// this model and stay in the Keychain-backed provider store.
@Model
final class AIChatSession {
    var stableID: UUID = UUID()
    var title: String = "新对话"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isStarred: Bool = false
    var isRecord: Bool = false
    var providerID: UUID? = nil
    var model: String = ""
    var effortRaw: String = AIReasoningEffort.low.rawValue

    init(
        stableID: UUID = UUID(),
        title: String = "新对话",
        isRecord: Bool = false,
        providerID: UUID? = nil,
        model: String = "",
        effort: AIReasoningEffort = .low
    ) {
        self.stableID = stableID
        self.title = title
        self.isRecord = isRecord
        self.providerID = providerID
        self.model = model
        self.effortRaw = effort.rawValue
    }

    var effort: AIReasoningEffort {
        get { AIReasoningEffort(rawValue: effortRaw) ?? .low }
        set { effortRaw = newValue.rawValue }
    }
}

@Model
final class AIChatMessage {
    var stableID: UUID = UUID()
    var sessionID: UUID = UUID()
    var role: String = "user"
    var content: String = ""
    var createdAt: Date = Date()
    var reasoningSummary: String = ""
    var sourceJSON: String = ""
    var attachmentsJSON: String = "[]"
    /// 固定“记一记”会话的结构化记账卡。普通文本消息为空。
    var recordJSON: String = ""
    var isError: Bool = false

    init(
        stableID: UUID = UUID(),
        sessionID: UUID,
        role: String,
        content: String,
        createdAt: Date = Date(),
        reasoningSummary: String = "",
        sourceJSON: String = "",
        attachmentsJSON: String = "[]",
        recordJSON: String = "",
        isError: Bool = false
    ) {
        self.stableID = stableID
        self.sessionID = sessionID
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.reasoningSummary = reasoningSummary
        self.sourceJSON = sourceJSON
        self.attachmentsJSON = attachmentsJSON
        self.recordJSON = recordJSON
        self.isError = isError
    }
}
