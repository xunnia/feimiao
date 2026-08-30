import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_exception.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/core/ai/llm_query_v2.dart';

class _ResponsesSseServer {
  final HttpServer server;
  final Future<Map<String, dynamic>> requestBody;

  const _ResponsesSseServer({
    required this.server,
    required this.requestBody,
  });

  String get baseUrl => 'http://${server.address.address}:${server.port}/v1';
}

Future<_ResponsesSseServer> _serveResponsesSse(String payload) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final requestBody = Completer<Map<String, dynamic>>();
  server.listen((request) async {
    final raw = await utf8.decoder.bind(request).join();
    requestBody.complete(jsonDecode(raw) as Map<String, dynamic>);
    final bytes = utf8.encode(payload);
    request.response.headers.contentType =
        ContentType('text', 'event-stream', charset: 'utf-8');
    request.response.headers.contentLength = bytes.length;
    request.response.headers.set(HttpHeaders.connectionHeader, 'close');
    request.response.add(bytes);
    await request.response.close();
    // Do not await graceful server shutdown here: it waits for the client
    // socket while the client is still waiting for this SSE response to end.
    unawaited(server.close(force: true));
  });
  return _ResponsesSseServer(server: server, requestBody: requestBody.future);
}

void main() {
  const config = AiProviderConfig(
    type: AiProviderType.custom,
    apiKey: 'test-key',
    baseUrl: 'https://gateway.example/v1/',
    model: 'gpt-5',
    endpointType: AiEndpointType.responses,
    reasoningEffort: AiReasoningEffort.high,
  );

  test('Responses 流式请求使用 /v1/responses、stream 与 reasoning effort', () {
    final body = LlmQueryV2.responsesStreamBodyForTest(
      config: config,
      messages: const [
        {'role': 'system', 'content': '系统规则'},
        {'role': 'system', 'content': '账目上下文'},
        {'role': 'user', 'content': '第一句问题'},
        {'role': 'assistant', 'content': '上一句回答'},
        {'role': 'user', 'content': '第二句问题'},
      ],
    );

    expect(
      LlmQueryV2.streamUriForTest(config).toString(),
      'https://gateway.example/v1/responses',
    );
    expect(body['model'], 'gpt-5');
    expect(body['stream'], isTrue);
    expect(body['store'], isFalse);
    expect(body['max_output_tokens'], 8192);
    expect(body['instructions'], '系统规则\n\n账目上下文');
    expect(
      body['input'],
      '第一句问题\n\nassistant: 上一句回答\n\n第二句问题',
    );
    expect(body['reasoning'], {'effort': 'high'});
  });

  test('官方 Codex 的非流式调用也强制使用 stream=true', () {
    const codex = AiProviderConfig(
      type: AiProviderType.custom,
      apiKey: 'access-token',
      baseUrl: AiProviderConfig.openAiCodexBaseUrl,
      model: 'gpt-5.4',
      endpointType: AiEndpointType.responses,
      authMethod: AiAuthMethod.oauth,
      oauthAccountId: 'acct-test',
    );
    final body = LlmQueryV2.responsesTransportBodyForTest(
      config: codex,
      body: const {'model': 'gpt-5.4', 'input': 'ping', 'stream': false},
    );
    expect(body['stream'], isTrue);

    final regular = LlmQueryV2.responsesTransportBodyForTest(
      config: config,
      body: const {'model': 'gpt-5', 'input': 'ping', 'stream': false},
    );
    expect(regular['stream'], isFalse);
  });

  test('开启联网搜索时 Responses 请求携带 web_search 工具', () {
    final searchConfig = config.copyWith(webSearchEnabled: true);
    final body = LlmQueryV2.responsesStreamBodyForTest(
      config: searchConfig,
      messages: const [
        {'role': 'user', 'content': '最新 GPT 新闻'},
      ],
    );
    expect(body['tools'], [
      {'type': 'web_search'},
    ]);
  });

  test('官方 OpenAI Responses 使用 preview 工具并请求结构化来源', () {
    const official = AiProviderConfig(
      type: AiProviderType.custom,
      apiKey: 'test-key',
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-5',
      endpointType: AiEndpointType.responses,
      webSearchEnabled: true,
    );
    final body = LlmQueryV2.responsesStreamBodyForTest(
      config: official,
      messages: const [
        {'role': 'user', 'content': '最新新闻'},
      ],
    );

    expect(body['tools'], [
      {'type': 'web_search_preview'},
    ]);
    expect(body['include'], ['web_search_call.action.sources']);
  });

  test('Codex OAuth Responses 明确开启 live web access', () {
    const oauth = AiProviderConfig(
      type: AiProviderType.custom,
      apiKey: 'oauth-access-token',
      baseUrl: AiProviderConfig.openAiCodexBaseUrl,
      model: 'gpt-5.4',
      endpointType: AiEndpointType.responses,
      authMethod: AiAuthMethod.oauth,
      oauthAccountId: 'acct-1',
      webSearchEnabled: true,
    );
    final body = LlmQueryV2.responsesStreamBodyForTest(
      config: oauth,
      messages: const [
        {'role': 'user', 'content': '最新新闻'},
      ],
    );

    expect(body['tools'], [
      {
        'type': 'web_search',
        'external_web_access': true,
        'search_context_size': 'high',
      },
    ]);
    expect(body.containsKey('include'), isFalse);
  });

  test('ChatGPT OAuth 使用 Codex Responses wire contract', () {
    const oauth = AiProviderConfig(
      type: AiProviderType.custom,
      apiKey: 'oauth-access-token',
      baseUrl: AiProviderConfig.openAiCodexBaseUrl,
      model: 'gpt-5.4',
      endpointType: AiEndpointType.responses,
      authMethod: AiAuthMethod.oauth,
      oauthAccountId: 'acct-1',
      reasoningEffort: AiReasoningEffort.high,
    );
    final body = LlmQueryV2.responsesStreamBodyForTest(
      config: oauth,
      messages: const [
        {'role': 'system', 'content': '必须输出简洁中文'},
        {'role': 'user', 'content': '你好'},
        {'role': 'assistant', 'content': '你好，我是喵助手'},
      ],
    );

    expect(LlmQueryV2.streamUriForTest(oauth).toString(),
        'https://chatgpt.com/backend-api/codex/responses');
    expect(body['instructions'], '必须输出简洁中文');
    expect(body['store'], isFalse);
    expect(body['stream'], isTrue);
    // The private Codex backend rejects the public Responses
    // `max_output_tokens` parameter; the official client lets the model
    // choose its own output budget.
    expect(body.containsKey('max_output_tokens'), isFalse);
    expect(body['reasoning'], {'effort': 'high'});
    expect(body['input'], [
      {
        'type': 'message',
        'role': 'user',
        'content': [
          {'type': 'input_text', 'text': '你好'},
        ],
      },
      {
        'type': 'message',
        'role': 'assistant',
        'content': [
          {'type': 'output_text', 'text': '你好，我是喵助手'},
        ],
      },
    ]);
  });

  test('三类协议都保留三张图片的数量、顺序与各自 wire format', () {
    const messages = <Map<String, dynamic>>[
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': '依次看这三张图'},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/jpeg;base64,Zmlyc3Q='},
          },
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/png;base64,c2Vjb25k'},
          },
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/webp;base64,dGhpcmQ='},
          },
        ],
      },
    ];

    final responses = LlmQueryV2.responsesStreamBodyForTest(
      config: config,
      messages: messages,
    );
    final responseContent =
        ((responses['input'] as List).single as Map)['content'] as List;
    expect(responseContent.map((item) => (item as Map)['type']).toList(), [
      'input_text',
      'input_image',
      'input_image',
      'input_image',
    ]);
    expect(
      responseContent
          .skip(1)
          .map((item) => (item as Map)['image_url'])
          .toList(),
      [
        'data:image/jpeg;base64,Zmlyc3Q=',
        'data:image/png;base64,c2Vjb25k',
        'data:image/webp;base64,dGhpcmQ=',
      ],
    );

    final chat = LlmQueryV2.chatCompletionsStreamBodyForTest(
      config: config.copyWith(endpointType: AiEndpointType.chatCompletions),
      messages: messages,
    );
    final chatContent =
        (((chat['messages'] as List).single as Map)['content'] as List);
    expect(chatContent.where((item) => (item as Map)['type'] == 'image_url'),
        hasLength(3));
    expect(
      chatContent
          .where((item) => (item as Map)['type'] == 'image_url')
          .map((item) => ((item as Map)['image_url'] as Map)['url'])
          .toList(),
      [
        'data:image/jpeg;base64,Zmlyc3Q=',
        'data:image/png;base64,c2Vjb25k',
        'data:image/webp;base64,dGhpcmQ=',
      ],
    );

    final claude = LlmQueryV2.messageForClaudeForTest(messages.single);
    final claudeContent = claude['content'] as List;
    final imageBlocks = claudeContent
        .where((item) => (item as Map)['type'] == 'image')
        .cast<Map>();
    expect(imageBlocks, hasLength(3));
    expect(
      imageBlocks.map((item) => (item['source'] as Map)['media_type']).toList(),
      ['image/jpeg', 'image/png', 'image/webp'],
    );
    expect(
      imageBlocks.map((item) => (item['source'] as Map)['data']).toList(),
      ['Zmlyc3Q=', 'c2Vjb25k', 'dGhpcmQ='],
    );
  });

  test('完整旧 endpoint 也会归一到模型目录和 Responses 根路径', () {
    const legacy = AiProviderConfig(
      type: AiProviderType.custom,
      apiKey: 'test-key',
      baseUrl: 'https://gateway.example/v1/chat/completions',
      model: 'gpt-5',
      endpointType: AiEndpointType.responses,
    );
    expect(legacy.modelsUri.toString(), 'https://gateway.example/v1/models');
    expect(
      legacy.responsesUri.toString(),
      'https://gateway.example/v1/responses',
    );
  });

  test('Responses 将 Max/Ultracode 映射为合法的 xhigh', () {
    final max = LlmQueryV2.responsesStreamBodyForTest(
      config: config.copyWith(reasoningEffort: AiReasoningEffort.max),
      messages: const [
        {'role': 'user', 'content': '你好'},
      ],
    );
    final ultra = LlmQueryV2.responsesStreamBodyForTest(
      config: config.copyWith(reasoningEffort: AiReasoningEffort.ultra),
      messages: const [
        {'role': 'user', 'content': '你好'},
      ],
    );
    expect(max['reasoning'], {'effort': 'xhigh'});
    expect(ultra['reasoning'], {'effort': 'xhigh'});
    expect(ultra['max_output_tokens'], 16384);
  });

  test('Codex OAuth 将 Max/Ultracode 映射为官方 max 且省略输出上限', () {
    const oauth = AiProviderConfig(
      type: AiProviderType.custom,
      apiKey: 'oauth-access-token',
      baseUrl: AiProviderConfig.openAiCodexBaseUrl,
      model: 'gpt-5.4',
      endpointType: AiEndpointType.responses,
      authMethod: AiAuthMethod.oauth,
      oauthAccountId: 'acct-1',
      reasoningEffort: AiReasoningEffort.ultra,
    );
    final body = LlmQueryV2.responsesStreamBodyForTest(
      config: oauth,
      messages: const [
        {'role': 'user', 'content': '你好'},
      ],
    );
    expect(body['reasoning'], {'effort': 'max'});
    expect(body.containsKey('max_output_tokens'), isFalse);
  });

  test('Responses 完成事件可以作为无 delta 网关的正文兜底', () {
    const payload =
        '{"type":"response.completed","response":{"output":[{"type":"message","content":[{"type":"output_text","text":"完成正文"}]}]}}';
    expect(
      LlmQueryV2.responsesCompletedTextForTest(payload),
      '完成正文',
    );
  });

  test('Responses SSE 只拼接文本增量，不重复 done 的完整文本', () {
    final payloads = <String>[
      '{"type":"response.output_text.delta","delta":"你好"}',
      '{"type":"response.reasoning_summary_text.delta","delta":"不展示"}',
      '{"type":"response.output_text.done","text":"你好，世界"}',
      '{"type":"response.output_text.delta","delta":"，世界"}',
      '[DONE]',
    ];

    final answer = StringBuffer();
    for (final payload in payloads) {
      final delta = LlmQueryV2.responsesStreamDeltaForTest(payload);
      if (delta != null) answer.write(delta);
    }

    expect(answer.toString(), '你好，世界');
  });

  test('Responses 只展示模型提供的 reasoning summary 增量且忽略 done 重复', () {
    expect(
      LlmQueryV2.responsesReasoningSummaryDeltaForTest({
        'type': 'response.reasoning_summary_text.delta',
        'delta': '先核对时间范围',
      }),
      '先核对时间范围',
    );
    expect(
      LlmQueryV2.responsesReasoningSummaryDeltaForTest({
        'type': 'response.reasoning_summary_part.added',
        'part': {'type': 'summary_text', 'text': '再比较两组数据'},
      }),
      '再比较两组数据',
    );
    expect(
      LlmQueryV2.responsesReasoningSummaryDeltaForTest({
        'type': 'response.reasoning_summary_text.done',
        'text': '先核对时间范围，再比较两组数据',
      }),
      isNull,
    );
    expect(
      LlmQueryV2.responsesReasoningSummaryDeltaForTest({
        'type': 'response.output_text.delta',
        'delta': '正文',
      }),
      isNull,
    );
  });

  test('兼容网关可用无 type 的 output_text 增量', () {
    expect(
      LlmQueryV2.responsesStreamDeltaForTest('{"output_text":"兼容增量"}'),
      '兼容增量',
    );
  });

  test('直连 DeepSeek 保留 Chat Completions SSE 并映射 Effort', () {
    const deepSeek = AiProviderConfig(
      type: AiProviderType.deepseek,
      apiKey: 'deepseek-key',
      baseUrl: AiProviderConfig.deepSeekBaseUrl,
      model: 'deepseek-v4-pro',
      endpointType: AiEndpointType.chatCompletions,
      reasoningEffort: AiReasoningEffort.ultra,
    );

    final body = LlmQueryV2.chatCompletionsStreamBodyForTest(
      config: deepSeek,
      messages: const [
        {'role': 'user', 'content': '你好'},
      ],
    );

    expect(
      LlmQueryV2.streamUriForTest(deepSeek).toString(),
      'https://api.deepseek.com/v1/chat/completions',
    );
    expect(body['stream'], isTrue);
    expect(body['thinking'], {'type': 'enabled'});
    expect(body['reasoning_effort'], 'max');
  });

  test('Responses 流内 failed 会通过 askStream 的 onError 返回', () async {
    final fixture = await _serveResponsesSse(
      'data: {"type":"response.failed","response":{"error":{"message":"上游失败"}}}\n\n',
    );
    final config = AiProviderConfig(
      type: AiProviderType.custom,
      apiKey: 'test-key',
      baseUrl: fixture.baseUrl,
      model: 'gpt-5',
      endpointType: AiEndpointType.responses,
    );
    final completed = Completer<AiException>();

    await LlmQueryV2.askStream(
      question: '你好',
      config: config,
      transactionsText: '',
      taskId: 'responses-failed-${fixture.server.port}',
      onChunk: (_) => fail('failed event must not emit text'),
      onDone: (_) => fail('failed event must not complete'),
      onError: completed.complete,
    );

    final error = await completed.future;
    expect(error, isA<AiServerException>());
    expect(error.message, '上游失败');
    final body = await fixture.requestBody;
    expect(body['stream'], isTrue);
    expect(body['reasoning'], isNull);
  });

  test('首包建连失败会用全新连接自动重试一次', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requestCount = 0;
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      requestCount++;
      if (requestCount == 1) {
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.destroy();
        return;
      }
      final payload = utf8.encode(
        'data: {"type":"response.output_text.delta","delta":"重试成功"}\n\n'
        'data: {"type":"response.completed","response":{"output":[{"type":"message","content":[{"type":"output_text","text":"重试成功"}]}]}}\n\n',
      );
      request.response.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');
      request.response.headers.contentLength = payload.length;
      request.response.add(payload);
      await request.response.close();
      unawaited(server.close(force: true));
    });
    final localConfig = config.copyWith(
      baseUrl: 'http://${server.address.address}:${server.port}/v1',
    );
    final completed = Completer<String>();

    await LlmQueryV2.askStream(
      question: '你好',
      config: localConfig,
      transactionsText: '',
      taskId: 'responses-first-packet-retry-${server.port}',
      onChunk: (_) {},
      onDone: completed.complete,
      onError: completed.completeError,
    );

    expect(await completed.future, '重试成功');
    expect(requestCount, 2);
  });

  test('已经收到任何可见流事件后不会重放整条请求', () {
    const networkError = AiNetworkException('连接中断');
    expect(
      LlmQueryV2.shouldRetryFirstPacketForTest(
        networkError,
        streamProducedOutput: true,
        alreadyRetried: false,
      ),
      isFalse,
    );
    expect(
      LlmQueryV2.shouldRetryFirstPacketForTest(
        networkError,
        streamProducedOutput: false,
        alreadyRetried: true,
      ),
      isFalse,
    );
    expect(
      LlmQueryV2.shouldRetryFirstPacketForTest(
        networkError,
        streamProducedOutput: false,
        alreadyRetried: false,
      ),
      isTrue,
    );
  });

  test('Responses 流内 incomplete 会通过 askStream 的 onError 返回', () async {
    final fixture = await _serveResponsesSse(
      'data: {"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"}}}\n\n',
    );
    final config = AiProviderConfig(
      type: AiProviderType.custom,
      apiKey: 'test-key',
      baseUrl: fixture.baseUrl,
      model: 'gpt-5',
      endpointType: AiEndpointType.responses,
    );
    final completed = Completer<AiException>();

    await LlmQueryV2.askStream(
      question: '你好',
      config: config,
      transactionsText: '',
      taskId: 'responses-incomplete-${fixture.server.port}',
      onChunk: (_) => fail('incomplete event must not emit text'),
      onDone: (_) => fail('incomplete event must not complete'),
      onError: completed.complete,
    );

    final error = await completed.future;
    expect(error, isA<AiTokenLimitException>());
    expect(error.message, contains('max_output_tokens'));
  });

  test('Responses delta 流会逐段渲染并以完整回答结束', () async {
    final fixture = await _serveResponsesSse(
      'data: {"type":"response.output_text.delta","delta":"你"}\n\n'
      'data: {"type":"response.output_text.delta","delta":"好"}\n\n'
      'data: {"type":"response.completed","response":{"output":[{"type":"message","content":[{"type":"output_text","text":"你好"}]}]}}\n\n',
    );
    final config = AiProviderConfig(
      type: AiProviderType.custom,
      apiKey: 'test-key',
      baseUrl: fixture.baseUrl,
      model: 'gpt-5',
      endpointType: AiEndpointType.responses,
    );
    final chunks = <String>[];
    final completed = Completer<String>();

    await LlmQueryV2.askStream(
      question: '你好',
      config: config,
      transactionsText: '',
      taskId: 'responses-delta-${fixture.server.port}',
      onChunk: chunks.add,
      onDone: completed.complete,
      onError: (error) => completed.completeError(error),
    );

    expect(await completed.future, '你好');
    expect(chunks, ['你', '好']);
  });

  test('Responses 完成事件比残缺 delta 更完整时优先采用完整正文', () async {
    final fixture = await _serveResponsesSse(
      'data: {"type":"response.output_text.delta","delta":"只收到前半"}\n\n'
      'data: {"type":"response.completed","response":{"output":[{"type":"message","content":[{"type":"output_text","text":"这是服务端完整正文"}]}]}}\n\n',
    );
    final config = AiProviderConfig(
      type: AiProviderType.custom,
      apiKey: 'test-key',
      baseUrl: fixture.baseUrl,
      model: 'gpt-5',
      endpointType: AiEndpointType.responses,
    );
    final completed = Completer<String>();

    await LlmQueryV2.askStream(
      question: '补全回答',
      config: config,
      transactionsText: '',
      taskId: 'responses-canonical-answer-${fixture.server.port}',
      onChunk: (_) {},
      onDone: completed.complete,
      onError: completed.completeError,
    );

    expect(await completed.future, '这是服务端完整正文');
  });

  test('Responses 来源标注不在回答正文输出裸 URL', () async {
    final fixture = await _serveResponsesSse(
      'data: {"type":"response.output_text.delta","delta":"答案"}\n\n'
      'data: {"type":"response.completed","response":{"output":[{"type":"message","content":[{"type":"output_text","text":"答案","annotations":[{"type":"url_citation","title":"官方文档","url":"https://example.com/docs"}]}]}]}}\n\n',
    );
    final config = AiProviderConfig(
      type: AiProviderType.custom,
      apiKey: 'test-key',
      baseUrl: fixture.baseUrl,
      model: 'gpt-5',
      endpointType: AiEndpointType.responses,
      webSearchEnabled: true,
    );
    final completed = Completer<String>();
    final sourceUrls = <String>[];

    await LlmQueryV2.askStream(
      question: '最新资料',
      config: config,
      transactionsText: '',
      taskId: 'responses-source-${fixture.server.port}',
      onChunk: (_) {},
      onDone: completed.complete,
      onError: completed.completeError,
      onSources: (sources) => sourceUrls.addAll(
        sources.map((source) => source.url),
      ),
    );

    final answer = await completed.future;
    expect(answer, '答案');
    expect(answer, isNot(contains('https://example.com/docs')));
    expect(sourceUrls, contains('https://example.com/docs'));
  });

  test('Codex web_search_call 来源保留给结构化来源回调', () async {
    final fixture = await _serveResponsesSse(
      'data: {"type":"response.output_text.delta","delta":"答案"}\n\n'
      'data: {"type":"response.output_item.done","item":{"type":"web_search_call","action":{"type":"search","sources":[{"type":"source","title":"实时来源","url":"https://example.com/live"}]}}}\n\n'
      'data: {"type":"response.completed","response":{"output":[{"type":"message","content":[{"type":"output_text","text":"答案"}]}]}}\n\n',
    );
    const configWithSearch = AiProviderConfig(
      type: AiProviderType.custom,
      apiKey: 'test-key',
      baseUrl: 'http://127.0.0.1:0',
      model: 'gpt-5',
      endpointType: AiEndpointType.responses,
      webSearchEnabled: true,
    );
    final config = configWithSearch.copyWith(
      baseUrl: fixture.baseUrl,
    );
    final completed = Completer<String>();
    final sourceUrls = <String>[];

    await LlmQueryV2.askStream(
      question: '最新资料',
      config: config,
      transactionsText: '',
      taskId: 'responses-codex-source-${fixture.server.port}',
      onChunk: (_) {},
      onDone: completed.complete,
      onError: completed.completeError,
      onSources: (sources) => sourceUrls.addAll(
        sources.map((source) => source.url),
      ),
    );

    final answer = await completed.future;
    expect(answer, '答案');
    expect(answer, isNot(contains('https://example.com/live')));
    expect(sourceUrls, contains('https://example.com/live'));
  });

  test('Responses SSE 忽略 event/注释行，并在 [DONE] 时结束', () async {
    final fixture = await _serveResponsesSse(
      ': keep-alive\n'
      'event: response.output_text.delta\n'
      'data:{"type":"response.output_text.delta","delta":"你好"}\n\n'
      'event: response.completed\n'
      'data: [DONE]\n\n',
    );
    final config = AiProviderConfig(
      type: AiProviderType.custom,
      apiKey: 'test-key',
      baseUrl: fixture.baseUrl,
      model: 'gpt-5',
      endpointType: AiEndpointType.responses,
    );
    final completed = Completer<String>();

    await LlmQueryV2.askStream(
      question: '你好',
      config: config,
      transactionsText: '',
      taskId: 'responses-event-done-${fixture.server.port}',
      onChunk: (_) {},
      onDone: completed.complete,
      onError: completed.completeError,
    );

    expect(await completed.future, '你好');
  });

  test('Responses 流在正文后自然断开时仍会结束请求', () async {
    // Some gateways omit both response.completed and [DONE] when the HTTP
    // response closes after the final text delta. The accumulated answer must
    // still resolve askStream so callers do not remain in the thinking state.
    final fixture = await _serveResponsesSse(
      'event: response.output_text.delta\n'
      'data:{"type":"response.output_text.delta","delta":"自然结束"}\n\n',
    );
    final config = AiProviderConfig(
      type: AiProviderType.custom,
      apiKey: 'test-key',
      baseUrl: fixture.baseUrl,
      model: 'gpt-5',
      endpointType: AiEndpointType.responses,
    );
    final completed = Completer<String>();

    await LlmQueryV2.askStream(
      question: '你好',
      config: config,
      transactionsText: '',
      taskId: 'responses-natural-close-${fixture.server.port}',
      onChunk: (_) {},
      onDone: completed.complete,
      onError: completed.completeError,
    );

    expect(await completed.future, '自然结束');
  });
}
