import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qingji/core/cloud/cloud_account.dart';
import 'package:qingji/core/cloud/cloud_api.dart';
import 'package:qingji/core/cloud/cloud_errors.dart';
import 'package:qingji/core/cloud/cloud_models.dart';
import 'package:qingji/core/cloud/cloud_session_guard.dart';
import 'package:qingji/core/cloud/cloud_session_store.dart';

final _storageFailure = throwsA(isA<CloudApiException>()
    .having((e) => e.rawCode, 'rawCode', 'LOCAL_STORAGE_FAILED'));

class FaultySecrets extends MemoryCloudSecretStore {
  bool refuseDeletes = false;
  bool refuseTokenWrites = false;
  bool throwDeletes = false;
  String? unreadableKey;
  final deleted = <String>[];

  @override
  Future<String?> read(String key) async {
    if (key == unreadableKey) throw CloudApiException.storageFailure();
    return super.read(key);
  }

  @override
  Future<bool> write(String key, String value) async =>
      key == CloudSessionStore.tokensKey && refuseTokenWrites
          ? false
          : super.write(key, value);

  @override
  Future<bool> delete(String key) async {
    deleted.add(key);
    if (throwDeletes) throw const FileSystemException('injected');
    return refuseDeletes ? false : super.delete(key);
  }
}

class FaultyGuard extends MemoryCloudSessionGuard {
  bool failBlock = false;
  bool failUnblock = false;
  bool failRead = false;

  @override
  Future<bool> isBlocked() async {
    if (failRead) throw const FileSystemException('injected');
    return super.isBlocked();
  }

  @override
  Future<void> setBlocked(bool value) async {
    if ((value && failBlock) || (!value && failUnblock)) {
      throw const FileSystemException('injected');
    }
    await super.setBlocked(value);
  }
}

Map<String, Object?> tokenBody(String id) => {
      'access_token': 'fake-access-$id',
      'refresh_token': 'fake-refresh-$id',
      'access_expires_in': 3600,
      'refresh_expires_in': 86400,
    };

CloudTokens tokens(String id) =>
    CloudTokens.fromResponse(tokenBody(id), DateTime.now());

class Harness {
  Harness({CloudSessionGuard? guard})
      : guard = guard ?? MemoryCloudSessionGuard();

  final CloudSessionGuard guard;
  final secrets = FaultySecrets();
  final requests = <http.Request>[];
  bool offline = false;
  late final store = CloudSessionStore(store: secrets, guard: guard);
  late final api = makeApi(store);

  CloudApi makeApi(CloudSessionStore value) => CloudApi(
        store: value,
        baseUrl: 'https://example.invalid/v1',
        deviceInfo: () async => const {},
        client: MockClient((request) async {
          requests.add(request);
          if (offline) throw const SocketException('test offline');
          final Object body = switch (request.url.path) {
            '/v1/auth/password/login' => tokenBody('B'),
            '/v1/entitlements' => {
                'tier': {'key': 'fresh', 'name': 'fresh'}
              },
            '/v1/me' => {'id': 'B', 'email': 'test@example.invalid'},
            _ => {},
          };
          return http.Response(jsonEncode(body), 200,
              headers: {'content-type': 'application/json'});
        }),
      );

  Future<void> seed() async {
    await store.writeTokens(tokens('A'));
    await store.writeRaw(CloudSessionStore.meKey, '{"id":"A"}');
    await store.writeEntitlements(CachedEntitlements(
        json: const {}, etag: 'old', fetchedAt: DateTime.now()));
    expect(await api.restore(), isTrue);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final throwsDelete in [false, true]) {
    test(
        'failed deletion ($throwsDelete) still revokes A and blocks restart on disk',
        () async {
      final directory = await Directory.systemTemp.createTemp('fm-logout-');
      addTearDown(() => directory.delete(recursive: true));
      final h = Harness(
          guard: FileCloudSessionGuard(directory: () async => directory));
      await h.seed();
      h.secrets.refuseDeletes = true;
      h.secrets.throwDeletes = throwsDelete;
      await expectLater(h.api.logout(), _storageFailure);
      expect(h.api.hasSession, isFalse);
      final logout =
          h.requests.singleWhere((r) => r.url.path.endsWith('/auth/logout'));
      expect(logout.headers['Authorization'], 'Bearer fake-access-A');
      expect(
          h.secrets.deleted,
          containsAll([
            CloudSessionStore.tokensKey,
            CloudSessionStore.meKey,
            CloudSessionStore.entitlementsKey,
          ]));
      expect(h.secrets.values[CloudSessionStore.tokensKey], isNotNull);
      // Use a new guard and session store, retaining only actual on-disk state.
      final restarted = h.makeApi(CloudSessionStore(
          store: h.secrets,
          guard: FileCloudSessionGuard(directory: () async => directory)));
      expect(await restarted.restore(), isFalse);
      expect(await restarted.store.readRaw(CloudSessionStore.meKey), isNull);
      expect(await restarted.store.readEntitlements(), isNull);
      h.secrets.refuseDeletes = false;
      h.secrets.throwDeletes = false;
      expect(await restarted.restore(), isFalse);
      expect(h.secrets.values[CloudSessionStore.tokensKey], isNull);
      await restarted.passwordLogin('B', 'fake-only');
      expect(restarted.hasSession, isTrue);
      expect(
          (await restarted.store.readTokens())!.accessToken, 'fake-access-B');
    });
  }

