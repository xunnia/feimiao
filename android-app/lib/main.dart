import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/auto_record.dart';
import 'core/ai/report_task_scheduler.dart';
import 'core/haptics.dart';
import 'core/widgets/widget_snapshot_service.dart';
import 'data/app_repository.dart';
import 'share_intake.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme_controller.dart';
import 'views/auto_record/auto_record_sheet.dart';
import 'widgets/app_buttons.dart';
import 'widgets/app_line_icon.dart';
import 'widgets/app_toast.dart';
import 'widgets/book_switch_chip.dart';
import 'widgets/glass.dart';
import 'widgets/pressable_scale.dart';
import 'widgets/slidable_tracker.dart';
import 'widgets/ios_dialogs.dart';
import 'widgets/ios_form.dart';
import 'widgets/ios_menu.dart';
import 'views/books/book_sheet.dart';
import 'views/home/ai_chat_panel.dart';
import 'views/home/home_view.dart';
import 'views/home/manual_add_sheet.dart';
import 'views/home/record_input_bar.dart';
import 'views/savings/savings_goals_view.dart';
import 'views/search/search_view.dart';
import 'views/settings/accounts_view.dart';
import 'views/settings/auto_record_setting_view.dart';
import 'views/settings/budget_setting_view.dart';
import 'views/settings/recurring_view.dart';
import 'views/settings/categories_view.dart';
import 'views/settings/import_export_view.dart';
import 'views/settings/app_update_flow.dart';
import 'views/settings/settings_view.dart';
import 'views/settings/tags_view.dart';
import 'views/statistics/statistics_view.dart';
import 'views/transactions/reimburse_view.dart';
import 'views/transactions/transaction_list_view.dart';
import 'widgets/app_page_route.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  final repo = AppRepository();
  await repo.init();
  await ReportTaskScheduler.initialize();
  await ReportTaskScheduler.reschedulePending(repo);
  WidgetSnapshotService.instance.attach(repo);
  // 主题偏好要在首帧前灌进 AppColors，否则会闪一下默认暖橙再切换。
  await AppThemeController.instance.load();

  ShareIntake.init(); // 「分享到肥喵」：监听系统分享，自动记账
  _autoRecordWatcher.start(); // 自动记账：回到 App 时读取通知队列、弹确认表

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppRepository>.value(value: repo),
        ChangeNotifierProvider<AppThemeController>.value(
            value: AppThemeController.instance),
      ],
      child: const QingJiApp(),
    ),
  );
}

/// 自动记账巡查：App 首帧后与每次回到前台时读取支付通知，用户明确处理后
/// 才从原生队列删除。用全局 navigatorKey 弹层。
class _AutoRecordWatcher with WidgetsBindingObserver {
  bool _busy = false;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _run();
  }

  Future<void> _run() async {
    if (_busy) return;
    _busy = true;
    try {
      final items = await AutoRecord.pending();
      if (items.isEmpty) return;
      final ctx = ShareIntake.navigatorKey.currentContext;
      if (ctx == null) return;
      if (!ctx.mounted) return;
      final handledIds = await showAutoRecordSheet(ctx, items);
      if (handledIds != null && handledIds.isNotEmpty) {
        await AutoRecord.acknowledgeIds(handledIds);
      }
    } catch (_) {
    } finally {
      _busy = false;
    }
  }
}

final _autoRecordWatcher = _AutoRecordWatcher();

class QingJiApp extends StatelessWidget {
  const QingJiApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 主题一变（色卡/滑杆/极简）整棵树重建；暮夜色卡强制深色。
    final appTheme = context.watch<AppThemeController>();
    return MaterialApp(
      title: '肥喵记账',
      debugShowCheckedModeBanner: false,
      navigatorKey: ShareIntake.navigatorKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: appTheme.forceDark ? ThemeMode.dark : ThemeMode.system,
      // 暖渐变背景由转场器按路由注入（app_colors.dart 的
      // _GradientCupertinoTransitionsBuilder）：每页自带不透明渐变底，
      // 转场不透视、合成器按不透明页优化，不在这里全局铺。
      home: const RootShell(),
    );
  }
}

/// 新主框架（对齐 iOS Claude 的抽屉分层）：
/// 抽屉固定在最底层，主页面像一张卡片被向右推开、露出圆角和阴影；
/// 点右侧余边或往左滑关回来。左缘右滑也可拉开。
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => RootShellState();
}

