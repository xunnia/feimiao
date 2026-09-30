import SwiftUI
import SwiftData
import UIKit
import QingJiCore

/// 新增 / 编辑预算规则（docs/08 §6.9），和安卓 budget_rule_sheet.dart 同一套文案。
/// suggestionYuan：第一次新建时预填的近 3 月平均建议。
struct BudgetRuleEditorSheet: View {
    let bookID: UUID
    let editing: BudgetRuleRecord?
    let suggestionYuan: Int?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var ruleRecords: [BudgetRuleRecord]

    @State private var name: String
    @State private var amountText: String
    @State private var unit: BudgetRuleUnit
    @State private var dated: Bool
    @State private var start: BudgetCivilDay?
    @State private var end: BudgetCivilDay?
    @State private var funding: BudgetFunding
    @State private var pickerMonth: Int
    @State private var draftCreatedMs: Int
    @State private var saving = false
    @State private var errorText: String?
    @State private var baseEditWarning: String?
    @State private var carvePrompt: String?
    @State private var confirmDelete = false

    init(bookID: UUID, editing: BudgetRuleRecord?, suggestionYuan: Int?) {
        self.bookID = bookID
        self.editing = editing
        self.suggestionYuan = suggestionYuan
        let isSpecial = editing?.kindRaw == BudgetRuleKind.special.rawValue
        let startDay: BudgetCivilDay? = isSpecial ? editing.flatMap { BudgetCivilDay(text: $0.startDate) } : nil
        let endDay: BudgetCivilDay? = isSpecial ? editing?.endDate.flatMap { BudgetCivilDay(text: $0) } : nil
        _name = State(initialValue: editing?.name ?? "")
        _amountText = State(initialValue: editing.map { "\($0.amountCents / 100)" } ?? suggestionYuan.map { "\($0)" } ?? "")
        _unit = State(initialValue: editing.flatMap { BudgetRuleUnit(rawValue: $0.unitRaw) } ?? .month)
        _dated = State(initialValue: isSpecial)
        _start = State(initialValue: startDay)
        _end = State(initialValue: endDay)
        _funding = State(initialValue: editing?.fundingRaw.flatMap(BudgetFunding.init(rawValue:)) ?? .carve)
        _pickerMonth = State(initialValue: (startDay ?? BudgetCivilDay(AppClock.now)).monthIndex)
        _draftCreatedMs = State(initialValue: editing?.createdMs ?? BudgetRuleStore.nowMs())
    }

    private var isEdit: Bool { editing != nil }
    private var today: BudgetCivilDay { BudgetCivilDay(AppClock.now) }
    private var amountYuan: Int? {
        guard let value = Int(amountText.trimmingCharacters(in: .whitespaces)), value > 0 else { return nil }
        return value
    }
    private var rangeEnd: BudgetCivilDay? { end ?? start }

    /// 这个账本的全部规则（引擎形态）；原规则按 uuid 找回来。
    private var allRules: [BudgetRule] { BudgetRuleStore.coreRules(BudgetRuleStore.liveRecords(ruleRecords, bookID: bookID)) }
    private var originalRule: BudgetRule? {
        guard let editing else { return nil }
        let uuid = editing.stableID.uuidString.lowercased()
        return allRules.first { $0.uuid == uuid }
    }
    private var others: [BudgetRule] {
        guard let original = originalRule else { return allRules }
        return allRules.filter { !budgetSameRule($0, original) }
    }

    /// 选的日子里有没有日常预算管着；一天都没有时只能「额外多给」（§6.5）。
    private func hasBaseInRange(_ others: [BudgetRule]) -> Bool {
        guard let start, let end = rangeEnd else { return true }
        let calendar = BudgetRuleCalendar(others)
        var day = start
        while day <= end {
            if calendar.baseOwner(day) != nil { return true }
            day = day.adding(days: 1)
        }
        return false
    }

    private func effectiveFunding(_ others: [BudgetRule]) -> BudgetFunding {
        hasBaseInRange(others) ? funding : .extra
    }

