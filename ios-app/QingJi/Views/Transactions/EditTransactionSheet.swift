import SwiftUI
import SwiftData
import QingJiCore

/// 编辑一笔已有流水。
struct EditTransactionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let transaction: MoneyTransaction

    @Query(filter: #Predicate<TxCategory> { !$0.isArchived }, sort: \TxCategory.sortOrder)
    private var allCategories: [TxCategory]
    @Query(sort: \Account.sortOrder)
    private var accounts: [Account]

    @State private var amountText = ""
    @State private var note = ""
    @State private var date = Date()
    @State private var category: TxCategory?
    @State private var account: Account?

    private var parsedAmount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ""))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("金额", text: $amountText)
                        .keyboardType(.decimalPad)
                    if transaction.kind != .transfer {
                        Picker("分类", selection: $category) {
                            ForEach(allCategories.filter { $0.kind == transaction.kind }) { item in
                                Label(item.name, systemImage: item.symbol).tag(Optional(item))
                            }
                        }
                    }
                    Picker("账户", selection: $account) {
                        Text("无").tag(Optional<Account>.none)
                        ForEach(accounts) { item in
                            Text(item.name).tag(Optional(item))
                        }
                    }
                    DatePicker("日期", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    TextField("备注", text: $note)
                }
                Section {
                    Button("删除这笔", role: .destructive) {
                        context.delete(transaction)
                        try? context.save()
                        dismiss()
                    }
                }
            }
            .navigationTitle("编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(parsedAmount == nil || parsedAmount! <= 0)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        amountText = "\(transaction.amount)"
        note = transaction.note
        date = transaction.date
        category = transaction.category
        account = transaction.account
    }

    private func save() {
        guard let amount = parsedAmount, amount > 0 else { return }
        transaction.amount = amount
        transaction.note = note
        transaction.date = date
        if transaction.kind != .transfer {
            transaction.category = category
        }
        transaction.account = account
        try? context.save()
        dismiss()
    }
}
