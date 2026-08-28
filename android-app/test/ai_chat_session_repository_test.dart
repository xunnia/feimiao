import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/core/ai/ai_extensions.dart';
import 'package:qingji/core/ai/report_task_scheduler.dart';
import 'package:qingji/core/ai/chat_session.dart';
import 'package:qingji/core/media/chat_attachment.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;
  late List<AppRepository> openRepositories;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('qingji_chat_sessions_');
    openRepositories = [];
    await databaseFactory.setDatabasesPath(tmp.path);
  });

  tearDown(() async {
    for (final repo in openRepositories) {
      await repo.closeForTest();
    }
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<AppRepository> freshRepo() async {
    final repo = AppRepository();
    openRepositories.add(repo);
    await repo.init();
    return repo;
  }

  test('v43 migration assigns legacy messages to the unique record session',
      () async {
    final seeded = await freshRepo();
    await seeded.closeForTest();

    final dbPath = p.join(tmp.path, 'qingji.db');
    final now = DateTime.now().millisecondsSinceEpoch;
    final legacy = await databaseFactory.openDatabase(dbPath);
    await legacy.transaction((txn) async {
      await txn.insert(
          'app_settings',
          {
            'key': 'chat_current_provider_id',
            'value': 'legacy-provider',
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert(
          'app_settings',
          {
            'key': 'chat_current_model',
            'value': 'legacy-model',
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert(
          'app_settings',
          {
            'key': 'ai_chat_reasoning_effort',
            'value': 'high',
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.execute('DROP TABLE chat_sessions');
      await txn.execute('DROP TABLE chat_messages');
      await txn.execute('''
        CREATE TABLE chat_messages (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          role       TEXT NOT NULL,
          text       TEXT NOT NULL DEFAULT '',
          question   TEXT NOT NULL DEFAULT '',
          created_ms INTEGER NOT NULL
        )
      ''');
      await txn.insert('chat_messages', {
        'role': 'user',
        'question': '午饭花了 20',
        'created_ms': now - 200,
      });
      await txn.insert('chat_messages', {
        'role': 'assistant',
        'text': '已记账',
        'created_ms': now - 100,
      });
      await txn.execute('PRAGMA user_version = 43');
    });
    await legacy.close();

    final repo = await freshRepo();
    final sessions = await repo.loadChatSessions();
    final record = sessions.where((item) => item.id == ChatSession.recordId);
    expect(record, hasLength(1));
    expect(record.single.isRecord, isTrue);
    expect(record.single.title, ChatSession.recordTitle);
    expect(record.single.providerId, 'legacy-provider');
    expect(record.single.model, 'legacy-model');
    expect(record.single.effort, AiReasoningEffort.high);

    final legacyMessages = await repo.loadChatMessages();
    expect(legacyMessages.map((row) => row['question']), ['午饭花了 20', '']);
    expect(legacyMessages.map((row) => row['text']), ['', '已记账']);

    await repo.closeForTest();
    final migrated = await databaseFactory.openDatabase(dbPath);
    final columns = await migrated.rawQuery('PRAGMA table_info(chat_messages)');
    final messages = await migrated.query('chat_messages');
    await migrated.close();
    expect(
      columns.map((column) => column['name']),
      contains('session_id'),
    );
    expect(
      columns.map((column) => column['name']),
      contains('attachments_json'),
    );
    expect(
      messages.map((row) => row['session_id']),
      everyElement(ChatSession.recordId),
    );
  });

  test('chat attachment metadata survives persistence and restart', () async {
    final repo = await freshRepo();
    final session = await repo.createChatSession(title: '附件会话');
    const attachment = ChatAttachment(
      kind: ChatAttachmentKind.image,
      path: r'C:\app\chat_attachments\photo.jpg',
      name: 'photo.jpg',
      mimeType: 'image/jpeg',
      sizeBytes: 1234,
    );
    await repo.addChatSessionMessage(
      sessionId: session.id,
      role: 'user',
      text: '看看这张图',
      attachmentsJson: ChatAttachment.encodeList([attachment]),
    );
    await repo.closeForTest();

    final reopened = await freshRepo();
    final rows = await reopened.loadChatSessionMessages(session.id);
    final restored = ChatAttachment.decodeList(rows.single['attachments_json']);
    expect(restored, hasLength(1));
    expect(restored.single.name, 'photo.jpg');
    expect(restored.single.path, attachment.path);
    expect(restored.single.isImage, isTrue);
  });

  test(
      'messages stay isolated by session and the record session cannot be deleted',
      () async {
    final repo = await freshRepo();
    final first = await repo.createChatSession(title: '第一个会话');
    final second = await repo.createChatSession(title: '第二个会话');

    await repo.addChatMessage(role: 'user', question: '记一笔午饭');
    await repo.addChatSessionMessage(
      sessionId: first.id,
      role: 'user',
      question: '第一个会话内容',
    );
    await repo.addChatSessionMessage(
      sessionId: second.id,
      role: 'assistant',
      text: '第二个会话内容',
    );

    final recordMessages = await repo.loadChatMessages();
    final firstMessages = await repo.loadChatSessionMessages(first.id);
    final secondMessages = await repo.loadChatSessionMessages(second.id);
    expect(recordMessages.map((row) => row['question']), ['记一笔午饭']);
    expect(firstMessages.map((row) => row['question']), ['第一个会话内容']);
    expect(secondMessages.map((row) => row['text']), ['第二个会话内容']);

    await expectLater(
      repo.deleteChatSession(ChatSession.recordId),
      throwsA(isA<StateError>()),
    );
    await repo.deleteChatSession(first.id);
    expect(await repo.loadChatSessionMessages(first.id), isEmpty);
    expect(repo.chatSessions.any((item) => item.id == first.id), isFalse);
    expect(repo.chatSessions.any((item) => item.id == second.id), isTrue);
    expect(repo.chatSessions.any((item) => item.isRecord), isTrue);
  });

  test('clearing one conversation never deletes messages from other sessions',
      () async {
    final repo = await freshRepo();
    final first = await repo.createChatSession(title: '第一个会话');
    final second = await repo.createChatSession(title: '第二个会话');

    await repo.addChatMessage(role: 'user', question: '记一笔午饭 20 元');
    await repo.addChatSessionMessage(
      sessionId: first.id,
      role: 'user',
      question: '第一个会话的问题',
    );
    await repo.addChatSessionMessage(
      sessionId: second.id,
      role: 'assistant',
      text: '第二个会话的回答',
    );

    await repo.clearChatSessionMessages(ChatSession.recordId);

    expect(await repo.loadChatMessages(), isEmpty);
    expect(
      (await repo.loadChatSessionMessages(first.id)).single['question'],
      '第一个会话的问题',
    );
    expect(
      (await repo.loadChatSessionMessages(second.id)).single['text'],
      '第二个会话的回答',
    );
    expect(repo.chatSessionById(first.id), isNotNull);
    expect(repo.chatSessionById(second.id), isNotNull);
  });

  test('retry cleanup deletes only the failed answer row in its own session',
      () async {
    final repo = await freshRepo();
    final first = await repo.createChatSession(title: 'first');
    final second = await repo.createChatSession(title: 'second');
    final failedAnswer = await repo.addChatSessionMessage(
      sessionId: first.id,
      role: 'answer',
      text: 'temporary failure',
    );
    await repo.addChatSessionMessage(
      sessionId: first.id,
      role: 'user',
      text: 'keep first user',
    );
    await repo.addChatSessionMessage(
      sessionId: second.id,
      role: 'answer',
      text: 'keep second answer',
    );

    await repo.deleteChatSessionMessage(
      sessionId: first.id,
      messageId: failedAnswer,
    );

    expect(
      (await repo.loadChatSessionMessages(first.id)).map((row) => row['text']),
      ['keep first user'],
    );
    expect(
      (await repo.loadChatSessionMessages(second.id)).map((row) => row['text']),
      ['keep second answer'],
    );
  });

  test('first user message auto-titles a new session', () async {
    final repo = await freshRepo();
    final session = await repo.createChatSession();
    await repo.addChatSessionMessage(
      sessionId: session.id,
      role: 'user',
      question: '帮我看看本月餐饮支出并给一个简短建议',
    );
    expect(repo.chatSessionById(session.id)!.title, '帮我看看本月餐饮支出并给一个简短建议');

    await repo.addChatSessionMessage(
      sessionId: session.id,
      role: 'user',
      question: '第二条消息不应覆盖会话标题',
    );
    expect(repo.chatSessionById(session.id)!.title, '帮我看看本月餐饮支出并给一个简短建议');
  });

  test('writing to a deleted session is rejected without an orphan message',
      () async {
    final repo = await freshRepo();
    final session = await repo.createChatSession();
    await repo.deleteChatSession(session.id);
    await expectLater(
      repo.addChatSessionMessage(
        sessionId: session.id,
        role: 'user',
        question: '不应写入',
      ),
      throwsA(isA<StateError>()),
    );
    expect(await repo.loadChatSessionMessages(session.id), isEmpty);
  });

  test('each session keeps its provider, model, and effort after restart',
      () async {
    final repo = await freshRepo();
    final first = await repo.createChatSession(title: 'Claude');
    final second = await repo.createChatSession(title: 'GPT');
    await repo.saveChatSessionSelection(
      sessionId: first.id,
      providerId: 'claude-relay',
      model: 'claude-sonnet-test',
      effort: AiReasoningEffort.high,
    );
    await repo.saveChatSessionSelection(
      sessionId: second.id,
      providerId: 'openai-relay',
      model: 'gpt-test',
      effort: AiReasoningEffort.ultra,
    );
    await repo.closeForTest();

    final reopened = await freshRepo();
    final restoredFirst = reopened.chatSessions.firstWhere(
      (item) => item.id == first.id,
    );
    final restoredSecond = reopened.chatSessions.firstWhere(
      (item) => item.id == second.id,
    );
    expect(restoredFirst.providerId, 'claude-relay');
    expect(restoredFirst.model, 'claude-sonnet-test');
    expect(restoredFirst.effort, AiReasoningEffort.high);
    expect(restoredSecond.providerId, 'openai-relay');
    expect(restoredSecond.model, 'gpt-test');
    expect(restoredSecond.effort, AiReasoningEffort.ultra);
  });

  test('v44 report jobs migrate into the record session with safe defaults',
      () async {
    final seeded = await freshRepo();
    await seeded.closeForTest();

    final dbPath = p.join(tmp.path, 'qingji.db');
    final legacy = await databaseFactory.openDatabase(dbPath);
    await legacy.transaction((txn) async {
      await txn.execute('DROP TABLE report_jobs');
      await txn.execute('''
        CREATE TABLE report_jobs (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          uuid            TEXT NOT NULL UNIQUE,
          book_id         INTEGER,
          report_id       INTEGER,
          question        TEXT NOT NULL DEFAULT '',
          type            TEXT NOT NULL,
          title           TEXT NOT NULL,
          period_start_ms INTEGER NOT NULL,
          period_end_ms   INTEGER NOT NULL,
          status          TEXT NOT NULL DEFAULT 'queued',
          stage           TEXT NOT NULL DEFAULT 'collect',
          error           TEXT NOT NULL DEFAULT '',
          created_ms      INTEGER NOT NULL DEFAULT 0,
          updated_ms      INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await txn.insert('report_jobs', {
        'uuid': 'legacy-report-job',
        'question': '旧月报',
        'type': 'monthly',
        'title': '旧报告任务',
        'period_start_ms': DateTime(2026, 6, 1).millisecondsSinceEpoch,
        'period_end_ms': DateTime(2026, 6, 30).millisecondsSinceEpoch,
        'created_ms': DateTime(2026, 7, 1).millisecondsSinceEpoch,
        'updated_ms': DateTime(2026, 7, 1).millisecondsSinceEpoch,
      });
      await txn.execute('PRAGMA user_version = 44');
    });
    await legacy.close();

    final repo = await freshRepo();
    final job = await repo.pendingReportJobs();
    expect(job, hasLength(1));
    expect(job.single.sessionId, ChatSession.recordId);
    expect(job.single.providerId, isEmpty);
    expect(job.single.model, isEmpty);
    expect(job.single.effort, AiReasoningEffort.low);

    await repo.closeForTest();
    final migrated = await databaseFactory.openDatabase(dbPath);
    final columns = await migrated.rawQuery('PRAGMA table_info(report_jobs)');
    await migrated.close();
    expect(
      columns.map((column) => column['name']),
      containsAll([
        'session_id',
        'provider_id',
        'model',
        'effort',
        'model_started_ms',
      ]),
    );
  });

  test('report jobs stay in their source Chat and freeze its model selection',
      () async {
    final repo = await freshRepo();
    final firstProvider = await repo.addAiConfiguredProvider(
      displayName: 'Claude Relay',
      baseUrl: 'https://claude.example/v1',
      apiKey: 'claude-key',
      model: 'claude-test',
      models: const ['claude-test'],
    );
    final secondProvider = await repo.addAiConfiguredProvider(
      displayName: 'GPT Relay',
      baseUrl: 'https://gpt.example/v1',
      apiKey: 'gpt-key',
      model: 'gpt-test',
      models: const ['gpt-test'],
    );
    final first = await repo.createChatSession(title: 'Claude 会话');
    final second = await repo.createChatSession(title: 'GPT 会话');
    await repo.saveChatSessionSelection(
      sessionId: first.id,
      providerId: firstProvider.id,
      model: 'claude-test',
      effort: AiReasoningEffort.high,
    );
    await repo.saveChatSessionSelection(
      sessionId: second.id,
      providerId: secondProvider.id,
      model: 'gpt-test',
      effort: AiReasoningEffort.low,
    );

    final firstJob = await repo.createReportJob(
      sessionId: first.id,
      question: '生成 Claude 会话的月报',
      type: 'monthly',
      title: 'Claude 月报',
      periodStart: DateTime(2026, 6, 1),
      periodEnd: DateTime(2026, 6, 30),
    );
    final secondJob = await repo.createReportJob(
      sessionId: second.id,
      question: '生成 GPT 会话的月报',
      type: 'monthly',
      title: 'GPT 月报',
      periodStart: DateTime(2026, 6, 1),
      periodEnd: DateTime(2026, 6, 30),
    );

    expect(firstJob.sessionId, first.id);
    expect(firstJob.providerId, firstProvider.id);
    expect(firstJob.model, 'claude-test');
    expect(firstJob.effort, AiReasoningEffort.high);
    expect(
      (await repo.pendingReportJobs(sessionId: first.id)).map((job) => job.id),
      [firstJob.id],
    );
    expect(
      (await repo.pendingReportJobs(sessionId: second.id)).map((job) => job.id),
      [secondJob.id],
    );

    // Changing the live conversation after queueing must not change the job
    // a later WorkManager run will send.
    await repo.saveChatSessionSelection(
      sessionId: first.id,
      providerId: secondProvider.id,
      model: 'gpt-test',
      effort: AiReasoningEffort.low,
    );
    final snapshotConfig = repo.aiProviderConfigForReportJob(firstJob);
    expect(snapshotConfig, isNotNull);
    final resolvedSnapshot = snapshotConfig!;
    expect(resolvedSnapshot.providerLabel, firstProvider.label);
    expect(resolvedSnapshot.model, 'claude-test');
    expect(resolvedSnapshot.reasoningEffort, AiReasoningEffort.high);

    await repo.completeReportJob(
      jobId: firstJob.id,
      summary: 'Claude 会话的报告摘要',
      markdown: '# Claude 月报',
    );
    expect(
      (await repo.loadChatSessionMessages(first.id))
          .where((row) => row['role'] == 'report'),
      hasLength(1),
    );
    expect(
      (await repo.loadChatSessionMessages(second.id))
          .where((row) => row['role'] == 'report'),
      isEmpty,
    );
    expect(
      (await repo.loadChatMessages()).where((row) => row['role'] == 'report'),
      isEmpty,
    );
  });

  test('scheduled report jobs snapshot their saved provider model and effort',
      () async {
    final repo = await freshRepo();
    final first = await repo.addAiConfiguredProvider(
      displayName: '当前聊天服务商',
      baseUrl: 'https://current.example/v1',
      apiKey: 'current-key',
      model: 'current-model',
      models: const ['current-model'],
    );
    final scheduled = await repo.addAiConfiguredProvider(
      displayName: '定时报表服务商',
      baseUrl: 'https://scheduled.example/v1',
      apiKey: 'scheduled-key',
      model: 'scheduled-default',
      models: const ['scheduled-default', 'scheduled-report'],
    );
    await repo.saveChatModelSelection(
      providerId: first.id,
      model: 'current-model',
      reasoningEffort: AiReasoningEffort.low,
    );

    final job = await repo.createReportJob(
      sessionId: repo.recordChatSession.id,
      question: '生成定时报表',
      type: 'monthly',
      title: '定时月报',
      periodStart: DateTime(2026, 7, 1),
      periodEnd: DateTime(2026, 7, 31),
      providerIdOverride: scheduled.id,
      modelOverride: 'scheduled-report',
      effortOverride: 'high',
    );

    expect(job.providerId, scheduled.id);
    expect(job.model, 'scheduled-report');
    expect(job.effort, AiReasoningEffort.high);
    final config = repo.aiProviderConfigForReportJob(job);
    expect(config, isNotNull);
    final resolvedConfig = config!;
    expect(resolvedConfig.providerLabel, scheduled.label);
    expect(resolvedConfig.model, 'scheduled-report');
    expect(resolvedConfig.reasoningEffort, AiReasoningEffort.high);
    await repo.closeForTest();
  });

  test('scheduled report claim is atomic and weekly period ends on Sunday',
      () async {
    final repo = await freshRepo();
    final provider = await repo.addAiConfiguredProvider(
      displayName: '定时服务商',
      baseUrl: 'https://scheduled.example/v1',
      apiKey: 'scheduled-key',
      model: 'scheduled-model',
      models: const ['scheduled-model'],
    );
    await repo.saveChatModelSelection(
      providerId: provider.id,
      model: provider.model,
      reasoningEffort: AiReasoningEffort.low,
    );
    final schedule = await repo.saveAiReportSchedule(
      AiReportSchedule(
        id: '',
        title: '每周报告',
        periodKind: 'weekly',
        providerId: provider.id,
        model: provider.model,
        effort: 'high',
      ),
    );
    final claimNow = DateTime(2030, 1, 15, 10);
    final due = await repo.dueAiReportSchedules(now: claimNow);
    expect(due, hasLength(1));
    final period = ReportTaskScheduler.schedulePeriodForTest(
      'weekly',
      claimNow,
    );
    expect(period.$1.weekday, DateTime.monday);
    expect(period.$2.weekday, DateTime.sunday);
    expect(period.$2, DateTime(2030, 1, 13));

    final job = await repo.createReportJobFromSchedule(
      schedule: due.single,
      periodStart: period.$1,
      periodEnd: period.$2,
      now: claimNow,
    );
    expect(job, isNotNull);
    expect(
      await repo.createReportJobFromSchedule(
        schedule: due.single,
        periodStart: period.$1,
        periodEnd: period.$2,
        now: claimNow,
      ),
      isNull,
    );
    expect((await repo.pendingReportJobs()), hasLength(1));
    expect((await repo.dueAiReportSchedules(now: claimNow)), isEmpty);
    await repo.closeForTest();
  });

  test('a deleted report provider pauses without silently changing recipient',
      () async {
    final repo = await freshRepo();
    final sourceProvider = await repo.addAiConfiguredProvider(
      displayName: 'Source Relay',
      baseUrl: 'https://source.example/v1',
      apiKey: 'source-key',
      model: 'source-model',
      models: const ['source-model'],
    );
    final fallbackProvider = await repo.addAiConfiguredProvider(
      displayName: 'Fallback Relay',
      baseUrl: 'https://fallback.example/v1',
      apiKey: 'fallback-key',
      model: 'fallback-model',
      models: const ['fallback-model'],
    );
    final session = await repo.createChatSession(title: '待生成报告');
    await repo.saveChatSessionSelection(
      sessionId: session.id,
      providerId: sourceProvider.id,
      model: 'source-model',
      effort: AiReasoningEffort.xhigh,
    );
    final job = await repo.createReportJob(
      sessionId: session.id,
      question: '生成月报',
      type: 'monthly',
      title: '测试月报',
      periodStart: DateTime(2026, 6, 1),
      periodEnd: DateTime(2026, 6, 30),
    );

    await repo.deleteAiConfiguredProvider(sourceProvider.id);
    final config = repo.aiProviderConfigForReportJob(job);
    expect(job.providerId, sourceProvider.id);
    expect(job.model, 'source-model');
    expect(job.effort, AiReasoningEffort.xhigh);
    expect(config, isNull);
    expect(repo.aiProviderById(fallbackProvider.id), isNotNull);
  });

  test('deleting a Chat drops unfinished reports before they can recreate it',
      () async {
    final repo = await freshRepo();
    final session = await repo.createChatSession(title: '将删除的会话');
    final job = await repo.createReportJob(
      sessionId: session.id,
      question: '生成月报',
      type: 'monthly',
      title: '不会写回的月报',
      periodStart: DateTime(2026, 6, 1),
      periodEnd: DateTime(2026, 6, 30),
    );

    await repo.deleteChatSession(session.id);
    expect(await repo.reportJobById(job.id), isNull);
    expect(await repo.pendingReportJobs(sessionId: session.id), isEmpty);
  });
}
