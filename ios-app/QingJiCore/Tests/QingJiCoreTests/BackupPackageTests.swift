import XCTest
@testable import QingJiCore

final class BackupPackageTests: XCTestCase {
    func testRoundTripKeepsStableRelationships() throws {
        let bookID = UUID()
        let accountID = UUID()
        let transactionID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let package = FeimiaoBackupPackage(
            exportedAt: date,
            books: [BackupBook(id: bookID, name: "总账本", isDefault: true)],
            accounts: [BackupAccount(id: accountID, name: "微信", kind: .weChat, initialBalance: 12.34)],
            categories: [BackupCategory(key: "dining", name: "餐饮", symbol: "fork.knife", kind: .expense)],
            transactions: [BackupTransaction(
                id: transactionID,
                amount: -20,
                kind: .expense,
                date: date,
                note: "退款",
                merchant: "某商户",
                product: "订单商品",
                categoryKey: "dining",
                accountID: accountID,
                bookID: bookID,
                refundOfID: UUID(),
                isReimbursed: true,
                tags: ["工作", "待核对"],
                categoryName: "餐饮",
                timePrecision: .exact,
                settlementQuality: .userConfirmed,
                eventType: .refund,
                attachmentPath: "receipts/receipt-1.jpg",
                orderNo: "ORDER-1"
            )]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(FeimiaoBackupPackage.self, from: encoder.encode(package))

        XCTAssertEqual(restored, package)
        XCTAssertEqual(restored.transactions.first?.bookID, bookID)
        XCTAssertEqual(restored.transactions.first?.refundOfID != nil, true)
        XCTAssertEqual(restored.accounts.first?.initialBalance, 12.34)
        XCTAssertEqual(restored.transactions.first?.eventType, .refund)
        XCTAssertEqual(restored.transactions.first?.attachmentPath, "receipts/receipt-1.jpg")
        XCTAssertEqual(restored.transactions.first?.orderNo, "ORDER-1")
        XCTAssertEqual(restored.transactions.first?.merchant, "某商户")
        XCTAssertEqual(restored.transactions.first?.product, "订单商品")
    }

    func testOlderPackageDefaultsNewFlags() throws {
        let data = #"{"schemaVersion":1,"exportedAt":"2023-11-14T22:13:20Z","books":[],"accounts":[],"categories":[],"transactions":[],"budgets":[]}"#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let package = try decoder.decode(FeimiaoBackupPackage.self, from: data)
        XCTAssertEqual(package.schemaVersion, 1)
        XCTAssertTrue(package.transactions.isEmpty)
        XCTAssertTrue(package.savingsGoals.isEmpty)
        XCTAssertTrue(package.recurringRules.isEmpty)
        XCTAssertTrue(package.physicalAssets.isEmpty)
        XCTAssertTrue(package.liabilities.isEmpty)
        XCTAssertTrue(package.aiChatSessions.isEmpty)
        XCTAssertTrue(package.aiChatMessages.isEmpty)
    }

    func testV4RoundTripKeepsChatHistoryWithoutCredentials() throws {
        let sessionID = UUID()
        let messageID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let package = FeimiaoBackupPackage(
            schemaVersion: 4,
            exportedAt: date,
            aiChatSessions: [BackupAIChatSession(
                id: sessionID,
                title: "本月消费",
                createdAt: date,
                updatedAt: date,
                isRecord: false,
                model: "gpt-5-mini",
                effortRaw: "medium"
            )],
            aiChatMessages: [BackupAIChatMessage(
                id: messageID,
                sessionID: sessionID,
                role: "user",
                content: "本月花了多少",
                createdAt: date
            )]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(FeimiaoBackupPackage.self, from: encoder.encode(package))

        XCTAssertEqual(restored, package)
        XCTAssertEqual(restored.aiChatMessages.first?.sessionID, sessionID)
        let encoded = try encoder.encode(package)
        let encodedText = String(data: encoded, encoding: .utf8) ?? ""
        XCTAssertFalse(encodedText.contains("apiKey"))
        XCTAssertFalse(encodedText.contains("refreshToken"))
    }

    func testV3RoundTripKeepsExtendedDomains() throws {
        let goalID = UUID()
        let ruleID = UUID()
        let assetID = UUID()
        let liabilityID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let package = FeimiaoBackupPackage(
            schemaVersion: 3,
            exportedAt: date,
            savingsGoals: [BackupSavingsGoal(
                id: goalID,
                name: "旅行",
                targetAmount: 12_000,
                savedAmount: 3_000,
                note: "秋天出发"
            )],
            recurringRules: [BackupRecurringRule(
                id: ruleID,
                kind: .expense,
                amount: 3_200,
                categoryKey: "housing",
                periodRaw: "monthly",
                startDate: date,
                nextDueDate: date,
                anchorDay: 31
            )],
            physicalAssets: [BackupPhysicalAsset(
                id: assetID,
                name: "手机",
                kindRaw: "digital",
                purchasePrice: 6_999,
                currentValue: 5_800
            )],
            liabilities: [BackupLiabilityProfile(
                id: liabilityID,
                kindRaw: "creditCard",
                originalPrincipal: 3_000,
                currentPrincipal: 1_800
            )]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(FeimiaoBackupPackage.self, from: encoder.encode(package))

        XCTAssertEqual(restored, package)
        XCTAssertEqual(restored.savingsGoals.first?.id, goalID)
        XCTAssertEqual(restored.recurringRules.first?.anchorDay, 31)
        XCTAssertEqual(restored.physicalAssets.first?.currentValue, 5_800)
        XCTAssertEqual(restored.liabilities.first?.currentPrincipal, 1_800)
    }

    func testV8RoundTripKeepsAuthorizedAIMemory() throws {
        let memoryID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let package = FeimiaoBackupPackage(
            schemaVersion: FeimiaoBackupPackage.currentSchemaVersion,
            exportedAt: date,
            aiMemories: [BackupAIMemory(
                id: memoryID,
                phrase: "不吃辣",
                content: "点餐时优先清淡口味",
                consent: true,
                createdAt: date,
                updatedAt: date
            )]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(
            FeimiaoBackupPackage.self,
            from: encoder.encode(package)
        )

        XCTAssertEqual(restored, package)
        XCTAssertEqual(restored.aiMemories.first?.id, memoryID)
        XCTAssertTrue(restored.aiMemories.first?.consent == true)
    }

    func testV9RoundTripKeepsAIExecutionAuditAndSchedule() throws {
        let runID = UUID()
        let eventID = UUID()
        let scheduleID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let package = FeimiaoBackupPackage(
            schemaVersion: FeimiaoBackupPackage.currentSchemaVersion,
            exportedAt: date,
            aiRequestRuns: [BackupAIRequestRun(
                id: runID,
                modeRaw: "record",
                statusRaw: "completed",
                providerLabel: "本机测试",
                model: "test-model",
                resultSummary: "已写入 1 笔",
                createdAt: date,
                finishedAt: date,
                updatedAt: date
            )],
            aiRequestEvents: [BackupAIRequestEvent(
                id: eventID,
                runID: runID,
                sequence: 1,
                typeRaw: "committed",
                summary: "已写入账本",
                count: 1,
                createdAt: date
            )],
            aiReportSchedules: [BackupAIReportSchedule(
                id: scheduleID,
                title: "每月账本报告",
                nextRunAt: date,
                createdAt: date,
                updatedAt: date
            )]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(
            FeimiaoBackupPackage.self,
            from: encoder.encode(package)
        )

        XCTAssertEqual(restored, package)
        XCTAssertEqual(restored.aiRequestRuns.first?.id, runID)
        XCTAssertEqual(restored.aiRequestEvents.first?.runID, runID)
        XCTAssertEqual(restored.aiReportSchedules.first?.id, scheduleID)
    }

    func testTransactionRecordV1PayloadDefaultsNewMetadata() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let data = """
        {"id":"\(id.uuidString)","kind":"expense","amount":12.5,"date":"2023-11-14T22:13:20Z"}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let record = try decoder.decode(TransactionRecord.self, from: data)

        XCTAssertEqual(record.id, id)
        XCTAssertEqual(record.amount, 12.5)
        XCTAssertEqual(record.eventType, .expense)
        XCTAssertEqual(record.timePrecision, .legacyUnknown)
        XCTAssertEqual(record.date, date)
    }
}
