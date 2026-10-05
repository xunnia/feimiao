import XCTest
import QingJiCore
@testable import QingJi

final class AIRecordCardTests: XCTestCase {
    func testBookIdentityIsPersistedAndOldCardsRemainReadable() throws {
        let bookID = UUID()
        let card = AIRecordCardState(entries: [], bookID: bookID)
        let data = try JSONEncoder().encode(card)
        XCTAssertEqual(try JSONDecoder().decode(AIRecordCardState.self, from: data).bookID, bookID)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        old.removeValue(forKey: "bookID")
        let oldData = try JSONSerialization.data(withJSONObject: old)
        XCTAssertNil(try JSONDecoder().decode(AIRecordCardState.self, from: oldData).bookID)
    }

    func testRecordCardRoundTripsSavedAndUndoState() throws {
        let entry = ParsedEntry(
            amount: Decimal(string: "23.50"),
            kind: .expense,
            categoryKey: "trans_taxi",
            note: "打车",
            date: Date(timeIntervalSince1970: 1_000),
            timePrecision: .entryClock,
            confidence: 0.91
        )
        let transactionID = UUID()
        let original = AIRecordCardState(
            entries: [entry],
            categoryKeys: ["trans_taxi"],
            transactionIDs: [transactionID],
            deletedIndices: [0],
            saved: true,
            rolledBack: true,
            feedback: "本次 AI 记账已撤销"
        )

        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(AIRecordCardState.self, from: data)
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.categoryKey(at: 0), "trans_taxi")
        XCTAssertEqual(restored.transactionID(at: 0), transactionID)
    }
}
