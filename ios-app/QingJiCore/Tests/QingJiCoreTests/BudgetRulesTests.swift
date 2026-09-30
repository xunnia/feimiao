import XCTest
@testable import QingJiCore

/// 预算规则模型验收用例（docs/08 §6.14），和安卓 test/budget_rules_test.dart 同一组数字。
final class BudgetRulesTests: XCTestCase {
    private func day(_ y: Int, _ m: Int, _ d: Int) -> BudgetCivilDay {
        BudgetCivilDay(year: y, month: m, day: d)
    }

    private func base(_ yuan: Int, _ unit: BudgetRuleUnit, _ start: BudgetCivilDay,
                      id: Int = 1, created: Int = 1) -> BudgetRule {
        BudgetRule(id: id, bookID: "b", kind: .base, amountCents: yuan * 100,
                   unit: unit, startDate: start, createdMs: created)
    }

    private func special(_ yuan: Int, _ unit: BudgetRuleUnit, _ start: BudgetCivilDay,
                         _ end: BudgetCivilDay, id: Int = 2, created: Int = 2,
                         funding: BudgetFunding? = nil) -> BudgetRule {
        BudgetRule(id: id, bookID: "b", kind: .special, amountCents: yuan * 100,
                   unit: unit, startDate: start, endDate: end, funding: funding,
                   createdMs: created)
    }

    private func month(_ rules: [BudgetRule], _ y: Int, _ m: Int,
                       spend: [Int: Int] = [:], today: BudgetCivilDay? = nil,
                       changes: [BudgetRolloverChange] = []) -> BudgetMonthResult {
        BudgetRuleEngine.resolveMonth(rules: rules, rolloverChanges: changes, spendByDay: spend,
                                      year: y, month: m, today: today ?? day(y, m, 1))
    }

    private func cents(_ r: BudgetMonthResult, _ d: Int) -> Int { r.days[d - 1].budgetCents }

    private lazy var sept4000 = base(4000, .month, day(2026, 9, 1))
    private lazy var midAutumn = special(300, .day, day(2026, 9, 25), day(2026, 9, 27))

    func testCivilDayArithmetic() {
        XCTAssertEqual(day(1970, 1, 1).serial, 0)
        XCTAssertEqual(day(1970, 1, 1).weekday, 4)
        XCTAssertEqual(day(2026, 9, 28).weekday, 1)
        XCTAssertEqual(day(2026, 12, 31).adding(days: 1), day(2027, 1, 1))
        XCTAssertEqual(day(2026, 13, 1), day(2027, 1, 1))
        XCTAssertEqual(day(2028, 2, 28).adding(days: 1), day(2028, 2, 29))
        XCTAssertEqual(BudgetCivilDay(text: "2026-09-30"), day(2026, 9, 30))
        XCTAssertNil(BudgetCivilDay(text: "2026-02-30"))
        XCTAssertEqual(day(2026, 9, 5).text, "2026-09-05")
    }

    func test1MonthlyEvenSplit() {
        let r = month([sept4000], 2026, 9)
        XCTAssertEqual(r.budgetCents, 400_000)
        for d in 1...30 { XCTAssertEqual(cents(r, d), d <= 10 ? 13_400 : 13_300, "9/\(d)") }
    }

    func test2MidAutumnCarve() {
        let r = month([sept4000, midAutumn], 2026, 9)
        XCTAssertEqual(r.budgetCents, 400_000)
        for d in [25, 26, 27] { XCTAssertEqual(cents(r, d), 30_000) }
        let others = (1...30).filter { $0 < 25 || $0 > 27 }.map { cents(r, $0) }
        XCTAssertEqual(others.filter { $0 == 11_500 }.count, 22)
        XCTAssertEqual(others.filter { $0 == 11_400 }.count, 5)
    }

    func test3MidAutumnExtra() {
        let extra = special(300, .day, day(2026, 9, 25), day(2026, 9, 27), funding: .extra)
        XCTAssertEqual(month([sept4000, extra], 2026, 9).budgetCents, 490_000)
    }

    func test4NationalDayWeeklyCarve() {
        let r = month([
            base(8000, .month, day(2026, 10, 1)),
            special(2000, .week, day(2026, 10, 1), day(2026, 10, 7)),
        ], 2026, 10)
        XCTAssertEqual(r.budgetCents, 800_000)
        for d in 1...31 {
            XCTAssertEqual(cents(r, d), d <= 5 ? 28_600 : (d <= 7 ? 28_500 : 25_000), "10/\(d)")
        }
    }

    func test5BaseRelayDeleteAndEdit() {
        let a = base(5000, .month, day(2026, 5, 1))
        let b = base(6000, .month, day(2026, 10, 1), id: 2, created: 2)
        XCTAssertEqual(month([a, b], 2026, 9).budgetCents, 500_000)
        XCTAssertEqual(month([a, b], 2026, 10).budgetCents, 600_000)
        XCTAssertEqual(month([a], 2026, 10).budgetCents, 500_000)
        let edited = base(5200, .month, day(2026, 5, 1))
        XCTAssertEqual(month([edited, b], 2026, 5).budgetCents, 520_000)
        XCTAssertEqual(month([edited, b], 2026, 9).budgetCents, 520_000)
    }

    func test6YearlyBudget() {
        let r = month([base(36_500, .year, day(2026, 1, 1))], 2026, 9)
        XCTAssertTrue(r.days.allSatisfy { $0.budgetCents == 10_000 })
        let leap = month([base(36_600, .year, day(2028, 1, 1))], 2028, 2)
        XCTAssertEqual(leap.days.count, 29)
        XCTAssertTrue(leap.days.allSatisfy { $0.budgetCents == 10_000 })
    }

