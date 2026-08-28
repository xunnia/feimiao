import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/ai/chat_intent.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/views/home/ai_chat_panel.dart';
import 'package:qingji/views/home/record_input_bar.dart';
import 'package:qingji/widgets/glass.dart';
import 'package:qingji/widgets/glass_input.dart';

import 'screenshot_font_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('主页 AI 记账不会在请求前用本地意图拦截自然语言', () {
    expect(
      resolveAiPanelIntent(
        recordOnly: true,
        text: '帮我查一下上个月的花销，并顺便说说今天的天气',
      ),
      ChatIntentKind.record,
    );
    expect(
      resolveAiPanelIntent(recordOnly: true, text: '随便聊聊最近的新闻'),
      ChatIntentKind.record,
    );
    expect(
      resolveAiPanelIntent(recordOnly: false, text: '这个月花了多少'),
      ChatIntentKind.query,
    );
  });

  testWidgets('喵助手发送按钮与主页记一记使用相同右边界', (tester) async {
    final repo = AppRepository();

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      _buildAlignmentPreview(repo, withCjkFallback: false),
    );
    await tester.pump();

    final aiShell = tester.getRect(
      find.byKey(const ValueKey('ai-chat-input-shell')),
    );
    final homeShell = tester.getRect(
      find.byKey(const ValueKey('home-record-input-shell')),
    );
    final aiSend = tester.getRect(
      find.byKey(const ValueKey('ai-chat-send-button')),
    );
    final aiModeSwitch = tester.getRect(
      find.byKey(const ValueKey('ai-chat-mode-switch-pill')),
    );
    final homeSend = tester.getRect(
      find.byKey(const ValueKey('home-record-send-button')),
    );

    expect(aiShell.right, closeTo(homeShell.right, 0.1));
    expect(aiShell.size, homeShell.size);
    expect(aiSend.right, closeTo(homeSend.right, 0.1));
    expect(aiShell.right - aiSend.right, closeTo(10, 0.1));
    expect(homeShell.right - homeSend.right, closeTo(10, 0.1));
    expect(aiSend.size, const Size(36, 36));
    expect(homeSend.size, const Size(36, 36));
    expect(aiModeSwitch.width, lessThan(150));
    expect(aiModeSwitch.right, lessThan(aiSend.left));

    final aiShellWidget = tester.widget<AppGlassInputShell>(
      find.byKey(const ValueKey('ai-chat-input-shell')),
    );
    final homeShellWidget = tester.widget<AppGlassInputShell>(
      find.byKey(const ValueKey('home-record-input-shell')),
    );
    expect(aiShellWidget.padding, homeShellWidget.padding);
    expect(aiShellWidget.opacity, homeShellWidget.opacity);
    expect(aiShellWidget.blur, 10);
    expect(homeShellWidget.blur, 6);
    final aiField = tester.widget<TextField>(
      find.byKey(const ValueKey('ai-chat-input-field')),
    );
    final aiDecoration = aiField.decoration!;
    expect(aiDecoration.hintText, '聊点什么');
    final homeHint = tester.widget<Text>(
      find.byKey(const ValueKey('home-record-input-hint')),
    );
    expect(aiDecoration.hintStyle, homeHint.style);
    expect(aiDecoration.hintStyle?.fontSize, 17);
    expect(aiDecoration.hintStyle?.fontWeight, FontWeight.w400);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ai-chat-plus-button')),
        matching: find.byType(GlassSurface),
      ),
      findsNothing,
    );

    if (Platform.environment['UPDATE_AI_INPUT_SCREENSHOTS'] == '1') {
      await loadScreenshotFonts();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        _buildAlignmentPreview(repo, withCjkFallback: true),
      );
      await tester.pump();
      await expectLater(
        find.byKey(const ValueKey('ai-chat-input-alignment-capture')),
        matchesGoldenFile(
          '../outputs/ai_chat_input_alignment/ai_chat_input_alignment.png',
        ),
      );
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('喵助手全屏输入区使用统一透明卡和无圆底加号', (tester) async {
    final repo = AppRepository();

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _buildFullscreenPreview(repo, withCjkFallback: false),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 420));

    final shell = tester.widget<AppGlassInputShell>(
      find.byKey(const ValueKey('ai-chat-input-shell')),
    );
    expect(shell.padding, AppGlassInputShell.standardPadding);
    expect(shell.blur, 10);
    expect(shell.opacity, 0.4);
    expect(
      find.byKey(const ValueKey('ai-chat-model-pill')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ai-chat-effort-pill')),
      findsOneWidget,
    );
    final modelLabelFinder = find.descendant(
      of: find.byKey(const ValueKey('ai-chat-model-label')),
      matching: find.byType(Text),
    );
    final modelLabel = tester.widget<Text>(modelLabelFinder);
    final effortLabel = tester.widget<Text>(find.text('Low').last);
    expect(modelLabel.style?.fontSize, 15);
    expect(effortLabel.style?.fontSize, 15);
    // The render rect is the glyph box (not the 15px line box); this guards
    // against the former extreme scale caused by the extra Spacer.
    expect(tester.getRect(modelLabelFinder).height, greaterThan(10));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ai-chat-plus-button')),
        matching: find.byType(GlassSurface),
      ),
      findsNothing,
    );
    final plusGlyph = find.byKey(const ValueKey('ai-chat-plus-glyph'));
    expect(plusGlyph, findsOneWidget);
    expect(tester.getSize(plusGlyph), const Size(26.4, 26.4));
    final plusRect = tester.getRect(
      find.byKey(const ValueKey('ai-chat-plus-button')),
    );
    final modelRect = tester.getRect(
      find.byKey(const ValueKey('ai-chat-model-pill')),
    );
    final effortRect = tester.getRect(
      find.byKey(const ValueKey('ai-chat-effort-pill')),
    );
    expect(modelRect.center.dy, closeTo(effortRect.center.dy, 0.1));
    expect(plusRect.center.dy, closeTo(modelRect.center.dy, 0.1));
    final modelPill = tester.widget<Container>(
      find.byKey(const ValueKey('ai-chat-model-pill')),
    );
    final effortPill = tester.widget<Container>(
      find.byKey(const ValueKey('ai-chat-effort-pill')),
    );
    expect(modelPill.decoration, isNull);
    expect(effortPill.decoration, isNull);

    if (Platform.environment['UPDATE_AI_INPUT_SCREENSHOTS'] == '1') {
      await loadScreenshotFonts();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        _buildFullscreenPreview(repo, withCjkFallback: true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 420));
      await expectLater(
        find.byType(AiChatPanel),
        matchesGoldenFile(
          '../outputs/ai_chat_input_alignment/assistant_fullscreen.png',
        ),
      );
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Widget _buildAlignmentPreview(
  AppRepository repo, {
  required bool withCjkFallback,
}) {
  return ChangeNotifierProvider<AppRepository>.value(
    value: repo,
    child: MaterialApp(
      theme: withCjkFallback
          ? ThemeData(
              fontFamily: 'Nunito',
              fontFamilyFallback: [screenshotCjkFontFamily],
              textTheme: ThemeData().textTheme.apply(
                fontFamily: 'Nunito',
                fontFamilyFallback: [screenshotCjkFontFamily],
              ),
              primaryTextTheme: ThemeData().primaryTextTheme.apply(
                fontFamily: 'Nunito',
                fontFamilyFallback: [screenshotCjkFontFamily],
              ),
            )
          : null,
      home: Scaffold(
        body: RepaintBoundary(
          key: const ValueKey('ai-chat-input-alignment-capture'),
          child: Column(
            children: [
              const SizedBox(
                width: double.infinity,
                height: 330,
                child: AiChatPanel(
                  recordOnly: false,
                  onSwitchToManual: _noop,
                ),
              ),
              const Spacer(),
              const RecordInputBar(),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _buildFullscreenPreview(
  AppRepository repo, {
  required bool withCjkFallback,
}) {
  final baseTheme = AppTheme.light();
  final theme = withCjkFallback
      ? baseTheme.copyWith(
          textTheme: baseTheme.textTheme.apply(
            fontFamily: 'Nunito',
            fontFamilyFallback: [screenshotCjkFontFamily],
          ),
          primaryTextTheme: baseTheme.primaryTextTheme.apply(
            fontFamily: 'Nunito',
            fontFamilyFallback: [screenshotCjkFontFamily],
          ),
        )
      : baseTheme;
  return ChangeNotifierProvider<AppRepository>.value(
    value: repo,
    child: MaterialApp(
      theme: theme,
      home: const AiChatPanel(
        fullScreen: true,
        recordOnly: false,
        onSwitchToManual: _noop,
      ),
    ),
  );
}

void _noop() {}
