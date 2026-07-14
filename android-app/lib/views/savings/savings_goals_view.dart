import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/mascot.dart';
import '../../widgets/settings_ui.dart';
import '../common/app_sheet.dart';

/// 存钱目标页：给「买相机」「旅行基金」这类目标攒钱，带进度条 + 存入/取出。
class SavingsGoalsView extends StatelessWidget {
  const SavingsGoalsView({super.key});

  static const _emojiChoices = [
    '🐷',
    '✈️',
    '📷',
    '💻',
    '🎮',
    '🏠',
    '🚗',
    '🎁',
    '💍',
    '🎓',
    '🐱',
    '❤️'
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('存钱目标'),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: AppCircleButton(
                icon: Icons.add,
                onPressed: () => _showEditSheet(context, null)),
          ),
        ],
      ),
      body: Consumer<AppRepository>(
        builder: (context, repo, _) {
          final goals = repo.savingsGoals;
          if (goals.isEmpty) return _empty(context);
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            itemCount: goals.length,
            itemBuilder: (_, i) => _GoalCard(
              goal: goals[i],
              onDeposit: () =>
                  _showAdjustDialog(context, goals[i], deposit: true),
              onWithdraw: () =>
                  _showAdjustDialog(context, goals[i], deposit: false),
              onEdit: () => _showEditSheet(context, goals[i]),
              onDelete: () => _confirmDelete(context, repo, goals[i]),
            ),
          );
        },
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return const AppEmptyState(
      mood: MascotMood.idle,
      title: '还没有存钱目标',
      message: '立个小目标，攒钱更有动力',
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, AppRepository repo, SavingsGoalEntity g) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除目标「${g.name}」？',
      message: '删除后攒钱记录不可恢复。',
      confirmText: '删除',
      destructive: true,
    );
    if (ok) await repo.deleteSavingsGoal(g.id);
  }

  /// 存入 / 取出对话框。
  Future<void> _showAdjustDialog(BuildContext context, SavingsGoalEntity g,
      {required bool deposit}) async {
    final repo = context.read<AppRepository>();
    final ctrl = TextEditingController();
    final ok = await showIosFormDialog(
      context,
      title: deposit ? '存入「${g.name}」' : '从「${g.name}」取出',
      confirmText: deposit ? '存入' : '取出',
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: iosInputDecoration(context, prefix: '¥ ', hint: '0.00'),
      ),
    );
    final rawValue = ctrl.text.trim();
    ctrl.dispose();
    if (ok) {
      final v = Decimal.tryParse(rawValue);
      if (v != null && v > Decimal.zero) {
        await repo.adjustSavingsGoal(g.id, deposit ? v : -v);
      }
    }
  }

  /// [goal] 为 null 时新建，否则编辑。
  Future<void> _showEditSheet(BuildContext context, SavingsGoalEntity? goal) {
    return showBlurSheet<void>(
      context,
      child: _SavingsGoalEditSheet(
        goal: goal,
        emojiChoices: _emojiChoices,
      ),
    );
  }

  static String _trimZero(Decimal v) {
    var s = v.toString();
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
  }
}

class _SavingsGoalEditSheet extends StatefulWidget {
  final SavingsGoalEntity? goal;
  final List<String> emojiChoices;

  const _SavingsGoalEditSheet({
    required this.goal,
    required this.emojiChoices,
  });

  @override
  State<_SavingsGoalEditSheet> createState() => _SavingsGoalEditSheetState();
}

