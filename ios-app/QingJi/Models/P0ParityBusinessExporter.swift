import Foundation
import QingJiCore

/// Exports the actual demo model graph in a platform-neutral shape.
///
/// The file is written only in the CI demo process. It is copied out of the
/// simulator container by the parity workflow and never ships as user data.
enum P0ParityBusinessExporter {
    static let fileName = "p0-business-ios.json"

    static func write(
        fixture: P0ParityFixture,
        inputHash: String,
        books: [String: Book],
        accounts: [String: Account],
        transactions: [MoneyTransaction],
        budgets: [Budget],
        savingsGoals: [SavingsGoal],
        recurringRules: [RecurringRule],
        reports: [ReportRecord],
        physicalAssets: [PhysicalAsset]
    ) throws {
        guard ProcessInfo.processInfo.environment["QINGJI_DEMO"] == "1" else { return }
        let payload = try makePayload(
            fixture: fixture,
            inputHash: inputHash,
            books: books,
            accounts: accounts,
            transactions: transactions,
            budgets: budgets,
            savingsGoals: savingsGoals,
            recurringRules: recurringRules,
            reports: reports,
            physicalAssets: physicalAssets
        )
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
    }

    private static func makePayload(
        fixture: P0ParityFixture,
        inputHash: String,
        books: [String: Book],
        accounts: [String: Account],
        transactions: [MoneyTransaction],
        budgets: [Budget],
        savingsGoals: [SavingsGoal],
        recurringRules: [RecurringRule],
        reports: [ReportRecord],
        physicalAssets: [PhysicalAsset]
    ) throws -> [String: Any] {
        guard books.count == fixture.books.count,
              accounts.count == fixture.accounts.count,
              transactions.count == fixture.transactions.count,
              budgets.count == fixture.budgets.count,
              savingsGoals.count == fixture.savingsGoals.count,
              recurringRules.count == fixture.recurringRules.count,
              reports.count == fixture.reports.count else {
            throw P0ParityFixtureError.invalidReference("export row count")
        }

        let bookKeyByID = Dictionary(uniqueKeysWithValues: books.map { ($0.value.stableID, $0.key) })
        let accountKeyByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.value.stableID, $0.key) })
        let transactionKeyByID = Dictionary(
            uniqueKeysWithValues: zip(fixture.transactions, transactions).map { ($1.stableID, $0.key) }
        )
        let logicalNow = try P0ParityFixtureLoader.date(fixture.clock)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: fixture.timezone) ?? .current
        let month = calendar.dateComponents([.year, .month], from: logicalNow)

        let transactionRows: [[String: Any]] = zip(fixture.transactions, transactions).map {
            row,
            transaction in
            transactionPayload(
                row: row,
                transaction: transaction,
                bookKeyByID: bookKeyByID,
                accountKeyByID: accountKeyByID,
                transactionKeyByID: transactionKeyByID
            )
        }
        let summary = summaryPayload(
            fixture: fixture,
            transactions: transactions,
            budgets: budgets,
            logicalNow: logicalNow,
            calendar: calendar
        )

        let bookRows: [[String: Any]] = try fixture.books.map { row in
            guard let book = books[row.key] else {
                throw P0ParityFixtureError.invalidReference("export book \(row.key)")
            }
            return [
                "key": row.key,
                "name": book.name,
                "includeInTotal": book.includeInTotal,
                "isDefault": book.isDefault,
                "sortOrder": book.sortOrder,
            ]
        }
        let accountRows: [[String: Any]] = try fixture.accounts.map { row in
            guard let account = accounts[row.key] else {
                throw P0ParityFixtureError.invalidReference("export account \(row.key)")
            }
            let balance = LedgerStore.accountBalance(
                for: account,
                transactions: transactions,
                checkpoints: []
            )
            return [
                "key": row.key,
                "name": account.name,
                "kind": canonicalAccountKind(account.kind),
                "initialBalance": decimal(account.initialBalance),
                "balance": decimal(balance),
                "sortOrder": account.sortOrder,
            ]
        }
        let budgetRows: [[String: Any]] = try zip(fixture.budgets, budgets).map {
            row,
            budget in
            let actualBook = budget.bookID.flatMap { bookKeyByID[$0] }
            guard actualBook == row.book,
                  budget.categoryKey == row.category else {
                throw P0ParityFixtureError.invalidReference("export budget references \(row.key)")
            }
            return [
                "key": row.key,
                "book": optional(actualBook),
                "category": optional(budget.categoryKey),
                "periodStart": optional(budget.periodStart.map(iso)),
                "cycle": budget.cycleRaw,
                "amount": decimal(budget.amount),
            ]
        }
        let savingsGoalRows: [[String: Any]] = zip(fixture.savingsGoals, savingsGoals).map {
            row,
            goal in
            [
                "key": row.key,
                "name": goal.name,
                "emoji": goal.emoji,
                "target": decimal(goal.targetAmount),
                "saved": decimal(goal.savedAmount),
            ]
        }
        let recurringRuleRows: [[String: Any]] = zip(fixture.recurringRules, recurringRules).map {
            row,
            rule in
            [
                "key": row.key,
                "kind": rule.kindRaw,
                "amount": decimal(rule.amount),
                "category": optional(rule.categoryKey),
                "account": optional(rule.accountID.flatMap { accountKeyByID[$0] }),
                "toAccount": optional(rule.toAccountID.flatMap { accountKeyByID[$0] }),
                "book": optional(rule.bookID.flatMap { bookKeyByID[$0] }),
                "note": rule.note,
                "period": rule.periodRaw,
                "startDate": iso(rule.startDate),
                "endDate": optional(rule.endDate.map(iso)),
                "totalCount": optional(rule.totalCount),
            ]
        }
        let reportRows: [[String: Any]] = try zip(fixture.reports, reports).map {
            row,
            report in
            let actualBook = report.bookID.flatMap { bookKeyByID[$0] }
            guard actualBook == row.book else {
                throw P0ParityFixtureError.invalidReference("export report book \(row.key)")
            }
            return [
                "key": row.key,
                "type": report.type,
                "book": optional(actualBook),
                "title": report.title,
                "summary": report.summary,
                "periodStart": iso(report.periodStart),
                "periodEnd": iso(report.periodEnd),
            ]
        }
        let physicalAssetRows: [[String: Any]] = physicalAssets.map { asset in
            [
                "name": asset.name,
                "kind": asset.kindRaw,
                "purchasePrice": decimal(asset.purchasePrice),
                "currentValue": decimal(asset.currentValue),
                "purchaseDate": optional(asset.purchaseDate.map(iso)),
                "warrantyUntil": optional(asset.warrantyUntil.map(iso)),
                "includeInNetWorth": asset.includeInNetWorth,
            ]
        }

        let fixturePayload: [String: Any] = [
            "fixtureId": fixture.fixtureId,
            "inputHash": inputHash,
            "logicalNow": fixture.clock,
            "locale": fixture.locale,
            "timezone": fixture.timezone,
            "currency": fixture.currency,
        ]
        let logicalMonthPayload: [String: Any] = [
            "year": month.year ?? 0,
            "month": month.month ?? 0,
        ]
        let payload: [String: Any] = [
            "schemaVersion": 1,
            "platform": "ios",
            "fixture": fixturePayload,
            "books": bookRows,
            "accounts": accountRows,
            "transactions": transactionRows,
            "budgets": budgetRows,
            "savingsGoals": savingsGoalRows,
            "recurringRules": recurringRuleRows,
            "reports": reportRows,
            "physicalAssets": physicalAssetRows,
            "summary": summary,
            "logicalMonth": logicalMonthPayload,
        ]
        return payload
    }

    private static func transactionPayload(
        row: P0FixtureTransaction,
        transaction: MoneyTransaction,
        bookKeyByID: [UUID: String],
        accountKeyByID: [UUID: String],
        transactionKeyByID: [UUID: String]
    ) -> [String: Any] {
        [
            "key": row.key,
            "kind": transaction.kindRaw,
            "amount": decimal(transaction.amount),
            "category": optional(transaction.category?.key),
            "account": optional(transaction.account.flatMap { accountKeyByID[$0.stableID] }),
            "toAccount": optional(transaction.toAccount.flatMap { accountKeyByID[$0.stableID] }),
            "book": optional(transaction.book.flatMap { bookKeyByID[$0.stableID] }),
            "note": transaction.note,
            "date": iso(transaction.date),
            "settledAt": optional(transaction.settledAt.map(iso)),
            "settlementAccount": optional(transaction.settlementAccountID.flatMap { accountKeyByID[$0] }),
            "eventType": transaction.eventTypeRaw,
            "reimbursable": transaction.reimbursable,
            "isReimbursed": transaction.isReimbursed,
            "excluded": transaction.isExcluded,
            "refundOf": optional(transaction.refundOfID.flatMap { transactionKeyByID[$0] }),
        ]
    }

    private static func canonicalAccountKind(_ kind: AccountKind) -> String {
        switch kind {
        case .bankCard:
            return "debit"
        case .creditCard:
            return "credit"
        default:
            return kind.rawValue
        }
    }

    private static func summaryPayload(
        fixture: P0ParityFixture,
        transactions: [MoneyTransaction],
        budgets: [Budget],
        logicalNow: Date,
        calendar: Calendar
    ) -> [String: Any] {
        let month = calendar.dateComponents([.year, .month], from: logicalNow)
        let monthTransactions = transactions.filter {
            let value = calendar.dateComponents([.year, .month], from: $0.date)
            return value.year == month.year && value.month == month.month
        }
        let income = monthTransactions
            .filter { $0.kind == .income }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let grossExpense = monthTransactions
            .filter { $0.kind == .expense && $0.amount > 0 }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let refund = monthTransactions
            .filter { $0.kind == .expense && $0.amount < 0 }
            .reduce(Decimal.zero) { $0 + (-$1.amount) }
        let netExpense = grossExpense - refund
        let ordinaryRows = monthTransactions.filter {
            $0.kind != .transfer && $0.refundOfID == nil
        }.count
        return [
            "augustIncome": decimal(income),
            "augustGrossExpense": decimal(grossExpense),
            "augustRefund": decimal(refund),
            "augustNetExpense": decimal(netExpense),
            "augustBalance": decimal(income - netExpense),
            "augustTransactionRowsIncludingOffsetAndTransfer": monthTransactions.count,
            "augustVisibleOrdinaryRows": ordinaryRows,
            "budget": decimal(budgets.first(where: { $0.categoryKey == nil })?.amount ?? 0),
            "fixtureExpectedBalance": fixture.expected.augustBalance,
        ]
    }

    private static func decimal(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private static func optional(_ value: Any?) -> Any {
        value ?? NSNull()
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
