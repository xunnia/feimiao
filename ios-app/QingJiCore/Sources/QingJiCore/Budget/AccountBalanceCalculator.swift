import Foundation

/// 账户账面余额计算：期初余额 + 收入 − 支出 + 转入 − 转出。
/// 「每周对账」用它和实际余额对比，差额一键补记。
public enum AccountBalanceCalculator {
    public static func balance(
        accountName: String,
        initialBalance: Decimal,
        records: [TransactionRecord]
    ) -> Decimal {
        var balance = initialBalance
        for record in records {
            switch record.kind {
            case .expense where record.accountName == accountName:
                balance -= record.amount
            case .income where record.accountName == accountName:
                balance += record.amount
            case .transfer:
                if record.accountName == accountName { balance -= record.amount }
                if record.toAccountName == accountName { balance += record.amount }
            default:
                break
            }
        }
        return balance
    }
}
