import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qingji/core/cloud/cloud_account.dart';
import 'package:qingji/core/cloud/cloud_api.dart';
import 'package:qingji/core/cloud/cloud_errors.dart';
import 'package:qingji/core/cloud/cloud_session_store.dart';
import 'package:qingji/core/cloud/profile_sync.dart';

http.Response _json(int status, Object body, {Map<String, String>? headers}) =>
    http.Response(jsonEncode(body), status, headers: {
      'content-type': 'application/json; charset=utf-8',
      ...?headers,
    });

const _tokens = {
  'access_token': 'a1',
  'access_expires_in': 900,
  'refresh_token': 'r1',
  'refresh_expires_in': 2592000,
  'is_new_user': false,
};

const _me = {
  'id': '6f1c7c1e-4b1e-4c6a-9a51-0c9f2b6f8f10',
  'email': 'cat@example.com',
  'created_at': '2026-09-01T00:00:00Z',
  'has_password': false,
  'profile': {'display_name': '肥喵', 'updated_at': '2026-09-29T00:00:00Z'},
};

Map<String, Object?> _entitlements(double usedPct) => {
      'tier': {'key': 'standard', 'name': '普通会员', 'is_internal': false},
      'membership': {'status': 'active', 'trial': false},
      'quota': {
        'display': 'bar',
        'weekly': {'used_pct': usedPct, 'resets_at': '2026-10-05T00:00:00Z'},
        'warn_pct': [80, 100],
      },
      'features': {},
      'limits': {'max_images': 4, 'max_image_bytes': 1572864},
      'redeem': {'in_app': true},
      'paywall': {'tiers': []},
    };

class _Server {
  final requests = <http.Request>[];
  bool offline = false;
  bool revoked = false;
  bool deviceLimit = false;
  String etag = '"v1"';
  double usedPct = 12;
  Map<String, Object?> profile = Map.of(_me['profile']! as Map<String, Object?>);
  bool rejectProfile = false;
  final profileWrites = <String>[];

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    if (offline) throw http.ClientException('offline');
    if (revoked && request.headers['Authorization'] != null) {
      return _json(401, {
        'error': {
          'code': 'SESSION_REVOKED',
          'message': '账号已在其他设备下线',
          'action': 'login',
          'request_id': 'r',
        },
      });
    }
    switch (request.url.path) {
      case '/v1/auth/otp/verify':
        if (deviceLimit) {
          return _json(409, {
            'error': {
              'code': 'DEVICE_LIMIT',
              'message': '登录设备已达上限',
              'action': 'choose_device',
              'request_id': 'r',
              'details': {
                'login_ticket': 't1',
                'login_ticket_expires_in': 300,
                'max_devices': 3,
                'devices': [
                  {
                    'id': 'd1',
                    'platform': 'android',
                    'last_seen_at': '2026-09-29T00:00:00Z',
                    'created_at': '2026-09-01T00:00:00Z',
                    'is_current': false,
                  },
                ],
              },
            },
          });
        }
        return _json(200, _tokens);
      case '/v1/auth/device-limit/resolve':
        return _json(200, _tokens);
      case '/v1/me':
        return _json(200, {..._me, 'profile': profile});
      case '/v1/me/profile':
        if (rejectProfile) {
          return _json(400, {
            'error': {
              'code': 'INVALID_REQUEST',
              'message': '昵称包含不允许的内容',
              'action': 'show_message',
              'request_id': 'r',
            },
          });
        }
        final name =
            (jsonDecode(request.body) as Map)['display_name'] as String;
        profileWrites.add(name);
        profile = {'display_name': name, 'updated_at': '2026-09-30T00:00:00Z'};
        return _json(200, profile);
      case '/v1/entitlements':
        if (request.headers['If-None-Match'] == etag) {
          return http.Response('', 304);
        }
        return _json(200, _entitlements(usedPct), headers: {'etag': etag});
      case '/v1/auth/logout':
        return http.Response('', 204);
    }
    return _json(404, {});
  }

  int count(String path) =>
      requests.where((r) => r.url.path == '/v1$path').length;
}

class _LocalProfile implements LocalProfileStore {
  _LocalProfile({this.nickname = '', this.nicknameUpdatedAt});

  @override
  String nickname;
  @override
  DateTime? nicknameUpdatedAt;
  final applied = <String>[];

  @override
  bool get profileLoaded => true;

  @override
  Future<void> whenProfileLoaded() async {}

  @override
  Future<void> applyCloudNickname(String name, DateTime? updatedAt) async {
    applied.add(name);
    nickname = name;
    nicknameUpdatedAt = updatedAt;
  }
}

