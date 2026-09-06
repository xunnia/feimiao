import Foundation
import XCTest
import SwiftData
import QingJiCore
@testable import QingJi

@MainActor
final class BudgetStoreV2Tests: XCTestCase {
    func testStatusV2UsesHistoricalRevisionAndCycleOverride() {
        let calendar = Calendar.current
        let bookID = UUID()
        let planID = UUID()
        let january = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let july = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        let august = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let september = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let cutoff = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31))!

        let plan = BudgetPlanV2(
            id: planID,
            bookID: bookID,
            cadence: .monthly,
            anchorStart: january,
            monthStartDay: 1,
            createdAt: .distantPast
        )
        let firstRevision = BudgetPlanRevisionV2(
            id: UUID(),
            planID: planID,
            effectiveCycleStart: january,
            amountCents: 3_100,
            createdAt: .distantPast
        )
        let augustRevision = BudgetPlanRevisionV2(
            id: UUID(),
            planID: planID,
            effectiveCycleStart: august,
            amountCents: 4_000,
            createdAt: .distantPast
        )
        let augustOverride = BudgetCycleOverrideV2(
            id: UUID(),
            planID: planID,
            cycleStart: august,
            cycleEndInclusive: calendar.date(byAdding: .day, value: 30, to: august)!,
            targetAmountCents: 6_200,
            createdAt: .distantPast
        )
        let records = [
            TransactionRecord(
                kind: .expense,
                amount: 10,
                bookID: bookID,
                date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 5))!
            )
        ]

        let historical = BudgetStore.statusV2(
            plans: [plan],
            revisions: [firstRevision, augustRevision],
            overrides: [],
            bookID: bookID,
            records: records,
            windowStart: july,
            windowEndExclusive: august,
            referenceDate: july,
            knowledgeCutoff: cutoff,
            calendar: calendar
        )
        XCTAssertEqual(historical?.monthlyBudget, Optional(Decimal(31)))
        XCTAssertEqual(historical?.spentThisMonth, Optional(Decimal.zero))

        let overridden = BudgetStore.statusV2(
            plans: [plan],
            revisions: [firstRevision, augustRevision],
            overrides: [augustOverride],
            bookID: bookID,
            records: records,
            windowStart: august,
            windowEndExclusive: september,
            referenceDate: calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!,
            knowledgeCutoff: cutoff,
            calendar: calendar
        )
        XCTAssertEqual(overridden?.monthlyBudget, Optional(Decimal(62)))
        XCTAssertEqual(overridden?.spentThisMonth, Optional(Decimal(10)))
        XCTAssertEqual(overridden?.remaining, Optional(Decimal(52)))
    }

    func testStatusV2ScopesSpendingToBookAndKnowledgeCutoff() {
        let calendar = Calendar.current
        let bookID = UUID()
        let otherBookID = UUID()
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let cutoff = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!
        let plan = BudgetPlanV2(
            id: UUID(),
            bookID: bookID,
            cadence: .monthly,
            anchorStart: start,
            monthStartDay: 1,
            createdAt: .distantPast
        )
        let revision = BudgetPlanRevisionV2(
            id: UUID(),
            planID: plan.id,
            effectiveCycleStart: start,
            amountCents: 10_000,
            createdAt: .distantPast
        )
        let records = [
            TransactionRecord(
                kind: .expense,
                amount: 10,
                bookID: bookID,
                date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 5))!,
                createdAt: calendar.date(from: DateComponents(year: 2026, month: 8, day: 5))!
            ),
            TransactionRecord(
                kind: .expense,
                amount: 90,
                bookID: otherBookID,
                date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 6))!,
                createdAt: calendar.date(from: DateComponents(year: 2026, month: 8, day: 6))!
            ),
            TransactionRecord(
                kind: .expense,
                amount: 50,
                bookID: bookID,
                date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 7))!,
                createdAt: calendar.date(from: DateComponents(year: 2026, month: 8, day: 21))!
            )
        ]

        let status = BudgetStore.statusV2(
            plans: [plan],
            revisions: [revision],
            overrides: [],
            bookID: bookID,
            records: records,
            windowStart: start,
            windowEndExclusive: calendar.date(byAdding: .month, value: 1, to: start)!,
            referenceDate: calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!,
            knowledgeCutoff: cutoff,
            calendar: calendar
        )

        XCTAssertEqual(status?.spentThisMonth, Optional(Decimal(10)))
    }

    func testStatusV2UsesAndroidRefundFamilyNetAndIncludedBookScope() {
        let calendar = Calendar.current
        let totalBookID = UUID()
        let childBookID = UUID()
        let totalRootID = UUID()
        let childRootID = UUID()
        let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 5))!
        let monthStart = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let monthEnd = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let plan = BudgetPlanV2(
            id: UUID(),
            bookID: totalBookID,
            cadence: .monthly,
            anchorStart: monthStart,
            monthStartDay: 1,
            createdAt: .distantPast
        )
        let revision = BudgetPlanRevisionV2(
            id: UUID(),
            planID: plan.id,
            effectiveCycleStart: monthStart,
            amountCents: 20_000,
            createdAt: .distantPast
        )
        let records = [
            TransactionRecord(
                id: totalRootID,
                kind: .expense,
                amount: 100,
                bookID: totalBookID,
                date: day,
                createdAt: day
            ),
            TransactionRecord(
                kind: .expense,
                amount: -40,
                bookID: totalBookID,
                date: day,
                createdAt: day,
                refundOfID: totalRootID,
                isExcluded: true
            ),
            TransactionRecord(
                id: childRootID,
                kind: .expense,
                amount: 80,
                bookID: childBookID,
                date: day,
                createdAt: day
            ),
            TransactionRecord(
                kind: .expense,
                amount: 10,
                bookID: childBookID,
                date: day,
                createdAt: day,
                refundOfID: childRootID
            ),
            TransactionRecord(
                kind: .expense,
                amount: 999,
                currencyCode: "USD",
                bookID: childBookID,
                date: day,
                createdAt: day
            )
        ]

        let status = BudgetStore.statusV2(
            plans: [plan],
            revisions: [revision],
            overrides: [],
            bookID: totalBookID,
            records: records,
            includedBookIDs: [totalBookID, childBookID],
            windowStart: monthStart,
            windowEndExclusive: monthEnd,
            referenceDate: day,
            knowledgeCutoff: day,
            calendar: calendar
        )

        // (100 - 40) + (80 - abs(10)) = 130.
        XCTAssertEqual(status?.spentThisMonth, Optional(Decimal(130)))
    }

    func testStatusV2SkipsAmbiguousDuplicateRootIDsWithoutCrashing() {
        let calendar = Calendar.current
        let bookID = UUID()
        let duplicateRootID = UUID()
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 5))!
        let plan = BudgetPlanV2(
            id: UUID(),
            bookID: bookID,
            cadence: .monthly,
            anchorStart: start,
            monthStartDay: 1,
            createdAt: .distantPast
        )
        let revision = BudgetPlanRevisionV2(
            id: UUID(),
            planID: plan.id,
            effectiveCycleStart: start,
            amountCents: 20_000,
            createdAt: .distantPast
        )
        let records = [
            TransactionRecord(
                id: duplicateRootID,
                kind: .expense,
                amount: 100,
                bookID: bookID,
                date: day,
                createdAt: day
            ),
            TransactionRecord(
                id: duplicateRootID,
                kind: .expense,
                amount: 80,
                bookID: bookID,
                date: day,
                createdAt: day
            ),
            TransactionRecord(
                kind: .expense,
                amount: -30,
                bookID: bookID,
                date: day,
                createdAt: day,
                refundOfID: duplicateRootID
            ),
        ]

        let status = BudgetStore.statusV2(
            plans: [plan],
            revisions: [revision],
            overrides: [],
            bookID: bookID,
            records: records,
            windowStart: start,
            windowEndExclusive: end,
            referenceDate: day,
            knowledgeCutoff: day,
            calendar: calendar
        )

        XCTAssertEqual(status?.spentThisMonth, Optional(Decimal.zero))
    }

    func testSpecialTrackingFoldsRefundsAtKnowledgeCutoffAndMatchesTagNames() {
        let calendar = Calendar.current
        let bookID = UUID()
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 8, day: 31))!
        let originalID = UUID()
        let firstRefundID = UUID()
        let lateRefundID = UUID()
        let positiveRefundOriginalID = UUID()
        let positiveRefundID = UUID()
        let nonExpenseRefundID = UUID()
        let otherBookID = UUID()
        let crossBookRefundID = UUID()
        let originalDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 5))!
        let firstRefundDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 6))!
        let lateRefundDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 7))!
        let firstCutoff = calendar.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 23))!
        let finalCutoff = calendar.date(from: DateComponents(year: 2026, month: 8, day: 8))!
        let plan = BudgetPlanV2(
            id: UUID(),
            bookID: bookID,
            role: "special",
            cadence: .oneOff,
            anchorStart: start,
            endInclusive: end,
            expenseScope: BudgetExpenseScopeV2(tagNames: ["旅行"]),
            createdAt: .distantPast
        )
        let revision = BudgetPlanRevisionV2(
            id: UUID(),
            planID: plan.id,
            effectiveCycleStart: start,
            amountCents: 10_000,
            createdAt: .distantPast
        )
        let records = [
            TransactionRecord(
                id: originalID,
                kind: .expense,
                amount: 100,
                topCategoryKey: "travel",
                bookID: bookID,
                merchant: "旅行平台",
                date: originalDate,
                createdAt: originalDate,
                tags: ["旅行"]
            ),
            TransactionRecord(
                id: firstRefundID,
                kind: .expense,
                amount: -25,
                bookID: bookID,
                date: firstRefundDate,
                createdAt: firstRefundDate,
                refundOfID: originalID
            ),
            TransactionRecord(
                id: lateRefundID,
                kind: .expense,
                amount: -75,
                bookID: bookID,
                date: lateRefundDate,
                createdAt: finalCutoff.addingTimeInterval(-60),
                refundOfID: originalID,
                isExcluded: true
            ),
            TransactionRecord(
                id: positiveRefundOriginalID,
                kind: .expense,
                amount: 40,
                bookID: bookID,
                date: originalDate,
                createdAt: originalDate,
                tags: ["旅行"]
            ),
            // Android normalizes legacy positive refund rows to a refund
            // magnitude, so this reduces the second family by 10 rather than
            // increasing spending.
            TransactionRecord(
                id: positiveRefundID,
                kind: .expense,
                amount: 10,
                bookID: bookID,
                date: firstRefundDate,
                createdAt: firstRefundDate,
                refundOfID: positiveRefundOriginalID
            ),
            // A non-expense row carrying refund_of must not affect an expense
            // family, even if an old export contains one.
            TransactionRecord(
                id: nonExpenseRefundID,
                kind: .income,
                amount: -100,
                bookID: bookID,
                date: firstRefundDate,
                createdAt: firstRefundDate,
                refundOfID: positiveRefundOriginalID
            ),
            // A refund in another book must not be attached to this book's
            // family just because its legacy refund_of points at the root.
            TransactionRecord(
                id: crossBookRefundID,
                kind: .expense,
                amount: -10,
                bookID: otherBookID,
                date: firstRefundDate,
                createdAt: firstRefundDate,
                refundOfID: originalID
            ),
            TransactionRecord(
                kind: .expense,
                amount: 20,
                currencyCode: "USD",
                bookID: bookID,
                date: originalDate,
                createdAt: originalDate,
                tags: ["旅行"]
            )
        ]

        let partial = BudgetStore.specialTrackings(
            plans: [plan],
            revisions: [revision],
            records: records,
            bookID: bookID,
            asOf: finalCutoff,
            knowledgeCutoff: firstCutoff,
            windowStartInclusive: start,
            windowEndExclusive: end.addingTimeInterval(86_400),
            calendar: calendar
        ).first
        XCTAssertEqual(partial?.spentCents, 10_500)
        XCTAssertEqual(partial?.matchedFamilyCount, 2)
        XCTAssertEqual(partial?.excludedForeignFamilyCount, 1)

        let fullyRefunded = BudgetStore.specialTrackings(
            plans: [plan],
            revisions: [revision],
            records: records,
            bookID: bookID,
            asOf: finalCutoff,
            knowledgeCutoff: finalCutoff,
            windowStartInclusive: start,
            windowEndExclusive: end.addingTimeInterval(86_400),
            calendar: calendar
        ).first
        XCTAssertEqual(fullyRefunded?.spentCents, 3_000)
        XCTAssertEqual(fullyRefunded?.matchedFamilyCount, 2)
    }

    func testSpecialTrackingAggregatesIncludedBooksIntoTheLogicalTotalBook() {
        let calendar = Calendar.current
        let totalBookID = UUID()
        let childBookID = UUID()
        let childOrderID = UUID()
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 8, day: 31))!
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!
        let plan = BudgetPlanV2(
            id: UUID(),
            bookID: totalBookID,
            role: "special",
            cadence: .oneOff,
            anchorStart: start,
            endInclusive: end,
            expenseScope: BudgetExpenseScopeV2(categoryKeys: ["travel"]),
            createdAt: .distantPast
        )
        let revision = BudgetPlanRevisionV2(
            id: UUID(),
            planID: plan.id,
            effectiveCycleStart: start,
            amountCents: 30_000,
            createdAt: .distantPast
        )
        let result = BudgetStore.specialTrackings(
            plans: [plan],
            revisions: [revision],
            records: [
                TransactionRecord(
                    id: childOrderID,
                    kind: .expense,
                    amount: 12,
                    bookID: childBookID,
                    date: date,
                    createdAt: date,
                    topCategoryKey: "travel"
                ),
                TransactionRecord(
                    kind: .expense,
                    amount: -2,
                    bookID: totalBookID,
                    date: date,
                    createdAt: date,
                    refundOfID: childOrderID
                ),
                TransactionRecord(
                    kind: .expense,
                    amount: 8,
                    bookID: totalBookID,
                    date: date,
                    createdAt: date,
                    topCategoryKey: "travel"
                )
            ],
            bookID: totalBookID,
            includedBookIDs: [totalBookID, childBookID],
            asOf: date,
            knowledgeCutoff: date,
            windowStartInclusive: start,
            windowEndExclusive: end.addingTimeInterval(86_400),
            calendar: calendar
        ).first

        XCTAssertEqual(result?.spentCents, 1_800)
        XCTAssertEqual(result?.matchedFamilyCount, 2)
    }

    func testSpecialTrackingEditCreatesSuccessorAndPreservesAuditHistory() throws {
        let schema = Schema([
            Account.self,
            Book.self,
            TxCategory.self,
            MoneyTransaction.self,
            BudgetPlanRecord.self,
            BudgetPlanRevisionRecord.self,
            BudgetChangeEventRecord.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let book = Book(name: "旅行账本")
        context.insert(book)
        try context.save()

        let start = Date(timeIntervalSince1970: 1_754_035_200)
        let original = try BudgetStore.saveSpecialTracking(
            bookID: book.stableID,
            name: "暑假旅行",
            startInclusive: start,
            endInclusive: start.addingTimeInterval(86_400 * 6),
            totalCents: 50_000,
            expenseScope: BudgetExpenseScopeV2(categoryKeys: ["travel"]),
            categoryBudgetsCents: ["travel": 20_000],
            in: context,
            now: start
        )
        let successor = try BudgetStore.saveSpecialTracking(
            planID: original.stableID,
            bookID: book.stableID,
            name: "国庆旅行",
            startInclusive: start.addingTimeInterval(86_400 * 10),
            endInclusive: start.addingTimeInterval(86_400 * 16),
            totalCents: 80_000,
            expenseScope: BudgetExpenseScopeV2(tagNames: ["旅行"]),
            in: context,
            now: start
        )

        let plans = try context.fetch(FetchDescriptor<BudgetPlanRecord>())
        XCTAssertEqual(plans.count, 2)
        XCTAssertEqual(plans.first(where: { $0.stableID == original.stableID })?.statusRaw, "archived")
        XCTAssertEqual(successor.statusRaw, "active")
        XCTAssertNotEqual(successor.stableID, original.stableID)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<BudgetPlanRevisionRecord>()).count,
            2
        )
        let successorRevision = try XCTUnwrap(
            try context.fetch(FetchDescriptor<BudgetPlanRevisionRecord>())
                .first(where: { $0.planID == successor.stableID })
        )
        XCTAssertEqual(
            BudgetPlanRevisionRecord.decodeCents(successorRevision.categoryBudgetsJSON),
            ["travel": 20_000]
        )

        let events = try context.fetch(FetchDescriptor<BudgetChangeEventRecord>())
        let superseded = events.first { $0.eventType == "special_superseded" }
        let supersededBefore = try XCTUnwrap(
            superseded.flatMap { event in
                try? JSONSerialization.jsonObject(with: Data(event.beforeJSON.utf8)) as? [String: Any]
            }
        )
        XCTAssertNotNil(supersededBefore["plan"] as? [String: Any])
        XCTAssertNotNil(supersededBefore["revision"] as? [String: Any])
        let created = events.filter { $0.eventType == "special_created" }
        XCTAssertEqual(created.count, 2)
        let originalCreated = try XCTUnwrap(created.first(where: { $0.planID == original.stableID }))
        let originalAfter = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(originalCreated.afterJSON.utf8)) as? [String: Any]
        )
        XCTAssertEqual((originalAfter["start_day"] as? NSNumber)?.intValue, civilDayKey(start))
        XCTAssertEqual(
            (originalAfter["end_day"] as? NSNumber)?.intValue,
            civilDayKey(start.addingTimeInterval(86_400 * 6))
        )
        XCTAssertTrue(superseded?.beforeJSON.contains(original.stableID.uuidString) == true)
        XCTAssertTrue(superseded?.afterJSON.contains(successor.stableID.uuidString) == true)
        XCTAssertTrue(created.contains { $0.planID == successor.stableID && $0.beforeJSON.contains(original.stableID.uuidString) })
        XCTAssertTrue(created.contains { $0.planID == successor.stableID && $0.afterJSON.contains("80000") })
    }

    func testArchiveSpecialTrackingWritesPlanArchiveEvent() throws {
        let schema = Schema([
            Account.self,
            Book.self,
            TxCategory.self,
            MoneyTransaction.self,
            BudgetPlanRecord.self,
            BudgetPlanRevisionRecord.self,
            BudgetChangeEventRecord.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let book = Book(name: "日常账本")
        context.insert(book)
        try context.save()

        let plan = try BudgetStore.saveSpecialTracking(
            bookID: book.stableID,
            name: "装修",
            startInclusive: Date(timeIntervalSince1970: 1_754_035_200),
            endInclusive: Date(timeIntervalSince1970: 1_754_121_600),
            totalCents: 100_000,
            expenseScope: BudgetExpenseScopeV2(categoryKeys: ["housing"]),
            in: context
        )
        try BudgetStore.archiveSpecialTracking(planID: plan.stableID, in: context)

        XCTAssertEqual(plan.statusRaw, BudgetPlanStatusV2.archived.rawValue)
        let events = try context.fetch(FetchDescriptor<BudgetChangeEventRecord>())
        let archiveEvent = try XCTUnwrap(events.first { $0.eventType == "plan_archived" })
        let after = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(archiveEvent.afterJSON.utf8)) as? [String: Any]
        )
        XCTAssertEqual((after["end_day"] as? NSNumber)?.intValue, civilDayKey(plan.endInclusive!))
    }

    private func civilDayKey(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (components.year ?? 0) * 10_000
            + (components.month ?? 0) * 100
            + (components.day ?? 0)
    }
}
