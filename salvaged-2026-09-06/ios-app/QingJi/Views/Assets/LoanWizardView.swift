import SwiftUI
import SwiftData

/// 房贷/大额分期向导：一次设置贷款账户、负债档案和每月自动还款。
/// 年利率只保存用于展示；本息拆分仍由手动还款路径处理。
struct LoanWizardSheet: View {
    private static let supportedKinds: [LiabilityKind] = [
        .mortgage, .carLoan, .consumerLoan
    ]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query(sort: \Book.sortOrder)
    private var books: [Book]

    @State private var kind: LiabilityKind = .mortgage
    @State private var name = "房贷"
    @State private var totalText = ""
    @State private var principalText = ""
    @State private var rateText = ""
    @State private var monthlyText = ""
    @State private var repaymentDay = 1
    @State private var fromAccountID: UUID?
    @State private var bookID: UUID?
    @State private var errorMessage: String?

    private var usableAccounts: [Account] {
        accounts.filter {
            !$0.isDeleted && $0.status == .active && $0.currencyCode == "CNY"
        }
    }

    private func positive(_ text: String) -> Decimal? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard !normalized.isEmpty, let value = Decimal(string: normalized), value > 0 else {
            return nil
        }
        return value
    }

    private var total: Decimal? { positive(totalText) }

    private var principal: Decimal? {
        principalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? total
            : positive(principalText)
    }

    private var monthly: Decimal? { positive(monthlyText) }

    private var rate: Decimal? {
        let normalized = rateText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized)
    }

    private var valid: Bool {
        guard let total, let principal, let monthly,
              total > 0, principal > 0, principal <= total, monthly > 0,
              rateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || rate != nil,
              fromAccountID != nil else {
            return false
        }
        return true
    }

    private var firstDuePreview: Date? {
        let calendar = Calendar.current
        let now = Date()
        func due(year: Int, month: Int) -> Date {
            let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? now
            let lastDay = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
            return calendar.date(from: DateComponents(
                year: year,
                month: month,
                day: min(repaymentDay, lastDay),
                hour: 12
            )) ?? now
        }
        let today = calendar.startOfDay(for: now)
        let components = calendar.dateComponents([.year, .month], from: now)
        let thisMonth = due(year: components.year ?? 2000, month: components.month ?? 1)
        if !calendar.startOfDay(for: thisMonth).isBefore(today) { return thisMonth }
        let next = calendar.date(byAdding: .month, value: 1, to: thisMonth) ?? now
        let nextComponents = calendar.dateComponents([.year, .month], from: next)
        return due(year: nextComponents.year ?? 2000, month: nextComponents.month ?? 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("贷款信息") {
                    Picker("类型", selection: $kind) {
                        ForEach(Self.supportedKinds) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    TextField("名称", text: $name)
                    TextField("贷款总额", text: $totalText)
                        .keyboardType(.decimalPad)
                    TextField("剩余本金", text: $principalText)
                        .keyboardType(.decimalPad)
                    TextField("年利率 %（可选，仅展示）", text: $rateText)
                        .keyboardType(.decimalPad)
                }

                Section("还款计划") {
                    TextField("每月还款额", text: $monthlyText)
                        .keyboardType(.decimalPad)
                    Picker("每月还款日", selection: $repaymentDay) {
                        ForEach(1...31, id: \.self) { day in
                            Text("每月 \(day) 日").tag(day)
                        }
                    }
                    Picker("扣款账户", selection: $fromAccountID) {
                        Text("请选择账户").tag(Optional<UUID>.none)
                        ForEach(usableAccounts) { account in
                            Text(account.name).tag(Optional(account.stableID))
                        }
                    }
                    Picker("账本", selection: $bookID) {
                        Text("总账本").tag(Optional<UUID>.none)
                        ForEach(books) { book in
                            Text(book.name).tag(Optional(book.stableID))
                        }
                    }
                    if let firstDuePreview {
                        LabeledContent(
                            "首次自动记账",
                            value: firstDuePreview.formatted(date: .abbreviated, time: .omitted)
                        )
                    }
                }

                Section {
                    Text("创建后会建立贷款账户（余额为负的剩余本金）、负债档案和每月自动转账规则。年利率只作展示，不在向导中虚构本息拆分。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("房贷/分期向导")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") { save() }
                        .disabled(!valid)
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
            }
            .onAppear {
                if fromAccountID == nil { fromAccountID = usableAccounts.first?.stableID }
            }
            .onChange(of: kind) { oldValue, newValue in
                let defaults: [LiabilityKind: String] = [
                    .mortgage: "房贷",
                    .carLoan: "车贷",
                    .consumerLoan: "消费贷",
                ]
                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    name == defaults[oldValue] {
                    name = defaults[newValue] ?? newValue.label
                }
            }
            .alert("无法创建", isPresented: Binding(
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
        guard let total, let principal, let monthly,
              let fromAccount = usableAccounts.first(where: { $0.stableID == fromAccountID }),
              valid else { return }
        do {
            _ = try LiabilityStore.createLoanWizardSetup(
                in: context,
                kind: kind,
                name: name,
                totalAmount: total,
                remainingPrincipal: principal,
                annualRate: rate,
                monthlyPayment: monthly,
                repaymentDay: repaymentDay,
                fromAccount: fromAccount,
                book: books.first(where: { $0.stableID == bookID })
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
