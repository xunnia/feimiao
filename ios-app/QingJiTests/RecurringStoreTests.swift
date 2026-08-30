import XCTest
import SwiftData
import QingJiCore
@testable import QingJi

@MainActor
final class RecurringStoreTests: XCTestCase {
    func testMaterializeDueCreatesOneTransactionAndIsIdempotent() throws {
        let schema = Schema([
            Account.self,
            Book.self,
            TxCategory.self,
            MoneyTransaction.self,
            RecurringRule.self,
            RecurringOccurrence.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        let due = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 30,
            hour: 9
        )))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 30,
            hour: 12
        )))

        let book = Book(name: "总账本", isDefault: true)
        let bank = Account(name: "Parity银行卡", kind: .bankCard)
        let housing = TxCategory(
            key: "housing",
            name: "居家住房",
            symbol: "house",
            kind: .expense,
            emoji: "🏠"
        )
        let rule = RecurringRule(
            amount: 3200,
            kind: .expense,
            bookID: book.stableID,
            categoryKey: housing.key,
            accountID: bank.stableID,
            note: "房租",
            period: .monthly,
            startDate: due,
            firstDueDate: due
        )
        context.insert(book)
        context.insert(bank)
        context.insert(housing)
        context.insert(rule)
        try context.save()

        XCTAssertEqual(
            try RecurringStore.materializeDue(in: context, now: now, calendar: calendar),
            1
        )
        let transactions = try context.fetch(FetchDescriptor<MoneyTransaction>())
        XCTAssertEqual(transactions.count, 1)
        let transaction = try XCTUnwrap(transactions.first)
        XCTAssertEqual(transaction.amount, 3200)
        XCTAssertEqual(transaction.note, "房租")
        XCTAssertEqual(transaction.recurringRuleID, rule.stableID)
        XCTAssertTrue(calendar.isDate(transaction.date, inSameDayAs: due))

        XCTAssertEqual(
            try RecurringStore.materializeDue(in: context, now: now, calendar: calendar),
            0
        )
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MoneyTransaction>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RecurringOccurrence>()), 1)
    }
}
