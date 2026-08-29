import UIKit
import SwiftUI
import SwiftData
import QingJiCore

/// 流水明细：按天分组、显示当日小计，支持搜索与左滑删除。
struct TransactionListView: View {
    let searchMode: Bool

    init(searchMode: Bool = false) {
        self.searchMode = searchMode
    }

    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \MoneyTransaction.date, order: .reverse)
    private var transactions: [MoneyTransaction]
    @Query(sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query(sort: \Tag.sortOrder)
    private var tags: [Tag]

    @State private var searchText = ""
    @State private var editingTransaction: MoneyTransaction?
    @State private var deleteError: String?
    @State private var showFilters = false
    @State private var kindFilter: TransactionKind?
    @State private var accountFilterID: UUID?
    @State private var tagFilterID: UUID?
    @State private var fromDate: Date?
    @State private var toDate: Date?
    @State private var minimumAmountText = ""
    @State private var maximumAmountText = ""
    @State private var projectionCache = IOSLedgerProjectionCache()
    @State private var listProjectionCache = TransactionListProjectionCache()

    private func makeProjection(from snapshot: IOSLedgerSnapshot) -> TransactionListProjection {
        let active = snapshot.scopedTransactions.filter { $0.refundOfID == nil }
        let calendar = Calendar.current
        let start = fromDate.map { calendar.startOfDay(for: $0) }
        let endExclusive = toDate.flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) }
        let minimumAmount = parsedAmount(minimumAmountText)
        let maximumAmount = parsedAmount(maximumAmountText)
        let query = normalizedSearchText(searchText)
        let selectedTagName = tagFilterID.flatMap { tagID in
            tags.first(where: { $0.stableID == tagID })?.name
        }
        let refundTotals = snapshot.refundTotals
        var filtered: [MoneyTransaction] = []
        filtered.reserveCapacity(active.count)
        var summary = TransactionListSummary()
        var netAmounts: [UUID: Decimal] = [:]
        netAmounts.reserveCapacity(active.count)

        for transaction in active {
            if let kindFilter, transaction.kind != kindFilter { continue }
            if let accountFilterID, transaction.account?.stableID != accountFilterID { continue }
            if let selectedTagName, !transaction.tags.contains(selectedTagName) { continue }
            if let start, transaction.date < start { continue }
            if let endExclusive, transaction.date >= endExclusive { continue }

            let netAmount = LedgerPolicy.netAmount(
                of: snapshot.record(for: transaction),
                refundTotals: refundTotals
            )
            let displayedAmount = absolute(netAmount)
            if let minimumAmount, displayedAmount < minimumAmount { continue }
            if let maximumAmount, displayedAmount > maximumAmount { continue }

            if !query.isEmpty {
                let categoryName = transaction.category?.name
                    ?? (transaction.kind == .transfer ? "转账" : "未分类")
                let searchValues = [
                    categoryName,
                    transaction.category?.key ?? "",
                    transaction.note,
                    transaction.account?.name ?? "",
                    transaction.toAccount?.name ?? "",
                    transaction.orderNo,
                    transaction.tags.joined(separator: " "),
                    transaction.amount.description,
                    netAmount.description,
                    NSDecimalNumber(decimal: transaction.amount).stringValue,
                    NSDecimalNumber(decimal: netAmount).stringValue,
                ]
                guard searchValues.contains(where: { normalizedSearchText($0).contains(query) }) else {
                    continue
                }
            }

            filtered.append(transaction)
            netAmounts[transaction.stableID] = netAmount
            guard !transaction.isExcluded else { continue }
            switch transaction.kind {
            case .expense where netAmount > 0:
                summary.expense += netAmount
                summary.expenseCount += 1
            case .income where netAmount > 0:
                summary.income += netAmount
                summary.incomeCount += 1
            default:
                break
            }
        }

        var grouped: [Date: [MoneyTransaction]] = [:]
        grouped.reserveCapacity(filtered.count)
        for transaction in filtered {
            grouped[calendar.startOfDay(for: transaction.date), default: []].append(transaction)
        }
        let sections = grouped.keys.sorted(by: >).map { day in
            let items = grouped[day] ?? []
            var expense = Decimal(0)
            var income = Decimal(0)
            for transaction in items where !transaction.isExcluded {
                let amount = netAmounts[transaction.stableID] ?? 0
                switch transaction.kind {
                case .expense:
                    expense += Swift.max(amount, Decimal.zero)
                case .income:
                    income += Swift.max(amount, Decimal.zero)
                case .transfer:
                    break
                }
            }
            return TransactionDaySection(
                day: day,
                items: items,
                expense: expense,
                income: income,
                currencyCode: items.first?.currencyCode ?? "CNY"
            )
        }

        return TransactionListProjection(
            filtered: filtered,
            summary: summary,
            sections: sections,
            refundByID: refundTotals.mapValues { $0 < 0 ? -$0 : $0 }
        )
    }

    private var hasActiveFilters: Bool {
        kindFilter != nil || accountFilterID != nil || tagFilterID != nil || fromDate != nil || toDate != nil ||
            !minimumAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !maximumAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        let snapshot = projectionCache.snapshot(
            for: transactions,
            selectedBookID: router.selectedBookID
        )
        let projection = listProjectionCache.projection(
            for: snapshot,
            filter: TransactionListFilterKey(
                searchText: normalizedSearchText(searchText),
                kind: kindFilter,
                accountID: accountFilterID,
                tagID: tagFilterID,
                tagName: tagFilterID.flatMap { tagID in
                    tags.first(where: { $0.stableID == tagID })?.name
                },
                fromDate: fromDate,
                toDate: toDate,
                minimumAmountText: minimumAmountText,
                maximumAmountText: maximumAmountText
            )
        ) {
            makeProjection(from: snapshot)
        }

        Group {
                if transactions.isEmpty {
                    ContentUnavailableView(
                        "还没有账目",
                        systemImage: "tray",
                        description: Text("去「记一笔」页开始记账吧")
                    )
                } else if projection.filtered.isEmpty {
                    ContentUnavailableView(
                        "没有匹配账目",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("试试调整搜索条件或筛选范围")
                    )
                } else {
                    list(projection)
                }
            }
            .navigationTitle(searchMode ? "搜索" : "明细")
            .modifier(
                ConditionalSearchable(
                    enabled: !searchMode,
                    text: $searchText
                )
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if searchMode {
                    TransactionSearchInput(text: $searchText)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFilters = true
                    } label: {
                        Label("筛选", systemImage: hasActiveFilters
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel(hasActiveFilters ? "已启用筛选" : "筛选账目")
                }
            }
            .sheet(item: $editingTransaction) { transaction in
                EditTransactionSheet(transaction: transaction)
            }
            .sheet(isPresented: $showFilters) {
                TransactionFilterSheet(
                    kind: kindFilter,
                    accountID: accountFilterID,
                    tagID: tagFilterID,
                    accounts: accounts,
                    tags: tags,
                    fromDate: fromDate,
                    toDate: toDate,
                    minimumAmountText: minimumAmountText,
                    maximumAmountText: maximumAmountText
                ) { values in
                    kindFilter = values.kind
                    accountFilterID = values.accountID
                    tagFilterID = values.tagID
                    fromDate = values.fromDate
                    toDate = values.toDate
                    minimumAmountText = values.minimumAmountText
                    maximumAmountText = values.maximumAmountText
                }
            }
            .alert("无法删除", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("好") { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
    }

    private func list(_ projection: TransactionListProjection) -> some View {
        List {
            if !searchText.isEmpty || hasActiveFilters {
                Section {
                    summaryCard(projection.summary)
                }
            }
            ForEach(projection.sections, id: \.day) { section in
                Section {
                    ForEach(section.items) { transaction in
                        TransactionRow(
                            transaction: transaction,
                            refundAmount: projection.refundByID[transaction.stableID] ?? 0
                        )
                            .contentShape(Rectangle())
                            .onTapGesture { editingTransaction = transaction }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            let transaction = section.items[index]
                            do {
                                try LedgerStore.delete(transaction, in: context)
                            } catch {
                                deleteError = error.localizedDescription
                            }
                        }
                    }
                } header: {
                    sectionHeader(section)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .liquidGlassCanvas()
    }

    private func summaryCard(_ summary: TransactionListSummary) -> some View {
        HStack(spacing: 0) {
            summaryColumn(
                title: "支出",
                amount: summary.expense,
                count: summary.expenseCount,
                color: .primary
            )
            Divider()
            summaryColumn(
                title: "收入",
                amount: summary.income,
                count: summary.incomeCount,
                color: .income
            )
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("筛选结果")
    }

    private func summaryColumn(title: String, amount: Decimal, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(MoneyFormat.string(amount, currencyCode: "CNY"))
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
            Text("\(count) 笔")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeader(_ section: TransactionDaySection) -> some View {
        return HStack {
            Text(section.day, format: .dateTime.month().day().weekday())
            Spacer()
            if section.expense > 0 {
                Text("支出 \(MoneyFormat.string(section.expense, currencyCode: section.currencyCode))")
            }
            if section.income > 0 {
                Text("收入 \(MoneyFormat.string(section.income, currencyCode: section.currencyCode))")
                    .foregroundStyle(Color.income)
            }
        }
        .font(.footnote)
    }

    private func parsedAmount(_ text: String) -> Decimal? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized).map { absolute($0) }
    }

    private func absolute(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
    }

    private func normalizedSearchText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "　", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private struct ConditionalSearchable: ViewModifier {
    let enabled: Bool
    @Binding var text: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $text, prompt: "搜索备注、分类、账户")
        } else {
            content
        }
    }
}

private struct TransactionSearchInput: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索备注、分类、账户", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}

private struct TransactionListSummary {
    var expense: Decimal = 0
    var expenseCount = 0
    var income: Decimal = 0
    var incomeCount = 0
}

private struct TransactionDaySection {
    let day: Date
    let items: [MoneyTransaction]
    let expense: Decimal
    let income: Decimal
    let currencyCode: String
}

private struct TransactionListProjection {
    let filtered: [MoneyTransaction]
    let summary: TransactionListSummary
    let sections: [TransactionDaySection]
    let refundByID: [UUID: Decimal]
}

private struct TransactionListFilterKey: Equatable {
    let searchText: String
    let kind: TransactionKind?
    let accountID: UUID?
    let tagID: UUID?
    let tagName: String?
    let fromDate: Date?
    let toDate: Date?
    let minimumAmountText: String
    let maximumAmountText: String
}

private final class TransactionListProjectionCache {
    private var lastRevision: IOSLedgerDataRevision?
    private var lastFilter: TransactionListFilterKey?
    private var lastProjection: TransactionListProjection?

    func projection(
        for snapshot: IOSLedgerSnapshot,
        filter: TransactionListFilterKey,
        build: () -> TransactionListProjection
    ) -> TransactionListProjection {
        if let lastProjection,
           lastRevision == snapshot.revision,
           lastFilter == filter {
            return lastProjection
        }

        let projection = build()
        lastRevision = snapshot.revision
        lastFilter = filter
        lastProjection = projection
        return projection
    }
}

private struct TransactionFilterValues {
    var kind: TransactionKind?
    var accountID: UUID?
    var tagID: UUID?
    var fromDate: Date?
    var toDate: Date?
    var minimumAmountText: String
    var maximumAmountText: String
}

private struct TransactionFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    let availableAccounts: [Account]
    let availableTags: [Tag]
    let onApply: (TransactionFilterValues) -> Void

    @State private var kind: TransactionKind?
    @State private var accountID: UUID?
    @State private var tagID: UUID?
    @State private var fromDate: Date?
    @State private var toDate: Date?
    @State private var hasFromDate: Bool
    @State private var hasToDate: Bool
    @State private var minimumAmountText: String
    @State private var maximumAmountText: String

    init(
        kind: TransactionKind?,
        accountID: UUID?,
        tagID: UUID?,
        accounts: [Account],
        tags: [Tag],
        fromDate: Date?,
        toDate: Date?,
        minimumAmountText: String,
        maximumAmountText: String,
        onApply: @escaping (TransactionFilterValues) -> Void
    ) {
        self.availableAccounts = accounts.filter { !$0.isDeleted && $0.status == .active }
        self.availableTags = tags
        self.onApply = onApply
        _kind = State(initialValue: kind)
        _accountID = State(initialValue: accountID)
        _tagID = State(initialValue: tagID)
        _fromDate = State(initialValue: fromDate)
        _toDate = State(initialValue: toDate)
        _hasFromDate = State(initialValue: fromDate != nil)
        _hasToDate = State(initialValue: toDate != nil)
        _minimumAmountText = State(initialValue: minimumAmountText)
        _maximumAmountText = State(initialValue: maximumAmountText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("类型") {
                    Picker("交易类型", selection: $kind) {
                        Text("全部").tag(TransactionKind?.none)
                        ForEach(TransactionKind.allCases, id: \.self) { item in
                            Text(kindName(item)).tag(Optional(item))
                        }
                    }
                }

                Section("账户与标签") {
                    Picker("账户", selection: $accountID) {
                        Text("全部账户").tag(UUID?.none)
                        ForEach(availableAccounts) { account in
                            Text(account.name).tag(Optional(account.stableID))
                        }
                    }
                    Picker("标签", selection: $tagID) {
                        Text("全部标签").tag(UUID?.none)
                        ForEach(availableTags) { tag in
                            Text(tag.name).tag(Optional(tag.stableID))
                        }
                    }
                }

                Section("日期") {
                    Toggle("开始日期", isOn: $hasFromDate)
                    if hasFromDate {
                        DatePicker("从", selection: fromDateBinding, displayedComponents: .date)
                    }
                    Toggle("结束日期", isOn: $hasToDate)
                    if hasToDate {
                        DatePicker("至", selection: toDateBinding, displayedComponents: .date)
                    }
                    if let fromDate, let toDate, hasFromDate, hasToDate, fromDate > toDate {
                        Text("结束日期不能早于开始日期")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("金额") {
                    TextField("最低金额", text: $minimumAmountText)
                        .keyboardType(.decimalPad)
                    TextField("最高金额", text: $maximumAmountText)
                        .keyboardType(.decimalPad)
                    if !minimumAmountText.isEmpty && parsedAmount(minimumAmountText) == nil {
                        Text("最低金额格式不正确")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if !maximumAmountText.isEmpty && parsedAmount(maximumAmountText) == nil {
                        Text("最高金额格式不正确")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if let minimum = parsedAmount(minimumAmountText),
                       let maximum = parsedAmount(maximumAmountText),
                       minimum > maximum {
                        Text("最高金额不能小于最低金额")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("清除全部筛选", role: .destructive) {
                        kind = nil
                        accountID = nil
                        tagID = nil
                        fromDate = nil
                        toDate = nil
                        hasFromDate = false
                        hasToDate = false
                        minimumAmountText = ""
                        maximumAmountText = ""
                    }
                }
            }
            .navigationTitle("筛选账目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        onApply(TransactionFilterValues(
                            kind: kind,
                            accountID: accountID,
                            tagID: tagID,
                            fromDate: hasFromDate ? fromDate : nil,
                            toDate: hasToDate ? toDate : nil,
                            minimumAmountText: minimumAmountText,
                            maximumAmountText: maximumAmountText
                        ))
                        dismiss()
                    }
                    .disabled(
                        !isValidAmount(minimumAmountText) ||
                        !isValidAmount(maximumAmountText) ||
                        !isValidRange ||
                        !isValidDateRange
                    )
                }
            }
        }
    }

    private var fromDateBinding: Binding<Date> {
        Binding(
            get: { fromDate ?? Date() },
            set: { fromDate = $0 }
        )
    }

    private var toDateBinding: Binding<Date> {
        Binding(
            get: { toDate ?? Date() },
            set: { toDate = $0 }
        )
    }

    private func parsedAmount(_ text: String) -> Decimal? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized)
    }

    private func isValidAmount(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parsedAmount(text) != nil
    }

    private var isValidRange: Bool {
        guard let minimum = parsedAmount(minimumAmountText),
              let maximum = parsedAmount(maximumAmountText) else {
            return true
        }
        return minimum <= maximum
    }

    private var isValidDateRange: Bool {
        guard hasFromDate, hasToDate, let fromDate, let toDate else { return true }
        return fromDate <= toDate
    }

    private func kindName(_ kind: TransactionKind) -> String {
        switch kind {
        case .expense: return "支出"
        case .income: return "收入"
        case .transfer: return "转账"
        }
    }
}

