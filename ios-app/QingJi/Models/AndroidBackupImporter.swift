import Foundation
import CryptoKit
import QingJiCore

#if canImport(SQLite3)
import SQLite3
#endif

/// Converts the Android full-device SQLite backup into the platform-neutral
/// package before SwiftData sees it. The Android database is opened read-only;
/// no Android migration or write-back is performed on the user's file.
enum AndroidBackupImporter {
    static let archiveFormat = "feimiao-backup"

    enum Error: LocalizedError {
        case unsupportedSQLite
        case invalidDatabase
        case openFailed(String)
        case queryFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedSQLite:
                return "当前 iOS 构建没有启用 SQLite 兼容组件，无法读取 Android 原始备份。"
            case .invalidDatabase:
                return "Android 备份中的数据库无法识别。"
            case .openFailed(let message):
                return "无法打开 Android 备份数据库：\(message)"
            case .queryFailed(let message):
                return "读取 Android 备份数据库失败：\(message)"
            }
        }
    }

    static func canonicalData(
        from databaseData: Data,
        databaseVersion: Int,
        exportedAt: Date
    ) throws -> Data {
#if canImport(SQLite3)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("feimiao-android-\(UUID().uuidString).db")
        do {
            try databaseData.write(to: url, options: .atomic)
            defer { try? FileManager.default.removeItem(at: url) }
            let package = try makePackage(
                at: url,
                databaseVersion: databaseVersion,
                exportedAt: exportedAt
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(package)
        } catch let error as Error {
            throw error
        } catch {
            throw Error.invalidDatabase
        }
#else
        throw Error.unsupportedSQLite
#endif
    }

#if canImport(SQLite3)
    private enum SQLiteValue {
        case null
        case integer(Int64)
        case real(Double)
        case text(String)
        case blob(Data)
    }

    private struct SQLiteRow {
        let values: [String: SQLiteValue]

        func string(_ key: String, fallback: String = "") -> String {
            guard let value = values[key] else { return fallback }
            switch value {
            case .null:
                return fallback
            case .integer(let value):
                return String(value)
            case .real(let value):
                return String(value)
            case .text(let value):
                return value
            case .blob(let value):
                return String(data: value, encoding: .utf8) ?? fallback
            }
        }

        func optionalString(_ key: String) -> String? {
            let value = string(key).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        func integer(_ key: String) -> Int64? {
            guard let value = values[key] else { return nil }
            switch value {
            case .null:
                return nil
            case .integer(let value):
                return value
            case .real(let value):
                return Int64(value)
            case .text(let value):
                if let integer = Int64(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return integer
                }
                guard let double = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
                return Int64(double)
            case .blob:
                return nil
            }
        }

        func decimal(_ key: String, fallback: Decimal = .zero) -> Decimal {
            guard let value = values[key] else { return fallback }
            switch value {
            case .null:
                return fallback
            case .integer(let value):
                return Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) ?? fallback
            case .real(let value):
                return NSDecimalNumber(value: value).decimalValue
            case .text(let value):
                return Decimal(
                    string: value.trimmingCharacters(in: .whitespacesAndNewlines),
                    locale: Locale(identifier: "en_US_POSIX")
                ) ?? fallback
            case .blob:
                return fallback
            }
        }

        func optionalDecimal(_ key: String) -> Decimal? {
            guard let value = values[key] else { return nil }
            switch value {
            case .null, .blob:
                return nil
            default:
                let parsed = decimal(key)
                return parsed == .zero && string(key).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : parsed
            }
        }

        func bool(_ key: String, fallback: Bool = false) -> Bool {
            if let value = integer(key) { return value != 0 }
            let text = string(key).lowercased()
            if text == "true" || text == "yes" { return true }
            if text == "false" || text == "no" { return false }
            return fallback
        }
    }

    private final class SQLiteReader {
        private var handle: OpaquePointer?

        init(url: URL) throws {
            var opened: OpaquePointer?
            let result = url.path.withCString { path in
                sqlite3_open_v2(
                    path,
                    &opened,
                    SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
                    nil
                )
            }
            guard result == SQLITE_OK, let opened else {
                let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
                if let opened { sqlite3_close(opened) }
                throw Error.openFailed(message)
            }
            handle = opened
        }

        deinit {
            if let handle { sqlite3_close(handle) }
        }

        func rows(from table: String) throws -> [SQLiteRow] {
            guard try hasTable(table), let handle else { return [] }
            let sql = "SELECT * FROM \"\(table)\""
            var statement: OpaquePointer?
            let prepareResult = sql.withCString {
                sqlite3_prepare_v2(handle, $0, -1, &statement, nil)
            }
            guard prepareResult == SQLITE_OK, let statement else {
                throw Error.queryFailed(message(for: handle))
            }
            defer { sqlite3_finalize(statement) }

            let columnCount = sqlite3_column_count(statement)
            var columnNames: [String] = []
            columnNames.reserveCapacity(Int(columnCount))
            for index in 0..<columnCount {
                guard let pointer = sqlite3_column_name(statement, index) else {
                    columnNames.append("column_\(index)")
                    continue
                }
                columnNames.append(String(cString: pointer))
            }

            var result: [SQLiteRow] = []
            while true {
                let stepResult = sqlite3_step(statement)
                if stepResult == SQLITE_DONE { break }
                guard stepResult == SQLITE_ROW else {
                    throw Error.queryFailed(message(for: handle))
                }
                var values: [String: SQLiteValue] = [:]
                values.reserveCapacity(Int(columnCount))
                for index in 0..<columnCount {
                    values[columnNames[Int(index)]] = value(from: statement, index: index)
                }
                result.append(SQLiteRow(values: values))
            }
            return result
        }

        private func hasTable(_ table: String) throws -> Bool {
            guard let handle else { return false }
            let escaped = table.replacingOccurrences(of: "'", with: "''")
            let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '\(escaped)' LIMIT 1"
            var statement: OpaquePointer?
            let prepareResult = sql.withCString {
                sqlite3_prepare_v2(handle, $0, -1, &statement, nil)
            }
            guard prepareResult == SQLITE_OK, let statement else {
                throw Error.queryFailed(message(for: handle))
            }
            defer { sqlite3_finalize(statement) }
            return sqlite3_step(statement) == SQLITE_ROW
        }

        private func value(from statement: OpaquePointer?, index: Int32) -> SQLiteValue {
            guard let statement else { return .null }
            switch sqlite3_column_type(statement, index) {
            case SQLITE_INTEGER:
                return .integer(sqlite3_column_int64(statement, index))
            case SQLITE_FLOAT:
                return .real(sqlite3_column_double(statement, index))
            case SQLITE_TEXT:
                guard let pointer = sqlite3_column_text(statement, index) else { return .null }
                let length = Int(sqlite3_column_bytes(statement, index))
                return .text(String(decoding: UnsafeBufferPointer(start: pointer, count: length), as: UTF8.self))
            case SQLITE_BLOB:
                let length = Int(sqlite3_column_bytes(statement, index))
                guard length > 0, let pointer = sqlite3_column_blob(statement, index) else {
                    return .blob(Data())
                }
                return .blob(Data(bytes: pointer, count: length))
            default:
                return .null
            }
        }

        private func message(for handle: OpaquePointer) -> String {
            String(cString: sqlite3_errmsg(handle))
        }
    }

    private static func makePackage(
        at url: URL,
        databaseVersion: Int,
        exportedAt: Date
    ) throws -> FeimiaoBackupPackage {
        let reader = try SQLiteReader(url: url)
        let bookRows = try reader.rows(from: "books")
        let accountRows = try reader.rows(from: "accounts")
        let categoryRows = try reader.rows(from: "categories")
        let tagRows = try reader.rows(from: "tags")
        let transactionRows = try reader.rows(from: "transactions")
        let budgetRows = try reader.rows(from: "budget")
        let budgetPeriodRows = try reader.rows(from: "budget_periods")
        let savingsRows = try reader.rows(from: "savings_goals")
        let recurringRows = try reader.rows(from: "recurring_rules")
        let recurringOccurrenceRows = try reader.rows(from: "recurring_occurrences")
        let assetRows = try reader.rows(from: "physical_assets")
        let assetEventRows = try reader.rows(from: "asset_events")
        let assetUsageRows = try reader.rows(from: "asset_usage_events")
        let assetLinkRows = try reader.rows(from: "asset_transaction_links")
        let assetRefundRows = try reader.rows(from: "asset_refund_allocations")
        let assetValuationRows = try reader.rows(from: "asset_valuations")
        let receivableRows = try reader.rows(from: "receivable_assets")
        let recoveryRows = try reader.rows(from: "receivable_recoveries")
        let liabilityRows = try reader.rows(from: "liability_profiles")
        let snapshotRows = try reader.rows(from: "net_worth_snapshots")
        let accountCheckpointRows = try reader.rows(from: "account_balance_checkpoints")
        let accountCheckpointUnknownRows = try reader.rows(from: "account_checkpoint_covered_unknown_events")
        let verifiedNetWorthRows = try reader.rows(from: "net_worth_verified_checkpoints")
        let verifiedNetWorthItemRows = try reader.rows(from: "net_worth_verified_checkpoint_items")
        let sessionRows = try reader.rows(from: "chat_sessions")
        let messageRows = try reader.rows(from: "chat_messages")
        let aiMemoryRows = try reader.rows(from: "ai_memories")
        let aiRunRows = try reader.rows(from: "ai_runs")
        let aiRunEventRows = try reader.rows(from: "ai_run_events")
        let aiReportScheduleRows = try reader.rows(from: "ai_report_schedules")
        let reportJobRows = try reader.rows(from: "report_jobs")
        let budgetPlanRows = try reader.rows(from: "budget_plans")
        let budgetRevisionRows = try reader.rows(from: "budget_plan_revisions")
        let budgetOverrideRows = try reader.rows(from: "budget_cycle_overrides")
        let budgetCommitmentRows = try reader.rows(from: "budget_fixed_commitment_occurrences")
        let budgetChangeRows = try reader.rows(from: "budget_change_events")
        let reportRows = try reader.rows(from: "reports")

        var bookIDs: [Int64: UUID] = [:]
        for row in bookRows {
            if let id = row.integer("id") { bookIDs[id] = stableID(row.string("uuid"), table: "books", id: id) }
        }
        let defaultBookID = bookRows.first(where: {
            $0.string("name") == "总账本"
        }).flatMap { row in
            row.integer("id").flatMap { bookIDs[$0] }
        } ?? bookRows.first.flatMap { row in
            row.integer("id").flatMap { bookIDs[$0] }
        }

        var accountIDs: [Int64: UUID] = [:]
        for row in accountRows {
            if let id = row.integer("id") { accountIDs[id] = stableID(row.string("uuid"), table: "accounts", id: id) }
        }
        var accountCheckpointIDs: [Int64: UUID] = [:]
        for row in accountCheckpointRows {
            if let id = row.integer("id") { accountCheckpointIDs[id] = stableID(row.string("uuid"), table: "account_balance_checkpoints", id: id) }
        }
        var verifiedNetWorthIDs: [Int64: UUID] = [:]
        for row in verifiedNetWorthRows {
            if let id = row.integer("id") { verifiedNetWorthIDs[id] = stableID(row.string("uuid"), table: "net_worth_verified_checkpoints", id: id) }
        }
        var unknownEventsByCheckpoint: [Int64: [String]] = [:]
        for row in accountCheckpointUnknownRows {
            guard let checkpointID = row.integer("checkpoint_id") else { continue }
            let eventID = row.string("account_event_uuid").trimmingCharacters(in: .whitespacesAndNewlines)
            if !eventID.isEmpty { unknownEventsByCheckpoint[checkpointID, default: []].append(eventID) }
        }

        var categoryByID: [Int64: (key: String, name: String, parentKey: String?, kind: TransactionKind)] = [:]
        for row in categoryRows {
            guard let id = row.integer("id") else { continue }
            let key = row.string("key", fallback: "other")
            let kind = TransactionKind(rawValue: row.string("kind")) ?? .expense
            categoryByID[id] = (key, row.string("name_zh", fallback: CategorySeed.byKey(key)?.nameZh ?? key), nil, kind)
        }
        for row in categoryRows {
            guard let id = row.integer("id"), let parentID = row.integer("parent_id"),
                  let parent = categoryByID[parentID], var value = categoryByID[id] else { continue }
            value.parentKey = parent.key
            categoryByID[id] = value
        }

        var tagNamesByID: [Int64: String] = [:]
        for row in tagRows {
            if let id = row.integer("id") { tagNamesByID[id] = row.string("name") }
        }

        var recurringIDs: [Int64: UUID] = [:]
        for row in recurringRows {
            if let id = row.integer("id") { recurringIDs[id] = stableID(row.string("uuid"), table: "recurring_rules", id: id) }
        }

        var transactionIDs: [Int64: UUID] = [:]
        for row in transactionRows {
            if let id = row.integer("id") { transactionIDs[id] = stableID(row.string("uuid"), table: "transactions", id: id) }
        }

        var assetIDs: [Int64: UUID] = [:]
        for row in assetRows {
            if let id = row.integer("id") { assetIDs[id] = stableID(row.string("uuid"), table: "physical_assets", id: id) }
        }
        var assetUsageIDs: [Int64: UUID] = [:]
        for row in assetUsageRows {
            if let id = row.integer("id") { assetUsageIDs[id] = stableID(row.string("uuid"), table: "asset_usage_events", id: id) }
        }
        var assetLinkIDs: [Int64: UUID] = [:]
        for row in assetLinkRows {
            if let id = row.integer("id") { assetLinkIDs[id] = stableID(row.string("uuid"), table: "asset_transaction_links", id: id) }
        }
        var assetRefundAllocationIDs: [Int64: UUID] = [:]
        for row in assetRefundRows {
            if let id = row.integer("id") { assetRefundAllocationIDs[id] = stableID(row.string("uuid"), table: "asset_refund_allocations", id: id) }
        }
        var reversedUsageIDs = Set<Int64>()
        for row in assetUsageRows {
            if let reversal = row.integer("reversal_of") { reversedUsageIDs.insert(reversal) }
        }
        var usageCountByAsset: [Int64: Int] = [:]
        for row in assetUsageRows {
            guard row.integer("reversal_of") == nil,
                  let assetID = row.integer("asset_id"),
                  let eventID = row.integer("id"),
                  !reversedUsageIDs.contains(eventID) else { continue }
            usageCountByAsset[assetID, default: 0] += Int(row.integer("count_delta") ?? 0)
        }
        var savingsIDs: [Int64: UUID] = [:]
        for row in savingsRows {
            if let id = row.integer("id") { savingsIDs[id] = stableID(row.string("uuid"), table: "savings_goals", id: id) }
        }
        var receivableIDs: [Int64: UUID] = [:]
        for row in receivableRows {
            if let id = row.integer("id") { receivableIDs[id] = stableID(row.string("uuid"), table: "receivable_assets", id: id) }
        }
        var sessionIDs: [String: UUID] = [:]
        for row in sessionRows {
            let raw = row.string("session_id", fallback: "record")
            sessionIDs[raw] = stableID(raw, table: "chat_sessions", id: nil)
        }
        sessionIDs["record"] = sessionIDs["record"] ?? stableID("record", table: "chat_sessions", id: nil)

        var aiRunIDs: [String: UUID] = [:]
        for row in aiRunRows {
            let raw = row.string("id")
            if !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                aiRunIDs[raw] = stableID(raw, table: "ai_runs", id: nil)
            }
        }

        var budgetPlanIDs: [Int64: UUID] = [:]
        for row in budgetPlanRows {
            if let id = row.integer("id") { budgetPlanIDs[id] = stableID(row.string("uuid"), table: "budget_plans", id: id) }
        }
        var budgetRevisionIDs: [Int64: UUID] = [:]
        for row in budgetRevisionRows {
            if let id = row.integer("id") { budgetRevisionIDs[id] = stableID(row.string("uuid"), table: "budget_plan_revisions", id: id) }
        }

        let books = bookRows.compactMap { row -> BackupBook? in
            guard let id = row.integer("id"), let stable = bookIDs[id] else { return nil }
            let name = row.string("name", fallback: "账本")
            return BackupBook(
                id: stable,
                name: name,
                cover: row.optionalString("cover"),
                remark: row.string("remark"),
                sortOrder: Int(row.integer("sort_order") ?? id),
                isStarred: row.bool("starred"),
                includeInTotal: row.bool("include_in_total", fallback: true),
                isDefault: stable == defaultBookID || name == "总账本",
                updatedAt: date(row.integer("updated_ms"))
            )
        }

        let accounts = accountRows.compactMap { row -> BackupAccount? in
            guard let id = row.integer("id"), let stable = accountIDs[id] else { return nil }
            let rawType = row.string("type")
            let kind: AccountKind
            switch rawType {
            case "debit": kind = .bankCard
            case "credit": kind = .creditCard
            case "we_chat": kind = .weChat
            case "alipay": kind = .alipay
            default: kind = AccountKind(rawValue: rawType) ?? .other
            }
            return BackupAccount(
                id: stable,
                name: row.string("name", fallback: "账户"),
                kind: kind,
                currencyCode: row.string("currency_code", fallback: "CNY"),
                initialBalance: row.decimal("opening_balance"),
                sortOrder: Int(row.integer("sort_order") ?? id),
                institution: row.optionalString("institution"),
                includeInNetWorth: row.bool("include_in_net_worth", fallback: true),
                isDeleted: row.bool("is_deleted"),
                status: AccountStatus(rawValue: row.string("status")),
                archivedAt: date(row.integer("archived_ms")),
                lastVerifiedAt: date(row.integer("last_verified_ms")),
                openingBalanceEffectiveAt: date(row.integer("opening_balance_effective_ms")),
                openingBalanceQuality: AccountOpeningBalanceQuality(rawValue: row.string("opening_balance_quality")),
                balanceMode: LiabilityBalanceMode(rawValue: row.string("balance_mode")),
                creditStatementDay: row.integer("statement_day").map(Int.init) ?? row.integer("credit_statement_day").map(Int.init),
                creditPaymentDay: row.integer("payment_day").map(Int.init) ?? row.integer("credit_payment_day").map(Int.init),
                creditLimit: row.optionalDecimal("credit_limit"),
                updatedAt: date(row.integer("updated_ms"))
            )
        }

        let categories = categoryRows.compactMap { row -> BackupCategory? in
            guard let id = row.integer("id"), let category = categoryByID[id] else { return nil }
            let seed = CategorySeed.byKey(category.key)
            return BackupCategory(
                key: category.key,
                name: category.name,
                symbol: seed?.symbol ?? "tag",
                emoji: seed?.emoji ?? "🏷️",
                kind: category.kind,
                parentKey: category.parentKey,
                sortOrder: Int(id),
                isArchived: row.bool("hidden")
            )
        }

        let tags = tagRows.compactMap { row -> BackupTag? in
            guard let id = row.integer("id") else { return nil }
            return BackupTag(
                id: stableID(row.string("uuid"), table: "tags", id: id),
                name: row.string("name", fallback: "标签"),
                colorValue: Int(row.integer("color") ?? Int64(0x7D8B9B)),
                sortOrder: Int(id),
                updatedAt: nil
            )
        }

        let transactions = transactionRows.compactMap { row -> BackupTransaction? in
            guard let id = row.integer("id"), let stable = transactionIDs[id] else { return nil }
            let kind = TransactionKind(rawValue: row.string("kind")) ?? .expense
            let category = row.integer("category_id").flatMap { categoryByID[$0] }
            let eventType = TransactionEventType(rawValue: row.string("event_type")) ?? .defaultFor(kind)
            let tagValues = row.string("tags")
                .split(separator: ",")
                .map { part -> String in
                    let raw = part.trimmingCharacters(in: .whitespacesAndNewlines)
                    return Int64(raw).flatMap { tagNamesByID[$0] } ?? raw
                }
                .filter { !$0.isEmpty }
            let refundID = row.integer("refund_of").flatMap { transactionIDs[$0] }
            return BackupTransaction(
                id: stable,
                amount: row.decimal("amount"),
                kind: kind,
                date: date(row.integer("date_ms")) ?? exportedAt,
                note: row.string("note"),
                merchant: nil,
                product: nil,
                currencyCode: row.string("currency_code", fallback: "CNY"),
                categoryKey: category?.key,
                accountID: row.integer("account_id").flatMap { accountIDs[$0] },
                toAccountID: row.integer("to_account_id").flatMap { accountIDs[$0] },
                bookID: row.integer("book_id").flatMap { bookIDs[$0] } ?? defaultBookID,
                refundOfID: refundID,
                isReimbursed: eventType == .reimbursement,
                isExcluded: row.bool("excluded"),
                tags: tagValues,
                categoryName: category?.name,
                topCategoryKey: category?.parentKey ?? category?.key,
                topCategoryName: category?.parentKey.flatMap { CategorySeed.byKey($0)?.nameZh } ?? (category?.parentKey == nil ? category?.name : nil),
                timePrecision: TransactionTimePrecision(rawValue: row.string("time_precision")),
                createdAt: date(row.integer("created_ms")),
                settledAt: date(row.integer("settled_ms")),
                settlementQuality: SettlementQuality(rawValue: row.string("settlement_quality")),
                settlementAccountID: row.integer("settlement_account_id").flatMap { accountIDs[$0] },
                settlementAccountQuality: SettlementQuality(rawValue: row.string("settlement_account_quality")),
                eventType: eventType,
                reimbursable: row.bool("reimbursable"),
                attachmentPath: storedPath(row.string("image_path")),
                orderNo: row.string("order_no"),
                recurringRuleID: row.integer("recurring_rule_id").flatMap { recurringIDs[$0] },
                updatedAt: date(row.integer("updated_ms"))
            )
        }

        var budgets: [BackupBudget] = []
        for row in budgetRows {
            guard let id = row.integer("id") else { continue }
            let key = row.optionalString("category_key")
            budgets.append(BackupBudget(
                id: stableID("legacy-\(id)", table: "budget", id: id),
                amount: row.decimal("amount"),
                categoryKey: key,
                updatedAt: nil
            ))
        }
        for row in budgetPeriodRows {
            guard let id = row.integer("id") else { continue }
            let start = date(row.integer("start_ms"))
            let end = date(row.integer("end_ms"))
            let cycle = row.bool("recurring_monthly", fallback: true) ? "monthly" : "custom"
            let bookID = row.integer("book_id").flatMap { bookIDs[$0] } ?? defaultBookID
            budgets.append(BackupBudget(
                id: stableID("total-\(id)", table: "budget_periods", id: id),
                amount: row.decimal("total"),
                bookID: bookID,
                periodStart: start,
                periodEnd: end,
                cycleRaw: cycle,
                updatedAt: date(row.integer("created_ms"))
            ))
            for (key, amount) in categoryBudgets(row.string("category_budgets")) {
                budgets.append(BackupBudget(
                    id: stableID("category-\(id)-\(key)", table: "budget_periods", id: id),
                    amount: amount,
                    categoryKey: key,
                    bookID: bookID,
                    periodStart: start,
                    periodEnd: end,
                    cycleRaw: cycle,
                    updatedAt: date(row.integer("created_ms"))
                ))
            }
        }

        let savingsGoals = savingsRows.compactMap { row -> BackupSavingsGoal? in
            guard let id = row.integer("id"), let stable = savingsIDs[id] else { return nil }
            let linkedAsset = assetRows.first(where: { $0.integer("savings_goal_id") == id })
                .flatMap { $0.integer("id") }
                .flatMap { assetIDs[$0] }
            return BackupSavingsGoal(
                id: stable,
                name: row.string("name", fallback: "存钱目标"),
                emoji: row.string("emoji", fallback: "🐷"),
                targetAmount: row.decimal("target_amount"),
                savedAmount: row.decimal("saved_amount"),
                currencyCode: row.string("currency_code", fallback: "CNY"),
                linkedAssetID: linkedAsset,
                updatedAt: date(row.integer("updated_ms"))
            )
        }

        let recurringRules = recurringRows.compactMap { row -> BackupRecurringRule? in
            guard let id = row.integer("id"), let stable = recurringIDs[id] else { return nil }
            let next = date(row.integer("next_due_ms")) ?? exportedAt
            return BackupRecurringRule(
                id: stable,
                bookID: row.integer("book_id").flatMap { bookIDs[$0] } ?? defaultBookID,
                kind: TransactionKind(rawValue: row.string("kind")) ?? .expense,
                amount: row.decimal("amount"),
                categoryKey: row.integer("category_id").flatMap { categoryByID[$0]?.key },
                accountID: row.integer("account_id").flatMap { accountIDs[$0] },
                toAccountID: row.integer("to_account_id").flatMap { accountIDs[$0] },
                note: row.string("note"),
                periodRaw: row.string("period", fallback: "monthly"),
                startDate: date(row.integer("start_date_ms")) ?? next,
                nextDueDate: next,
                endDate: date(row.integer("end_date_ms")),
                totalCount: row.integer("total_count").map(Int.init),
                generatedCount: Int(row.integer("generated_count") ?? 0),
                anchorDay: Int(row.integer("anchor_day") ?? 0),
                isEnabled: row.bool("enabled", fallback: true),
                updatedAt: date(row.integer("updated_ms")) ?? date(row.integer("created_ms"))
            )
        }

        let recurringOccurrences = recurringOccurrenceRows.compactMap { row -> BackupRecurringOccurrence? in
            guard let ruleID = row.integer("rule_id"), let ruleUUID = recurringIDs[ruleID],
                  let dueMs = row.integer("due_ms") else { return nil }
            let composite = "\(ruleID)-\(dueMs)"
            return BackupRecurringOccurrence(
                id: stableID(composite, table: "recurring_occurrences", id: ruleID),
                ruleID: ruleUUID,
                dueDate: date(dueMs) ?? exportedAt,
                transactionID: row.integer("transaction_id").flatMap { transactionIDs[$0] },
                createdAt: date(row.integer("created_ms"))
            )
        }

        let physicalAssets = assetRows.compactMap { row -> BackupPhysicalAsset? in
            guard let id = row.integer("id"), let stable = assetIDs[id] else { return nil }
            return BackupPhysicalAsset(
                id: stable,
                bookID: row.integer("book_id").flatMap { bookIDs[$0] } ?? defaultBookID,
                name: row.string("name", fallback: "物品资产"),
                kindRaw: row.string("asset_type", fallback: "other"),
                lifecycleRaw: physicalLifecycle(row),
                economicStatusRaw: row.optionalString("economic_status"),
                usageStatusRaw: row.optionalString("usage_status"),
                visibilityStatusRaw: row.optionalString("visibility_status"),
                inclusionQualityRaw: row.optionalString("inclusion_quality"),
                sourceTypeRaw: row.optionalString("source_type"),
                acquisitionCostSourceRaw: row.optionalString("acquisition_cost_source"),
                purchasePrice: row.decimal("purchase_price"),
                currentValue: row.decimal("current_value"),
                currencyCode: row.string("currency_code", fallback: "CNY"),
                purchaseDate: date(row.integer("purchase_date_ms")),
                brand: row.string("brand"),
                model: row.string("model"),
                location: row.string("location"),
                warrantyUntil: date(row.integer("warranty_until_ms")),
                usageTrackingEnabled: row.bool("usage_tracking_enabled"),
                usageCount: Int(row.integer("usage_count") ?? Int64(usageCountByAsset[id] ?? 0)),
                savingsGoalID: row.integer("savings_goal_id").flatMap { savingsIDs[$0] },
                photoPath: storedMediaPath(row.string("photo_path")),
                thumbnailPath: storedMediaPath(row.string("thumbnail_path")),
                invoicePath: storedMediaPath(row.string("invoice_path")),
                depreciationMethod: row.string("depreciation_method"),
                depreciationBase: row.decimal("depreciation_base"),
                salvageValue: row.decimal("salvage_value"),
                usefulLifeMonths: Int(row.integer("useful_life_months") ?? 0),
                depreciationStartDate: date(row.integer("depreciation_start_ms")),
                depreciationPaused: row.bool("depreciation_paused"),
                note: row.string("note"),
                includeInNetWorth: row.bool("include_in_net_worth", fallback: true),
                isDeleted: row.bool("is_deleted"),
                endedAt: date(row.integer("ended_ms")),
                archivedAt: date(row.integer("archived_ms")),
                createdAt: date(row.integer("created_ms")),
                updatedAt: date(row.integer("updated_ms"))
            )
        }

        let assetEvents = assetEventRows.compactMap { row -> BackupAssetEvent? in
            guard let id = row.integer("id"), let assetID = row.integer("asset_id") else { return nil }
            let objectType = row.string("asset_type", fallback: "physical").lowercased()
            let stableAssetID = objectType == "receivable" ? receivableIDs[assetID] : assetIDs[assetID]
            guard let stableAssetID else { return nil }
            return BackupAssetEvent(
                id: stableID(row.string("uuid"), table: "asset_events", id: id),
                assetID: stableAssetID,
                kindRaw: assetEventKind(row.string("event_type")),
                occurredAt: date(row.integer("occurred_ms")) ?? exportedAt,
                value: row.optionalDecimal("value"),
                note: row.string("note"),
                metadataJSON: row.string("metadata"),
                createdAt: date(row.integer("created_ms"))
            )
        }

        let assetUsageEvents = assetUsageRows.compactMap { row -> BackupAssetUsageEvent? in
            guard let id = row.integer("id"),
                  let assetID = row.integer("asset_id"),
                  let stableAssetID = assetIDs[assetID],
                  let stableID = assetUsageIDs[id] else { return nil }
            return BackupAssetUsageEvent(
                id: stableID,
                assetID: stableAssetID,
                countDelta: Int(row.integer("count_delta") ?? 0),
                reversalOfID: row.integer("reversal_of").flatMap { assetUsageIDs[$0] },
                occurredAt: date(row.integer("occurred_ms")) ?? exportedAt,
                note: row.string("note"),
                createdAt: date(row.integer("created_ms")),
                updatedAt: date(row.integer("updated_ms"))
            )
        }

        let assetTransactionLinks = assetLinkRows.compactMap { row -> BackupAssetTransactionLink? in
            guard let id = row.integer("id"),
                  let stable = assetLinkIDs[id],
                  let assetID = row.integer("asset_id"),
                  let transactionID = row.integer("transaction_id").flatMap({ transactionIDs[$0] }) else { return nil }
            let objectType = row.string("asset_object_type", fallback: "physical").lowercased()
            let stableAssetID = objectType == "receivable" ? receivableIDs[assetID] : assetIDs[assetID]
            guard let stableAssetID else { return nil }
            return BackupAssetTransactionLink(
                id: stable,
                assetID: stableAssetID,
                assetObjectType: objectType,
                transactionID: transactionID,
                linkTypeRaw: row.string("link_type", fallback: "source_transaction"),
                amount: row.decimal("amount"),
                allocatedGrossCents: Int(row.integer("allocated_gross_cents") ?? 0),
                allocatedRefundCents: Int(row.integer("allocated_refund_cents") ?? 0),
                costQualityRaw: row.string("cost_quality", fallback: "partial"),
                note: row.string("note"),
                createdAt: date(row.integer("created_ms")),
                updatedAt: date(row.integer("updated_ms"))
            )
        }

        let assetRefundAllocations = assetRefundRows.compactMap { row -> BackupAssetRefundAllocation? in
            guard let id = row.integer("id"),
                  let stable = assetRefundAllocationIDs[id],
                  let linkID = row.integer("asset_transaction_link_id").flatMap({ assetLinkIDs[$0] }),
                  let refundID = row.integer("refund_transaction_id").flatMap({ transactionIDs[$0] }) else { return nil }
            return BackupAssetRefundAllocation(
                id: stable,
                assetTransactionLinkID: linkID,
                refundTransactionID: refundID,
                allocatedRefundCents: Int(row.integer("allocated_refund_cents") ?? 0),
                statusRaw: row.string("status", fallback: "active"),
                createdAt: date(row.integer("created_ms")),
                updatedAt: date(row.integer("updated_ms"))
            )
        }

        let assetValuations = assetValuationRows.compactMap { row -> BackupAssetValuation? in
            guard let id = row.integer("id"), let assetID = row.integer("asset_id"),
                  let stableAssetID = assetIDs[assetID] else { return nil }
            return BackupAssetValuation(
                id: stableID(row.string("uuid"), table: "asset_valuations", id: id),
                assetID: stableAssetID,
                value: row.decimal("value"),
                sourceRaw: row.string("source", fallback: "manual"),
                valuedAt: date(row.integer("valued_at_ms")) ?? exportedAt,
                note: row.string("note"),
                createdAt: date(row.integer("created_ms"))
            )
        }

        let receivableAssets = receivableRows.compactMap { row -> BackupReceivableAsset? in
            guard let id = row.integer("id"), let stable = receivableIDs[id] else { return nil }
            return BackupReceivableAsset(
                id: stable,
                bookID: row.integer("book_id").flatMap { bookIDs[$0] } ?? defaultBookID,
                name: row.string("name", fallback: "应收权益"),
                kindRaw: receivableKind(row.string("receivable_type")),
                lifecycleRaw: receivableLifecycle(row.string("status")),
                economicStatusRaw: row.optionalString("economic_status"),
                visibilityStatusRaw: row.optionalString("visibility_status"),
                inclusionQualityRaw: row.optionalString("inclusion_quality"),
                originalAmount: row.decimal("original_amount"),
                remainingAmount: row.decimal("remaining_amount"),
                currencyCode: row.string("currency_code", fallback: "CNY"),
                counterparty: row.string("counterparty"),
                dueDate: date(row.integer("due_date_ms")),
                includeInNetWorth: row.bool("include_in_net_worth", fallback: true),
                note: row.string("note"),
                isDeleted: row.bool("is_deleted"),
                endedAt: date(row.integer("ended_ms")),
                archivedAt: date(row.integer("archived_ms")),
                createdAt: date(row.integer("created_ms")),
                updatedAt: date(row.integer("updated_ms"))
            )
        }

        let receivableRecoveries = recoveryRows.compactMap { row -> BackupReceivableRecovery? in
            guard let id = row.integer("id"), let receivableID = row.integer("receivable_asset_id"),
                  let stableReceivableID = receivableIDs[receivableID] else { return nil }
            return BackupReceivableRecovery(
                id: stableID(row.string("uuid"), table: "receivable_recoveries", id: id),
                receivableID: stableReceivableID,
                amount: row.decimal("amount"),
                recoveredAt: date(row.integer("recovered_ms")) ?? exportedAt,
                targetAccountID: row.integer("target_account_id").flatMap { accountIDs[$0] },
                transactionID: row.integer("transaction_id").flatMap { transactionIDs[$0] },
                note: row.string("note"),
                createdAt: date(row.integer("created_ms"))
            )
        }

        let liabilities = liabilityRows.compactMap { row -> BackupLiabilityProfile? in
            guard let id = row.integer("id") else { return nil }
            return BackupLiabilityProfile(
                id: stableID(row.string("uuid"), table: "liability_profiles", id: id),
                accountID: row.integer("account_id").flatMap { accountIDs[$0] },
                repaymentAccountID: row.integer("repayment_account_id").flatMap { accountIDs[$0] },
                kindRaw: liabilityKind(row.string("liability_type")),
                lifecycleRaw: liabilityLifecycle(row.string("status")),
                originalPrincipal: row.decimal("original_amount"),
                currentPrincipal: row.decimal("current_principal"),
                currencyCode: row.string("currency_code", fallback: "CNY"),
                counterparty: row.string("counterparty"),
                annualRate: row.optionalDecimal("interest_rate"),
                startDate: date(row.integer("start_date_ms")),
                dueDate: date(row.integer("end_date_ms")),
                statementDay: row.integer("statement_day").map(Int.init),
                paymentDay: row.integer("repayment_day").map(Int.init),
                creditLimit: row.optionalDecimal("credit_limit"),
                note: row.string("note"),
                updatedAt: date(row.integer("updated_ms"))
            )
        }

        let netWorthSnapshots = snapshotRows.compactMap { row -> BackupNetWorthSnapshot? in
            guard let id = row.integer("id") else { return nil }
            let asOf = date(row.integer("as_of_ms")) ?? parseDate(row.string("snapshot_date")) ?? exportedAt
            let knowledgeCutoff = date(row.integer("knowledge_cutoff_ms")) ?? asOf
            return BackupNetWorthSnapshot(
                id: stableID(row.string("uuid"), table: "net_worth_snapshots", id: id),
                asOf: asOf,
                knowledgeCutoff: knowledgeCutoff,
                scopeKey: row.string("scope_key", fallback: "global"),
                scopeVersion: Int(row.integer("scope_version") ?? 1),
                calculationVersion: Int(row.integer("calculation_version") ?? 1),
                baseCurrency: row.string("base_currency", fallback: "CNY"),
                coveredCurrenciesJSON: row.string("currency_coverage_json", fallback: "[\"CNY\"]"),
                uncoveredCurrenciesJSON: "[]",
                qualityRaw: row.string("quality", fallback: "legacy_unverified"),
                cashAssets: row.decimal("cash_assets"),
                investmentAssets: row.decimal("investment_assets"),
                physicalAssets: row.decimal("physical_assets"),
                receivableAssets: row.decimal("receivable_assets"),
                liabilities: row.decimal("total_liabilities"),
                reasonsJSON: row.string("reasons_json", fallback: "[]"),
                causesJSON: row.string("cause_set_json", fallback: "[]"),
                provisional: row.bool("provisional"),
                createdAt: date(row.integer("created_ms"))
            )
        }

        let accountBalanceCheckpoints = accountCheckpointRows.compactMap { row -> BackupAccountBalanceCheckpoint? in
            guard let id = row.integer("id"),
                  let stable = accountCheckpointIDs[id],
                  let accountID = row.integer("account_id").flatMap({ accountIDs[$0] }) else { return nil }
            return BackupAccountBalanceCheckpoint(
                id: stable,
                accountID: accountID,
                eventKindRaw: row.string("event_kind", fallback: "anchor"),
                effectiveAt: date(row.integer("effective_ms")) ?? exportedAt,
                sequence: Int(row.integer("sequence") ?? 0),
                timezone: row.string("timezone", fallback: "device_local"),
                knowledgeCutoff: date(row.integer("knowledge_cutoff_ms")) ?? exportedAt,
                targetBalance: row.decimal("target_balance"),
                calculatedBefore: row.decimal("calculated_before"),
                deltaAtCreation: row.decimal("delta_at_creation"),
                reason: row.string("reason", fallback: "manual"),
                note: row.string("note"),
                status: row.string("status", fallback: "active"),
                reversalOfID: row.integer("reversal_of").flatMap { accountCheckpointIDs[$0] },
                coveredUnknownEventIDs: (unknownEventsByCheckpoint[id] ?? []).sorted(),
                createdAt: date(row.integer("created_ms")) ?? exportedAt,
                updatedAt: date(row.integer("updated_ms")) ?? exportedAt
            )
        }

        let netWorthVerifiedCheckpoints = verifiedNetWorthRows.compactMap { row -> BackupNetWorthVerifiedCheckpoint? in
            guard let id = row.integer("id"), let stable = verifiedNetWorthIDs[id] else { return nil }
            return BackupNetWorthVerifiedCheckpoint(
                id: stable,
                asOf: date(row.integer("as_of_ms")) ?? exportedAt,
                knowledgeCutoff: date(row.integer("knowledge_cutoff_ms")) ?? exportedAt,
                scopeVersion: Int(row.integer("scope_version") ?? 1),
                calculationVersion: Int(row.integer("calculation_version") ?? 1),
                currencyCoverageJSON: row.string("currency_coverage_json"),
                totalAssets: row.decimal("total_assets"),
                totalLiabilities: row.decimal("total_liabilities"),
                netWorth: row.decimal("net_worth"),
                completenessRaw: row.string("completeness", fallback: "partial"),
                reasonsJSON: row.string("reasons_json"),
                statusRaw: row.string("status", fallback: "active"),
                supersedesID: row.integer("supersedes_id").flatMap { verifiedNetWorthIDs[$0] },
                createdAt: date(row.integer("created_ms")) ?? exportedAt
            )
        }

        let netWorthVerifiedItems = verifiedNetWorthItemRows.compactMap { row -> BackupNetWorthVerifiedCheckpointItem? in
            guard let checkpointID = row.integer("checkpoint_id"),
                  let stableCheckpointID = verifiedNetWorthIDs[checkpointID] else { return nil }
            return BackupNetWorthVerifiedCheckpointItem(
                checkpointID: stableCheckpointID,
                objectType: row.string("object_type", fallback: "unknown"),
                objectUUID: row.string("object_uuid", fallback: "unknown"),
                confirmedAmount: row.decimal("confirmed_amount"),
                currencyCode: row.string("currency_code", fallback: "CNY"),
                valueEffectiveAt: date(row.integer("value_effective_ms")) ?? exportedAt,
                valueSource: row.string("value_source", fallback: "unknown"),
                quality: row.string("quality", fallback: "partial")
            )
        }

        let aiChatSessions = sessionRows.compactMap { row -> BackupAIChatSession? in
            let rawID = row.string("session_id", fallback: "record")
            guard let id = sessionIDs[rawID] else { return nil }
            return BackupAIChatSession(
                id: id,
                title: row.string("title", fallback: rawID == "record" ? "记一记" : "新对话"),
                createdAt: date(row.integer("created_ms")) ?? exportedAt,
                updatedAt: date(row.integer("updated_ms")) ?? exportedAt,
                isStarred: row.bool("starred"),
                isRecord: row.bool("is_record") || rawID == "record",
                providerID: row.optionalString("provider_id").map { stableID($0, table: "ai_provider", id: nil) },
                model: row.string("model"),
                effortRaw: row.string("effort", fallback: "low")
            )
        }

        let aiChatMessages = messageRows.compactMap { row -> BackupAIChatMessage? in
            guard let id = row.integer("id") else { return nil }
            let rawSessionID = row.string("session_id", fallback: "record")
            let sessionID = sessionIDs[rawSessionID] ?? sessionIDs["record"]!
            let question = row.string("question")
            let text = row.string("text")
            let attachments = row.string("attachments_json")
            return BackupAIChatMessage(
                id: stableID(row.string("uuid"), table: "chat_messages", id: id),
                sessionID: sessionID,
                role: row.string("role", fallback: "assistant"),
                content: question.isEmpty ? text : question,
                createdAt: date(row.integer("created_ms")) ?? exportedAt,
                attachmentsJSON: attachments,
                isError: false
            )
        }

        let aiMemories = aiMemoryRows.compactMap { row -> BackupAIMemory? in
            let rawID = row.string("id")
            guard !rawID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let created = date(row.integer("created_ms")) ?? exportedAt
            let updated = date(row.integer("updated_ms")) ?? created
            let sessionID = row.optionalString("session_id").map {
                sessionIDs[$0] ?? stableID($0, table: "chat_sessions", id: nil)
            }
            return BackupAIMemory(
                id: stableID(rawID, table: "ai_memories", id: nil),
                phrase: row.string("phrase"),
                content: row.string("content"),
                source: row.string("source", fallback: "user"),
                sessionID: sessionID,
                consent: row.bool("consent"),
                statusRaw: row.string("status", fallback: "active"),
                createdAt: created,
                updatedAt: updated,
                lastUsedAt: date(row.integer("last_used_ms"))
            )
        }

        let aiRequestRuns = aiRunRows.compactMap { row -> BackupAIRequestRun? in
            let rawID = row.string("id")
            guard let id = aiRunIDs[rawID] else { return nil }
            let rawSessionID = row.string("session_id", fallback: "record")
            let sessionID = sessionIDs[rawSessionID] ?? UUID(uuidString: rawSessionID)
            let createdAt = date(row.integer("created_ms")) ?? exportedAt
            let updatedAt = date(row.integer("updated_ms")) ?? createdAt
            let status = normalizedAIStatus(row.string("status", fallback: "queued"))
            let result = row.string("result_json")
            return BackupAIRequestRun(
                id: id,
                sessionID: sessionID,
                modeRaw: normalizedAIMode(row.string("mode", fallback: "chat")),
                statusRaw: status,
                providerID: row.optionalString("provider_id").map {
                    stableID($0, table: "ai_provider", id: nil)
                },
                providerLabel: row.string("provider_label"),
                model: row.string("model"),
                effortRaw: row.string("effort", fallback: "low"),
                endpointRaw: row.string("endpoint_type", fallback: "auto"),
                resultSummary: result.isEmpty ? "" : "已保留结果记录",
                errorMessage: row.string("error_message"),
                createdAt: createdAt,
                startedAt: status == "queued" ? nil : createdAt,
                finishedAt: isTerminalAIStatus(status) ? updatedAt : nil,
                updatedAt: updatedAt
            )
        }

        // Android report jobs are a separate durable queue rather than rows in
        // ai_runs. Preserve their audit trail as scheduled-report runs on iOS;
        // raw prompts and report result JSON are deliberately not copied.
        let reportJobRuns = reportJobRows.compactMap { row -> BackupAIRequestRun? in
            let rawID = row.string("uuid")
            guard !rawID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let id = stableID(rawID, table: "report_jobs", id: nil)
            if aiRequestRuns.contains(where: { $0.id == id }) { return nil }
            let createdAt = date(row.integer("created_ms")) ?? exportedAt
            let updatedAt = date(row.integer("updated_ms")) ?? createdAt
            let status = normalizedAIStatus(row.string("status", fallback: "queued"))
            let question = row.string("question")
            return BackupAIRequestRun(
                id: id,
                sessionID: sessionIDs[row.string("session_id", fallback: "record")],
                modeRaw: "scheduled_report",
                statusRaw: status,
                providerID: row.optionalString("provider_id").map {
                    stableID($0, table: "ai_provider", id: nil)
                },
                providerLabel: "",
                model: row.string("model"),
                effortRaw: row.string("effort", fallback: "low"),
                endpointRaw: "",
                inputCharacters: question.count,
                resultSummary: row.string("title"),
                errorMessage: row.string("error"),
                createdAt: createdAt,
                startedAt: date(row.integer("model_started_ms")),
                finishedAt: isTerminalAIStatus(status) ? updatedAt : nil,
                updatedAt: updatedAt
            )
        }

        let aiRequestEvents = aiRunEventRows.compactMap { row -> BackupAIRequestEvent? in
            let rawRunID = row.string("run_id")
            guard let runID = aiRunIDs[rawRunID],
                  let sequence = row.integer("sequence") else { return nil }
            let rawType = row.string("type", fallback: "stageChanged")
            let eventID = stableID(
                "\(rawRunID)#\(sequence)",
                table: "ai_run_events",
                id: nil
            )
            return BackupAIRequestEvent(
                id: eventID,
                runID: runID,
                sequence: Int(sequence),
                typeRaw: normalizedAIEventType(rawType),
                summary: eventSummary(from: row.string("payload_json")),
                count: eventCount(from: row.string("payload_json")),
                createdAt: date(row.integer("created_ms")) ?? exportedAt
            )
        }

        let aiReportSchedules = aiReportScheduleRows.compactMap { row -> BackupAIReportSchedule? in
            let rawID = row.string("id")
            guard !rawID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let createdAt = date(row.integer("created_ms")) ?? exportedAt
            let updatedAt = date(row.integer("updated_ms")) ?? createdAt
            return BackupAIReportSchedule(
                id: stableID(rawID, table: "ai_report_schedules", id: nil),
                sessionID: sessionIDs[row.string("session_id", fallback: "record")],
                title: row.string("title", fallback: "周期账本报告"),
                reportType: row.string("report_type", fallback: "monthly"),
                periodKind: row.string("period_kind", fallback: "monthly"),
                dayValue: Int(row.integer("day_value") ?? 1),
                enabled: row.bool("enabled", fallback: true),
                nextRunAt: date(row.integer("next_run_ms")) ?? exportedAt,
                providerID: row.optionalString("provider_id").map {
                    stableID($0, table: "ai_provider", id: nil)
                },
                model: row.string("model"),
                effortRaw: row.string("effort", fallback: "low"),
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }

        let budgetPlansV2 = budgetPlanRows.compactMap { row -> BackupBudgetPlanV2? in
            guard let id = row.integer("id"),
                  let stable = budgetPlanIDs[id],
                  let bookID = row.integer("book_id").flatMap({ bookIDs[$0] }),
                  let anchorStart = civilDay(row.integer("anchor_start_day")) else { return nil }
            return BackupBudgetPlanV2(
                id: stable,
                bookID: bookID,
                currencyCode: row.string("currency_code", fallback: "CNY"),
                timezone: row.string("timezone", fallback: "device_local"),
                name: row.string("name"),
                role: row.string("role", fallback: "primary"),
                cadenceRaw: row.string("cadence", fallback: "monthly"),
                anchorStart: anchorStart,
                monthStartDay: row.integer("month_start_day").map(Int.init),
                weekStart: row.integer("week_start").map { Int(($0 % 7) + 1) },
                endInclusive: civilDay(row.integer("end_day")),
                expenseScopeJSON: row.string("expense_scope_json"),
                statusRaw: row.string("status", fallback: "active"),
                createdAt: date(row.integer("created_ms")) ?? exportedAt,
                updatedAt: date(row.integer("updated_ms")) ?? exportedAt
            )
        }

        let budgetPlanRevisionsV2 = budgetRevisionRows.compactMap { row -> BackupBudgetPlanRevisionV2? in
            guard let id = row.integer("id"),
                  let stable = budgetRevisionIDs[id],
                  let planID = row.integer("plan_id").flatMap({ budgetPlanIDs[$0] }),
                  let effectiveStart = civilDay(row.integer("effective_cycle_start_day")) else { return nil }
            return BackupBudgetPlanRevisionV2(
                id: stable,
                planID: planID,
                effectiveCycleStart: effectiveStart,
                effectiveToCycleStart: civilDay(row.integer("effective_to_cycle_start_day")),
                amountCents: Int(row.integer("amount_cents") ?? 0),
                categoryBudgetsJSON: row.string("category_budgets_json", fallback: "{}"),
                monthlyIncomeCents: row.integer("monthly_income_cents").map(Int.init),
                fixedTemplatesJSON: row.string("fixed_templates_json", fallback: "[]"),
                legacySourcePeriodID: row.integer("legacy_source_period_id").map(Int.init),
                createdAt: date(row.integer("created_ms")) ?? exportedAt,
                updatedAt: date(row.integer("updated_ms")) ?? exportedAt
            )
        }

        let budgetCycleOverridesV2 = budgetOverrideRows.compactMap { row -> BackupBudgetCycleOverrideV2? in
            guard let id = row.integer("id"),
                  let planID = row.integer("plan_id").flatMap({ budgetPlanIDs[$0] }),
                  let cycleStart = civilDay(row.integer("cycle_start_day")),
                  let cycleEnd = civilDay(row.integer("cycle_end_day")) else { return nil }
            return BackupBudgetCycleOverrideV2(
                id: stableID(row.string("uuid"), table: "budget_cycle_overrides", id: id),
                planID: planID,
                cycleStart: cycleStart,
                cycleEndInclusive: cycleEnd,
                targetAmountCents: Int(row.integer("target_amount_cents") ?? 0),
                categoryBudgetsJSON: row.optionalString("category_budgets_json"),
                inputIntentRaw: row.string("input_intent", fallback: "replace_total"),
                inputDeltaCents: row.integer("input_delta_cents").map(Int.init),
                createdAt: date(row.integer("created_ms")) ?? exportedAt,
                updatedAt: date(row.integer("updated_ms")) ?? exportedAt
            )
        }

        let budgetCommitmentOccurrencesV2 = budgetCommitmentRows.compactMap { row -> BackupBudgetCommitmentOccurrenceV2? in
            guard let id = row.integer("id"),
                  let planID = row.integer("plan_id").flatMap({ budgetPlanIDs[$0] }),
                  let revisionID = row.integer("revision_id").flatMap({ budgetRevisionIDs[$0] }),
                  let cycleStart = civilDay(row.integer("cycle_start_day")),
                  let cycleEnd = civilDay(row.integer("cycle_end_day")),
                  let dueDate = civilDay(row.integer("due_day")) else { return nil }
            return BackupBudgetCommitmentOccurrenceV2(
                id: stableID(row.string("uuid"), table: "budget_fixed_commitment_occurrences", id: id),
                planID: planID,
                revisionID: revisionID,
                templateID: row.string("template_id"),
                cycleStart: cycleStart,
                cycleEndInclusive: cycleEnd,
                dueDate: dueDate,
                plannedCents: Int(row.integer("planned_cents") ?? 0),
                resolutionStatusRaw: row.string("resolution_status", fallback: "planned"),
                reviewReasonRaw: row.string("review_reason"),
                matchedTransactionFamilyID: row.optionalString("matched_transaction_family_uuid"),
                resolvedAt: date(row.integer("resolved_ms")),
                createdAt: date(row.integer("created_ms")) ?? exportedAt,
                updatedAt: date(row.integer("updated_ms")) ?? exportedAt
            )
        }

        let budgetChangeEventsV2 = budgetChangeRows.compactMap { row -> BackupBudgetChangeEventV2? in
            guard let id = row.integer("id"),
                  let planID = row.integer("plan_id").flatMap({ budgetPlanIDs[$0] }) else { return nil }
            return BackupBudgetChangeEventV2(
                id: stableID(row.string("uuid"), table: "budget_change_events", id: id),
                planID: planID,
                eventType: row.string("event_type"),
                beforeJSON: row.string("before_json"),
                afterJSON: row.string("after_json"),
                createdAt: date(row.integer("created_ms")) ?? exportedAt
            )
        }

        let reports = reportRows.compactMap { row -> BackupReport? in
            guard let id = row.integer("id") else { return nil }
            let periodStart = date(row.integer("period_start_ms")) ?? exportedAt
            let periodEnd = date(row.integer("period_end_ms")) ?? periodStart
            return BackupReport(
                id: stableID(row.string("uuid"), table: "reports", id: id),
                bookID: row.integer("book_id").flatMap { bookIDs[$0] },
                type: row.string("type", fallback: "monthly"),
                title: row.string("title"),
                summary: row.string("summary"),
                markdown: row.string("markdown"),
                periodStart: periodStart,
                periodEnd: periodEnd,
                createdAt: date(row.integer("created_ms")) ?? exportedAt,
                pinnedAt: date(row.integer("pinned_ms"))
            )
        }

        return FeimiaoBackupPackage(
            schemaVersion: FeimiaoBackupPackage.currentSchemaVersion,
            exportedAt: exportedAt,
            books: books,
            accounts: accounts,
            categories: categories,
            tags: tags,
            transactions: transactions,
            budgets: budgets,
            savingsGoals: savingsGoals,
            recurringRules: recurringRules,
            recurringOccurrences: recurringOccurrences,
            physicalAssets: physicalAssets,
            assetEvents: assetEvents,
            assetUsageEvents: assetUsageEvents,
            assetTransactionLinks: assetTransactionLinks,
            assetRefundAllocations: assetRefundAllocations,
            assetValuations: assetValuations,
            receivableAssets: receivableAssets,
            receivableRecoveries: receivableRecoveries,
            liabilities: liabilities,
            netWorthSnapshots: netWorthSnapshots,
            aiChatSessions: aiChatSessions,
            aiChatMessages: aiChatMessages,
            aiMemories: aiMemories,
            aiRequestRuns: aiRequestRuns + reportJobRuns,
            aiRequestEvents: aiRequestEvents,
            aiReportSchedules: aiReportSchedules,
            budgetPlansV2: budgetPlansV2,
            budgetPlanRevisionsV2: budgetPlanRevisionsV2,
            budgetCycleOverridesV2: budgetCycleOverridesV2,
            budgetCommitmentOccurrencesV2: budgetCommitmentOccurrencesV2,
            budgetChangeEventsV2: budgetChangeEventsV2,
            reports: reports,
            accountBalanceCheckpoints: accountBalanceCheckpoints,
            netWorthVerifiedCheckpoints: netWorthVerifiedCheckpoints,
            netWorthVerifiedItems: netWorthVerifiedItems
        )
    }

    private static func normalizedAIMode(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch value {
        case "scheduledReport", "scheduled-report": return "scheduled_report"
        case "localModel", "local-model": return "local_model"
        case "run", "record": return "record"
        case "chat", "query", "report", "import", "local_model", "scheduled_report": return value
        default: return "chat"
        }
    }

    private static func normalizedAIStatus(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch value {
        case "awaitingConfirmation", "awaiting-confirmation": return "awaiting_confirmation"
        case "rolledBack", "rolled-back": return "rolled_back"
        case "tool_call", "toolCall": return "preparing"
        case "queued", "preparing", "thinking", "streaming", "awaiting_confirmation", "background", "completed", "rolled_back", "failed", "cancelled":
            return value
        default: return "queued"
        }
    }

    private static func isTerminalAIStatus(_ status: String) -> Bool {
        ["completed", "rolled_back", "failed", "cancelled"].contains(status)
    }

    private static func normalizedAIEventType(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch value {
        case "runStarted", "run_started": return "started"
        case "stageChanged", "stage_changed": return "stage_changed"
        case "contextReady", "context_ready": return "context_ready"
        case "attachmentReady", "attachment_ready": return "attachment_ready"
        case "proposalReady", "proposal_ready": return "proposal_ready"
        case "rolledBack", "rolled_back": return "rolled_back"
        case "retry", "source", "reasoning", "committed", "completed", "failed", "cancelled": return value
        case "toolRequested", "toolResult", "confirmationRequired", "delta": return "stage_changed"
        default: return "stage_changed"
        }
    }

    private static func eventObject(from raw: String) -> [String: Any]? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func eventSummary(from raw: String) -> String {
        guard let object = eventObject(from: raw) else { return "" }
        for key in ["summary", "stage", "message"] {
            if let value = object[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value.count > 160 ? String(value.prefix(160)) + "…" : value
            }
        }
        return ""
    }

    private static func eventCount(from raw: String) -> Int {
        guard let object = eventObject(from: raw) else { return 0 }
        for key in ["count", "items"] {
            if let value = object[key] as? NSNumber { return max(value.intValue, 0) }
        }
        return 0
    }

    private static func date(_ milliseconds: Int64?) -> Date? {
        guard let milliseconds, milliseconds != 0 else { return nil }
        return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    private static func civilDay(_ key: Int64?) -> Date? {
        guard let key, key > 0 else { return nil }
        let value = Int(key)
        let year = value / 10_000
        let month = (value / 100) % 100
        let day = value % 100
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
        guard let date,
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else { return nil }
        return date
    }

    private static func parseDate(_ value: String) -> Date? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        let plain = DateFormatter()
        plain.locale = Locale(identifier: "en_US_POSIX")
        plain.dateFormat = "yyyy-MM-dd"
        return plain.date(from: text)
    }

    private static func stableID(_ raw: String, table: String, id: Int64?) -> UUID {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let uuid = UUID(uuidString: normalizeUUID(trimmed)) { return uuid }
        let seed = "\(table):\(trimmed.isEmpty ? String(id ?? 0) : trimmed)"
        let digest = Array(SHA256.hash(data: Data(seed.utf8)))
        var value: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &value) { bytes in
            for index in 0..<16 { bytes[index] = digest[index] }
        }
        return UUID(uuid: value)
    }

    private static func normalizeUUID(_ raw: String) -> String {
        let compact = raw.replacingOccurrences(of: "-", with: "")
        guard compact.count == 32 else { return raw }
        let characters = Array(compact)
        return [
            String(characters[0..<8]),
            String(characters[8..<12]),
            String(characters[12..<16]),
            String(characters[16..<20]),
            String(characters[20..<32])
        ].joined(separator: "-")
    }

    private static func storedPath(_ raw: String) -> String {
        let normalizedSeparators = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        let value = pathSuffix(normalizedSeparators, directory: "receipts/")
            ?? pathSuffix(normalizedSeparators, directory: "asset_media/")
            ?? normalizedSeparators
        return AttachmentStore.isSafeRelativePath(value) ? value : ""
    }

    private static func storedMediaPath(_ raw: String) -> String {
        let normalizedSeparators = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        let normalized: String
        if let suffix = pathSuffix(normalizedSeparators, directory: "asset_media/") {
            normalized = "asset_media/\(suffix)"
        } else if let suffix = pathSuffix(normalizedSeparators, directory: "receipts/") {
            normalized = suffix
        } else {
            normalized = normalizedSeparators
        }
        return AttachmentStore.isSafeRelativePath(normalized) ? normalized : ""
    }

    private static func pathSuffix(_ path: String, directory: String) -> String? {
        guard let range = path.range(of: directory, options: .backwards) else { return nil }
        let suffix = String(path[range.upperBound...])
        return suffix.isEmpty ? nil : suffix
    }

    private static func categoryBudgets(_ raw: String) -> [(String, Decimal)] {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else { return [] }
        return dictionary.compactMap { key, value in
            let amount: Decimal?
            if let text = value as? String {
                amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
            } else if let number = value as? NSNumber {
                amount = NSDecimalNumber(decimal: Decimal(number.doubleValue)).decimalValue
            } else {
                amount = nil
            }
            guard let amount else { return nil }
            return (key, amount)
        }.sorted { $0.0 < $1.0 }
    }

    private static func physicalLifecycle(_ row: SQLiteRow) -> String {
        if row.string("visibility_status") == "archived" || row.string("status") == "archived" {
            return "archived"
        }
        switch row.string("economic_status", fallback: row.string("status", fallback: "active")) {
        case "owned", "active": return "owned"
        case "idle": return "idle"
        case "sold": return "sold"
        case "returned": return "returned"
        case "disposed", "scrapped": return "disposed"
        case "lost": return "lost"
        case "gifted": return "gifted"
        default: return "owned"
        }
    }

    private static func assetEventKind(_ raw: String) -> String {
        switch raw {
        case "asset_purchased": return "purchased"
        case "asset_edited", "evidence_updated": return "edited"
        case "value_updated": return "valuationUpdated"
        case "asset_sold", "asset_sale_undone": return raw == "asset_sold" ? "sold" : "restored"
        case "asset_returned", "asset_return_undone": return raw == "asset_returned" ? "returned" : "restored"
        case "asset_disposed": return "disposed"
        case "asset_lost": return "lost"
        case "asset_gifted": return "gifted"
        case "asset_archived", "asset_unarchived": return raw == "asset_archived" ? "archived" : "restored"
        case "asset_usage_tracking_enabled", "asset_usage_tracking_disabled": return "usageAdded"
        case "depreciation_configured", "auto_depreciation_applied": return "depreciation"
        default: return "created"
        }
    }

    private static func receivableKind(_ raw: String) -> String {
        switch raw {
        case "rental_deposit": return "rentalDeposit"
        case "loan_out": return "loanOut"
        case "account_receivable": return "accountReceivable"
        case "prepaid_card": return "prepaidCard"
        case "membership_card": return "membershipCard"
        case "security_deposit": return "securityDeposit"
        default: return "other"
        }
    }

    private static func receivableLifecycle(_ raw: String) -> String {
        switch raw {
        case "partial_recovered": return "partiallyRecovered"
        case "recovered": return "recovered"
        case "lost": return "lost"
        case "archived": return "archived"
        default: return "active"
        }
    }

    private static func liabilityKind(_ raw: String) -> String {
        switch raw {
        case "credit_card": return "creditCard"
        case "car_loan": return "carLoan"
        case "consumer_loan": return "consumerLoan"
        case "personal_borrow": return "personalBorrow"
        case "mortgage": return "mortgage"
        default: return "other"
        }
    }

    private static func liabilityLifecycle(_ raw: String) -> String {
        switch raw {
        case "paid_off": return "paidOff"
        case "paused": return "paused"
        case "archived": return "archived"
        default: return "active"
        }
    }
#endif
}
