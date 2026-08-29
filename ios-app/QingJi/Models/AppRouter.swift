import SwiftUI
import Observation

/// 全局路由状态，通过 environment 注入，驱动深链跳转。
/// 保持极简：只持有「当前 Tab」和「待执行的导航意图」。
@Observable
final class AppRouter {

    /// Android 使用单一主页 + 抽屉 + push 页面；iOS 保持同一信息架构，
    /// 只把页面内部控件和转场换成 SwiftUI 原生实现。
    enum Route: Hashable {
        case quickAdd
        case search
        case transactions
        case statistics
        case settings
    }

    // MARK: - Tab 选中

    var selectedTab: AppTab = .home

    /// 当前账本筛选；nil 表示总览所有“计入总账”的账本。
    var selectedBookID: UUID?

    // MARK: - 统计页 scope

    /// 统计页的时间维度（由深链 qingji://stats/week 等设置）。
    enum StatsScope: Hashable { case week, month, year, custom }
    var statsScope: StatsScope = .month

    // MARK: - 设置页导航意图

    /// 设置页接到深链后要 push 的子页面。
    enum SettingsDestination: Hashable {
        case books, accounts, accountDetail, categories, tags, memory, aiMemory, aiTasks, aiExtensions, aiSchedules, aiSearch, aiDiagnostics, aiLocal, budget, reconcile, reimburse, savings, recurring, assets, assetDetail, liabilities, netWorth, importReview, importExport, reports, backup, display, theme, moneyDisplay, autoRecord, ai
    }
    var settingsPushTarget: SettingsDestination? = nil

    // MARK: - QuickAdd 页意图

    /// 记一笔页接到 qingji://ai 时弹出 AI 记账 sheet。
    var showAISheet: Bool = false

    /// CI parity only: open the real quick-add page on the income segment.
    /// Normal launches keep the Android default of expense.
    var quickAddStartsWithIncome = false

    /// AI 深链打开 Chats 会话列表。
    var showChats: Bool = false

    /// 预留给需要直接打开会话正文的内部导航。
    var showAssistant: Bool = false

    var pendingShareText: String?
    var pendingShareImageFileName: String?

    // MARK: - 初始化

    init() {
        // CI 截图专用：QINGJI_SCREEN 环境变量指定启动后直接跳到的页面，
        // 避免 simctl openurl 触发模拟器「Open in App?」确认弹窗导致无法导航。
        if let screen = ProcessInfo.processInfo.environment["QINGJI_SCREEN"], !screen.isEmpty {
            applyLaunchScreen(screen)
        }
    }

    /// 把启动参数映射到初始路由状态。
    private func applyLaunchScreen(_ screen: String) {
        if screen == "home/drawer" {
            selectedTab = .home
            return
        }
        if screen == "books" {
            selectedTab = .home
            return
        }
        if screen == "quickadd/income" {
            selectedTab = .quickAdd
            quickAddStartsWithIncome = true
            return
        }
        if screen == "settings/ai" {
            selectedTab = .settings
            settingsPushTarget = .ai
            return
        }
        let normalizedScreen: String
        if screen.hasPrefix("settings/") {
            normalizedScreen = String(screen.dropFirst("settings/".count))
        } else {
            normalizedScreen = screen
        }

        switch normalizedScreen {
        case "home":        selectedTab = .home
        case "search":      selectedTab = .search
        case "transactions": selectedTab = .transactions
        case "stats-week", "stats/week":  selectedTab = .statistics; statsScope = .week
        case "stats-month", "stats/month":  selectedTab = .statistics; statsScope = .month
        case "stats-year", "stats/year":   selectedTab = .statistics; statsScope = .year
        case "stats-custom", "stats/custom": selectedTab = .statistics; statsScope = .custom
        case "quickadd":    selectedTab = .quickAdd
        case "budget":       selectedTab = .settings;   settingsPushTarget = .budget
        case "reconcile":    selectedTab = .settings;   settingsPushTarget = .reconcile
        case "reimburse":    selectedTab = .settings;   settingsPushTarget = .reimburse
        case "books":        selectedTab = .settings;   settingsPushTarget = .books
        case "accounts":     selectedTab = .settings;   settingsPushTarget = .accounts
        case "categories":   selectedTab = .settings;   settingsPushTarget = .categories
        case "tags":         selectedTab = .settings;   settingsPushTarget = .tags
        case "memory":       selectedTab = .settings;   settingsPushTarget = .memory
        case "ai-memory":    selectedTab = .settings;   settingsPushTarget = .aiMemory
        case "ai-tasks":     selectedTab = .settings;   settingsPushTarget = .aiTasks
        case "ai-extensions": selectedTab = .settings; settingsPushTarget = .aiExtensions
        case "ai-schedules": selectedTab = .settings; settingsPushTarget = .aiSchedules
        case "ai-search":     selectedTab = .settings; settingsPushTarget = .aiSearch
        case "ai-diagnostics": selectedTab = .settings; settingsPushTarget = .aiDiagnostics
        case "ai-local":       selectedTab = .settings; settingsPushTarget = .aiLocal
        case "savings":      selectedTab = .settings;   settingsPushTarget = .savings
        case "recurring":    selectedTab = .settings;   settingsPushTarget = .recurring
        case "assets-detail", "assets/detail":
            selectedTab = .settings
            settingsPushTarget = .assetDetail
        case "assets":       selectedTab = .settings;   settingsPushTarget = .assets
        case "accounts-detail", "accounts/detail":
            selectedTab = .settings
            settingsPushTarget = .accountDetail
        case "liabilities":  selectedTab = .settings;   settingsPushTarget = .liabilities
        case "net-worth":    selectedTab = .settings;   settingsPushTarget = .netWorth
        case "import-review": selectedTab = .settings; settingsPushTarget = .importReview
        case "import", "import-export": selectedTab = .settings; settingsPushTarget = .importExport
        case "reports":      selectedTab = .settings; settingsPushTarget = .reports
        case "settings":     selectedTab = .settings
        case "backup":       selectedTab = .settings; settingsPushTarget = .backup
        case "display":      selectedTab = .settings; settingsPushTarget = .display
        case "theme":        selectedTab = .settings; settingsPushTarget = .theme
        case "auto-record", "autorecord": selectedTab = .settings; settingsPushTarget = .autoRecord
        case "ai":           selectedTab = .quickAdd;   showChats = true
        case "ai-settings":  selectedTab = .settings;   settingsPushTarget = .ai
        default:             selectedTab = .quickAdd
        }
    }

