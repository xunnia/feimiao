import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/ai/web_search.dart';
import 'package:qingji/core/media/chat_attachment.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/theme/app_theme_controller.dart';
import 'package:qingji/views/home/ai_chat_panel.dart';

import 'screenshot_font_support.dart';

const _key = ValueKey('chat-popup-capture');

void main() {
  setUpAll(() => loadScreenshotFonts(force: true));
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 16; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
  }

  Future<void> pump(WidgetTester tester, Widget child, bool dark) async {
    await tester.binding.setSurfaceSize(const Size(420, 912));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final preset = kThemePresets[dark ? 5 : 0];
    AppColors.applyTheme(
        bgTop: preset.top,
        bgBottom: preset.bottom,
        bgSolid: preset.solid,
        bgDark: preset.bottom,
        bgDarkTop: preset.top,
        cardAlphaL: 0.8,
        cardAlphaD: 0.8);
    await tester.pumpWidget(RepaintBoundary(
        key: _key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            home: Scaffold(
                backgroundColor: Colors.transparent,
                body: DecoratedBox(
                    decoration: AppColors.pageBackground(
                        dark ? Brightness.dark : Brightness.light),
                    child: SizedBox.expand(child: child))))));
    await settle(tester);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (Platform.environment['UPDATE_CHAT_READING_SCREENSHOTS'] != '1') return;
    final phase = Platform.environment['CHAT_READING_PHASE'] ?? 'after';
    final root =
        Directory('outputs/ui_comparisons/2026-10-04-chat-reading/$phase');
    final source = File(Platform.environment['CHAT_POPUP_SOURCE'] ??
        'lib/views/home/ai_chat_panel.dart');
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      image.dispose();
      await root.create(recursive: true);
      await File('${root.path}/$name.png').writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
      await File('${root.path}/$name.json').writeAsString(jsonEncode({
        'evidence': 'Flutter widget rendering; not an installed app',
        'phase': phase,
        'source_sha256': sha256.convert(await source.readAsBytes()).toString(),
        'source': source.path,
        'size': [420, 912],
        'pixel_ratio': 3,
      }));
    });
  }

  for (final dark in [false, true]) {
    final name = dark ? 'night' : 'warm';
    testWidgets('来源弹层 $name', (tester) async {
      await pump(
          tester,
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 160, 16, 0),
              child: buildAiChatAnswerForTesting(
                  text: '先留出休息时间，再安排两件小事。',
                  sources: const [
                    AiWebSource(
                        title: '周末安排',
                        url: 'https://example.com/weekend',
                        snippet: '开放时间和交通信息'),
                    AiWebSource(
                        title: '开放时间', url: 'https://example.org/hours'),
                  ])),
          dark);
      await tester.tap(find.text('2 个来源'));
      await settle(tester);
      expect(find.text('来源'), findsOneWidget);
      if (Platform.environment['CHAT_READING_PHASE'] != 'before') {
        final surface = tester.widget<Container>(
            find.byKey(const ValueKey('ai-chat-sources-surface')));
        final scheme = Theme.of(tester.element(find.text('来源'))).colorScheme;
        expect((surface.decoration as BoxDecoration).color,
            AppColors.sheetSurface(scheme).withValues(alpha: 0.98));
      }
      await capture(tester, 'sources-$name');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('长按菜单主题 $name', (tester) async {
      await pump(
          tester,
          Stack(children: [
            Positioned(
                top: 170,
                right: 22,
                child: Text('这周末想轻松一点',
                    style: aiChatMessageBodyStyleForTesting(
                        (dark ? AppTheme.dark() : AppTheme.light())
                            .colorScheme))),
            buildAiChatMessageActionOverlayForTesting(
                anchor: const Rect.fromLTWH(160, 160, 230, 54)),
          ]),
          dark);
      expect(find.text('今天 23:39'), findsOneWidget);
      expect(find.text('复制'), findsOneWidget);
      expect(find.text('编辑'), findsOneWidget);
      expect(find.text('选择文本'), findsOneWidget);
      if (Platform.environment['CHAT_READING_PHASE'] != 'before') {
        final surface = tester.widget<Container>(
            find.byKey(const ValueKey('ai-chat-message-action-card')));
        final scheme = Theme.of(tester.element(find.text('复制'))).colorScheme;
        expect((surface.decoration as BoxDecoration).color,
            AppColors.sheetSurface(scheme).withValues(alpha: 0.94));
      }
      await capture(tester, 'menu-$name');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('点击图片打开预览', (tester) async {
    final repo = AppRepository();
    await pump(
        tester,
        ChangeNotifierProvider<AppRepository>.value(
            value: repo,
            child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 120, 16, 0),
                child: buildAiChatUserMessageForTesting(
                    text: '看看这张图片',
                    attachments: [
                      ChatAttachment(
                          kind: ChatAttachmentKind.image,
                          path: File('assets/book_covers/dining.png')
                              .absolute
                              .path,
                          name: 'dining.png',
                          mimeType: 'image/png',
                          sizeBytes: 100),
                    ]))),
        false);
    await tester.tap(find.byType(Image).first);
    await settle(tester);
    final before = Platform.environment['CHAT_READING_PHASE'] == 'before';
    expect(find.byKey(const ValueKey('ai-chat-attachment-preview')),
        before ? findsNothing : findsOneWidget);
    await capture(tester, 'image-preview');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
