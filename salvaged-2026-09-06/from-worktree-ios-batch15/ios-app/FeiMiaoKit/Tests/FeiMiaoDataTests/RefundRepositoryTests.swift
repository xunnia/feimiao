import Foundation
import GRDB
import XCTest
@testable import FeiMiaoData
@testable import FeiMiaoDomain

final class RefundRepositoryTests: XCTestCase {
    func testPartialRefundUsesOriginalPostingFieldsAndReturnsDetails() throws {
        let repository = try inMemoryRepository()
        let original = try saveExpense(
            repository,
            amount: "100",
            date: Date(timeIntervalSince1970: 1_704_067_200.123)
        )

        let refund = try repository.refundTransaction(
            id: original.id,
            amount: try money("30"),
            note: "  部分退款  "
        )

        XCTAssertEqual(refund.kind, .expense)
        XCTAssertEqual(refund.amount, try money("-30"))
        XCTAssertEqual(refund.bookID, original.bookID)
        XCTAssertEqual(refund.currencyCode, original.currencyCode)
        XCTAssertEqual(refund.categoryID, original.categoryID)
        XCTAssertEqual(refund.accountID, original.accountID)
        XCTAssertNil(refund.toAccountID)
        XCTAssertEqual(refund.note, "部分退款")
        XCTAssertEqual(refund.date, original.date)
        XCTAssertEqual(refund.timePrecision, original.timePrecision)
        XCTAssertEqual(refund.refundOf, original.id)

        let details = try repository.refundDetails(transactionID: original.id)
        XCTAssertEqual(details.transaction.id, original.id)
        XCTAssertEqual(details.refunds.map(\.id), [refund.id])
        XCTAssertEqual(details.refundedAmount, try money("30"))
        XCTAssertEqual(details.refundableAmount, try money("70"))
        XCTAssertEqual(details.netAmount, try money("70"))
        XCTAssertFalse(details.isFullyRefunded)
        XCTAssertEqual(try repository.netAmount(transactionID: original.id), try money("70"))
        XCTAssertEqual(try repository.transactions().map(\.id), [original.id])
        XCTAssertEqual(try repository.summary().expense, try money("70"))
    }

    func testFullRefundUsesExactlyTheRemainingAmount() throws {
        let repository = try inMemoryRepository()
        let original = try saveExpense(repository, amount: "100")
        _ = try repository.refundTransaction(
            id: original.id,
            amount: try money("35")
        )

        let fullRefund = try repository.refundTransactionInFull(id: original.id)

        XCTAssertEqual(fullRefund.amount, try money("-65"))
        let details = try repository.refundDetails(transactionID: original.id)
        XCTAssertEqual(details.refunds.count, 2)
        XCTAssertEqual(details.refundedAmount, try money("100"))
        XCTAssertEqual(details.refundableAmount, .zero)
        XCTAssertEqual(details.netAmount, .zero)
        XCTAssertTrue(details.isFullyRefunded)
        XCTAssertThrowsError(try repository.refundTransactionInFull(id: original.id)) { error in
            XCTAssertEqual(error as? LedgerRepositoryError, .noRefundableAmount)
        }
    }

    func testRefundRejectsAmountsAboveTheRemainingBalance() throws {
        let repository = try inMemoryRepository()
        let original = try saveExpense(repository, amount: "100")
        _ = try repository.refundTransaction(
            id: original.id,
            amount: try money("60")
        )

        XCTAssertThrowsError(
            try repository.refundTransaction(
                id: original.id,
                amount: try money("40.01")
            )
        ) { error in
            XCTAssertEqual(error as? LedgerRepositoryError, .refundExceedsRemainingAmount)
        }
        XCTAssertThrowsError(
            try repository.refundTransaction(id: original.id, amount: .zero)
        ) { error in
            XCTAssertEqual(error as? LedgerRepositoryError, .invalidAmount)
        }
        let firstRefund = try XCTUnwrap(
            repository.refundDetails(transactionID: original.id).refunds.first
        )
        XCTAssertThrowsError(
            try repository.refundTransaction(
                id: firstRefund.id,
                amount: try money("1")
            )
        ) { error in
            XCTAssertEqual(error as? LedgerRepositoryError, .invalidRefundTarget)
        }

        let details = try repository.refundDetails(transactionID: original.id)
        XCTAssertEqual(details.refunds.count, 1)
        XCTAssertEqual(details.refundedAmount, try money("60"))
        XCTAssertEqual(details.refundableAmount, try money("40"))
    }

