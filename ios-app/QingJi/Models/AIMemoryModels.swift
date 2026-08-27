import Foundation
import SwiftData

/// 用户明确授权后保存的 AI 记忆。原始内容只保存在本机 SwiftData；
/// 备份和请求上下文由上层按授权边界处理。
@Model
final class AIMemoryRecord {
    var stableID: UUID = UUID()
    var phrase: String = ""
    var content: String = ""
    var source: String = "user"
    var sessionID: UUID? = nil
    var consent: Bool = false
    var statusRaw: String = "active"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastUsedAt: Date? = nil

    init(
        stableID: UUID = UUID(),
        phrase: String,
        content: String,
        source: String = "user",
        sessionID: UUID? = nil,
        consent: Bool = false
    ) {
        self.stableID = stableID
        self.phrase = phrase
        self.content = content
        self.source = source
        self.sessionID = sessionID
        self.consent = consent
    }

    var isActive: Bool { statusRaw == "active" && consent }
}

enum AIMemoryStore {
    enum Error: LocalizedError, Equatable {
        case emptyPhrase
        case emptyContent

        var errorDescription: String? {
            switch self {
            case .emptyPhrase: return "触发短语不能为空。"
            case .emptyContent: return "记忆内容不能为空。"
            }
        }
    }

    static func all(in context: ModelContext) throws -> [AIMemoryRecord] {
        try context.fetch(FetchDescriptor<AIMemoryRecord>(sortBy: [
            SortDescriptor(\AIMemoryRecord.updatedAt, order: .reverse)
        ]))
    }

    @discardableResult
    static func add(
        phrase: String,
        content: String,
        consent: Bool = true,
        in context: ModelContext
    ) throws -> AIMemoryRecord {
        let cleanPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPhrase.isEmpty else { throw Error.emptyPhrase }
        guard !cleanContent.isEmpty else { throw Error.emptyContent }
        let memory = AIMemoryRecord(
            phrase: cleanPhrase,
            content: cleanContent,
            consent: consent
        )
        context.insert(memory)
        try context.save()
        return memory
    }

    static func delete(_ memory: AIMemoryRecord, in context: ModelContext) throws {
        context.delete(memory)
        try context.save()
    }

    static func forgetAll(in context: ModelContext) throws {
        let items = try all(in: context)
        items.forEach(context.delete)
        try context.save()
    }

    static func promptBlock(
        memories: [AIMemoryRecord],
        query: String,
        limit: Int = 10
    ) -> String {
        let value = query.lowercased()
        let selected = memories
            .filter { $0.isActive }
            .filter {
                value.isEmpty ||
                value.contains($0.phrase.lowercased()) ||
                $0.phrase.lowercased().contains(value)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(max(limit, 0))
        guard !selected.isEmpty else { return "" }
        return selected.map { "- \($0.content)" }.joined(separator: "\n")
    }

    static func markUsed(_ memories: [AIMemoryRecord], query: String, in context: ModelContext) {
        let value = query.lowercased()
        var changed = false
        for memory in memories where memory.isActive {
            let phrase = memory.phrase.lowercased()
            guard value.contains(phrase) || phrase.contains(value) else { continue }
            memory.lastUsedAt = Date()
            memory.updatedAt = Date()
            changed = true
        }
        if changed { try? context.save() }
    }
}
