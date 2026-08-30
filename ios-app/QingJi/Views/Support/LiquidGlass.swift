import SwiftUI
import UIKit

/// A quiet, content-bearing backdrop makes Liquid Glass read as translucent
/// glass instead of an opaque white pill on a flat system background.
struct LiquidGlassBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let warmTop = colorScheme == .dark
            ? Color(red: 0.11, green: 0.12, blue: 0.14)
            : Color(red: 0.99, green: 0.90, blue: 0.70)
        let warmBottom = colorScheme == .dark
            ? Color(red: 0.06, green: 0.07, blue: 0.09)
            : Color(red: 1.00, green: 0.97, blue: 0.89)

        ZStack {
            Color(uiColor: .systemGroupedBackground)

            LinearGradient(
                colors: [
                    warmTop.opacity(colorScheme == .dark ? 0.45 : 0.78),
                    warmBottom.opacity(colorScheme == .dark ? 0.20 : 0.62),
                    Color(uiColor: .systemGroupedBackground).opacity(0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
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
