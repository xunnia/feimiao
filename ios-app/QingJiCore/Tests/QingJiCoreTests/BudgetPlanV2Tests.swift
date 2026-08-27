import XCTest
@testable import QingJiCore

final class BudgetPlanV2Tests: XCTestCase {
    func testMonthlyCycleAndStableDailyShareMatchAndroidContract() {
        let calendar = Calendar.current
        let bookID = UUID()
        let plan = BudgetPlanV2(
            id: UUID(),
            bookID: bookID,
            cadence: .monthly,
            anchorStart: calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!,
            monthStartDay: 15
        )
        let cycle = plan.cycle(
            for: calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!,
            calendar: calendar
        )
        XCTAssertEqual(calendar.component(.day, from: cycle.start), 15)
        XCTAssertEqual(cycle.dayCount, 31)

        let shares = (0..<31).map { stableBudgetDailyShare(1000, dayCount: 31, dayOffset: $0) }
        XCTAssertEqual(shares.reduce(0, +), 1000)
        XCTAssertEqual(shares.filter { $0 == 33 }.count, 8)
        XCTAssertEqual(shares.filter { $0 == 32 }.count, 23)
    }

    func testResolverAppliesRevisionAndCycleOverride() {
        let calendar = Calendar.current
        let bookID = UUID()
        let planID = UUID()
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let plan = BudgetPlanV2(
            id: planID,
            bookID: bookID,
            cadence: .monthly,
            anchorStart: start,
            monthStartDay: 1
        )
        let revision = BudgetPlanRevisionV2(
            id: UUID(),
            planID: planID,
            effectiveCycleStart: start,
            amountCents: 3100,
            categoryBudgetsCents: ["dining": 1000],
            createdAt: start
        )
        let override = BudgetCycleOverrideV2(
            id: UUID(),
            planID: planID,
            cycleStart: start,
            cycleEndInclusive: calendar.date(byAdding: .day, value: 30, to: start)!,
            targetAmountCents: 6200,
            categoryBudgetsCents: ["dining": 2000],
            createdAt: start
        )
        let result = BudgetPlanV2Resolver.resolveDay(
            day: calendar.date(from: DateComponents(year: 2026, month: 8, day: 2))!,
            bookID: bookID,
            knowledgeCutoff: calendar.date(byAdding: .day, value: 1, to: start)!,
            plans: [plan],
            revisions: [revision],
            overrides: [override],
            calendar: calendar
        )
        XCTAssertEqual(result.status, .available)
        XCTAssertEqual(result.plannedCents, 200)
        XCTAssertEqual(result.categoryPlannedCents["dining"], 65)
    }
}
