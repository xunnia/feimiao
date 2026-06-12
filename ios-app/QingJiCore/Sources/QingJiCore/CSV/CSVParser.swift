import Foundation

/// 极简 CSV 解析器：支持引号包裹字段、字段内逗号/换行、双引号转义、CRLF。
public enum CSVParser {
    public static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var insideQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = nil

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            // 跳过完全空白的行（常见于账单文件的空行分隔）
            if !(row.count == 1 && row[0].trimmingCharacters(in: .whitespaces).isEmpty) {
                rows.append(row)
            }
            row = []
        }

        while let char = pending ?? iterator.next() {
            pending = nil
            if insideQuotes {
                if char == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            insideQuotes = false
                            pending = next
                        }
                    } else {
                        insideQuotes = false
                    }
                } else {
                    field.append(char)
                }
            } else {
                switch char {
                case "\"" where field.isEmpty:
                    insideQuotes = true
                case ",":
                    endField()
                case "\r":
                    if let next = iterator.next(), next != "\n" { pending = next }
                    endRow()
                case "\n":
                    endRow()
                default:
                    field.append(char)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty {
            endRow()
        }
        return rows
    }
}
