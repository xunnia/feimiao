import 'dart:io';
import 'dart:ui' as ui;

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/views/home/home_view.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'screenshot_font_support.dart';

/// 同一场景前后图：旧版留下两笔编号重复的账单，升级后第一次打开首页。
/// UPDATE_UUID_REPAIR_SCREENSHOTS=1 时出图，UUID_REPAIR_PHASE 取 before / after。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late AppRepository repo;
  final now = DateTime.now();
  // 都放在本月 1 号，首页默认就显示这两笔。
  final lunchAt = DateTime(now.year, now.month, 1, 12);
  final dinnerAt = DateTime(now.year, now.month, 1, 19);

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await loadScreenshotFonts(force: true);
    // 分类图标是 emoji，不装字体会画成方块。
    final emoji = File(Platform.environment['FEIMIAO_EMOJI_FONT'] ??
        flutterSdkEmojiFontPath());
    if (emoji.existsSync()) {
      await (FontLoader('NotoColorEmoji')
            ..addFont(
                Future.value(ByteData.sublistView(await emoji.readAsBytes()))))
          .load();
    }
    // 轻提示不在 Material 里，正式版的字用框架默认的系统等宽字体
    // （monospace）。测试环境没有系统字体，借本机等宽字体代替，免得数字
    // 画成方块；找不到就跳过，只影响截图观感。
    for (final path in [
      Platform.environment['FEIMIAO_MONO_FONT'],
      r'C:\Windows\Fonts\consola.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
    ]) {
      if (path == null || !File(path).existsSync()) continue;
      await (FontLoader('monospace')
            ..addFont(Future.value(
                ByteData.sublistView(await File(path).readAsBytes()))))
          .load();
      break;
    }
  });
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('feimiao_uuid_repair_');
    await databaseFactory.setDatabasesPath(temp.path);
    final seed = AppRepository();
    await seed.init();
    final account = seed.accounts.first.id;
    final lunch = await seed.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(20),
        accountId: account,
        note: '午饭',
        date: lunchAt);
    final dinner = await seed.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(30),
        accountId: account,
        note: '晚饭',
        date: dinnerAt);
    // 旧版撞号：午饭用着和晚饭同一个编号，还没查过。
    final db = seed.debugDb;
    final uuid = (await db.query('transactions',
            columns: ['uuid'], where: 'id = ?', whereArgs: [dinner]))
        .single['uuid'];
    await db.update('transactions', {'uuid': uuid},
        where: 'id = ?', whereArgs: [lunch]);
    await db.delete('app_settings',
        where: 'key = ?',
        whereArgs: ['transaction_uuid_duplicates_checked_v1']);
    await seed.closeForTest();
    repo = AppRepository();
    await repo.init();
  });
  tearDown(() async {
    await repo.closeForTest();
    await temp.delete(recursive: true);
  });
  testWidgets('旧版留下的重复编号修好后，首页提示一次，两笔账单都在', (tester) async {
    // 和预算页截图一样设屏幕本身：只设画布时，轻提示按默认 800 宽排版。
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final base = AppTheme.light();
    final theme = base.copyWith(
        textTheme: base.textTheme.apply(fontFamilyFallback: const [
      screenshotCjkFontFamily,
      'NotoColorEmoji'
    ]));
    const capture = ValueKey('uuid-repair-capture');
    await tester.pumpWidget(RepaintBoundary(
        key: capture,
        child: ChangeNotifierProvider<AppRepository>.value(
            value: repo,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme,
                // 轻提示的字不走主题，单独补中文字体，免得截图里是方块。
                builder: (context, child) => DefaultTextStyle.merge(
                    style: const TextStyle(fontFamilyFallback: [
                      screenshotCjkFontFamily,
                      'NotoColorEmoji'
                    ]),
                    child: DecoratedBox(
                        decoration: AppColors.pageBackground(base.brightness),
                        child: child!)),
                home: const Scaffold(body: HomeView(bottomInset: 0))))));
    await tester.pump();
    // 金额数字滚动约 0.65 秒、提示滑入约 0.2 秒，都停稳再截图。
    await tester.pump(const Duration(milliseconds: 900));

    final phase = Platform.environment['UUID_REPAIR_PHASE'] ?? 'after';
    expect(find.text('午饭'), findsWidgets);
    expect(find.text('晚饭'), findsWidgets);
    final notice = find.text('发现 1 笔账单编号重复，已换新编号，没有删除或合并');
    expect(notice, phase == 'after' ? findsOneWidget : findsNothing);
    if (Platform.environment['UPDATE_UUID_REPAIR_SCREENSHOTS'] == '1') {
      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(capture));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3);
        final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        image.dispose();
        final dir =
            Directory('outputs/ui_comparisons/2026-11-06-uuid-repair-notice');
        await dir.create(recursive: true);
        await File('${dir.path}/$phase.png').writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      });
    }
    // 等提示自己收起，再拆页面，不留计时器。
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
