import SwiftUI
import QingJiCore

/// 预算页顶部大数字卡（docs/08 §6.8 第 2 块），文案和安卓 BudgetHeroCard 一致。
struct BudgetHeroCard: View {
    let month: BudgetMonthResult
    let today: BudgetCivilDay
    /// 近 3 个自然月平均支出（取整到百，分）；没有记录时为 nil。
    let suggestionCents: Int?
    /// 下个月会用的结余方式（过去的月份写「已留给 X月」用）。
    let nextMonthMode: BudgetRolloverMode
    let onCreate: () -> Void

    private var monthIndex: Int { month.year * 12 + month.month - 1 }
    private var prevMonth: Int { month.month == 1 ? 12 : month.month - 1 }
    private var nextMonth: Int { month.month == 12 ? 1 : month.month + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !month.hasRules {
                empty
            } else if monthIndex < today.monthIndex {
                past
            } else if monthIndex > today.monthIndex {
                future
            } else {
                current
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
        .liquidGlassSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("budget-hero-card")
    }

    private func big(_ text: String, warning: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 38, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(warning ? Color.warning : Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityIdentifier("budget-hero-amount")
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("budget-hero-label")
    }

    private func secondary(_ text: String, warning: Bool = false) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(warning ? Color.warning : Color.secondary)
            .padding(.top, 4)
    }

    private var caption: some View {
        HStack {
            Text("已花 \(budgetYuanText(month.spentCents))")
            Spacer()
            Text("\(month.month)月预算 \(budgetYuanText(month.budgetCents))")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 6)
    }

    private var bar: some View {
        BudgetHeroBar(
            spentCents: month.spentCents,
            effectiveCents: month.effectiveCents,
            plannedCents: month.today?.plannedBeforeTodayCents
        )
        .padding(.top, 12)
    }

    // MARK: 四种状态

    @ViewBuilder
    private var empty: some View {
        if monthIndex < today.monthIndex {
            label("\(month.month)月")
            Text("这个月没有设预算").font(.headline).padding(.top, 6)
        } else {
            Text("给这个月定个小目标吧").font(.headline)
            secondary(suggestionCents.map { "近 3 个月平均每月花 \(budgetYuanText($0))，可以从这个数开始" }
                ?? "先定一个每月能花多少，之后每天都能看到还剩多少")
                .padding(.top, 2)
            LiquidGlassPillButton("设个预算", prominent: true, action: onCreate)
                .padding(.top, 14)
                .accessibilityIdentifier("budget-hero-create")
        }
    }

    @ViewBuilder
    private var past: some View {
        let result = month.remainingCents
        let saved = result >= 0
        label(saved ? "\(month.month)月顺利收官，省下" : "\(month.month)月超出")
        big(budgetYuanText(budgetFloorYuanCents(abs(result))), warning: !saved)
            .padding(.top, 2)
        if saved && result > 0 && nextMonthMode != .reset {
            secondary("已留给 \(nextMonth)月")
        } else if !saved && nextMonthMode == .carryBoth {
            secondary("已从 \(nextMonth)月扣")
        }
        bar
        caption
    }

    @ViewBuilder
    private var future: some View {
        label("\(month.month)月预算")
        big(budgetYuanText(month.budgetCents)).padding(.top, 2)
        secondary("到时候按下面的规则来")
    }

    @ViewBuilder
    private var current: some View {
        let remaining = month.remainingCents
        let effective = month.effectiveCents
        let over = remaining < 0 && effective >= 0
        let covered = month.days.contains { $0.covered && $0.day.day == today.day }
        let pace = budgetPaceText(month)
        label(over ? "\(month.month)月超出" : "\(month.month)月还能花")
        big(budgetYuanText(over ? budgetFloorYuanCents(-remaining) : budgetLeftDisplayCents(remaining)), warning: over)
            .padding(.top, 2)
        if let status = month.today {
            let days = "还剩 \(status.remainingDays) 天"
            secondary(!covered
                ? "今天没有预算 · \(days)"
                : status.leftTodayCents >= 0
                    ? "今天约 \(budgetYuanText(status.leftTodayCents)) · \(days)"
                    : "今天多花了 \(budgetYuanText(-status.leftTodayCents)) · \(days)")
                .accessibilityIdentifier("budget-hero-today")
        }
        if month.carryInCents > 0 {
            secondary("\(month.month)月预算 \(budgetYuanText(month.budgetCents)) + \(prevMonth)月省下 \(budgetYuanText(month.carryInCents))")
        } else if month.carryInCents < 0 {
            secondary("\(prevMonth)月超出的 \(budgetYuanText(-month.carryInCents)) 从这个月扣")
        }
        if effective < 0 {
            secondary("\(prevMonth)月超出的还有 \(budgetYuanText(-effective)) 没扣完，这个月先省着点", warning: true)
        }
        bar
        caption
        if !pace.text.isEmpty && covered {
            let color = pace.warning ? Color.warning : Color.budgetHealthy
            Text(pace.text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(color.opacity(0.14), in: Capsule())
                .padding(.top, 10)
                .accessibilityIdentifier("budget-hero-pace")
        }
    }
}

/// 进度条（和主页同一个 BudgetGradientProgressBar）；细竖线是按计划到今天该花到哪。
struct BudgetHeroBar: View {
    let spentCents: Int
    let effectiveCents: Int
    let plannedCents: Int?

    var body: some View {
        let overflow = spentCents > effectiveCents && spentCents > 0
        let ratio: Double = effectiveCents <= 0
            ? (spentCents > 0 ? 1 : 0)
            : Double(spentCents) / Double(effectiveCents)
        let overflowStart: Double? = overflow
            ? min(1, max(0, Double(max(effectiveCents, 0)) / Double(spentCents)))
            : nil
        ZStack(alignment: .leading) {
            BudgetGradientProgressBar(value: min(1, max(0, ratio)), overflowStart: overflowStart)
            if let plannedCents, effectiveCents > 0, !overflow {
                GeometryReader { proxy in
                    let planned = min(1, max(0, Double(plannedCents) / Double(effectiveCents)))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 2, height: 16)
                        .offset(x: min(max(0, proxy.size.width * planned - 1), max(0, proxy.size.width - 2)))
                        .accessibilityIdentifier("budget-hero-plan-mark")
                }
            }
        }
        .frame(height: 16)
    }
}