    func testRevokingOneRefundRestoresOnlyItsAmount() throws {
        let repository = try inMemoryRepository()
        let original = try saveExpense(repository, amount: "100")
        let first = try repository.refundTransaction(
            id: original.id,
            amount: try money("30")
        )
        let second = try repository.refundTransaction(
            id: original.id,
            amount: try money("20")
        )

        try repository.revokeRefund(id: first.id)

        let details = try repository.refundDetails(transactionID: original.id)
        XCTAssertEqual(details.refunds.map(\.id), [second.id])
        XCTAssertEqual(details.refundedAmount, try money("20"))
        XCTAssertEqual(details.refundableAmount, try money("80"))
        XCTAssertTrue(try repository.transaction(id: first.id).isDeleted)
        XCTAssertFalse(try repository.transaction(id: second.id).isDeleted)
        XCTAssertFalse(try repository.transaction(id: original.id).isDeleted)
        XCTAssertThrowsError(try repository.revokeRefund(id: first.id)) { error in
            XCTAssertEqual(error as? LedgerRepositoryError, .recordNotFound)
        }
    }

    func testRefundDateBelongsToTheOriginalTransactionMonth() throws {
        let repository = try inMemoryRepository()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let januaryStart = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))
        )
        let februaryStart = try XCTUnwrap(
            calendar.date(byAdding: .month, value: 1, to: januaryStart)
        )
        let marchStart = try XCTUnwrap(
            calendar.date(byAdding: .month, value: 1, to: februaryStart)
        )
        let originalDate = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 1,
                day: 31,
                hour: 23,
                minute: 59,
                second: 59,
                nanosecond: 123_000_000
            ))
        )
        let original = try saveExpense(
            repository,
            amount: "100",
            date: originalDate
        )

        let refund = try repository.refundTransaction(
            id: original.id,
            amount: try money("40")
        )

        let storedOriginalDateMS = try storedDateMS(
            transactionID: original.id,
            repository: repository
        )
        let storedRefundDateMS = try storedDateMS(
            transactionID: refund.id,
            repository: repository
        )
        XCTAssertEqual(storedRefundDateMS, storedOriginalDateMS)
        XCTAssertEqual(milliseconds(refund.date), milliseconds(original.date))
        XCTAssertEqual(refund.bookID, original.bookID)
        let january = try repository.homeMonthSnapshot(
            bookID: original.bookID,
            monthStart: januaryStart,
            nextMonthStart: februaryStart
        )
        XCTAssertEqual(january.transactions.map(\.id), [original.id])
        XCTAssertEqual(january.summary.expense, try money("60"))
        XCTAssertEqual(january.netAmounts[original.id], try money("60"))

        let february = try repository.homeMonthSnapshot(
            bookID: original.bookID,
            monthStart: februaryStart,
            nextMonthStart: marchStart
        )
        XCTAssertTrue(february.transactions.isEmpty)
        XCTAssertEqual(february.summary.expense, .zero)
    }

    func testDeletingOriginalTransactionSoftDeletesItsRefunds() throws {
        let repository = try inMemoryRepository()
        let original = try saveExpense(repository, amount: "100")
        let first = try repository.refundTransaction(
            id: original.id,
            amount: try money("30")
        )
        let second = try repository.refundTransaction(
            id: original.id,
            amount: try money("20")
        )

        try repository.deleteTransaction(id: original.id)

        XCTAssertTrue(try repository.transaction(id: original.id).isDeleted)
        XCTAssertTrue(try repository.transaction(id: first.id).isDeleted)
        XCTAssertTrue(try repository.transaction(id: second.id).isDeleted)
        XCTAssertTrue(try repository.transactions().isEmpty)
        XCTAssertThrowsError(try repository.refundDetails(transactionID: original.id)) { error in
            XCTAssertEqual(error as? LedgerRepositoryError, .recordNotFound)
        }
    }

    private func inMemoryRepository() throws -> LedgerRepository {
        LedgerRepository(database: try AppDatabase(inMemory: true))
    }

    private func saveExpense(
        _ repository: LedgerRepository,
        amount: String,
        date: Date = Date(timeIntervalSince1970: 1_720_000_000)
    ) throws -> LedgerTransaction {
        let accountID = try XCTUnwrap(repository.accounts().first?.id)
        let categoryID = try XCTUnwrap(
            repository.categories(kind: .expense).first?.id
        )
        return try repository.saveTransaction(
            TransactionDraft(
                bookID: try repository.defaultBookID(),
                kind: .expense,
                amountText: amount,
                categoryID: categoryID,
                accountID: accountID,
                note: "original expense",
                date: date,
                timePrecision: .dateOnly
            )
        )
    }

    private func money(_ value: String) throws -> MoneyAmount {
        try XCTUnwrap(MoneyAmount(value))
    }

    private func milliseconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1_000)
    }

    private func storedDateMS(
        transactionID: Int64,
        repository: LedgerRepository
    ) throws -> Int64 {
        try repository.database.queue.read { db in
            try XCTUnwrap(
                Int64.fetchOne(
                    db,
                    sql: "SELECT date_ms FROM transactions WHERE id = ?",
                    arguments: [transactionID]
                )
            )
        }
    }
}
