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
    @AppThemeContext private var theme
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
    @State private var referenceDate = AppClock.now

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
    private var today: BudgetCivilDay { BudgetCivilDay(referenceDate) }
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
                name: name.trimmingCharacters(in: .whitespaces), amountCents: yuan * 100, unit: unit,
                startDate: original?.isBase == true ? original!.startDate : BudgetCivilDay(year: today.year, month: today.month, day: 1),
                createdMs: draftCreatedMs)
        }
        guard let start, let end = rangeEnd else { return nil }
        return BudgetRule(
            id: original?.id ?? 0, uuid: original?.uuid ?? "", bookID: bookID.uuidString, kind: .special,
            name: name.trimmingCharacters(in: .whitespaces), amountCents: yuan * 100, unit: unit,
            startDate: start, endDate: end, funding: effectiveFunding(others),
            colorIndex: original?.colorIndex ?? ruleRecords.filter {
                $0.bookID == bookID && $0.kindRaw == BudgetRuleKind.special.rawValue
            }.count % BudgetRuleColors.palette.count, createdMs: draftCreatedMs)
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
           let warning = budgetBaseEditWarning(original: original, amountCents: yuan * 100,
                                              unit: unit, today: today, existing: allRules) {
            baseEditWarning = warning
            return
        }
        saving = true
        errorText = nil
        do {
            try BudgetRuleStore.save(
                in: context, editing: editing, bookID: bookID,
                kind: dated ? .special : .base,
                name: name.trimmingCharacters(in: .whitespaces),
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
        let head = "\(start.year != today.year || start.year != end.year ? "\(start.year)年" : "")\(start.month)月\(start.day)日"
        if days == 1 { return "\(head) · 1 天\(self.end == nil ? "（再点一下选结束）" : "")" }
        let tail = start.month == end.month && start.year == end.year ? "\(end.day)日"
            : "\(start.year != end.year ? "\(end.year)年" : "")\(end.month)月\(end.day)日"
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
            let span = budgetRuleSpan(original, rules: allRules, today: today)
            return span.text == "没有生效过" ? span.text : "\(span.text)有效"
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
        let accent = candidate.map { $0.isBase ? Color.statisticsAccent : BudgetRuleColors.color($0) }
            ?? Color.statisticsAccent
        let preview: [BudgetRulePreviewLine] = candidate
            .map { budgetRulePreview(existing: allRules, candidate: $0, today: today) } ?? []
        let baseWarning: String? = dated ? nil : candidate.flatMap {
            budgetBaseEditWarning(original: originalRule, amountCents: $0.amountCents,
                                  unit: unit, today: today, existing: allRules)
        }
        let lines: [BudgetRulePreviewLine] = preview
            + (baseWarning.map { [BudgetRulePreviewLine($0, warning: true)] } ?? [])
        let hasBase = hasBaseInRange(others)
        let prefilled = !isEdit && suggestionYuan
            .map { amountText.trimmingCharacters(in: .whitespaces) == "\($0)" } ?? false
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AppLabeledField("名称") {
                        TextField(dated ? "如 国庆出游（可以不填）" : "日常（可以不填）", text: $name)
                            .font(.system(size: 15))
                            .padding(12)
                            .appThemeInput()
                            .onChange(of: name) { _, value in
                                if value.count > 20 { name = String(value.prefix(20)) }
                            }
                            .accessibilityIdentifier("budget-rule-name")
                    }
                    AppLabeledField("预算", helper: prefilled ? "按近 3 个月平均支出预填的，可以改" : nil) {
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
                        .font(.system(size: 15, design: .rounded))
                        .padding(12)
                        .appThemeInput()
                    }
                    AppSlidingSegment(options: BudgetRuleUnit.allCases.map {
                        AppSegmentOption(value: $0, title: budgetUnitText($0))
                    }, selection: $unit)
                    .accessibilityIdentifier("budget-rule-unit")

                    AppLabeledField("时间", helper: dated ? nil : baseCaption) {
                        if !isEdit {
                            AppSlidingSegment(options: [
                                AppSegmentOption(value: false, title: "一直有效"),
                                AppSegmentOption(value: true, title: "选日期")
                            ], selection: $dated)
                            .accessibilityIdentifier("budget-rule-dated")
                        } else {
                            Text(dated ? "选日期" : "一直有效")
                                .font(.system(size: 15)).foregroundStyle(.primary)
                        }
                    }
                    if dated {
                        BudgetRangeCalendar(
                            monthIndex: $pickerMonth, start: start, end: rangeEnd, today: today,
                            accent: accent, onTapDay: tapDay)
                            .padding(12)
                            .appThemeInput()
                        if end == nil {
                            Text(rangeText)
                                .font(.system(size: 12.5)).foregroundStyle(.secondary)
                                .accessibilityIdentifier("budget-rule-range-text")
                        }
                        AppLabeledField("钱从哪来") {
                            if hasBase {
                                AppSlidingSegment(options: [
                                    AppSegmentOption(value: BudgetFunding.carve, title: fundingSourceLabel),
                                    AppSegmentOption(value: BudgetFunding.extra, title: "额外多给")
                                ], selection: $funding)
                                .accessibilityIdentifier("budget-rule-funding")
                            } else {
                                Text("这几天还没有日常预算，只能额外多给")
                                    .font(.system(size: 15)).foregroundStyle(.primary)
                                    .accessibilityIdentifier("budget-rule-extra-only")
                            }
                        }
                    }
                    if !lines.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            if dated && end != nil {
                                Text(rangeText).font(.system(size: 13)).foregroundStyle(.primary)
                            }
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                Text(line.text)
                                    .font(.system(size: 13))
                                    .foregroundStyle(line.warning ? Color.warning : Color.primary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(accent.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityIdentifier("budget-rule-preview")
                    }
                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.warning)
                            .accessibilityIdentifier("budget-rule-error")
                    }
                }
                .padding(EdgeInsets(top: 8, leading: 20, bottom: 24, trailing: 20))
            }
            .scrollDismissesKeyboard(.interactively)
            .background(theme.sheet.ignoresSafeArea())
            .navigationTitle(isEdit ? "编辑规则" : "新增规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    LiquidGlassIconButton(systemName: "xmark", accessibilityLabel: "取消", size: 36) { dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    if isEdit {
                        LiquidGlassIconButton(systemName: "trash", accessibilityLabel: "删除这条预算", size: 32) {
                            confirmDelete = true
                        }
                        .foregroundStyle(Color.warning)
                        .accessibilityIdentifier("budget-rule-delete")
                    }
                    LiquidGlassPillButton("保存") { save() }
                        .disabled(saving)
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
        .presentationBackground(theme.sheet)
        .appRefreshOnDayChange { referenceDate = AppClock.now }
    }
}

/// 编辑页里的小日历：点一下开始、再点一下结束（§6.9「内嵌小日历点起止」）。
struct BudgetRangeCalendar: View {
    @Binding var monthIndex: Int
    let start: BudgetCivilDay?
    let end: BudgetCivilDay?
    let today: BudgetCivilDay
    var accent: Color = .statisticsAccent
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
                BudgetMonthArrow(systemName: "chevron.left", label: "上个月") {
                    monthIndex -= 1
                }
                BudgetMonthArrow(systemName: "chevron.right", label: "下个月") {
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
                    Rectangle().fill(accent.opacity(0.12))
                }
                if isEdge {
                    Circle().fill(accent).frame(width: 32, height: 32)
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
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.month)月\(day.day)日")
        .accessibilityAddTraits(isEdge ? .isSelected : [])
        .accessibilityIdentifier("budget-range-day-\(day.key)")
    }
}
