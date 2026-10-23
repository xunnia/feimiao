import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/core/ai/claude_messages_protocol.dart';
import 'package:qingji/core/ai/llm_entry_parser.dart';
import 'package:qingji/core/ai/llm_query.dart';
import 'package:qingji/core/ai/llm_query_v2.dart';
import 'package:qingji/core/media/chat_attachment.dart';

const _config = AiProviderConfig(
  type: AiProviderType.custom,
  apiKey: 'test-key',
  baseUrl: 'https://relay.example/v1',
  model: 'claude-test',
  endpointType: AiEndpointType.anthropicMessages,
);

const _parts = [
  {'type': 'text', 'text': 'receipt'},
  {
    'type': 'image_url',
    'image_url': {'url': 'data:image/png;base64,AQID'}
  },
  {
    'type': 'file',
    'file': {
      'filename': 'bill.pdf',
      'file_data': 'data:application/pdf;base64,BAUG',
    }
  },
];

void main() {
  for (final kind in ClaudeRequestKind.values) {
    test('$kind preserves system strategy and role ordering', () {
      final body = ClaudeMessagesProtocol.bodyFromChat({
        'model': 'claude-test',
        'messages': [
          {'role': 'system', 'content': 'first rule'},
          {'role': 'user', 'content': 'question'},
          {'role': 'system', 'content': 'last rule'},
          {'role': 'assistant', 'content': 'answer'},
        ],
        'response_format': {'type': 'json_object'},
        'response_schema': {'type': 'object'},
      }, _config, kind: kind);
      expect(
          body['system'],
          kind == ClaudeRequestKind.report
              ? 'last rule'
              : 'first rule\n\nlast rule');
      expect((body['messages'] as List).map((message) => message['role']),
          ['user', 'assistant']);
      expect(body['messages'], [
        {'role': 'user', 'content': 'question'},
        {'role': 'assistant', 'content': 'answer'},
      ]);
      expect(body.containsKey('stream'), kind == ClaudeRequestKind.streamChat);
      expect(body.containsKey('response_format'), isFalse);
      expect(body.containsKey('response_schema'), isFalse);
      expect(body.containsKey('tools'), isFalse);
    });

    test(
        '$kind keeps thinking budget, sufficient output and temperature policy',
        () {
      for (final effort in AiReasoningEffort.values) {
        final provider = _config.copyWith(reasoningEffort: effort);
        final body = ClaudeMessagesProtocol.bodyFromChat({
          'model': 'claude-test',
          'messages': <Map<String, dynamic>>[],
          'temperature': 0.2,
        }, provider, kind: kind);
        final budget = effort.claudeBudgetTokens;
        expect(body['max_tokens'], budget == null ? 4096 : budget + 4096);
        if (budget == null) {
          expect(body.containsKey('thinking'), isFalse);
          expect(body.containsKey('temperature'), isFalse);
        } else {
          expect(
              body['thinking'], {'type': 'enabled', 'budget_tokens': budget});
          expect(body['temperature'], 1);
        }
      }
      final body = ClaudeMessagesProtocol.bodyFromChat({
        'messages': <Map<String, dynamic>>[],
        'max_tokens': 100000,
      }, _config.copyWith(reasoningEffort: AiReasoningEffort.high), kind: kind);
      expect(body['max_tokens'], 100000);
    });
  }

  test('only entry and streamed chat encode attachments; inputs stay unchanged',
      () {
    final original = {
      'model': 'claude-test',
      'messages': [
        {'role': 'user', 'content': _parts}
      ],
    };
    for (final kind in ClaudeRequestKind.values) {
      final body =
          ClaudeMessagesProtocol.bodyFromChat(original, _config, kind: kind);
      final content = (body['messages'] as List).single['content'];
      if (kind == ClaudeRequestKind.report) {
        expect(content, 'receipt');
      } else if (kind == ClaudeRequestKind.query) {
        expect(content, _parts);
      } else {
        expect(content, [
          {'type': 'text', 'text': 'receipt'},
          {
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': 'image/png',
              'data': 'AQID'
            }
          },
          {
            'type': 'document',
            'source': {
              'type': 'base64',
              'media_type': 'application/pdf',
              'data': 'BAUG'
            },
            'title': 'bill.pdf',
          },
        ]);
      }
    }
    expect((original['messages'] as List).single['content'], _parts);
  });

  test(
      'legacy report ignores blanks and trims, entry preserves its system block join',
      () {
    final messages = [
      {'role': 'system', 'content': '  kept  '},
      {'role': 'system', 'content': '   '},
      {'role': ' user ', 'content': '  question  '},
    ];
    final report = ClaudeMessagesProtocol.bodyFromChat(
        {'messages': messages}, _config,
        kind: ClaudeRequestKind.report);
    expect(report['system'], 'kept');
    expect(report['messages'], [
      {'role': 'user', 'content': 'question'}
    ]);
    final entry = ClaudeMessagesProtocol.bodyFromChat({
      'messages': [
        {
          'role': 'system',
          'content': [
            {'type': 'text', 'text': 'first'},
            {'type': 'image_url', 'text': 'excluded'},
            {'type': 'text', 'text': 'second'},
          ]
        },
        {'role': 'user', 'content': null},
      ],
    }, _config, kind: ClaudeRequestKind.entry);
    expect(entry['system'], 'first second');
    expect((entry['messages'] as List).single['content'], '');
  });

  test('legacy no-messages contract remains unchanged outside report', () {
    final body = <String, dynamic>{'model': 'claude-test'};
    for (final kind in [ClaudeRequestKind.query, ClaudeRequestKind.entry]) {
      expect(ClaudeMessagesProtocol.bodyFromChat(body, _config, kind: kind),
          same(body));
    }
  });

  for (final kind in ClaudeRequestKind.values) {
    test(
        '$kind real caller reaches native Messages with preserved wire contract',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final captured = Completer<Map<String, dynamic>>();
      final ledgerJson = jsonEncode({
        'intent': 'record',
        'entries': [
          {
            'amount': 18,
            'kind': 'expense',
            'categoryKey': 'dining',
            'date': '2026-10-24',
            'note': '午饭',
            'confidence': 0.95,
          }
        ],
      });
      server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>;
        captured.complete({'path': request.uri.path, 'body': body});
        if (kind == ClaudeRequestKind.streamChat) {
          request.response.headers.contentType =
              ContentType('text', 'event-stream', charset: 'utf-8');
          request.response.write('data: ${jsonEncode({
                'type': 'content_block_delta',
                'delta': {'type': 'text_delta', 'text': 'answer'},
              })}\n\ndata: {"type":"message_stop"}\n\n');
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'content': [
              {
                'type': 'text',
                'text': kind == ClaudeRequestKind.entry ? ledgerJson : 'answer'
              }
            ],
          }));
        }
        await request.response.close();
      });
      final provider =
          _config.copyWith(baseUrl: 'http://127.0.0.1:${server.port}/v1');
      final directory =
          await Directory.systemTemp.createTemp('claude-protocol-');
      addTearDown(() => directory.delete(recursive: true));
      final pdf = File('${directory.path}/bill.pdf');
      await pdf.writeAsBytes([4, 5, 6]);
      final attachment = ChatAttachment(
        kind: ChatAttachmentKind.file,
        path: pdf.path,
        name: 'bill.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 3,
      );
      switch (kind) {
        case ClaudeRequestKind.report:
          expect(
              await LlmQuery.askReport(
                reportTitle: '测试月报',
                reportType: 'monthly',
                transactionsText: '本期准确合计：支出18元',
                config: provider,
              ),
              'answer');
        case ClaudeRequestKind.query:
          expect(
              await LlmQueryV2.ask(
                question: '你好',
                transactionsText: '',
                config: provider,
              ),
              'answer');
        case ClaudeRequestKind.streamChat:
          final completed = Completer<String>();
          final chunks = <String>[];
          await LlmQueryV2.askStream(
            question: '看看附件',
            transactionsText: '',
            config: provider,
            attachments: [attachment],
            onChunk: chunks.add,
            onDone: completed.complete,
            onError: completed.completeError,
          );
          expect(await completed.future, 'answer');
          expect(chunks, ['answer']);
        case ClaudeRequestKind.entry:
          final result = await LlmEntryParser.parseWithLLM(
            text: '午饭18元',
            forceRecord: true,
            config: provider,
            attachments: [attachment],
            expenseCats: const [(key: 'dining', name: '餐饮')],
            incomeCats: const [(key: 'salary', name: '工资')],
          );
          expect(result.entries, hasLength(1));
      }
      final request = await captured.future;
      final body = request['body'] as Map;
      expect(request['path'], '/v1/messages');
      expect(body['system'], isA<String>());
      expect(body['max_tokens'], isPositive);
      expect(body.containsKey('stream'), kind == ClaudeRequestKind.streamChat);
      expect(body.containsKey('response_schema'), isFalse);
      if (kind == ClaudeRequestKind.entry ||
          kind == ClaudeRequestKind.streamChat) {
        final content = (body['messages'] as List).last['content'] as List;
        final document = content
            .cast<Map>()
            .singleWhere((part) => part['type'] == 'document');
        expect(document['source'], {
          'type': 'base64',
          'media_type': 'application/pdf',
          'data': 'BAUG'
        });
        expect(document['title'], 'bill.pdf');
      }
    });
  }
}
