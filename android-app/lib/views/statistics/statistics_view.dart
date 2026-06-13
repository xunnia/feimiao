import 'package:flutter/material.dart';

/// 统计页占位，下个里程碑实现。
class StatisticsView extends StatelessWidget {
  const StatisticsView({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('统计'), centerTitle: true),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pie_chart_outline, size: 64, color: scheme.outlineVariant),
            const SizedBox(height: 16),
            Text('统计', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('即将到来', style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
