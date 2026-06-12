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
        XCTAssertEqual(entry.categoryKey, "transport")
        let day = calendar.component(.day, from: entry.date)
        XCTAssertEqual(day, 11)
    }

    func testColloquialKuaiAmount() {
        let entry = NaturalLanguageEntryParser.parse("午饭23块5", at: now, calendar: calendar)
        XCTAssertEqual(entry.amount, Decimal(string: "23.5"))
        XCTAssertEqual(entry.categoryKey, "dining")
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
        XCTAssertEqual(entry.categoryKey, "dining")
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
