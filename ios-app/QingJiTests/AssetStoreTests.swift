import XCTest
import SwiftData
import QingJiCore
@testable import QingJi

@MainActor
final class AssetStoreTests: XCTestCase {
    private final class Stack {
        let container: ModelContainer
        let context: ModelContext

        init() throws {
            let schema = Schema([
                Account.self,
                Book.self,
                TxCategory.self,
                MoneyTransaction.self,
                PhysicalAsset.self,
                AssetEvent.self,
                AssetUsageEvent.self,
                AssetTransactionLink.self,
                AssetRefundAllocation.self,
                AssetValuation.self,
            ])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let modelContainer = try ModelContainer(for: schema, configurations: [configuration])
            container = modelContainer
            context = ModelContext(modelContainer)
        }
    }

    func testMetricsUsePurchaseCostAndShowDailyHoldingCost() throws {
        let schema = Schema([
            PhysicalAsset.self,
            AssetValuation.self,
            AssetTransactionLink.self,
            AssetRefundAllocation.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let calendar = Calendar(identifier: .gregorian)
        let purchaseDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let asOf = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let asset = PhysicalAsset(
            name: "测试手机",
            kind: .digital,
            purchasePrice: 1_000,
            currentValue: 880
        )
        asset.purchaseDate = purchaseDate
        context.insert(asset)
        context.insert(AssetValuation(assetID: asset.stableID, value: 880, valuedAt: asOf))
        try context.save()

        let metrics = try AssetStore.metrics(for: asset, in: context, asOf: asOf)
        XCTAssertEqual(metrics.heldDays.value, 10)
        XCTAssertEqual(metrics.cumulativeHoldingInvestment.value, 1_000)
        XCTAssertEqual(metrics.dailyHoldingCost.value, 100)
        XCTAssertEqual(metrics.valueRetentionRatio.value, Decimal(string: "0.88"))
    }

    func testSellingMovesCashWithoutEnteringNormalIncomeAndCanBeUndone() throws {
        let stack = try Stack()
        let book = Book(name: "测试账本", isDefault: true)
        let cash = Account(name: "现金", kind: .cash)
        cash.initialBalance = 100
        let asset = PhysicalAsset(
            name: "测试相机",
            kind: .digital,
            purchasePrice: 1_000,
            currentValue: 800,
            bookID: book.stableID
        )
        asset.purchaseDate = Date(timeIntervalSince1970: 1_690_000_000)
        stack.context.insert(book)
        stack.context.insert(cash)
        stack.context.insert(asset)
        try stack.context.save()

        let soldAt = Date(timeIntervalSince1970: 1_700_000_000)
        let sale = try AssetStore.sell(
            asset,
            grossProceeds: 500,
            fee: 20,
            account: cash,
            at: soldAt,
            in: stack.context
        )
        let saleTransaction = try XCTUnwrap(sale)
        XCTAssertEqual(saleTransaction.amount, 480)
        XCTAssertEqual(saleTransaction.kind, .income)
        XCTAssertEqual(saleTransaction.eventType, .assetSale)
        XCTAssertTrue(saleTransaction.isExcluded)
        XCTAssertEqual(asset.lifecycle, .sold)
        XCTAssertEqual(asset.currentValue, 0)
        XCTAssertFalse(asset.includeInNetWorth)
        XCTAssertEqual(
            LedgerStore.accountBalance(
                for: cash,
                transactions: try stack.context.fetch(FetchDescriptor<MoneyTransaction>())
            ),
            580
        )

        try AssetStore.undoSale(asset, at: soldAt.addingTimeInterval(60), in: stack.context)
        XCTAssertEqual(asset.lifecycle, .owned)
        XCTAssertEqual(asset.currentValue, 800)
        XCTAssertTrue(asset.includeInNetWorth)
        XCTAssertEqual(
            try stack.context.fetchCount(FetchDescriptor<MoneyTransaction>()),
            0
        )
    }

    func testReturnRefundsCompletePurchaseAndUndoKeepsRefundAudit() throws {
        let stack = try Stack()
        let book = Book(name: "测试账本", isDefault: true)
        let cash = Account(name: "现金", kind: .cash)
        let asset = PhysicalAsset(
            name: "测试耳机",
            kind: .digital,
            purchasePrice: 80,
            currentValue: 50,
            bookID: book.stableID
        )
        asset.purchaseDate = Date(timeIntervalSince1970: 1_690_000_000)
        stack.context.insert(book)
        stack.context.insert(cash)
        stack.context.insert(asset)
        try stack.context.save()
        let original = try LedgerStore.createTransaction(
            in: stack.context,
            amount: 80,
            kind: .expense,
            date: asset.purchaseDate!,
            note: "耳机购置",
            account: cash,
            book: book
        )
        _ = try AssetStore.linkPurchaseAllocation(
            asset,
            transaction: original,
            grossCents: 8_000,
            in: stack.context
        )

        let returnedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let refund = try AssetStore.returnToPurchase(
            asset,
            at: returnedAt,
            in: stack.context
        )
        XCTAssertEqual(refund.amount, -80)
        XCTAssertEqual(refund.refundOfID, original.stableID)
        XCTAssertEqual(asset.lifecycle, .returned)
        XCTAssertEqual(asset.currentValue, 0)
        XCTAssertEqual(
            try stack.context.fetchCount(FetchDescriptor<MoneyTransaction>()),
            2
        )

        try AssetStore.undoReturn(asset, at: returnedAt.addingTimeInterval(60), in: stack.context)
        XCTAssertEqual(asset.lifecycle, .owned)
        XCTAssertEqual(asset.currentValue, 50)
        XCTAssertEqual(
            try stack.context.fetchCount(FetchDescriptor<MoneyTransaction>()),
            2
        )
    }

    func testHistoricalValuationDoesNotOverwriteCurrentValue() throws {
        let stack = try Stack()
        let asset = PhysicalAsset(
            name: "测试相机",
            kind: .digital,
            purchasePrice: 1_000,
            currentValue: 800
        )
        let january10 = Date(timeIntervalSince1970: 1_705_000_000)
        let january11 = january10.addingTimeInterval(86_400)
        stack.context.insert(asset)
        stack.context.insert(AssetValuation(
            assetID: asset.stableID,
            value: 800,
            valuedAt: january10
        ))
        try stack.context.save()

        _ = try AssetStore.updateCurrentValue(
            asset,
            value: 700,
            at: january10.addingTimeInterval(-86_400),
            in: stack.context
        )
        XCTAssertEqual(asset.currentValue, 800)

        _ = try AssetStore.updateCurrentValue(
            asset,
            value: 650,
            at: january11,
            in: stack.context
        )
        XCTAssertEqual(asset.currentValue, 650)
        XCTAssertTrue(asset.depreciationPaused)
    }

    func testLinearDepreciationReachesMonthlyValueWithoutCashflow() throws {
        let stack = try Stack()
        let asset = PhysicalAsset(
            name: "测试电脑",
            kind: .digital,
            purchasePrice: 1_000,
            currentValue: 1_000
        )
        let start = Date(timeIntervalSince1970: 1_704_067_200)
        let asOf = Date(timeIntervalSince1970: 1_711_929_600)
        asset.purchaseDate = start
        stack.context.insert(asset)
        stack.context.insert(AssetValuation(assetID: asset.stableID, value: 1_000, valuedAt: start))
        try stack.context.save()

        try AssetStore.configureDepreciation(
            asset,
            enabled: true,
            base: 1_000,
            salvageValue: 100,
            usefulLifeMonths: 10,
            startAt: start,
            at: start,
            in: stack.context
        )
        XCTAssertEqual(try AssetStore.applyDepreciation(asOf: asOf, in: stack.context), 1)
        XCTAssertLessThan(asset.currentValue, 1_000)
        XCTAssertGreaterThanOrEqual(asset.currentValue, 100)
        XCTAssertEqual(
            try stack.context.fetchCount(FetchDescriptor<MoneyTransaction>()),
            0
        )
    }

    func testTerminalAssetStatusZeroesValueAndCanBeUndone() throws {
        let stack = try Stack()
        let asset = PhysicalAsset(
            name: "测试物品",
            kind: .other,
            purchasePrice: 100,
            currentValue: 60
        )
        stack.context.insert(asset)
        try stack.context.save()

        let endedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try AssetStore.end(
            asset,
            lifecycle: .disposed,
            at: endedAt,
            note: "损坏",
            in: stack.context
        )
        XCTAssertEqual(asset.lifecycle, .disposed)
        XCTAssertEqual(asset.currentValue, 0)
        XCTAssertFalse(asset.includeInNetWorth)

        try AssetStore.undoEnd(asset, at: endedAt.addingTimeInterval(60), in: stack.context)
        XCTAssertEqual(asset.lifecycle, .owned)
        XCTAssertEqual(asset.currentValue, 60)
        XCTAssertTrue(asset.includeInNetWorth)
    }
}
