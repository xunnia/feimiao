import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/widgets/transaction_actions.dart';

class _RepaymentRepository extends AppRepository {
  bool repaymentActive = true;
  final undoCalls = <int>[];
  final deleteCalls = <int>[];
  Completer<void>? pending;
  Object? failure;

  @override
  AssetEventEntity? liabilityRepaymentEventForTransaction(int transactionId) =>
      repaymentActive && (transactionId == 1 || transactionId == 2)
          ? const AssetEventEntity(
              id: 71,
              uuid: 'repayment-71',
              assetId: 3,
              assetType: AssetObjectType.liability,
              eventType: AssetEventType.liabilityRepaid,
              occurredMs: 0,
            )
          : null;

  @override
  Future<void> undoLiabilityRepayment(int eventId) async {
    undoCalls.add(eventId);
    if (pending != null) await pending!.future;
    if (failure != null) throw failure!;
    repaymentActive = false;
    notifyListeners();
  }

  @override
  Future<void> deleteTransaction(int id) async => deleteCalls.add(id);
}

TransactionEntity _transaction(int id, String kind) => TransactionEntity(
      id: id,
      kind: kind,
      amountStr: '100',
      dateMs: 0,
    );

Future<void> _showRow(
  WidgetTester tester,
  _RepaymentRepository repo,
  TransactionEntity transaction,
) async {
  await tester.pumpWidget(ChangeNotifierProvider<AppRepository>.value(
    value: repo,
    child: MaterialApp(
      home: Scaffold(
        body: TransactionSlidable(
          transaction: transaction,
          child: const SizedBox(
            height: 64,
            width: double.infinity,
            child: Text('账单'),
          ),
        ),
      ),
    ),
  ));
  await tester.drag(find.text('账单'), const Offset(-600, 0));
  await tester.pumpAndSettle();
}

void main() {
  for (final (id, kind) in [(1, 'transfer'), (2, 'expense')]) {
    testWidgets('还款$id左滑只能整笔撤销，确认前与取消均不写入', (tester) async {
      final repo = _RepaymentRepository();
      await _showRow(tester, repo, _transaction(id, kind));
      expect(find.text('撤销'), findsOneWidget);
      for (final label in ['编辑', '退款', '删除']) {
        expect(find.text(label), findsNothing);
      }
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(find.text('撤销本次还款'), findsOneWidget);
      expect(repo.undoCalls, isEmpty);
      final controller = Slidable.of(tester.element(find.text('账单')))!;
      controller.close();
      await tester.pumpAndSettle();
      controller.openEndActionPane();
      await tester.pumpAndSettle();
      expect(find.text('撤销'), findsOneWidget);
      expect(find.text('撤销本次还款'), findsNothing);
      expect(repo.undoCalls, isEmpty);
      expect(repo.deleteCalls, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('撤销处理中重复点击只调用一次，成功显示反馈且不走删除', (tester) async {
    final repo = _RepaymentRepository()..pending = Completer<void>();
    await _showRow(tester, repo, _transaction(2, 'expense'));
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销本次还款'));
    await tester.tap(find.text('撤销本次还款'));
    await tester.pump();
    expect(repo.undoCalls, [71]);
    expect(find.text('撤销中'), findsOneWidget);
    await tester.tap(find.text('撤销中'));
    expect(repo.undoCalls, [71]);
    repo.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('已撤销本次还款'), findsOneWidget);
    expect(repo.deleteCalls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('仓储StateError显示原原因，可重试且不转为删除', (tester) async {
    final repo = _RepaymentRepository()..failure = StateError('请先撤销该负债最近一次还款');
    await _showRow(tester, repo, _transaction(1, 'transfer'));
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销本次还款'));
    await tester.pumpAndSettle();
    expect(find.text('请先撤销该负债最近一次还款'), findsOneWidget);
    expect(find.text('撤销本次还款'), findsOneWidget);
    expect(repo.undoCalls, [71]);
    expect(repo.deleteCalls, isEmpty);
    repo.failure = null;
    await tester.tap(find.text('撤销本次还款'));
    await tester.pumpAndSettle();
    expect(repo.undoCalls, [71, 71]);
    expect(repo.deleteCalls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('确认后凭证失效仍提交原还款编号，仓储拦截后不误删账单', (tester) async {
    final repo = _RepaymentRepository();
    await _showRow(tester, repo, _transaction(1, 'transfer'));
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    repo.repaymentActive = false;
    repo.failure = StateError('本次还款不存在或已经撤销');
    repo.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('撤销本次还款'), findsOneWidget);
    await tester.tap(find.text('撤销本次还款'));
    await tester.pumpAndSettle();
    expect(repo.undoCalls, [71]);
    expect(repo.deleteCalls, isEmpty);
    expect(find.text('本次还款不存在或已经撤销'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final kind in ['expense', 'income', 'transfer']) {
    testWidgets('普通$kind账单保留原有左滑操作与删除确认', (tester) async {
      final repo = _RepaymentRepository();
      await _showRow(tester, repo, _transaction(10, kind));
      expect(find.text('编辑'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      expect(
          find.text('退款'), kind == 'expense' ? findsOneWidget : findsNothing);
      expect(find.text('撤销'), findsNothing);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('删除这笔'), findsOneWidget);
      await tester.tap(find.text('删除这笔'));
      await tester.pumpAndSettle();
      expect(repo.deleteCalls, [10]);
      expect(repo.undoCalls, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
