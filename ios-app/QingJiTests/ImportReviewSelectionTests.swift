import XCTest
import QingJiCore
@testable import QingJi

/// 导入复核的默认分类：分类晚到、账单重建都要补选，已经选好的不动。
@MainActor
final class ImportReviewSelectionTests: XCTestCase {
    private var categories: [ImportReviewView.SeedCategory] {
        CategorySeed.all.map { (key: $0.key, kind: $0.kind, name: $0.localizedName(languageCode: "zh")) }
    }

    func testSeedWaitsForCategoriesAndKeepsExistingChoices() throws {
        let records = ImportReviewView.demoResult().records
        let keyboard = records[0], transfer = records[1], daily = records[2]
        let refund = try XCTUnwrap(records.first(where: { $0.eventType == .refund }))

        // 分类还没读到时什么都不选；读到以后再补。
        XCTAssertEqual(seed(records, categories: []), [:])
        let automatic = seed(records)
        XCTAssertEqual(automatic[keyboard.id], "shop_digital_acc")
        XCTAssertNotNil(automatic[transfer.id])
        XCTAssertNotNil(automatic[daily.id])
        XCTAssertNil(automatic[refund.id])

        // 用户手动选过的行，再补选也不改，其他行照常补。
        let manual = try XCTUnwrap(categories.first(where: {
            $0.kind == .expense && $0.key != automatic[transfer.id]
        })).key
        let seeded = seed(records, existing: [transfer.id: manual])
        XCTAssertEqual(seeded[transfer.id], manual)
        XCTAssertEqual(seeded[keyboard.id], automatic[keyboard.id])
        XCTAssertEqual(seeded[daily.id], automatic[daily.id])
        XCTAssertNil(seeded[refund.id])
    }

    func testRebuiltBillRowsAreSeededAgain() {
        // 截图路由重画会重新生成演示账单，编号全换；旧选择对不上，新行要重新补上。
        let earlier = seed(ImportReviewView.demoResult().records)
        let rebuilt = ImportReviewView.demoResult().records
        let seeded = seed(rebuilt, existing: earlier)
        for record in rebuilt where record.eventType != .refund {
            XCTAssertNotNil(seeded[record.id], record.note)
        }
    }

    private func seed(
        _ records: [TransactionRecord],
        categories: [ImportReviewView.SeedCategory]? = nil,
        existing: [UUID: String] = [:]
    ) -> [UUID: String] {
        ImportReviewView.seededSelections(
            records: records,
            categories: categories ?? self.categories,
            existing: existing,
            remembered: { _, _ in nil }
        )
    }
}