    // MARK: - URL 解析

    /// 解析 qingji:// URL 并更新路由状态。
    /// 由 RootTabView 的 onOpenURL 调用。
    func handle(url: URL) {
        guard url.scheme == "qingji" else { return }
        let host = url.host ?? ""
        let path = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "home":
            selectedTab = .home

        case "add":
            selectedTab   = .quickAdd
            showAISheet   = false

        case "ai":
            selectedTab   = .quickAdd
            // 短暂延迟确保 Tab 切换完成后再触发 sheet
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.showChats = true
            }

        case "search":
            selectedTab = .search

        case "transactions":
            selectedTab   = .transactions

        case "stats":
            selectedTab   = .statistics
            switch path.first {
            case "week": statsScope = .week
            case "year": statsScope = .year
            case "custom": statsScope = .custom
            default: statsScope = .month
            }

        case "settings":
            selectedTab   = .settings
            switch path.first {
            case "budget":    settingsPushTarget = .budget
            case "reconcile": settingsPushTarget = .reconcile
            case "reimburse": settingsPushTarget = .reimburse
            case "books":     settingsPushTarget = .books
            case "accounts":
                settingsPushTarget = path.dropFirst().first == "detail"
                    ? .accountDetail
                    : .accounts
            case "categories": settingsPushTarget = .categories
            case "tags":      settingsPushTarget = .tags
            case "memory":    settingsPushTarget = .memory
            case "ai-memory": settingsPushTarget = .aiMemory
            case "ai-tasks": settingsPushTarget = .aiTasks
            case "ai-extensions": settingsPushTarget = .aiExtensions
            case "ai-schedules": settingsPushTarget = .aiSchedules
            case "ai-search": settingsPushTarget = .aiSearch
            case "ai-diagnostics": settingsPushTarget = .aiDiagnostics
            case "ai-local": settingsPushTarget = .aiLocal
            case "savings":   settingsPushTarget = .savings
            case "recurring": settingsPushTarget = .recurring
            case "assets":
                settingsPushTarget = path.dropFirst().first == "detail"
                    ? .assetDetail
                    : .assets
            case "liabilities": settingsPushTarget = .liabilities
            case "net-worth": settingsPushTarget = .netWorth
            case "import-review": settingsPushTarget = .importReview
            case "import", "import-export": settingsPushTarget = .importExport
            case "reports": settingsPushTarget = .reports
            case "ai":        settingsPushTarget = .ai
            case "backup":    settingsPushTarget = .backup
            case "display":   settingsPushTarget = .display
            case "theme":     settingsPushTarget = .theme
            case "money-display": settingsPushTarget = .moneyDisplay
            case "auto-record", "autorecord": settingsPushTarget = .autoRecord
            default:          settingsPushTarget = nil
            }

        default:
            break
        }
    }

    func consumePendingShare() {
        guard let pending = ShareIntake.consume() else { return }
        pendingShareText = pending.text.isEmpty ? nil : pending.text
        pendingShareImageFileName = pending.imageFileName
        selectedTab = .quickAdd
        showAISheet = true
    }

    func clearPendingShare() {
        pendingShareText = nil
        pendingShareImageFileName = nil
    }
}
