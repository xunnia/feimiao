import 'package:flutter/material.dart';

import '../../widgets/ios_dialogs.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/ios_menu.dart';
import 'package:provider/provider.dart';

import '../../data/app_repository.dart';
import '../../widgets/mascot.dart';

/// 标签可选颜色（取自猫系配色 + 常用萌色）。
const List<Color> kTagPalette = [
  Color(0xFF7D8B9B), // 蓝灰毛
  Color(0xFFF2B23C), // 铜金眼
  Color(0xFFF4A9B8), // 粉鼻爪
  Color(0xFFFF9F68), // 暖橙
  Color(0xFF7FB069), // 草绿
  Color(0xFF6FB3D2), // 天蓝
  Color(0xFFB088D9), // 薰衣草
  Color(0xFFD94B3D), // 红绳
];

/// 标签管理页：列出所有标签，可新建 / 改名改色 / 删除。
class TagsView extends StatelessWidget {
  const TagsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('标签管理'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建标签',
            onPressed: () => _showEditDialog(context, null),
          ),
        ],
      ),
      body: Consumer<AppRepository>(
        builder: (context, repo, _) {
          final tags = repo.tags;
          if (tags.isEmpty) return _empty(context);
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            itemCount: tags.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (_, i) {
              final t = tags[i];
              final color = Color(t.colorValue);
              // 统计引用该标签的笔数
              final count = repo.transactions
                  .where((tx) => tx.tagIds.contains(t.id))
                  .length;
              return Card(
                elevation: 0,
                color: color.withValues(alpha: 0.10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  leading: CircleAvatar(
                      radius: 12, backgroundColor: color),
                  title: Text(t.name,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text('$count 笔账目用到'),
                  trailing: Builder(
                    builder: (iconCtx) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => showIosMenu(iconCtx, [
                        IosMenuItem(
                          label: '编辑',
                          icon: Icons.drive_file_rename_outline,
                          onTap: () => _showEditDialog(context, t),
                        ),
                        IosMenuItem(
                          label: '删除',
                          icon: Icons.delete_outline,
                          destructive: true,
                          onTap: () => _confirmDelete(context, repo, t),
                        ),
                      ]),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.more_horiz),
                      ),
                    ),
                  ),
                  onTap: () => _showEditDialog(context, t),
                ),
              );
            },
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
          const Mascot(mood: MascotMood.empty, size: 72, animate: true),
          const SizedBox(height: 12),
          Text('还没有标签', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('用标签把账目分组，比如「聚餐」「报销」',
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, AppRepository repo, TagEntity t) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除标签「${t.name}」？',
      message: '删除后，账目上的这个标签也会被移除（账目本身不受影响）。',
      confirmText: '删除',
      destructive: true,
    );
    if (ok) await repo.deleteTag(t.id);
  }

  /// [tag] 为 null 时新建，否则编辑。
  Future<void> _showEditDialog(BuildContext context, TagEntity? tag) async {
    final repo = context.read<AppRepository>();
    final ctrl = TextEditingController(text: tag?.name ?? '');
    int colorValue = tag?.colorValue ?? kTagPalette.first.toARGB32();

    final ok = await showIosFormDialog(
      context,
      title: tag == null ? '新建标签' : '编辑标签',
      content: StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLength: 8,
              decoration: iosInputDecoration(hint: '标签名'),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('颜色', style: Theme.of(ctx).textTheme.labelMedium),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in kTagPalette)
                  GestureDetector(
                    onTap: () => setLocal(() => colorValue = c.toARGB32()),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colorValue == c.toARGB32()
                              ? Colors.black87
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: colorValue == c.toARGB32()
                          ? const Icon(Icons.check,
                              size: 18, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );

    if (ok && ctrl.text.trim().isNotEmpty) {
      final name = ctrl.text.trim();
      if (tag == null) {
        await repo.addTag(name: name, colorValue: colorValue);
      } else {
        await repo.updateTag(tag.id, name: name, colorValue: colorValue);
      }
    }
  }
}
