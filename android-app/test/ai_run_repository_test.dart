import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_extensions.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/core/ai/ai_run.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('qingji_ai_runs_');
    await databaseFactory.setDatabasesPath(temp.path);
  });

  tearDown(() async {
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
  });

  AiProviderConfig config({String model = 'gpt-5'}) => AiProviderConfig(
        type: AiProviderType.custom,
        apiKey: 'test-key',
        baseUrl: 'https://api.openai.com/v1',
        model: model,
        endpointType: AiEndpointType.responses,
        reasoningEffort: AiReasoningEffort.high,
        displayName: 'OpenAI',
        providerId: 'openai-test',
      );

  test('run idempotency, event ordering, proposal commit and undo', () async {
    final repo = AppRepository();
    await repo.init();
    addTearDown(repo.closeForTest);

    final first = await repo.createOrGetAiRun(
      sessionId: 'record',
      mode: AiRunMode.record,
      config: config(),
      idempotencyKey: 'same-logical-send',
      inputDigest: 'digest-a',
    );
    final duplicate = await repo.createOrGetAiRun(
      sessionId: 'record',
      mode: AiRunMode.record,
      config: config(model: 'other-model'),
      idempotencyKey: 'same-logical-send',
      inputDigest: 'digest-b',
    );
    expect(duplicate.id, first.id);
    expect(duplicate.config.model, 'gpt-5');

    await repo.appendAiRunEvent(
      first.id,
      AiRunEventType.stageChanged,
      payload: {'stage': 'parse'},
    );
    final events = await repo.loadAiRunEvents(first.id);
    expect(events.map((event) => event.sequence), [1, 2]);
    expect(events.first.type, AiRunEventType.runStarted);
    final reasoning = await repo.appendAiRunEvent(
      first.id,
      AiRunEventType.reasoning,
      payload: {'text': '这段内容不应进入运行记录'},
    );
    expect(reasoning.payload, {'characters': 12});
    expect((await repo.loadAiRunEvents(first.id)).last.payload,
        {'characters': 12});

    await repo.saveAiRunProposal(
      first.id,
      AiLedgerProposal(
        runId: first.id,
        items: const [
          AiLedgerProposalItem(
            amount: '18.50',
            kind: 'expense',
            categoryKey: 'dining',
            date: '2026-08-27T10:00:00.000',
            note: 'lunch',
            confidence: 0.8,
          ),
        ],
        requiresConfirmation: true,
        createdMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    expect(
      (await repo.aiRunById(first.id))?.status,
      AiRunStatus.awaitingConfirmation,
    );

    final accountId = repo.transactionAccounts.first.id;
    final transactionId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.parse('18.50'),
      accountId: accountId,
      date: DateTime(2026, 8, 27),
      note: 'lunch',
    );
    await repo.commitAiRun(first.id, [transactionId, transactionId]);
    final committed = await repo.aiRunById(first.id);
    expect(committed?.status, AiRunStatus.completed);
    expect(committed?.resultJson, contains(transactionId.toString()));

    expect(await repo.undoAiRun(first.id), isTrue);
    final rolledBack = await repo.aiRunById(first.id);
    expect(rolledBack?.status, AiRunStatus.rolledBack);
    expect(repo.transactionById(transactionId), isNull);
    expect(await repo.undoAiRun(first.id), isFalse);
    expect(
      (await repo.loadAiRunEvents(first.id)).last.type,
      AiRunEventType.rolledBack,
    );
  });

  test('AI ledger commit is atomic and terminal callbacks are idempotent',
      () async {
    final repo = AppRepository();
    await repo.init();
    addTearDown(repo.closeForTest);

    final failedRun = await repo.createOrGetAiRun(
      sessionId: 'record',
      mode: AiRunMode.record,
      config: config(),
      idempotencyKey: 'atomic-failure',
    );
    final validDraft = TransactionDraft(
      kind: TransactionKind.expense,
      amount: Decimal.parse('9.90'),
      accountId: repo.transactionAccounts.first.id,
      date: DateTime(2026, 8, 27),
      note: 'atomic-first',
    );
    expect(
      () => repo.addTransactionDraftsAtomically([
        validDraft,
        validDraft.copyWith(accountId: -999),
      ], runId: failedRun.id),
      throwsArgumentError,
    );
    expect(repo.transactions.where((t) => t.note == 'atomic-first'), isEmpty);
    expect((await repo.aiRunById(failedRun.id))?.status,
        isNot(AiRunStatus.completed));

    final run = await repo.createOrGetAiRun(
      sessionId: 'record',
      mode: AiRunMode.record,
      config: config(),
      idempotencyKey: 'atomic-success',
    );
    final ids = await repo.addTransactionDraftsAtomically([
      validDraft.copyWith(note: 'atomic-a'),
      validDraft.copyWith(note: 'atomic-b'),
    ], runId: run.id);
    expect(ids, hasLength(2));
    expect((await repo.aiRunById(run.id))?.status, AiRunStatus.completed);
    final events = await repo.loadAiRunEvents(run.id);
    expect(events.where((event) => event.type == AiRunEventType.committed),
        hasLength(1));
    expect(events.where((event) => event.type == AiRunEventType.completed),
        hasLength(1));

    // A delayed callback from the same request must not add a second batch or
    // another terminal event.
    expect(
      () => repo.addTransactionDraftsAtomically([validDraft], runId: run.id),
      throwsStateError,
    );
    expect(repo.transactions.where((t) => t.note.startsWith('atomic-')),
        hasLength(2));
    final eventsAfterRetry = await repo.loadAiRunEvents(run.id);
    expect(
        eventsAfterRetry
            .where((event) => event.type == AiRunEventType.committed),
        hasLength(1));
  });

  test('undo preserves a transaction edited after the AI commit', () async {
    final repo = AppRepository();
    await repo.init();
    addTearDown(repo.closeForTest);

    final run = await repo.createOrGetAiRun(
      sessionId: 'record',
      mode: AiRunMode.record,
      config: config(),
      idempotencyKey: 'undo-edit-protection',
    );
    final id = (await repo.addTransactionDraftsAtomically([
      TransactionDraft(
        kind: TransactionKind.expense,
        amount: Decimal.parse('12.00'),
        accountId: repo.transactionAccounts.first.id,
        date: DateTime(2026, 8, 27),
        note: 'before-edit',
      ),
    ], runId: run.id))
        .single;
    await Future<void>.delayed(const Duration(milliseconds: 3));
    await repo.updateTransaction(
      id: id,
      kind: TransactionKind.expense,
      amount: Decimal.parse('13.00'),
      accountId: repo.transactionAccounts.first.id,
      date: DateTime(2026, 8, 27),
      note: 'after-edit',
    );

    expect(await repo.undoAiRun(run.id), isFalse);
    expect(repo.transactionById(id)?.note, 'after-edit');
    expect((await repo.aiRunById(run.id))?.status, AiRunStatus.rolledBack);
  });

  test('provider health, explicit memories, schedules and search persist',
      () async {
    final repo = AppRepository();
    await repo.init();
    addTearDown(repo.closeForTest);

    await repo.recordAiProviderFailure('openai-test', 'timeout');
    await repo.recordAiProviderFailure('openai-test', 'timeout');
    final health = await repo.recordAiProviderFailure('openai-test', 'timeout');
    expect(health.failureCount, 3);
    expect(health.cooldownUntilMs, isNotNull);

    expect(
      await repo.addAiMemory(
        phrase: '不要保存',
        content: 'secret',
        consent: false,
      ),
      isNull,
    );
    final memory = await repo.addAiMemory(
      phrase: '咖啡',
      content: '将咖啡归到餐饮',
      consent: true,
    );
    expect(memory, isNotNull);
    expect(repo.aiMemories.map((item) => item.phrase), contains('咖啡'));
    final sessionMemory = await repo.addAiMemory(
      phrase: '只在工作会话',
      content: '这条偏好不能泄漏到其他会话',
      consent: true,
      sessionId: 'work-chat',
    );
    expect(
      repo.aiMemoryPromptBlock('今天喝咖啡', sessionId: 'record'),
      contains('将咖啡归到餐饮'),
    );
    expect(
      repo.aiMemoryPromptBlock('今天喝茶', sessionId: 'record'),
      isEmpty,
    );
    expect(
      repo.aiMemoryPromptBlock('只在工作会话', sessionId: 'record'),
      isEmpty,
    );
    expect(
      repo.aiMemoryPromptBlock('只在工作会话', sessionId: 'work-chat'),
      contains('不能泄漏'),
    );
    expect(sessionMemory, isNotNull);
    await repo.setAiMemoryConsent(memory!.id, false);
    expect(repo.aiMemories.map((item) => item.id), contains(sessionMemory!.id));
    expect(repo.aiMemories.map((item) => item.id), isNot(contains(memory.id)));
    await repo.setAiMemoryConsent(sessionMemory.id, false);
    expect(repo.aiMemories, isEmpty);

    final schedule = await repo.saveAiReportSchedule(
      AiReportSchedule(
        id: '',
        title: '每月摘要',
        nextRunMs: DateTime.now().millisecondsSinceEpoch - 1,
      ),
    );
    expect(schedule.id, isNotEmpty);
    expect(repo.aiReportSchedules.single.title, '每月摘要');
    expect(
        schedule.nextRunMs, greaterThan(DateTime.now().millisecondsSinceEpoch));

    final run = await repo.createOrGetAiRun(
      sessionId: 'record',
      mode: AiRunMode.chat,
      config: config(),
      idempotencyKey: 'searchable-run',
    );
    final results = await repo.searchAiHistory('OpenAI');
    expect(results.any((item) => item['kind'] == 'run' && item['id'] == run.id),
        isTrue);

    final transactionId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.parse('28.00'),
      accountId: repo.transactionAccounts.first.id,
      date: DateTime(2026, 8, 27),
      note: '统一搜索账单',
    );
    final ledgerResults = await repo.searchAiHistory('统一搜索账单');
    expect(
      ledgerResults.any(
        (item) => item['kind'] == 'transaction' && item['id'] == transactionId,
      ),
      isTrue,
    );

    await repo.saveAiLocalModelCompanionSettings(
      endpoint: 'http://127.0.0.1:8787',
      model: 'qwen-local',
      enabled: true,
    );
    final companion = await repo.loadAiLocalModelCompanionSettings();
    expect(companion.endpoint, 'http://127.0.0.1:8787');
    expect(companion.model, 'qwen-local');
    expect(companion.enabled, isTrue);
  });
}
