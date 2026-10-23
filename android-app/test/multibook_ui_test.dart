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
import 'package:qingji/widgets/settings_ui.dart';
import 'package:qingji/widgets/sliding_segment.dart';
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
    if (!(Platform.environment['MULTIBOOK_CAPTURE_PHASE']
            ?.startsWith('before') ??
        false)) ...[
      'book-select',
      'history-add',
      'history-remove',
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
                          showTransactionBooksSheet(context,
                              selectedIds: [business]);
                        } else if (scene.startsWith('history-')) {
                          showBookTransactionsSheet(context,
                              book: repo.books.firstWhere((b) =>
                                  b.name ==
                                  (scene == 'history-add' ? '项目 A' : '生意账本')),
                              removeOnly: scene == 'history-remove');
                        } else if (scene == 'entry-edit') {
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
        if (!isBefore && scene != 'entry-edit') {
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
            final file = File('outputs/ui_comparisons/2026-10-23-multibook/'
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
        of: find.byType(TransactionBooksSheet), matching: find.text('项目 A')));
    expect(
        find.descendant(
            of: find.byType(TransactionBooksSheet), matching: find.text('总账本')),
        findsNothing);
    await tester.tap(find.text('确定'));
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
    await tester.tap(find.text('全选'));
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
