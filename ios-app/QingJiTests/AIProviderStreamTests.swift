import XCTest
@testable import QingJi

@MainActor
final class AIProviderStreamTests: XCTestCase {
    private func account(_ endpoint: AIEndpointKind, host: String) -> AIProviderAccount {
        AIProviderAccount(name: "Stream fixture", type: .custom,
                          baseURL: "https://\(host)/v1", model: "fixture-model", endpoint: endpoint)
    }

    private func fixture(_ scenario: StreamFixtureProtocol.Scenario) -> (String, URLSession) {
        let host = "\(UUID().uuidString.lowercased()).fixture.invalid"
        StreamFixtureProtocol.register(scenario, host: host)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamFixtureProtocol.self]
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        return (host, URLSession(configuration: configuration))
    }

    private func close(_ host: String, _ session: URLSession) {
        session.invalidateAndCancel()
        StreamFixtureProtocol.remove(host: host)
    }

    private func run(_ endpoint: AIEndpointKind, chunks: [String]) async throws -> AIChatResponse {
        let (host, session) = fixture(.init(chunks: chunks))
        defer { close(host, session) }
        return try await AIProviderClient.stream(account: account(endpoint, host: host),
            secret: "fixture-only", messages: [AIChatTurn(role: "user", content: "hello")],
            onText: { _ in }, session: session)
    }

    private func assertInterrupted(_ endpoint: AIEndpointKind, chunks: [String],
                                   expectedText: String, failure: URLError.Code? = nil,
                                   file: StaticString = #filePath, line: UInt = #line) async {
        let (host, session) = fixture(.init(chunks: chunks, failure: failure))
        defer { close(host, session) }
        var received = ""
        do {
            _ = try await AIProviderClient.stream(account: account(endpoint, host: host),
                secret: "fixture-only", messages: [AIChatTurn(role: "user", content: "hello")],
                onText: { received += $0 }, session: session)
            XCTFail("An incomplete stream must not be saved as success", file: file, line: line)
        } catch {
            if let failure {
                XCTAssertEqual((error as? URLError)?.code, failure, file: file, line: line)
            } else if let providerError = error as? AIProviderError, case .interrupted = providerError {
                // The partial text remains available through onText.
            } else {
                XCTFail("Expected a classified interruption, got \(error)", file: file, line: line)
            }
        }
        XCTAssertEqual(received, expectedText, file: file, line: line)
    }

    func testChatCompletionsReassemblesMultilineDataAndChunkBoundaries() async throws {
        let response = try await run(.chatCompletions, chunks: [
            ": keep-alive\n\nevent: message\ndata: {\"choices\":[{\"delta\":",
            "\ndata: {\"content\":\"Hello\"}}]}\n\n",
            "data: {\"choices\":[{\"finish_reason\":\"stop\"}]}\n\n",
        ])
        XCTAssertEqual(response.text, "Hello")
    }

    func testChatCompletionsDoneSentinelCompletesButEOFDoesNot() async throws {
        let text = "data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n"
        let response = try await run(.chatCompletions, chunks: [text, "data: [DONE]\n\n"])
        XCTAssertEqual(response.text, "partial")
        await assertInterrupted(.chatCompletions, chunks: [text], expectedText: "partial")
    }

    func testSSEAcceptsBOMCRLFAndUnicodeWithoutLosingBlankEventBoundaries() async throws {
        let response = try await run(.chatCompletions, chunks: [
            "\u{FEFF}: keep-alive\r\ndata: {\"choices\":[{\"delta\":{\"content\":\"你好\"}}]}\r",
            "\n\r\ndata: [DONE]\r\n\r\n",
        ])
        XCTAssertEqual(response.text, "你好")
    }

    func testChatLengthAndErrorCannotBecomeSuccessfulPartialAnswer() async {
        let text = "data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n"
        for terminal in [
            "data: {\"choices\":[{\"finish_reason\":\"length\"}]}\n\n",
            "data: {\"error\":{\"message\":\"overloaded\"}}\n\ndata: [DONE]\n\n",
            "event: error\ndata: {\"message\":\"overloaded\"}\n\ndata: [DONE]\n\n",
        ] {
            await assertInterrupted(.chatCompletions, chunks: [text, terminal], expectedText: "partial")
        }
    }

    func testResponsesReturnsAuthoritativeFinalTextAndPublicSummary() async throws {
        let response = try await run(.responses, chunks: [
            "data: {\"type\":\"response.reasoning_summary_text.delta\",\"delta\":\"Plan\\n\\n\"}\n\n",
            "data: {\"type\":\"response.output_text.delta\",\"delta\":\"draft\"}\n\n",
            "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"output_text\":\"final\"}}\n\n",
        ])
        XCTAssertEqual(response.text, "final")
        XCTAssertEqual(response.reasoningSummary, "Plan\n\n")
    }

    func testResponsesFailureIncompleteAndBareDoneRetainPartialText() async {
        let text = "data: {\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}\n\n"
        for terminal in [
            "data: {\"type\":\"response.failed\"}\n\n",
            "data: {\"type\":\"response.incomplete\"}\n\n",
            "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"incomplete\"}}\n\n",
            "data: [DONE]\n\n", "",
        ] {
            await assertInterrupted(.responses, chunks: [text, terminal], expectedText: "partial")
        }
    }

    func testAnthropicRequiresNormalStopReasonAndMessageStop() async throws {
        let text = "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"answer\"}}\n\n"
        for reason in ["end_turn", "stop_sequence", "refusal"] {
            let response = try await run(.anthropicMessages, chunks: [text,
                "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"\(reason)\"}}\n\n",
                "data: {\"type\":\"message_stop\"}\n\n"])
            XCTAssertEqual(response.text, "answer")
        }
    }

    func testAnthropicTruncationUnsupportedToolAndMissingStopAreInterrupted() async {
        let text = "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"partial\"}}\n\n"
        for reason in ["max_tokens", "pause_turn", "tool_use", "unknown"] {
            await assertInterrupted(.anthropicMessages, chunks: [text,
                "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"\(reason)\"}}\n\n",
                "data: {\"type\":\"message_stop\"}\n\n"], expectedText: "partial")
        }
        await assertInterrupted(.anthropicMessages, chunks: [text,
            "data: {\"type\":\"message_stop\"}\n\n"], expectedText: "partial")
        await assertInterrupted(.anthropicMessages, chunks: [text,
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"}}\n\n"], expectedText: "partial")
    }

    func testTransportDisconnectionPreservesDeliveredText() async {
        await assertInterrupted(.responses, chunks: [
            "data: {\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}\n\n",
        ], expectedText: "partial", failure: .networkConnectionLost)
    }

    func testHTTPFailureIsClassifiedBeforeParsingTheStream() async {
        let (host, session) = fixture(.init(status: 403, chunks: ["unsupported_country_region"]))
        defer { close(host, session) }
        var received = ""
        do {
            _ = try await AIProviderClient.stream(account: account(.responses, host: host),
                secret: "fixture-only", messages: [], onText: { received += $0 }, session: session)
            XCTFail("HTTP failure must not be a successful answer")
        } catch AIProviderError.http(let status, let message) {
            XCTAssertEqual(status, 403)
            XCTAssertEqual(message, "unsupported_country_region")
        } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(received, "")
    }

    func testCancellationIsNotReportedAsProviderFailure() async {
        let (host, session) = fixture(.init(chunks: [
            "data: {\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}\n\n",
        ], holdOpen: true))
        defer { close(host, session) }
        let firstText = expectation(description: "Real URLSession delivered a text delta")
        let task = Task {
            try await AIProviderClient.stream(account: account(.responses, host: host),
                secret: "fixture-only", messages: [], onText: { _ in firstText.fulfill() }, session: session)
        }
        await fulfillment(of: [firstText], timeout: 2)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled stream must not complete")
        } catch { XCTAssertTrue(AIProviderError.isCancellation(error)) }
    }
}

