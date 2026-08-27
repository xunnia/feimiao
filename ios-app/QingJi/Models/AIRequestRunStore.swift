import Foundation
import SwiftData

enum AIRequestMode: String, Codable, CaseIterable, Hashable, Identifiable {
    case record
    case chat
    case query
    case report
    case importBill = "import"
    case scheduledReport = "scheduled_report"
    case localModel = "local_model"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .record: return "AI 记账"
        case .chat: return "喵助手聊天"
        case .query: return "账本查询"
        case .report: return "报告生成"
        case .importBill: return "账单导入"
        case .scheduledReport: return "定时报表"
        case .localModel: return "本地模型"
        }
    }
}

enum AIRequestStatus: String, Codable, CaseIterable, Hashable, Identifiable {
    case queued
    case preparing
    case thinking
    case streaming
    case awaitingConfirmation = "awaiting_confirmation"
    case background
    case completed
    case rolledBack = "rolled_back"
    case failed
    case cancelled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .queued: return "排队中"
        case .preparing: return "准备中"
        case .thinking: return "思考中"
        case .streaming: return "生成中"
        case .awaitingConfirmation: return "等待确认"
        case .background: return "后台处理中"
        case .completed: return "已完成"
        case .rolledBack: return "已撤销"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .rolledBack, .failed, .cancelled:
            return true
        default:
            return false
        }
    }
}

enum AIRequestEventType: String, Codable, CaseIterable, Hashable, Identifiable {
    case started
    case stageChanged = "stage_changed"
    case contextReady = "context_ready"
    case attachmentReady = "attachment_ready"
    case reasoning
    case source
    case proposalReady = "proposal_ready"
    case committed
    case rolledBack = "rolled_back"
    case retry
    case completed
    case failed
    case cancelled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .started: return "任务已创建"
        case .stageChanged: return "阶段更新"
        case .contextReady: return "上下文已准备"
        case .attachmentReady: return "附件已准备"
        case .reasoning: return "思考摘要更新"
        case .source: return "来源更新"
        case .proposalReady: return "记账方案已生成"
        case .committed: return "已写入账本"
        case .rolledBack: return "已撤销"
        case .retry: return "正在重试"
        case .completed: return "任务完成"
        case .failed: return "任务失败"
        case .cancelled: return "任务已取消"
        }
    }
}

@Model
final class AIRequestRunRecord {
    var stableID: UUID = UUID()
    var sessionID: UUID? = nil
    var modeRaw: String = AIRequestMode.chat.rawValue
    var statusRaw: String = AIRequestStatus.queued.rawValue
    var providerID: UUID? = nil
    var providerLabel: String = ""
    var model: String = ""
    var effortRaw: String = ""
    var endpointRaw: String = ""
    var inputCharacters: Int = 0
    var attachmentCount: Int = 0
    var resultSummary: String = ""
    var errorMessage: String = ""
    var createdAt: Date = Date()
    var startedAt: Date? = nil
    var finishedAt: Date? = nil
    var updatedAt: Date = Date()

    init(
        stableID: UUID = UUID(),
        sessionID: UUID? = nil,
        mode: AIRequestMode,
        providerID: UUID? = nil,
        providerLabel: String = "",
        model: String = "",
        effortRaw: String = "",
        endpointRaw: String = "",
        inputCharacters: Int = 0,
        attachmentCount: Int = 0
    ) {
        self.stableID = stableID
        self.sessionID = sessionID
        self.modeRaw = mode.rawValue
        self.providerID = providerID
        self.providerLabel = providerLabel
        self.model = model
        self.effortRaw = effortRaw
        self.endpointRaw = endpointRaw
        self.inputCharacters = max(inputCharacters, 0)
        self.attachmentCount = max(attachmentCount, 0)
    }

    var mode: AIRequestMode {
        get { AIRequestMode(rawValue: modeRaw) ?? .chat }
        set { modeRaw = newValue.rawValue }
    }

