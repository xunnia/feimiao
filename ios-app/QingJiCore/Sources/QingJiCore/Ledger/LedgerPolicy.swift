import Foundation

/// 一笔支出家族的退款状态，供编辑页、账单行和导入复核共用。
public struct RefundStatus: Equatable, Sendable {
    public let originalAmount: Decimal
    public let refundedAmount: Decimal
    public let remainingAmount: Decimal

    public var isFullyRefunded: Bool { remainingAmount == 0 }

    public init(originalAmount: Decimal, refundedAmount: Decimal, remainingAmount: Decimal) {
        self.originalAmount = originalAmount
        self.refundedAmount = refundedAmount
        self.remainingAmount = remainingAmount
    }
}

/// Android / iOS 共用的用户账务口径。
///
/// 存储层保留原始交易和附着式退款行；统计、预算、报告和导出使用本策略
/// 将退款家族折叠成一条用户可见记录。这样退款不会重复计笔数，也不会因为
/// 退款行的写入时间不同而漂移到另一个统计月份。
public enum LedgerPolicy {
    /// 一次遍历建立“原交易 ID -> 附着退款合计”的索引。
    /// 退款行本身通常是负支出，因此合计也保持负数。
    public static func refundTotals(from records: [TransactionRecord]) -> [UUID: Decimal] {
        var totals: [UUID: Decimal] = [:]
        for record in records {
            guard let originalID = record.refundOfID,
                  !record.isExcluded,
                  record.kind == .expense,
                  record.amount < 0 else { continue }
            totals[originalID, default: 0] += record.amount
        }
        return totals
    }

    /// 返回原账单当前已退款和剩余可退款金额。
    public static func refundStatus(
        for original: TransactionRecord,
        in records: [TransactionRecord]
    ) -> RefundStatus {
        guard original.kind == .expense, original.amount > 0 else {
            return RefundStatus(originalAmount: original.amount, refundedAmount: 0, remainingAmount: 0)
        }
        let totals = refundTotals(from: records)
        let refunded = -(totals[original.id] ?? 0)
        let remaining = Swift.max(original.amount - refunded, Decimal.zero)
        return RefundStatus(
            originalAmount: original.amount,
            refundedAmount: refunded,
            remainingAmount: remaining
        )
    }

    /// 是否仍可对这笔支出创建附着式退款/报销。
    public static func canOffset(
        _ original: TransactionRecord,
        in records: [TransactionRecord]
    ) -> Bool {
        refundStatus(for: original, in: records).remainingAmount > 0
    }

    /// 原交易净额。退款行是负数，所以直接累加即可。
    public static func netAmount(
        of record: TransactionRecord,
        refundTotals: [UUID: Decimal]
    ) -> Decimal {
        record.amount + (refundTotals[record.id] ?? 0)
    }

    /// 将原始交易转换为用户可见的交易流。
    ///
    /// - 附着式退款行不单独输出；
    /// - 退款金额折叠回原交易；
    /// - 不计入收支的原交易和它的退款家族都不输出；
    /// - 没有 `refundOfID` 的旧式独立负调整仍保留，兼容历史数据。
    public static func userRecords(from records: [TransactionRecord]) -> [TransactionRecord] {
        let originals = Set(records.filter { $0.refundOfID == nil }.map(\.id))
        let totals = refundTotals(from: records)

        return records.compactMap { record in
            guard record.refundOfID == nil else { return nil }
            guard !record.isExcluded else { return nil }

            // 只把真实存在的原交易退款折叠回来。孤儿退款行不应凭空制造
            // 一笔支出，也不能让导入损坏时统计出现“幽灵金额”。
            let net = originals.contains(record.id)
                ? netAmount(of: record, refundTotals: totals)
                : record.amount
            return record.withAmount(net)
        }
    }

    /// 统计/预算中的支出笔数：只数净额仍为正的原始消费家族。
    public static func expenseFamilyCount(from records: [TransactionRecord]) -> Int {
        userRecords(from: records).filter {
            $0.kind == .expense && $0.amount > 0
        }.count
    }
}
