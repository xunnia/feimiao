import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_version.dart';

/// App 内检查更新：version.json 和 APK 托管在用户自己的 Cloudflare Worker/KV。
/// versionCode 比本机大才算有更新。
class AppUpdateInfo {
  final String versionName;
  final int versionCode;
  final String url;
  final String notes;
  final int sizeBytes;
  final String sha256;
  final String releaseId;

  const AppUpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.url,
    required this.notes,
    required this.sizeBytes,
    required this.sha256,
    required this.releaseId,
  });

  static AppUpdateInfo? fromJson(Map<String, dynamic> json) {
    final code = json['versionCode'];
    final url = json['url'];
    if (code is! int || url is! String || url.isEmpty) return null;
    return AppUpdateInfo(
      versionName: (json['versionName'] as String?) ?? '',
      versionCode: code,
      url: url,
      notes: (json['notes'] as String?) ?? '',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      sha256: sanitizeSha256(json['sha256'] as String?),
      releaseId: ((json['releaseId'] as String?) ?? '').trim(),
    );
  }

  /// sha256 必须是 64 位十六进制；发布链路出过「sha256sum 转义反斜杠前缀」
  /// 污染字段的事故（v177），格式不对宁可当没有（走响应头兜底/跳过校验），
  /// 也不能拿脏值去比对——那会让用户下满整包后必定「校验失败」。
  static String sanitizeSha256(String? raw) {
    final s =
        (raw ?? '').trim().toLowerCase().replaceFirst(RegExp(r'^\\+'), '');
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(s) ? s : '';
  }

  String get sizeText => sizeBytes <= 0
      ? ''
      : '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// A historical build that was repackaged with a monotonically increasing
/// Android install versionCode.  Android's ordinary package installer will
/// only replace an installed package when the signing certificate matches and
/// the package versionCode is not lower.  [sourceVersionCode] is the version
/// users recognise; [installVersionCode] is the immutable install sequence
/// used by the OS.
class AppRollbackInfo {
  final String versionName;
  final int sourceVersionCode;
  final int installVersionCode;
  final String url;
  final String notes;
  final int sizeBytes;
  final String sha256;
  final String releaseId;
  final int? databaseVersion;

  const AppRollbackInfo({
    required this.versionName,
    required this.sourceVersionCode,
    required this.installVersionCode,
    required this.url,
    required this.notes,
    required this.sizeBytes,
    required this.sha256,
    required this.releaseId,
    this.databaseVersion,
  });

  static AppRollbackInfo? fromJson(Map<String, dynamic> json) {
    final sourceCode = _readPositiveInt(
      json['sourceVersionCode'] ??
          json['source_version_code'] ??
          json['versionCode'],
    );
    final installCode = _readPositiveInt(
      json['installVersionCode'] ?? json['install_version_code'],
    );
    final nameRaw = json['versionName'] ?? json['version_name'];
    final name = nameRaw is String ? nameRaw : null;
    final rawUrl = json['url'];
    if (sourceCode == null ||
        installCode == null ||
        name == null ||
        name.trim().isEmpty ||
        rawUrl is! String ||
        !isSecureUpdateUrl(rawUrl)) {
      return null;
    }
    final releaseId =
        (json['releaseId'] ?? json['release_id'] ?? '').toString().trim();
    if (!RegExp(r'^v\d+-[0-9a-f]{12}$').hasMatch(releaseId)) return null;
    final db = _readPositiveInt(
      json['databaseVersion'] ?? json['database_version'],
    );
    return AppRollbackInfo(
      versionName: name.trim(),
      sourceVersionCode: sourceCode,
      installVersionCode: installCode,
      url: rawUrl.trim(),
      notes: json['notes'] is String ? json['notes'] as String : '',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      sha256: AppUpdateInfo.sanitizeSha256(json['sha256'] as String?),
      releaseId: releaseId,
      databaseVersion: db,
    );
  }

