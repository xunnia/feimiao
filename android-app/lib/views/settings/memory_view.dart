import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/cat_svg_icon.dart';
import '../../widgets/app_buttons.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/transaction_kind.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/mascot.dart';

/// 喵学到的分类记忆管理：AI 记账时「备注短语 → 分类」的纠正记录。
/// 让用户能看到喵学了什么、把学错的删掉——AI 记账的信任感来源。
class MemoryView extends StatelessWidget {
  const MemoryView({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final scheme = Theme.of(context).colorScheme;
    final memories = repo.categoryMemories;

    return Scaffold(
      appBar: AppBar(
          leading: const AppBackButton(),
          title: const Text('喵学到的分类'),
          centerTitle: true),
      body: memories.isEmpty
          ? const AppEmptyState(
              mood: MascotMood.thinking,
              title: '还没学到东西',
              message: '记账后在账单里改一次分类，喵就记住了',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                Text(
                  '你纠正过的分类喵都记着，下次同样的备注会优先用它。学错了就删掉。',
                  style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                      height: 1.4),
                ),
                const SizedBox(height: 12),
                Container(
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
                  child: Column(
                    children: [
                      for (var i = 0; i < memories.length; i++) ...[
                        if (i > 0)
                          Divider(
                              height: 0.5,
                              indent: 14,
                              color: AppColors.hairline(scheme)),
                        _MemoryRow(memory: memories[i], repo: repo),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _MemoryRow extends StatelessWidget {
  final ({String phrase, TransactionKind kind, String key}) memory;
  final AppRepository repo;

  const _MemoryRow({required this.memory, required this.repo});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cat = repo.categories
        .where((c) => c.key == memory.key && c.kind == memory.kind)
        .firstOrNull;
    final catName = cat?.nameZh ?? memory.key;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Row(
        children: [
          CatIcon(
            categoryKey: memory.key,
            emoji: CategorySeed.emojiOf(memory.key),
            size: 30,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('「${memory.phrase}」',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14)),
                Text(
                  '→ $catName · ${memory.kind == TransactionKind.income ? '收入' : '支出'}',
                  style:
                      TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: scheme.onSurfaceVariant),
            tooltip: '删除这条记忆',
            onPressed: () async {
              final ok = await showConfirmDialog(
                context,
                title: '忘掉「${memory.phrase}」？',
                message: '删除后这条备注不再自动归到「$catName」，历史账单不受影响。',
                confirmText: '删除',
                destructive: true,
              );
              if (ok && context.mounted) {
                await repo.forgetCategory(memory.phrase, memory.kind);
                if (context.mounted) showAppToast(context, '已忘掉');
              }
            },
          ),
        ],
      ),
    );
  }
}
