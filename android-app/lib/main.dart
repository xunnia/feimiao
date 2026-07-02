import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute, CupertinoIcons;
import 'package:provider/provider.dart';

import 'core/auto_record.dart';
import 'core/haptics.dart';
import 'data/app_repository.dart';
import 'share_intake.dart';
import 'theme/app_colors.dart';
import 'views/auto_record/auto_record_sheet.dart';
import 'widgets/glass.dart';
import 'widgets/pressable_scale.dart';
import 'widgets/ios_dialogs.dart';
import 'widgets/ios_form.dart';
import 'widgets/ios_menu.dart';
import 'views/account/personal_center_view.dart';
import 'views/books/book_sheet.dart';
import 'views/common/coming_soon_view.dart';
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
import 'views/settings/tags_view.dart';
import 'views/statistics/statistics_view.dart';
import 'views/transactions/transaction_list_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final repo = AppRepository();
  await repo.init();

  ShareIntake.init(); // 「分享到肥喵」：监听系统分享，自动记账
  autoRecordWatcher.start(); // 自动记账：回到 App 时排空通知队列、弹确认表

  runApp(
    ChangeNotifierProvider<AppRepository>.value(
      value: repo,
      child: const QingJiApp(),
    ),
  );
}

/// 自动记账巡查：App 首帧后与每次回到前台时，取出原生抓到的支付通知，
/// 本地解析成候选，弹「确认记账」表（无候选则静默）。用全局 navigatorKey 弹层。
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
      final items = await AutoRecord.drain();
      if (items.isEmpty) return;
      final ctx = ShareIntake.navigatorKey.currentContext;
      if (ctx == null) return;
      await showAutoRecordSheet(ctx, items);
    } catch (_) {
    } finally {
      _busy = false;
    }
  }
}

final _AutoRecordWatcher autoRecordWatcher = _AutoRecordWatcher();

class QingJiApp extends StatelessWidget {
  const QingJiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '肥喵记账',
      debugShowCheckedModeBanner: false,
      navigatorKey: ShareIntake.navigatorKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
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
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell>
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

  void _openDrawer() =>
      _drawerCtl.animateTo(1, curve: Curves.easeOutCubic);
  void _closeDrawer() =>
      _drawerCtl.animateTo(0, curve: Curves.easeOutCubic);

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
    final scheme = Theme.of(context).colorScheme;
    final screenW = MediaQuery.sizeOf(context).width;
    // 抽屉占 75%（用户 0703：0.82 偏大）。
    final drawerW = (screenW * 0.75).clamp(240.0, 320.0);

