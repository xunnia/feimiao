import Foundation

public struct BackupReport: Codable, Equatable, Sendable {
    public var id: UUID
    public var bookID: UUID?
    public var type: String
    public var title: String
    public var summary: String
    public var markdown: String
    public var periodStart: Date
    public var periodEnd: Date
    public var createdAt: Date
    public var pinnedAt: Date?

    public init(id: UUID, bookID: UUID? = nil, type: String = "monthly", title: String, summary: String = "", markdown: String = "", periodStart: Date, periodEnd: Date, createdAt: Date = .distantPast, pinnedAt: Date? = nil) {
        self.id = id
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
}
