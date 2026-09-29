import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/cloud/cloud_account.dart';
import 'package:qingji/core/cloud/cloud_api.dart';
import 'package:qingji/core/cloud/cloud_models.dart';
import 'package:qingji/core/cloud/cloud_session_store.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/views/account/account_page.dart';
import 'package:qingji/views/account/account_section.dart';
import 'package:qingji/views/account/login_sheet.dart';
import 'package:qingji/views/settings/ai_setting_view.dart';
import 'package:qingji/views/settings/settings_view.dart';
import 'package:qingji/widgets/app_buttons.dart';

http.Response _json(int status, Object body, {Map<String, String>? headers}) =>
    http.Response(jsonEncode(body), status, headers: {
      'content-type': 'application/json; charset=utf-8',
      ...?headers,
    });

Map<String, Object?> _error(String code, String message, String action,
        [Map<String, Object?> details = const {}]) =>
    {
      'error': {
        'code': code,
        'message': message,
        'action': action,
        'request_id': 'r',
        'details': details,
      },
    };

Map<String, Object?> _device(String id, {bool current = false}) => {
      'id': id,
      'platform': 'android',
      'model': current ? '本机型号' : 'Pixel $id',
      'last_seen_at': '2026-09-29T00:00:00Z',
      'created_at': '2026-09-01T00:00:00Z',
      'is_current': current,
    };

/// 假服务端：按路径回固定数据，可以切换设备超限、票据过期、额度隐藏。
class _Server {
  final requests = <http.Request>[];
  bool deviceLimit = false;
  bool ticketExpired = false;
  String quotaDisplay = 'bar';
  bool internal = false;

  /// 服务端下发的功能开关，比如 `{'adv.byok': true}`。
  Map<String, bool> features = {};

  Map<String, Object?> get entitlements => {
        'tier': {
          'key': internal ? 'internal' : 'standard',
          'name': internal ? '内部' : '普通会员',
          'is_internal': internal,
        },
        'membership': {
          'status': 'active',
          'ends_at': '2026-12-31T00:00:00Z',
          'trial': false,
        },
        'quota': {
          'display': quotaDisplay,
          'weekly': {'used_pct': 42, 'resets_at': '2026-10-05T00:00:00Z'},
          'warn_pct': [80, 100],
        },
        'features': {
          for (final entry in features.entries)
            entry.key: {'enabled': entry.value},
        },
        'limits': {'max_images': 4, 'max_image_bytes': 1572864},
        'redeem': {'in_app': true},
        'paywall': {'tiers': []},
      };

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    switch (request.url.path) {
      case '/v1/auth/otp/send':
        return _json(200, {'resend_after_s': 60});
      case '/v1/auth/otp/verify':
      case '/v1/auth/password/login':
        if (deviceLimit) {
          return _json(
            409,
            _error('DEVICE_LIMIT', '登录设备已达上限', 'choose_device', {
              'login_ticket': 't1',
              'login_ticket_expires_in': 300,
              'max_devices': 3,
              'devices': [_device('d1'), _device('d2')],
            }),
          );
        }
        return _json(200, _tokens);
      case '/v1/auth/device-limit/resolve':
        if (ticketExpired) {
          return _json(
              400, _error('LOGIN_TICKET_EXPIRED', '登录已超时', 'login'));
        }
        return _json(200, _tokens);
      case '/v1/me':
        return _json(200, {
          'id': '6f1c7c1e-4b1e-4c6a-9a51-0c9f2b6f8f10',
          'email': 'cat@example.com',
          'created_at': '2026-09-01T00:00:00Z',
          'has_password': false,
          'profile': {'display_name': '肥喵'},
        });
      case '/v1/me/devices':
        return _json(200, {
          'devices': [_device('me', current: true), _device('d1')],
        });
      case '/v1/entitlements':
        return _json(200, entitlements, headers: {'etag': '"v1"'});
      case '/v1/auth/logout':
        return http.Response('', 204);
    }
    return _json(404, _error('NOT_FOUND', '没有这个接口', 'show_message'));
  }

  int count(String path) =>
      requests.where((r) => r.url.path == '/v1$path').length;

  Map<String, Object?> lastBody(String path) => jsonDecode(
        requests.lastWhere((r) => r.url.path == '/v1$path').body,
      ) as Map<String, Object?>;
}

