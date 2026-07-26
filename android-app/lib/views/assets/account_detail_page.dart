// 账户详情页：余额与校准、余额趋势、核对记录与账户资料，从 accounts_view.dart 拆出。
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money_format.dart';
import '../../core/statistics/metric_contract.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/mascot.dart';
import '../../widgets/settings_ui.dart';
import '../../widgets/sliding_segment.dart';
import '../common/app_sheet.dart';
import 'account_activity_list.dart';
import 'account_form_sheet.dart';
import 'asset_form_kit.dart';

class AccountDetailPage extends StatefulWidget {
  final AccountEntity account;

  const AccountDetailPage({super.key, required this.account});

  @override
  State<AccountDetailPage> createState() => _AccountDetailPageState();
}

class _AccountDetailPageState extends State<AccountDetailPage> {
  int _trendDays = 90;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final current = repo.accounts
            .where((item) => item.id == widget.account.id && !item.isDeleted)
            .firstOrNull ??
        widget.account;
    final balanceResult = repo.accountBalanceResultOf(current);
    final balance = balanceResult.value!.balance;
    final movement = balanceResult.value!.movement;
    final activities = repo.accountActivitiesFor(current.id);
    final checkpoints = repo
        .accountBalanceCheckpointsFor(current.id)
        .where((checkpoint) => checkpoint.isAnchor)
        .take(3)
        .toList();
    final trend = repo.accountBalanceTrend(current, days: _trendDays);
    final recurringRuleCount = repo.recurringRules
        .where((rule) => rule.accountId == current.id)
        .length;
    final qualityText = movement.unknownSettlementAccountCount > 0
        ? '${movement.unknownSettlementAccountCount} 笔到账账户待确认，当前余额只能部分核对'
        : movement.unknownSettlementDateCount > 0
            ? '${movement.unknownSettlementDateCount} 笔到账日期待确认，已计入当前余额但无法精确归入历史趋势'
            : movement.assumedAccountCount > 0 ||
                    movement.assumedSettlementDateCount > 0
                ? '余额含估算的到账日期或账户'
                : balanceResult.status != MetricStatus.available
                    ? '余额仍有待确认信息，当前只能部分核对'
                    : balanceResult.value!.checkpoint != null
                        ? '已核对于 ${assetShortDateTime(balanceResult.value!.checkpoint!.effectiveMs)}'
                        : current.openingBalanceQuality ==
                                AccountOpeningBalanceQuality.exact
                            ? '从账户建立时点起可信'
                            : null;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(current.name),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Builder(
              builder: (menuContext) => AppCircleButton(
                icon: Icons.more_horiz,
                onPressed: () => _showMoreMenu(
                  menuContext,
                  repo,
                  current,
                  recurringRuleCount: recurringRuleCount,
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: appCardDecoration(scheme),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前余额', style: AppType.secondary(scheme)),
                const SizedBox(height: 6),
                Text(
                  MoneyFormat.string(
                    balance,
                    currencyCode: current.currencyCode,
                  ),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w600,
                        color: balance < Decimal.zero
                            ? AppColors.warning
                            : scheme.onSurface,
                      ),
                ),
                if (qualityText != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    qualityText,
                    style: AppType.caption(scheme),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          SettingsGroup(
            margin: EdgeInsets.zero,
            children: [
              SettingsRow(
                leading: const Icon(Icons.fact_check_outlined),
                title: '校准余额',
                subtitle: '按现在的实际余额修正，不计入收支',
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => _showCalibration(context, current),
              ),
              if (!current.isArchived && recurringRuleCount > 0)
                SettingsRow(
                  leading: const Icon(Icons.schedule_outlined),
                  title: '定时记账',
                  subtitle: '$recurringRuleCount 个定时记账仍使用此账户，先修改或删除相关规则',
                ),
            ],
          ),
          const SizedBox(height: 12),
          _AccountBalanceTrendCard(
            trend: trend,
            days: _trendDays,
            onDaysChanged: (days) => setState(() => _trendDays = days),
          ),
          if (checkpoints.isNotEmpty) ...[
            const SizedBox(height: 12),
            AssetDetailSection(
              title: '余额核对记录',
              children: [
                for (final checkpoint in checkpoints)
                  _CheckpointRow(
                    checkpoint: checkpoint,
                    reversed: repo.isAccountBalanceCheckpointReversed(
                      checkpoint.id,
                    ),
                    onReverse: () =>
                        _reverseCheckpoint(context, repo, checkpoint),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          AssetDetailSection(
            title: '账户资料',
            children: [
              AssetDetailRow(label: '类型', value: current.type.label),
              if (current.institution.isNotEmpty)
                AssetDetailRow(
                  label: '机构',
                  value: current.institution,
                ),
              AssetDetailRow(
                label: '币种',
                value: current.currencyCode == 'CNY'
                    ? '人民币'
                    : current.currencyCode,
              ),
              AssetDetailRow(
                label: '净资产',
                value: current.includeInNetWorth ? '计入净资产' : '不计入净资产',
              ),
            ],
          ),
          const SizedBox(height: 12),
          AccountActivityList(items: activities),
        ],
      ),
    );
  }

  /// 右上角 ⋯ 菜单：编辑资料、归档/恢复等动作类操作都收在这里，正文只留信息区。
  void _showMoreMenu(
    BuildContext menuContext,
    AppRepository repo,
    AccountEntity current, {
    required int recurringRuleCount,
  }) {
    showIosMenu(
      menuContext,
      [
        IosMenuItem(
          label: '编辑资料',
          icon: Icons.edit_outlined,
          onTap: () => showBlurSheet<void>(
            context,
            child: AccountFormSheet(account: current),
          ),
        ),
        IosMenuItem(
          key: ValueKey('account-archive-action-${current.id}'),
          label: current.isArchived ? '恢复到账户列表' : '归档账户',
          icon: current.isArchived
              ? Icons.unarchive_outlined
              : Icons.archive_outlined,
          onTap: () => _toggleArchive(
            context,
            repo,
            current,
            recurringRuleCount: recurringRuleCount,
          ),
        ),
      ],
    );
  }

  Future<void> _showCalibration(
    BuildContext context,
    AccountEntity account,
  ) async {
    await showBlurSheet<void>(
      context,
      child: _AccountBalanceCalibrationSheet(account: account),
    );
  }

  Future<void> _toggleArchive(
      BuildContext context, AppRepository repo, AccountEntity account,
      {required int recurringRuleCount}) async {
    if (account.isArchived) {
      await repo.restoreArchivedAccount(account.id);
      if (!context.mounted) return;
      showAppToast(context, '已恢复「${account.name}」');
      Navigator.pop(context);
      return;
    }
    if (recurringRuleCount > 0) {
      showAppToast(context, '请先修改或删除使用此账户的定时记账');
      return;
    }
    final confirmed = await showConfirmDialog(
      context,
      title: '归档账户',
      message: '归档只会把「${account.name}」移出默认列表，余额、历史记录和净资产合计都不会改变。',
      confirmText: '归档',
    );
    if (!confirmed) return;
    try {
      await repo.archiveAccount(account.id);
    } on StateError {
      if (context.mounted) {
        showAppToast(context, '账户状态刚刚变化，请先检查相关定时记账');
      }
      return;
    }
    if (!context.mounted) return;
    showAppToast(context, '已归档「${account.name}」');
    Navigator.pop(context);
  }

  Future<void> _reverseCheckpoint(
    BuildContext context,
    AppRepository repo,
    AccountBalanceCheckpointEntity checkpoint,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '撤销这次余额校准？',
      message: '撤销后会回到上一条有效校准并重新计算，不会写一笔反向收支。',
      confirmText: '撤销',
    );
    if (!confirmed) return;
    await repo.reverseAccountBalanceCheckpoint(checkpoint.id);
    if (context.mounted) showAppToast(context, '已撤销余额校准');
  }
}

class _CheckpointRow extends StatelessWidget {
  final AccountBalanceCheckpointEntity checkpoint;
  final bool reversed;
  final VoidCallback onReverse;

  const _CheckpointRow({
    required this.checkpoint,
    required this.reversed,
    required this.onReverse,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  MoneyFormat.string(checkpoint.targetBalance),
                  style:
                      AppType.rowTitle(scheme).copyWith(fontFamily: 'Nunito'),
                ),
                const SizedBox(height: 2),
                Text(
                  '${assetShortDateTime(checkpoint.effectiveMs)} · '
                  '保存时差额 ${MoneyFormat.string(checkpoint.deltaAtCreation)}',
                  style: AppType.caption(scheme),
                ),
              ],
            ),
          ),
          reversed
              ? Text('已撤销', style: AppType.caption(scheme))
              : AppPillButton(label: '撤销', onPressed: onReverse),
        ],
      ),
    );
  }
}

