import UIKit
import SwiftUI
import QingJiCore

/// 快记数字键盘：左侧 3 列数字 + 右侧功能列（删除、连加、保存）。
struct AmountKeypad: View {
    @Binding var expression: AmountExpression
    var onSave: () -> Void

    private let keyHeight: CGFloat = 56
    private let spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: spacing) {
            VStack(spacing: spacing) {
                row(["7", "8", "9"])
                row(["4", "5", "6"])
                row(["1", "2", "3"])
                HStack(spacing: spacing) {
                    digitKey(".") { expression.insertDot() }
                    digitKey("0") { expression.insertDigit("0") }
                    digitKey("C") { expression.clear() }
                }
            }

            VStack(spacing: spacing) {
                functionKey(systemImage: "delete.left") { expression.deleteBackward() }
                functionKey(systemImage: "plus") { expression.beginAddition() }
                Button(action: onSave) {
                    Text("保存")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: keyHeight * 2 + spacing)
                        .background(expression.value > 0 ? Color.accentColor : Color.accentColor.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(expression.value <= 0)
            }
            .frame(width: 84)
        }
        .padding(.horizontal)
    }

    private func row(_ digits: [String]) -> some View {
        HStack(spacing: spacing) {
            ForEach(digits, id: \.self) { digit in
                digitKey(digit) { expression.insertDigit(Character(digit)) }
            }
        }
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
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
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
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
