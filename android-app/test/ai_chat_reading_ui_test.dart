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
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'screenshot_font_support.dart';

const _captureKey = ValueKey('chat-reading-capture');
const _sources = [
  AiWebSource(title: '周末安排', url: 'https://example.com/weekend'),
  AiWebSource(title: '开放时间', url: 'https://example.org/hours'),
];
const _readingText = '## 周末安排\n\n'
    '先留出休息时间，再安排 **两件小事**。\n\n'
    '1. 上午沿着熟悉的路线散步，遇到喜欢的小店可以停一会儿，不必为了完成计划而赶路。\n'
    '2. 午后读书，把需要处理的事情放到下周。\n\n'
    '> 不必把每段空闲都安排满。\n\n'
    '| 安排 | 时间 | 注意事项 |\n'
    '| --- | ---: | --- |\n'
    '| 散步 | 40 分钟 | 选熟悉的路线，途中可以停下来休息 |\n'
    '| 看书 | 60 分钟 | 在安静的地方慢慢读，不设完成任务 |\n\n'
    '```text\n周六：散步、看书\n周日：留给自己\n```';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final baselineErrors = <String>[];
  setUp(baselineErrors.clear);
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await loadScreenshotFonts(force: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 24; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    final error = tester.takeException();
    if (Platform.environment['CHAT_READING_PHASE'] == 'before' &&
        error != null) {
      baselineErrors.add(error.toString());
    } else {
      expect(error, isNull);
    }
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (Platform.environment['UPDATE_CHAT_READING_SCREENSHOTS'] != '1') {
      return;
    }
    final phase = Platform.environment['CHAT_READING_PHASE'] ?? 'after';
    final dir =
        Directory('outputs/ui_comparisons/2026-10-04-chat-reading/$phase');
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      image.dispose();
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png').writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
      await File('${dir.path}/$name.json').writeAsString(jsonEncode({
        'evidence': 'Flutter widget rendering; not an installed app',
        'phase': phase,
        'source_sha256': sha256
            .convert(
                await File('lib/views/home/ai_chat_panel.dart').readAsBytes())
            .toString(),
        'size': [boundary.size.width, boundary.size.height],
        'pixel_ratio': 3,
        'known_baseline_errors': baselineErrors,
      }));
    });
  }

  Future<void> pump(WidgetTester tester, Widget child,
      {bool dark = false, double width = 420, double scale = 1}) async {
    await tester.binding.setSurfaceSize(Size(width, 912));
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
    final base = dark ? AppTheme.dark() : AppTheme.light();
    final theme = base.copyWith(
        textTheme: base.textTheme
            .apply(fontFamilyFallback: const [screenshotCjkFontFamily]));
    await tester.pumpWidget(RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: DecoratedBox(
                    decoration: AppColors.pageBackground(base.brightness),
                    child: child)),
            home: child)));
    await settle(tester);
  }

  tearDown(() {
    resetChatHistoryForTesting();
  });

  for (final dark in [false, true]) {
    final themeName = dark ? 'night' : 'warm';
    testWidgets('阅读层级 $themeName', (tester) async {
      await pump(
          tester,
          Scaffold(
              backgroundColor: Colors.transparent,
              body: SafeArea(
                  child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: buildAiChatAnswerForTesting(
                          text: _readingText, sources: _sources)))),
          dark: dark);
      await capture(tester, 'reading-$themeName');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('思考详情 $themeName', (tester) async {
      await pump(
          tester,
          Scaffold(
              backgroundColor: Colors.transparent,
              body: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 120, 16, 0),
                  child: buildAiChatThinkingForTesting(
                      completed: true,
                      elapsed: const Duration(seconds: 12),
                      summary: '核对用户希望放慢节奏的偏好，整理三个简短安排。'))),
          dark: dark);
      await tester.tap(find.text('思考了 12s'));
      await settle(tester);
      await capture(tester, 'thinking-$themeName');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final (width, scale) in [(420.0, 1.0), (320.0, 2.0)]) {
    testWidgets('真实会话阅读 ${width.toInt()} ${scale}x', (tester) async {
      late Directory temp;
      final repo = AppRepository();
      final session = await tester.runAsync(() async {
        temp = await Directory.systemTemp.createTemp('fm_reading_');
        await databaseFactory.setDatabasesPath(temp.path);
        await repo.init();
        final session = await repo.createChatSession(title: '周末安排');
        await repo.addChatSessionMessage(
            sessionId: session.id, role: 'user', text: '这周末想轻松一点，帮我整理三个安排。');
        await repo.addChatSessionMessage(
            sessionId: session.id,
            role: 'answer',
            question: '这周末想轻松一点，帮我整理三个安排。',
            text: '可以留得松一些：\n\n'
                '1. **上午散步**，选熟悉的路线。\n'
                '2. **午后看书**，不设完成任务。\n'
                '3. **傍晚吃饭**，选交通方便的店。\n\n'
                '先看自己的精力，再决定要不要增加安排。',
            attachmentsJson: jsonEncode({
              'version': 1,
              'interrupted': false,
              'sources': [
                for (final source in _sources)
                  {'title': source.title, 'url': source.url, 'snippet': ''}
              ],
            }));
        return session;
      });
      await pump(
          tester,
          ChangeNotifierProvider<AppRepository>.value(
              value: repo,
              child: AiChatPanel(
                  sessionId: session!.id,
                  fullScreen: true,
                  recordOnly: false,
                  onSwitchToManual: () {})),
          width: width,
          scale: scale);
      await capture(tester, 'conversation-${width.toInt()}-${scale.toInt()}x');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await repo.closeForTest();
        await temp.delete(recursive: true);
      });
    });
  }

  testWidgets('三图附件与补充文字', (tester) async {
    final attachments = [
      for (final name in ['dining', 'shopping', 'travel'])
        ChatAttachment(
            kind: ChatAttachmentKind.image,
            path: File('assets/book_covers/$name.png').absolute.path,
            name: '$name.png',
            mimeType: 'image/png',
            sizeBytes: 100)
    ];
    final repo = AppRepository();
    await pump(
        tester,
        ChangeNotifierProvider<AppRepository>.value(
            value: repo,
            child: Scaffold(
                backgroundColor: Colors.transparent,
                body: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 120, 16, 0),
                    child: buildAiChatUserMessageForTesting(
                        text: '看看这三张图片，帮我安排周末。', attachments: attachments)))));
    await capture(tester, 'three-images');
    expect(find.byType(Image), findsNWidgets(3));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
