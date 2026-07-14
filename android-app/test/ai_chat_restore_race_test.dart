import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/budget/budget_window_resolver.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/views/home/ai_chat_panel.dart';

class _ChatRaceRepository extends AppRepository {
  static const _book = BookEntity(id: 1, name: '总账本');
  final Completer<void> loadStarted = Completer<void>();
  final Completer<void> releaseLoad = Completer<void>();
  final Completer<void> userInsertStarted = Completer<void>();
  final Completer<void> releaseUserInsert = Completer<void>();
  final List<Map<String, Object?>> rows = <Map<String, Object?>>[
    {
      'id': 1,
      'role': 'user',
      'text': '旧消息',
      'question': '',
      'created_ms': 1,
    },
  ];
  int _nextId = 2;
  int loadCalls = 0;

  @override
  bool get isInitialized => true;

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
    return rows.map(Map<String, Object?>.of).toList(growable: false);
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

void main() {
  testWidgets('历史恢复与新消息入库交错时不会重复插入新消息', (tester) async {
    resetChatHistoryForTesting();
    final repo = _ChatRaceRepository();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          home: Scaffold(body: AiChatPanel(onSwitchToManual: () {})),
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
        return {
          'id': index + 1,
          'role': 'user',
          'text': '历史消息 $index',
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

    await tester.pump();
    expect(viewport().opacity, 1);
    expect(list.controller!.position.pixels, position.maxScrollExtent);

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
}
