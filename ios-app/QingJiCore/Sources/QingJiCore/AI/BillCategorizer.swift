import Foundation

public enum BillCategoryConfidence: String, Codable, Sendable {
    case high
    case medium
    case low
}

public struct BillCategoryGuess: Equatable, Sendable {
    public let key: String?
    public let confidence: BillCategoryConfidence

    public init(key: String?, confidence: BillCategoryConfidence) {
        self.key = key
        self.confidence = confidence
    }

    public static let none = BillCategoryGuess(key: nil, confidence: .low)
}

/// 账单分类决策顺序，与 Android BillCategorizer 保持一致。
/// 商品信号优先；万能平台只给安全的顶级分类；无法确定时由复核页处理。
public enum BillCategorizer {
    public static let platformDefaults: [String: String] = [
        "京东": "shopping", "淘宝": "shopping", "天猫": "shopping",
        "拼多多": "shopping", "苏宁": "shopping", "唯品会": "shopping",
        "闲鱼": "shopping", "得物": "shopping", "1688": "shopping",
        "美团": "dining", "饿了么": "dining",
        "抖音": "shopping", "快手": "shopping"
    ]

    /// 去掉订单号、平台后缀和转账备注，得到可用于学习的稳定商户名。
    public static func normalizeMerchant(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        value = replacing(value, pattern: #"(收款方备注|转账备注|备注)[:：].*$"#)
        value = replacing(value, pattern: #"商城平台商户|平台商户|旗舰店|官方旗舰店|-?退款|扫二维码付款|散单"#)
        value = replacing(value, pattern: #"订单\s*(编号|号)?\s*[-:：]?\s*[A-Za-z0-9]+"#)
        value = replacing(value, pattern: #"[-_·:：]?\s*[A-Za-z]*\d{5,}[A-Za-z0-9]*"#)
        value = replacing(value, pattern: #"^[-_·:：\s]+|[-_·:：\s]+$"#)
        value = replacing(value, pattern: #"\s+"#, replacement: " ")
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func matchedPlatform(_ merchant: String) -> String? {
        platformDefaults.keys.sorted { $0.count > $1.count }.first { merchant.contains($0) }
    }

    public static func classify(
        merchant: String,
        product: String,
        note: String,
        kind: TransactionKind
    ) -> BillCategoryGuess {
        if let key = fromText(product, kind: kind) {
            return BillCategoryGuess(key: key, confidence: .high)
        }

        let normalizedMerchant = normalizeMerchant(merchant)
        if let platform = matchedPlatform(normalizedMerchant) {
            return BillCategoryGuess(key: platformDefaults[platform], confidence: .medium)
        }
        if let key = fromText(normalizedMerchant, kind: kind) {
            return BillCategoryGuess(key: key, confidence: .high)
        }
        if let key = fromText(note, kind: kind) {
            return BillCategoryGuess(key: key, confidence: .low)
        }
        return .none
    }

    /// 只有决定性商户才写入商户级学习记忆，电商平台不学习，避免一次购买污染所有后续订单。
    public static func learnKey(for merchant: String) -> String? {
        let normalized = normalizeMerchant(merchant)
        guard !normalized.isEmpty, matchedPlatform(normalized) == nil else { return nil }
        return normalized
    }

    private static func replacing(_ value: String, pattern: String, replacement: String = "") -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..., in: value)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: replacement)
    }

    private static func fromText(_ text: String, kind: TransactionKind) -> String? {
        MerchantCategory.classify(text, kind: kind)
            ?? NaturalLanguageEntryParser.guessCategory(text, kind: kind)
    }
}
