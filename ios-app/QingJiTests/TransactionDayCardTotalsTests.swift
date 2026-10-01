import XCTest
import SwiftData
import QingJiCore
@testable import QingJi

/// 账单日卡的当天合计和「已退」金额（07 F-TXN-013、F-TXN-008）。
/// 回归：主页传进来的退款合计是负数，曾把 38 元、退 15 元的午餐算成 53 元。
@MainActor
final class TransactionDayCardTotalsTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        let schema = Schema([Account.self, Book.self, TxCategory.self, MoneyTransaction.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
    }

    override func tearDown() {
        container = nil
    }

    private func insert(_ transaction: MoneyTransaction) -> MoneyTransaction {
        container.mainContext.insert(transaction)
        return transaction
    }

    func testRefundTotalsWithEitherSignGiveTheSameNetAndBadge() {
        let lunch = insert(MoneyTransaction(amount: 38, kind: .expense))
        let refund = insert(MoneyTransaction(amount: -15, kind: .expense, refundOfID: lunch.stableID))
        let items = [lunch, refund]

        // LedgerPolicy.refundTotals 的原样输出（负数），主页就是这样传的。
        let raw: [UUID: Decimal] = [lunch.stableID: -15]
        // 其他页面先转成正数再传。
        let normalized: [UUID: Decimal] = [lunch.stableID: 15]

        XCTAssertEqual(TransactionDayCard.dayExpense(items, refundByID: raw), 23)
        XCTAssertEqual(TransactionDayCard.dayExpense(items, refundByID: normalized), 23)
        XCTAssertEqual(TransactionDayCard.refundAmount(for: lunch, in: raw), 15)
        XCTAssertEqual(TransactionDayCard.refundAmount(for: lunch, in: normalized), 15)
        XCTAssertEqual(TransactionDayCard.refundAmount(for: refund, in: raw), 0)
    }

    func testFullRefundLeavesZero() {
        let order = insert(MoneyTransaction(amount: 99, kind: .expense))
        let refund = insert(MoneyTransaction(amount: -99, kind: .expense, refundOfID: order.stableID))
        XCTAssertEqual(TransactionDayCard.dayExpense([order, refund], refundByID: [order.stableID: -99]), 0)
    }

    func testExcludedRowsDoNotCount() {
        let counted = insert(MoneyTransaction(amount: 50, kind: .expense))
        let excludedExpense = insert(MoneyTransaction(amount: 200, kind: .expense, isExcluded: true))
        let salary = insert(MoneyTransaction(amount: 120, kind: .income))
        let excludedIncome = insert(MoneyTransaction(amount: 1000, kind: .income, isExcluded: true))
        let items = [counted, excludedExpense, salary, excludedIncome]

        XCTAssertEqual(TransactionDayCard.dayExpense(items, refundByID: [:]), 50)
        XCTAssertEqual(TransactionDayCard.dayIncome(items), 120)
    }

    func testLegacyStandaloneNegativeExpenseOffsetsLikeStatistics() {
        // 没挂原单的老式负支出：照原额冲减，和统计页 / 安卓日卡一致，不猜成退款。
        let coffee = insert(MoneyTransaction(amount: 30, kind: .expense))
        let legacyOffset = insert(MoneyTransaction(amount: -10, kind: .expense))
        XCTAssertEqual(TransactionDayCard.dayExpense([coffee, legacyOffset], refundByID: [:]), 20)
    }

    func testTransfersAreIgnored() {
        let expense = insert(MoneyTransaction(amount: 12, kind: .expense))
        let transfer = insert(MoneyTransaction(amount: 500, kind: .transfer))
        XCTAssertEqual(TransactionDayCard.dayExpense([expense, transfer], refundByID: [:]), 12)
        XCTAssertEqual(TransactionDayCard.dayIncome([expense, transfer]), 0)
    }
}
