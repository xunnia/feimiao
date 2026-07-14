import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_version.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/settings_ui.dart';
import '../settings/ai_setting_view.dart';
import '../settings/backup_view.dart';
import '../settings/settings_view.dart';
import '../../widgets/app_page_route.dart';

class PersonalCenterView extends StatelessWidget {
  const PersonalCenterView({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = context.watch<AppRepository>();
    return Scaffold(
      backgroundColor: AppColors.appBg(scheme),
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('我的'),
        centerTitle: true,
        backgroundColor: AppColors.appBg(scheme),
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 36),
        children: [
          const _ProfileHeader(),
          const SizedBox(height: 22),
          const _SectionLabel('设置'),
          _SettingsGroupCard(children: [
            _SettingsRow(
              icon: Icons.smart_toy_outlined,
              title: 'AI 记账设置',
              onTap: () => _push(context, const AiSettingView()),
            ),
            _SettingsRow(
              icon: Icons.payments_outlined,
              title: '金额显示',
              trailingText: moneyDisplayLabel(repo),
              onTap: () => showMoneyDisplaySheet(context),
            ),
            _SettingsRow(
              icon: Icons.inventory_2_outlined,
              title: '备份与恢复',
              onTap: () => _push(context, const BackupView()),
            ),
            _SettingsRow(
              icon: Icons.info_outline,
              title: '关于',
              onTap: () => _showAboutSheet(context),
            ),
          ]),
          const SizedBox(height: 22),
          Center(
            child: Text(
              '${AppVersion.display} · ${AppVersion.name}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
                    fontFamily: 'Nunito',
                  ),
            ),
          ),
        ],
      ),
    );
  }

  static void _push(BuildContext context, Widget page) {
    Navigator.push<void>(
      context,
      AppPageRoute<void>(builder: (_) => page),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.card(scheme),
            border: Border.all(color: AppColors.hairline(scheme)),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '肥喵记账',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w400,
                color: scheme.onSurface,
              ),
        ),
        const SizedBox(height: 3),
        Text(
          AppVersion.display,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w300,
              ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12.5,
              fontWeight: FontWeight.w400,
            ),
      ),
    );
  }
}

class _SettingsGroupCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsGroupCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 0.5,
                thickness: 0.5,
                indent: 72,
                color: scheme.outlineVariant.withValues(alpha: 0.58),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailingText;
  final VoidCallback onTap;

  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.trailingText,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 54,
        child: Row(
          children: [
            const SizedBox(width: 18),
            Icon(icon, size: 22, color: scheme.onSurface),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w400,
                      color: scheme.onSurface,
                    ),
              ),
            ),
            if (trailingText != null)
              Text(
                trailingText!,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w300,
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            const SizedBox(width: 10),
            Icon(
              CupertinoIcons.chevron_forward,
              size: 15,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.45),
            ),
            const SizedBox(width: 18),
          ],
        ),
      ),
    );
  }
}

void _showAboutSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.appBg(scheme),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetHeader(title: '关于', onClose: () => Navigator.pop(ctx)),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
                child: _SettingsGroupCard(children: [
                  _SettingsRow(
                    icon: Icons.article_outlined,
                    title: '使用条款',
                    onTap: () => _showTextSheet(
                      ctx,
                      title: '使用条款',
                      body:
                          '肥喵记账用于个人记账、账单整理和消费分析。你需要自行确认录入、导入和 AI 识别结果是否准确。\n\nAI 记账和 AI 分析可能产生错误，涉及金额、分类、退款和统计结论时，请以你的真实账单和银行、支付平台记录为准。\n\n你应妥善保管自己的设备、备份文件和 API Key。因误删、误导入、第三方服务异常或设备故障造成的数据损失，建议优先通过备份恢复。',
                    ),
                  ),
                  _SettingsRow(
                    icon: Icons.lock_outline,
                    title: '隐私政策',
                    onTap: () => _showTextSheet(
                      ctx,
                      title: '隐私政策',
                      body:
                          '肥喵记账默认将账本数据保存在本机。完整备份会包含账本数据库和收据图片，但不会包含 AI API Key。\n\n当你使用 AI 解析或 AI 分析时，相关文本、账单摘要或你输入的问题可能会发送给你配置的 AI 服务提供方，用于生成结果。请避免提交身份证号、银行卡号、验证码等敏感信息。\n\n导入、导出和分享备份文件由你主动触发。请只把备份文件保存到你信任的位置。',
                    ),
                  ),
                  _SettingsRow(
                    icon: Icons.info_outline,
                    title: AppVersion.name,
                    trailingText: AppVersion.fullDisplay,
                    onTap: () {},
                  ),
                ]),
              ),
            ],
          ),
        ),
      );
    },
  );
}

void _showTextSheet(BuildContext context,
    {required String title, required String body}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.appBg(scheme),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetHeader(title: title, onClose: () => Navigator.pop(ctx)),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
                child: Text(
                  body,
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        height: 1.55,
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w300,
                      ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
