import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_http_transport.dart';
import 'ai_logger.dart';
import 'ai_provider_config.dart';

/// A source returned by either the provider-native search tool or the local
/// adapter used for non-Responses providers.
class AiWebSource {
  final String title;
  final String url;
  final String snippet;

  const AiWebSource({
    required this.title,
    required this.url,
    this.snippet = '',
  });

  @override
  bool operator ==(Object other) =>
      other is AiWebSource && other.url == url && other.title == title;

  @override
  int get hashCode => Object.hash(title, url);
}

class AiWebSearchResponse {
  final String query;
  final List<AiWebSource> sources;

  const AiWebSearchResponse({required this.query, required this.sources});

  bool get hasSources => sources.isNotEmpty;
}

abstract interface class AiWebSearchAdapter {
  Future<AiWebSearchResponse> search(
    String query, {
    int maxResults = 5,
  });
}

/// A keyless search adapter for providers that do not implement Responses
/// `web_search`. DuckDuckGo's JSON endpoint returns short public snippets and
/// URLs, so the app can give the model evidence without proxying ledger data.
class DuckDuckGoSearchAdapter implements AiWebSearchAdapter {
  final AiHttpTransport _transport;
  final Duration timeout;

  DuckDuckGoSearchAdapter(
      {http.Client? client, this.timeout = const Duration(seconds: 3)})
      : _transport = AiHttpTransport(client: client);

  @override
  Future<AiWebSearchResponse> search(
    String query, {
    int maxResults = 5,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return const AiWebSearchResponse(query: '', sources: []);
    }
    final uri = Uri.https('api.duckduckgo.com', '/', {
      'q': normalized,
      'format': 'json',
      'no_html': '1',
      'no_redirect': '1',
      'skip_disambig': '1',
    });
    final response = await _transport.get(
      uri,
      headers: const {'Accept': 'application/json'},
      timeout: timeout,
    );
    // DuckDuckGo may return 202 (accepted) while still including a complete
    // JSON payload. Treat every 2xx response as successful instead of turning
    // valid public results into a false "search unavailable" warning.
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiWebSearchException('搜索服务返回 ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Object?;
    if (decoded is! Map) {
      throw const AiWebSearchException('搜索响应格式错误');
    }

    final sources = <AiWebSource>[];
    final seenUrls = <String>{};
    void addSource(Object? raw, {String? fallbackTitle}) {
      if (raw is! Map || sources.length >= maxResults) return;
      final url = (raw['FirstURL'] ?? raw['first_url'] ?? raw['url'])
          ?.toString()
          .trim();
      final text =
          (raw['Text'] ?? raw['text'] ?? raw['snippet'])?.toString().trim();
      if (url == null || url.isEmpty || !url.startsWith('http')) return;
      if (!seenUrls.add(url)) return;
      final title = (raw['Heading'] ?? raw['title'] ?? fallbackTitle ?? '')
          .toString()
          .trim();
      sources.add(
        AiWebSource(
          title: title.isEmpty ? _hostTitle(url) : title,
          url: url,
          snippet: text ?? '',
        ),
      );
    }

    final root = Map<String, dynamic>.from(decoded);
    addSource({
      'FirstURL': root['AbstractURL'],
      'Text': root['AbstractText'],
      'Heading': root['Heading'],
    });
    final answer = root['Answer'];
    if (sources.isEmpty && answer is String && answer.trim().isNotEmpty) {
      final url = root['AbstractURL']?.toString().trim() ?? '';
      if (url.startsWith('http')) {
        addSource(
            {'FirstURL': url, 'Text': answer, 'Heading': root['Heading']});
      }
    }

    void walkTopics(Object? value) {
      if (sources.length >= maxResults) return;
      if (value is List) {
        for (final item in value) {
          walkTopics(item);
          if (sources.length >= maxResults) return;
        }
      } else if (value is Map) {
        if (value.containsKey('Topics')) {
          walkTopics(value['Topics']);
        } else {
          addSource(value);
        }
      }
    }

    walkTopics(root['RelatedTopics']);
    return AiWebSearchResponse(query: normalized, sources: sources);
  }

  static String _hostTitle(String rawUrl) {
    final host = Uri.tryParse(rawUrl)?.host ?? '';
    return host.isEmpty ? '网页来源' : host.replaceFirst(RegExp(r'^www\.'), '');
  }
}

class AiWebSearchException implements Exception {
  final String message;

