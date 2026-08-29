import SwiftUI
import SwiftData
import UIKit
import QingJiCore

/// 账户详情与 Android AccountDetailPage 对应。
///
/// 账户列表负责快速切换和编辑；详情页集中展示当前余额、余额趋势、校准记录、
/// 账户资料和流水活动。校准沿用同一套 checkpoint 账务模型，不写入虚假收支。
struct AccountDetailView: View {
    private enum TrendRange: String, CaseIterable, Identifiable {
        case month
        case quarter
        case year

        var id: String { rawValue }
        var days: Int {
            switch self {
            case .month: 30
            case .quarter: 90
            case .year: 365
            }
        }
        var label: String {
            switch self {
            case .month: "1 月"
            case .quarter: "3 月"
            case .year: "1 年"
            }
        }
    }

    private struct Activity: Identifiable {
        let id: UUID
        let transaction: MoneyTransaction
        let delta: Decimal
    }

    @Environment(\.modelContext) private var context
    @Query private var accounts: [Account]
    @Query(sort: \MoneyTransaction.date, order: .reverse)
    private var transactions: [MoneyTransaction]
    @Query private var checkpoints: [AccountBalanceCheckpointRecord]

    let account: Account
    @State private var trendRange: TrendRange = .month
    @State private var showCalibration = false
    @State private var showEditor = false
    @State private var showArchiveConfirmation = false
    @State private var checkpointToReverse: AccountBalanceCheckpointRecord?
    @State private var errorMessage: String?

    init(account: Account) {
        self.account = account
    }

    private var currentAccount: Account {
        accounts.first(where: { $0.stableID == account.stableID }) ?? account
    }

    private var balance: Decimal {
        LedgerStore.accountBalance(
            for: currentAccount,
            transactions: transactions,
            checkpoints: checkpoints
        )
    }

    private var accountCheckpoints: [AccountBalanceCheckpointRecord] {
        checkpoints
            .filter { $0.accountID == currentAccount.stableID && $0.eventKindRaw == "anchor" }
            .sorted {
                if $0.effectiveAt != $1.effectiveAt { return $0.effectiveAt > $1.effectiveAt }
                return $0.sequence > $1.sequence
            }
    }

    private var activities: [Activity] {
        let id = currentAccount.stableID
        return transactions.compactMap { transaction in
            let record = transaction.record
            let isOutgoing = record.accountID == id ||
                record.settlementAccountID == id ||
                transaction.account?.stableID == id ||
                transaction.settlementAccountID == id
            let isIncoming = record.toAccountID == id || transaction.toAccount?.stableID == id

            let delta: Decimal
            if record.kind == .transfer {
                if isIncoming && !isOutgoing {
                    delta = record.amount
                } else if isOutgoing {
                    delta = -record.amount
                } else {
                    return nil
                }
            } else if isOutgoing {
                delta = record.kind == .income ? record.amount : -record.amount
            } else {
                return nil
            }
            return Activity(id: transaction.stableID, transaction: transaction, delta: delta)
        }
        .prefix(12)
        .map { $0 }
    }