    var status: AIRequestStatus {
        get { AIRequestStatus(rawValue: statusRaw) ?? .queued }
        set { statusRaw = newValue.rawValue }
    }
}

@Model
final class AIRequestEventRecord {
    var stableID: UUID = UUID()
    var runID: UUID = UUID()
    var sequence: Int = 0
    var typeRaw: String = AIRequestEventType.stageChanged.rawValue
    var summary: String = ""
    var count: Int = 0
    var createdAt: Date = Date()

    init(
        stableID: UUID = UUID(),
        runID: UUID,
        sequence: Int,
        type: AIRequestEventType,
        summary: String = "",
        count: Int = 0,
        createdAt: Date = Date()
    ) {
        self.stableID = stableID
        self.runID = runID
        self.sequence = sequence
        self.typeRaw = type.rawValue
        self.summary = summary
        self.count = max(count, 0)
        self.createdAt = createdAt
    }

    var type: AIRequestEventType {
        get { AIRequestEventType(rawValue: typeRaw) ?? .stageChanged }
        set { typeRaw = newValue.rawValue }
    }
}

@MainActor
enum AIRequestRunStore {
    @discardableResult
    static func start(
        mode: AIRequestMode,
        account: AIProviderAccount,
        sessionID: UUID?,
        inputCharacters: Int,
        attachmentCount: Int,
        in context: ModelContext
    ) -> UUID? {
        let run = AIRequestRunRecord(
            sessionID: sessionID,
            mode: mode,
            providerID: account.id,
            providerLabel: account.displayName,
            model: account.model,
            effortRaw: account.effort.rawValue,
            endpointRaw: account.endpoint.rawValue,
            inputCharacters: inputCharacters,
            attachmentCount: attachmentCount
        )
        context.insert(run)
        do {
            try context.save()
            append(.started, runID: run.stableID, summary: mode.label, in: context)
            return run.stableID
        } catch {
            context.delete(run)
            return nil
        }
    }

    static func setStatus(
        _ runID: UUID?,
        _ status: AIRequestStatus,
        summary: String = "",
        errorMessage: String = "",
        in context: ModelContext
    ) {
        guard let runID,
              let run = (try? context.fetch(FetchDescriptor<AIRequestRunRecord>()))?
                .first(where: { $0.stableID == runID }) else { return }
        run.status = status
        run.updatedAt = Date()
        if !summary.isEmpty { run.resultSummary = summary }
        if !errorMessage.isEmpty { run.errorMessage = errorMessage }
        if status == .thinking || status == .streaming {
            run.startedAt = run.startedAt ?? Date()
        }
        if status.isTerminal { run.finishedAt = Date() }
        try? context.save()
    }

    static func append(
        _ type: AIRequestEventType,
        runID: UUID?,
        summary: String = "",
        count: Int = 0,
        in context: ModelContext
    ) {
        guard let runID else { return }
        let existing = (try? context.fetch(FetchDescriptor<AIRequestEventRecord>()))?
            .filter { $0.runID == runID }
            .map(\.sequence)
            .max() ?? -1
        context.insert(AIRequestEventRecord(
            runID: runID,
            sequence: existing + 1,
            type: type,
            summary: summary,
            count: count
        ))
        try? context.save()
    }

    static func runs(in context: ModelContext) -> [AIRequestRunRecord] {
        (try? context.fetch(FetchDescriptor<AIRequestRunRecord>(sortBy: [
            SortDescriptor(\AIRequestRunRecord.updatedAt, order: .reverse)
        ]))) ?? []
    }

    static func events(for runID: UUID, in context: ModelContext) -> [AIRequestEventRecord] {
        ((try? context.fetch(FetchDescriptor<AIRequestEventRecord>(sortBy: [
            SortDescriptor(\AIRequestEventRecord.sequence)
        ]))) ?? []).filter { $0.runID == runID }
    }
}
