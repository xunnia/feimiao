import 'package:flutter/material.dart';

import '../../widgets/mascot.dart';
import '../settings/ai_setting_view.dart';

/// 个人中心页（未登录态）。
/// 对齐 Claude 账号页版式，设置/主题/关于都收在这里。
class PersonalCenterView extends StatelessWidget {
  const PersonalCenterView({super.key});

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 2000),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // ── 未登录卡 ──────────────────────────────────────
          Card(
            margin: const EdgeInsets.only(bottom: 20),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 0,
            color: scheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              child: Row(
                children: [
                  const Mascot(mood: MascotMood.idle, size: 56),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '未登录',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '登录后可云端备份账单',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => _showSnackBar(context, '云同步即将到来'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                    child: const Text('登录 / 注册'),
                  ),
                ],
              ),
            ),
          ),

          // ── 功能分组 ──────────────────────────────────────
          _SectionLabel(label: '设置'),
          _SettingsTile(
            icon: Icons.smart_toy_outlined,
            label: 'AI 记账设置',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                  builder: (_) => const AiSettingView()),
            ),
          ),
          _SettingsTile(
            icon: Icons.palette_outlined,
            label: '主题皮肤',
            onTap: () => _showSnackBar(context, '更多猫皮肤即将到来'),
          ),

          const SizedBox(height: 12),
          _SectionLabel(label: '关于'),
          _SettingsTile(
            icon: Icons.info_outline,
            label: '关于轻记',
            onTap: () => showAboutDialog(
              context: context,
              applicationName: '轻记 QingJi',
              applicationVersion: 'v0.2',
              applicationLegalese: '© 2025 轻记团队',
              children: const [
                SizedBox(height: 8),
                Text('一款可爱的 AI 记账 App，以你家的猫为灵感。'),
              ],
            ),
          ),

          const SizedBox(height: 24),
          Center(
            child: Text(
              'v0.2 · 轻记 QingJi',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 小工具组件 ──────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4, top: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, size: 22, color: scheme.onSurfaceVariant),
      title: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(fontWeight: FontWeight.w500),
      ),
      trailing: Icon(
        Icons.chevron_right,
        size: 18,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    );
  }
}
