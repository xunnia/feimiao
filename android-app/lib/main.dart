import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/app_repository.dart';
import 'theme/app_colors.dart';
import 'views/home/home_view.dart';
import 'views/quick_add/quick_add_view.dart';
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
      home: const RootTabs(),
    );
  }
}

class RootTabs extends StatefulWidget {
  const RootTabs({super.key});

  @override
  State<RootTabs> createState() => _RootTabsState();
}

class _RootTabsState extends State<RootTabs> {
  int _index = 0;

  // FAB 仅在首页(0)和明细(1)显示
  static const _fabVisibleTabs = {0, 1};

  void _openQuickAdd() {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => const QuickAddView()),
    );
  }

  void _goToTransactions() {
    setState(() => _index = 1);
  }

  @override
  Widget build(BuildContext context) {
    // 用 IndexedStack 保持各页状态
    final pages = [
      HomeView(onShowTransactions: _goToTransactions),
      const TransactionListView(),
      const StatisticsView(),
      const SettingsView(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: pages,
      ),
      // FAB：记一笔入口，仅首页和明细 tab 可见
      floatingActionButton: _fabVisibleTabs.contains(_index)
          ? FloatingActionButton(
              onPressed: _openQuickAdd,
              tooltip: '记一笔',
              child: const Icon(Icons.add),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: '明细',
          ),
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline),
            selectedIcon: Icon(Icons.pie_chart),
            label: '统计',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
