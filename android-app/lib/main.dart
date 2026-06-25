import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute, CupertinoIcons;
import 'package:provider/provider.dart';

import 'data/app_repository.dart';
import 'theme/app_colors.dart';
import 'widgets/glass.dart';
import 'widgets/ios_dialogs.dart';
import 'widgets/ios_form.dart';
import 'widgets/ios_menu.dart';
import 'views/account/personal_center_view.dart';
import 'views/common/coming_soon_view.dart';
import 'views/home/ai_chat_panel.dart';
import 'views/home/home_view.dart';
import 'views/home/manual_add_sheet.dart';
import 'views/home/record_input_bar.dart';
import 'views/savings/savings_goals_view.dart';
import 'views/search/search_view.dart';
import 'views/settings/accounts_view.dart';
import 'views/settings/budget_setting_view.dart';
import 'views/settings/categories_view.dart';
import 'views/settings/import_export_view.dart';
import 'views/settings/tags_view.dart';
import 'views/statistics/statistics_view.dart';
import 'views/transactions/transaction_list_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final repo = AppRepository();
  await repo.init();

  runApp(
    ChangeNotifierProvider<AppRepository>.value(
      value: repo,
      child: const QingJiApp(),
    ),
  );
}

class QingJiApp extends StatelessWidget {
  const QingJiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '轻记',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const RootShell(),
    );
  }
}

/// 新主框架：
/// - AppBar：标题当前月份，左侧汉堡按钮打开 Drawer
/// - Drawer：左侧抽屉，明细 / 统计 / 设置
/// - body：HomeView（本月概览 + 最近几笔，无嵌套 Scaffold）
/// - bottomNavigationBar：RecordInputBar（Claude 风格输入栏）
class RootShell extends StatelessWidget {
  const RootShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.appBg(Theme.of(context).colorScheme),
      // 左侧大片区域右滑即可拉出抽屉（行内左滑删除不受影响）。
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.5,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        backgroundColor: AppColors.appBg(Theme.of(context).colorScheme),
        surfaceTintColor: Colors.transparent,
        title: Builder(
          builder: (innerCtx) => Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: _MenuGlyphButton(
                  onTap: () => Scaffold.of(innerCtx).openDrawer(),
                ),
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
      ),
      drawer: const _AppDrawer(),
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
// 左侧 Drawer
// ---------------------------------------------------------------------------

class _AppDrawer extends StatefulWidget {
  const _AppDrawer();

