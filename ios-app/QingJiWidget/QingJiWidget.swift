import UIKit
import WidgetKit
import SwiftUI

@main
struct QingJiWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickAddWidget()
    }
}

/// 锁屏 / 桌面快记入口：点一下直达快记键盘（qingji://add）。
struct QuickAddWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickAddWidget", provider: QuickAddProvider()) { _ in
            QuickAddWidgetView()
                .widgetURL(URL(string: "qingji://add"))
        }
        .configurationDisplayName("记一笔")
        .description("一键打开快记键盘，3 秒记完一笔。")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct QuickAddEntry: TimelineEntry {
    let date: Date
}

struct QuickAddProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickAddEntry {
        QuickAddEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickAddEntry) -> Void) {
        completion(QuickAddEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickAddEntry>) -> Void) {
        completion(Timeline(entries: [QuickAddEntry(date: .now)], policy: .never))
    }
}

struct QuickAddWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Image(systemName: "plus.circle.fill")
                    .font(.title)
            case .accessoryRectangular:
                Label("记一笔", systemImage: "plus.circle.fill")
                    .font(.headline)
            default:
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.tint)
                    Text("记一笔")
                        .font(.headline)
                }
            }
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }
}