private final class StreamFixtureProtocol: URLProtocol {
    struct Scenario {
        var status = 200
        var chunks: [String]
        var failure: URLError.Code? = nil
        var holdOpen = false
    }
    private static let lock = NSLock()
    private static var scenarios: [String: Scenario] = [:]
    private let stateLock = NSRecursiveLock()
    private var stopped = false

    static func register(_ scenario: Scenario, host: String) {
        lock.lock(); defer { lock.unlock() }
        scenarios[host] = scenario
    }
    static func remove(host: String) {
        lock.lock(); defer { lock.unlock() }
        scenarios.removeValue(forKey: host)
    }
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix(".fixture.invalid") == true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let host = request.url?.host
        let scenario = host.flatMap { Self.scenarios[$0] }
        Self.lock.unlock()
        guard let url = request.url, let scenario,
              let response = HTTPURLResponse(url: url, statusCode: scenario.status,
                  httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in scenario.chunks { client?.urlProtocol(self, didLoad: Data(chunk.utf8)) }
        guard !scenario.holdOpen else { return }
        // Deliver EOF/errors after AsyncBytes has had a chance to yield the body.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { [self] in
            stateLock.lock(); defer { stateLock.unlock() }
            guard !stopped else { return }
            if let failure = scenario.failure {
                client?.urlProtocol(self, didFailWithError: URLError(failure))
            } else {
                client?.urlProtocolDidFinishLoading(self)
            }
        }
    }
    override func stopLoading() {
        stateLock.lock(); defer { stateLock.unlock() }
        stopped = true
    }
}
