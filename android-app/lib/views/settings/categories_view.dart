import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';
import '../../core/models/cat_svg_icon.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/transaction_kind.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/sliding_segment.dart';
import '../common/app_sheet.dart';
import '../quick_add/category_grid.dart';

/// 分类管理（2026-07-03 重构）：轻卡片 + 清晰层级，不做后台表格。
/// 一级分类 = 白卡，点卡头展开 5 列子类网格（复用 CategoryGrid）；
/// 操作全部收进「⋯」菜单（重命名 / 隐藏 / 合并 / 删除 / 添加子分类）。
/// 删除保护：有历史账单的分类引导「隐藏 / 合并」，不硬删。
class CategoriesView extends StatefulWidget {
  const CategoriesView({super.key});

  @override
  State<CategoriesView> createState() => _CategoriesViewState();
}

class _CategoriesViewState extends State<CategoriesView> {
  TransactionKind _kind = TransactionKind.expense;
  final Set<int> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final scheme = Theme.of(context).colorScheme;
    final tops = repo
        .categoriesForKind(_kind)
        .where((c) => c.isTopLevel)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('分类管理')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          Center(
            child: SizedBox(
              width: 172,
              child: SlidingSegment<TransactionKind>(
                items: const [
                  (TransactionKind.expense, '支出'),
                  (TransactionKind.income, '收入'),
                ],
                value: _kind,
                onChanged: (v) {
                  Haptics.selection();
                  setState(() => _kind = v);
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (final top in tops)
            _TopCategoryCard(
              repo: repo,
              category: top,
              expanded: _expanded.contains(top.id),
              onToggle: () => setState(() {
                _expanded.contains(top.id)
                    ? _expanded.remove(top.id)
                    : _expanded.add(top.id);
              }),
            ),
          const SizedBox(height: 8),
          // 新建一级分类：白底描边轻按钮（同预算页「新建预算」）。
          PressableScale(
            onPressed: () => _showCategorySheet(context, kind: _kind),
            child: Container(
              width: double.infinity,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.card(scheme),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: AppColors.hairline(scheme, strength: 1.3)),
              ),
              child: Text(
                '新建分类',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 一级分类卡（点头部展开子类网格，操作收进 ⋯）
// ─────────────────────────────────────────────────────────────────────────────

class _TopCategoryCard extends StatelessWidget {
  final AppRepository repo;
  final CategoryEntity category;
  final bool expanded;
  final VoidCallback onToggle;

  const _TopCategoryCard({
    required this.repo,
    required this.category,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final children = repo.childrenOf(category.id);
    final hiddenIds = {
      for (final c in children)
        if (c.hidden) c.id,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 卡头：图标 + 名称（隐藏标记）+ ⋯ + 展开箭头 ──
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Haptics.selection();
              onToggle();
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              child: Row(
                children: [
                  Opacity(
                    opacity: category.hidden ? 0.4 : 1,
                    child: CatIcon(
                      categoryKey: category.key,
                      emoji: CategorySeed.emojiOf(category.key),
                      size: 36,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            category.nameZh,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: category.hidden
                                  ? scheme.onSurfaceVariant
                                  : scheme.onSurface,
                            ),
                          ),
                        ),
                        if (category.hidden) ...[
                          const SizedBox(width: 6),
                          _Badge(text: '已隐藏', scheme: scheme),
                        ],
                        if (children.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${children.length} 个子分类',
                            style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Builder(
                    builder: (menuCtx) => PressableScale(
                      onPressed: () =>
                          _showCategoryMenu(menuCtx, repo, category),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(Icons.more_horiz,
                            size: 20, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── 展开区：子类 5 列网格（点子类 = 弹操作菜单）+ 添加子分类 ──
          if (expanded) ...[
            if (children.isNotEmpty)
              Builder(
                builder: (gridCtx) => CategoryGrid(
                  categories: children,
                  selectedId: null,
                  dimmedIds: hiddenIds,
                  onSelected: (c) => _showCategoryMenu(gridCtx, repo, c),
                ),
              ),
            PressableScale(
              onPressed: () => _showCategorySheet(
                context,
                kind: category.kind,
                parent: category,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 15, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      '添加子分类',
                      style: TextStyle(
                          fontSize: 12.5, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final ColorScheme scheme;

  const _Badge({required this.text, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ⋯ 操作菜单（一级 / 二级通用）
// ─────────────────────────────────────────────────────────────────────────────

void _showCategoryMenu(
    BuildContext anchorCtx, AppRepository repo, CategoryEntity cat) {
  showIosMenu(anchorCtx, [
    IosMenuItem(
      label: '重命名',
      icon: Icons.edit_outlined,
      onTap: () => _showCategorySheet(anchorCtx, edit: cat, kind: cat.kind),
    ),
    IosMenuItem(
      label: cat.hidden ? '恢复显示' : '隐藏',
      icon: cat.hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      onTap: () async {
        await repo.setCategoryHidden(cat.id, !cat.hidden);
        if (anchorCtx.mounted) {
          showAppToast(anchorCtx,
              cat.hidden ? '「${cat.nameZh}」已恢复显示' : '「${cat.nameZh}」已隐藏');
        }
      },
    ),
    IosMenuItem(
      label: '合并到…',
      icon: Icons.call_merge,
      onTap: () => _pickMergeTarget(anchorCtx, repo, cat),
    ),
    IosMenuItem(
      label: '删除',
      icon: Icons.delete_outline,
      destructive: true,
      onTap: () => _deleteWithProtection(anchorCtx, repo, cat),
    ),
  ]);
}

/// 合并第二步：选目标分类（同收支类型，排除自己和自己的子类）。
void _pickMergeTarget(
    BuildContext anchorCtx, AppRepository repo, CategoryEntity from) {
  final childIds = repo.childrenOf(from.id).map((c) => c.id).toSet();
  final targets = repo
      .categoriesForKind(from.kind)
      .where((c) => c.id != from.id && !childIds.contains(c.id))
      .toList();
  if (targets.isEmpty) return;
  showIosMenu(anchorCtx, [
    for (final t in targets)
      IosMenuItem(
        label: t.isTopLevel ? t.nameZh : '　${t.nameZh}', // 子类缩进一格
        icon: Icons.label_outline,
        onTap: () => _confirmMerge(anchorCtx, repo, from, t),
      ),
  ]);
}

Future<void> _confirmMerge(BuildContext context, AppRepository repo,
    CategoryEntity from, CategoryEntity to) async {
  final n = await repo.transactionCountForCategory(from.id);
  if (!context.mounted) return;
  final ok = await showConfirmDialog(
    context,
    title: '把「${from.nameZh}」并入「${to.nameZh}」？',
    message: '$n 笔账单会改挂到「${to.nameZh}」，喵学过的分类记忆也一起迁移。'
        '此操作不可撤销。',
    confirmText: '合并',
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  await repo.mergeCategory(from.id, to.id);
  if (context.mounted) showAppToast(context, '已并入「${to.nameZh}」');
}

/// 删除保护：有历史账单 → 引导隐藏；没有 → 二次确认后删。
Future<void> _deleteWithProtection(
    BuildContext context, AppRepository repo, CategoryEntity cat) async {
  final n = await repo.transactionCountForCategory(cat.id);
  if (!context.mounted) return;

  if (n > 0) {
    final ok = await showConfirmDialog(
      context,
      title: '「${cat.nameZh}」有 $n 笔账单',
      message: '直接删除会让这些账单失去分类。建议改为「隐藏」——'
          '不再出现在记账面板，历史账单原样保留。\n（想保留数据到别的分类，用「合并到…」。）',
      confirmText: '改为隐藏',
    );
    if (ok && context.mounted && !cat.hidden) {
      await repo.setCategoryHidden(cat.id, true);
      if (context.mounted) showAppToast(context, '「${cat.nameZh}」已隐藏');
    }
    return;
  }

  final children = repo.childrenOf(cat.id);
  final ok = await showConfirmDialog(
    context,
    title: '删除「${cat.nameZh}」？',
    message: children.isEmpty
        ? '这个分类没有账单，删除后不可恢复。'
        : '它的 ${children.length} 个子分类会一起删除（都没有账单），不可恢复。',
    confirmText: '删除',
    destructive: true,
  );
  if (ok && context.mounted) {
    await repo.deleteCategory(cat.id);
    if (context.mounted) showAppToast(context, '已删除');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 新建 / 重命名弹层（showBlurSheet，同全局大弹层设计）
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _showCategorySheet(
  BuildContext context, {
  required TransactionKind kind,
  CategoryEntity? parent,
  CategoryEntity? edit,
}) {
  return showBlurSheet<void>(
    context,
    child: _CategorySheet(kind: kind, parent: parent, edit: edit),
  );
}

class _CategorySheet extends StatefulWidget {
  final TransactionKind kind;
  final CategoryEntity? parent;
  final CategoryEntity? edit;

  const _CategorySheet({required this.kind, this.parent, this.edit});

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.edit?.nameZh ?? '');

  bool get _isEdit => widget.edit != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final repo = context.read<AppRepository>();
    if (_isEdit) {
      await repo.renameCategory(widget.edit!.id, nameZh: name, nameEn: name);
    } else {
      await repo.addCategory(
        key: 'custom_${DateTime.now().millisecondsSinceEpoch}',
        nameZh: name,
        nameEn: name,
        kind: widget.kind,
        parentId: widget.parent?.id,
      );
    }
    Haptics.of(Haptic.success);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = _isEdit
        ? '重命名分类'
        : (widget.parent == null
            ? '新建${widget.kind == TransactionKind.income ? '收入' : '支出'}分类'
            : '给「${widget.parent!.nameZh}」添加子分类');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              PressableScale(
                onPressed: () => Navigator.pop(context),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.close,
                      size: 20, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            onChanged: (_) => setState(() {}),
            decoration: iosInputDecoration(context, hint: '分类名称'),
          ),
          if (!_isEdit) ...[
            const SizedBox(height: 6),
            Text(
              '自建分类的图标先用 🏷️ 兜底显示',
              style:
                  TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 16),
          PressableScale(
            onPressed: _nameCtrl.text.trim().isEmpty ? null : _save,
            child: Opacity(
              opacity: _nameCtrl.text.trim().isEmpty ? 0.4 : 1,
              child: Container(
                width: double.infinity,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.onSurface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _isEdit ? '保存' : '创建',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: scheme.surface,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
