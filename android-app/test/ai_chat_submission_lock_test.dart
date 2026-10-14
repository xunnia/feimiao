import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/views/home/ai_chat_panel.dart';

class _DelayedReadyRepository extends AppRepository {
  final readyGate = Completer<void>();
  int userWrites = 0;
  @override
  bool get isInitialized => true;
  @override
  bool get isAiReady => readyGate.isCompleted;
  @override
  Future<void> get aiReady => readyGate.future;
  @override
  Future<List<Map<String, Object?>>> loadChatMessages() async => [];
  @override
  Future<int> addChatMessage({
    required String role,
    String text = '',
    String question = '',
  }) async {
    if (role == 'user') userWrites++;
    return userWrites + 100;
  }
}

void main() {
  testWidgets('提交等待初始化时重复按发送只能写入一条用户消息', (tester) async {
    resetChatHistoryForTesting();
    final repo = _DelayedReadyRepository();
    await tester.pumpWidget(ChangeNotifierProvider<AppRepository>.value(
      value: repo,
      child: MaterialApp(
          home: Scaffold(
              body: AiChatPanel(
        recordOnly: true,
        onSwitchToManual: () {},
      ))),
    ));
    await tester.pump();
    await tester.enterText(
        find.byKey(const ValueKey('ai-chat-input-field')), '奶茶 18');
    final field = tester
        .widget<TextField>(find.byKey(const ValueKey('ai-chat-input-field')));
    field.onSubmitted!('奶茶 18');
    await tester.pump();
    field.onSubmitted!('奶茶 18');
    await tester.pump();
    repo.readyGate.complete();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.userWrites, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    resetChatHistoryForTesting();
  });
}