const _tokens = {
  'access_token': 'a1',
  'access_expires_in': 900,
  'refresh_token': 'r1',
  'refresh_expires_in': 2592000,
  'is_new_user': false,
};

CloudAccount _account(_Server server, {bool enabled = true}) => CloudAccount(
      enabled: enabled,
      api: CloudApi(
        client: MockClient(server.handle),
        store: CloudSessionStore(store: MemoryCloudSecretStore()),
        baseUrl: 'https://api.test/v1',
        deviceInfo: () async => const {},
      ),
    );

Widget _host(CloudAccount account, Widget child) =>
    ChangeNotifierProvider<CloudAccount>.value(
      value: account,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      ),
    );

Widget _section(CloudAccount account) =>
    _host(account, ListView(children: const [AccountSettingsSection()]));

/// 等 toast 自己消失，免得测试结束时还有计时器挂着。
Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

Future<void> _signIn(CloudAccount account) async {
  await account.init();
  await account.loginWithCode('cat@example.com', '123456');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> tallViewport(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('账号功能关闭时设置页和原来一样', (tester) async {
    await tallViewport(tester);
    final server = _Server();
    final account = _account(server, enabled: false);
    await account.init();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppRepository>.value(value: AppRepository()),
          ChangeNotifierProvider<CloudAccount>.value(value: account),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SettingsView()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('登录 / 注册'), findsNothing);
    expect(find.byKey(const ValueKey('membership-card')), findsNothing);
    expect(server.requests, isEmpty);
  });

  testWidgets('上层没挂账号时设置页照常显示', (tester) async {
    await tallViewport(tester);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: AppRepository(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SettingsView()),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('登录 / 注册'), findsNothing);
    expect(find.text('管理'), findsOneWidget);
  });

  testWidgets('没登录显示登录入口，登录页密码方式直接可见', (tester) async {
    await tallViewport(tester);
    final server = _Server();
    final account = _account(server);
    await account.init();
    await tester.pumpWidget(_section(account));

    await tester.tap(find.byKey(const ValueKey('account-login-row')));
    await tester.pumpAndSettle();

    expect(find.byType(LoginSheet), findsOneWidget);
    expect(find.text('验证码'), findsWidgets);
    expect(find.text('密码'), findsOneWidget);
    expect(find.textContaining('账本只存在这台手机上'), findsOneWidget);

    await tester.tap(find.text('密码'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('account-password')), findsOneWidget);
    expect(find.byKey(const ValueKey('account-code')), findsNothing);
  });

  testWidgets('验证码登录后显示会员卡和兑换码', (tester) async {
    await tallViewport(tester);
    final server = _Server();
    final account = _account(server);
    await account.init();
    await tester.pumpWidget(_section(account));
    await tester.tap(find.byKey(const ValueKey('account-login-row')));
    await tester.pumpAndSettle();

    // 邮箱不对时不发请求，就地提示
    await tester.tap(find.byKey(const ValueKey('account-send-code')));
    await tester.pump();
    expect(find.text('请先填写正确的邮箱'), findsOneWidget);
    expect(server.count('/auth/otp/send'), 0);

    await tester.enterText(
        find.byKey(const ValueKey('account-email')), 'cat@example.com');
    await tester.tap(find.byKey(const ValueKey('account-send-code')));
    await tester.pump();
    await tester.pump();
    expect(server.count('/auth/otp/send'), 1);
    expect(server.lastBody('/auth/otp/send'),
        {'purpose': 'login', 'email': 'cat@example.com'});
    expect(find.text('60 秒后重发'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('account-code')), '123456');
    await tester.tap(find.text('登录'));
    await _settle(tester);

    expect(account.signedIn, isTrue);
    expect(find.byType(LoginSheet), findsNothing);
    expect(find.byKey(const ValueKey('membership-card')), findsOneWidget);
    expect(find.text('普通会员'), findsOneWidget);
    expect(find.text('已用 42%'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-redeem-row')), findsOneWidget);
    expect(find.text('cat@example.com'), findsOneWidget);
  });

  testWidgets('设备数已满：选设备下线后登录', (tester) async {
    await tallViewport(tester);
    final server = _Server()..deviceLimit = true;
    final account = _account(server);
    await account.init();
    await tester.pumpWidget(_section(account));
    await tester.tap(find.byKey(const ValueKey('account-login-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('密码'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('account-email')), 'cat@example.com');
    await tester.enterText(
        find.byKey(const ValueKey('account-password')), 'password1');
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();

    expect(find.text('设备数已满'), findsOneWidget);
    expect(find.textContaining('最多同时登录 3 台'), findsOneWidget);

    // 没选设备不能继续
    await tester.tap(find.text('继续'));
    await tester.pump();
    expect(find.text('至少选一台设备下线'), findsOneWidget);

    server.deviceLimit = false;
    await tester.tap(find.byKey(const ValueKey('device-d2')));
    await tester.pump();
    await tester.tap(find.text('继续'));
    await _settle(tester);

    expect(server.lastBody('/auth/device-limit/resolve')['revoke_device_ids'],
        ['d2']);
    expect(account.signedIn, isTrue);
    expect(find.byType(LoginSheet), findsNothing);
  });

  testWidgets('选设备太久票据过期，回到登录第一步', (tester) async {
    await tallViewport(tester);
    final server = _Server()
      ..deviceLimit = true
      ..ticketExpired = true;
    final account = _account(server);
    await account.init();
    await tester.pumpWidget(_section(account));
    await tester.tap(find.byKey(const ValueKey('account-login-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('密码'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('account-email')), 'cat@example.com');
    await tester.enterText(
        find.byKey(const ValueKey('account-password')), 'password1');
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('device-d1')));
    await tester.pump();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(find.text('登录 / 注册'), findsWidgets);
    expect(find.text('等待时间太久，请重新登录'), findsOneWidget);
    expect(account.signedIn, isFalse);
  });

  testWidgets('额度设为隐藏时会员卡不显示额度', (tester) async {
    final server = _Server()..quotaDisplay = 'hidden';
    final account = _account(server);
    await _signIn(account);
    await tester.pumpWidget(_host(
      account,
      MembershipCard(entitlements: account.entitlements!),
    ));

    expect(find.text('普通会员'), findsOneWidget);
    expect(find.byKey(const ValueKey('quota-weekly')), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('会员卡不出现积分、金额和 token', (tester) async {
    final server = _Server();
    final account = _account(server);
    await _signIn(account);
    await tester.pumpWidget(_host(
      account,
      MembershipCard(
        entitlements: account.entitlements!,
        now: DateTime(2026, 9, 30),
      ),
    ));

    expect(find.byKey(const ValueKey('quota-weekly')), findsOneWidget);
    expect(find.textContaining('10月5日'), findsOneWidget);
    for (final word in ['积分', '点数', 'token', 'Token', '¥', '元']) {
      expect(find.textContaining(word), findsNothing, reason: word);
    }
  });

  test('会员状态文案', () {
    final now = DateTime(2026, 9, 30);
    expect(
      membershipStatusText(
        Membership(status: MembershipStatus.active, endsAt: DateTime(2026, 12, 31)),
        now: now,
      ),
      '12月31日 00:00 到期',
    );
    expect(
      membershipStatusText(
          const Membership(status: MembershipStatus.none), now: now),
      '未开通会员',
    );
    expect(
      membershipStatusText(
          const Membership(status: MembershipStatus.expired), now: now),
      '已到期',
    );
  });

  testWidgets('账号页：设备列表、退出登录后回到设置', (tester) async {
    await tallViewport(tester);
    final server = _Server();
    final account = _account(server);
    await _signIn(account);
    await tester.pumpWidget(_section(account));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('account-row')));
    await tester.pumpAndSettle();

    expect(find.byType(AccountPage), findsOneWidget);
    expect(find.text('本机'), findsOneWidget);
    expect(find.text('下线'), findsOneWidget);
    expect(find.text('设置密码'), findsOneWidget);
    expect(find.textContaining('不保存你的账本'), findsOneWidget);

    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('account-logout')), 200);
    await tester.tap(find.byKey(const ValueKey('account-logout')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出'));
    await _settle(tester);

    expect(server.count('/auth/logout'), 1);
    expect(account.signedIn, isFalse);
    expect(find.byType(AccountPage), findsNothing);
    expect(find.byKey(const ValueKey('account-login-row')), findsOneWidget);
    expect(find.byType(AppBackButton), findsNothing);
  });

  group('设置首页「AI」分组', () {
    test('账号功能关着或没挂账号时全部显示', () {
      final off = settingsAiRowsFor(_account(_Server(), enabled: false));
      expect(off.showAiAccount, isTrue);
      expect(off.showTaskDiagnostics, isTrue);
      final none = settingsAiRowsFor(null);
      expect(none.showAiAccount, isTrue);
      expect(none.showTaskDiagnostics, isTrue);
    });

    test('没登录：和改版前一样全部显示', () async {
      final account = _account(_Server());
      await account.init();
      final rows = settingsAiRowsFor(account);
      expect(rows.showAiAccount, isTrue);
      expect(rows.showTaskDiagnostics, isTrue);
    });

    test('登录后按服务端开关，没下发的按关', () async {
      final standard = _account(_Server());
      await _signIn(standard);
      final s = settingsAiRowsFor(standard);
      expect(s.showAiAccount, isFalse);
      expect(s.showTaskDiagnostics, isFalse);

      final byokOnly = _account(_Server()..features = {'adv.byok': true});
      await _signIn(byokOnly);
      final b = settingsAiRowsFor(byokOnly);
      expect(b.showAiAccount, isTrue);
      expect(b.showTaskDiagnostics, isFalse);

      final all = _account(_Server()
        ..features = {'adv.byok': true, 'adv.diagnostics': true});
      await _signIn(all);
      final a = settingsAiRowsFor(all);
      expect(a.showAiAccount, isTrue);
      expect(a.showTaskDiagnostics, isTrue);
    });

    test('只看开关不看档位：内部档但开关关着也不显示', () async {
      final account = _account(_Server()
        ..internal = true
        ..features = {'adv.byok': false});
      await _signIn(account);
      final rows = settingsAiRowsFor(account);
      expect(rows.showAiAccount, isFalse);
      expect(rows.showTaskDiagnostics, isFalse);
    });

    testWidgets('默认构建：AI 分组四行，记忆页两个分段都能切', (tester) async {
      await tallViewport(tester);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppRepository>.value(
          value: AppRepository(),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: SettingsView()),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('AI'), findsOneWidget);
      for (final key in const [
        'settings-ai-account',
        'settings-ai-memory',
        'settings-ai-schedules',
        'settings-ai-tasks',
        'settings-ai-privacy',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
      expect(find.text('AI 记账设置'), findsNothing);
      for (final gone in const ['统一搜索', '技能与连接', '本地模型伴侣']) {
        expect(find.text(gone), findsNothing, reason: gone);
      }

      await tester.tap(find.byKey(const ValueKey('settings-ai-memory')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('memory-hub-tabs')), findsOneWidget);
      expect(find.text('没有已授权记忆'), findsOneWidget);
      await tester.tap(find.text('喵学到的分类'));
      await tester.pumpAndSettle();
      expect(find.text('还没学到东西'), findsOneWidget);
    });

    testWidgets('隐私与数据从设置首页直接进', (tester) async {
      await tallViewport(tester);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppRepository>.value(
          value: AppRepository(),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: SettingsView()),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('settings-ai-privacy')));
      await tester.pumpAndSettle();
      expect(find.byType(AiPrivacyDataPage), findsOneWidget);
      expect(find.text('AI 隐私确认'), findsOneWidget);
    });

    testWidgets('普通会员登录后设置页不出现 AI 账号和任务与诊断', (tester) async {
      await tallViewport(tester);
      final account = _account(_Server());
      await _signIn(account);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppRepository>.value(value: AppRepository()),
            ChangeNotifierProvider<CloudAccount>.value(value: account),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: SettingsView()),
          ),
        ),
      );
      await _settle(tester);

      expect(find.byKey(const ValueKey('settings-ai-account')), findsNothing);
      expect(find.byKey(const ValueKey('settings-ai-tasks')), findsNothing);
      expect(find.byKey(const ValueKey('settings-ai-memory')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('settings-ai-schedules')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-ai-privacy')), findsOneWidget);
    });
  });
}
