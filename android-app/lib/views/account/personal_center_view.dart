import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute, CupertinoIcons;

import '../../theme/app_colors.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/mascot.dart';
import '../settings/ai_setting_view.dart';

/// 个人中心页（未登录态）。
/// 对齐 Claude 账号页版式，设置/主题/关于都收在这里。
class PersonalCenterView extends StatelessWidget {
  const PersonalCenterView({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(leading: const AppBackButton(), 
        title: const Text('我的'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // ── 未登录卡 ──────────────────────────────────────
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: AppColors.card(scheme),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              child: Row(
                children: [
                  const Mascot(mood: MascotMood.idle, size: 56, animate: true),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '未登录',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
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
                    onPressed: () => showAppToast(context, '云同步即将到来',
                        icon: Icons.info_outline),
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
          _Group(children: [
            _SettingsTile(
              icon: Icons.smart_toy_outlined,
              label: 'AI 记账设置',
              onTap: () => Navigator.push<void>(
                context,
                CupertinoPageRoute<void>(
                    builder: (_) => const AiSettingView()),
              ),
            ),
            _SettingsTile(
              icon: Icons.palette_outlined,
              label: '主题皮肤',
              onTap: () => showAppToast(context, '更多猫皮肤即将到来',
                  icon: Icons.info_outline),
            ),
          ]),

          const SizedBox(height: 12),
          _SectionLabel(label: '关于'),
          _Group(children: [
            _SettingsTile(
              icon: Icons.info_outline,
              label: '关于肥喵记账',
              onTap: () => showAboutDialog(
                context: context,
                applicationName: '肥喵记账',
                applicationVersion: 'v0.2',
                applicationLegalese: '© 2025 肥喵记账团队',
                children: const [
                  SizedBox(height: 8),
                  Text('一款可爱的 AI 记账 App，以你家的猫为灵感。'),
                ],
              ),
            ),
          ]),

          const SizedBox(height: 24),
          Center(
            child: Text(
              'v0.2 · 肥喵记账',
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
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

/// 白色圆角分组卡：内含若干行，发丝线分隔（左缩进对齐图标后）。
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
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
        CupertinoIcons.chevron_forward,
        size: 18,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
      onTap: onTap,
      minLeadingWidth: 0,
      horizontalTitleGap: 12,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }
}