    private func candidate(_ others: [BudgetRule]) -> BudgetRule? {
        guard let yuan = amountYuan else { return nil }
        let original = originalRule
        if !dated {
            return BudgetRule(
                id: original?.id ?? 0, uuid: original?.uuid ?? "", bookID: bookID.uuidString, kind: .base,
                amountCents: yuan * 100, unit: unit,
                startDate: original?.isBase == true ? original!.startDate : BudgetCivilDay(year: today.year, month: today.month, day: 1),
                createdMs: draftCreatedMs)
        }
        guard let start, let end = rangeEnd else { return nil }
        return BudgetRule(
            id: original?.id ?? 0, uuid: original?.uuid ?? "", bookID: bookID.uuidString, kind: .special,
            name: name.trimmingCharacters(in: .whitespaces), amountCents: yuan * 100, unit: unit,
            startDate: start, endDate: end, funding: effectiveFunding(others),
            colorIndex: original?.colorIndex ?? 0, createdMs: draftCreatedMs)
    }
}

// MARK: - 保存 / 删除

extension BudgetRuleEditorSheet {
    fileprivate func save(force: BudgetFunding? = nil, confirmedBaseEdit: Bool = false) {
        guard !saving else { return }
        guard let yuan = amountYuan else {
            errorText = "填一个大于 0 的整数金额"
            return
        }
        if dated && start == nil {
            errorText = "在日历上点一下开始和结束的日子"
            return
        }
        let others = self.others
        // 改的是从以前月份开始的日常预算：先说清楚会重算哪些月（§6.4）。
        if !dated, !confirmedBaseEdit, let original = originalRule,
           original.startDate < BudgetCivilDay(year: today.year, month: today.month, day: 1),
           let warning = budgetBaseEditWarning(original: original, amountCents: yuan * 100, unit: unit, today: today) {
            baseEditWarning = warning
            return
        }
        saving = true
        errorText = nil
        do {
            try BudgetRuleStore.save(
                in: context, editing: editing, bookID: bookID,
                kind: dated ? .special : .base,
                name: dated ? name : "",
                amountYuan: yuan, unit: unit,
                start: dated ? start : nil,
                end: dated ? rangeEnd : nil,
                funding: force ?? effectiveFunding(others))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch BudgetRuleSaveError.validation(let validation) {
            saving = false
            carvePrompt = budgetRuleValidationText(validation)
        } catch {
            saving = false
            errorText = (error as? LocalizedError)?.errorDescription ?? "没保存成功，再试一次"
        }
    }

    fileprivate func deleteRule() {
        guard let editing else { return }
        do {
            try BudgetRuleStore.delete(editing, in: context)
            dismiss()
        } catch {
            errorText = "没删掉，再试一次"
        }
    }

    fileprivate func tapDay(_ day: BudgetCivilDay) {
        UISelectionFeedbackGenerator().selectionChanged()
        errorText = nil
        if start == nil || end != nil {
            start = day
            end = nil
        } else if let current = start, day < current {
            start = day
            end = current
        } else {
            end = day
        }
    }

    fileprivate var rangeText: String {
        guard let start, let end = rangeEnd else { return "点一下开始的日子，再点结束的日子" }
        let days = start.days(to: end) + 1
        let head = "\(start.month)月\(start.day)日"
        if days == 1 { return "\(head) · 1 天\(self.end == nil ? "（再点一下选结束）" : "")" }
        let tail = start.month == end.month && start.year == end.year ? "\(end.day)日" : "\(end.month)月\(end.day)日"
        return "\(head)–\(tail) · \(days) 天"
    }

    fileprivate var fundingSourceLabel: String {
        if let start, let end = rangeEnd, start.year == end.year, start.month == end.month {
            return "从\(start.month)月预算里匀"
        }
        return "从月预算里匀"
    }

    fileprivate var baseCaption: String {
        if let original = originalRule, original.isBase {
            let s = original.startDate
            return "从\(s.year != today.year ? "\(s.year)年" : "")\(s.month)月起一直有效"
        }
        return others.contains(where: \.isBase)
            ? "从\(today.month)月 1 号起按这个算，之前的月份不变"
            : "从\(today.month)月 1 号起一直有效"
    }

    fileprivate var deleteMessage: String {
        originalRule?.isBase == true
            ? "它管的日子会交还给它之前的那条日常预算；前面没有就没有预算。"
            : "这几天会回到日常预算。"
    }
}

// MARK: - 界面

extension BudgetRuleEditorSheet {
    @ViewBuilder
    var body: some View {
        let others = self.others
        let candidate = self.candidate(others)
        let preview: [BudgetRulePreviewLine] = candidate
            .map { budgetRulePreview(existing: others, candidate: $0, today: today) } ?? []
        let baseWarning: String? = dated ? nil : candidate.flatMap {
            budgetBaseEditWarning(original: originalRule, amountCents: $0.amountCents, unit: unit, today: today)
        }
        let lines: [BudgetRulePreviewLine] = preview
            + (baseWarning.map { [BudgetRulePreviewLine($0, warning: true)] } ?? [])
        let hasBase = hasBaseInRange(others)
        let prefilled = !isEdit && suggestionYuan
            .map { amountText.trimmingCharacters(in: .whitespaces) == "\($0)" } ?? false
        NavigationStack {
            Form {
                Section {
                    if !isEdit {
                        Picker("有效期", selection: $dated.animation(.snappy)) {
                            Text("一直有效").tag(false)
                            Text("选日期").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("budget-rule-dated")
                    }
                    if dated {
                        TextField("名称，如 国庆出游（可以不填）", text: $name)
                            .onChange(of: name) { _, value in
                                if value.count > 20 { name = String(value.prefix(20)) }
                            }
                            .accessibilityIdentifier("budget-rule-name")
                    }
                } footer: {
                    Text(dated ? "特别安排：这几天按它算，优先于日常预算" : baseCaption)
                }

                Section {
                    HStack(spacing: 6) {
                        Text("¥").foregroundStyle(.secondary)
                        TextField("整数，如 4000", text: $amountText)
                            .keyboardType(.numberPad)
                            .onChange(of: amountText) { _, value in
                                let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(8))
                                if digits != value { amountText = digits }
                                errorText = nil
                            }
                            .accessibilityIdentifier("budget-rule-amount")
                    }
                    Picker("单位", selection: $unit) {
                        ForEach(BudgetRuleUnit.allCases, id: \.self) { value in
                            Text(budgetUnitText(value)).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("budget-rule-unit")
                } header: {
                    Text("预算")
                } footer: {
                    if prefilled { Text("按近 3 个月平均支出预填的，可以改") }
                }

                if dated {
                    Section {
                        BudgetRangeCalendar(
                            monthIndex: $pickerMonth, start: start, end: rangeEnd, today: today, onTapDay: tapDay)
                    } header: {
                        Text("日期")
                    } footer: {
                        Text(rangeText).accessibilityIdentifier("budget-rule-range-text")
                    }

                    Section {
                        if hasBase {
                            Picker("钱从哪来", selection: $funding) {
                                Text(fundingSourceLabel).tag(BudgetFunding.carve)
                                Text("额外多给").tag(BudgetFunding.extra)
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("budget-rule-funding")
                        } else {
                            Text("这几天还没有日常预算，只能额外多给")
                                .accessibilityIdentifier("budget-rule-extra-only")
                        }
                    } header: {
                        Text("钱从哪来")
                    } footer: {
                        Text(effectiveFunding(others) == .carve
                             ? "月总额不变，其余日子平均少一点"
                             : "在原来的预算上多给这笔钱，月总额变大")
                    }
                }

                if !lines.isEmpty {
                    Section("预览") {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line.text)
                                .font(.subheadline)
                                .foregroundStyle(line.warning ? Color.warning : Color.primary)
                        }
                    }
                    .accessibilityIdentifier("budget-rule-preview")
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundStyle(Color.warning)
                            .accessibilityIdentifier("budget-rule-error")
                    }
                }

                if isEdit {
                    Section {
                        Button("删除这条预算") { confirmDelete = true }
                            .foregroundStyle(Color.warning)
                            .accessibilityIdentifier("budget-rule-delete")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .liquidGlassCanvas()
            .navigationTitle(isEdit ? "编辑预算" : "新增预算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(saving)
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                        .accessibilityIdentifier("budget-rule-save")
                }
            }
            .alert("改日常预算", isPresented: Binding(
                get: { baseEditWarning != nil }, set: { if !$0 { baseEditWarning = nil } }
            )) {
                Button("取消", role: .cancel) {}
                Button("改") { save(confirmedBaseEdit: true) }
            } message: {
                Text(baseEditWarning ?? "")
            }
            .alert("改成额外多给吗？", isPresented: Binding(
                get: { carvePrompt != nil }, set: { if !$0 { carvePrompt = nil } }
            )) {
                Button("取消", role: .cancel) {}
                Button("改成额外多给") {
                    funding = .extra
                    save(force: .extra, confirmedBaseEdit: true)
                }
            } message: {
                Text(carvePrompt ?? "")
            }
            .confirmationDialog(
                "删除「\(originalRule.map(budgetRuleName) ?? "")」？",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) { deleteRule() }
                Button("取消", role: .cancel) {}
            } message: {
                Text(deleteMessage)
            }
        }
    }
}

/// 编辑页里的小日历：点一下开始、再点一下结束（§6.9「内嵌小日历点起止」）。
struct BudgetRangeCalendar: View {
    @Binding var monthIndex: Int
    let start: BudgetCivilDay?
    let end: BudgetCivilDay?
    let today: BudgetCivilDay
    let onTapDay: (BudgetCivilDay) -> Void

