import SwiftUI
import UIKit

/// Android 端的自动记账依赖 NotificationListenerService。
/// iOS 没有面向第三方 App 的等价系统权限，因此这里把同一目标拆成
/// iOS 真正支持的系统分享、Vision OCR 和 App Intents，而不是伪造后台监听状态。
struct AutoRecordView: View {
    var body: some View {
        List {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("iOS 不支持后台读取微信 / 支付宝通知")
                            .font(.body.weight(.medium))
                        Text("这是系统权限边界，不是肥喵的开关状态。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text("安卓端的通知监听服务可以在后台发现付款通知；iOS 不向第三方应用开放同等的全局通知读取权限，因此不会在后台偷偷读取其他 App 的通知。")
            }

            Section {
                NavigationLink {
                    AIQuickEntryView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("截图 / 账单识别")
                            Text("选择支付截图，使用 iOS Vision OCR 和当前 AI 解析")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "text.viewfinder")
                            .foregroundStyle(Color.accentColor)
                    }
                }

                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("系统分享扩展")
                        Text("从微信、支付宝或照片中分享文本 / 截图到肥喵")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(Color.accentColor)
                }

                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("快捷指令与 Siri")
                        Text("支持快速记一笔，也可配合轻点背面和截图 OCR")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(Color.accentColor)
                }
            } header: {
                Text("可用的自动入口")
            } footer: {
                Text("分享扩展和快捷指令仍由你主动触发；识别结果会先进入肥喵的记账流程，账目不会因为一条通知被静默写入。")
            }

            Section {
                Button {
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                } label: {
                    Label("打开肥喵的系统设置", systemImage: "gearshape")
                }
            } header: {
                Text("提醒")
            } footer: {
                Text("可在系统设置中管理照片、麦克风、通知和 Siri 权限。")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .liquidGlassCanvas()
        .navigationTitle("自动记账")
        .navigationBarTitleDisplayMode(.inline)
    }
}
