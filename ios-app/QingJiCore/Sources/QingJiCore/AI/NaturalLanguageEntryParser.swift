import Foundation

/// 一句话记账的解析结果。
public struct ParsedEntry: Equatable, Sendable {
    public var amount: Decimal?
    public var kind: TransactionKind
    /// 匹配到的分类 key（对应 CategorySeed.key），nil 表示没识别出来。
    public var categoryKey: String?
    public var note: String
    public var date: Date

    public init(amount: Decimal?, kind: TransactionKind, categoryKey: String?, note: String, date: Date) {
        self.amount = amount
        self.kind = kind
        self.categoryKey = categoryKey
        self.note = note
        self.date = date
    }
}

/// 本地规则版「一句话记账」解析器：
/// 「昨天打车23块」→ 支出 / 交通 / 23 元 / 昨天。
/// 纯本地、零网络，后续可在 App 层用云端 LLM 替换（同样产出 ParsedEntry）。
public enum NaturalLanguageEntryParser {
    public static func parse(
        _ text: String,
        at now: Date = Date(),
        calendar: Calendar = .current
    ) -> ParsedEntry {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = detectKind(trimmed)
        return ParsedEntry(
            amount: extractAmount(trimmed),
            kind: kind,
            categoryKey: detectCategory(trimmed, kind: kind),
            note: trimmed,
            date: detectDate(trimmed, now: now, calendar: calendar)
        )
    }

    // MARK: - 金额

    /// 提取金额。优先「X块Y」口语格式，其次带货币标记（¥/元/块/刀）的数字，最后取文本中最后一个数字。
    public static func extractAmount(_ text: String) -> Decimal? {
        // “23块5” -> 23.5
        if let match = firstMatch(in: text, pattern: #"(\d+)[块元]([1-9])\b"#),
           match.count >= 3,
           let yuan = Decimal(string: match[1]), let jiao = Decimal(string: match[2]) {
            return yuan + jiao / 10
        }
        // 带货币标记的数字：¥23.5 / 23.5元 / 23块 / 23.5刀
        if let match = firstMatch(in: text, pattern: #"[¥￥]\s*(\d+(?:\.\d{1,2})?)"#) ??
            firstMatch(in: text, pattern: #"(\d+(?:\.\d{1,2})?)\s*[块元刀]"#),
           match.count >= 2 {
            return Decimal(string: match[1])
        }
        // 兜底：最后一个数字（“买了2杯咖啡58” -> 58）
        let all = allMatches(in: text, pattern: #"(\d+(?:\.\d{1,2})?)"#)
        if let last = all.last, last.count >= 2 {
            return Decimal(string: last[1])
        }
        return nil
    }

    // MARK: - 收支方向

    static func detectKind(_ text: String) -> TransactionKind {
        let incomeMarkers = ["收入", "工资", "发薪", "奖金", "年终奖", "退款", "退了", "报销", "收到红包", "收红包", "分红", "利息", "卖了"]
        return incomeMarkers.contains(where: text.contains) ? .income : .expense
    }

    // MARK: - 日期

    static func detectDate(_ text: String, now: Date, calendar: Calendar) -> Date {
        let offsets: [(String, Int)] = [("大前天", -3), ("前天", -2), ("昨天", -1), ("昨晚", -1), ("今天", 0), ("今早", 0), ("今晚", 0)]
        for (word, offset) in offsets where text.contains(word) {
            return calendar.date(byAdding: .day, value: offset, to: now) ?? now
        }
        return now
    }

    // MARK: - 分类

    /// 关键词 -> 分类 key 的优先级表（靠前的先匹配，避免「买菜」命中「购物-买」）。
    static let expenseKeywords: [(key: String, words: [String])] = [
        ("groceries", ["买菜", "超市", "菜市场", "生鲜", "grocery"]),
        ("dining", ["早餐", "午餐", "晚餐", "夜宵", "外卖", "吃", "饭", "餐", "咖啡", "奶茶", "火锅", "烧烤", "面", "lunch", "dinner", "coffee"]),
        ("transport", ["打车", "滴滴", "出租", "地铁", "公交", "高铁", "火车", "加油", "油费", "停车", "taxi", "uber", "metro"]),
        ("travel", ["机票", "酒店", "门票", "旅游", "旅行", "民宿", "flight", "hotel"]),
        ("housing", ["房租", "物业", "房贷", "rent"]),
        ("utilities", ["水费", "电费", "燃气", "网费", "话费", "宽带", "流量"]),
        ("medical", ["医院", "挂号", "药", "体检", "看病", "牙", "hospital"]),
        ("education", ["学费", "课", "培训", "书", "网课", "course"]),
        ("entertainment", ["电影", "游戏", "KTV", "演唱会", "音乐会", "剧本杀", "桌游", "movie", "game"]),
        ("pets", ["猫", "狗", "宠物", "猫粮", "狗粮", "pet"]),
        ("gifts", ["随礼", "份子", "礼物", "发红包", "给红包", "gift"]),
        ("subscription", ["会员", "订阅", "续费", "subscription"]),
        ("shopping", ["买", "购物", "淘宝", "京东", "拼多多", "网购", "衣服", "鞋", "shopping"]),
    ]

    static let incomeKeywords: [(key: String, words: [String])] = [
        ("salary", ["工资", "发薪", "薪水", "salary"]),
        ("bonus", ["奖金", "年终奖", "bonus"]),
        ("investment", ["理财", "基金", "股票", "分红", "利息", "investment"]),
        ("redPacket", ["红包"]),
        ("refund", ["退款", "退了", "报销", "refund"]),
    ]

    static func detectCategory(_ text: String, kind: TransactionKind) -> String? {
        let table = kind == .income ? incomeKeywords : expenseKeywords
        for entry in table where entry.words.contains(where: text.contains) {
            return entry.key
        }
        return nil
    }

    // MARK: - 正则工具

    private static func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return groups(of: match, in: text)
    }

    private static func allMatches(in text: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { groups(of: $0, in: text) }
    }

    private static func groups(of match: NSTextCheckingResult, in text: String) -> [String] {
        (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }
}

/// 支付截图 OCR 文本的金额提取（微信/支付宝支付完成页、账单详情页）。
public enum PaymentScreenshotParser {
    /// 从 OCR 出来的多行文本里找「这笔交易的金额」：
    /// 优先带 ¥/￥/− 标记的大号金额行，其次任何两位小数的数字，取金额最大者
    /// （支付页上余额/积分一般比交易额小或无小数）。
    public static func extractAmount(fromOCRText text: String) -> Decimal? {
        var marked: [Decimal] = []
        var plain: [Decimal] = []
        guard let regex = try? NSRegularExpression(pattern: #"([-−¥￥]?)\s*(\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)"#) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            guard let markRange = Range(match.range(at: 1), in: text),
                  let numberRange = Range(match.range(at: 2), in: text) else { continue }
            let numberText = text[numberRange].replacingOccurrences(of: ",", with: "")
            guard let value = Decimal(string: numberText), value > 0 else { continue }
            if !text[markRange].isEmpty {
                marked.append(value)
            } else if numberText.contains(".") {
                plain.append(value)
            }
        }
        return marked.max() ?? plain.max()
    }
}
