import Foundation

/// AI 记账入口的结构化意图。与 Android LlmIntent 的三态保持一致，
/// 但首页/快速记账只接受 record，避免把一句账务描述误当成聊天或查账。
public enum AIRecordIntent: String, Codable, Equatable, Sendable {
    case record
    case query
    case chat
}

/// 一个结构化 AI 响应。它是值类型，页面可以先展示和修改，用户确认后
/// 才交给 LedgerStore 写入 SwiftData。
public struct AIRecordParseResult: Equatable, Sendable {
    public let intent: AIRecordIntent
    public let entries: [ParsedEntry]

    public init(intent: AIRecordIntent, entries: [ParsedEntry]) {
        self.intent = intent
        self.entries = entries
    }
}

/// 对 Chat Completions、Responses 和兼容网关返回文本的统一容错解析。
///
/// 模型偶尔会包一层 Markdown code fence，或者把 amount/confidence 编成
/// 字符串；这里集中兼容这些非业务差异，业务层只消费经过金额、日期、分类
/// 和精度清洗的 ParsedEntry。
public enum AIRecordProposalCodec {
    public static func decode(
        _ raw: String,
        fallbackDate: Date = Date(),
        allowedCategoryKeys: Set<String>? = nil,
        calendar: Calendar = .current
    ) -> AIRecordParseResult? {
        guard let json = extractJSONObject(from: raw),
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let intent = AIRecordIntent(rawValue: (object["intent"] as? String)?.lowercased() ?? "record") ?? .record
        let rawEntries = object["entries"] as? [Any] ?? []
        let entries = rawEntries.compactMap { value -> ParsedEntry? in
            guard let item = value as? [String: Any] else { return nil }
            return parseEntry(
                item,
                fallbackDate: fallbackDate,
                allowedCategoryKeys: allowedCategoryKeys,
                calendar: calendar
            )
        }
        return AIRecordParseResult(intent: intent, entries: entries)
    }

    /// 从可能带说明文字或 code fence 的模型响应中取出第一个完整 JSON 对象。
    public static func extractJSONObject(from raw: String) -> String? {
        let characters = Array(raw)
        guard let start = characters.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false

        for index in start..<characters.count {
            let character = characters[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(characters[start...index])
                }
            }
        }
        return nil
    }

    private static func parseEntry(
        _ item: [String: Any],
        fallbackDate: Date,
        allowedCategoryKeys: Set<String>?,
        calendar: Calendar
    ) -> ParsedEntry? {
        let kind: TransactionKind = (item["kind"] as? String)?.lowercased() == "income" ? .income : .expense
        let amount = parseDecimal(item["amount"]) ?? parseDecimal(item["amt"])
        let cleanedAmount: Decimal? = {
            guard let amount, amount > 0, amount <= 100_000_000 else { return nil }
            var rounded = Decimal()
            var value = amount
            NSDecimalRound(&rounded, &value, 2, .plain)
            return rounded
        }()

        let category = (item["categoryKey"] as? String ?? item["catKey"] as? String)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { key in
                guard !key.isEmpty,
                      allowedCategoryKeys == nil || allowedCategoryKeys!.contains(key) else { return nil }
                return key
            }
        let note = (item["note"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawDate = (item["date"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedDate = parseDate(rawDate, fallback: fallbackDate, calendar: calendar)
        let confidence = min(max(parseDouble(item["confidence"] ?? item["conf"]) ?? 0.7, 0), 1)

        return ParsedEntry(
            amount: cleanedAmount,
            kind: kind,
            categoryKey: category,
            note: note,
            date: clampFutureDay(parsedDate.date, to: fallbackDate, calendar: calendar),
            timePrecision: parsedDate.precision,
            confidence: confidence
        )
    }

    private static func parseDecimal(_ value: Any?) -> Decimal? {
        if let decimal = value as? Decimal { return decimal }
        if let number = value as? NSNumber {
            return Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX"))
        }
        if let string = value as? String {
            return Decimal(string: string.trimmingCharacters(in: .whitespacesAndNewlines), locale: Locale(identifier: "en_US_POSIX"))
        }
        return nil
    }

    private static func parseDouble(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private static func parseDate(
        _ raw: String,
        fallback: Date,
        calendar: Calendar
    ) -> (date: Date, precision: TransactionTimePrecision) {
        guard !raw.isEmpty else { return (fallback, .entryClock) }
        if raw.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            if let day = formatter.date(from: raw) {
                return (calendarDayWithClock(day, clock: fallback, calendar: calendar), .entryClock)
            }
            return (fallback, .entryClock)
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) {
            return (date, .exact)
        }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) {
            return (date, .exact)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return (formatter.date(from: raw).map { ($0, .exact) } ?? (fallback, .entryClock))
    }

    private static func calendarDayWithClock(_ day: Date, clock: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = calendar.component(.hour, from: clock)
        components.minute = calendar.component(.minute, from: clock)
        components.second = calendar.component(.second, from: clock)
        return calendar.date(from: components) ?? day
    }

    private static func clampFutureDay(_ value: Date, to fallback: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: value) > calendar.startOfDay(for: fallback) ? fallback : value
    }
}
