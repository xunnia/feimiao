import 'dart:convert';
import 'dart:math';

import '../security/secure_key_store.dart';
import 'cloud_models.dart';
import 'cloud_errors.dart';
import 'cloud_session_guard.dart';

/// 键值型的安全存储。正式环境用 [SecureKeyStore]（Android Keystore），
/// 测试用 [MemoryCloudSecretStore]。
abstract class CloudSecretStore {
  Future<String?> read(String key);
  Future<bool> write(String key, String value);
  Future<bool> delete(String key);
}

class SecureCloudSecretStore implements CloudSecretStore {
  const SecureCloudSecretStore();

  @override
  Future<String?> read(String key) => SecureKeyStore.read(key);

  @override
  Future<bool> write(String key, String value) =>
      SecureKeyStore.write(key, value);

  @override
  Future<bool> delete(String key) => SecureKeyStore.delete(key);
}

class MemoryCloudSecretStore implements CloudSecretStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<bool> write(String key, String value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<bool> delete(String key) async => values.remove(key) != null;
}

/// 缓存的权益，带 ETag 和拉取时间（离线时显示"更新于…"）。
class CachedEntitlements {
  const CachedEntitlements({
    required this.json,
    required this.etag,
    required this.fetchedAt,
  });

  final Map<String, Object?> json;
  final String? etag;
  final DateTime fetchedAt;

  Entitlements get value => Entitlements.fromJson(json);
}

/// 账号相关的本机持久化：安装 ID、令牌、权益缓存。全部放安全存储。
///
/// 安装 ID 跟着"这次安装"走，退出登录不清；令牌和权益缓存退出登录就清。
class CloudSessionStore {
  CloudSessionStore(
      {CloudSecretStore? store, CloudSessionGuard? guard, Random? random})
      : _store = store ?? const SecureCloudSecretStore(),
        _guard = guard ?? FileCloudSessionGuard(),
        _random = random ?? Random.secure();

  static const installIdKey = 'fm_cloud_install_id_v1';
  static const tokensKey = 'fm_cloud_tokens_v1';
  static const entitlementsKey = 'fm_cloud_entitlements_v1';

  final CloudSecretStore _store;
  final CloudSessionGuard _guard;
  final Random _random;
  String? _installId;
  Future<String>? _installIdInFlight;
  Future<void> _sessionTail = Future.value();
  int _sessionGeneration = 0;

  int get sessionGeneration => _sessionGeneration;

  /// 同步使旧读写失效；已进入底层存储的写入由队列保证先于新会话清理完成。
  int beginSession() => ++_sessionGeneration;

  Future<T> _sessionOperation<T>(
    Future<T> Function() operation, {
    int? generation,
  }) {
    final expected = generation ?? _sessionGeneration;
    final run = _sessionTail.then((_) {
      if (expected != _sessionGeneration) {
        throw CloudApiException.sessionChanged();
      }
      return operation();
    });
    _sessionTail =
        run.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return run;
  }

  /// 首次调用时生成 UUID v4 并保存，之后一直返回同一个。
  Future<String> installId() => _installIdInFlight ??= _loadInstallId();

  Future<String> _loadInstallId() async {
    try {
      final cached = _installId;
      if (cached != null) return cached;
      final stored = await _store.read(installIdKey);
      if (stored != null && isUuid(stored)) return _installId = stored;
      final created = newUuidV4(_random);
      if (!await _store.write(installIdKey, created)) {
        throw CloudApiException.storageFailure();
      }
      return _installId = created;
    } finally {
      _installIdInFlight = null;
    }
  }

  Future<CloudTokens?> readTokens() => _sessionOperation(() async {
        if (await _isBlocked()) {
          // Retry old credential/cache cleanup on every restart, but keep the
          // durable guard until a new login has actually saved new tokens.
          try {
            await _clearSessionValues();
          } on CloudApiException {
            // The independent guard still prevents restoring these secrets.
          }
          return null;
        }
        final decoded = _decode(await _store.read(tokensKey));
        if (decoded == null) return null;
        final tokens = CloudTokens.fromStorage(decoded);
        return tokens.isUsable ? tokens : null;
      });

