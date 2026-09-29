import SwiftUI
import SwiftData
import UIKit

enum AppTab: Hashable {
    case home, quickAdd, search, transactions, statistics, settings
}

struct RootTabView: View {
    @Environment(AppRouter.self) private var router
    @State private var path: [AppRouter.Route] = []
    /// 抽屉打开程度：0 = 关，1 = 开。拖动时跟手连续变化（对齐安卓推开式抽屉）。
    @State private var drawerProgress: CGFloat = 0
    /// 一次拖动开始时的 drawerProgress。
    @State private var dragStartProgress: CGFloat = 0
    /// 一次拖动的方向判定：先看头一段位移，明显横向才接管，竖着滑交给主页滚动。
    @State private var dragMode: DrawerDragMode = .undecided
    @State private var didFinishInitialSync = false
    @State private var demoQuickAddPresented = false

    init() {
        // CI and deep-link launches must start with the destination already in
        // the stack.  Waiting for onAppear to push it lets NavigationStack
        // publish its initial [] value first, which previously reset the
        // router to home and left the requested page blank.
        _path = State(initialValue: Self.initialPath())
        _drawerProgress = State(initialValue: Self.initialDrawerPresented() ? 1 : 0)
    }

    var body: some View {
        Group {
            if Self.shouldRenderDemoImportReviewAsRoot(environment: ProcessInfo.processInfo.environment) {
                // The screenshot runner must not depend on an initial path
                // being consumed by the outer NavigationStack. Keep the
                // review surface at the root of a dedicated, path-less stack.
                NavigationStack {
                    importReviewDestination
                }
            } else {
                drawerShell
            }
        }
        .liquidGlassChrome()
        .liquidGlassCanvas()
        .onAppear {
            DispatchQueue.main.async {
                let screen = ProcessInfo.processInfo.environment["QINGJI_SCREEN"] ?? ""
                if screen == "quickadd" || screen == "quickadd/income" {
                    router.quickAddStartsWithIncome = screen == "quickadd/income"
                    router.selectedTab = .home
                    path = []
                    demoQuickAddPresented = true
                } else {
                    syncPath()
                }
                didFinishInitialSync = true
            }
        }
        .onChange(of: router.selectedTab) { _, _ in syncPath() }
        .onChange(of: path) { _, newPath in
            guard didFinishInitialSync else { return }
            guard let route = newPath.first else {
                router.settingsPushTarget = nil
                router.selectedTab = .home
                return
            }
            switch route {
            case .quickAdd: router.selectedTab = .quickAdd
            case .search: router.selectedTab = .search
            case .transactions: router.selectedTab = .transactions
            case .statistics: router.selectedTab = .statistics
            case .settings: router.selectedTab = .settings
            case .importReview:
                router.settingsPushTarget = nil
                router.selectedTab = .settings
            }
        }
        // 所有深链统一由 AppRouter 解析；路径同步后仍由各页面处理自己的
        // settingsPushTarget，这保证冷启动和用户点击走同一条导航链。
        .onOpenURL { url in
            router.handle(url: url)
            DispatchQueue.main.async { syncPath() }
        }
        .fullScreenCover(isPresented: Binding(
            get: { router.showAssistant },
            set: { router.showAssistant = $0 }
        )) {
            MeowAssistantView()
        }
        .sheet(isPresented: $demoQuickAddPresented) {
            QuickAddView()
                .presentationDetents([.fraction(0.84), .large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
        }
    }

    // MARK: - 推开式抽屉（对齐安卓 main.dart：抽屉在下，主页整张卡片右移）

    private var drawerOpen: Bool { drawerProgress > 0.5 }

    private var drawerShell: some View {
        GeometryReader { proxy in
            let drawerWidth = min(max(proxy.size.width * 0.75, 240), 320)
            let p = drawerProgress
            let card = DrawerCardShape(radius: 26 * p, insets: proxy.safeAreaInsets)

            ZStack(alignment: .leading) {
                AppDrawerView(
                    isOpen: drawerOpen,
                    onClose: { setDrawer(open: false) },
                    onNavigate: { destination in
                        setDrawer(open: false)
                        navigate(to: destination)
                    }
                )
                .frame(width: drawerWidth)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(p < 0.01)

                mainStack
                    .accessibilityHidden(drawerOpen)
                    // 抽屉打开时主页盖一层淡底色，点一下或往左拖都能关。
                    .overlay {
                        Color(uiColor: .systemBackground)
                            .opacity(0.22 * p)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .allowsHitTesting(p > 0.01)
                            .onTapGesture { setDrawer(open: false) }
                            .accessibilityElement()
                            .accessibilityLabel("关闭菜单")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHidden(!drawerOpen)
                    }
                    .clipShape(card)
                    .overlay {
                        card.stroke(Color.primary.opacity(0.08 * p), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                    .background {
                        card.fill(Color(uiColor: .systemBackground))
                            .shadow(color: .black.opacity(0.14 * p), radius: 24, x: -4, y: 0)
                            .opacity(p > 0.001 ? 1 : 0)
                    }
                    .offset(x: drawerWidth * p)
            }
            .simultaneousGesture(
                drawerDrag(width: drawerWidth),
                // 只在主页根层可用；进了子页面交给系统的侧滑返回。
                including: path.isEmpty ? .all : .subviews
            )
            .accessibilityAction(.escape) {
                if drawerOpen { setDrawer(open: false) }
            }
        }
    }

    private var mainStack: some View {
        NavigationStack(path: $path) {
            HomeView(onOpenDrawer: { setDrawer(open: true) })
                .navigationDestination(for: AppRouter.Route.self) { route in
                    switch route {
                    case .quickAdd:
                        QuickAddView()
                    case .search:
                        TransactionListView(searchMode: true)
                    case .transactions:
                        TransactionListView()
                    case .statistics:
                        MonthlyStatsView()
                    case .settings:
                        SettingsView()
                    case .importReview:
                        importReviewDestination
                    }
                }
        }
        .liquidGlassCanvas()
    }

    /// 横向位移 > 24 且 |dx| > |dy|·1.6 才算拖抽屉（同安卓阈值）；
    /// 关着只认向右拉开，开着只认向左推回。
    private func drawerDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if dragMode == .undecided {
                    if abs(dy) > abs(dx) * 1.6 && abs(dy) > 10 {
                        dragMode = .ignored
                    } else if abs(dx) > 24 && abs(dx) > abs(dy) * 1.6 {
                        let wantsOpen = dx > 0
                        dragMode = wantsOpen != drawerOpen ? .horizontal : .ignored
                        dragStartProgress = drawerProgress
                    }
                }
                guard dragMode == .horizontal else { return }
                drawerProgress = min(max(dragStartProgress + dx / width, 0), 1)
            }
            .onEnded { value in
                defer { dragMode = .undecided }
                guard dragMode == .horizontal else { return }
                // 预测位移比当前位移多出来的部分约等于甩动速度。
                let fling = value.predictedEndTranslation.width - value.translation.width
                if fling > 120 {
                    setDrawer(open: true)
                } else if fling < -120 {
                    setDrawer(open: false)
                } else {
                    setDrawer(open: drawerProgress > 0.5)
                }
            }
    }

    /// 240ms easeOutCubic，与安卓抽屉动画一致。
    private func setDrawer(open: Bool) {
        if open {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
        }
        withAnimation(.timingCurve(0.215, 0.61, 0.355, 1, duration: 0.24)) {
            drawerProgress = open ? 1 : 0
        }
    }

    @ViewBuilder
    private var importReviewDestination: some View {
        if Self.usesDemoImportReview(environment: ProcessInfo.processInfo.environment) {
            // The screenshot runner needs a deterministic review surface, but
            // this fixture must never be reachable from a production entry.
            ImportReviewView(result: ImportReviewView.demoResult()) { _, _ in }
        } else {
            ImportExportView()
        }
    }

    static func usesDemoImportReview(environment: [String: String]) -> Bool {
        environment["QINGJI_DEMO"] == "1"
    }

    static func shouldRenderDemoImportReviewAsRoot(environment: [String: String]) -> Bool {
        guard usesDemoImportReview(environment: environment) else { return false }
        let screen = environment["QINGJI_SCREEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return screen == "import-review" || screen == "settings/import-review"
    }

    private func syncPath() {
        // 导入复核是 parity 冷启动目标，也是正常设置子路由。它显示时保留
        // 专用根路由，避免 selectedTab 的观察者把它重置回设置首页。
        if router.settingsPushTarget == .importReview {
            router.settingsPushTarget = nil
            let next: [AppRouter.Route] = [.importReview]
            if path != next { path = next }
            return
        }
        if path.first == .importReview {
            return
        }
        let next: [AppRouter.Route]
        switch router.selectedTab {
        case .home: next = []
        case .quickAdd: next = [.quickAdd]
        case .search: next = [.search]
        case .transactions: next = [.transactions]
        case .statistics: next = [.statistics]
        case .settings: next = [.settings]
        }
        if path != next { path = next }
    }

    private static func initialPath() -> [AppRouter.Route] {
        initialPath(for: ProcessInfo.processInfo.environment["QINGJI_SCREEN"])
    }

    /// 独立纯函数供 XCTest 验证每个 CI 冷启动入口，不再只靠 PNG 存在判断。
    static func initialPath(for screen: String?) -> [AppRouter.Route] {
        guard let screen, !screen.isEmpty else { return [] }
        if screen == "settings/ai" {
            return [.settings]
        }
        let normalized = screen.hasPrefix("settings/")
            ? String(screen.dropFirst("settings/".count))
            : screen
        switch normalized {
        case "home": return []
        case "home/drawer": return []
        case "quickadd": return []
        case "quickadd/income": return []
        case "search": return [.search]
        case "transactions": return [.transactions]
        case "import-review": return [.importReview]
        case "stats-month", "stats-week", "stats/year", "stats/week", "stats-year", "stats-custom", "stats/custom", "stats/month", "stats/month/ring", "stats/month/trend", "stats/month/trend/income", "stats/month/top5", "stats/month/sources", "stats/month/picker", "stats/month/books", "stats/month/book-selected", "stats/month/pace", "stats/month/pace/activity", "stats/month/pace/detail", "stats/month/budget-ring", "stats/month/cards", "stats/month/cards/optional", "stats/month/insights", "stats/month/heatmap", "stats/month/radar", "stats/month/stacked", "stats/custom/category-detail":
            return [.statistics]
        case "budget", "reconcile", "reimburse", "books", "accounts", "categories", "tags",
             "memory", "ai-memory", "ai-tasks", "ai-schedules",
             "ai-diagnostics", "savings", "recurring", "assets", "assets/funds", "assets/add", "assets/detail",
             "assets/purchase", "assets/purchase/form",
             "assets-detail", "liabilities", "net-worth", "import", "import-export",
             "accounts/detail", "accounts-detail",
             "reimburse/settlement",
             "reports", "settings", "backup", "display", "theme", "money-display", "auto-record",
             "autorecord", "ai-settings":
            return [.settings]
        case "ai": return [.quickAdd]
        default: return []
        }
    }

    private static func initialDrawerPresented() -> Bool {
        let screen = ProcessInfo.processInfo.environment["QINGJI_SCREEN"] ?? ""
        return screen == "home/drawer" || screen == "books"
    }

    private func navigate(to destination: DrawerDestination) {
        switch destination {
        case .home:
            router.settingsPushTarget = nil
            router.selectedTab = .home
        case .quickAdd:
            router.settingsPushTarget = nil
            router.selectedTab = .quickAdd
        case .transactions:
            router.settingsPushTarget = nil
            router.selectedTab = .transactions
        case .statistics:
            router.settingsPushTarget = nil
            router.selectedTab = .statistics
        case .settings:
            router.settingsPushTarget = nil
            router.selectedTab = .settings
        case .assistant:
            router.settingsPushTarget = nil
            router.selectedTab = .quickAdd
            router.showAssistant = true
        case .settingsDestination(let target):
            if target == .importReview {
                router.settingsPushTarget = nil
                router.selectedTab = .settings
                path = [.importReview]
            } else {
                router.settingsPushTarget = target
                router.selectedTab = .settings
            }
        }
    }
}

enum DrawerDragMode {
    case undecided, horizontal, ignored
}

enum DrawerDestination {
    case home
    case quickAdd
    case transactions
    case statistics
    case settings
    case assistant
    case settingsDestination(AppRouter.SettingsDestination)
}

/// 主页卡片的裁切形状。卡片内容（背景、顶栏）会延伸到安全区外，所以形状按安全区
/// 向外扩一圈，关着时（半径 0）等于不裁；打开后圆角随进度出现。
struct DrawerCardShape: Shape {
    var radius: CGFloat
    var insets: EdgeInsets

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let expanded = CGRect(
            x: rect.minX - insets.leading,
            y: rect.minY - insets.top,
            width: rect.width + insets.leading + insets.trailing,
            height: rect.height + insets.top + insets.bottom
        )
        return Path(roundedRect: expanded, cornerRadius: radius, style: .continuous)
    }
}

#Preview {
    RootTabView()
        .modelContainer(AppModelContainer.shared)
        .environment(AppRouter())
}
