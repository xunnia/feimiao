import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
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
      appBar: AppBar(title: const Text('存钱目标'), centerTitle: true),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditDialog(context, null),
        icon: const Icon(Icons.add),
        label: const Text('新目标'),
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
          const Mascot(mood: MascotMood.idle, size: 80),
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除目标「${g.name}」？'),
        content: const Text('删除后攒钱记录不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) await repo.deleteSavingsGoal(g.id);
  }

  /// 存入 / 取出对话框。
  Future<void> _showAdjustDialog(BuildContext context, SavingsGoalEntity g,
      {required bool deposit}) async {
    final repo = context.read<AppRepository>();
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(deposit ? '存入「${g.name}」' : '从「${g.name}」取出'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(prefixText: '¥ ', hintText: '0.00'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(deposit ? '存入' : '取出')),
        ],
      ),
    );
    if (ok == true) {
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

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(goal == null ? '新建存钱目标' : '编辑目标'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  maxLength: 12,
                  decoration: const InputDecoration(hintText: '目标名，如「换新相机」'),
                ),
                TextField(
                  controller: targetCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      prefixText: '¥ ', hintText: '目标金额'),
                ),
                const SizedBox(height: 12),
                Text('选个图标', style: Theme.of(ctx).textTheme.labelMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in _emojiChoices)
                      GestureDetector(
                        onTap: () => setLocal(() => emoji = e),
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: emoji == e
                                ? Theme.of(ctx).colorScheme.primaryContainer
                                : Theme.of(ctx)
                                    .colorScheme
                                    .surfaceContainerHighest,
                            border: Border.all(
                              color: emoji == e
                                  ? Theme.of(ctx).colorScheme.primary
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Text(e, style: const TextStyle(fontSize: 20)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存')),
          ],
        ),
      ),
    );

    if (ok == true) {
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

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(goal.emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(goal.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
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
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz, color: scheme.onSurfaceVariant),
                  onSelected: (v) {
                    if (v == 'edit') onEdit();
                    if (v == 'delete') onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('编辑')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
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
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                  ),
                  Text('${(goal.progress * 100).round()}%',
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: barColor, fontWeight: FontWeight.w700)),
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
