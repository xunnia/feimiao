import XCTest
import SwiftData
@testable import QingJi

@MainActor
final class AssetStoreTests: XCTestCase {
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
}
