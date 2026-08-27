import Foundation
import SwiftData
import QingJiCore

/// 账户余额核对/校准的持久化边界。
///
/// 校准只记录“从已知账面余额到用户确认余额的差额”，不生成伪造的收入或
/// 支出。后续流水仍按正常事件继续计算；撤销通过 reversal 记录完成。
enum AccountCheckpointStore {
    enum Error: LocalizedError, Equatable {
        case invalidBalance
        case accountUnavailable
        case checkpointNotFound

        var errorDescription: String? {
            switch self {
            case .invalidBalance: return "实际余额格式不正确。"
            case .accountUnavailable: return "账户不存在、已归档或币种无效。"
            case .checkpointNotFound: return "余额核对记录不存在。"
            }
        }
    }

    static func checkpoints(
        for accountID: UUID,
        in context: ModelContext
    ) throws -> [AccountBalanceCheckpointRecord] {
        try context.fetch(FetchDescriptor<AccountBalanceCheckpointRecord>(
            sortBy: [
                SortDescriptor(\AccountBalanceCheckpointRecord.effectiveAt, order: .reverse),
                SortDescriptor(\AccountBalanceCheckpointRecord.sequence, order: .reverse),
            ]
        )).filter { $0.accountID == accountID }
    }

    static func effectiveAdjustment(
        for accountID: UUID,
        checkpoints: [AccountBalanceCheckpointRecord]
    ) -> Decimal {
        let accountCheckpoints = checkpoints.filter { $0.accountID == accountID }
        let reversed = Set(
            accountCheckpoints
                .filter { $0.eventKindRaw == "reversal" && $0.status == "active" }
                .compactMap(\.reversalOfID)
        )
        return accountCheckpoints
            .filter {
                $0.eventKindRaw == "anchor" &&
                $0.status == "active" &&
                !reversed.contains($0.stableID)
            }
            .sorted {
                if $0.effectiveAt != $1.effectiveAt {
                    return $0.effectiveAt > $1.effectiveAt
                }
                if $0.sequence != $1.sequence {
                    return $0.sequence > $1.sequence
                }
                return $0.createdAt > $1.createdAt
            }
            .first?
            .deltaAtCreation ?? 0
    }

    @discardableResult
    static func create(
        for account: Account,
        actualBalance: Decimal,
        effectiveAt: Date = Date(),
        in context: ModelContext
    ) throws -> AccountBalanceCheckpointRecord {
        guard !account.isDeleted,
              account.status == .active,
              !account.currencyCode.isEmpty else {
            throw Error.accountUnavailable
        }
        let normalizedActualBalance = MoneyNormalization.roundToCents(actualBalance)

        let transactions = try context.fetch(FetchDescriptor<MoneyTransaction>())
        let calculatedBefore = AccountBalanceCalculator.balance(
            accountName: account.name,
            initialBalance: account.initialBalance,
            records: transactions.map(\.record),
            accountID: account.stableID
        )
        let history = try checkpoints(for: account.stableID, in: context)
        let sequence = (history.map(\.sequence).max() ?? -1) + 1
        let checkpoint = AccountBalanceCheckpointRecord(
            accountID: account.stableID,
            effectiveAt: effectiveAt,
            knowledgeCutoff: effectiveAt,
            targetBalance: normalizedActualBalance
        )
        checkpoint.sequence = sequence
        checkpoint.calculatedBefore = calculatedBefore
        checkpoint.deltaAtCreation = normalizedActualBalance - calculatedBefore
        checkpoint.reason = "manual"
        checkpoint.note = "用户余额核对"
        checkpoint.status = "active"
        context.insert(checkpoint)
        try context.save()
        return checkpoint
    }

    static func reverse(
        _ checkpoint: AccountBalanceCheckpointRecord,
        in context: ModelContext,
        at date: Date = Date()
    ) throws {
        guard checkpoint.eventKindRaw == "anchor",
              checkpoint.status == "active" else {
            throw Error.checkpointNotFound
        }
        checkpoint.status = "reversed"
        checkpoint.updatedAt = date
        let reversal = AccountBalanceCheckpointRecord(
            accountID: checkpoint.accountID,
            effectiveAt: date,
            knowledgeCutoff: date,
            targetBalance: 0,
            eventKindRaw: "reversal"
        )
        reversal.reversalOfID = checkpoint.stableID
        reversal.reason = "manual_reversal"
        reversal.note = "撤销余额核对"
        context.insert(reversal)
        try context.save()
    }
}
