import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/theme/app_theme_controller.dart';
import 'package:qingji/theme/app_tokens.dart';
import 'package:qingji/widgets/transaction_actions.dart';
import 'package:qingji/widgets/transaction_day_list.dart';

import 'screenshot_font_support.dart';

class _VisualRepository extends AppRepository {
  @override
  AssetEventEntity? liabilityRepaymentEventForTransaction(int id) => id < 3
      ? const AssetEventEntity(
          id: 71,
          uuid: 'repayment-71',
          assetId: 3,
          assetType: AssetObjectType.liability,
          eventType: AssetEventType.liabilityRepaid,
          occurredMs: 0,
        )
      : null;
}

final _transactions = [
  TransactionEntity(
    id: 1,
    kind: 'transfer',
    amountStr: '100',
    accountName: '银行卡',
    toAccountName: '借款',
    note: '还款本金：借款',
    dateMs: DateTime(2026, 10, 4, 12).millisecondsSinceEpoch,
  ),
  TransactionEntity(
    id: 2,
    kind: 'expense',
    amountStr: '10',
    accountName: '银行卡',
    categoryKey: 'other_fee',
    categoryNameZh: '利息',
    note: '还款利息：借款',
    dateMs: DateTime(2026, 10, 4, 12).millisecondsSinceEpoch,
  ),
  TransactionEntity(
    id: 10,
    kind: 'expense',
    amountStr: '18',
    accountName: '银行卡',
    categoryKey: 'food',
    categoryNameZh: '餐饮',
    note: '午餐',
    dateMs: DateTime(2026, 10, 4, 12).millisecondsSinceEpoch,
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => loadScreenshotFonts(force: true));
  final baseline = Platform.environment['REPAYMENT_BASELINE'] == '1';
  for (final preset in [kThemePresets[0], kThemePresets[1], kThemePresets[5]]) {
    for (final (width, scale) in [(420.0, 1.0), (320.0, 2.0)]) {
      testWidgets('还款左滑 ${preset.key} ${width.toInt()} ${scale}x',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        AppColors.applyTheme(
          bgTop: preset.top,
          bgBottom: preset.bottom,
          bgSolid: preset.solid,
          cardAlphaL: 0.8,
          cardAlphaD: 0.8,
          bgDark: preset.bottom,
          bgDarkTop: preset.top,
        );
        final base = preset.forceDark ? AppTheme.dark() : AppTheme.light();
        final theme = base.copyWith(
          textTheme: base.textTheme.apply(
            fontFamilyFallback: const [screenshotCjkFontFamily],
          ),
          appBarTheme: base.appBarTheme.copyWith(
            titleTextStyle: base.appBarTheme.titleTextStyle!.copyWith(
              fontFamilyFallback: const [screenshotCjkFontFamily],
            ),
          ),
        );
        const capture = ValueKey('repayment-capture');
        await tester.pumpWidget(RepaintBoundary(
          key: capture,
          child: ChangeNotifierProvider<AppRepository>.value(
            value: _VisualRepository(),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                ),
                child: DecoratedBox(
                  decoration: AppColors.pageBackground(base.brightness),
                  child: child,
                ),
              ),
              home: Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(title: const Text('账单')),
                body: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                  children: [
                    for (final tx in _transactions) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          tx.id == 1
                              ? '还款本金'
                              : tx.id == 2
                                  ? '还款利息'
                                  : '普通支出',
                          style: AppType.secondary(theme.colorScheme),
                        ),
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Material(
                          color: AppColors.card(theme.colorScheme),
                          child: TransactionSlidable(
                            key: ValueKey('repayment-row-${tx.id}'),
                            transaction: tx,
                            child: TxRow(
                              key: ValueKey('repayment-content-${tx.id}'),
                              transaction: tx,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        for (final tx in _transactions) {
          Slidable.of(tester.element(
            find.byKey(ValueKey('repayment-content-${tx.id}')),
          ))!
              .openEndActionPane();
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final stem = '${preset.key}-${width.toInt()}-${scale.toInt()}x';

        Future<void> captureImage(String phase) async {
          if (Platform.environment['UPDATE_REPAYMENT_SCREENSHOTS'] != '1') {
            return;
          }
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(capture),
          );
          final bounds = <String, List<double>>{};
          for (final tx in _transactions) {
            final box = tester.renderObject<RenderBox>(
              find.byKey(ValueKey('repayment-row-${tx.id}')),
            );
            final offset = box.localToGlobal(Offset.zero);
            bounds['${tx.id}'] = [
              offset.dx,
              offset.dy,
              offset.dx + box.size.width,
              offset.dy + box.size.height,
            ];
          }
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 3);
            try {
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              final output = File(
                'outputs/ui_comparisons/2026-10-04-repayment-actions/'
                '${baseline ? 'before' : 'after'}/$stem-$phase.png',
              );
              await output.parent.create(recursive: true);
              await output.writeAsBytes(bytes!.buffer.asUint8List());
              await File(output.path.replaceFirst('.png', '.json'))
                  .writeAsString(jsonEncode(bounds));
            } finally {
              image.dispose();
            }
          });
        }

        await captureImage('actions');
        for (final tx in _transactions) {
          final row = find.byKey(ValueKey('repayment-row-${tx.id}'));
          await tester.tap(find.descendant(
            of: row,
            matching: find.text(!baseline && tx.id < 3 ? '撤销' : '删除'),
          ));
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (!baseline) {
          expect(find.text('撤销本次还款'), findsNWidgets(2));
          for (final text in tester.renderObjectList<RenderParagraph>(
            find.text('撤销本次还款'),
          )) {
            expect(text.didExceedMaxLines, isFalse);
            final full = TextPainter(
              text: text.text,
              textDirection: TextDirection.ltr,
              textScaler: TextScaler.linear(scale),
            )..layout();
            expect(text.size.width, greaterThanOrEqualTo(full.width - 0.1));
            expect(text.size.height, greaterThanOrEqualTo(full.height - 0.1));
            full.dispose();
          }
        }
        await captureImage('confirm');
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
