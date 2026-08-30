import UIKit
import SwiftUI
import QingJiCore

/// 与 Android 手动记账完全同序的 4×4 数字键盘。
/// 全键采用 iOS 26 液态玻璃（Liquid Glass），按压有玻璃形变反馈。
struct AmountKeypad: View {
    @Binding var expression: AmountExpression
    var onSave: () -> Void
    var onSaveAgain: (() -> Void)? = nil
    var saveLabel = "完成"

    private let keyHeight: CGFloat = 52
    private let spacing: CGFloat = 8

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
                GridRow {
                    digitKey("1") { expression.insertDigit("1") }
                    digitKey("2") { expression.insertDigit("2") }
                    digitKey("3") { expression.insertDigit("3") }
                    functionKey(systemImage: "delete.left") { expression.deleteBackward() }
                }
                GridRow {
                    digitKey("4") { expression.insertDigit("4") }
                    digitKey("5") { expression.insertDigit("5") }
                    digitKey("6") { expression.insertDigit("6") }
                    functionKey(systemImage: "plus") { expression.beginAddition() }
                }
                GridRow {
                    digitKey("7") { expression.insertDigit("7") }
                    digitKey("8") { expression.insertDigit("8") }
                    digitKey("9") { expression.insertDigit("9") }
                    functionKey(systemImage: "minus") { expression.beginSubtraction() }
                }
                GridRow {
                    textKey(onSaveAgain == nil ? "C" : "再记", enabled: expression.value > 0 || onSaveAgain == nil) {
                        if let onSaveAgain { onSaveAgain() } else { expression.clear() }
                    }
                    digitKey("0") { expression.insertDigit("0") }
                    digitKey(".") { expression.insertDot() }
                    primaryKey(saveLabel, action: onSave)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private func digitKey(_ label: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Text(label)
                .font(.title2.weight(.medium))
                .frame(maxWidth: .infinity)
                .frame(height: keyHeight)
        }
        .liquidGlassKeyControl(cornerRadius: 14)
    }

    private func functionKey(systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(maxWidth: .infinity)
                .frame(height: keyHeight)
        }
        .liquidGlassKeyControl(cornerRadius: 14)
    }

    private func textKey(_ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.headline.weight(.medium))
                .frame(maxWidth: .infinity)
                .frame(height: keyHeight)
        }
        .liquidGlassKeyControl(cornerRadius: 14)
        .disabled(!enabled)
    }

    private func primaryKey(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.headline.weight(.medium))
                .frame(maxWidth: .infinity)
                .frame(height: keyHeight)
        }
        .liquidGlassPrimaryKeyControl(
            cornerRadius: 14,
            tint: expression.value > 0 ? Color.accentColor.opacity(0.82) : Color.gray.opacity(0.30)
        )
        .disabled(expression.value <= 0)
    }
}
