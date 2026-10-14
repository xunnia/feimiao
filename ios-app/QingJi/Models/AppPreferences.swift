import SwiftUI
import UIKit

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

enum AppThemePreset: String, CaseIterable, Identifiable {
    case warm, white, pink, mint, blue, night

    var id: String { rawValue }
    var label: String {
        switch self {
        case .warm: return "暖橙"
        case .white: return "简约白"
        case .pink: return "樱粉"
        case .mint: return "薄荷"
        case .blue: return "雾蓝"
        case .night: return "暮夜"
        }
    }
    var top: UIColor {
        switch self {
        case .warm: return Self.color(0xFAE0B0)
        case .white: return Self.color(0xF7F8FA)
        case .pink: return Self.color(0xF7D9E0)
        case .mint: return Self.color(0xD8EEDF)
        case .blue: return Self.color(0xD9E6F2)
        case .night: return Self.color(0x23262F)
        }
    }
    var bottom: UIColor {
        switch self {
        case .warm: return Self.color(0xFFFDF7)
        case .white: return Self.color(0xF7F8FA)
        case .pink: return Self.color(0xFFFDFB)
        case .mint: return Self.color(0xFBFEFC)
        case .blue: return Self.color(0xFBFDFF)
        case .night: return Self.color(0x17191F)
        }
    }

    static func color(_ hex: Int) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

/// Saved opacity is used as-is within its supported range; 40% is a valid preference.
struct AppThemePreferences: Equatable {
    static let defaultCardAlpha = 0.80
    let preset: AppThemePreset
    let intensity: Double
    let cardAlpha: Double

    init(presetKey: String, intensity: Double, cardAlpha: Double) {
        preset = AppThemePreset(rawValue: presetKey) ?? .warm
        self.intensity = intensity.isFinite ? min(1, max(0, intensity)) : 1
        self.cardAlpha = cardAlpha.isFinite ? min(0.90, max(0.25, cardAlpha)) : Self.defaultCardAlpha
    }

    func colorScheme(appearanceMode: AppAppearanceMode) -> ColorScheme? {
        preset == .night ? .dark : appearanceMode.colorScheme
    }
}

struct AppThemePalette {
    let preferences: AppThemePreferences
    let colorScheme: ColorScheme

    var isDark: Bool { colorScheme == .dark || preferences.preset == .night }
    private var darkBase: UIColor { AppThemePreset.color(preferences.preset == .night ? 0x17191F : 0x211E1C) }
    private var topUIColor: UIColor {
        Self.blend(preferences.preset.bottom, preferences.preset.top, fraction: preferences.intensity)
    }
    var backgroundTop: Color {
        Color(uiColor: isDark && preferences.preset != .night ? darkBase : topUIColor)
    }
    var backgroundBottom: Color {
        Color(uiColor: isDark ? darkBase : preferences.preset.bottom)
    }
    private var sheetUIColor: UIColor {
        if isDark { return Self.blend(darkBase, .white, fraction: 0.06) }
        if preferences.preset == .white { return .white }
        // Match Android: carry a restrained amount of the actual theme tint into floating surfaces.
        return Self.blend(preferences.preset.bottom, topUIColor, fraction: 0.35)
    }
    var sheet: Color { Color(uiColor: sheetUIColor) }
    var card: Color {
        Color(uiColor: isDark ? AppThemePreset.color(0x332F2C) : .white)
            .opacity(isDark ? min(0.95, preferences.cardAlpha + 0.15) : preferences.cardAlpha)
    }
    var fill: Color {
        let ink = isDark ? UIColor.white : Self.blend(topUIColor, .black, fraction: 0.55)
        return Color(uiColor: Self.blend(sheetUIColor, ink, fraction: isDark ? 0.07 : 0.09))
    }
    var segmentTrack: Color {
        let ink = isDark ? UIColor.white : Self.blend(topUIColor, .black, fraction: 0.55)
        return Color(uiColor: ink).opacity(isDark ? 0.08 : 0.12)
    }
    var segmentSelected: Color {
        isDark ? Color(uiColor: AppThemePreset.color(0x4A4540)).opacity(0.75) : Color.white.opacity(0.65)
    }
    var hairline: Color { isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06) }

    private static func blend(_ from: UIColor, _ to: UIColor, fraction: Double) -> UIColor {
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        from.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        to.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        let amount = CGFloat(fraction)
        return UIColor(red: fr + (tr - fr) * amount, green: fg + (tg - fg) * amount,
                       blue: fb + (tb - fb) * amount, alpha: fa + (ta - fa) * amount)
    }
}

@propertyWrapper
struct AppThemeContext: DynamicProperty {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("qingji.themePreset") private var presetKey = AppThemePreset.warm.rawValue
    @AppStorage("qingji.themeIntensity") private var intensity = 1.0
    @AppStorage("qingji.themeCardAlpha") private var cardAlpha = AppThemePreferences.defaultCardAlpha

    var wrappedValue: AppThemePalette {
        AppThemePalette(preferences: AppThemePreferences(presetKey: presetKey, intensity: intensity,
                                                       cardAlpha: cardAlpha), colorScheme: colorScheme)
    }
}
