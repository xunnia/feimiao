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
        // 写交易流水（覆盖近几个月，让年度图和月度图都有内容）
        insertTransactions(context: context, categories: categories, accounts: accounts)
        // 写月度预算
        context.insert(Budget(amount: 3000))
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
                sortOrder: index
            )
            context.insert(cat)
            map[seed.key] = cat
        }
        return map
    }

    // MARK: - 账户

    private static func insertAccounts(context: ModelContext) -> [Account] {
        let defs: [(String, AccountKind, Decimal)] = [
            ("现金",  .cash,     500),
            ("微信",  .weChat,  2380),
            ("银行卡", .bankCard, 12600),
        ]
        return defs.enumerated().map { index, item in
            let acc = Account(name: item.0, kind: item.1, currencyCode: "CNY", sortOrder: index)
            acc.initialBalance = item.2
            context.insert(acc)
            return acc
        }
    }

    // MARK: - 交易流水

    /// 生成约 28 条真实感流水，分布在近 4 个月（本月占多数）。
    private static func insertTransactions(
        context: ModelContext,
        categories: [String: TxCategory],
        accounts: [Account]
    ) {
        let wechat  = accounts.first { $0.kind == .weChat }   ?? accounts[0]
        let bank    = accounts.first { $0.kind == .bankCard } ?? accounts[0]
        let cash    = accounts.first { $0.kind == .cash }     ?? accounts[0]

        // cat() 简写：取分类，取不到就用「其他」
        func cat(_ key: String) -> TxCategory? {
            categories[key] ?? categories["other"]
        }

        let now = Date()
        // 生成相对 now 的偏移日期
        func daysAgo(_ n: Int) -> Date {
            Calendar.current.date(byAdding: .day, value: -n, to: now) ?? now
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

        for (index, row) in thisMonth.enumerated() {
            let (amount, kind, catKey, note, account, currency) = row
            let tx = MoneyTransaction(
                amount: amount,
                kind: kind,
                date: daysAgo(index * 2),   // 每条间隔 2 天，铺满本月
                note: note,
                currencyCode: currency,
                category: cat(catKey),
                account: account
            )
            context.insert(tx)
        }

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
                account: account
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
                account: bank
            )
            context.insert(tx)
        }
    }
}
