import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_prompt_templates.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/core/ai/llm_query.dart';
import 'package:qingji/core/ai/llm_query_v2.dart';

Future<({AiProviderConfig config, Future<Map<String, dynamic>> body})> _fixture(
    {bool streaming = false,
    bool responses = false,
    bool webSearchEnabled = false}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  final body = Completer<Map<String, dynamic>>();
  server.listen((request) async {
    final raw = await utf8.decoder.bind(request).join();
    body.complete(jsonDecode(raw) as Map<String, dynamic>);
    final payload = !streaming
        ? jsonEncode(responses
            ? {
                'output_text': 'fixture-answer',
              }
            : {
                'choices': [
                  {
                    'message': {'content': 'fixture-answer'}
                  }
                ]
              })
        : responses
            ? 'data: {"type":"response.completed","response":{"output":[{"type":"message","content":[{"type":"output_text","text":"fixture-answer"}]}]}}\n\n'
            : 'data: {"choices":[{"delta":{"content":"fixture-answer"},"finish_reason":"stop"}]}\n\n'
                'data: [DONE]\n\n';
    final bytes = utf8.encode(payload);
    request.response.headers.contentType = streaming
        ? ContentType('text', 'event-stream', charset: 'utf-8')
        : ContentType.json;
    request.response.headers.contentLength = bytes.length;
    request.response.add(bytes);
    await request.response.close();
  });
  return (
    config: AiProviderConfig(
      type: AiProviderType.custom,
      apiKey: 'fixture-key',
      baseUrl: 'http://${server.address.address}:${server.port}/v1',
      model: responses ? 'gpt-5' : 'deepseek-v4-flash-vision',
      endpointType:
          responses ? AiEndpointType.responses : AiEndpointType.chatCompletions,
      webSearchEnabled: webSearchEnabled,
    ),
    body: body.future,
  );
}

void main() {
  test('实际聊天流请求保留通用能力，记忆与历史拒答不冒充账本', () async {
    final fixture = await _fixture(streaming: true);
    final done = Completer<String>();
    await LlmQueryV2.askStream(
      question: '帮我分析下最近的股市',
      config: fixture.config,
      transactionsText: '',
      memoryText: '偏好详细说明',
      priorTurns: const [
        {'role': 'assistant', 'content': '我只能回答账单问题'},
      ],
      taskId: 'chat-prompt-contract-${fixture.config.baseUrl}',
      onChunk: (_) {},
      onDone: done.complete,
      onError: done.completeError,
    );
    expect(await done.future, 'fixture-answer');
    final body = await fixture.body;
    final messages = (body['messages'] as List).cast<Map>();
    expect(messages.first['content'], AiPromptTemplates.systemPrompt);
    final system = messages
        .where((message) => message['role'] == 'system')
        .map((message) => message['content'])
        .join('\n');
    expect(system, contains('不构成新的能力限制'));
    expect(system, contains('偏好详细说明'));
    expect(system, isNot(contains('账目上下文：')));
    expect(messages.last['content'], '帮我分析下最近的股市');
    expect(messages.where((message) => message['role'] == 'assistant'),
        hasLength(1));
  });

  test('实际 Responses 查账流请求保留准确合计与分类锁定规则', () async {
    final fixture = await _fixture(
        streaming: true, responses: true, webSearchEnabled: true);
    final done = Completer<String>();
    await LlmQueryV2.askStream(
      question: '本月餐饮花了多少',
      config: fixture.config,
      transactionsText: '分类筛选已锁定；分类查询准确合计：123.45 元',
      taskId: 'ledger-prompt-contract-${fixture.config.baseUrl}',
      onChunk: (_) {},
      onDone: done.complete,
      onError: done.completeError,
    );
    expect(await done.future, 'fixture-answer');
    final body = await fixture.body;
    expect(body['instructions'], contains(AiPromptTemplates.systemPrompt));
    expect(body['instructions'], contains(AiPromptTemplates.ledgerQueryRules));
    expect(body['instructions'], contains('123.45 元'));
    expect(body['input'], '本月餐饮花了多少');
    expect(body['store'], isFalse);
    expect(body['tools'], isNull);
    expect(fixture.config.webSearchEnabled, isTrue);
  });

  test('普通市场 Responses 流请求保留原生联网能力', () async {
    final fixture = await _fixture(
        streaming: true, responses: true, webSearchEnabled: true);
    final done = Completer<String>();
    await LlmQueryV2.askStream(
      question: '帮我分析下最近的股市',
      config: fixture.config,
      transactionsText: '',
      taskId: 'native-market-prompt-contract-${fixture.config.baseUrl}',
      onChunk: (_) {},
      onDone: done.complete,
      onError: done.completeError,
    );
    expect(await done.future, 'fixture-answer');
    final body = await fixture.body;
    expect(body['tools'], fixture.config.responsesWebSearchTools);
    expect(body['instructions'], isNot(contains('账目上下文：')));
  });

  for (final legacy in [true, false]) {
    test('${legacy ? '旧接口' : 'V2非流式'}查账 Responses 请求不提供联网工具', () async {
      final fixture = await _fixture(responses: true, webSearchEnabled: true);
      final answer = legacy
          ? await LlmQuery.ask(
              question: '本月支出多少',
              config: fixture.config,
              transactionsText: '本期准确合计：123.45 元',
            )
          : await LlmQueryV2.ask(
              question: '本月支出多少',
              config: fixture.config,
              transactionsText: '本期准确合计：123.45 元',
              taskId: 'private-sync-prompt-contract-${fixture.config.baseUrl}',
            );
      expect(answer, 'fixture-answer');
      expect((await fixture.body)['tools'], isNull);
      expect(fixture.config.webSearchEnabled, isTrue);
    });

    test('${legacy ? '旧接口' : 'V2非流式'}实际请求使用相同通用角色与查账规则', () async {
      final fixture = await _fixture();
      final answer = legacy
          ? await LlmQuery.ask(
              question: '本月花了多少',
              config: fixture.config,
              transactionsText: '本期准确合计：123.45 元',
              memoryText: '偏好按周分析',
            )
          : await LlmQueryV2.ask(
              question: '本月花了多少',
              config: fixture.config,
              transactionsText: '本期准确合计：123.45 元',
              memoryText: '偏好按周分析',
              taskId: 'sync-prompt-contract-${fixture.config.baseUrl}',
            );
      expect(answer, 'fixture-answer');
      final messages = ((await fixture.body)['messages'] as List).cast<Map>();
      expect(messages.first['content'], AiPromptTemplates.systemPrompt);
      final ledger = messages.singleWhere(
        (message) => message['content'].toString().contains('账目上下文：'),
      );
      expect(ledger['content'], contains(AiPromptTemplates.ledgerQueryRules));
      expect(ledger['content'], contains('123.45 元'));
      expect(ledger['content'], isNot(contains('偏好按周分析')));
      expect(
          messages.any(
              (message) => message['content'].toString().contains('用户记忆（偏好参考')),
          isTrue);
    });
  }
}
