import UIKit
import SwiftUI

struct ThemeSettingsView: View {
    @AppStorage("qingji.appearanceMode") private var appearanceModeRaw = AppAppearanceMode.system.rawValue
    @AppStorage("qingji.themePreset") private var presetRaw = AppThemePreset.warm.rawValue
    @AppStorage("qingji.themeIntensity") private var intensity = 1.0
    @AppStorage("qingji.themeCardAlpha") private var cardAlpha = AppThemePreferences.defaultCardAlpha
    @AppThemeContext private var theme

    private var appearanceMode: Binding<AppAppearanceMode> {
        Binding(
            get: { AppAppearanceMode(rawValue: appearanceModeRaw) ?? .system },
            set: { appearanceModeRaw = $0.rawValue }
        )
    }

    private var intensityValue: Binding<Double> {
        Binding(get: { theme.preferences.intensity }, set: { intensity = $0 })
    }

    private var cardAlphaValue: Binding<Double> {
        Binding(get: { theme.preferences.cardAlpha }, set: { cardAlpha = $0 })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                AppLabeledField("应用外观") {
                    AppSlidingSegment(options: AppAppearanceMode.allCases.map {
                        AppSegmentOption(value: $0, title: $0.label)
                    }, selection: appearanceMode)
                    .accessibilityIdentifier("theme-appearance")
                }
                AppLabeledField("背景") {
                    HStack(spacing: 6) {
                        ForEach(AppThemePreset.allCases) { preset in
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                presetRaw = preset.rawValue
                            } label: {
                                VStack(spacing: 7) {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(LinearGradient(colors: [Color(uiColor: preset.top), Color(uiColor: preset.bottom)],
                                                             startPoint: .top, endPoint: .bottom))
                                        .frame(height: 50)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(presetRaw == preset.rawValue ? Color.statisticsAccent : theme.hairline,
                                                              lineWidth: presetRaw == preset.rawValue ? 2 : 0.5)
                                        }
                                    Text(preset.label)
                                        .font(.system(size: 12))
                                        .foregroundStyle(presetRaw == preset.rawValue ? Color.primary : Color.secondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("theme-preset-\(preset.rawValue)")
                            .accessibilityAddTraits(presetRaw == preset.rawValue ? .isSelected : [])
                        }
                    }
                }
                VStack(spacing: 16) {
                    if theme.preferences.preset != .white {
                        slider("背景浓度", value: intensityValue, range: 0...1, identifier: "theme-intensity")
                        Divider()
                    }
                    slider("卡片透明度", value: cardAlphaValue, range: 0.25...0.90, identifier: "theme-card-alpha")
                }
                .padding(16)
                .appThemeCard()
            }
            .padding(20)
        }
        .liquidGlassCanvas()
        .navigationTitle("主题外观")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                LiquidGlassIconButton(systemName: "arrow.counterclockwise", accessibilityLabel: "恢复默认", size: 32) {
                    presetRaw = AppThemePreset.warm.rawValue
                    intensity = 1
                    cardAlpha = AppThemePreferences.defaultCardAlpha
                }
                .disabled(theme.preferences.preset == .warm && theme.preferences.intensity == 1
                          && theme.preferences.cardAlpha == AppThemePreferences.defaultCardAlpha)
                .accessibilityIdentifier("theme-reset")
            }
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                        identifier: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).font(.system(size: 15))
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .font(.system(size: 14, design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .tint(Color.statisticsAccent)
                .accessibilityIdentifier(identifier)
        }
    }
}
