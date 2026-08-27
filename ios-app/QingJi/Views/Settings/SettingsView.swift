import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import WidgetKit
import QingJiCore

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    /// 全局路由：qingji://settings/budget 或 /reconcile 深链会设置 settingsPushTarget，
    /// NavigationStack 读取后 push 对应子页面。
    @Environment(AppRouter.self) private var router

    @Query(sort: \MoneyTransaction.date, order: .reverse)
    private var transactions: [MoneyTransaction]

    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportDocument = CSVDocument()
    @State private var importMessage: String?
    @State private var pendingImport: ImportedBillResult?
    @State private var showImportReview = false
    @AppStorage("qingji.repaymentReminderEnabled") private var repaymentReminderEnabled = true
    @AppStorage("qingji.widgetPrivacyMode") private var widgetPrivacyMode = false

    var body: some View {
        NavigationStack {
            List {
                Section("管理") {
                    NavigationLink {
                        AIProviderSettingsView()
                    } label: {
                        Label("AI 与喵助手", systemImage: "sparkles")
                    }
                    NavigationLink {
                        AIChatsView()
                    } label: {
                        Label("Chats", systemImage: "bubble.left.and.bubble.right")
                    }
                    NavigationLink {
                        BooksView()
                    } label: {
                        Label("账本管理", systemImage: "book.closed")
                    }
                    NavigationLink {
                        AccountsView()
                    } label: {
                        Label("账户管理", systemImage: "creditcard")
                    }
                    NavigationLink {
                        CategoriesView()
                    } label: {
                        Label("分类管理", systemImage: "square.grid.2x2")
                    }
                    NavigationLink {
                        TagsView()
                    } label: {
                        Label("标签管理", systemImage: "tag")
                    }
                    NavigationLink {
                        MemoryView()
                    } label: {
                        Label("喵学到的分类", systemImage: "brain.head.profile")
                    }
                    NavigationLink {
                        AIMemoryView()
                    } label: {
                        Label("可控记忆", systemImage: "lock.shield")
                    }
                    NavigationLink {
                        AITaskCenterView()
                    } label: {
                        Label("AI 任务中心", systemImage: "waveform")
                    }
                    NavigationLink {
                        AIExtensionSettingsView()
                    } label: {
                        Label("技能与连接", systemImage: "link")
                    }
                    NavigationLink {
                        AIReportScheduleView()
                    } label: {
                        Label("定时报表", systemImage: "calendar.badge.clock")
                    }
                    NavigationLink {
                        AIUnifiedSearchView()
                    } label: {
                        Label("AI 统一搜索", systemImage: "magnifyingglass")
                    }
                    NavigationLink {
                        AIDiagnosticsView()
                    } label: {
                        Label("AI 诊断", systemImage: "waveform.path.ecg")
                    }
                    NavigationLink {
                        LocalModelCompanionView()
                    } label: {
                        Label("本地模型伴侣", systemImage: "desktopcomputer")
                    }
                    NavigationLink {
                        BudgetSettingView()
                    } label: {
                        Label("月度预算", systemImage: "gauge.with.needle")
                    }
                    NavigationLink {
                        SavingsGoalsView()
                    } label: {
                        Label("存钱目标", systemImage: "target")
                    }
                    NavigationLink {
                        RecurringRulesView()
                    } label: {
                        Label("定时记账", systemImage: "clock.badge")
                    }
                    NavigationLink {
                        AssetsView()
                    } label: {
                        Label("资产管理", systemImage: "shippingbox")
                    }
                    NavigationLink {
                        LiabilitiesView()
                    } label: {
                        Label("负债管理", systemImage: "minus.circle")
                    }
                    NavigationLink {
                        NetWorthView()
                    } label: {
                        Label("净资产", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    NavigationLink {
                        ReportsView()
                    } label: {
                        Label("报告", systemImage: "doc.text.magnifyingglass")
                    }
                    NavigationLink {
                        ReconcileView()
                    } label: {
                        Label("对账", systemImage: "checkmark.seal")
                    }
                    NavigationLink {
                        ReimburseView()
                    } label: {
                        Label("待报销", systemImage: "arrow.uturn.backward.circle")
                    }
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
                }

                Section {
                    Button {
                        showImporter = true
                    } label: {
                        Label("导入微信 / 支付宝账单", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        let visible = LedgerPolicy.userRecords(from: transactions.map(\.record))
                        exportDocument = CSVDocument(text: CSVExporter.export(visible))
                        showExporter = true
                    } label: {
                        Label("导出全部账目为 CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(transactions.isEmpty)
                } header: {
                    Text("数据")
                } footer: {
                    Text("在微信「我-服务-钱包-账单」或支付宝「我的-账单」申请导出 CSV 账单后，从文件 App 导入。数据只保存在你的设备和 iCloud。")
                }

                Section {
                    NavigationLink {
                        BackupView()
                    } label: {
                        Label("备份与恢复", systemImage: "archivebox")
                    }
                } footer: {
                    Text("完整备份会保留账本、资产和附件；密钥类凭据不会导出。")
                }

                Section("提醒") {
                    Toggle("还款提醒", isOn: $repaymentReminderEnabled)
                        .onChange(of: repaymentReminderEnabled) { _, enabled in
                            Task { @MainActor in
                                if enabled {
                                    guard await RepaymentReminderScheduler.requestAuthorization() else {
                                        repaymentReminderEnabled = false
                                        importMessage = "系统没有允许通知，请到设置中打开通知权限。"
                                        return
                                    }
                                    await RepaymentReminderScheduler.reschedule(context: context)
                                } else {
                                    await RepaymentReminderScheduler.cancelAll()
                                }
                            }
                        }
                } footer: {
                    Text("信用卡、贷款和个人借入会在还款日前一天及当天提醒；通知时间由 iOS 系统管理。")
                }

                Section {
                    Toggle("隐藏小组件金额", isOn: $widgetPrivacyMode)
                        .onChange(of: widgetPrivacyMode) { _, _ in
                            WidgetCenter.shared.reloadAllTimelines()
                        }
                } header: {
                    Text("小组件")
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
            // 深链路由：qingji://settings/budget 或 /reconcile 时 push 对应子页面
            .navigationDestination(isPresented: Binding(
                get: { router.settingsPushTarget != nil },
                set: { if !$0 { router.settingsPushTarget = nil } }
            )) {
                switch router.settingsPushTarget {
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
                case .liabilities: LiabilitiesView()
                case .netWorth:  NetWorthView()
                case .importReview:
                    ImportReviewView(result: ImportReviewView.demoResult()) { _, _ in }
                case .reports:   ReportsView()
                case .backup:    BackupView()
                case .display:   TransactionDisplaySettingsView()
                case .theme:     ThemeSettingsView()
                case nil:        EmptyView()
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [
                    .commaSeparatedText,
                    .plainText,
                    UTType(filenameExtension: "xlsx") ?? .data,
                    .data
                ]
            ) { result in
                handleImport(result)
            }
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: .commaSeparatedText,
                defaultFilename: "qingji-export"
            ) { _ in }
            .sheet(isPresented: $showImportReview) {
                if let pendingImport {
                    ImportReviewView(result: pendingImport) { count, skipped in
                        importMessage = "成功导入 \(count) 笔，跳过 \(skipped) 行中性或无效交易。"
                        self.pendingImport = nil
                    }
                }
            }
            .alert(
                "导入结果",
                isPresented: Binding(
                    get: { importMessage != nil },
                    set: { isPresented in
                        if !isPresented { importMessage = nil }
                    }
                )
            ) {
                Button("好") { importMessage = nil }
            } message: {
                Text(importMessage ?? "")
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else {
                importMessage = String(localized: "无法读取所选文件")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: url)
            let imported: ImportedBillResult
            if url.pathExtension.lowercased() == "xlsx" {
                imported = try XLSXBillImporter.importBill(from: data)
            } else {
                guard let text = BillTextDecoder.decode(data) else {
                    importMessage = String(localized: "无法识别文件编码")
                    return
                }
                imported = try PaymentBillImporter.importBill(fromCSV: text)
            }
            pendingImport = imported
            showImportReview = true
        } catch is BillImportError {
            importMessage = String(localized: "无法识别账单格式，请确认是微信或支付宝导出的 CSV 文件。")
        } catch {
            importMessage = error.localizedDescription
        }
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
                reimbursable: record.reimbursable,
                isReimbursed: record.isReimbursed,
                isExcluded: record.isExcluded,
                tagNames: record.tags.joined(separator: ","),
                attachmentPath: record.attachmentPath,
                orderNo: record.orderNo
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