CloudAccount _account(_Server server, MemoryCloudSecretStore secrets,
        {bool enabled = true, LocalProfileStore? profile}) =>
    CloudAccount(
      enabled: enabled,
      profileStore: profile,
      api: CloudApi(
        client: MockClient(server.handle),
        store: CloudSessionStore(store: secrets),
        baseUrl: 'https://api.test/v1',
        deviceInfo: () async => const {},
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('disabled account never touches storage or network', () async {
    final server = _Server();
    final secrets = MemoryCloudSecretStore();
    final account = _account(server, secrets, enabled: false);

    await account.init();

    expect(account.ready, isTrue);
    expect(account.signedIn, isFalse);
    expect(server.requests, isEmpty);
    expect(secrets.values, isEmpty);
    account.dispose();
  });

  test('login loads profile and entitlements, and survives restart offline',
      () async {
    final server = _Server();
    final secrets = MemoryCloudSecretStore();
    final account = _account(server, secrets);
    await account.init();
    expect(account.signedIn, isFalse);

    final outcome = await account.loginWithCode('cat@example.com', '123456');

    expect(outcome, isA<LoginSucceeded>());
    expect(account.signedIn, isTrue);
    expect(account.me!.email, 'cat@example.com');
    expect(account.entitlements!.quota.weekly!.usedPct, 12);
    account.dispose();

    server.offline = true;
    final restarted = _account(server, secrets);
    await restarted.init();
    await restarted.refresh();

    expect(restarted.signedIn, isTrue);
    expect(restarted.me!.profile.displayName, '肥喵');
    expect(restarted.entitlements!.tier.name, '普通会员');
    expect(restarted.entitlementsFetchedAt, isNotNull);
    restarted.dispose();
  });

  test('entitlements refresh uses the cached ETag', () async {
    final server = _Server();
    final account = _account(server, MemoryCloudSecretStore());
    await account.init();
    await account.loginWithCode('cat@example.com', '123456');

    await account.refreshEntitlements();
    final lastRequest =
        server.requests.lastWhere((r) => r.url.path == '/v1/entitlements');
    expect(lastRequest.headers['If-None-Match'], '"v1"');
    expect(account.entitlements!.quota.weekly!.usedPct, 12);

    server.etag = '"v2"';
    server.usedPct = 55;
    await account.refreshEntitlements();
    expect(account.entitlements!.quota.weekly!.usedPct, 55);
    account.dispose();
  });

  test('device limit returns the list, then resolve logs in', () async {
    final server = _Server()..deviceLimit = true;
    final account = _account(server, MemoryCloudSecretStore());
    await account.init();

    final outcome = await account.loginWithCode('cat@example.com', '123456');

    expect(outcome, isA<LoginNeedsDeviceChoice>());
    expect(account.signedIn, isFalse);
    final info = (outcome as LoginNeedsDeviceChoice).info;
    expect(info.devices.single.id, 'd1');

    final resolved = await account.resolveDeviceLimit(info, ['d1']);
    expect(resolved, isA<LoginSucceeded>());
    expect(account.signedIn, isTrue);
    account.dispose();
  });

  test('being signed out elsewhere clears account state with a notice',
      () async {
    final server = _Server();
    final secrets = MemoryCloudSecretStore();
    final account = _account(server, secrets);
    await account.init();
    await account.loginWithCode('cat@example.com', '123456');
    final installId = secrets.values[CloudSessionStore.installIdKey];

    server.revoked = true;
    await account.refresh();

    expect(account.signedIn, isFalse);
    expect(account.me, isNull);
    expect(account.entitlements, isNull);
    expect(account.signOutNotice, '账号已在其他设备下线');
    expect(secrets.values.keys, [CloudSessionStore.installIdKey]);
    expect(secrets.values[CloudSessionStore.installIdKey], installId);
    account.clearSignOutNotice();
    expect(account.signOutNotice, isNull);
    account.dispose();
  });

  test('logout clears state without a notice', () async {
    final server = _Server();
    final account = _account(server, MemoryCloudSecretStore());
    await account.init();
    await account.loginWithCode('cat@example.com', '123456');

    await account.logout();

    expect(account.signedIn, isFalse);
    expect(account.signOutNotice, isNull);
    expect(server.count('/auth/logout'), 1);
    account.dispose();
  });

  group('nickname sync', () {
    // 登录后的昵称同步是不等待的，让排队的请求跑完。
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('new device with no local name takes the server name on login',
        () async {
      final server = _Server();
      final local = _LocalProfile();
      final account =
          _account(server, MemoryCloudSecretStore(), profile: local);
      await account.init();

      await account.loginWithCode('cat@example.com', '123456');
      await settle();

      expect(local.nickname, '肥喵');
      expect(local.nicknameUpdatedAt!.toUtc(), DateTime.utc(2026, 9, 29));
      expect(server.count('/me/profile'), 0);
      account.dispose();
    });

    test('a newer local name is uploaded and a 20-char server name is cut',
        () async {
      final server = _Server();
      final local = _LocalProfile(
          nickname: '本机新名', nicknameUpdatedAt: DateTime.utc(2026, 9, 30));
      final account =
          _account(server, MemoryCloudSecretStore(), profile: local);
      await account.init();
      await account.loginWithCode('cat@example.com', '123456');
      await settle();

      expect(server.profileWrites, ['本机新名']);
      expect(account.me!.profile.displayName, '本机新名');
      expect(local.applied, isEmpty);

      server.profile = {
        'display_name': '一二三四五六七八九十甲乙丙丁戊己庚辛壬癸',
        'updated_at': '2026-10-01T00:00:00Z',
      };
      await account.refresh();
      await settle();
      expect(local.nickname, '一二三四五六七八九十甲乙');
      account.dispose();
    });

    test('a rejected upload throws and keeps the local name', () async {
      final server = _Server()..rejectProfile = true;
      final local = _LocalProfile(
          nickname: '肥喵', nicknameUpdatedAt: DateTime.utc(2026, 9, 29));
      final account =
          _account(server, MemoryCloudSecretStore(), profile: local);
      await account.init();
      await account.loginWithCode('cat@example.com', '123456');
      await settle();

      local
        ..nickname = '不合适的名字'
        ..nicknameUpdatedAt = DateTime.utc(2026, 10, 2);
      await expectLater(
          account.syncNickname(), throwsA(isA<CloudApiException>()));

      expect(local.nickname, '不合适的名字');
      expect(account.me!.profile.displayName, '肥喵');
      account.dispose();
    });

    test('without a local store the account never writes the profile',
        () async {
      final server = _Server();
      final account = _account(server, MemoryCloudSecretStore());
      await account.init();
      await account.loginWithCode('cat@example.com', '123456');
      await settle();
      await account.syncNickname();

      expect(server.count('/me/profile'), 0);
      account.dispose();
    });
  });
}
