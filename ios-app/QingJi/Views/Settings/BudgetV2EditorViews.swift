import Foundation
import SwiftData
import SwiftUI
import QingJiCore

private struct FixedTemplateDraft: Identifiable, Equatable {
    let id: String
    var name: String
    var amount: String
    var dueValue: String

    init(
        id: String = UUID().uuidString,
        name: String = "",
        amount: String = "",
        dueValue: String = "1"
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.dueValue = dueValue
    }
}

struct BudgetV2PlanEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Book.sortOrder) private var books: [Book]
    @Query(filter: #Predicate<TxCategory> { !$0.isArchived }, sort: \TxCategory.sortOrder)
    private var categories: [TxCategory]

    @State private var name = ""
    @State private var amount = ""
    @State private var bookID: UUID?
    @State private var cadence: BudgetPlanCadenceV2 = .monthly
    @State private var anchorStart = AppClock.now
    @State private var monthStartDay = 1
    @State private var weekStart = 2
    @State private var categoryAmounts: [String: String] = [:]
    @State private var fixedTemplates: [FixedTemplateDraft] = []
    @State private var message: String?

    private var expenseCategories: [TxCategory] {
        categories.filter { $0.kind == .expense && $0.parentKey == nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("计划") {
                    TextField("计划名称", text: $name)
                    TextField("周期总额", text: $amount)
                        .keyboardType(.decimalPad)
                    Picker("适用账本", selection: $bookID) {
                        Text("选择账本").tag(nil as UUID?)
                        ForEach(books) { book in
                            Text(book.name).tag(Optional(book.stableID))
                        }
                    }
                }

                Section("周期") {
                    Picker("周期类型", selection: $cadence) {
                        Text("每月").tag(BudgetPlanCadenceV2.monthly)
                        Text("每周").tag(BudgetPlanCadenceV2.weekly)
                    }
                    DatePicker("首次生效", selection: $anchorStart, displayedComponents: .date)
                    if cadence == .monthly {
                        Picker("每月起始日", selection: $monthStartDay) {
                            ForEach(1...28, id: \.self) { day in
                                Text("每月 \(day) 日").tag(day)
                            }
                        }
                    } else {
                        Picker("每周开始", selection: $weekStart) {
                            Text("周一").tag(2)
                            Text("周二").tag(3)
                            Text("周三").tag(4)
                            Text("周四").tag(5)
                            Text("周五").tag(6)
                            Text("周六").tag(7)
                            Text("周日").tag(1)
                        }
                    }
                }

                Section("分类额度") {
                    ForEach(expenseCategories) { category in
                        HStack(spacing: 10) {
                            Label("\(category.emoji) \(category.name)", systemImage: category.symbol)
                            Spacer()
                            TextField("不设", text: categoryAmountBinding(for: category.key))
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(width: 92)
                        }
                    }
                    Text("分类额度合计不能超过周期总额。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("固定承诺") {
                    if fixedTemplates.isEmpty {
                        Text("可选：房租、订阅、保险等固定支出会在每个周期单独预留。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(fixedTemplates) { template in
                        let templateID = template.id
                        let index = fixedTemplates.firstIndex(where: { $0.id == templateID }) ?? 0
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("例如 房租 / 订阅", text: Binding(
                                get: { fixedTemplates[index].name },
                                set: { fixedTemplates[index].name = $0 }
                            ))
                            HStack(spacing: 8) {
                                Text(cadence == .monthly ? "每月第" : "每周第")
                                    .foregroundStyle(.secondary)
                                TextField("1", text: Binding(
                                    get: { fixedTemplates[index].dueValue },
                                    set: { fixedTemplates[index].dueValue = $0 }
                                ))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 48)
                                Text(cadence == .monthly ? "日" : "天")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                TextField("每期金额", text: Binding(
                                    get: { fixedTemplates[index].amount },
                                    set: { fixedTemplates[index].amount = $0 }
                                ))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 96)
                            }
                            Button("删除这项", role: .destructive) {
                                fixedTemplates.removeAll { $0.id == templateID }
                            }
                            .font(.caption)
                        }
                    }
                    Button {
                        fixedTemplates.append(FixedTemplateDraft())
                    } label: {
                        Label("添加固定承诺", systemImage: "plus.circle")
                    }
                } footer: {
                    Text(cadence == .monthly
                         ? "每月日期限制为 1–28 日，避免月底周期在不同月份漂移。"
                         : "每周日期使用 1–7 表示周一至周日。固定承诺只预留预算，不会自动造账。")
                }
            }
            .navigationTitle("新建预算计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if bookID == nil { bookID = books.first?.stableID }
            }
            .alert("预算计划", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("好") { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var parsedCents: Int? {
        guard let value = Decimal(string: amount.replacingOccurrences(of: ",", with: "")), value >= 0 else { return nil }
        return MoneyNormalization.cents(value)
    }

    private var categoryBudgetCents: [String: Int] {
        categoryAmounts.compactMapValues { value in
            guard let amount = Decimal(string: value.replacingOccurrences(of: ",", with: "")), amount >= 0 else { return nil }
            return MoneyNormalization.cents(amount)
        }
    }

    private func categoryAmountBinding(for key: String) -> Binding<String> {
        Binding<String>(
            get: { categoryAmounts[key] ?? "" },
            set: { categoryAmounts[key] = $0 }
        )
    }

    private var parsedFixedTemplates: [BudgetFixedTemplateV2]? {
        let allowedDue: ClosedRange<Int> = cadence == .monthly ? 1...28 : 1...7
        return fixedTemplates.compactMap { draft -> BudgetFixedTemplateV2? in
            let cleanName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanName.isEmpty,
                  let value = Decimal(string: draft.amount.replacingOccurrences(of: ",", with: "")),
                  value > 0,
                  let due = Int(draft.dueValue.trimmingCharacters(in: .whitespacesAndNewlines)),
                  allowedDue.contains(due) else {
                return nil
            }
            return BudgetFixedTemplateV2(
                id: draft.id,
                name: cleanName,
                plannedCents: MoneyNormalization.cents(value),
                dueValue: due
            )
        }
    }

    private var canSave: Bool {
        guard let parsedCents, parsedCents > 0, bookID != nil else { return false }
        guard let parsedFixedTemplates,
              parsedFixedTemplates.count == fixedTemplates.count else { return false }
        let fixedTotal = parsedFixedTemplates.reduce(0) { $0 + $1.plannedCents }
        return categoryBudgetCents.values.reduce(0, +) + fixedTotal <= parsedCents
    }

    private func save() {
        guard let bookID, let parsedCents, parsedCents > 0 else { return }
        let now = Date()
        let plan = BudgetPlanRecord(
            bookID: bookID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            cadenceRaw: cadence.rawValue,
            anchorStart: Calendar.current.startOfDay(for: anchorStart),
            monthStartDay: cadence == .monthly ? monthStartDay : nil,
            weekStart: cadence == .weekly ? weekStart : nil
        )
        plan.createdAt = now
        plan.updatedAt = now
        let revision = BudgetPlanRevisionRecord(
            planID: plan.stableID,
            effectiveCycleStart: Calendar.current.startOfDay(for: anchorStart),
            amountCents: parsedCents
        )
        revision.categoryBudgetsJSON = encodeCents(categoryBudgetCents)
        revision.fixedTemplatesJSON = encodeFixedTemplates(parsedFixedTemplates ?? [])
        revision.createdAt = now
        revision.updatedAt = now
        let event = BudgetChangeEventRecord(
            planID: plan.stableID,
            eventType: "plan_created",
            afterJSON: "{\"amount_cents\":\(parsedCents)}"
        )
        event.createdAt = now
        context.insert(plan)
        context.insert(revision)
        context.insert(event)
        do {
            try context.save()
            try? BudgetCommitmentStore.materializeCurrent(in: context, now: AppClock.now)
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }

    private func encodeCents(_ values: [String: Int]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private func encodeFixedTemplates(_ values: [BudgetFixedTemplateV2]) -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let data = try? encoder.encode(values) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}

struct BudgetV2SpecialEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Book.sortOrder) private var books: [Book]
    @Query(filter: #Predicate<TxCategory> { !$0.isArchived }, sort: \TxCategory.sortOrder)
    private var categories: [TxCategory]

    @State private var name = ""
    @State private var amount = ""
    @State private var bookID: UUID?
    @State private var startDate = AppClock.now
    @State private var endDate = AppClock.now
    @State private var selectedCategoryKeys: Set<String> = []
    @State private var message: String?

    private var expenseCategories: [TxCategory] {
        categories.filter { $0.kind == .expense && $0.parentKey == nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("专项") {
                    TextField("专项名称", text: $name)
                    TextField("额度", text: $amount)
                        .keyboardType(.decimalPad)
                    Picker("适用账本", selection: $bookID) {
                        Text("选择账本").tag(nil as UUID?)
                        ForEach(books) { book in
                            Text(book.name).tag(Optional(book.stableID))
                        }
                    }
                }
                Section("时间范围") {
                    DatePicker("开始", selection: $startDate, displayedComponents: .date)
                    DatePicker("结束", selection: $endDate, displayedComponents: .date)
                }
                Section("追踪范围") {
                    ForEach(expenseCategories) { category in
                        Toggle(isOn: Binding(
                            get: { selectedCategoryKeys.contains(category.key) },
                            set: { isSelected in
                                if isSelected { selectedCategoryKeys.insert(category.key) }
                                else { selectedCategoryKeys.remove(category.key) }
                            }
                        )) {
                            Label("\(category.emoji) \(category.name)", systemImage: category.symbol)
                        }
                    }
                }
            }
            .navigationTitle("新建专项追踪")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if bookID == nil { bookID = books.first?.stableID }
            }
            .alert("专项追踪", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("好") { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var parsedCents: Int? {
        guard let value = Decimal(string: amount.replacingOccurrences(of: ",", with: "")), value >= 0 else { return nil }
        return MoneyNormalization.cents(value)
    }

    private var canSave: Bool {
        parsedCents != nil && bookID != nil && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !selectedCategoryKeys.isEmpty && Calendar.current.startOfDay(for: endDate) >= Calendar.current.startOfDay(for: startDate)
    }

    private func save() {
        guard let bookID, let parsedCents, canSave else { return }
        let now = Date()
        let start = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.startOfDay(for: endDate)
        let scope = BudgetExpenseScopeV2(categoryKeys: Array(selectedCategoryKeys))
        let plan = BudgetPlanRecord(
            bookID: bookID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            roleRaw: "special",
            cadenceRaw: BudgetPlanCadenceV2.oneOff.rawValue,
            anchorStart: start,
            endInclusive: end,
            expenseScopeJSON: (try? scope.jsonString()) ?? ""
        )
        plan.createdAt = now
        plan.updatedAt = now
        let revision = BudgetPlanRevisionRecord(
            planID: plan.stableID,
            effectiveCycleStart: start,
            amountCents: parsedCents
        )
        revision.createdAt = now
        revision.updatedAt = now
        let event = BudgetChangeEventRecord(planID: plan.stableID, eventType: "special_created")
        event.createdAt = now
        context.insert(plan)
        context.insert(revision)
        context.insert(event)
        do {
            try context.save()
            try? BudgetCommitmentStore.materializeCurrent(in: context, now: AppClock.now)
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}

/// 固定承诺的账单匹配页。匹配只建立关系，不修改原账单金额或日期。
struct BudgetCommitmentMatchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let occurrence: BudgetCommitmentOccurrenceRecord
    @State private var candidates: [MoneyTransaction] = []
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        "没有可匹配账单",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("只显示同一账本、币种和预算周期内的未退款支出。")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    Section("选择一笔账单") {
                        ForEach(candidates) { transaction in
                            Button {
                                match(transaction)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "yensign.circle")
                                        .foregroundStyle(Color.accentColor)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(transaction.note.isEmpty ? "未命名交易" : transaction.note)
                                            .foregroundStyle(.primary)
                                        Text("\(transaction.date.formatted(date: .abbreviated, time: .omitted)) · \(transaction.category?.name ?? "未分类")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(MoneyFormat.string(
                                        transaction.amount,
                                        currencyCode: transaction.currencyCode
                                    ))
                                        .font(.callout.monospacedDigit())
                                        .foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("匹配固定承诺")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear { reload() }
            .alert("固定承诺", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("好") { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func reload() {
        do {
            candidates = try BudgetCommitmentStore.matchCandidates(
                for: occurrence,
                in: context
            )
        } catch {
            message = error.localizedDescription
        }
    }

    private func match(_ transaction: MoneyTransaction) {
        do {
            try BudgetCommitmentStore.match(occurrence, to: transaction, in: context)
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}