struct TransactionRow: View {
    let transaction: MoneyTransaction
    var refundAmount: Decimal = 0
    @AppStorage("qingji.transactionCardDisplayMode") private var displayModeRaw = TransactionCardDisplayMode.contentFirst.rawValue

    private var netAmount: Decimal {
        guard transaction.kind == .expense, transaction.amount > 0 else { return transaction.amount }
        return transaction.amount - refundAmount
    }

    var body: some View {
        let card = resolveTransactionCardText(
            mode: TransactionCardDisplayMode(rawValue: displayModeRaw) ?? .contentFirst,
            kind: transaction.kind,
            note: transaction.note,
            categoryName: transaction.category?.name ?? "",
            accountName: transaction.account?.name ?? "",
            toAccountName: transaction.toAccount?.name ?? ""
        )
        let detail = joinTransactionCardDetails([
            transactionCardTimeLabel(
                transaction.date,
                dateGrouped: true,
                precision: transaction.timePrecision
            ),
            card.secondary
        ])
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .frame(width: 36, height: 36)
                .background(Color(.secondarySystemBackground))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(.body)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if transaction.isExcluded {
                    Text("不计入收支")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if transaction.reimbursable {
                    Text("待报销")
                        .font(.caption2)
                        .foregroundStyle(Color.warning)
                }
                if !transaction.tags.isEmpty {
                    Text(transaction.tags.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if refundAmount > 0, transaction.amount > 0 {
                    Text(MoneyFormat.string(transaction.amount, currencyCode: transaction.currencyCode))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .strikethrough()
                }
                Text(amountText)
                    .font(.body.monospacedDigit().weight(.medium))
                    .foregroundStyle(amountColor)
                if refundAmount > 0 {
                    Text("已退 \(MoneyFormat.string(refundAmount, currencyCode: transaction.currencyCode))")
                        .font(.caption2)
                        .foregroundStyle(Color.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        switch transaction.kind {
        case .transfer: return "arrow.left.arrow.right"
        default: return transaction.category?.symbol ?? "tag"
        }
    }

    private var title: String {
        switch transaction.kind {
        case .transfer:
            let from = transaction.account?.name ?? "?"
            let to = transaction.toAccount?.name ?? "?"
            return "\(from) → \(to)"
        default:
            return transaction.category?.name ?? "未分类"
        }
    }

    private var amountText: String {
        let amount = netAmount
        if amount == 0 { return MoneyFormat.string(0, currencyCode: transaction.currencyCode) }
        let absolute = amount < 0 ? -amount : amount
        let text = MoneyFormat.string(absolute, currencyCode: transaction.currencyCode)
        switch transaction.kind {
        case .expense: return amount < 0 ? "+\(text)" : "-\(text)"
        case .income: return "+\(text)"
        case .transfer: return text
        }
    }

    private var amountColor: Color {
        if transaction.isExcluded { return .secondary }
        switch transaction.kind {
        case .expense: return netAmount <= 0 ? .secondary : (netAmount < transaction.amount ? Color.orange : Color.expense)
        case .income: return Color.income
        case .transfer: return .secondary
        }
    }
}
