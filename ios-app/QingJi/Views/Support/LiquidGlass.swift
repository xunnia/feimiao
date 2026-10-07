import SwiftUI
import UIKit

/// A quiet, content-bearing backdrop makes Liquid Glass read as translucent
/// glass instead of an opaque white pill on a flat system background.
struct LiquidGlassBackdrop: View {
    @AppThemeContext private var theme

    var body: some View {
        LinearGradient(colors: [theme.backgroundTop, theme.backgroundBottom],
                       startPoint: .top, endPoint: .bottom)
        .accessibilityHidden(true)
    }
}

/// Shared app chrome for the iOS 26 Liquid Glass hierarchy.
struct LiquidGlassChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .tint(Color.accentColor)
            // Keep the native glass button as a fallback for text actions. Icon
            // controls opt into an explicit circle below so SwiftUI's default
            // capsule cannot stretch them into a second surface.
            .buttonStyle(.glass(.clear))
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}

extension View {
    func appThemeCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(AppThemeSurface(cornerRadius: cornerRadius, input: false))
    }

    func appThemeInput(cornerRadius: CGFloat = 8) -> some View {
        modifier(AppThemeSurface(cornerRadius: cornerRadius, input: true))
    }

    func appRefreshOnDayChange(_ action: @escaping () -> Void) -> some View {
        modifier(AppDayRefresh(action: action))
    }

    func liquidGlassChrome() -> some View {
        modifier(LiquidGlassChrome())
    }

    func liquidGlassCanvas() -> some View {
        background {
            LiquidGlassBackdrop()
                .ignoresSafeArea()
        }
    }

    func liquidGlassSurface(cornerRadius: CGFloat = 18) -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }

    /// A single, explicitly shaped Liquid Glass hit target for icon actions.
    /// The plain button style is important: applying a glass button style and a
    /// glass effect to the same control produces the white-plus-gray double
    /// surface visible in the parity screenshots.
    func liquidGlassCircleControl(size: CGFloat = 48, subtle: Bool = false) -> some View {
        buttonStyle(.plain)
            .frame(width: size, height: size)
            .contentShape(Circle())
            .modifier(LiquidGlassControlSurface(shape: Circle(), subtle: subtle))
    }

    /// A single glass capsule for text actions and menus.
    func liquidGlassPillControl(
        horizontalPadding: CGFloat = 14,
        minWidth: CGFloat? = nil,
        minHeight: CGFloat = 44,
        subtle: Bool = false
    ) -> some View {
        buttonStyle(.plain)
            .padding(.horizontal, horizontalPadding)
            .frame(minWidth: minWidth, minHeight: minHeight)
            .contentShape(Capsule())
            .modifier(LiquidGlassControlSurface(shape: Capsule(), subtle: subtle))
    }

    /// The prominent action keeps the native Liquid Glass behavior while using
    /// a deliberate shape instead of the default capsule inferred from a
    /// button's label.
    func liquidGlassPrimaryCircleControl(
        size: CGFloat = 48,
        tint: Color = Color.accentColor.opacity(0.90)
    ) -> some View {
        buttonStyle(.plain)
            .frame(width: size, height: size)
            .foregroundStyle(.white)
            .contentShape(Circle())
            .glassEffect(
                .regular.tint(tint).interactive(),
                in: .circle
            )
    }

    func liquidGlassPrimaryPillControl(
        horizontalPadding: CGFloat = 16,
        minWidth: CGFloat? = nil,
        minHeight: CGFloat = 44,
        tint: Color = Color.accentColor.opacity(0.90)
    ) -> some View {
        buttonStyle(.plain)
            .padding(.horizontal, horizontalPadding)
            .frame(minWidth: minWidth, minHeight: minHeight)
            .foregroundStyle(.white)
            .contentShape(Capsule())
            .glassEffect(
                .regular.tint(tint).interactive(),
                in: .capsule
            )
    }

    func liquidGlassPrimaryKeyControl(
        cornerRadius: CGFloat = 24,
        tint: Color = Color.accentColor.opacity(0.90)
    ) -> some View {
        buttonStyle(.plain)
            .foregroundStyle(.white)
            .contentShape(.rect(cornerRadius: cornerRadius))
            .glassEffect(
                .regular.tint(tint).interactive(),
                in: .rect(cornerRadius: cornerRadius)
            )
    }

    /// Calculator keys are rounded rectangles rather than capsules. They keep
    /// the same 48pt minimum action area without becoming pill-shaped.
    func liquidGlassKeyControl(cornerRadius: CGFloat = 24) -> some View {
        buttonStyle(.plain)
            .contentShape(.rect(cornerRadius: cornerRadius))
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
    }
}

enum LiquidGlassControlAppearance {
    static func usesNeutralLightSurface(subtle: Bool, isDark: Bool) -> Bool { subtle && !isDark }
    static func outlineOpacity(subtle: Bool, isDark: Bool) -> Double {
        usesNeutralLightSurface(subtle: subtle, isDark: isDark) ? 0.18 : 0.12
    }
}

