import Foundation

struct AIStreamSummaryBuffer {
    static let maxCharacters = 65536
    private(set) var text = ""
    private(set) var truncated = false
    private var characterCount = 0

    @discardableResult mutating func append(_ delta: String) -> String {
        // Count only the new chunk, not the whole accumulated summary.
        let remaining = max(0, Self.maxCharacters - characterCount)
        let accepted = String(delta.prefix(remaining))
        text += accepted
        characterCount += accepted.count
        truncated = truncated || accepted != delta
        return accepted
    }
}
