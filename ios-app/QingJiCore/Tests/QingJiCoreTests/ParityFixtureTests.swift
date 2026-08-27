import XCTest
@testable import QingJiCore

/// 安卓 integration_test/parity_screenshots_test.dart 使用的当前稳定演示
/// fixture 的 iOS 统计合同。页面截图可以有原生视觉差异，但这组数字不能漂移。
final class ParityFixtureTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: day,
            hour: 12
        ))!
    }

    private func fixtureRecords() -> [TransactionRecord] {
        let rows: [(Decimal, TransactionKind, String, String, Int)] = [
            (38, .expense, "食品餐饮", "午餐 麦当劳", 27),
            (23, .expense, "出行交通", "滴滴打车", 25),
            (156, .expense, "生鲜食品", "盒马超市", 23),
            (88, .expense, "休闲娱乐", "网易云音乐年费", 21),
            (45, .expense, "食品餐饮", "晚餐 外卖", 19),
            (198, .expense, "购物消费", "优衣库 T 恤", 17),
            (12, .expense, "出行交通", "公交充值", 15),
            (68, .expense, "食品餐饮", "朋友聚餐 AA", 13),
            (30, .expense, "居家住房", "话费充值", 11),
            (280, .expense, "购物消费", "京东 数据线+充电头", 9),
            (Decimal(string: "9.9")!, .expense, "虚拟充值", "微信读书月卡", 7),
            (15, .expense, "食品餐饮", "咖啡 瑞幸", 5),
            (52, .expense, "生鲜食品", "菜市场买菜", 3),
            (18, .expense, "出行交通", "共享单车月卡", 1),
            (120, .income, "工资薪酬", "兼职收入", 27),
            (500, .income, "礼金红包", "朋友红包", 25),
        ]
        let originals = rows.map { amount, kind, category, note, day in
            TransactionRecord(
                kind: kind,
                amount: amount,
                categoryName: category,
                topCategoryName: category,
                date: date(day)
            )
        }
        let lunchID = originals[0].id
        let refund = TransactionRecord(
            kind: .expense,
            amount: -15,
            categoryName: "食品餐饮",
            topCategoryName: "食品餐饮",
            date: date(27),
            eventType: .refund,
            refundOfID: lunchID
        )
        return originals + [refund,
            TransactionRecord(
                kind: .transfer,
                amount: 120,
                note: "账户转入",
                date: date(17),
                eventType: .transfer
            )]
    }

    func testCurrentAndroidFixtureHasStableMonthlyTotals() {
        let records = fixtureRecords()
        let summary = StatisticsEngine.monthlySummary(
            of: records,
            year: 2026,
            month: 8,
            calendar: calendar
        )

        XCTAssertEqual(summary.totalExpense, Decimal(string: "1017.9")!)
        XCTAssertEqual(summary.totalIncome, 620)
        XCTAssertEqual(summary.balance, Decimal(string: "-397.9")!)
        XCTAssertEqual(summary.expenseByCategory.map(\.name), [
            "购物消费", "生鲜食品", "食品餐饮", "休闲娱乐", "出行交通", "居家住房", "虚拟充值",
        ])
        XCTAssertEqual(summary.expenseByCategory.map(\.total), [
            478, 208, 151, 88, 53, 30, Decimal(string: "9.9")!,
        ])
        XCTAssertEqual(summary.expenseByCategory.map(\.count), [2, 2, 4, 1, 3, 1, 1])
        XCTAssertEqual(summary.dailyTotals.count, 31)
    }

    func testFixtureRefundIsOneVisibleExpenseFamily() {
        let records = fixtureRecords()
        let visible = LedgerPolicy.userRecords(from: records)
        XCTAssertEqual(visible.filter { $0.kind == .expense }.count, 14)
        XCTAssertEqual(visible.first?.amount, Decimal(string: "23"))
        XCTAssertEqual(LedgerPolicy.expenseFamilyCount(from: records), 14)
    }
}
