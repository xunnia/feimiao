// A5 负债余额口径升级向导。
// 引导用户把负债账户从 legacy_hybrid（双算）迁移到 ledger（余额是唯一真相）。
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/account/liability_balance_mode.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/settings_ui.dart';

enum _MigrationPhase { preview, running, ambiguous, done }

class LiabilityMigrationSheet extends StatefulWidget {
  const LiabilityMigrationSheet({super.key});

  @override
  State<LiabilityMigrationSheet> createState() =>
      _LiabilityMigrationSheetState();
}

class _LiabilityMigrationSheetState extends State<LiabilityMigrationSheet> {
  _MigrationPhase _phase = _MigrationPhase.preview;
  int _safeCount = 0;
  List<LiabilityMigrationPlanItem> _pending = [];
  int _currentIdx = 0;
  // 当前歧义账户的选择：0=余额是资产, 1=余额是欠款(-P), 2=暂不处理
  int _choice = -1;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: switch (_phase) {
        _MigrationPhase.preview => _buildPreview(context, repo, scheme),
        _MigrationPhase.running => _buildRunning(scheme),
        _MigrationPhase.ambiguous => _buildAmbiguous(context, repo, scheme),
        _MigrationPhase.done => _buildDone(context, scheme),
      },
    );
  }

  Widget _buildPreview(
      BuildContext context, AppRepository repo, ColorScheme scheme) {
    final plan = repo.buildMigrationPlan();
    final preview = LiabilityMigrationClassifier.preview(plan);
    final autoCount = preview.autoSafeCount;
    final ambiguousCount = preview.ambiguousCount;
    final allDone = autoCount == 0 && ambiguousCount == 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SheetHeader(title: '余额口径升级', onClose: () => Navigator.pop(context)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            '统一负债账户的显示口径，让净资产计算更准确。',
            style: AppType.secondary(scheme),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: _ExplainerCard(
            icon: Icons.info_outline,
            text: '如果你的花呗/信用卡账户余额是正数（溢缴款或押金），'
                '目前可能被重复计入资产。升级后，余额是多少就算多少，不再重复。',
            scheme: scheme,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.iconCircleFill(scheme),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (allDone)
                  _SummaryRow(
                    icon: Icons.check_circle,
                    color: AppColors.income(scheme),
                    label: '所有负债账户已是余额口径 ✓',
                    scheme: scheme,
                  ),
                if (autoCount > 0)
                  _SummaryRow(
                    icon: Icons.check_circle_outline,
                    color: AppColors.income(scheme),
                    label: '$autoCount 个账户可自动切换（净资产不变）',
                    scheme: scheme,
                  ),
                if (ambiguousCount > 0) ...[
                  if (autoCount > 0) const SizedBox(height: 4),
                  _SummaryRow(
                    icon: Icons.help_outline,
                    color: AppColors.warning,
                    label: '$ambiguousCount 个账户需要确认',
                    scheme: scheme,
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: allDone
              ? AppPillButton(
                  label: '关闭',
                  onPressed: () => Navigator.pop(context),
                )
              : AppPillButton(
                  label: autoCount > 0 ? '开始升级' : '去确认',
                  onPressed: () => _start(repo),
                ),
        ),
      ],
    );
  }

  Widget _buildRunning(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator.adaptive(),
          const SizedBox(height: 16),
          Text('正在升级...', style: AppType.secondary(scheme)),
        ],
      ),
    );
  }

  Widget _buildAmbiguous(
      BuildContext context, AppRepository repo, ColorScheme scheme) {
    if (_currentIdx >= _pending.length) {
      // 全部处理完，触发收口（A5-7 scope bump）
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await repo.finalizeA5Migration();
        if (mounted) setState(() => _phase = _MigrationPhase.done);
      });
      return _buildRunning(scheme);
    }
    final item = _pending[_currentIdx];
    final account =
        repo.accounts.where((a) => a.id == item.accountId).firstOrNull;
    final accountName = account?.name ?? '账户 ${item.accountId}';
    final balance = item.balance;
    final principal = item.principal;
    final remaining = _pending.length - _currentIdx;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(
          title: '需确认：$accountName',
          subtitle: remaining > 1 ? '还有 ${remaining - 1} 个' : null,
          onClose: () => Navigator.pop(context),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '余额 ${MoneyFormat.string(balance)} 和档案欠款 '
                '${MoneyFormat.string(principal)} 同时计入净资产。'
                '请选择这个正数余额实际代表什么：',
                style: AppType.secondary(scheme),
              ),
              const SizedBox(height: 8),
              _ExplainerCard(
                icon: Icons.undo,
                text: '不确定？没关系，升级后可以在「资金」页撤销，恢复原样。',
                scheme: scheme,
              ),
            ],
          ),
        ),
        SettingsGroup(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          children: [
            _ChoiceTile(
              selected: _choice == 0,
              title: '余额是真实资产（溢缴款/押金）',
              subtitle:
                  '档案本金不再算负债，净资产 +${MoneyFormat.string(principal)}',
              example: '例：信用卡多还了 ¥500，这笔钱是你的资产',
              onTap: () => setState(() => _choice = 0),
              scheme: scheme,
            ),
            _ChoiceTile(
              selected: _choice == 1,
              title: '余额应该是欠款（录错了符号）',
              subtitle:
                  '余额校准为 -${MoneyFormat.string(principal)}，'
                  '净资产 -${MoneyFormat.string(balance)}',
              example: '例：花呗实际欠 ¥1000，但余额不小心记成了正数',
              onTap: () => setState(() => _choice = 1),
              scheme: scheme,
            ),
            _ChoiceTile(
              selected: _choice == 2,
              title: '暂不处理',
              subtitle: '保持现有计算方式，以后再决定',
              example: '这个账户先跳过，不影响其他账户升级',
              onTap: () => setState(() => _choice = 2),
              scheme: scheme,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: AppPillButton(
            label: _currentIdx + 1 < _pending.length ? '确认，下一个' : '确认',
            onPressed:
                _choice >= 0 ? () => _confirmAmbiguous(repo, item) : null,
          ),
        ),
      ],
    );
  }

  Widget _buildDone(BuildContext context, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('✅', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text('升级完成',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            _safeCount > 0 ? '已升级 $_safeCount 个账户' : '已处理完成',
            style: AppType.secondary(scheme),
          ),
          const SizedBox(height: 12),
          _ExplainerCard(
            icon: Icons.info_outline,
            text: '升级后如需调整，可在「资金」页找到对应账户，点「撤销余额校准」恢复。',
            scheme: scheme,
          ),
          const SizedBox(height: 24),
          AppPillButton(
            label: '关闭',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Future<void> _start(AppRepository repo) async {
    setState(() {
      _phase = _MigrationPhase.running;
      _choice = -1;
    });
    _safeCount = await repo.runAllSafeMigrations();
    final ambiguous = repo
        .buildMigrationPlan()
        .where(
            (item) => item.branch == LiabilityMigrationBranch.ambiguousNeedsUser)
        .toList();
    _pending = ambiguous;
    _currentIdx = 0;
    if (mounted) {
      setState(() => _phase =
          ambiguous.isEmpty ? _MigrationPhase.done : _MigrationPhase.ambiguous);
    }
  }

  Future<void> _confirmAmbiguous(
      AppRepository repo, LiabilityMigrationPlanItem item) async {
    switch (_choice) {
      case 0:
        await repo.resolveAmbiguousBalanceIsAsset(
            item.accountId, bumpScope: false);
      case 1:
        await repo.resolveAmbiguousCalibrateToDebt(
            item.accountId, -item.principal,
            bumpScope: false);
      case 2:
        break; // 保持现状
    }
    if (_currentIdx + 1 >= _pending.length) {
      // 所有歧义账户处理完——统一 bump scope（A5-7）。
      await repo.finalizeA5Migration();
      if (mounted) setState(() { _phase = _MigrationPhase.done; _choice = -1; });
    } else {
      if (mounted) setState(() { _currentIdx++; _choice = -1; });
    }
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final ColorScheme scheme;

  const _SummaryRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: AppType.secondary(scheme))),
        ],
      );
}

class _ChoiceTile extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final String example;
  final VoidCallback onTap;
  final ColorScheme scheme;

  const _ChoiceTile({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.example,
    required this.onTap,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
          size: 20,
        ),
        title: Text(title, style: AppType.secondary(scheme)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle, style: AppType.caption(scheme)),
            const SizedBox(height: 2),
            Text(
              example,
              style: AppType.caption(scheme).copyWith(
                fontStyle: FontStyle.italic,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        onTap: onTap,
        dense: true,
        visualDensity: VisualDensity.compact,
      );
}

/// 浅色背景的解释卡片，用于在向导中插入场景化说明。
class _ExplainerCard extends StatelessWidget {
  final IconData icon;
  final String text;
  final ColorScheme scheme;

  const _ExplainerCard({
    required this.icon,
    required this.text,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: AppType.caption(scheme).copyWith(height: 1.4),
              ),
            ),
          ],
        ),
      );
}
