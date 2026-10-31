import SwiftUI
import SwiftData

@main
@MainActor
struct QingJiApp: App {
    /// 全局路由，通过 environment 传递给子视图。
    @State private var router = AppRouter()
    @State private var aiProviderStore = AIProviderStore()
    @State private var database = DatabaseStartupState()
    @AppStorage("qingji.appearanceMode") private var appearanceModeRaw = AppAppearanceMode.system.rawValue
    @AppStorage("qingji.themePreset") private var themePresetRaw = AppThemePreset.warm.rawValue
    @AppStorage("qingji.repaymentReminderEnabled") private var repaymentReminderEnabled = true
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BackgroundMaintenance.register()
    }

    var body: some Scene {
        WindowGroup {
          Group {
            if let container = database.container {
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
                        DataSeeder.seedIfNeeded(context: container.mainContext)
                    }
                    // 预算规则模型（docs/08 §6.12）：旧预算只迁一次到新规则表。
                    BudgetRuleStore.migrateIfNeeded(in: container.mainContext)
                    try? RecurringStore.materializeDue(
                        in: container.mainContext,
                        now: AppClock.now
                    )
                    WidgetSnapshotWriter.write(context: container.mainContext)
                    router.consumePendingShare()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        try? RecurringStore.materializeDue(
                            in: container.mainContext,
                            now: AppClock.now
                        )
                        WidgetSnapshotWriter.write(context: container.mainContext)
                        if repaymentReminderEnabled {
                            Task { @MainActor in
                                await RepaymentReminderScheduler.reschedule(
                                    context: container.mainContext
                                )
                            }
                        }
                        Task { @MainActor in
                            await AIReportScheduleScheduler.rescheduleAll(
                                in: container.mainContext
                            )
                        }
                        router.consumePendingShare()
                    } else if phase == .background {
                        BackgroundMaintenance.schedule()
                    }
                }
                .modelContainer(container)
            } else if database.failed {
                ContentUnavailableView {
                    Label("暂时无法打开账本", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("没有创建空账本替换原数据。请确认设备存储空间充足后重试；若仍失败，请保留本机数据和已有备份，联系支持协助恢复。不要卸载 App。")
                } actions: {
                    Button("重新打开账本") { database.open() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView("正在打开账本")
            }
          }
          .task { database.open() }
          .preferredColorScheme(
                    AppThemePreferences(presetKey: themePresetRaw, intensity: 1,
                                        cardAlpha: AppThemePreferences.defaultCardAlpha)
                        .colorScheme(appearanceMode: AppAppearanceMode(rawValue: appearanceModeRaw) ?? .system)
                )
        }
    }
}

/// Opening errors stay outside the ledger UI. Keeping the opener injectable
/// lets tests verify retry without replacing or deleting a user's store.
@MainActor
@Observable
final class DatabaseStartupState {
    private(set) var container: ModelContainer?
    private(set) var failed = false
    private let opener: () throws -> ModelContainer

    init(opener: @escaping () throws -> ModelContainer = { try AppModelContainer.shared }) {
        self.opener = opener
    }

    func open() {
        guard container == nil else { return }
        do {
            container = try opener()
            failed = false
        } catch {
            failed = true
        }
    }
}
