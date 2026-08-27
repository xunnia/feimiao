import XCTest
@testable import QingJi

@MainActor
final class OpenAIOAuthTests: XCTestCase {
    func testPKCEUsesRFC7636Challenge() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(
            OpenAIOAuth.codeChallenge(for: verifier),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
    }

    func testAuthorizationURLContainsStateAndPKCEContract() throws {
        let url = OpenAIOAuth.authorizationURL(verifier: "verifier", state: "state")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["client_id"], OpenAIOAuth.clientID)
        XCTAssertEqual(query["redirect_uri"], OpenAIOAuth.redirectURI)
        XCTAssertEqual(query["state"], "state")
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["code_challenge"], OpenAIOAuth.codeChallenge(for: "verifier"))
    }

    func testOAuthCodexRequestUsesCodexRouteAndHeaders() throws {
        let account = AIProviderAccount(
            name: "ChatGPT",
            type: .custom,
            baseURL: OpenAIOAuth.codexBaseURL,
            model: "gpt-5",
            endpoint: .responses,
            authMethod: .oauth,
            oauthAccountID: "workspace-1"
        )
        let request = try XCTUnwrap(AIProviderClient.requestForTesting(
            account: account,
            secret: "access-token",
            messages: [AIChatTurn(role: "user", content: "你好")]
        ))
        XCTAssertEqual(request.url, OpenAIOAuth.codexResponsesURL)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "workspace-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "originator"), OpenAIOAuth.originator)
        XCTAssertEqual(request.value(forHTTPHeaderField: "OpenAI-Beta"), "responses=v1")
    }

    func testAccountIDCanBeReadFromOpenAIAuthClaim() throws {
        let header = base64URL(#"{"alg":"none","typ":"JWT"}"#)
        let payload = base64URL(#"{"https://api.openai.com/auth":{"chatgpt_account_id":"acct-1"}}"#)
        XCTAssertEqual(OpenAIOAuth.accountID(fromIDToken: "\(header).\(payload).signature"), "acct-1")
    }

    private func base64URL(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
