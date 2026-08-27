import Foundation

/// AI 退款只负责把一笔退款附着到已经存在的支出原单。
///
/// 该类型不读数据库、不执行写入；调用方提供当前可见的原始支出候选，
/// 只有唯一强匹配且金额不超过剩余可退金额时，才允许进入 LedgerStore。
public enum RefundMatchStatus: String, Codable, Equatable, Sendable {
    case notRefundMutation
    case missingAmount
    case noMatch
    case ambiguous
    case exceedsRemaining
    case matched
}

public struct RefundCandidate: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let label: String
    public let amount: Decimal
    public let refunded: Decimal
    public let date: Date

    public init(id: UUID, label: String, amount: Decimal, refunded: Decimal, date: Date) {
        self.id = id
        self.label = label
        self.amount = amount
        self.refunded = refunded
        self.date = date
    }

    public var remaining: Decimal {
        let value = amount - refunded
        return value > 0 ? value : 0
    }
}

public struct RefundMatchResult: Equatable, Sendable {
    public let status: RefundMatchStatus
    public let amount: Decimal?
    public let candidate: RefundCandidate?
    public let candidates: [RefundCandidate]

    public init(
        status: RefundMatchStatus,
        amount: Decimal? = nil,
        candidate: RefundCandidate? = nil,
        candidates: [RefundCandidate] = []
    ) {
        self.status = status
        self.amount = amount
        self.candidate = candidate
        self.candidates = candidates
    }

    public var isRefundMutation: Bool { status != .notRefundMutation }
}

