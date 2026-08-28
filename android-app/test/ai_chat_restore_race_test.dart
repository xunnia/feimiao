import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/budget/budget_window_resolver.dart';
import 'package:qingji/core/media/chat_attachment.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/views/home/ai_chat_panel.dart';

class _ChatRaceRepository extends AppRepository {
  static const _book = BookEntity(id: 1, name: '总账本');
  final Completer<void> loadStarted = Completer<void>();
  final Completer<void> releaseLoad = Completer<void>();
  final Completer<void> userInsertStarted = Completer<void>();
  final Completer<void> releaseUserInsert = Completer<void>();
  Completer<void>? nextLoadGate;
  final List<Map<String, Object?>> rows = <Map<String, Object?>>[
    {
      'id': 1,
      'role': 'user',
      'text': '旧消息',
      'question': '',
      'created_ms': 1,
    },
  ];
  final Map<int, ReportEntity> reportsById = <int, ReportEntity>{};
  int _nextId = 2;
  int _databaseGeneration = 0;
  int loadCalls = 0;
  int reportReloadCalls = 0;

  @override
  bool get isInitialized => true;

  @override
  int get databaseGeneration => _databaseGeneration;

  @override
  int get currentBookId => _book.id;

  @override
  int get defaultBookId => _book.id;

  @override
  BookEntity get currentBook => _book;

  @override
  List<BookEntity> get books => const [_book];

  @override
  BudgetWindowResult budgetForCalendarMonth(
    DateTime month, {
    int? bookId,
    DateTime? asOf,
    DateTime? knowledgeCutoff,
  }) =>
      super.budgetForCalendarMonth(
        month,
        bookId: bookId ?? _book.id,
        asOf: asOf,
        knowledgeCutoff: knowledgeCutoff,
      );

  @override
  Future<List<Map<String, Object?>>> loadChatMessages() async {
    loadCalls++;
    if (!loadStarted.isCompleted) loadStarted.complete();
    await releaseLoad.future;
    final gate = nextLoadGate;
    nextLoadGate = null;
    if (gate != null) await gate.future;
    return rows.map(Map<String, Object?>.of).toList(growable: false);
  }

  @override
  Future<ReportEntity?> getReport(int id) async => reportsById[id];

  @override
  Future<void> reloadReportsFromStorage() async {
    reportReloadCalls++;
  }

  void commitRestoredRows(List<Map<String, Object?>> restoredRows) {
    rows
      ..clear()
      ..addAll(restoredRows.map(Map<String, Object?>.of));
    _databaseGeneration++;
    notifyListeners();
  }

  @override
  Future<int> addChatMessage({
    required String role,
    String text = '',
    String question = '',
  }) async {
    final id = _nextId++;
    rows.add({
      'id': id,
      'role': role,
      'text': text,
      'question': question,
      'created_ms': id,
    });
    if (role == 'user') {
      if (!userInsertStarted.isCompleted) userInsertStarted.complete();
      await releaseUserInsert.future;
    }
    return id;
  }
}

class _ExplodingChatRepository extends AppRepository {
  bool explode = false;
  int _nextId = 1;

  @override
  bool get isInitialized => true;

  @override
  Future<List<Map<String, Object?>>> loadChatMessages() async => const [];

  @override
  Future<List<Map<String, Object?>>> loadChatSessionMessages(
    String sessionId,
  ) async =>
      const [];

  @override
  Future<int> addChatMessage({
    required String role,
    String text = '',
    String question = '',
  }) async =>
      _nextId++;

  @override
  AiProviderConfig aiProviderConfigForChatSession(String? sessionId) {
    return AiProviderConfig.deepSeek(apiKey: '');
  }

  @override
  AiProviderConfig aiProviderConfigFor(AiTaskType task) {
    if (explode) throw StateError('simulated provider resolution failure');
    return AiProviderConfig.deepSeek(apiKey: '');
  }
}

