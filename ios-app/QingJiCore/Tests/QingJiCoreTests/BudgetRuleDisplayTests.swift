import XCTest
@testable import QingJiCore

/// 预算页显示文字，和安卓 test/budget_rule_display_test.dart 同一组数字。
final class BudgetRuleDisplayTests: XCTestCase {
    private func day(_ y: Int, _ m: Int, _ d: Int) -> BudgetCivilDay {
        BudgetCivilDay(year: y, month: m, day: d)
    }

    private func base(_ id: Int, _ yuan: Int, _ start: BudgetCivilDay,
                      unit: BudgetRuleUnit = .month) -> BudgetRule {
        BudgetRule(id: id, bookID: "b", kind: .base, amountCents: yuan * 100,
                   unit: unit, startDate: start, createdMs: id)
    }

    private func special(_ id: Int, _ yuan: Int, _ start: BudgetCivilDay, _ end: BudgetCivilDay,
                         name: String = "", unit: BudgetRuleUnit = .day,
                         funding: BudgetFunding = .carve, created: Int? = nil) -> BudgetRule {
        BudgetRule(id: id, bookID: "b", kind: .special, name: name, amountCents: yuan * 100,
                   unit: unit, startDate: start, endDate: end, funding: funding,
                   createdMs: created ?? id)
    }

    private var today: BudgetCivilDay { day(2026, 9, 18) }

    func testMoneyUnitsAndDefaultNames() {
        XCTAssertEqual(budgetYuanText(400000), "¥4,000")
        XCTAssertEqual(budgetYuanText(123456789), "¥1,234,567")
        XCTAssertEqual(budgetYuanText(-12000), "-¥120")
        XCTAssertEqual(budgetLeftDisplayCents(-500), 0)
        XCTAssertEqual(budgetLeftDisplayCents(184099), 184000)
        let rule = base(1, 4000, day(2026, 9, 1))
        XCTAssertEqual(budgetRuleAmountText(rule), "每月 ¥4,000")
        XCTAssertEqual(budgetRuleName(rule), "日常")
        XCTAssertEqual(budgetRuleName(special(2, 300, today, today)), "特别安排")
    }

    func testSpans() {
        let may = base(1, 5000, day(2026, 5, 1))
        let oct = base(2, 6000, day(2026, 10, 1))
        let rules = [may, oct]
        XCTAssertEqual(budgetRuleSpan(may, rules: rules, today: today).text, "5月起")
        XCTAssertEqual(budgetRuleSpan(may, rules: rules, today: today).state, .active)
        XCTAssertEqual(budgetRuleSpan(oct, rules: rules, today: today).state, .upcoming)
        let ended = budgetRuleSpan(may, rules: rules, today: day(2026, 11, 2))
        XCTAssertEqual(ended.state, .ended)
        XCTAssertEqual(ended.text, "5月–9月")

        let festival = special(3, 300, day(2026, 9, 25), day(2026, 9, 27))
        XCTAssertEqual(budgetRuleSpan(festival, rules: rules, today: today).text, "9月25日–27日")
        XCTAssertEqual(budgetRuleSpan(festival, rules: rules, today: today).state, .upcoming)
        XCTAssertEqual(budgetRuleSpan(festival, rules: rules, today: day(2026, 9, 28)).state, .ended)
        XCTAssertEqual(budgetRulesNewestFirst(rules + [festival]).map(\.id), [3, 2, 1])
    }

    func testPace() {
        func month(_ spentBefore: Int) -> BudgetMonthResult {
            BudgetRuleEngine.resolveMonth(rules: [base(1, 3000, day(2026, 9, 1))],
                                          spendByDay: [20260910: spentBefore],
                                          year: 2026, month: 9, today: today)
        }
        XCTAssertEqual(budgetPaceText(month(150000)).text, "比计划少花 ¥200 · 节奏不错")
        XCTAssertFalse(budgetPaceText(month(150000)).warning)
        XCTAssertEqual(budgetPaceText(month(180000)).text, "比计划多花 ¥100")
        XCTAssertTrue(budgetPaceText(month(180000)).warning)
        XCTAssertEqual(budgetPaceText(month(280000)).text, "只剩 ¥200 啦")
        XCTAssertEqual(budgetPaceText(month(310000)).text, "这个月已经超出预算啦")
    }

    func testPreviewCarveMidAutumn() {
        let lines = budgetRulePreview(
            existing: [base(1, 4000, day(2026, 9, 1))],
            candidate: special(0, 300, day(2026, 9, 25), day(2026, 9, 27), name: "中秋", created: 99),
            today: today
        ).map(\.text)
        XCTAssertEqual(lines, ["这 3 天一共 ¥900，每天约 ¥300", "9月一共还是 ¥4,000，其余日子每天约 ¥115"])
    }

