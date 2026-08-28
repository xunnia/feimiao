import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_attachment_pipeline.dart';
import 'package:qingji/core/ai/ai_context.dart';
import 'package:qingji/core/ai/ai_extensions.dart';
import 'package:qingji/core/ai/ai_provider_health.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/core/ai/ai_run.dart';
import 'package:qingji/core/ai/ai_tool_registry.dart';
import 'package:qingji/core/ai/chat_session.dart';
import 'package:qingji/core/ai/local_model_companion.dart';
import 'package:qingji/core/media/chat_attachment.dart';

void main() {
  test('run and proposal round trips without secrets', () {
    const config = AiRunConfigSnapshot(
      providerId: 'provider-1',
      providerLabel: 'OpenAI',
      model: 'gpt-5',
      effort: 'high',
      endpointType: 'responses',
    );
    const run = AiRun(
      id: 'run-1',
      idempotencyKey: 'key-1',
      sessionId: ChatSession.recordId,
      mode: AiRunMode.record,
      config: config,
      status: AiRunStatus.awaitingConfirmation,
      inputDigest: 'input-digest',
      contextDigest: 'context-digest',
      proposalJson: '',
      resultJson: '',
      errorCode: '',
      errorMessage: '',
      retryCount: 0,
      requiresConfirmation: true,
      createdMs: 10,
      updatedMs: 20,
    );

    final map = run.toMap();
    expect(map, isNot(contains('apiKey')));
    expect(AiRun.fromMap(map).config.model, 'gpt-5');
    expect(AiRunStatusX.fromStorage('rolledBack'), AiRunStatus.rolledBack);

    final proposal = AiLedgerProposal(
      runId: run.id,
      items: const [
        AiLedgerProposalItem(
          amount: '12.50',
          kind: 'expense',
          categoryKey: 'dining',
          date: '2026-08-27T09:00:00.000',
          note: 'coffee',
          confidence: 0.97,
        ),
      ],
      requiresConfirmation: true,
      createdMs: 20,
    );
    expect(
      AiLedgerProposal.decode(proposal.encode())?.selectedItems,
      hasLength(1),
    );
  });

  test('tool policy keeps writes confirmable outside record mode', () {
    expect(
      AiToolRegistry.needsConfirmation(
        'create_transactions',
        policy: AiToolAccessPolicy.automatic,
        recordMode: false,
        highConfidence: true,
        itemCount: 1,
      ),
      isTrue,
    );
    expect(
      AiToolRegistry.needsConfirmation(
        'create_transactions',
        policy: AiToolAccessPolicy.automatic,
        recordMode: true,
        highConfidence: true,
        itemCount: 1,
      ),
      isFalse,
    );
    expect(
      AiToolRegistry.allowed(
        'delete_transactions',
        policy: AiToolAccessPolicy.automatic,
        recordMode: false,
      ),
      isFalse,
    );
  });

  test('provider health cools down after repeated failures and recovers', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    var health = const AiProviderHealth(providerId: 'p');
    health = health.recordFailure('first', now);
    health = health.recordFailure('second', now + 1);
    health = health.recordFailure('third', now + 2);
    expect(health.failureCount, 3);
    expect(health.cooldownUntilMs, now + 2 + 120000);
    expect(health.isCoolingDown, isTrue);
    health = health.recordSuccess(80, now + 3);
    expect(health.consecutiveFailures, 0);
    expect(health.cooldownUntilMs, isNull);
    expect(health.averageLatencyMs, 80);
  });

  test('context snapshot exposes counts and digest, never raw text', () {
    final snapshot = AiContextInspector.inspect(
      question: 'secret question',
      historyTurns: 4,
      ledgerRows: 12,
      memoryItems: 2,
      attachmentCount: 1,
      maxTokens: 1,
    );
    expect(snapshot.truncated, isTrue);
    expect(snapshot.digest, isNotEmpty);
    expect(snapshot.encode(), isNot(contains('secret question')));
    expect(
      snapshot.blocks.map((item) => item.kind),
      contains(AiContextBlockKind.ledger),
    );
  });

  test('attachment preflight enforces persisted file limits and image count',
      () async {
    final directory = await Directory.systemTemp.createTemp('ai_attachment_');
    addTearDown(() => directory.delete(recursive: true));
    final image = File('${directory.path}/image.png');
    await image.writeAsBytes(List<int>.filled(8, 1));
    final attachments = [
      for (var i = 0; i < 4; i++)
        ChatAttachment(
          kind: ChatAttachmentKind.image,
          path: image.path,
          name: 'image-$i.png',
          mimeType: 'image/png',
          sizeBytes: 8,
        ),
    ];
    final result = await AiAttachmentPipeline.validate(attachments);
    expect(result.accepted, hasLength(3));
    expect(result.rejected, hasLength(1));
    expect(result.rejected.single.error, contains('3'));
  });

  test('connector and memory definitions use explicit allowlists', () {
    final connector = AiConnectorRegistry.byId('local_companion');
    expect(connector, isNotNull);
    expect(connector!.accepts(Uri.parse('http://127.0.0.1:8787')), isTrue);
    expect(connector.accepts(Uri.parse('http://localhost:8787')), isTrue);
    expect(connector.accepts(Uri.parse('http://localhost:8787@evil.example')),
        isFalse);
    expect(connector.accepts(Uri.parse('https://localhost:8787')), isFalse);
    expect(connector.accepts(Uri.parse('https://example.com')), isFalse);
    final webSearch = AiConnectorRegistry.byId('web_search');
    expect(webSearch?.accepts(Uri.parse('https://api.duckduckgo.com')), isTrue);
    expect(webSearch?.accepts(Uri.parse('http://api.duckduckgo.com')), isFalse);
    expect(AiSkillRegistry.builtIns, isNotEmpty);
    expect(
      decodeAiSkillState('{"ledger_assistant":false}')['ledger_assistant'],
      isFalse,
    );

    const config = AiProviderConfig(
      type: AiProviderType.custom,
      apiKey: 'must-not-be-in-consent-key',
      baseUrl: 'https://gateway.example/v1',
      model: 'model-a',
      providerId: 'provider-a',
    );
    expect(config.privacyReceiverKey,
        isNot(contains('must-not-be-in-consent-key')));
    expect(config.privacyReceiverKey, contains('provider-a'));
  });

  test('local companion is health-checkable, bounded and loopback-only',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requests = <String>[];
    server.listen((request) async {
      requests.add(request.uri.path);
      if (request.uri.path == '/health') {
        request.response.statusCode = HttpStatus.noContent;
      } else {
        final body = await utf8.decoder.bind(request).join();
        expect(body, contains('qwen-local'));
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'choices': [
            {
              'message': {'content': '本地结果'},
            },
          ],
        }));
      }
      await request.response.close();
    });

    final client = LocalModelCompanionClient(
      LocalModelCompanionConfig(
        endpoint: Uri.parse(
          'http://${server.address.address}:${server.port}',
        ),
        model: 'qwen-local',
        enabled: true,
      ),
    );
    expect(await client.checkHealth(), isTrue);
    expect(await client.complete('你好'), '本地结果');
    expect(requests, containsAll(['/health', '/v1/chat/completions']));

    final remote = LocalModelCompanionClient(
      LocalModelCompanionConfig(
        endpoint: Uri.parse('http://192.0.2.1:8787'),
        enabled: true,
      ),
    );
    expect(await remote.checkHealth(), isFalse);
    expect(() => remote.complete('拒绝远程'), throwsStateError);
  });
}
