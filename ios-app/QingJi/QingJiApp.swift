import SwiftUI
import SwiftData

@main
@MainActor
struct QingJiApp: App {
    /// 全局路由，通过 environment 传递给子视图。
    @State private var router = AppRouter()
    @State private var aiProviderStore = AIProviderStore()
    @AppStorage("qingji.appearanceMode") private var appearanceModeRaw = AppAppearanceMode.system.rawValue
    @AppStorage("qingji.repaymentReminderEnabled") private var repaymentReminderEnabled = true
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BackgroundMaintenance.register()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(router)
                .environment(aiProviderStore)
                // Android parity uses the Chinese fixture labels. Keep the
                // CI screenshots language-aligned without changing the real
                // app's user-selected system locale.
                .environment(
                    \.locale,
                    ProcessInfo.processInfo.environment["QINGJI_DEMO"] == "1"
                        ? Locale(identifier: "zh-Hans")
                        : Locale.current
                )
                .task {
                    // 演示模式下 DemoDataSeeder 已在容器初始化时完成种子，
                    // 正常模式走正常首启分类/账户种子。
                    if ProcessInfo.processInfo.environment["QINGJI_DEMO"] != "1" {
                        DataSeeder.seedIfNeeded(context: AppModelContainer.shared.mainContext)
                    }
                    try? BudgetCommitmentStore.materializeCurrent(
                        in: AppModelContainer.shared.mainContext,
                        now: AppClock.now
                    )
                    try? BudgetCommitmentStore.refreshRefundReviews(
                        in: AppModelContainer.shared.mainContext
                    )
                    WidgetSnapshotWriter.write(context: AppModelContainer.shared.mainContext)
                    router.consumePendingShare()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        WidgetSnapshotWriter.write(context: AppModelContainer.shared.mainContext)
                        if repaymentReminderEnabled {
                            Task { @MainActor in
                                await RepaymentReminderScheduler.reschedule(
                                    context: AppModelContainer.shared.mainContext
                                )
                            }
                        }
                        Task { @MainActor in
                            await AIReportScheduleScheduler.rescheduleAll(
                                in: AppModelContainer.shared.mainContext
                            )
                        }
                        router.consumePendingShare()
                    } else if phase == .background {
                        BackgroundMaintenance.schedule()
                    }
                }
                .preferredColorScheme(
                    AppAppearanceMode(rawValue: appearanceModeRaw)?.colorScheme
                )
        }
        .modelContainer(AppModelContainer.shared)
    }
}
