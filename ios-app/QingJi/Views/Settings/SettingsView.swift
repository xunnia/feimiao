import Foundation
import SwiftUI
import SwiftData
import WidgetKit
import PhotosUI
import UIKit
import QingJiCore

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    /// 全局路由：qingji://settings/budget 或 /reconcile 深链会设置 settingsPushTarget，
    /// NavigationStack 读取后 push 对应子页面。
    @Environment(AppRouter.self) private var router

    @State private var settingsMessage: String?
    @State private var showProfileEditor = false
    @AppStorage("qingji.repaymentReminderEnabled") private var repaymentReminderEnabled = true
    @AppStorage("qingji.widgetPrivacyMode") private var widgetPrivacyMode = false
    @AppStorage("qingji.profileNickname") private var profileNickname = ""
    @AppStorage("qingji.profileAvatarPath") private var profileAvatarPath = ""

    var body: some View {
        @Bindable var router = router

        List {
                Section {
                    Button {
                        showProfileEditor = true
                    } label: {
                        VStack(spacing: 10) {
                            ProfileAvatar(
                                nickname: profileNickname,
                                relativePath: profileAvatarPath,
                                size: 72
                            )
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "pencil")
                                    .font(.caption.weight(.semibold))
                                    .frame(width: 24, height: 24)
                                    .background(.background, in: .circle)
                                    .overlay { Circle().stroke(Color(uiColor: .separator), lineWidth: 0.5) }
                            }

                            Text(profileNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                 ? "点击设置昵称"
                                 : profileNickname)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(profileNickname.isEmpty ? .secondary : .primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(profileNickname.isEmpty ? "点击设置昵称和头像" : "编辑个人资料：\(profileNickname)")
                }
                .listRowBackground(Color.clear)

                Section {
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
                } header: {
                    Text("管理")
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

                Section {
                    Toggle("还款提醒", isOn: $repaymentReminderEnabled)
                        .onChange(of: repaymentReminderEnabled) { _, enabled in
                            updateRepaymentReminder(enabled)
                        }
                } header: {
                    Text("提醒")
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
            .scrollContentBackground(.hidden)
            .liquidGlassCanvas()
            .navigationTitle("设置")
            .navigationDestination(item: $router.settingsPushTarget) { target in
                settingsDestinationView(target)
            }
            .sheet(isPresented: $showProfileEditor) {
                ProfileEditorSheet(
                    nickname: $profileNickname,
                    avatarPath: $profileAvatarPath
                )
                .presentationDetents([.medium])
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

    @ViewBuilder
    private func settingsDestinationView(
        _ target: AppRouter.SettingsDestination
    ) -> some View {
        switch target {
        case .ai:        AIProviderSettingsView()
        case .books:     BooksView()
        case .accounts:  AccountsView()
        case .accountDetail: AccountsView(opensFirstDetail: true)
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
        case .reimburseSettlement: ReimburseView(opensFirstSettlement: true)
        case .savings:   SavingsGoalsView()
        case .recurring: RecurringRulesView()
        case .assets:    AssetsView(startsOnPhysical: true)
        case .assetDetail: AssetsView(opensFirstDetail: true, startsOnPhysical: true)
        case .liabilities: LiabilitiesView()
        case .netWorth:  NetWorthView()
        case .lending:   LendingView()
        case .importReview:
            // A review is only valid when it came from a real selected file.
            // The deterministic fixture is reserved for the CI demo launch.
            ImportExportView()
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

private struct ProfileAvatar: View {
    let nickname: String
    let relativePath: String
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let initial = nickname.trimmingCharacters(in: .whitespacesAndNewlines).first {
                Text(String(initial))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            } else {
                Image(systemName: "person.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .glassEffect(.regular.tint(Color.accentColor.opacity(0.10)), in: .circle)
    }

    private var image: UIImage? {
        guard let url = AttachmentStore.url(for: relativePath) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

private struct ProfileEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var nickname: String
    @Binding var avatarPath: String

    @State private var draftNickname: String
    @State private var draftAvatarPath: String
    @State private var photoItem: PhotosPickerItem?
    @State private var errorMessage: String?

    init(nickname: Binding<String>, avatarPath: Binding<String>) {
        _nickname = nickname
        _avatarPath = avatarPath
        _draftNickname = State(initialValue: nickname.wrappedValue)
        _draftAvatarPath = State(initialValue: avatarPath.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            ProfileAvatar(
                                nickname: draftNickname,
                                relativePath: draftAvatarPath,
                                size: 86
                            )
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "camera.fill")
                                    .font(.caption)
                                    .frame(width: 28, height: 28)
                                    .background(.background, in: .circle)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)

                Section("昵称") {
                    TextField("昵称", text: $draftNickname)
                        .textInputAutocapitalization(.never)
                        .onChange(of: draftNickname) { _, value in
                            if value.count > 20 {
                                draftNickname = String(value.prefix(20))
                            }
                        }
                }
            }
            .scrollContentBackground(.hidden)
            .liquidGlassCanvas()
            .navigationTitle("个人资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        nickname = draftNickname.trimmingCharacters(in: .whitespacesAndNewlines)
                        avatarPath = draftAvatarPath
                        dismiss()
                    }
                    .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self),
                              let image = UIImage(data: data),
                              let jpeg = image.jpegData(compressionQuality: 0.88) else {
                            throw ProfileImageError.invalidImage
                        }
                        let path = try AttachmentStore.save(data: jpeg, fileExtension: "jpg")
                        await MainActor.run { draftAvatarPath = path }
                    } catch {
                        await MainActor.run { errorMessage = error.localizedDescription }
                    }
                }
            }
            .alert("头像", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
}

private enum ProfileImageError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        "这张图片暂时不能作为头像"
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
