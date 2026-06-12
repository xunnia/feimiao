import Foundation
import SwiftData
import QingJiCore

/// 首次启动写入预置分类与默认账户。
enum DataSeeder {
    static func seedIfNeeded(context: ModelContext) {
        let categoryCount = (try? context.fetchCount(FetchDescriptor<TxCategory>())) ?? 0
        guard categoryCount == 0 else { return }

        let language = Locale.current.language.languageCode?.identifier ?? "zh"

        for (index, seed) in CategorySeed.all.enumerated() {
            context.insert(TxCategory(
                key: seed.key,
                name: seed.localizedName(languageCode: language),
                symbol: seed.symbol,
                kind: seed.kind,
                sortOrder: index
            ))
        }

        let isChinese = language.hasPrefix("zh")
        let defaultAccounts: [(String, AccountKind)] = [
            (isChinese ? "现金" : "Cash", .cash),
            (isChinese ? "微信" : "WeChat Pay", .weChat),
            (isChinese ? "支付宝" : "Alipay", .alipay),
            (isChinese ? "银行卡" : "Bank Card", .bankCard),
        ]
        let currency = Locale.current.currency?.identifier ?? "CNY"
        for (index, item) in defaultAccounts.enumerated() {
            context.insert(Account(name: item.0, kind: item.1, currencyCode: currency, sortOrder: index))
        }

        try? context.save()
    }
}
