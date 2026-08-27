import XCTest
@testable import QingJiCore

final class BillImportTests: XCTestCase {
    func testCSVParserHandlesQuotedFields() {
        let rows = CSVParser.parse("a,\"b,1\",c\n\"say \"\"hi\"\"\",2,3\n")
        XCTAssertEqual(rows, [["a", "b,1", "c"], ["say \"hi\"", "2", "3"]])
    }

    func testImportWeChatBill() throws {
        let csv = """
        微信支付账单明细,,,,,,,,
        微信昵称：[test],,,,,,,,
        起始时间：[2026-06-01 00:00:00] 终止时间：[2026-06-10 00:00:00],,,,,,,,
        ----------------------微信支付账单明细列表--------------------,,,,,,,,
        交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号
        2026-06-01 08:30:00,商户消费,煎饼摊,早餐煎饼,支出,¥8.50,零钱,支付成功,10001
        2026-06-02 12:00:00,微信红包,张三,/,收入,¥66.00,/,已存入零钱,10002
        2026-06-03 10:00:00,零钱提现,/,/,/,¥100.00,零钱,提现已到账,10003
        2026-06-04 18:00:00,商户消费,某商店,退货商品,支出,¥30.00,零钱,已全额退款,10004
        """
        let result = try PaymentBillImporter.importBill(fromCSV: csv)
        XCTAssertEqual(result.source, .weChat)
        XCTAssertEqual(result.records.count, 2)
        XCTAssertEqual(result.skippedRowCount, 2)

        let breakfast = result.records[0]
        XCTAssertEqual(breakfast.kind, .expense)
        XCTAssertEqual(breakfast.amount, Decimal(string: "8.5"))
        XCTAssertTrue(breakfast.note.contains("煎饼摊"))
        XCTAssertEqual(breakfast.merchant, "煎饼摊")
        XCTAssertEqual(breakfast.product, "早餐煎饼")

        XCTAssertEqual(result.records[1].kind, .income)
        XCTAssertEqual(result.records[1].amount, 66)
    }

    func testImportAlipayBill() throws {
        let csv = """
        支付宝交易明细（个人）,,,,,,,,,
        姓名：测试,,,,,,,,,
        交易时间,交易分类,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号
        2026-06-05 09:15:00,餐饮美食,肯德基,kfc@example.com,早餐套餐,支出,23.00,余额宝,交易成功,20001
        2026-06-06 14:00:00,转账红包,李四,li@example.com,转账,不计收支,200.00,余额,交易成功,20002
        """
        let result = try PaymentBillImporter.importBill(fromCSV: csv)
        XCTAssertEqual(result.source, .alipay)
        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(result.skippedRowCount, 1)
        XCTAssertEqual(result.records[0].categoryName, "餐饮美食")
        XCTAssertEqual(result.records[0].categoryKey, "dining_breakfast")
        XCTAssertEqual(result.records[0].amount, 23)
    }

    func testImportKeepsRefundAndUsesMerchantOrderNumber() throws {
        let csv = """
        支付宝交易明细（个人）,,,,,,,,,
        交易时间,交易分类,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,商户订单号,交易订单号
        2026-06-05 09:15:00,购物,某店,shop@example.com,耳机,支出,100.00,余额,交易成功,M-100,T-100
        2026-06-06 14:00:00,退款,某店,shop@example.com,退款-耳机,收入,100.00,余额,交易成功,M-100,T-100-refund
        """

        let result = try PaymentBillImporter.importBill(fromCSV: csv)

        XCTAssertEqual(result.records.count, 2)
        XCTAssertEqual(result.records[0].eventType, .expense)
        XCTAssertEqual(result.records[0].orderNo, "M-100")
        XCTAssertEqual(result.records[0].merchant, "某店")
        XCTAssertEqual(result.records[0].product, "耳机")
        XCTAssertEqual(result.records[1].eventType, .refund)
        XCTAssertEqual(result.records[1].kind, .expense)
        XCTAssertEqual(result.records[1].amount, -100)
        XCTAssertEqual(result.records[1].orderNo, "M-100")
    }

