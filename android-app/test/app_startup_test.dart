import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/main.dart' as app;
import 'package:qingji/theme/app_theme_controller.dart';

void main() {
  testWidgets('后台报告服务只在 Flutter 第一帧之后启动', (tester) async {
    final calls = <String>[];
    final repo = AppRepository();

    app.schedulePostFrameServices(
      repo,
      initializeReportScheduler: () async {
        calls.add('initialize');
        return true;
      },
      rescheduleReports: (_) async => calls.add('reschedule'),
    );

    expect(calls, isEmpty);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(calls, ['initialize', 'reschedule']);
  });

  testWidgets('完整 hydration 未成功时不启动后台报告服务', (tester) async {
    final calls = <String>[];
    final repo = AppRepository();

    app.schedulePostFrameServices(
      repo,
      repositoryReady: Future<void>.value(),
      initializeReportScheduler: () async {
        calls.add('initialize');
        return true;
      },
      rescheduleReports: (_) async => calls.add('reschedule'),
    );

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(calls, isEmpty);
  });

  test('Android 启动窗口使用主页色而不是模板纯白', () {
    final resourceFiles = [
      'android/app/src/main/res/drawable/launch_background.xml',
      'android/app/src/main/res/drawable-v21/launch_background.xml',
      'android/app/src/main/res/values/styles.xml',
      'android/app/src/main/res/values-night/styles.xml',
      'android/app/src/main/res/values-v31/styles.xml',
      'android/app/src/main/res/values-night-v31/styles.xml',
    ];

    for (final path in resourceFiles) {
      final contents = File(path).readAsStringSync();
      expect(contents, contains('@color/launch_background'), reason: path);
      expect(contents, isNot(contains('@android:color/white')), reason: path);
    }

    for (final path in [
      'android/app/src/main/res/values-v31/styles.xml',
      'android/app/src/main/res/values-night-v31/styles.xml',
    ]) {
      final contents = File(path).readAsStringSync();
      expect(
        contents,
        contains('android:windowSplashScreenAnimatedIcon'),
        reason: path,
      );
      expect(contents, contains('@drawable/splash_transparent'), reason: path);
      expect(
        contents,
        contains('android:windowSplashScreenIconBackgroundColor'),
        reason: path,
      );
      expect(contents, contains('@android:color/transparent'), reason: path);
    }

    final transparentIcon = File(
      'android/app/src/main/res/drawable/splash_transparent.xml',
    ).readAsStringSync();
    expect(transparentIcon, contains('@android:color/transparent'));
  });

  testWidgets('主页首帧不依赖仓库完成初始化', (tester) async {
    final repo = AppRepository();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppRepository>.value(value: repo),
          ChangeNotifierProvider<AppThemeController>.value(
            value: AppThemeController.instance,
          ),
        ],
        child: const app.QingJiApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(app.RootShell), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-record-input-shell')),
      findsOneWidget,
    );

    // RootShell schedules a four-second silent update check. Dispose the page
    // and advance fake time so the test does not leave that existing timer open.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  });
}
