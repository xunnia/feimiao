import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/media/chat_attachment.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/theme/app_theme_controller.dart';
import 'package:qingji/views/home/ai_chat_panel.dart';
import 'package:qingji/views/home/chat_reading_viewport.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'screenshot_font_support.dart';

const _captureKey = ValueKey('chat-theme-capture');
const _before = String.fromEnvironment('CHAT_THEME_BASELINE') == 'true';
const _output = 'outputs/ui_comparisons/2026-10-04-chat-theme';

void _theme(ThemePreset preset, {double intensity = 1}) {
  AppColors.applyTheme(
      bgTop: Color.lerp(preset.bottom, preset.top, intensity)!,
      bgBottom: preset.bottom,
      bgSolid: preset.solid,
      bgDark: preset.bottom,
      bgDarkTop: preset.top,
      cardAlphaL: 0.8,
      cardAlphaD: 0.8);
}

Future<ui.Image> _image(WidgetTester tester, {double ratio = 1}) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
  return (await tester.runAsync(() => boundary.toImage(pixelRatio: ratio)))!;
}

int _difference(ByteData data, int width, int x, int y, Color expected) {
  final offset = (y * width + x) * 4;
  final argb = expected.toARGB32();
  return [
    (data.getUint8(offset) - ((argb >> 16) & 255)).abs(),
    (data.getUint8(offset + 1) - ((argb >> 8) & 255)).abs(),
    (data.getUint8(offset + 2) - (argb & 255)).abs(),
  ].reduce(math.max);
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (Platform.environment['UPDATE_CHAT_THEME_SCREENSHOTS'] != '1') return;
  const phase = _before ? 'before' : 'after';
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final file = File('$_output/$phase/$name.png');
      if (await file.exists()) {
        throw StateError(
            'Refusing to overwrite original capture: ${file.path}');
      }
      await file.parent.create(recursive: true);
      await file.writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
      await File('$_output/$phase/$name.json').writeAsString(jsonEncode({
        'evidence': 'Flutter widget rendering; not an installed app',
        'phase': phase,
        'logical_size': [image.width / 3, image.height / 3],
        'pixel_ratio': 3,
        'source_sha256': {
          for (final path in [
            'lib/views/home/chat_reading_viewport.dart',
            'lib/views/home/ai_chat_panel.dart',
            'lib/widgets/glass_input.dart',
            'test/ai_chat_theme_transition_test.dart',
          ])
            path: sha256.convert(await File(path).readAsBytes()).toString(),
        },
      }));
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await loadScreenshotFonts(force: true);
  });
  tearDown(() {
    resetChatHistoryForTesting();
    _theme(kThemePresets.first);
  });

  // Empty history must not tint the page, regardless of input/keyboard height.
  for (final preset in kThemePresets) {
    testWidgets('background stays continuous: ${preset.key}', (tester) async {
      const height = 740;
      await tester.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final (composer, inset, intensity) in [
        (80.0, 0.0, 1.0),
        (280.0, 0.0, 0.5),
        (180.0, 300.0, 1.0),
      ]) {
        _theme(preset, intensity: intensity);
        final theme = preset.forceDark ? AppTheme.dark() : AppTheme.light();
        await tester.pumpWidget(RepaintBoundary(
            key: _captureKey,
            child: MaterialApp(
                theme: theme,
                home: DecoratedBox(
                    decoration: AppColors.pageBackground(theme.brightness),
                    child: Padding(
                        padding: EdgeInsets.only(bottom: inset),
                        child: ChatReadingViewport(
                            history: (_) => const SizedBox.expand(),
                            header: const SizedBox.shrink(),
                            topFade: const SizedBox.shrink(),
                            composer: SizedBox(height: composer)))))));
        await tester.pump();
        final image = await _image(tester);
        final data = (await tester.runAsync(() => image.toByteData()))!;
        var maxDifference = 0;
        for (var y = 0; y < height; y++) {
          maxDifference = math.max(
              maxDifference,
              _difference(data, image.width, 180, y,
                  AppColors.pageBgAt(theme.brightness, (y + 0.5) / height)));
        }
        image.dispose();
        if (_before && !preset.solid) {
          expect(maxDifference, greaterThan(5),
              reason: 'Known pre-fix overlay must be reproduced.');
        } else {
          expect(maxDifference, lessThanOrEqualTo(1),
              reason: '${preset.key}, composer=$composer, keyboard=$inset');
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('history fades without tinting or blocking composer taps',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var tapped = false;
    _theme(kThemePresets[1]);
    await tester.pumpWidget(RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
            home: ColoredBox(
                color: Colors.white,
                child: ChatReadingViewport(
                    history: (_) => const ColoredBox(color: Colors.black),
                    header: const SizedBox.shrink(),
                    topFade: const SizedBox.shrink(),
                    composer: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => tapped = true,
                        child: const SizedBox(height: 180)))))));
    await tester.pump();
    final image = await _image(tester);
    final data = (await tester.runAsync(() => image.toByteData()))!;
    expect(_difference(data, image.width, 180, 500, Colors.black), 0);
    expect(_difference(data, image.width, 180, 640, const Color(0xFF808080)),
        lessThanOrEqualTo(1));
    expect(_difference(data, image.width, 180, 739, Colors.white),
        lessThanOrEqualTo(1));
    image.dispose();
    await tester.tapAt(const Offset(180, 640));
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('short viewport keeps finite fade stops', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Center(
            child: SizedBox(
                width: 240,
                height: 60,
                child: ChatReadingViewport(
                    history: _emptyHistory,
                    header: SizedBox.shrink(),
                    topFade: SizedBox.shrink(),
                    composer: SizedBox(height: 80))))));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final scene in [
    (name: 'empty-warm', preset: 0, inset: 0.0, width: 450.0, scale: 1.0),
    (name: 'empty-pink', preset: 2, inset: 0.0, width: 450.0, scale: 1.0),
    (name: 'empty-white', preset: 1, inset: 0.0, width: 450.0, scale: 1.0),
    (name: 'empty-night', preset: 5, inset: 0.0, width: 450.0, scale: 1.0),
    (name: 'keyboard-warm', preset: 0, inset: 320.0, width: 450.0, scale: 1.0),
    (name: 'attachments-warm', preset: 0, inset: 0.0, width: 450.0, scale: 1.0),
    (name: 'large-text-warm', preset: 0, inset: 0.0, width: 320.0, scale: 2.0),
    (
      name: 'conversation-warm',
      preset: 0,
      inset: 0.0,
      width: 450.0,
      scale: 1.0
    ),
  ]) {
    testWidgets('full chat theme: ${scene.name}', (tester) async {
      final repo = AppRepository();
      Directory? temp;
      var sessionId = 'record';
      if (scene.name == 'conversation-warm') {
        sessionId = (await tester.runAsync(() async {
          temp = await Directory.systemTemp.createTemp('fm_chat_theme_');
          await databaseFactory.setDatabasesPath(temp!.path);
          await repo.init();
          final session = await repo.createChatSession(title: '周末安排');
          await repo.addChatSessionMessage(
              sessionId: session.id, role: 'user', text: '这周末想轻松一点。');
          await repo.addChatSessionMessage(
              sessionId: session.id,
              role: 'answer',
              question: '这周末想轻松一点。',
              text: '## 周末安排\n\n'
                  '不必安排太满，留些时间给自己。\n\n'
                  '${List.generate(8, (i) => '${i + 1}. **放慢节奏**，走熟悉的路线，沿途找一家小店坐坐。\n\n休息一下再决定下一步，不必为了完成计划而赶路。').join('\n\n')}');
          return session.id;
        }))!;
      }
      addTearDown(() async {
        if (temp != null) {
          await repo.closeForTest();
          await temp!.delete(recursive: true);
        }
        repo.dispose();
      });
      await tester.binding.setSurfaceSize(Size(scene.width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final preset = kThemePresets[scene.preset];
      _theme(preset);
      final base = preset.forceDark ? AppTheme.dark() : AppTheme.light();
      final theme = base.copyWith(
          textTheme: base.textTheme
              .apply(fontFamilyFallback: const [screenshotCjkFontFamily]));
      final attachments = scene.name == 'attachments-warm'
          ? [
              for (final name in ['dining', 'shopping', 'travel'])
                ChatAttachment(
                    kind: ChatAttachmentKind.image,
                    path: File('assets/book_covers/$name.png').absolute.path,
                    name: '$name.png',
                    mimeType: 'image/png',
                    sizeBytes: 100)
            ]
          : <ChatAttachment>[];
      await tester.pumpWidget(RepaintBoundary(
          key: _captureKey,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      padding: const EdgeInsets.only(top: 24, bottom: 28),
                      viewPadding: const EdgeInsets.only(top: 24, bottom: 28),
                      viewInsets: EdgeInsets.only(bottom: scene.inset),
                      textScaler: TextScaler.linear(scene.scale)),
                  child: child!),
              home: ChangeNotifierProvider<AppRepository>.value(
                  value: repo,
                  child: AiChatPanel(
                      sessionId: sessionId,
                      fullScreen: true,
                      recordOnly: false,
                      initialText: attachments.isEmpty
                          ? null
                          : '看看这三张图片，帮我安排周末。\n我希望节奏轻松一点。',
                      initialDraftAttachments: attachments,
                      onSwitchToManual: () {})))));
      for (var i = 0; i < 24; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      if (scene.name == 'conversation-warm') {
        expect(find.textContaining('周末安排'), findsWidgets);
      }
      if (attachments.isNotEmpty) {
        expect(find.byKey(const ValueKey('ai-chat-draft-attachment-2')),
            findsOneWidget);
      }
      expect(find.byKey(const ValueKey('ai-chat-input-field')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, scene.name);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}

Widget _emptyHistory(EdgeInsets padding) => const SizedBox.expand();
