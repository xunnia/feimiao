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

    func testPurchaseDateUsesLocalCalendarDayAndFixedNumericFormat() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-26T16:30:00Z"))
        XCTAssertEqual(PhysicalAssetEditor.purchaseDateText(instant, timeZone: zone), "2026-08-27")
        XCTAssertEqual(PhysicalAssetEditor.purchaseDateText(instant, timeZone: TimeZone(secondsFromGMT: 0)!), "2026-08-26")
    }

    func testManualIdleAssetKeepsNetWorthChoiceAfterReload() throws {
        let stack = try Stack()
        let asset = try AssetStore.create(
            in: stack.context, name: "闲置键盘", kind: .tools,
            purchasePrice: 100, currentValue: 80,
            includeInNetWorth: false, usageLifecycle: .idle
        )
        let reloaded = try XCTUnwrap(ModelContext(stack.container).fetch(FetchDescriptor<PhysicalAsset>()).first)
        XCTAssertEqual(reloaded.stableID, asset.stableID)
        XCTAssertEqual(reloaded.lifecycle, .idle)
        XCTAssertEqual(reloaded.usageStatusRaw, "idle")
        XCTAssertEqual(reloaded.economicStatusRaw, "owned")
        XCTAssertFalse(reloaded.includeInNetWorth)
        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<AssetEvent>()), 1)
    }

    func testExistingBillCanCreateIdleAssetWithoutSecondExpense() throws {
        let stack = try Stack()
        let original = MoneyTransaction(amount: 38, kind: .expense, note: "购买物品")
        stack.context.insert(original)
        try stack.context.save()
        let asset = try AssetStore.createFromTransaction(
            in: stack.context, transaction: original, name: "闲置物品", kind: .other,
            allocatedGrossCents: 3_800, includeInNetWorth: false, usageLifecycle: .idle
        )
        XCTAssertEqual(asset.lifecycle, .idle)
        XCTAssertEqual(asset.usageStatusRaw, "idle")
        XCTAssertFalse(asset.includeInNetWorth)
        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<MoneyTransaction>()), 1)
        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<AssetTransactionLink>()), 1)
    }

    func testNewPurchaseCanCreateIdleAssetWithoutEnablingNetWorth() throws {
        let stack = try Stack()
        let account = Account(name: "现金", kind: .cash)
        stack.context.insert(account)
        try stack.context.save()
        let asset = try AssetStore.createPurchased(
            in: stack.context, name: "备用键盘", kind: .tools,
            purchasePrice: 100, currentValue: 90, account: account,
            purchaseDate: Date(), includeInNetWorth: false, usageLifecycle: .idle
        )
        XCTAssertEqual(asset.lifecycle, .idle)
        XCTAssertEqual(asset.usageStatusRaw, "idle")
        XCTAssertFalse(asset.includeInNetWorth)
        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<MoneyTransaction>()), 1)
        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<AssetTransactionLink>()), 1)
    }

    func testEditingUsagePreservesNetWorthAndLegacyCallsPreserveState() throws {
        let stack = try Stack()
        let asset = try AssetStore.create(
            in: stack.context, name: "键盘", kind: .tools,
            purchasePrice: 100, currentValue: 80,
            includeInNetWorth: false, usageLifecycle: .idle
        )
        func edit(_ usage: PhysicalAssetLifecycle? = nil) throws {
            try AssetStore.update(
                asset, in: stack.context, name: "键盘", kind: .tools,
                purchasePrice: 100, currentValue: 80, purchaseDate: nil,
                warrantyUntil: nil, brand: "", model: "", location: "", note: "",
                includeInNetWorth: false, usageLifecycle: usage
            )
        }
        try edit()
        XCTAssertEqual(asset.lifecycle, .idle)
        XCTAssertEqual(asset.usageStatusRaw, "idle")
        try edit(.owned)
        XCTAssertEqual(asset.lifecycle, .owned)
        XCTAssertEqual(asset.usageStatusRaw, "active")
        XCTAssertFalse(asset.includeInNetWorth)
        try edit(.idle)
        XCTAssertEqual(asset.lifecycle, .idle)
        XCTAssertFalse(asset.includeInNetWorth)
        let eventCount = try stack.context.fetchCount(FetchDescriptor<AssetEvent>())
        XCTAssertThrowsError(try edit(.sold))
        XCTAssertEqual(asset.lifecycle, .idle)
        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<AssetEvent>()), eventCount)
    }

    func testAllCreationPathsRejectTerminalUsageWithoutPartialWrites() throws {
        for usage in PhysicalAssetLifecycle.allCases where usage != .owned && usage != .idle {
            let stack = try Stack()
            let account = Account(name: "现金", kind: .cash)
            let original = MoneyTransaction(amount: 38, kind: .expense, note: "购买物品")
            stack.context.insert(account)
            stack.context.insert(original)
            try stack.context.save()
            XCTAssertThrowsError(try AssetStore.create(
                in: stack.context, name: "物品", kind: .other,
                purchasePrice: 38, currentValue: 38, usageLifecycle: usage
            ))
            XCTAssertThrowsError(try AssetStore.createPurchased(
                in: stack.context, name: "物品", kind: .other,
                purchasePrice: 38, currentValue: 38, account: account,
                purchaseDate: Date(), usageLifecycle: usage
            ))
            XCTAssertThrowsError(try AssetStore.createFromTransaction(
                in: stack.context, transaction: original, name: "物品", kind: .other,
                allocatedGrossCents: 3_800, usageLifecycle: usage
            ))
            XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<PhysicalAsset>()), 0)
            XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<AssetEvent>()), 0)
            XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<AssetValuation>()), 0)
            XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<AssetTransactionLink>()), 0)
            XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<MoneyTransaction>()), 1)
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

    func testNewPurchaseCreatesAssetPurchaseTransactionAndAllocation() throws {
        let stack = try Stack()
        let book = Book(name: "测试账本", isDefault: true)
        let cash = Account(name: "现金", kind: .cash)
        cash.initialBalance = 500
        let category = TxCategory(
            key: "shopping",
            name: "购物",
            symbol: "bag",
            kind: .expense
        )
        stack.context.insert(book)
        stack.context.insert(cash)
        stack.context.insert(category)
        try stack.context.save()

        let purchaseDate = Date(timeIntervalSince1970: 1_705_000_000)
        let asset = try AssetStore.createPurchased(
            in: stack.context,
            name: "新键盘",
            kind: .tools,
            purchasePrice: 100,
            currentValue: 90,
            account: cash,
            category: category,
            book: book,
            purchaseDate: purchaseDate
        )
        XCTAssertEqual(asset.sourceType, .newPurchaseWithAccount)
        XCTAssertEqual(asset.purchasePrice, 100)
        XCTAssertEqual(
            try stack.context.fetchCount(FetchDescriptor<MoneyTransaction>()),
            1
        )
        let transaction = try XCTUnwrap(
            stack.context.fetch(FetchDescriptor<MoneyTransaction>()).first
        )
        XCTAssertEqual(transaction.eventType, .assetPurchase)
        XCTAssertEqual(transaction.amount, 100)
        let links = try stack.context.fetch(FetchDescriptor<AssetTransactionLink>())
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].allocatedGrossCents, 10_000)
        XCTAssertEqual(
            LedgerStore.accountBalance(
                for: cash,
                transactions: [transaction]
            ),
            400
        )
    }

    func testInvalidNewPurchaseLeavesNoAssetOrExpense() throws {
        let stack = try Stack()
        let cash = Account(name: "停用账户", kind: .cash)
        cash.status = .archived
        let incomeCategory = TxCategory(
            key: "salary",
            name: "工资",
            symbol: "banknote",
            kind: .income
        )
        stack.context.insert(cash)
        stack.context.insert(incomeCategory)
        try stack.context.save()
        let purchaseDate = Date(timeIntervalSince1970: 1_705_000_000)

        XCTAssertThrowsError(try AssetStore.createPurchased(
            in: stack.context,
            name: "不应创建的物品",
            kind: .other,
            purchasePrice: 100,
            currentValue: 90,
            account: cash,
            purchaseDate: purchaseDate
        ))
        cash.status = .active
        XCTAssertThrowsError(try AssetStore.createPurchased(
            in: stack.context,
            name: "分类不符的物品",
            kind: .other,
            purchasePrice: 100,
            currentValue: 90,
            account: cash,
            category: incomeCategory,
            purchaseDate: purchaseDate
        ))

        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<PhysicalAsset>()), 0)
        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<MoneyTransaction>()), 0)
        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<AssetTransactionLink>()), 0)
        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<AssetEvent>()), 0)
    }

    func testExistingPurchaseCanBeSplitAcrossMultipleAssets() throws {
        let stack = try Stack()
        let book = Book(name: "测试账本", isDefault: true)
        let cash = Account(name: "现金", kind: .cash)
        stack.context.insert(book)
        stack.context.insert(cash)
        try stack.context.save()
        let purchaseDate = Date(timeIntervalSince1970: 1_705_000_000)
        let original = try LedgerStore.createTransaction(
            in: stack.context,
            amount: 120,
            kind: .expense,
            date: purchaseDate,
            note: "两件商品",
            account: cash,
            book: book
        )

        let first = try AssetStore.createFromTransaction(
            in: stack.context,
            transaction: original,
            name: "商品 A",
            kind: .other,
            allocatedGrossCents: 7_000,
            currentValue: 65
        )
        let remaining = AssetStore.purchaseCandidates(
            transactions: [original],
            links: try stack.context.fetch(FetchDescriptor<AssetTransactionLink>())
        )
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.remainingGrossCents, 5_000)
        let second = try AssetStore.createFromTransaction(
            in: stack.context,
            transaction: original,
            name: "商品 B",
            kind: .other,
            allocatedGrossCents: 5_000,
            currentValue: 45
        )
        XCTAssertEqual(first.sourceType, .fromTransaction)
        XCTAssertEqual(second.sourceType, .fromTransaction)
        XCTAssertEqual(first.purchasePrice, 70)
        XCTAssertEqual(second.purchasePrice, 50)
        let links = try stack.context.fetch(FetchDescriptor<AssetTransactionLink>())
        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(links.map(\.allocatedGrossCents).reduce(0, +), 12_000)
        XCTAssertTrue(AssetStore.purchaseCandidates(transactions: [original], links: links).isEmpty)
    }

    func testPurchaseCandidateTracksUnallocatedRefund() throws {
        let stack = try Stack()
        let book = Book(name: "测试账本", isDefault: true)
        let cash = Account(name: "现金", kind: .cash)
        stack.context.insert(book)
        stack.context.insert(cash)
        try stack.context.save()
        let original = try LedgerStore.createTransaction(
            in: stack.context,
            amount: 120,
            kind: .expense,
            date: Date(timeIntervalSince1970: 1_705_000_000),
            note: "两件商品",
            account: cash,
            book: book
        )
        let refund = MoneyTransaction(
            amount: -20,
            kind: .expense,
            date: original.date.addingTimeInterval(86_400),
            account: cash,
            book: book,
            refundOfID: original.stableID
        )
        stack.context.insert(refund)
        try stack.context.save()
        _ = try AssetStore.createFromTransaction(
            in: stack.context,
            transaction: original,
            name: "商品 A",
            kind: .other,
            allocatedGrossCents: 7_000,
            allocatedRefundCents: 1_000
        )
        let candidates = AssetStore.purchaseCandidates(
            transactions: [refund, original],
            links: try stack.context.fetch(FetchDescriptor<AssetTransactionLink>())
        )
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.transaction.stableID, original.stableID)
        XCTAssertEqual(candidates.first?.remainingGrossCents, 5_000)
        XCTAssertEqual(candidates.first?.remainingRefundCents, 1_000)
    }

    func testPurchaseFormSuggestedValueUsesNetCents() {
        XCTAssertEqual(
            PhysicalAssetEditor.suggestedPurchaseValue(grossText: " 1,200.50 ", refundText: "200.25"),
            Decimal(string: "1000.25")
        )
        XCTAssertEqual(
            PhysicalAssetEditor.suggestedPurchaseValue(grossText: "10", refundText: "20"),
            .zero
        )
        XCTAssertEqual(
            PhysicalAssetEditor.suggestedPurchaseValue(grossText: "", refundText: ""),
            .zero
        )
        XCTAssertEqual(
            PhysicalAssetEditor.suggestedPurchaseValue(grossText: "12.345", refundText: "2.115"),
            Decimal(string: "10.23")
        )
    }

    func testPurchaseCandidatesIgnoreExcludedBillsAndNonPurchaseLinks() throws {
        let stack = try Stack()
        let book = Book(name: "测试账本", isDefault: true)
        let cash = Account(name: "现金", kind: .cash)
        stack.context.insert(book)
        stack.context.insert(cash)
        try stack.context.save()
        let original = try LedgerStore.createTransaction(
            in: stack.context,
            amount: 100,
            kind: .expense,
            date: Date(timeIntervalSince1970: 1_705_000_000),
            note: "购买",
            account: cash,
            book: book
        )
        let unrelatedCost = AssetTransactionLink(
            assetID: UUID(),
            transactionID: original.stableID,
            linkTypeRaw: AssetTransactionLinkType.maintenance.rawValue
        )
        unrelatedCost.allocatedGrossCents = 8_000
        stack.context.insert(unrelatedCost)
        try stack.context.save()

        let candidates = AssetStore.purchaseCandidates(
            transactions: [original],
            links: [unrelatedCost]
        )
        XCTAssertEqual(candidates.first?.remainingGrossCents, 10_000)

        original.isExcluded = true
        XCTAssertTrue(AssetStore.purchaseCandidates(
            transactions: [original],
            links: [unrelatedCost]
        ).isEmpty)
    }

    func testInvalidPurchaseAllocationDoesNotCreateOrphanAsset() throws {
        let stack = try Stack()
        let book = Book(name: "测试账本", isDefault: true)
        let cash = Account(name: "现金", kind: .cash)
        stack.context.insert(book)
        stack.context.insert(cash)
        try stack.context.save()
        let original = try LedgerStore.createTransaction(
            in: stack.context,
            amount: 120,
            kind: .expense,
            date: Date(timeIntervalSince1970: 1_705_000_000),
            note: "两件商品",
            account: cash,
            book: book
        )
        _ = try AssetStore.createFromTransaction(
            in: stack.context,
            transaction: original,
            name: "商品 A",
            kind: .other,
            allocatedGrossCents: 7_000
        )
        let assetCount = try stack.context.fetchCount(FetchDescriptor<PhysicalAsset>())
        let eventCount = try stack.context.fetchCount(FetchDescriptor<AssetEvent>())
        let valuationCount = try stack.context.fetchCount(FetchDescriptor<AssetValuation>())
        let linkCount = try stack.context.fetchCount(FetchDescriptor<AssetTransactionLink>())

        XCTAssertThrowsError(try AssetStore.createFromTransaction(
            in: stack.context,
            transaction: original,
            name: "超额商品",
            kind: .other,
            allocatedGrossCents: 6_000
        ))
        XCTAssertThrowsError(try AssetStore.createFromTransaction(
            in: stack.context,
            transaction: original,
            name: "无退款商品",
            kind: .other,
            allocatedGrossCents: 1_000,
            allocatedRefundCents: 100
        ))

        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<PhysicalAsset>()), assetCount)
        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<AssetEvent>()), eventCount)
        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<AssetValuation>()), valuationCount)
        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<AssetTransactionLink>()), linkCount)
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
