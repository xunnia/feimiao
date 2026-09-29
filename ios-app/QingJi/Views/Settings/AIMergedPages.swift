import SwiftUI

/// 设置首页「AI」分组里的合并页（01 §4「账号与设置」）：
/// 「可控记忆」和「喵学到的分类」合成一页「记忆」；任务中心和诊断合成「任务与诊断」。
/// 两页都用顶部分段切换，两个旧深链各自落到对应分段，内容本身沿用原页面。

struct MemoryHubView: View {
    enum Tab: Hashable {
        case aiMemory, categories
    }

    @State private var tab: Tab

    init(initialTab: Tab = .aiMemory) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        Group {
            switch tab {
            case .aiMemory: AIMemoryView()
            case .categories: MemoryView()
            }
        }
        .navigationTitle("记忆")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("记忆类型", selection: $tab) {
                Text("可控记忆").tag(Tab.aiMemory)
                Text("喵学到的分类").tag(Tab.categories)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

struct AITaskDiagnosticsView: View {
    enum Tab: Hashable {
        case tasks, diagnostics
    }

    @State private var tab: Tab

    init(initialTab: Tab = .tasks) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        Group {
            switch tab {
            case .tasks: AITaskCenterView()
            case .diagnostics: AIDiagnosticsView()
            }
        }
        .navigationTitle("任务与诊断")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("查看内容", selection: $tab) {
                Text("任务").tag(Tab.tasks)
                Text("诊断").tag(Tab.diagnostics)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
