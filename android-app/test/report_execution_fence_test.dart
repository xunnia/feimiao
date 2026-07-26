import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qingji/core/ai/report_execution_fence.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('qingji_report_fence_test_');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  ReportExecutionFence fenceWithGenerations(List<String> generations) {
    var index = 0;
    return ReportExecutionFence(
      databasePathProvider: () async => p.join(tmp.path, 'fence.db'),
      generationFactory: () => generations[index++],
    );
  }

  test('successful restore rotation invalidates an older report lease',
      () async {
    final fence = fenceWithGenerations(['generation-1', 'generation-2']);
    final lease = (await fence.acquire()).bind(
      jobId: 7,
      jobUuid: 'job-old',
    );

    await fence.withRestoreBarrier(() async {});

    await expectLater(
      lease.guard(
        () async => 'must not run',
        readJobUuid: (_) async => 'job-old',
      ),
      throwsA(isA<ReportGenerationInvalidated>()),
    );
  });

  test('restore waits for a guarded database write before rotating', () async {
    final fence = fenceWithGenerations(['generation-1', 'generation-2']);
    final lease = (await fence.acquire()).bind(
      jobId: 8,
      jobUuid: 'job-current',
    );
    final writeStarted = Completer<void>();
    final releaseWrite = Completer<void>();
    var restoreEntered = false;

    final write = lease.guard(
      () async {
        writeStarted.complete();
        await releaseWrite.future;
      },
      readJobUuid: (_) async => 'job-current',
    );
    await writeStarted.future;

    final restore = fence.withRestoreBarrier(() async {
      restoreEntered = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(restoreEntered, isFalse);

    releaseWrite.complete();
    await write;
    await restore;
    expect(restoreEntered, isTrue);
  });

  test('restore generation is durable before database replacement starts',
      () async {
    final fencePath = p.join(tmp.path, 'fence.db');
    final fence = fenceWithGenerations(['generation-1', 'generation-2']);
    final oldLease = (await fence.acquire()).bind(
      jobId: 9,
      jobUuid: 'job-before-crash',
    );

    await expectLater(
      fence.withRestoreBarrier(() async {
        final journal = await File('$fencePath.generations').readAsString();
        expect(journal.endsWith('\n'), isTrue);
        expect(
          journal.trim().split('\n').last,
          'generation-2',
        );
        throw StateError('simulated replacement failure');
      }),
      throwsStateError,
    );

    await expectLater(
      oldLease.guard(
        () async => 'must not run',
        readJobUuid: (_) async => 'job-before-crash',
      ),
      throwsA(isA<ReportGenerationInvalidated>()),
    );
  });

  test('an interrupted journal tail is discarded before the next rotation',
      () async {
    final fencePath = p.join(tmp.path, 'fence.db');
    final fence = fenceWithGenerations(['generation-1', 'generation-2']);
    final oldLease = (await fence.acquire()).bind(
      jobId: 10,
      jobUuid: 'job-before-partial-tail',
    );
    await File('$fencePath.generations').writeAsString('partial-generation',
        mode: FileMode.append, flush: true);

    await fence.withRestoreBarrier(() async {});

    final records = (await File('$fencePath.generations').readAsString())
        .trim()
        .split('\n');
    expect(records, ['generation-1', 'generation-2']);
    await expectLater(
      oldLease.guard(
        () async => 'must not run',
        readJobUuid: (_) async => 'job-before-partial-tail',
      ),
      throwsA(isA<ReportGenerationInvalidated>()),
    );
  });

  test('same integer job id with another UUID is rejected', () async {
    final fence = fenceWithGenerations(['generation-1']);
    final lease = (await fence.acquire()).bind(
      jobId: 9,
      jobUuid: 'job-before-restore',
    );
    var actionRan = false;

    await expectLater(
      lease.guard(
        () async {
          actionRan = true;
        },
        readJobUuid: (_) async => 'job-from-restored-database',
      ),
      throwsA(isA<ReportGenerationInvalidated>()),
    );
    expect(actionRan, isFalse);
  });

  test('worker input preserves generation and stable job identity', () async {
    final fence = fenceWithGenerations(['generation-1']);
    final original = (await fence.acquire()).bind(
      jobId: 10,
      jobUuid: 'job-worker',
    );

    final restored = ReportGenerationLease.tryFromWorkerInput(
      original.toWorkerInput(),
      fence: fence,
    );

    expect(restored, isNotNull);
    expect(restored!.generation, 'generation-1');
    expect(restored.matchesJob(jobId: 10, jobUuid: 'job-worker'), isTrue);
    expect(restored.runtimeKey, 'generation-1:job-worker');
  });
}
