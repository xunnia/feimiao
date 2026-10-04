import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/core/ai/chat_answer_metadata.dart';
import 'package:qingji/core/media/chat_attachment.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/views/home/ai_chat_panel.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _LocalRepository extends AppRepository {
  late AiProviderConfig config;
  @override
  AiProviderConfig aiProviderConfigForChatSession(String? sessionId) => config;
  @override
  AiProviderConfig aiProviderConfigFor(AiTaskType task) => config;
  @override
  bool aiPrivacyAcceptedFor(AiProviderConfig config) => true;
}

class _RealHttp extends HttpOverrides {}

void main() {
  late Directory temp;
  late _LocalRepository repo;
  late HttpServer server;
  late String sessionId;
  final bodies = <Map<String, dynamic>>[];
  Completer<void>? responseGate;
  var interrupted = false;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    resetChatHistoryForTesting();
    bodies.clear();
    responseGate = null;
    interrupted = false;
    temp = await Directory.systemTemp.createTemp('feimiao_chat_stream_');
    await databaseFactory.setDatabasesPath(temp.path);
    repo = _LocalRepository();
    await repo.init();
    sessionId = (await repo.createChatSession()).id;
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
      bodies.add(jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>);
      request.response.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');
      request.response.bufferOutput = false;
      request.response.write('data: ${jsonEncode({
            'type': 'response.reasoning_summary_text.delta',
            'delta': '公开的简短处理摘要',
          })}\n\n');
      request.response.write('data: ${jsonEncode({
            'type': 'response.output_text.delta',
            'delta': '已收到的回答',
          })}\n\n');
      await request.response.flush();
      await responseGate?.future;
      request.response.write('data: ${jsonEncode(interrupted ? {
          'type': 'response.failed',
          'response': {
            'error': {'message': 'local interruption'}
          }
        } : {
          'type': 'response.completed',
          'response': {'output_text': '已收到的回答'}
        })}\n\n');
      await request.response.close();
    });
  });
  tearDown(() async {
    if (responseGate != null && !responseGate!.isCompleted) {
      responseGate!.complete();
    }
    await server.close(force: true);
    await repo.closeForTest();
    await temp.delete(recursive: true);
    resetChatHistoryForTesting();
  });

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(ChangeNotifierProvider<AppRepository>.value(
      value: repo,
      child: MaterialApp(
          home: Scaffold(
              body: AiChatPanel(
        sessionId: sessionId,
        fullScreen: true,
        recordOnly: false,
        onSwitchToManual: () {},
      ))),
    ));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> waitFor(
      WidgetTester tester, FutureOr<bool> Function() ready) async {
    for (var i = 0; i < 200; i++) {
      final done = await tester.runAsync(() async => await ready());
      if (done == true) return;
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)));
      await tester.pump(const Duration(milliseconds: 15));
    }
    fail('本地聊天流程未在预期时间完成');
  }

  Future<List<Map<String, Object?>>> answers() async =>
      (await repo.loadChatSessionMessages(sessionId))
          .where((row) => row['role'] == 'answer')
          .toList();

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(
        find.byKey(const ValueKey('ai-chat-input-field')), text);
    await waitFor(tester, () {
      final taps = tester.widgetList<GestureDetector>(find.descendant(
          of: find.byKey(const ValueKey('ai-chat-send-button')),
          matching: find.byType(GestureDetector)));
      return taps.any((tap) => tap.onTap != null);
    });
    final field = tester
        .widget<TextField>(find.byKey(const ValueKey('ai-chat-input-field')));
    await tester.runAsync(() async {
      field.onSubmitted!(text);
    });
    await tester.pump();
  }

  Future<void> closePanel(WidgetTester tester) async {
    await waitFor(
        tester,
        () => !aiChatHasActiveFlowForTesting(
            tester.state(find.byType(AiChatPanel))));
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('断流保留正文及摘要，关闭重开后恢复中断状态', (tester) async {
    await HttpOverrides.runZoned(() async {
      interrupted = true;
      await pumpPanel(tester);
      await send(tester, '你好');
      await waitFor(tester, () async => (await answers()).isNotEmpty);
      final row = (await tester.runAsync(answers))!.single;
      expect(row['text'], '已收到的回答');
      final metadata = ChatAnswerMetadata.decode(row['attachments_json']);
      expect(metadata.interrupted, isTrue);
      expect(metadata.thinking.toString(), contains('公开的简短处理摘要'));
      await closePanel(tester);
      resetChatHistoryForTesting();
      await pumpPanel(tester);
      await waitFor(
          tester,
          () => find
              .textContaining('已收到的回答')
              .hitTestable()
              .evaluate()
              .isNotEmpty);
      expect(find.textContaining('已收到的回答'), findsWidgets);
      expect(find.text('回复已中断'), findsOneWidget);
      expect(find.byTooltip('重新生成'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('ai-chat-continue-answer')), findsNothing);
      await closePanel(tester);
    }, createHttpClient: _RealHttp().createHttpClient);
  });

  testWidgets('图片回答重试携带原图片，追问仍保留图片上下文', (tester) async {
    await tester.runAsync(() async {
      final file = File('${temp.path}/image.png');
      await file.writeAsBytes(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aFukAAAAASUVORK5CYII='));
      final image = ChatAttachment(
          kind: ChatAttachmentKind.image,
          path: file.path,
          name: 'image.png',
          mimeType: 'image/png',
          sizeBytes: await file.length());
      await repo.addChatSessionMessage(
          sessionId: sessionId,
          role: 'user',
          attachmentsJson: ChatAttachment.encodeList([image]));
      await repo.addChatSessionMessage(
          sessionId: sessionId,
          role: 'answer',
          text: '旧失败回复',
          question: '请查看我发送的附件并直接回答。');
    });
    await HttpOverrides.runZoned(() async {
      await pumpPanel(tester);
      await waitFor(tester,
          () => find.byTooltip('重新生成').hitTestable().evaluate().isNotEmpty);
      await tester.runAsync(() => tester.tap(find.byTooltip('重新生成').last));
      await waitFor(tester,
          () async => (await answers()).any((row) => row['text'] == '已收到的回答'));
      expect(jsonEncode(bodies.single['input']),
          contains('data:image/png;base64,'));
      expect(await tester.runAsync(answers), hasLength(1));
      await send(tester, '这张图还有什么细节？');
      await waitFor(tester, () async => (await answers()).length == 2);
      expect(bodies, hasLength(2));
      expect(
          jsonEncode(bodies.last['input']), contains('data:image/png;base64,'));
      expect(jsonEncode(bodies.last['input']), isNot(contains('旧失败回复')));
      await closePanel(tester);
    }, createHttpClient: _RealHttp().createHttpClient);
  });

  testWidgets('生成中离开页面，迟到完成保留正文而不是永久生成中', (tester) async {
    await HttpOverrides.runZoned(() async {
      responseGate = Completer<void>();
      await pumpPanel(tester);
      await send(tester, '你好');
      await waitFor(
          tester,
          () => find
              .textContaining('已收到的回答', findRichText: true)
              .evaluate()
              .isNotEmpty);
      final state = tester.state(find.byType(AiChatPanel));
      await tester.pumpWidget(const SizedBox.shrink());
      responseGate!.complete();
      await waitFor(tester, () => !aiChatHasActiveFlowForTesting(state));
      expect((await tester.runAsync(answers))!.single['text'], '已收到的回答');
      await pumpPanel(tester);
      await waitFor(tester,
          () => find.byTooltip('重新生成').hitTestable().evaluate().isNotEmpty);
      expect(find.text('回复已中断'), findsNothing);
      await closePanel(tester);
    }, createHttpClient: _RealHttp().createHttpClient);
  });

  testWidgets('清空当前会话后已启动的流不能写回，发送按钮恢复可用', (tester) async {
    await HttpOverrides.runZoned(() async {
      responseGate = Completer<void>();
      await pumpPanel(tester);
      await send(tester, '你好');
      await waitFor(tester, () => bodies.isNotEmpty);
      await tester.runAsync(() => repo.clearChatSessionMessages(sessionId));
      await tester.pump();
      responseGate!.complete();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      expect(
          await tester.runAsync(() => repo.loadChatSessionMessages(sessionId)),
          isEmpty);
      responseGate = null;
      await send(tester, '再试一次');
      await waitFor(tester, () async => (await answers()).length == 1);
      expect(bodies, hasLength(2));
      await closePanel(tester);
    }, createHttpClient: _RealHttp().createHttpClient);
  });

  testWidgets('重开后相同文字创建新运行，不复用上次完成的请求', (tester) async {
    await HttpOverrides.runZoned(() async {
      await pumpPanel(tester);
      await send(tester, '你好');
      await waitFor(tester, () async => (await answers()).length == 1);
      await closePanel(tester);
      resetChatHistoryForTesting();
      await pumpPanel(tester);
      await send(tester, '你好');
      await waitFor(tester, () async => (await answers()).length == 2);
      final runs =
          (await tester.runAsync(() => repo.loadAiRuns(sessionId: sessionId)))!;
      expect(runs, hasLength(2));
      expect(runs.map((run) => run.idempotencyKey).toSet(), hasLength(2));
      await closePanel(tester);
    }, createHttpClient: _RealHttp().createHttpClient);
  });

  testWidgets('长会话懒构建并定位最新，用户阅读历史时完成回复不抢滚动', (tester) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 60; i++) {
        await repo.addChatSessionMessage(
            sessionId: sessionId, role: 'user', text: '历史消息 $i，需要保留阅读位置');
      }
    });
    await HttpOverrides.runZoned(() async {
      await pumpPanel(tester);
      await waitFor(
          tester,
          () => find
              .text('历史消息 59，需要保留阅读位置')
              .hitTestable()
              .evaluate()
              .isNotEmpty);
      final listFinder = find.byType(ListView).first;
      expect(tester.widget<ListView>(listFinder).childrenDelegate,
          isA<SliverChildBuilderDelegate>());
      expect(find.text('历史消息 0，需要保留阅读位置'), findsNothing);
      responseGate = Completer<void>();
      await send(tester, '你好');
      await waitFor(tester, () => bodies.isNotEmpty);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.drag(listFinder, const Offset(0, 360));
      await tester.pump(const Duration(milliseconds: 500));
      final scrollable = tester.state<ScrollableState>(find
          .descendant(of: listFinder, matching: find.byType(Scrollable))
          .first);
      final position = scrollable.position;
      expect(position.extentAfter, greaterThan(48));
      final offset = position.pixels;
      responseGate!.complete();
      await waitFor(tester, () async => (await answers()).isNotEmpty);
      await waitFor(
          tester,
          () => !aiChatHasActiveFlowForTesting(
              tester.state(find.byType(AiChatPanel))));
      await tester.pump(const Duration(milliseconds: 500));
      expect(position.pixels, closeTo(offset, 1));
      await closePanel(tester);
    }, createHttpClient: _RealHttp().createHttpClient);
  });
}
