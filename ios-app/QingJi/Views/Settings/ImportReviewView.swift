import Foundation
import UIKit
import SwiftData
import SwiftUI
import QingJiCore

/// 导入前的逐行复核。解析、分类选择和真正入账分开，避免一份格式异常的
/// CSV 在用户还没有确认前就改变本地账本。
struct ImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AIProviderStore.self) private var providerStore
    @Query(filter: #Predicate<TxCategory> { !$0.isArchived }, sort: \.sortOrder)
    private var categories: [TxCategory]
    @Query(filter: #Predicate<Account> { !$0.isDeleted }, sort: \.sortOrder)
    private var accounts: [Account]

    let result: ImportedBillResult
    let onComplete: (Int, Int) -> Void

    /// 固定演示数据只用于双端截图和 CI；正常导入仍由文件选择器产生结果。
    static func demoResult() -> ImportedBillResult {
        let now = AppClock.now
        let calendar = Calendar.current
        func date(_ daysAgo: Int) -> Date {
            calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        }
        let order = "PARITY-ORDER-100"
        return ImportedBillResult(
            source: .alipay,
            records: [
                TransactionRecord(
                    kind: .expense,
                    amount: 280,
                    categoryKey: "shop_digital_acc",
                    note: "京东 · 机械键盘",
                    merchant: "京东-订单编号349126",
                    product: "机械键盘",
                    date: date(1),
                    timePrecision: .exact,
                    eventType: .expense,
                    orderNo: order
                ),
                TransactionRecord(
                    kind: .expense,
                    amount: 48,
                    note: "转账",
                    merchant: "M&X*^O^*",
                    date: date(2),
                    timePrecision: .exact,
                    eventType: .expense
                ),
                TransactionRecord(
                    kind: .expense,
                    amount: 26,
                    note: "日常消费",
                    merchant: "M&X*^O^*",
                    date: date(3),
                    timePrecision: .exact,
                    eventType: .expense
                ),
                TransactionRecord(
                    kind: .expense,
                    amount: -280,
                    note: "退款 · 机械键盘",
                    merchant: "京东",
                    product: "机械键盘退款",
                    date: now,
                    timePrecision: .exact,
                    eventType: .refund,
                    orderNo: order
                )
            ],
            skippedRowCount: 2
        )
    }

    @State private var selectedKeys: [UUID: String] = [:]
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var selectedAccountID: UUID?
    @State private var aiWorking = false
    @State private var aiTask: Task<Void, Never>?

    private struct ReviewGroup: Identifiable {
        let id: String
        let title: String
        let kind: TransactionKind
        let records: [TransactionRecord]
    }

    private var unresolvedCount: Int {
        result.records.filter { isUnresolved($0) }.count
    }

    private var unresolvedGroups: [ReviewGroup] {
        let grouped = Dictionary(grouping: result.records.filter { isUnresolved($0) }) { record in
            "\(record.kind.rawValue)|\(groupTitle(for: record))"
        }
        return grouped.keys.sorted().compactMap { key in
            guard let records = grouped[key], let first = records.first else { return nil }
            return ReviewGroup(
                id: key,
                title: groupTitle(for: first),
                kind: first.kind,
                records: records
            )
        }
    }

    private var sourceName: String {
        switch result.source {
        case .weChat: return "微信"
        case .alipay: return "支付宝"
        case .unknown: return "账单"
        }
    }

    private var activeAccounts: [Account] {
        accounts.filter { $0.status == .active }
    }

    private var suggestedAccount: Account? {
        switch result.source {
        case .weChat:
            return activeAccounts.first(where: { $0.kind == .weChat }) ?? activeAccounts.first
        case .alipay:
            return activeAccounts.first(where: { $0.kind == .alipay }) ?? activeAccounts.first
        case .unknown:
            return activeAccounts.first
        }
    }

    private var selectedAccount: Account? {
        activeAccounts.first(where: { $0.stableID == selectedAccountID }) ?? suggestedAccount
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("导入 \(sourceName) 账单")
                            .font(.headline)
                        Text("共 \(result.records.count) 笔，先确认分类，再写入当前账本。退款行会自动尝试挂回原订单。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            summaryPill("自动匹配", value: result.records.count - unresolvedCount, color: .accentColor)
                            summaryPill("待确认", value: unresolvedCount, color: unresolvedCount == 0 ? .secondary : .orange)
                            summaryPill("跳过", value: result.skippedRowCount, color: .secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Picker("入账账户", selection: $selectedAccountID) {
                        Text("自动选择").tag(nil as UUID?)
                        ForEach(activeAccounts) { account in
                            Text(account.name).tag(Optional(account.stableID))
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("入账账户")
                } footer: {
                    Text("导入的收支和匹配退款会作用于这个账户。")
                }

                if !unresolvedGroups.isEmpty {
                    Section("按商户批量确认") {
                        ForEach(unresolvedGroups) { group in
                            reviewGroup(group)
                        }
                    }
                }

                let matchedRecords = result.records.filter { !isUnresolved($0) }
                if !matchedRecords.isEmpty {
                    Section("已自动匹配") {
                        ForEach(matchedRecords) { record in
                            reviewRow(record)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .liquidGlassCanvas()
            .navigationTitle("导入复核")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "导入中" : "确认导入") { commit() }
                        .disabled(saving || result.records.isEmpty || selectedAccount == nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        classifyPendingGroupsWithAI()
                    } label: {
                        if aiWorking {
                            ProgressView()
                        } else {
                            Image(systemName: "sparkles")
                        }
                    }
                    .accessibilityLabel("用 AI 归类待确认商户")
                    .disabled(aiWorking || unresolvedGroups.isEmpty || providerStore.selectedAccount == nil)
                }
            }
            .onAppear {
                selectedAccountID = selectedAccountID ?? suggestedAccount?.stableID
                seedSelections()
            }
            .onDisappear {
                aiTask?.cancel()
            }
            .alert("无法导入", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func summaryPill(_ title: LocalizedStringKey, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func reviewRow(_ record: TransactionRecord) -> some View {
        let category = selectedCategory(for: record)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: record.eventType == .refund ? "arrow.uturn.backward.circle" : (record.kind == .income ? "arrow.down.circle" : "arrow.up.circle"))
                    .foregroundStyle(record.kind == .income ? Color.income : record.eventType == .refund ? Color.orange : Color.expense)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.note.isEmpty ? "未命名交易" : record.note)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(record.date, format: .dateTime.year().month().day())
                        if !record.orderNo.isEmpty {
                            Text("订单已识别")
                        }
                        if record.eventType == .refund {
                            Text("退款")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(amountText(record))
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(record.kind == .income ? Color.income : record.eventType == .refund ? Color.orange : Color.expense)
            }

            if record.eventType == .refund {
                Label(
                    record.orderNo.isEmpty ? "退款，导入时自动匹配原订单" : "退款订单 · \(record.orderNo)",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            } else {
                Menu {
                    ForEach(categoryOptions(for: record)) { option in
                        Button {
                            selectedKeys[record.id] = option.key
                        } label: {
                            if option.key == category?.key {
                                Label(option.name, systemImage: "checkmark")
                            } else {
                                Text(option.name)
                            }
                        }
                    }
                } label: {
                    categoryLabel(category, unresolved: isUnresolved(record))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 5)
    }

    private func reviewGroup(_ group: ReviewGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title)
                        .font(.subheadline.weight(.semibold))
                    Text("\(group.records.count) 笔待确认")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Menu {
                    ForEach(categoryOptions(for: group.kind)) { option in
                        Button {
                            for record in group.records {
                                selectedKeys[record.id] = option.key
                            }
                        } label: {
                            if option.key == selectedCategory(for: group.records[0])?.key {
                                Label(option.name, systemImage: "checkmark")
                            } else {
                                Text(option.name)
                            }
                        }
                    }
                } label: {
                    categoryLabel(
                        selectedCategory(for: group.records[0]),
                        unresolved: true,
                        fallback: "整组选择"
                    )
                }
                .buttonStyle(.plain)
            }
            ForEach(group.records) { record in
                reviewRow(record)
            }
        }
        .padding(.vertical, 5)
    }

    private func categoryLabel(
        _ category: TxCategory?,
        unresolved: Bool,
        fallback: String = "未分类"
    ) -> some View {
        HStack(spacing: 6) {
            CategoryIcon(
                categoryKey: category?.key ?? "",
                emoji: category?.emoji ?? "🏷️",
                size: 24
            )
            Text(category?.name ?? fallback)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
        }
        .font(.subheadline)
        .foregroundStyle(unresolved ? Color.orange : Color.accentColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            unresolved ? Color.orange.opacity(0.12) : Color.accentColor.opacity(0.12),
            in: .capsule
        )
        .overlay {
            if unresolved {
                Capsule().stroke(Color.orange.opacity(0.65), lineWidth: 1)
            }
        }
    }

    private func amountText(_ record: TransactionRecord) -> String {
        let number = NSDecimalNumber(decimal: record.amount).stringValue
        return record.amount < 0 ? "-¥\(String(number.dropFirst()))" : "¥\(number)"
    }

    private func groupTitle(for record: TransactionRecord) -> String {
        let merchant = BillCategorizer.normalizeMerchant(record.merchant)
        if !merchant.isEmpty { return merchant }
        return record.note.isEmpty ? "未识别商户" : record.note
    }

    private func categoryOptions(for record: TransactionRecord) -> [TxCategory] {
        categoryOptions(for: record.kind)
    }

    private func categoryOptions(for kind: TransactionKind) -> [TxCategory] {
        categories
            .filter { $0.kind == kind }
            .sorted {
                if ($0.parentKey == nil) != ($1.parentKey == nil) {
                    return $0.parentKey == nil
                }
                return $0.sortOrder < $1.sortOrder
            }
    }

    private func selectedCategory(for record: TransactionRecord) -> TxCategory? {
        guard let key = selectedKeys[record.id] else { return nil }
        return categories.first { $0.key == key && $0.kind == record.kind }
    }

    private func seedSelections() {
        guard selectedKeys.isEmpty else { return }
        for record in result.records {
            guard record.eventType != .refund else { continue }
            if let rememberedKey = CategoryMemoryStore.categoryKey(
                for: record.merchant,
                kind: record.kind
            ), categories.contains(where: { $0.key == rememberedKey && $0.kind == record.kind }) {
                selectedKeys[record.id] = rememberedKey
                continue
            }
            if let exact = categories.first(where: { $0.kind == record.kind && $0.key == record.categoryKey }) {
                selectedKeys[record.id] = exact.key
                continue
            }
            let guess = BillCategorizer.classify(
                merchant: record.merchant,
                product: record.product,
                note: record.note,
                kind: record.kind
            )
            if let guessedKey = guess.key,
               categories.contains(where: { $0.key == guessedKey && $0.kind == record.kind }) {
                selectedKeys[record.id] = guessedKey
                continue
            }
            if let named = categories.first(where: {
                $0.kind == record.kind && !record.categoryName.isEmpty &&
                    ($0.name == record.categoryName || $0.name.contains(record.categoryName) || record.categoryName.contains($0.name))
            }) {
                selectedKeys[record.id] = named.key
                continue
            }
            let fallback = record.kind == .income ? "otherIncome" : CategorySeed.fallbackExpenseKey
            if let fallback = categories.first(where: { $0.kind == record.kind && $0.key == fallback }) {
                selectedKeys[record.id] = fallback.key
            }
        }
    }

    private func isUnresolved(_ record: TransactionRecord) -> Bool {
        guard record.eventType != .refund else { return false }
        guard let category = selectedCategory(for: record) else { return true }
        let fallback = record.kind == .income ? "otherIncome" : CategorySeed.fallbackExpenseKey
        return category.key == fallback && record.categoryKey.isEmpty && record.categoryName.isEmpty
    }

    private func commit() {
        guard !saving else { return }
        saving = true
        var records = result.records
        var learnedMerchants: [(merchant: String, kind: TransactionKind, categoryKey: String)] = []
        for index in records.indices {
            guard let category = selectedCategory(for: records[index]) else { continue }
            records[index].categoryKey = category.key
            records[index].categoryName = category.name
            records[index].topCategoryKey = category.parentKey ?? category.key
            records[index].topCategoryName = category.parentKey.flatMap { key in
                categories.first(where: { $0.key == key && $0.kind == records[index].kind })?.name
            } ?? category.name
            learnedMerchants.append((records[index].merchant, records[index].kind, category.key))
        }
        let updated = ImportedBillResult(
            source: result.source,
            records: records,
            skippedRowCount: result.skippedRowCount
        )
        do {
            let count = try BillRecordSaver.save(updated, account: selectedAccount, context: context)
            for item in learnedMerchants {
                CategoryMemoryStore.learn(
                    merchant: item.merchant,
                    kind: item.kind,
                    categoryKey: item.categoryKey
                )
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onComplete(count, result.skippedRowCount)
            dismiss()
        } catch {
            saving = false
            errorMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    private func classifyPendingGroupsWithAI() {
        guard !aiWorking,
              let account = providerStore.selectedAccount else { return }
        let groups = unresolvedGroups
        guard !groups.isEmpty else { return }
        let categoryList = categories
            .filter { $0.kind == .expense }
            .map { "\($0.key)=\($0.name)" }
            .joined(separator: "、")
        let examples = groups.map { group in
            let products = group.records
                .map(\.product)
                .filter { !$0.isEmpty }
                .prefix(2)
                .joined(separator: " / ")
            return "商户：\(group.title)；商品：\(products.isEmpty ? "无" : products)"
        }.joined(separator: "\n")
        aiWorking = true
        aiTask = Task { @MainActor in
            defer {
                aiWorking = false
                aiTask = nil
            }
            do {
                var output = ""
                _ = try await providerStore.stream(
                    account: account,
                    messages: [
                        AIChatTurn(
                            role: "system",
                            content: "你是账单分类器。只输出 JSON 对象，键必须是输入商户名，值只能是给定分类 key；信息不足时选择安全的顶级分类，不要输出 Markdown。给定分类：\(categoryList)"
                        ),
                        AIChatTurn(role: "user", content: examples)
                    ],
                    onText: { output += $0 }
                )
                guard !Task.isCancelled,
                      let mapping = parseAIClassification(output) else {
                    throw AIProviderError.invalidResponse
                }
                var changed = 0
                for group in groups {
                    guard let key = mapping[group.title],
                          categories.contains(where: { $0.key == key && $0.kind == group.kind }) else {
                        continue
                    }
                    for record in group.records {
                        selectedKeys[record.id] = key
                    }
                    changed += 1
                }
                if changed == 0 { throw AIProviderError.invalidResponse }
            } catch is CancellationError {
                return
            } catch {
                errorMessage = "AI 归类失败：\(error.localizedDescription)"
            }
        }
    }

    private func parseAIClassification(_ output: String) -> [String: String]? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"), start <= end,
              let data = String(trimmed[start...end]).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let mapping = object.compactMapValues { $0 as? String }
        return mapping.isEmpty ? nil : mapping
    }
}
