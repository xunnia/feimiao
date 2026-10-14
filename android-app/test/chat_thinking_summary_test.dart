import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/views/home/chat_thinking_summary.dart';

void main() {
  const key = ValueKey('thinking-capture');
  Future<void> pump(WidgetTester tester,
      {bool completed = false,
      String summary = '',
      bool reduceMotion = false}) async {
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: Scaffold(
                body: RepaintBoundary(
                    key: key,
                    child: ChatThinkingSummary(
                        completed: completed,
                        summary: summary,
                        label: completed ? 'Processed' : 'Thinking',
                        style: const TextStyle(
                            fontSize: 15, color: Color(0xFF666666))))))));
  }

  Future<String> pixels(WidgetTester tester) async {
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
    return (await tester.runAsync(() async {
      final image = await boundary.toImage();
      try {
        final bytes =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        return sha256
            .convert(bytes.buffer
                .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes))
            .toString();
      } finally {
        image.dispose();
      }
    }))!;
  }

  testWidgets('等待文字真的有像素动效，减弱动态时保持静止', (tester) async {
    await pump(tester);
    await tester.pump(const Duration(milliseconds: 100));
    final first = await pixels(tester);
    await tester.pump(const Duration(milliseconds: 700));
    expect(await pixels(tester), isNot(first));
    await pump(tester, reduceMotion: true);
    await tester.pump();
    final still = await pixels(tester);
    await tester.pump(const Duration(milliseconds: 700));
    expect(await pixels(tester), still);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('摘要增量刷新保留展开状态，完成自动折叠，无摘要不能假展开', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Thinking'));
    expect(
        find.byKey(const ValueKey('ai-chat-thinking-details')), findsNothing);
    await pump(tester, summary: '**First**\n\nParagraph');
    await tester.tap(find.text('Thinking'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(
        find.textContaining('Paragraph', findRichText: true), findsOneWidget);
    await pump(tester, summary: '**First**\n\nParagraph\n\nMore');
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('More', findRichText: true), findsOneWidget);
    await pump(tester,
        completed: true, summary: '**First**\n\nParagraph\n\nMore');
    await tester.pump(const Duration(milliseconds: 250));
    expect(
        find.byKey(const ValueKey('ai-chat-thinking-details')), findsNothing);
    await tester.tap(find.text('Processed'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('More', findRichText: true), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
