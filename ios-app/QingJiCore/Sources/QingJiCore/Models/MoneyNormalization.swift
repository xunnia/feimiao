import Foundation

/// 财务金额的唯一归一化入口。持久化前统一到最小货币单位（人民币为分），
/// 不用 Double 参与累加。
public enum MoneyNormalization {
    public static func roundToCents(_ amount: Decimal) -> Decimal {
        let behavior = NSDecimalNumberHandler(
            roundingMode: .plain,
            scale: 2,
            raiseOnExactness: false,
            raiseOnOverflow: true,
            raiseOnUnderflow: true,
            raiseOnDivideByZero: true
        )
        return NSDecimalNumber(decimal: amount)
            .rounding(accordingToBehavior: behavior)
            .decimalValue
    }

    public static func cents(_ amount: Decimal) -> Int {
        let rounded = roundToCents(amount)
        return NSDecimalNumber(decimal: rounded * 100).intValue
    }
}
