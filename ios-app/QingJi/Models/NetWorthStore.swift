import Foundation
import SwiftData
import QingJiCore

/// 净资产计算的单一入口。资金余额、物品当前价值、权益剩余金额和负债本金
/// 使用与 Android 相同的组件拆分，且只把人民币纳入当前总额。
enum NetWorthStore {
    struct Breakdown: Equatable {
        let totalAssets: Decimal
        let totalLiabilities: Decimal
        let netWorth: Decimal
        let cashAssets: Decimal
        let investmentAssets: Decimal
        let physicalAssets: Decimal
        let receivableAssets: Decimal
        let unsupportedCurrencies: Set<String>
    }

    static func breakdown(
        accounts: [Account],
        transactions: [MoneyTransaction],
        physicalAssets: [PhysicalAsset],
        receivables: [ReceivableAsset],
        liabilities: [LiabilityProfile],
        checkpoints: [AccountBalanceCheckpointRecord] = []
    ) -> Breakdown {
        var cash = Decimal.zero
        var investment = Decimal.zero
        var accountBalances: [UUID: Decimal] = [:]
        var unsupported = Set<String>()

        for account in accounts where !account.isDeleted && account.status == .active {
            let currency = account.currencyCode.uppercased()
            guard account.includeInNetWorth else { continue }
            guard currency == "CNY" else {
                unsupported.insert(currency)
                continue
            }
            let balance = LedgerStore.accountBalance(
                for: account,
                transactions: transactions,
                checkpoints: checkpoints
            )
            accountBalances[account.stableID] = balance
            if balance >= 0 {
                if account.kind == .investment {
                    investment += balance
                } else {
                    cash += balance
                }
            }
        }

        var totalLiabilities = Decimal.zero
        // 负余额本身就是负债；档案本金只在 legacyHybrid 下追加，避免重复计算。
        for account in accounts where !account.isDeleted && account.status == .active {
            guard account.includeInNetWorth, account.currencyCode.uppercased() == "CNY" else { continue }
            let balance = accountBalances[account.stableID] ?? 0
            if balance < 0 { totalLiabilities -= balance }
        }
        for profile in liabilities where profile.lifecycle == .active && profile.currentPrincipal > 0 {
            guard let accountID = profile.accountID,
                  let account = accounts.first(where: { $0.stableID == accountID }),
                  !account.isDeleted,
                  account.includeInNetWorth,
                  account.currencyCode.uppercased() == "CNY" else { continue }
            if account.balanceMode != .ledger {
                let accountBalance = accountBalances[account.stableID] ?? 0
                if accountBalance >= 0 { totalLiabilities += profile.currentPrincipal }
            }
        }

        let physical = physicalAssets.reduce(into: Decimal.zero) { total, asset in
            guard !asset.isDeleted,
                  asset.includeInNetWorth,
                  (asset.lifecycle == .owned || asset.lifecycle == .idle) else { return }
            if asset.currencyCode.uppercased() == "CNY" {
                total += asset.currentValue
            } else {
                unsupported.insert(asset.currencyCode.uppercased())
            }
        }
        let receivable = receivables.reduce(into: Decimal.zero) { total, asset in
            guard !asset.isDeleted,
                  asset.includeInNetWorth,
                  (asset.lifecycle == .active || asset.lifecycle == .partiallyRecovered) else { return }
            if asset.currencyCode.uppercased() == "CNY" {
                total += asset.remainingAmount
            } else {
                unsupported.insert(asset.currencyCode.uppercased())
            }
        }
        let totalAssets = cash + investment + physical + receivable
        return Breakdown(
            totalAssets: totalAssets,
            totalLiabilities: totalLiabilities,
            netWorth: totalAssets - totalLiabilities,
            cashAssets: cash,
            investmentAssets: investment,
            physicalAssets: physical,
            receivableAssets: receivable,
            unsupportedCurrencies: unsupported
        )
    }

    static func current(in context: ModelContext) throws -> Breakdown {
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let transactions = try context.fetch(FetchDescriptor<MoneyTransaction>())
        let assets = try context.fetch(FetchDescriptor<PhysicalAsset>())
        let receivables = try context.fetch(FetchDescriptor<ReceivableAsset>())
        let liabilities = try context.fetch(FetchDescriptor<LiabilityProfile>())
        let checkpoints = try context.fetch(FetchDescriptor<AccountBalanceCheckpointRecord>())
        return breakdown(
            accounts: accounts,
            transactions: transactions,
            physicalAssets: assets,
            receivables: receivables,
            liabilities: liabilities,
            checkpoints: checkpoints
        )
    }

    @discardableResult
    static func saveSnapshot(in context: ModelContext, asOf: Date = Date()) throws -> NetWorthSnapshot {
        let value = try current(in: context)
        let snapshot = NetWorthSnapshot(asOf: asOf)
        snapshot.cashAssets = value.cashAssets
        snapshot.investmentAssets = value.investmentAssets
        snapshot.physicalAssets = value.physicalAssets
        snapshot.receivableAssets = value.receivableAssets
        snapshot.liabilities = value.totalLiabilities
        snapshot.quality = value.unsupportedCurrencies.isEmpty ? .available : .partial
        snapshot.coveredCurrenciesJSON = "[\"CNY\"]"
        snapshot.uncoveredCurrenciesJSON = jsonArray(value.unsupportedCurrencies.sorted())
        snapshot.reasonsJSON = value.unsupportedCurrencies.isEmpty ? "[]" : "[\"存在未换算外币\"]"
        context.insert(snapshot)
        try context.save()
        return snapshot
    }

    private static func jsonArray(_ values: [String]) -> String {
        let quoted = values.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }
        return "[\(quoted.joined(separator: ","))]"
    }
}
