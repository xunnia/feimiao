import 'package:flutter/material.dart';

void main() => runApp(const QingJiApp());

/// 品牌主色：沉稳深蓝（与 iOS 版一致 #2E5090）。
const Color kBrandBlue = Color(0xFF2E5090);

class QingJiApp extends StatelessWidget {
  const QingJiApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: kBrandBlue,
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: '轻记',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
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

  static const _pages = [
    _Placeholder(title: '记一笔', icon: Icons.add_circle_outline),
    _Placeholder(title: '明细', icon: Icons.receipt_long_outlined),
    _Placeholder(title: '统计', icon: Icons.pie_chart_outline),
    _Placeholder(title: '设置', icon: Icons.settings_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.add_circle_outline), label: '记一笔'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: '明细'),
          NavigationDestination(icon: Icon(Icons.pie_chart_outline), label: '统计'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: '设置'),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final String title;
  final IconData icon;
  const _Placeholder({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('轻记'),
        backgroundColor: scheme.surface,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: scheme.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('即将到来', style: TextStyle(color: scheme.outline)),
          ],
        ),
      ),
    );
  }
}
