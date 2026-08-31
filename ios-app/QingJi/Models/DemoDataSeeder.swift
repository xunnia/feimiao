import Foundation
import SwiftData
import QingJiCore

/// 演示模式种子数据 —— 仅在 QINGJI_DEMO=1 时调用，绝不出现在正式构建里。
/// 目的：让 CI 截图时统计图表、账单列表、预算进度条都有真实感的内容。
enum DemoDataSeeder {

    // MARK: - 入口

    /// 向内存容器写入仿真示例数据。
    /// 调用方需确保仅在 QINGJI_DEMO == "1" 时调用。
    static func seed(context: ModelContext) {
        // 先写分类（复用 CategorySeed，与正式首启一致）
        let categories = insertCategories(context: context)
        // 再写账户
        let accounts = insertAccounts(context: context)
        let book = Book(name: "总账本", includeInTotal: true, isDefault: true)
        context.insert(book)
        // 写交易流水（覆盖近几个月，让年度图和月度图都有内容）
        insertTransactions(context: context, categories: categories, accounts: accounts, book: book)
        // 与 android-app/integration_test/parity_screenshots_test.dart 保持同一
        // 个账本、同一周期和同一分类预算。截图只有在共享这组输入时才有对账意义。
        let calendar = Calendar.current
        let now = AppClock.now
        let monthStart = calendar.date(from: calendar.dateComponents(
            [.year, .month],
            from: now
        )) ?? now
        context.insert(Budget(
            amount: 3000,
            bookID: book.stableID,
            periodStart: monthStart,
            cycleRaw: BudgetCycle.monthly.rawValue
        ))
        context.insert(Budget(
            amount: 600,
            categoryKey: "dining",
            bookID: book.stableID,
            periodStart: monthStart,
            cycleRaw: BudgetCycle.monthly.rawValue
        ))
        context.insert(Budget(
            amount: 800,
            categoryKey: "shopping",
            bookID: book.stableID,
            periodStart: monthStart,
            cycleRaw: BudgetCycle.monthly.rawValue
        ))
        insertSavingsGoals(context: context)
        insertRecurringRules(context: context, categories: categories, accounts: accounts, book: book)
        // Keep the base 35-screen fixture aligned with Android, which starts
        // the asset hub without an existing physical asset. The detail
        // operation screen opts into the richer asset fixture explicitly.
        let launchScreen = ProcessInfo.processInfo.environment["QINGJI_SCREEN"] ?? ""
        if launchScreen == "assets/detail" ||
            launchScreen == "assets-detail" ||
            launchScreen == "settings/assets/detail" {
            insertAssetData(context: context, accounts: accounts, book: book)
        }
        if launchScreen == "lending" || launchScreen == "settings/lending" {
            insertLendingData(context: context, accounts: accounts, book: book)
        }
        insertReports(context: context, book: book)
        try? context.save()
    }

    // MARK: - 分类

    private static func insertCategories(context: ModelContext) -> [String: TxCategory] {
        var map: [String: TxCategory] = [:]
        for (index, seed) in CategorySeed.all.enumerated() {
            let cat = TxCategory(
                key: seed.key,
                name: seed.nameZh,
                symbol: seed.symbol,
                kind: seed.kind,
                sortOrder: index,
                emoji: seed.emoji,
                parentKey: seed.parentKey
            )
            context.insert(cat)
            map[seed.key] = cat
        }
        return map
    }

    // MARK: - 账户

    private static func insertAccounts(context: ModelContext) -> [Account] {
        let defs: [(String, AccountKind, Decimal)] = [
            ("现金",       .cash,       0),
            ("Parity银行卡", .bankCard, 12000),
            ("Parity信用卡", .creditCard, -1800),
        ]
        return defs.enumerated().map { index, item in
            let acc = Account(name: item.0, kind: item.1, currencyCode: "CNY", sortOrder: index)
            acc.initialBalance = item.2
            context.insert(acc)
            return acc
        }
    }

    // MARK: - 交易流水

