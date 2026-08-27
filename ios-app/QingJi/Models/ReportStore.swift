import Foundation
import SwiftData
import QingJiCore

enum ReportStore {
    @discardableResult
    static func createMonthly(
        in context: ModelContext,
        transactions: [MoneyTransaction],
        bookID: UUID?,
        month: Date
    ) throws -> ReportRecord {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month], from: month)
        guard let start = calendar.date(from: DateComponents(year: components.year, month: components.month, day: 1)),
              let nextStart = calendar.date(byAdding: .month, value: 1, to: start),
              let end = calendar.date(byAdding: .second, value: -1, to: nextStart) else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        let records = transactions
            .filter { $0.book?.stableID == bookID || bookID == nil }
            .map(\.record)
        let summary = StatisticsEngine.monthlySummary(
            of: records,
            year: components.year ?? calendar.component(.year, from: start),
            month: components.month ?? calendar.component(.month, from: start),
            calendar: calendar
        )
        let currency = transactions.first?.currencyCode ?? "CNY"
        let title = "\(components.year ?? 0)年\(components.month ?? 0)月账单报告"
        let summaryText = "支出 \(MoneyFormat.string(summary.totalExpense, currencyCode: currency)) · 收入 \(MoneyFormat.string(summary.totalIncome, currencyCode: currency))"
        var markdown = "# \(title)\n\n"
        markdown += "- 支出：\(MoneyFormat.string(summary.totalExpense, currencyCode: currency))\n"
        markdown += "- 收入：\(MoneyFormat.string(summary.totalIncome, currencyCode: currency))\n"
        markdown += "- 结余：\(MoneyFormat.string(summary.balance, currencyCode: currency))\n\n"
        if !summary.expenseByCategory.isEmpty {
            markdown += "## 支出分类\n\n"
            for item in summary.expenseByCategory {
                markdown += "- \(item.name)：\(MoneyFormat.string(item.total, currencyCode: currency))（\(item.count)笔）\n"
            }
        }
        let report = ReportRecord(
            bookID: bookID,
            type: "monthly",
            title: title,
            summary: summaryText,
            markdown: markdown,
            periodStart: start,
            periodEnd: end
        )
        context.insert(report)
        try context.save()
        return report
    }

    static func delete(_ report: ReportRecord, from context: ModelContext) throws {
        context.delete(report)
        try context.save()
    }

    static func togglePinned(_ report: ReportRecord, in context: ModelContext) throws {
        report.pinnedAt = report.pinnedAt == nil ? Date() : nil
        try context.save()
    }
}
