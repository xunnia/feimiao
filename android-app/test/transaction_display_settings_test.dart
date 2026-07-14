import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/models/transaction_card_display.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/views/settings/transaction_display_settings.dart';

class _DisplayPreferenceRepository extends AppRepository {
  TransactionCardDisplayMode mode = TransactionCardDisplayMode.contentFirst;
  UserMessageBubbleStyle bubbleStyle = UserMessageBubbleStyle.followCardOpacity;

  @override
  TransactionCardDisplayMode get transactionCardDisplayMode => mode;

  @override
  UserMessageBubbleStyle get userMessageBubbleStyle => bubbleStyle;

  @override
  Future<void> setTransactionCardDisplayMode(
    TransactionCardDisplayMode value,
  ) async {
    mode = value;
    notifyListeners();
  }

  @override
  Future<void> setUserMessageBubbleStyle(
    UserMessageBubbleStyle value,
  ) async {
    bubbleStyle = value;
    notifyListeners();
  }
}

void main() {
  testWidgets('display settings previews both transaction title hierarchies',
      (tester) async {
    final repo = _DisplayPreferenceRepository();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTransactionDisplaySettings(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    Text previewTitle() => tester.widget<Text>(
          find.byKey(const ValueKey('transaction-display-preview-title')),
        );
    Text previewDetail() => tester.widget<Text>(
          find.byKey(const ValueKey('transaction-display-preview-detail')),
        );

    expect(previewTitle().data, '原神充值');
    expect(previewDetail().data, '21:08 · 虚拟充值');

    await tester.tap(find.text('分类优先'));
    await tester.pump();

    expect(repo.mode, TransactionCardDisplayMode.categoryFirst);
    expect(previewTitle().data, '虚拟充值');
    expect(previewDetail().data, '21:08 · 原神充值');

    final before = (tester
            .widget<Container>(
              find.byKey(const ValueKey('user-bubble-style-preview')),
            )
            .decoration as BoxDecoration)
        .color;
    await tester.tap(find.text('跟随卡片透明度'));
    await tester.pump();
    final after = (tester
            .widget<Container>(
              find.byKey(const ValueKey('user-bubble-style-preview')),
            )
            .decoration as BoxDecoration)
        .color;

    expect(repo.bubbleStyle, UserMessageBubbleStyle.fixedGray);
    expect(after, isNot(before));

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
