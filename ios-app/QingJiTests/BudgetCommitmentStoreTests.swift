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
        [book, account, category, plan, occurrence, transaction].forEach(context.insert)
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
            refundOfID: transaction.stableID,
            eventType: .refund
        )
        context.insert(refund)
        try context.save()
        XCTAssertEqual(try BudgetCommitmentStore.refreshRefundReviews(in: context), 1)
        XCTAssertEqual(occurrence.resolutionStatusRaw, FixedCommitmentResolutionStatus.requiresReview.rawValue)
        try BudgetCommitmentStore.acceptRefundReview(occurrence, in: context)
        XCTAssertEqual(occurrence.resolutionStatusRaw, FixedCommitmentResolutionStatus.matched.rawValue)
        XCTAssertEqual(occurrence.reviewReasonRaw, "")
    }
}
