import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

typedef ReportFencePathProvider = Future<String> Function();
typedef ReportGenerationFactory = String Function();
typedef ReportJobUuidReader = Future<String?> Function(int jobId);

class ReportGenerationInvalidated implements Exception {
  const ReportGenerationInvalidated(
      [this.reason = 'report generation expired']);

  final String reason;

  @override
  String toString() => 'ReportGenerationInvalidated: $reason';
}

/// A lease identifies the database generation in which AI work started.
///
/// A bound lease also carries the stable report-job UUID. Integer IDs alone
/// are unsafe because restoring a backup can reuse them for a different row.
class ReportGenerationLease {
  const ReportGenerationLease._({
    required ReportExecutionFence fence,
    required this.generation,
    this.jobId,
    this.jobUuid,
  }) : _fence = fence;

  final ReportExecutionFence _fence;
  final String generation;
  final int? jobId;
  final String? jobUuid;

  bool get isBound => jobId != null && (jobUuid?.isNotEmpty ?? false);

  String get runtimeKey => '$generation:${jobUuid ?? 'unbound'}';

  ReportGenerationLease bind({
    required int jobId,
    required String jobUuid,
  }) {
    final normalizedUuid = jobUuid.trim();
    if (jobId <= 0) {
      throw ArgumentError.value(jobId, 'jobId', 'must be positive');
    }
    if (normalizedUuid.isEmpty) {
      throw ArgumentError.value(jobUuid, 'jobUuid', 'must not be empty');
    }
    return ReportGenerationLease._(
      fence: _fence,
      generation: generation,
      jobId: jobId,
      jobUuid: normalizedUuid,
    );
  }

  Map<String, Object> toWorkerInput() {
    if (!isBound) {
      throw StateError('only a job-bound lease can be scheduled');
    }
    return {
      'jobId': jobId!,
      'jobUuid': jobUuid!,
      'generation': generation,
    };
  }

  static ReportGenerationLease? tryFromWorkerInput(
    Map<String, dynamic>? inputData, {
    ReportExecutionFence? fence,
  }) {
    final rawJobId = inputData?['jobId'];
    final rawJobUuid = inputData?['jobUuid'];
    final rawGeneration = inputData?['generation'];
    final jobId = rawJobId is num ? rawJobId.toInt() : null;
    final jobUuid = rawJobUuid is String ? rawJobUuid.trim() : '';
    final generation = rawGeneration is String ? rawGeneration.trim() : '';
    if (jobId == null || jobId <= 0 || jobUuid.isEmpty || generation.isEmpty) {
      return null;
    }
    return ReportGenerationLease._(
      fence: fence ?? ReportExecutionFence.shared,
      generation: generation,
      jobId: jobId,
      jobUuid: jobUuid,
    );
  }

  bool matchesJob({required int jobId, required String jobUuid}) =>
      isBound && this.jobId == jobId && this.jobUuid == jobUuid;

  Future<T> guard<T>(
    Future<T> Function() action, {
    required ReportJobUuidReader readJobUuid,
  }) =>
      _fence._guard(this, readJobUuid, action);
}

class ReportExecutionFence {
  ReportExecutionFence({
    ReportFencePathProvider? databasePathProvider,
    ReportGenerationFactory? generationFactory,
  })  : _databasePathProvider = databasePathProvider ?? _defaultDatabasePath,
        _generationFactory = generationFactory ?? _newGeneration;

  static final ReportExecutionFence shared = ReportExecutionFence();

  static const _databaseName = 'feimiao_report_execution_fence.db';
  static const _stateTable = 'fence_state';
  static const _stateId = 1;

  final ReportFencePathProvider _databasePathProvider;
  final ReportGenerationFactory _generationFactory;
  final Object _zoneKey = Object();
  Future<void> _localTail = Future<void>.value();

