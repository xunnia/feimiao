import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Durable activation boundary for the database and its local attachments.
/// A process exit never runs a catch block: startup must finish this journal
/// before SQLite is allowed to create/open the live database.
class RestoreActivation {
  RestoreActivation._(this.databasePath, this.token, this.parts);

  final String databasePath;
  final String token;
  final List<RestoreActivationPart> parts;

  static String journalPath(String databasePath) =>
      '$databasePath.restore-journal.json';

  static Future<bool> needsRecovery(String databasePath) async {
    if (await File(journalPath(databasePath)).exists()) return true;
    if (await File(databasePath).exists()) return false;
    final parent = File(databasePath).parent;
    if (!await parent.exists()) return false;
    final prefix = '${p.basename(databasePath)}.restore-old-';
    return parent.list(followLinks: false).any(
        (entry) => entry is File && p.basename(entry.path).startsWith(prefix));
  }

  File get _journal => File(journalPath(databasePath));
  File get _commit => File('$databasePath.restore-committed-$token');

  RestoreActivationPart get database => parts.first;
  RestoreActivationPart? media(String name) =>
      parts.where((part) => part.name == name).firstOrNull;

  static Future<RestoreActivation> begin({
    required String databasePath,
    required String token,
    Directory? documentsDirectory,
    bool receipts = false,
    bool assetMedia = false,
  }) async {
    _validateToken(token);
    if (await File(journalPath(databasePath)).exists()) {
      throw StateError('上次恢复尚未完成，请重新启动后重试。');
    }
    final parts = <RestoreActivationPart>[];
    for (final name in [
      'database',
      if (receipts) 'receipts',
      if (assetMedia) 'asset_media'
    ]) {
      final live = name == 'database'
          ? databasePath
          : p.join(documentsDirectory!.path, name);
      parts.add(RestoreActivationPart(
        name: name,
        live: live,
        token: token,
        hadOriginal:
            await FileSystemEntity.type(live) != FileSystemEntityType.notFound,
      ));
    }
    final activation = RestoreActivation._(databasePath, token, parts);
    final pending = File('${activation._journal.path}.pending');
    await pending.writeAsString(
        jsonEncode({
          'version': 1,
          'token': token,
          'parts': {for (final part in parts) part.name: part.hadOriginal},
        }),
        flush: true);
    await pending.rename(activation._journal.path);
    return activation;
  }

  /// [documentsDirectory] is supplied by the app, never read from journal JSON.
  /// A malformed journal fails closed and retains all files for recovery.
  static Future<void> recover({
    required String databasePath,
    required Future<Directory> Function() documentsDirectory,
  }) async {
    final journal = File(journalPath(databasePath));
    if (!await journal.exists()) {
      await _recoverLegacyMissingDatabase(databasePath, documentsDirectory);
      return;
    }
    if (await journal.length() > 4096) {
      throw const FormatException('恢复记录无效，原始文件已保留。');
    }
    final raw = jsonDecode(await journal.readAsString());
    if (raw is! Map ||
        raw['version'] != 1 ||
        raw['token'] is! String ||
        raw['parts'] is! Map) {
      throw const FormatException('恢复记录无效，原始文件已保留。');
    }
    final token = raw['token'] as String;
    _validateToken(token);
    final recorded = raw['parts'] as Map;
    if (!recorded.containsKey('database') ||
        recorded.keys.any((key) =>
            !const ['database', 'receipts', 'asset_media'].contains(key)) ||
        recorded.values.any((value) => value is! bool)) {
      throw const FormatException('恢复记录不完整，原始文件已保留。');
    }
    final docs = recorded.length > 1 ? await documentsDirectory() : null;
    final activation = RestoreActivation._(databasePath, token, [
      for (final name in ['database', 'receipts', 'asset_media'])
        if (recorded.containsKey(name))
          RestoreActivationPart(
            name: name,
            live: name == 'database' ? databasePath : p.join(docs!.path, name),
            token: token,
            hadOriginal: recorded[name] as bool,
          ),
    ]);
    if (await activation._commit.exists()) {
      if (await activation._commit.length() != 9 ||
          await activation._commit.readAsString() != 'committed') {
        throw const FormatException('恢复提交记录无效，原始文件已保留。');
      }
      // Committed means the new DB was opened and all app convergence passed.
      // Never replace it with old data just because cleanup was interrupted.
      for (final part in activation.parts) {
        if (!await part.exists(part.live)) {
          throw StateError('已恢复的文件不完整，停止打开以保护原始数据。');
        }
      }
      try {
        await activation._cleanup();
      } on FileSystemException {
        // The committed live files are valid. Optional cleanup must not turn
        // a successful restore into an unavailable ledger.
      }
    } else {
      await activation.rollback();
    }
  }

