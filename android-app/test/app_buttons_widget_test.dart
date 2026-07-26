import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/widgets/app_buttons.dart';
import 'package:qingji/widgets/settings_ui.dart';

void main() {
  testWidgets('AppPillButton stays compact in a wide sheet header slot',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: Align(
              alignment: Alignment.centerRight,
              child: AppPillButton(
                key: const ValueKey('pill'),
                label: '创建',
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byKey(const ValueKey('pill')));
    expect(size.height, 34);
    expect(size.width, lessThan(96));
  });

  testWidgets('AppSwitch 关闭态灰槽可见、两态同尺寸（iOS 经典形态）', (tester) async {
    var switched = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AppSwitch(
                key: const ValueKey('switch-off'),
                value: false,
                semanticLabel: '计入净资产',
                onChanged: (value) => switched = value,
              ),
              AppSwitch(
                key: const ValueKey('switch-on'),
                value: true,
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    BoxDecoration decorationOf(String key) {
      final animated = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(AnimatedContainer),
        ),
      );
      return animated.decoration! as BoxDecoration;
    }

    // 2026-07-10 用户拍板改回 iOS 经典形态：槽体常显——
    // 关=可见灰槽（半透明卡上裸点根本看不出是开关）、开=深色槽；
    // 两态同尺寸（40 宽），只有白点位置左右滑。
    final offColor = decorationOf('switch-off').color!;
    expect(offColor, isNot(Colors.transparent));
    expect(offColor.a, greaterThan(0.05)); // 灰槽必须可见
    expect(decorationOf('switch-on').color, isNot(Colors.transparent));
    for (final key in const ['switch-off', 'switch-on']) {
      expect(
        tester
            .getSize(
              find.descendant(
                of: find.byKey(ValueKey(key)),
                matching: find.byType(AnimatedContainer),
              ),
            )
            .width,
        40,
      );
    }
    expect(tester.getSize(find.byKey(const ValueKey('switch-off'))),
        const Size(48, 48));
    final semantics =
        tester.getSemantics(find.byKey(const ValueKey('switch-off')));
    expect(semantics.label, '计入净资产');
    expect(semantics.flagsCollection.isToggled, Tristate.isFalse);
    await tester.tap(find.byKey(const ValueKey('switch-off')));
    expect(switched, isTrue);
  });
}