class RootShellState extends State<RootShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drawerCtl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );

  // 抽屉拖动手势用 Listener 裸指针实现（不进手势竞技场）：
  // 这样在账单行（有左滑操作的 Slidable）上右滑也能拉出抽屉，
  // 而行自己的左滑编辑不受影响——两边永远不打架。
  Offset? _ptrStart;
  bool _ptrDragging = false;
  double _ptrLastX = 0;
  double _ptrLastDx = 0;

  void _openDrawer() => _drawerCtl.animateTo(1, curve: Curves.easeOutCubic);
  void _closeDrawer() => _drawerCtl.animateTo(0, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    // 启动后静默检查更新（延迟几秒别抢首屏；失败/没更新都不打扰）。
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) checkAppUpdate(context, silent: true);
    });
  }

  /// 指针抬起：按最后一段滑动方向（快挥）或当前进度落定开/关。
  void _settlePointerDrag() {
    _ptrStart = null;
    if (!_ptrDragging) return;
    _ptrDragging = false;
    if (_ptrLastDx > 6) {
      _openDrawer();
    } else if (_ptrLastDx < -6) {
      _closeDrawer();
    } else {
      _drawerCtl.value >= 0.5 ? _openDrawer() : _closeDrawer();
    }
  }

  @override
  void dispose() {
    _drawerCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 订阅主题：色卡/滑杆一变整个主框架（背景/卡片/遮罩）立即重绘。
    context.watch<AppThemeController>();
    final scheme = Theme.of(context).colorScheme;
    final screenW = MediaQuery.sizeOf(context).width;
    // 抽屉占 75%（用户 0703：0.82 偏大）。
    final drawerW = (screenW * 0.75).clamp(240.0, 320.0);

    return AnimatedBuilder(
      animation: _drawerCtl,
      child: RepaintBoundary(
        child: _MainScaffold(onMenu: _openDrawer),
      ),
      builder: (context, mainChild) {
        // 主页平移量恒等于进度值（线性）：拖动时 = 手指位移，1:1 跟手不跑手前面；
        // 回弹的缓动交给 _openDrawer/_closeDrawer 的 animateTo(easeOutCubic) 在
        // 时间维度上做，所以既顺滑又不会在松手瞬间跳一下。
        final t = _drawerCtl.value;
        final open = _drawerCtl.value > 0.5;
        return PopScope(
          // 抽屉开着时系统返回键先关抽屉，不退出页面。
          canPop: !open,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _closeDrawer();
          },
          child: Scaffold(
            // 透明：透出路由级暖渐变底（抽屉推开后露出的背景也是渐变）。
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                // ── 底层：抽屉面板（固定不动，主页推开后露出来）──
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: drawerW,
                  child: IgnorePointer(
                    ignoring: _drawerCtl.value < 0.01,
                    child: ExcludeSemantics(
                      excluding: _drawerCtl.value < 0.01,
                      child: _DrawerPanel(
                        onClose: _closeDrawer,
                        closed: _drawerCtl.value < 0.01,
                      ),
                    ),
                  ),
                ),
                // ── 上层：主页面卡片，右移 + 圆角 + 阴影 ──
                // 拖动手势用 Listener 裸指针：不进手势竞技场，所以在账单行
                // （有左滑操作的 Slidable）上右滑也能拉出抽屉，互不打架。
                Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (e) {
                    _ptrStart = e.position;
                    _ptrDragging = false;
                    _ptrLastDx = 0;
                  },
                  onPointerMove: (e) {
                    final start = _ptrStart;
                    if (start == null) return;
                    if (!_ptrDragging) {
                      final total = e.position - start;
                      final open = _drawerCtl.value > 0.01;
                      // 横向位移明显大于纵向才接管，不干扰列表上下滚动；
                      // 关着时只认「向右拖」（左滑仍归账单行的编辑操作）；
                      // 有账单行的操作面板开着时，右滑先让它关面板，不开抽屉。
                      final horizontal = total.dx.abs() > 24 &&
                          total.dx.abs() > total.dy.abs() * 1.6;
                      if (horizontal &&
                          (open
                              ? total.dx < 0
                              : total.dx > 0 && !SlidableTracker.anyOpen)) {
                        _ptrDragging = true;
                        _ptrLastX = e.position.dx;
                      }
                    } else {
                      _drawerCtl.value = (_drawerCtl.value +
                              (e.position.dx - _ptrLastX) / drawerW)
                          .clamp(0.0, 1.0);
                      _ptrLastDx = e.delta.dx;
                      _ptrLastX = e.position.dx;
                    }
                  },
                  onPointerUp: (_) => _settlePointerDrag(),
                  onPointerCancel: (_) => _settlePointerDrag(),
                  child: Transform.translate(
                    offset: Offset(drawerW * t, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26 * t),
                        border: t > 0.01
                            ? Border.all(
                                color: scheme.onSurface.withValues(
                                  alpha: 0.08 * t,
                                ),
                                width: 0.7,
                              )
                            : null,
                        // 向抽屉侧投影，明确区分上下两层页面。
                        boxShadow: t > 0.08
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: 0.14 * t,
                                  ),
                                  blurRadius: 24,
                                  spreadRadius: 1,
                                  offset: const Offset(-4, 0),
                                ),
                              ]
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(26 * t),
                        child: Stack(
                          children: [
                            // 主页卡片自带不透明渐变底：主页 Scaffold 是透明的，
                            // 不垫这层会透出下面的抽屉面板。
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration:
                                    AppColors.pageBackground(scheme.brightness),
                              ),
                            ),
                            mainChild!,
                            // 打开时主页盖轻遮罩，点一下关抽屉。
                            // 拖动中不再做全屏实时模糊，避免右滑抽屉卡顿。
                            if (_drawerCtl.value > 0.01)
                              Positioned.fill(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _closeDrawer,
                                  child: ColoredBox(
                                    color: AppColors.appBg(scheme)
                                        .withValues(alpha: 0.22 * t),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 主页面本体（顶栏 + 账单流 + 底部渐变 + 输入栏）。
class _MainScaffold extends StatefulWidget {
  final VoidCallback onMenu;

  const _MainScaffold({required this.onMenu});

  @override
  State<_MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<_MainScaffold> {
  final GlobalKey _inputKey = GlobalKey();
  double _inputInset = 150;
  bool _measureScheduled = false;

  void _measureInputBar() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      final ctx = _inputKey.currentContext;
      if (ctx == null || !mounted) return;
      final box = ctx.findRenderObject() as RenderBox?;
      final next = box?.size.height;
      if (next == null || next <= 0) return;
      final inset = next + 18;
      if ((inset - _inputInset).abs() > 1) {
        setState(() => _inputInset = inset);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _measureInputBar();
  }

  @override
  Widget build(BuildContext context) {
    _measureInputBar();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      extendBodyBehindAppBar: true,
      // 透明：透出 RootShell 垫的暖渐变底。之前这里画不透明 appBg 灰，
      // 把渐变整个盖住了——主页一直没有主题色的真凶。
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        // 状态栏图标必须跟主题走：深色主题背景近黑，硬编码深色图标
        // 会让时间/电量在深色模式下看不见。
        systemOverlayStyle: scheme.brightness == Brightness.dark
            ? const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarIconBrightness: Brightness.light,
              )
            : const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.dark,
                statusBarBrightness: Brightness.light,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarIconBrightness: Brightness.dark,
              ),
        titleSpacing: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: const _TopFrostedFade(
          blur: 12,
          topAlpha: 0.70,
          midAlpha: 0.24,
          bottomAlpha: 0.0,
        ),
        title: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: _MenuGlyphButton(onTap: widget.onMenu),
            ),
            const Spacer(),
            // 搜索（在账本左边）
            const _SearchIconButton(),
            const SizedBox(width: 8),
            // 当前账本快切（最右）
            const _BookSwitchChip(),
            const SizedBox(width: 12),
          ],
        ),
      ),
      // 输入栏悬浮在列表之上：只有那张圆角卡片本身遮挡列表，
      // 卡片外的透明边距让后面的账单透出来（不再整条“一刀切”遮挡）。
      body: Stack(
        children: [
          Positioned.fill(
            child: HomeView(
              bottomInset: _inputInset,
              onShowTransactions: () => Navigator.push<void>(
                context,
                AppPageRoute<void>(builder: (_) => const TransactionListView()),
              ),
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 150,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.appBg(scheme).withValues(alpha: 0.0),
                      AppColors.appBg(scheme).withValues(alpha: 0.85),
                      AppColors.appBg(scheme),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // 底部渐变过渡（对标 Telegram 聊天底部）：列表内容滑到输入栏后面时
          // 渐渐隐入背景色，而不是被“一刀切”遮住。不拦截点击。
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: NotificationListener<SizeChangedLayoutNotification>(
              onNotification: (_) {
                _measureInputBar();
                return false;
              },
              child: SizeChangedLayoutNotifier(
                child: RecordInputBar(key: _inputKey),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopFrostedFade extends StatelessWidget {
  final double blur;
  final double topAlpha;
  final double midAlpha;
  final double bottomAlpha;

  const _TopFrostedFade({
    required this.blur,
    required this.topAlpha,
    required this.midAlpha,
    required this.bottomAlpha,
  });

  @override
  Widget build(BuildContext context) {
    final bg = AppColors.topFrostTint(Theme.of(context).colorScheme);
    return ClipRect(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0.0, 0.46, 1.0],
        ).createShader(bounds),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  bg.withValues(alpha: topAlpha),
                  bg.withValues(alpha: midAlpha),
                  bg.withValues(alpha: bottomAlpha),
                ],
                stops: const [0.0, 0.58, 1.0],
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 左侧抽屉面板（对齐 iOS Claude：主页推开后露出，功能项可长按拖动排序）
// ---------------------------------------------------------------------------

/// 抽屉功能项注册表：key 用于持久化排序，别改已有 key。
class _DrawerFn {
  final String key;
  final AppLineIconData icon;
  final String label;

  const _DrawerFn(this.key, this.icon, this.label);
}

const List<_DrawerFn> _kDrawerFns = [
  _DrawerFn('stats', AppLineIcons.chart, '统计数据'),
  _DrawerFn('assets', AppLineIcons.wallet, '资产管理'),
  _DrawerFn('budget', AppLineIcons.calendar, '预算管理'),
  _DrawerFn('savings', AppLineIcons.savings, '存钱目标'),
  _DrawerFn('assistant', AppLineIcons.sparkles, '喵助手'),
  _DrawerFn('categories', AppLineIcons.grid, '分类管理'),
  _DrawerFn('tags', AppLineIcons.tag, '标签管理'),
  _DrawerFn('import', AppLineIcons.importExport, '导入导出'),
  _DrawerFn('reimburse', AppLineIcons.receipt, '待报销'),
  _DrawerFn('recurring', AppLineIcons.calendarClock, '定时记账'),
  _DrawerFn('autorecord', AppLineIcons.bell, '自动记账'),
];

class _DrawerPanel extends StatefulWidget {
  /// 关抽屉（收回主页面卡片）。
  final VoidCallback onClose;

  /// 抽屉是否已完全关闭。面板常驻不销毁，关上时用它把「更多」折叠态收回去。
  final bool closed;

  const _DrawerPanel({required this.onClose, required this.closed});

  @override
  State<_DrawerPanel> createState() => _DrawerPanelState();
}

class _DrawerPanelState extends State<_DrawerPanel> {
  /// 「更多」折叠：默认只露前 5 个功能项，展开后全部可见（都可长按拖动排序）。
  bool _moreExpanded = false;

  @override
  void didUpdateWidget(_DrawerPanel old) {
    super.didUpdateWidget(old);
    // 抽屉刚关上（含点功能项跳页时的关闭）→ 收回「更多」，下次打开是折叠态。
    if (widget.closed && !old.closed && _moreExpanded) {
      _moreExpanded = false;
    }
  }

  void _popAndPush(Widget page) {
    widget.onClose();
    Navigator.push<void>(
      context,
      AppPageRoute<void>(builder: (_) => page),
    );
  }

  /// 按保存的顺序排功能项：没排过/有新功能时按默认顺序补齐。
  List<_DrawerFn> _orderedFns(AppRepository repo) {
    final byKey = {for (final f in _kDrawerFns) f.key: f};
    final out = <_DrawerFn>[];
    final seen = <String>{};
    for (final k in repo.drawerOrder) {
      final f = byKey[k];
      if (f != null && seen.add(k)) out.add(f);
    }
    for (final f in _kDrawerFns) {
      if (seen.add(f.key)) out.add(f);
    }
    return out;
  }

  void _onFnTap(String key) {
    switch (key) {
      case 'stats':
        _popAndPush(const StatisticsView());
      case 'assets':
        _popAndPush(const AccountsView());
      case 'budget':
        _popAndPush(const BudgetSettingView());
      case 'savings':
        _popAndPush(const SavingsGoalsView());
      case 'assistant':
        _openAssistant();
      case 'categories':
        _popAndPush(const CategoriesView());
      case 'tags':
        _popAndPush(const TagsView());
      case 'import':
        _popAndPush(const ImportExportView());
      case 'reimburse':
        _popAndPush(const ReimburseView());
      case 'recurring':
        _popAndPush(const RecurringView());
      case 'autorecord':
        _popAndPush(const AutoRecordSettingView());
    }
  }

  // ── 喵助手：关抽屉后打开全屏 AI 面板（与首页记账栏同一套）──────────────────
  void _openAssistant() {
    widget.onClose();
    _pushAssistant();
  }

  /// 全屏喵助手作为「页面」push 进去：原生从右滑入 + 可侧滑返回，不再是弹层。
  void _pushAssistant() {
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => AiChatPanel(
          fullScreen: true,
          onSwitchToManual: _openManualFromDrawer,
        ),
      ),
    );
  }

  void _openManualFromDrawer() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    showManualAddSheet(
      context,
      fastSwitch: true,
      onSwitchToAi: () {
        Navigator.of(context, rootNavigator: true).pop();
        Future<void>.delayed(const Duration(milliseconds: 28), () {
          if (mounted) _pushAssistant();
        });
      },
    );
  }

  // ── 账本列表项 ──────────────────────────────────────────────────────────
  Widget _bookTile(BookEntity b, AppRepository repo) {
    final scheme = Theme.of(context).colorScheme;
    final selected = b.id == repo.currentBookId;
    final deletable = repo.books.length > 1 && b.id != repo.defaultBookId;
    final hasRemark = b.remark.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        minLeadingWidth: 0,
        // 放大的封面（竖版 3:4，猫脸能看清）；无封面回退 emoji 浅底方块。
        // 总账本没自选封面时用「日常生活」封面。
        leading: _bookCover(b, scheme, isTotal: b.id == repo.defaultBookId),
        horizontalTitleGap: 12,
        title: Row(
          children: [
            Flexible(
              child: Text(
                b.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? scheme.primary : scheme.onSurface,
                    ),
              ),
            ),
            if (b.starred) ...[
              const SizedBox(width: 4),
              Icon(Icons.star_rounded,
                  size: 14, color: AppColors.income(scheme)),
            ],
          ],
        ),
        subtitle: hasRemark
            ? Text(b.remark,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))
            : null,
        trailing: Builder(
          builder: (iconCtx) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showIosMenu(iconCtx, [
              // 对齐 Claude 的会话菜单：加星 / 编辑 / 改名 / 删除
              IosMenuItem(
                label: b.starred ? '取消加星' : '加星',
                icon: b.starred ? Icons.star : Icons.star_outline,
                onTap: () => repo.setBookStarred(b.id, !b.starred),
              ),
              IosMenuItem(
                label: '编辑',
                icon: Icons.edit_outlined,
                onTap: () => showBookSheet(context, edit: b),
              ),
              IosMenuItem(
                label: '改名',
                icon: Icons.drive_file_rename_outline,
                onTap: () => _showRenameBookDialog(b, repo),
              ),
              if (deletable)
                IosMenuItem(
                  label: '删除',
                  icon: Icons.delete_outline,
                  destructive: true,
                  onTap: () => _confirmDeleteBook(b, repo),
                ),
            ]),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.more_horiz,
                  size: 20, color: scheme.onSurfaceVariant),
            ),
          ),
        ),
        tileColor: selected ? AppColors.selectedCard(scheme) : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        onTap: () {
          repo.switchBook(b.id);
          widget.onClose();
        },
      ),
    );
  }

  /// 抽屉账本行的放大封面（竖版 3:4 圆角图）；无封面 = 浅底方块 + emoji。
  /// 总账本([isTotal]) 没自选封面时用「日常生活」封面 default.png。
  Widget _bookCover(BookEntity b, ColorScheme scheme, {bool isTotal = false}) {
    const w = 46.0, h = 54.0;
    Widget fallback() => Container(
          width: w,
          height: h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.selectedCard(scheme),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(b.icon, style: const TextStyle(fontSize: 24)),
        );
    final cover = b.cover.isNotEmpty
        ? b.cover
        : (isTotal ? 'assets/book_covers/default.png' : null);
    if (cover == null) return fallback();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.asset(
        cover,
        width: w,
        height: h,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback(),
      ),
    );
  }

  Future<void> _showRenameBookDialog(BookEntity b, AppRepository repo) async {
    final ctrl = TextEditingController(text: b.name);
    final ok = await showIosFormDialog(
      context,
      title: '账本改名',
      subtitle: '给账本起个新名字',
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: iosInputDecoration(context, hint: '账本名称'),
      ),
    );
    if (ok && ctrl.text.trim().isNotEmpty) {
      await repo.renameBook(b.id, name: ctrl.text.trim());
    }
  }

  /// 删账本保护：有账单时先给「转移到总账本」的温和出路，
  /// 连账单一起删要过两道确认（真实数据，别让一次手滑清掉）。
  Future<void> _confirmDeleteBook(BookEntity b, AppRepository repo) async {
    final n = await repo.transactionCountForBook(b.id);
    if (!mounted) return;

    if (n == 0) {
      final ok = await showConfirmDialog(
        context,
        title: '删除「${b.name}」？',
        message: '这个账本没有账目，删除后不可恢复。',
        confirmText: '删除',
        destructive: true,
      );
      if (ok) await repo.deleteBook(b.id);
      return;
    }

    // 有账单：先推荐转移。
    final move = await showConfirmDialog(
      context,
      title: '「${b.name}」有 $n 笔账目',
      message: '建议把账目转移到总账本再删——记录一笔不丢。\n'
          '（点「取消」后仍想连账目一起删，再删一次会有单独确认。）',
      confirmText: '转移并删除',
    );
    if (!mounted) return;
    if (move) {
      await repo.deleteBook(b.id, moveRecordsToDefault: true);
      if (mounted) showAppToast(context, '$n 笔账目已转移到总账本');
      return;
    }

    // 用户拒绝转移：更深一层的破坏性确认。
    final wipe = await showConfirmDialog(
      context,
      title: '连 $n 笔账目一起删除？',
      message: '「${b.name}」和它的全部账目将永久删除，无法恢复。',
      confirmText: '永久删除',
      destructive: true,
    );
    if (wipe) await repo.deleteBook(b.id);
  }

  void _onReorder(int oldIndex, int newIndex, List<_DrawerFn> fns) {
    final keys = fns.map((f) => f.key).toList();
    final k = keys.removeAt(oldIndex);
    keys.insert(newIndex, k);
    Haptics.selection();
    context.read<AppRepository>().setDrawerOrder(keys);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = context.watch<AppRepository>();
    final fns = _orderedFns(repo);
    // 折叠态只露排序后的前 5 个（shown 是 fns 的前缀，排序索引可直接对应全局）。
    final shown = _moreExpanded ? fns : fns.take(5).toList();

    return Material(
      // 透明：透出路由级暖渐变底（抽屉和主页共一层渐变，推开不换色）。
      color: Colors.transparent,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 头部：字标 logo（藏青+金币爪印，用户选定的第二版）──
            // 深色模式下藏青字看不清，退回文字字标；图加载失败同样退回文字。
            Padding(
              // 左距再压到贴边（用户 0703 二次反馈：还要更左）。
              padding: const EdgeInsets.fromLTRB(4, 18, 14, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Builder(builder: (context) {
                  final wordmark = Text(
                    '肥喵记账',
                    style: TextStyle(
                      fontSize: 29,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'serif',
                      color: scheme.onSurface,
                    ),
                  );
                  if (scheme.brightness == Brightness.dark) return wordmark;
                  return Image.asset(
                    'assets/brand/logo.png',
                    height: 36,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => wordmark,
                  );
                }),
              ),
            ),
            const SizedBox(height: 4),

            // ── 功能区（长按拖动排序，常用的放上面）+ 账本区 ──
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      onReorderItem: (o, n) => _onReorder(o, n, fns),
                      children: [
                        for (int i = 0; i < shown.length; i++)
                          ReorderableDelayedDragStartListener(
                            key: ValueKey(shown[i].key),
                            index: i,
                            child: _DrawerItem(
                              icon: shown[i].icon,
                              label: shown[i].label,
                              onTap: () => _onFnTap(shown[i].key),
                            ),
                          ),
                      ],
                    ),

                    // 「更多 / 收起」折叠开关：右侧不再重复放展开符号。
                    InkWell(
                      onTap: () =>
                          setState(() => _moreExpanded = !_moreExpanded),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        child: Row(
                          children: [
                            Icon(Icons.more_horiz,
                                size: 20, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 12),
                            Text(
                              _moreExpanded ? '收起' : '更多',
                              style: TextStyle(
                                fontSize: 15,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    Divider(
                        height: 20,
                        indent: 16,
                        endIndent: 16,
                        color: scheme.outlineVariant),

                    // ── 我的账本区 ────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                      child: Text(
                        '我的账本',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                      ),
                    ),
                    // 账本列表：总账本第一、加星靠前；⋮ 加星/编辑/改名/删除
                    ...repo.books.map((b) => _bookTile(b, repo)),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            // ── 底部：高频新建账本在左，设置齿轮在右（全局唯一设置入口）。──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 18, 16),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    icon: AppLineIcon(
                      AppLineIcons.squarePen,
                      size: 19,
                      color: scheme.onSurface,
                    ),
                    label: const Text('新建账本'),
                    onPressed: () => showBookSheet(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.card(scheme),
                      foregroundColor: scheme.onSurface,
                      shape: const StadiumBorder(),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 12),
                      side: BorderSide(color: AppColors.hairline(scheme)),
                    ),
                  ),
                  const Spacer(),
                  // 设置钮：走全局标准件 AppCircleButton（主页顶栏/返回键/
                  // 设置✕同款），别再手搓白圆+阴影（用户点名两次了）。
                  AppCircleButton.custom(
                    iconWidget: AppLineIcon(
                      AppLineIcons.settings,
                      size: 24,
                      color: scheme.onSurface,
                    ),
                    size: 44,
                    onPressed: () {
                      widget.onClose();
                      showSettingsSheet(context);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶栏当前账本快切：图标 + 名 + chevron，点开 iOS 菜单一键切换账本。
class _BookSwitchChip extends StatelessWidget {
  const _BookSwitchChip();

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final book =
        repo.currentBook ?? (repo.books.isNotEmpty ? repo.books.first : null);

    return Builder(
      builder: (ctx) => AppBookSwitchChip(
        iconText: book?.icon ?? '📒',
        label: book?.name ?? '账本',
        onPressed: () => showIosMenu(ctx, [
          for (final b in repo.books)
            IosMenuItem(
              label: '${b.icon} ${b.name}',
              icon: b.id == repo.currentBookId
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              onTap: () => repo.switchBook(b.id),
            ),
        ]),
      ),
    );
  }
}

/// 顶栏搜索按钮：圆形浅底放大镜，点进搜索页（与左侧菜单按钮对称）。
class _SearchIconButton extends StatelessWidget {
  const _SearchIconButton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onPressed: () => Navigator.of(context).push(
        AppPageRoute<void>(builder: (_) => const SearchView()),
      ),
      child: SizedBox(
        width: 38,
        height: 38,
        child: GlassSurface(
          circle: true,
          blur: 0, // 纯色背景，模糊看不出来，省 GPU
          child: Center(
            child: Icon(Icons.search, size: 19, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// 顶栏菜单按钮：圆形浅底 + 两条长短不一的圆角横线（对标 iOS Claude）。
class _MenuGlyphButton extends StatelessWidget {
  final VoidCallback onTap;
  const _MenuGlyphButton({required this.onTap});

  Widget _bar(ColorScheme scheme, double w) => Container(
        width: w,
        height: 1.5,
        decoration: BoxDecoration(
          color: scheme.onSurfaceVariant,
          borderRadius: BorderRadius.circular(1),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onPressed: onTap,
      child: SizedBox(
        width: 38,
        height: 38,
        // 统一玻璃圆钮 + 三条左对齐横线（最下一条半长）。
        child: GlassSurface(
          circle: true,
          blur: 0, // 纯色背景，模糊看不出来，省 GPU
          child: Center(
            child: SizedBox(
              width: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bar(scheme, 16),
                  const SizedBox(height: 3),
                  _bar(scheme, 16),
                  const SizedBox(height: 3),
                  _bar(scheme, 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final AppLineIconData icon;
  final String label;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 对齐 Claude 抽屉项：细线图标 + 常规字重深色文字，行高舒展。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -1),
        minLeadingWidth: 0,
        leading: AppLineIcon(
          icon,
          size: 21,
          color: scheme.onSurfaceVariant,
        ),
        horizontalTitleGap: 12,
        title: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: scheme.onSurface,
          ),
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      ),
    );
  }
}
