import XCTest
import SwiftUI
import SwiftData
import UIKit
import QingJiCore
@testable import QingJi

@MainActor
final class AssetsConceptPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_244_800)

    func testFundsFiltersKeepInvestmentAndDebtInSeparateGroups() {
        XCTAssertTrue(AssetsFundsFilter.accounts.includes(.bankCard))
        XCTAssertFalse(AssetsFundsFilter.accounts.includes(.investment))
        XCTAssertFalse(AssetsFundsFilter.accounts.includes(.creditCard))
        XCTAssertTrue(AssetsFundsFilter.investment.includes(.investment))
        XCTAssertTrue(AssetsFundsFilter.liabilities.includes(.loan))
        XCTAssertTrue(AssetsFundsFilter.liabilities.includes(.cash, balance: -25))
        XCTAssertFalse(AssetsFundsFilter.liabilities.includes(.bankCard, balance: 25))
        XCTAssertFalse(AssetsFundsFilter.receivables.includes(.cash))
        XCTAssertTrue(AccountKind.allCases.allSatisfy { AssetsFundsFilter.all.includes($0) })
        XCTAssertTrue(AssetsPresentation.matches("  招商  ", values: "日常卡", "招商银行"))
        XCTAssertFalse(AssetsPresentation.matches("零钱", values: "日常卡", "招商银行"))
    }

    func testCalibrationIgnoresReversedFutureAndOtherAccountAnchors() {
        let account = UUID()
        let earlier = anchor(account, days: -8)
        let later = anchor(account, days: -1)
        let future = anchor(account, days: 1)
        let other = anchor(UUID(), days: 0)
        let reversal = AccountBalanceCheckpointRecord(accountID: account, effectiveAt: now,
            knowledgeCutoff: now, eventKindRaw: "reversal")
        reversal.reversalOfID = later.stableID
        let result = AssetsPresentation.latestCalibration(accountID: account,
            checkpoints: [earlier, later, future, other, reversal], now: now)
        XCTAssertEqual(result?.stableID, earlier.stableID)
        XCTAssertEqual(AssetsPresentation.calibrationText(result, now: now), "8 天前校准")
        XCTAssertEqual(AssetsPresentation.calibrationText(nil, now: now), "从未校准")
    }

    func testSameInstantCalibrationUsesSequenceAndMarksStaleDates() {
        let account = UUID()
        let first = anchor(account, days: -31)
        let second = anchor(account, days: -31)
        first.sequence = 1
        second.sequence = 2
        let result = AssetsPresentation.latestCalibration(accountID: account, checkpoints: [first, second], now: now)
        XCTAssertEqual(result?.stableID, second.stableID)
        XCTAssertEqual(AssetsPresentation.calibrationText(result, now: now), "31 天未校准")
    }

    func testFrozenComparisonReadsBothSavedTotalsWithoutLiveBalance() throws {
        let earlier = try verified(days: -10, assets: 100)
        let later = try verified(days: -2, assets: 125)
        let change = try XCTUnwrap(AssetsPresentation.verifiedChange([later, earlier], now: now))
        XCTAssertEqual(change.amount, 25)
        XCTAssertEqual(change.earlierDate, earlier.asOf)
        XCTAssertEqual(change.laterDate, later.asOf)
        XCTAssertNil(AssetsPresentation.verifiedChange([earlier], now: now))
    }

    func testComparisonUsesLastCompletePairButNeverCrossesScopeOrVersionChanges() throws {
        let earlier = try verified(days: -10, assets: 100)
        let later = try verified(days: -2, assets: 125)
        let partial = try verified(days: -1, assets: 130)
        partial.completenessRaw = "partial"
        XCTAssertEqual(AssetsPresentation.verifiedChange([earlier, later, partial], now: now)?.amount, 25)
        later.scopeVersion = 2
        XCTAssertNil(AssetsPresentation.verifiedChange([earlier, later], now: now))
        later.scopeVersion = 1
        later.calculationVersion = 2
        XCTAssertNil(AssetsPresentation.verifiedChange([earlier, later], now: now))
        later.calculationVersion = 1
        later.currencyCoverageJSON = "{\"base_currency\":\"CNY\",\"covered\":[\"CNY\"],\"uncovered\":[\"USD\"]}"
        XCTAssertNil(AssetsPresentation.verifiedChange([earlier, later], now: now))
    }

    func testMissingFrozenEvidenceInvalidTotalsAndFutureHeadersAreUnavailable() throws {
        let earlier = try verified(days: -10, assets: 100)
        let later = try verified(days: -2, assets: 125)
        later.itemsJSON = "[]"
        XCTAssertNil(AssetsPresentation.verifiedChange([earlier, later], now: now))
        let corrupt = try verified(days: -1, assets: 150)
        corrupt.netWorth = 149
        XCTAssertNil(AssetsPresentation.verifiedChange([earlier, corrupt], now: now))
        let inconsistentItems = try verified(days: -1, assets: 150, frozenAmount: 149)
        XCTAssertNil(AssetsPresentation.verifiedChange([earlier, inconsistentItems], now: now))
        let future = try verified(days: 1, assets: 150)
        XCTAssertNil(AssetsPresentation.verifiedChange([earlier, future], now: now))
        earlier.statusRaw = "revoked"
        XCTAssertNil(AssetsPresentation.verifiedChange([earlier, corrupt], now: now))
    }

    func testUnknownCostDoesNotTurnDefaultZeroIntoDailyCost() {
        let metrics = AssetMetrics.resolve(PhysicalAssetMetricInput(netAcquisitionCost: 0,
            currentNetValue: 0, purchasedAt: now, endedAt: nil, isEconomicallyOwned: true,
            hasKnownValuation: false), asOf: now)
        XCTAssertNil(AssetsPresentation.physicalDailyValue(metrics, costSource: "manual_unknown"))
        XCTAssertEqual(AssetsPresentation.physicalDailyValue(metrics, costSource: "manual"), 0)
        XCTAssertNil(AssetsPresentation.physicalDailyValue(nil, costSource: "manual"))
    }

    func testPhysicalAssetDateFormatUsesChineseLocale() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 27, hour: 12)))
        XCTAssertEqual(PhysicalAssetDetailView.formattedDate(date), "2026年5月27日")
        XCTAssertEqual(PhysicalAssetDetailView.formattedDate(nil), "未填写")
    }

    func testPhysicalPhotoFallsBackWhenThumbnailIsMissingOrUndecodable() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { renderer in
            renderer.cgContext.setFillColor(UIColor.black.cgColor)
            renderer.cgContext.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let data = try XCTUnwrap(original.pngData())
        let photoPath = try AttachmentStore.save(data: data, fileExtension: "png")
        defer { AttachmentStore.remove(photoPath) }
        let corruptPath = try AttachmentStore.save(data: Data([0, 1, 2]), fileExtension: "png")
        defer { AttachmentStore.remove(corruptPath) }
        let missingPath = "\(UUID().uuidString).png"
        XCTAssertEqual(try XCTUnwrap(PhysicalAssetDetailView.photoImage(thumbnailPath: missingPath,
            photoPath: photoPath)).size.width, 8)
        XCTAssertEqual(try XCTUnwrap(PhysicalAssetDetailView.photoImage(thumbnailPath: corruptPath,
            photoPath: photoPath)).size.width, 8)
        XCTAssertNil(PhysicalAssetDetailView.photoImage(thumbnailPath: corruptPath, photoPath: missingPath))
    }

    func testCaptureFourConceptPagesWithThemesNarrowWidthAndLargeText() async throws {
        let schema = Schema([Account.self, Book.self, TxCategory.self, MoneyTransaction.self,
            PhysicalAsset.self, AssetEvent.self, AssetUsageEvent.self, AssetTransactionLink.self,
            AssetValuation.self, ReceivableAsset.self, ReceivableRecovery.self, LiabilityProfile.self,
            NetWorthSnapshot.self, AccountBalanceCheckpointRecord.self, NetWorthVerifiedCheckpointRecord.self,
            BudgetRuleRecord.self, BudgetRolloverChangeRecord.self])
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let book = Book(name: "总账本", isDefault: true)
        context.insert(book)
        let cash = Account(name: "日常现金", kind: .cash, sortOrder: 0)
        cash.initialBalance = -25
        let bank = Account(name: "储蓄卡", kind: .bankCard, sortOrder: 1)
        bank.initialBalance = 1200
        context.insert(cash)
        context.insert(bank)
        let item = PhysicalAsset(name: "日常手机", kind: .digital, purchasePrice: 800,
            currentValue: 600, bookID: book.stableID)
        item.purchaseDate = AppClock.now.addingTimeInterval(-92 * 86400)
        item.warrantyUntil = AppClock.now.addingTimeInterval(365 * 86400)
        item.brand = "测试品牌"
        item.model = "测试型号"
        context.insert(item)
        context.insert(AssetValuation(assetID: item.stableID, value: 600, valuedAt: AppClock.now))
        for (days, cashValue) in [(60, Decimal(1100)), (1, Decimal(1200))] {
            let date = AppClock.now.addingTimeInterval(-Double(days) * 86400)
            let snapshot = NetWorthSnapshot(asOf: date)
            snapshot.knowledgeCutoff = date
            snapshot.cashAssets = cashValue
            snapshot.physicalAssets = 600
            snapshot.liabilities = 25
            snapshot.quality = .available
            context.insert(snapshot)
        }
        let today = BudgetCivilDay(AppClock.now)
        context.insert(BudgetRuleRecord(bookID: book.stableID, kindRaw: "base", amountCents: 300_000,
            unitRaw: "month", startDate: BudgetCivilDay(year: today.year, month: today.month, day: 1).description,
            createdMs: Int(AppClock.now.timeIntervalSince1970 * 1000)))
        try context.save()
        let router = AppRouter()
        for (scheme, width, size, name) in [(ColorScheme.light, CGFloat(390), UIContentSizeCategory.large, "light"),
            (.dark, CGFloat(390), .large, "dark"), (.light, CGFloat(320), .accessibilityExtraExtraLarge, "narrow-large")] {
            try await capture(AnyView(NavigationStack { AssetsView() }), container: container, router: router,
                scheme: scheme, width: width, size: size, name: "assets-overview-\(name)")
            try await capture(AnyView(NavigationStack { AssetsView(startsOnFunds: true) }), container: container, router: router,
                scheme: scheme, width: width, size: size, name: "assets-funds-\(name)")
            try await capture(AnyView(PhysicalAssetDetailView(asset: item)), container: container, router: router,
                scheme: scheme, width: width, size: size, name: "assets-detail-\(name)")
            try await capture(AnyView(NavigationStack { BudgetView() }), container: container, router: router,
                scheme: scheme, width: width, size: size, name: "budget-\(name)")
        }
    }

    private func anchor(_ account: UUID, days: Int) -> AccountBalanceCheckpointRecord {
        let date = now.addingTimeInterval(Double(days) * 86400)
        return AccountBalanceCheckpointRecord(accountID: account, effectiveAt: date, knowledgeCutoff: date)
    }

    private func verified(days: Int, assets: Decimal, frozenAmount: Decimal? = nil) throws -> NetWorthVerifiedCheckpointRecord {
        let date = now.addingTimeInterval(Double(days) * 86400)
        let record = NetWorthVerifiedCheckpointRecord(asOf: date, knowledgeCutoff: date,
            totalAssets: assets, totalLiabilities: 0, netWorth: assets)
        record.completenessRaw = "complete"
        record.reasonsJSON = "[]"
        record.currencyCoverageJSON = "{\"base_currency\":\"CNY\",\"covered\":[\"CNY\"],\"uncovered\":[]}"
        let item = BackupNetWorthVerifiedCheckpointItem(checkpointID: record.stableID, objectType: "account",
            objectUUID: UUID().uuidString, confirmedAmount: frozenAmount ?? assets, valueEffectiveAt: date,
            valueSource: "manual", quality: "exact")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        record.itemsJSON = String(decoding: try encoder.encode([item]), as: UTF8.self)
        return record
    }

    private func capture(_ view: AnyView, container: ModelContainer, router: AppRouter, scheme: ColorScheme,
                         width: CGFloat, size: UIContentSizeCategory, name: String) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 844)
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        window.traitOverrides.preferredContentSizeCategory = size
        let controller = UIHostingController(rootView: view.modelContainer(container).environment(router)
            .environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: "zh-Hans")))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)
        controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "concept-v1-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