    func testUnrecognizedFormatThrows() {
        XCTAssertThrowsError(try PaymentBillImporter.importBill(fromCSV: "foo,bar\n1,2\n")) { error in
            XCTAssertEqual(error as? BillImportError, .unrecognizedFormat)
        }
    }

    func testParseAmountVariants() {
        XCTAssertEqual(PaymentBillImporter.parseAmount("¥1,234.50"), Decimal(string: "1234.5"))
        XCTAssertEqual(PaymentBillImporter.parseAmount("￥8.00"), 8)
        XCTAssertEqual(PaymentBillImporter.parseAmount("23.00"), 23)
        XCTAssertEqual(PaymentBillImporter.parseAmount("-23.00 元"), -23)
        XCTAssertNil(PaymentBillImporter.parseAmount(""))
        XCTAssertNil(PaymentBillImporter.parseAmount("/"))
    }

    func testImportAcceptsDateOnlyAndTypeColumn() throws {
        let csv = """
        日期,交易类型,交易对方,金额
        2026/06/07,支出,小店,-12.50
        2026/06/08,收入,返现,8.00
        """

        let result = try PaymentBillImporter.importBill(fromCSV: csv)

        XCTAssertEqual(result.records.count, 2)
        XCTAssertEqual(result.records[0].kind, .expense)
        XCTAssertEqual(result.records[0].amount, 12.5)
        XCTAssertEqual(result.records[0].timePrecision, .dateOnly)
        XCTAssertEqual(result.records[1].kind, .income)
        XCTAssertEqual(result.records[1].amount, 8)
    }

    func testImportAcceptsCreationTimeAndIncomeExpenseColumn() throws {
        let csv = """
        创建时间,收入/支出,交易对方,金额
        2026-06-09 07:05,支出,早餐店,12.50
        2026-06-09,收入,返现,3.00
        """

        let result = try PaymentBillImporter.importBill(fromCSV: csv)

        XCTAssertEqual(result.records.map(\.kind), [.expense, .income])
        XCTAssertEqual(result.records.map(\.amount), [Decimal(string: "12.5")!, 3])
        XCTAssertEqual(result.records[0].timePrecision, .exact)
        XCTAssertEqual(result.records[1].timePrecision, .dateOnly)
    }

    func testExportRoundTripEscaping() {
        let records = [
            TransactionRecord(
                kind: .expense,
                amount: Decimal(string: "12.5")!,
                categoryName: "餐饮",
                accountName: "微信",
                note: "煎饼, 加蛋 \"双份\"",
                date: Date(timeIntervalSince1970: 1_700_000_000)
            ),
        ]
        let csv = CSVExporter.export(records)
        let rows = CSVParser.parse(String(csv.dropFirst())) // 去掉 BOM
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0], CSVExporter.header)
        XCTAssertEqual(rows[1][4], "餐饮")
        XCTAssertEqual(rows[1][6], "煎饼, 加蛋 \"双份\"")
    }

    func testOwnExportCanBeImportedAgain() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let source = TransactionRecord(
            kind: .expense,
            amount: 18,
            categoryName: "饮料酒水",
            categoryKey: "dining_drink",
            accountName: "微信",
            note: "午后咖啡",
            merchant: "瑞幸",
            product: "拿铁",
            date: date
        )

        let result = try PaymentBillImporter.importBill(fromCSV: CSVExporter.export([source]))

        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(result.records[0].kind, .expense)
        XCTAssertEqual(result.records[0].amount, 18)
        XCTAssertEqual(result.records[0].merchant, "瑞幸")
        XCTAssertEqual(result.records[0].product, "拿铁")
        XCTAssertEqual(result.records[0].categoryKey, "dining_drink")
    }
}
