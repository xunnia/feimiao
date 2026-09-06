import Foundation
import FeiMiaoData
import FeiMiaoDomain

#if DEBUG && targetEnvironment(simulator)
enum SimulatorDemoSeeder {
    private static let settingKey = "ios_simulator_demo_v1"

    static func seedIfNeeded(repository: LedgerRepository) throws {
        guard try repository.setting(for: settingKey) != "1",
              !(try repository.hasAnyVisibleTransaction()) else { return }

        let bookID = try repository.defaultBookID()
        guard let accountID = try repository.accounts()
            .first(where: \.isAvailableForNewTransactions)?.id else { return }

        let categories = try repository.categories()
        let categoryIDs = Dictionary(
            uniqueKeysWithValues: categories.map { ($0.key, $0.id) }
        )
        let calendar = Calendar.current
        let now = Date.now

        func date(daysAgo: Int, hour: Int, minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            return calendar.date(
                bySettingHour: hour,
                minute: minute,
                second: 0,
                of: day
            ) ?? day
        }

        let drafts: [TransactionDraft] = [
            TransactionDraft(
                bookID: bookID,
                kind: .expense,
                amountText: "18.30",
                categoryID: categoryIDs["trans_public"],
                accountID: accountID,
                note: "公交出行",
                date: date(daysAgo: 0, hour: 8, minute: 42)
            ),
            TransactionDraft(
                bookID: bookID,
                kind: .expense,
                amountText: "30.00",
                categoryID: categoryIDs["subscription"],
                accountID: accountID,
                note: "原神充值",
                date: date(daysAgo: 1, hour: 21, minute: 16)
            ),
            TransactionDraft(
                bookID: bookID,
                kind: .expense,
                amountText: "20.79",
                categoryID: categoryIDs["dining"],
                accountID: accountID,
                note: "蒙自源",
                date: date(daysAgo: 1, hour: 12, minute: 25)
            ),
            TransactionDraft(
                bookID: bookID,
                kind: .expense,
                amountText: "37.80",
                categoryID: categoryIDs["dining_lunch"],
                accountID: accountID,
                note: "遇见小面",
                date: date(daysAgo: 2, hour: 18, minute: 35)
            ),
            TransactionDraft(
                bookID: bookID,
                kind: .expense,
                amountText: "68.00",
                categoryID: categoryIDs["shopping"],
                accountID: accountID,
                note: "日用品",
                date: date(daysAgo: 3, hour: 19, minute: 8)
            ),
            TransactionDraft(
                bookID: bookID,
                kind: .income,
                amountText: "3200.00",
                categoryID: categoryIDs["salary"],
                accountID: accountID,
                note: "本月工资",
                date: date(daysAgo: 5, hour: 9, minute: 0)
            ),
        ]

        for draft in drafts {
            _ = try repository.saveTransaction(draft)
        }
        try repository.setSetting("1", for: settingKey)
    }
}
#endif