  /// Convert the catalog entry to the same download/install pipeline used by
  /// normal updates.  The install sequence, rather than the historical source
  /// code, is intentionally passed to DownloadManager and the installer.
  AppUpdateInfo get installInfo => AppUpdateInfo(
        versionName: versionName,
        versionCode: installVersionCode,
        url: url,
        notes: notes,
        sizeBytes: sizeBytes,
        sha256: sha256,
        releaseId: releaseId,
      );

  String get sizeText => installInfo.sizeText;
}

int? _readPositiveInt(Object? raw) {
  final value = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
  return value != null && value > 0 ? value : null;
}

bool isSecureUpdateUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  return uri != null &&
      uri.scheme.toLowerCase() == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}

class AppUpdate {
  AppUpdate._();

  static const versionJsonUrl =
      'https://updates.xunni9481.dpdns.org/version.json';
  static const rollbackJsonUrl =
      'https://updates.xunni9481.dpdns.org/rollback.json';
  static const _channel = MethodChannel('feimiao/update');
  static const _headerTimeout = Duration(seconds: 30);
  static const _idleTimeout = Duration(seconds: 60);
  static const _overallTimeout = Duration(minutes: 30);

  /// 查询是否有新版本；网络失败 / 解析失败一律返回 null，不打扰用户。
  static Future<AppUpdateInfo?> check() async {
    try {
      final resp = await http
          .get(Uri.parse(versionJsonUrl))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final info = AppUpdateInfo.fromJson(
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>,
      );
      if (info == null) return null;
      return info.versionCode > await installedVersionCode() ? info : null;
    } catch (_) {
      return null;
    }
  }

  /// The compile-time Flutter build number is not sufficient after installing
  /// a rollback-compatible APK: its Dart code intentionally keeps the old
  /// source version while Android sees a newer install sequence.  Ask the
  /// package manager for the value that will actually gate the next install.
  /// Non-Android tests and old builds fall back to the compile-time value.
  static Future<int> installedVersionCode() async {
    try {
      final value = await _channel.invokeMethod<num>('installedVersionCode');
      final code = value?.toInt() ?? 0;
      if (code > 0) return code;
    } catch (_) {}
    return AppVersion.buildNumber;
  }

