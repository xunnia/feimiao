import XCTest
@testable import QingJi

final class AssetStructureProjectionTests: XCTestCase {
    private func projection(total: Decimal = 6, liabilities: Decimal = 9,
                            cash: Decimal = 1, investment: Decimal = 2,
                            receivable: Decimal = 3, currencies: Set<String> = []) -> AssetStructureProjection {
        AssetStructureProjection(breakdown: NetWorthStore.Breakdown(
            totalAssets: total, totalLiabilities: liabilities, netWorth: total - liabilities,
            cashAssets: cash, investmentAssets: investment, physicalAssets: 0,
            receivableAssets: receivable, unsupportedCurrencies: currencies))
    }
    func testExactAmountsAndShareDenominator() {
        let value = projection()
        XCTAssertTrue(value.isConsistent)
        XCTAssertEqual(value.visibleKinds.count, 3)
        XCTAssertEqual(AssetStructureProjection.percentLabel(value.percentage(.cash)), "16.7%")
        XCTAssertEqual(value.percentage(.receivable), 50)
        XCTAssertEqual(value.liabilityPercentage, 150)
    }
    func testSingleBucketHasRealShare() {
        let value = projection(total: 42, cash: 42, investment: 0, receivable: 0)
        XCTAssertEqual(value.visibleKinds, [.cash])
        XCTAssertEqual(value.percentage(.cash), 100)
    }
    func testMissingCurrencyDoesNotClaimFullShare() {
        let value = projection(currencies: ["USD"])
        XCTAssertEqual(value.amounts[.cash], 1)
        XCTAssertNil(value.percentage(.cash))
        XCTAssertNil(value.liabilityPercentage)
    }
    func testZeroAssetsWithDebtIsNotApplicable() {
        let value = projection(total: 0, cash: 0, investment: 0, receivable: 0)
        XCTAssertTrue(value.isConsistent)
        XCTAssertEqual(value.visibleKinds, [])
        XCTAssertNil(value.liabilityPercentage)
    }
    func testMismatchAndNegativeAmountsAreNotNormalized() {
        XCTAssertFalse(projection(total: 100).hasShares)
        let value = projection(total: 4, cash: -1)
        XCTAssertEqual(value.amounts[.cash], -1)
        XCTAssertFalse(value.hasShares)
    }
    func testLiabilityRatioIsNotCapped() {
        XCTAssertEqual(projection(liabilities: 60).liabilityPercentage, 1000)
        XCTAssertNil(projection(liabilities: -1).liabilityPercentage)
    }
}
