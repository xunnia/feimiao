import Foundation

/// 导出全部流水为 CSV（UTF-8 带 BOM，方便 Excel 直接打开中文）。
public enum CSVExporter {
    public static let header = ["date", "kind", "amount", "currency", "category", "account", "note"]

    public static func export(_ records: [TransactionRecord]) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = [header.joined(separator: ",")]
        for record in records {
            let fields = [
                formatter.string(from: record.date),
                record.kind.rawValue,
                "\(record.amount)",
                record.currencyCode,
                record.categoryName,
                record.accountName,
                record.note,
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return "\u{FEFF}" + lines.joined(separator: "\n")
    }

    static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
