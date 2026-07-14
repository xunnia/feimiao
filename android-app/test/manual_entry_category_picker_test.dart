import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/views/common/category_picker_sheet.dart';
import 'package:qingji/views/home/manual_add_sheet.dart';
import 'package:qingji/views/quick_add/amount_keypad.dart';
import 'package:qingji/views/quick_add/category_grid.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDirectory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDirectory = Directory.systemTemp.createTempSync('manual_entry_test_');
    await databaseFactory.setDatabasesPath(tempDirectory.path);
  });

  tearDown(() {
    if (tempDirectory.existsSync()) {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  testWidgets('manual note requests done and invalid submit stays in place',
      (tester) async {
    tester.view.physicalSize = const Size(430, 920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = AppRepository();
    await tester.runAsync(() => repository.init());
    addTearDown(() => tester.runAsync(() => repository.closeForTest()));

    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repository,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showManualAddSheet(context),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final noteFinder = find.byKey(const ValueKey('manual-note-field'));
    final field = tester.widget<TextField>(noteFinder);
    expect(field.textInputAction, TextInputAction.done);
    expect(field.maxLines, 1);
    expect(field.onSubmitted, isNotNull);

    await tester.tap(noteFinder);
    await tester.enterText(noteFinder, '没有金额');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(repository.allRecords, isEmpty);
    expect(find.byType(ManualAddSheet), findsOneWidget);
    expect(tester.widget<TextField>(noteFinder).focusNode?.hasFocus, isTrue);
    expect(find.byType(AmountKeypad), findsNothing);
  });

  testWidgets('manual note done saves through the normal completion path',
      (tester) async {
    tester.view.physicalSize = const Size(430, 920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = AppRepository();
    await tester.runAsync(() => repository.init());
    addTearDown(() => tester.runAsync(() => repository.closeForTest()));
    final navigatorObserver = _PopObserver();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repository,
        child: MaterialApp(
          navigatorObservers: [navigatorObserver],
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showManualAddSheet(context),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(of: find.byType(AmountKeypad), matching: find.text('1')),
    );
    await tester.pump();
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('manual-amount-display')),
          )
          .data,
      '1',
    );
    final noteFinder = find.byKey(const ValueKey('manual-note-field'));
    await tester.tap(noteFinder);
    await tester.enterText(noteFinder, '完成键保存');
    final submittedAfter = DateTime.now();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    for (var attempt = 0;
        attempt < 500 && !navigatorObserver.popped.isCompleted;
        attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    if (!navigatorObserver.popped.isCompleted) {
      throw TestFailure(
        'done did not reach Navigator.pop; records=${repository.allRecords.length}',
      );
    }
    expect(repository.allRecords, hasLength(1));
    await tester.pumpAndSettle();

    expect(find.byType(ManualAddSheet), findsNothing);
    expect(repository.allRecords.single.note, '完成键保存');
    expect(repository.allRecords.single.amount.toString(), '1');
    expect(
      repository.allRecords.single.date
          .isBefore(submittedAfter.subtract(const Duration(seconds: 1))),
      isFalse,
    );
    expect(
      repository.allRecords.single.date
          .isAfter(DateTime.now().add(const Duration(seconds: 1))),
      isFalse,
    );
  });

  testWidgets('hierarchical picker expands children below their parent row',
      (tester) async {
    const food = CategoryEntity(
      id: 1,
      key: 'food',
      nameZh: '食品',
      nameEn: 'Food',
      kindRaw: 'expense',
    );
    const shopping = CategoryEntity(
      id: 2,
      key: 'shopping',
      nameZh: '购物',
      nameEn: 'Shopping',
      kindRaw: 'expense',
    );
    const dining = CategoryEntity(
      id: 3,
      key: 'dining',
      nameZh: '餐饮',
      nameEn: 'Dining',
      kindRaw: 'expense',
      parentId: 1,
    );

    int? selectedId;
    int? expandedId;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 360,
                child: HierarchicalCategoryPicker(
                  categories: const [food, shopping],
                  children: expandedId == food.id ? const [dining] : const [],
                  selectedId: selectedId,
                  selectedParentId:
                      selectedId == dining.id ? food.id : selectedId,
                  expandedParentId: expandedId,
                  expandableIds: const {1},
                  subLabels:
                      selectedId == dining.id ? const {1: '餐饮'} : const {},
                  onParentSelected: (category) => setState(() {
                    selectedId = category.id;
                    expandedId = expandedId == category.id ? null : category.id;
                  }),
                  onChildSelected: (category) => setState(() {
                    selectedId = category.id;
                    expandedId = null;
                  }),
                  onClosePanel: () => setState(() => expandedId = null),
                  obscuredChild: const SizedBox(
                    key: ValueKey('content-under-picker'),
                    height: 180,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final parentFinder = find.byKey(const ValueKey('category-parent-1'));
    expect(
      find.descendant(
        of: parentFinder,
        matching: find.byIcon(Icons.keyboard_arrow_down),
      ),
      findsOneWidget,
    );

    await tester.tap(parentFinder);
    await tester.pumpAndSettle();

    final panelFinder = find.byKey(const ValueKey('subcategory-panel'));
    expect(panelFinder, findsOneWidget);
    expect(
      tester.getTopLeft(panelFinder).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(parentFinder).dy),
    );
    expect(find.byType(ImageFiltered), findsWidgets);
    expect(
      find.descendant(
        of: parentFinder,
        matching: find.byIcon(Icons.keyboard_arrow_up),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('category-child-3')));
    await tester.pumpAndSettle();

    expect(selectedId, dining.id);
    expect(expandedId, isNull);
    expect(panelFinder, findsNothing);
    expect(find.text('食品·餐饮'), findsOneWidget);
  });

  testWidgets('shared picker restores an existing child selection expanded',
      (tester) async {
    tester.view.physicalSize = const Size(430, 920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = AppRepository();
    await tester.runAsync(() => repository.init());
    addTearDown(() => tester.runAsync(() => repository.closeForTest()));
    final child = repository.categories.firstWhere(
      (category) => category.parentId != null && !category.hidden,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repository,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCategoryPickerSheet(
                context,
                kind: child.kind,
                selectedId: child.id,
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final parentFinder =
        find.byKey(ValueKey('category-parent-${child.parentId}'));
    expect(find.byKey(const ValueKey('subcategory-panel')), findsOneWidget);
    expect(find.byKey(ValueKey('category-child-${child.id}')), findsOneWidget);
    expect(
      find.descendant(
        of: parentFinder,
        matching: find.byIcon(Icons.keyboard_arrow_up),
      ),
      findsOneWidget,
    );
  });
}

class _PopObserver extends NavigatorObserver {
  final Completer<void> popped = Completer<void>();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!popped.isCompleted) popped.complete();
    super.didPop(route, previousRoute);
  }
}
