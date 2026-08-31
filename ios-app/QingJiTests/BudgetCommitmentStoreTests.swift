import XCTest
import SwiftData
import QingJiCore
@testable import QingJi

@MainActor
final class BudgetCommitmentStoreTests: XCTestCase {
    func testMaterializesCurrentAndNextCycleIdempotently() throws {
        let schema = Schema([
            BudgetPlanRecord.self,
            BudgetPlanRevisionRecord.self,
            BudgetCommitmentOccurrenceRecord.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let calendar = Calendar(identifier: .gregorian)
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let plan = BudgetPlanRecord(bookID: UUID(), cadenceRaw: "monthly", anchorStart: anchor)
        let template = BudgetFixedTemplateV2(
            id: "rent",
            name: "房租",
            plannedCents: 320_000,
            dueValue: 1
        )
        let revision = BudgetPlanRevisionRecord(
            planID: plan.stableID,
            effectiveCycleStart: anchor,
            amountCents: 500_000
        )
        revision.fixedTemplatesJSON = String(
            decoding: try JSONEncoder().encode([template]),
            as: UTF8.self
        )
        context.insert(plan)
        context.insert(revision)
        try context.save()

        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 28))!
        XCTAssertEqual(
            try BudgetCommitmentStore.materializeCurrent(in: context, now: now),
            2
        )
        XCTAssertEqual(
            try BudgetCommitmentStore.materializeCurrent(in: context, now: now),
            0
        )
        let occurrences = try context.fetch(FetchDescriptor<BudgetCommitmentOccurrenceRecord>())
        XCTAssertEqual(occurrences.count, 2)
        XCTAssertTrue(occurrences.allSatisfy { $0.templateID == "rent" && $0.plannedCents == 320_000 })
    }

