import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/views/home/ai_chat_panel.dart';

import 'screenshot_font_support.dart';

const _output = 'outputs/ui_comparisons/2026-10-04-chat-stream';
const _phase =
    String.fromEnvironment('CHAT_STREAM_PHASE', defaultValue: 'after');
const _summary =
    '**核对信息**\n\n先核对问题中的时间范围。\n\n**整理回答**\n\n保留可以验证的结论，区分目前没有证据的部分。';

void main() {
  setUpAll(() => loadScreenshotFonts(force: true));
  for (final scene in [
    ('waiting', false, false, '', false, 393.0, 1.0),
    ('live-expanded', false, true, _summary, false, 393.0, 1.0),
    ('completed-expanded', true, true, _summary, false, 393.0, 1.0),
    ('completed-collapsed', true, false, _summary, false, 393.0, 1.0),
    ('night-live', false, true, _summary, true, 393.0, 1.0),
    ('large-live', false, true, _summary, false, 320.0, 2.0),
  ]) {
    testWidgets('流式体验 ${scene.$1}', (tester) async {
      tester.view.physicalSize = Size(scene.$6, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final brightness = scene.$5 ? Brightness.dark : Brightness.light;
      AppColors.applyTheme(
          bgTop: const Color(0xFFFFD1A9),
          bgBottom: const Color(0xFFFFF2D5),
          bgSolid: false,
          bgDark: const Color(0xFF211D1B),
          bgDarkTop: const Color(0xFF362A26),
          cardAlphaL: 0.8,
          cardAlphaD: 0.8);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness, fontFamily: 'Nunito').copyWith(
            textTheme: ThemeData(brightness: brightness).textTheme.apply(
                fontFamily: 'Nunito',
                fontFamilyFallback: [screenshotCjkFontFamily])),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scene.$7)),
            child: child!),
        home: RepaintBoundary(
            key: const ValueKey('stream-capture'),
            child: DecoratedBox(
                decoration: AppColors.pageBackground(brightness),
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  appBar: AppBar(title: const Text('喵助手')),
                  body: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Align(
                                alignment: Alignment.centerRight,
                                child: Text('请帮我核对这些信息。')),
                            const SizedBox(height: 28),
                            buildAiChatThinkingForTesting(
                                completed: scene.$2,
                                expanded: scene.$3,
                                elapsed: const Duration(seconds: 11),
                                summary: scene.$4),
                            if (scene.$2)
                              buildAiChatAnswerForTesting(
                                  text:
                                      '目前可以确认两点：\n\n1. 信息的时间范围一致。\n2. 其余结论还需要核对来源。'),
                          ])),
                ))),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      if (Platform.environment['UPDATE_CHAT_STREAM_SCREENSHOTS'] == '1') {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('stream-capture')));
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 3);
          try {
            final data =
                (await image.toByteData(format: ui.ImageByteFormat.png))!;
            final file = File('$_output/$_phase/${scene.$1}.png');
            if (await file.exists()) {
              throw StateError('Refusing to overwrite original screenshot');
            }
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data.buffer
                .asUint8List(data.offsetInBytes, data.lengthInBytes));
            await File(file.path.replaceAll('.png', '.json'))
                .writeAsString(jsonEncode({
              'phase': _phase,
              'logical_size': [scene.$6, 800],
              'text_scale': scene.$7,
              'evidence': 'Flutter Widget offscreen, not an installed app',
              'source_sha256': sha256
                  .convert(await File('lib/views/home/ai_chat_panel.dart')
                      .readAsBytes())
                  .toString(),
              'summary_widget_sha256':
                  File('lib/views/home/chat_thinking_summary.dart').existsSync()
                      ? sha256
                          .convert(await File(
                                  'lib/views/home/chat_thinking_summary.dart')
                              .readAsBytes())
                          .toString()
                      : null,
            }));
          } finally {
            image.dispose();
          }
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
