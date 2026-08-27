import XCTest
@testable import QingJiCore

final class ChatIntentTests: XCTestCase {
    func testExplicitLedgerQuestionIsQuery() {
        XCTAssertEqual(
            ChatIntent.classify("本月餐饮花了多少", hasArabicAmount: false),
            .query
        )
    }

    func testKnowledgeQuestionWithNumbersIsChat() {
        XCTAssertEqual(
            ChatIntent.classify("推荐 3 部电影，预算 500 元够吗？", hasArabicAmount: true),
            .chat
        )
    }

    func testExpensePhraseWithBareAmountIsRecord() {
        XCTAssertEqual(
            ChatIntent.classify("午饭 28", hasArabicAmount: true),
            .record
        )
    }

    func testPlainAmountWithoutLedgerContextIsChat() {
        XCTAssertEqual(
            ChatIntent.classify("我写了 500 字", hasArabicAmount: true),
            .chat
        )
    }
}
