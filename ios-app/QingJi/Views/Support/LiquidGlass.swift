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
    func liquidGlassCircleControl(size: CGFloat = 48) -> some View {
        buttonStyle(.plain)
            .frame(width: size, height: size)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: .circle)
    }

    /// A single glass capsule for text actions and menus.
    func liquidGlassPillControl(
        horizontalPadding: CGFloat = 14,
        minWidth: CGFloat? = nil,
        minHeight: CGFloat = 44
    ) -> some View {
        buttonStyle(.plain)
            .padding(.horizontal, horizontalPadding)
            .frame(minWidth: minWidth, minHeight: minHeight)
            .contentShape(Capsule())
            .glassEffect(.regular.interactive(), in: .capsule)
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
    @State private var showing = false
    @AppThemeContext private var theme
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var subtitleSize: CGFloat = 12.5

    init(selected: Value, options: [AppMenuOption<Value>], onSelect: @escaping (Value) -> Void,
         @ViewBuilder label: () -> Label) {
        self.selected = selected
        self.options = options
        self.onSelect = onSelect
        self.label = label()
    }

    var body: some View {
        Button { showing = true } label: { label }
            .buttonStyle(.plain)
            .popover(isPresented: $showing) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                            if index > 0 { Divider().padding(.horizontal, 12) }
                            Button {
                                showing = false
                                onSelect(option.value)
                            } label: {
                                HStack(spacing: 10) {
                                    if let icon = option.systemName {
                                        Image(systemName: icon).frame(width: 20).foregroundStyle(.secondary)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(option.title)
                                            .font(.system(size: titleSize, weight: .medium))
                                            .fixedSize(horizontal: false, vertical: true)
                                        if let subtitle = option.subtitle {
                                            Text(subtitle)
                                                .font(.system(size: subtitleSize)).foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.statisticsAccent)
                                        .opacity(selected == option.value ? 1 : 0)
                                        .frame(width: 16)
                                }
                                .foregroundStyle(.primary)
                                .padding(12)
                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(option.identifier ?? "")
                            .accessibilityAddTraits(selected == option.value ? .isSelected : [])
                        }
                    }
                }
                .frame(width: 280, height: min(420, CGFloat(options.count) * (options.contains { $0.subtitle != nil } ? 90 : 52)))
                .presentationCompactAdaptation(.popover)
                .presentationBackground(theme.sheet)
            }
    }
}

/// Reusable 44pt control matching the touch target and native glass press
/// animation used by iOS 26 system apps.
struct LiquidGlassIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let size: CGFloat
    let action: () -> Void

    init(
        systemName: String,
        accessibilityLabel: String,
        size: CGFloat = 48,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline.weight(.semibold))
                .frame(width: size, height: size)
        }
        .liquidGlassCircleControl(size: size)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// A compact native glass action for sheet headers and page-level actions.
struct LiquidGlassPillButton: View {
    let title: String
    let prominent: Bool
    let action: () -> Void

    init(_ title: String, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.prominent = prominent
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
                .liquidGlassPillControl()
        }
    }
}
