import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/core/ai/llm_query_v2.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/views/home/ai_chat_panel.dart';
import 'package:qingji/views/home/chat_markdown_body.dart';
import 'package:qingji/views/home/chat_smooth_stream.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _LocalHttp extends HttpOverrides {}

void main() {
  test('computeSmoothRevealStep adapts to backlog and scales cleanly from 60Hz to 120Hz', () {
    // Small backlog glides gently (never 0, never huge).
    final small60 = computeSmoothRevealStep(pendingChars: 5, dtSeconds: 1 / 60);
    expect(small60, inInclusiveRange(1, 3));

    // Large burst (e.g. 200 chars arriving in one SSE packet) stays capped at
    // fluid word-by-word velocity (max 220 chars/sec -> ~1-2 chars per 120Hz
    // frame, ~3-4 chars per 60Hz frame) instead of dumping whole blocks.
    final burst60 = computeSmoothRevealStep(pendingChars: 200, dtSeconds: 1 / 60);
    final burst120 = computeSmoothRevealStep(pendingChars: 200, dtSeconds: 1 / 120);
    expect(burst60, inInclusiveRange(2, 5));
    expect(burst120, inInclusiveRange(1, 3));
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

    // After 1 frame at 120Hz (~8.3ms), only 1–2 chars should appear (not a whole block).
    await tester.pump(const Duration(milliseconds: 8));
    expect(controller.visibleText.length, inInclusiveRange(1, 4));
    expect(controller.isCatchingUp, isTrue);

    // After ~1.1s (140 frames at 120Hz), the entire 55-char burst finishes smoothly.
    for (var i = 0; i < 140; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(controller.visibleText, burstText);
    expect(controller.isCatchingUp, isFalse);
    // Many fine-grained intermediate frames were emitted (not block jumps).
    expect(snapshots.length, greaterThanOrEqualTo(25));

    // Smooth finish drains buffered tail smoothly when stream ends instead of hard-snapping.
    const nextChunk = '$burstText这是最后一口气刷出来的收尾段落，结束后依然平滑吐完不瞬间跳出来。';
    controller.update(nextChunk, streaming: true);
    await tester.pump(const Duration(milliseconds: 8));
    var drainCompleted = false;
    controller.update(
      nextChunk,
      streaming: false,
      smoothFinish: true,
      onDrainComplete: () => drainCompleted = true,
    );
    expect(controller.isFinishing, isTrue);
    expect(drainCompleted, isFalse);
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(controller.visibleText, nextChunk);
    expect(drainCompleted, isTrue);

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
    // Streaming prose AND code block render with lightweight Text.rich (0
    // SelectableText while streaming), and fenced code block stays intact.
    expect(find.textContaining('第一段已完成', findRichText: true), findsOneWidget);
    expect(find.textContaining('最后一段仍在流式输出', findRichText: true), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);

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

  testWidgets('长对话上滑阅读历史时显示「回到底部」悬浮按钮，点击平滑回底并隐藏',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    resetChatHistoryForTesting();
    late Directory temp;
    final repo = AppRepository();
    late String sessionId;
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('fm_jump_bottom_');
      await databaseFactory.setDatabasesPath(temp.path);
      await repo.init();
      final session = await repo.createChatSession(title: '长对话');
      sessionId = session.id;
      await repo.addChatSessionMessage(
        sessionId: sessionId,
        role: 'user',
        text: '请写一段长回答',
      );
      await repo.addChatSessionMessage(
        sessionId: sessionId,
        role: 'answer',
        question: '请写一段长回答',
        text: List.generate(
          24,
          (i) => '${i + 1}. 这是第 ${i + 1} 段较长的回复内容，用于验证上滑查看历史时出现回到底部按钮。',
        ).join('\n\n'),
      );
    });
    addTearDown(() async {
      resetChatHistoryForTesting();
      await repo.closeForTest();
      await temp.delete(recursive: true);
      repo.dispose();
    });

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: AiChatPanel(
            sessionId: sessionId,
            fullScreen: true,
            recordOnly: false,
            onSwitchToManual: () {},
          ),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }

    final jumpFinder = find.byKey(const ValueKey('ai-chat-scroll-to-bottom'));
    AnimatedOpacity opacityWidget() => tester.widget<AnimatedOpacity>(
          find.ancestor(of: jumpFinder, matching: find.byType(AnimatedOpacity)).first,
        );

    // Initially anchored at the bottom -> button stays hidden.
    expect(opacityWidget().opacity, 0);

    // Scroll up toward the top to read history -> button fades in.
    final listView = find.byType(ListView).first;
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: listView, matching: find.byType(Scrollable)).first,
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(300));
    scrollable.position.jumpTo(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(opacityWidget().opacity, 1);

    // Tap "回到底部" -> smoothly scrolls back to maxScrollExtent and hides again.
    await tester.tap(jumpFinder);
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
    expect(
      scrollable.position.pixels,
      closeTo(scrollable.position.maxScrollExtent, 2.0),
    );
    expect(opacityWidget().opacity, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  });

  testWidgets('流式长回复自动顺滑跟随到底部，不用用户手动下滑；上滑阅读后立即停止抢滚',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    resetChatHistoryForTesting();
    late Directory temp;
    final repo = _StreamTestRepository();
    late String sessionId;
    late HttpServer server;
    final holdEnd = Completer<void>();
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('fm_stream_follow_');
      await databaseFactory.setDatabasesPath(temp.path);
      await repo.init();
      sessionId = (await repo.createChatSession(title: '自动跟随')).id;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      repo.config = AiProviderConfig(
        type: AiProviderType.custom,
        apiKey: 'local-test-only',
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        model: 'gpt-test',
        endpointType: AiEndpointType.responses,
        webSearchEnabled: false,
      );
      server.listen((request) async {
        // Verify Accept-Encoding: identity is sent so proxies don't gzip-buffer SSE.
        expect(request.headers.value('accept-encoding'), 'identity');
        await utf8.decoder.bind(request).join();
        request.response.headers.contentType =
            ContentType('text', 'event-stream', charset: 'utf-8');
        request.response.bufferOutput = false;
        // Emit many long paragraphs so total height exceeds viewport (> 1500px).
        for (var i = 0; i < 18; i++) {
          final para = '${i + 1}. 这是流式生成的第 ${i + 1} 段较长内容，用来验证列表高度大幅增长时会自动跟随到底部，不需要用户手动下滑才能看到最新文字。\n\n';
          request.response.write('data: ${jsonEncode({
                'type': 'response.output_text.delta',
                'delta': para,
              })}\n\n');
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 12));
        }
        await holdEnd.future;
        request.response.write('data: ${jsonEncode({
              'type': 'response.completed',
              'response': {'output_text': ''},
            })}\n\n');
        await request.response.close();
      });
    });
    addTearDown(() async {
      if (!holdEnd.isCompleted) holdEnd.complete();
      await server.close(force: true);
      await repo.closeForTest();
      await temp.delete(recursive: true);
      repo.dispose();
      resetChatHistoryForTesting();
    });

    await tester.binding.setSurfaceSize(const Size(390, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppRepository>.value(
          value: repo,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: AiChatPanel(
              sessionId: sessionId,
              fullScreen: true,
              recordOnly: false,
              onSwitchToManual: () {},
            ),
          ),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }

      await tester.enterText(
        find.byKey(const ValueKey('ai-chat-input-field')),
        '详细讲讲今年怎么存钱',
      );
      await tester.pump();
      final field = tester
          .widget<TextField>(find.byKey(const ValueKey('ai-chat-input-field')));
      await tester.runAsync(() async => field.onSubmitted!('详细讲讲今年怎么存钱'));
      await tester.pump();

      // Let streaming chunks arrive and smooth reveal run for ~1.5s of frames.
      for (var i = 0; i < 120; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 6)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }

      final listFinder = find.byType(ListView).first;
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: listFinder, matching: find.byType(Scrollable)).first,
      );
      // Content grew well past 1 viewport AND auto-scroll kept us right at the bottom!
      expect(scrollable.position.maxScrollExtent, greaterThan(200));
      expect(scrollable.position.extentAfter, lessThan(40));

      // Now finish stream and let final tail drain cleanly.
      holdEnd.complete();
      for (var i = 0; i < 60; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(scrollable.position.extentAfter, lessThan(40));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }, createHttpClient: _LocalHttp().createHttpClient);
  });
}

class _StreamTestRepository extends AppRepository {
  late AiProviderConfig config;

  @override
  AiProviderConfig aiProviderConfigForChatSession(String? sessionId) => config;

  @override
  AiProviderConfig aiProviderConfigFor(AiTaskType task) => config;

  @override
  bool aiPrivacyAcceptedFor(AiProviderConfig config) => true;
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
