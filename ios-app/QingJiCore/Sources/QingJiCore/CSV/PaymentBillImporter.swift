import Foundation

/// 账单来源平台。
public enum BillSource: String, Sendable {
    case weChat
    case alipay
    case unknown
}

/// 导入结果：成功解析的流水 + 被跳过的行数（不计收支、退款中等）。
public struct ImportedBillResult: Sendable {
    public let source: BillSource
    public let records: [TransactionRecord]
    public let skippedRowCount: Int
}

public enum BillImportError: Error, Equatable {
    /// 找不到包含「交易时间」等必需列的表头行。
    case unrecognizedFormat
}

/// 微信支付 / 支付宝导出账单（CSV，UTF-8）的通用导入器。
///
/// 两家账单都是「若干行说明文字 + 表头行 + 数据行」的结构，
/// 通过列名定位字段，对列顺序变化不敏感：
/// - 微信：交易时间, 交易类型, 交易对方, 商品, 收/支, 金额(元), 支付方式, 当前状态, ...
/// - 支付宝：交易时间, 交易分类, 交易对方, ..., 商品说明, 收/支, 金额, 收/付款方式, 交易状态, ...
///
/// 注意：支付宝导出的 CSV 通常是 GBK 编码，App 层读取文件时需先转成 UTF-8 字符串。
public enum PaymentBillImporter {
    public static func importBill(fromCSV text: String) throws -> ImportedBillResult {
        let rows = CSVParser.parse(text)
        guard let headerIndex = rows.firstIndex(where: { row in
            row.contains { $0.contains("交易时间") }
        }) else {
            throw BillImportError.unrecognizedFormat
        }

        let header = rows[headerIndex].map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func column(_ candidates: String...) -> Int? {
            for name in candidates {
                if let index = header.firstIndex(where: { $0.hasPrefix(name) }) {
                    return index
                }
            }
            return nil
        }

        guard let timeColumn = column("交易时间"),
              let inOutColumn = column("收/支"),
              let amountColumn = column("金额") else {
            throw BillImportError.unrecognizedFormat
        }
        let counterpartyColumn = column("交易对方")
        let productColumn = column("商品说明", "商品")
        let alipayCategoryColumn = column("交易分类")
        let statusColumn = column("当前状态", "交易状态")

        let source: BillSource = detectSource(preamble: rows[..<headerIndex], header: header)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var records: [TransactionRecord] = []
        var skipped = 0

        for row in rows[(headerIndex + 1)...] {
            guard row.count > max(timeColumn, inOutColumn, amountColumn) else {
                skipped += 1
                continue
            }
            func cell(_ index: Int?) -> String {
                guard let index, index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let kind: TransactionKind
            switch cell(inOutColumn) {
            case "支出": kind = .expense
            case "收入": kind = .income
            default:
                // "/"、"不计收支" 等中性交易（零钱提现、互转）不导入
                skipped += 1
                continue
            }

            let status = cell(statusColumn)
            if status.contains("退款") || status.contains("关闭") || status.contains("失败") {
                skipped += 1
                continue
            }

            guard let amount = parseAmount(cell(amountColumn)), amount > 0,
                  let date = formatter.date(from: cell(timeColumn)) else {
                skipped += 1
                continue
            }

            let note = [cell(counterpartyColumn), cell(productColumn)]
                .filter { !$0.isEmpty && $0 != "/" }
                .joined(separator: " ")

            records.append(TransactionRecord(
                kind: kind,
                amount: amount,
                currencyCode: "CNY",
                categoryName: cell(alipayCategoryColumn),
                accountName: "",
                note: note,
                date: date
            ))
        }

        return ImportedBillResult(source: source, records: records, skippedRowCount: skipped)
    }

    /// 去掉金额里的货币符号与千分位，如 "¥1,234.50" -> 1234.50。
    static func parseAmount(_ text: String) -> Decimal? {
        let cleaned = text
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        return Decimal(string: cleaned)
    }

    private static func detectSource(preamble: ArraySlice<[String]>, header: [String]) -> BillSource {
        let preambleText = preamble.flatMap { $0 }.joined()
        if preambleText.contains("微信") { return .weChat }
        if preambleText.contains("支付宝") { return .alipay }
        // 表头兜底：微信金额列叫「金额(元)」，支付宝有「交易分类」列
        if header.contains(where: { $0.hasPrefix("金额(元)") }) { return .weChat }
        if header.contains(where: { $0.hasPrefix("交易分类") }) { return .alipay }
        return .unknown
    }
}