    private var trendPoints: [Double] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: AppClock.now)
        let start = calendar.date(byAdding: .day, value: -(trendRange.days - 1), to: today) ?? today
        let accountActivities = transactions.compactMap { transaction -> (Date, Decimal)? in
            let record = transaction.record
            let id = currentAccount.stableID
            let outgoing = record.accountID == id || record.settlementAccountID == id ||
                transaction.account?.stableID == id || transaction.settlementAccountID == id
            let incoming = record.toAccountID == id || transaction.toAccount?.stableID == id
            let delta: Decimal
            if record.kind == .transfer {
                if incoming && !outgoing { delta = record.amount }
                else if outgoing { delta = -record.amount }
                else { return nil }
            } else if outgoing {
                delta = record.kind == .income ? record.amount : -record.amount
            } else {
                return nil
            }
            guard transaction.date >= start else { return nil }
            return (transaction.date, delta)
        }

        let movementInRange = accountActivities.reduce(Decimal.zero) { $0 + $1.1 }
        var value = balance - movementInRange
        var values: [Double] = []
        for offset in 0..<trendRange.days {
            let day = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            for (date, delta) in accountActivities where date >= day && date < nextDay {
                value += delta
            }
            values.append(NSDecimalNumber(decimal: value).doubleValue)
        }
        return values
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                balanceCard
                actionSection
                trendCard
                if !accountCheckpoints.isEmpty {
                    checkpointSection
                }
                accountInfoSection
                activitySection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .liquidGlassCanvas()
        .navigationTitle(currentAccount.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showEditor = true
                    } label: {
                        Label("编辑资料", systemImage: "pencil")
                    }
                    Button {
                        showArchiveConfirmation = true
                    } label: {
                        Label(
                            currentAccount.status == .active ? "归档账户" : "恢复到账户列表",
                            systemImage: currentAccount.status == .active ? "archivebox" : "arrow.uturn.backward"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass(.clear))
                .accessibilityLabel("账户操作")
            }
        }
        .sheet(isPresented: $showCalibration) {
            AccountCalibrationSheet(account: currentAccount)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showEditor) {
            AccountEditorSheet(account: currentAccount, nextSortOrder: currentAccount.sortOrder)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            currentAccount.status == .active ? "归档账户" : "恢复账户",
            isPresented: $showArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button(currentAccount.status == .active ? "归档" : "恢复", role: currentAccount.status == .active ? .destructive : nil) {
                toggleArchive()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(currentAccount.status == .active
                 ? "归档只会把账户移出默认列表，余额和历史流水都会保留。"
                 : "恢复后账户会重新出现在可用账户列表。")
        }
        .confirmationDialog(
            "撤销余额校准？",
            isPresented: Binding(
                get: { checkpointToReverse != nil },
                set: { if !$0 { checkpointToReverse = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("撤销", role: .destructive) {
                reverseCheckpoint()
            }
            Button("取消", role: .cancel) { checkpointToReverse = nil }
        } message: {
            Text("撤销后会回到上一条有效校准，不会写入一笔反向收支。")
        }
        .alert("账户操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("当前余额")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(MoneyFormat.string(balance, currencyCode: currentAccount.currencyCode))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(balance < 0 ? Color.warning : .primary)
            if let checkpoint = accountCheckpoints.first(where: { $0.status == "active" }) {
                Label(
                    "已核对于 \(checkpoint.effectiveAt.formatted(date: .abbreviated, time: .shortened))",
                    systemImage: "checkmark.seal"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if currentAccount.openingBalanceQuality == .exact || currentAccount.openingBalanceQuality == .userConfirmed {
                Label("从账户建立时点起可信", systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("历史起点可能需要校准", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private var actionSection: some View {
        VStack(spacing: 0) {
            Button {
                showCalibration = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("校准余额")
                            .font(.body.weight(.medium))
                        Text("按现在的实际余额修正，不计入收支")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.glass(.clear))
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("余额趋势")
                    .font(.headline)
                Spacer()
                Picker("趋势区间", selection: $trendRange) {
                    ForEach(TrendRange.allCases) { range in
                        Text(range.label).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 178)
                .accessibilityLabel("余额趋势区间")
            }

            AccountTrendGraph(values: trendPoints)
                .frame(height: 128)
            HStack {
                Text("\(trendRange.days) 天")
                Spacer()
                Text("当前 \(MoneyFormat.string(balance, currencyCode: currentAccount.currencyCode))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private var checkpointSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("余额核对记录")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 4)
            ForEach(Array(accountCheckpoints.prefix(3))) { checkpoint in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(MoneyFormat.string(checkpoint.targetBalance, currencyCode: currentAccount.currencyCode))
                            .font(.body.monospacedDigit().weight(.medium))
                        Text("\(checkpoint.effectiveAt.formatted(date: .abbreviated, time: .shortened)) · 差额 \(MoneyFormat.string(checkpoint.deltaAtCreation, currencyCode: currentAccount.currencyCode))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if checkpoint.status == "active" {
                        Button("撤销") {
                            checkpointToReverse = checkpoint
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.glass(.clear))
                        .controlSize(.small)
                    } else {
                        Text("已撤销")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                if checkpoint.stableID != accountCheckpoints.prefix(3).last?.stableID {
                    Divider().padding(.leading, 14)
                }
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private var accountInfoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("账户资料")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 4)
            infoRow("类型", kindName(currentAccount.kind))
            if !currentAccount.institution.isEmpty {
                infoRow("机构", currentAccount.institution)
            }
            infoRow("币种", currentAccount.currencyCode == "CNY" ? "人民币" : currentAccount.currencyCode)
            infoRow("净资产", currentAccount.includeInNetWorth ? "计入净资产" : "不计入净资产")
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("最近账户活动")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 4)
            if activities.isEmpty {
                Text("还没有与这个账户关联的流水。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(14)
            } else {
                ForEach(activities) { activity in
                    HStack(spacing: 10) {
                        Image(systemName: activity.transaction.kind == .income ? "arrow.down.left" : "arrow.up.right")
                            .foregroundStyle(activity.delta >= 0 ? Color.accentColor : .secondary)
                            .frame(width: 30, height: 30)
                            .background(Color.accentColor.opacity(0.1), in: .circle)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(activityTitle(activity.transaction))
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(activity.transaction.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text((activity.delta >= 0 ? "+" : "") + MoneyFormat.string(activity.delta, currencyCode: currentAccount.currencyCode))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(activity.delta >= 0 ? Color.accentColor : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .padding(14)
                    if activity.id != activities.last?.id {
                        Divider().padding(.leading, 54)
                    }
                }
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func activityTitle(_ transaction: MoneyTransaction) -> String {
        if !transaction.note.isEmpty { return transaction.note }
        if !transaction.merchantName.isEmpty { return transaction.merchantName }
        if !transaction.productName.isEmpty { return transaction.productName }
        switch transaction.kind {
        case .expense: return "支出"
        case .income: return "收入"
        case .transfer: return "转账"
        }
    }

    private func kindName(_ kind: AccountKind) -> String {
        switch kind {
        case .cash: "现金"
        case .bankCard: "储蓄卡"
        case .creditCard: "信用卡"
        case .savings: "存款"
        case .investment: "投资"
        case .loan: "贷款"
        case .weChat: "微信"
        case .alipay: "支付宝"
        case .other: "其他"
        }
    }

    private func toggleArchive() {
        currentAccount.status = currentAccount.status == .active ? .archived : .active
        currentAccount.isDeleted = false
        currentAccount.archivedAt = currentAccount.status == .archived ? AppClock.now : nil
        currentAccount.updatedAt = AppClock.now
        do {
            try context.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reverseCheckpoint() {
        guard let checkpoint = checkpointToReverse else { return }
        checkpointToReverse = nil
        do {
            try AccountCheckpointStore.reverse(checkpoint, in: context)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AccountTrendGraph: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geometry in
            let bounds = chartBounds
            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { index in
                        Rectangle()
                            .fill(Color.secondary.opacity(0.14))
                            .frame(height: 1)
                        if index < 3 { Spacer() }
                    }
                }
                Path { path in
                    guard values.count > 1 else { return }
                    for (index, value) in values.enumerated() {
                        let x = geometry.size.width * CGFloat(index) / CGFloat(values.count - 1)
                        let ratio = (value - bounds.min) / max(bounds.max - bounds.min, 0.0001)
                        let y = geometry.size.height * (1 - CGFloat(ratio))
                        if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel("账户余额趋势")
    }

    private var chartBounds: (min: Double, max: Double) {
        guard let minValue = values.min(), let maxValue = values.max() else { return (0, 1) }
        if minValue == maxValue { return (minValue - 1, maxValue + 1) }
        let padding = max((maxValue - minValue) * 0.08, 1)
        return (minValue - padding, maxValue + padding)
    }
}

private struct AccountCalibrationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let account: Account
    @State private var actualText: String
    @State private var note = ""
    @State private var errorMessage: String?

    init(account: Account) {
        self.account = account
        _actualText = State(initialValue: NSDecimalNumber(decimal: account.initialBalance).stringValue)
    }

    private var actualBalance: Decimal? {
        Decimal(string: actualText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ""))
    }

    private var calculatedBalance: Decimal {
        let transactions = (try? context.fetch(FetchDescriptor<MoneyTransaction>())) ?? []
        let checkpoints = (try? context.fetch(FetchDescriptor<AccountBalanceCheckpointRecord>())) ?? []
        return LedgerStore.accountBalance(for: account, transactions: transactions, checkpoints: checkpoints)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("本次核对") {
                    LabeledContent("系统计算余额") {
                        Text(MoneyFormat.string(calculatedBalance, currencyCode: account.currencyCode))
                            .monospacedDigit()
                    }
                    TextField("实际余额", text: $actualText)
                        .keyboardType(.numbersAndPunctuation)
                    if let actualBalance {
                        LabeledContent("差额") {
                            Text(MoneyFormat.string(actualBalance - calculatedBalance, currencyCode: account.currencyCode))
                                .monospacedDigit()
                        }
                    }
                    TextField("说明（可选）", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    Text("以实际余额为准，差额会作为可撤销的余额校准保存，不会生成收入、支出或现金流。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("校准余额")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(actualBalance == nil)
                }
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        guard let actualBalance else { return }
        do {
            let checkpoint = try AccountCheckpointStore.create(
                for: account,
                actualBalance: actualBalance,
                effectiveAt: AppClock.now,
                in: context
            )
            if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                checkpoint.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
                try context.save()
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
