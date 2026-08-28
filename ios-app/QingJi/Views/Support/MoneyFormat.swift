import Foundation
import QingJiCore

enum MoneyFormat {
    /// "¥1,234.50" 风格的金额文本。小数位和整数取整方式跟随安卓端的
    /// “金额显示”设置，只影响展示，不改变账务层保存的 Decimal 精度。
    static func string(_ amount: Decimal, currencyCode: String) -> String {
        let defaults = UserDefaults.standard
        let places = defaults.object(forKey: "qingji.moneyDecimalPlaces") as? Int ?? 2
        let roundingRaw = defaults.string(forKey: "qingji.moneyRoundingMode") ?? "round"
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = currencyCode.uppercased() == "CNY"
            ? Locale(identifier: "zh_CN")
            : Locale.current
        formatter.minimumFractionDigits = max(0, min(2, places))
        formatter.maximumFractionDigits = max(0, min(2, places))
        formatter.roundingMode = switch roundingRaw {
        case "ceil": .ceiling
        case "floor": .floor
        case "truncate": .down
        default: .halfUp
        }
        return formatter.string(from: NSDecimalNumber(decimal: amount))
            ?? amount.formatted(.currency(code: currencyCode).presentation(.narrow))
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
