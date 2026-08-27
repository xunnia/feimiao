import Foundation

/// 账单卡片的标题优先级。与 Android 的 transaction_card_display.dart
/// 使用相同的持久化值，iOS 只替换呈现控件。
public enum TransactionCardDisplayMode: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case contentFirst = "content_first"
    case categoryFirst = "category_first"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .contentFirst: return "内容优先"
        case .categoryFirst: return "分类优先"
        }
    }
}

/// 喵助手用户消息气泡的背景策略。
public enum UserMessageBubbleStyle: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case followCardOpacity = "follow_card_opacity"
    case fixedGray = "fixed_gray"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .followCardOpacity: return "跟随卡片透明度"
        case .fixedGray: return "固定灰底"
        }
    }
}

public struct TransactionCardText: Equatable, Sendable {
    public let title: String
    public let secondary: String

    public init(title: String, secondary: String = "") {
        self.title = title
        self.secondary = secondary
    }
}

/// 同一条流水在 Android/iOS 上采用相同的信息层级，避免只因换平台就
/// 让用户先看到不同的字段。
public func resolveTransactionCardText(
    mode: TransactionCardDisplayMode,
    kind: TransactionKind,
    note: String,
    categoryName: String,
    accountName: String = "",
    toAccountName: String = ""
) -> TransactionCardText {
    let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanCategory: String
    if !categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        cleanCategory = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
        cleanCategory = kind == .income ? "其他收入" : "未分类"
    }

    if kind == .transfer {
        let from = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = toAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
        let route: String
        if !from.isEmpty && !to.isEmpty {
            route = "\(from) → \(to)"
        } else if !from.isEmpty {
            route = from
        } else if !to.isEmpty {
            route = to
        } else {
            route = "转账"
        }
        return TransactionCardText(title: route, secondary: cleanNote)
    }

    if mode == .contentFirst && !cleanNote.isEmpty {
        return TransactionCardText(title: cleanNote, secondary: cleanCategory)
    }
    return TransactionCardText(title: cleanCategory, secondary: cleanNote)
}

/// 日期分组账单行的附加时间文本。日期精度不足时不伪造时分。
public func transactionCardTimeLabel(
    _ date: Date,
    dateGrouped: Bool,
    precision: TransactionTimePrecision
) -> String {
    let showClock = precision == .exact || precision == .entryClock
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = dateGrouped ? "HH:mm" : (showClock ? "yyyy/MM/dd HH:mm" : "yyyy/MM/dd")
    return dateGrouped && !showClock ? "" : formatter.string(from: date)
}

public func joinTransactionCardDetails(_ parts: [String]) -> String {
    parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
}