    func test7WeekAcrossMonths() {
        let rules = [base(700, .week, day(2026, 9, 1))]
        let sep = month(rules, 2026, 9)
        let oct = month(rules, 2026, 10)
        for d in [28, 29, 30] { XCTAssertEqual(cents(sep, d), 10_000) }
        for d in [1, 2, 3, 4] { XCTAssertEqual(cents(oct, d), 10_000) }
    }

    func test8Validation() {
        let tooMuch = special(2000, .day, day(2026, 9, 25), day(2026, 9, 27), id: 0)
        let issue = BudgetRuleEngine.validateSpecial(existing: [sept4000], candidate: tooMuch)
        XCTAssertEqual(issue?.issue, .carveExceedsBase)
        XCTAssertEqual(issue?.month, 9)
        XCTAssertEqual(BudgetRuleEngine.validateSpecial(existing: [], candidate: tooMuch)?.issue,
                       .carveWithoutBase)
        XCTAssertNil(BudgetRuleEngine.validateSpecial(existing: [sept4000], candidate: midAutumn))
    }

    private func change(_ mode: BudgetRolloverMode) -> [BudgetRolloverChange] {
        [BudgetRolloverChange(id: 1, bookID: "b", year: 2026, month: 10, mode: mode)]
    }

    func test9RolloverReset() {
        let r = month([sept4000], 2026, 10, spend: [20_260_910: 366_000], today: day(2026, 10, 15))
        XCTAssertEqual(r.carryInCents, 0)
        XCTAssertEqual(r.effectiveCents, 400_000)
    }

    func test9RolloverKeepSavings() {
        let saved = month([sept4000], 2026, 10, spend: [20_260_910: 366_000],
                          today: day(2026, 10, 15), changes: change(.keepSavings))
        XCTAssertEqual(saved.carryInCents, 34_000)
        XCTAssertEqual(saved.effectiveCents, 434_000)
        let over = month([sept4000], 2026, 10, spend: [20_260_910: 412_000],
                         today: day(2026, 10, 15), changes: change(.keepSavings))
        XCTAssertEqual(over.carryInCents, 0)
    }

    func test9RolloverCarryBoth() {
        let over = month([sept4000], 2026, 10, spend: [20_260_910: 412_000],
                         today: day(2026, 10, 15), changes: change(.carryBoth))
        XCTAssertEqual(over.carryInCents, -12_000)
        let huge = month([sept4000], 2026, 10, spend: [20_260_910: 900_000],
                         today: day(2026, 10, 15), changes: change(.carryBoth))
        XCTAssertEqual(huge.carryInCents, -500_000)
        XCTAssertEqual(huge.remainingCents, -100_000)
        let nov = month([sept4000], 2026, 11, spend: [20_260_910: 900_000],
                        today: day(2026, 11, 15), changes: change(.carryBoth))
        XCTAssertEqual(nov.carryInCents, -100_000)
    }

    func test10TodayAllowance() {
        let today = day(2026, 9, 18)
        let r = month([sept4000, midAutumn], 2026, 9,
                      spend: [20_260_910: 216_000, 20_260_918: 6000], today: today)
        let t = r.today!
        XCTAssertEqual(t.allowanceCents, 10_300)
        XCTAssertEqual(t.leftTodayCents, 4300)
        XCTAssertEqual(t.remainingDays, 13)
        XCTAssertEqual(t.plannedBeforeTodayCents, 195_500)
        XCTAssertEqual(t.paceDeltaCents, -20_500)
        XCTAssertTrue(r.todayCovered)
        let over = month([sept4000, midAutumn], 2026, 9,
                         spend: [20_260_910: 216_000, 20_260_918: 20_000], today: today)
        XCTAssertEqual(over.today?.leftTodayCents, -9700)
    }

    func test11UncoveredDaysDoNotCount() {
        let r = month([special(1500, .week, day(2026, 10, 1), day(2026, 10, 7), funding: .extra)],
                      2026, 10, spend: [20_261_002: 5000, 20_261_015: 8000], today: day(2026, 10, 31))
        XCTAssertEqual(r.budgetCents, 150_000)
        XCTAssertEqual(r.spentCents, 5000)
        XCTAssertFalse(r.days[14].covered)
    }

    func testSpecialTotalPartialWeek() {
        XCTAssertEqual(budgetSpecialTotalYuan(special(1500, .week, day(2026, 10, 1), day(2026, 10, 5))), 1071)
    }

    func testOverlappingSpecials() {
        let a = special(300, .day, day(2026, 9, 24), day(2026, 9, 27))
        let b = special(200, .day, day(2026, 9, 26), day(2026, 9, 28), id: 3, created: 3)
        let r = month([sept4000, a, b], 2026, 9)
        XCTAssertEqual(r.budgetCents, 400_000)
        XCTAssertEqual(cents(r, 24), 30_000)
        XCTAssertEqual(cents(r, 25), 30_000)
        XCTAssertEqual(cents(r, 26), 20_000)
        XCTAssertEqual(cents(r, 28), 20_000)
        XCTAssertEqual(cents(r, 1), 11_200)
    }

    func testRangeWithoutRollover() {
        let range = BudgetRuleEngine.resolveRange(
            rules: [base(70, .day, day(2026, 9, 1))],
            spendByDay: [20_260_901: 2500, 20_260_903: 900],
            start: day(2026, 8, 29), end: day(2026, 9, 3), today: day(2026, 9, 2))
        XCTAssertEqual(range.budgetCents, 3 * 7000)
        XCTAssertEqual(range.spentCents, 2500)
    }
}
