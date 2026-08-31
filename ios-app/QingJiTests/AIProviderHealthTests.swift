import XCTest
@testable import QingJi

@MainActor
final class AIProviderHealthTests: XCTestCase {
    func testVerificationStatusSurvivesARegularFailure() {
        let now = Date(timeIntervalSince1970: 1_735_689_600)
        var health = AIProviderHealth(providerID: UUID())

        health = health.recordVerification(
            status: .invalidCredential,
            message: "凭据失效",
            latencyMs: 120,
            now: now
        )
        health = health.recordFailure("temporary network error", now: now.addingTimeInterval(1))

        XCTAssertEqual(health.verificationStatus, AIProviderVerificationStatus.invalidCredential.rawValue)
        XCTAssertEqual(health.statusLabel, "凭据失效")
        XCTAssertEqual(health.failureCount, 2)
    }

    func testRegularFailureDoesNotLeaveAStaleAvailableStatus() {
        let now = Date()
        var health = AIProviderHealth(providerID: UUID())
        health = health.recordSuccess(latencyMs: 100, now: now)
        health = health.recordFailure("网络暂时不可用", now: now.addingTimeInterval(1))

        XCTAssertEqual(health.verificationStatus, "")
        XCTAssertEqual(health.statusLabel, "最近失败")
    }

    func testSuccessfulVerificationRecordsAverageLatency() {
        let now = Date(timeIntervalSince1970: 1_735_689_600)
        let id = UUID()
        var health = AIProviderHealth(providerID: id)
        health = health.recordVerification(
            status: .available,
            message: "",
            latencyMs: 100,
            now: now
        )
        health = health.recordSuccess(latencyMs: 300, now: now.addingTimeInterval(1))

        XCTAssertEqual(health.verificationStatus, AIProviderVerificationStatus.available.rawValue)
        XCTAssertEqual(health.successCount, 2)
        XCTAssertEqual(health.averageLatencyMs, 200)
        XCTAssertEqual(health.lastError, "")
    }

    func testThreeFailuresEnterCooldownAndSanitizeCredential() {
        let now = Date(timeIntervalSince1970: 1_735_689_600)
        var health = AIProviderHealth(providerID: UUID())
        for offset in 0..<3 {
            health = health.recordFailure(
                "Bearer secret-token sk-test-secret",
                now: now.addingTimeInterval(Double(offset))
            )
        }

        XCTAssertNotNil(health.cooldownUntil)
        XCTAssertEqual(health.failureCount, 3)
        XCTAssertFalse(health.lastError.contains("secret-token"))
        XCTAssertFalse(health.lastError.contains("sk-test-secret"))
    }

    func testHealthPersistsAcrossStoreReload() {
        let suiteName = "qingji.ai-provider-health-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let providerID = UUID()
        let store = AIProviderStore(defaults: defaults)
        _ = store.recordProviderVerification(
            for: providerID,
            status: .needsProxy,
            message: "unsupported_country_region",
            latencyMs: 240
        )

        let reloaded = AIProviderStore(defaults: defaults)
        let health = reloaded.health(for: providerID)
        XCTAssertEqual(health.statusLabel, "需要代理/VPN")
        XCTAssertEqual(health.failureCount, 1)
        XCTAssertEqual(health.lastError, "unsupported_country_region")
        XCTAssertEqual(health.averageLatencyMs, 0)
    }

    func testVerificationWithoutCredentialsReturnsConfigurationError() async {
        let suiteName = "qingji.ai-provider-verification-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let account = AIProviderAccount(
            name: "未配置服务商",
            type: .custom,
            baseURL: "https://example.com/v1",
            model: "gpt-test"
        )
        let store = AIProviderStore(defaults: defaults)
        let result = await store.verify(account: account)

        XCTAssertEqual(result.status, .configurationError)
        XCTAssertEqual(store.health(for: account.id).statusLabel, "配置不完整")
        XCTAssertEqual(store.health(for: account.id).failureCount, 1)
    }

    func testVerificationStatusClassifiesOAuthRegionFailureAsProxy() {
        let error = AIProviderError.http(403, "unsupported_country_region")
        XCTAssertEqual(AIProviderVerificationStatus.from(error: error), .needsProxy)
        XCTAssertEqual(
            AIProviderVerificationStatus.from(error: AIProviderError.http(401, "invalid token")),
            .invalidCredential
        )
        XCTAssertEqual(
            AIProviderVerificationStatus.from(error: AIProviderError.http(404, "model not found")),
            .modelUnavailable
        )
    }

    func testOAuthRefreshFailureIsAnInvalidCredential() {
        XCTAssertEqual(
            AIProviderVerificationStatus.from(error: OpenAIOAuthError.http(400, "invalid_grant")),
            .invalidCredential
        )
        XCTAssertEqual(
            AIProviderVerificationStatus.from(error: AIProviderError.http(400, "invalid_token")),
            .invalidCredential
        )
        XCTAssertEqual(
            AIProviderVerificationStatus.from(error: OpenAIOAuthError.authorizationFailed("token expired")),
            .invalidCredential
        )
        XCTAssertEqual(
            AIProviderVerificationStatus.from(error: OpenAIOAuthError.invalidTokenResponse),
            .invalidCredential
        )
        XCTAssertEqual(
            AIProviderVerificationStatus.from(error: AIProviderStoreError.missingSecret),
            .configurationError
        )
    }

    func testAuthorizationResultKeepsVerificationSeparateFromAccountMetadata() {
        let account = AIProviderAccount(
            name: "ChatGPT",
            type: .custom,
            baseURL: OpenAIOAuth.codexBaseURL,
            model: "gpt-5",
            endpoint: .responses,
            authMethod: .oauth
        )
        let verification = AIProviderVerificationResult(
            status: .needsProxy,
            message: "unsupported_country_region"
        )
        let result = AIProviderAuthorizationResult(account: account, verification: verification)

        XCTAssertEqual(result.account.id, account.id)
        XCTAssertEqual(result.verification.status, .needsProxy)
        XCTAssertEqual(result.verification.message, "unsupported_country_region")
    }

    func testVerificationResultRetainsDiscoveredModelsOnFailure() {
        let result = AIProviderVerificationResult(
            status: .needsProxy,
            models: ["gpt-5", "gpt-5-mini"],
            message: "需要代理/VPN"
        )

        XCTAssertEqual(result.models, ["gpt-5", "gpt-5-mini"])
        XCTAssertFalse(result.isAvailable)
    }
}
