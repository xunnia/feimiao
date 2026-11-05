import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/views/settings/import_export_view.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'screenshot_font_support.dart';

/// 同一场景前后图：肥喵导出表里两笔账单编号重复，走真实导入流程后的提示。
/// UPDATE_IMPORT_DUPLICATE_SCREENSHOTS=1 时出图，IMPORT_DUPLICATE_PHASE 取
/// before / after。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late AppRepository repo;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await loadScreenshotFonts(force: true);
  });
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('feimiao_import_dup_');
    await databaseFactory.setDatabasesPath(temp.path);
    repo = AppRepository();
    await repo.init();
  });
  tearDown(() async {
    await repo.closeForTest();
    await temp.delete(recursive: true);
  });

  testWidgets('肥喵导出表编号重复时，恢复提示说明换了新编号', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const header = '日期,类型,分类,净额,原始金额,已退款,计入收支,账户,备注,记录类型,交易UUID';
    const uuid = 'abababababababababababababababab';
    const csv = '﻿$header\n'
        '2026-07-02 19:00,支出,餐饮,30,30,0,是,,晚饭,账单,$uuid\n'
        '2026-07-01 12:00,支出,餐饮,20,20,0,是,,午饭,账单,$uuid\n';
    final bytes = Uint8List.fromList(utf8.encode(csv));
    Future<FilePickerResult?> pick() async => FilePickerResult([
          PlatformFile(name: '肥喵导出.csv', size: bytes.length, bytes: bytes),
        ]);

    final base = AppTheme.light();
    final theme = base.copyWith(
        textTheme: base.textTheme
            .apply(fontFamilyFallback: const [screenshotCjkFontFamily]),
        appBarTheme: base.appBarTheme.copyWith(
            titleTextStyle: base.appBarTheme.titleTextStyle!.copyWith(
                fontFamilyFallback: const [screenshotCjkFontFamily])));
    const capture = ValueKey('import-duplicate-capture');
    await tester.pumpWidget(RepaintBoundary(
        key: capture,
        child: ChangeNotifierProvider<AppRepository>.value(
            value: repo,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme,
                builder: (context, child) => DecoratedBox(
                    decoration: AppColors.pageBackground(base.brightness),
                    child: child),
                home: ImportExportView(debugPickFile: pick)))));
    await tester.tap(find.text('导入'));
    await tester.runAsync(() async {
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (find.textContaining('已恢复').evaluate().isNotEmpty) break;
        await tester.pump();
      }
    });
    await tester.pump();

    final phase = Platform.environment['IMPORT_DUPLICATE_PHASE'] ?? 'after';
    expect(find.textContaining('已恢复'), findsOneWidget);
    if (phase == 'after') {
      expect(find.text('已恢复 2 笔，退款 0 笔。1 笔编号和别的账单重复，已换新编号保留'), findsOneWidget);
      expect(repo.visibleTransactions, hasLength(2));
    }
    if (Platform.environment['UPDATE_IMPORT_DUPLICATE_SCREENSHOTS'] == '1') {
      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(capture));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3);
        final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        image.dispose();
        final dir = Directory(
            'outputs/ui_comparisons/2026-11-05-import-duplicate-uuid');
        await dir.create(recursive: true);
        await File('${dir.path}/$phase.png').writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
