import Foundation
import SwiftUI
import SwiftData
import QingJiCore

/// 月度总预算设置。设置后快记页和统计页会显示「今日可花」。
struct BudgetSettingView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query private var budgets: [Budget]
    @Query private var transactions: [MoneyTransaction]
    @Query(filter: #Predicate<TxCategory> { !$0.isArchived }, sort: \.sortOrder)
    private var categories: [TxCategory]
    @Query(sort: \Book.sortOrder)
    private var books: [Book]
    @Query(sort: \BudgetPlanRecord.updatedAt, order: .reverse)
    private var budgetPlansV2: [BudgetPlanRecord]
    @Query(sort: \BudgetPlanRevisionRecord.effectiveCycleStart, order: .reverse)
    private var budgetRevisionsV2: [BudgetPlanRevisionRecord]
    @Query(sort: \BudgetCommitmentOccurrenceRecord.dueDate)
    private var fixedOccurrencesV2: [BudgetCommitmentOccurrenceRecord]

    @State private var amountText = ""
    @State private var cycle: BudgetCycle = .monthly
    @State private var startDate = AppClock.now
    @State private var endDate = AppClock.now
    @State private var budgetBookID: UUID?
    @State private var message: String?
    @State private var showCategoryBudgetSheet = false
    @State private var categoryBudgetKey: String?
    @State private var categoryBudgetAmountText = ""
    @State private var showBudgetPlanEditor = false
    @State private var editingBudgetPlan: BudgetPlanRecord?
    @State private var editingOverrideCurrent = false
    @State private var budgetPlanToArchive: BudgetPlanRecord?
    @State private var showArchiveBudgetPlanConfirmation = false
    @State private var showSpecialTrackingEditor = false
    @State private var matchingOccurrence: BudgetCommitmentOccurrenceRecord?

    private var totalBudget: Budget? {
        BudgetStore.effectiveTotalBudget(
            from: budgets,
            selectedBookID: router.selectedBookID,
            fallbackBookID: books.first(where: \.isDefault)?.stableID
        )
    }

    private var parsedAmount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ""))
            .map(MoneyNormalization.roundToCents)
    }

    private var currencyCode: String {
        scopedTransactions.first?.currencyCode ?? "CNY"
    }

    private var scopedTransactions: [MoneyTransaction] {
        LedgerScope.filter(transactions, selectedBookID: router.selectedBookID)
    }

    var body: some View {
        Form {
            Section {
                ForEach(activeBudgetPlansV2, id: \.stableID) { plan in
                    budgetPlanRow(plan)
                }
                HStack {
                    Button {
                        editingBudgetPlan = nil
                        editingOverrideCurrent = false
                        showBudgetPlanEditor = true
                    } label: {
                        Label("新建预算计划", systemImage: "calendar.badge.plus")
                    }
                    Spacer()
                    Button {
                        showSpecialTrackingEditor = true
                    } label: {
                        Label("专项追踪", systemImage: "scope")
                    }
                }
            } header: {
                Text("预算计划")
            } footer: {
                Text("预算计划按生效周期保存；专项追踪不会并入总预算。")
            }

            if !currentFixedOccurrences.isEmpty {
                Section {
                    ForEach(currentFixedOccurrences) { occurrence in
                        HStack(spacing: 10) {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(fixedOccurrenceName(occurrence))
                                    .font(.body.weight(.medium))
                                Text("到期 \(occurrence.dueDate, format: .dateTime.month().day()) · \(fixedOccurrenceStatus(occurrence))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(MoneyFormat.string(
                                Decimal(occurrence.plannedCents) / Decimal(100),
                                currencyCode: currencyCode
                            ))
                                .font(.callout.monospacedDigit())
                            Menu {
                                if occurrence.resolutionStatusRaw == FixedCommitmentResolutionStatus.requiresReview.rawValue {
                                    Button("确认退款复核") {
                                        do { try BudgetCommitmentStore.acceptRefundReview(occurrence, in: context) }
                                        catch { message = error.localizedDescription }
                                    }
                                }
                                if occurrence.resolutionStatusRaw == FixedCommitmentResolutionStatus.planned.rawValue {
                                    Button("匹配账单") { matchingOccurrence = occurrence }
                                    Button("跳过") {
                                        do { try BudgetCommitmentStore.skip(occurrence, in: context) }
                                        catch { message = error.localizedDescription }
                                    }
                                } else {
                                    Button("重置为待匹配") {
                                        do { try BudgetCommitmentStore.reset(occurrence, in: context) }
                                        catch { message = error.localizedDescription }
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("固定承诺操作")
                        }
                    }
                } header: {
                    Text("本周期固定承诺")
                } footer: {
                    Text("固定承诺只预留预算，不会自动创建账单；账单匹配、跳过和退款复核只改变承诺状态，不修改原账单。")
                }
            }

            Section {
                TextField("预算金额", text: $amountText)
                    .keyboardType(.decimalPad)
            }

            Section("预算周期") {
                Picker("周期", selection: $cycle) {
                    Text("每月").tag(BudgetCycle.monthly)
                    Text("每周").tag(BudgetCycle.weekly)
                    Text("自定义").tag(BudgetCycle.custom)
                }
                if cycle == .weekly {
                    DatePicker("周期参考日", selection: $startDate, displayedComponents: .date)
                } else if cycle == .custom {
                    DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                    DatePicker("结束日期", selection: $endDate, displayedComponents: .date)
                }
                Picker("适用账本", selection: $budgetBookID) {
                    Text("总账本").tag(Optional<UUID>.none)
                    ForEach(books) { book in
                        Text(book.name).tag(Optional(book.stableID))
                    }
                }
            }

            Section {
                Button("保存预算") {
                    save()
                }
                .disabled(parsedAmount == nil || parsedAmount! < 0 ||
                          (cycle == .custom && endDate < startDate))
                .liquidGlassPrimaryPillControl(horizontalPadding: 16, minHeight: 48)
                .frame(maxWidth: .infinity)
            } footer: {
                Text("设为 0 可停用计划；退款和报销会按原账单净额参与执行。")
            }

            if let budget = totalBudget, budget.amount > 0 {
                Section {
                    monthProgress(budget)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                ForEach(categoryBudgets) { budget in
                    categoryBudgetRow(budget)
                }
                Button {
                    categoryBudgetKey = nil
                    categoryBudgetAmountText = ""
                    showCategoryBudgetSheet = true
                } label: {
                    Label("添加分类预算", systemImage: "plus.circle")
                }
            } header: {
                Text("分类预算")
            } footer: {
                Text("分类预算只用于拆分查看，不会和总预算重复相加。")
            }
        }
        .scrollContentBackground(.hidden)
        .liquidGlassCanvas()
        .navigationTitle("月度预算")
        .alert("预算", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .sheet(isPresented: $showCategoryBudgetSheet) {
            categoryBudgetEditor
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showBudgetPlanEditor) {
            BudgetV2PlanEditorView(
                plan: editingBudgetPlan,
                overrideCurrent: editingOverrideCurrent
            )
        }
        .sheet(isPresented: $showSpecialTrackingEditor) {
            BudgetV2SpecialEditorView()
        }
        .sheet(item: $matchingOccurrence) { occurrence in
            BudgetCommitmentMatchView(occurrence: occurrence)
        }
        .confirmationDialog(
            "归档预算计划",
            isPresented: $showArchiveBudgetPlanConfirmation,
            titleVisibility: .visible
        ) {
            Button("归档", role: .destructive) {
                if let budgetPlanToArchive { archiveBudgetPlan(budgetPlanToArchive) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("归档只会停止后续周期，不会删除历史预算修订和固定承诺记录。")
        }
        .onAppear {
            try? BudgetCommitmentStore.materializeCurrent(in: context, now: AppClock.now)
            try? BudgetCommitmentStore.refreshRefundReviews(in: context)
            if let budget = totalBudget, budget.amount > 0 {
                amountText = "\(budget.amount)"
            }
            if let budget = totalBudget {
                cycle = budget.cycle
                startDate = budget.periodStart ?? AppClock.now
                endDate = budget.periodEnd ?? startDate
                budgetBookID = budget.bookID
            } else {
                budgetBookID = router.selectedBookID
            }
        }
    }

    private var categoryBudgets: [Budget] {
        budgets
            .filter { budget in
                budget.categoryKey != nil && budget.isActive && budget.bookID == budgetBookID
            }
            .sorted { ($0.categoryKey ?? "") < ($1.categoryKey ?? "") }
    }

    private var activeBudgetPlansV2: [BudgetPlanRecord] {
        budgetPlansV2.filter { $0.statusRaw == BudgetPlanStatusV2.active.rawValue }
    }

    private var currentFixedOccurrences: [BudgetCommitmentOccurrenceRecord] {
        guard let plan = activeBudgetPlansV2.first(where: { $0.roleRaw == "primary" }) else {
            return []
        }
        let cycle = plan.core.cycle(for: AppClock.now)
        return fixedOccurrencesV2.filter {
            $0.planID == plan.stableID &&
            Calendar.current.isDate($0.cycleStart, inSameDayAs: cycle.start)
        }
    }

    private func fixedOccurrenceStatus(_ occurrence: BudgetCommitmentOccurrenceRecord) -> String {
        switch occurrence.resolutionStatusRaw {
        case "matched": return "已匹配"
        case "skipped": return "已跳过"
        case "requires_review": return "待复核"
        default: return "待匹配"
        }
    }

    private func fixedOccurrenceName(_ occurrence: BudgetCommitmentOccurrenceRecord) -> String {
        guard let revision = budgetRevisionsV2.first(where: { $0.stableID == occurrence.revisionID }),
              let template = BudgetPlanRevisionRecord.decodeTemplates(revision.fixedTemplatesJSON)
                .first(where: { $0.id == occurrence.templateID }) else {
            return occurrence.templateID
        }
        return template.name
    }

    private func budgetPlanRow(_ plan: BudgetPlanRecord) -> some View {
        let revision = displayRevision(for: plan)
        let amount = revision.map { Decimal($0.amountCents) / Decimal(100) } ?? 0
        let fixedCount = revision.map {
            BudgetPlanRevisionRecord.decodeTemplates($0.fixedTemplatesJSON).count
        } ?? 0
        let isSpecial = plan.roleRaw == "special"
        return HStack(spacing: 12) {
            Image(systemName: isSpecial ? "scope" : "calendar")
                .foregroundStyle(isSpecial ? Color.orange : Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(plan.name.isEmpty ? (isSpecial ? "专项追踪" : "预算计划") : plan.name)
                    .font(.body.weight(.medium))
                Text(isSpecial
                     ? specialDateText(plan)
                     : cycleText(plan) + (fixedCount == 0 ? "" : " · 固定 \(fixedCount) 项"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(MoneyFormat.string(amount, currencyCode: currencyCode))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.primary)
            Menu {
                if !isSpecial {
                    Button("下周期修改") {
                        editBudgetPlan(plan, overrideCurrent: false)
                    }
                    Button("调整本周期") {
                        editBudgetPlan(plan, overrideCurrent: true)
                    }
                }
                Button("归档", role: .destructive) {
                    budgetPlanToArchive = plan
                    showArchiveBudgetPlanConfirmation = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("预算计划操作")
        }
    }

    private func displayRevision(for plan: BudgetPlanRecord) -> BudgetPlanRevisionRecord? {
        let cycle = plan.core.cycle(for: AppClock.now)
        return budgetRevisionsV2
            .filter { $0.planID == plan.stableID && $0.core.applies(to: cycle) }
            .sorted {
                if $0.effectiveCycleStart != $1.effectiveCycleStart {
                    return $0.effectiveCycleStart < $1.effectiveCycleStart
                }
                return $0.stableID.uuidString < $1.stableID.uuidString
            }
            .last
    }

    private func editBudgetPlan(_ plan: BudgetPlanRecord, overrideCurrent: Bool) {
        editingBudgetPlan = plan
        editingOverrideCurrent = overrideCurrent
        showBudgetPlanEditor = true
    }

    private func archiveBudgetPlan(_ plan: BudgetPlanRecord) {
        guard plan.statusRaw == BudgetPlanStatusV2.active.rawValue else { return }
        let now = Date()
        plan.statusRaw = BudgetPlanStatusV2.archived.rawValue
        plan.updatedAt = now
        let event = BudgetChangeEventRecord(
            planID: plan.stableID,
            eventType: "plan_archived",
            beforeJSON: "{\"status\":\"active\"}",
            afterJSON: "{\"status\":\"archived\"}"
        )
        event.createdAt = now
        context.insert(event)
        do {
            try context.save()
            budgetPlanToArchive = nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func cycleText(_ plan: BudgetPlanRecord) -> String {
        switch plan.cadenceRaw {
        case BudgetPlanCadenceV2.weekly.rawValue: return "每周 · \(bookName(for: plan))"
        case BudgetPlanCadenceV2.oneOff.rawValue: return "一次性 · \(bookName(for: plan))"
        default: return "每月 · \(bookName(for: plan))"
        }
    }

    private func specialDateText(_ plan: BudgetPlanRecord) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        let range = "\(formatter.string(from: plan.anchorStart)) - \(formatter.string(from: plan.endInclusive ?? plan.anchorStart))"
        return "\(range) · \(bookName(for: plan))"
    }

    private func bookName(for plan: BudgetPlanRecord) -> String {
        books.first(where: { $0.stableID == plan.bookID })?.name ?? "未知账本"
    }

    private func categoryBudgetRow(_ budget: Budget) -> some View {
        let category = categories.first { $0.key == budget.categoryKey && $0.kind == .expense }
        let status = BudgetStore.status(
            for: budget,
            transactions: scopedTransactions,
            categoryKey: budget.categoryKey,
            referenceDate: AppClock.now
        )
        return Button {
            categoryBudgetKey = budget.categoryKey
            categoryBudgetAmountText = "\(budget.amount)"
            showCategoryBudgetSheet = true
        } label: {
            HStack(spacing: 10) {
                CategoryIcon(
                    categoryKey: category?.key ?? "",
                    emoji: category?.emoji ?? "🏷️",
                    size: 32
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(category?.name ?? "未分类")
                        .foregroundStyle(.primary)
                    Text("已花 \(MoneyFormat.string(status.spentThisMonth, currencyCode: currencyCode))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("/ \(MoneyFormat.string(budget.amount, currencyCode: currencyCode))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(status.isOverBudget ? Color.warning : .secondary)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                budget.isActive = false
                budget.updatedAt = Date()
                try? context.save()
            } label: {
                Label("停用", systemImage: "archivebox")
            }
        }
    }

    private var categoryBudgetEditor: some View {
        NavigationStack {
            Form {
                Picker("分类", selection: $categoryBudgetKey) {
                    Text("选择分类").tag(nil as String?)
                    ForEach(categories.filter { $0.kind == .expense }) { category in
                        Label {
                            Text(category.name)
                        } icon: {
                            CategoryIcon(
                                categoryKey: category.key,
                                emoji: category.emoji,
                                size: 24
                            )
                        }
                        .tag(Optional(category.key))
                    }
                }
                TextField("预算金额", text: $categoryBudgetAmountText)
                    .keyboardType(.decimalPad)
            }
            .navigationTitle("分类预算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showCategoryBudgetSheet = false }
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveCategoryBudget() }
                        .disabled(categoryBudgetKey == nil || categoryBudgetAmount == nil || categoryBudgetAmount! < 0)
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
            }
        }
    }

    private var categoryBudgetAmount: Decimal? {
        Decimal(string: categoryBudgetAmountText.replacingOccurrences(of: ",", with: ""))
            .map(MoneyNormalization.roundToCents)
    }

    private func saveCategoryBudget() {
        guard let key = categoryBudgetKey,
              let amount = categoryBudgetAmount,
              amount >= 0 else { return }
        let existing = budgets.first { $0.categoryKey == key && $0.bookID == budgetBookID }
        let budget = existing ?? Budget(
            amount: amount,
            categoryKey: key,
            bookID: budgetBookID,
            periodStart: cycle == .monthly ? nil : startDate,
            periodEnd: cycle == .custom ? endDate : nil,
            cycleRaw: cycle.rawValue
        )
        if existing == nil { context.insert(budget) }
        budget.amount = amount
        budget.bookID = budgetBookID
        budget.cycle = cycle
        budget.periodStart = cycle == .monthly ? nil : startDate
        budget.periodEnd = cycle == .custom ? endDate : nil
        budget.isActive = amount > 0
        budget.updatedAt = Date()
        do {
            try context.save()
            showCategoryBudgetSheet = false
        } catch {
            message = error.localizedDescription
        }
    }

    /// 本月预算执行进度卡片，复用 BudgetEngine.status 计算逻辑。
    private func monthProgress(_ budget: Budget) -> some View {
        let status = BudgetStore.status(
            for: budget,
            transactions: scopedTransactions,
            referenceDate: AppClock.now
        )
        let ratio = min(max(MoneyFormat.double(status.spentThisMonth) / max(MoneyFormat.double(budget.amount), 0.01), 0), 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("当前周期进度")
                    .font(.headline)
                Spacer()
                Text("已花 \(MoneyFormat.string(status.spentThisMonth, currencyCode: currencyCode)) / \(MoneyFormat.string(budget.amount, currencyCode: currencyCode))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(status.isOverBudget ? Color.warning : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            ProgressView(value: ratio)
                .tint(status.isOverBudget ? Color.warning : Color.accentColor)
            Text(status.todayAllowance >= 0
                 ? "今日可花 \(MoneyFormat.string(status.todayAllowance, currencyCode: currencyCode))"
                 : "今日已超 \(MoneyFormat.string(-status.todayAllowance, currencyCode: currencyCode))")
                .font(.footnote)
                .foregroundStyle(status.todayAllowance >= 0 ? Color.secondary : Color.warning)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func save() {
        guard let amount = parsedAmount, amount >= 0 else { return }
        let existing = budgets.first {
            $0.categoryKey == nil && $0.bookID == budgetBookID
        }
        let budget: Budget
        if let existing {
            budget = existing
        } else {
            budget = Budget(
                amount: amount,
                bookID: budgetBookID,
                periodStart: cycle == .monthly ? nil : startDate,
                periodEnd: cycle == .custom ? endDate : nil,
                cycleRaw: cycle.rawValue
            )
            context.insert(budget)
        }
        budget.amount = amount
        budget.bookID = budgetBookID
        budget.cycle = cycle
        budget.periodStart = cycle == .monthly ? nil : startDate
        budget.periodEnd = cycle == .custom ? endDate : nil
        budget.isActive = amount > 0
        budget.updatedAt = Date()
        do {
            try context.save()
            message = amount > 0 ? "预算已保存" : "预算已停用"
        } catch {
            message = error.localizedDescription
        }
    }
}
