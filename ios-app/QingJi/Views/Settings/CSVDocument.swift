import SwiftUI
import UniformTypeIdentifiers

/// 用于 fileExporter 的纯文本 CSV 文档。
struct CSVDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText, .plainText]

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = BillTextDecoder.decode(data) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// 账单文件解码：微信账单是 UTF-8，支付宝导出的 CSV 通常是 GBK（GB18030）。
enum BillTextDecoder {
    static func decode(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        let gb18030 = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        return String(data: data, encoding: String.Encoding(rawValue: gb18030))
    }
}
