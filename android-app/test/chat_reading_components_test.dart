import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/media/chat_attachment.dart';
import 'package:qingji/core/ai/web_search.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/views/home/ai_chat_panel.dart';
import 'package:qingji/views/home/chat_attachment_preview.dart';
import 'package:qingji/views/home/chat_markdown_body.dart';
import 'package:qingji/views/home/chat_reading_viewport.dart';

import 'screenshot_font_support.dart';

void main() {
  setUpAll(() => loadScreenshotFonts(force: true));

  Future<void> pump(WidgetTester tester, String text, {double width = 320}) =>
      tester.pumpWidget(MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
              body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                      width: width,
                      child: ChatMarkdownBody(
                          text: text,
                          style: const TextStyle(
                              fontSize: 15.5,
                              fontFamily: 'Nunito',
                              fontFamilyFallback: ['NotoSansSC'])))))));

  List<TextSpan> spans(InlineSpan span) => [
        if (span is TextSpan) span,
        if (span is TextSpan)
          for (final child in span.children ?? []) ...spans(child),
      ];

  testWidgets('列表内的粗体和正文保持同一段，续行采用悬挂缩进', (tester) async {
    await pump(tester, '1. **上午散步**，沿着熟悉的路线走，不必为了完成计划而赶路。\n2. 午后休息');
    final paragraphs =
        tester.widgetList<SelectableText>(find.byType(SelectableText)).toList();
    expect(paragraphs, hasLength(2));
    expect(paragraphs.first.textSpan!.toPlainText(), startsWith('上午散步，沿着'));
    expect(
        spans(paragraphs.first.textSpan!).any(
            (s) => s.text == '上午散步' && s.style?.fontWeight == FontWeight.w600),
        isTrue);
    expect(tester.getTopLeft(find.byType(SelectableText).first).dx,
        greaterThan(tester.getTopLeft(find.text('1.')).dx + 16));
    expect(tester.takeException(), isNull);
  });

  testWidgets('嵌套列表、引用、实体和转义由标准解析器处理', (tester) async {
    await pump(tester, '- 第一项\n  - 子项\n\n> A & B\n\n\\*不是斜体\\*');
    final content = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((w) => w.textSpan!.toPlainText())
        .join('\n');
    expect(content, contains('子项'));
    expect(content, contains('A & B'));
    expect(content, contains('*不是斜体*'));
    expect(content, isNot(contains('&amp;')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('长表格保留自然列宽，可横向滑到最后一列', (tester) async {
    await pump(
        tester,
        '| 名称 | 说明 |\n| --- | --- |\n'
        '| 散步 | 一段很长的说明，不挤压列也不截断内容 |');
    final table = find.byKey(const ValueKey('ai-chat-markdown-table'));
    expect(tester.getSize(find.byType(Table)).width, greaterThan(320));
    await tester.drag(table, const Offset(-400, 0));
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(
        find.descendant(of: table, matching: find.byType(Scrollable)).first);
    expect(scroll.position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('链接可点击且只允许网页协议，文本保持可选择和换行', (tester) async {
    await pump(
        tester, '[网页链接](https://example.com) 和 [禁止](file:///private/data)');
    final paragraph =
        tester.widget<SelectableText>(find.byType(SelectableText));
    final values = spans(paragraph.textSpan!);
    expect(values.singleWhere((s) => s.text == '网页链接').recognizer,
        isA<TapGestureRecognizer>());
    expect(values.singleWhere((s) => s.text == '禁止').recognizer, isNull);
    expect(find.byType(WidgetSpan), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('模型返回的远程图片不会发起网络加载', (tester) async {
    await pump(tester, '![猫咪](https://example.com/private.png)');
    expect(find.byType(Image), findsNothing);
    final paragraph =
        tester.widget<SelectableText>(find.byType(SelectableText));
    expect(paragraph.textSpan!.toPlainText(), '猫咪');
  });

  testWidgets('代码保留原文、中文字体并能复制', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = call.arguments['text'];
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await pump(tester, '```text\n周六：散步\nprint(42)\n```');
    final code = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(code.textSpan!.toPlainText(), '周六：散步\nprint(42)');
    expect(
        spans(code.textSpan!).any(
            (s) => s.text == '周六：散步' && s.style?.fontFamily == 'NotoSansSC'),
        isTrue);
    await tester.tap(find.byTooltip('复制代码'));
    await tester.pump();
    expect(copied, '周六：散步\nprint(42)\n');
  });

  testWidgets('附件预览支持缩放，缺图显示明确反馈', (tester) async {
    final attachment = ChatAttachment(
        kind: ChatAttachmentKind.image,
        path: File('assets/book_covers/dining.png').absolute.path,
        name: '图片.png',
        mimeType: 'image/png',
        sizeBytes: 100);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ChatAttachmentPreview(attachment: attachment))));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('图片已缺失或无法读取'), findsNothing);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: ChatAttachmentPreview(
                attachment: ChatAttachment(
                    kind: ChatAttachmentKind.image,
                    path: 'missing-image.png',
                    name: 'missing.png',
                    mimeType: 'image/png',
                    sizeBytes: 100)))));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(find.text('图片已缺失或无法读取'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('来源操作栏在窄屏大字下完整换行，不增加继续生成', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: SizedBox(
                    width: 264,
                    child:
                        buildAiChatAnswerForTesting(text: '回答', sources: const [
                      AiWebSource(title: '一', url: 'https://example.com'),
                      AiWebSource(title: '二', url: 'https://example.org'),
                    ]))))));
    expect(find.text('继续生成'), findsNothing);
    expect(tester.getTopLeft(find.text('2 个来源')).dy,
        greaterThan(tester.getTopLeft(find.byTooltip('复制')).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('输入框高度变化只改变滚动留距，不重建输入或丢失焦点', (tester) async {
    final controller = TextEditingController(text: '未发送的草稿');
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    double height = 80;
    EdgeInsets? padding;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
      update = setState;
      return ChatReadingViewport(
          history: (p) {
            padding = p;
            return const SizedBox.expand();
          },
          header: const SizedBox(height: 56),
          topFade: const SizedBox.shrink(),
          composer: SizedBox(
              height: height,
              child: TextField(controller: controller, focusNode: focus)));
    }))));
    await tester.pump();
    expect(padding?.bottom, 88);
    focus.requestFocus();
    await tester.pump();
    final field = tester.state(find.byType(EditableText));
    update(() => height = 180);
    await tester.pump();
    await tester.pump();
    expect(padding?.bottom, 188);
    expect(identical(field, tester.state(find.byType(EditableText))), isTrue);
    expect(focus.hasFocus, isTrue);
    expect(controller.text, '未发送的草稿');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
