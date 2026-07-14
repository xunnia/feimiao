import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/models/transaction_record.dart';
import 'package:qingji/core/statistics/statistics_engine.dart';
import 'package:qingji/core/widgets/widget_card_renderer.dart';
import 'package:qingji/core/widgets/widget_snapshot_service.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/widgets/home_summary_card.dart';
import 'package:qingji/widgets/monthly_pace_card.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // 测试环境默认只有 Ahem 占位字体（文字全渲成方块）。
    // 渲染预览图需要真字体：数字用自带 Nunito，中文借本机微软雅黑。
    // 字体缺失就静默跳过——普通断言不看字形，只有预览图生成在乎。
    await _tryLoadRealFonts();
  });

  testWidgets('真实总览卡和本月进度卡可离屏渲染为 4x2 PNG', (tester) async {
    final now = DateTime(2026, 7, 9);
    final records = _sampleRecords(now);
    final summary = StatisticsEngine.monthlySummary(
      records,
      year: now.year,
      month: now.month,
    );

    // 渲染器内部用真实 Timer 等图片解码、toImage 走引擎真异步——
    // 必须包 tester.runAsync，否则在 testWidgets 的假异步时钟里永远卡死。
    final images = await tester.runAsync(() async {
      final overview = await renderWidgetToPng(
        HomeSummaryCard(
          monthDate: DateTime(now.year, now.month),
          isCurrentMonth: true,
          summary: summary,
          budgetStatus: null,
          budget: null,
        ),
        logicalSize: WidgetCardRenderSizes.overview,
        naturalHeight: true,
        pixelRatio: 2,
        fontFamily: 'PreviewCJK',
      );
      final pace = await renderWidgetToPng(
        MonthlyPaceCard(
          records: records,
          summary: summary,
          year: now.year,
          month: now.month,
          isCurrentMonth: true,
          compact: true,
        ),
        logicalSize: WidgetCardRenderSizes.pace,
        naturalHeight: true,
        pixelRatio: 2,
        fontFamily: 'PreviewCJK',
      );
      return (overview: overview, pace: pace);
    });
    final overview = images!.overview;
    final pace = images.pace;

    expect(overview.length, greaterThan(1000));
    expect(pace.length, greaterThan(1000));
    await tester.runAsync(() async {
      // 自然高度渲染：宽度固定（300@2x=600），高度跟内容走、只受上限约束。
      await _expectPngWidth(overview, width: 680, maxHeight: 760);
      await _expectPngWidth(pace, width: 680, maxHeight: 760);
    });

    if (Platform.environment['UPDATE_WIDGET_PREVIEWS'] == '1') {
      await tester.runAsync(() async {
        await File(
          p.join(
            Directory.current.path,
            'android',
            'app',
            'src',
            'main',
            'res',
            'drawable-nodpi',
            'widget_preview_overview.png',
          ),
        ).writeAsBytes(overview, flush: true);
        await File(
          p.join(
            Directory.current.path,
            'android',
            'app',
            'src',
            'main',
            'res',
            'drawable-nodpi',
            'widget_preview_budget.png',
          ),
        ).writeAsBytes(pace, flush: true);
      });
    }
  });

  testWidgets('快照服务写入 PNG 路径且隐私渲染输入已脱敏', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('qingji_widget_render_');
    await databaseFactory.setDatabasesPath(tmp.path);
    final repo = AppRepository();
    // sqflite ffi 与离屏渲染都是真实异步，testWidgets 假时钟下必须包 runAsync。
    await tester.runAsync(() => repo.init());
    try {
      final expenseCat = repo.categoriesForKind(TransactionKind.expense).first;
      final incomeCat = repo.categoriesForKind(TransactionKind.income).first;
      final json = (await tester.runAsync(() async {
        await repo.addTransaction(
          kind: TransactionKind.expense,
          amount: Decimal.parse('88.66'),
          categoryId: expenseCat.id,
          accountId: repo.accounts.first.id,
          note: '小组件渲染测试支出',
          date: DateTime(2026, 7, 9),
        );
        await repo.addTransaction(
          kind: TransactionKind.income,
          amount: Decimal.parse('1888.00'),
          categoryId: incomeCat.id,
          accountId: repo.accounts.first.id,
          note: '小组件渲染测试收入',
          date: DateTime(2026, 7, 8),
        );
        await repo.setWidgetPrivacyMode(true);

        final renderDir = Directory(p.join(tmp.path, 'render'));
        return WidgetSnapshotService.instance.buildSnapshotJsonForRepo(
          repo,
          now: DateTime(2026, 7, 9),
          renderDirectory: renderDir,
        );
      }))!;
      final modules = json['modules'] as Map<String, Object?>;
      final overview = modules['overview'] as Map<String, Object?>;
      final pace = modules['pace'] as Map<String, Object?>;
      final overviewRender = overview['render'] as Map<String, Object?>;
      final paceRender = pace['render'] as Map<String, Object?>;

      expect(File(overviewRender['path']! as String).existsSync(), isTrue);
      expect(File(paceRender['path']! as String).existsSync(), isTrue);
      expect(overviewRender['byteLength'], isPositive);
      expect(paceRender['byteLength'], isPositive);
      expect(json['privacyMode'], isTrue);
      expect(json['monthExpenseText'], '••••');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: HomeSummaryCard(
              monthDate: DateTime(2026, 7),
              isCurrentMonth: true,
              summary: StatisticsEngine.monthlySummary(
                repo.allRecords,
                year: 2026,
                month: 7,
              ),
              budgetStatus: null,
              budget: null,
              maskAmounts: true,
            ),
          ),
        ),
      );
      expect(find.text('¥****'), findsWidgets);
      expect(find.textContaining('88.66'), findsNothing);
      expect(find.textContaining('1888'), findsNothing);
    } finally {
      await tester.runAsync(() => repo.closeForTest());
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    }
  });
}

