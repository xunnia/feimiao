import SwiftUI

/// 设置 →「关于」里的使用条款 / 隐私政策。文字与安卓「关于」弹窗逐字一致，改一端要同步另一端。
enum LegalText {
    static let terms = [
        "肥喵记账用于个人记账、账单整理和消费分析。你需要自行确认录入、导入和 AI 识别结果是否准确。",
        "AI 记账和 AI 分析可能产生错误，涉及金额、分类、退款和统计结论时，请以你的真实账单和银行、支付平台记录为准。",
        "你应妥善保管自己的设备、备份文件和 API Key。因误删、误导入、第三方服务异常或设备故障造成的数据损失，建议优先通过备份恢复。"
    ]

    static let privacy = [
        "肥喵记账默认将账本数据保存在本机。完整备份会包含账本数据库和收据图片，但不会包含 AI API Key。",
        "当你使用 AI 解析或 AI 分析时，相关文本、账单摘要或你输入的问题可能会发送给你配置的 AI 服务提供方，用于生成结果。请避免提交身份证号、银行卡号、验证码等敏感信息。",
        "导入、导出和分享备份文件由你主动触发。请只把备份文件保存到你信任的位置。"
    ]
}

struct LegalTextView: View {
    let title: String
    let paragraphs: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(paragraphs, id: \.self) { paragraph in
                    Text(paragraph)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .liquidGlassSurface(cornerRadius: 20)
            .padding(16)
        }
        .liquidGlassCanvas()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
