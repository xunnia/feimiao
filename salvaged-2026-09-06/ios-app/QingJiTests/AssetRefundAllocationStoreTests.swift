import XCTest
import SwiftData
import QingJiCore
@testable import QingJi

@MainActor
final class AssetRefundAllocationStoreTests: XCTestCase {
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
                ReceivableAsset.self,
                ReceivableRecovery.self,
            ])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let modelContainer = try ModelContainer(for: schema, configurations: [configuration])
            container = modelContainer
            context = ModelContext(modelContainer)
        }
    }

    private func seed(_ stack: Stack) throws -> (Book, Account, TxCategory) {
        let book = Book(name: "测试账本", isDefault: true)
        let account = Account(name: "现金", kind: .cash)
        let category = TxCategory(key: "shopping", name: "购物", symbol: "bag", kind: .expense)
        stack.context.insert(book)
        stack.context.insert(account)
        stack.context.insert(category)
        try stack.context.save()
        return (book, account, category)
    }

    func testFullOrderRefundIsAutoAllocatedAndDeletionReversesTheAudit() throws {
        let stack = try Stack()
        let (book, account, category) = try seed(stack)
        let original = try LedgerStore.createTransaction(
            in: stack.context,
            amount: 100,
            kind: .expense,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            note: "购买相机",
            category: category,
            account: account,
            book: book
        )
        let asset = try AssetStore.createFromTransaction(
            in: stack.context,
            transaction: original,
            name: "相机",
            kind: .digital,
            allocatedGrossCents: 10_000,
            currentValue: 80
        )

        let refund = try LedgerStore.createOffset(
            for: original,
            amount: 25,
            note: "部分退款",
            eventType: .refund,
            settlementAccount: account,
            in: stack.context
        )
        let link = try XCTUnwrap(
            stack.context.fetch(FetchDescriptor<AssetTransactionLink>())
                .first(where: { $0.assetID == asset.stableID })
        )
        XCTAssertEqual(link.allocatedRefundCents, 2_500)
        XCTAssertEqual(
            try stack.context.fetch(FetchDescriptor<AssetRefundAllocation>())
                .filter { $0.statusRaw == "active" }
                .count,
            1
        )
        XCTAssertTrue(try AssetRefundAllocationStore.pendingRefundAllocations(for: asset, in: stack.context).isEmpty)
        XCTAssertEqual(asset.purchasePrice, 75)

        try LedgerStore.delete(refund, in: stack.context)
        XCTAssertEqual(link.allocatedRefundCents, 0)
        XCTAssertEqual(asset.purchasePrice, 100)
        XCTAssertTrue(
            try stack.context.fetch(FetchDescriptor<AssetRefundAllocation>())
                .allSatisfy { $0.statusRaw == "reversed" }
        )
    }

    func testMultiAssetRefundMustBeSplitBetweenAssets() throws {
        let stack = try Stack()
        let (book, account, category) = try seed(stack)
        let original = try LedgerStore.createTransaction(
            in: stack.context,
            amount: 120,
            kind: .expense,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            note: "两件商品",
            category: category,
            account: account,
            book: book
        )
        let first = try AssetStore.createFromTransaction(
            in: stack.context,
            transaction: original,
            name: "商品 A",
            kind: .other,
            allocatedGrossCents: 7_000,
            currentValue: 70
        )
        let second = try AssetStore.createFromTransaction(
            in: stack.context,
            transaction: original,
            name: "商品 B",
            kind: .other,
            allocatedGrossCents: 5_000,
            currentValue: 50
        )
        let refund = try LedgerStore.createOffset(
            for: original,
            amount: 30,
            note: "组合订单退款",
            eventType: .refund,
            settlementAccount: account,
            in: stack.context
        )

        let pending = try AssetRefundAllocationStore.pendingRefundAllocations(for: first, in: stack.context)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].refundCents, 3_000)
        XCTAssertEqual(pending[0].untrackedLimitCents, 0)
        XCTAssertEqual(pending[0].remainingCents, 3_000)

        XCTAssertThrowsError(
            try AssetRefundAllocationStore.allocateRefund(
                refundTransactionID: refund.stableID,
                allocationsByAssetID: [first.stableID: 1_000],
                in: stack.context
            )
        ) { error in
            XCTAssertEqual(error as? AssetRefundAllocationStore.Error, .amountMismatch)
        }
        try AssetRefundAllocationStore.allocateRefund(
            refundTransactionID: refund.stableID,
            allocationsByAssetID: [first.stableID: 1_000, second.stableID: 2_000],
            in: stack.context
        )

        let links = try stack.context.fetch(FetchDescriptor<AssetTransactionLink>())
        XCTAssertEqual(links.first(where: { $0.assetID == first.stableID })?.allocatedRefundCents, 1_000)
        XCTAssertEqual(links.first(where: { $0.assetID == second.stableID })?.allocatedRefundCents, 2_000)
        XCTAssertEqual(first.purchasePrice, 60)
        XCTAssertEqual(second.purchasePrice, 30)
        XCTAssertTrue(try AssetRefundAllocationStore.pendingRefundAllocations(for: first, in: stack.context).isEmpty)
        XCTAssertEqual(
            try stack.context.fetch(FetchDescriptor<AssetRefundAllocation>())
                .filter { $0.statusRaw == "active" }
                .map(\.allocatedRefundCents)
                .reduce(0, +),
            3_000
        )
    }

    func testUntrackedOrderPortionCanReceivePartOfTheRefund() throws {
        let stack = try Stack()
        let (book, account, category) = try seed(stack)
        let original = try LedgerStore.createTransaction(
            in: stack.context,
            amount: 120,
            kind: .expense,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            note: "订单含未登记物品",
            category: category,
            account: account,
            book: book
        )
        let asset = try AssetStore.createFromTransaction(
            in: stack.context,
            transaction: original,
            name: "已登记物品",
            kind: .other,
            allocatedGrossCents: 7_000,
            currentValue: 70
        )
        let refund = try LedgerStore.createOffset(
            for: original,
            amount: 30,
            note: "部分退款",
            eventType: .refund,
            settlementAccount: account,
            in: stack.context
        )
        let pending = try XCTUnwrap(
            AssetRefundAllocationStore.pendingRefundAllocations(for: asset, in: stack.context).first
        )
        XCTAssertEqual(pending.untrackedLimitCents, 5_000)

        try AssetRefundAllocationStore.allocateRefund(
            refundTransactionID: refund.stableID,
            allocationsByAssetID: [asset.stableID: 2_000],
            untrackedCents: 1_000,
            in: stack.context
        )
        let link = try XCTUnwrap(
            stack.context.fetch(FetchDescriptor<AssetTransactionLink>())
                .first(where: { $0.assetID == asset.stableID })
        )
        XCTAssertEqual(link.allocatedRefundCents, 2_000)
        XCTAssertEqual(asset.purchasePrice, 50)
        XCTAssertTrue(try AssetRefundAllocationStore.pendingRefundAllocations(for: asset, in: stack.context).isEmpty)
        XCTAssertEqual(
            try stack.context.fetch(FetchDescriptor<AssetRefundAllocation>())
                .filter { $0.statusRaw == "active" }
                .map(\.allocatedRefundCents)
                .reduce(0, +),
            3_000
        )
    }

    func testHistoricalFullOrderRefundIsAuditedWhenAssetIsLinkedLater() throws {
        let stack = try Stack()
        let (book, account, category) = try seed(stack)
        let original = try LedgerStore.createTransaction(
            in: stack.context,
            amount: 80,
            kind: .expense,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            note: "历史购置",
            category: category,
            account: account,
            book: book
        )
        _ = try LedgerStore.createOffset(
            for: original,
            amount: 30,
            note: "历史退款",
            eventType: .refund,
            settlementAccount: account,
            in: stack.context
        )
        let asset = try AssetStore.createFromTransaction(
            in: stack.context,
            transaction: original,
            name: "历史物品",
            kind: .tools,
            allocatedGrossCents: 8_000,
            currentValue: 50
        )
        XCTAssertEqual(asset.purchasePrice, 50)
        XCTAssertEqual(
            try stack.context.fetch(FetchDescriptor<AssetRefundAllocation>())
                .filter { $0.statusRaw == "active" }
                .map(\.allocatedRefundCents),
            [3_000]
        )
        XCTAssertTrue(try AssetRefundAllocationStore.pendingRefundAllocations(for: asset, in: stack.context).isEmpty)
    }

    func testPurchaseLinkedTransactionCannotBeDeleted() throws {
        let stack = try Stack()
        let (book, account, category) = try seed(stack)
        let original = try LedgerStore.createTransaction(
            in: stack.context,
            amount: 40,
            kind: .expense,
            date: Date(),
            note: "已关联物品",
            category: category,
            account: account,
            book: book
        )
        _ = try AssetStore.createFromTransaction(
            in: stack.context,
            transaction: original,
            name: "物品",
            kind: .other,
            allocatedGrossCents: 4_000,
            currentValue: 40
        )

        XCTAssertThrowsError(try LedgerStore.delete(original, in: stack.context)) { error in
            XCTAssertEqual(error as? LedgerStore.Error, .immutableAssetLink)
        }
        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<MoneyTransaction>()), 1)
    }

    func testPurchaseLinkCanBeUnlinkedAndRefundedNetCostBecomesManual() throws {
        let stack = try Stack()
        let (book, account, category) = try seed(stack)
        let original = try LedgerStore.createTransaction(
            in: stack.context,
            amount: 100,
            kind: .expense,
            date: Date(),
            note: "可解除购置",
            category: category,
            account: account,
            book: book
        )
        let asset = try AssetStore.createFromTransaction(
            in: stack.context,
            transaction: original,
            name: "可解除物品",
            kind: .other,
            allocatedGrossCents: 10_000,
            currentValue: 70
        )
        let refund = try LedgerStore.createOffset(
            for: original,
            amount: 30,
            note: "购置退款",
            eventType: .refund,
            settlementAccount: account,
            in: stack.context
        )
        let link = try XCTUnwrap(
            stack.context.fetch(FetchDescriptor<AssetTransactionLink>())
                .first(where: { $0.assetID == asset.stableID })
        )

        try AssetStore.unlinkCost(link, in: stack.context)

        XCTAssertTrue(
            try stack.context.fetch(FetchDescriptor<AssetTransactionLink>())
                .filter { $0.assetID == asset.stableID }
                .isEmpty
        )
        XCTAssertEqual(asset.sourceType, .historicalExisting)
        XCTAssertEqual(asset.acquisitionCostSourceRaw, AssetAcquisitionCostSource.manual.rawValue)
        XCTAssertEqual(asset.purchasePrice, 70)
        XCTAssertTrue(
            try stack.context.fetch(FetchDescriptor<AssetRefundAllocation>())
                .allSatisfy { $0.statusRaw == "reversed" }
        )
        XCTAssertTrue(try AssetRefundAllocationStore.pendingRefundAllocations(for: asset, in: stack.context).isEmpty)

        try LedgerStore.delete(original, in: stack.context)
        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<MoneyTransaction>()), 0)
    }

    func testLinkedAssetPurchaseCostCannotBeEditedDirectly() throws {
        let stack = try Stack()
        let (book, account, category) = try seed(stack)
        let original = try LedgerStore.createTransaction(
            in: stack.context,
            amount: 100,
            kind: .expense,
            date: Date(),
            note: "成本由账单管理",
            category: category,
            account: account,
            book: book
        )
        let asset = try AssetStore.createFromTransaction(
            in: stack.context,
            transaction: original,
            name: "关联物品",
            kind: .other,
            allocatedGrossCents: 10_000,
            currentValue: 80
        )

        XCTAssertThrowsError(
            try AssetStore.update(
                asset,
                in: stack.context,
                name: asset.name,
                kind: asset.kind,
                purchasePrice: 99,
                currentValue: asset.currentValue,
                book: book,
                purchaseDate: asset.purchaseDate,
                warrantyUntil: asset.warrantyUntil,
                brand: asset.brand,
                model: asset.model,
                location: asset.location,
                note: asset.note,
                includeInNetWorth: asset.includeInNetWorth
            )
        )
    }

    func testRefundUsedForReturnCannotBeDeletedFromTheLedger() throws {
        let stack = try Stack()
        let (book, account, category) = try seed(stack)
        let original = try LedgerStore.createTransaction(
            in: stack.context,
            amount: 60,
            kind: .expense,
            date: Date(),
            note: "可退物品",
            category: category,
            account: account,
            book: book
        )
        let asset = try AssetStore.createFromTransaction(
            in: stack.context,
            transaction: original,
            name: "可退物品",
            kind: .other,
            allocatedGrossCents: 6_000,
            currentValue: 50
        )
        let refund = try AssetStore.returnToPurchase(asset, in: stack.context)

        XCTAssertThrowsError(try LedgerStore.delete(refund, in: stack.context)) { error in
            XCTAssertEqual(error as? LedgerStore.Error, .immutableReturnedRefund)
        }
        XCTAssertEqual(asset.lifecycle, .returned)
        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<MoneyTransaction>()), 2)
    }
}