    private var year: Int { monthIndex / 12 }
    private var month: Int { monthIndex % 12 + 1 }

    private var cells: [BudgetCivilDay?] {
        let first = BudgetCivilDay(year: year, month: month, day: 1)
        var result: [BudgetCivilDay?] = Array(repeating: nil, count: first.weekday - 1)
        for day in 1...BudgetCivilDay.daysInMonth(year: year, month: month) {
            result.append(BudgetCivilDay(year: year, month: month, day: day))
        }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    var body: some View {
        let cells = self.cells
        VStack(spacing: 2) {
            HStack {
                Text("\(String(year))年\(month)月").font(.headline)
                Spacer()
                LiquidGlassIconButton(systemName: "chevron.left", accessibilityLabel: "上个月", size: 30) {
                    monthIndex -= 1
                }
                LiquidGlassIconButton(systemName: "chevron.right", accessibilityLabel: "下个月", size: 30) {
                    monthIndex += 1
                }
            }
            .padding(.bottom, 4)
            HStack(spacing: 0) {
                ForEach(budgetWeekdayNames, id: \.self) { name in
                    Text(name).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(stride(from: 0, to: cells.count, by: 7)), id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(row..<row + 7, id: \.self) { index in
                        if let day = cells[index] {
                            cell(day)
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: 38)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("budget-rule-range-calendar")
    }

    private func cell(_ day: BudgetCivilDay) -> some View {
        let isEdge = day == start || day == end
        let inRange = start.map { day >= $0 } == true && end.map { day <= $0 } == true
        let isToday = day == today
        return Button {
            onTapDay(day)
        } label: {
            ZStack {
                if inRange && !isEdge {
                    Rectangle().fill(Color.accentColor.opacity(0.12))
                }
                if isEdge {
                    Circle().fill(Color.accentColor).frame(width: 32, height: 32)
                }
                Text("\(day.day)")
                    .font(.system(size: 14, weight: isToday ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isEdge ? Color.white : Color.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(day.month)月\(day.day)日")
        .accessibilityAddTraits(isEdge ? .isSelected : [])
        .accessibilityIdentifier("budget-range-day-\(day.key)")
    }
}
