import Foundation
import SwiftData
import QingJiCore

/// 首次启动写入预置分类与默认账户。
enum DataSeeder {
    static func seedIfNeeded(context: ModelContext) {
        let language = Locale.current.language.languageCode?.identifier ?? "zh"

        // 幂等升级：旧版 iOS 只有一级分类，更新后补齐安卓同款两级树；
        // 历史交易只依赖 stable key，不会因名称或父级变化而丢失。
        let existingCategories = (try? context.fetch(FetchDescriptor<TxCategory>())) ?? []
        var byKey = Dictionary(uniqueKeysWithValues: existingCategories.map { ($0.key, $0) })
        for (index, seed) in CategorySeed.all.enumerated() {
            let category = byKey[seed.key] ?? TxCategory(
                key: seed.key,
                name: seed.localizedName(languageCode: language),
                symbol: seed.symbol,
                kind: seed.kind,
                sortOrder: index,
                emoji: seed.emoji,
                parentKey: seed.parentKey
            )
            if byKey[seed.key] == nil { context.insert(category) }
            category.name = seed.localizedName(languageCode: language)
            category.symbol = seed.symbol
            category.emoji = seed.emoji
            category.kind = seed.kind
            category.parentKey = seed.parentKey
            category.sortOrder = index
            byKey[seed.key] = category
        }

        let isChinese = language.hasPrefix("zh")
        let defaultAccounts: [(String, AccountKind)] = [
            (isChinese ? "现金" : "Cash", .cash),
            (isChinese ? "微信" : "WeChat Pay", .weChat),
            (isChinese ? "支付宝" : "Alipay", .alipay),
            (isChinese ? "银行卡" : "Bank Card", .bankCard),
        ]
        let accountCount = (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0
        // 肥喵当前账务主口径是人民币；设备地区不应默默改变新账户币种。
        let currency = "CNY"
        if accountCount == 0 {
            for (index, item) in defaultAccounts.enumerated() {
                context.insert(Account(name: item.0, kind: item.1, currencyCode: currency, sortOrder: index))
            }
        }

        var books = (try? context.fetch(FetchDescriptor<Book>(sortBy: [SortDescriptor(\Book.sortOrder)]))) ?? []
        if books.isEmpty {
            let book = Book(name: isChinese ? "总账本" : "All records", includeInTotal: true, isDefault: true)
            context.insert(book)
            books = [book]
        }

        // 旧版原型没有账本字段，升级后把这些历史流水归入总账本，避免它们
        // 在账本管理页看不见、导出时也无法还原归属。
        if let defaultBook = books.first(where: { $0.isDefault }) ?? books.first {
            if !defaultBook.isDefault { defaultBook.isDefault = true }
            let legacyTransactions = (try? context.fetch(FetchDescriptor<MoneyTransaction>())) ?? []
            for transaction in legacyTransactions where transaction.book == nil {
                transaction.book = defaultBook
            }
        }

        try? context.save()
    }
}
