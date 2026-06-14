import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import '../views/settings/tags_view.dart';

/// 标签选择器：一行可横滑的标签胶囊，点选/取消，末尾「+」可快速建标签。
///
/// 用于记账大卡（手动 / 编辑），通过 [selectedIds] + [onChanged] 受控。
class TagSelector extends StatelessWidget {
  final List<int> selectedIds;
  final ValueChanged<List<int>> onChanged;

  const TagSelector({
    super.key,
    required this.selectedIds,
    required this.onChanged,
  });

  void _toggle(int id) {
    final next = List<int>.of(selectedIds);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    onChanged(next);
  }

  Future<void> _quickCreate(BuildContext context) async {
    final repo = context.read<AppRepository>();
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建标签'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 8,
          decoration: const InputDecoration(hintText: '如：聚餐、报销、旅行'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('创建')),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      final id = await repo.addTag(
        name: ctrl.text.trim(),
        colorValue: kTagPalette.first.toARGB32(),
      );
      _toggle(id); // 新建后默认选中
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = context.watch<AppRepository>();
    final tags = repo.tags;

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          Icon(Icons.label_outline,
              size: 16, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
          const SizedBox(width: 6),
          for (final t in tags) ...[
            _TagChip(
              label: t.name,
              color: Color(t.colorValue),
              selected: selectedIds.contains(t.id),
              onTap: () => _toggle(t.id),
            ),
            const SizedBox(width: 6),
          ],
          // 快速新建
          GestureDetector(
            onTap: () => _quickCreate(context),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 2),
                  Text('标签',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 只读的行内标签小条：在明细行里展示该笔账目贴的标签。
/// 找不到对应标签（已删除）的 id 会被忽略。
class InlineTagChips extends StatelessWidget {
  final List<int> tagIds;

  const InlineTagChips({super.key, required this.tagIds});

  @override
  Widget build(BuildContext context) {
    if (tagIds.isEmpty) return const SizedBox.shrink();
    final repo = context.watch<AppRepository>();
    final tags = [
      for (final id in tagIds)
        ...repo.tags.where((t) => t.id == id),
    ];
    if (tags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final t in tags)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Color(t.colorValue).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                t.name,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: Color(t.colorValue),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _TagChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check, size: 13, color: Colors.white),
              const SizedBox(width: 3),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: selected ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
