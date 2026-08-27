import AuthenticationServices
import CryptoKit
import Foundation
import Network
import Security
import UIKit

/// ChatGPT/Codex OAuth 的协议常量和 PKCE 工具。
///
/// 访问令牌、刷新令牌和 id_token 只在内存中流转，持久化由
/// AIProviderStore 写入 Keychain；这个类型本身不参与账本备份。
enum OpenAIOAuth {
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let authorizationEndpoint = URL(string: "https://auth.openai.com/oauth/authorize")!
    static let tokenEndpoint = URL(string: "https://auth.openai.com/oauth/token")!
    static let codexBaseURL = "https://chatgpt.com/backend-api"
    static let codexModelsURL = URL(string: "https://chatgpt.com/backend-api/codex/models?client_version=0.146.0")!
    static let codexResponsesURL = URL(string: "https://chatgpt.com/backend-api/codex/responses")!
    /// The OpenAI/Codex public client is registered for these loopback
    /// redirects. The app's private qingji scheme is used only after the
    /// local listener has received and validated the HTTP request.
    static let redirectURI = "http://localhost:1455/auth/callback"
    static let loopbackPorts: [UInt16] = [1455, 1457]
    static let callbackURI = "qingji://oauth/callback"
    static let callbackScheme = "qingji"
    static let originator = "codex_vscode"
    static let userAgent = "codex_vscode/0.146.0"
    static let scopes = "openid profile email offline_access api.connectors.read api.connectors.invoke"

    static func generateVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func authorizationURL(
        verifier: String,
        state: String,
        redirectURI: String = redirectURI
    ) -> URL {
        var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: codeChallenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "originator", value: originator),
        ]
        return components.url!
    }

    static func accountID(fromIDToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var encoded = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let auth = object["https://api.openai.com/auth"] as? [String: Any],
           let id = (auth["chatgpt_account_id"] as? String) ?? (auth["account_id"] as? String),
           !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return id.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let id = (object["chatgpt_account_id"] as? String) ?? (object["account_id"] as? String),
           !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return id.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let organizations = object["organizations"] as? [[String: Any]],
           let first = organizations.first,
           let id = (first["id"] as? String) ?? (first["organization_id"] as? String),
           !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return id.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    static func expiresAt(from token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var encoded = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["exp"] as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: raw.doubleValue)
    }

    @MainActor
    static func authorize() async throws -> OpenAIOAuthTokens {
        let verifier = generateVerifier()
        let state = generateVerifier()
        let redirectServer = try await LoopbackRedirectServer.bind()
        defer { redirectServer.stop() }
        let url = authorizationURL(
            verifier: verifier,
            state: state,
            redirectURI: redirectServer.redirectURI
        )
        // Keep the coordinator alive until the browser callback resumes the
        // continuation. ASWebAuthenticationSession does not own the
        // presentation context provider strongly enough to rely on a
        // temporary value here.
        let authenticationSession = AuthenticationSession(url: url)
        let callback = try await authenticationSession.start()
        guard callback.scheme == callbackScheme,
              let returnedState = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "state" })?.value,
              returnedState == state else {
            throw OpenAIOAuthError.invalidCallback
        }
        if let error = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "error" })?.value {
            throw OpenAIOAuthError.authorizationFailed(error)
        }
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            throw OpenAIOAuthError.invalidCallback
        }
        return try await exchange(
            code: code,
            verifier: verifier,
            redirectURI: redirectServer.redirectURI
        )
    }

    static func refresh(refreshToken: String) async throws -> OpenAIOAuthTokens {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ]).data(using: .utf8)
        return try await decodeTokenResponse(request)
    }

    private static func exchange(
        code: String,
        verifier: String,
        redirectURI: String
    ) async throws -> OpenAIOAuthTokens {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ]).data(using: .utf8)
        return try await decodeTokenResponse(request)
    }

    private static func decodeTokenResponse(_ request: URLRequest) async throws -> OpenAIOAuthTokens {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIOAuthError.invalidTokenResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenAIOAuthError.http(http.statusCode, body)
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = object["access_token"] as? String,
              !accessToken.isEmpty else {
            throw OpenAIOAuthError.invalidTokenResponse
        }
        let idToken = object["id_token"] as? String ?? ""
        let refreshToken = object["refresh_token"] as? String
        let expiresAt: Date? = {
            if let expiresIn = object["expires_in"] as? NSNumber {
                return Date().addingTimeInterval(expiresIn.doubleValue)
            }
            return expiresAt(from: accessToken)
        }()
        return OpenAIOAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: idToken,
            accountID: accountID(fromIDToken: idToken),
            expiresAt: expiresAt
        )
    }

    private static func formEncoded(_ values: [String: String]) -> String {
        values.sorted(by: { $0.key < $1.key }).map { key, value in
            "\(formEscape(key))=\(formEscape(value))"
        }.joined(separator: "&")
    }

    private static func formEscape(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

struct OpenAIOAuthTokens: Sendable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String
    let accountID: String?
    let expiresAt: Date?
}

