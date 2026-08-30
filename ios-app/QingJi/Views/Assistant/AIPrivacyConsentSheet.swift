import SwiftUI

/// 第一次向某个 AI 服务商发送账本上下文/主动选择的附件前的授权页。
struct AIPrivacyConsentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let account: AIProviderAccount
    let includesAttachment: Bool
    let onAccept: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Label(account.displayName, systemImage: "lock.shield")
                    .font(.title3.weight(.semibold))
                Text("肥喵会把本次问题发送给你选择的服务商，用于生成回答。")
                    .font(.body)
                VStack(alignment: .leading, spacing: 9) {
                    Label("会发送：本次问题和必要的账本统计/近期记录", systemImage: "arrow.up.circle")
                    if includesAttachment {
                        Label("会发送：你主动选择的图片或文件附件", systemImage: "paperclip")
                    }
                    Label("不会发送：本机 API Key、OAuth refresh token", systemImage: "checkmark.shield")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Text("你可以在 AI 设置中随时重置授权。切换到其他服务商时会再次确认。")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("同意并继续") {
                    onAccept()
                    dismiss()
                }
                .liquidGlassPrimaryPillControl(horizontalPadding: 18, minHeight: 48)
                .frame(maxWidth: .infinity)
            }
            .padding(22)
            .navigationTitle("隐私与数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("暂不") { dismiss() }
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