  Future<void> writeTokens(CloudTokens tokens, {int? generation}) {
    final expected = generation ?? _sessionGeneration;
    return _sessionOperation(() async {
      if (!await _store.write(tokensKey, jsonEncode(tokens.toStorage()))) {
        throw CloudApiException.storageFailure();
      }
      if (expected != _sessionGeneration) {
        // A write already inside the secure store finishes before the queued
        // new-session cleanup. It must not reopen that session's logout guard.
        return;
      }
      // Only a successfully persisted new credential can reopen restoration.
      await _setBlocked(false);
    }, generation: expected);
  }

  Future<CachedEntitlements?> readEntitlements() => _sessionOperation(() async {
        if (await _isBlocked()) return null;
        final decoded = _decode(await _store.read(entitlementsKey));
        if (decoded == null) return null;
        final json = decoded['json'];
        final fetchedMs = decoded['fetched_at_ms'];
        final etag = decoded['etag'];
        if (json is! Map ||
            (etag != null && etag is! String) ||
            fetchedMs is! num ||
            !fetchedMs.isFinite ||
            fetchedMs < 0 ||
            fetchedMs > 8640000000000000) {
          return null;
        }
        return CachedEntitlements(
          json: Map<String, Object?>.from(json),
          etag: etag as String?,
          fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetchedMs.toInt()),
        );
      });

  Future<void> writeEntitlements(CachedEntitlements cached,
          {int? generation}) =>
      _writeSessionValue(
        entitlementsKey,
        jsonEncode({
          'json': cached.json,
          'etag': cached.etag,
          'fetched_at_ms': cached.fetchedAt.millisecondsSinceEpoch,
        }),
        generation,
      );

  Future<void> _writeSessionValue(String key, String value, int? generation) =>
      _sessionOperation(() async {
        if (!await _store.write(key, value)) {
          throw CloudApiException.storageFailure();
        }
      }, generation: generation);

  /// 账号资料等其他随登录走的缓存。键必须登记在 [_sessionKeys] 里，退出时才会一起清掉。
  Future<String?> readRaw(String key) {
    assert(_sessionKeys.contains(key), 'unregistered session key $key');
    return _sessionOperation(
        () async => await _isBlocked() ? null : _store.read(key));
  }

  Future<bool> writeRaw(String key, String value, {int? generation}) {
    assert(_sessionKeys.contains(key), 'unregistered session key $key');
    return _sessionOperation(() => _store.write(key, value),
        generation: generation);
  }

  static const meKey = 'fm_cloud_me_v1';
  static const _sessionKeys = {tokensKey, entitlementsKey, meKey};

  /// 退出登录：清掉令牌、权益和资料缓存，安装 ID 保留。
  Future<void> clearSession({int? generation}) => _sessionOperation(() async {
        // Attempt both independent protections, even when one store is broken.
        Object? failure;
        try {
          await _setBlocked(true);
        } catch (error) {
          failure = error;
        }
        try {
          await _clearSessionValues();
        } catch (error) {
          failure ??= error;
        }
        if (failure != null) throw failure;
      }, generation: generation);

  Future<void> _clearSessionValues() async {
    var failed = false;
    for (final key in _sessionKeys) {
      try {
        if (!await _store.delete(key) && await _store.read(key) != null) {
          failed = true;
        }
      } catch (_) {
        failed = true;
      }
    }
    if (failed) throw CloudApiException.storageFailure();
  }

  Future<bool> _isBlocked() async {
    try {
      return await _guard.isBlocked();
    } catch (_) {
      throw CloudApiException.storageFailure();
    }
  }

  Future<void> _setBlocked(bool blocked) async {
    try {
      await _guard.setBlocked(blocked);
    } catch (_) {
      throw CloudApiException.storageFailure();
    }
  }

  static Map<String, Object?>? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  static bool isUuid(String value) => _uuidPattern.hasMatch(value);

  static String newUuidV4([Random? random]) {
    final source = random ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => source.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