  @override
  State<_AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<_AppDrawer> {
  bool _moreExpanded = false;

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 2000),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      ),
    );
  }

  void _popAndPush(Widget page) {
    Navigator.pop(context);
    Navigator.push<void>(
      context,
      CupertinoPageRoute<void>(builder: (_) => page),
    );
  }

  // ── 喵助手：关抽屉后打开半屏 AI 面板（与首页记账栏同一套）──────────────────
  void _openAssistant() {
    Navigator.pop(context); // 关抽屉
    showAiChatPanel(context,
        onSwitchToManual: _openManualFromDrawer, fullScreen: true);
  }

  void _openManualFromDrawer() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => ManualAddSheet(
        onSwitchToAi: () {
          Navigator.pop(ctx);
          showAiChatPanel(context,
              onSwitchToManual: _openManualFromDrawer, fullScreen: true);
        },
      ),
    );
  }

  // ── 账本列表项 ──────────────────────────────────────────────────────────
  Widget _bookTile(BookEntity b, AppRepository repo) {
    final scheme = Theme.of(context).colorScheme;
    final selected = b.id == repo.currentBookId;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -2),
        minLeadingWidth: 0,
        leading: Text(b.icon, style: const TextStyle(fontSize: 19)),
        horizontalTitleGap: 10,
        title: Text(
          b.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? scheme.primary : scheme.onSurface,
              ),
        ),
        trailing: Builder(
          builder: (iconCtx) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showIosMenu(iconCtx, [
              IosMenuItem(
                label: '改名',
                icon: Icons.drive_file_rename_outline,
                onTap: () => _showRenameBookDialog(b, repo),
              ),
              if (repo.books.length > 1)
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
          Navigator.pop(context);
        },
      ),
    );
  }

  // ── 新建账本（带场景模板）─────────────────────────────────────────────────
  Future<void> _showNewBookDialog() async {
    final repo = context.read<AppRepository>();
    final ctrl = TextEditingController();
    String icon = '📒';
    const templates = <(String, String)>[
      ('日常账本', '📒'),
      ('旅行', '✈️'),
      ('家庭AA', '🍚'),
      ('装修', '🔨'),
    ];

    final created = await showIosFormDialog(
      context,
      title: '新建账本',
      confirmText: '创建',
      content: StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final t in templates)
                  ActionChip(
                    label: Text('${t.$2} ${t.$1}'),
                    onPressed: () {
                      setLocal(() => icon = t.$2);
                      ctrl.text = t.$1;
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: iosInputDecoration(hint: '账本名称'),
            ),
          ],
        ),
      ),
    );

    if (created) {
      final name = ctrl.text.trim().isEmpty ? '新账本' : ctrl.text.trim();
      final id = await repo.addBook(name: name, icon: icon);
      await repo.switchBook(id);
      if (mounted) Navigator.pop(context); // 关闭抽屉
    }
  }

  Future<void> _showRenameBookDialog(BookEntity b, AppRepository repo) async {
    final ctrl = TextEditingController(text: b.name);
    final ok = await showIosFormDialog(
      context,
      title: '账本改名',
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = context.watch<AppRepository>();

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 头部行：轻记字标（衬线）+ 账号头像（无关闭按钮，对齐 Claude）──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 12),
              child: Row(
                children: [
                  Text(
                    '轻记',
                    style:
                        Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'serif',
                            ),
                  ),
                  const Spacer(),
                  // 账号头像：未登录👤 / 登录后名字首字，点进个人中心
                  _AccountAvatar(
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push<void>(
                        context,
                        CupertinoPageRoute<void>(
                            builder: (_) => const PersonalCenterView()),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),

            // ── 功能区（前 5 项固定，更多折叠）────────────────────
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. 统计数据
                    _DrawerItem(
                      icon: Icons.analytics_outlined,
                      label: '统计数据',
                      onTap: () => _popAndPush(const StatisticsView()),
                    ),

                    // 3. 资产管理
                    _DrawerItem(
                      icon: Icons.account_balance_wallet_outlined,
                      label: '资产管理',
                      onTap: () => _popAndPush(const AccountsView()),
                    ),

                    // 4. 预算管理
                    _DrawerItem(
                      icon: Icons.calendar_today_outlined,
                      label: '预算管理',
                      onTap: () => _popAndPush(const BudgetSettingView()),
                    ),

                    // 5. 存钱目标
                    _DrawerItem(
                      icon: Icons.savings_outlined,
                      label: '存钱目标',
                      onTap: () => _popAndPush(const SavingsGoalsView()),
                    ),

                    // 6. 喵助手（统一到首页那套半屏 AI 面板）
                    _DrawerItem(
                      icon: Icons.auto_awesome,
                      label: '喵助手',
                      onTap: _openAssistant,
                    ),

                    // 「更多 ⌄ / ⌃」折叠按钮
                    InkWell(
                      onTap: () =>
                          setState(() => _moreExpanded = !_moreExpanded),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 7),
                        child: Row(
                          children: [
                            Icon(
                              Icons.more_horiz,
                              size: 21,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '更多',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w400,
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

                    // 折叠内容
                    if (_moreExpanded) ...[
                      _DrawerItem(
                        icon: Icons.category_outlined,
                        label: '分类管理',
                        onTap: () => _popAndPush(const CategoriesView()),
                        indent: true,
                      ),
                      _DrawerItem(
                        icon: Icons.label_outline,
                        label: '标签管理',
                        onTap: () => _popAndPush(const TagsView()),
                        indent: true,
                      ),
                      _DrawerItem(
                        icon: Icons.import_export_outlined,
                        label: '导入导出',
                        onTap: () => _popAndPush(const ImportExportView()),
                        indent: true,
                      ),
                      _DrawerItem(
                        icon: Icons.schedule_outlined,
                        label: '定时记账',
                        onTap: () =>
                            _popAndPush(const ComingSoonView(title: '定时记账')),
                        indent: true,
                      ),
                      _DrawerItem(
                        icon: Icons.widgets_outlined,
                        label: '小组件',
                        onTap: () =>
                            _popAndPush(const ComingSoonView(title: '小组件')),
                        indent: true,
                      ),
                    ],

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
                    // 真实账本列表（点击切换，⋮ 改名/删除）
                    ...repo.books.map((b) => _bookTile(b, repo)),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            // ── 底部：+ 新建账本（短胶囊·居中，对齐 Claude 的 New chat）──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Align(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新建账本'),
                  onPressed: _showNewBookDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.onSurface,
                    foregroundColor: scheme.surface,
                    shape: const StadiumBorder(),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 12),
                  ),
                ),
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
      builder: (ctx) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showIosMenu(ctx, [
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        CupertinoPageRoute<void>(builder: (_) => const SearchView()),
      ),
      child: SizedBox(
        width: 38,
        height: 38,
        child: GlassSurface(
          circle: true,
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 38,
        height: 38,
        // 统一玻璃圆钮 + 三条左对齐横线（最下一条半长）。
        child: GlassSurface(
          circle: true,
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
  /// 折叠区子项：左侧额外缩进
  final bool indent;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.indent = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -2),
        minLeadingWidth: 0,
        leading: Icon(icon, size: 21, color: scheme.onSurfaceVariant),
        horizontalTitleGap: 10,
        title: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w400,
                color: scheme.onSurface,
              ),
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: EdgeInsets.symmetric(
            horizontal: indent ? 22 : 12, vertical: 0),
      ),
    );
  }
}

/// 抽屉右上角账号头像：未登录显示 👤，登录后显示用户名首字。点进个人中心。
class _AccountAvatar extends StatelessWidget {
  final VoidCallback onTap;

  /// 登录后传入用户名首字；未登录为 null。
  final String? initial;

  const _AccountAvatar({required this.onTap, this.initial});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.surfaceContainerHighest,
        ),
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
    );
  }
}
