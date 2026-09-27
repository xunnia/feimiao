import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/core/ai/llm_entry_parser.dart';

Future<void> _writeRecordStream(HttpRequest request, String content) async {
  request.response.headers
      .set(HttpHeaders.contentTypeHeader, 'text/event-stream');
  final split = content.length ~/ 2;
  for (final delta in [content.substring(0, split), content.substring(split)]) {
    request.response.add(utf8.encode('data: ${jsonEncode({
          'type': 'response.output_text.delta',
          'delta': delta,
        })}\n\n'));
    await request.response.flush();
  }
  request.response.add(utf8.encode('data: ${jsonEncode({
        'type': 'response.completed',
        'response': {'output_text': content},
      })}\n\n'));
  await request.response.close();
}

void main() {
  test('record-only prompt is smaller while preserving categories and rules',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final prompts = <String>[];
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      prompts.add(body['instructions'] as String);
      expect(body['stream'], isTrue);
      await _writeRecordStream(request, '{"intent":"record","entries":[]}');
    });
    final results = <LlmParseResult>[];
    for (final recordOnly in [false, true]) {
      results.add(await LlmEntryParser.parseWithLLM(
        text: '昨天午饭20元',
        now: DateTime(2026, 9, 13),
        forceRecord: recordOnly,
        config: AiProviderConfig.custom(
            apiKey: 'test',
            baseUrl: 'http://127.0.0.1:${server.port}/v1',
            model: 'gpt-5.6-luna'),
        expenseCats: const [
          (key: 'dining', name: '餐饮'),
          (key: 'custom', name: '自建分类')
        ],
        incomeCats: const [(key: 'salary', name: '工资')],
        learnedHints: const [(phrase: '午饭', categoryKey: 'dining')],
      ));
    }
    expect(
        prompts.last.runes.length, lessThan(prompts.first.runes.length * 0.8));
    for (final requiredText in [
      'custom:自建分类',
      'salary:工资',
      '午饭→dining',
      '2026-09-12',
      '一百二=120',
      'AA',
      '不猜金额',
      'confidence',
      '时分',
      '补贴'
    ]) {
      expect(prompts.last, contains(requiredText));
    }
    expect(prompts.last, isNot(contains('"intent":"query"')));
    expect(results.last.entries, isEmpty);
    expect(results.last.metrics['category_count'], 3);
    expect(results.last.metrics['hint_count'], 1);
    expect(results.last.metrics['attachment_count'], 0);
    expect(results.last.metrics['request_ms'], greaterThanOrEqualTo(0));
    expect(
        results.last.metrics['parser_total_ms'],
        greaterThanOrEqualTo(results.last.metrics['credential_ms']! +
            results.last.metrics['prepare_ms']! +
            results.last.metrics['request_ms']! +
            results.last.metrics['parse_ms']!));
    expect(results.last.metrics.toString(), isNot(contains('午饭')));
    print(
        'record_prompt_chars before=${prompts.first.runes.length} after=${prompts.last.runes.length}');
  });

  test('GPT overrides old endpoint choices without changing other models', () {
    for (final model in [
      'gpt-5.6-luna',
      'GPT-4o',
      'openai/gpt-5',
      'chatgpt-4o-latest'
    ]) {
      for (final endpoint in AiEndpointType.values) {
        final config = AiProviderConfig.custom(
          apiKey: 'test',
          baseUrl: 'https://relay.example/v1',
          model: model,
          endpointType: endpoint,
        );
        expect(config.shouldUseResponses, isTrue);
        expect(config.shouldUseClaudeMessages, isFalse);
        expect(config.responsesUri.path, '/v1/responses');
      }
    }
    for (final model in ['claude-sonnet', 'deepseek-chat', 'my-gpt-wrapper']) {
      final config = AiProviderConfig.custom(
        apiKey: 'test',
        baseUrl: 'https://relay.example/v1',
        model: model,
        endpointType: AiEndpointType.chatCompletions,
      );
      expect(config.shouldUseResponses, isFalse);
    }
  });

  test(
      'GPT record request really reaches Responses with instructions and schema',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = Completer<Map<String, dynamic>>();
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>;
      received.complete({'path': request.uri.path, 'body': body});
      await _writeRecordStream(
          request,
          jsonEncode({
            'intent': 'record',
            'entries': [
              {
                'amount': 20,
                'kind': 'expense',
                'categoryKey': 'dining',
                'date': '2026-09-13',
                'note': '午饭',
                'confidence': 0.95,
              }
            ],
          }));
    });
    final result = await LlmEntryParser.parseWithLLM(
      text: '午饭20元',
      now: DateTime(2026, 9, 13),
      forceRecord: true,
      config: AiProviderConfig.custom(
          apiKey: 'test',
          baseUrl: 'http://127.0.0.1:${server.port}/v1/chat/completions',
          model: 'gpt-5.6-luna',
          endpointType: AiEndpointType.chatCompletions),
      expenseCats: const [(key: 'dining', name: '餐饮')],
      incomeCats: const [(key: 'salary', name: '工资')],
      learnedHints: const [(phrase: '午饭', categoryKey: 'dining')],
    );
    final request = await received.future;
    final body = request['body'] as Map;
    expect(request['path'], '/v1/responses');
    expect(body.containsKey('messages'), isFalse);
    expect(body['store'], isFalse);
    expect(body['stream'], isTrue);
    expect(body['instructions'], contains('dining:餐饮'));
    expect(body['instructions'], contains('午饭→dining'));
    expect((body['text'] as Map)['format']['type'], 'json_schema');
    expect((body['input'] as List).length, 1);
    expect(body.containsKey('tools'), isFalse);
    expect(result.entries.length, 1);
  });

  test('GPT record rejects incomplete SSE rather than accepting partial ledger',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response.headers
          .set(HttpHeaders.contentTypeHeader, 'text/event-stream');
      request.response.write('data: ${jsonEncode({
            'type': 'response.output_text.delta',
            'delta': '{"intent":"record","entries":[]}',
          })}\n\n');
      await request.response.close();
    });

    await expectLater(
      LlmEntryParser.parseWithLLM(
        text: '午饭20元',
        forceRecord: true,
        config: AiProviderConfig.custom(
          apiKey: 'test',
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          model: 'gpt-5.6-luna',
        ),
        expenseCats: const [(key: 'dining', name: '餐饮')],
        incomeCats: const [(key: 'salary', name: '工资')],
      ),
      throwsA(isA<LlmParseException>()
          .having((error) => error.message, 'message', contains('意外中断'))),
    );
  });

  test('GPT record rejects response.incomplete after a valid JSON delta',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response.headers
          .set(HttpHeaders.contentTypeHeader, 'text/event-stream');
      request.response.write('data: ${jsonEncode({
            'type': 'response.output_text.delta',
            'delta': '{"intent":"record","entries":[]}',
          })}\n\n');
      request.response.write('data: ${jsonEncode({
            'type': 'response.incomplete',
            'response': {
              'incomplete_details': {'reason': 'max_output_tokens'}
            },
          })}\n\n');
      await request.response.close();
    });

    await expectLater(
      LlmEntryParser.parseWithLLM(
        text: '午饭20元',
        forceRecord: true,
        config: AiProviderConfig.custom(
          apiKey: 'test',
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          model: 'gpt-5.6-luna',
        ),
        expenseCats: const [(key: 'dining', name: '餐饮')],
        incomeCats: const [(key: 'salary', name: '工资')],
      ),
      throwsA(isA<LlmParseException>()
          .having((error) => error.message, 'message', contains('未完成'))),
    );
  });
}
