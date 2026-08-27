import Foundation
import QingJiCore

/// 读取常见 XLSX 账单（sharedStrings + worksheet XML），然后复用
/// PaymentBillImporter 的列识别和分类逻辑。旧式二进制 .xls 不在此支持范围。
enum XLSXBillImporter {
    static func importBill(from data: Data) throws -> ImportedBillResult {
        let entries = try ZipArchive.decode(data)
        let byPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0.data) })
        let sharedStrings = parseSharedStrings(byPath["xl/sharedStrings.xml"])
        let worksheetPath = byPath.keys
            .filter { $0.hasPrefix("xl/worksheets/") && $0.hasSuffix(".xml") }
            .sorted()
            .first
        guard let worksheetPath, let worksheet = byPath[worksheetPath] else {
            throw BillImportError.unrecognizedFormat
        }
        let rows = parseWorksheet(worksheet, sharedStrings: sharedStrings)
        guard !rows.isEmpty else { throw BillImportError.unrecognizedFormat }
        return try PaymentBillImporter.importBill(fromCSV: csvText(rows))
    }

    private static func parseSharedStrings(_ data: Data?) -> [String] {
        guard let data else { return [] }
        let parser = SharedStringsParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        guard xml.parse() else { return [] }
        return parser.values
    }

    private static func parseWorksheet(
        _ data: Data,
        sharedStrings: [String]
    ) -> [[String]] {
        let parser = WorksheetParser(sharedStrings: sharedStrings)
        let xml = XMLParser(data: data)
        xml.delegate = parser
        guard xml.parse() else { return [] }
        return parser.rows
    }

    private static func csvText(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { value in
                let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
                return escaped.contains(where: { $0 == "," || $0 == "\n" || $0 == "\r" || $0 == "\"" })
                    ? "\"\(escaped)\""
                    : escaped
            }.joined(separator: ",")
        }.joined(separator: "\n")
    }
}

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    var values: [String] = []
    private var current = ""
    private var inItem = false
    private var inText = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "si":
            current = ""
            inItem = true
        case "t" where inItem:
            inText = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { current.append(string) }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "t":
            inText = false
        case "si":
            if inItem { values.append(current) }
            inItem = false
        default:
            break
        }
    }
}

private final class WorksheetParser: NSObject, XMLParserDelegate {
    let sharedStrings: [String]
    var rows: [[String]] = []
    private var currentRow: [String] = []
    private var currentColumn = 0
    private var currentType = ""
    private var currentValue = ""
    private var collectingValue = false

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "row":
            currentRow = []
        case "c":
            currentColumn = Self.columnIndex(attributeDict["r"] ?? "")
            currentType = attributeDict["t"] ?? ""
            currentValue = ""
        case "v", "t":
            currentValue = ""
            collectingValue = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collectingValue { currentValue.append(string) }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "v", "t":
            collectingValue = false
        case "c":
            var value = currentValue
            if currentType == "s", let index = Int(currentValue), index >= 0, index < sharedStrings.count {
                value = sharedStrings[index]
            }
            while currentRow.count <= currentColumn { currentRow.append("") }
            currentRow[currentColumn] = value
        case "row":
            if !currentRow.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                rows.append(currentRow)
            }
        default:
            break
        }
    }

    private static func columnIndex(_ reference: String) -> Int {
        let letters = reference.prefix { $0.isLetter }
        var result = 0
        for scalar in letters.unicodeScalars {
            result = result * 26 + Int(scalar.value - 64)
        }
        return max(result - 1, 0)
    }
}