class _SavingsGoalEditSheetState extends State<_SavingsGoalEditSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _targetCtrl;
  late String _emoji;
  bool _saving = false;

  bool get _valid {
    final target = Decimal.tryParse(_targetCtrl.text.trim());
    return _nameCtrl.text.trim().isNotEmpty &&
        target != null &&
        target > Decimal.zero;
  }

  @override
  void initState() {
    super.initState();
    final goal = widget.goal;
    _nameCtrl = TextEditingController(text: goal?.name ?? '');
    _targetCtrl = TextEditingController(
      text: goal == null ? '' : SavingsGoalsView._trimZero(goal.target),
    );
    _emoji = goal?.emoji ?? widget.emojiChoices.first;
    _nameCtrl.addListener(_onFieldChanged);
    _targetCtrl.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _nameCtrl
      ..removeListener(_onFieldChanged)
      ..dispose();
    _targetCtrl
      ..removeListener(_onFieldChanged)
      ..dispose();
    super.dispose();
  }

  void _onFieldChanged() => setState(() {});

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() => _saving = true);
    final repo = context.read<AppRepository>();
    final name = _nameCtrl.text.trim();
    final target = Decimal.parse(_targetCtrl.text.trim());
    final goal = widget.goal;
    if (goal == null) {
      await repo.addSavingsGoal(name: name, target: target, emoji: _emoji);
    } else {
      await repo.updateSavingsGoal(
        goal.id,
        name: name,
        target: target,
        emoji: _emoji,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.86),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: widget.goal == null ? '新建存钱目标' : '编辑目标',
              onClose: () => Navigator.pop(context),
              actionLabel: '保存',
              onAction: _valid && !_saving ? _save : null,
            ),
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppLabeledField(
                      label: '目标名称',
                      child: TextField(
                        controller: _nameCtrl,
                        autofocus: true,
                        maxLength: 12,
                        textInputAction: TextInputAction.next,
                        decoration:
                            iosInputDecoration(context, hint: '如「换新相机」'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppLabeledField(
                      label: '目标金额',
                      child: TextField(
                        controller: _targetCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          if (_valid) _save();
                        },
                        decoration: iosInputDecoration(
                          context,
                          prefix: '¥ ',
                          hint: '0.00',
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    AppLabeledField(
                      label: '目标图标',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final emoji in widget.emojiChoices)
                            GestureDetector(
                              onTap: () => setState(() => _emoji = emoji),
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: _emoji == emoji
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.transparent,
                                    width: 2.5,
                                  ),
                                ),
                                child: GoalIcon(emoji: emoji, size: 40),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// emoji → 存钱目标方块 SVG 图标 key（去掉变体选择符再查，兼容 ✈️/❤️）。
const Map<String, String> _goalSvg = {
  '🐷': 'goal_pig',
  '✈': 'goal_plane',
  '📷': 'goal_camera',
  '💻': 'goal_laptop',
  '🎮': 'goal_game',
  '🏠': 'goal_house',
  '🚗': 'goal_car',
  '🎁': 'goal_gift',
  '💍': 'goal_ring',
  '🎓': 'goal_grad',
  '🐱': 'goal_cat',
  '❤': 'goal_heart',
};

/// 存钱目标图标：优先渲染 iOS 方块 SVG（与分类图标同款），找不到回退 emoji。
class GoalIcon extends StatelessWidget {
  final String emoji;
  final double size;
  const GoalIcon({super.key, required this.emoji, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final key = _goalSvg[emoji] ?? _goalSvg[emoji.replaceAll('️', '')];
    if (key != null) {
      return SvgPicture.asset('assets/cat_icons/$key.svg',
          width: size, height: size);
    }
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Text(emoji, style: TextStyle(fontSize: size * 0.6)),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final SavingsGoalEntity goal;
  final VoidCallback onDeposit;
  final VoidCallback onWithdraw;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _GoalCard({
    required this.goal,
    required this.onDeposit,
    required this.onWithdraw,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = goal.isDone;
    final barColor = done ? AppColors.income(scheme) : scheme.primary;
    final remaining = goal.target - goal.saved;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GoalIcon(emoji: goal.emoji, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(goal.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(
                        done ? '已达成 🎉' : '还差 ${MoneyFormat.string(remaining)}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: done
                                  ? AppColors.income(scheme)
                                  : scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Builder(
                  builder: (iconCtx) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => showIosMenu(iconCtx, [
                      IosMenuItem(
                        label: '编辑',
                        icon: Icons.drive_file_rename_outline,
                        onTap: onEdit,
                      ),
                      IosMenuItem(
                        label: '删除',
                        icon: Icons.delete_outline,
                        destructive: true,
                        onTap: onDelete,
                      ),
                    ]),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.more_horiz,
                          color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 进度条
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: goal.progress,
                minHeight: 10,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${MoneyFormat.string(goal.saved)} / ${MoneyFormat.string(goal.target)}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Nunito',
                          color: scheme.onSurface,
                        ),
                  ),
                  Text('${(goal.progress * 100).round()}%',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: barColor,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Nunito')),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onWithdraw,
                  icon: const Icon(Icons.remove, size: 18),
                  label: const Text('取出'),
                  style: TextButton.styleFrom(
                      foregroundColor: scheme.onSurfaceVariant),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: onDeposit,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('存入'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