void main() {
  testWidgets('历史恢复与新消息入库交错时不会重复插入新消息', (tester) async {
    resetChatHistoryForTesting();
    final repo = _ChatRaceRepository();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          home: Scaffold(
            body: AiChatPanel(recordOnly: false, onSwitchToManual: () {}),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() => repo.loadStarted.future);

    final input = find.byKey(const ValueKey('ai-chat-input-field'));
    await tester.enterText(input, '我有没有 k12');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.runAsync(() => repo.userInsertStarted.future);

    repo.releaseLoad.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();

    expect(find.text('旧消息'), findsOneWidget);
    expect(find.text('我有没有 k12'), findsOneWidget);

    repo.releaseUserInsert.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    resetChatHistoryForTesting();
  });

  testWidgets('历史区只在同步定位到底部后显示首帧', (tester) async {
    resetChatHistoryForTesting();
    await tester.binding.setSurfaceSize(const Size(390, 620));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _ChatRaceRepository();
    repo.rows
      ..clear()
      ..addAll(List.generate(30, (index) {
        final content =
            index < 20 ? '短消息' : List.filled(10, '后段故意使用很长的聊天内容').join('，');
        return {
          'id': index + 1,
          'role': 'user',
          'text': '历史消息 $index：$content',
          'question': '',
          'created_ms': index + 1,
        };
      }));

    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          home: AiChatPanel(
            fullScreen: true,
            recordOnly: false,
            onSwitchToManual: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => repo.loadStarted.future);

    Opacity viewport() => tester.widget<Opacity>(
          find.byKey(const ValueKey('ai-chat-history-viewport')),
        );
    expect(viewport().opacity, 0);

    repo.releaseLoad.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();

    final list = tester.widget<ListView>(find.byType(ListView));
    final position = list.controller!.position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(position.pixels, position.maxScrollExtent);
    expect(
      viewport().opacity,
      0,
      reason: '定位回调完成的这一帧仍不能把错误位置画出来',
    );

    var revealPass = -1;
    for (var pass = 0; pass < 10; pass++) {
      await tester.pump();
      if (viewport().opacity == 1) {
        revealPass = pass;
        break;
      }
      expect(viewport().opacity, 0, reason: '滚动范围稳定前历史区必须保持隐藏');
    }
    expect(revealPass, greaterThanOrEqualTo(1));
    expect(viewport().opacity, 1);
    final stablePixels = list.controller!.position.pixels;
    final stableMaxScrollExtent = list.controller!.position.maxScrollExtent;
    expect(stablePixels, stableMaxScrollExtent);
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump();
      expect(viewport().opacity, 1);
      expect(list.controller!.position.pixels, stablePixels);
      expect(list.controller!.position.maxScrollExtent, stableMaxScrollExtent);
    }

    await tester.pumpWidget(const SizedBox.shrink());
    resetChatHistoryForTesting();
  });

  testWidgets('短回答的操作栏贴近输入框，不留下整屏底部空白', (tester) async {
    resetChatHistoryForTesting();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _ChatRaceRepository()
      ..rows.clear()
      ..rows.addAll([
        {
          'id': 1,
          'role': 'user',
          'text': '昨晚纳斯达克怎么样？',
          'question': '',
          'created_ms': 1,
        },
        {
          'id': 2,
          'role': 'answer',
          'text': '纳斯达克收盘 **25,980.19**，下跌 **0.76%**。',
          'question': '昨晚纳斯达克怎么样？',
          'created_ms': 2,
        },
      ]);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          home: AiChatPanel(
            fullScreen: true,
            recordOnly: false,
            onSwitchToManual: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    repo.releaseLoad.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    final actions = tester.getRect(
      find.byKey(const ValueKey('ai-chat-answer-actions')),
    );
    final composer = tester.getRect(
      find.byKey(const ValueKey('ai-chat-input-shell')),
    );
    expect(composer.top - actions.bottom, lessThan(100));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    resetChatHistoryForTesting();
  });

  testWidgets('生产历史区三张图片使用完整聊天内容宽度', (tester) async {
    resetChatHistoryForTesting();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _ChatRaceRepository()
      ..rows.clear()
      ..rows.add({
        'id': 1,
        'role': 'user',
        'text': '请看看这三张图片',
        'question': '',
        'created_ms': 1,
        'attachments_json': ChatAttachment.encodeList([
          ChatAttachment(
            kind: ChatAttachmentKind.image,
            path:
                r'C:\src\xunni-codex\android-app\assets\book_covers\dining.png',
            name: '图片1.png',
            mimeType: 'image/png',
            sizeBytes: 100,
          ),
          ChatAttachment(
            kind: ChatAttachmentKind.image,
            path:
                r'C:\src\xunni-codex\android-app\assets\book_covers\shopping.png',
            name: '图片2.png',
            mimeType: 'image/png',
            sizeBytes: 100,
          ),
          ChatAttachment(
            kind: ChatAttachmentKind.image,
            path:
                r'C:\src\xunni-codex\android-app\assets\book_covers\travel.png',
            name: '图片3.png',
            mimeType: 'image/png',
            sizeBytes: 100,
          ),
        ]),
      });

    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          home: AiChatPanel(
            fullScreen: true,
            recordOnly: false,
            onSwitchToManual: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    repo.releaseLoad.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    final images = find.byWidgetPredicate(
      (widget) => widget is Image && widget.image is FileImage,
    );
    expect(images, findsNWidgets(3));
    final rects = [for (var i = 0; i < 3; i++) tester.getRect(images.at(i))];
    expect(rects.first.left, closeTo(16, 0.5));
    expect(rects.last.right, closeTo(374, 0.5));
    expect(rects.map((rect) => rect.width).toList(),
        everyElement(greaterThan(100)));
    expect(rects[0].height, closeTo(rects[0].width, 0.5));
    expect(rects[0].top, closeTo(rects[1].top, 0.1));
    expect(rects[1].top, closeTo(rects[2].top, 0.1));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    resetChatHistoryForTesting();
  });

  testWidgets('前置流程异常也会结束思考并显示可重试错误', (tester) async {
    resetChatHistoryForTesting();
    final repo = _ExplodingChatRepository();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          home: AiChatPanel(
            fullScreen: true,
            recordOnly: true,
            onSwitchToManual: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    repo.explode = true;
    await tester.enterText(
      find.byKey(const ValueKey('ai-chat-input-field')),
      '你好',
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }

    expect(find.text('喵这次处理失败了，请检查网络后重试'), findsOneWidget);
    expect(find.textContaining('正在思考'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    resetChatHistoryForTesting();
  });

  testWidgets('恢复负责人被关闭后新面板会接管恢复而不是显示空历史', (tester) async {
    resetChatHistoryForTesting();
    final repo = _ChatRaceRepository();

    Widget panel() => ChangeNotifierProvider<AppRepository>.value(
          value: repo,
          child: MaterialApp(
            home: Scaffold(
              body: AiChatPanel(
                fullScreen: true,
                recordOnly: false,
                onSwitchToManual: () {},
              ),
            ),
          ),
        );

    await tester.pumpWidget(panel());
    await tester.pump();
    await tester.runAsync(() => repo.loadStarted.future);
    expect(repo.loadCalls, 1);

    // Unmount the restore owner while its database read is still blocked, then
    // mount a waiter before releasing that read.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(panel());
    await tester.pump(const Duration(milliseconds: 20));

    repo.releaseLoad.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(repo.loadCalls, 2, reason: '挂载中的等待者必须接管被卸载实例的恢复');
    expect(find.text('旧消息'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    resetChatHistoryForTesting();
  });

  testWidgets('同一仓库恢复数据库后会丢弃旧行 ID 内存并读取新快照', (tester) async {
    resetChatHistoryForTesting();
    final repo = _ChatRaceRepository();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          home: Scaffold(
            body: AiChatPanel(
              fullScreen: true,
              recordOnly: false,
              onSwitchToManual: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    repo.releaseLoad.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('旧消息'), findsOneWidget);

    repo.commitRestoredRows([
      {
        'id': 1,
        'role': 'user',
        'text': '恢复快照里的消息',
        'question': '',
        'created_ms': 1,
      },
    ]);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(repo.loadCalls, 2);
    expect(find.text('旧消息'), findsNothing);
    expect(find.text('恢复快照里的消息'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    resetChatHistoryForTesting();
  });

  testWidgets('同进程重新打开会增量恢复后台写入的报告卡且不重复', (tester) async {
    resetChatHistoryForTesting();
    final repo = _ChatRaceRepository();

    Widget panel() => ChangeNotifierProvider<AppRepository>.value(
          value: repo,
          child: MaterialApp(
            home: Scaffold(
              body: AiChatPanel(
                fullScreen: true,
                recordOnly: false,
                onSwitchToManual: () {},
              ),
            ),
          ),
        );

    await tester.pumpWidget(panel());
    await tester.pump();
    await tester.runAsync(() => repo.loadStarted.future);
    repo.releaseLoad.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('旧消息'), findsOneWidget);
    expect(repo.loadCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    const report = ReportEntity(
      id: 42,
      bookId: 1,
      type: 'monthly',
      title: '2026年6月消费月报',
      summary: '后台报告摘要唯一标记',
      markdown: '# 2026年6月消费月报\n\n后台报告正文',
      periodStartMs: 1780243200000,
      periodEndMs: 1782835199000,
      createdMs: 1782835200000,
    );
    repo.reportsById[report.id] = report;
    repo.rows.add({
      'id': 2,
      'role': 'report',
      'text': encodeReportChatMessage(report, report.summary),
      'question': '生成 6 月月报',
      'created_ms': 2,
    });

    await tester.pumpWidget(panel());
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(repo.loadCalls, 2, reason: '同进程重开也必须查询后台新增的聊天行');
    expect(find.text('旧消息'), findsOneWidget);
    expect(find.text('后台报告摘要唯一标记'), findsOneWidget);
    expect(find.text('2026年6月消费月报'), findsOneWidget);

    // 再次重建不能把同一条持久化 report row 插入第二遍。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(panel());
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(repo.loadCalls, 3);
    expect(find.text('后台报告摘要唯一标记'), findsOneWidget);
    expect(find.text('2026年6月消费月报'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    resetChatHistoryForTesting();
  });

  testWidgets('同一报告行原地更新后会刷新现有报告卡', (tester) async {
    resetChatHistoryForTesting();
    final repo = _ChatRaceRepository();
    const oldReport = ReportEntity(
      id: 42,
      bookId: 1,
      type: 'monthly',
      title: '6月月报',
      summary: '旧报告摘要',
      markdown: '# 旧报告',
      periodStartMs: 1780243200000,
      periodEndMs: 1782835199000,
      createdMs: 1782835200000,
    );
    const updatedReport = ReportEntity(
      id: 42,
      bookId: 1,
      type: 'monthly',
      title: '6月月报',
      summary: '后台重新生成后的摘要',
      markdown: '# 新报告',
      periodStartMs: 1780243200000,
      periodEndMs: 1782835199000,
      createdMs: 1782835300000,
    );
    repo.reportsById[42] = oldReport;
    repo.rows.add({
      'id': 2,
      'role': 'report',
      'text': encodeReportChatMessage(oldReport, oldReport.summary),
      'question': '重新生成 6 月月报',
      'created_ms': 2,
    });

    Widget panel() => ChangeNotifierProvider<AppRepository>.value(
          value: repo,
          child: MaterialApp(
            home: Scaffold(
              body: AiChatPanel(
                fullScreen: true,
                recordOnly: false,
                onSwitchToManual: () {},
              ),
            ),
          ),
        );

    await tester.pumpWidget(panel());
    await tester.pump();
    repo.releaseLoad.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('旧报告摘要'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    repo.reportsById[42] = updatedReport;
    repo.rows.last['text'] =
        encodeReportChatMessage(updatedReport, updatedReport.summary);
    await tester.pumpWidget(panel());
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.text('旧报告摘要'), findsNothing);
    expect(find.text('后台重新生成后的摘要'), findsOneWidget);
    expect(repo.reportReloadCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    resetChatHistoryForTesting();
  });

  testWidgets('增量恢复负责人关闭后新面板会接管后台消息加载', (tester) async {
    resetChatHistoryForTesting();
    final repo = _ChatRaceRepository();

    Widget panel() => ChangeNotifierProvider<AppRepository>.value(
          value: repo,
          child: MaterialApp(
            home: Scaffold(
              body: AiChatPanel(
                fullScreen: true,
                recordOnly: false,
                onSwitchToManual: () {},
              ),
            ),
          ),
        );

    await tester.pumpWidget(panel());
    await tester.pump();
    repo.releaseLoad.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());

    const report = ReportEntity(
      id: 43,
      bookId: 1,
      type: 'monthly',
      title: '接管恢复月报',
      summary: '接管后可见的后台摘要',
      markdown: '# 接管恢复月报',
      periodStartMs: 1780243200000,
      periodEndMs: 1782835199000,
      createdMs: 1782835200000,
    );
    repo.reportsById[report.id] = report;
    repo.rows.add({
      'id': 2,
      'role': 'report',
      'text': encodeReportChatMessage(report, report.summary),
      'question': '生成报告',
      'created_ms': 2,
    });
    final gate = Completer<void>();
    repo.nextLoadGate = gate;

    await tester.pumpWidget(panel());
    await tester.pump();
    await tester.runAsync(() async {
      while (repo.loadCalls < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(panel());
    await tester.pump(const Duration(milliseconds: 20));

    gate.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(repo.loadCalls, 3, reason: '挂载中的面板必须接管被卸载实例的增量读取');
    expect(find.text('接管后可见的后台摘要'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    resetChatHistoryForTesting();
  });

  testWidgets('思考阶段状态与回答图标保留点击热区', (tester) async {
    resetChatHistoryForTesting();
    final repo = _ChatRaceRepository();
    repo.releaseLoad.complete();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          home: Scaffold(
            body: AiChatPanel(
              fullScreen: true,
              recordOnly: false,
              onSwitchToManual: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final input = find.byKey(const ValueKey('ai-chat-input-field'));
    await tester.enterText(input, '帮我看看本月支出');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.runAsync(() => repo.userInsertStarted.future);
    expect(find.textContaining('正在思考'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    repo.releaseUserInsert.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    resetChatHistoryForTesting();

    final answerRepo = _ChatRaceRepository();
    answerRepo.rows
      ..clear()
      ..add({
        'id': 1,
        'role': 'answer',
        'text': '已完成的回答',
        'question': '',
        'created_ms': 1,
      });
    answerRepo.releaseLoad.complete();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: answerRepo,
        child: MaterialApp(
          home: Scaffold(
            body: AiChatPanel(
              fullScreen: true,
              recordOnly: false,
              onSwitchToManual: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    await tester.pump();

    final copyButton = find.byTooltip('复制');
    expect(copyButton, findsOneWidget);
    expect(tester.getSize(copyButton), const Size(36, 36));
    final copyIcon = tester.widget<SvgPicture>(
      find.descendant(of: copyButton, matching: find.byType(SvgPicture)),
    );
    expect(copyIcon.width, 17.2);
    expect(copyIcon.height, 17.2);

    await tester.pumpWidget(const SizedBox.shrink());
    resetChatHistoryForTesting();
  });
}