/// 与 Android RefundMatcher 保持相同的保守匹配策略。
public enum RefundMatcher {
    public static func extractAmount(_ text: String) -> Decimal? {
        var value = text
        for pattern in [
            #"\d{4}[年./-]\d{1,2}[月./-]\d{1,2}日?"#,
            #"\d{1,2}月\d{1,2}[日号]"#,
            #"(?<!\d)\d{1,2}月(?!\d)"#
        ] {
            value = value.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return NaturalLanguageEntryParser.extractAmount(value)
    }

    public static func match(
        text: String,
        candidates: some Sequence<RefundCandidate>,
        amount: Decimal?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> RefundMatchResult {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty,
              raw.range(of: #"退款|退回|已退|退了|退给我|退我|refund"#, options: [.regularExpression, .caseInsensitive]) != nil else {
            return RefundMatchResult(status: .notRefundMutation)
        }
        if raw.range(of: #"多少|几笔|几次|合计|总计|统计|明细|记录有哪些|有哪些|哪一笔|哪笔|是什么|为什么|怎么|如何|是否|有没有|了吗|了没|吗[？?]?\s*$|查一下|查询|帮我查|算一下|占比|趋势"#, options: .regularExpression) != nil {
            return RefundMatchResult(status: .notRefundMutation)
        }
        guard let amount, amount > 0 else {
            return RefundMatchResult(status: .missingAmount)
        }

        let window = dateWindow(for: raw, now: now, calendar: calendar)
        var scoped = candidates.filter { candidate in
            guard candidate.amount > 0 else { return false }
            guard let window else { return true }
            return candidate.date >= window.start && candidate.date < window.endExclusive
        }
        if let window {
            scoped = scoped.filter { $0.date >= window.start && $0.date < window.endExclusive }
        }
        let pool = Array(scoped)
        guard !pool.isEmpty else {
            return RefundMatchResult(status: .noMatch, amount: amount)
        }

        let hint = normalizedHint(raw)
        var ranked: [(candidate: RefundCandidate, score: Double)] = []
        if hint.count >= 2 {
            for candidate in pool {
                let candidateHint = normalizedHint(candidate.label)
                let score = similarity(hint, candidateHint) + (window == nil ? 0 : 4)
                if score >= 76 {
                    ranked.append((candidate, score))
                }
            }
            ranked.sort { $0.score > $1.score }
        } else if window != nil,
                  raw.range(of: #"这笔|那笔|该笔|这一笔|那一笔"#, options: .regularExpression) != nil,
                  pool.count == 1 {
            ranked = [(pool[0], 80)]
        }

        guard let best = ranked.first else {
            return RefundMatchResult(status: .noMatch, amount: amount)
        }
        let close = ranked.dropFirst()
            .filter { best.score - $0.score < 8 }
            .map(\.candidate)
        if !close.isEmpty {
            return RefundMatchResult(
                status: .ambiguous,
                amount: amount,
                candidates: [best.candidate] + close
            )
        }
        if amount > best.candidate.remaining {
            return RefundMatchResult(
                status: .exceedsRemaining,
                amount: amount,
                candidate: best.candidate
            )
        }
        return RefundMatchResult(status: .matched, amount: amount, candidate: best.candidate)
    }

    private struct DateWindow {
        let start: Date
        let endExclusive: Date
    }

    private static func dateWindow(for text: String, now: Date, calendar: Calendar) -> DateWindow? {
        func singleDay(_ value: Date) -> DateWindow {
            let start = calendar.startOfDay(for: value)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return DateWindow(start: start, endExclusive: end)
        }

        if let groups = firstMatch(in: text, pattern: #"(\d{4})年(\d{1,2})月(\d{1,2})[日号]?"#),
           groups.count >= 4,
           let year = Int(groups[1]), let month = Int(groups[2]), let day = Int(groups[3]),
           let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) {
            return singleDay(date)
        }
        if let groups = firstMatch(in: text, pattern: #"(\d{1,2})月(\d{1,2})[日号]"#),
           groups.count >= 3,
           let month = Int(groups[1]), let day = Int(groups[2]),
           let date = calendar.date(from: DateComponents(
               year: calendar.component(.year, from: now), month: month, day: day
           )) {
            return singleDay(date)
        }
        if text.contains("大前天") { return singleDay(calendar.date(byAdding: .day, value: -3, to: now) ?? now) }
        if text.contains("前天") { return singleDay(calendar.date(byAdding: .day, value: -2, to: now) ?? now) }
        if text.contains("昨天") { return singleDay(calendar.date(byAdding: .day, value: -1, to: now) ?? now) }
        if text.contains("今天") { return singleDay(now) }

        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        if text.contains("上个月"),
           let start = calendar.date(from: DateComponents(year: year, month: month - 1, day: 1)),
           let end = calendar.date(from: DateComponents(year: year, month: month, day: 1)) {
            return DateWindow(start: start, endExclusive: end)
        }
        if text.contains("本月") || text.contains("这个月"),
           let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
           let end = calendar.date(from: DateComponents(year: year, month: month + 1, day: 1)) {
            return DateWindow(start: start, endExclusive: end)
        }
        if let groups = firstMatch(in: text, pattern: #"(?<!\d)(\d{1,2})月(?!\d)"#),
           groups.count >= 2,
           let targetMonth = Int(groups[1]), targetMonth >= 1, targetMonth <= 12 {
            let targetYear = targetMonth > month ? year - 1 : year
            guard let start = calendar.date(from: DateComponents(year: targetYear, month: targetMonth, day: 1)),
                  let end = calendar.date(from: DateComponents(year: targetYear, month: targetMonth + 1, day: 1)) else {
                return nil
            }
            return DateWindow(start: start, endExclusive: end)
        }
        return nil
    }

    private static func similarity(_ request: String, _ candidate: String) -> Double {
        guard candidate.count >= 2 else { return 0 }
        if request == candidate { return 100 }
        if request.contains(candidate) || candidate.contains(request) {
            return 90 - Double(min(abs(request.count - candidate.count), 8))
        }
        let left = bigrams(request)
        let right = bigrams(candidate)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let overlap = left.intersection(right).count
        let dice = (2.0 * Double(overlap)) / Double(left.count + right.count)
        return dice >= 0.5 ? 60 + dice * 40 : 0
    }

    private static func bigrams(_ value: String) -> Set<String> {
        let characters = Array(value)
        guard characters.count >= 2 else { return [] }
        return Set((0..<(characters.count - 1)).map { String(characters[$0...($0 + 1)]) })
    }

    private static func normalizedHint(_ value: String) -> String {
        var result = value.lowercased()
        for pattern in [
            #"\d{4}[年./-]\d{1,2}[月./-]\d{1,2}日?"#,
            #"\d{1,2}月\d{1,2}[日号]"#,
            #"\d{1,2}月"#,
            #"\d+(?:\.\d+)?\s*(?:元|块|块钱|人民币|￥|¥)?"#,
            #"[零〇一二两三四五六七八九十百千万]+(?:元|块|块钱|钱)"#,
            #"请帮我|帮我|给我|把这笔|把那笔|这一笔|那一笔|这笔|那笔|该笔|原来的|原订单|原单|订单|交易|消费|购买|买的|买了|买|付款了|支付了|之前|以前|上一次|上次|过往|历史|对应|已经|成功|到账|收到|记一下|记一笔|记上|入账|一下|今天|昨天|前天|大前天|本月|这个月|上个月|今年|去年|的|我|了"#,
            #"[^\u4e00-\u9fff a-z0-9]"#
        ] {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return result.replacingOccurrences(of: " ", with: "")
    }

    private static func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }
}
