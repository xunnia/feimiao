import 'dart:async';
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
import 'package:qingji/views/books/book_sheet.dart';
import 'package:qingji/views/books/transaction_books_sheet.dart';
import 'package:qingji/views/home/manual_add_sheet.dart';
import 'package:qingji/widgets/ios_menu.dart';
import 'package:qingji/widgets/settings_ui.dart';
import 'package:qingji/widgets/sliding_segment.dart';
import 'package:qingji/widgets/transaction_day_list.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'screenshot_font_support.dart';

const _captureKey = ValueKey('multibook-capture');

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await loadScreenshotFonts(force: true);
    await _loadEmojiFont();
  });

  for (final scene in [
    'book-new',
    'book-edit',
    'entry-edit',
    'entry-books',
    'entry-tags',
    if (Platform.environment['MULTIBOOK_CAPTURE_DIRECTORY'] != null ||
        !(Platform.environment['MULTIBOOK_CAPTURE_PHASE']
                ?.startsWith('before') ??
            false)) ...[
      'book-select',
      'history-add',
      'history-remove',
      'history-filtered',
      'history-selected',
    ],
  ]) {
    for (final variant in [
      'light',
      'dark',
      'large',
      if (scene == 'history-add') 'keyboard-large',
    ]) {
      testWidgets('$scene $variant keeps the production sheet usable',
          (tester) async {
        final large = variant == 'large' || variant == 'keyboard-large';
        tester.view.physicalSize = Size(large ? 320 : 393, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final dir = Directory.systemTemp.createTempSync('multibook-ui-');
        final repo = AppRepository();
        late int business;
        await tester.runAsync(() async {
          await databaseFactory.setDatabasesPath(dir.path);
          await repo.init();
          business = await repo.addBook(name: '生意账本', icon: '💼');
          await repo.addBook(name: '项目 A', icon: '📒');
          await repo.addTag(name: '工作', colorValue: 0xff81929b);
          await repo.addTag(name: '旅行', colorValue: 0xff81929b);
          await repo.switchBook(business);
          await repo.addTransaction(
            kind: TransactionKind.expense,
            amount: Decimal.fromInt(100),
            categoryId: repo.categories.first.id,
            accountId: repo.transactionAccounts.first.id,
            note: '项目设备采购',
            date: DateTime(2026, 10, 22, 12),
            bookId: business,
          );
          if (scene.startsWith('history-')) {
            for (var index = 0; index < 7; index++) {
              await repo.addTransaction(
                kind: index == 2
                    ? TransactionKind.income
                    : TransactionKind.expense,
                amount: Decimal.fromInt(index == 2 ? 3200 : 28 + index * 43),
                categoryId: repo.categories.first.id,
                accountId: repo.transactionAccounts.first.id,
                note: const [
                  '采购打印纸',
                  '客户拜访交通费',
                  '项目尾款',
                  '办公室网络费',
                  '设备配件和转接线',
                  '工作午餐',
                  '资料打印',
                ][index],
                date: DateTime(2026, 10, 22 - index ~/ 3, 11 - index),
                bookId: business,
              );
            }
          }
        });
        addTearDown(() => tester.runAsync(() async {
              await repo.closeForTest();
              dir.deleteSync(recursive: true);
            }));
        final brightness =
            variant == 'dark' ? Brightness.dark : Brightness.light;
        final theme =
            brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light();
        await tester.pumpWidget(RepaintBoundary(
          key: _captureKey,
          child: ChangeNotifierProvider.value(
            value: repo,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme.copyWith(
                textTheme: theme.textTheme.apply(
                  fontFamily: 'Nunito',
                  fontFamilyFallback: [
                    screenshotCjkFontFamily,
                    'NotoColorEmoji'
                  ],
                ),
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
                child: child!,
              ),
              home: DecoratedBox(
                decoration: AppColors.pageBackground(brightness),
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  body: Builder(builder: (context) {
                    return TextButton(
                      onPressed: () {
                        if (scene == 'book-select') {
                          showTransactionBooksMenu(context,
                              selectedIds: [business], onChanged: (_) {});
                        } else if (scene.startsWith('history-')) {
                          showBookTransactionsSheet(context,
                              book: repo.books.firstWhere((b) =>
                                  b.name ==
                                  (scene == 'history-remove'
                                      ? '生意账本'
                                      : '项目 A')),
                              removeOnly: scene == 'history-remove');
                        } else if (scene.startsWith('entry-')) {
                          showManualAddSheet(context,
                              edit: repo.transactions.first);
                        } else {
                          showBookSheet(context,
                              edit: scene == 'book-edit'
                                  ? repo.books
                                      .firstWhere((b) => b.id == business)
                                  : null);
                        }
                      },
                      child: const Text('打开'),
                    );
                  }),
                ),
              ),
            ),
          ),
        ));
        if (scene == 'book-new') {
          final imageContext = tester.element(find.text('打开'));
          await tester.runAsync(() async {
            for (final template in kBookTemplates) {
              final cover = template.cover;
              if (cover == null) continue;
              Object? failure;
              await precacheImage(AssetImage(cover), imageContext,
                  onError: (error, _) => failure = error);
              if (failure != null) {
                throw StateError('封面解码失败：$cover / $failure');
              }
            }
          });
        }
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
        if (scene == 'entry-books' || scene == 'entry-tags') {
          final chip = find.text(scene == 'entry-books' ? '生意账本' : '标签');
          for (var attempt = 0;
              chip.evaluate().isEmpty && attempt < 6;
              attempt++) {
            await tester.drag(
                find.byWidgetPredicate((w) =>
                    w is ListView && w.scrollDirection == Axis.horizontal),
                const Offset(-160, 0));
            await tester.pumpAndSettle();
          }
          await tester.ensureVisible(chip);
          await tester.pumpAndSettle();
          await tester.tap(chip);
          await tester.pumpAndSettle();
        }
        if (scene == 'book-new') {
          expect(find.byType(RawImage), findsWidgets);
          for (final image
              in tester.widgetList<RawImage>(find.byType(RawImage))) {
            expect(image.image, isNotNull, reason: '封面必须完成解码后才能采图');
          }
        }
        if (variant == 'keyboard-large') {
          tester.view.viewInsets = const FakeViewPadding(bottom: 320);
          addTearDown(tester.view.resetViewInsets);
          await tester
              .tap(find.byKey(const ValueKey('book-transactions-search')));
          await tester.pumpAndSettle();
        }
        if (scene == 'history-filtered' || scene == 'history-selected') {
          await tester.enterText(
              find.byKey(const ValueKey('book-transactions-search')), '设备');
          await tester.pumpAndSettle();
          if (scene == 'history-selected') {
            await tester.tap(find.text('项目设备采购'));
            await tester.pumpAndSettle();
          }
        }
        if (variant != 'large' ||
            !(Platform.environment['MULTIBOOK_CAPTURE_PHASE']
                    ?.startsWith('before') ??
                false)) {
          expect(tester.takeException(), isNull);
        } else {
          // Preserve the baseline's real large-text overflow; do not pretend
          // that the previous UI passed this adaptation check.
          while (tester.takeException() != null) {}
        }
        final isBefore = Platform.environment['MULTIBOOK_CAPTURE_PHASE']
                ?.startsWith('before') ??
            false;
        if (!isBefore && scene.startsWith('history-')) {
          final header = tester.widget<SheetHeader>(find.byType(SheetHeader));
          expect(header.subtitle, isNull);
          final modeRect = tester
              .getRect(find.byKey(const ValueKey('book-transactions-mode')));
          final searchRect = tester
              .getRect(find.byKey(const ValueKey('book-transactions-search')));
          expect(searchRect.left, greaterThan(modeRect.right));
          expect(searchRect.center.dy, closeTo(modeRect.center.dy, 1));
          final typeRect = tester.getRect(find.text('全部类型'));
          expect(typeRect.left, closeTo(20, 1));
          for (final key in [
            'book-transactions-kind',
            'book-transactions-date',
          ]) {
            expect(
                find.descendant(
                    of: find.byKey(ValueKey(key)),
                    matching: find.byIcon(Icons.keyboard_arrow_down_rounded)),
                findsOneWidget);
          }
          expect(find.byType(TxDayCard), findsWidgets);
          expect(find.byType(TxRow), findsWidgets);
          expect(find.byType(TxDismissibleRow), findsNothing,
              reason: '批量选择不能触发编辑或侧滑删除');
          expect(find.textContaining('不会复制账单'), findsNothing);
          expect(find.textContaining('仅解除当前账本关联'), findsNothing);
          final status = find.byKey(const ValueKey('book-transactions-status'));
          if (scene == 'history-filtered') {
            expect(find.text('筛选出 2 笔'), findsOneWidget);
            expect(find.textContaining('已选'), findsNothing);
          } else if (scene == 'history-selected') {
            expect(find.text('已选 1 笔'), findsOneWidget);
            expect(find.textContaining('筛选出'), findsNothing);
          } else {
            expect(status, findsNothing, reason: '初始状态不能显示零勾选或未经筛选的结果数');
          }
          if (!large) {
            final kindRect = tester
                .getRect(find.byKey(const ValueKey('book-transactions-kind')));
            final allRect = tester.getRect(
                find.byKey(const ValueKey('book-transactions-select-all')));
            expect(allRect.center.dy, closeTo(kindRect.center.dy, 1));
            if (status.evaluate().isNotEmpty) {
              final statusRect = tester.getRect(status);
              expect(statusRect.center.dy, closeTo(kindRect.center.dy, 1));
              expect(statusRect.right, lessThanOrEqualTo(allRect.left - 8));
            }
          }
        }
        if (!isBefore && scene == 'book-select') {
          expect(find.textContaining('可同时选择多个账本'), findsNothing);
          expect(
              find.byKey(const ValueKey('book-picker-menu')), findsOneWidget);
          expect(find.byType(SheetHeader), findsNothing);
          expect(find.text('确定'), findsNothing);
          expect(
              tester
                  .getSize(find.byKey(const ValueKey('book-picker-menu')))
                  .width,
              lessThanOrEqualTo(196));
        }
        if (!isBefore && (scene == 'entry-books' || scene == 'entry-tags')) {
          final bookMenu = scene == 'entry-books';
          final menu = tester.getRect(find.byKey(
              ValueKey(bookMenu ? 'book-picker-menu' : 'tag-picker-menu')));
          final chip = tester.getRect(find.byKey(
              ValueKey(bookMenu ? 'manual-book-chip' : 'manual-tag-chip')));
          expect(menu.width, lessThanOrEqualTo(196));
          expect(menu.left, greaterThanOrEqualTo(8));
          expect(menu.right,
              lessThanOrEqualTo(tester.view.physicalSize.width - 8));
          expect(menu.top >= chip.bottom || menu.bottom <= chip.top, isTrue,
              reason: '菜单贴着所点芯片展开，不再成为居中或底部弹层');
          expect(find.byType(AppMenuScrim), findsOneWidget);
          final highlight = tester
              .widget<AppMenuScrim>(find.byType(AppMenuScrim))
              .highlightRect;
          expect(highlight.center.dx, closeTo(chip.center.dx, 2),
              reason: '遮罩必须高亮实际所点芯片');
        }
        if (!isBefore &&
            !scene.startsWith('entry-') &&
            scene != 'book-select') {
          final headerFinder = find.byType(SheetHeader).last;
          final header = tester.widget<SheetHeader>(headerFinder);
          final titleRect = tester.getRect(find
              .descendant(of: headerFinder, matching: find.text(header.title))
              .first);
          final actionRect = tester.getRect(find
              .descendant(
                  of: headerFinder, matching: find.text(header.actionLabel!))
              .last);
          expect(titleRect.right, lessThanOrEqualTo(actionRect.left - 4),
              reason: '弹层标题不能与右侧操作重叠');
        }
        if (!isBefore && scene == 'entry-edit') {
          final segment = find
              .byWidgetPredicate((w) => w is SlidingSegment<TransactionKind>);
          final segmentRect = tester.getRect(segment);
          for (final label in ['支出', '收入']) {
            final textRect = tester.getRect(
                find.descendant(of: segment, matching: find.text(label)));
            expect(textRect.top, greaterThanOrEqualTo(segmentRect.top));
            expect(textRect.bottom, lessThanOrEqualTo(segmentRect.bottom));
          }
        }
        final phase = Platform.environment['MULTIBOOK_CAPTURE_PHASE'];
        if (phase != null) {
          final boundary = tester
              .renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 3);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final directory =
                Platform.environment['MULTIBOOK_CAPTURE_DIRECTORY'] ??
                    'outputs/ui_comparisons/2026-10-23-multibook';
            final file = File('$directory/'
                '${scene}_${variant}_$phase.png');
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }
  }

  for (final dismissal in ['遮罩', '返回']) {
    testWidgets('book picker $dismissal keeps draft without writing the ledger',
        (tester) async {
      final fixture = await _fixture(tester);
      final selected = {fixture.business};
      final originalLinks = fixture.repo
          .transactionBookIds(fixture.repo.allTransactions.single)
          .toSet();
      Set<int>? result;
      await _mountPicker(tester, fixture.repo, selected, (value) {
        result = value;
      });
      await tester.tap(find.text('项目 A'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('book-picker-menu')), findsOneWidget,
          reason: '多选过程中不能立即关闭弹窗');
      expect(selected, {fixture.business});
      switch (dismissal) {
        case '遮罩':
          await tester.tapAt(const Offset(8, 8));
        case '返回':
          await tester.binding.handlePopRoute();
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('book-picker-menu')), findsNothing);
      expect(result, {fixture.business, fixture.project});
      expect(selected, {fixture.business});
      expect(
          fixture.repo.transactionBookIds(fixture.repo.allTransactions.single),
          originalLinks);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final clear in [false, true]) {
    testWidgets('book picker toggles ${clear ? 'empty' : 'multiple'} selection',
        (tester) async {
      final fixture = await _fixture(tester);
      Set<int>? result;
      await _mountPicker(tester, fixture.repo, {fixture.business, -1},
          (value) => result = value);
      await tester.tap(find.text(clear ? '生意账本' : '项目 A'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(result, clear ? <int>{} : {fixture.business, fixture.project},
          reason: '空集合表示仅总账本；已删除的账本ID不能被重新提交');
      expect(fixture.repo.allTransactions, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('book picker scrolls long names at 200 percent with keyboard',
      (tester) async {
    final fixture = await _fixture(tester);
    final repo = fixture.repo;
    const lastName = '跨区域经营项目与设备采购专用账本';
    late int lastId;
    await tester.runAsync(() async {
      for (var index = 0; index < 12; index++) {
        await repo.addBook(name: '经营项目 $index');
      }
      lastId = await repo.addBook(name: lastName);
    });
    tester.view.physicalSize = const Size(320, 852);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    Set<int>? result;
    await _mountPicker(tester, repo, {}, (value) => result = value, scale: 2);
    final scrollable = find.descendant(
        of: find.byKey(const ValueKey('book-picker-menu')),
        matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(find.text(lastName), 180,
        scrollable: scrollable);
    await tester.tap(find.text(lastName));
    await tester.pumpAndSettle();
    final card = tester.getRect(find.byKey(const ValueKey('book-picker-menu')));
    expect(card.bottom, lessThanOrEqualTo(852 - 320 - 8));
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(result, {lastId});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('edit selects multiple books and saves the same transaction once',
      (tester) async {
    final fixture = await _fixture(tester);
    final repo = fixture.repo;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: repo,
      child: MaterialApp(
          home: Builder(
              builder: (context) => TextButton(
                  onPressed: () => showManualAddSheet(context,
                      edit: repo.allTransactions.single),
                  child: const Text('编辑')))),
    ));
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('生意账本'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('book-picker-menu')),
        matching: find.text('项目 A')));
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('book-picker-menu')),
            matching: find.text('总账本')),
        findsNothing);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.text('2 个账本'), findsOneWidget);
    final note = find.byKey(const ValueKey('manual-note-field'));
    await tester.tap(note);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _waitFor(
        tester,
        () => repo
            .transactionBookIds(repo.allTransactions.single)
            .contains(fixture.project));
    expect(repo.allTransactions, hasLength(1));
    expect(repo.transactionBookIds(repo.allTransactions.single),
        containsAll([fixture.business, fixture.project]));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('tag menu toggles drafts, reopens and cancels without saving',
      (tester) async {
    final fixture = await _fixture(tester);
    final repo = fixture.repo;
    await tester.runAsync(() async {
      await repo.addTag(name: '工作', colorValue: 0xff81929b);
      await repo.addTag(name: '旅行', colorValue: 0xff81929b);
    });
    await _mountEditor(tester, repo);
    await _openTagMenu(tester);
    await tester.tap(find.text('工作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('旅行'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tag-picker-menu')), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
    final highlight =
        tester.widget<AppMenuScrim>(find.byType(AppMenuScrim)).highlightRect;
    final chip = tester.getRect(find.byKey(const ValueKey('manual-tag-chip')));
    expect(highlight.center.dx, closeTo(chip.center.dx, 2),
        reason: '多选期间保持芯片尺寸稳定，不能让高亮漂移到相邻入口');
    expect(repo.allTransactions.single.tagIds, isEmpty);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.text('2 个标签'), findsOneWidget);
    await _openTagMenu(tester);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
    await tester.tap(find.text('工作'));
    await tester.tap(find.text('旅行'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    await tester.tap(find.text('工作'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('1 个标签'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(repo.allTransactions.single.tagIds, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('empty tag menu creates a tag then saves on the original entry',
      (tester) async {
    final fixture = await _fixture(tester);
    final repo = fixture.repo;
    await _mountEditor(tester, repo);
    await _openTagMenu(tester);
    await tester.tap(find.text('新建标签'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '采购');
    await tester.tap(find.text('创建'));
    await _waitFor(tester, () => repo.tags.any((tag) => tag.name == '采购'));
    await tester.pumpAndSettle();
    expect(find.text('1 个标签'), findsOneWidget);
    expect(repo.allTransactions.single.tagIds, isEmpty);
    await _openTagMenu(tester);
    expect(find.text('采购'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('manual-note-field')));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _waitFor(tester, () => repo.allTransactions.single.tagIds.isNotEmpty);
    expect(repo.allTransactions, hasLength(1));
    expect(repo.allTransactions.single.tagIds,
        [repo.tags.singleWhere((tag) => tag.name == '采购').id]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('cancelling quick tag creation preserves the empty draft',
      (tester) async {
    final fixture = await _fixture(tester);
    await _mountEditor(tester, fixture.repo);
    await _openTagMenu(tester);
    await tester.tap(find.text('新建标签'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '不保存');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(fixture.repo.tags, isEmpty);
    expect(find.text('标签'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('history search and add/remove change only book links',
      (tester) async {
    final fixture = await _fixture(tester);
    final repo = fixture.repo;
    final account = repo.transactionAccounts.first;
    final beforeBalance = repo.accountBalanceOf(account);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: repo,
      child: MaterialApp(
          home: Builder(
              builder: (context) => Column(children: [
                    TextButton(
                        onPressed: () => showBookTransactionsSheet(context,
                            book: repo.books
                                .firstWhere((b) => b.id == fixture.project)),
                        child: const Text('归集')),
                    TextButton(
                        onPressed: () => showBookTransactionsSheet(context,
                            book: repo.books
                                .firstWhere((b) => b.id == fixture.project),
                            removeOnly: true),
                        child: const Text('管理')),
                  ]))),
    ));
    await tester.tap(find.text('归集'));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('book-transactions-search'));
    await tester.enterText(search, '没有这笔账');
    await tester.pump();
    expect(find.text('项目设备采购'), findsNothing);
    await tester.enterText(search, '设备');
    await tester.pump();
    expect(find.text('项目设备采购'), findsOneWidget);
    await tester.tap(find.byType(AppCheckmark));
    await tester.pump();
    expect(find.text('已选 1 笔'), findsOneWidget);
    expect(find.textContaining('筛选出'), findsNothing);
    await tester.tap(find.text('项目设备采购'));
    await tester.pump();
    expect(find.text('筛选出 1 笔'), findsOneWidget);
    expect(find.textContaining('已选'), findsNothing);
    await tester.tap(find.text('项目设备采购'));
    await tester.pump();
    await tester.tap(find.text('添加'));
    await _waitFor(
        tester,
        () => repo
            .transactionBookIds(repo.allTransactions.single)
            .contains(fixture.project));
    await tester.pumpAndSettle();
    expect(repo.allTransactions, hasLength(1));
    expect(repo.accountBalanceOf(account), beforeBalance);
    await tester.tap(find.text('管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pump();
    await tester.tap(find.text('移出'));
    await _waitFor(
        tester,
        () => !repo
            .transactionBookIds(repo.allTransactions.single)
            .contains(fixture.project));
    await tester.pumpAndSettle();
    expect(repo.allTransactions, hasLength(1));
    expect(repo.transactionBookIds(repo.allTransactions.single),
        contains(fixture.business));
    expect(repo.accountBalanceOf(account), beforeBalance);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('history count follows filters and selection priority',
      (tester) async {
    final fixture = await _fixture(tester);
    final repo = fixture.repo;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: repo,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: BookTransactionsSheet(
              book: repo.books.firstWhere((b) => b.id == fixture.project)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final status = find.byKey(const ValueKey('book-transactions-status'));
    final search = find.byKey(const ValueKey('book-transactions-search'));
    final all = find.byKey(const ValueKey('book-transactions-select-all'));
    final kind = find.byKey(const ValueKey('book-transactions-kind'));
    expect(status, findsNothing);
    await tester.enterText(search, '   ');
    await tester.pump();
    expect(status, findsNothing, reason: '纯空格不是有效搜索条件');
    await tester.enterText(search, '找不到');
    await tester.pump();
    expect(find.text('筛选出 0 笔'), findsOneWidget);
    expect(tester.widget<TextButton>(all).onPressed, isNull);
    await tester.tap(find.byTooltip('清除筛选'));
    await tester.pumpAndSettle();
    expect(status, findsNothing);
    await tester.tap(kind);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '实际打开类型菜单，不能漏传公共菜单必需的图标');
    await tester.tap(find.text('支出'));
    await tester.pumpAndSettle();
    expect(find.text('筛选出 1 笔'), findsOneWidget);
    await tester.tap(all);
    await tester.pumpAndSettle();
    expect(find.text('已选 1 笔'), findsOneWidget);
    expect(find.textContaining('筛选出'), findsNothing);
    await tester.enterText(search, '找不到');
    await tester.pump();
    expect(find.text('已选 1 笔'), findsOneWidget, reason: '筛选暂时隐藏已选账单时仍保留勾选数');
    await tester.tap(find.byTooltip('清除筛选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 笔'), findsOneWidget, reason: '清除筛选不能清除勾选');
    await tester.tap(all);
    await tester.pumpAndSettle();
    expect(status, findsNothing);
    expect(find.text('全选'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('history shows cross-book refund net and day total',
      (tester) async {
    final fixture = await _fixture(tester);
    final repo = fixture.repo;
    final root = repo.allTransactions.single;
    await tester.runAsync(() async {
      await repo.refundTransaction(root, Decimal.fromInt(30),
          settledAt: root.date,
          settlementAccountId: repo.transactionAccounts.first.id);
      await repo.switchBook(fixture.project);
    });
    expect(repo.transactions, isEmpty);
    expect(repo.userAmountAcrossBooks(root), Decimal.fromInt(70));
    await tester.pumpWidget(ChangeNotifierProvider<AppRepository>.value(
      value: repo,
      child: MaterialApp(
        home: Scaffold(
          body: BookTransactionsSheet(
              book: repo.books.firstWhere((b) => b.id == fixture.project)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(TxRow), findsOneWidget,
        reason: '附着退款只能跟原账展示，不能作为另一笔待归集账单');
    expect(find.text('已退 ¥30.00'), findsOneWidget);
    expect(find.text('-¥70.00'), findsOneWidget);
    expect(find.text('支 70.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('history waits for the complete startup snapshot',
      (tester) async {
    final repo = _DeferredHistoryRepository();
    final fixture = await _fixture(tester, repository: repo);
    final loading = Completer<void>();
    repo.deferHistory = true;
    repo.onHydrate = () => loading.future;
    await tester.pumpWidget(ChangeNotifierProvider<AppRepository>.value(
      value: repo,
      child: MaterialApp(
        home: Scaffold(
          body: BookTransactionsSheet(
              book: repo.books.firstWhere((b) => b.id == fixture.project)),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('正在加载完整账单…'), findsOneWidget);
    expect(find.text('项目设备采购'), findsNothing);
    expect(find.text('全选'), findsNothing);
    loading.complete();
    await _waitFor(tester, () => repo.isFullyReady);
    await tester.pumpAndSettle();
    expect(find.text('项目设备采购'), findsOneWidget);
    expect(find.text('正在加载完整账单…'), findsNothing);
    expect(repo.hydrateAttempts, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
      'history hydration failure can retry without exposing partial data',
      (tester) async {
    final repo = _DeferredHistoryRepository();
    final fixture = await _fixture(tester, repository: repo);
    repo.deferHistory = true;
    repo.onHydrate = () async => throw StateError('模拟历史加载失败');
    await tester.pumpWidget(ChangeNotifierProvider<AppRepository>.value(
      value: repo,
      child: MaterialApp(
        home: Scaffold(
          body: BookTransactionsSheet(
              book: repo.books.firstWhere((b) => b.id == fixture.project)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('历史账单加载失败，请重试'), findsOneWidget);
    expect(find.text('项目设备采购'), findsNothing);
    expect(find.text('全选'), findsNothing);
    repo.onHydrate = () async {};
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('项目设备采购'), findsOneWidget);
    expect(find.text('历史账单加载失败，请重试'), findsNothing);
    expect(repo.hydrateAttempts, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}

Future<void> _mountPicker(
  WidgetTester tester,
  AppRepository repo,
  Set<int> selected,
  void Function(Set<int>?) onResult, {
  double scale = 1,
}) async {
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: repo,
    child: MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showTransactionBooksMenu(context,
                selectedIds: selected, onChanged: onResult),
            child: const Text('打开选择器'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('打开选择器'));
  await tester.pumpAndSettle();
}

Future<void> _mountEditor(WidgetTester tester, AppRepository repo) async {
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: repo,
    child: MaterialApp(
      home: Builder(
          builder: (context) => TextButton(
                onPressed: () => showManualAddSheet(context,
                    edit: repo.allTransactions.single),
                child: const Text('编辑'),
              )),
    ),
  ));
  await tester.tap(find.text('编辑'));
  await tester.pumpAndSettle();
}

Future<void> _openTagMenu(WidgetTester tester) async {
  final chip = find.byKey(const ValueKey('manual-tag-chip'));
  for (var attempt = 0; chip.evaluate().isEmpty && attempt < 6; attempt++) {
    await tester.drag(
        find.byWidgetPredicate(
            (w) => w is ListView && w.scrollDirection == Axis.horizontal),
        const Offset(-160, 0));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

class _DeferredHistoryRepository extends AppRepository {
  bool deferHistory = false;
  int hydrateAttempts = 0;
  Future<void> Function()? onHydrate;

  @override
  bool get isFullyReady => !deferHistory && super.isFullyReady;

  @override
  Future<void> finishDeferredInitialization() async {
    hydrateAttempts++;
    await onHydrate?.call();
    deferHistory = false;
  }
}

Future<void> _loadEmojiFont() async {
  final configuredPath = Platform.environment['FEIMIAO_EMOJI_FONT'];
  final candidates = <String>[
    if (configuredPath != null) configuredPath,
    '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf',
    '/usr/share/fonts/noto/NotoColorEmoji.ttf',
    if (Platform.environment['WINDIR'] case final String windows)
      '$windows/Fonts/seguiemj.ttf',
    '/System/Library/Fonts/Apple Color Emoji.ttc',
    // CI 的 Linux 镜像不一定装了系统 emoji 字体，用 SDK 自带的同一份兜底。
    flutterSdkEmojiFontPath(),
  ];
  // An explicit font must be honored rather than silently changing the
  // comparison baseline. Otherwise use a platform's installed emoji font.
  final paths = configuredPath == null ? candidates : [configuredPath];
  final emoji =
      paths.map(File.new).where((file) => file.existsSync()).firstOrNull;
  if (emoji == null) {
    throw StateError('截图需要 Emoji 字体，请设置 FEIMIAO_EMOJI_FONT。');
  }
  await (FontLoader('NotoColorEmoji')
        ..addFont(Future.value(ByteData.sublistView(emoji.readAsBytesSync()))))
      .load();
}

Future<({AppRepository repo, int business, int project})> _fixture(
  WidgetTester tester, {
  AppRepository? repository,
}) async {
  tester.view.physicalSize = const Size(430, 920);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final dir = Directory.systemTemp.createTempSync('multibook-flow-');
  final repo = repository ?? AppRepository();
  late int business, project;
  await tester.runAsync(() async {
    await databaseFactory.setDatabasesPath(dir.path);
    await repo.init();
    business = await repo.addBook(name: '生意账本');
    project = await repo.addBook(name: '项目 A');
    await repo.switchBook(business);
    await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(100),
        categoryId: repo.categories.first.id,
        accountId: repo.transactionAccounts.first.id,
        note: '项目设备采购',
        date: DateTime(2026, 10, 22),
        bookIds: [business]);
  });
  addTearDown(() => tester.runAsync(() async {
        await repo.closeForTest();
        dir.deleteSync(recursive: true);
      }));
  return (repo: repo, business: business, project: project);
}

Future<void> _waitFor(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 500 && !done(); attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue, reason: '账本关联应在写库完成后生效');
}
