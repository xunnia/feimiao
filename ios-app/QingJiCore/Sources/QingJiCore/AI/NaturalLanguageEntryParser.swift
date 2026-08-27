import Foundation

/// 一句话记账的解析结果。
public struct ParsedEntry: Codable, Equatable, Sendable {
    public var amount: Decimal?
    public var kind: TransactionKind
    /// 匹配到的分类 key（对应 CategorySeed.key），nil 表示没识别出来。
    public var categoryKey: String?
    public var note: String
    public var date: Date
    /// 与 Android 的 transaction_time.dart 对齐。普通“今天/昨天”只代表
    /// 日期和提交时刻，不应在账单行中冒充用户明确提供了时分。
    public var timePrecision: TransactionTimePrecision
    /// 解析置信度，供上层决定是否需要用户确认。
    public var confidence: Double

    public init(
        amount: Decimal?,
        kind: TransactionKind,
        categoryKey: String?,
        note: String,
        date: Date,
        timePrecision: TransactionTimePrecision = .entryClock,
        confidence: Double = 0.7
    ) {
        self.amount = amount
        self.kind = kind
        self.categoryKey = categoryKey
        self.note = note
        self.date = date
        self.timePrecision = timePrecision
        self.confidence = confidence
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
        let rawAmount = extractAmount(trimmed)
        return ParsedEntry(
            amount: aaShare(trimmed, rawAmount),
            kind: kind,
            categoryKey: detectCategory(trimmed, kind: kind),
            note: trimmed,
            date: detectDate(trimmed, now: now, calendar: calendar),
            timePrecision: hasExplicitTime(trimmed) ? .exact : .entryClock,
            confidence: 0.55
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
        // 中文口语金额：三十块、两块五、一百二。
        let chineseDigits = "零〇一二两三四五六七八九十百千万"
        if let match = firstMatch(
            in: text,
            pattern: "([\(chineseDigits)]+)\\s*[块元]\\s*([一二两三四五六七八九])\\s*[毛角]?"
        ),
           match.count >= 3,
           let yuan = chineseInteger(match[1]),
           let jiao = chineseInteger(match[2]) {
            return Decimal(yuan) + Decimal(jiao) / 10
        }
        if let match = firstMatch(
            in: text,
            pattern: "([\(chineseDigits)]+)\\s*[块元]"
        ),
           match.count >= 2,
           let yuan = chineseInteger(match[1]) {
            return Decimal(yuan)
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
        let incomeMarkers = [
            "收入", "工资", "发薪", "奖金", "年终奖", "退款", "退了", "报销",
            "收到红包", "收红包", "收款", "到账", "到帐", "入账", "入帐",
            "失业金", "失业保险", "社保", "补贴", "津贴", "养老金", "退休金",
            "分红", "利息", "卖了"
        ]
        return incomeMarkers.contains(where: text.contains) ? .income : .expense
    }

    // MARK: - 日期

    static func detectDate(_ text: String, now: Date, calendar: Calendar) -> Date {
        let offsets: [(String, Int)] = [
            ("大前天", -3), ("前天", -2), ("昨天", -1), ("昨晚", -1),
            ("今天", 0), ("今早", 0), ("今晚", 0)
        ]
        for (word, offset) in offsets where text.contains(word) {
            let base = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            return applyExplicitTime(text, fallback: base, calendar: calendar)
        }

        // “13号失业金到账 2250”是常见补记方式。只有没有年月时才按当前月
        // 解释，避免把完整日期里的“13日”重复套回当前月份。
        let hasExplicitYearOrMonth = firstMatch(in: text, pattern: #"\d{1,4}\s*[年月]"#) != nil
        if !hasExplicitYearOrMonth,
           let match = firstMatch(in: text, pattern: #"(?<!\d)([1-3]?\d)\s*[号日](?!\d)"#),
           match.count >= 2,
           let day = Int(match[1]),
           let range = calendar.range(of: .day, in: .month, for: now),
           range.contains(day) {
            var components = calendar.dateComponents([.year, .month], from: now)
            components.day = day
            components.hour = calendar.component(.hour, from: now)
            components.minute = calendar.component(.minute, from: now)
            components.second = calendar.component(.second, from: now)
            let base = calendar.date(from: components) ?? now
            return applyExplicitTime(text, fallback: base, calendar: calendar)
        }
        return applyExplicitTime(text, fallback: now, calendar: calendar)
    }

    // MARK: - 分类

    /// 关键词 -> 分类 key 的优先级表（靠前的先匹配，避免「买菜」命中「购物-买」）。
    static let expenseKeywords: [(key: String, words: [String])] = [
        ("dining_drink", ["咖啡", "奶茶", "饮料", "酒水", "瑞幸", "星巴克", "coffee"]),
        ("dining_breakfast", ["早餐", "早饭", "包子", "豆浆", "油条"]),
        ("dining_lunch", ["午餐", "午饭", "中午饭"]),
        ("dining_dinner", ["晚餐", "晚饭", "夜宵", "宵夜"]),
        ("dining_treat", ["请客", "请吃饭", "聚餐", "饭局", "做东"]),
        ("groceries", ["买菜", "超市", "菜市场", "生鲜", "盒马", "grocery"]),
        ("dining_cook", ["粮油", "调味", "食用油", "大米", "酱油", "挂面"]),
        ("dining_snack", ["零食", "薯片", "瓜子", "小吃", "坚果"]),
        ("dining", ["外卖", "吃", "饭", "餐", "火锅", "烧烤", "美团", "饿了么", "lunch", "dinner"]),
        ("trans_taxi", ["打车", "滴滴", "出租", "网约车", "taxi", "uber"]),
        ("trans_public", ["地铁", "公交", "巴士", "metro"]),
        ("trans_train", ["高铁", "火车", "动车", "12306"]),
        ("trans_flight", ["机票", "航班", "飞机", "flight"]),
        ("trans_fuel", ["加油", "油费"]),
        ("trans_park", ["停车", "停车费"]),
        ("travel", ["酒店", "门票", "旅游", "旅行", "民宿", "hotel"]),
        ("house_phone", ["话费", "宽带", "流量", "网费"]),
        ("utilities", ["电费"]),
        ("house_water", ["水费"]),
        ("house_gas", ["燃气", "天然气"]),
        ("house_property", ["物业"]),
        ("house_rent", ["房租", "房贷", "租金", "rent"]),
        ("med_drug", ["药", "药店", "大药房"]),
        ("med_checkup", ["体检"]),
        ("med_clinic", ["医院", "挂号", "看病", "门诊", "hospital"]),
        ("edu_book", ["买书", "书店", "图书"]),
        ("edu_course", ["学费", "培训", "网课", "课程", "课", "course"]),
        ("ent_movie", ["电影", "KTV", "唱歌", "演唱会", "音乐会", "movie"]),
        ("ent_game", ["游戏", "剧本杀", "桌游", "棋牌", "game"]),
        ("pets", ["猫", "狗", "宠物", "猫粮", "狗粮", "pet"]),
        ("gift_red", ["随礼", "份子", "发红包", "给红包"]),
        ("gift_present", ["礼物", "送礼", "gift"]),
        ("subscription", ["会员", "订阅", "续费", "subscription"]),
        ("shopping", ["买", "购物", "淘宝", "京东", "拼多多", "网购", "衣服", "鞋", "shopping"]),
    ]

    static let incomeKeywords: [(key: String, words: [String])] = [
        ("salary", ["工资", "发薪", "薪水", "salary"]),
        ("inc_salary_allow", ["餐补", "交通补", "住房补", "通讯补"]),
        ("bonus", ["奖金", "年终奖", "bonus"]),
        ("investment", ["理财", "基金", "股票", "分红", "利息", "investment"]),
        ("pension", ["养老金", "退休金"]),
        ("inc_subsidy", ["失业金", "失业保险", "社保", "政府补助", "补助", "补贴", "津贴"]),
        ("redPacket", ["红包"]),
        ("refund", ["退款", "退了", "报销", "refund"]),
        ("otherIncome", ["到账", "到帐", "入账", "入帐", "收款"]),
    ]

    static func detectCategory(_ text: String, kind: TransactionKind) -> String? {
        if let dictionaryKey = MerchantCategory.classify(text, kind: kind) {
            return dictionaryKey
        }
        let table = kind == .income ? incomeKeywords : expenseKeywords
        for entry in table where entry.words.contains(where: text.contains) {
            return entry.key
        }
        return nil
    }

    /// 给导入分类器复用的一句话分类入口；结果始终是稳定分类 key。
    public static func guessCategory(_ text: String, kind: TransactionKind) -> String? {
        detectCategory(text, kind: kind)
    }

    // MARK: - 口语与时间辅助

    private static func aaShare(_ text: String, _ total: Decimal?) -> Decimal? {
        guard let total, total > 0,
              text.range(of: #"AA|aa|均摊|平摊|分摊|各付|各自付"#, options: .regularExpression) != nil,
              let match = firstMatch(in: text, pattern: #"(\d+)\s*(?:个人|人)"#),
              match.count >= 2,
              let people = Int(match[1]), people > 1 else {
            return total
        }
        var result = total / Decimal(people)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &result, 2, .plain)
        return rounded
    }

    private static func chineseInteger(_ value: String) -> Int? {
        let digits: [Character: Int] = [
            "零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3,
            "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
        ]
        let units: [Character: Int] = ["十": 10, "百": 100, "千": 1000]
        guard !value.isEmpty else { return nil }
        var section = 0
        var number = 0
        var result = 0
        var lastUnit = 0
        var bareUnits = false
        var found = false
        for character in value {
            if character == "零" || character == "〇" {
                bareUnits = true
                number = 0
                found = true
            } else if let digit = digits[character] {
                number = digit
                found = true
            } else if let unit = units[character] {
                section += (number == 0 ? 1 : number) * unit
                lastUnit = unit
                bareUnits = false
                number = 0
                found = true
            } else if character == "万" {
                let base = section + number
                result += (base == 0 ? 1 : base) * 10000
                section = 0
                number = 0
                lastUnit = 10000
                bareUnits = false
                found = true
            } else {
                return nil
            }
        }
        if number != 0 {
            section += (!bareUnits && lastUnit >= 10) ? number * (lastUnit / 10) : number
        }
        return found ? result + section : nil
    }

    private static func hasExplicitTime(_ text: String) -> Bool {
        firstMatch(
            in: text,
            pattern: #"(?:凌晨|早上|上午|中午|下午|晚上|昨晚|今晚|今早)?\s*\d{1,2}\s*(?::|：|点|时)\s*\d{0,2}\s*分?"#
        ) != nil
    }

    private static func applyExplicitTime(_ text: String, fallback: Date, calendar: Calendar) -> Date {
        guard let match = firstMatch(
            in: text,
            pattern: #"(凌晨|早上|上午|中午|下午|晚上|昨晚|今晚|今早)?\s*(\d{1,2})\s*(?::|：|点|时)\s*(\d{1,2})?\s*分?"#
        ),
        match.count >= 3,
        var hour = Int(match[2]),
        hour <= 23,
        let minute = Int(match.count >= 4 ? match[3] : "0"),
        minute <= 59 else {
            return fallback
        }
        let period = match[1]
        if (period == "下午" || period.contains("晚")) && hour < 12 { hour += 12 }
        if period.contains("晚") && hour == 12 { hour = 0 }
        if period == "中午" && hour < 11 { hour += 12 }
        if period == "凌晨" && hour == 12 { hour = 0 }

        var components = calendar.dateComponents([.year, .month, .day], from: fallback)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components) ?? fallback
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
