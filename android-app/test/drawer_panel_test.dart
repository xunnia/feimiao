import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/budget/budget_window_resolver.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/main.dart' as app;
import 'package:qingji/theme/app_theme_controller.dart';
import 'package:qingji/theme/app_tokens.dart';
import 'package:qingji/widgets/app_buttons.dart';
import 'package:qingji/widgets/app_line_icon.dart';
import 'package:qingji/widgets/book_switch_chip.dart';

class _DrawerRepo extends AppRepository {
  _DrawerRepo({this.nickname = ''});

  final String nickname;

  @override
  String get profileNickname => nickname;

  static const _books = [
    BookEntity(id: 1, name: '总账本', icon: '📒'),
    BookEntity(id: 2, name: '旅行', icon: '✈️', starred: true),
  ];

  @override
  List<BookEntity> get books => _books;

  @override
  int get currentBookId => 1;

  @override
  int get defaultBookId => 1;

  // 夹具只覆盖了 currentBookId 的 getter，仓库内部 id 仍是 0；预算查询
  // 要求正数 id，这里显式带上夹具账本。
  @override
  BudgetWindowResult budgetForCalendarMonth(
    DateTime month, {
    int? bookId,
    DateTime? asOf,
    DateTime? knowledgeCutoff,
  }) =>
      super.budgetForCalendarMonth(
        month,
        bookId: bookId ?? 1,
        asOf: asOf,
        knowledgeCutoff: knowledgeCutoff,
      );
}

Future<void> _pumpOpenDrawer(WidgetTester tester, {String nickname = ''}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppRepository>.value(
            value: _DrawerRepo(nickname: nickname)),
        ChangeNotifierProvider<AppThemeController>.value(
          value: AppThemeController.instance,
        ),
      ],
      child: const app.QingJiApp(),
    ),
  );
  await tester.pump();
  await tester.tap(find.byType(AppDrawerButton));
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
}

Future<void> _disposeShell(WidgetTester tester) async {
  // RootShell 会排一个 4 秒后的静默更新检查，拆掉页面并推进假时钟收尾。
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 4));
}

void main() {
  testWidgets('抽屉不混用粗 Material 图标，账本 ⋯ 热区够 48', (tester) async {
    await _pumpOpenDrawer(tester);

    expect(find.text('我的账本'), findsOneWidget);
    expect(find.text('更多'), findsOneWidget);
    // 「更多」、账本 ⋯、加星标记都改用细线图标。
    expect(find.byIcon(Icons.more_horiz), findsNothing);
    expect(find.byIcon(Icons.star_rounded), findsNothing);

    final more = find.bySemanticsLabel('旅行更多操作');
    expect(more, findsOneWidget);
    final size = tester.getSize(more);
    expect(size.width, greaterThanOrEqualTo(AppHitTarget.min));
    expect(size.height, greaterThanOrEqualTo(AppHitTarget.min));

    await _disposeShell(tester);
  });

  testWidgets('抽屉左下角是「头像 + 昵称」进设置，新建账本在右边', (tester) async {
    await _pumpOpenDrawer(tester, nickname: '肥喵主人');

    final entry = find.byKey(const ValueKey('drawer-profile-entry'));
    expect(entry, findsOneWidget);
    expect(
      find.descendant(of: entry, matching: find.text('肥喵主人')),
      findsOneWidget,
    );
    final newBook = find.text('新建账本');
    expect(newBook, findsOneWidget);
    expect(tester.getCenter(entry).dx, lessThan(tester.getCenter(newBook).dx));
    // 原来的齿轮按钮去掉了，设置只从头像昵称进。
    expect(
      find.byWidgetPredicate(
          (w) => w is AppLineIcon && w.data == AppLineIcons.settings),
      findsNothing,
    );

    await tester.tap(entry);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(find.text('记忆'), findsOneWidget);
    expect(find.text('定时报表'), findsOneWidget);

    await _disposeShell(tester);
  });

  testWidgets('没设昵称时抽屉左下角显示「设置」', (tester) async {
    await _pumpOpenDrawer(tester);
    final entry = find.byKey(const ValueKey('drawer-profile-entry'));
    expect(
      find.descendant(of: entry, matching: find.text('设置')),
      findsOneWidget,
    );
    await _disposeShell(tester);
  });

  testWidgets('账本菜单只留加星/编辑/删除，改名并入编辑', (tester) async {
    await _pumpOpenDrawer(tester);

    await tester.tap(find.bySemanticsLabel('旅行更多操作'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    expect(find.text('取消加星'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(find.text('改名'), findsNothing);

    await _disposeShell(tester);
  });

  testWidgets('顶栏账本快切菜单用统一选中态，不再用粗圆圈', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppRepository>.value(value: _DrawerRepo()),
          ChangeNotifierProvider<AppThemeController>.value(
            value: AppThemeController.instance,
          ),
        ],
        child: const app.QingJiApp(),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(AppBookSwitchChip));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    expect(find.text('📒 总账本'), findsOneWidget);
    expect(find.text('✈️ 旅行'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
    // 当前账本一行带统一菜单件的对勾。
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await _disposeShell(tester);
  });
}
