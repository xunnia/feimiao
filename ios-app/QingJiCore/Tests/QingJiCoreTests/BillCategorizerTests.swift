import XCTest
@testable import QingJiCore

final class BillCategorizerTests: XCTestCase {
    func testProductWinsOverPlatformMerchant() {
        let guess = BillCategorizer.classify(
            merchant: "京东-订单编号349126",
            product: "机械键盘",
            note: "京东 订单付款",
            kind: .expense
        )

        XCTAssertEqual(guess.key, "shop_digital_acc")
        XCTAssertEqual(guess.confidence, .high)
    }

    func testPlatformOnlyFallsBackToSafeTopLevelCategory() {
        let guess = BillCategorizer.classify(
            merchant: "拼多多平台商户",
            product: "订单付款",
            note: "拼多多",
            kind: .expense
        )

        XCTAssertEqual(guess.key, "shopping")
        XCTAssertEqual(guess.confidence, .medium)
    }

    func testDeterministicMerchantUsesMerchantSignal() {
        let guess = BillCategorizer.classify(
            merchant: "中国电信",
            product: "",
            note: "中国电信",
            kind: .expense
        )

        XCTAssertEqual(guess.key, "house_phone")
        XCTAssertEqual(guess.confidence, .high)
        XCTAssertEqual(BillCategorizer.learnKey(for: "中国电信"), "中国电信")
    }

    func testPlatformIsNeverALearningKey() {
        XCTAssertNil(BillCategorizer.learnKey(for: "京东-订单编号349126"))
    }

    func testNormalizeMerchantRemovesNoise() {
        XCTAssertEqual(
            BillCategorizer.normalizeMerchant("京东-订单编号349126"),
            "京东"
        )
        XCTAssertEqual(
            BillCategorizer.normalizeMerchant("M&X*^O^* 转账备注:微信转账"),
            "M&X*^O^*"
        )
    }
}
