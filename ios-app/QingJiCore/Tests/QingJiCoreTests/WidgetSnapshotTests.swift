import XCTest
@testable import QingJiCore

final class WidgetSnapshotTests: XCTestCase {
    func testSnapshotRoundTripsWithoutFloatingPointAmounts() throws {
        let snapshot = WidgetSnapshot(
            generatedAtMs: 1_725_000_000_000,
            bookName: "总账本",
            dateText: "8月27日",
            todayExpenseText: "¥23.00",
            monthExpenseText: "¥1,017.90",
            monthIncomeText: "¥620.00",
            balanceText: "¥-397.90",
            budgetTitle: "预算剩余",
            budgetText: "¥1,982.10",
            budgetHint: "已用 ¥1,017.90 / ¥3,000.00",
            budgetProgress: 34,
            paceCaption: "截至8月27日",
            paceAverageText: "--",
            privacyMode: false,
            categories: [WidgetCategorySnapshot(
                id: "shopping",
                name: "购物消费",
                amountText: "¥478.00",
                percentText: "47%",
                progress: 47,
                count: 2
            )]
        )
        let data = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(restored, snapshot)
        XCTAssertEqual(restored.categories.first?.amountText, "¥478.00")
    }
}
