import AppIntents
import SwiftData
import QingJiCore

/// 快捷指令 / Siri 记账入口。配合「双击背面触发快捷指令」可实现
/// 在微信/支付宝支付完成页一键截屏 OCR 后自动入账（快捷指令侧解析金额后调用本 Intent）。
struct AddTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "快速记一笔"
    static let description = IntentDescription("不打开 App，直接往轻记里记一笔支出或收入。")
    static let openAppWhenRun = false

    @Parameter(title: "金额")
    var amount: Double

    @Parameter(title: "分类名")
    var categoryName: String?

    @Parameter(title: "备注")
    var note: String?

    @Parameter(title: "是收入", default: false)
    var isIncome: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0 else {
            return .result(dialog: "金额要大于 0 才能入账。")
        }
        let context = AppModelContainer.shared.mainContext
        DataSeeder.seedIfNeeded(context: context)

        let kind: TransactionKind = isIncome ? .income : .expense
        let categories = (try? context.fetch(FetchDescriptor<TxCategory>())) ?? []
        let matched = categories.first {
            guard $0.kind == kind, let name = categoryName, !name.isEmpty else { return false }
            return $0.name.localizedStandardContains(name) || name.localizedStandardContains($0.name)
        }
        let fallbackKey = kind == .income ? "otherIncome" : CategorySeed.fallbackExpenseKey
        let category = matched ?? categories.first { $0.key == fallbackKey }
        let account = (try? context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)])))?
            .first(where: { !$0.isDeleted && $0.status == .active })

        let transaction = try LedgerStore.createTransaction(
            in: context,
            amount: Decimal(amount),
            kind: kind,
            date: Date(),
            note: note ?? "",
            category: category,
            account: account,
            book: (try? context.fetch(FetchDescriptor<Book>(sortBy: [SortDescriptor(\.sortOrder)])))?.first
        )

        let amountText = MoneyFormat.string(transaction.amount, currencyCode: transaction.currencyCode)
        return .result(dialog: "已记一笔：\(category?.name ?? "") \(amountText)")
    }
}

struct QingJiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTransactionIntent(),
            phrases: [
                "用\(.applicationName)记一笔",
                "\(.applicationName)记账",
            ],
            shortTitle: "记一笔",
            systemImageName: "plus.circle.fill"
        )
    }
}