  Future<void> commit() async {
    final pending = File('${_commit.path}.pending');
    await pending.writeAsString('committed', flush: true);
    await pending.rename(_commit.path);
    // Cleanup failure is not a failed restore: next startup resumes cleanup.
    try {
      await _cleanup();
    } on FileSystemException {
      // Keep the committed journal and remaining old files intact.
    }
  }

  Future<void> rollback() async {
    // Each part is idempotent even if the process dies during rollback itself.
    for (final part in parts.reversed) {
      await part.rollback();
    }
    await _finish();
  }

  Future<void> _cleanup() async {
    for (final part in parts) {
      await part.remove(part.old);
      await part.remove(part.staged);
    }
    await _finish();
  }

  Future<void> _finish() async {
    // Remove the journal first: a leftover commit marker alone is harmless.
    if (await _journal.exists()) await _journal.delete();
    if (await _commit.exists()) await _commit.delete();
  }

  static void _validateToken(String token) {
    if (!RegExp(r'^\d{1,24}$').hasMatch(token)) {
      throw const FormatException('无效的恢复标识。');
    }
  }

  static Future<void> _recoverLegacyMissingDatabase(
      String dbPath, Future<Directory> Function() documentsDirectory) async {
    if (await File(dbPath).exists()) return;
    final parent = File(dbPath).parent;
    if (!await parent.exists()) return;
    final prefix = '${p.basename(dbPath)}.restore-old-';
    final candidates = await parent
        .list(followLinks: false)
        .where((entry) =>
            entry is File && p.basename(entry.path).startsWith(prefix))
        .cast<File>()
        .toList();
    if (candidates.isEmpty) return;
    if (candidates.length != 1) {
      throw StateError('发现多份未完成恢复的原库，请先保留文件并核对，不能创建空库。');
    }
    final token = p.basename(candidates.single.path).substring(prefix.length);
    _validateToken(token);
    // Older versions had no journal. Only recover the unambiguous missing-live
    // case; retain all other artifacts rather than guess which version to use.
    final docs = await documentsDirectory();
    for (final name in ['receipts', 'asset_media']) {
      final part = RestoreActivationPart(
          name: name,
          live: p.join(docs.path, name),
          token: token,
          hadOriginal: true);
      if (await part.exists(part.old)) await part.rollback();
    }
    await candidates.single.rename(dbPath);
  }
}

class RestoreActivationPart {
  RestoreActivationPart(
      {required this.name,
      required this.live,
      required this.token,
      required this.hadOriginal});

  final String name;
  final String live;
  final String token;
  final bool hadOriginal;
  String get staged => '$live.restore-new-$token';
  String get old => '$live.restore-old-$token';
  bool get _isDatabase => name == 'database';

  Future<bool> exists(String path) async =>
      await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  Future<void> remove(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else if (type != FileSystemEntityType.notFound) {
      await File(path).delete();
    }
  }

  Future<void> moveOriginal() async {
    if (await exists(live)) await _rename(live, old);
  }

  Future<void> install() => _rename(staged, live);

  Future<void> _rename(String from, String to) async {
    if (_isDatabase) {
      await File(from).rename(to);
    } else {
      await Directory(from).rename(to);
    }
  }

  Future<void> rollback() async {
    if (await exists(old)) {
      await remove(live);
      if (_isDatabase) {
        for (final suffix in ['-wal', '-shm']) {
          await remove('$live$suffix');
        }
      }
      await _rename(old, live);
    } else if (!hadOriginal) {
      await remove(live);
    } else if (!await exists(live)) {
      throw StateError('原始恢复文件缺失，停止打开以保护数据。');
    }
    await remove(staged);
  }
}