  const AiWebSearchException(this.message);

  @override
  String toString() => 'AiWebSearchException: $message';
}

/// Search policy and prompt/citation formatting shared by all chat paths.
class AiWebSearchContext {
  final AiWebSearchResponse? response;
  final String? warning;

  const AiWebSearchContext({this.response, this.warning});

  bool get hasSources => response?.hasSources ?? false;

  String get promptBlock {
    final result = response;
    if (result == null) {
      return warning == null ? '' : '【联网搜索】$warning';
    }
    if (!result.hasSources) {
      return '【联网搜索】未找到可靠的公开来源。请如实说明这一点，不要编造网页内容。';
    }
    final lines = <String>[
      '【联网搜索结果】',
      '搜索词：${result.query}',
      '以下内容是公开网页摘要，仅作证据参考；不要把摘要之外的内容当成事实。',
    ];
    for (var i = 0; i < result.sources.length; i++) {
      final source = result.sources[i];
      lines.add('${i + 1}. ${source.title}');
      if (source.snippet.isNotEmpty) lines.add('摘要：${source.snippet}');
      lines.add('来源：${source.url}');
    }
    lines.add('回答涉及搜索结果时，请在对应句末使用 [1]、[2] 等编号。');
    return lines.join('\n');
  }

  String annotateAnswer(String answer) =>
      formatAnswerWithSources(answer, response?.sources ?? const []);

  static String encodeSources(Iterable<AiWebSource> sources) => jsonEncode([
        for (final source in sources)
          {
            'title': source.title,
            'url': source.url,
            'snippet': source.snippet,
          },
      ]);

