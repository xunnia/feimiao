import Foundation

/// 资金账户类型。
public enum AccountKind: String, Codable, CaseIterable, Hashable, Sendable {
    case cash
    case bankCard
    case creditCard
    case savings
    case investment
    case loan
    case weChat
    case alipay
    case other

    /// 账户类型对应的 SF Symbol 图标名。
    public var symbol: String {
        switch self {
        case .cash: return "banknote"
        case .bankCard: return "creditcard"
        case .creditCard: return "creditcard.fill"
        case .savings: return "banknote"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .loan: return "doc.text.magnifyingglass"
        case .weChat: return "message.fill"
        case .alipay: return "a.circle.fill"
        case .other: return "wallet.pass"
        }
    }

    /// 信用卡和贷款的账面余额属于负债类账户。
    public var isLiability: Bool {
        self == .creditCard || self == .loan
    }
}