    /// 生成约 30 条真实感流水，分布在近 4 个月（本月占多数）。
    private static func insertTransactions(
        context: ModelContext,
        categories: [String: TxCategory],
        accounts: [Account],
        book: Book
    ) {
        let wechat  = accounts.first { $0.kind == .cash }     ?? accounts[0]
        let bank    = accounts.first { $0.kind == .bankCard } ?? accounts[0]
        let cash    = accounts.first { $0.kind == .cash }     ?? accounts[0]

        // cat() 简写：取分类，取不到就用「其他」
        func cat(_ key: String) -> TxCategory? {
            categories[key] ?? categories["other"]
        }

        let now = AppClock.now
        // 生成相对 now 的偏移日期
        func daysAgo(_ n: Int) -> Date {
            Calendar.current.date(byAdding: .day, value: -n, to: now) ?? now
        }
        func thisMonthDate(_ index: Int) -> Date {
            guard index >= 14 else { return daysAgo(index * 2) }
            // Keep the two income rows inside the current month. Spacing all
            // 16 rows by two days would move indexes 14 and 15 into July.
            var components = Calendar.current.dateComponents([.year, .month], from: now)
            components.day = 27 - (index - 14) * 2
            components.hour = 12
            return Calendar.current.date(from: components) ?? now
        }
        func monthsAgo(_ m: Int, day: Int) -> Date {
            var comps = Calendar.current.dateComponents([.year, .month], from: now)
            comps.month = (comps.month ?? 1) - m
            comps.day   = day
            comps.hour  = 12
            return Calendar.current.date(from: comps) ?? now
        }

        // 本月流水（支出为主）
        let thisMonth: [(Decimal, TransactionKind, String, String, Account, String)] = [
            (38,   .expense, "dining",       "午餐 麦当劳",       wechat, "CNY"),
            (23,   .expense, "transport",    "滴滴打车",          wechat, "CNY"),
            (156,  .expense, "groceries",    "盒马超市",          wechat, "CNY"),
            (88,   .expense, "entertainment","网易云音乐年费",     wechat, "CNY"),
            (45,   .expense, "dining",       "晚餐 外卖",         wechat, "CNY"),
            (198,  .expense, "shopping",     "优衣库 T 恤",       bank,   "CNY"),
            (12,   .expense, "transport",    "公交充值",          wechat, "CNY"),
            (68,   .expense, "dining",       "朋友聚餐 AA",       wechat, "CNY"),
            (30,   .expense, "utilities",    "话费充值",          wechat, "CNY"),
            (280,  .expense, "shopping",     "京东 数据线+充电头", bank,   "CNY"),
            (9.9,  .expense, "subscription", "微信读书月卡",       wechat, "CNY"),
            (15,   .expense, "dining",       "咖啡 瑞幸",         wechat, "CNY"),
            (52,   .expense, "groceries",    "菜市场买菜",         cash,   "CNY"),
            (18,   .expense, "transport",    "共享单车月卡",       wechat, "CNY"),
            (120,  .income,  "salary",       "兼职收入",          bank,   "CNY"),
            (500,  .income,  "redPacket",    "朋友红包",          wechat, "CNY"),
        ]

        var lunchTransaction: MoneyTransaction?
        for (index, row) in thisMonth.enumerated() {
            let (amount, kind, catKey, note, account, currency) = row
            let tx = MoneyTransaction(
                amount: amount,
                kind: kind,
                date: thisMonthDate(index), // 支出按 2 天间隔，收入固定留在本月
                note: note,
                currencyCode: currency,
                category: cat(catKey),
                account: account,
                book: book,
                timePrecision: .entryClock,
                reimbursable: note == "朋友聚餐 AA"
            )
            context.insert(tx)
            if index == 0 { lunchTransaction = tx }
        }

        if let lunchTransaction {
            context.insert(MoneyTransaction(
                amount: -15,
                kind: .expense,
                date: lunchTransaction.date,
                note: "部分退款",
                currencyCode: lunchTransaction.currencyCode,
                category: lunchTransaction.category,
                account: lunchTransaction.account,
                book: lunchTransaction.book,
                timePrecision: lunchTransaction.timePrecision,
                // 安卓 fixture 的退款在原账单日期归属统计，但结算时点是
                // 截图时的当天；两条日期不能混用。
                settledAt: daysAgo(0),
                settlementQuality: .userConfirmed,
                settlementAccountID: cash.stableID,
                settlementAccountQuality: .userConfirmed,
                eventType: .refund,
                orderNo: lunchTransaction.orderNo,
                refundOfID: lunchTransaction.stableID
            ))
        }

        context.insert(MoneyTransaction(
            amount: 120,
            kind: .transfer,
            date: daysAgo(10),
            note: "账户转入",
            currencyCode: cash.currencyCode,
            account: cash,
            toAccount: bank,
            book: book,
            timePrecision: .entryClock,
            settledAt: daysAgo(10),
            settlementQuality: .userConfirmed,
            settlementAccountID: cash.stableID,
            settlementAccountQuality: .userConfirmed,
            eventType: .transfer
        ))

        // 上月流水（让月度统计图有对比）
        let lastMonth: [(Decimal, TransactionKind, String, String, Account)] = [
            (42,   .expense, "dining",      "午餐",           wechat),
            (320,  .expense, "housing",     "房租（水电）",    bank),
            (76,   .expense, "groceries",   "超市采购",        wechat),
            (25,   .expense, "transport",   "出租车",          cash),
            (8800, .income,  "salary",      "7 月工资",        bank),
            (560,  .expense, "shopping",    "网购衣物",        bank),
            (35,   .expense, "medical",     "药店",            wechat),
        ]
        for (index, row) in lastMonth.enumerated() {
            let (amount, kind, catKey, note, account) = row
            let tx = MoneyTransaction(
                amount: amount,
                kind: kind,
                date: monthsAgo(1, day: index + 3),
                note: note,
                currencyCode: "CNY",
                category: cat(catKey),
                account: account,
                book: book,
                timePrecision: .entryClock
            )
            context.insert(tx)
        }

        // 再往前两个月（让年度报告柱状图有更多月份数据）
        let twoMonthsAgo: [(Decimal, TransactionKind, String, String)] = [
            (8800, .income,  "salary",   "6 月工资"),
            (380,  .expense, "travel",   "周末游"),
            (95,   .expense, "dining",   "朋友生日聚餐"),
            (290,  .expense, "education","极客时间年卡"),
            (18,   .expense, "transport","高铁票"),
        ]
        for (index, row) in twoMonthsAgo.enumerated() {
            let (amount, kind, catKey, note) = row
            let tx = MoneyTransaction(
                amount: amount,
                kind: kind,
                date: monthsAgo(2, day: index + 5),
                note: note,
                currencyCode: "CNY",
                category: cat(catKey),
                account: bank,
                book: book,
                timePrecision: .entryClock
            )
            context.insert(tx)
        }
    }

