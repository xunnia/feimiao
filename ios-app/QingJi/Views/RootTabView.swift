import SwiftUI

enum AppTab: Hashable {
    case quickAdd, transactions, statistics, settings
}

struct RootTabView: View {
    @State private var selectedTab: AppTab = .quickAdd

    var body: some View {
        TabView(selection: $selectedTab) {
            QuickAddView()
                .tabItem { Label("记一笔", systemImage: "plus.circle.fill") }
                .tag(AppTab.quickAdd)
            TransactionListView()
                .tabItem { Label("明细", systemImage: "list.bullet") }
                .tag(AppTab.transactions)
            MonthlyStatsView()
                .tabItem { Label("统计", systemImage: "chart.pie") }
                .tag(AppTab.statistics)
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        // iOS 26 液态玻璃 TabBar：滚动时自动收起，突出内容
        .tabBarMinimizeBehavior(.onScrollDown)
        // 小组件 / 快捷指令通过 qingji://add 直达快记页
        .onOpenURL { url in
            if url.host == "add" || url.path.contains("add") {
                selectedTab = .quickAdd
            }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(AppModelContainer.shared)
}
