import Foundation
import SwiftData

@Model
final class ReportRecord {
    var stableID: UUID = UUID()
    var bookID: UUID? = nil
    var type: String = "monthly"
    var title: String = ""
    var summary: String = ""
    var markdown: String = ""
    var periodStart: Date = Date()
    var periodEnd: Date = Date()
    var createdAt: Date = Date()
    var pinnedAt: Date? = nil

    init(
        stableID: UUID = UUID(),
        bookID: UUID? = nil,
        type: String = "monthly",
        title: String,
        summary: String = "",
        markdown: String = "",
        periodStart: Date,
        periodEnd: Date,
        createdAt: Date = Date(),
        pinnedAt: Date? = nil
    ) {
        self.stableID = stableID
        self.bookID = bookID
        self.type = type
        self.title = title
        self.summary = summary
        self.markdown = markdown
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.createdAt = createdAt
        self.pinnedAt = pinnedAt
    }

    var isPinned: Bool { pinnedAt != nil }
}