    // MARK: - 存钱目标与定时记账

    private static func insertSavingsGoals(context: ModelContext) {
        context.insert(SavingsGoal(
            name: "东京旅行",
            emoji: "✈️",
            targetAmount: 12000,
            savedAmount: 6800,
            note: "今年秋天出发"
        ))
    }

    private static func insertRecurringRules(
        context: ModelContext,
        categories: [String: TxCategory],
        accounts: [Account],
        book: Book
    ) {
        let bank = accounts.first { $0.kind == .bankCard } ?? accounts[0]
        let calendar = Calendar.current
        var dueComponents = calendar.dateComponents([.year, .month], from: AppClock.now)
        dueComponents.month = (dueComponents.month ?? 1) + 1
        dueComponents.day = 30
        dueComponents.hour = 12
        let startDate = calendar.date(from: dueComponents) ?? AppClock.now

        context.insert(RecurringRule(
            amount: 3200,
            kind: .expense,
            bookID: book.stableID,
            categoryKey: categories["housing"]?.key,
            accountID: bank.stableID,
            note: "房租",
            period: .monthly,
            startDate: startDate,
            firstDueDate: startDate,
            endDate: nil,
            totalCount: nil
        ))
    }

    private static func insertAssetData(
        context: ModelContext,
        accounts: [Account],
        book: Book
    ) {
        let now = AppClock.now
        let phone = PhysicalAsset(
            name: "iPhone Air",
            kind: .digital,
            purchasePrice: 6999,
            currentValue: 5800,
            currencyCode: "CNY",
            bookID: book.stableID
        )
        phone.brand = "Apple"
        phone.model = "iPhone Air"
        phone.location = "随身"
        phone.purchaseDate = Calendar.current.date(byAdding: .month, value: -3, to: now)
        phone.warrantyUntil = Calendar.current.date(byAdding: .year, value: 1, to: now)
        phone.usageTrackingEnabled = true
        phone.usageCount = 86
        phone.note = "演示物品资产"
        context.insert(phone)
        context.insert(AssetEvent(
            assetID: phone.stableID,
            kind: .created,
            occurredAt: phone.purchaseDate ?? now,
            value: phone.currentValue,
            note: "从购买记录建立"
        ))
        context.insert(AssetValuation(
            assetID: phone.stableID,
            value: phone.currentValue,
            sourceRaw: "purchase",
            valuedAt: phone.purchaseDate ?? now,
            note: "初始当前价值"
        ))

        let receivable = ReceivableAsset(
            name: "借给小林",
            originalAmount: 1500,
            kind: .loanOut,
            bookID: book.stableID
        )
        receivable.remainingAmount = 800
        receivable.lifecycle = .partiallyRecovered
        receivable.counterparty = "小林"
        receivable.dueDate = Calendar.current.date(byAdding: .day, value: 18, to: now)
        receivable.note = "分两次收回"
        context.insert(receivable)
        context.insert(ReceivableRecovery(
            receivableID: receivable.stableID,
            amount: 700,
            recoveredAt: Calendar.current.date(byAdding: .day, value: -4, to: now) ?? now,
            note: "第一次收回"
        ))

        let credit = accounts.first { $0.kind == .creditCard }
        if let credit {
            credit.initialBalance = -1800
            credit.balanceMode = .ledger
            let profile = LiabilityProfile(
                accountID: credit.stableID,
                kind: .creditCard,
                originalPrincipal: 3000,
                currentPrincipal: 1800,
                currencyCode: "CNY"
            )
            profile.statementDay = 5
            profile.paymentDay = 20
            profile.creditLimit = 12000
            profile.note = "演示信用卡"
            context.insert(profile)
        }
    }