    return AnimatedBuilder(
      animation: _drawerCtl,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_drawerCtl.value);
        final open = _drawerCtl.value > 0.5;
        return PopScope(
          // 抽屉开着时系统返回键先关抽屉，不退出页面。
          canPop: !open,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _closeDrawer();
          },
          child: Scaffold(
            backgroundColor: AppColors.appBg(scheme),
            body: Stack(
              children: [
                // ── 底层：抽屉面板（固定不动，主页推开后露出来）──
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: drawerW,
                  child: _DrawerPanel(onClose: _closeDrawer),
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
                      // 关着时只认「向右拖」（左滑仍归账单行的编辑操作）。
                      final horizontal = total.dx.abs() > 24 &&
                          total.dx.abs() > total.dy.abs() * 1.6;
                      if (horizontal && (open ? total.dx < 0 : total.dx > 0)) {
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
                        // 阴影收敛（blur 小、不偏移），避免在左下圆角外
                        // 晕出一块灰底。
                        boxShadow: t > 0.01
                            ? [
                                BoxShadow(
                                  color:
                                      Colors.black.withValues(alpha: 0.10 * t),
                                  blurRadius: 18,
                                ),
                              ]
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(26 * t),
                        child: Stack(
                          children: [
                            _MainScaffold(onMenu: _openDrawer),
                            // 打开时主页盖白色半透明模糊遮罩（对齐 Claude），
                            // 点一下关抽屉。
                            if (_drawerCtl.value > 0.01)
                              Positioned.fill(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _closeDrawer,
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(
                                      sigmaX: 5 * t,
                                      sigmaY: 5 * t,
                                    ),
                                    child: Container(
                                      color: Colors.white
                                          .withValues(alpha: 0.35 * t),
                                    ),
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
class _MainScaffold extends StatelessWidget {
  final VoidCallback onMenu;

  const _MainScaffold({required this.onMenu});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: AppColors.appBg(scheme),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        backgroundColor: AppColors.appBg(scheme),
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: _MenuGlyphButton(onTap: onMenu),
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
              onShowTransactions: () => Navigator.push<void>(
                context,
                CupertinoPageRoute<void>(
                    builder: (_) => const TransactionListView()),
              ),
            ),
          ),
          // 底部渐变过渡（对标 Telegram 聊天底部）：列表内容滑到输入栏后面时
          // 渐渐隐入背景色，而不是被“一刀切”遮住。不拦截点击。
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
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: RecordInputBar(),
          ),
        ],
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
  final IconData icon;
  final String label;

  const _DrawerFn(this.key, this.icon, this.label);
}

const List<_DrawerFn> _kDrawerFns = [
  _DrawerFn('stats', Icons.analytics_outlined, '统计数据'),
  _DrawerFn('assets', Icons.account_balance_wallet_outlined, '资产管理'),
  _DrawerFn('budget', Icons.calendar_today_outlined, '预算管理'),
  _DrawerFn('savings', Icons.savings_outlined, '存钱目标'),
  _DrawerFn('assistant', Icons.auto_awesome, '喵助手'),
  _DrawerFn('categories', Icons.category_outlined, '分类管理'),
  _DrawerFn('tags', Icons.label_outline, '标签管理'),
  _DrawerFn('import', Icons.import_export_outlined, '导入导出'),
  _DrawerFn('recurring', Icons.schedule_outlined, '定时记账'),
  _DrawerFn('autorecord', Icons.notifications_active_outlined, '自动记账'),
  _DrawerFn('widgets', Icons.widgets_outlined, '小组件'),
];

class _DrawerPanel extends StatefulWidget {
  /// 关抽屉（收回主页面卡片）。
  final VoidCallback onClose;

  const _DrawerPanel({required this.onClose});

  @override
  State<_DrawerPanel> createState() => _DrawerPanelState();
}

class _DrawerPanelState extends State<_DrawerPanel> {
  /// 「更多」折叠：默认只露前 5 个功能项，展开后全部可见（都可长按拖动排序）。
  bool _moreExpanded = false;

  void _popAndPush(Widget page) {
    widget.onClose();
    Navigator.push<void>(
      context,
      CupertinoPageRoute<void>(builder: (_) => page),
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
      case 'recurring':
        _popAndPush(const RecurringView());
      case 'autorecord':
        _popAndPush(const AutoRecordSettingView());
      case 'widgets':
        _popAndPush(const ComingSoonView(title: '小组件'));
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
      CupertinoPageRoute<void>(
        builder: (_) => AiChatPanel(
          fullScreen: true,
          onSwitchToManual: _openManualFromDrawer,
        ),
      ),
    );
  }

  void _openManualFromDrawer() {
    showManualAddSheet(
      context,
      onSwitchToAi: () {
        Navigator.pop(context);
        _pushAssistant();
      },
    );
  }

  // ── 账本列表项 ──────────────────────────────────────────────────────────
  Widget _bookTile(BookEntity b, AppRepository repo) {
    final scheme = Theme.of(context).colorScheme;
    final selected = b.id == repo.currentBookId;
    final deletable = repo.books.length > 1 && b.id != repo.defaultBookId;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -2),
        minLeadingWidth: 0,
        // 有封面图显示小缩略图，没有回退 emoji。
        leading: b.cover.isEmpty
            ? Text(b.icon, style: const TextStyle(fontSize: 19))
            : ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  b.cover,
                  width: 24,
                  height: 24,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Text(b.icon, style: const TextStyle(fontSize: 19)),
                ),
              ),
        horizontalTitleGap: 10,
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
        tileColor: selected ? scheme.surfaceContainerHighest : null,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        onTap: () {
          repo.switchBook(b.id);
          widget.onClose();
        },
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
        decoration: iosInputDecoration(hint: '账本名称'),
      ),
    );
    if (ok && ctrl.text.trim().isNotEmpty) {
      await repo.renameBook(b.id, name: ctrl.text.trim());
    }
  }

  Future<void> _confirmDeleteBook(BookEntity b, AppRepository repo) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除「${b.name}」？',
      message: '该账本下的所有账目都会一起删除，且不可恢复。',
      confirmText: '删除',
      destructive: true,
    );
    if (ok) await repo.deleteBook(b.id);
  }

  void _onReorder(int oldIndex, int newIndex, List<_DrawerFn> fns) {
    if (newIndex > oldIndex) newIndex--;
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
      color: AppColors.appBg(scheme),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 头部：字标（对齐 Claude 抽屉左上角 wordmark：衬线、深色、不喧哗）──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 12),
              child: Text(
                '肥喵记账',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'serif',
                  color: scheme.onSurface,
                ),
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
                      onReorder: (o, n) => _onReorder(o, n, fns),
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

                    // 「更多 ⌄ / 收起 ⌃」折叠开关
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
                            const SizedBox(width: 4),
                            Icon(
                              _moreExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 18,
                              color: scheme.onSurfaceVariant,
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
                        style:
                            Theme.of(context).textTheme.labelSmall?.copyWith(
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

            // ── 底部：头像（左下角，对齐 Claude）+ 新建账本胶囊（右侧多留边）──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 24, 16),
              child: Row(
                children: [
                  _AccountAvatar(
                    onTap: () {
                      widget.onClose();
                      Navigator.push<void>(
                        context,
                        CupertinoPageRoute<void>(
                            builder: (_) => const PersonalCenterView()),
                      );
                    },
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('新建账本'),
                    onPressed: () => showBookSheet(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.onSurface,
                      foregroundColor: scheme.surface,
                      shape: const StadiumBorder(),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 12),
                    ),
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
    final scheme = Theme.of(context).colorScheme;
    final repo = context.watch<AppRepository>();
    final book = repo.currentBook ??
        (repo.books.isNotEmpty ? repo.books.first : null);

    return Builder(
      builder: (ctx) => PressableScale(
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
        child: GlassSurface(
          radius: 18,
          blur: 0, // 纯色背景，模糊看不出来，省 GPU
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: SizedBox(
            height: 36,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(book?.icon ?? '📒', style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    book?.name ?? '账本',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: scheme.onSurface,
                        ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(CupertinoIcons.chevron_down,
                    size: 14, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
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
        CupertinoPageRoute<void>(builder: (_) => const SearchView()),
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
  final IconData icon;
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
        leading: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      ),
    );
  }
}

/// 抽屉左下角账号头像：未登录显示 👤，登录后显示用户名首字。点进个人中心。
/// 与全 App 圆形按钮同一套设计（玻璃白底+细边，纯色背景免模糊）。
class _AccountAvatar extends StatelessWidget {
  final VoidCallback onTap;

  /// 登录后传入用户名首字；未登录为 null。
  final String? initial;

  const _AccountAvatar({required this.onTap, this.initial});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onPressed: onTap,
      child: SizedBox(
        width: 38,
        height: 38,
        child: GlassSurface(
          circle: true,
          blur: 0,
          child: Center(
            child: initial == null
                ? Icon(Icons.person_outline,
                    size: 20, color: scheme.onSurfaceVariant)
                : Text(
                    initial!,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                  ),
          ),
        ),
      ),
    );
  }
}