  Future<ReportGenerationLease> acquire() {
    return _withExclusive((db, databasePath) async {
      final generation = await _ensureGeneration(db, databasePath);
      return ReportGenerationLease._(
        fence: this,
        generation: generation,
      );
    });
  }

  /// Rotates the generation and keeps the exclusive fence held until the
  /// database replacement (or its rollback) has completely converged.
  Future<T> withRestoreBarrier<T>(Future<T> Function() action) async {
    final outcome =
        await _withExclusive<_RestoreOutcome<T>>((db, databasePath) async {
      final generation = _generationFactory().trim();
      if (generation.isEmpty || generation.contains(RegExp(r'[\r\n]'))) {
        throw StateError('report generation factory returned an invalid value');
      }
      // Persist the new generation before replacing the live database. The
      // SQLite fence transaction intentionally stays open across the restore,
      // so its row would roll back if the process were killed mid-replacement.
      // The append-only journal survives that crash and becomes authoritative
      // when the next process opens the fence.
      await _appendDurableGeneration(databasePath, generation);
      await db.insert(
        _stateTable,
        {'id': _stateId, 'generation': generation},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      try {
        final value = await _runWithHeldFence(generation, action);
        return _RestoreSuccess<T>(value);
      } catch (error, stackTrace) {
        // Returning the failure as data lets _withExclusive commit the rotated
        // generation before the original restore failure escapes. Rolling the
        // fence row back would make work from the replaced database valid
        // again after the repository has already converged to its rollback.
        return _RestoreFailure<T>(error, stackTrace);
      }
    });
    return switch (outcome) {
      _RestoreSuccess<T>(:final value) => value,
      _RestoreFailure<T>(:final error, :final stackTrace) =>
        Error.throwWithStackTrace(error, stackTrace),
    };
  }

  Future<T> _guard<T>(
    ReportGenerationLease lease,
    ReportJobUuidReader readJobUuid,
    Future<T> Function() action,
  ) async {
    final held = Zone.current[_zoneKey] as _HeldFence?;
    if (held != null && held.active && identical(held.owner, this)) {
      if (held.generation != lease.generation) {
        throw const ReportGenerationInvalidated();
      }
      await _validateBoundJob(lease, readJobUuid);
      return action();
    }

    return _withExclusive((db, databasePath) async {
      final current = await _readGeneration(db, databasePath);
      if (current == null || current != lease.generation) {
        throw const ReportGenerationInvalidated();
      }
      await _validateBoundJob(lease, readJobUuid);
      return _runWithHeldFence(lease.generation, action);
    });
  }

  Future<T> _runWithHeldFence<T>(
    String generation,
    Future<T> Function() action,
  ) async {
    final held = _HeldFence(this, generation);
    try {
      return await runZoned(
        action,
        zoneValues: {_zoneKey: held},
      );
    } finally {
      held.active = false;
    }
  }

  Future<void> _validateBoundJob(
    ReportGenerationLease lease,
    ReportJobUuidReader readJobUuid,
  ) async {
    if (!lease.isBound) return;
    final currentUuid = await readJobUuid(lease.jobId!);
    if (currentUuid == null || currentUuid != lease.jobUuid) {
      throw const ReportGenerationInvalidated('report job identity changed');
    }
  }

  Future<T> _withExclusive<T>(
    Future<T> Function(Database db, String databasePath) action,
  ) async {
    final predecessor = _localTail;
    final release = Completer<void>();
    _localTail = release.future;
    await predecessor;
    try {
      return await _withDatabaseExclusive(action);
    } finally {
      release.complete();
    }
  }

  Future<T> _withDatabaseExclusive<T>(
    Future<T> Function(Database db, String databasePath) action,
  ) async {
    final path = await _databasePathProvider();
    await Directory(p.dirname(path)).create(recursive: true);
    final db = await openDatabase(
      path,
      version: 1,
      singleInstance: false,
      onConfigure: (database) async {
        await database.execute('PRAGMA busy_timeout = 300000');
      },
      onCreate: (database, _) async {
        await database.execute('''
          CREATE TABLE $_stateTable (
            id INTEGER PRIMARY KEY CHECK (id = $_stateId),
            generation TEXT NOT NULL
          )
        ''');
      },
    );
    var transactionStarted = false;
    try {
      await db.execute('BEGIN EXCLUSIVE');
      transactionStarted = true;
      final value = await action(db, path);
      await db.execute('COMMIT');
      transactionStarted = false;
      return value;
    } catch (_) {
      if (transactionStarted) {
        try {
          await db.execute('ROLLBACK');
        } catch (_) {}
      }
      rethrow;
    } finally {
      await db.close();
    }
  }

  Future<String> _ensureGeneration(Database db, String databasePath) async {
    final existing = await _readGeneration(db, databasePath);
    if (existing != null) return existing;
    final generation = _generationFactory().trim();
    if (generation.isEmpty || generation.contains(RegExp(r'[\r\n]'))) {
      throw StateError('report generation factory returned an invalid value');
    }
    await _appendDurableGeneration(databasePath, generation);
    await db.insert(
      _stateTable,
      {'id': _stateId, 'generation': generation},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return generation;
  }

  Future<String?> _readGeneration(
    Database db,
    String databasePath,
  ) async {
    final rows = await db.query(
      _stateTable,
      columns: ['generation'],
      where: 'id = ?',
      whereArgs: [_stateId],
      limit: 1,
    );
    final stored = rows.isEmpty
        ? null
        : (rows.single['generation'] as String? ?? '').trim();
    final durable = await _readDurableGeneration(databasePath);
    if (durable != null) {
      if (stored != durable) {
        await db.insert(
          _stateTable,
          {'id': _stateId, 'generation': durable},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      return durable;
    }
    if (stored == null || stored.isEmpty) return null;
    await _appendDurableGeneration(databasePath, stored);
    return stored;
  }

  Future<String?> _readDurableGeneration(String databasePath) async {
    final journal = File('$databasePath.generations');
    if (!await journal.exists()) return null;
    final contents = await journal.readAsString();
    final lastTerminator = contents.lastIndexOf('\n');
    if (lastTerminator < 0) return null;
    final completeRecords = contents.substring(0, lastTerminator).split('\n');
    for (var index = completeRecords.length - 1; index >= 0; index--) {
      final value = completeRecords[index].trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  Future<void> _appendDurableGeneration(
    String databasePath,
    String generation,
  ) async {
    if (await _readDurableGeneration(databasePath) == generation) return;
    final journal = File('$databasePath.generations');
    await journal.parent.create(recursive: true);
    final bytes =
        await journal.exists() ? await journal.readAsBytes() : const <int>[];
    final lastTerminator = bytes.lastIndexOf(10);
    final completeLength = lastTerminator + 1;
    final writer = await journal.open(mode: FileMode.append);
    try {
      if (completeLength != bytes.length) {
        await writer.truncate(completeLength);
      }
      await writer.setPosition(completeLength);
      await writer.writeString('$generation\n');
      await writer.flush();
    } finally {
      await writer.close();
    }
  }

  static Future<String> _defaultDatabasePath() async {
    return p.join(await getDatabasesPath(), _databaseName);
  }

  static String _newGeneration() {
    final random = Random.secure();
    final suffix = List.generate(
      12,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '${DateTime.now().microsecondsSinceEpoch}-$suffix';
  }
}

class _HeldFence {
  _HeldFence(this.owner, this.generation);

  final ReportExecutionFence owner;
  final String generation;
  bool active = true;
}

sealed class _RestoreOutcome<T> {
  const _RestoreOutcome();
}

class _RestoreSuccess<T> extends _RestoreOutcome<T> {
  const _RestoreSuccess(this.value);

  final T value;
}

class _RestoreFailure<T> extends _RestoreOutcome<T> {
  const _RestoreFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}
