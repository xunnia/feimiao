import Foundation
import QingJiCore
import SwiftUI
import UIKit
import WidgetKit

private let appGroupID = "group.com.qingji.app"
private let snapshotFileName = "widget-snapshot.json"

struct FeimiaoWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct FeimiaoWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FeimiaoWidgetEntry {
        FeimiaoWidgetEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (FeimiaoWidgetEntry) -> Void) {
        completion(FeimiaoWidgetEntry(date: .now, snapshot: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FeimiaoWidgetEntry>) -> Void) {
        let now = Date()
        let entry = FeimiaoWidgetEntry(date: now, snapshot: loadSnapshot())
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: now)
            ?? now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func loadSnapshot() -> WidgetSnapshot {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ),
        let data = try? Data(contentsOf: container.appendingPathComponent(snapshotFileName)),
        let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
        snapshot.schemaVersion <= WidgetSnapshot.currentSchemaVersion else {
            return .empty
        }
        return snapshot
    }
}

@main
struct QingJiWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickAddWidget()
        OverviewWidget()
        PaceWidget()
        CategoriesWidget()
    }
}

struct QuickAddWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickAddWidget", provider: FeimiaoWidgetProvider()) { _ in
            VStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.tint)
                Text("记一笔")
                    .font(.headline)
            }
            .widgetURL(URL(string: "qingji://add"))
            .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("记一笔")
        .description("一键打开快记键盘，3 秒记完一笔。")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct OverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OverviewWidget", provider: FeimiaoWidgetProvider()) { entry in
            OverviewWidgetView(snapshot: entry.snapshot)
                .widgetURL(URL(string: "qingji://home"))
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("本月概览")
        .description("查看本月收支、结余和预算剩余。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

private struct OverviewWidgetView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(snapshot.budgetTitle)
                    .font(.caption.weight(.medium))
                Spacer()
                Text(snapshot.dateText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(snapshot.budgetText)
                .font(.title2.weight(.bold).monospacedDigit())
                .minimumScaleFactor(0.65)
            if family != .systemSmall {
                HStack(spacing: 12) {
                    metric("支出", snapshot.monthExpenseText)
                    metric("收入", snapshot.monthIncomeText)
                    metric("结余", snapshot.balanceText)
                }
            } else {
                Text(snapshot.budgetHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if snapshot.budgetProgress > 0 {
                ProgressView(value: Double(snapshot.budgetProgress), total: 100)
                    .tint(snapshot.budgetProgress >= 100 ? .orange : .accentColor)
            }
        }
        .padding(4)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PaceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PaceWidget", provider: FeimiaoWidgetProvider()) { entry in
            VStack(alignment: .leading, spacing: 8) {
                Text("消费节奏")
                    .font(.caption.weight(.medium))
                Text(entry.snapshot.paceCaption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("本月").font(.caption2).foregroundStyle(.secondary)
                        Text(entry.snapshot.monthExpenseText)
                            .font(.headline.monospacedDigit())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("同期平均").font(.caption2).foregroundStyle(.secondary)
                        Text(entry.snapshot.paceAverageText)
                            .font(.headline.monospacedDigit())
                    }
                }
            }
            .padding(4)
            .widgetURL(URL(string: "qingji://stats/month"))
            .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("消费节奏")
        .description("查看本月支出和历史同期平均。")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct CategoriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CategoriesWidget", provider: FeimiaoWidgetProvider()) { entry in
            VStack(alignment: .leading, spacing: 7) {
                Text("分类与支出活动")
                    .font(.caption.weight(.medium))
                if entry.snapshot.categories.isEmpty {
                    Text("本月还没有支出")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entry.snapshot.categories) { item in
                        VStack(spacing: 3) {
                            HStack {
                                Text(item.name).font(.caption)
                                Spacer()
                                Text("\(item.amountText) · \(item.percentText)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: Double(item.progress), total: 100)
                                .tint(.accentColor)
                        }
                    }
                }
            }
            .padding(4)
            .widgetURL(URL(string: "qingji://stats/month"))
            .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("分类支出")
        .description("查看本月支出最多的分类。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
