import SwiftUI
import SwiftData
import QingJiCore

struct AccountsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder)
    private var accounts: [Account]

    @State private var showAddSheet = false

    var body: some View {
        List {
            ForEach(accounts) { account in
                HStack {
                    Image(systemName: account.kind.symbol)
                        .frame(width: 32)
                    VStack(alignment: .leading) {
                        Text(account.name)
                        Text(account.currencyCode)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    context.delete(accounts[index])
                }
                try? context.save()
            }
        }
        .navigationTitle("账户管理")
        .toolbar {
            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddAccountSheet(nextSortOrder: (accounts.last?.sortOrder ?? -1) + 1)
                .presentationDetents([.medium])
        }
    }
}

private struct AddAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let nextSortOrder: Int
    @State private var name = ""
    @State private var kind: AccountKind = .bankCard
    @State private var currencyCode = Locale.current.currency?.identifier ?? "CNY"

    var body: some View {
        NavigationStack {
            Form {
                TextField("账户名称", text: $name)
                Picker("类型", selection: $kind) {
                    ForEach(AccountKind.allCases, id: \.self) { kind in
                        Label(kindName(kind), systemImage: kind.symbol).tag(kind)
                    }
                }
                TextField("币种代码（如 CNY、USD）", text: $currencyCode)
                    .textInputAutocapitalization(.characters)
            }
            .navigationTitle("新增账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        context.insert(Account(
                            name: name,
                            kind: kind,
                            currencyCode: currencyCode.uppercased(),
                            sortOrder: nextSortOrder
                        ))
                        try? context.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func kindName(_ kind: AccountKind) -> LocalizedStringKey {
        switch kind {
        case .cash: return "现金"
        case .bankCard: return "储蓄卡"
        case .creditCard: return "信用卡"
        case .weChat: return "微信"
        case .alipay: return "支付宝"
        case .other: return "其他"
        }
    }
}
