import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/views/settings/settings_view.dart';
import 'package:qingji/widgets/app_buttons.dart';
import 'package:qingji/widgets/settings_ui.dart';

import 'screenshot_font_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadScreenshotFonts);

  Future<void> setViewport(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('设置页使用统一分组、行和按钮外壳', (tester) async {
    await setViewport(tester);
    final repo = AppRepository();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey('global-ui-settings-capture'),
              child: const SettingsView(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(SettingsGroup), findsWidgets);
    expect(find.byType(SettingsRow), findsWidgets);
    expect(find.byType(AppSwitch), findsNWidgets(2));
    expect(find.byType(AppCircleButton), findsOneWidget);
    if (Platform.environment['UPDATE_GLOBAL_UI_SCREENSHOTS'] == '1') {
      await expectLater(
        find.byKey(const ValueKey('global-ui-settings-capture')),
        matchesGoldenFile('../outputs/global_ui/settings.png'),
      );
    }
  });

  testWidgets('全局控件画廊在浅色主题保持同一边界和层级', (tester) async {
    await setViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('global-ui-gallery-capture'),
            child: DecoratedBox(
              decoration: AppColors.pageBackground(Brightness.light),
              child: Material(
                color: Colors.transparent,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SheetHeader(
                      title: '统一弹层',
                      subtitle: '关闭、标题和主要动作保持同一条基线',
                      onClose: () {},
                      actionLabel: '保存',
                      onAction: () {},
                    ),
                    SettingsGroup(
                      margin: EdgeInsets.zero,
                      children: [
                        SettingsRow(
                          leading:
                              const Icon(CupertinoIcons.slider_horizontal_3),
                          title: '显示设置',
                          subtitle: '标准设置行和发丝线分隔',
                          trailing: const Icon(CupertinoIcons.chevron_forward),
                          onTap: () {},
                        ),
                        SettingsRow(
                          leading: const Icon(CupertinoIcons.bell),
                          title: '通知提醒',
                          trailing: const AppSwitch(
                            value: true,
                            semanticLabel: '通知提醒',
                            onChanged: null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        AppCircleButton(
                          icon: CupertinoIcons.plus,
                          semanticLabel: '添加',
                          onPressed: () {},
                        ),
                        AppPillButton(label: '确认', onPressed: () {}),
                        const AppCheckmark(
                          value: true,
                          semanticLabel: '已选择',
                          onChanged: null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(SheetHeader), findsOneWidget);
    expect(find.byType(SettingsGroup), findsOneWidget);
    expect(find.byType(AppPillButton), findsWidgets);
    if (Platform.environment['UPDATE_GLOBAL_UI_SCREENSHOTS'] == '1') {
      await expectLater(
        find.byKey(const ValueKey('global-ui-gallery-capture')),
        matchesGoldenFile('../outputs/global_ui/gallery.png'),
      );
    }
  });

  testWidgets('设置页在窄屏、大字号和深色主题下不溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
    });

    final repo = AppRepository();
    addTearDown(repo.dispose);
    final capturedErrors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      capturedErrors.add(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: ChangeNotifierProvider<AppRepository>.value(
          value: repo,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: SettingsView()),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(capturedErrors, isEmpty);
    expect(tester.takeException(), isNull);
    final scrollable = find.byType(Scrollable).first;
    await tester.drag(scrollable, const Offset(0, -900));
    await tester.pump();
    expect(capturedErrors, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
