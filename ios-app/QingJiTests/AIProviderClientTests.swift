import XCTest
import QingJiCore
@testable import QingJi

@MainActor
final class AIProviderClientTests: XCTestCase {
    func testOnlyProviderPublicSummaryEventsAreDisplayed() {
        let account = AIProviderAccount(name: "Test", type: .custom,
            baseURL: "https://example.com/v1", model: "gpt-test", endpoint: .responses)
        XCTAssertEqual(AIProviderClient.publicSummaryForTesting(
            payload: #"{"type":"response.reasoning_summary_text.delta","delta":"\n\n"}"#, account: account), "\n\n")
        for event in ["response.reasoning_text.delta", "response.reasoning_summary_text.done", "untrusted.reasoning_summary"] {
            XCTAssertEqual(AIProviderClient.publicSummaryForTesting(
                payload: "{\"type\":\"\(event)\",\"delta\":\"not public\"}", account: account), "")
        }
    }
    func testEndpointNormalizationRemovesPastedOperationSuffix() {
        let account = AIProviderAccount(
            name: "OpenAI",
            type: .custom,
            baseURL: "https://api.openai.com/v1/chat/completions",
            model: "gpt-5-mini",
            endpoint: .automatic
        )

        XCTAssertEqual(
            AIProviderClient.endpointURLForTesting(account: account)?.absoluteString,
            "https://api.openai.com/v1/responses"
        )
        XCTAssertEqual(
            AIProviderClient.endpointURLForTesting(account: account, modelsRequest: true)?.absoluteString,
            "https://api.openai.com/v1/models"
        )
    }

    func testChatCompletionsBodyMapsDeepSeekEffort() throws {
        let account = AIProviderAccount(
            name: "DeepSeek",
            type: .deepSeek,
            baseURL: "https://api.deepseek.com",
            model: "deepseek-v4-flash",
            endpoint: .chatCompletions,
            effort: .high
        )
        let body = AIProviderClient.requestBodyForTesting(
            account: account,
            messages: [AIChatTurn(role: "user", content: "你好")]
        )

        XCTAssertEqual(body["model"] as? String, "deepseek-v4-flash")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["reasoning_effort"] as? String, "high")
        XCTAssertNotNil(body["thinking"] as? [String: String])
    }

    func testResponsesBodySeparatesSystemInstructions() throws {
        let account = AIProviderAccount(
            name: "OpenAI",
            type: .custom,
            baseURL: "https://api.openai.com/v1",
            model: "gpt-5-mini",
            endpoint: .responses,
            effort: .medium
        )
        let body = AIProviderClient.requestBodyForTesting(
            account: account,
            messages: [
                AIChatTurn(role: "system", content: "只回答账务事实"),
                AIChatTurn(role: "user", content: "本月支出多少")
            ]
        )

        XCTAssertEqual(body["instructions"] as? String, "只回答账务事实")
        XCTAssertEqual(body["store"] as? Bool, false)
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 1)
        XCTAssertEqual(input.first?["role"] as? String, "user")
    }

    func testStructuredRecordBodyUsesProviderNativeFormat() throws {
        let responses = AIProviderAccount(
            name: "OpenAI",
            type: .custom,
            baseURL: "https://api.openai.com/v1",
            model: "gpt-5-mini",
            endpoint: .responses
        )
        let responseBody = AIProviderClient.requestBodyForTesting(
            account: responses,
            messages: [AIChatTurn(role: "user", content: "昨天打车23")],
            structuredRecord: true
        )
        let text = try XCTUnwrap(responseBody["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["name"] as? String, "feimiao_record")

        let chat = AIProviderAccount(
            name: "DeepSeek",
            type: .deepSeek,
            baseURL: "https://api.deepseek.com",
            model: "deepseek-v4-flash",
            endpoint: .chatCompletions
        )
        let chatBody = AIProviderClient.requestBodyForTesting(
            account: chat,
            messages: [AIChatTurn(role: "user", content: "昨天打车23")],
            structuredRecord: true
        )
        XCTAssertEqual((chatBody["response_format"] as? [String: String])?["type"], "json_object")
        XCTAssertNotNil(chatBody["response_schema"] as? [String: Any])
    }

    func testPrivateLedgerConversationDisablesNativeWebSearchPerRequest() {
        let now = Date(timeIntervalSince1970: 1_787_803_200)
        let ledgerMessages = AssistantChatContract.systemMessages(
            now: now,
            ledgerText: "账本范围：总账本（发起时已锁定）\n本期准确合计：支出 ¥100.00"
        ).map { AIChatTurn(role: "system", content: $0) }
            + [AIChatTurn(role: "user", content: "这个月花了多少")]
        XCTAssertFalse(
            AIProviderStore.allowsWebSearch(
                messages: ledgerMessages,
                globalEnabled: true,
                structuredRecord: false
            )
        )

        let mixedMessages = AssistantChatContract.systemMessages(
            now: now,
            ledgerText: ""
        ).map { AIChatTurn(role: "system", content: $0) }
            + [AIChatTurn(role: "user", content: "查询我的账单，并分析最近股市")]
        XCTAssertFalse(
            AIProviderStore.allowsWebSearch(
                messages: mixedMessages,
                globalEnabled: true,
                structuredRecord: false
            )
        )

        let publicMessages = AssistantChatContract.systemMessages(
            now: now,
            ledgerText: ""
        ).map { AIChatTurn(role: "system", content: $0) }
            + [AIChatTurn(role: "user", content: "帮我分析下最近的股市")]
        XCTAssertTrue(
            AIProviderStore.allowsWebSearch(
                messages: publicMessages,
                globalEnabled: true,
                structuredRecord: false
            )
        )
        XCTAssertTrue(AIWebSearch.shouldSearch("帮我分析下最近的股市"))
        XCTAssertFalse(AIWebSearch.shouldSearch("查询我的账单，并分析最近股市"))
        XCTAssertFalse(
            AIWebSearch.shouldSearch(
                "上个月呢",
                previousUserQuestionsNewestFirst: ["这个月花了多少"]
            )
        )

        var responsesAccount = AIProviderAccount(
            name: "OpenAI",
            type: .custom,
            baseURL: "https://api.openai.com/v1",
            model: "gpt-5-mini",
            endpoint: .responses,
            webSearchEnabled: false
        )
        let privateBody = AIProviderClient.requestBodyForTesting(
            account: responsesAccount,
            messages: ledgerMessages
        )
        XCTAssertNil(privateBody["tools"])

        responsesAccount.webSearchEnabled = true
        let publicBody = AIProviderClient.requestBodyForTesting(
            account: responsesAccount,
            messages: publicMessages
        )
        XCTAssertNotNil(publicBody["tools"])
    }
}
