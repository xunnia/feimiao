import XCTest
@testable import QingJiCore

final class AssetMetricsTests: XCTestCase {
    func testMetricsMatchAndroidContract() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let result = AssetMetrics.resolve(
            PhysicalAssetMetricInput(
                netAcquisitionCost: 1_000,
                additionalNetCost: 100,
                currentNetValue: 880,
                purchasedAt: start,
                endedAt: nil,
                isEconomicallyOwned: true,
                hasKnownValuation: true,
                usageTrackingEnabled: true,
                usageCount: 11
            ),
            asOf: end,
            calendar: calendar
        )

        XCTAssertEqual(result.heldDays.value, 10)
        XCTAssertEqual(result.cumulativeHoldingInvestment.value, 1_100)
        XCTAssertEqual(result.dailyHoldingCost.value, 110)
        XCTAssertEqual(result.perUseHoldingCost.value, 100)
        XCTAssertEqual(result.valueRetentionRatio.value, Decimal(string: "0.88"))
    }

    func testUnknownPurchaseDateDoesNotInventAverages() {
        let result = AssetMetrics.resolve(
            PhysicalAssetMetricInput(
                netAcquisitionCost: 1_000,
                currentNetValue: 900,
                purchasedAt: nil,
                endedAt: nil,
                isEconomicallyOwned: true,
                hasKnownValuation: true
            )
        )

        XCTAssertFalse(result.heldDays.isExact)
        XCTAssertFalse(result.dailyHoldingCost.isExact)
        XCTAssertEqual(result.heldDays.reason, "购买日期未知")
    }

    func testAllocationPolicyRejectsOverlappingRefundOrGross() throws {
        let first = UUID()
        let second = UUID()
        XCTAssertThrowsError(try AssetAllocationPolicy.validate(
            orderGrossCents: 10_000,
            validOrderRefundCents: 2_000,
            lines: [
                AssetAllocationLine(assetID: first, grossCents: 6_000, refundCents: 1_000),
                AssetAllocationLine(assetID: second, grossCents: 5_000, refundCents: 1_000),
            ]
        )) { error in
            XCTAssertEqual(error as? AssetAllocationError, .grossExceedsOrder)
        }
        XCTAssertThrowsError(try AssetAllocationPolicy.validate(
            orderGrossCents: 10_000,
            validOrderRefundCents: 2_000,
            lines: [
                AssetAllocationLine(assetID: first, grossCents: 5_000, refundCents: 1_000),
                AssetAllocationLine(assetID: first, grossCents: 1_000, refundCents: 0),
            ]
        )) { error in
            XCTAssertEqual(error as? AssetAllocationError, .duplicateAsset)
        }
    }
}
