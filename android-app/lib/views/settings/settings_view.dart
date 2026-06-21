import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute, CupertinoIcons;

import 'accounts_view.dart';
import 'ai_setting_view.dart';
import 'backup_view.dart';
import 'budget_setting_view.dart';
import 'categories_view.dart';

/// 设置页：管理分组 + 关于分组。
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  static const _appVersion = '0.1.0';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: ListView(
        children: [
          // ---- 管理分组 ----
          _SectionHeader(label: '管理'),
          ListTile(
            leading: const Icon(Icons.savings_outlined),
            title: const Text('月度预算'),
            trailing: const Icon(CupertinoIcons.chevron_forward),
            onTap: () => Navigator.push(
              context,
              CupertinoPageRoute<void>(
                builder: (_) => const BudgetSettingView(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('账户管理'),
            trailing: const Icon(CupertinoIcons.chevron_forward),
            onTap: () => Navigator.push(
              context,
              CupertinoPageRoute<void>(
                builder: (_) => const AccountsView(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: const Text('分类管理'),
            trailing: const Icon(CupertinoIcons.chevron_forward),
            onTap: () => Navigator.push(
              context,
              CupertinoPageRoute<void>(
                builder: (_) => const CategoriesView(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('AI 记账设置'),
            trailing: const Icon(CupertinoIcons.chevron_forward),
            onTap: () => Navigator.push(
              context,
              CupertinoPageRoute<void>(
                builder: (_) => const AiSettingView(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('备份与恢复'),
            trailing: const Icon(CupertinoIcons.chevron_forward),
            onTap: () => Navigator.push(
              context,
              CupertinoPageRoute<void>(
                builder: (_) => const BackupView(),
              ),
            ),
          ),
          const Divider(height: 32),

          // ---- 关于分组 ----
          _SectionHeader(label: '关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('版本'),
            trailing: Text(
              _appVersion,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '本地优先存储，无广告、无账号。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