    private static func insertLendingData(
        context: ModelContext,
        accounts: [Account],
        book: Book
    ) {
        guard let cash = accounts.first(where: { $0.kind == .cash }) else { return }
        let calendar = Calendar.current
        let now = AppClock.now
        let borrowDate = calendar.date(byAdding: .day, value: -12, to: now) ?? now
        let recoveryDate = calendar.date(byAdding: .day, value: -5, to: now) ?? now

        let loanAccount = Account(
            name: "借入·小林",
            kind: .loan,
            currencyCode: "CNY",
            sortOrder: accounts.count + 1
        )
        loanAccount.balanceMode = .ledger
        context.insert(loanAccount)

        context.insert(MoneyTransaction(
            amount: 320,
            kind: .transfer,
            date: borrowDate,
            note: "借入：小林",
            currencyCode: "CNY",
            account: loanAccount,
            toAccount: cash,
            book: book,
            timePrecision: .dateOnly,
            settledAt: borrowDate,
            settlementQuality: .userConfirmed,
            settlementAccountID: loanAccount.stableID,
            settlementAccountQuality: .userConfirmed,
            eventType: .transfer
        ))

        let profile = LiabilityProfile(
            accountID: loanAccount.stableID,
            kind: .personalBorrow,
            originalPrincipal: 320,
            currentPrincipal: 320,
            currencyCode: "CNY"
        )
        profile.counterparty = "小林"
        profile.startDate = borrowDate
        profile.dueDate = calendar.date(byAdding: .day, value: 24, to: now)
        profile.repaymentAccountID = cash.stableID
        profile.note = "Parity 借入演示"
        context.insert(profile)

        let receivable = ReceivableAsset(
            name: "借给小林",
            originalAmount: 800,
            kind: .loanOut,
            bookID: book.stableID,
            currencyCode: "CNY"
        )
        receivable.counterparty = "小林"
        receivable.remainingAmount = 500
        receivable.lifecycle = .partiallyRecovered
        receivable.dueDate = calendar.date(byAdding: .day, value: 15, to: now)
        receivable.note = "Parity 借出演示"
        context.insert(receivable)
        context.insert(AssetEvent(
            assetID: receivable.stableID,
            kind: .receivableCreated,
            occurredAt: borrowDate,
            value: receivable.originalAmount,
            note: receivable.note
        ))

        let recoveryTransaction = MoneyTransaction(
            amount: 300,
            kind: .income,
            date: recoveryDate,
            note: "收回：小林",
            currencyCode: "CNY",
            account: cash,
            book: book,
            timePrecision: .dateOnly,
            settledAt: recoveryDate,
            settlementQuality: .userConfirmed,
            settlementAccountID: cash.stableID,
            settlementAccountQuality: .userConfirmed,
            eventType: .receivableRecovery,
            isExcluded: true
        )
        context.insert(recoveryTransaction)
        let recovery = ReceivableRecovery(
            receivableID: receivable.stableID,
            amount: 300,
            recoveredAt: recoveryDate,
            targetAccountID: cash.stableID,
            transactionID: recoveryTransaction.stableID,
            note: "第一次收回"
        )
        let recoveryEvent = AssetEvent(
            assetID: receivable.stableID,
            kind: .receivableRecovered,
            occurredAt: recoveryDate,
            value: 300,
            note: "第一次收回"
        )
        recovery.eventID = recoveryEvent.stableID
        context.insert(recovery)
        context.insert(recoveryEvent)
    }

    private static func insertReports(context: ModelContext, book: Book) {
        let now = AppClock.now
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: now)
        guard let start = calendar.date(from: DateComponents(
            year: components.year,
            month: components.month,
            day: 1
        )),
        let nextStart = calendar.date(byAdding: .month, value: 1, to: start),
        let end = calendar.date(byAdding: .second, value: -1, to: nextStart) else { return }
        let report = ReportRecord(
            bookID: book.stableID,
            type: "monthly",
            title: "\(components.year ?? 0)年\(components.month ?? 0)月账单报告",
            summary: "支出 ¥1,017.90 · 收入 ¥620.00",
            markdown: "# \(components.year ?? 0)年\(components.month ?? 0)月账单报告\n\n- 支出：¥1,017.90\n- 收入：¥620.00\n- 结余：¥-397.90\n\n## 支出分类\n\n- 餐饮：¥151.00（4笔）\n- 购物：¥478.00（2笔）\n- 出行：¥53.00（3笔）\n- 食品：¥208.00（2笔）",
            periodStart: start,
            periodEnd: end,
            createdAt: now,
            pinnedAt: nil
        )
        context.insert(report)
    }
}
