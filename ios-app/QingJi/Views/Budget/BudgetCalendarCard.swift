import SwiftUI
import QingJiCore

/// 特别安排的颜色：按新建顺序轮流取蓝、紫、粉、青、灰蓝（docs/08 §6.2），和安卓 budgetRulePalette 同一组色值。
/// 不用绿（预算健康）、金（收入）、橙（超支）。
enum BudgetRuleColors {
    static let palette: [Color] = [
        Color(red: 0x5C / 255, green: 0x8D / 255, blue: 0xD4 / 255),
        Color(red: 0x9C / 255, green: 0x7F / 255, blue: 0xD0 / 255),
        Color(red: 0xD0 / 255, green: 0x8B / 255, blue: 0xB0 / 255),
        Color(red: 0x4F / 255, green: 0xA3 / 255, blue: 0xB3 / 255),
        Color(red: 0x7F / 255, green: 0x93 / 255, blue: 0xAE / 255),
    ]

    /// 日常预算不画色条，点用灰。
    static func color(_ rule: BudgetRule) -> Color {
        rule.isBase ? Color.secondary.opacity(0.6) : palette[((rule.colorIndex % palette.count) + palette.count) % palette.count]
    }
}

struct BudgetRuleDot: View {
    let color: Color
    var size: CGFloat = 10

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

/// 周一开头的星期标题。
let budgetWeekdayNames = ["一", "二", "三", "四", "五", "六", "日"]

/// 预算页的大日历（docs/08 §6.8 第 3 块）：周一开头；过去的日子写当天已花，
/// 超当天日历预算显示橙色；今天实心圆；以后留空；特别安排画彩色条和名字。
struct BudgetCalendarCard: View {
    let year: Int
    let month: Int
    let days: [BudgetDayInfo]
    let spendByDay: [Int: Int]
    let today: BudgetCivilDay
    let onPrev: () -> Void
    let onNext: () -> Void
    let onTapDay: (BudgetDayInfo) -> Void

    private var weeks: [[BudgetDayInfo?]] {
        guard let first = days.first else { return [] }
        var cells: [BudgetDayInfo?] = Array(repeating: nil, count: first.day.weekday - 1)
        cells.append(contentsOf: days.map { Optional($0) })
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(year == today.year ? "\(month)月" : "\(String(year))年\(month)月")
                    .font(.headline)
                Spacer()
                BudgetMonthArrow(systemName: "chevron.left", label: "上个月", action: onPrev)
                BudgetMonthArrow(systemName: "chevron.right", label: "下个月", action: onNext)
            }
            .padding(.leading, 4)
            HStack(spacing: 0) {
                ForEach(budgetWeekdayNames, id: \.self) { name in
                    Text(name).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 4)
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                BudgetCalendarWeekRow(week: week, spendByDay: spendByDay, today: today, onTapDay: onTapDay)
            }
            Text("数字是当天花了多少，橙色表示当天超了")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12))
        .appThemeCard()
        .accessibilityIdentifier("budget-calendar-card")
    }
}

struct BudgetMonthArrow: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct BudgetCalendarWeekRow: View {
    let week: [BudgetDayInfo?]
    let spendByDay: [Int: Int]
    let today: BudgetCivilDay
    let onTapDay: (BudgetDayInfo) -> Void

    private struct Bar: Identifiable {
        let from: Int
        var to: Int
        let rule: BudgetRule
        var id: Int { from }
    }

    /// 同一条特别安排连续的几天合成一段色条。
    private var bars: [Bar] {
        var result: [Bar] = []
        for (index, info) in week.enumerated() {
            guard let rule = info?.specialRule else { continue }
            if let last = result.last, last.to == index - 1, budgetSameRule(last.rule, rule) {
                result[result.count - 1].to = index
            } else {
                result.append(Bar(from: index, to: index, rule: rule))
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    if let info = week[index] {
                        BudgetCalendarDayCell(info: info, spentCents: spendByDay[info.day.key] ?? 0, today: today) {
                            onTapDay(info)
                        }
                    } else {
                        Color.clear.frame(maxWidth: .infinity).frame(height: 46)
                    }
                }
            }
            .padding(.top, 4)
            let bars = self.bars
            if !bars.isEmpty {
                GeometryReader { proxy in
                    let cell = proxy.size.width / 7
                    ForEach(bars) { bar in
                        let color = BudgetRuleColors.color(bar.rule)
                        Text(budgetRuleName(bar.rule))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(color)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .frame(width: CGFloat(bar.to - bar.from + 1) * cell - 4, height: 18, alignment: .leading)
                            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .clipped()
                            .offset(x: CGFloat(bar.from) * cell + 2)
                    }
                }
                .frame(height: 18)
            }
        }
        .padding(.bottom, 4)
    }
}

private struct BudgetCalendarDayCell: View {
    let info: BudgetDayInfo
    let spentCents: Int
    let today: BudgetCivilDay
    let action: () -> Void

    var body: some View {
        let isToday = info.day == today
        let isPast = info.day < today
        let weekend = info.day.weekday >= 6
        let over = info.covered && spentCents > info.budgetCents
        let sub: String? = isToday
            ? "今天"
            : (isPast && info.covered && spentCents >= 100 ? "\(spentCents / 100)" : nil)
        let subColor: Color = isToday ? .accentColor : (over && !isToday ? .warning : .secondary)
        Button(action: action) {
            VStack(spacing: 0) {
                Text("\(info.day.day)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(isToday ? Color.white : (weekend ? Color.secondary : Color.primary))
                    .frame(width: 28, height: 28)
                    .background {
                        if isToday { Circle().fill(Color.accentColor) }
                    }
                Text(sub ?? " ")
                    .font(.system(size: 11, weight: over || isToday ? .semibold : .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(subColor)
                    .frame(height: 14)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText(sub: sub, over: over))
        .accessibilityIdentifier("budget-day-\(info.day.key)")
    }

    private func accessibilityText(sub: String?, over: Bool) -> String {
        var text = "\(info.day.month)月\(info.day.day)日"
        if info.day == today { text += "，今天" }
        if let sub, info.day != today { text += "，花了 \(sub) 元" }
        if over { text += "，超了" }
        return text
    }
}
