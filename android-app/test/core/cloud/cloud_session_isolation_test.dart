import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qingji/core/cloud/cloud_account.dart';
import 'package:qingji/core/cloud/cloud_api.dart';
import 'package:qingji/core/cloud/cloud_errors.dart';
import 'package:qingji/core/cloud/cloud_models.dart';
import 'package:qingji/core/cloud/cloud_session_store.dart';
import 'session_test_store.dart';

http.Response _json(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, Object?> _tokens(String id, {int expiresIn = 900}) => {
      'access_token': 'access-$id',
      'refresh_token': 'refresh-$id',
      'access_expires_in': expiresIn,
      'refresh_expires_in': 2592000,
      'is_new_user': false,
    };

Map<String, Object?> _me(String id) => {
      'id': id,
      'email': '$id@example.invalid',
      'has_password': true,
      'profile': {'display_name': id},
    };

http.Response _revoked() => _json({
      'error': {
        'code': 'SESSION_REVOKED',
        'action': 'login',
        'message': '旧会话失效',
      },
    }, 401);

final _changed = throwsA(isA<CloudApiException>()
    .having((error) => error.rawCode, 'rawCode', 'LOCAL_SESSION_CHANGED'));

class _Server {
  _Server({MemoryCloudSecretStore? secrets})
      : secrets = secrets ?? MemoryCloudSecretStore();

  final MemoryCloudSecretStore secrets;
  final requests = <http.Request>[];
  Future<http.Response> Function(http.Request)? intercept;

  late final api = CloudApi(
    store: testSessionStore(secrets),
    client: MockClient((request) async {
      requests.add(request);
      final handler = intercept;
      if (handler != null) return handler(request);
      return normal(request);
    }),
    baseUrl: 'https://example.invalid/v1',
    deviceInfo: () async => const {},
  );

  http.Response normal(http.Request request) {
    final id = request.headers['Authorization']?.split('-').last ?? '';
    switch (request.url.path) {
      case '/v1/auth/password/login':
        return _json(
            _tokens((jsonDecode(request.body) as Map)['email'] as String));
      case '/v1/me':
        return _json(_me(id));
      case '/v1/entitlements':
        return _json({
          'tier': {'key': id, 'name': id}
        }, 200);
      case '/v1/me/profile':
        return _json({
          'display_name': (jsonDecode(request.body) as Map)['display_name']
        });
      case '/v1/auth/logout':
        return http.Response('', 204);
      default:
        return _json({}, 404);
    }
  }

  Future<void> login(String id) async {
    await api.passwordLogin(id, 'test-only');
  }
}

class _SlowSecrets extends MemoryCloudSecretStore {
  final entered = Completer<void>();
  final release = Completer<void>();
  String? blockedKey;
  bool failTokens = false;

  @override
  Future<bool> write(String key, String value) async {
    if (key == blockedKey) {
      blockedKey = null;
      entered.complete();
      await release.future;
    }
    if (key == CloudSessionStore.tokensKey && failTokens) return false;
    return super.write(key, value);
  }
}

class _SlowReadSecrets extends MemoryCloudSecretStore {
  final entered = Completer<void>();
  final release = Completer<void>();
  bool _blocked = false;

  @override
  Future<String?> read(String key) async {
    if (key == CloudSessionStore.tokensKey && !_blocked) {
      _blocked = true;
      entered.complete();
      await release.future;
    }
    return super.read(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('login superseding startup restore finishes init without stale errors',
      () async {
    final secrets = _SlowReadSecrets();
    final server = _Server(secrets: secrets);
    final account = CloudAccount(api: server.api, enabled: true);
    addTearDown(account.dispose);
    final initializing = account.init();
    expect(identical(account.init(), initializing), isTrue);
    await secrets.entered.future;
    final login = account.loginWithPassword('B', 'test-only');
    secrets.release.complete();
    await initializing;
    await login;
    expect(account.ready, isTrue);
    expect(account.signedIn, isTrue);
    expect(account.me!.id, 'B');
    expect((await server.api.store.readTokens())!.accessToken, 'access-B');
  });

  test('dispose during startup does not notify or register an observer',
      () async {
    final secrets = _SlowReadSecrets();
    final server = _Server(secrets: secrets);
    final account = CloudAccount(api: server.api, enabled: true);
    var notifications = 0;
    account.addListener(() => notifications++);
    final initializing = account.init();
    await secrets.entered.future;
    account.dispose();
    secrets.release.complete();
    await initializing;
    expect(notifications, 0);
    expect(account.ready, isFalse);
  });

  for (final status in [200, 401]) {
    test('late A response $status cannot return data or end B session',
        () async {
      final server = _Server();
      final ended = <CloudApiException>[];
      server.api.onSessionEnded = ended.add;
      await server.login('A');
      final entered = Completer<void>();
      final response = Completer<http.Response>();
      server.intercept = (request) async {
        if (request.url.path == '/v1/me') {
          entered.complete();
          return response.future;
        }
        return server.normal(request);
      };
      final old = server.api.me();
      final rejected = expectLater(old, _changed);
      await entered.future;
      await server.login('B');
      response.complete(status == 200 ? _json(_me('A')) : _revoked());
      await rejected;
      expect(server.api.hasSession, isTrue);
      expect((await server.api.store.readTokens())!.accessToken, 'access-B');
      expect(ended, isEmpty);
      expect(server.requests.where((r) => r.url.path == '/v1/auth/refresh'),
          isEmpty);
    });
  }

  for (final status in [200, 401]) {
    test('late A refresh $status cannot replace or clear B tokens', () async {
      final server = _Server();
      await server.login('A');
      final entered = Completer<void>();
      final response = Completer<http.Response>();
      server.intercept = (request) async {
        if (request.url.path == '/v1/auth/refresh') {
          entered.complete();
          return response.future;
        }
        if (request.url.path == '/v1/me') {
          return _json({
            'error': {'code': 'UNAUTHENTICATED', 'action': 'refresh_or_login'}
          }, 401);
        }
        return server.normal(request);
      };
      final rejected = expectLater(server.api.me(), _changed);
      await entered.future;
      await server.login('B');
      response
          .complete(status == 200 ? _json(_tokens('A-refreshed')) : _revoked());
      await rejected;
      expect(server.api.hasSession, isTrue);
      expect((await server.api.store.readTokens())!.accessToken, 'access-B');
    });
  }

  test('overlapping login keeps the last initiated account', () async {
    final server = _Server();
    final entered = Completer<void>();
    final response = Completer<http.Response>();
    server.intercept = (request) async {
      if (request.url.path == '/v1/auth/password/login' &&
          (jsonDecode(request.body) as Map)['email'] == 'A') {
        entered.complete();
        return response.future;
      }
      return server.normal(request);
    };
    final rejected = expectLater(server.login('A'), _changed);
    await entered.future;
    await server.login('B');
    response.complete(_json(_tokens('A')));
    await rejected;
    expect((await server.api.store.readTokens())!.accessToken, 'access-B');
  });

  test('slow logout only sends old credentials and cannot clear new login',
      () async {
    final server = _Server();
    await server.login('A');
    final entered = Completer<void>();
    final response = Completer<http.Response>();
    server.intercept = (request) async {
      if (request.url.path == '/v1/auth/logout') {
        expect(request.headers['Authorization'], 'Bearer access-A');
        entered.complete();
        return response.future;
      }
      return server.normal(request);
    };
    final logout = server.api.logout();
    await entered.future;
    await server.login('B');
    response.complete(_revoked());
    await logout;
    expect(server.api.hasSession, isTrue);
    expect((await server.api.store.readTokens())!.accessToken, 'access-B');
  });

  test(
      'A profile and entitlements in flight do not block or overwrite B caches',
      () async {
    final server = _Server();
    final account = CloudAccount(api: server.api, enabled: true);
    addTearDown(account.dispose);
    await account.init();
    await account.loginWithPassword('A', 'test-only');
    final meEntered = Completer<void>();
    final entitlementEntered = Completer<void>();
    final oldMe = Completer<http.Response>();
    final oldEntitlements = Completer<http.Response>();
    server.intercept = (request) async {
      if (request.headers['Authorization'] == 'Bearer access-A') {
        if (request.url.path == '/v1/me') {
          meEntered.complete();
          return oldMe.future;
        }
        if (request.url.path == '/v1/entitlements') {
          entitlementEntered.complete();
          return oldEntitlements.future;
        }
      }
      return server.normal(request);
    };
    final refresh = account.refresh();
    await Future.wait([meEntered.future, entitlementEntered.future]);
    await account.logout();
    await account.loginWithPassword('B', 'test-only');
    expect(account.me!.id, 'B');
    expect(account.entitlements!.tier.key, 'B');
    oldMe.complete(_json(_me('A')));
    oldEntitlements.complete(_json({
      'tier': {'key': 'A'}
    }));
    await refresh;
    expect(account.me!.id, 'B');
    expect(account.entitlements!.tier.key, 'B');
    expect(
        jsonDecode(
            (await server.api.store.readRaw(CloudSessionStore.meKey))!)['id'],
        'B');
    expect((await server.api.store.readEntitlements())!.value.tier.key, 'B');
  });

  test('late profile edit cannot apply an A name to B', () async {
    final server = _Server();
    final account = CloudAccount(api: server.api, enabled: true);
    addTearDown(account.dispose);
    await account.init();
    await account.loginWithPassword('A', 'test-only');
    final entered = Completer<void>();
    final response = Completer<http.Response>();
    server.intercept = (request) async {
      if (request.url.path == '/v1/me/profile') {
        entered.complete();
        return response.future;
      }
      return server.normal(request);
    };
    final rejected =
        expectLater(account.updateDisplayName('A-edited'), _changed);
    await entered.future;
    await account.loginWithPassword('B', 'test-only');
    response.complete(_json({'display_name': 'A-edited'}));
    await rejected;
    expect(account.me!.profile.displayName, 'B');
  });

  test('dispose while refreshing never notifies a disposed account', () async {
    final server = _Server();
    final account = CloudAccount(api: server.api, enabled: true);
    await account.init();
    await account.loginWithPassword('A', 'test-only');
    final entered = Completer<void>();
    final response = Completer<http.Response>();
    server.intercept = (request) async {
      if (request.url.path == '/v1/me') {
        entered.complete();
        return response.future;
      }
      return server.normal(request);
    };
    final refresh = account.refresh();
    await entered.future;
    account.dispose();
    response.complete(_json(_me('A')));
    await refresh;
  });

  test('already started secret write completes before new session clear/write',
      () async {
    final secrets = _SlowSecrets()..blockedKey = CloudSessionStore.tokensKey;
    final store = testSessionStore(secrets);
    final a = store.beginSession();
    final oldWrite = store.writeTokens(
        CloudTokens.fromResponse(_tokens('A'), DateTime.now()),
        generation: a);
    await secrets.entered.future;
    final b = store.beginSession();
    final clear = store.clearSession(generation: b);
    final newWrite = store.writeTokens(
        CloudTokens.fromResponse(_tokens('B'), DateTime.now()),
        generation: b);
    secrets.release.complete();
    await Future.wait([oldWrite, clear, newWrite]);
    expect((await store.readTokens())!.accessToken, 'access-B');
  });

  test('queued stale cache writes are rejected after session switch', () async {
    final secrets = _SlowSecrets()..blockedKey = CloudSessionStore.tokensKey;
    final store = testSessionStore(secrets);
    final a = store.beginSession();
    final oldWrite = store.writeTokens(
        CloudTokens.fromResponse(_tokens('A'), DateTime.now()),
        generation: a);
    await secrets.entered.future;
    final rejected = expectLater(
        store.writeRaw(CloudSessionStore.meKey, '{"id":"A"}', generation: a),
        _changed);
    final b = store.beginSession();
    final clear = store.clearSession(generation: b);
    secrets.release.complete();
    await Future.wait([oldWrite, rejected, clear]);
    expect(await store.readRaw(CloudSessionStore.meKey), isNull);
  });

  test('failed secure token persistence never reports a signed-in session',
      () async {
    final secrets = _SlowSecrets()..failTokens = true;
    final api = CloudApi(
      store: testSessionStore(secrets),
      client: MockClient((_) async => _json(_tokens('A'))),
      baseUrl: 'https://example.invalid/v1',
      deviceInfo: () async => const {},
    );
    await expectLater(
        api.passwordLogin('A', 'test-only'),
        throwsA(isA<CloudApiException>()
            .having((e) => e.rawCode, 'rawCode', 'LOCAL_STORAGE_FAILED')));
    expect(api.hasSession, isFalse);
    expect(await api.store.readTokens(), isNull);
  });
}
