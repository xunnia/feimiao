import Foundation
import SwiftData
import SwiftUI

struct ReportsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \ReportRecord.createdAt, order: .reverse)
    private var reports: [ReportRecord]
    @Query(sort: \MoneyTransaction.date, order: .reverse)
    private var transactions: [MoneyTransaction]
    @State private var message: String?

    var body: some View {
        Group {
                if reports.isEmpty {
                    ContentUnavailableView(
                        "还没有报告",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("点击右上角生成本月报告")
                    )
                } else {
                    List {
                        ForEach(reports, id: \.stableID) { report in
                            NavigationLink {
                                ReportReaderView(report: report)
                            } label: {
                                ReportRow(report: report)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    try? ReportStore.togglePinned(report, in: context)
                                } label: {
                                    Label(report.isPinned ? "取消置顶" : "置顶", systemImage: report.isPinned ? "pin.slash" : "pin")
                                }
                                .tint(.orange)
                                Button(role: .destructive) {
                                    try? ReportStore.delete(report, from: context)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .liquidGlassCanvas()
                }
            }
            .navigationTitle("报告")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        do {
                            _ = try ReportStore.createMonthly(
                                in: context,
                                transactions: transactions,
                                bookID: router.selectedBookID,
                                month: AppClock.now
                            )
                            message = "本月报告已生成"
                        } catch {
                            message = error.localizedDescription
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .liquidGlassCircleControl()
                    .accessibilityLabel("生成本月报告")
                }
            }
            .alert("报告", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("好") { message = nil }
            } message: {
                Text(message ?? "")
            }
    }
}

private struct ReportRow: View {
    let report: ReportRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: report.isPinned ? "pin.fill" : "doc.text")
                .foregroundStyle(report.isPinned ? .orange : .accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(report.title)
                    .font(.body.weight(.medium))
                Text(report.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(report.createdAt, format: .dateTime.month().day())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct ReportReaderView: View {
    let report: ReportRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(report.title)
                    .font(.title2.weight(.semibold))
                Text("\(report.periodStart, format: .dateTime.year().month().day()) - \(report.periodEnd, format: .dateTime.year().month().day())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Divider()
                if let content = try? AttributedString(markdown: report.markdown) {
                    Text(content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(report.markdown)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationTitle("报告正文")
        .navigationBarTitleDisplayMode(.inline)
    }
}
