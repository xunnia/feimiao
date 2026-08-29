import UIKit
import SwiftUI

/// iOS 原生外观设置。系统负责 Liquid Glass 的材质、对比度和动态效果，
/// 肥喵只保存用户选择的浅/深色策略。
struct ThemeSettingsView: View {
    @AppStorage("qingji.appearanceMode") private var appearanceModeRaw = AppAppearanceMode.system.rawValue

    private var appearanceMode: Binding<AppAppearanceMode> {
        Binding(
            get: { AppAppearanceMode(rawValue: appearanceModeRaw) ?? .system },
            set: { appearanceModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("应用外观") {
                Picker("外观", selection: appearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.inline)
            }
            Section("iOS 原生视觉") {
                Label("液态玻璃", systemImage: "circle.hexagongrid.fill")
                Text("导航栏、快记键盘和高频操作使用系统 Liquid Glass；系统的动态效果、对比度和减少动态效果选项会自动生效。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .liquidGlassCanvas()
        .navigationTitle("主题外观")
        .navigationBarTitleDisplayMode(.inline)
    }
}
