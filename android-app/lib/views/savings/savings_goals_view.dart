import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/mascot.dart';

/// 存钱目标页：给「买相机」「旅行基金」这类目标攒钱，带进度条 + 存入/取出。
class SavingsGoalsView extends StatelessWidget {
  const SavingsGoalsView({super.key});

  static const _emojiChoices = [
    '🐷', '✈️', '📷', '💻', '🎮', '🏠', '🚗', '🎁', '💍', '🎓', '🐱', '❤️'
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('存钱目标'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新目标',
            onPressed: () => _showEditDialog(context, null),
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
              onDeposit: () => _showAdjustDialog(context, goals[i], deposit: true),
              onWithdraw: () =>
                  _showAdjustDialog(context, goals[i], deposit: false),
              onEdit: () => _showEditDialog(context, goals[i]),
              onDelete: () => _confirmDelete(context, repo, goals[i]),
            ),
          );
        },
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Mascot(mood: MascotMood.idle, size: 80, animate: true),
          const SizedBox(height: 12),
          Text('还没有存钱目标', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('立个小目标，攒钱更有动力～',
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
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
        decoration: iosInputDecoration(prefix: '¥ ', hint: '0.00'),
      ),
    );
    if (ok) {
      final v = Decimal.tryParse(ctrl.text.trim());
      if (v != null && v > Decimal.zero) {
        await repo.adjustSavingsGoal(g.id, deposit ? v : -v);
      }
    }
  }

  /// [goal] 为 null 时新建，否则编辑。
  Future<void> _showEditDialog(
      BuildContext context, SavingsGoalEntity? goal) async {
    final repo = context.read<AppRepository>();
    final nameCtrl = TextEditingController(text: goal?.name ?? '');
    final targetCtrl =
        TextEditingController(text: goal == null ? '' : _trimZero(goal.target));
    String emoji = goal?.emoji ?? _emojiChoices.first;

    final ok = await showIosFormDialog(
      context,
      title: goal == null ? '新建存钱目标' : '编辑目标',
      content: StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              maxLength: 12,
              decoration: iosInputDecoration(hint: '目标名，如「换新相机」'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: targetCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: iosInputDecoration(prefix: '¥ ', hint: '目标金额'),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child:
                  Text('选个图标', style: Theme.of(ctx).textTheme.labelMedium),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in _emojiChoices)
                  GestureDetector(
                    onTap: () => setLocal(() => emoji = e),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: emoji == e
                              ? Theme.of(ctx).colorScheme.primary
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: GoalIcon(emoji: e, size: 40),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );

    if (ok) {
      final name = nameCtrl.text.trim();
      final target = Decimal.tryParse(targetCtrl.text.trim()) ?? Decimal.zero;
      if (name.isEmpty || target <= Decimal.zero) return;
      if (goal == null) {
        await repo.addSavingsGoal(name: name, target: target, emoji: emoji);
      } else {
        await repo.updateSavingsGoal(goal.id,
            name: name, target: target, emoji: emoji);
      }
    }
  }

  static String _trimZero(Decimal v) {
    var s = v.toString();
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
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
                        done
                            ? '已达成 🎉'
                            : '还差 ${MoneyFormat.string(remaining)}',
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
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(
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
