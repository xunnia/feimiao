import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/main.dart' as app;
import 'package:qingji/theme/app_theme_controller.dart';
import 'package:qingji/widgets/slidable_tracker.dart';

void main() {
  testWidgets('first home swipe opens drawer and closing preserves home state',
      (tester) async {
    final repo = AppRepository();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppRepository>.value(value: repo),
        ChangeNotifierProvider<AppThemeController>.value(
            value: AppThemeController.instance),
      ],
      child: const app.QingJiApp(),
    ));
    await tester.pump();
    final input = find.byKey(const ValueKey('home-record-input-shell'));
    final originalElement = tester.element(input);
    final originalX = tester.getTopLeft(input).dx;

    Future<void> swipe(Offset start, Offset delta) async {
      final gesture = await tester.startGesture(start);
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(delta / 8);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    // Closed state must retain the listener without first tapping the menu.
    final row = Object();
    SlidableTracker.setOpen(row, true);
    addTearDown(() => SlidableTracker.setOpen(row, false));
    await swipe(const Offset(15, 200), const Offset(330, 0));
    expect(tester.getTopLeft(input).dx, closeTo(originalX, 0.1));
    SlidableTracker.setOpen(row, false);
    await swipe(const Offset(15, 200), const Offset(330, 0));
    expect(tester.getTopLeft(input).dx, greaterThan(originalX + 200));
    expect(tester.element(input), same(originalElement));

    await swipe(const Offset(650, 200), const Offset(-330, 0));
    expect(tester.getTopLeft(input).dx, closeTo(originalX, 0.1));
    expect(tester.element(input), same(originalElement));

    // Vertical scrolling and a left swipe must not open the left drawer.
    await swipe(const Offset(250, 200), const Offset(0, 150));
    expect(tester.getTopLeft(input).dx, closeTo(originalX, 0.1));
    await swipe(const Offset(350, 200), const Offset(-200, 0));
    expect(tester.getTopLeft(input).dx, closeTo(originalX, 0.1));
    await swipe(const Offset(15, 200), const Offset(330, 0));
    expect(tester.getTopLeft(input).dx, greaterThan(originalX + 200));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    repo.dispose();
  });
}
