import SwiftUI
import SwiftData
import WidgetKit
import QingJiCore

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    /// 全局路由：qingji://settings/budget 或 /reconcile 深链会设置 settingsPushTarget，
    /// NavigationStack 读取后 push 对应子页面。
    @Environment(AppRouter.self) private var router

    @State private var settingsMessage: String?
    @AppStorage("qingji.repaymentReminderEnabled") private var repaymentReminderEnabled = true
    @AppStorage("qingji.widgetPrivacyMode") private var widgetPrivacyMode = false

    var body: some View {
        @Bindable var router = router

        NavigationStack {
            List {
                Section("管理") {
                    NavigationLink {
                        AIProviderSettingsView()
                    } label: {
                        Label("AI 记账设置", systemImage: "sparkles")
                    }
                    NavigationLink {
                        BackupView()
                    } label: {
                        Label("备份与恢复", systemImage: "archivebox")
                    }
                } footer: {
                    Text("AI、备份和恢复是设置页的系统级选项；预算、资产和导入等业务入口位于主页抽屉。")
                }

                Section("显示") {
                    NavigationLink {
                        TransactionDisplaySettingsView()
                    } label: {
                        Label("账单与聊天显示", systemImage: "rectangle.3.group")
                    }
                    NavigationLink {
                        ThemeSettingsView()
                    } label: {
                        Label("主题外观", systemImage: "paintbrush")
                    }
                    NavigationLink {
                        MoneyDisplaySettingsView()
                    } label: {
                        Label("金额显示", systemImage: "yensign.circle")
                    }
                }

                Section("提醒") {
                    Toggle("还款提醒", isOn: $repaymentReminderEnabled)
                        .onChange(of: repaymentReminderEnabled) { _, enabled in
                            updateRepaymentReminder(enabled)
                        }
                } footer: {
                    Text("信用卡、贷款和个人借入会在还款日前一天及当天提醒；通知时间由 iOS 系统管理。")
                }

                Section("小组件") {
                    Toggle("隐藏小组件金额", isOn: $widgetPrivacyMode)
                        .onChange(of: widgetPrivacyMode) { _, _ in
                            WidgetCenter.shared.reloadAllTimelines()
                        }
                } footer: {
                    Text("开启后，小组件保留分类和进度，但不显示具体金额。")
                }

                Section("关于") {
                    LabeledContent("版本", value: appVersion)
                    Text("本地优先存储，开启 iCloud 后自动多端同步；无广告、无账号。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .navigationDestination(item: $router.settingsPushTarget) { target in
                settingsDestinationView(target)
            }
            .alert("设置", isPresented: Binding(
                get: { settingsMessage != nil },
                set: { if !$0 { settingsMessage = nil } }
            )) {
                Button("好") { settingsMessage = nil }
            } message: {
                Text(settingsMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func settingsDestinationView(
        _ target: AppRouter.SettingsDestination
    ) -> some View {
        switch target {
        case .ai:        AIProviderSettingsView()
        case .books:     BooksView()
        case .accounts:  AccountsView()
        case .categories: CategoriesView()
        case .tags:      TagsView()
        case .memory:    MemoryView()
        case .aiMemory:  AIMemoryView()
        case .aiTasks:   AITaskCenterView()
        case .aiExtensions: AIExtensionSettingsView()
        case .aiSchedules: AIReportScheduleView()
        case .aiSearch:  AIUnifiedSearchView()
        case .aiDiagnostics: AIDiagnosticsView()
        case .aiLocal: LocalModelCompanionView()
        case .budget:    BudgetSettingView()
        case .reconcile: ReconcileView()
        case .reimburse: ReimburseView()
        case .savings:   SavingsGoalsView()
        case .recurring: RecurringRulesView()
        case .assets:    AssetsView()
        case .assetDetail: AssetsView(opensFirstDetail: true)
        case .liabilities: LiabilitiesView()
        case .netWorth:  NetWorthView()
        case .importReview:
            ImportReviewView(result: ImportReviewView.demoResult()) { _, _ in }
        case .importExport: ImportExportView()
        case .reports:   ReportsView()
        case .backup:    BackupView()
        case .display:   TransactionDisplaySettingsView()
        case .theme:     ThemeSettingsView()
        case .moneyDisplay: MoneyDisplaySettingsView()
        case .autoRecord: AutoRecordView()
        }
    }

    private func updateRepaymentReminder(_ enabled: Bool) {
        Task { @MainActor in
            if enabled {
                guard await RepaymentReminderScheduler.requestAuthorization() else {
                    repaymentReminderEnabled = false
                    settingsMessage = "系统没有允许通知，请到设置中打开通知权限。"
                    return
                }
                await RepaymentReminderScheduler.reschedule(context: context)
            } else {
                await RepaymentReminderScheduler.cancelAll()
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

}

/// 把导入的账单流水落库：按来源匹配账户、按名称匹配分类，匹配不到用「其他」。
enum BillRecordSaver {
    @discardableResult
    static func save(
        _ result: ImportedBillResult,
        account selectedAccount: Account? = nil,
        context: ModelContext
    ) throws -> Int {
        let categories = (try? context.fetch(FetchDescriptor<TxCategory>())) ?? []
        let accounts = ((try? context.fetch(FetchDescriptor<Account>())) ?? [])
            .filter { !$0.isDeleted && $0.status == .active }
        let books = (try? context.fetch(FetchDescriptor<Book>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let existingTransactions = (try? context.fetch(FetchDescriptor<MoneyTransaction>())) ?? []

        let account: Account? = selectedAccount ?? {
            switch result.source {
            case .weChat: return accounts.first { $0.kind == .weChat } ?? accounts.first
            case .alipay: return accounts.first { $0.kind == .alipay } ?? accounts.first
            case .unknown: return accounts.first
            }
        }()
        let book = books.first(where: { $0.includeInTotal }) ?? books.first

        func category(for record: TransactionRecord) -> TxCategory? {
            if !record.categoryKey.isEmpty,
               let keyMatch = categories.first(where: {
                   $0.key == record.categoryKey && $0.kind == record.kind
               }) {
                return keyMatch
            }
            if !record.categoryName.isEmpty,
               let match = categories.first(where: {
                   $0.kind == record.kind &&
                   (record.categoryName.contains($0.name) || $0.name.contains(record.categoryName))
               }) {
                return match
            }
            let fallbackKey = record.kind == .income ? "otherIncome" : CategorySeed.fallbackExpenseKey
            return categories.first { $0.key == fallbackKey }
        }

        var importedByOrder = Dictionary(
            existingTransactions
                .filter { $0.refundOfID == nil && $0.kind == .expense && !$0.orderNo.isEmpty }
                .map { ($0.orderNo, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var candidateTransactions = existingTransactions.filter {
            $0.refundOfID == nil && $0.kind == .expense
        }
        var committed = 0
        var allRecords = existingTransactions.map(\.record)
        var existingFingerprints = Set(existingTransactions.map { fingerprint($0) })

        func isDuplicate(_ record: TransactionRecord) -> Bool {
            existingFingerprints.contains(fingerprint(record))
        }

        // 先落普通交易，建立“商户订单号 -> 原账单”的映射；退款必须在这一步之后
        // 创建，且日期归属原账单，避免跨月导入污染统计。
        for rawRecord in result.records where rawRecord.eventType != .refund && rawRecord.amount > 0 {
            var record = rawRecord
            record.amount = MoneyNormalization.roundToCents(record.amount)
            guard record.amount > 0 else { continue }
            if isDuplicate(record) {
                if record.kind == .expense, !record.orderNo.isEmpty,
                   let existing = existingTransactions.first(where: {
                       $0.refundOfID == nil && $0.kind == .expense && $0.orderNo == record.orderNo
                   }) {
                    importedByOrder[record.orderNo] = existing
                }
                continue
            }
            let transaction = MoneyTransaction(
                amount: record.amount,
                kind: record.kind,
                date: record.date,
                note: record.note,
                merchantName: record.merchant,
                productName: record.product,
                currencyCode: record.currencyCode,
                category: category(for: record),
                account: account,
                book: book,
                stableID: record.id,
                timePrecision: record.timePrecision,
                settledAt: record.settledAt ?? record.date,
                settlementQuality: account == nil ? .unknown : .userConfirmed,
                settlementAccountID: account?.stableID,
                settlementAccountQuality: account == nil ? .unknown : .userConfirmed,
                eventType: record.eventType,
                attachmentPath: record.attachmentPath,
                orderNo: record.orderNo,
                reimbursable: record.reimbursable,
                refundOfID: record.refundOfID,
                isReimbursed: record.isReimbursed,
                isExcluded: record.isExcluded,
                tagNames: record.tags.joined(separator: ",")
            )
            context.insert(transaction)
            if transaction.kind == .expense && !record.orderNo.isEmpty {
                importedByOrder[record.orderNo] = transaction
            }
            if transaction.kind == .expense { candidateTransactions.append(transaction) }
            allRecords.append(transaction.record)
            existingFingerprints.insert(fingerprint(transaction.record))
            committed += 1
        }

        func matchKey(_ value: String) -> String {
            BillCategorizer.normalizeMerchant(value)
                .lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .joined()
        }

        func findOriginal(for refund: TransactionRecord) -> MoneyTransaction? {
            if !refund.orderNo.isEmpty, let exact = importedByOrder[refund.orderNo] {
                return exact
            }

            let refundMerchant = matchKey(refund.merchant)
            let refundText = matchKey("\(refund.product) \(refund.note)")
            var bestScore = -1
            var bestCount = 0
            var best: MoneyTransaction?
            for candidate in candidateTransactions {
                let status = LedgerPolicy.refundStatus(for: candidate.record, in: allRecords)
                guard status.remainingAmount > 0 else { continue }
                let candidateMerchant = matchKey(candidate.merchantName)
                let candidateText = matchKey("\(candidate.productName) \(candidate.note)")
                var score = 0
                if !refundMerchant.isEmpty && refundMerchant == candidateMerchant { score += 8 }
                if !refundText.isEmpty && !candidateText.isEmpty &&
                   (refundText.contains(candidateText) || candidateText.contains(refundText)) {
                    score += 3
                }
                let days = abs(refund.date.timeIntervalSince(candidate.date)) / 86_400
                if days <= 1 { score += 3 }
                else if days <= 45 { score += 1 }
                if -refund.amount <= status.remainingAmount { score += 2 }
                if score > bestScore {
                    bestScore = score
                    bestCount = 1
                    best = candidate
                } else if score == bestScore {
                    bestCount += 1
                }
            }
            guard bestCount == 1 else { return nil }
            return bestScore >= 8 || bestScore >= 5 ? best : nil
        }

        for rawRecord in result.records where rawRecord.eventType == .refund && rawRecord.amount < 0 {
            var record = rawRecord
            record.amount = MoneyNormalization.roundToCents(record.amount)
            guard record.amount < 0 else { continue }
            let original = findOriginal(for: record)
            guard let original else {
                // 退款没有可靠原单时不能静默丢失：按真实退款收入落库，
                // 让用户仍能在账单中看到并手动修正，而不是凭空少一笔钱。
                var fallback = record
                fallback.kind = .income
                fallback.amount = -record.amount
                fallback.categoryKey = "refund"
                fallback.categoryName = "退款报销"
                fallback.topCategoryKey = "refund"
                fallback.topCategoryName = "退款报销"
                fallback.eventType = .income
                if !isDuplicate(fallback) {
                    let transaction = MoneyTransaction(
                        amount: fallback.amount,
                        kind: .income,
                        date: fallback.date,
                        note: fallback.note.isEmpty ? "退款" : fallback.note,
                        merchantName: fallback.merchant,
                        productName: fallback.product,
                        currencyCode: fallback.currencyCode,
                        category: category(for: fallback),
                        account: account,
                        book: book,
                        stableID: fallback.id,
                        timePrecision: fallback.timePrecision,
                        settledAt: fallback.settledAt ?? fallback.date,
                        settlementQuality: account == nil ? .unknown : .exact,
                        settlementAccountID: account?.stableID,
                        settlementAccountQuality: account == nil ? .unknown : .exact,
                        eventType: .income,
                        orderNo: fallback.orderNo,
                        isExcluded: fallback.isExcluded,
                        tagNames: fallback.tags.joined(separator: ",")
                    )
                    context.insert(transaction)
                    allRecords.append(transaction.record)
                    existingFingerprints.insert(fingerprint(transaction.record))
                    committed += 1
                }
                continue
            }

            let status = LedgerPolicy.refundStatus(for: original.record, in: allRecords)
            let requested = -record.amount
            guard requested > 0, requested <= status.remainingAmount else { continue }
            let duplicate = allRecords.contains {
                $0.refundOfID == original.stableID &&
                $0.amount == record.amount &&
                $0.eventType == .refund
            }
            if duplicate { continue }

            let refund = MoneyTransaction(
                amount: -requested,
                kind: .expense,
                date: original.date,
                note: record.note.isEmpty ? "退款" : record.note,
                merchantName: record.merchant,
                productName: record.product,
                currencyCode: original.currencyCode,
                category: original.category,
                account: original.account,
                book: original.book,
                stableID: record.id,
                timePrecision: original.timePrecision,
                settledAt: record.settledAt ?? record.date,
                settlementQuality: account == nil ? .unknown : .exact,
                settlementAccountID: account?.stableID,
                settlementAccountQuality: account == nil ? .unknown : .exact,
                eventType: .refund,
                orderNo: record.orderNo,
                refundOfID: original.stableID
            )
            context.insert(refund)
            allRecords.append(refund.record)
            committed += 1
        }
        try context.save()
        return committed
    }

    private static func fingerprint(_ transaction: MoneyTransaction) -> String {
        fingerprint(transaction.record)
    }

    private static func fingerprint(_ record: TransactionRecord) -> String {
        let date = String(Int(record.date.timeIntervalSince1970))
        return [
            record.kind.rawValue,
            record.amount.description,
            date,
            record.orderNo,
            record.note
        ].joined(separator: "|")
    }
}
