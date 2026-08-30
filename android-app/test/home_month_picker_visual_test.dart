import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/views/home/home_view.dart';
import 'package:qingji/widgets/app_buttons.dart';
import 'package:qingji/widgets/settings_ui.dart';

import 'screenshot_font_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadScreenshotFonts);

  testWidgets('月份选择器沿用参考布局且年份箭头无圆形底', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: DecoratedBox(
            key: const ValueKey('home-month-picker-capture'),
            decoration: AppColors.pageBackground(Brightness.light),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Material(
                color: AppTheme.light().colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                clipBehavior: Clip.antiAlias,
                child: buildHomeMonthPickerForTesting(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // The home selector intentionally keeps the original lightweight layout,
    // rather than the global form-sheet header: title left, helper right, and
    // no close-circle control inside the sheet.
    expect(find.byType(SheetHeader), findsNothing);
    expect(find.byType(AppCircleButton), findsNothing);
    final title = tester.widget<Text>(find.text('月份选择'));
    expect(title.style?.fontSize, 22);
    final subtitle = tester.widget<Text>(
      find.text('月统计起始日：每月 1 号'),
    );
    expect(subtitle.style?.fontSize, 13);
    expect(find.text('2026年'), findsOneWidget);
    expect(find.text('8月'), findsOneWidget);

    if (Platform.environment['UPDATE_HOME_UI_SCREENSHOTS'] == '1') {
      await expectLater(
        find.byKey(const ValueKey('home-month-picker-capture')),
        matchesGoldenFile(
          '../outputs/ui_comparisons/2026-08-30/month_picker_after.png',
        ),
      );
    }
  });
}