Future<void> _tryLoadRealFonts() async {
  ByteData? read(String path) {
    try {
      final f = File(path);
      if (!f.existsSync()) return null;
      final bytes = f.readAsBytesSync();
      return ByteData.view(bytes.buffer);
    } catch (_) {
      return null;
    }
  }

  final cjkData = read(r'C:\Windows\Fonts\Deng.ttf') ??
      read(r'C:\Windows\Fonts\simhei.ttf');

  try {
    final loader = FontLoader('Nunito');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      final data = read(
        p.join(Directory.current.path, 'assets', 'fonts', 'Nunito-$weight.ttf'),
      );
      if (data == null) return;
      loader.addFont(Future.value(data));
    }
    // 把中文字体追加进 Nunito 字族做兜底：Nunito 样式的文字里夹的中文
    //（如「结余 ¥…」）才不会渲成方块。
    if (cjkData != null) loader.addFont(Future.value(cjkData));
    await loader.load();
  } catch (_) {}
  try {
    // 图标字体：Material 图标在 Flutter SDK 缓存里，Cupertino 图标在 pub 包资产里。
    final material = read(
      r'C:\src\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    );
    if (material != null) {
      await (FontLoader('MaterialIcons')..addFont(Future.value(material)))
          .load();
    }
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null) {
      final hosted = Directory(
        p.join(localAppData, 'Pub', 'Cache', 'hosted', 'pub.flutter-io.cn'),
      );
      if (hosted.existsSync()) {
        // 版本号不写死，扫目录找 cupertino_icons-*。
        for (final e in hosted.listSync()) {
          if (e is Directory &&
              p.basename(e.path).startsWith('cupertino_icons-')) {
            final cupertino =
                read(p.join(e.path, 'assets', 'CupertinoIcons.ttf'));
            if (cupertino != null) {
              await (FontLoader('packages/cupertino_icons/CupertinoIcons')
                    ..addFont(Future.value(cupertino)))
                  .load();
            }
            break;
          }
        }
      }
    }
  } catch (_) {}
  try {
    // Material 在 Android 主题下默认 family 是 Roboto；把本机中文字体注册成
    // Roboto，中文就有真字形了（仅本机生成预览用，没有该文件会静默跳过）。
    // 注意用 .ttf 不用 .ttc——TTC 容器 FontLoader 加载不了。
    // 注册成独立字族，渲染时经 renderWidgetToPng(fontFamily:) 从主题层应用；
    // 测试引擎的默认字族 Ahem 顶不掉，只有显式请求这个字族才生效。
    if (cjkData == null) return;
    final loader = FontLoader('PreviewCJK')..addFont(Future.value(cjkData));
    await loader.load();
  } catch (_) {}
}

List<TransactionRecord> _sampleRecords(DateTime now) {
  return [
    for (var offset = 6; offset >= 0; offset--)
      TransactionRecord(
        id: 'expense-$offset',
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(200 + offset * 35),
        categoryName: offset.isEven ? '食品' : '交通',
        date: DateTime(now.year, now.month - offset, 5),
      ),
    TransactionRecord(
      id: 'expense-current-extra',
      kind: TransactionKind.expense,
      amount: Decimal.parse('168.50'),
      categoryName: '房租',
      date: DateTime(now.year, now.month, 9),
    ),
    TransactionRecord(
      id: 'income-current',
      kind: TransactionKind.income,
      amount: Decimal.parse('6200'),
      categoryName: '工资',
      date: DateTime(now.year, now.month, 3),
    ),
  ];
}

Future<void> _expectPngWidth(
  List<int> bytes, {
  required int width,
  required int maxHeight,
}) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
  final frame = await codec.getNextFrame();
  expect(frame.image.width, width);
  expect(frame.image.height, greaterThan(0));
  expect(frame.image.height, lessThanOrEqualTo(maxHeight));
  frame.image.dispose();
}
