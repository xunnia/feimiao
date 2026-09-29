import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qingji/core/cloud/cloud_api.dart';
import 'package:qingji/core/cloud/cloud_errors.dart';
import 'package:qingji/core/cloud/cloud_models.dart';
import 'package:qingji/core/cloud/cloud_session_store.dart';

const _base = 'https://api.test/v1';

http.Response _json(int status, Object body, {Map<String, String>? headers}) =>
    http.Response(jsonEncode(body), status, headers: {
      'content-type': 'application/json; charset=utf-8',
      ...?headers,
    });

http.Response _error(int status, String code, String action,
        {String message = '出错了', Map<String, Object?>? details}) =>
    _json(status, {
      'error': {
        'code': code,
        'message': message,
        'action': action,
        'request_id': 'req-1',
        if (details != null) 'details': details,
      },
    });

Map<String, Object?> _tokens(String suffix, {int accessIn = 900}) => {
      'access_token': 'access-$suffix',
      'access_expires_in': accessIn,
      'refresh_token': 'refresh-$suffix',
      'refresh_expires_in': 2592000,
    };

class _Harness {
  _Harness(this.handler);

  final Future<http.Response> Function(http.Request request) handler;
  final requests = <http.Request>[];
  final secrets = MemoryCloudSecretStore();
  DateTime now = DateTime(2026, 9, 30, 10);
  final ended = <CloudApiException>[];

  late final CloudApi api = CloudApi(
    client: MockClient((request) {
      requests.add(request);
      return handler(request);
    }),
    store: CloudSessionStore(store: secrets),
    baseUrl: _base,
    clock: () => now,
    deviceInfo: () async => {'model': 'Xiaomi 14', 'os_version': 'Android 15'},
  )..onSessionEnded = ended.add;

  Iterable<http.Request> at(String path) =>
      requests.where((r) => r.url.path == '/v1$path');
}

/// 用验证码登录一次，拿到 `access-1` / `refresh-1`。
Future<void> _login(_Harness h) async {
  await h.api.verifyOtp('cat@example.com', '123456');
  h.requests.clear();
}

