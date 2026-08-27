import XCTest
import SQLite3
import QingJiCore
@testable import QingJi

final class AndroidBackupImporterTests: XCTestCase {
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
