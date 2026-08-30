import Foundation
import SwiftUI
import SwiftData
import UIKit
import QingJiCore

/// 资金账户管理。
///
/// 账户是流水、资产和导入映射的共同边界。已有流水的账户只能归档，不能
/// 直接从 SwiftData 删除，否则历史账单会失去余额计算所需的 stableID。
struct AccountsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query(sort: \MoneyTransaction.date, order: .reverse)
    private var transactions: [MoneyTransaction]
    @Query
    private var checkpoints: [AccountBalanceCheckpointRecord]

    @State private var showAddSheet = false
    @State private var editingAccount: Account?
    @State private var errorMessage: String?
    let opensFirstDetail: Bool
    @State private var launchDetailAccount: Account?
    @State private var didOpenLaunchDetail = false

    private var activeAccounts: [Account] {
        accounts.filter { !$0.isDeleted && $0.status == .active }
    }

    private var archivedAccounts: [Account] {
        accounts.filter { $0.isDeleted || $0.status != .active }
    }

    init(opensFirstDetail: Bool = false) {
        self.opensFirstDetail = opensFirstDetail
    }

    var body: some View {
        List {
            Section {
                ForEach(activeAccounts) { account in
                    NavigationLink {
                        AccountDetailView(account: account)
                    } label: {
                        accountRow(account)
                    }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                editingAccount = account
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.accentColor)

                            Button {
                                archive(account)
                            } label: {
                                Label("归档", systemImage: "archivebox")
                            }
                            .tint(.orange)
                        }
                }
                .onMove(perform: moveAccounts)
            } header: {
                Text("使用中的账户")
            } footer: {
                Text("账户余额由期初余额和已记录流水计算；不再使用的账户建议归档。")
            }

            if !archivedAccounts.isEmpty {
                Section("已归档") {
                    ForEach(archivedAccounts) { account in
                        NavigationLink {
                            AccountDetailView(account: account)
                        } label: {
                            accountRow(account, isArchived: true)
                        }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    restore(account)
                                } label: {
                                    Label("恢复", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.accentColor)
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .liquidGlassCanvas()
        .navigationTitle("账户管理")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
                    .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .liquidGlassCircleControl()
                .accessibilityLabel("新建账户")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AccountEditorSheet(
                account: nil,
                nextSortOrder: (accounts.map(\.sortOrder).max() ?? -1) + 1
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingAccount) { account in
            AccountEditorSheet(account: account, nextSortOrder: account.sortOrder)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $launchDetailAccount) { account in
            AccountDetailView(account: account)
                .presentationDetents([.large])
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            guard opensFirstDetail, !didOpenLaunchDetail,
                  let account = activeAccounts.first else { return }
            didOpenLaunchDetail = true
            launchDetailAccount = account
        }
    }

    private func accountRow(_ account: Account, isArchived: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: account.kind.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(isArchived ? .secondary : Color.accentColor)
                .frame(width: 36, height: 36)
                .background(
                    (isArchived ? Color.secondary : Color.accentColor).opacity(0.12),
                    in: .circle
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(account.name)
                        .font(.body.weight(.medium))
                    if account.kind.isLiability {
                        Text("负债")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.12), in: .capsule)
                    }
                }
                HStack(spacing: 5) {
                    Text(account.currencyCode)
                    if !account.institution.isEmpty {
                        Text("·")
                        Text(account.institution)
                            .lineLimit(1)
                    }
                    if account.creditLimit != nil {
                        Text("· 有额度")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                let currentBalance = balance(for: account)
                Text(MoneyFormat.string(currentBalance, currencyCode: account.currencyCode))
                    .font(.body.monospacedDigit().weight(.medium))
                    .foregroundStyle(isArchived ? .secondary : (currentBalance < 0 ? Color.warning : .primary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(isArchived ? "已归档" : "余额")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(isArchived ? Color.secondary : Color.primary)
    }

    private func balance(for account: Account) -> Decimal {
        LedgerStore.accountBalance(
            for: account,
            transactions: transactions,
            checkpoints: checkpoints
        )
    }

    private func moveAccounts(from source: IndexSet, to destination: Int) {
        var ordered = activeAccounts
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, account) in ordered.enumerated() {
            account.sortOrder = index
            account.updatedAt = Date()
        }
        saveContext()
    }

    private func archive(_ account: Account) {
        account.status = .archived
        account.isDeleted = false
        account.archivedAt = Date()
        account.updatedAt = Date()
        saveContext()
    }

    private func restore(_ account: Account) {
        account.status = .active
        account.isDeleted = false
        account.archivedAt = nil
        account.updatedAt = Date()
        saveContext()
    }

    private func saveContext() {
        do {
            try context.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AccountEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let account: Account?
    let nextSortOrder: Int

    @State private var name: String
    @State private var kind: AccountKind
    @State private var currencyCode: String
    @State private var initialBalanceText: String
    @State private var institution: String
    @State private var includeInNetWorth: Bool
    @State private var statementDay: Int
    @State private var paymentDay: Int
    @State private var creditLimitText: String
    @State private var errorMessage: String?

    init(account: Account?, nextSortOrder: Int) {
        self.account = account
        self.nextSortOrder = nextSortOrder
        _name = State(initialValue: account?.name ?? "")
        _kind = State(initialValue: account?.kind ?? .bankCard)
        _currencyCode = State(initialValue: account?.currencyCode ?? "CNY")
        _initialBalanceText = State(initialValue: account.map { Self.decimalText($0.initialBalance) } ?? "0")
        _institution = State(initialValue: account?.institution ?? "")
        _includeInNetWorth = State(initialValue: account?.includeInNetWorth ?? true)
        _statementDay = State(initialValue: account?.creditStatementDay ?? 1)
        _paymentDay = State(initialValue: account?.creditPaymentDay ?? 20)
        _creditLimitText = State(initialValue: account.flatMap { $0.creditLimit.map(Self.decimalText) } ?? "")
    }

    private var parsedInitialBalance: Decimal? {
        Decimal(string: initialBalanceText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ""))
    }

    private var parsedCreditLimit: Decimal? {
        let text = creditLimitText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return Decimal(string: text.replacingOccurrences(of: ",", with: ""))
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).count == 3 &&
        parsedInitialBalance != nil &&
        (creditLimitText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parsedCreditLimit != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("账户名称", text: $name)
                    Picker("类型", selection: $kind) {
                        ForEach(AccountKind.allCases, id: \.self) { item in
                            Label(kindName(item), systemImage: item.symbol).tag(item)
                        }
                    }
                    TextField("币种代码", text: $currencyCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("期初余额", text: $initialBalanceText)
                        .keyboardType(.decimalPad)
                }

                Section("归属") {
                    TextField("机构（可选）", text: $institution)
                    Toggle("计入净资产", isOn: $includeInNetWorth)
                }

                if kind == .creditCard {
                    Section("信用卡信息") {
                        Stepper("账单日：\(statementDay) 日", value: $statementDay, in: 1...31)
                        Stepper("还款日：\(paymentDay) 日", value: $paymentDay, in: 1...31)
                        TextField("信用额度（可选）", text: $creditLimitText)
                            .keyboardType(.decimalPad)
                    }
                }
            }
            .navigationTitle(account == nil ? "新增账户" : "编辑账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(account == nil ? "创建" : "保存") { save() }
                        .disabled(!canSave)
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
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
        guard canSave,
              let initialBalance = parsedInitialBalance else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanInstitution = institution.trimmingCharacters(in: .whitespacesAndNewlines)

        if let account {
            account.name = cleanName
            account.kind = kind
            account.currencyCode = cleanCurrency
            account.initialBalance = initialBalance
            account.institution = cleanInstitution
            account.includeInNetWorth = includeInNetWorth
            account.creditStatementDay = kind == .creditCard ? statementDay : nil
            account.creditPaymentDay = kind == .creditCard ? paymentDay : nil
            account.creditLimit = kind == .creditCard ? parsedCreditLimit : nil
            account.updatedAt = Date()
        } else {
            let newAccount = Account(
                name: cleanName,
                kind: kind,
                currencyCode: cleanCurrency,
                sortOrder: nextSortOrder
            )
            newAccount.initialBalance = initialBalance
            newAccount.institution = cleanInstitution
            newAccount.includeInNetWorth = includeInNetWorth
            newAccount.creditStatementDay = kind == .creditCard ? statementDay : nil
            newAccount.creditPaymentDay = kind == .creditCard ? paymentDay : nil
            newAccount.creditLimit = kind == .creditCard ? parsedCreditLimit : nil
            context.insert(newAccount)
        }

        do {
            try context.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func kindName(_ kind: AccountKind) -> String {
        switch kind {
        case .cash: return "现金"
        case .bankCard: return "储蓄卡"
        case .creditCard: return "信用卡"
        case .savings: return "存款"
        case .investment: return "投资"
        case .loan: return "贷款"
        case .weChat: return "微信"
        case .alipay: return "支付宝"
        case .other: return "其他"
        }
    }

    private static func decimalText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