class _AccountBalanceCalibrationSheet extends StatefulWidget {
  final AccountEntity account;

  const _AccountBalanceCalibrationSheet({required this.account});

  @override
  State<_AccountBalanceCalibrationSheet> createState() =>
      _AccountBalanceCalibrationSheetState();
}

class _AccountBalanceCalibrationSheetState
    extends State<_AccountBalanceCalibrationSheet> {
  late final TextEditingController _targetController;
  final _noteController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final repo = context.read<AppRepository>();
    _targetController = TextEditingController(
      text: repo.accountBalanceOf(widget.account).toString(),
    );
  }

  @override
  void dispose() {
    _targetController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Decimal? get _target => Decimal.tryParse(_targetController.text.trim());

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final scheme = Theme.of(context).colorScheme;
    final calculated = repo.accountBalanceOf(widget.account);
    final target = _target;
    final difference = target == null ? null : target - calculated;
    final now = DateTime.now();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: '校准余额',
          subtitle: widget.account.name,
          onClose: () => Navigator.pop(context),
          actionLabel: '保存',
          onAction: target == null || _saving ? null : _save,
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              AssetDetailSection(
                title: '本次核对',
                children: [
                  AssetDetailRow(
                    label: '系统计算余额',
                    value: MoneyFormat.string(calculated),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: AppLabeledField(
                      label: '实际余额',
                      child: TextField(
                        controller: _targetController,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        inputFormatters:
                            moneyInputFormatters(allowNegative: true),
                        decoration:
                            iosInputDecoration(context, hint: '例如 1234.56'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  AssetDetailRow(
                    label: '差额',
                    value: difference == null
                        ? '待输入'
                        : MoneyFormat.string(difference),
                  ),
                  AssetDetailRow(
                    label: '核对时点',
                    value: '现在 · ${now.year}/${now.month}/${now.day} '
                        '${now.hour.toString().padLeft(2, '0')}:'
                        '${now.minute.toString().padLeft(2, '0')}',
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                    child: AppLabeledField(
                      label: '说明（可选）',
                      child: TextField(
                        controller: _noteController,
                        minLines: 2,
                        maxLines: 3,
                        decoration:
                            iosInputDecoration(context, hint: '例如 微信实际余额'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '以本次填写的实际余额为准，之前的差额会自动修正，不会生成收入、支出或现金流。',
                style: AppType.caption(scheme),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final target = _target;
    if (target == null || _saving) return;
    setState(() => _saving = true);
    try {
      await context.read<AppRepository>().createAccountBalanceCheckpoint(
            accountId: widget.account.id,
            targetBalance: target,
            note: _noteController.text,
          );
      if (!mounted) return;
      showAppToast(context, '余额已核对', mascot: MascotMood.success);
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _AccountBalanceTrendCard extends StatelessWidget {
  final AccountBalanceTrendValue? trend;
  final int days;
  final ValueChanged<int> onDaysChanged;

  const _AccountBalanceTrendCard({
    required this.trend,
    required this.days,
    required this.onDaysChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: appCardDecoration(scheme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 300 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3;
              final segment = SizedBox(
                width: compact ? constraints.maxWidth : 180,
                child: SlidingSegment<int>(
                  items: const [(30, '1月'), (90, '3月'), (365, '1年')],
                  value: days,
                  onChanged: onDaysChanged,
                ),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('余额趋势', style: AppType.rowTitle(scheme)),
                    const SizedBox(height: 8),
                    segment,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: Text('余额趋势', style: AppType.rowTitle(scheme)),
                  ),
                  segment,
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          if (trend == null)
            Text('历史起点待确认，完成一次余额校准后显示趋势。', style: AppType.secondary(scheme))
          else if (!trend!.hasTrend)
            Text('已建立可信起点，积累更多结算活动后显示趋势。', style: AppType.secondary(scheme))
          else ...[
            SizedBox(
              height: 112,
              width: double.infinity,
              child: CustomPaint(
                painter: _AccountBalanceTrendPainter(
                  points: trend!.points,
                  color: scheme.primary,
                  gridColor: AppColors.hairline(scheme),
                ),
              ),
            ),
            if (trend!.points.any((point) => !point.trusted)) ...[
              const SizedBox(height: 6),
              Text('待确认到账信息所在区间不会连成可信趋势。', style: AppType.caption(scheme)),
            ],
          ],
        ],
      ),
    );
  }
}

class _AccountBalanceTrendPainter extends CustomPainter {
  final List<AccountBalanceTrendPoint> points;
  final Color color;
  final Color gridColor;

  const _AccountBalanceTrendPainter({
    required this.points,
    required this.color,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.isEmpty) return;
    final values = points.map((point) => point.balance.toDouble()).toList();
    var minimum = values.reduce(math.min);
    var maximum = values.reduce(math.max);
    if (minimum == maximum) {
      minimum -= 1;
      maximum += 1;
    }
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.7;
    for (var row = 1; row <= 2; row++) {
      final y = size.height * row / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    Offset offset(int index) {
      final x = size.width * index / (points.length - 1);
      final ratio = (values[index] - minimum) / (maximum - minimum);
      return Offset(x, size.height - ratio * size.height);
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    // 线下渐变填充：主色 18% 透明度渐隐到 0，按段独立（断点处不连成一片）。
    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, size.height),
        [
          color.withValues(alpha: 0.18),
          color.withValues(alpha: 0.0),
        ],
      );
    Path? path;
    Offset? segmentFirst;
    Offset? segmentLast;
    var segmentPointCount = 0;

    // 收尾一段：先画渐变填充（至少两个点才有面积），再描线。
    void flushSegment() {
      final current = path;
      if (current != null) {
        if (segmentPointCount > 1) {
          final fill = Path.from(current)
            ..lineTo(segmentLast!.dx, size.height)
            ..lineTo(segmentFirst!.dx, size.height)
            ..close();
          canvas.drawPath(fill, fillPaint);
        }
        canvas.drawPath(current, paint);
      }
      path = null;
      segmentFirst = null;
      segmentLast = null;
      segmentPointCount = 0;
    }

    for (var index = 0; index < points.length; index++) {
      if (!points[index].trusted) {
        flushSegment();
        continue;
      }
      final current = offset(index);
      if (path == null) {
        path = Path()..moveTo(current.dx, current.dy);
        segmentFirst = current;
      } else {
        path!.lineTo(current.dx, current.dy);
      }
      segmentLast = current;
      segmentPointCount++;
    }
    flushSegment();
  }

  @override
  bool shouldRepaint(covariant _AccountBalanceTrendPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.color != color ||
      oldDelegate.gridColor != gridColor;
}
