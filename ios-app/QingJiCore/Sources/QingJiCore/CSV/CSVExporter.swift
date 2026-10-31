import Foundation

/// 导出全部流水为 CSV（UTF-8 带 BOM，方便 Excel 直接打开中文）。
public enum CSVExporter {
    public static let header = [
        "date", "kind", "amount", "currency", "category", "account", "note",
        "merchant", "product", "order_no", "attachment_path", "excluded", "reimbursable",
        "账本UUID", "账本名称"
    ]

    public static func export(_ records: [TransactionRecord], bookNames: [UUID: String] = [:]) -> String {
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
                record.merchant,
                record.product,
                record.orderNo,
                record.attachmentPath,
                record.isExcluded ? "1" : "0",
                record.reimbursable ? "1" : "0",
                json(record.scenarioBookIDs?.map(\.uuidString)),
                json(record.scenarioBookIDs.map { ids in ids.map { bookNames[$0] ?? "" } }),
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return "\u{FEFF}" + lines.joined(separator: "\n")
    }

    private static func json(_ values: [String]?) -> String {
        guard let values, let data = try? JSONEncoder().encode(values) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }

    static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
