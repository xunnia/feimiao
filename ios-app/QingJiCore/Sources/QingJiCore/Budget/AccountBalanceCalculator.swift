import Foundation

/// 账户账面余额计算：期初余额 + 收入 − 支出 + 转入 − 转出。
/// [balanceAdjustment] 是可审计的余额校准差额；它不是一笔普通收支。
public enum AccountBalanceCalculator {
    public static func balance(
        accountName: String,
        initialBalance: Decimal,
        records: [TransactionRecord],
        accountID: UUID? = nil,
        balanceAdjustment: Decimal = 0
    ) -> Decimal {
        var balance = initialBalance
        for record in records {
            if record.isExcluded { continue }

            // 新写入事件按结算账户投影；旧版只有 kind/account 时走兼容分支。
            let fallbackSource = matches(
                id: record.accountID,
                name: record.accountName,
                accountID: accountID,
                accountName: accountName
            )
            let target = matches(
                id: record.toAccountID,
                name: record.toAccountName,
                accountID: accountID,
                accountName: accountName
            )
            let settlement = matches(
                id: record.settlementAccountID ?? record.accountID,
                name: record.accountName,
                accountID: accountID,
                accountName: accountName
            )
            let amount = record.amount < 0 ? -record.amount : record.amount

            switch record.eventType {
            case .expense, .assetPurchase, .principalPayment, .interest:
                if settlement { balance -= amount }
            case .income, .refund, .reimbursement, .assetSale, .receivableRecovery:
                if settlement { balance += amount }
            case .transfer:
                if settlement { balance -= amount }
                if target { balance += amount }
            case .legacyAdjustment:
                switch record.kind {
                case .expense where fallbackSource:
                    balance -= record.amount
                case .income where fallbackSource:
                    balance += record.amount
                case .transfer:
                    if fallbackSource { balance -= amount }
                    if target { balance += amount }
                default:
                    break
                }
            }
        }
        return balance + balanceAdjustment
    }

    private static func matches(
        id: UUID?,
        name: String,
        accountID: UUID?,
        accountName: String
    ) -> Bool {
        if let accountID {
            return id == accountID || (id == nil && name == accountName)
        }
        return name == accountName
    }
}
