import XCTest
@testable import QingJi

final class AIChatOperationFenceTests: XCTestCase {
    func testClearingOneSessionDoesNotInvalidateOthers() {
        let fence = AIChatOperationFence()
        let firstID = UUID()
        let secondID = UUID()
        let bookID = UUID()
        let first = fence.capture(sessionID: firstID, bookID: bookID)
        let second = fence.capture(sessionID: secondID, bookID: bookID)
        fence.invalidate(sessionID: firstID)
        XCTAssertFalse(fence.isCurrent(first))
        XCTAssertTrue(fence.isCurrent(second))
        XCTAssertEqual(second.bookID, bookID)
        XCTAssertTrue(fence.isCurrent(fence.capture(sessionID: firstID, bookID: bookID)))
    }

    func testRestoreRevokesAllOldRequestsEvenWithSameStableIDs() {
        let fence = AIChatOperationFence()
        let sessionID = UUID()
        let bookID = UUID()
        let old = fence.capture(sessionID: sessionID, bookID: bookID)
        fence.invalidateDatabase()
        let new = fence.capture(sessionID: sessionID, bookID: bookID)
        XCTAssertFalse(fence.isCurrent(old))
        XCTAssertTrue(fence.isCurrent(new))
        XCTAssertNotEqual(old.generation, new.generation)
    }

    func testCompletionRoundTripKeepsInterruptedAndDuration() throws {
        let value = AIChatCompletionMetadata(thinkingSeconds: 11, interrupted: true)
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(AIChatCompletionMetadata.self, from: data), value)
        XCTAssertEqual(AIChatCompletionMetadata(thinkingSeconds: -1, interrupted: false).thinkingSeconds, 0)
    }
}
