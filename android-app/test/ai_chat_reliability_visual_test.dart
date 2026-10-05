import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/theme/app_theme_controller.dart';
import 'package:qingji/views/home/ai_chat_panel.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'screenshot_font_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late AppRepository repo;
  late String sessionId;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await loadScreenshotFonts(force: true);
  });
  setUp(() async {
    resetChatHistoryForTesting();
    temp = await Directory.systemTemp.createTemp('feimiao_chat_visual_');
    await databaseFactory.setDatabasesPath(temp.path);
    repo = AppRepository();
    await repo.init();
    sessionId = (await repo.createChatSession(title: '周末安排')).id;
    await repo.addChatSessionMessage(
        sessionId: sessionId, role: 'user', text: '周末想轻松一点，帮我整理三个不赶时间的安排。');
    await repo.addChatSessionMessage(
        sessionId: sessionId,
        role: 'answer',
        question: '周末想轻松一点，帮我整理三个不赶时间的安排。',
        text: '可以把周末留得松一些：\n\n'
            '1. **上午散步**，找一条熟悉的路线，不赶时间。\n'
            '2. **午后看书**，给自己留一段安静的时间。\n'
            '3. **傍晚吃饭**，和朋友约一家方便到达的店。\n\n'
            '如果还想加一件事，可以先看自己的精力，再决定。',
        attachmentsJson: jsonEncode({
          'version': 1,
          'interrupted': true,
          'sources': <Object>[],
          'thinking': {
            'kind': 'queryAnswer',
            'startedAt': '2026-10-04T12:00:00.000',
            'modelStartedAt': '2026-10-04T12:00:00.000',
            'completedAt': '2026-10-04T12:00:11.000',
            'hidden': false,
            'steps': [
              {
                'kind': 'queryAnswer',
                'startedAt': '2026-10-04T12:00:00.000',
                'completedAt': '2026-10-04T12:00:11.000',
                'detail': '按用户希望放慢节奏的偏好，整理三个简短安排。',
              }
            ],
          },
        }));
  });
  tearDown(() async {
    await repo.closeForTest();
    await temp.delete(recursive: true);
    resetChatHistoryForTesting();
  });

  for (final preset in [kThemePresets[0], kThemePresets[1], kThemePresets[5]]) {
    for (final (width, scale) in [(420.0, 1.0), (320.0, 2.0)]) {
      testWidgets('聊天冷恢复 ${preset.key} ${width.toInt()} ${scale}x',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 912));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        AppColors.applyTheme(
            bgTop: preset.top,
            bgBottom: preset.bottom,
            bgSolid: preset.solid,
            cardAlphaL: 0.8,
            cardAlphaD: 0.8,
            bgDark: preset.bottom,
            bgDarkTop: preset.top);
        final base = preset.forceDark ? AppTheme.dark() : AppTheme.light();
        final theme = base.copyWith(
            textTheme: base.textTheme
                .apply(fontFamilyFallback: const [screenshotCjkFontFamily]),
            primaryTextTheme: base.primaryTextTheme
                .apply(fontFamilyFallback: const [screenshotCjkFontFamily]));
        const capture = ValueKey('chat-reliability-capture');
        await tester.pumpWidget(RepaintBoundary(
            key: capture,
            child: ChangeNotifierProvider<AppRepository>.value(
                value: repo,
                child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: theme,
                    builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(textScaler: TextScaler.linear(scale)),
                        child: DecoratedBox(
                            decoration:
                                AppColors.pageBackground(base.brightness),
                            child: child)),
                    home: AiChatPanel(
                        sessionId: sessionId,
                        fullScreen: true,
                        recordOnly: false,
                        onSwitchToManual: () {})))));
        for (var frame = 0; frame < 24; frame++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 15)));
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(tester.takeException(), isNull);
        expect(find.textContaining('可以把周末留得松一些', findRichText: true),
            findsWidgets);
        final viewport = tester.widget<Opacity>(
            find.byKey(const ValueKey('ai-chat-history-viewport')));
        expect(viewport.opacity, 1);
        expect(
            find.byKey(const ValueKey('ai-chat-input-field')), findsOneWidget);
        final isBaseline =
            Platform.environment['CHAT_RELIABILITY_PHASE'] == 'before';
        if (!isBaseline) {
          final model =
              tester.getRect(find.byKey(const ValueKey('ai-chat-model-pill')));
          final effort =
              tester.getRect(find.byKey(const ValueKey('ai-chat-effort-pill')));
          final send =
              tester.getRect(find.byKey(const ValueKey('ai-chat-send-button')));
          expect(model.right, lessThanOrEqualTo(effort.left));
          expect(effort.right, lessThanOrEqualTo(send.left));
          for (final text in find
              .descendant(
                  of: find.byKey(const ValueKey('ai-chat-model-pill')),
                  matching: find.byType(Text))
              .evaluate()) {
            expect(tester.getRect(find.byWidget(text.widget)).right,
                lessThanOrEqualTo(model.right + 0.1));
          }
          expect(find.text('回复已中断'), findsOneWidget);
          expect(find.byTooltip('重新生成'), findsOneWidget);
          expect(find.byKey(const ValueKey('ai-chat-continue-answer')),
              findsNothing);
        }
        if (Platform.environment['UPDATE_CHAT_RELIABILITY_SCREENSHOTS'] ==
            '1') {
          final boundary =
              tester.renderObject<RenderRepaintBoundary>(find.byKey(capture));
          final phase =
              Platform.environment['CHAT_RELIABILITY_PHASE'] ?? 'after';
          final dir = Directory(
              'outputs/ui_comparisons/2026-10-04-chat-reliability/$phase');
          final bounds = <String, List<double>>{};
          void mark(String name, Rect rect) {
            if (rect.top < 0 || rect.bottom > 912) return;
            bounds[name] = [rect.left, rect.top, rect.right, rect.bottom];
          }

          if (!isBaseline) {
            mark('thinking', tester.getRect(find.text('处理了 11s')));
            mark('interrupted', tester.getRect(find.text('回复已中断')));
          }
          mark(
              'selectors',
              tester
                  .getRect(find.byKey(const ValueKey('ai-chat-model-pill')))
                  .expandToInclude(tester.getRect(
                      find.byKey(const ValueKey('ai-chat-send-button')))));
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 3);
            final bytes =
                (await image.toByteData(format: ui.ImageByteFormat.png))!;
            image.dispose();
            await dir.create(recursive: true);
            await File(
                    '${dir.path}/${preset.key}-${width.toInt()}-${scale.toInt()}x.png')
                .writeAsBytes(bytes.buffer
                    .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
            await File(
                    '${dir.path}/${preset.key}-${width.toInt()}-${scale.toInt()}x.json')
                .writeAsString(jsonEncode(bounds));
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
