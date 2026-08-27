import XCTest
import SwiftData
@testable import QingJi

@MainActor
final class AIRequestRunStoreTests: XCTestCase {
    private final class Stack {
        let container: ModelContainer
        let context: ModelContext

        init() throws {
            let schema = Schema([AIRequestRunRecord.self, AIRequestEventRecord.self])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let modelContainer = try ModelContainer(for: schema, configurations: [configuration])
            container = modelContainer
            context = ModelContext(modelContainer)
        }
    }

    func testRunMovesToAwaitingConfirmationAndKeepsOnlyStageMetadata() throws {
        let stack = try Stack()
        let account = AIProviderAccount(
            name: "测试服务商",
            type: .custom,
            baseURL: "https://example.com/v1",
            model: "test-model"
        )
        let runID = try XCTUnwrap(AIRequestRunStore.start(
            mode: .record,
            account: account,
            sessionID: nil,
            inputCharacters: 8,
            attachmentCount: 1,
            in: stack.context
        ))
        AIRequestRunStore.setStatus(runID, .awaitingConfirmation, summary: "1 笔提案", in: stack.context)
        AIRequestRunStore.append(.proposalReady, runID: runID, count: 1, in: stack.context)

        let run = try XCTUnwrap(
            AIRequestRunStore.runs(in: stack.context).first(where: { $0.stableID == runID })
        )
        XCTAssertEqual(run.status, .awaitingConfirmation)
        XCTAssertEqual(run.inputCharacters, 8)
        XCTAssertEqual(run.attachmentCount, 1)
        XCTAssertTrue(run.errorMessage.isEmpty)
        XCTAssertEqual(AIRequestRunStore.events(for: runID, in: stack.context).count, 2)
    }
}
