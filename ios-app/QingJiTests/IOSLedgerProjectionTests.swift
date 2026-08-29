import XCTest
import QingJiCore
@testable import QingJi

@MainActor
final class IOSLedgerProjectionTests: XCTestCase {
    func testLedgerSnapshotReusesProjectionUntilLedgerChanges() {
        let transactions = makeTransactions(count: 256)
        let cache = IOSLedgerProjectionCache()

        let first = cache.snapshot(for: transactions, selectedBookID: nil)
        let second = cache.snapshot(for: transactions, selectedBookID: nil)

        XCTAssertEqual(first.records.count, 256)
        XCTAssertEqual(first.includedRecords.count, 256)
        XCTAssertEqual(cache.rebuildCount, 1)
        XCTAssertEqual(first.records, second.records)

        let selectedBookID = UUID()
        _ = cache.snapshot(for: transactions, selectedBookID: selectedBookID)
        XCTAssertEqual(cache.rebuildCount, 2)

        transactions[0].note = "已修改"
        _ = cache.snapshot(for: transactions, selectedBookID: selectedBookID)
        XCTAssertEqual(cache.rebuildCount, 3)
    }

    func testRepeatedSnapshotReadsDoNotRebuildDTOs() {
        let transactions = makeTransactions(count: 10_000)
        let cache = IOSLedgerProjectionCache()
        let snapshot = cache.snapshot(for: transactions, selectedBookID: nil)
        let statisticsCache = IOSStatisticsProjectionCache()
        let calendar = Calendar(identifier: .gregorian)
        let monthComponents = calendar.dateComponents([.year, .month], from: transactions[0].date)
        let year = monthComponents.year ?? 2023
        let month = monthComponents.month ?? 1

        measure(metrics: [XCTClockMetric()]) {
            for _ in 0..<30 {
                _ = cache.snapshot(for: transactions, selectedBookID: nil)
                _ = statisticsCache.monthly(
                    of: snapshot.records,
                    revision: snapshot.revision,
                    year: year,
                    month: month,
                    calendar: calendar
                )
            }
        }

        XCTAssertEqual(cache.rebuildCount, 1)
        XCTAssertEqual(statisticsCache.calculationCount, 1)
    }

    private func makeTransactions(count: Int) -> [MoneyTransaction] {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<count).map { index in
            MoneyTransaction(
                amount: Decimal(index % 97 + 1),
                kind: index.isMultiple(of: 5) ? .income : .expense,
                date: baseDate.addingTimeInterval(TimeInterval(index * 60)),
                note: "测试流水 \(index)"
            )
        }
    }
}
