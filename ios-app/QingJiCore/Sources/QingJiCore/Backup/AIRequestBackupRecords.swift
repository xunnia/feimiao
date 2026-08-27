import Foundation

/// AI 运行记录只保存可审计的阶段和摘要，不保存完整提示词、密钥或原始思考内容。
public struct BackupAIRequestRun: Codable, Equatable, Sendable {
    public var id: UUID
    public var sessionID: UUID?
    public var modeRaw: String
    public var statusRaw: String
    public var providerID: UUID?
    public var providerLabel: String
    public var model: String
    public var effortRaw: String
    public var endpointRaw: String
    public var inputCharacters: Int
    public var attachmentCount: Int
    public var resultSummary: String
    public var errorMessage: String
    public var createdAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?
    public var updatedAt: Date

    public init(
        id: UUID,
        sessionID: UUID? = nil,
        modeRaw: String,
        statusRaw: String,
        providerID: UUID? = nil,
        providerLabel: String = "",
        model: String = "",
        effortRaw: String = "",
        endpointRaw: String = "",
        inputCharacters: Int = 0,
        attachmentCount: Int = 0,
        resultSummary: String = "",
        errorMessage: String = "",
        createdAt: Date = .now,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.sessionID = sessionID
        self.modeRaw = modeRaw
        self.statusRaw = statusRaw
        self.providerID = providerID
        self.providerLabel = providerLabel
        self.model = model
        self.effortRaw = effortRaw
        self.endpointRaw = endpointRaw
        self.inputCharacters = max(inputCharacters, 0)
        self.attachmentCount = max(attachmentCount, 0)
        self.resultSummary = resultSummary
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.updatedAt = updatedAt
    }
}

public struct BackupAIRequestEvent: Codable, Equatable, Sendable {
    public var id: UUID
    public var runID: UUID
    public var sequence: Int
    public var typeRaw: String
    public var summary: String
    public var count: Int
    public var createdAt: Date

    public init(
        id: UUID,
        runID: UUID,
        sequence: Int,
        typeRaw: String,
        summary: String = "",
        count: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.runID = runID
        self.sequence = sequence
        self.typeRaw = typeRaw
        self.summary = summary
        self.count = max(count, 0)
        self.createdAt = createdAt
    }
}

public struct BackupAIReportSchedule: Codable, Equatable, Sendable {
    public var id: UUID
    public var sessionID: UUID?
    public var title: String
    public var reportType: String
    public var periodKind: String
    public var dayValue: Int
    public var enabled: Bool
    public var nextRunAt: Date
    public var providerID: UUID?
    public var model: String
    public var effortRaw: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        sessionID: UUID? = nil,
        title: String,
        reportType: String = "monthly",
        periodKind: String = "monthly",
        dayValue: Int = 1,
        enabled: Bool = true,
        nextRunAt: Date,
        providerID: UUID? = nil,
        model: String = "",
        effortRaw: String = "low",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.sessionID = sessionID
        self.title = title
        self.reportType = reportType
        self.periodKind = periodKind
        self.dayValue = dayValue
        self.enabled = enabled
        self.nextRunAt = nextRunAt
        self.providerID = providerID
        self.model = model
        self.effortRaw = effortRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
