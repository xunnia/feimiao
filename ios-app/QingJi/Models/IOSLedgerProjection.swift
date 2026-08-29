import Foundation
import SwiftData
import QingJiCore

/// Immutable, view-ready ledger data shared by the expensive iOS screens.
///
/// SwiftUI can reevaluate a view body many times for a toolbar, sheet, or
/// animation state change. Keeping the SwiftData objects and their DTOs
/// together prevents each child view from rebuilding the same ledger.
struct IOSLedgerSnapshot {
    let revision: IOSLedgerDataRevision
    let scopedTransactions: [MoneyTransaction]
    let includedTransactions: [MoneyTransaction]
    let records: [TransactionRecord]
    let includedRecords: [TransactionRecord]
    let recordsByID: [UUID: TransactionRecord]
    let refundTotals: [UUID: Decimal]
    let includedRefundTotals: [UUID: Decimal]

    var scopedCurrencyCode: String {
        scopedTransactions.first?.currencyCode ?? "CNY"
    }

    var includedCurrencyCode: String {
        includedTransactions.first?.currencyCode ?? "CNY"
    }

    func record(for transaction: MoneyTransaction) -> TransactionRecord {
        recordsByID[transaction.stableID] ?? transaction.record
    }
}

/// Content fingerprint for the fields that affect ledger projection output.
///
/// It is intentionally cheaper than rebuilding `TransactionRecord` values and
/// also includes relationship display fields, because those can change without
/// changing the transaction's own `updatedAt` value.
struct IOSLedgerDataRevision: Equatable, Hashable {
    let count: Int
    let digest: Int

    init(_ transactions: [MoneyTransaction], selectedBookID: UUID? = nil) {
        var state: UInt64 = 14_695_981_039_346_656_037
        state = Self.mix(state, UInt64(transactions.count))
        state = Self.mix(state, Self.uuidBits(selectedBookID))
        for transaction in transactions {
            state = Self.mix(state, Self.uuidBits(transaction.stableID))
            state = Self.mix(state, Self.stringBits(transaction.amount.description))
            state = Self.mix(state, Self.stringBits(transaction.kindRaw))
            state = Self.mix(state, transaction.date.timeIntervalSinceReferenceDate.bitPattern)
            state = Self.mix(state, Self.stringBits(transaction.note))
            state = Self.mix(state, Self.stringBits(transaction.merchantName))
            state = Self.mix(state, Self.stringBits(transaction.productName))
            state = Self.mix(state, Self.stringBits(transaction.currencyCode))
            state = Self.mix(state, transaction.updatedAt.timeIntervalSinceReferenceDate.bitPattern)
            state = Self.mix(state, Self.stringBits(transaction.timePrecisionRaw))
            state = Self.mix(state, Self.dateBits(transaction.settledAt))
            state = Self.mix(state, Self.uuidBits(transaction.settlementAccountID))
            state = Self.mix(state, Self.stringBits(transaction.eventTypeRaw))
            state = Self.mix(state, Self.stringBits(transaction.attachmentPath))
            state = Self.mix(state, Self.stringBits(transaction.orderNo))
            state = Self.mix(state, Self.uuidBits(transaction.recurringRuleID))
            state = Self.mix(state, Self.boolBits(
                transaction.reimbursable,
                transaction.refundOfID != nil,
                transaction.isReimbursed,
                transaction.isExcluded
            ))
            state = Self.mix(state, Self.uuidBits(transaction.refundOfID))
            state = Self.mix(state, Self.stringBits(transaction.tagNames))
            state = Self.mix(state, Self.stringBits(transaction.category?.key ?? ""))
            state = Self.mix(state, Self.stringBits(transaction.category?.name ?? ""))
            state = Self.mix(state, Self.stringBits(transaction.category?.parentKey ?? ""))
            state = Self.mix(state, Self.dateBits(transaction.category?.updatedAt))
            state = Self.mix(state, Self.uuidBits(transaction.account?.stableID))
            state = Self.mix(state, Self.stringBits(transaction.account?.name ?? ""))
            state = Self.mix(state, Self.dateBits(transaction.account?.updatedAt))
            state = Self.mix(state, Self.uuidBits(transaction.toAccount?.stableID))
            state = Self.mix(state, Self.stringBits(transaction.toAccount?.name ?? ""))
            state = Self.mix(state, Self.dateBits(transaction.toAccount?.updatedAt))
            state = Self.mix(state, Self.uuidBits(transaction.book?.stableID))
            state = Self.mix(state, Self.stringBits(transaction.book?.name ?? ""))
            state = Self.mix(state, Self.boolBits(transaction.book?.includeInTotal ?? true))
            state = Self.mix(state, Self.dateBits(transaction.book?.updatedAt))
        }
        count = transactions.count
        digest = Int(truncatingIfNeeded: state)
    }

    private static func mix(_ state: UInt64, _ value: UInt64) -> UInt64 {
        var result = (state ^ value) &* 1_099_511_628_211
        result ^= result >> 31
        return result
    }

    private static func stringBits(_ value: String) -> UInt64 {
        var result: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            result ^= UInt64(byte)
            result &*= 1_099_511_628_211
        }
        return result
    }

    private static func uuidBits(_ value: UUID?) -> UInt64 {
        guard let value else { return 0 }
        return stringBits(value.uuidString)
    }

    private static func dateBits(_ value: Date?) -> UInt64 {
        value?.timeIntervalSinceReferenceDate.bitPattern ?? 0
    }

    private static func boolBits(_ values: Bool...) -> UInt64 {
        var result: UInt64 = 0
        for (offset, value) in values.enumerated() where value {
            result |= UInt64(1) << UInt64(offset)
        }
        return result
    }
}

