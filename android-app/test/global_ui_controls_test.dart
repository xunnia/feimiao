import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/theme/app_tokens.dart';
import 'package:qingji/widgets/app_buttons.dart';
import 'package:qingji/widgets/settings_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget harness(Widget child) => MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(child: child),
        ),
      );

  testWidgets('图标按钮保留视觉尺寸但提供至少 48dp 点击区域', (tester) async {
    await tester.pumpWidget(harness(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppCircleButton(
            icon: CupertinoIcons.plus,
            semanticLabel: '添加',
            onPressed: () {},
          ),
          AppCloseButton(onPressed: () {}),
        ],
      ),
    ));

    expect(tester.getSize(find.byType(AppCircleButton)).shortestSide,
        greaterThanOrEqualTo(AppHitTarget.min));
    expect(tester.getSize(find.byType(AppCloseButton)).shortestSide,
        greaterThanOrEqualTo(AppHitTarget.min));
    expect(find.bySemanticsLabel('添加'), findsOneWidget);
    expect(find.bySemanticsLabel('关闭'), findsOneWidget);
  });

  testWidgets('胶囊按钮的禁用态仍有稳定视觉尺寸', (tester) async {
    await tester.pumpWidget(harness(
      const AppPillButton(label: '保存', onPressed: null),
    ));

    expect(tester.getSize(find.byType(AppPillButton)).height,
        greaterThanOrEqualTo(AppHitTarget.min));
    expect(find.text('保存'), findsOneWidget);
  });

  testWidgets('统一勾选件的选中态使用主题主色且可访问', (tester) async {
    await tester.pumpWidget(harness(
      AppCheckmark(
        value: true,
        semanticLabel: '选择账单',
        onChanged: (_) {},
      ),
    ));

    expect(tester.getSize(find.byType(AppCheckmark)).shortestSide,
        greaterThanOrEqualTo(AppHitTarget.min));
    expect(find.bySemanticsLabel('选择账单'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    final theme = AppTheme.light().colorScheme;
    final check = tester.widget<Icon>(find.byIcon(Icons.check_rounded));
    expect(check.color, theme.onPrimary);
    expect(AppColors.warning, isNot(const Color(0xFFFF3B30)));
  });
}