    func testMatchAndRefundReviewKeepTheOccurrenceAuditable() throws {
        let schema = Schema([
            Account.self,
            Book.self,
            TxCategory.self,
            MoneyTransaction.self,
            BudgetPlanRecord.self,
            BudgetPlanRevisionRecord.self,
            BudgetCommitmentOccurrenceRecord.self,
            BudgetChangeEventRecord.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let book = Book(name: "测试账本", isDefault: true)
        let account = Account(name: "银行卡", kind: .bankCard)
        let category = TxCategory(key: "dining", name: "餐饮", symbol: "fork.knife", kind: .expense)
        let plan = BudgetPlanRecord(bookID: book.stableID, anchorStart: Date(timeIntervalSince1970: 1_700_000_000))
        let cycleStart = Date(timeIntervalSince1970: 1_700_000_000)
        let cycleEnd = Date(timeIntervalSince1970: 1_700_086_400)
        let occurrence = BudgetCommitmentOccurrenceRecord(
            planID: plan.stableID,
            revisionID: UUID(),
            templateID: "meal",
            cycleStart: cycleStart,
            cycleEndInclusive: cycleEnd,
            dueDate: cycleStart,
            plannedCents: 10_000
        )
        let transaction = MoneyTransaction(
            amount: 100,
            kind: .expense,
            date: cycleStart,
            note: "午餐",
            category: category,
            account: account,
            book: book
        )
        context.insert(book)
        context.insert(account)
        context.insert(category)
        context.insert(plan)
        context.insert(occurrence)
        context.insert(transaction)
        try context.save()

        XCTAssertEqual(try BudgetCommitmentStore.matchCandidates(for: occurrence, in: context).count, 1)
        try BudgetCommitmentStore.match(occurrence, to: transaction, in: context)
        XCTAssertEqual(occurrence.resolutionStatusRaw, FixedCommitmentResolutionStatus.matched.rawValue)

        let refund = MoneyTransaction(
            amount: -20,
            kind: .expense,
            date: cycleStart,
            note: "退款",
            category: category,
            account: account,
            book: book,
            eventType: .refund,
            refundOfID: transaction.stableID
        )
        context.insert(refund)
        try context.save()
        XCTAssertEqual(try BudgetCommitmentStore.refreshRefundReviews(in: context), 1)
        XCTAssertEqual(occurrence.resolutionStatusRaw, FixedCommitmentResolutionStatus.requiresReview.rawValue)
        try BudgetCommitmentStore.acceptRefundReview(occurrence, in: context)
        XCTAssertEqual(occurrence.resolutionStatusRaw, FixedCommitmentResolutionStatus.matched.rawValue)
        XCTAssertEqual(occurrence.reviewReasonRaw, "")
    }

    func testRevisionEditClosesHistoryAndReconcilesCommitments() throws {
        let schema = Schema([
            BudgetPlanRecord.self,
            BudgetPlanRevisionRecord.self,
            BudgetCommitmentOccurrenceRecord.self,
            BudgetChangeEventRecord.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let calendar = Calendar.current
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let target = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let plan = BudgetPlanRecord(bookID: UUID(), anchorStart: anchor)
        let firstTemplate = BudgetFixedTemplateV2(
            id: "rent",
            name: "房租",
            plannedCents: 100_000,
            dueValue: 1
        )
        let firstRevision = BudgetPlanRevisionRecord(
            planID: plan.stableID,
            effectiveCycleStart: anchor,
            amountCents: 500_000
        )
        firstRevision.fixedTemplatesJSON = String(
            decoding: try JSONEncoder().encode([firstTemplate]),
            as: UTF8.self
        )
        let cycle = plan.core.cycle(for: target)
        let occurrence = BudgetCommitmentOccurrenceRecord(
            planID: plan.stableID,
            revisionID: firstRevision.stableID,
            templateID: "rent",
            cycleStart: cycle.start,
            cycleEndInclusive: cycle.endInclusive,
            dueDate: cycle.start,
            plannedCents: firstTemplate.plannedCents
        )
        occurrence.resolutionStatusRaw = FixedCommitmentResolutionStatus.matched.rawValue
        occurrence.matchedTransactionFamilyID = "matched-family"

        context.insert(plan)
        context.insert(firstRevision)
        context.insert(occurrence)
        try context.save()

        let secondTemplate = BudgetFixedTemplateV2(
            id: "rent",
            name: "房租",
            plannedCents: 120_000,
            dueValue: 2
        )
        let addedTemplate = BudgetFixedTemplateV2(
            id: "internet",
            name: "网络",
            plannedCents: 20_000,
            dueValue: 5
        )
        let now = calendar.date(from: DateComponents(year: 2026, month: 2, day: 20))!
        let secondRevision = try BudgetCommitmentStore.upsertRevision(
            planID: plan.stableID,
            amountCents: 600_000,
            categoryBudgetsCents: ["housing": 200_000],
            fixedTemplates: [secondTemplate, addedTemplate],
            effectiveCycleStart: target,
            in: context,
            now: now
        )

        let revisions = try context.fetch(FetchDescriptor<BudgetPlanRevisionRecord>())
            .sorted { $0.effectiveCycleStart < $1.effectiveCycleStart }
        XCTAssertEqual(revisions.count, 2)
        XCTAssertEqual(revisions[0].effectiveToCycleStart, Optional(cycle.start))
        XCTAssertEqual(revisions[1].stableID, secondRevision.stableID)
        XCTAssertNil(revisions[1].effectiveToCycleStart)
        XCTAssertEqual(revisions[1].amountCents, 600_000)
        XCTAssertEqual(BudgetPlanRevisionRecord.decodeCents(revisions[1].categoryBudgetsJSON)["housing"], 200_000)

        let reconciled = try context.fetch(FetchDescriptor<BudgetCommitmentOccurrenceRecord>())
            .first { $0.templateID == "rent" }
        XCTAssertEqual(reconciled?.revisionID, Optional(secondRevision.stableID))
        XCTAssertEqual(reconciled?.plannedCents, Optional(120_000))
        XCTAssertEqual(reconciled?.dueDate, calendar.date(byAdding: .day, value: 1, to: cycle.start))
        XCTAssertEqual(reconciled?.resolutionStatusRaw, Optional(FixedCommitmentResolutionStatus.requiresReview.rawValue))
        XCTAssertEqual(reconciled?.reviewReasonRaw, Optional(FixedCommitmentReviewReason.amountConflict.rawValue))
        XCTAssertNil(reconciled?.matchedTransactionFamilyID)

        let added = try context.fetch(FetchDescriptor<BudgetCommitmentOccurrenceRecord>())
            .first { $0.templateID == "internet" }
        XCTAssertEqual(added?.revisionID, Optional(secondRevision.stableID))
        XCTAssertEqual(added?.plannedCents, Optional(20_000))

        let events = try context.fetch(FetchDescriptor<BudgetChangeEventRecord>())
            .filter { $0.eventType == "revision_created" }
        XCTAssertEqual(events.count, 1)
        XCTAssertFalse(events[0].afterJSON.isEmpty)
        XCTAssertTrue(events[0].afterJSON.contains("600000"))
    }

    func testRevisionEditAtSameCycleIsAnUpdateAndOverrideStaysScoped() throws {
        let schema = Schema([
            BudgetPlanRecord.self,
            BudgetPlanRevisionRecord.self,
            BudgetCycleOverrideRecord.self,
            BudgetChangeEventRecord.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let calendar = Calendar.current
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let plan = BudgetPlanRecord(bookID: UUID(), anchorStart: anchor)
        let revision = BudgetPlanRevisionRecord(
            planID: plan.stableID,
            effectiveCycleStart: anchor,
            amountCents: 500_000
        )
        revision.categoryBudgetsJSON = "{\"food\":100000}"
        context.insert(plan)
        context.insert(revision)
        try context.save()

        let target = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let created = try BudgetCommitmentStore.upsertRevision(
            planID: plan.stableID,
            amountCents: 550_000,
            effectiveCycleStart: target,
            in: context,
            now: anchor
        )
        let updated = try BudgetCommitmentStore.upsertRevision(
            planID: plan.stableID,
            amountCents: 575_000,
            effectiveCycleStart: target,
            in: context,
            now: calendar.date(byAdding: .day, value: 1, to: anchor)!
        )
        let revisions = try context.fetch(FetchDescriptor<BudgetPlanRevisionRecord>())
        XCTAssertEqual(revisions.count, 2)
        XCTAssertEqual(created.stableID, updated.stableID)
        XCTAssertEqual(updated.amountCents, 575_000)

        let cycle = plan.core.cycle(for: target)
        let override = try BudgetCommitmentStore.upsertCycleOverride(
            planID: plan.stableID,
            cycleStart: cycle.start,
            targetAmountCents: 300_000,
            categoryBudgetsCents: ["food": 80_000],
            in: context,
            now: anchor
        )
        let sameOverride = try BudgetCommitmentStore.upsertCycleOverride(
            planID: plan.stableID,
            cycleStart: cycle.start,
            targetAmountCents: 320_000,
            in: context,
            now: calendar.date(byAdding: .day, value: 2, to: anchor)!
        )
        XCTAssertEqual(override.stableID, sameOverride.stableID)
        XCTAssertEqual(sameOverride.targetAmountCents, 320_000)
        XCTAssertNil(sameOverride.categoryBudgetsJSON)
        XCTAssertEqual(revision.amountCents, 500_000)

        let events = try context.fetch(FetchDescriptor<BudgetChangeEventRecord>())
        XCTAssertEqual(events.filter { $0.eventType == "revision_created" }.count, 1)
        XCTAssertEqual(events.filter { $0.eventType == "revision_updated" }.count, 1)
        XCTAssertEqual(events.filter { $0.eventType == "cycle_override_saved" }.count, 2)
    }
}