void main() {
  group('CloudSessionStore', () {
    test('install id is a stable UUID v4', () async {
      final secrets = MemoryCloudSecretStore();
      final first = await CloudSessionStore(store: secrets).installId();
      final second = await CloudSessionStore(store: secrets).installId();
      expect(first, second);
      expect(CloudSessionStore.isUuid(first), isTrue);
      expect(first[14], '4');
      expect('89ab'.contains(first[19]), isTrue);
    });

    test('clearSession keeps the install id', () async {
      final secrets = MemoryCloudSecretStore();
      final store = CloudSessionStore(store: secrets);
      final id = await store.installId();
      await store.writeTokens(CloudTokens.fromResponse(_tokens('1'), DateTime(2026)));
      await store.writeRaw(CloudSessionStore.meKey, '{}');
      await store.clearSession();
      expect(await store.readTokens(), isNull);
      expect(await store.readRaw(CloudSessionStore.meKey), isNull);
      expect(await store.installId(), id);
    });
  });

  group('CloudErrorCode / CloudApiException', () {
    test('parses a known error body', () {
      final error = CloudApiException.fromResponse(429, {
        'error': {
          'code': 'RATE_LIMITED',
          'message': '太频繁了',
          'action': 'retry_later',
          'request_id': 'r',
          'retry_after': 30,
        },
      });
      expect(error.code, CloudErrorCode.rateLimited);
      expect(error.action, CloudErrorAction.retryLater);
      expect(error.message, '太频繁了');
      expect(error.retryAfter, const Duration(seconds: 30));
    });

    test('unknown code keeps the server action and message', () {
      final error = CloudApiException.fromResponse(403, {
        'error': {
          'code': 'SOMETHING_NEW',
          'message': '新的限制',
          'action': 'open_paywall',
          'request_id': 'r',
        },
      });
      expect(error.code, CloudErrorCode.unknown);
      expect(error.rawCode, 'SOMETHING_NEW');
      expect(error.action, CloudErrorAction.openPaywall);
      expect(error.message, '新的限制');
    });

    test('unknown code and unknown action fall back to HTTP status', () {
      final error = CloudApiException.fromResponse(402, {
        'error': {'code': 'X', 'message': '', 'action': 'y', 'request_id': 'r'},
      });
      expect(error.action, CloudErrorAction.openPaywall);
      expect(error.message, isNotEmpty);
    });

    test('non-JSON error page becomes a generic error', () {
      final error = CloudApiException.fromResponse(502, null);
      expect(error.status, 502);
      expect(error.action, CloudErrorAction.showMessage);
      expect(error.message, '服务暂时不可用，请稍后再试');
    });

    test('LOGIN_TICKET_EXPIRED does not end a session', () {
      final error = CloudApiException.fromResponse(400, {
        'error': {
          'code': 'LOGIN_TICKET_EXPIRED',
          'message': 'm',
          'action': 'login',
          'request_id': 'r',
        },
      });
      expect(error.endsSession, isFalse);
    });
  });

  group('CloudApi', () {
    test('every request carries client headers; writes carry X-Request-Id',
        () async {
      final h = _Harness((request) async => switch (request.url.path) {
            '/v1/auth/otp/verify' => _json(200, {..._tokens('1'), 'is_new_user': true}),
            _ => _json(200, {'devices': []}),
          });
      final result = await h.api.verifyOtp(' cat@example.com ', '123456');
      await h.api.devices();

      expect(result.isNewUser, isTrue);
      final installId = await h.api.store.installId();
      for (final request in h.requests) {
        expect(request.headers['X-Install-Id'], installId);
        expect(request.headers['X-Platform'], 'android');
        expect(request.headers['X-App-Version'], isNotEmpty);
      }
      final login = h.at('/auth/otp/verify').single;
      expect(CloudSessionStore.isUuid(login.headers['X-Request-Id']!), isTrue);
      expect(login.headers['Authorization'], isNull);
      final body = jsonDecode(login.body) as Map<String, dynamic>;
      expect(body['email'], 'cat@example.com');
      expect(body['device'], {
        'install_id': installId,
        'platform': 'android',
        'app_version': body['device']['app_version'],
        'model': 'Xiaomi 14',
        'os_version': 'Android 15',
      });

      final list = h.at('/me/devices').single;
      expect(list.headers['X-Request-Id'], isNull);
      expect(list.headers['Authorization'], 'Bearer access-1');
      expect((await h.api.store.readTokens())!.refreshToken, 'refresh-1');
    });

    test('401 UNAUTHENTICATED refreshes once and retries with the same request id',
        () async {
      var profileCalls = 0;
      final h = _Harness((request) async {
        switch (request.url.path) {
          case '/v1/auth/otp/verify':
            return _json(200, {..._tokens('1'), 'is_new_user': false});
          case '/v1/auth/refresh':
            return _json(200, _tokens('2'));
          case '/v1/me/profile':
            profileCalls++;
            return request.headers['Authorization'] == 'Bearer access-2'
                ? _json(200, {'display_name': '肥喵', 'updated_at': '2026-09-30T02:00:00Z'})
                : _error(401, 'UNAUTHENTICATED', 'refresh_or_login');
        }
        return _json(404, {});
      });
      await _login(h);

      final profile = await h.api.updateProfile(displayName: '肥喵');

      expect(profile.displayName, '肥喵');
      expect(profileCalls, 2);
      final refresh = h.at('/auth/refresh').single;
      expect(jsonDecode(refresh.body), {'refresh_token': 'refresh-1'});
      final ids = h.at('/me/profile').map((r) => r.headers['X-Request-Id']).toSet();
      expect(ids, hasLength(1));
      expect((await h.api.store.readTokens())!.accessToken, 'access-2');
      expect(h.ended, isEmpty);
    });

    test('concurrent 401s share one refresh', () async {
      final gate = Completer<void>();
      final h = _Harness((request) async {
        switch (request.url.path) {
          case '/v1/auth/otp/verify':
            return _json(200, {..._tokens('1'), 'is_new_user': false});
          case '/v1/auth/refresh':
            await gate.future;
            return _json(200, _tokens('2'));
        }
        return request.headers['Authorization'] == 'Bearer access-2'
            ? _json(200, {'devices': []})
            : _error(401, 'UNAUTHENTICATED', 'refresh_or_login');
      });
      await _login(h);

      final calls = [h.api.devices(), h.api.devices(), h.api.devices()];
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await Future.wait(calls);

      expect(h.at('/auth/refresh'), hasLength(1));
    });

    test('refresh rejected ends the session without touching anything else',
        () async {
      final h = _Harness((request) async => switch (request.url.path) {
            '/v1/auth/otp/verify' => _json(200, {..._tokens('1'), 'is_new_user': false}),
            '/v1/auth/refresh' =>
              _error(401, 'SESSION_REVOKED', 'login', message: '你已在其他设备退出'),
            _ => _error(401, 'UNAUTHENTICATED', 'refresh_or_login'),
          });
      await _login(h);
      final installId = await h.api.store.installId();

      await expectLater(
        h.api.me(),
        throwsA(isA<CloudApiException>()
            .having((e) => e.code, 'code', CloudErrorCode.sessionRevoked)),
      );

      expect(h.api.hasSession, isFalse);
      expect(await h.api.store.readTokens(), isNull);
      expect(await h.api.store.installId(), installId);
      expect(h.ended.single.message, '你已在其他设备退出');
    });

    test('SESSION_REVOKED on a request ends the session without refreshing',
        () async {
      final h = _Harness((request) async => switch (request.url.path) {
            '/v1/auth/otp/verify' => _json(200, {..._tokens('1'), 'is_new_user': false}),
            _ => _error(401, 'SESSION_REVOKED', 'login'),
          });
      await _login(h);

      await expectLater(h.api.me(), throwsA(isA<CloudApiException>()));

      expect(h.at('/auth/refresh'), isEmpty);
      expect(h.api.hasSession, isFalse);
      expect(h.ended, hasLength(1));
    });

    test('ACCOUNT_BANNED ends the session', () async {
      final h = _Harness((request) async => switch (request.url.path) {
            '/v1/auth/otp/verify' => _json(200, {..._tokens('1'), 'is_new_user': false}),
            _ => _error(403, 'ACCOUNT_BANNED', 'show_message', message: '账号已被封禁'),
          });
      await _login(h);

      await expectLater(h.api.me(), throwsA(isA<CloudApiException>()));
      expect(h.api.hasSession, isFalse);
      expect(h.ended.single.code, CloudErrorCode.accountBanned);
    });

    test('server error on refresh keeps the session', () async {
      final h = _Harness((request) async => switch (request.url.path) {
            '/v1/auth/otp/verify' => _json(200, {..._tokens('1'), 'is_new_user': false}),
            '/v1/auth/refresh' => _error(500, 'INTERNAL', 'show_message'),
            _ => _error(401, 'UNAUTHENTICATED', 'refresh_or_login'),
          });
      await _login(h);

      await expectLater(h.api.me(), throwsA(isA<CloudApiException>()));
      expect(h.api.hasSession, isTrue);
      expect(h.ended, isEmpty);
    });

    test('network failure keeps the session and is reported as network',
        () async {
      var offline = false;
      final h = _Harness((request) async {
        if (offline) throw http.ClientException('no route');
        return _json(200, {..._tokens('1'), 'is_new_user': false});
      });
      await _login(h);
      offline = true;

      await expectLater(
        h.api.me(),
        throwsA(isA<CloudApiException>().having((e) => e.isNetwork, 'isNetwork', true)),
      );
      expect(h.api.hasSession, isTrue);
      expect(h.ended, isEmpty);
    });

    test('access token close to expiry is refreshed before the request',
        () async {
      final h = _Harness((request) async => switch (request.url.path) {
            '/v1/auth/otp/verify' => _json(200, {..._tokens('1'), 'is_new_user': false}),
            '/v1/auth/refresh' => _json(200, _tokens('2')),
            _ => _json(200, {'devices': []}),
          });
      await _login(h);
      h.now = h.now.add(const Duration(seconds: 870));

      await h.api.devices();

      expect(h.requests.map((r) => r.url.path).toList(),
          ['/v1/auth/refresh', '/v1/me/devices']);
      expect(h.at('/me/devices').single.headers['Authorization'], 'Bearer access-2');
    });

    test('expired refresh token ends the session locally', () async {
      final h = _Harness((request) async =>
          _json(200, {..._tokens('1'), 'is_new_user': false}));
      await _login(h);
      h.now = h.now.add(const Duration(days: 31));

      await expectLater(h.api.me(), throwsA(isA<CloudApiException>()));
      expect(h.requests, isEmpty);
      expect(h.ended.single.code, CloudErrorCode.sessionRevoked);
    });

    test('DEVICE_LIMIT exposes the device list and ticket', () async {
      final h = _Harness((request) async => switch (request.url.path) {
            '/v1/auth/password/login' => _error(409, 'DEVICE_LIMIT', 'choose_device',
                  details: {
                    'login_ticket': 'ticket-1',
                    'login_ticket_expires_in': 300,
                    'max_devices': 3,
                    'devices': [
                      {
                        'id': 'd1',
                        'platform': 'ios',
                        'model': 'iPhone16,2',
                        'last_seen_at': '2026-09-29T08:00:00Z',
                        'created_at': '2026-09-01T08:00:00Z',
                        'is_current': false,
                      },
                    ],
                  }),
            '/v1/auth/device-limit/resolve' =>
              _json(200, {..._tokens('1'), 'is_new_user': false}),
            _ => _json(404, {}),
          });

      CloudApiException? caught;
      try {
        await h.api.passwordLogin('cat@example.com', 'secret');
      } on CloudApiException catch (e) {
        caught = e;
      }
      final info = h.api.deviceLimitOf(caught!)!;
      expect(info.loginTicket, 'ticket-1');
      expect(info.maxDevices, 3);
      expect(info.devices.single.model, 'iPhone16,2');
      expect(h.api.hasSession, isFalse);

      await h.api.resolveDeviceLimit(info.loginTicket, ['d1']);
      expect(jsonDecode(h.at('/auth/device-limit/resolve').single.body),
          {'login_ticket': 'ticket-1', 'revoke_device_ids': ['d1']});
      expect(h.api.hasSession, isTrue);
    });

    test('wrong password is a plain error, not a session event', () async {
      final h = _Harness((request) async =>
          _error(401, 'INVALID_CREDENTIALS', 'show_message', message: '邮箱或密码错误'));

      await expectLater(
        h.api.passwordLogin('cat@example.com', 'bad'),
        throwsA(isA<CloudApiException>()
            .having((e) => e.message, 'message', '邮箱或密码错误')),
      );
      expect(h.at('/auth/refresh'), isEmpty);
      expect(h.ended, isEmpty);
    });

    test('entitlements sends If-None-Match and understands 304', () async {
      final h = _Harness((request) async {
        switch (request.url.path) {
          case '/v1/auth/otp/verify':
            return _json(200, {..._tokens('1'), 'is_new_user': false});
          case '/v1/entitlements':
            if (request.headers['If-None-Match'] == '"e1"') {
              return http.Response('', 304);
            }
            return _json(200, {'tier': {'key': 'free'}}, headers: {'etag': '"e1"'});
        }
        return _json(404, {});
      });
      await _login(h);

      final first = await h.api.entitlements();
      final second = await h.api.entitlements(etag: first.etag);

      expect(first.notModified, isFalse);
      expect(first.etag, '"e1"');
      expect(second.notModified, isTrue);
      expect(h.at('/entitlements').first.headers['If-None-Match'], isNull);
    });

    test('logout clears locally even when offline and is not a session event',
        () async {
      var offline = false;
      final h = _Harness((request) async {
        if (offline) throw http.ClientException('offline');
        return _json(200, {..._tokens('1'), 'is_new_user': false});
      });
      await _login(h);
      offline = true;

      await h.api.logout();

      expect(h.api.hasSession, isFalse);
      expect(await h.api.store.readTokens(), isNull);
      expect(h.ended, isEmpty);
    });

    test('restore picks up saved tokens and drops expired ones', () async {
      final h = _Harness((request) async =>
          _json(200, {..._tokens('1'), 'is_new_user': false}));
      await _login(h);

      final again = CloudApi(
        client: MockClient((_) async => _json(200, {})),
        store: CloudSessionStore(store: h.secrets),
        baseUrl: _base,
        clock: () => h.now,
      );
      expect(await again.restore(), isTrue);

      final later = CloudApi(
        client: MockClient((_) async => _json(200, {})),
        store: CloudSessionStore(store: h.secrets),
        baseUrl: _base,
        clock: () => h.now.add(const Duration(days: 31)),
      );
      expect(await later.restore(), isFalse);
      expect(await later.store.readTokens(), isNull);
    });
  });

  group('Entitlements parsing', () {
    test('hidden quota shows no bar; used_pct is clamped', () {
      final hidden = Entitlements.fromJson({
        'tier': {'key': 'free', 'name': '免费', 'is_internal': false},
        'membership': {'status': 'none', 'trial': false},
        'quota': {'display': 'hidden', 'warn_pct': [80, 100]},
        'features': {},
        'limits': {'max_images': 4, 'max_image_bytes': 1572864},
        'redeem': {'in_app': true},
        'paywall': {'tiers': []},
      });
      expect(hidden.quota.showBar, isFalse);
      expect(hidden.quota.weekly, isNull);
      expect(hidden.redeemInApp, isTrue);

      final bar = Entitlements.fromJson({
        'tier': {'key': 'standard', 'name': '普通会员', 'is_internal': false},
        'membership': {'status': 'active', 'trial': true, 'ends_at': '2026-10-30T00:00:00Z'},
        'quota': {
          'display': 'bar',
          'weekly': {'used_pct': 120, 'resets_at': '2026-10-05T00:00:00Z'},
          'bonus': {'remaining_pct': 40},
        },
        'features': {
          'ai.record': {'enabled': true, 'metering': 'quota'},
        },
        'membership_extra': 'ignored',
      });
      expect(bar.quota.showBar, isTrue);
      expect(bar.quota.weekly!.usedPct, 100);
      expect(bar.quota.bonus!.remainingPct, 40);
      expect(bar.membership.status, MembershipStatus.active);
      expect(bar.membership.trial, isTrue);
      expect(bar.features['ai.record']!.enabled, isTrue);
      expect(bar.redeemInApp, isFalse);
    });

    test('unknown membership status does not crash', () {
      final e = Entitlements.fromJson({
        'membership': {'status': 'paused'},
      });
      expect(e.membership.status, MembershipStatus.unknown);
      expect(e.quota.showBar, isFalse);
    });
  });
}
