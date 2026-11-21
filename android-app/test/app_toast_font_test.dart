import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/widgets/app_toast.dart';

import 'screenshot_font_support.dart';

/// 顶部轻提示字体统一验证 & 同场景前后图（浅色、深色、320dp窄屏+200%大字）。
/// 运行 `UPDATE_TOAST_FONT_SCREENSHOTS=1 TOAST_FONT_PHASE=before|after` 出图到
/// `outputs/ui_comparisons/2026-11-22-app-toast-font/`。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadScreenshotFonts(force: true);
    // 改前截图里旧轻提示走框架默认 monospace，借本机等宽字体还原真机等宽效果；
    // 改后轻提示不再走 monospace，只用 App 自己的 Nunito + NotoSansSC。
    if (Platform.environment['UPDATE_TOAST_FONT_SCREENSHOTS'] == '1') {
      for (final path in [
        Platform.environment['FEIMIAO_MONO_FONT'],
        r'C:\Windows\Fonts\consola.ttf',
        '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
      ]) {
        if (path == null || !File(path).existsSync()) continue;
        await (FontLoader('monospace')
              ..addFont(Future.value(
                  ByteData.sublistView(await File(path).readAsBytes()))))
            .load();
        break;
      }
    }
  });

  Future<void> pumpAndCapture(
    WidgetTester tester, {
    required String sceneName,
    required ThemeData theme,
    required Size logicalSize,
    required double textScale,
    required String toastText,
    bool assertUnifiedFont = true,
  }) async {
    tester.view.physicalSize = logicalSize * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const captureKey = ValueKey('toast-font-capture');
    late BuildContext hostContext;
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            Widget body = DecoratedBox(
              decoration: AppColors.pageBackground(theme.brightness),
              child: child!,
            );
            // 仅拍改前图时为离屏引擎补汉字回退（还原真机效果，避免改前图汉字成方框）；
            // 正常测试和改后图不注入任何额外回退，确保 app_toast 自己走主题字体。
            if (Platform.environment['TOAST_FONT_PHASE'] == 'before') {
              body = DefaultTextStyle.merge(
                style: const TextStyle(
                  fontFamilyFallback: [screenshotCjkFontFamily],
                ),
                child: body,
              );
            }
            return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(textScale)),
              child: body,
            );
          },
          home: Scaffold(
            body: Builder(
              builder: (context) {
                hostContext = context;
                final cs = Theme.of(context).colorScheme;
                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 88, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '正文参照：Nunito + NotoSansSC',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '对比数字与英文：1234567890 · AI · CSV · ¥128.50',
                          style: TextStyle(
                            fontSize: 14,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    showAppToast(
      hostContext,
      toastText,
      icon: Icons.info_outline,
      hold: const Duration(seconds: 3),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final toastFinder = find.text(toastText);
    expect(toastFinder, findsOneWidget);

    if (assertUnifiedFont) {
      final renderParagraph = tester.renderObject<RenderParagraph>(toastFinder);
      final effective = renderParagraph.text.style!;
      expect(effective.fontFamily, 'Nunito');
      expect(effective.fontFamilyFallback, contains('NotoSansSC'));
      expect(effective.decoration, TextDecoration.none);
      expect(effective.color, Colors.white);
    }

    // 确认轻提示没有超出屏幕边界。
    final rect = tester.getRect(toastFinder);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(logicalSize.width));
    expect(tester.takeException(), isNull);

    if (Platform.environment['UPDATE_TOAST_FONT_SCREENSHOTS'] == '1') {
      final phase = Platform.environment['TOAST_FONT_PHASE'] ?? 'after';
      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(captureKey));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3);
        final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        image.dispose();
        final dir =
            Directory('outputs/ui_comparisons/2026-11-22-app-toast-font');
        await dir.create(recursive: true);
        await File('${dir.path}/${sceneName}_$phase.png').writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      });
    }

    // 等轻提示自己收起，避免残留计时器。
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('浅色主题：顶部轻提示使用 App 主题字体 Nunito + NotoSansSC，不走 monospace',
      (tester) async {
    await pumpAndCapture(
      tester,
      sceneName: 'light_390',
      theme: AppTheme.light(),
      logicalSize: const Size(390, 320),
      textScale: 1.0,
      toastText: '发现 12 笔账单已同步，AI 识别 CSV 共 ¥128.50',
      assertUnifiedFont: Platform.environment['TOAST_FONT_PHASE'] != 'before',
    );
  });

  testWidgets('深色主题：顶部轻提示使用 App 主题字体且白字清晰可读', (tester) async {
    await pumpAndCapture(
      tester,
      sceneName: 'dark_390',
      theme: AppTheme.dark(),
      logicalSize: const Size(390, 320),
      textScale: 1.0,
      toastText: '发现 12 笔账单已同步，AI 识别 CSV 共 ¥128.50',
      assertUnifiedFont: Platform.environment['TOAST_FONT_PHASE'] != 'before',
    );
  });

  testWidgets('320dp 窄屏 + 200% 大字：顶部轻提示使用 App 字体且不溢出', (tester) async {
    await pumpAndCapture(
      tester,
      sceneName: 'narrow_320_scale200',
      theme: AppTheme.light(),
      logicalSize: const Size(320, 360),
      textScale: 2.0,
      toastText: '发现 12 笔账单已同步，AI 识别 CSV 共 ¥128.50',
      assertUnifiedFont: Platform.environment['TOAST_FONT_PHASE'] != 'before',
    );
  });
}