  /// Fetch the immutable historical-build catalog.  APK bytes are not
  /// embedded in the catalog: each entry may point to the worker's immutable
  /// release endpoint or to an external HTTPS archive (for example a GitHub
  /// Release/R2 object), so KV retention can keep only the active pair.
  static Future<List<AppRollbackInfo>> fetchRollbackCatalog() async {
    try {
      final resp = await http
          .get(Uri.parse(rollbackJsonUrl))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return const [];
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      final rawEntries = decoded is List
          ? decoded
          : decoded is Map<String, dynamic>
              ? (decoded['versions'] ??
                  decoded['rollbacks'] ??
                  decoded['items'])
              : null;
      if (rawEntries is! List) return const [];
      final entries = <AppRollbackInfo>[];
      final seen = <String>{};
      for (final raw in rawEntries) {
        if (raw is! Map) continue;
        final entry = AppRollbackInfo.fromJson(
          Map<String, dynamic>.from(raw),
        );
        if (entry == null || !seen.add(entry.releaseId)) continue;
        entries.add(entry);
      }
      entries.sort(
        (a, b) => b.sourceVersionCode.compareTo(a.sourceVersionCode) == 0
            ? b.installVersionCode.compareTo(a.installVersionCode)
            : b.sourceVersionCode.compareTo(a.sourceVersionCode),
      );
      return entries;
    } catch (_) {
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // 后台下载（系统 DownloadManager）：切后台/锁屏/杀进程都继续下，
  // 通知栏自带进度；进程内下载 [download] 保留作个别 ROM 禁用下载管理器时的兜底。
  // ---------------------------------------------------------------------------

  /// 交给系统 DownloadManager 下载，返回 downloadId；null = 系统侧不可用（走兜底）。
  static Future<int?> startBackgroundDownload(AppUpdateInfo info) async {
    try {
      final id = await _channel.invokeMethod<int>('startDownload', {
        'url': info.url,
        'fileName': 'feimiao-update-${info.versionCode}.apk',
        'title': '肥喵记账 v${info.versionName}',
        'versionCode': info.versionCode,
      });
      return id;
    } catch (_) {
      return null;
    }
  }

  /// 查询系统下载进度。null = 通道异常；status 为
  /// running/pending/paused/successful/failed/missing。
  static Future<UpdateDownloadStatus?> queryDownload(int id) async {
    try {
      final raw = await _channel
          .invokeMapMethod<String, Object?>('queryDownload', {'id': id});
      if (raw == null) return null;
      return UpdateDownloadStatus(
        status: (raw['status'] as String?) ?? 'missing',
        received: (raw['received'] as num?)?.toInt() ?? 0,
        total: (raw['total'] as num?)?.toInt() ?? 0,
        reason: (raw['reason'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> cancelDownload(int id) async {
    try {
      await _channel.invokeMethod<bool>('cancelDownload', {'id': id});
    } catch (_) {}
  }

  /// 上次入队且未清理的更新下载（冷启动接续：下载完了但还没装）。
  static Future<PendingUpdateDownload?> pendingDownload() async {
    try {
      final raw =
          await _channel.invokeMapMethod<String, Object?>('pendingDownload');
      if (raw == null) return null;
      final id = (raw['id'] as num?)?.toInt();
      if (id == null || id < 0) return null;
      return PendingUpdateDownload(
        id: id,
        versionCode: (raw['versionCode'] as num?)?.toInt() ?? 0,
        path: (raw['path'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearPendingDownload() async {
    try {
      await _channel.invokeMethod<bool>('clearPendingDownload');
    } catch (_) {}
  }

  static Future<void> discardPendingDownload(
    PendingUpdateDownload pending,
  ) async {
    await cancelDownload(pending.id);
    final path = pending.path.trim();
    if (path.isNotEmpty) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    await clearPendingDownload();
  }

  /// 已经安装到本机的旧版本下载不再有价值，启动检查时顺手清理。
  static Future<void> cleanupObsoletePendingDownload() async {
    final pending = await pendingDownload();
    if (pending != null &&
        pending.versionCode <= await installedVersionCode()) {
      await discardPendingDownload(pending);
    }
  }

  /// 流式校验文件 SHA256。expected 为空（元数据没给）时直接放行。
  static Future<bool> verifyFileSha256(String path, String expected) async {
    if (expected.isEmpty) return true;
    try {
      final f = File(path);
      if (!await f.exists()) return false;
      final digestSink = _DigestSink();
      final hashSink = sha256.startChunkedConversion(digestSink);
      await for (final chunk in f.openRead()) {
        hashSink.add(chunk);
      }
      hashSink.close();
      final actual = digestSink.value?.toString().toLowerCase() ?? '';
      return actual == expected;
    } catch (_) {
      return false;
    }
  }

  /// 流式下载 APK 到应用缓存目录，[onProgress] 回调 0~1；未知总长回调 -1。
  /// 下载完成后如果 version.json 提供 sha256，会先校验再交给系统安装器。
  static Future<File> download(
    AppUpdateInfo info, {
    void Function(double progress)? onProgress,
    Directory? downloadDirectory,
  }) async {
    final Directory dir;
    if (downloadDirectory != null) {
      dir = downloadDirectory;
    } else {
      final externals = await getExternalCacheDirectories();
      if (externals != null && externals.isNotEmpty) {
        dir = externals.first;
      } else {
        dir = await getTemporaryDirectory();
      }
    }
    if (!await dir.exists()) await dir.create(recursive: true);
    final out =
        File(p.join(dir.path, 'feimiao-update-${info.versionCode}.apk'));
    final partial = File('${out.path}.part');
    if (await out.exists()) {
      final reusable = info.sha256.isNotEmpty &&
          await verifyFileSha256(out.path, info.sha256);
      if (reusable) return out;
      await out.delete();
    }

    final client = http.Client();
    final req = http.Request('GET', Uri.parse(info.url));
    var resumeFrom = await partial.exists() ? await partial.length() : 0;
    if (resumeFrom > 0) req.headers['Range'] = 'bytes=$resumeFrom-';
    final digestSink = _DigestSink();
    final hashSink = sha256.startChunkedConversion(digestSink);
    var hashSinkClosed = false;
    IOSink? sink;

    try {
      final resp = await client.send(req).timeout(_headerTimeout);
      final isPartial = resumeFrom > 0 && resp.statusCode == 206;
      if (resp.statusCode != 200 && !isPartial) {
        throw Exception('下载失败：HTTP ${resp.statusCode}');
      }
      if (isPartial) {
        final contentRange = resp.headers['content-range'] ?? '';
        if (!contentRange.startsWith('bytes $resumeFrom-')) {
          throw Exception('服务器续传范围不一致');
        }
        await for (final chunk in partial.openRead()) {
          hashSink.add(chunk);
        }
      } else {
        resumeFrom = 0;
      }
      final rangeTotal = isPartial
          ? int.tryParse(
              (resp.headers['content-range'] ?? '').split('/').last,
            )
          : null;
      final total = rangeTotal ??
          (resp.contentLength == null
              ? info.sizeBytes
              : resumeFrom + resp.contentLength!);
      var received = resumeFrom;
      final deadline = DateTime.now().add(_overallTimeout);
      sink = partial.openWrite(
        mode: isPartial ? FileMode.append : FileMode.write,
      );
      onProgress?.call(total > 0 ? received / total : -1);

      await for (final chunk in resp.stream.timeout(_idleTimeout)) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('下载超时', _overallTimeout);
        }
        sink.add(chunk);
        hashSink.add(chunk);
        received += chunk.length;
        onProgress?.call(total > 0 ? received / total : -1);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      hashSink.close();
      hashSinkClosed = true;

      if (total > 0 && received != total) {
        throw Exception('下载不完整（$received/$total）');
      }
      // version.json 没给（或格式脏被清掉）时，退回 Worker 从 manifest
      // 透传的 x-feimiao-sha256 响应头，尽量不放弃完整性校验。
      var expected = info.sha256;
      if (expected.isEmpty) {
        expected =
            AppUpdateInfo.sanitizeSha256(resp.headers['x-feimiao-sha256']);
      }
      if (expected.isNotEmpty) {
        final actual = digestSink.value?.toString().toLowerCase() ?? '';
        if (actual != expected) {
          if (await partial.exists()) await partial.delete();
          throw Exception('安装包校验失败');
        }
      }
      if (await out.exists()) await out.delete();
      await partial.rename(out.path);
      return out;
    } finally {
      client.close();
      if (!hashSinkClosed) hashSink.close();
      try {
        await sink?.close();
      } catch (_) {}
      // 失败时保留 .part，下一次走 Range 续传；完整 APK 只在校验成功后出现。
    }
  }

  /// 调系统安装器覆盖安装（同签名无缝升级）。
  static Future<bool> install(File apk) async {
    try {
      final ok =
          await _channel.invokeMethod<bool>('installApk', {'path': apk.path});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// 系统 DownloadManager 一次下载的状态快照。
class UpdateDownloadStatus {
  final String status; // running/pending/paused/successful/failed/missing
  final int received;
  final int total;
  final int reason;

  const UpdateDownloadStatus({
    required this.status,
    required this.received,
    required this.total,
    required this.reason,
  });

  bool get isTerminal =>
      status == 'successful' || status == 'failed' || status == 'missing';

  double get progress => total > 0 ? (received / total).clamp(0.0, 1.0) : -1;
}

/// 跨启动挂起的更新下载记录。
class PendingUpdateDownload {
  final int id;
  final int versionCode;
  final String path;

  const PendingUpdateDownload({
    required this.id,
    required this.versionCode,
    required this.path,
  });
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
