import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/core/ai/web_search.dart';

void main() {
  test('只对明显的联网问题触发搜索', () {
    expect(AiWebSearchContext.shouldSearchQuestion('我今天花了多少钱'), isFalse);
    expect(AiWebSearchContext.shouldSearchQuestion('今天北京天气怎么样'), isTrue);
    expect(AiWebSearchContext.shouldSearchQuestion('帮我看看本月餐饮'), isFalse);
    expect(
        AiWebSearchContext.shouldSearchQuestion('GitHub 上最新的 GPT 桌面端'), isTrue);
  });

  test('Responses 账号不走本地搜索适配器', () async {
    var called = false;
    final adapter = _RecordingAdapter(() {
      called = true;
      return const AiWebSearchResponse(query: 'x', sources: []);
    });
    final context = await AiWebSearchContext.prepare(
      question: '最新新闻',
      config: const AiProviderConfig(
        type: AiProviderType.custom,
        apiKey: 'key',
        baseUrl: 'https://api.example.com/v1',
        model: 'gpt-5',
        endpointType: AiEndpointType.responses,
        webSearchEnabled: true,
      ),
      adapter: adapter,
    );
    expect(called, isFalse);
    expect(context.promptBlock, isEmpty);
  });

  test('DuckDuckGo JSON 结果解析为来源列表', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'api.duckduckgo.com');
      expect(request.url.queryParameters['q'], '最新 GPT 新闻');
      return http.Response(
        jsonEncode({
          'Heading': '摘要标题',
          'AbstractText': '摘要内容',
          'AbstractURL': 'https://example.com/abstract',
          'RelatedTopics': [
            {
              'Text': '相关结果',
              'FirstURL': 'https://example.com/related',
            },
          ],
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });
    final response = await DuckDuckGoSearchAdapter(client: client).search(
      '最新 GPT 新闻',
    );
    expect(response.sources.map((source) => source.url), [
      'https://example.com/abstract',
      'https://example.com/related',
    ]);
    final context = AiWebSearchContext(response: response);
    expect(context.promptBlock, contains('摘要内容'));
    expect(context.annotateAnswer('结论'), '结论');
  });

  test('正文移除模型生成的尾部来源清单但保留正常段落', () {
    expect(
      AiWebSearchContext.stripTrailingSourceSection(
        '第一段结论。\n\n来源：\n[1] 官方文档\n[2] 新闻报道',
      ),
      '第一段结论。',
    );
    expect(
      AiWebSearchContext.stripTrailingSourceSection(
        '第一段结论。\n\nSources:\n- https://example.com/docs',
      ),
      '第一段结论。',
    );
    expect(
      AiWebSearchContext.stripTrailingSourceSection('这句话讨论信息来源，但不是清单。'),
      '这句话讨论信息来源，但不是清单。',
    );
  });

  test('结构化来源可随回答持久化并恢复去重', () {
    const sources = [
      AiWebSource(title: 'A', url: 'https://a.example', snippet: 'one'),
      AiWebSource(title: 'A again', url: 'https://a.example'),
      AiWebSource(title: 'B', url: 'https://b.example'),
    ];
    final restored = AiWebSearchContext.decodeSources(
      AiWebSearchContext.encodeSources(sources),
    );
    expect(restored.map((source) => source.url), [
      'https://a.example',
      'https://b.example',
    ]);
    expect(restored.first.snippet, 'one');
  });

  test('DuckDuckGo 202 仍解析有效 JSON 结果', () async {
    final client = MockClient((request) async {
      return http.Response.bytes(
        utf8.encode(jsonEncode({
          'RelatedTopics': [
            {
              'Text': '已接受的结果',
              'FirstURL': 'https://example.com/accepted',
            },
          ],
        })),
        202,
      );
    });

    final response = await DuckDuckGoSearchAdapter(client: client).search('x');

    expect(response.sources.single.url, 'https://example.com/accepted');
  });

  test('搜索失败会留下诚实的不可用提示', () async {
    final adapter = _ThrowingAdapter();
    final context = await AiWebSearchContext.prepare(
      question: '最新天气',
      config: const AiProviderConfig(
        type: AiProviderType.deepseek,
        apiKey: 'key',
        baseUrl: AiProviderConfig.deepSeekBaseUrl,
        model: 'deepseek-v4-flash',
        endpointType: AiEndpointType.chatCompletions,
        webSearchEnabled: true,
      ),
      adapter: adapter,
    );
    expect(context.promptBlock, contains('暂时不可用'));
  });

  test('服务商搜索开关会进入 JSON 且可以恢复', () {
    final provider = AiConfiguredProvider(
      id: 'custom-1',
      type: AiProviderType.custom,
      displayName: '中转',
      baseUrl: 'https://gateway.example/v1',
      apiKey: 'key',
      model: 'claude-3-7-sonnet',
      webSearchEnabled: true,
    );
    final restored = AiConfiguredProvider.fromJson(
      provider.toJson(),
      apiKey: 'key',
    );
    expect(restored.webSearchEnabled, isTrue);
    expect(restored.toConfig().webSearchEnabled, isTrue);
  });

  test('Codex web_search_call action sources 会被解析为引用', () {
    final sources = AiWebSearchContext.extractResponseSources({
      'type': 'response.output_item.done',
      'item': {
        'type': 'web_search_call',
        'action': {
          'type': 'search',
          'sources': [
            {
              'type': 'source',
              'title': 'OpenAI Codex',
              'url': 'https://example.com/codex',
              'snippet': 'Codex search source',
            },
          ],
        },
      },
    });

    expect(sources, hasLength(1));
    expect(sources.single.title, 'OpenAI Codex');
    expect(sources.single.url, 'https://example.com/codex');
    expect(sources.single.snippet, 'Codex search source');
  });
}

class _RecordingAdapter implements AiWebSearchAdapter {
  final AiWebSearchResponse Function() callback;

  _RecordingAdapter(this.callback);

  @override
  Future<AiWebSearchResponse> search(String query,
          {int maxResults = 5}) async =>
      callback();
}

class _ThrowingAdapter implements AiWebSearchAdapter {
  @override
  Future<AiWebSearchResponse> search(String query, {int maxResults = 5}) {
    throw const AiWebSearchException('网络不可用');
  }
}
