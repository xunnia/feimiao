import XCTest
@testable import QingJiCore

final class ChatIntentTests: XCTestCase {
    func testExplicitLedgerQuestionIsQuery() {
        XCTAssertEqual(
            ChatIntent.classify("本月餐饮花了多少", hasArabicAmount: false),
            .query
        )
    }

    func testKnowledgeQuestionWithNumbersIsChat() {
        XCTAssertEqual(
            ChatIntent.classify("推荐 3 部电影，预算 500 元够吗？", hasArabicAmount: true),
            .chat
        )
    }

    func testExpensePhraseWithBareAmountIsRecord() {
        XCTAssertEqual(
            ChatIntent.classify("午饭 28", hasArabicAmount: true),
            .record
        )
    }

    func testPlainAmountWithoutLedgerContextIsChat() {
        XCTAssertEqual(
            ChatIntent.classify("我写了 500 字", hasArabicAmount: true),
            .chat
        )
    }

    func testCalendarWordsAloneAreNotFinanceQueries() {
        for question in [
            "帮我分析下最近的股市",
            "今年股市怎么样",
            "本月股票涨幅怎么样",
            "上个月广州天气怎么样",
            "今年有什么好电影",
        ] {
            XCTAssertEqual(ChatIntent.classify(question), .chat, question)
        }
        XCTAssertEqual(ChatIntent.classify("今年收入多少"), .query)
        XCTAssertEqual(ChatIntent.classify("这个月超支了吗"), .query)
        XCTAssertEqual(ChatIntent.classify("查一下本月餐饮"), .query)
    }

    func testPeriodFollowUpInheritsOnlyFromLastExplicitUserTopic() {
        let topic = ChatIntent.lastTopicQuestion([
            "上个月呢",
            "那上周呢",
            "这个月花了多少",
        ])
        XCTAssertEqual(topic, "这个月花了多少")
        XCTAssertEqual(ChatIntent.classify("去年呢", previousQuestion: topic), .query)
        XCTAssertEqual(ChatIntent.classify("上个月呢", previousQuestion: "广州天气怎么样"), .chat)
        XCTAssertEqual(ChatIntent.classify("上个月呢", previousQuestion: "今年股市怎么样"), .chat)
        XCTAssertEqual(ChatIntent.classify("上个月呢"), .chat)
        XCTAssertEqual(
            ChatIntent.lastTopicQuestion(["今年股市怎么样", "这个月花了多少"]),
            "今年股市怎么样"
        )
    }

    func testAssistantChatContractSystemMessagesSeparateLedgerAndMemory() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = Date(timeIntervalSince1970: 1_787_803_200) // 2026-08-27T12:00:00+08:00

        let chatMessages = AssistantChatContract.systemMessages(
            now: now,
            timeZone: timeZone,
            ledgerText: "",
            memoryText: "- 喜欢喝美式咖啡"
        )
        XCTAssertEqual(chatMessages.count, 4)
        XCTAssertTrue(chatMessages[0].contains("股市分析"))
        XCTAssertTrue(chatMessages[1].contains("UTC+08:00"))
        XCTAssertTrue(chatMessages[2].contains("本次是普通对话，没有提供账本数据"))
        XCTAssertTrue(chatMessages[3].contains("偏好参考，不是账本数据"))
        XCTAssertTrue(chatMessages[3].contains("喜欢喝美式咖啡"))

        let queryMessages = AssistantChatContract.systemMessages(
            now: now,
            timeZone: timeZone,
            ledgerText: "本期准确合计：支出 ¥1017.90",
            memoryText: ""
        )
        XCTAssertEqual(queryMessages.count, 3)
        XCTAssertTrue(queryMessages[2].contains("本期准确合计：支出 ¥1017.90"))
        XCTAssertTrue(queryMessages[2].contains("必须引用该数"))
    }

    func testAssistantChatContractDisablesWebSearchForPrivateLedgerRequests() {
        for question in [
            "本月花了多少",
            "查询我的账单，并分析最近股市",
            "查账以后搜索最近股市",
            "记一笔股票手续费 30 元",
        ] {
            XCTAssertFalse(
                AssistantChatContract.allowsWebSearch(
                    globalEnabled: true,
                    structuredRecord: false,
                    question: question,
                    ledgerText: ""
                ),
                question
            )
            XCTAssertFalse(
                AssistantChatContract.shouldRunPublicWebSearch(question),
                question
            )
        }

        // 带账本上下文时（例如日期追问「上个月呢」继承查账），即使问句本身不含财务词也要关搜索。
        XCTAssertFalse(
            AssistantChatContract.allowsWebSearch(
                globalEnabled: true,
                structuredRecord: false,
                question: "上个月呢",
                ledgerText: "本期准确合计：支出 ¥100",
                previousUserQuestionsNewestFirst: ["这个月花了多少"]
            )
        )

        // 公开市场问题保持放行。
        for question in [
            "帮我分析下最近的股市",
            "今年股市怎么样",
            "本月股票涨幅怎么样",
            "看看上周大盘走势",
        ] {
            XCTAssertTrue(
                AssistantChatContract.allowsWebSearch(
                    globalEnabled: true,
                    structuredRecord: false,
                    question: question,
                    ledgerText: ""
                ),
                question
            )
            XCTAssertTrue(
                AssistantChatContract.shouldRunPublicWebSearch(question),
                question
            )
        }
        XCTAssertFalse(
            AssistantChatContract.allowsWebSearch(
                globalEnabled: false,
                structuredRecord: false,
                question: "帮我分析下最近的股市",
                ledgerText: ""
            )
        )
    }

    func testResolveIntentHandlesRecordSessionAttachmentsAndFollowUp() {
        XCTAssertEqual(
            AssistantChatContract.resolveIntent(
                recordSession: true,
                text: "今天天气怎么样"
            ),
            .record
        )
        XCTAssertEqual(
            AssistantChatContract.resolveIntent(
                recordSession: false,
                text: "本月餐饮花了多少",
                hasAttachments: true
            ),
            .chat
        )
        XCTAssertEqual(
            AssistantChatContract.resolveIntent(
                recordSession: false,
                text: "上个月呢",
                previousUserQuestionsNewestFirst: ["这个月花了多少"]
            ),
            .query
        )
        XCTAssertEqual(
            AssistantChatContract.resolveIntent(
                recordSession: false,
                text: "上个月呢",
                previousUserQuestionsNewestFirst: ["今年股市怎么样", "这个月花了多少"]
            ),
            .chat
        )
    }
}
