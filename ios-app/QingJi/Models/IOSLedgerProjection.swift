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
        var hasher = Hasher()
        hasher.combine(transactions.count)
        hasher.combine(selectedBookID)
        for transaction in transactions {
            hasher.combine(transaction.stableID)
            hasher.combine(transaction.amount.description)
            hasher.combine(transaction.kindRaw)
            hasher.combine(transaction.date)
            hasher.combine(transaction.note)
            hasher.combine(transaction.merchantName)
            hasher.combine(transaction.productName)
            hasher.combine(transaction.currencyCode)
            hasher.combine(transaction.updatedAt)
            hasher.combine(transaction.timePrecisionRaw)
            hasher.combine(transaction.settledAt)
            hasher.combine(transaction.settlementAccountID)
            hasher.combine(transaction.eventTypeRaw)
            hasher.combine(transaction.attachmentPath)
            hasher.combine(transaction.orderNo)
            hasher.combine(transaction.recurringRuleID)
            hasher.combine(transaction.reimbursable)
            hasher.combine(transaction.refundOfID)
            hasher.combine(transaction.isReimbursed)
            hasher.combine(transaction.isExcluded)
            hasher.combine(transaction.tagNames)
            hasher.combine(transaction.category?.key ?? "")
            hasher.combine(transaction.category?.name ?? "")
            hasher.combine(transaction.category?.parentKey ?? "")
            hasher.combine(transaction.account?.stableID)
            hasher.combine(transaction.account?.name ?? "")
            hasher.combine(transaction.toAccount?.stableID)
            hasher.combine(transaction.toAccount?.name ?? "")
            hasher.combine(transaction.book?.stableID)
            hasher.combine(transaction.book?.includeInTotal)
        }
        count = transactions.count
        digest = hasher.finalize()
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
