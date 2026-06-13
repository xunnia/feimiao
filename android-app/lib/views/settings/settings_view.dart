import 'package:flutter/material.dart';

/// 设置页占位，下个里程碑实现。
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.settings_outlined, size: 64, color: scheme.outlineVariant),
            const SizedBox(height: 16),
            Text('设置', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('即将到来', style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