  static List<AiWebSource> decodeSources(Object? raw) {
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty) return const [];
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) return const [];
      final result = <AiWebSource>[];
      final seen = <String>{};
      for (final item in decoded) {
        if (item is! Map) continue;
        final url = item['url']?.toString().trim() ?? '';
        if (!url.startsWith('http') || !seen.add(url)) continue;
        result.add(AiWebSource(
          title: item['title']?.toString() ?? '',
          url: url,
          snippet: item['snippet']?.toString() ?? '',
        ));
      }
      return List<AiWebSource>.unmodifiable(result);
    } catch (_) {
      return const [];
    }
  }

  /// Extract citations from both public Responses responses and the private
  /// Codex Responses stream. The two backends do not use the same shape:
  /// public responses commonly put `url_citation` annotations on output text,
  /// while Codex emits `web_search_call.action.sources` items. Keeping the
  /// walker here prevents the streaming and buffered chat paths from drifting.
  static List<AiWebSource> extractResponseSources(Object? payload) {
    final result = <AiWebSource>[];
    final seen = <String>{};

    void add(Object? raw, {bool sourceContext = false}) {
      if (raw is! Map) return;
      final type = raw['type']?.toString().trim().toLowerCase() ?? '';
      final isCitation = type.contains('url_citation');
      final isSource = type == 'source' || type == 'web_search_source';
      if (!sourceContext && !isCitation && !isSource) return;
      final url = (raw['url'] ?? raw['uri'] ?? raw['link'] ?? raw['source_url'])
          ?.toString()
          .trim();
      if (url == null || url.isEmpty || !url.startsWith('http')) return;
      if (!seen.add(url)) return;
      final title = (raw['title'] ?? raw['name'] ?? raw['source_name'])
              ?.toString()
              .trim() ??
          '';
      final snippet = (raw['snippet'] ?? raw['text'] ?? raw['description'])
              ?.toString()
              .trim() ??
          '';
      result.add(
        AiWebSource(
          title: title.isEmpty ? _hostTitle(url) : title,
          url: url,
          snippet: snippet,
        ),
      );
    }

    void walk(Object? value, {bool sourceContext = false}) {
      if (value is Map) {
        final type = value['type']?.toString().trim().toLowerCase() ?? '';
        final isSearchItem = type.contains('web_search');
        add(value, sourceContext: sourceContext || isSearchItem);

        final annotations = value['annotations'];
        if (annotations is List) {
          for (final item in annotations) {
            walk(item, sourceContext: true);
          }
        }
        for (final key in const ['sources', 'results']) {
          final nested = value[key];
          if (nested != null) walk(nested, sourceContext: true);
        }
        final action = value['action'];
        if (action != null) walk(action, sourceContext: true);
        for (final key in const [
          'response',
          'output',
          'content',
          'item',
          'data',
        ]) {
          final nested = value[key];
          if (nested != null) walk(nested, sourceContext: sourceContext);
        }
      } else if (value is List) {
        for (final item in value) {
          walk(item, sourceContext: sourceContext);
        }
      }
    }

    walk(payload);
    return result;
  }

  static String formatAnswerWithSources(
    String answer,
    Iterable<AiWebSource> sources,
  ) {
    // Sources are structured metadata rendered in the answer action row and
    // draggable source sheet. Never append a second textual citation list to
    // the body, and remove a model-generated trailing Sources/来源 section.
    return stripTrailingSourceSection(answer);
  }

  static String stripTrailingSourceSection(String answer) {
    final lines = answer.trim().split('\n');
    if (lines.isEmpty) return '';
    final heading = RegExp(
      r'^\s*(?:#{1,6}\s*)?(?:来源|参考来源|参考资料|参考链接|sources?|references?)\s*[:：]?\s*$',
      caseSensitive: false,
    );
    final inlineHeading = RegExp(
      r'^\s*(?:#{1,6}\s*)?(?:来源|参考来源|参考资料|参考链接|sources?|references?)\s*[:：]\s*(?:\[?\d+\]?|https?://|[-*•])',
      caseSensitive: false,
    );
    var cut = -1;
    for (var index = lines.length - 1; index >= 0; index--) {
      final line = lines[index];
      if (heading.hasMatch(line) || inlineHeading.hasMatch(line)) {
        cut = index;
        break;
      }
    }
    if (cut < 0) return lines.join('\n').trim();

    final trailing = lines.skip(cut).join('\n');
    final looksLikeSources = RegExp(
      r'(https?://|\[[0-9]+\]|(?:^|\n)\s*(?:[-*•]|[0-9]+[.)])\s+)',
      caseSensitive: false,
    ).hasMatch(trailing);
    if (!looksLikeSources && cut != lines.length - 1) {
      return lines.join('\n').trim();
    }
    return lines.take(cut).join('\n').trimRight();
  }

  static String _hostTitle(String rawUrl) {
    final host = Uri.tryParse(rawUrl)?.host ?? '';
    return host.isEmpty ? '网页来源' : host.replaceFirst(RegExp(r'^www\.'), '');
  }

  static Future<AiWebSearchContext> prepare({
    required String question,
    required AiProviderConfig config,
    AiWebSearchAdapter? adapter,
  }) async {
    if (!config.webSearchEnabled || config.shouldUseResponses) {
      return const AiWebSearchContext();
    }
    if (!shouldSearchQuestion(question)) return const AiWebSearchContext();
    try {
      final response = await (adapter ?? DuckDuckGoSearchAdapter()).search(
        question,
      );
      return AiWebSearchContext(response: response);
    } on Object catch (error) {
      return AiWebSearchContext(warning: '暂时不可用（${_shortError(error)}）。');
    }
  }

  static bool shouldSearchQuestion(String question) {
    final value = question.trim().toLowerCase();
    if (value.isEmpty) return false;
    // Ledger questions are answered from the local repository. Never send
    // them to a public search endpoint merely because they contain "今天" or
    // "多少钱".
    if (RegExp(r'(账本|记账|账单|支出|收入|消费|预算|余额|分类|花了|本月|本周|上月|上周)')
        .hasMatch(value)) {
      return false;
    }
    return RegExp(
      r'(最新|今天|现在|近期|新闻|天气|价格|多少钱|官网|搜索|查一下|网上|联网|开源|github|版本|政策|规定|股价|汇率|比赛|发布|更新|教程|是什么|怎么用)',
    ).hasMatch(value);
  }

  static String _shortError(Object error) {
    final raw = AiLogger.sanitizeErrorForDisplay(error.toString())
        .replaceFirst(RegExp(r'^.*?:\s*'), '')
        .trim();
    return raw.length > 80 ? '${raw.substring(0, 80)}…' : raw;
  }
}
