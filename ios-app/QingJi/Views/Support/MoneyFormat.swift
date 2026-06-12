import Foundation
import QingJiCore

enum MoneyFormat {
    /// "¥1,234.50" 风格的金额文本。
    static func string(_ amount: Decimal, currencyCode: String) -> String {
        amount.formatted(.currency(code: currencyCode).presentation(.narrow))
    }

    /// 货币符号，如 CNY -> "¥"。
    static func symbol(of currencyCode: String) -> String {
        Locale.current.localizedCurrencySymbol(forCurrencyCode: currencyCode) ?? currencyCode
    }

    static func double(_ amount: Decimal) -> Double {
        NSDecimalNumber(decimal: amount).doubleValue
    }
}

private extension Locale {
    func localizedCurrencySymbol(forCurrencyCode code: String) -> String? {
        let canonical = Locale(identifier: Locale.identifier(fromComponents: [
            NSLocale.Key.currencyCode.rawValue: code,
            NSLocale.Key.languageCode.rawValue: language.languageCode?.identifier ?? "zh",
        ]))
        return canonical.currencySymbol
    }
}
