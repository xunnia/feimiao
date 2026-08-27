import UIKit
import SwiftUI
import QingJiCore

/// 与 Android「账单与聊天显示」对应的 iOS 原生设置页。
struct TransactionDisplaySettingsView: View {
    @AppStorage("qingji.transactionCardDisplayMode") private var displayModeRaw = TransactionCardDisplayMode.contentFirst.rawValue
    @AppStorage("qingji.userMessageBubbleStyle") private var bubbleStyleRaw = UserMessageBubbleStyle.followCardOpacity.rawValue

    private var displayMode: Binding<TransactionCardDisplayMode> {
        Binding(
            get: { TransactionCardDisplayMode(rawValue: displayModeRaw) ?? .contentFirst },
            set: { displayModeRaw = $0.rawValue }
        )
    }

    private var bubbleStyle: Binding<UserMessageBubbleStyle> {
        Binding(
            get: { UserMessageBubbleStyle(rawValue: bubbleStyleRaw) ?? .followCardOpacity },
            set: { bubbleStyleRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("账单卡片") {
                Picker("标题优先级", selection: displayMode) {
                    ForEach(TransactionCardDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                TransactionPreview(mode: displayMode.wrappedValue)
            }
            Section("用户消息气泡") {
                Picker("背景", selection: bubbleStyle) {
                    ForEach(UserMessageBubbleStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.inline)
                HStack {
                    Spacer()
                    Text("原神充值 648 元")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            bubbleStyle.wrappedValue == .followCardOpacity
                                ? Color.accentColor.opacity(0.12)
                                : Color(.secondarySystemBackground),
                            in: .rect(cornerRadius: 16)
                        )
                }
            }
        }
        .navigationTitle("账单与聊天显示")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TransactionPreview: View {
    let mode: TransactionCardDisplayMode

    var body: some View {
        let text = resolveTransactionCardText(
            mode: mode,
            kind: .expense,
            note: "原神充值",
            categoryName: "虚拟充值"
        )
        HStack(spacing: 10) {
            Text("🎮")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(text.title).font(.subheadline.weight(.medium))
                Text(joinTransactionCardDetails(["21:08", text.secondary]))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("-¥648.00")
                .font(.subheadline.monospacedDigit().weight(.semibold))
        }
        .padding(.vertical, 4)
    }
}
