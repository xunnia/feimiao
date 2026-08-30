import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case home, quickAdd, search, transactions, statistics, settings
}

struct RootTabView: View {
    @Environment(AppRouter.self) private var router
    @State private var path: [AppRouter.Route] = []
    @State private var drawerPresented = false
    @State private var didFinishInitialSync = false

    init() {
        // CI and deep-link launches must start with the destination already in
        // the stack.  Waiting for onAppear to push it lets NavigationStack
        // publish its initial [] value first, which previously reset the
        // router to home and left the requested page blank.
        _path = State(initialValue: Self.initialPath())
        _drawerPresented = State(initialValue: Self.initialDrawerPresented())
    }

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(onOpenDrawer: { drawerPresented = true })
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
                    }
                }
        }
        .liquidGlassChrome()
        .liquidGlassCanvas()
        .onAppear {
            DispatchQueue.main.async {
                syncPath()
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
            }
        }
        // 所有深链统一由 AppRouter 解析；路径同步后仍由各页面处理自己的
        // settingsPushTarget，这保证冷启动和用户点击走同一条导航链。
        .onOpenURL { url in
            router.handle(url: url)
            DispatchQueue.main.async { syncPath() }
        }
        .overlay {
            if drawerPresented {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Color.black.opacity(0.16)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture { drawerPresented = false }

                        AppDrawerView(
                            onClose: { drawerPresented = false },
                            onNavigate: { destination in
                                drawerPresented = false
                                navigate(to: destination)
                            }
                        )
                        .frame(width: min(proxy.size.width * 0.78, 320))
                        .frame(maxHeight: .infinity)
                         .liquidGlassSurface(cornerRadius: 26)
                        .clipShape(.rect(bottomTrailingRadius: 26, topTrailingRadius: 26))
                        .shadow(color: .black.opacity(0.18), radius: 24, x: 8, y: 0)
                        .transition(.move(edge: .leading))
                    }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .animation(.snappy(duration: 0.24), value: drawerPresented)
        .fullScreenCover(isPresented: Binding(
            get: { router.showAssistant },
            set: { router.showAssistant = $0 }
        )) {
            MeowAssistantView()
        }
    }

    private func syncPath() {
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
        guard let screen = ProcessInfo.processInfo.environment["QINGJI_SCREEN"],
              !screen.isEmpty else {
            return []
        }
        if screen == "settings/ai" {
            return [.settings]
        }
        let normalized = screen.hasPrefix("settings/")
            ? String(screen.dropFirst("settings/".count))
            : screen
        switch normalized {
        case "home": return []
        case "home/drawer": return []
        case "quickadd": return [.quickAdd]
        case "quickadd/income": return [.quickAdd]
        case "search": return [.search]
        case "transactions": return [.transactions]
        case "stats-month", "stats-week", "stats/year", "stats/week", "stats-year", "stats-custom", "stats/month":
            return [.statistics]
        case "budget", "reconcile", "reimburse", "books", "accounts", "categories", "tags",
             "memory", "ai-memory", "ai-tasks", "ai-extensions", "ai-schedules", "ai-search",
             "ai-diagnostics", "ai-local", "savings", "recurring", "assets", "assets/detail",
             "assets-detail", "liabilities", "net-worth", "import-review", "import", "import-export",
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
            router.settingsPushTarget = target
            router.selectedTab = .settings
        }
    }
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

/// 与 Android RootShell 的左侧抽屉对应。它只负责导航和账本筛选，页面本身
/// 仍由根 NavigationStack push，避免 iOS 另造一套底部 Tab 信息架构。
private struct AppDrawerView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \Book.sortOrder)
    private var books: [Book]

    let onClose: () -> Void
    let onNavigate: (DrawerDestination) -> Void

    private let entries: [(String, String, DrawerDestination)] = [
        ("chart.pie", "统计数据", .statistics),
        ("shippingbox", "资产管理", .settingsDestination(.assets)),
        ("gauge.with.needle", "预算管理", .settingsDestination(.budget)),
        ("target", "存钱目标", .settingsDestination(.savings)),
        ("cat.fill", "喵助手", .assistant),
        ("square.grid.2x2", "分类管理", .settingsDestination(.categories)),
        ("tag", "标签管理", .settingsDestination(.tags)),
        ("square.and.arrow.down", "导入导出", .settingsDestination(.importExport)),
        ("arrow.uturn.backward.circle", "待报销", .settingsDestination(.reimburse)),
        ("clock.badge", "定时记账", .settingsDestination(.recurring)),
        ("bell", "自动记账", .settingsDestination(.autoRecord))
    ]

    var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("肥喵记账")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .liquidGlassCircleControl(size: 44)
                    .accessibilityLabel("关闭菜单")
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                            drawerRow(icon: entry.0, title: entry.1) {
                                onNavigate(entry.2)
                            }
                        }

                        Divider()
                            .padding(.vertical, 10)

                        Text("我的账本")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 4)

                        drawerRow(
                            icon: "book.closed",
                            title: "总账本",
                            selected: router.selectedBookID == nil
                        ) {
                            router.selectedBookID = nil
                            onClose()
                        }
                        ForEach(books) { book in
                            drawerRow(
                                icon: "book.closed",
                                title: book.name,
                                selected: router.selectedBookID == book.stableID
                            ) {
                                router.selectedBookID = book.stableID
                                onClose()
                            }
                        }

                        Divider()
                            .padding(.vertical, 10)
                        drawerRow(icon: "book.badge.plus", title: "账本管理") {
                            onNavigate(.settingsDestination(.books))
                        }
                        drawerRow(icon: "creditcard", title: "账户管理") {
                            onNavigate(.settingsDestination(.accounts))
                        }
                    }
                    .padding(.vertical, 8)
                }

                Divider()
                HStack(spacing: 10) {
                    drawerRow(icon: "gearshape", title: "设置") {
                        onNavigate(.settings)
                    }
                    .frame(maxWidth: .infinity)
                    drawerRow(icon: "archivebox", title: "备份") {
                        onNavigate(.settingsDestination(.backup))
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(12)
            }
            .safeAreaPadding()
    }

    private func drawerRow(
        icon: String,
        title: String,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 24)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                Text(title)
                    .font(.body)
                    .foregroundStyle(selected ? Color.accentColor : .primary)
                Spacer()
                if selected { Image(systemName: "checkmark").font(.caption.weight(.semibold)) }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(selected ? Color.accentColor.opacity(0.12) : .clear, in: .rect(cornerRadius: 12))
        }
        // Drawer rows are already inside one glass drawer surface. Adding a
        // glass button style to every row creates nested pills and hides the
        // selection treatment behind a second white layer.
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

#Preview {
    RootTabView()
        .modelContainer(AppModelContainer.shared)
        .environment(AppRouter())
}
