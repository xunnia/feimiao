import SwiftUI
import UIKit

/// A quiet, content-bearing backdrop makes Liquid Glass read as translucent
/// glass instead of an opaque white pill on a flat system background.
struct LiquidGlassBackdrop: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)

            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.10),
                    Color.purple.opacity(0.045),
                    Color(uiColor: .systemGroupedBackground).opacity(0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.accentColor.opacity(0.10))
                .frame(width: 240, height: 240)
                .blur(radius: 58)
                .offset(x: 150, y: -330)

            Circle()
                .fill(Color.purple.opacity(0.06))
                .frame(width: 210, height: 210)
                .blur(radius: 64)
                .offset(x: -150, y: 360)
        }
        .accessibilityHidden(true)
    }
}

/// Shared app chrome for the iOS 26 Liquid Glass hierarchy.
struct LiquidGlassChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .tint(Color.accentColor)
            .buttonStyle(.glass)
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
        .buttonStyle(.glass)
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
                .buttonStyle(.glass)
        }
    }
}
