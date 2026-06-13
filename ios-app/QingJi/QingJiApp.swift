import SwiftUI
import SwiftData

@main
struct QingJiApp: App {
    /// 全局路由，通过 environment 传递给子视图。
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(router)
                .task {
                    // 演示模式下 DemoDataSeeder 已在容器初始化时完成种子，
                    // 正常模式走正常首启分类/账户种子。
                    if ProcessInfo.processInfo.environment["QINGJI_DEMO"] != "1" {
                        DataSeeder.seedIfNeeded(context: AppModelContainer.shared.mainContext)
                    }
                }
        }
        .modelContainer(AppModelContainer.shared)
    }
}
