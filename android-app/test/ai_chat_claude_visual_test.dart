// Claude 桌面端风格的喵助手浮层截图验收。
// 默认只做结构/尺寸断言；设置 UPDATE_CLAUDE_POPUP_SCREENSHOTS=1 时写出 PNG。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/core/ai/chat_session.dart';
import 'package:qingji/core/ai/web_search.dart';
import 'package:qingji/core/media/recent_photos.dart';
import 'package:qingji/core/media/chat_attachment.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/views/home/ai_chat_panel.dart';
import 'package:qingji/views/home/chat_add_sheet.dart';
import 'package:qingji/widgets/app_line_icon.dart';
import 'package:qingji/widgets/ios_menu.dart';

import 'screenshot_font_support.dart';

const _visualModels = [
  'claude-fable-5',
  'claude-fable-5 1M',
  'claude-haiku-4-5',
  'claude-haiku-4-5 1M',
  'claude-opus-5',
  'claude-opus-5 1M',
  'claude-sonnet-5',
  'claude-sonnet-5 1M',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final screenshotMode =
        Platform.environment['UPDATE_CLAUDE_POPUP_SCREENSHOTS'] == '1';
    await loadScreenshotFonts();
    if (!screenshotMode) {
      final file = File(
        r'C:\src\xunni-codex\android-app\assets\fonts\Nunito-Regular.ttf',
      );
      if (file.existsSync()) {
        final bytes = file.readAsBytesSync();
        await (FontLoader('Nunito')
              ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer))))
            .load();
      }
    }

    // 截图模式由 loadScreenshotFonts() 统一加载 Material/Cupertino 图标字体；
    // 非截图模式保留原来的本地 Cupertino 字体加载，确保结构断言也能找到图标。
    if (!screenshotMode) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData == null) return;
      final hosted = Directory(
        p.join(localAppData, 'Pub', 'Cache', 'hosted', 'pub.flutter-io.cn'),
      );
      if (!hosted.existsSync()) return;
      for (final entry in hosted.listSync()) {
        if (entry is! Directory ||
            !p.basename(entry.path).startsWith('cupertino_icons-')) {
          continue;
        }
        final iconFile = File(
          p.join(entry.path, 'assets', 'CupertinoIcons.ttf'),
        );
        if (!iconFile.existsSync()) continue;
        final iconBytes = iconFile.readAsBytesSync();
        await (FontLoader('packages/cupertino_icons/CupertinoIcons')
              ..addFont(
                Future<ByteData>.value(ByteData.view(iconBytes.buffer)),
              ))
            .load();
        break;
      }
    }
  });

  testWidgets('喵助手 Claude 风格 Models 浮层截图验收', (tester) async {
    await _pumpVisualCard(
      tester,
      buildClaudeModelPopupForTesting(
        options: [
          for (final model in _visualModels)
            AiModelOption(
              providerId: 'claude-gateway',
              providerLabel: 'Claude 中转',
              model: model,
            ),
        ],
        currentKey: 'claude-gateway\u0000${_visualModels[5]}',
        onSelected: (_) {},
      ),
    );
    final modelPopup = find.byKey(const ValueKey('ai-chat-model-popup'));
    expect(modelPopup, findsOneWidget);
    final modelRect = tester.getRect(modelPopup);
    expect(modelRect.width, closeTo(195, 0.1));
    expect(modelRect.height, closeTo(224, 0.1));
    expect(find.text('Models'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.checkmark), findsOneWidget);
    expect(find.text('claude-opus-5 1M'), findsWidgets);
    final modelRowText = tester.widget<Text>(
      find.text('claude-fable-5').first,
    );
    expect(modelRowText.style?.fontSize, 15);
    final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hover.moveTo(
      tester.getCenter(find.text('claude-haiku-4-5 1M')),
    );
    await tester.pump();
    await _captureIfRequested(tester, modelPopup, 'ai_chat_claude_models.png');
    await hover.removePointer();
  });

  testWidgets('真实模型选择入口使用统一灰幕和 Claude 浮层', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (anchor) => TextButton(
                key: const ValueKey('open-live-model-popup'),
                onPressed: () => showAiModelPickerPopup(
                  context: anchor,
                  anchor: anchor,
                  options: [
                    for (final model in _visualModels)
                      AiModelOption(
                        providerId: 'claude-gateway',
                        providerLabel: 'Claude 中转',
                        model: model,
                      ),
                  ],
                  currentKey: 'claude-gateway\u0000${_visualModels[5]}',
                  onSelected: (_) {},
                ),
                child: const Text('打开模型'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-live-model-popup')));
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.byType(AppMenuScrim), findsOneWidget);
    expect(
      find.byKey(const ValueKey('unified-ios-menu-scrim')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('ai-chat-model-popup')), findsOneWidget);
  });

  testWidgets('喵助手 Claude 风格 Effort 浮层截图验收', (tester) async {
    var effort = AiReasoningEffort.max;
    await _pumpVisualCard(
      tester,
      buildClaudeEffortPopupForTesting(
        currentEffort: effort,
        onChanged: (value) => effort = value,
      ),
    );
    final effortPopup = find.byKey(const ValueKey('ai-chat-effort-popup'));
    expect(effortPopup, findsOneWidget);
    final effortRect = tester.getRect(effortPopup);
    expect(effortRect.width, closeTo(222, 0.1));
    expect(effortRect.height, closeTo(102, 0.1));
    expect(find.text('Effort'), findsOneWidget);
    expect(find.text('Faster'), findsOneWidget);
    expect(find.text('Smarter'), findsOneWidget);
    expect(find.text('?'), findsNothing);
    final effortValue = tester.widget<Text>(
      find.byKey(const ValueKey('ai-chat-effort-value')),
    );
    expect(effortValue.style?.color,
        isNot(equals(AppTheme.light().colorScheme.onSurface)));
    await _captureIfRequested(
      tester,
      effortPopup,
      'ai_chat_claude_effort_max.png',
    );

    final slider = find.byKey(const ValueKey('ai-chat-effort-slider'));
    expect(slider, findsOneWidget);
    final sliderRect = tester.getRect(slider);
    await tester.tapAt(Offset(sliderRect.right - 2, sliderRect.center.dy));
    await tester.pump(const Duration(milliseconds: 100));
    expect(effort, AiReasoningEffort.ultra);
    expect(find.text('Ultracode'), findsWidgets);
    await _captureIfRequested(
      tester,
      effortPopup,
      'ai_chat_claude_effort_ultracode.png',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('跨服务商同名模型只显示模型名，不显示服务商前缀', (tester) async {
    await _pumpVisualCard(
      tester,
      buildClaudeModelPopupForTesting(
        options: const [
          AiModelOption(
            providerId: 'deepseek',
            providerLabel: 'DeepSeek',
            model: 'shared-model',
          ),
          AiModelOption(
            providerId: 'claude',
            providerLabel: 'Claude 中转',
            model: 'shared-model',
          ),
          AiModelOption(
            providerId: 'deepseek',
            providerLabel: 'DeepSeek',
            model: 'deepseek-chat',
          ),
        ],
        currentKey: 'deepseek\u0000shared-model',
        onSelected: (_) {},
      ),
    );
    expect(find.text('DeepSeek · shared-model'), findsNothing);
    expect(find.text('Claude 中转 · shared-model'), findsNothing);
    expect(find.text('shared-model'), findsNWidgets(2));
    expect(find.text('deepseek-chat'), findsOneWidget);
  });

  testWidgets('喵助手聊天正文使用缩小且轻量的统一字阶', (tester) async {
    final preview = RepaintBoundary(
      key: const ValueKey('ai-chat-message-typography-preview'),
      child: DecoratedBox(
        decoration: AppColors.pageBackground(Brightness.light),
        child: ChangeNotifierProvider<AppRepository>.value(
          value: AppRepository(),
          child: SizedBox(
            width: 358,
            child: buildAiChatMessageTypographyForTesting(),
          ),
        ),
      ),
    );
    await _pumpVisualCard(tester, preview);

    final userText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('ai-chat-message-typography-user')),
        matching: find.byType(Text),
      ),
    );
    expect(userText.style?.fontSize, 15);
    expect(userText.style?.fontWeight, FontWeight.w400);
    expect(userText.style?.fontVariations, hasLength(1));
    expect(userText.style?.fontVariations?.single.value, 350);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ai-chat-message-typography-answer')),
        matching: find.byType(SelectableText),
      ),
      findsOneWidget,
    );
    final answerStyle =
        aiChatMessageBodyStyleForTesting(AppTheme.light().colorScheme);
    expect(answerStyle.fontSize, 15.5);
    expect(answerStyle.fontWeight, FontWeight.w400);
    expect(answerStyle.fontVariations, hasLength(1));
    expect(answerStyle.fontVariations?.single.value, 350);
    final infoText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('ai-chat-message-typography-info')),
        matching: find.byType(Text),
      ),
    );
    expect(infoText.style?.fontSize, 14);
    expect(infoText.style?.fontWeight, FontWeight.w400);
    expect(infoText.style?.fontVariations, isNull);

    await _captureIfRequested(
      tester,
      find.byKey(const ValueKey('ai-chat-message-typography-preview')),
      'ai_chat_messages.png',
    );
  });

  testWidgets('选择文本直接发生在原消息气泡，不复制到居中白框', (tester) async {
    const text = '点击启动计费就这样了';
    final repo = AppRepository();
    await _pumpVisualCard(
      tester,
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: RepaintBoundary(
          key: const ValueKey('ai-chat-user-selection-capture'),
          child: DecoratedBox(
            decoration: AppColors.pageBackground(Brightness.light),
            child: SizedBox(
              width: 390,
              height: 180,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 54, 16, 18),
                child: buildAiChatUserTextSelectionForTesting(text: text),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.controller.text, text);
    expect(editable.controller.selection.baseOffset, 0);
    expect(editable.controller.selection.extentOffset, text.length);
    expect(editable.readOnly, isTrue);
    expect(editable.selectionControls, materialTextSelectionControls);

    final scale = tester.widget<AnimatedScale>(
      find.byKey(const ValueKey('ai-chat-user-bubble-scale')),
    );
    expect(scale.scale, 1.18);
    final bubbleRect = tester.getRect(
      find.byKey(const ValueKey('ai-chat-user-bubble-surface')),
    );
    expect(bubbleRect.width, lessThan(330));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ai-chat-user-bubble-surface')),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
    await _captureIfRequested(
      tester,
      find.byKey(const ValueKey('ai-chat-user-selection-capture')),
      'ai_chat_user_text_selection.png',
    );
  });

  testWidgets('消息操作菜单使用镂空灰幕、无分隔线和统一细线图标', (tester) async {
    const anchor = Rect.fromLTWH(178, 220, 174, 48);
    await _pumpVisualCard(
      tester,
      RepaintBoundary(
        key: const ValueKey('ai-chat-message-action-capture'),
        child: DecoratedBox(
          decoration: AppColors.pageBackground(Brightness.light),
          child: SizedBox(
            width: 390,
            height: 844,
            child: Stack(
              children: [
                const Positioned(
                  left: 22,
                  right: 22,
                  top: 118,
                  child: Text(
                    '这是一段回复正文，长按消息后其他内容退到中性灰背景。',
                    style: TextStyle(fontSize: 15.5, height: 1.55),
                  ),
                ),
                Positioned.fromRect(
                  rect: anchor,
                  child: Transform.scale(
                    scale: 1.18,
                    alignment: Alignment.centerRight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppTheme.light().colorScheme.surface,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(4),
                        ),
                      ),
                      child: const Center(
                        child: Text('点击启动计费就这样了'),
                      ),
                    ),
                  ),
                ),
                buildAiChatMessageActionOverlayForTesting(anchor: anchor),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.byType(AppMenuScrim), findsOneWidget);
    expect(find.text('今天 23:39'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('选择文本'), findsOneWidget);
    expect(find.byType(AppLineIcon), findsNWidgets(3));
    expect(find.byType(Divider), findsNothing);
    await _captureIfRequested(
      tester,
      find.byKey(const ValueKey('ai-chat-message-action-capture')),
      'ai_chat_message_action_menu.png',
    );
  });

  testWidgets('思考状态只有正在思考动效，完成后显示时间和真实摘要', (tester) async {
    await _pumpVisualCard(
      tester,
      RepaintBoundary(
        key: const ValueKey('ai-chat-thinking-live-capture'),
        child: DecoratedBox(
          decoration: AppColors.pageBackground(Brightness.light),
          child: buildAiChatThinkingForTesting(),
        ),
      ),
    );
    expect(find.text('正在思考'), findsOneWidget);
    expect(find.text('...'), findsNothing);
    await _captureIfRequested(
      tester,
      find.byKey(const ValueKey('ai-chat-thinking-live-capture')),
      'ai_chat_thinking_live_1.png',
    );
    await tester.pump(const Duration(milliseconds: 520));
    await _captureIfRequested(
      tester,
      find.byKey(const ValueKey('ai-chat-thinking-live-capture')),
      'ai_chat_thinking_live_2.png',
    );

    await _pumpVisualCard(
      tester,
      RepaintBoundary(
        key: const ValueKey('ai-chat-thinking-long-live-capture'),
        child: buildAiChatThinkingForTesting(
          elapsed: const Duration(seconds: 16),
        ),
      ),
    );
    expect(find.text('正在思考 · 完成后会显示在这里。'), findsOneWidget);

    await _pumpVisualCard(
      tester,
      RepaintBoundary(
        key: const ValueKey('ai-chat-thinking-expanded-capture'),
        child: DecoratedBox(
          decoration: AppColors.pageBackground(Brightness.light),
          child: buildAiChatThinkingForTesting(
            completed: true,
            expanded: true,
            elapsed: const Duration(seconds: 12),
            sourceCount: 2,
          ),
        ),
      ),
    );
    expect(find.text('思考了 12s'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('思考了 12s')).style?.fontSize,
      15,
    );
    expect(find.text('核对了公开数据并整理出关键变化。'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
    expect(find.textContaining('整理本地账目'), findsNothing);
    await _captureIfRequested(
      tester,
      find.byKey(const ValueKey('ai-chat-thinking-expanded-capture')),
      'ai_chat_thinking_expanded.png',
    );
  });

  testWidgets('来源显示在操作栏右侧，正文不出现裸链接', (tester) async {
    const sources = [
      AiWebSource(
        title: 'Markets overview',
        url: 'https://markets.example.com/overview',
      ),
      AiWebSource(
        title: 'Fed release',
        url: 'https://fed.example.com/release',
      ),
    ];
    await _pumpVisualCard(
      tester,
      RepaintBoundary(
        key: const ValueKey('ai-chat-answer-sources-capture'),
        child: DecoratedBox(
          decoration: AppColors.pageBackground(Brightness.light),
          child: SizedBox(
            width: 358,
            child: buildAiChatAnswerForTesting(
              text:
                  '这是回答内容，详情见 https://markets.example.com/overview，来源会出现在操作栏右侧。',
              sources: sources,
            ),
          ),
        ),
      ),
    );
    expect(find.text('2 个来源'), findsOneWidget);
    expect(find.text('https://markets.example.com/overview'), findsNothing);
    final answerBody = tester.widget<SelectableText>(
      find.byType(SelectableText).first,
    );
    expect(
      answerBody.textSpan?.toPlainText(),
      isNot(contains('markets.example.com')),
    );
    expect(
      answerBody.textSpan?.toPlainText(),
      contains('来源会出现在操作栏右侧。'),
    );
    expect(find.text('Markets overview'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '2 个来源',
      ),
      findsOneWidget,
    );
    await _captureIfRequested(
      tester,
      find.byKey(const ValueKey('ai-chat-answer-sources-capture')),
      'ai_chat_answer_sources.png',
    );
  });

  testWidgets('三张已发送图片真实显示在同一气泡的一行内', (tester) async {
    const paths = [
      r'C:\src\xunni-codex\android-app\assets\book_covers\dining.png',
      r'C:\src\xunni-codex\android-app\assets\book_covers\shopping.png',
      r'C:\src\xunni-codex\android-app\assets\book_covers\travel.png',
    ];
    final attachments = [
      for (var i = 0; i < 3; i++)
        ChatAttachment(
          kind: ChatAttachmentKind.image,
          path: paths[i],
          name: '图片${i + 1}.png',
          mimeType: 'image/png',
          sizeBytes: 100,
        ),
    ];
    await _pumpVisualCard(
      tester,
      ChangeNotifierProvider<AppRepository>.value(
        value: AppRepository(),
        child: RepaintBoundary(
          key: const ValueKey('ai-chat-three-images-capture'),
          child: DecoratedBox(
            decoration: AppColors.pageBackground(Brightness.light),
            child: SizedBox(
              width: 390,
              child: Padding(
                // Mirror the production history list's 16dp content inset. The
                // real image message deliberately bleeds back out to the full
                // chat viewport while text bubbles keep this inset.
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: buildAiChatUserMessageForTesting(
                  text: '请看看这三张图片',
                  attachments: attachments,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _settleFileImages(tester);
    final tiles = find.byType(Image);
    expect(tiles, findsNWidgets(3));
    final rects = [for (var i = 0; i < 3; i++) tester.getRect(tiles.at(i))];
    // Image messages fill the chat content area, retaining the reference
    // screen's 16dp side inset and only the intentional 6px inter-image gaps.
    expect(rects.first.left, closeTo(16, 0.5));
    expect(rects.last.right, closeTo(374, 0.5));
    expect(rects.first.width, greaterThan(100));
    expect(rects.first.height, closeTo(rects.first.width, 0.5));
    expect(rects[0].top, closeTo(rects[1].top, 0.1));
    expect(rects[1].top, closeTo(rects[2].top, 0.1));
    expect(rects[0].right, lessThanOrEqualTo(rects[2].right));
    expect(rects[1].left, greaterThan(rects[0].left));
    expect(rects[2].left, greaterThan(rects[1].left));
    await _captureIfRequested(
      tester,
      find.byKey(const ValueKey('ai-chat-three-images-capture')),
      'ai_chat_three_images.png',
    );
  });

  testWidgets('选中图片先进入扩大的输入框且首屏只完整展示三张', (tester) async {
    const paths = [
      r'C:\src\xunni-codex\android-app\assets\book_covers\dining.png',
      r'C:\src\xunni-codex\android-app\assets\book_covers\shopping.png',
      r'C:\src\xunni-codex\android-app\assets\book_covers\travel.png',
      r'C:\src\xunni-codex\android-app\assets\book_covers\pet.png',
    ];
    final attachments = [
      for (var i = 0; i < 4; i++)
        ChatAttachment(
          kind: ChatAttachmentKind.image,
          path: paths[i],
          name: '待发送图片${i + 1}.png',
          mimeType: 'image/png',
          sizeBytes: 100,
        ),
    ];
    final repo = AppRepository();
    await _pumpFullScreenChat(
      tester,
      repo,
      initialDraftAttachments: attachments,
    );
    await _settleFileImages(tester);

    final strip = find.byKey(
      const ValueKey('ai-chat-attachment-draft-strip'),
    );
    expect(strip, findsOneWidget);
    final stripRect = tester.getRect(strip);
    final firstThree = [
      for (var i = 0; i < 3; i++)
        tester.getRect(
          find.byKey(ValueKey('ai-chat-draft-attachment-$i')),
        ),
    ];
    expect(firstThree[0].left, closeTo(stripRect.left, 0.1));
    expect(firstThree[2].right, closeTo(stripRect.right, 0.1));
    expect(firstThree[0].width, closeTo(firstThree[1].width, 0.1));
    expect(firstThree[1].width, closeTo(firstThree[2].width, 0.1));
    expect(
      find.byKey(const ValueKey('ai-chat-draft-attachment-3')).hitTestable(),
      findsNothing,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('ai-chat-input-shell'))).height,
      greaterThan(180),
    );
    expect(find.byKey(const ValueKey('ai-chat-input-field')), findsOneWidget);

    await _captureIfRequested(
      tester,
      find.byKey(const ValueKey('ai-chat-add-sheet-fullscreen-capture')),
      'ai_chat_draft_four_images.png',
    );
  });

  testWidgets('回答中的 Markdown 表格使用对齐列，并提供 GPT 风格操作栏', (tester) async {
    await _pumpVisualCard(
      tester,
      SizedBox(
        width: 358,
        child: buildAiChatAnswerForTesting(
          text: '| 指数 | 收盘 | 涨跌 |\n'
              '| --- | ---: | :---: |\n'
              '| 纳斯达克 | 25,980.19 | -0.76% |\n'
              '| 标普 500 | 7,652.86 | -0.28% |',
        ),
      ),
    );

    expect(
        find.byKey(const ValueKey('ai-chat-markdown-table')), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(
        find.byKey(const ValueKey('ai-chat-answer-actions')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '分享',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '更多',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('模型和思考强度只在选中时显示灰底', (tester) async {
    Future<void> pumpPills({
      required bool modelSelected,
      required bool effortSelected,
    }) async {
      await _pumpVisualCard(
        tester,
        buildClaudeInputPillsForTesting(
          modelSelected: modelSelected,
          effortSelected: effortSelected,
        ),
      );
    }

    await pumpPills(modelSelected: false, effortSelected: false);
    final model = tester.widget<Container>(
      find.byKey(const ValueKey('ai-chat-model-pill')),
    );
    final effort = tester.widget<Container>(
      find.byKey(const ValueKey('ai-chat-effort-pill')),
    );
    expect(model.decoration, isNull);
    expect(effort.decoration, isNull);
    expect(
        tester.widget<Text>(find.text('claude-sonnet-5')).style?.fontSize, 15);
    expect(tester.widget<Text>(find.text('Max')).style?.fontSize, 15);
    final modelRect = tester.getRect(
      find.byKey(const ValueKey('ai-chat-model-pill')),
    );
    final effortRect = tester.getRect(
      find.byKey(const ValueKey('ai-chat-effort-pill')),
    );
    expect(effortRect.left - modelRect.right, closeTo(4, 0.1));

    await pumpPills(modelSelected: true, effortSelected: true);
    final selectedModel = tester.widget<Container>(
      find.byKey(const ValueKey('ai-chat-model-pill')),
    );
    final selectedEffort = tester.widget<Container>(
      find.byKey(const ValueKey('ai-chat-effort-pill')),
    );
    expect(selectedModel.decoration, isA<BoxDecoration>());
    expect(selectedEffort.decoration, isA<BoxDecoration>());
  });

  testWidgets('长模型名完整缩放，并保留模型与思考强度的紧凑间距', (tester) async {
    const longModel = 'claude-sonnet-5-thinking-extended-202608';
    await _pumpVisualCard(
      tester,
      buildClaudeInputPillsForTesting(
        modelSelected: false,
        effortSelected: false,
        model: longModel,
        maxWidth: 220,
      ),
    );

    final modelRect = tester.getRect(
      find.byKey(const ValueKey('ai-chat-model-pill')),
    );
    final effortRect = tester.getRect(
      find.byKey(const ValueKey('ai-chat-effort-pill')),
    );
    expect(effortRect.left - modelRect.right, closeTo(4, 0.1));
    expect(find.byKey(const ValueKey('ai-chat-model-label')), findsOneWidget);
    expect(find.text(longModel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('喵助手加号使用 Claude Add to Chat 菜单并保留聊天工具', (tester) async {
    var webSearch = false;
    var toolAccess = AiChatToolAccess.auto;
    await _pumpVisualCard(
      tester,
      RepaintBoundary(
        key: const ValueKey('ai-chat-add-sheet-capture'),
        child: buildClaudeChatAddSheetForTesting(
          webSearchEnabled: webSearch,
          onAttachmentsPicked: (_) async {},
          onWebSearchChanged: (value) async => webSearch = value,
          toolAccess: toolAccess,
          onToolAccessChanged: (value) async => toolAccess = value,
        ),
      ),
    );

    expect(find.text('添加到聊天'), findsOneWidget);
    expect(find.text('相机'), findsOneWidget);
    expect(find.text('照片'), findsOneWidget);
    expect(find.text('添加文件'), findsOneWidget);
    expect(find.text('工具权限'), findsOneWidget);
    expect(find.text('联网搜索'), findsOneWidget);
    expect(find.text('支付截图识别'), findsNothing);
    expect(find.text('导入账单'), findsNothing);
    expect(find.text('导出账单'), findsNothing);
    expect(find.text('Add to project'), findsNothing);
    expect(find.text('Connectors'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('chat-web-search-switch')));
    await tester.pump();
    expect(webSearch, isTrue);

    await tester.tap(find.byKey(const ValueKey('chat-tool-access-row')));
    await tester.pump();
    expect(find.text('按需加载'), findsOneWidget);
    expect(find.text('始终可用'), findsOneWidget);
    await tester.tap(find.text('按需加载'));
    await tester.pump();
    expect(toolAccess, AiChatToolAccess.onDemand);

    // Golden 要按真实页面验收：输入区/聊天内容在底下，添加到聊天从底部
    // 上滑并覆盖在整屏上；单独截面板会把比例夸大，无法和实机截图比较。
    final repo = AppRepository();
    await _pumpFullScreenChat(tester, repo);
    await tester.tap(find.byKey(const ValueKey('ai-chat-plus-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('添加到聊天'), findsOneWidget);
    expect(
      tester
          .getRect(find.byKey(const ValueKey('chat-add-sheet-surface')))
          .width,
      closeTo(374, 0.1),
    );
    await _captureIfRequested(
      tester,
      find.byKey(const ValueKey('ai-chat-add-sheet-fullscreen-capture')),
      'ai_chat_add_sheet.png',
    );
  });

  testWidgets('加号首屏默认显示近期图片并支持横向滑动', (tester) async {
    final recent = <ChatRecentPhoto>[
      for (var i = 0; i < 6; i++)
        ChatRecentPhoto(
          id: 'recent-$i',
          // The production widget still creates Image.memory for these
          // thumbnails; an empty payload is enough for this layout test and
          // intentionally exercises its visual error fallback.
          thumbnail: Uint8List(0),
          loadPath: () async => 'recent-$i.jpg',
        ),
    ];
    await _pumpVisualCard(
      tester,
      RepaintBoundary(
        key: const ValueKey('ai-chat-add-sheet-recent-capture'),
        child: buildClaudeChatAddSheetForTesting(
          onAttachmentsPicked: (_) async {},
          recentPhotos: Future.value(recent),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('照片'), findsNothing);
    expect(find.byKey(const ValueKey('chat-recent-photo-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-recent-photo-1')), findsOneWidget);
    final camera = tester.getRect(find.text('相机'));
    expect(camera.width, lessThan(94));
    final firstPhoto = tester.getRect(
      find.byKey(const ValueKey('chat-recent-photo-0')),
    );
    expect(firstPhoto.width, closeTo(94, 0.1));
    expect(firstPhoto.height, closeTo(94, 0.1));

    // The rail is a real horizontal ListView, not a clipped static row.
    await tester.drag(find.byKey(const ValueKey('chat-recent-photo-0')),
        const Offset(-140, 0));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await _captureIfRequested(
      tester,
      find.byKey(const ValueKey('ai-chat-add-sheet-recent-capture')),
      'ai_chat_add_sheet_recent.png',
    );
  });
}

Future<void> _pumpFullScreenChat(
  WidgetTester tester,
  AppRepository repo, {
  List<ChatAttachment> initialDraftAttachments = const [],
}) async {
  tester.binding.platformDispatcher.textScaleFactorTestValue = 1.0;
  await tester.binding.setSurfaceSize(const Size(390, 844));

  final baseTheme = AppTheme.light();
  final withCjkFallback =
      Platform.environment['UPDATE_CLAUDE_POPUP_SCREENSHOTS'] == '1';
  await tester.pumpWidget(
    ChangeNotifierProvider<AppRepository>.value(
      value: repo,
      child: MaterialApp(
        theme: baseTheme.copyWith(
          textTheme: baseTheme.textTheme.apply(
            fontFamily: 'Nunito',
            fontFamilyFallback:
                withCjkFallback ? const [screenshotCjkFontFamily] : null,
          ),
          primaryTextTheme: baseTheme.primaryTextTheme.apply(
            fontFamily: 'Nunito',
            fontFamilyFallback:
                withCjkFallback ? const [screenshotCjkFontFamily] : null,
          ),
        ),
        builder: (context, child) => RepaintBoundary(
          key: const ValueKey('ai-chat-add-sheet-fullscreen-capture'),
          child: child ?? const SizedBox.shrink(),
        ),
        home: AiChatPanel(
          fullScreen: true,
          recordOnly: false,
          initialDraftAttachments: initialDraftAttachments,
          onSwitchToManual: () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpVisualCard(WidgetTester tester, Widget card) async {
  tester.binding.platformDispatcher.textScaleFactorTestValue = 1.0;
  await tester.binding.setSurfaceSize(const Size(390, 844));

  final baseTheme = AppTheme.light();
  final withCjkFallback =
      Platform.environment['UPDATE_CLAUDE_POPUP_SCREENSHOTS'] == '1';
  await tester.pumpWidget(
    MaterialApp(
      theme: baseTheme.copyWith(
        textTheme: baseTheme.textTheme.apply(
          fontFamily: 'Nunito',
          fontFamilyFallback:
              withCjkFallback ? const [screenshotCjkFontFamily] : null,
        ),
        primaryTextTheme: baseTheme.primaryTextTheme.apply(
          fontFamily: 'Nunito',
          fontFamilyFallback:
              withCjkFallback ? const [screenshotCjkFontFamily] : null,
        ),
      ),
      home: Scaffold(
        body: Center(child: card),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _captureIfRequested(
  WidgetTester tester,
  Finder boundaryFinder,
  String fileName,
) async {
  if (Platform.environment['UPDATE_CLAUDE_POPUP_SCREENSHOTS'] != '1') return;
  final output = Directory(
    r'C:\src\xunni-codex\android-app\outputs\ai_chat_claude',
  );
  output.createSync(recursive: true);
  await expectLater(
    boundaryFinder,
    matchesGoldenFile('../outputs/ai_chat_claude/$fileName'),
  );
}

Future<void> _settleFileImages(WidgetTester tester) async {
  // Image.file decoding uses real asynchronous I/O. Let that work finish,
  // then pump the frame that paints the decoded image. Awaiting precacheImage
  // inside runAsync would deadlock because precache completion itself needs a
  // subsequent Flutter frame.
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    final rawImages = tester.widgetList<RawImage>(find.byType(RawImage));
    if (rawImages.isNotEmpty &&
        rawImages.every((image) => image.image != null)) {
      return;
    }
  }
  throw TestFailure('Image.file did not decode before the screenshot deadline');
}