private final class LoopbackRedirectServer {
    let port: UInt16
    let redirectURI: String
    private let queue = DispatchQueue(label: "com.qingji.app.oauth-loopback")
    private var listener: NWListener?

    private init(port: UInt16, listener: NWListener) {
        self.port = port
        self.redirectURI = "http://localhost:\(port)/auth/callback"
        self.listener = listener
    }

    static func bind() async throws -> LoopbackRedirectServer {
        var lastError: Error?
        for port in OpenAIOAuth.loopbackPorts {
            do {
                return try await bind(port: port)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? OpenAIOAuthError.loopbackUnavailable
    }

    private static func bind(port: UInt16) async throws -> LoopbackRedirectServer {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw OpenAIOAuthError.loopbackUnavailable
        }
        let listener = try NWListener(using: .tcp, on: endpointPort)
        let server = LoopbackRedirectServer(port: port, listener: listener)
        try await withCheckedThrowingContinuation { continuation in
            var completed = false
            listener.stateUpdateHandler = { state in
                guard !completed else { return }
                switch state {
                case .ready:
                    completed = true
                    continuation.resume(returning: ())
                case .failed(let error):
                    completed = true
                    listener.cancel()
                    continuation.resume(throwing: error)
                case .cancelled:
                    completed = true
                    continuation.resume(throwing: OpenAIOAuthError.loopbackUnavailable)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak server] connection in
                server?.handle(connection)
            }
            listener.start(queue: server.queue)
        }
        return server
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var combined = buffer
            if let data { combined.append(data) }
            if let headerEnd = combined.range(of: Data("\r\n\r\n".utf8)) {
                let header = Data(combined[..<headerEnd.lowerBound])
                self.respond(to: connection, requestHeader: header)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receive(connection, buffer: combined)
            }
        }
    }

    private func respond(to connection: NWConnection, requestHeader: Data) {
        guard let text = String(data: requestHeader, encoding: .utf8),
              let requestLine = text.components(separatedBy: "\r\n").first,
              let rawPath = requestLine.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: "http://localhost\(rawPath)"),
              components.path == "/auth/callback" else {
            send(connection, status: "404 Not Found", headers: [], body: "")
            return
        }
        var callback = URLComponents(string: OpenAIOAuth.callbackURI)!
        callback.queryItems = components.queryItems
        guard let callbackURL = callback.url else {
            send(connection, status: "400 Bad Request", headers: [], body: "")
            return
        }
        send(
            connection,
            status: "302 Found",
            headers: ["Location: \(callbackURL.absoluteString)"],
            body: ""
        )
    }

    private func send(_ connection: NWConnection, status: String, headers: [String], body: String) {
        var response = "HTTP/1.1 \(status)\r\n"
        response += headers.joined(separator: "\r\n")
        if !headers.isEmpty { response += "\r\n" }
        response += "Cache-Control: no-store\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

enum OpenAIOAuthError: LocalizedError {
    case invalidCallback
    case authorizationFailed(String)
    case invalidTokenResponse
    case loopbackUnavailable
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidCallback:
            return "OAuth 回调无效或 state 校验失败，请重新登录。"
        case .authorizationFailed(let reason):
            return "OAuth 授权失败：\(reason)"
        case .invalidTokenResponse:
            return "OAuth Token 响应无法识别。"
        case .loopbackUnavailable:
            return "无法监听 OAuth 本机回调端口 1455/1457，请关闭旧授权后重试。"
        case .http(let status, let body):
            let compact = body.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            return "OAuth 请求失败（\(status)）\(compact.isEmpty ? "" : "：\(String(compact.prefix(180)))")"
        }
    }
}

@MainActor
private final class AuthenticationSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let url: URL
    private var session: ASWebAuthenticationSession?

    init(url: URL) {
        self.url = url
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let current = ASWebAuthenticationSession(url: url, callbackURLScheme: OpenAIOAuth.callbackScheme) { [weak self] callback, error in
                self?.session = nil
                if let error {
                    continuation.resume(throwing: error)
                } else if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: OpenAIOAuthError.invalidCallback)
                }
            }
            current.presentationContextProvider = self
            current.prefersEphemeralWebBrowserSession = false
            session = current
            guard current.start() else {
                session = nil
                continuation.resume(throwing: OpenAIOAuthError.invalidCallback)
                return
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: { $0.isKeyWindow })
            ?? scenes.flatMap(\.windows).first
            ?? ASPresentationAnchor()
    }
}