/// Main-actor-owned memoization for SwiftUI ledger screens.
final class IOSLedgerProjectionCache {
    private var lastRevision: IOSLedgerDataRevision?
    private var lastBookID: UUID?
    private var lastSnapshot: IOSLedgerSnapshot?

    /// Exposed for the performance regression test; it is not app state.
    private(set) var rebuildCount = 0

    func snapshot(
        for transactions: [MoneyTransaction],
        selectedBookID: UUID?
    ) -> IOSLedgerSnapshot {
        let revision = IOSLedgerDataRevision(
            transactions,
            selectedBookID: selectedBookID
        )
        if let lastSnapshot,
           lastRevision == revision,
           lastBookID == selectedBookID {
            return lastSnapshot
        }

        let scoped = LedgerScope.filter(transactions, selectedBookID: selectedBookID)
        let records = scoped.map(\.record)
        var recordsByID = [UUID: TransactionRecord](minimumCapacity: records.count)
        for record in records {
            recordsByID[record.id] = record
        }

        let includedPairs = zip(scoped, records).filter { !$0.0.isExcluded }
        let includedTransactions = includedPairs.map { $0.0 }
        let includedRecords = includedPairs.map { $0.1 }
        let snapshot = IOSLedgerSnapshot(
            revision: revision,
            scopedTransactions: scoped,
            includedTransactions: includedTransactions,
            records: records,
            includedRecords: includedRecords,
            recordsByID: recordsByID,
            refundTotals: LedgerPolicy.refundTotals(from: records),
            includedRefundTotals: LedgerPolicy.refundTotals(from: includedRecords)
        )

        lastRevision = revision
        lastBookID = selectedBookID
        lastSnapshot = snapshot
        rebuildCount += 1
        return snapshot
    }
}

/// Memoizes pure core calculations for one SwiftUI screen lifetime.
///
/// A scope/date switch creates a new key; toolbar and animation redraws reuse
/// the existing value. When ledger content changes, all derived calculations
/// are invalidated together so no stale aggregate can leak into the UI.
final class IOSStatisticsProjectionCache {
    private var activeRevision: IOSLedgerDataRevision?
    private var monthly: [MonthlyKey: MonthlySummary] = [:]
    private var yearly: [Int: YearlySummary] = [:]
    private var periods: [PeriodKey: PeriodSummary] = [:]
    private var budgets: [BudgetKey: BudgetStatus] = [:]

    /// Exposed for the performance regression test; it counts core calculations,
    /// not SwiftUI body evaluations.
    private(set) var calculationCount = 0

    private func prepare(for revision: IOSLedgerDataRevision) {
        guard activeRevision != revision else { return }
        activeRevision = revision
        monthly.removeAll(keepingCapacity: true)
        yearly.removeAll(keepingCapacity: true)
        periods.removeAll(keepingCapacity: true)
        budgets.removeAll(keepingCapacity: true)
    }

    func monthly(
        of records: [TransactionRecord],
        revision: IOSLedgerDataRevision,
        year: Int,
        month: Int,
        calendar: Calendar = .current
    ) -> MonthlySummary {
        prepare(for: revision)
        let key = MonthlyKey(year: year, month: month)
        if let cached = monthly[key] { return cached }
        calculationCount += 1
        let value = StatisticsEngine.monthlySummary(of: records, year: year, month: month, calendar: calendar)
        monthly[key] = value
        return value
    }

    func yearly(
        of records: [TransactionRecord],
        revision: IOSLedgerDataRevision,
        year: Int,
        calendar: Calendar = .current
    ) -> YearlySummary {
        prepare(for: revision)
        if let cached = yearly[year] { return cached }
        calculationCount += 1
        let value = StatisticsEngine.yearlySummary(of: records, year: year, calendar: calendar)
        yearly[year] = value
        return value
    }

    func period(
        of records: [TransactionRecord],
        revision: IOSLedgerDataRevision,
        start: Date,
        end: Date,
        calendar: Calendar = .current
    ) -> PeriodSummary {
        prepare(for: revision)
        let key = PeriodKey(start: start, end: end)
        if let cached = periods[key] { return cached }
        calculationCount += 1
        let value = StatisticsEngine.periodSummary(of: records, start: start, end: end, calendar: calendar)
        periods[key] = value
        return value
    }

    func status(
        for budget: Budget,
        records: [TransactionRecord],
        revision: IOSLedgerDataRevision,
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> BudgetStatus {
        prepare(for: revision)
        let key = BudgetKey(budget: budget, referenceDate: referenceDate)
        if let cached = budgets[key] { return cached }
        calculationCount += 1
        let value = BudgetStore.status(
            for: budget,
            records: records,
            referenceDate: referenceDate,
            calendar: calendar
        )
        budgets[key] = value
        return value
    }

    private struct MonthlyKey: Hashable {
        let year: Int
        let month: Int
    }

    private struct PeriodKey: Hashable {
        let start: Date
        let end: Date
    }

    private struct BudgetKey: Hashable {
        let id: UUID
        let amount: String
        let categoryKey: String
        let bookID: UUID?
        let periodStart: Date?
        let periodEnd: Date?
        let cycleRaw: String
        let isActive: Bool
        let referenceDate: Date

        init(budget: Budget, referenceDate: Date) {
            id = budget.stableID
            amount = budget.amount.description
            categoryKey = budget.categoryKey ?? ""
            bookID = budget.bookID
            periodStart = budget.periodStart
            periodEnd = budget.periodEnd
            cycleRaw = budget.cycleRaw
            isActive = budget.isActive
            self.referenceDate = referenceDate
        }
    }
}
