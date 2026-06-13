import SwiftUI

/// 全局路由状态，通过 environment 注入，驱动深链跳转。
/// 保持极简：只持有「当前 Tab」和「待执行的导航意图」。
@Observable
final class AppRouter {

    // MARK: - Tab 选中

    var selectedTab: AppTab = .quickAdd

    // MARK: - 统计页 scope

    /// 统计页的月度/年度切换（由深链 qingji://stats/year 设置）。
    enum StatsScope: Hashable { case month, year }
    var statsScope: StatsScope = .month

    // MARK: - 设置页导航意图

    /// 设置页接到深链后要 push 的子页面。
    enum SettingsDestination: Hashable { case budget, reconcile }
    var settingsPushTarget: SettingsDestination? = nil

    // MARK: - QuickAdd 页意图

    /// 记一笔页接到 qingji://ai 时弹出 AI 记账 sheet。
    var showAISheet: Bool = false

    // MARK: - URL 解析

    /// 解析 qingji:// URL 并更新路由状态。
    /// 由 RootTabView 的 onOpenURL 调用。
    func handle(url: URL) {
        guard url.scheme == "qingji" else { return }
        let host = url.host ?? ""
        let path = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "add":
            selectedTab   = .quickAdd
            showAISheet   = false

        case "ai":
            selectedTab   = .quickAdd
            // 短暂延迟确保 Tab 切换完成后再触发 sheet
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.showAISheet = true
            }

        case "transactions":
            selectedTab   = .transactions

        case "stats":
            selectedTab   = .statistics
            statsScope    = path.first == "year" ? .year : .month

        case "settings":
            selectedTab   = .settings
            switch path.first {
            case "budget":    settingsPushTarget = .budget
            case "reconcile": settingsPushTarget = .reconcile
            default:          settingsPushTarget = nil
            }

        default:
            break
        }
    }
}
