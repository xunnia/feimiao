import Foundation

/// Keyless public-web fallback for Claude and OpenAI-compatible gateways.
/// Official Responses/Codex accounts use their native web-search tool instead;
/// this adapter is only used when the provider has no equivalent tool.
enum AIWebSearch {
    static func shouldSearch(_ query: String) -> Bool {
        let keywords = [
            "最新", "新闻", "今天", "天气", "价格", "汇率", "官网", "政策",
            "资料", "搜索", "网上", "现在", "近期", "发布", "版本"
        ]
        let value = query.lowercased()
        return keywords.contains(where: { value.contains($0) })
    }

    static func search(_ query: String, maxResults: Int = 5) async throws -> [AIChatSource] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, maxResults > 0 else { return [] }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.duckduckgo.com"
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "q", value: normalized),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "no_redirect", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1"),
        ]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AIWebSearchError.unavailable
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIWebSearchError.invalidResponse
        }

        var result: [AIChatSource] = []
        var seen = Set<String>()
        func add(url rawURL: String?, title rawTitle: String?, snippet rawSnippet: String?) {
            guard result.count < maxResults,
                  let rawURL,
                  rawURL.hasPrefix("http"),
                  seen.insert(rawURL).inserted else { return }
            let host = URL(string: rawURL)?.host?.replacingOccurrences(of: "www.", with: "") ?? "网页来源"
            let title = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let snippet = rawSnippet?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            result.append(AIChatSource(title: title.isEmpty ? host : title, url: rawURL, snippet: snippet))
        }
        add(
            url: root["AbstractURL"] as? String,
            title: root["Heading"] as? String,
            snippet: root["AbstractText"] as? String
        )
        func walk(_ value: Any?) {
            guard result.count < maxResults else { return }
            if let list = value as? [Any] {
                list.forEach(walk)
            } else if let map = value as? [String: Any] {
                if let nested = map["Topics"] { walk(nested); return }
                add(
                    url: (map["FirstURL"] as? String) ?? (map["url"] as? String),
                    title: (map["Heading"] as? String) ?? (map["title"] as? String),
                    snippet: (map["Text"] as? String) ?? (map["snippet"] as? String)
                )
            }
        }
        walk(root["RelatedTopics"])
        return result
    }
}

enum AIWebSearchError: LocalizedError {
    case unavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unavailable: return "公开搜索暂时不可用。"
        case .invalidResponse: return "公开搜索返回格式无法识别。"
        }
    }
}
