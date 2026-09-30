import XCTest
import SwiftData
import QingJiCore
@testable import QingJi

/// 预算规则的存取、快照、结余方式和旧预算迁移（docs/08 §6）。
@MainActor
final class BudgetRuleStoreTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Account.self,
            Book.self,
            TxCategory.self,
            MoneyTransaction.self,
            Budget.self,
            BudgetPlanRecord.self,
            BudgetPlanRevisionRecord.self,
            BudgetRuleRecord.self,
            BudgetRolloverChangeRecord.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testBaseRuleStartsOnFirstAndSnapshotCountsSpendUpToToday() throws {
        let context = try makeContext()
        let book = Book(name: "日常", isDefault: true)
        context.insert(book)
        try context.save()
        let now = day(2026, 8, 20)

        let record = try BudgetRuleStore.save(
            in: context, editing: nil, bookID: book.stableID, kind: .base, name: "",
            amountYuan: 3100, unit: .month, start: nil, end: nil, funding: .carve, now: now)
        XCTAssertEqual(record.startDate, "2026-08-01")
        XCTAssertNil(record.endDate)
        XCTAssertNil(record.fundingRaw)

        context.insert(MoneyTransaction(amount: 100, kind: .expense, date: day(2026, 8, 10), book: book))
        // 明天的账还没到，不算。
        context.insert(MoneyTransaction(amount: 500, kind: .expense, date: day(2026, 8, 21), book: book))
        // 外币只计数，不加进金额。
        context.insert(MoneyTransaction(amount: 30, kind: .expense, date: day(2026, 8, 12), currencyCode: "USD", book: book))
        try context.save()

        let snapshot = BudgetRuleStore.snapshot(
            rules: try context.fetch(FetchDescriptor<BudgetRuleRecord>()),
            rollovers: [],
            selectedBookID: nil,
            books: [book],
            transactions: try context.fetch(FetchDescriptor<MoneyTransaction>()),
            year: 2026, month: 8, now: now)
        XCTAssertEqual(snapshot.bookID, book.stableID)
        XCTAssertTrue(snapshot.hasBudget)
        XCTAssertTrue(snapshot.hasDailyGuidance)
        XCTAssertEqual(snapshot.month.budgetCents, 310_000)
        XCTAssertEqual(snapshot.month.spentCents, 10_000)
        XCTAssertEqual(snapshot.spendByDay[20260810], 10_000)
        XCTAssertNil(snapshot.spendByDay[20260821])
        XCTAssertEqual(snapshot.excludedForeignCount, 1)
        XCTAssertEqual(snapshot.plannedAmount, 3100)
    }

    func testCarveSpecialWithoutBaseIsRejected() throws {
        let context = try makeContext()
        let book = Book(name: "日常", isDefault: true)
        context.insert(book)
        try context.save()
        let now = day(2026, 8, 20)

        XCTAssertThrowsError(try BudgetRuleStore.save(
            in: context, editing: nil, bookID: book.stableID, kind: .special, name: "出游",
            amountYuan: 800, unit: .month, start: BudgetCivilDay(year: 2026, month: 10, day: 1),
            end: BudgetCivilDay(year: 2026, month: 10, day: 7), funding: .carve, now: now)) { error in
            guard let saveError = error as? BudgetRuleSaveError, case .validation = saveError else {
                return XCTFail("expected validation error, got \(error)")
            }
        }
        // 额外多给不需要日常预算。
        let extra = try BudgetRuleStore.save(
            in: context, editing: nil, bookID: book.stableID, kind: .special, name: "出游",
            amountYuan: 800, unit: .month, start: BudgetCivilDay(year: 2026, month: 10, day: 7),
            end: BudgetCivilDay(year: 2026, month: 10, day: 1), funding: .extra, now: now)
        XCTAssertEqual(extra.startDate, "2026-10-01")
        XCTAssertEqual(extra.endDate, "2026-10-07")
        XCTAssertEqual(extra.fundingRaw, BudgetFunding.extra.rawValue)
    }

    func testRolloverModeKeepsOneRecordPerMonth() throws {
        let context = try makeContext()
        let bookID = UUID()
        let now = day(2026, 8, 20)
        try BudgetRuleStore.setRolloverMode(.keepSavings, bookID: bookID, in: context, now: now)
        try BudgetRuleStore.setRolloverMode(.carryBoth, bookID: bookID, in: context, now: now)
        let records = try context.fetch(FetchDescriptor<BudgetRolloverChangeRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.effectiveMonth, "2026-08")
        XCTAssertEqual(records.first?.modeRaw, BudgetRolloverMode.carryBoth.rawValue)
        XCTAssertEqual(BudgetRuleStore.rolloverMode(in: context, bookID: bookID, year: 2026, month: 9), .carryBoth)
        XCTAssertEqual(BudgetRuleStore.rolloverMode(in: context, bookID: bookID, year: 2026, month: 7), .reset)
    }

    func testLegacyMonthlyBudgetMigratesOnceToBaseRule() throws {
        let context = try makeContext()
        let book = Book(name: "日常", isDefault: true)
        context.insert(book)
        context.insert(Budget(amount: Decimal(string: "4000.40")!, periodStart: day(2026, 5, 10)))
        try context.save()
        let now = day(2026, 8, 20)

        BudgetRuleStore.migrate(in: context, now: now)
        BudgetRuleStore.migrate(in: context, now: now)
        let rules = try context.fetch(FetchDescriptor<BudgetRuleRecord>())
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.bookID, book.stableID)
        XCTAssertEqual(rules.first?.kindRaw, BudgetRuleKind.base.rawValue)
        XCTAssertEqual(rules.first?.amountCents, 400_000)
        XCTAssertEqual(rules.first?.unitRaw, BudgetRuleUnit.month.rawValue)
        XCTAssertEqual(rules.first?.startDate, "2026-05-01")
    }

    func testDeleteIsSoftAndLeavesRuleOutOfSnapshot() throws {
        let context = try makeContext()
        let book = Book(name: "日常", isDefault: true)
        context.insert(book)
        try context.save()
        let now = day(2026, 8, 20)
        let record = try BudgetRuleStore.save(
            in: context, editing: nil, bookID: book.stableID, kind: .base, name: "",
            amountYuan: 3000, unit: .month, start: nil, end: nil, funding: .carve, now: now)
        try BudgetRuleStore.delete(record, in: context)

        let all = try context.fetch(FetchDescriptor<BudgetRuleRecord>())
        XCTAssertEqual(all.count, 1)
        XCTAssertNotNil(all.first?.deletedMs)
        let snapshot = BudgetRuleStore.snapshot(
            rules: all, rollovers: [], selectedBookID: book.stableID, books: [book],
            transactions: [], year: 2026, month: 8, now: now)
        XCTAssertFalse(snapshot.hasBudget)
        XCTAssertNil(snapshot.plannedAmount)
    }
}
