import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/core/ai/responses_protocol.dart';

String _sse(List<Map<String, dynamic>> events) =>
    events.map((event) => 'data: ${jsonEncode(event)}\r\n\r\n').join();

void main() {
  const public = AiProviderConfig(
    type: AiProviderType.custom,
    apiKey: 'test-key',
    baseUrl: 'https://relay.example/v1',
    model: 'gpt-5',
    reasoningEffort: AiReasoningEffort.high,
    webSearchEnabled: true,
  );
  final codex = public.copyWith(
    baseUrl: AiProviderConfig.openAiCodexBaseUrl,
    authMethod: AiAuthMethod.oauth,
    oauthAccountId: 'test-account',
  );
  const textBody = <String, dynamic>{
    'model': 'gpt-5',
    'messages': [
      {'role': 'system', 'content': 'system rule'},
      {'role': 'developer', 'content': 'private ledger'},
      {'role': 'user', 'content': 'question'},
      {'role': 'assistant', 'content': 'answer'},
      {'role': 'user', 'content': 'follow-up'},
    ],
    'max_tokens': 2400,
    'temperature': 0.25,
    'response_format': {'type': 'json_object'},
    'response_schema': {
      'type': 'object',
      'properties': {},
      'additionalProperties': false
    },
  };

  for (final kind in ResponsesRequestKind.values) {
    test('$kind preserves non-retention and its explicit request contract', () {
      final body = ResponsesProtocol.bodyFromChat(textBody, public, kind: kind);
      expect(body['store'], isFalse);
      expect(body['instructions'], 'system rule\n\nprivate ledger');
      expect(body['reasoning'], {'effort': 'high'});
      expect(body, isNot(contains('temperature')));
      if (kind == ResponsesRequestKind.entry) {
        expect(body['stream'], isTrue);
        expect(body['input'], hasLength(3));
        expect((body['input'] as List)[1]['content'][0]['type'], 'output_text');
        expect(body['text']['format']['strict'], isTrue);
        expect(body, isNot(contains('max_output_tokens')));
        expect(body, isNot(contains('tools')));
      } else {
        expect(body['input'], 'question\n\nassistant: answer\n\nfollow-up');
        expect(body['max_output_tokens'], 2400);
        expect(body['tools'], isNotEmpty);
        expect(body, isNot(contains('text')));
        expect(body, isNot(contains('stream')));
      }
    });

    test('$kind preserves Codex mandatory stream/message input contract', () {
      final body = ResponsesProtocol.bodyFromChat(textBody, codex, kind: kind);
      expect(body['store'], isFalse);
      expect(body['stream'], isTrue);
      expect(body['input'], hasLength(3));
      expect(body, isNot(contains('max_output_tokens')));
      expect((body['input'] as List).first['role'], 'user');
    });
  }

  test('entry and Codex add fallback instructions without leaking system input',
      () {
    for (final kind in ResponsesRequestKind.values) {
      final body = ResponsesProtocol.bodyFromChat(
        {
          'model': 'gpt-5',
          'messages': [
            {'role': 'user', 'content': 'ping'}
          ]
        },
        codex,
        kind: kind,
      );
      expect(body['instructions'], 'You are a helpful assistant.');
      expect(body['input'], hasLength(1));
    }
  });

  for (final provider in [public, codex]) {
    test('${provider.baseUrl} chat and entry preserve image/file content', () {
      for (final kind in [
        ResponsesRequestKind.chat,
        ResponsesRequestKind.entry
      ]) {
        final body = ResponsesProtocol.bodyFromChat({
          'model': 'gpt-5',
          'messages': [
            {'role': 'system', 'content': 'rule'},
            {'role': 'assistant', 'content': 'previous'},
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': 'receipt'},
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:image/png;base64,AA=='}
                },
                {
                  'type': 'file',
                  'file': {
                    'filename': 'bill.pdf',
                    'file_data': 'data:application/pdf;base64,AA=='
                  }
                },
              ]
            },
          ],
        }, provider, kind: kind);
        final input = body['input'] as List;
        expect(input, hasLength(2));
        expect(input[0]['content'][0]['type'], 'output_text');
        expect(input[1]['content'], [
          {'type': 'input_text', 'text': 'receipt'},
          {'type': 'input_image', 'image_url': 'data:image/png;base64,AA=='},
          {
            'type': 'input_file',
            'filename': 'bill.pdf',
            'file_data': 'data:application/pdf;base64,AA=='
          },
        ]);
      }
    });
  }

  test('extracts only answer output, never provider reasoning or tool results',
      () {
    expect(
        ResponsesProtocol.extractText({
          'output': [
            {
              'type': 'reasoning',
              'summary': [
                {'type': 'summary_text', 'text': 'private'}
              ]
            },
            {
              'type': 'web_search_call',
              'result': {'text': 'search'}
            },
            {
              'type': 'message',
              'content': [
                {'type': 'output_text', 'text': 'answer'}
              ]
            },
          ]
        }),
        'answer');
    expect(
        ResponsesProtocol.extractText({'output_text': 'direct', 'output': []}),
        'direct');
    expect(ResponsesProtocol.extractText(null), '');
  });

  test('buffered streams never concatenate reasoning delta with answer JSON',
      () {
    final body = _sse([
      {'type': 'response.reasoning_summary_text.delta', 'delta': 'reasoning'},
      {
        'type': 'response.function_call_arguments.delta',
        'delta': 'tool argument'
      },
      {'type': 'response.output_text.delta', 'delta': '{"entries":'},
      {'type': 'response.output_text.delta', 'delta': '[]}'},
      {'type': 'response.output_text.done', 'text': '{"entries":[]}'},
      {
        'type': 'response.completed',
        'response': {'output_text': '{"entries":[]}'}
      },
    ]);
    for (final requireComplete in [false, true]) {
      expect(
          ResponsesProtocol.collectSseText(body,
              requireComplete: requireComplete),
          '{"entries":[]}');
    }
  });

  test('terminal snapshots are not deltas and done-only providers still work',
      () {
    final snapshot = {
      'type': 'response.completed',
      'response': {'output_text': 'answer'}
    };
    expect(ResponsesProtocol.textDelta(snapshot), isNull);
    expect(
        ResponsesProtocol.textDelta(
            {'type': 'response.output_text.done', 'text': 'answer'}),
        isNull);
    expect(
        ResponsesProtocol.collectSseText(_sse([snapshot]),
            requireComplete: true),
        'answer');
    expect(
        ResponsesProtocol.collectSseText(_sse([
          {'type': 'response.output_text.done', 'text': 'answer'}
        ])),
        'answer');
  });

  test('entry rejects disconnected streams even when partial JSON is valid',
      () {
    final body = _sse([
      {'type': 'response.output_text.delta', 'delta': '{"entries":[]}'}
    ]);
    expect(
        () => ResponsesProtocol.collectSseText(body, requireComplete: true),
        throwsA(isA<ResponsesProtocolException>().having(
            (error) => error.kind, 'kind', ResponsesFailureKind.interrupted)));
    expect(ResponsesProtocol.collectSseText(body), '{"entries":[]}');
    expect(
        ResponsesProtocol.collectSseText('$body' 'data: [DONE]\n\n',
            requireComplete: true),
        '{"entries":[]}');
  });

  test('entry keeps complete terminal JSON when delta snapshot was truncated',
      () {
    final body = _sse([
      {'type': 'response.output_text.delta', 'delta': '{"entries":'},
      {
        'type': 'response.completed',
        'response': {'output_text': '{"entries":[]}'}
      },
    ]);
    expect(ResponsesProtocol.collectSseText(body, requireComplete: true),
        '{"entries":[]}');
  });

  for (final type in ['response.failed', 'error', 'response.incomplete']) {
    test('$type prevents success even after an answer delta', () {
      final body = _sse([
        {'type': 'response.output_text.delta', 'delta': '{"entries":[]}'},
        {
          'type': type,
          'response': {
            'error': {'message': 'denied'}
          }
        },
      ]);
      for (final strict in [false, true]) {
        expect(
            () =>
                ResponsesProtocol.collectSseText(body, requireComplete: strict),
            throwsA(isA<ResponsesProtocolException>()));
      }
    });
  }

  test('optional malformed events and comments cannot pollute visible output',
      () {
    const body =
        ': ping\nevent: message\ndata: malformed\n\ndata: {"type":"response.output_text.delta","delta":"ok"}\n\ndata: [DONE]\n\ndata: {"delta":"ignored"}\n';
    expect(ResponsesProtocol.collectSseText(body, requireComplete: true), 'ok');
    expect(ResponsesProtocol.sseEvents(body), hasLength(1));
    expect(ResponsesProtocol.decodeEvent('[1,2]'), isNull);
  });
}