  test('offline logout with deletion failure never restores old tokens',
      () async {
    final h = Harness();
    await h.seed();
    h.offline = true;
    h.secrets.refuseDeletes = true;
    await expectLater(h.api.logout(), _storageFailure);
    final restarted =
        h.makeApi(CloudSessionStore(store: h.secrets, guard: h.guard));
    expect(await restarted.restore(), isFalse);
    expect(
        h.requests.where((r) => r.url.path.endsWith('/auth/logout')).length, 1);
  });

  test('failed new token write preserves logout guard', () async {
    final h = Harness();
    await h.seed();
    await h.api.logout();
    h.secrets.refuseTokenWrites = true;
    await expectLater(h.api.passwordLogin('B', 'fake-only'), _storageFailure);
    expect(await h.guard.isBlocked(), isTrue);
    expect(h.api.hasSession, isFalse);
    expect(await h.api.restore(), isFalse);
  });

  test('failed guard removal does not report successful login', () async {
    final guard = FaultyGuard();
    final h = Harness(guard: guard);
    await h.seed();
    await h.api.logout();
    guard.failUnblock = true;
    await expectLater(h.api.passwordLogin('B', 'fake-only'), _storageFailure);
    expect(h.api.hasSession, isFalse);
    expect(await h.api.restore(), isFalse);
  });

  test(
      'failed guard creation still deletes all secrets and revokes old session',
      () async {
    final guard = FaultyGuard();
    final h = Harness(guard: guard);
    await h.seed();
    guard.failBlock = true;
    await expectLater(h.api.logout(), _storageFailure);
    expect(h.secrets.values[CloudSessionStore.tokensKey], isNull);
    expect(
        h.requests.where((r) => r.url.path.endsWith('/auth/logout')).length, 1);
    expect(await h.api.restore(), isFalse);
  });

  test('startup handles unreadable logout state without an unhandled error',
      () async {
    final guard = FaultyGuard()..failRead = true;
    final h = Harness(guard: guard);
    final account = CloudAccount(api: h.api, enabled: true);
    addTearDown(account.dispose);
    await account.init();
    expect(account.ready, isTrue);
    expect(account.signedIn, isFalse);
    expect(h.api.hasSession, isFalse);
    expect(h.requests, isEmpty);
  });

  final badCaches = <String, Object?>{
    'non-json': '{',
    'non-object': '[]',
    'numeric-etag': jsonEncode({'json': {}, 'etag': 7, 'fetched_at_ms': 1}),
    'bad-date-type': jsonEncode({'json': {}, 'fetched_at_ms': 'yesterday'}),
    'date-overflow':
        jsonEncode({'json': {}, 'fetched_at_ms': 9000000000000000000}),
    'negative-date': jsonEncode({'json': {}, 'fetched_at_ms': -1}),
    'bad-entitlements-type': jsonEncode({'json': [], 'fetched_at_ms': 1}),
  };
  for (final entry in badCaches.entries) {
    test('bad optional cache ${entry.key} retains login and fetches fresh data',
        () async {
      final h = Harness();
      await h.seed();
      h.secrets.values[CloudSessionStore.entitlementsKey] =
          entry.value as String;
      expect(await h.store.readEntitlements(), isNull);
      final account = CloudAccount(api: h.api, enabled: true);
      addTearDown(account.dispose);
      await account.init();
      expect(account.ready, isTrue);
      expect(account.signedIn, isTrue);
      expect(h.api.hasSession, isTrue);
      await account.refresh();
      expect(account.entitlements!.tier.key, 'fresh');
      final requests =
          h.requests.where((r) => r.url.path.endsWith('/entitlements'));
      expect(requests, isNotEmpty);
      expect(requests.first.headers['If-None-Match'], isNull);
      expect((await h.store.readEntitlements())!.value.tier.key, 'fresh');
    });
  }

  test(
      'optional cache storage failure keeps restored login and offline usability',
      () async {
    final h = Harness();
    await h.seed();
    h.secrets.unreadableKey = CloudSessionStore.entitlementsKey;
    h.offline = true;
    final account = CloudAccount(api: h.api, enabled: true);
    addTearDown(account.dispose);
    await account.init();
    expect(account.signedIn, isTrue);
    expect(account.ready, isTrue);
    await account.refresh();
    expect(h.api.hasSession, isTrue);
    expect(account.signedIn, isTrue);
  });
}
