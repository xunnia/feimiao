import 'dart:async';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/chat_operation_lease.dart';
import 'package:qingji/core/ai/chat_session.dart';
import 'package:qingji/core/ai/ai_run.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temp;
  late AppRepository repo;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('feimiao_chat_lease_');
    await databaseFactory.setDatabasesPath(temp.path);
    repo = AppRepository();
    await repo.init();
  });
  tearDown(() async {
    await repo.closeForTest();
    await temp.delete(recursive: true);
  });

  TransactionDraft draft({int? bookId}) => TransactionDraft(
        bookId: bookId,
        kind: TransactionKind.expense,
        amount: Decimal.parse('18.50'),
        accountId: repo.transactionAccounts.first.id,
        date: DateTime(2026, 10, 4),
        note: 'lease test',
      );

  test('发起后切换账本仍写入发起账本，不读保存时选择', () async {
    final lease = repo.captureChatOperation(ChatSession.recordId);
    expect(lease.bookUuid, isNotEmpty);
    final other = await repo.addBook(name: '另一个账本');
    await repo.switchBook(other);
    final ids =
        await lease.run(() => repo.addTransactionDraftsAtomically([draft()]));
    expect(repo.transactionById(ids.single)!.bookId, lease.bookId);
    expect(repo.currentBookId, other);
  });

  test('清空后迟到消息和账单都被拒绝，另一会话仍可写入', () async {
    final session = await repo.createChatSession();
    final old = repo.captureChatOperation(ChatSession.recordId);
    final other = repo.captureChatOperation(session.id);
    await repo.clearChatSessionMessages(ChatSession.recordId);
    await expectLater(
        old.run(() => repo.addChatMessage(role: 'answer', text: '迟到')),
        throwsA(isA<ChatOperationInvalidated>()));
    await expectLater(
        old.run(() => repo.addTransactionDraftsAtomically([draft()])),
        throwsA(isA<ChatOperationInvalidated>()));
    await other.run(() => repo.addChatSessionMessage(
        sessionId: session.id, role: 'answer', text: '另一个会话'));
    expect(await repo.loadChatMessages(), isEmpty);
    expect(await repo.loadChatSessionMessages(session.id), hasLength(1));
  });

  test('清空写库失败仍通知重读，保留记录但撤销旧请求', () async {
    await repo.addChatMessage(role: 'user', text: '应保留的原记录');
    final lease = repo.captureChatOperation(ChatSession.recordId);
    final db = await databaseFactory.openDatabase('${temp.path}/qingji.db');
    await db.execute("CREATE TRIGGER reject_chat_delete BEFORE DELETE ON "
        "chat_messages BEGIN SELECT RAISE(ABORT, 'local delete failure'); END");
    var notifications = 0;
    repo.addListener(() => notifications++);
    await expectLater(repo.clearChatSessionMessages(ChatSession.recordId),
        throwsA(isA<DatabaseException>()));
    expect(notifications, 1);
    expect(repo.isChatOperationCurrent(lease), isFalse);
    expect((await repo.loadChatMessages()).single['text'], '应保留的原记录');
    await db.execute('DROP TRIGGER reject_chat_delete');
    await repo.clearChatSessionMessages(ChatSession.recordId);
    expect(await repo.loadChatMessages(), isEmpty);
  });

  test('排队写库在清空后恢复执行不能回写', () async {
    final lease = repo.captureChatOperation(ChatSession.recordId);
    final gate = Completer<void>();
    final lateWrite = lease.run(() async {
      await gate.future;
      return repo.addChatMessage(role: 'answer', text: '迟到');
    });
    final assertion =
        expectLater(lateWrite, throwsA(isA<ChatOperationInvalidated>()));
    await repo.clearChatSessionMessages(ChatSession.recordId);
    gate.complete();
    await assertion;
    expect(await repo.loadChatMessages(), isEmpty);
  });

  test('取消、跨仓库、错账本及跨会话租约不能写账', () async {
    final cancelled = repo.captureChatOperation(ChatSession.recordId)..cancel();
    await expectLater(
        cancelled.run(() => repo.addTransactionDraftsAtomically([draft()])),
        throwsA(isA<ChatOperationInvalidated>()));
    final fresh = repo.captureChatOperation(ChatSession.recordId);
    final otherBook = await repo.addBook(name: '错误归属');
    await expectLater(
        fresh.run(() =>
            repo.addTransactionDraftsAtomically([draft(bookId: otherBook)])),
        throwsA(isA<ChatOperationInvalidated>()));
    final session = await repo.createChatSession();
    await expectLater(
        fresh.run(() =>
            repo.addChatSessionMessage(sessionId: session.id, role: 'answer')),
        throwsA(isA<ChatOperationInvalidated>()));
    expect(AppRepository().isChatOperationCurrent(fresh), isFalse);
  });

  test('全部清空也会使未曾单独清空过的会话租约失效', () async {
    final lease = repo.captureChatOperation(ChatSession.recordId);
    await repo.clearChatMessages();
    expect(repo.isChatOperationCurrent(lease), isFalse);
  });

  test('删除会话使迟到提案失效，不影响另一会话', () async {
    final session = await repo.createChatSession();
    final lease = repo.captureChatOperation(session.id);
    final other = repo.captureChatOperation(ChatSession.recordId);
    await repo.deleteChatSession(session.id);
    expect(repo.isChatOperationCurrent(lease), isFalse);
    expect(repo.isChatOperationCurrent(other), isTrue);
    await expectLater(
        lease.run(() => repo.addTransactionDraftsAtomically([draft()])),
        throwsA(isA<ChatOperationInvalidated>()));
  });

  test('清空后旧请求不能改运行状态或追加事件', () async {
    final lease = repo.captureChatOperation(ChatSession.recordId);
    final run = await lease.run(() => repo.createOrGetAiRun(
        sessionId: ChatSession.recordId,
        mode: AiRunMode.chat,
        config: AiProviderConfig.deepSeek(apiKey: 'test-only'),
        idempotencyKey: 'run-fence-test'));
    final events = await repo.loadAiRunEvents(run.id);
    await repo.clearChatSessionMessages(ChatSession.recordId);
    await expectLater(
        lease
            .run(() => repo.updateAiRun(run.id, status: AiRunStatus.completed)),
        throwsA(isA<ChatOperationInvalidated>()));
    await expectLater(
        lease
            .run(() => repo.appendAiRunEvent(run.id, AiRunEventType.completed)),
        throwsA(isA<ChatOperationInvalidated>()));
    expect((await repo.aiRunById(run.id))!.status, AiRunStatus.queued);
    expect(await repo.loadAiRunEvents(run.id), hasLength(events.length));
  });

  test('账本编号相同但稳定标识不同拒绝保存', () async {
    final lease = repo.captureChatOperation(ChatSession.recordId,
        bookId: repo.currentBookId, bookUuid: 'different-database-book');
    await expectLater(
        lease.run(() => repo.addTransactionDraftsAtomically([draft()])),
        throwsA(isA<ChatOperationInvalidated>()));
  });

  test('清空只撤销当前会话未完成报告，保留完成文档和其他会话任务', () async {
    final other = await repo.createChatSession();
    Future<ReportJobEntity> create(String sessionId) => repo.createReportJob(
        question: '生成本月报告',
        type: 'monthly',
        title: '本月报告',
        periodStart: DateTime(2026, 10),
        periodEnd: DateTime(2026, 11),
        sessionId: sessionId);
    final pending = await create(ChatSession.recordId);
    final completed = await create(ChatSession.recordId);
    final report = await repo.completeReportJob(
        jobId: completed.id,
        expectedJobUuid: completed.uuid,
        summary: '已生成',
        markdown: '已生成报告');
    final otherPending = await create(other.id);
    await repo.clearChatSessionMessages(ChatSession.recordId);
    expect(await repo.reportJobById(pending.id), isNull);
    expect(await repo.reportJobById(completed.id), isNotNull);
    expect(await repo.getReport(report.id), isNotNull);
    expect(await repo.reportJobById(otherPending.id), isNotNull);
    await expectLater(
        repo.completeReportJob(
            jobId: pending.id,
            expectedJobUuid: pending.uuid,
            summary: '迟到',
            markdown: '迟到报告'),
        throwsStateError);
    expect(await repo.loadChatMessages(), isEmpty);
    expect((await repo.pendingReportJobs()).single.id, otherPending.id);
    await repo.clearChatMessages();
    expect(await repo.pendingReportJobs(), isEmpty);
    expect(await repo.getReport(report.id), isNotNull);
  });

  test('清空后旧菜单不能删新消息、学习分类或创建报告', () async {
    final old = repo.captureChatOperation(ChatSession.recordId);
    await repo.clearChatSessionMessages(ChatSession.recordId);
    final newRow = await repo.addChatMessage(role: 'user', text: '新消息');
    await expectLater(
        old.run(() => repo.deleteChatSessionMessage(
            sessionId: ChatSession.recordId, messageId: newRow)),
        throwsA(isA<ChatOperationInvalidated>()));
    await expectLater(
        old.run(() => repo.learnCategory(
            phrase: '午餐',
            kind: TransactionKind.expense,
            categoryKey: 'dining')),
        throwsA(isA<ChatOperationInvalidated>()));
    await expectLater(
        old.run(() => repo.createReportJob(
            question: '迟到报告',
            type: 'monthly',
            title: '旧请求',
            periodStart: DateTime(2026, 10),
            periodEnd: DateTime(2026, 11))),
        throwsA(isA<ChatOperationInvalidated>()));
    expect((await repo.loadChatMessages()).single['text'], '新消息');
    expect(repo.categoryMemories, isEmpty);
    expect(await repo.pendingReportJobs(), isEmpty);
  });

  test('成功和回滚的备份恢复都会撤销旧请求权限', () async {
    final docs = await Directory('${temp.path}/documents').create();
    final exports = await Directory('${temp.path}/exports').create();
    final package = await repo.exportBackupPackage(
        documentsDirectory: docs, temporaryDirectory: exports);
    for (final fail in [false, true]) {
      final lease = repo.captureChatOperation(ChatSession.recordId);
      final restored = await repo.restoreBackupPackage(package.path,
          documentsDirectory: docs,
          temporaryDirectory: exports, onRestoreStep: (step) {
        if (fail && step == 'before_database_open') {
          throw StateError('activation failure');
        }
      });
      expect(restored, !fail);
      expect(repo.isChatOperationCurrent(lease), isFalse);
      await expectLater(
          lease.run(() => repo.addTransactionDraftsAtomically([draft()])),
          throwsA(isA<ChatOperationInvalidated>()));
    }
  });
}
