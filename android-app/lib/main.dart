import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/app_repository.dart';
import 'theme/app_colors.dart';
import 'views/home/home_view.dart';
import 'views/home/record_input_bar.dart';
import 'views/transactions/transaction_list_view.dart';
import 'views/statistics/statistics_view.dart';
import 'views/settings/settings_view.dart';

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

class _AppDrawer extends StatelessWidget {
  const _AppDrawer();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 头部：App 名
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '轻记',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '极简记账',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: 8),

            // 明细
            _DrawerItem(
              icon: Icons.receipt_long_outlined,
              label: '明细',
              onTap: () {
                Navigator.pop(context); // 关闭 Drawer
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => const TransactionListView()),
                );
              },
            ),

            // 统计
            _DrawerItem(
              icon: Icons.bar_chart_outlined,
              label: '统计',
              onTap: () {
                Navigator.pop(context);
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => const StatisticsView()),
                );
              },
            ),

            // 设置
            _DrawerItem(
              icon: Icons.settings_outlined,
              label: '设置',
              onTap: () {
                Navigator.pop(context);
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => const SettingsView()),
                );
              },
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

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }
}
