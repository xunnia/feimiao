import SwiftUI
import SwiftData
import UIKit
import QingJiCore

/// 预算页（docs/08 §6.8）：大数字卡、日历、规则列表、月底结余。只按自然月看。
/// 和安卓 lib/views/budget/budget_view.dart 同一套结构和文案。
struct BudgetView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router

    @Query(sort: \Book.sortOrder) private var books: [Book]
    @Query private var ruleRecords: [BudgetRuleRecord]
    @Query private var rolloverRecords: [BudgetRolloverChangeRecord]
    @Query private var transactions: [MoneyTransaction]

    /// 页内切换的账本；没切过就跟着当前账本（nil = 总账本）。
    @State private var pickedBook = false
    @State private var pickedBookID: UUID?
    @State private var monthIndex: Int = BudgetCivilDay(AppClock.now).monthIndex
    @State private var referenceDate = AppClock.now
    @State private var showEnded = false
    @State private var editor: BudgetRuleEditorTarget?
    @State private var dayTarget: BudgetDayTarget?
    @State private var errorMessage: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var scopeBookID: UUID? { pickedBook ? pickedBookID : router.selectedBookID }
    private var year: Int { monthIndex / 12 }
    private var month: Int { monthIndex % 12 + 1 }

    private var bookName: String {
        if let id = scopeBookID, let book = books.first(where: { $0.stableID == id }) { return book.name }
        return "总账本"
    }

    private func monthSnapshot(year: Int, month: Int) -> BudgetRuleSnapshot {
        BudgetRuleStore.snapshot(
            rules: ruleRecords, rollovers: rolloverRecords, selectedBookID: scopeBookID,
            books: books, transactions: transactions, year: year, month: month, now: referenceDate)
    }

    var body: some View {
        let snapshot = monthSnapshot(year: year, month: month)
        Group {
            if let bookID = snapshot.bookID {
                content(snapshot: snapshot, bookID: bookID)
            } else {
                ContentUnavailableView("先建一个账本再设预算", systemImage: "book.closed")
            }
        }
        .liquidGlassCanvas()
        .navigationTitle("预算")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                bookMenu
                LiquidGlassIconButton(systemName: "plus", accessibilityLabel: "新增预算", size: 32) {
                    openEditor(bookID: snapshot.bookID, record: nil, hasRules: !liveRecords(snapshot.bookID).isEmpty)
                }
                .disabled(snapshot.bookID == nil)
                .accessibilityLabel("新增预算")
                .accessibilityIdentifier("budget-add-rule")
            }
        }
        .sheet(item: $editor) { target in
            BudgetRuleEditorSheet(bookID: target.bookID, editing: target.record, suggestionYuan: target.suggestionYuan)
        }
        .sheet(item: $dayTarget) { target in
            BudgetDaySheet(selectedBookID: scopeBookID, day: target.day)
                .presentationDetents([.medium, .large])
        }
        .alert("没保存成功", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .appRefreshOnDayChange(refreshDate)
    }

    private var bookMenu: some View {
        AppSelectionMenu(selected: scopeBookID, options: DrawerLayout.orderedBooks(books).map { book in
            AppMenuOption<UUID?>(value: book.isDefault ? nil : book.stableID,
                                 title: book.name, systemName: "book.closed")
        }, onSelect: { value in
            pickedBook = true
            pickedBookID = value
        }) {
            HStack(spacing: 5) {
                Image(systemName: "book.closed")
                Text(bookName).lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
            .font(.subheadline.weight(.medium))
        }
        .tint(.primary)
        .accessibilityLabel("当前账本：\(bookName)")
        .accessibilityIdentifier("budget-book-chip")
    }

    private func refreshDate() {
        let now = AppClock.now
        let previous = BudgetCivilDay(referenceDate)
        let current = BudgetCivilDay(now)
        guard previous != current else { return }
        monthIndex = BudgetMonthNavigation.refreshedMonthIndex(displayed: monthIndex,
                                                               previousToday: previous, currentToday: current)
        referenceDate = now
    }

    private func liveRecords(_ bookID: UUID?) -> [BudgetRuleRecord] {
        guard let bookID else { return [] }
        return BudgetRuleStore.liveRecords(ruleRecords, bookID: bookID)
    }

    private func openEditor(bookID: UUID?, record: BudgetRuleRecord?, hasRules: Bool) {
        guard let bookID else { return }
        editor = BudgetRuleEditorTarget(
            bookID: bookID, record: record,
            suggestionYuan: record == nil && !hasRules ? suggestionYuan() : nil)
    }

    /// 近 3 个自然月（不含本月）有支出的月份平均，取整到百元，最少 100；没有支出返回 nil。
    private func suggestionYuan() -> Int? {
        BudgetRuleStore.suggestionYuan(transactions: transactions, selectedBookID: scopeBookID,
                                       now: referenceDate)
    }

    private func step(_ delta: Int) {
        UISelectionFeedbackGenerator().selectionChanged()
        monthIndex += delta
    }
}

