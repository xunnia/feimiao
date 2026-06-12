import Foundation

/// 资金账户类型。
public enum AccountKind: String, Codable, CaseIterable, Sendable {
    case cash
    case bankCard
    case creditCard
    case weChat
    case alipay
    case other

    /// 账户类型对应的 SF Symbol 图标名。
    public var symbol: String {
        switch self {
        case .cash: return "banknote"
        case .bankCard: return "creditcard"
        case .creditCard: return "creditcard.fill"
        case .weChat: return "message.fill"
        case .alipay: return "a.circle.fill"
        case .other: return "wallet.pass"
        }
    }
}
