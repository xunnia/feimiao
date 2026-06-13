import SwiftUI

extension Color {
    /// 收入/正向金额 —— 品牌蓝（中性化方案：收入用蓝不用绿）
    static let income = Color.accentColor
    /// 支出/普通金额 —— 中性文本色（中性化方案：支出用灰不用红）
    static let expense = Color.primary
    /// 警示（超支、负结余、今日已超）—— 柔和橙，避免刺激的红
    static let warning = Color(red: 0.90, green: 0.49, blue: 0.13)
}
