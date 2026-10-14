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

    func testFirstDayHasNoPaceEvaluation() {
        let firstDay = day(2026, 9, 1)
        for spentToday in [0, 100_000] {
            let month = BudgetRuleEngine.resolveMonth(rules: [base(1, 3000, firstDay)],
                                                      spendByDay: [firstDay.key: spentToday],
                                                      year: 2026, month: 9, today: firstDay)
            XCTAssertEqual(month.today?.plannedBeforeTodayCents, 0)
            XCTAssertEqual(budgetPaceText(month).text, "")
            XCTAssertFalse(budgetPaceText(month).warning)
        }
    }

    func testFirstDayStillShowsLowBalanceAndOverspendWarnings() {
        let firstDay = day(2026, 9, 1)
        func month(_ spentToday: Int) -> BudgetMonthResult {
            BudgetRuleEngine.resolveMonth(rules: [base(1, 3000, firstDay)],
                                          spendByDay: [firstDay.key: spentToday],
                                          year: 2026, month: 9, today: firstDay)
        }
        XCTAssertEqual(month(280_000).today?.plannedBeforeTodayCents, 0)
        XCTAssertEqual(budgetPaceText(month(280_000)).text, "只剩 ¥200 啦")
        XCTAssertTrue(budgetPaceText(month(280_000)).warning)
        XCTAssertEqual(budgetPaceText(month(310_000)).text, "这个月已经超出预算啦")
        XCTAssertTrue(budgetPaceText(month(310_000)).warning)
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
                       "这次修改会调整5月以来的预算，已记录的账单不变。")
        XCTAssertNil(budgetBaseEditWarning(original: nil, amountCents: 600000, unit: .week, today: today))
    }

    func testBaseEditWarningStopsAtActualTakeover() {
        let may = base(1, 5000, day(2026, 5, 1))
        let oct = base(2, 6000, day(2026, 10, 1))
        XCTAssertEqual(budgetBaseEditWarning(original: may, amountCents: 520000, unit: .month,
                                            today: day(2026, 11, 2), existing: [may, oct]),
                       "这次修改会调整5月–9月的预算，已记录的账单不变。")
        let sameMonth = base(3, 7000, day(2026, 5, 1))
        XCTAssertNil(budgetBaseEditWarning(original: may, amountCents: 520000, unit: .month,
                                          today: today, existing: [may, sameMonth]))
    }

    func testUpcomingBaseSpanRetainsKnownTakeoverEnd() {
        let oct = base(1, 5000, day(2026, 10, 1))
        let dec = base(2, 6000, day(2026, 12, 1))
        let span = budgetRuleSpan(oct, rules: [oct, dec], today: today)
        XCTAssertEqual(span.state, .upcoming)
        XCTAssertEqual(span.text, "10月起")
        XCTAssertEqual(span.effectiveEnd, day(2026, 11, 30))
        XCTAssertNil(budgetRuleSpan(dec, rules: [oct, dec], today: today).effectiveEnd)
    }

    func testUpcomingBaseEditWarningStopsAtKnownTakeover() {
        let oct = base(1, 5000, day(2026, 10, 1))
        let dec = base(2, 6000, day(2026, 12, 1))
        XCTAssertEqual(budgetBaseEditWarning(original: oct, amountCents: 520000, unit: .month,
                                            today: today, existing: [oct, dec]),
                       "这次修改会调整10月–11月的预算，已记录的账单不变。")
    }

    func testBaseEditWarningIncludesYearsAndSingleMonth() {
        let dec = base(1, 5000, day(2025, 12, 1))
        let feb = base(2, 6000, day(2026, 2, 1))
        XCTAssertEqual(budgetBaseEditWarning(original: dec, amountCents: 520000, unit: .month,
                                            today: today, existing: [dec, feb]),
                       "这次修改会调整2025年12月–2026年1月的预算，已记录的账单不变。")
        let jan = base(3, 6000, day(2026, 1, 1))
        XCTAssertEqual(budgetBaseEditWarning(original: dec, amountCents: 520000, unit: .month,
                                            today: today, existing: [dec, jan]),
                       "这次修改会调整2025年12月的预算，已记录的账单不变。")
    }

    func testEndedBasePreviewUsesLastOwnedMonthAndEngineTotals() {
        let may = base(1, 5000, day(2026, 5, 1))
        let oct = base(2, 6000, day(2026, 10, 1))
        let edited = base(1, 5200, day(2026, 5, 1))
        let lines = budgetRulePreview(existing: [may, oct], candidate: edited, today: day(2026, 11, 2)).map(\.text)
        XCTAssertEqual(lines.first, "9月预算 ¥5,000 → ¥5,200")
        XCTAssertFalse(lines.contains { $0.contains("11月") })
        let replaced = base(3, 7000, day(2026, 5, 1))
        XCTAssertEqual(budgetRulePreview(existing: [may, replaced], candidate: edited, today: today).map(\.text),
                       ["这条日常预算没有生效过，修改后仍不影响任何月份"])
    }

    func testUpcomingBasePreviewUsesFirstOwnedFutureMonth() {
        let oct = base(1, 5000, day(2026, 10, 1))
        let dec = base(2, 6000, day(2026, 12, 1))
        let edited = base(1, 5200, day(2026, 10, 1))
        let lines = budgetRulePreview(existing: [oct, dec], candidate: edited, today: today).map(\.text)
        XCTAssertEqual(lines.first, "10月预算 ¥5,000 → ¥5,200")
        XCTAssertFalse(lines.contains { $0.contains("9月") || $0.contains("12月") })
    }

    func testSpecialPreviewExplainsFullMonthOverrideAndEditedReduction() {
        let daily = base(1, 3000, day(2026, 10, 1))
        let override = special(2, 1000, day(2026, 10, 1), day(2026, 10, 31), unit: .month)
        let lines = budgetRulePreview(existing: [daily], candidate: override, today: today).map(\.text)
        XCTAssertEqual(lines[1], "10月一共 ¥1,000（少了 ¥2,000）")
        let previous = special(2, 2000, day(2026, 10, 1), day(2026, 10, 31), unit: .month, funding: .extra)
        let reduced = special(2, 1000, day(2026, 10, 1), day(2026, 10, 31), unit: .month, funding: .extra)
        let editLines = budgetRulePreview(existing: [daily, previous], candidate: reduced, today: today).map(\.text)
        XCTAssertTrue(editLines[1].contains("少了 ¥1,000"))
        XCTAssertFalse(editLines[1].contains("多了 -"))
    }

    private func suggestionSpend(_ cents: Int, on day: BudgetCivilDay, id: UUID = UUID(),
                                 refundOf: UUID? = nil, excluded: Bool = false,
                                 currency: String = "CNY", createdAt: Date? = nil,
                                 expense: Bool = true) -> BudgetSpendRow {
        BudgetSpendRow(id: id, isExpense: expense, amountCents: cents, currencyCode: currency,
                       attributionDay: day, createdAt: createdAt, refundOfID: refundOf, isExcluded: excluded)
    }

    func testSuggestionUsesRefundNetAndIgnoresExcludedForeignAndFullyRefundedMonths() {
        let original = UUID()
        let fullyRefunded = UUID()
        let rows = [
            suggestionSpend(100_000, on: day(2026, 8, 10), id: original),
            suggestionSpend(-90_000, on: day(2026, 9, 2), refundOf: original),
            suggestionSpend(300_000, on: day(2026, 6, 10), excluded: true),
            suggestionSpend(900_000, on: day(2026, 6, 11), currency: "USD"),
            suggestionSpend(800_000, on: day(2026, 6, 12), expense: false),
            suggestionSpend(20_000, on: day(2026, 7, 1), id: fullyRefunded),
            suggestionSpend(-20_000, on: day(2026, 9, 3), refundOf: fullyRefunded),
        ]
        XCTAssertEqual(budgetSuggestedMonthlyYuan(rows, today: today, knowledgeCutoff: .distantFuture), 100)
        XCTAssertNil(budgetSuggestedMonthlyYuan(Array(rows[2...4]), today: today, knowledgeCutoff: .distantFuture))
        XCTAssertNil(budgetSuggestedMonthlyYuan(Array(rows[5...6]), today: today, knowledgeCutoff: .distantFuture))
        XCTAssertNil(budgetSuggestedMonthlyYuan([], today: today, knowledgeCutoff: .distantFuture))
    }

    func testSuggestionOnlyUsesLastThreeCompleteMonthsAcrossYearAndPreservesRoundingOrder() {
        let january = day(2027, 1, 18)
        let rows = [
            suggestionSpend(10_000, on: day(2026, 10, 1)),
            suggestionSpend(50_000, on: day(2026, 12, 31)),
            suggestionSpend(900_000, on: day(2026, 9, 30)),
            suggestionSpend(800_000, on: day(2027, 1, 1)),
        ]
        XCTAssertEqual(budgetSuggestedMonthlyYuan(rows, today: january, knowledgeCutoff: .distantFuture), 300)
        XCTAssertEqual(budgetSuggestedMonthlyYuan([suggestionSpend(14_949, on: day(2026, 12, 1))],
                                                 today: january, knowledgeCutoff: .distantFuture), 100)
        XCTAssertEqual(budgetSuggestedMonthlyYuan([suggestionSpend(14_950, on: day(2026, 12, 1))],
                                                 today: january, knowledgeCutoff: .distantFuture), 200)
    }

    func testSuggestionDoesNotUseRefundsThatAreNotKnownYet() {
        let original = UUID()
        let cutoff = Date(timeIntervalSince1970: 1_000)
        let rows = [
            suggestionSpend(100_000, on: day(2026, 8, 10), id: original, createdAt: cutoff),
            suggestionSpend(-100_000, on: day(2026, 8, 10), refundOf: original,
                            createdAt: cutoff.addingTimeInterval(1)),
        ]
        XCTAssertEqual(budgetSuggestedMonthlyYuan(rows, today: today, knowledgeCutoff: cutoff), 1000)
        XCTAssertNil(budgetSuggestedMonthlyYuan(rows, today: today, knowledgeCutoff: cutoff.addingTimeInterval(1)))
    }

    func testSuggestionIgnoresStandaloneNonpositiveRootsButKeepsLinkedRefunds() {
        let original = UUID()
        let rows = [
            suggestionSpend(100_000, on: day(2026, 8, 10), id: original),
            suggestionSpend(-40_000, on: day(2026, 9, 2), refundOf: original),
            suggestionSpend(-50_000, on: day(2026, 8, 11)),
            suggestionSpend(0, on: day(2026, 6, 10)),
        ]
        XCTAssertEqual(budgetSuggestedMonthlyYuan(rows, today: today, knowledgeCutoff: .distantFuture), 600)
        XCTAssertNil(budgetSuggestedMonthlyYuan(Array(rows[2...3]), today: today, knowledgeCutoff: .distantFuture))
        XCTAssertEqual(budgetSpendByDay(rows, today: today, knowledgeCutoff: .distantFuture).spend,
                       [20260810: 60_000, 20260811: -50_000])
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
