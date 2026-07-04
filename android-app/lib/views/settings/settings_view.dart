import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute, CupertinoIcons;

import '../../theme/app_colors.dart';
import '../../widgets/app_buttons.dart';
import 'accounts_view.dart';
import 'ai_setting_view.dart';
import 'backup_view.dart';
import 'budget_setting_view.dart';
import 'categories_view.dart';

/// 设置页：iOS 风分组——灰底白卡 + 发丝分隔。
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  static const _appVersion = '0.1.0';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
          leading: const AppBackButton(),
          title: const Text('设置'),
          centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          const _SectionHeader(label: '管理'),
          _Group(children: [
            _Tile(
              icon: Icons.savings_outlined,
              title: '月度预算',
              onTap: () => Navigator.push(
                context,
                CupertinoPageRoute<void>(
                    builder: (_) => const BudgetSettingView()),
              ),
            ),
            _Tile(
              icon: Icons.account_balance_wallet_outlined,
              title: '账户管理',
              onTap: () => Navigator.push(
                context,
                CupertinoPageRoute<void>(builder: (_) => const AccountsView()),
              ),
            ),
            _Tile(
              icon: Icons.label_outline,
              title: '分类管理',
              onTap: () => Navigator.push(
                context,
                CupertinoPageRoute<void>(
                    builder: (_) => const CategoriesView()),
              ),
            ),
            _Tile(
              icon: Icons.smart_toy_outlined,
              title: 'AI 记账设置',
              onTap: () => Navigator.push(
                context,
                CupertinoPageRoute<void>(builder: (_) => const AiSettingView()),
              ),
            ),
            _Tile(
              icon: Icons.backup_outlined,
              title: '备份与恢复',
              onTap: () => Navigator.push(
                context,
                CupertinoPageRoute<void>(builder: (_) => const BackupView()),
              ),
            ),
          ]),
          const _SectionHeader(label: '关于'),
          _Group(children: [
            _Tile(
              icon: Icons.info_outline,
              title: '版本',
              trailing: Text(
                _appVersion,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontFamily: 'Nunito',
                    ),
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
            child: Text(
              '本地优先存储，无广告、无账号。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 分组小标题（灰、细）。
class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }
}

/// 白色圆角分组卡：内含若干行，发丝线分隔（左缩进对齐图标后）。
class _Group extends StatelessWidget {
  final List<Widget> children;

  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 0.5,
                thickness: 0.5,
                indent: 54,
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// 设置行：图标 + 标题 +（值 / 箭头）。
class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _Tile({
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, size: 22, color: scheme.onSurfaceVariant),
      minLeadingWidth: 0,
      horizontalTitleGap: 12,
      title: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .bodyLarge
            ?.copyWith(fontWeight: FontWeight.w400),
      ),
      trailing: trailing ??
          (onTap != null
              ? Icon(CupertinoIcons.chevron_forward,
                  size: 18, color: scheme.outline)
              : null),
      onTap: onTap,
    );
  }
}