    func testPreviewExtraAndCarveTooBig() {
        let oct = base(1, 8000, day(2026, 10, 1))
        let lines = budgetRulePreview(
            existing: [oct],
            candidate: special(9, 2000, day(2026, 10, 1), day(2026, 10, 7), unit: .week, funding: .extra),
            today: today
        ).map(\.text)
        XCTAssertEqual(lines[0], "这 7 天一共 ¥2,000，每天约 ¥286")
        XCTAssertTrue(lines[1].hasPrefix("10月一共 ¥10,000（多了 ¥2,000）"))

        let tooBig = budgetRulePreview(existing: [oct],
                                       candidate: special(9, 9000, day(2026, 10, 1), day(2026, 10, 1)),
                                       today: today)
        XCTAssertTrue(tooBig.last!.warning)
        XCTAssertTrue(tooBig.last!.text.contains("比10月整月预算还多"))
    }

    func testPreviewOverlap() {
        let lines = budgetRulePreview(
            existing: [base(1, 4000, day(2026, 9, 1)),
                       special(2, 200, day(2026, 9, 20), day(2026, 9, 26), name: "旅行")],
            candidate: special(3, 300, day(2026, 9, 25), day(2026, 9, 27), name: "中秋"),
            today: today
        ).map(\.text)
        XCTAssertTrue(lines.contains("会盖掉「旅行」的 9月25日–26日"))
    }

    func testBaseEditWarning() {
        let rule = base(1, 5000, day(2026, 5, 1))
        XCTAssertNil(budgetBaseEditWarning(original: rule, amountCents: 500000, unit: .month, today: today))
        XCTAssertEqual(budgetBaseEditWarning(original: rule, amountCents: 600000, unit: .month, today: today),
                       "5月以来的每个月都会按新金额重新计算")
        XCTAssertNil(budgetBaseEditWarning(original: nil, amountCents: 600000, unit: .week, today: today))
    }

    func testSpendByDayFollowsBudgetRules() {
        let now = Date()
        let lunch = UUID()
        let rows = [
            BudgetSpendRow(id: lunch, isExpense: true, amountCents: 10000, currencyCode: "CNY",
                           attributionDay: today, createdAt: now, refundOfID: nil, isExcluded: false),
            // 退了 30 → 净 70
            BudgetSpendRow(id: UUID(), isExpense: true, amountCents: -3000, currencyCode: "CNY",
                           attributionDay: today, createdAt: now, refundOfID: lunch, isExcluded: false),
            // 不计入预算
            BudgetSpendRow(id: UUID(), isExpense: true, amountCents: 4000, currencyCode: "CNY",
                           attributionDay: today, createdAt: now, refundOfID: nil, isExcluded: true),
            // 外币：只计笔数
            BudgetSpendRow(id: UUID(), isExpense: true, amountCents: 900, currencyCode: "usd",
                           attributionDay: today, createdAt: now, refundOfID: nil, isExcluded: false),
            // 明天的等到明天
            BudgetSpendRow(id: UUID(), isExpense: true, amountCents: 5000, currencyCode: "CNY",
                           attributionDay: today.adding(days: 1), createdAt: now, refundOfID: nil, isExcluded: false),
            // 收入不算
            BudgetSpendRow(id: UUID(), isExpense: false, amountCents: 99900, currencyCode: "CNY",
                           attributionDay: today, createdAt: now, refundOfID: nil, isExcluded: false),
            // 全退的不算
            {
                let id = UUID()
                return BudgetSpendRow(id: id, isExpense: true, amountCents: 2000, currencyCode: "CNY",
                                      attributionDay: day(2026, 9, 10), createdAt: now, refundOfID: nil, isExcluded: false)
            }(),
        ]
        let full = rows.last!
        let refundAll = BudgetSpendRow(id: UUID(), isExpense: true, amountCents: -2000, currencyCode: "CNY",
                                       attributionDay: day(2026, 9, 11), createdAt: now,
                                       refundOfID: full.id, isExcluded: false)
        let result = budgetSpendByDay(rows + [refundAll], today: today, knowledgeCutoff: now.addingTimeInterval(1))
        XCTAssertEqual(result.spend, [today.key: 7000])
        XCTAssertEqual(result.foreign, [today.key: 1])

        let month = BudgetRuleEngine.resolveMonth(rules: [base(1, 3000, day(2026, 9, 1))],
                                                  spendByDay: result.spend, year: 2026, month: 9, today: today)
        XCTAssertEqual(budgetForeignCount(result.foreign, month: month, today: today), 1)
    }
}
