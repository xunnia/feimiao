import SwiftUI

enum AppTab: Hashable {
    case home, quickAdd, transactions, statistics, settings
}

struct RootTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        // 用 Bindable 包装 @Observable 对象，让 TabView 绑定到 router.selectedTab
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house") }
                .tag(AppTab.home)
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
        // 所有深链统一由 AppRouter 解析
        .onOpenURL { url in
            router.handle(url: url)
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(AppModelContainer.shared)
        .environment(AppRouter())
}