private struct LiquidGlassControlSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let subtle: Bool
    @AppThemeContext private var theme

    private var glass: Glass {
        if LiquidGlassControlAppearance.usesNeutralLightSurface(subtle: subtle, isDark: theme.isDark) {
            // Tint the native material, not the page or a second opaque button background.
            return .clear.tint(Color(white: 0.96).opacity(0.24)).interactive()
        }
        return subtle ? .clear.interactive() : .regular.interactive()
    }

    func body(content: Content) -> some View {
        content
            .glassEffect(glass, in: shape)
            .background {
                if LiquidGlassControlAppearance.usesNeutralLightSurface(subtle: subtle, isDark: theme.isDark) {
                    // Place the backing beneath the glass, not inside its content layer.
                    shape.fill(Color.white.opacity(0.52))
                }
            }
            .overlay {
                if subtle {
                    shape.strokeBorder(Color.primary.opacity(LiquidGlassControlAppearance.outlineOpacity(
                        subtle: subtle, isDark: theme.isDark)), lineWidth: 0.5)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .shadow(color: .black.opacity(subtle ? 0.04 : 0), radius: 8, x: 0, y: 3)
    }
}

private struct AppThemeSurface: ViewModifier {
    let cornerRadius: CGFloat
    let input: Bool
    @AppThemeContext private var theme

    func body(content: Content) -> some View {
        content
            .background(input ? theme.fill : theme.card,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
    }
}

private struct AppDayRefresh: ViewModifier {
    let action: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear(perform: action)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { action() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in action() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in action() }
    }
}

struct AppLabeledField<Content: View>: View {
    let label: String
    let helper: String?
    let content: Content

    init(_ label: String, helper: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.helper = helper
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 13)).foregroundStyle(.secondary)
            content
            if let helper {
                Text(helper).font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Theme the content layer, while Form retains native rows, controls and sheet chrome.
struct AppThemedForm<Content: View>: View {
    @AppThemeContext private var theme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Form {
            content.listRowBackground(theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(theme.sheet)
        .tint(Color.statisticsAccent)
    }
}

struct AppSegmentOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var id: Value { value }
}

struct AppSlidingSegment<Value: Hashable>: View {
    let options: [AppSegmentOption<Value>]
    @Binding var selection: Value
    @AppThemeContext private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .footnote) private var labelSize: CGFloat = 13
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(.system(size: labelSize, weight: selection == option.value ? .semibold : .regular))
                        .foregroundStyle(selection == option.value ? Color.primary : Color.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: .infinity)
                        .background {
                            if selection == option.value {
                                Capsule()
                                    .fill(theme.segmentSelected)
                                    .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
                                    .matchedGeometryEffect(id: "selection", in: highlight)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(3)
        .background(theme.segmentTrack, in: Capsule())
    }
}

struct AppMenuOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var subtitle: String? = nil
    var systemName: String? = nil
    var identifier: String? = nil
    var id: Value { value }
}

struct AppSelectionMenu<Value: Hashable, Label: View>: View {
    let selected: Value
    let options: [AppMenuOption<Value>]
    let onSelect: (Value) -> Void
    let label: Label

    init(selected: Value, options: [AppMenuOption<Value>], onSelect: @escaping (Value) -> Void,
         @ViewBuilder label: () -> Label) {
        self.selected = selected
        self.options = options
        self.onSelect = onSelect
        self.label = label()
    }

    var body: some View {
        Menu {
            ForEach(options) { option in
                Toggle(isOn: Binding(
                    get: { selected == option.value },
                    set: { if $0 && selected != option.value { onSelect(option.value) } }
                )) {
                    if let icon = option.systemName {
                        SwiftUI.Label(option.title, systemImage: icon)
                    } else {
                        Text(option.title)
                    }
                    if let subtitle = option.subtitle { Text(subtitle) }
                }
                .accessibilityIdentifier(option.identifier ?? "")
            }
        } label: { label }
        .menuActionDismissBehavior(.enabled)
        .buttonStyle(.plain)
    }
}

/// Reusable 44pt control matching the touch target and native glass press
/// animation used by iOS 26 system apps.
struct LiquidGlassIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let size: CGFloat
    let subtle: Bool
    let action: () -> Void

    init(
        systemName: String,
        accessibilityLabel: String,
        size: CGFloat = 48,
        subtle: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel
        self.size = size
        self.subtle = subtle
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(subtle ? .system(size: 20, weight: .medium) : .headline.weight(.semibold))
                .frame(width: size, height: size)
        }
        .liquidGlassCircleControl(size: size, subtle: subtle)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// A compact native glass action for sheet headers and page-level actions.
struct LiquidGlassPillButton: View {
    let title: String
    let prominent: Bool
    let subtle: Bool
    let action: () -> Void

    init(_ title: String, prominent: Bool = false, subtle: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.prominent = prominent
        self.subtle = subtle
        self.action = action
    }

    @ViewBuilder
    var body: some View {
        if prominent {
            Button(action: action) {
                Text(title)
            }
                .liquidGlassPrimaryPillControl()
        } else {
            Button(action: action) {
                Text(title)
            }
                .liquidGlassPillControl(subtle: subtle)
        }
    }
}
