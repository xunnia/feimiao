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

    func testPhysicalIdentityHeaderKeepsRegularLayoutAndStacksAtLargeTextSizes() {
        XCTAssertFalse(PhysicalAssetDetailView.stacksIdentityHeader(for: .large))
        XCTAssertFalse(PhysicalAssetDetailView.stacksIdentityHeader(for: .xxLarge))
        XCTAssertTrue(PhysicalAssetDetailView.stacksIdentityHeader(for: .xxxLarge))
        XCTAssertTrue(PhysicalAssetDetailView.stacksIdentityHeader(for: .accessibility3))
        XCTAssertTrue(PhysicalAssetDetailView.stacksIdentityHeader(for: .accessibility5))
    }

    func testBudgetBookControlCompactsBeforeCrowdingTheNavigationTitle() {
        XCTAssertFalse(BudgetView.usesCompactBookControl(width: 420, typeSize: .large))
        XCTAssertFalse(BudgetView.usesCompactBookControl(width: 375, typeSize: .xLarge))
        XCTAssertTrue(BudgetView.usesCompactBookControl(width: 374, typeSize: .large))
        XCTAssertTrue(BudgetView.usesCompactBookControl(width: 320, typeSize: .large))
        XCTAssertTrue(BudgetView.usesCompactBookControl(width: 420, typeSize: .xxLarge))
        XCTAssertTrue(BudgetView.usesCompactBookControl(width: 420, typeSize: .accessibility5))
    }

    func testThinChromeIsOptInAndKeepsExistingDefaultControls() {
        let standard = LiquidGlassIconButton(systemName: "plus", accessibilityLabel: "新增") {}
        let subtle = LiquidGlassIconButton(systemName: "plus", accessibilityLabel: "新增", size: 44, subtle: true) {}
        XCTAssertEqual(standard.size, 48)
        XCTAssertFalse(standard.subtle)
        XCTAssertEqual(subtle.size, 44)
        XCTAssertTrue(subtle.subtle)
        let standardPill = LiquidGlassPillButton("保存") {}
        let subtlePill = LiquidGlassPillButton("保存", subtle: true) {}
        XCTAssertFalse(standardPill.subtle)
        XCTAssertTrue(subtlePill.subtle)
    }

    func testNeutralGlassCalibrationOnlyChangesOptInLightControls() {
        XCTAssertTrue(LiquidGlassControlAppearance.usesNeutralLightSurface(subtle: true, isDark: false))
        XCTAssertFalse(LiquidGlassControlAppearance.usesNeutralLightSurface(subtle: true, isDark: true))
        XCTAssertFalse(LiquidGlassControlAppearance.usesNeutralLightSurface(subtle: false, isDark: false))
        XCTAssertFalse(LiquidGlassControlAppearance.usesNeutralLightSurface(subtle: false, isDark: true))
        XCTAssertEqual(LiquidGlassControlAppearance.outlineOpacity(subtle: true, isDark: false), 0.18)
        XCTAssertEqual(LiquidGlassControlAppearance.outlineOpacity(subtle: true, isDark: true), 0.12)
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
        let defaults = UserDefaults.standard
        let savedTheme = ["qingji.themePreset", "qingji.themeIntensity", "qingji.themeCardAlpha"]
            .map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in savedTheme {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(AppThemePreset.warm.rawValue, forKey: "qingji.themePreset")
        defaults.set(1.0, forKey: "qingji.themeIntensity")
        defaults.set(0.8, forKey: "qingji.themeCardAlpha")
        let schema = Schema([Account.self, Book.self, TxCategory.self, Tag.self, MoneyTransaction.self,
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
        let scenes: [(ColorScheme, CGFloat, UIContentSizeCategory, String)] = [
            (.light, 420, .large, "light"), (.dark, 420, .large, "dark"),
            (.light, 320, .accessibilityExtraExtraLarge, "narrow-large")
        ]
        for (scheme, width, size, name) in scenes {
            try await capture(pushed(AnyView(AssetsView())), container: container, router: router,
                scheme: scheme, width: width, size: size, name: "assets-overview-\(name)")
            try await capture(pushed(AnyView(AssetsView(startsOnFunds: true))), container: container, router: router,
                scheme: scheme, width: width, size: size, name: "assets-funds-\(name)")
            try await capture(AnyView(PhysicalAssetDetailView(asset: item)), container: container, router: router,
                scheme: scheme, width: width, size: size, name: "assets-detail-\(name)",
                sheetOver: pushed(AnyView(AssetsView())))
            try await capture(pushed(AnyView(BudgetView())), container: container, router: router,
                scheme: scheme, width: width, size: size, name: "budget-\(name)")
        }

        for preset in [AppThemePreset.white, .pink, .mint, .blue] {
            defaults.set(preset.rawValue, forKey: "qingji.themePreset")
            try await capture(pushed(AnyView(AssetsView())), container: container, router: router,
                scheme: .light, width: 420, size: .large, name: "assets-overview-\(preset.rawValue)-light")
            try await capture(pushed(AnyView(BudgetView())), container: container, router: router,
                scheme: .light, width: 420, size: .large, name: "budget-\(preset.rawValue)-light")
        }
        defaults.set(AppThemePreset.warm.rawValue, forKey: "qingji.themePreset")

        // Use the same fixture without history; the range menu must remain available.
        for snapshot in try context.fetch(FetchDescriptor<NetWorthSnapshot>()) { context.delete(snapshot) }
        let longBook = Book(name: "家庭共同账本与长期生活预算", sortOrder: 1)
        context.insert(longBook)
        let rule = BudgetRuleRecord(bookID: longBook.stableID, kindRaw: "base", amountCents: 300_000,
            unitRaw: "month", startDate: BudgetCivilDay(year: today.year, month: today.month, day: 1).description,
            createdMs: Int(AppClock.now.timeIntervalSince1970 * 1000))
        context.insert(rule)
        let category = TxCategory(key: "concept-dining", name: "餐饮", symbol: "fork.knife", kind: .expense)
        context.insert(category)
        let transaction = MoneyTransaction(amount: 15, kind: .expense, date: AppClock.now,
            note: "午餐", category: category, account: bank, book: longBook)
        context.insert(transaction)
        router.selectedBookID = longBook.stableID
        try context.save()
        XCTAssertFalse(longBook.isDefault)
        XCTAssertEqual(router.selectedBookID, longBook.stableID)
        for (scheme, width, size, name) in scenes {
            try await capture(pushed(AnyView(AssetsView())), container: container, router: router,
                scheme: scheme, width: width, size: size, name: "assets-no-history-\(name)")
            try await capture(pushed(AnyView(BudgetView())), container: container, router: router,
                scheme: scheme, width: width, size: size, name: "budget-long-book-\(name)")
            try await capture(AnyView(BudgetRuleEditorSheet(bookID: longBook.stableID, editing: rule, suggestionYuan: nil)),
                container: container, router: router, scheme: scheme, width: width, size: size,
                name: "budget-editor-\(name)", sheetOver: pushed(AnyView(BudgetView())))
            try await capture(AnyView(AccountEditorSheet(account: bank, nextSortOrder: bank.sortOrder)),
                container: container, router: router, scheme: scheme, width: width, size: size,
                name: "assets-account-editor-\(name)", sheetOver: pushed(AnyView(AssetsView(startsOnFunds: true))),
                detents: [.medium, .large])
            try await capture(AnyView(BudgetDaySheet(selectedBookID: longBook.stableID, day: today)),
                container: container, router: router, scheme: scheme, width: width, size: size,
                name: "budget-day-\(name)", sheetOver: pushed(AnyView(BudgetView())), detents: [.medium, .large])
            try await capture(AnyView(EditTransactionSheet(transaction: transaction)),
                container: container, router: router, scheme: scheme, width: width, size: size,
                name: "budget-transaction-editor-\(name)", sheetOver: pushed(AnyView(BudgetView())),
                through: AnyView(BudgetDaySheet(selectedBookID: longBook.stableID, day: today)))
        }
    }

    private func pushed(_ destination: AnyView) -> AnyView {
        AnyView(NavigationStack(path: .constant(["page"])) {
            Color.clear
                .navigationTitle("肥喵")
                .navigationDestination(for: String.self) { _ in destination }
        })
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
                         width: CGFloat, size: UIContentSizeCategory, name: String, sheetOver parent: AnyView? = nil,
                         detents: Set<PresentationDetent> = [.large], through intermediate: AnyView? = nil) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 912)
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        window.traitOverrides.preferredContentSizeCategory = size
        let presentation = CapturePresentation()
        let nestedPresentation = CapturePresentation()
        let sheetContent = intermediate.map {
            AnyView(CaptureSheetHost(parent: $0, content: view, presentation: nestedPresentation, detents: detents))
        } ?? view
        let root = parent.map {
            AnyView(CaptureSheetHost(parent: $0, content: sheetContent, presentation: presentation,
                                    detents: intermediate == nil ? detents : [.medium, .large]))
        } ?? view
        let controller = CaptureHostingController(rootView: root.liquidGlassChrome().modelContainer(container).environment(router)
            .environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: "zh-Hans")))
        let presenter = CapturePresenterController()
        window.rootViewController = presenter
        controller.modalPresentationStyle = .fullScreen
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        var captureError: Error?
        var intermediateController: UIViewController?
        do {
            try await waitUntil(name: name, phase: "window appearance") {
                presenter.isVisible && presenter.view.window === window && presenter.transitionCoordinator == nil
            }
            var presented = false
            presenter.present(controller, animated: false) { presented = true }
            try await waitUntil(name: name, phase: "appearance") {
                presented && controller.isVisible && controller.view.window === window
                    && !controller.isBeingPresented && controller.transitionCoordinator == nil
            }
            if parent != nil {
                presentation.isPresented = true
                try await waitUntil(name: name, phase: "sheet presentation") {
                    guard let sheet = controller.presentedViewController else { return false }
                    return sheet.view.window === window && !sheet.isBeingPresented
                        && sheet.transitionCoordinator == nil && sheet.presentationController != nil
                }
                if intermediate != nil {
                    let host = try XCTUnwrap(controller.presentedViewController)
                    intermediateController = host
                    nestedPresentation.isPresented = true
                    try await waitUntil(name: name, phase: "nested sheet presentation") {
                        guard let sheet = host.presentedViewController else { return false }
                        return sheet.view.window === window && !sheet.isBeingPresented
                            && sheet.transitionCoordinator == nil && sheet.presentationController != nil
                    }
                }
            }
            controller.view.layoutIfNeeded()
            controller.presentedViewController?.view.layoutIfNeeded()
            intermediateController?.presentedViewController?.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            XCTAssertEqual(image.size.width, width)
            XCTAssertEqual(image.size.height, 912)
            let attachment = XCTAttachment(image: image)
            attachment.name = "concept-v1-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch {
            captureError = error
        }
        do {
            if let host = intermediateController {
                nestedPresentation.isPresented = false
                try await waitUntil(name: name, phase: "nested sheet dismissal") {
                    host.presentedViewController == nil && host.transitionCoordinator == nil
                        && !host.isBeingDismissed
                }
            }
            presentation.isPresented = false
            try await waitUntil(name: name, phase: "sheet dismissal") {
                controller.presentedViewController == nil && controller.isVisible && controller.transitionCoordinator == nil
            }
            try await closeCapture(controller, window: window, name: name)
        } catch {
            // Preserve the failure, but still attempt native dismissal before detaching the window.
            nestedPresentation.isPresented = false
            presentation.isPresented = false
            try? await closeCapture(controller, window: window, name: name)
            if let captureError { throw captureError }
            throw error
        }
        if let captureError { throw captureError }
    }

    private func closeCapture<Content: View>(_ controller: CaptureHostingController<Content>,
                                             window: UIWindow, name: String) async throws {
        if let sheet = controller.presentedViewController {
            var completed = false
            controller.dismiss(animated: false) { completed = true }
            try await waitUntil(name: name, phase: "native dismissal cleanup") {
                completed && controller.presentedViewController == nil && sheet.presentingViewController == nil
                    && !sheet.isBeingDismissed && sheet.transitionCoordinator == nil
            }
        }
        try await waitUntil(name: name, phase: "host before removal") {
            controller.isVisible && controller.transitionCoordinator == nil
        }
        if let presenter = controller.presentingViewController {
            var completed = false
            presenter.dismiss(animated: false) { completed = true }
            try await waitUntil(name: name, phase: "host dismissal") {
                completed && presenter.presentedViewController == nil && controller.presentingViewController == nil
                    && !controller.isVisible && !controller.isBeingDismissed && controller.transitionCoordinator == nil
                    && (presenter as? CapturePresenterController)?.isVisible == true
            }
        }
        try await waitUntil(name: name, phase: "disappearance") {
            !controller.isVisible && controller.transitionCoordinator == nil
        }
        window.isHidden = true
    }

    private func waitUntil(name: String, phase: String, _ ready: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !ready(), Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(ready(), "\(name): host not ready for \(phase)")
        guard ready() else { throw CaptureError.hostNotReady }
    }

    private enum CaptureError: Error { case hostNotReady }

    private final class CapturePresenterController: UIViewController {
        private(set) var isVisible = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            isVisible = true
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            isVisible = false
        }
    }

    private final class CapturePresentation: ObservableObject {
        @Published var isPresented = false
    }

    private struct CaptureSheetHost: View {
        let parent: AnyView
        let content: AnyView
        @ObservedObject var presentation: CapturePresentation
        let detents: Set<PresentationDetent>

        var body: some View {
            parent.sheet(isPresented: $presentation.isPresented) {
                content.presentationDetents(detents)
            }
        }
    }

    private final class CaptureHostingController<Content: View>: UIHostingController<Content> {
        private(set) var isVisible = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            isVisible = true
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            isVisible = false
        }
    }
}
