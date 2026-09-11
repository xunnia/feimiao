import XCTest
import QingJiCore
@testable import QingJi

final class BudgetStoreV2Tests: XCTestCase {
    func testStatusV2UsesHistoricalRevisionAndCycleOverride() {
        let calendar = Calendar.current
        let bookID = UUID()
        let planID = UUID()
        let january = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let july = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        let august = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let september = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let cutoff = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31))!

        let plan = BudgetPlanV2(
            id: planID,
            bookID: bookID,
            cadence: .monthly,
            anchorStart: january,
            monthStartDay: 1,
            createdAt: .distantPast
        )
        let firstRevision = BudgetPlanRevisionV2(
            id: UUID(),
            planID: planID,
            effectiveCycleStart: january,
            amountCents: 3_100,
            createdAt: .distantPast
        )
        let augustRevision = BudgetPlanRevisionV2(
            id: UUID(),
            planID: planID,
            effectiveCycleStart: august,
            amountCents: 4_000,
            createdAt: .distantPast
        )
        let augustOverride = BudgetCycleOverrideV2(
            id: UUID(),
            planID: planID,
            cycleStart: august,
            cycleEndInclusive: calendar.date(byAdding: .day, value: 30, to: august)!,
            targetAmountCents: 6_200,
            createdAt: .distantPast
        )
        let records = [
            TransactionRecord(
                kind: .expense,
                amount: 10,
                bookID: bookID,
                date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 5))!
            )
        ]

        let historical = BudgetStore.statusV2(
            plans: [plan],
            revisions: [firstRevision, augustRevision],
            overrides: [],
            bookID: bookID,
            records: records,
            windowStart: july,
            windowEndExclusive: august,
            referenceDate: july,
            knowledgeCutoff: cutoff,
            calendar: calendar
        )
        XCTAssertEqual(historical?.monthlyBudget, Optional(Decimal(31)))
        XCTAssertEqual(historical?.spentThisMonth, Optional(Decimal.zero))

        let overridden = BudgetStore.statusV2(
            plans: [plan],
            revisions: [firstRevision, augustRevision],
            overrides: [augustOverride],
            bookID: bookID,
            records: records,
            windowStart: august,
            windowEndExclusive: september,
            referenceDate: calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!,
            knowledgeCutoff: cutoff,
            calendar: calendar
        )
        XCTAssertEqual(overridden?.monthlyBudget, Optional(Decimal(62)))
        XCTAssertEqual(overridden?.spentThisMonth, Optional(Decimal(10)))
        XCTAssertEqual(overridden?.remaining, Optional(Decimal(52)))
    }

    func testStatusV2ScopesSpendingToBookAndKnowledgeCutoff() {
        let calendar = Calendar.current
        let bookID = UUID()
        let otherBookID = UUID()
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let cutoff = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!
        let plan = BudgetPlanV2(
            id: UUID(),
            bookID: bookID,
            cadence: .monthly,
            anchorStart: start,
            monthStartDay: 1,
            createdAt: .distantPast
        )
        let revision = BudgetPlanRevisionV2(
            id: UUID(),
            planID: plan.id,
            effectiveCycleStart: start,
            amountCents: 10_000,
            createdAt: .distantPast
        )
        let records = [
            TransactionRecord(
                kind: .expense,
                amount: 10,
                bookID: bookID,
                date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 5))!,
                createdAt: calendar.date(from: DateComponents(year: 2026, month: 8, day: 5))!
            ),
            TransactionRecord(
                kind: .expense,
                amount: 90,
                bookID: otherBookID,
                date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 6))!,
                createdAt: calendar.date(from: DateComponents(year: 2026, month: 8, day: 6))!
            ),
            TransactionRecord(
                kind: .expense,
                amount: 50,
                bookID: bookID,
                date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 7))!,
                createdAt: calendar.date(from: DateComponents(year: 2026, month: 8, day: 21))!
            )
        ]

        let status = BudgetStore.statusV2(
            plans: [plan],
            revisions: [revision],
            overrides: [],
            bookID: bookID,
            records: records,
            windowStart: start,
            windowEndExclusive: calendar.date(byAdding: .month, value: 1, to: start)!,
            referenceDate: calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!,
            knowledgeCutoff: cutoff,
            calendar: calendar
        )

        XCTAssertEqual(status?.spentThisMonth, Optional(Decimal(10)))
    }
}
