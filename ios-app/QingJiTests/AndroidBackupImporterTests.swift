import XCTest
import SQLite3
import QingJiCore
@testable import QingJi

final class AndroidBackupImporterTests: XCTestCase {
    func testAndroidMembershipRowsPreserveMultipleEmptyAndRefundInheritance() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("android-multibook-\(UUID().uuidString).db")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil), SQLITE_OK)
        let db = try XCTUnwrap(database)
        defer { sqlite3_close(db); try? FileManager.default.removeItem(at: url) }
        try execute(db, """
            CREATE TABLE books (id INTEGER PRIMARY KEY, uuid TEXT, name TEXT, sort_order INTEGER);
            INSERT INTO books VALUES (1, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', '总账本', 0);
            INSERT INTO books VALUES (2, 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', '生意', 1);
            INSERT INTO books VALUES (3, 'cccccccccccccccccccccccccccccccc', '项目', 2);
            CREATE TABLE transactions (id INTEGER PRIMARY KEY, uuid TEXT, book_id INTEGER, kind TEXT, amount TEXT, refund_of INTEGER);
            INSERT INTO transactions VALUES (1, '11111111111111111111111111111111', 2, 'expense', '100', NULL);
            INSERT INTO transactions VALUES (2, '22222222222222222222222222222222', 2, 'expense', '-20', 1);
            INSERT INTO transactions VALUES (3, '33333333333333333333333333333333', 2, 'expense', '30', NULL);
            INSERT INTO transactions VALUES (4, '44444444444444444444444444444444', 3, 'income', '50', NULL);
            CREATE TABLE transaction_books (transaction_id INTEGER, book_id INTEGER);
            INSERT INTO transaction_books VALUES (1,1),(1,2),(1,3),(3,1);
            """)
        let data = try AndroidBackupImporter.canonicalData(from: Data(contentsOf: url), databaseVersion: 51, exportedAt: Date())
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let package = try decoder.decode(FeimiaoBackupPackage.self, from: data)
        let business = try XCTUnwrap(package.books.first { $0.name == "生意" }?.id)
        let project = try XCTUnwrap(package.books.first { $0.name == "项目" }?.id)
        XCTAssertEqual(Set(try XCTUnwrap(package.transactions.first { $0.amount == 100 }?.scenarioBookIDs)), [business, project])
        XCTAssertEqual(Set(try XCTUnwrap(package.transactions.first { $0.amount == -20 }?.scenarioBookIDs)), [business, project])
        XCTAssertEqual(package.transactions.first { $0.amount == 30 }?.scenarioBookIDs, [])
        XCTAssertNil(package.transactions.first { $0.amount == 50 }?.scenarioBookIDs)
    }

    func testConvertsCoreAndroidSQLiteAndKeepsStableRelations() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("android-backup-test-\(UUID().uuidString).db")
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
            nil
        )
        XCTAssertEqual(openResult, SQLITE_OK)
        guard openResult == SQLITE_OK, let database else { return }
        defer {
            sqlite3_close(database)
            try? FileManager.default.removeItem(at: url)
        }

        try execute(database, """
            CREATE TABLE books (
              id INTEGER PRIMARY KEY, uuid TEXT, name TEXT, icon TEXT,
              cover TEXT, remark TEXT, sort_order INTEGER, created_ms INTEGER,
              starred INTEGER, include_in_total INTEGER, updated_ms INTEGER
            );
            INSERT INTO books VALUES (1, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', '总账本', '📒', '', '', 0, 1000, 0, 1, 1000);
            CREATE TABLE accounts (
              id INTEGER PRIMARY KEY, uuid TEXT, name TEXT, currency_code TEXT,
              type TEXT, opening_balance TEXT, include_in_net_worth INTEGER,
              institution TEXT, sort_order INTEGER, is_deleted INTEGER,
              created_ms INTEGER, updated_ms INTEGER, opening_balance_quality TEXT,
              status TEXT, balance_mode TEXT
            );
            INSERT INTO accounts VALUES (1, 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', '现金', 'CNY', 'cash', '500', 1, '', 0, 0, 1000, 1000, 'exact', 'active', 'legacy_hybrid');
            CREATE TABLE categories (
              id INTEGER PRIMARY KEY, key TEXT, name_zh TEXT, name_en TEXT,
              kind TEXT, parent_id INTEGER, hidden INTEGER
            );
            INSERT INTO categories VALUES (1, 'dining', '食品餐饮', 'Food', 'expense', NULL, 0);
            CREATE TABLE tags (id INTEGER PRIMARY KEY, name TEXT, color INTEGER);
            INSERT INTO tags VALUES (1, '工作', 123);
            CREATE TABLE transactions (
              id INTEGER PRIMARY KEY, uuid TEXT, book_id INTEGER, kind TEXT,
              amount TEXT, currency_code TEXT, category_id INTEGER,
              account_id INTEGER, to_account_id INTEGER, note TEXT,
              date_ms INTEGER, time_precision TEXT, tags TEXT,
              reimbursable INTEGER, image_path TEXT, recurring_rule_id INTEGER,
              excluded INTEGER, updated_ms INTEGER, refund_of INTEGER,
              created_ms INTEGER, settled_ms INTEGER, settlement_quality TEXT,
              settlement_account_id INTEGER, settlement_account_quality TEXT,
              event_type TEXT, order_no TEXT
            );
            INSERT INTO transactions VALUES (1, '11111111111111111111111111111111', 1, 'expense', '100', 'CNY', 1, 1, NULL, '午餐', 1725000000000, 'exact', '1', 0, '', NULL, 0, 1725000000000, NULL, 1725000000000, NULL, 'unknown', NULL, 'unknown', 'expense', 'ORDER-1');
            INSERT INTO transactions VALUES (2, '22222222222222222222222222222222', 1, 'expense', '-40', 'CNY', 1, 1, NULL, '退款', 1725000000000, 'exact', '1', 0, '', NULL, 0, 1725000000000, 1, 1725000000000, NULL, 'unknown', NULL, 'unknown', 'refund', 'ORDER-1');
            CREATE TABLE ai_runs (
              id TEXT PRIMARY KEY, idempotency_key TEXT, session_id TEXT,
              mode TEXT, provider_id TEXT, provider_label TEXT, model TEXT,
              effort TEXT, endpoint_type TEXT, status TEXT,
              input_digest TEXT, context_digest TEXT, proposal_json TEXT,
              result_json TEXT, error_code TEXT, error_message TEXT,
              retry_count INTEGER, requires_confirmation INTEGER,
              created_ms INTEGER, updated_ms INTEGER
            );
            INSERT INTO ai_runs VALUES ('33333333-3333-3333-3333-333333333333', 'key-1', 'record', 'record', 'provider-1', '测试服务商', 'test-model', 'medium', 'auto', 'awaitingConfirmation', '', '', '', '{"items":1}', '', '', 0, 1, 1725000000000, 1725000001000);
            CREATE TABLE ai_run_events (
              id INTEGER PRIMARY KEY, run_id TEXT, sequence INTEGER,
              type TEXT, payload_json TEXT, created_ms INTEGER
            );
            INSERT INTO ai_run_events VALUES (1, '33333333-3333-3333-3333-333333333333', 1, 'proposalReady', '{"items":1,"summary":"方案已生成"}', 1725000001000);
            CREATE TABLE ai_report_schedules (
              id TEXT PRIMARY KEY, session_id TEXT, title TEXT,
              report_type TEXT, period_kind TEXT, day_value INTEGER,
              enabled INTEGER, next_run_ms INTEGER, provider_id TEXT,
              model TEXT, effort TEXT, created_ms INTEGER, updated_ms INTEGER
            );
            INSERT INTO ai_report_schedules VALUES ('44444444-4444-4444-4444-444444444444', 'record', '每月账本报告', 'monthly', 'monthly', 1, 1, 1725003600000, 'provider-1', 'test-model', 'low', 1725000000000, 1725000000000);
            """)

        let databaseData = try Data(contentsOf: url)
        let canonical = try AndroidBackupImporter.canonicalData(
            from: databaseData,
            databaseVersion: 47,
            exportedAt: Date(timeIntervalSince1970: 1_725_000_000)
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let package = try decoder.decode(FeimiaoBackupPackage.self, from: canonical)

        XCTAssertEqual(package.books.count, 1)
        XCTAssertEqual(package.accounts.first?.initialBalance, Decimal(500))
        XCTAssertEqual(package.categories.first?.key, "dining")
        XCTAssertEqual(package.transactions.count, 2)
        XCTAssertEqual(package.transactions[0].id, UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        XCTAssertEqual(package.transactions[1].refundOfID, package.transactions[0].id)
        XCTAssertEqual(package.transactions[0].tags, ["工作"])
        XCTAssertEqual(package.aiRequestRuns.count, 1)
        XCTAssertEqual(package.aiRequestRuns.first?.statusRaw, "awaiting_confirmation")
        XCTAssertEqual(package.aiRequestEvents.count, 1)
        XCTAssertEqual(package.aiRequestEvents.first?.typeRaw, "proposal_ready")
        XCTAssertEqual(package.aiReportSchedules.count, 1)
        XCTAssertEqual(package.aiReportSchedules.first?.title, "每月账本报告")

        let secondCanonical = try AndroidBackupImporter.canonicalData(
            from: databaseData,
            databaseVersion: 47,
            exportedAt: Date(timeIntervalSince1970: 1_725_000_000)
        )
        let second = try decoder.decode(FeimiaoBackupPackage.self, from: secondCanonical)
        XCTAssertEqual(package.transactions.map(\.id), second.transactions.map(\.id))
        XCTAssertEqual(package.books.map(\.id), second.books.map(\.id))
    }

    func testDuplicateAndroidTransactionUUIDsKeepNewestAndRenumberRestLikeAndroid() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("android-duplicate-uuid-\(UUID().uuidString).db")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil), SQLITE_OK)
        let db = try XCTUnwrap(database)
        defer { sqlite3_close(db); try? FileManager.default.removeItem(at: url) }
        // 三笔账单共用一个编号（第 2 行是大写带横线的写法），第 4 行是第 2 行的退款。
        try execute(db, """
            CREATE TABLE books (id INTEGER PRIMARY KEY, uuid TEXT, name TEXT, sort_order INTEGER);
            INSERT INTO books VALUES (1, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', '总账本', 0);
            INSERT INTO books VALUES (2, 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', '生意', 1);
            CREATE TABLE transactions (id INTEGER PRIMARY KEY, uuid TEXT, book_id INTEGER, kind TEXT, amount TEXT, note TEXT, date_ms INTEGER, refund_of INTEGER);
            INSERT INTO transactions VALUES (1, 'abababababababababababababababab', 1, 'expense', '30', '晚饭', 1751454000000, NULL);
            INSERT INTO transactions VALUES (2, 'ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB', 2, 'expense', '20', '午饭', 1751342400000, NULL);
            INSERT INTO transactions VALUES (3, 'abababababababababababababababab', 1, 'expense', '10', '早饭', 1751342400000, NULL);
            INSERT INTO transactions VALUES (4, 'efefefefefefefefefefefefefefefef', 2, 'expense', '-5', '退款', 1751360000000, 2);
            CREATE TABLE transaction_books (transaction_id INTEGER, book_id INTEGER);
            INSERT INTO transaction_books VALUES (2,1),(2,2);
            """)
        let databaseData = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let package = try decoder.decode(
            FeimiaoBackupPackage.self,
            from: AndroidBackupImporter.canonicalData(from: databaseData, databaseVersion: 51, exportedAt: Date())
        )
        XCTAssertEqual(package.transactions.count, 4)
        XCTAssertEqual(Set(package.transactions.map(\.id)).count, 4)
        let byNote = Dictionary(uniqueKeysWithValues: package.transactions.map { ($0.note, $0) })
        // 时间新的那笔保留原编号；同一时间的按安卓行号大的在前。新编号和安卓表格恢复算出来的一致。
        XCTAssertEqual(byNote["晚饭"]?.id, UUID(uuidString: "ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB"))
        XCTAssertEqual(byNote["早饭"]?.id, UUID(uuidString: "4A59A4DA-06FB-AEDD-DD21-962E263EDDA9"))
        XCTAssertEqual(byNote["午饭"]?.id, UUID(uuidString: "083DA2F4-6CBD-4108-03B1-7A01E8280EC6"))
        XCTAssertEqual(byNote["退款"]?.id, UUID(uuidString: "EFEFEFEF-EFEF-EFEF-EFEF-EFEFEFEFEFEF"))
        XCTAssertEqual(byNote["退款"]?.refundOfID, byNote["午饭"]?.id)
        let business = try XCTUnwrap(package.books.first { $0.name == "生意" }?.id)
        XCTAssertEqual(byNote["午饭"]?.scenarioBookIDs, [business])
        XCTAssertEqual(byNote["退款"]?.scenarioBookIDs, [business])
        XCTAssertNil(byNote["晚饭"]?.scenarioBookIDs)
        XCTAssertNil(byNote["早饭"]?.scenarioBookIDs)

        let again = try decoder.decode(
            FeimiaoBackupPackage.self,
            from: AndroidBackupImporter.canonicalData(from: databaseData, databaseVersion: 51, exportedAt: Date())
        )
        XCTAssertEqual(package.transactions.map(\.id), again.transactions.map(\.id))
    }

    private func execute(_ database: OpaquePointer, _ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sql.withCString {
            sqlite3_exec(database, $0, nil, nil, &errorMessage)
        }
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown SQLite error"
            if let errorMessage { sqlite3_free(errorMessage) }
            throw NSError(domain: "AndroidBackupImporterTests", code: Int(result), userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
