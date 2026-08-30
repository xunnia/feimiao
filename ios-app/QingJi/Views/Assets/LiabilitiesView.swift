import SwiftUI
import SwiftData
import QingJiCore

/// 负债管理：本金档案和账户余额分开解释，还款动作由 LiabilityStore 生成真实流水。
struct LiabilitiesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LiabilityProfile.updatedAt, order: .reverse)
    private var profiles: [LiabilityProfile]
    @Query(sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query(sort: \Book.sortOrder)
    private var books: [Book]
    @Query(filter: #Predicate<TxCategory> { !$0.isArchived }, sort: \TxCategory.sortOrder)
    private var categories: [TxCategory]

    @State private var showEditor = false
    @State private var editingProfile: LiabilityProfile?
    @State private var repaymentProfile: LiabilityProfile?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                HStack {
                    Label("当前负债", systemImage: "minus.circle")
                    Spacer()
                    Text(MoneyFormat.string(totalLiabilities, currencyCode: "CNY"))
                        .font(.headline.monospacedDigit())
                }
            }

            if profiles.isEmpty {
                ContentUnavailableView(
                    "还没有负债档案",
                    systemImage: "creditcard",
                    description: Text("信用卡、贷款和借入款可以单独记录本金与还款计划")
                )
                .listRowBackground(Color.clear)
            } else {
                Section("负债档案") {
                    ForEach(profiles) { profile in
                        liabilityRow(profile)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .liquidGlassCanvas()
        .navigationTitle("负债管理")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEditor = true } label: {
                    Image(systemName: "plus")
                }
                .liquidGlassCircleControl()
                .accessibilityLabel("新建负债")
            }
        }
        .sheet(isPresented: $showEditor) {
            LiabilityEditor(profile: nil)
                .presentationDetents([.large])
        }
        .sheet(item: $editingProfile) { profile in
            LiabilityEditor(profile: profile)
                .presentationDetents([.large])
        }
        .sheet(item: $repaymentProfile) { profile in
            LiabilityRepaymentSheet(profile: profile)
                .presentationDetents([.medium, .large])
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var totalLiabilities: Decimal {
        profiles
            .filter { $0.lifecycle == .active }
            .reduce(into: Decimal.zero) { $0 += $1.currentPrincipal }
    }

    private func liabilityRow(_ profile: LiabilityProfile) -> some View {
        let account = accounts.first { $0.stableID == profile.accountID }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: profile.kind.symbolName)
                    .foregroundStyle(profile.lifecycle == .active ? Color.red : Color.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color.red.opacity(0.1), in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.kind.label)
                        .font(.body.weight(.medium))
                    Text(profile.counterparty.isEmpty ? (account?.name ?? "未绑定账户") : profile.counterparty)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(MoneyFormat.string(profile.currentPrincipal, currencyCode: profile.currencyCode))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            HStack(spacing: 6) {
                Text(profile.lifecycle.label)
                if let paymentDay = profile.paymentDay {
                    Text("· 每月 \(paymentDay) 日还款")
                }
                if let dueDate = profile.dueDate {
                    Text("· 到期 \(dueDate.formatted(date: .abbreviated, time: .omitted))")
                }
                Spacer()
                if profile.lifecycle == .active {
                    Button("还款") { repaymentProfile = profile }
                        .font(.caption.weight(.semibold))
                        .liquidGlassPrimaryPillControl(horizontalPadding: 10, minHeight: 36)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { editingProfile = profile }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if profile.lifecycle == .active {
                Button {
                    do { try LiabilityStore.setLifecycle(profile, status: .paused, in: context) }
                    catch { errorMessage = error.localizedDescription }
                } label: {
                    Label("暂停", systemImage: "pause.fill")
                }
                .tint(.orange)
            } else if profile.lifecycle == .paused {
                Button {
                    do { try LiabilityStore.setLifecycle(profile, status: .active, in: context) }
                    catch { errorMessage = error.localizedDescription }
                } label: {
                    Label("恢复", systemImage: "play.fill")
                }
                .tint(.accentColor)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                do { try LiabilityStore.setLifecycle(profile, status: .archived, in: context) }
                catch { errorMessage = error.localizedDescription }
            } label: {
                Label("归档", systemImage: "archivebox")
            }
            .tint(.gray)
        }
    }
}

private extension LiabilityKind {
    var symbolName: String {
        switch self {
        case .creditCard: return "creditcard.fill"
        case .mortgage: return "house.fill"
        case .carLoan: return "car.fill"
        case .consumerLoan: return "doc.text.fill"
        case .personalBorrow: return "person.2.fill"
        case .other: return "minus.circle.fill"
        }
    }
}

private struct LiabilityEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder)
    private var accounts: [Account]

    let profile: LiabilityProfile?
    @State private var kind: LiabilityKind
    @State private var originalText: String
    @State private var currentText: String
    @State private var accountID: UUID?
    @State private var counterparty: String
    @State private var rateText: String
    @State private var statementDayText: String
    @State private var paymentDayText: String
    @State private var creditLimitText: String
    @State private var startDateEnabled: Bool
    @State private var startDate: Date
    @State private var dueDateEnabled: Bool
    @State private var dueDate: Date
    @State private var note: String
    @State private var errorMessage: String?

    init(profile: LiabilityProfile?) {
        self.profile = profile
        _kind = State(initialValue: profile?.kind ?? .other)
        _originalText = State(initialValue: profile.map { "\($0.originalPrincipal)" } ?? "")
        _currentText = State(initialValue: profile.map { "\($0.currentPrincipal)" } ?? "")
        _accountID = State(initialValue: profile?.accountID)
        _counterparty = State(initialValue: profile?.counterparty ?? "")
        _rateText = State(initialValue: profile.flatMap { $0.annualRate.map(String.init) } ?? "")
        _statementDayText = State(initialValue: profile.flatMap { $0.statementDay.map(String.init) } ?? "")
        _paymentDayText = State(initialValue: profile.flatMap { $0.paymentDay.map(String.init) } ?? "")
        _creditLimitText = State(initialValue: profile.flatMap { $0.creditLimit.map(String.init) } ?? "")
        _startDateEnabled = State(initialValue: profile?.startDate != nil)
        _startDate = State(initialValue: profile?.startDate ?? Date())
        _dueDateEnabled = State(initialValue: profile?.dueDate != nil)
        _dueDate = State(initialValue: profile?.dueDate ?? Date())
        _note = State(initialValue: profile?.note ?? "")
    }

    private var original: Decimal? { Decimal(string: originalText.replacingOccurrences(of: ",", with: "")) }
    private var current: Decimal? { Decimal(string: currentText.replacingOccurrences(of: ",", with: "")) }
    private var account: Account? { accounts.first { $0.stableID == accountID } }
    private var rate: Decimal? {
        let text = rateText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : Decimal(string: text)
    }
    private var statementDay: Int? { parseDay(statementDayText) }
    private var paymentDay: Int? { parseDay(paymentDayText) }
    private var creditLimit: Decimal? {
        let text = creditLimitText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : Decimal(string: text)
    }
    private var canSave: Bool {
        guard let original, let current, original > 0, current >= 0, current <= original,
              account != nil else { return false }
        if let statementDay, !(1...31).contains(statementDay) { return false }
        if let paymentDay, !(1...31).contains(paymentDay) { return false }
        if dueDateEnabled && startDateEnabled && dueDate < startDate { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("类型", selection: $kind) {
                        ForEach(LiabilityKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    TextField("原始本金", text: $originalText)
                        .keyboardType(.decimalPad)
                    TextField("当前本金", text: $currentText)
                        .keyboardType(.decimalPad)
                    Picker("绑定负债账户", selection: $accountID) {
                        Text("请选择账户").tag(Optional<UUID>.none)
                        ForEach(accounts.filter { !$0.isDeleted }) { account in
                            Text(account.name).tag(Optional(account.stableID))
                        }
                    }
                    TextField("借款对象 / 机构（可选）", text: $counterparty)
                }
                Section("还款计划") {
                    TextField("年利率 %（可选）", text: $rateText)
                        .keyboardType(.decimalPad)
                    if kind == .creditCard {
                        TextField("账单日 1-31（可选）", text: $statementDayText)
                            .keyboardType(.numberPad)
                        TextField("还款日 1-31（可选）", text: $paymentDayText)
                            .keyboardType(.numberPad)
                        TextField("信用额度（可选）", text: $creditLimitText)
                            .keyboardType(.decimalPad)
                    } else {
                        TextField("每月还款日 1-31（可选）", text: $paymentDayText)
                            .keyboardType(.numberPad)
                    }
                    Toggle("记录开始日期", isOn: $startDateEnabled)
                    if startDateEnabled {
                        DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                    }
                    Toggle("记录结清日期", isOn: $dueDateEnabled)
                    if dueDateEnabled {
                        DatePicker("结清日期", selection: $dueDate, displayedComponents: .date)
                    }
                }
                Section {
                    TextField("备注（可选）", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(profile == nil ? "新建负债" : "编辑负债")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(profile == nil ? "创建" : "保存") { save() }
                        .disabled(!canSave)
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
            }
            .onAppear {
                if accountID == nil { accountID = accounts.first?.stableID }
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

    private func parseDay(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Int(trimmed)
    }

    private func save() {
        guard let original, let current, let account, canSave else { return }
        do {
            if let profile {
                try LiabilityStore.update(
                    profile,
                    in: context,
                    kind: kind,
                    originalPrincipal: original,
                    currentPrincipal: current,
                    account: account,
                    counterparty: counterparty,
                    annualRate: rate,
                    statementDay: statementDay,
                    paymentDay: paymentDay,
                    creditLimit: creditLimit,
                    startDate: startDateEnabled ? startDate : nil,
                    dueDate: dueDateEnabled ? dueDate : nil,
                    note: note
                )
            } else {
                _ = try LiabilityStore.create(
                    in: context,
                    kind: kind,
                    originalPrincipal: original,
                    currentPrincipal: current,
                    account: account,
                    counterparty: counterparty,
                    annualRate: rate,
                    statementDay: statementDay,
                    paymentDay: paymentDay,
                    creditLimit: creditLimit,
                    startDate: startDateEnabled ? startDate : nil,
                    dueDate: dueDateEnabled ? dueDate : nil,
                    note: note
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct LiabilityRepaymentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query(sort: \Book.sortOrder)
    private var books: [Book]
    @Query(filter: #Predicate<TxCategory> { !$0.isArchived }, sort: \TxCategory.sortOrder)
    private var categories: [TxCategory]

    let profile: LiabilityProfile
    @State private var amountText: String
    @State private var fromAccountID: UUID?
    @State private var bookID: UUID?
    @State private var date = Date()
    @State private var note = ""
    @State private var errorMessage: String?
    @State private var resultMessage: String?

    init(profile: LiabilityProfile) {
        self.profile = profile
        _amountText = State(initialValue: "\(profile.currentPrincipal)")
    }

    private var amount: Decimal? { Decimal(string: amountText.replacingOccurrences(of: ",", with: "")) }
    private var fromAccount: Account? { accounts.first { $0.stableID == fromAccountID } }
    private var liabilityAccountID: UUID? { profile.accountID }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("当前本金 \(MoneyFormat.string(profile.currentPrincipal, currencyCode: profile.currencyCode))")
                        .foregroundStyle(.secondary)
                    TextField("本次还款金额", text: $amountText)
                        .keyboardType(.decimalPad)
                    Picker("付款账户", selection: $fromAccountID) {
                        Text("请选择账户").tag(Optional<UUID>.none)
                        ForEach(accounts.filter {
                            !$0.isDeleted &&
                            $0.status == .active &&
                            $0.stableID != liabilityAccountID
                        }) { account in
                            Text(account.name).tag(Optional(account.stableID))
                        }
                    }
                    Picker("账本", selection: $bookID) {
                        Text("总账本").tag(Optional<UUID>.none)
                        ForEach(books) { book in
                            Text(book.name).tag(Optional(book.stableID))
                        }
                    }
                    DatePicker("还款日期", selection: $date, displayedComponents: .date)
                    TextField("备注（可选）", text: $note)
                }
                Section {
                    Text("本金部分生成付款账户到负债账户的转账；超出本金的部分才记为利息支出。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("还款")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认") { repay() }
                        .disabled(amount == nil || amount! <= 0 || fromAccount == nil)
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
            }
            .onAppear {
                if fromAccountID == nil {
                    fromAccountID = accounts.first {
                        !$0.isDeleted &&
                        $0.status == .active &&
                        $0.stableID != liabilityAccountID &&
                        $0.currencyCode == profile.currencyCode
                    }?.stableID
                }
            }
            .alert("还款结果", isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            )) {
                Button("好") { dismiss() }
            } message: {
                Text(resultMessage ?? "")
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

    private func repay() {
        guard let amount, let fromAccount else { return }
        do {
            let category = categories.first { $0.kind == .expense && $0.key == "other" }
            let result = try LiabilityStore.repay(
                profile,
                amount: amount,
                fromAccount: fromAccount,
                book: books.first { $0.stableID == bookID },
                category: category,
                date: date,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                in: context
            )
            resultMessage = result.interest > 0
                ? "已还本金 \(MoneyFormat.string(result.principal, currencyCode: profile.currencyCode))，利息 \(MoneyFormat.string(result.interest, currencyCode: profile.currencyCode))。"
                : "已记录还款 \(MoneyFormat.string(result.principal, currencyCode: profile.currencyCode))。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
