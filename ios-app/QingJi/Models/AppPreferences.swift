import SwiftUI

/// iOS 外观选择。账务语义色不开放为用户自定义，避免“收入/支出”含义
/// 因主题改变而失去一致性；系统/浅色/深色交给 Apple 的原生环境处理。
enum AppAppearanceMode: String, CaseIterable, Hashable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
