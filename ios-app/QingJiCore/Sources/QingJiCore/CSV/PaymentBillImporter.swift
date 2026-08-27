import Foundation

/// 账单来源平台。
public enum BillSource: String, Sendable {
    case weChat
    case alipay
    case unknown
}

/// 导入结果：成功解析的流水 + 被跳过的行数。
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
            row.contains { cell in
                let header = normalizeHeader(cell)
                return header.contains("交易时间") || header.contains("日期") || header == "时间" ||
                    header.contains("时间") || header.contains("收/支") || header.contains("收支") ||
                    header == "date" || header == "time" || header == "kind"
            } && row.contains {
                let header = normalizeHeader($0)
                return header.contains("金额") || header == "amount"
            }
        }) else {
            throw BillImportError.unrecognizedFormat
        }

        let header = rows[headerIndex].map(normalizeHeader)
        func column(_ candidates: String...) -> Int? {
            for name in candidates {
                let normalizedName = normalizeHeader(name)
                if let index = header.firstIndex(where: { $0.hasPrefix(normalizedName) }) {
                    return index
                }
            }
            return nil
        }

        guard let timeColumn = column(
            "交易时间", "交易创建时间", "付款时间", "日期", "记账时间", "创建时间", "时间", "date", "time"
        ),
              let amountColumn = column("金额", "amount") else {
            throw BillImportError.unrecognizedFormat
        }
        let inOutColumn = column("收/支", "收支", "收入/支出", "direction")
        let kindColumn = column("类型", "交易类型", "收支类型", "收入/支出", "业务类型", "kind")
        let counterpartyColumn = column("交易对方", "merchant")
        let productColumn = column("商品说明", "商品", "product")
        let noteColumn = column("交易备注", "付款备注", "备注", "note")
        let alipayCategoryColumn = column("交易分类", "category")
        let statusColumn = column("当前状态", "交易状态")
        let orderColumn = column("商户订单号", "商户单号", "交易订单号", "交易单号", "订单号", "order_no")

        let source: BillSource = detectSource(preamble: rows[..<headerIndex], header: header)

        var records: [TransactionRecord] = []
        var skipped = 0

        for row in rows.dropFirst(headerIndex + 1) {
            guard row.count > max(timeColumn, amountColumn) else {
                skipped += 1
                continue
            }
            func cell(_ index: Int?) -> String {
                guard let index, index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard let parsedAmount = parseAmount(cell(amountColumn)), parsedAmount != 0,
                  let date = parseDate(cell(timeColumn)) else {
                skipped += 1
                continue
            }

            let direction = cell(inOutColumn)
            let type = cell(kindColumn)
            let category = cell(alipayCategoryColumn)
            let product = cell(productColumn)
            let counterparty = cell(counterpartyColumn)
            let extraNote = cell(noteColumn)
            let order = cell(orderColumn) == "/" ? "" : cell(orderColumn)
            let status = cell(statusColumn)
            let refundText = [category, type, product, counterparty, status]
                .joined(separator: " ")
            let hasRefundSignal = containsRefundSignal(refundText)
            let directionText = "\(direction) \(type)"
            let isExplicitExpense = directionText.contains("支") && !directionText.contains("不计")
            let isExplicitIncome = directionText.contains("收") && !directionText.contains("不计") && !isExplicitExpense
            let platformRefundSignal = containsRefundSignal(category) ||
                containsRefundSignal(type) ||
                (containsRefundSignal(product) && !product.contains("转账备注"))
            let isRefund = hasRefundSignal && !isExplicitExpense &&
                (!isExplicitIncome || platformRefundSignal)

            // 微信有时把已经全额退款的原消费行标为“支出 + 已全额退款”，
            // 这不是可独立入账的支出，也不是可挂回原单的退款子行。
            if status.contains("关闭") || status.contains("失败") ||
                (status.contains("退款") && !isRefund) {
                skipped += 1
                continue
            }

            let resolvedKind: TransactionKind?
            if isRefund {
                resolvedKind = .expense
            } else {
                resolvedKind = resolveKind(direction: direction, type: type, amount: parsedAmount)
            }
            guard let kind = resolvedKind else {
                skipped += 1
                continue
            }

            let noteParts = [counterparty, product, extraNote]
                .filter { !$0.isEmpty && $0 != "/" }
                .reduce(into: [String]()) { parts, value in
                    if !parts.contains(value) { parts.append(value) }
                }
            let note = noteParts.joined(separator: " · ")
            let classificationNote = [category, note].filter { !$0.isEmpty }.joined(separator: " ")
            let guess = isRefund
                ? BillCategoryGuess.none
                : BillCategorizer.classify(
                    merchant: counterparty,
                    product: product,
                    note: classificationNote,
                    kind: kind
                )
            let seed = guess.key.flatMap(CategorySeed.byKey)

            records.append(TransactionRecord(
                kind: kind,
                amount: isRefund ? -absolute(parsedAmount) : absolute(parsedAmount),
                currencyCode: "CNY",
                categoryName: isRefund ? "" : category,
                categoryKey: isRefund ? "" : (guess.key ?? ""),
                topCategoryName: isRefund ? "" : (seed.flatMap { item in
                    guard let parentKey = item.parentKey else { return item.nameZh }
                    return CategorySeed.byKey(parentKey)?.nameZh ?? item.nameZh
                } ?? ""),
                topCategoryKey: isRefund ? "" : (seed?.parentKey ?? seed?.key ?? ""),
                accountName: "",
                note: note,
                merchant: counterparty,
                product: product == "/" ? "" : product,
                date: date,
                timePrecision: containsClock(cell(timeColumn)) ? .exact : .dateOnly,
                eventType: isRefund ? .refund : .defaultFor(kind),
                orderNo: order
            ))
        }

        return ImportedBillResult(source: source, records: records, skippedRowCount: skipped)
    }

    /// 去掉金额里的货币符号与千分位，如 "¥1,234.50" -> 1234.50。
    static func parseAmount(_ text: String) -> Decimal? {
        let cleaned = text.filter { $0.isNumber || $0 == "." || $0 == "-" || $0 == "+" }
        guard !cleaned.isEmpty else { return nil }
        return Decimal(string: cleaned)
    }

    private static func normalizeHeader(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
    }

    private static func containsRefundSignal(_ text: String) -> Bool {
        text.contains("退款") || text.contains("退回") || text.contains("退货") ||
            text.localizedCaseInsensitiveContains("refund")
    }

    private static func resolveKind(direction: String, type: String, amount: Decimal) -> TransactionKind? {
        for value in [direction, type] where !value.isEmpty {
            let normalized = value.lowercased()
            if normalized == "expense" { return .expense }
            if normalized == "income" { return .income }
            if normalized == "transfer" { return .transfer }
            if value.contains("不计") || value.contains("中性") || value == "/" {
                return nil
            }
            if value.contains("收") && !value.contains("支") { return .income }
            if value.contains("支") && !value.contains("收") { return .expense }
        }
        return amount < 0 ? .expense : .income
    }

    private static func parseDate(_ text: String) -> Date? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // XLSX 日期单元格常以 1899-12-30 为基准的序列值保存；这里只在
        // 日期列解析它，金额仍始终走 Decimal。
        if let serial = Double(value), serial > 1, serial < 100_000 {
            return Date(timeIntervalSince1970: (serial - 25_569) * 86_400)
        }
        if let iso = ISO8601DateFormatter().date(from: value.replacingOccurrences(of: " ", with: "T")) {
            return iso
        }
        for format in [
            "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm",
            "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm",
            "yyyy-MM-dd", "yyyy/MM/dd"
        ] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func containsClock(_ value: String) -> Bool {
        value.range(of: #"(?:T|\s)\d{1,2}:\d{2}"#, options: .regularExpression) != nil
    }

    private static func absolute(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
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
