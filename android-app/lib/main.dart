import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/app_repository.dart';
import 'theme/app_colors.dart';
import 'views/account/personal_center_view.dart';
import 'views/common/coming_soon_view.dart';
import 'views/home/home_view.dart';
import 'views/home/record_input_bar.dart';
import 'views/settings/accounts_view.dart';
import 'views/settings/budget_setting_view.dart';
import 'views/settings/categories_view.dart';
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
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        surfaceTintColor: Colors.transparent,
        title: Builder(
          builder: (innerCtx) => Row(
            children: [
              // 左上角：Claude 风侧栏面板图标，打开 Drawer
              IconButton(
                icon: const Icon(Icons.view_sidebar_outlined),
                onPressed: () => Scaffold.of(innerCtx).openDrawer(),
                tooltip: '打开菜单',
              ),
              // 长条搜索栏，占满剩余宽度
              Expanded(
                child: GestureDetector(
                  onTap: () => ScaffoldMessenger.of(innerCtx).showSnackBar(
                    SnackBar(
                      content: const Text('搜索功能开发中（M7）'),
                      duration: const Duration(milliseconds: 1800),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    ),
                  ),
                  child: Container(
                    height: 36,
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(innerCtx).colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Theme.of(innerCtx)
                            .colorScheme
                            .outlineVariant
                            .withOpacity(0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search,
                          size: 16,
                          color: Theme.of(innerCtx)
                              .colorScheme
                              .onSurfaceVariant
                              .withOpacity(0.55),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '搜索账单 / 备注 / 金额',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(innerCtx)
                                .colorScheme
                                .onSurfaceVariant
                                .withOpacity(0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      drawer: const _AppDrawer(),
      body: HomeView(
        onShowTransactions: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
              builder: (_) => const TransactionListView()),
        ),
      ),
      bottomNavigationBar: const RecordInputBar(),
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
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 头部行：轻记字标 + 登录 + 关闭 ────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Text(
                    '轻记',
                    style:
                        Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ),
                  ),
                  const Spacer(),
                  // 个人中心（未登录态头像）
                  IconButton(
                    icon: const Icon(Icons.person_outline),
                    tooltip: '个人中心',
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => const PersonalCenterView()),
                      );
                    },
                  ),
                  // 关闭抽屉
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: 4),

            // ── 功能区（前 5 项固定，更多折叠）────────────────────
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. 账本（M4 占位）
                    _DrawerItem(
                      icon: Icons.menu_book_outlined,
                      label: '账本',
                      onTap: () {
                        Navigator.pop(context);
                        _showSnackBar('多账本即将到来（M4）');
                      },
                    ),

                    // 2. 统计数据
                    _DrawerItem(
                      icon: Icons.bar_chart,
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

                    // 5. 喵助手（M5 占位）
                    _DrawerItem(
                      icon: Icons.auto_awesome,
                      label: '喵助手',
                      onTap: () =>
                          _popAndPush(const ComingSoonView(title: '喵助手')),
                    ),

                    // 「更多 ⌄ / ⌃」折叠按钮
                    InkWell(
                      onTap: () =>
                          setState(() => _moreExpanded = !_moreExpanded),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            Icon(
                              Icons.more_horiz,
                              size: 22,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '更多',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w500,
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
                        onTap: () =>
                            _popAndPush(const ComingSoonView(title: '标签管理')),
                        indent: true,
                      ),
                      _DrawerItem(
                        icon: Icons.import_export_outlined,
                        label: '导入导出',
                        onTap: () =>
                            _popAndPush(const ComingSoonView(title: '导入导出')),
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
                    // 静态：总账本（选中态）
                    ListTile(
                      leading: Icon(Icons.menu_book_outlined,
                          size: 22, color: scheme.primary),
                      title: Text(
                        '总账本',
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: scheme.primary,
                                ),
                      ),
                      trailing: Icon(Icons.check, size: 18, color: scheme.primary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      onTap: () => Navigator.pop(context),
                    ),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            // ── 底部：+ 新建账本 ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                height: 44,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新建账本'),
                  onPressed: () {
                    Navigator.pop(context);
                    _showSnackBar('多账本即将到来（M4）');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.onSurface,
                    foregroundColor: scheme.surface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22)),
                    elevation: 0,
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
    return ListTile(
      leading: Icon(icon, size: 22, color: scheme.onSurfaceVariant),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: EdgeInsets.symmetric(
          horizontal: indent ? 28 : 16, vertical: 2),
    );
  }
}
