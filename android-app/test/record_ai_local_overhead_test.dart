import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/core/media/chat_attachment.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('qingji_record_perf_');
    await databaseFactory.setDatabasesPath(tmp.path);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('cold ready, dispatch and consecutive local overhead stay bounded',
      () async {
    final cold = Stopwatch()..start();
    final repo = AppRepository();
    await repo.init();
    cold.stop();

    final session = await repo.createChatSession(title: '性能测试');
    const attachment = ChatAttachment(
      kind: ChatAttachmentKind.image,
      path: 'perf.jpg',
      name: 'perf.jpg',
      mimeType: 'image/jpeg',
      sizeBytes: 1024,
    );

    // This is the critical send-path cost after the optimization: schedule
    // durable persistence, then the AI request may start without awaiting it.
    final dispatch = Stopwatch()..start();
    final persistence = repo.addChatSessionMessage(
      sessionId: session.id,
      role: 'user',
      text: '午饭 20',
      attachmentsJson: ChatAttachment.encodeList([attachment]),
    );
    dispatch.stop();
    await persistence;

    final consecutive = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      await repo.addChatSessionMessage(
        sessionId: session.id,
        role: 'user',
        text: '连续记账 $i',
      );
    }
    consecutive.stop();

    final prep = Stopwatch()..start();
    for (var i = 0; i < 100; i++) {
      repo.aiProviderConfigFor(AiTaskType.recordParse);
      repo.llmCategoryOptions(i.isEven ? _expense : _income);
      repo.llmLearnedHints;
    }
    prep.stop();

    final averagePersistenceMs = consecutive.elapsedMilliseconds / 10;
    // ignore: avoid_print
    print('record_ai_perf cold_ready_ms=${cold.elapsedMilliseconds} '
        'dispatch_blocking_ms=${dispatch.elapsedMilliseconds} '
        'consecutive_persist_avg_ms=${averagePersistenceMs.toStringAsFixed(1)} '
        'prepare_100x_ms=${prep.elapsedMilliseconds} '
        'db=${p.join(tmp.path, 'qingji.db')}');

    expect(dispatch.elapsedMilliseconds, lessThan(200));
    expect(averagePersistenceMs, lessThan(200));
    expect(prep.elapsedMilliseconds, lessThan(200));
    await repo.closeForTest();
  });
}

// Kept outside the timed loop so the test measures the production repository
// getters rather than enum allocation.
const _expense = TransactionKind.expense;
const _income = TransactionKind.income;
