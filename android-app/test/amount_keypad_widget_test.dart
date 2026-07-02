import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/amount_expression.dart';
import 'package:qingji/views/quick_add/amount_keypad.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('AmountKeypad（咔皮布局）', () {
    testWidgets('提供 onSaveAgain 时显示「再记」，否则显示 C', (tester) async {
      final expr = AmountExpression();
      await tester.pumpWidget(_wrap(AmountKeypad(
        expression: expr,
        onExpressionChanged: () {},
        onSave: () {},
        onSaveAgain: () {},
      )));
      expect(find.text('再记'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
      expect(find.text('C'), findsNothing);

      await tester.pumpWidget(_wrap(AmountKeypad(
        expression: expr,
        onExpressionChanged: () {},
        onSave: () {},
      )));
      expect(find.text('再记'), findsNothing);
      expect(find.text('C'), findsOneWidget);
    });

    testWidgets('金额为 0 时「完成」「再记」都点不动', (tester) async {
      final expr = AmountExpression();
      var saved = false;
      var savedAgain = false;
      await tester.pumpWidget(_wrap(AmountKeypad(
        expression: expr,
        onExpressionChanged: () {},
        onSave: () => saved = true,
        onSaveAgain: () => savedAgain = true,
      )));
      await tester.tap(find.text('完成'));
      await tester.tap(find.text('再记'));
      await tester.pump();
      expect(saved, isFalse);
      expect(savedAgain, isFalse);
    });

    testWidgets('点数字和加减号会更新表达式，金额>0 后完成可点', (tester) async {
      final expr = AmountExpression();
      var saved = false;
      var version = 0;
      late StateSetter rebuild;
      await tester.pumpWidget(_wrap(StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return AmountKeypad(
            expression: expr,
            onExpressionChanged: () => rebuild(() => version++),
            onSave: () => saved = true,
          );
        },
      )));

      await tester.tap(find.text('1'));
      await tester.tap(find.text('2'));
      await tester.pump();
      expect(expr.displayText, '12');

      // 减号：12-2 = 10
      await tester.tap(find.byIcon(Icons.remove));
      await tester.tap(find.text('2'));
      await tester.pump();
      expect(expr.displayText, '12-2');
      expect(expr.value.toString(), '10');
      expect(version, greaterThan(0));

      await tester.tap(find.text('完成'));
      await tester.pump();
      expect(saved, isTrue);
    });

    testWidgets('长按 ⌫ 清空整个表达式', (tester) async {
      final expr = AmountExpression();
      await tester.pumpWidget(_wrap(StatefulBuilder(
        builder: (context, setState) => AmountKeypad(
          expression: expr,
          onExpressionChanged: () => setState(() {}),
          onSave: () {},
        ),
      )));
      await tester.tap(find.text('9'));
      await tester.tap(find.text('9'));
      await tester.pump();
      expect(expr.displayText, '99');

      await tester.longPress(find.byIcon(Icons.backspace_outlined));
      await tester.pump();
      expect(expr.isEmpty, isTrue);
    });
  });
}
