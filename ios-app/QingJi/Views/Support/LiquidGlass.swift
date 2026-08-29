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
}

/// Reusable 44pt control matching the touch target and native glass press
/// animation used by iOS 26 system apps.
struct LiquidGlassIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass(.clear))
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
                .buttonStyle(.glassProminent)
        } else {
            Button(action: action) {
                Text(title)
            }
                .buttonStyle(.glass(.clear))
        }
    }
}