enum BudgetMonthNavigation {
    static func refreshedMonthIndex(displayed: Int, previousToday: BudgetCivilDay,
                                    currentToday: BudgetCivilDay) -> Int {
        displayed == previousToday.monthIndex ? currentToday.monthIndex : displayed
    }
}

struct BudgetRuleEditorTarget: Identifiable {
    let id = UUID()
    let bookID: UUID
    let record: BudgetRuleRecord?
    let suggestionYuan: Int?
}

struct BudgetDayTarget: Identifiable {
    let day: BudgetCivilDay
    var id: Int { day.key }
}

// MARK: - 内容

extension BudgetView {
    @ViewBuilder
    fileprivate func content(snapshot: BudgetRuleSnapshot, bookID: UUID) -> some View {
        let result = snapshot.month
        let today = snapshot.today
        let records = liveRecords(bookID)
        let rules = BudgetRuleStore.coreRules(records)
        let next = monthIndex + 1
        let nextMode = BudgetRuleStore.rolloverMode(
            BudgetRuleStore.coreRollovers(rolloverRecords, bookID: bookID), year: next / 12, month: next % 12 + 1)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    BudgetHeroCard(
                        month: result,
                        today: today,
                        suggestionCents: result.hasRules ? nil : suggestionYuan().map { $0 * 100 },
                        nextMonthMode: nextMode,
                        onCreate: { openEditor(bookID: bookID, record: nil, hasRules: !records.isEmpty) }
                    )
                    if snapshot.excludedForeignCount > 0 {
                        Text("有 \(snapshot.excludedForeignCount) 笔外币支出没算进预算")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                    }
                }
                BudgetCalendarCard(
                    year: result.year,
                    month: result.month,
                    days: result.days,
                    spendByDay: snapshot.spendByDay,
                    today: today,
                    onPrev: { step(-1) },
                    onNext: { step(1) },
                    onTapDay: { info in dayTarget = BudgetDayTarget(day: info.day) }
                )
                ruleSection(rules: rules, records: records, bookID: bookID, today: today)
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 32, trailing: 16))
        }
        .accessibilityIdentifier("budget-view-list")
    }

    @ViewBuilder
    fileprivate func ruleSection(rules: [BudgetRule], records: [BudgetRuleRecord], bookID: UUID,
                                 today: BudgetCivilDay) -> some View {
        let sorted = budgetRulesNewestFirst(rules)
        let spans = Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, budgetRuleSpan($0, rules: rules, today: today)) })
        let live = sorted.filter { spans[$0.id]?.state != .ended }
        let ended = sorted.filter { spans[$0.id]?.state == .ended }
        VStack(alignment: .leading, spacing: 6) {
            Text("预算规则")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 4)
            VStack(spacing: 0) {
                ForEach(Array(live.enumerated()), id: \.element.id) { index, rule in
                    if index > 0 { Divider().padding(.leading, 40) }
                    ruleRow(rule, span: spans[rule.id], records: records, bookID: bookID)
                }
                if !ended.isEmpty {
                    if !live.isEmpty { Divider().padding(.leading, 16) }
                    Button {
                        withAnimation(.snappy) { showEnded.toggle() }
                    } label: {
                        HStack {
                            Text("已结束 \(ended.count) 条").foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: showEnded ? "chevron.up" : "chevron.down")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("budget-ended-toggle")
                    if showEnded {
                        ForEach(ended, id: \.id) { rule in
                            Divider().padding(.leading, 40)
                            ruleRow(rule, span: spans[rule.id], records: records, bookID: bookID)
                        }
                    }
                }
                if !sorted.isEmpty { Divider().padding(.leading, 40) }
                rolloverRow(bookID: bookID)
            }
            .appThemeCard(cornerRadius: 22)
            if rules.contains(where: { !$0.isBase }) {
                Text("日期重叠时，以后加的特别安排为准")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.top, 2)
            }
        }
    }

    fileprivate func ruleRow(_ rule: BudgetRule, span: BudgetRuleSpan?, records: [BudgetRuleRecord],
                             bookID: UUID) -> some View {
        Button {
            openEditor(bookID: bookID, record: BudgetRuleStore.record(for: rule, in: records), hasRules: true)
        } label: {
            HStack(spacing: 14) {
                BudgetRuleDot(color: BudgetRuleColors.color(rule))
                VStack(alignment: .leading, spacing: 2) {
                    Text(budgetRuleName(rule))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(span?.text ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if span?.state == .upcoming {
                        Text("即将开始").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if typeSize >= .xxxLarge {
                        Text(budgetRuleAmountText(rule))
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                Spacer(minLength: 8)
                if typeSize < .xxxLarge {
                    Text(budgetRuleAmountText(rule))
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.trailing)
                        .layoutPriority(1)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("budget-rule-row-\(rule.id)")
    }
}

// MARK: - 月底结余

extension BudgetView {
    fileprivate static func rolloverName(_ mode: BudgetRolloverMode) -> String {
        switch mode {
        case .reset: return "每月重新开始"
        case .keepSavings: return "省下的留给下个月"
        case .carryBoth: return "多退少补"
        }
    }

    fileprivate func rolloverRow(bookID: UUID) -> some View {
        let now = BudgetCivilDay(referenceDate)
        let changes = BudgetRuleStore.coreRollovers(rolloverRecords, bookID: bookID)
        let current = BudgetRuleStore.rolloverMode(changes, year: now.year, month: now.month)
        let prevIndex = now.monthIndex - 1
        let last = monthSnapshot(year: prevIndex / 12, month: prevIndex % 12 + 1).month
        // 例子用用户自己上个月的结果；上个月没预算时举个 ¥300 / ¥120 的例子。
        let result: Int? = last.hasRules ? last.remainingCents : nil
        let pm = prevIndex % 12 + 1
        let cm = now.month
        let keepExample: String = {
            guard let result else { return "比如\(pm)月省下 ¥300，\(cm)月就多 ¥300；超了不扣" }
            if result > 0 { return "\(pm)月省下 \(budgetYuanText(result))，\(cm)月就多 \(budgetYuanText(result))" }
            return "\(pm)月超出 \(budgetYuanText(-result))，只留省下的，\(cm)月不扣"
        }()
        let carryExample: String = {
            guard let result else { return "比如\(pm)月超出 ¥120，\(cm)月就少 ¥120；省下的也带过来" }
            if result >= 0 { return "\(pm)月省下 \(budgetYuanText(result))，\(cm)月就多 \(budgetYuanText(result))" }
            return "\(pm)月超出 \(budgetYuanText(-result))，\(cm)月就少 \(budgetYuanText(-result))"
        }()
        let options: [AppMenuOption<BudgetRolloverMode>] = [
            AppMenuOption(value: .reset, title: Self.rolloverName(.reset),
                          subtitle: "每个月从头算，上个月省下或超出都不影响", systemName: "arrow.clockwise", identifier: "budget-rollover-reset"),
            AppMenuOption(value: .keepSavings, title: Self.rolloverName(.keepSavings),
                          subtitle: keepExample, systemName: "arrow.turn.down.right", identifier: "budget-rollover-keep"),
            AppMenuOption(value: .carryBoth, title: Self.rolloverName(.carryBoth),
                          subtitle: carryExample, systemName: "arrow.left.arrow.right", identifier: "budget-rollover-carry"),
        ]
        return AppSelectionMenu(selected: current, options: options,
                                onSelect: { pickRollover($0, bookID: bookID) }) {
            HStack {
                Color.clear.frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("月底结余").font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    Text(Self.rolloverName(current)).foregroundStyle(.secondary).font(.caption)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .tint(.primary)
        .accessibilityIdentifier("budget-rollover-row")
    }

    fileprivate func pickRollover(_ mode: BudgetRolloverMode, bookID: UUID) {
        UISelectionFeedbackGenerator().selectionChanged()
        do {
            try BudgetRuleStore.setRolloverMode(mode, bookID: bookID, in: context)
        } catch {
            errorMessage = "月底结余没改成，再试一次"
        }
    }
}
