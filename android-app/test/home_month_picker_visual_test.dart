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

    expect(find.byType(SheetHeader), findsOneWidget);
    expect(find.byType(AppCircleButton), findsOneWidget);
    expect(
      tester.widget<SheetHeader>(find.byType(SheetHeader)).closeExtraInset,
      8,
    );
    expect(find.text('2026年'), findsOneWidget);
    expect(find.text('8月'), findsOneWidget);

    if (Platform.environment['UPDATE_HOME_UI_SCREENSHOTS'] == '1') {
      await expectLater(
        find.byKey(const ValueKey('home-month-picker-capture')),
        matchesGoldenFile('../outputs/home_ui/month_picker.png'),
      );
    }
  });
}
