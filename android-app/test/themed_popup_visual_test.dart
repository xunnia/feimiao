import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/theme/app_theme_controller.dart';
import 'package:qingji/views/account/account_widgets.dart';
import 'package:qingji/views/budget/budget_rule_sheet.dart';
import 'package:qingji/views/common/app_sheet.dart';
import 'package:qingji/views/home/ai_chat_panel.dart';
import 'package:qingji/views/home/chat_add_sheet.dart';
import 'package:qingji/views/home/home_view.dart';
import 'package:qingji/views/settings/theme_settings_view.dart';
import 'package:qingji/views/settings/settings_view.dart';
import 'package:qingji/widgets/app_line_icon.dart';
import 'package:qingji/widgets/app_date_picker.dart';
import 'package:qingji/widgets/ios_dialogs.dart';
import 'package:qingji/widgets/ios_form.dart';
import 'package:qingji/widgets/ios_menu.dart';
import 'package:qingji/widgets/settings_ui.dart';

import 'screenshot_font_support.dart';

const _captureKey = ValueKey('themed-popup-capture');

void _applyPreset(ThemePreset preset, {double intensity = 1}) {
  AppColors.applyTheme(
    bgTop: Color.lerp(preset.bottom, preset.top, intensity)!,
    bgBottom: preset.bottom,
    bgSolid: preset.solid,
    cardAlphaL: AppColors.cardAlphaLight,
    cardAlphaD: AppColors.cardAlphaDark,
    bgDark: preset.forceDark ? preset.bottom : const Color(0xFF211E1C),
    bgDarkTop: preset.forceDark ? preset.top : const Color(0xFF211E1C),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final capture = Platform.environment['UPDATE_POPUP_UI_SCREENSHOTS'] == '1';
  setUpAll(() async {
    await loadScreenshotFonts();
    if (!capture) return;
    final emojiFont = File(Platform.environment['FEIMIAO_EMOJI_FONT'] ??
        r'C:\src\xunni-codex\.tmp\flutter-audit-sdk\flutter\engine\src\flutter\txt\third_party\fonts\NotoColorEmoji.ttf');
    if (!emojiFont.existsSync()) {
      throw StateError('头像截图需要 Noto Color Emoji，请设置 FEIMIAO_EMOJI_FONT。');
    }
    final bytes = await emojiFont.readAsBytes();
    await (FontLoader('NotoColorEmoji')
          ..addFont(Future.value(ByteData.sublistView(bytes))))
        .load();
  });
  final narrow = Platform.environment['POPUP_NARROW'] == '1';
  final suffix = Platform.environment['POPUP_SHOT_SUFFIX'] ?? 'after';
  final outDir = Platform.environment['POPUP_SHOT_OUTPUT'] ??
      'outputs/ui_comparisons/2026-10-02-themed-popups/verified';
  final controller = AppThemeController.instance;
  final kinds = Platform.environment['POPUP_KINDS']?.split(',') ??
      [
        'confirm',
        'form',
        'menu',
        'budget',
        'model',
        'effort',
        'add',
        'date',
        'month',
        'account',
        'profile',
        'about',
        'terms',
        'privacy',
      ];
  final savedKey = controller.presetKey;
  final savedIntensity = controller.bgIntensity;
  final savedAlpha = controller.cardAlpha;
  tearDown(() {
    controller.presetKey = savedKey;
    controller.bgIntensity = savedIntensity;
    controller.cardAlpha = savedAlpha;
    _applyPreset(controller.preset, intensity: savedIntensity);
  });

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!capture) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final target = File('$outDir/${name}_$suffix.png');
        await target.parent.create(recursive: true);
        await target.writeAsBytes(data!.buffer.asUint8List(), flush: true);
      } finally {
        image.dispose();
      }
    });
  }

  for (final preset in kThemePresets) {
    for (final kind in kinds) {
      testWidgets('${preset.key} $kind uses the production popup',
          (tester) async {
        await tester.binding.setSurfaceSize(
          narrow ? const Size(320, 640) : const Size(420, 912),
        );
        if (narrow) {
          tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
        }
        addTearDown(() {
          tester.binding.setSurfaceSize(null);
          tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
        });
        controller.presetKey = preset.key;
        controller.bgIntensity = 1;
        controller.cardAlpha = AppColors.cardAlphaLight;
        _applyPreset(preset);
        final repo = AppRepository();
        final settingsScene = ['about', 'terms', 'privacy'].contains(kind);
        addTearDown(repo.dispose);
        await tester.pumpWidget(
          RepaintBoundary(
            key: _captureKey,
            child: MultiProvider(
              providers: [
                ChangeNotifierProvider<AppRepository>.value(value: repo),
                ChangeNotifierProvider<AppThemeController>.value(
                  value: controller,
                ),
              ],
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                // AppBar has an independent text style. Supply the device's
                // CJK fallback to the desktop renderer too, for both baselines.
                theme: (() {
                  final base =
                      preset.forceDark ? AppTheme.dark() : AppTheme.light();
                  return base.copyWith(
                      textTheme: base.textTheme.apply(
                        fontFamilyFallback: const [
                          screenshotCjkFontFamily,
                          'NotoColorEmoji',
                        ],
                      ),
                      appBarTheme: base.appBarTheme.copyWith(
                        titleTextStyle:
                            base.appBarTheme.titleTextStyle!.copyWith(
                          fontFamily: 'Nunito',
                          fontFamilyFallback: const [screenshotCjkFontFamily],
                        ),
                      ));
                })(),
                builder: (context, child) => DecoratedBox(
                  decoration: AppColors.pageBackground(
                    preset.forceDark ? Brightness.dark : Brightness.light,
                  ),
                  child: child,
                ),
                home: settingsScene
                    ? const Material(
                        type: MaterialType.transparency,
                        child: SettingsView(),
                      )
                    : const ThemeSettingsView(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(
          settingsScene ? SettingsView : ThemeSettingsView,
        ));
        Future<dynamic> popup;
        var popupDepth = 1;
        switch (kind) {
          case 'confirm':
            popup = showConfirmDialog(
              context,
              title: '删除这条预算？',
              message: '删除后会重新计算对应月份的预算，已记录的账单不变。',
              confirmText: '删除',
              destructive: true,
            );
          case 'form':
            popup = showIosFormDialog(
              context,
              title: '修改名称',
              subtitle: '为账本设置一个容易识别的名字',
              content: Builder(
                builder: (context) => AppLabeledField(
                  label: '账本名称',
                  child: TextField(
                    decoration: iosInputDecoration(context, hint: '例如：日常生活'),
                  ),
                ),
              ),
            );
          case 'menu':
            final anchor = tester.element(find.text('恢复默认'));
            popup = showIosMenu(anchor, [
              IosMenuItem(
                label: '加星',
                lineIcon: AppLineIcons.star,
                onTap: () {},
              ),
              IosMenuItem(
                label: '编辑',
                lineIcon: AppLineIcons.pencil,
                onTap: () {},
              ),
              IosMenuItem(
                label: '删除',
                lineIcon: AppLineIcons.trash,
                destructive: true,
                onTap: () {},
              ),
            ]);
          case 'budget':
            popup =
                showBudgetRuleSheet(context, bookId: 1, suggestionYuan: 3000);
          case 'model':
          case 'effort':
            final anchor = tester.element(find.text('卡片透明度'));
            final options = [
              const AiModelOption(
                providerId: 'test',
                providerLabel: 'GPT',
                model: 'gpt-5.4',
              ),
              const AiModelOption(
                providerId: 'test',
                providerLabel: 'GPT',
                model: 'gpt-5.4-mini',
              ),
            ];
            showAiFloatingPopup(
              context: context,
              anchor: anchor,
              width: 195,
              child: kind == 'model'
                  ? buildClaudeModelPopupForTesting(
                      options: options,
                      currentKey: options.first.key,
                      onSelected: (_) {},
                    )
                  : buildClaudeEffortPopupForTesting(
                      currentEffort: AiReasoningEffort.high,
                      onChanged: (_) {},
                    ),
            );
            popup = Future<void>.value();
          case 'add':
            popup = showChatAddSheet(
              context,
              onAttachmentsPicked: (_) async {},
              webSearchEnabled: true,
              onWebSearchChanged: (_) async {},
              recentPhotos: Future.value([]),
            );
          case 'date':
            popup = showAppDatePicker(context, initial: DateTime(2026, 10, 2));
          case 'account':
            popup = showAccountSheet<void>(
                context,
                AccountFormSheet(
                  title: '登录肥喵',
                  children: [
                    Builder(
                        builder: (ctx) => AppLabeledField(
                              label: '邮箱地址',
                              child: TextField(
                                  decoration: iosInputDecoration(ctx,
                                      hint: 'name@example.com')),
                            ))
                  ],
                ));
          case 'profile':
            popup = showEditProfileSheet(context);
          case 'about':
          case 'terms':
          case 'privacy':
            final row = find.widgetWithText(SettingsRow, '关于').hitTestable();
            await tester.scrollUntilVisible(row, 200,
                scrollable: find.byType(Scrollable).first);
            await tester.tap(row);
            await tester.pumpAndSettle();
            expect(find.text('使用条款').hitTestable(), findsOneWidget);
            if (kind != 'about') {
              await tester.tap(find.text(kind == 'terms' ? '使用条款' : '隐私政策'));
              await tester.pumpAndSettle();
              popupDepth = 2;
            }
            popup = Future<void>.value();
          default:
            popup = appSheet<void>(
              context,
              child: buildHomeMonthPickerForTesting(),
            );
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await screenshot(
          tester,
          '${preset.key}_$kind${narrow ? '_narrow' : ''}',
        );
        for (var layer = 0; layer < popupDepth; layer++) {
          Navigator.of(context, rootNavigator: true).pop();
          await tester.pumpAndSettle();
        }
        await popup;
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
