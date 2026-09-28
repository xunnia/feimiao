import SwiftUI
import UIKit

extension Color {
    /// 收入/正向金额 —— 收入绿（与 Android AppColors.income 同值：浅色 5B9A4B / 深色 93C77F）
    static let income = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x93 / 255, green: 0xC7 / 255, blue: 0x7F / 255, alpha: 1)
            : UIColor(red: 0x5B / 255, green: 0x9A / 255, blue: 0x4B / 255, alpha: 1)
    })
    /// 支出/普通金额 —— 中性文本色（中性化方案：支出用灰不用红）
    static let expense = Color.primary
    /// 警示（超支、负结余、今日已超）—— 柔和橙，避免刺激的红
    static let warning = Color(red: 0.90, green: 0.49, blue: 0.13)
    /// 预算健康绿（预算条/圆环起点，与 Android budgetHealthy 7FB069 同值）
    static let budgetHealthy = Color(red: 0x7F / 255, green: 0xB0 / 255, blue: 0x69 / 255)
    /// 超出 100% 预算的部分 —— 比 warning 更深的橙（与 Android overspendDeep D9602E 同值）
    static let overspendDeep = Color(red: 0xD9 / 255, green: 0x60 / 255, blue: 0x2E / 255)
}
