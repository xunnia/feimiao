import XCTest
@testable import QingJiCore

final class NaturalLanguageEntryParserTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 12))!
    }

    func testTaxiYesterday() {
        let entry = NaturalLanguageEntryParser.parse("昨天打车23块", at: now, calendar: calendar)
        XCTAssertEqual(entry.amount, 23)
        XCTAssertEqual(entry.kind, .expense)
        XCTAssertEqual(entry.categoryKey, "trans_taxi")
        let day = calendar.component(.day, from: entry.date)
        XCTAssertEqual(day, 11)
    }

    func testColloquialKuaiAmount() {
        let entry = NaturalLanguageEntryParser.parse("午饭23块5", at: now, calendar: calendar)
        XCTAssertEqual(entry.amount, Decimal(string: "23.5"))
        XCTAssertEqual(entry.categoryKey, "dining_lunch")
    }

    func testCurrencySymbol() {
        let entry = NaturalLanguageEntryParser.parse("超市 ¥128.40", at: now, calendar: calendar)
        XCTAssertEqual(entry.amount, Decimal(string: "128.4"))
        XCTAssertEqual(entry.categoryKey, "groceries")
    }

    func testLastNumberFallback() {
        // “2杯”不是金额，应取最后的 58
        let entry = NaturalLanguageEntryParser.parse("买了2杯咖啡58", at: now, calendar: calendar)
        XCTAssertEqual(entry.amount, 58)
        XCTAssertEqual(entry.categoryKey, "dining_drink")
    }

    func testIncomeSalary() {
        let entry = NaturalLanguageEntryParser.parse("发工资20000", at: now, calendar: calendar)
        XCTAssertEqual(entry.kind, .income)
        XCTAssertEqual(entry.categoryKey, "salary")
        XCTAssertEqual(entry.amount, 20000)
    }

    func testRefundIsIncome() {
        let entry = NaturalLanguageEntryParser.parse("淘宝退款35.5元", at: now, calendar: calendar)
        XCTAssertEqual(entry.kind, .income)
        XCTAssertEqual(entry.categoryKey, "refund")
    }

    func testGroceriesBeatsShopping() {
        // “买菜”应命中买菜超市而不是购物的“买”
        let entry = NaturalLanguageEntryParser.parse("买菜45", at: now, calendar: calendar)
        XCTAssertEqual(entry.categoryKey, "groceries")
    }

    func testNoAmount() {
        let entry = NaturalLanguageEntryParser.parse("今天吃了顿好的", at: now, calendar: calendar)
        XCTAssertNil(entry.amount)
        XCTAssertEqual(entry.categoryKey, "dining")
    }

    func testChineseAmountAndAAShareKeepEntryClockPrecision() {
        let entry = NaturalLanguageEntryParser.parse("昨天4个人AA吃饭一百二十块", at: now, calendar: calendar)
        XCTAssertEqual(entry.amount, Decimal(string: "30"))
        XCTAssertEqual(entry.categoryKey, "dining")
        XCTAssertEqual(entry.timePrecision, .entryClock)
        XCTAssertEqual(entry.confidence, 0.55)
    }

    func testDayOfMonthAndExplicitClock() {
        let entry = NaturalLanguageEntryParser.parse("13号下午 3:20 收款300", at: now, calendar: calendar)
        XCTAssertEqual(entry.kind, .income)
        XCTAssertEqual(entry.amount, 300)
        XCTAssertEqual(calendar.component(.day, from: entry.date), 13)
        XCTAssertEqual(calendar.component(.hour, from: entry.date), 15)
        XCTAssertEqual(calendar.component(.minute, from: entry.date), 20)
        XCTAssertEqual(entry.timePrecision, .exact)
    }
}

final class AIRecordProposalTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    func testDecodesMultipleEntriesAndDateOnlyInheritsClock() throws {
        let fallback = calendar.date(from: DateComponents(year: 2026, month: 8, day: 27, hour: 12, minute: 34))!
        let result = try XCTUnwrap(AIRecordProposalCodec.decode(
            "```json\n{\"intent\":\"record\",\"entries\":[{\"amount\":23,\"kind\":\"expense\",\"categoryKey\":\"trans_taxi\",\"date\":\"2026-08-26\",\"note\":\"打车\",\"confidence\":0.91},{\"amount\":\"8.50\",\"kind\":\"income\",\"categoryKey\":\"bad-key\",\"date\":\"2026-08-27T09:10:00+08:00\",\"note\":\"补贴\",\"confidence\":1.2}]}\n```",
            fallbackDate: fallback,
            allowedCategoryKeys: ["trans_taxi", "otherIncome"],
            calendar: calendar
        ))

        XCTAssertEqual(result.intent, .record)
        XCTAssertEqual(result.entries.count, 2)
        XCTAssertEqual(result.entries[0].amount, 23)
        XCTAssertEqual(result.entries[0].timePrecision, .entryClock)
        XCTAssertEqual(calendar.component(.hour, from: result.entries[0].date), 12)
        XCTAssertNil(result.entries[1].categoryKey)
        XCTAssertEqual(result.entries[1].confidence, 1)
        XCTAssertEqual(result.entries[1].timePrecision, .exact)
    }

    func testInvalidJsonReturnsNil() {
        XCTAssertNil(AIRecordProposalCodec.decode("不是 JSON"))
    }
}

final class RefundMatcherTests: XCTestCase {
    func testMatchesOnlyTheUniqueOriginalAndRejectsOverRefund() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 12))!
        let candidate = RefundCandidate(
            id: UUID(),
            label: "淘宝 机械键盘",
            amount: 280,
            refunded: 20,
            date: day
        )
        let matched = RefundMatcher.match(
            text: "8月20日淘宝机械键盘退款30",
            candidates: [candidate],
            amount: RefundMatcher.extractAmount("8月20日淘宝机械键盘退款30"),
            now: day,
            calendar: calendar
        )
        XCTAssertEqual(matched.status, .matched)
        XCTAssertEqual(matched.amount, 30)
        XCTAssertEqual(matched.candidate?.id, candidate.id)

        let tooMuch = RefundMatcher.match(
            text: "淘宝机械键盘退款300",
            candidates: [candidate],
            amount: 300,
            now: day,
            calendar: calendar
        )
        XCTAssertEqual(tooMuch.status, .exceedsRemaining)
    }

    func testQuestionDoesNotMutateLedger() {
        let result = RefundMatcher.match(
            text: "本月退款多少",
            candidates: [],
            amount: nil
        )
        XCTAssertEqual(result.status, .notRefundMutation)
    }
}

final class PaymentScreenshotParserTests: XCTestCase {
    func testWeChatPaymentScreenshot() {
        let ocr = """
        支付成功
        -88.50
        老王煎饼店
        支付方式 零钱
        余额 12.30
        """
        XCTAssertEqual(PaymentScreenshotParser.extractAmount(fromOCRText: ocr), Decimal(string: "88.5"))
    }

    func testCurrencyMarkedAmountWins() {
        let ocr = """
        订单编号 20260612001
        ¥1,299.00
        积分 5000
        """
        XCTAssertEqual(PaymentScreenshotParser.extractAmount(fromOCRText: ocr), 1299)
    }

    func testNoAmount() {
        XCTAssertNil(PaymentScreenshotParser.extractAmount(fromOCRText: "支付失败，请重试"))
    }
}
