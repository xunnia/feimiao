import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/core/ai/llm_query_v2.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/views/home/chat_markdown_body.dart';
import 'package:qingji/views/home/chat_smooth_stream.dart';

class _LocalHttp extends HttpOverrides {}

void main() {
  test('computeSmoothRevealStep adapts to backlog and scales cleanly from 60Hz to 120Hz', () {
    // Small backlog glides gently (never 0, never huge).
    final small60 = computeSmoothRevealStep(pendingChars: 5, dtSeconds: 1 / 60);
    expect(small60, inInclusiveRange(1, 3));

    // Large burst (e.g. 200 chars arriving in one SSE packet) drains smoothly
    // with rate cap; at 120Hz (8.3ms) each frame takes ~half the step of 60Hz
    // so motion is twice as granular with identical physical speed.
    final burst60 = computeSmoothRevealStep(pendingChars: 200, dtSeconds: 1 / 60);
    final burst120 = computeSmoothRevealStep(pendingChars: 200, dtSeconds: 1 / 120);
    expect(burst60, inInclusiveRange(14, 28));
    expect(burst120, inInclusiveRange(7, 15));
    expect(burst120, lessThan(burst60));

    expect(computeSmoothRevealStep(pendingChars: 0, dtSeconds: 1 / 120), 0);
  });

  testWidgets('SmoothStreamTextController reveals bursty chunks progressively at 120Hz',
      (tester) async {
    late SmoothStreamTextController controller;
    final snapshots = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: _StreamHarness(
          onCreated: (c) {
            controller = c;
            c.addListener(() => snapshots.add(c.visibleText));
          },
        ),
      ),
    );

    const burstText = '这是一大段从上游网关一次性吐出的流式回复内容，包含表情😀和**加粗文字**，需要平滑逐帧展开而不是整块跳出来。';
    controller.update(burstText, streaming: true);

    // After 1 frame at 120Hz (~8.3ms), only a small progressive prefix should be shown.
    await tester.pump(const Duration(milliseconds: 8));
    expect(controller.visibleText.length, greaterThan(0));
    expect(controller.visibleText.length, lessThan(burstText.length));
    expect(controller.isCatchingUp, isTrue);

    // After ~640ms (80 frames at 120Hz), the entire 55-char burst should finish
    // smoothly with fine per-frame steps.
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(controller.visibleText, burstText);
    expect(controller.isCatchingUp, isFalse);
    // Many fine-grained intermediate frames were emitted (not block jumps).
    expect(snapshots.length, greaterThanOrEqualTo(12));

    // No broken UTF-16 surrogate pairs in any intermediate snapshot.
    for (final s in snapshots) {
      if (s.isNotEmpty) {
        final last = s.codeUnitAt(s.length - 1);
        expect(last >= 0xD800 && last <= 0xDBFF, isFalse);
      }
    }

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('SmoothStreamTextController respects reduceMotion and snaps immediately',
      (tester) async {
    late SmoothStreamTextController controller;

    await tester.pumpWidget(
      MaterialApp(
        home: _StreamHarness(
          onCreated: (c) => controller = c,
        ),
      ),
    );
    controller.setReduceMotion(true);
    const burstText = '开启减弱动态后，流式大块文本应立刻完整显示而不播放逐帧动画。';
    controller.update(burstText, streaming: true);
    expect(controller.visibleText, burstText);
    expect(controller.isCatchingUp, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ChatMarkdownBody uses lightweight Text during streaming and SelectableText once done',
      (tester) async {
    const body = '第一段已完成。\n\n```dart\nfinal a = 1;\n\nfinal b = 2;\n```\n\n最后一段仍在流式输出';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: ChatMarkdownBody(
            text: body,
            style: TextStyle(fontSize: 15.5),
            streaming: true,
          ),
        ),
      ),
    );
    await tester.pump();
    // Streaming prose renders with lightweight Text.rich (no heavy SelectableText
    // except inside code block), and fenced code block stays intact across blank line.
    expect(find.textContaining('第一段已完成', findRichText: true), findsOneWidget);
    expect(find.textContaining('最后一段仍在流式输出', findRichText: true), findsOneWidget);
    // Prose paragraphs are not wrapped in SelectableText while streaming.
    final streamingSelectables = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((w) => w.textSpan?.toPlainText() ?? w.data ?? '')
        .toList();
    expect(streamingSelectables.any((t) => t.contains('第一段已完成')), isFalse);

    // Once streaming completes, full SelectableText selection returns.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: ChatMarkdownBody(
            text: body,
            style: TextStyle(fontSize: 15.5),
            streaming: false,
          ),
        ),
      ),
    );
    await tester.pump();
    final settledSelectables = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((w) => w.textSpan?.toPlainText() ?? w.data ?? '')
        .toList();
    expect(settledSelectables.any((t) => t.contains('第一段已完成')), isTrue);
    expect(settledSelectables.any((t) => t.contains('最后一段仍在流式输出')), isTrue);
  });

  test('OpenAI/DeepSeek SSE forwards reasoning_content and accepts data: without space',
      () async {
    await HttpOverrides.runZoned(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await utf8.decoder.bind(request).join();
        request.response.headers.contentType =
            ContentType('text', 'event-stream', charset: 'utf-8');
        request.response.bufferOutput = false;
        // Both `data:` without space and DeepSeek `reasoning_content` delta.
        request.response.write(
          'data:${jsonEncode({'choices': [{'delta': {'reasoning_content': '先核对数据'}}]})}\n\n',
        );
        request.response.write(
          'data: ${jsonEncode({'choices': [{'delta': {'content': '你好'}}]})}\n\n',
        );
        request.response.write(
          'data:${jsonEncode({'choices': [{'delta': {'content': '世界'}}]})}\n\n',
        );
        request.response.write('data:[DONE]\n\n');
        await request.response.close();
      });

      final chunks = <String>[];
      final reasoning = <String>[];
      final done = Completer<String>();
      final config = AiProviderConfig(
        type: AiProviderType.deepseek,
        apiKey: 'local-test-only',
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        model: 'deepseek-chat',
        endpointType: AiEndpointType.chatCompletions,
        webSearchEnabled: false,
      );

      await LlmQueryV2.askStream(
        question: 'hi',
        config: config,
        transactionsText: '',
        onChunk: chunks.add,
        onReasoningSummary: reasoning.add,
        onDone: done.complete,
        onError: done.completeError,
      );

      expect(await done.future, '你好世界');
      expect(chunks, ['你好', '世界']);
      expect(reasoning, ['先核对数据']);
    }, createHttpClient: _LocalHttp().createHttpClient);
  });
}

class _StreamHarness extends StatefulWidget {
  final ValueChanged<SmoothStreamTextController> onCreated;
  const _StreamHarness({required this.onCreated});

  @override
  State<_StreamHarness> createState() => _StreamHarnessState();
}

class _StreamHarnessState extends State<_StreamHarness>
    with SingleTickerProviderStateMixin {
  late final SmoothStreamTextController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SmoothStreamTextController(vsync: this);
    widget.onCreated(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
