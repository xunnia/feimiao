import XCTest
import SwiftData
@testable import QingJi

@MainActor
final class AIMemoryStoreTests: XCTestCase {
    private final class Stack {
        let container: ModelContainer
        let context: ModelContext

        init() throws {
            let schema = Schema([AIMemoryRecord.self])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let modelContainer = try ModelContainer(for: schema, configurations: [configuration])
            container = modelContainer
            context = ModelContext(modelContainer)
        }
    }

    func testOnlyAuthorizedMatchingMemoryEntersPromptBlock() throws {
        let stack = try Stack()
        let context = stack.context
        let matching = try AIMemoryStore.add(
            phrase: "不吃辣",
            content: "点餐时优先选择清淡口味",
            consent: true,
            in: context
        )
        _ = try AIMemoryStore.add(
            phrase: "不相关",
            content: "这条不应该进入本次上下文",
            consent: false,
            in: context
        )
        let prompt = AIMemoryStore.promptBlock(
            memories: try AIMemoryStore.all(in: context),
            query: "帮我找不吃辣的餐厅"
        )
        XCTAssertTrue(prompt.contains(matching.content))
        XCTAssertFalse(prompt.contains("这条不应该进入本次上下文"))
    }
}
