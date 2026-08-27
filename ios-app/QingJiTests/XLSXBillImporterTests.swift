import XCTest
import QingJiCore
@testable import QingJi

final class XLSXBillImporterTests: XCTestCase {
    func testReadsSharedStringsAndReusesPaymentBillImporter() throws {
        let sharedStrings = """
        <?xml version="1.0" encoding="UTF-8"?>
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <si><t>交易时间</t></si>
          <si><t>收/支</t></si>
          <si><t>金额(元)</t></si>
          <si><t>交易对方</t></si>
          <si><t>商品</t></si>
          <si><t>2026-08-27 12:00:00</t></si>
          <si><t>支出</t></si>
          <si><t>京东</t></si>
          <si><t>机械键盘</t></si>
        </sst>
        """
        let sheet = """
        <?xml version="1.0" encoding="UTF-8"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>
            <row r="1">
              <c r="A1" t="s"><v>0</v></c>
              <c r="B1" t="s"><v>1</v></c>
              <c r="C1" t="s"><v>2</v></c>
              <c r="D1" t="s"><v>3</v></c>
              <c r="E1" t="s"><v>4</v></c>
            </row>
            <row r="2">
              <c r="A2" t="s"><v>5</v></c>
              <c r="B2" t="s"><v>6</v></c>
              <c r="C2"><v>280</v></c>
              <c r="D2" t="s"><v>7</v></c>
              <c r="E2" t="s"><v>8</v></c>
            </row>
          </sheetData>
        </worksheet>
        """
        let archive = try ZipArchive.encode([
            try ZipArchive.Entry(path: "xl/sharedStrings.xml", data: Data(sharedStrings.utf8)),
            try ZipArchive.Entry(path: "xl/worksheets/sheet1.xml", data: Data(sheet.utf8)),
        ])
        let result = try XLSXBillImporter.importBill(from: archive)
        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(result.records[0].amount, 280)
        XCTAssertEqual(result.records[0].merchant, "京东")
        XCTAssertEqual(result.records[0].product, "机械键盘")
    }
}
