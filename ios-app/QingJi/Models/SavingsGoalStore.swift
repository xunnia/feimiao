import Foundation
import SwiftData
import QingJiCore

/// 存钱目标的持久化边界。目标金额和已存金额分开编辑，避免把普通流水
/// 误当成目标贡献；后续关联资产时仍可用 stableID 对接。
enum SavingsGoalStore {
    enum Error: LocalizedError {
        case invalidName
        case invalidTarget
        case invalidSavedAmount

        var errorDescription: String? {
            switch self {
            case .invalidName: return "目标名称不能为空。"
            case .invalidTarget: return "目标金额必须大于 0。"
            case .invalidSavedAmount: return "已存金额不能小于 0。"
            }
        }
    }

    static func goals(in context: ModelContext) throws -> [SavingsGoal] {
        try context.fetch(FetchDescriptor<SavingsGoal>(sortBy: [
            SortDescriptor(\SavingsGoal.updatedAt, order: .reverse)
        ]))
    }

    @discardableResult
    static func create(
        in context: ModelContext,
        name: String,
        emoji: String,
        targetAmount: Decimal,
        savedAmount: Decimal = 0,
        currencyCode: String = "CNY",
        note: String = ""
    ) throws -> SavingsGoal {
        let normalizedTarget = MoneyNormalization.roundToCents(targetAmount)
        let normalizedSaved = MoneyNormalization.roundToCents(savedAmount)
        try validate(name: name, targetAmount: normalizedTarget, savedAmount: normalizedSaved)
        let goal = SavingsGoal(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            emoji: emoji,
            targetAmount: normalizedTarget,
            savedAmount: normalizedSaved,
            currencyCode: currencyCode.uppercased(),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        context.insert(goal)
        try context.save()
        return goal
    }

    static func update(
        _ goal: SavingsGoal,
        in context: ModelContext,
        name: String,
        emoji: String,
        targetAmount: Decimal,
        savedAmount: Decimal,
        currencyCode: String,
        note: String
    ) throws {
        let normalizedTarget = MoneyNormalization.roundToCents(targetAmount)
        let normalizedSaved = MoneyNormalization.roundToCents(savedAmount)
        try validate(name: name, targetAmount: normalizedTarget, savedAmount: normalizedSaved)
        goal.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        goal.emoji = emoji
        goal.targetAmount = normalizedTarget
        goal.savedAmount = normalizedSaved
        goal.currencyCode = currencyCode.uppercased()
        goal.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        goal.updatedAt = Date()
        try context.save()
    }

    static func archive(_ goal: SavingsGoal, in context: ModelContext) throws {
        goal.isArchived = true
        goal.updatedAt = Date()
        try context.save()
    }

    static func restore(_ goal: SavingsGoal, in context: ModelContext) throws {
        goal.isArchived = false
        goal.updatedAt = Date()
        try context.save()
    }

    static func delete(_ goal: SavingsGoal, in context: ModelContext) throws {
        context.delete(goal)
        try context.save()
    }

    private static func validate(name: String, targetAmount: Decimal, savedAmount: Decimal) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Error.invalidName
        }
        guard targetAmount > 0 else { throw Error.invalidTarget }
        guard savedAmount >= 0 else { throw Error.invalidSavedAmount }
    }
}
