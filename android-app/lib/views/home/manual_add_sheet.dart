import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:provider/provider.dart';

import '../../core/amount_expression.dart';
import '../../core/haptics.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/cat_svg_icon.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/glass.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/sliding_segment.dart';
import '../../widgets/tag_selector.dart';
import '../common/receipt_picker.dart';
import '../quick_add/amount_keypad.dart';
import '../quick_add/category_grid.dart';

/// 手动记账大卡片（模态底部弹出）。
///
/// 布局对齐咔皮（自上而下）：
///   支出/收入 分段（Telegram 胶囊）+ 模式胶囊 + 关闭
///   分类网格（点有子类的大类 → 原位展开二级面板，其余区域模糊）
///   芯片排：日期 / 账本 / 账户 / 标签 / 待报销
///   金额卡（输入框风格）：左上金额 + 细横线 + 备注 + 右下相册/拍照
///   数字键盘：1-9 / ⌫ / + / − / 再记 / 0 / . / 完成
/// 「再记」保存后不关卡片继续记；「完成」保存并关闭。
class ManualAddSheet extends StatefulWidget {
  /// 点击"AI助手"时的回调（由调用方切换到 AiFocusedInputSheet）。
  final VoidCallback onSwitchToAi;

  const ManualAddSheet({super.key, required this.onSwitchToAi});

  @override
  State<ManualAddSheet> createState() => _ManualAddSheetState();
}

class _ManualAddSheetState extends State<ManualAddSheet> {
  TransactionKind _kind = TransactionKind.expense;
  final AmountExpression _expression = AmountExpression();
  int? _selectedCategoryId;
  int? _activeParentId; // 当前选中的大类
  int? _panelParentId; // 当前展开二级面板的大类（null=没开）
  int? _selectedAccountId;
  int? _bookId; // 记到哪个账本（默认当前账本）
  DateTime _date = DateTime.now();
  final TextEditingController _noteController = TextEditingController();
  List<int> _tagIds = [];
  bool _reimbursable = false;
  String? _imagePath;
  int _expressionVersion = 0;

  /// 「再记」后的短暂提示文案（如「已记 ¥30」），1.6 秒后消失。
  String? _flash;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyDefaults());
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _noteController.dispose();
    super.dispose();
  }

  void _applyDefaults() {
    final repo = context.read<AppRepository>();
    setState(() {
      _selectedAccountId ??= repo.accounts.firstOrNull?.id;
      _bookId ??= repo.currentBookId;
      final cats = repo.categoriesForKindRanked(_kind);
      _selectedCategoryId ??= cats.firstOrNull?.id;
      _activeParentId ??= _selectedCategoryId;
    });
  }

  void _onKindChanged(TransactionKind kind) {
    if (kind == _kind) return;
    final repo = context.read<AppRepository>();
    Haptics.selection();
    setState(() {
      _kind = kind;
      final cats = repo.categoriesForKindRanked(kind);
      _selectedCategoryId = cats.firstOrNull?.id;
      _activeParentId = _selectedCategoryId;
      _panelParentId = null;
      if (kind != TransactionKind.expense) _reimbursable = false;
    });
  }

  void _onExpressionChanged() => setState(() => _expressionVersion++);

  // ── 分类点击：无子类=选中；有子类=选中+展开/收起二级面板 ──────────────────
  void _onCategoryTap(CategoryEntity cat, AppRepository repo) {
    setState(() {
      _activeParentId = cat.id;
      _selectedCategoryId = cat.id; // 不选子类则记到大类
      final hasChildren = repo.childrenOf(cat.id).isNotEmpty;
      if (!hasChildren) {
        _panelParentId = null;
      } else {
        // 再点已展开的大类 = 收起
        _panelParentId = _panelParentId == cat.id ? null : cat.id;
      }
    });
  }

  void _closePanel() => setState(() => _panelParentId = null);

  // ── 拍照 / 相册 ──────────────────────────────────────────────────────────
  Future<void> _pickImage(ImageSource source) async {
    final path = await pickAndSaveReceiptFrom(source);
    if (path != null && mounted) setState(() => _imagePath = path);
  }

  // ── 保存 ─────────────────────────────────────────────────────────────────
  Future<bool> _saveEntry() async {
    final amount = _expression.value;
    if (amount <= Decimal.zero) return false;

    final repo = context.read<AppRepository>();
    final accountId = _selectedAccountId ?? repo.accounts.firstOrNull?.id;
    if (accountId == null) return false;

    await repo.addTransaction(
      kind: _kind,
      amount: amount,
      categoryId: _selectedCategoryId,
      accountId: accountId,
      note: _noteController.text.trim(),
      date: _date,
      tagIds: _tagIds,
      reimbursable: _kind == TransactionKind.expense ? _reimbursable : false,
      imagePath: _imagePath ?? '',
      bookId: _bookId,
    );
    return true;
  }

  /// 完成：保存并关闭。
  Future<void> _save() async {
    if (!await _saveEntry()) return;
    Haptics.of(Haptic.success);
    if (mounted) Navigator.pop(context);
  }

  /// 再记：保存但不关闭，清掉金额/备注/照片继续记下一笔。
  Future<void> _saveAgain() async {
    final amount = _expression.value;
    if (!await _saveEntry()) return;
    Haptics.of(Haptic.success);
    if (!mounted) return;
    setState(() {
      _expression.clear();
      _expressionVersion++;
      _noteController.clear();
      _imagePath = null;
      _flash = '已记 ${MoneyFormat.string(amount)}，继续下一笔';
    });
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  // ── 标签选择小弹层 ────────────────────────────────────────────────────────
  Future<void> _pickTags() async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('选标签', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              StatefulBuilder(
                builder: (ctx2, setLocal) => TagSelector(
                  selectedIds: _tagIds,
                  onChanged: (v) {
                    setLocal(() {});
                    setState(() => _tagIds = v);
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ── build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // isScrollControlled sheet 需要自己限高：屏幕 92% 减去键盘高度。
    // 高度按内容自适应（分类少时卡片就矮，别留大片空白），超了才滚动。
    final screenH = MediaQuery.sizeOf(context).height;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxH = screenH * 0.92 - bottomInset;
    final panelOpen = _panelParentId != null;

    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: maxH.clamp(300.0, screenH * 0.92)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _DragHandle(),

          // ── 顶部栏：支出/收入 分段（对齐主页大小）+ 模式胶囊 + 关闭 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
            child: Row(
              children: [
                SizedBox(
                  width: 150,
                  child: SlidingSegment<TransactionKind>(
                    items: const [
                      (TransactionKind.expense, '支出'),
                      (TransactionKind.income, '收入'),
                    ],
                    value: _kind,
                    onChanged: _onKindChanged,
                  ),
                ),
                const Spacer(),
                _ModePill(label: '手动记账', onTap: widget.onSwitchToAi),
                const SizedBox(width: 8),
                _ToolCircleButton(
                  icon: Icons.close,
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // ── 分类区（内容多高就多高，放不下才滚动）──
          Flexible(
            child: Consumer<AppRepository>(
              builder: (context, repo, _) {
                final cats = repo.categoriesForKindRanked(_kind);
                final expandable = <int>{
                  for (final c in cats)
                    if (repo.childrenOf(c.id).isNotEmpty) c.id,
                };
                // 5 个一行切行，展开面板插在所在行下面（对齐咔皮）。
                const cols = 5;
                final rows = <List<CategoryEntity>>[];
                for (var i = 0; i < cats.length; i += cols) {
                  rows.add(cats.sublist(
                      i, i + cols > cats.length ? cats.length : i + cols));
                }
                return SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final row in rows) ...[
                        _blurIf(
                          panelOpen &&
                              !row.any((c) => c.id == _panelParentId),
                          CategoryGrid(
                            categories: row,
                            selectedId: _activeParentId,
                            expandableIds: expandable,
                            expandedId: _panelParentId,
                            onSelected: (c) => _onCategoryTap(c, repo),
                          ),
                        ),
                        if (panelOpen &&
                            row.any((c) => c.id == _panelParentId))
                          _SubcategoryPanel(
                            children:
                                repo.childrenOfRanked(_panelParentId!),
                            selectedId: _selectedCategoryId,
                            onSelected: (c) => setState(() {
                              _selectedCategoryId = c.id;
                              _panelParentId = null;
                            }),
                          ),
                      ],
                      const SizedBox(height: 4),
                    ],
                  ),
                );
              },
            ),
          ),

          // ── 底部固定区：芯片排 + 金额卡 + 键盘（面板展开时整体模糊+点击收起）──
          _blurIf(
            panelOpen,
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ChipsRow(
                  kind: _kind,
                  date: _date,
                  bookId: _bookId,
                  accountId: _selectedAccountId,
                  tagCount: _tagIds.length,
                  reimbursable: _reimbursable,
                  onDateChanged: (d) => setState(() => _date = d),
                  onBookChanged: (id) => setState(() => _bookId = id),
                  onAccountChanged: (id) =>
                      setState(() => _selectedAccountId = id),
                  onTagsTap: _pickTags,
                  onReimbursableToggle: () =>
                      setState(() => _reimbursable = !_reimbursable),
                ),
                _AmountCard(
                  expression: _expression,
                  version: _expressionVersion,
                  kind: _kind,
                  noteController: _noteController,
                  imagePath: _imagePath,
                  flash: _flash,
                  onPickGallery: () => _pickImage(ImageSource.gallery),
                  onPickCamera: () => _pickImage(ImageSource.camera),
                  onRemoveImage: () => setState(() => _imagePath = null),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 14, top: 6),
                  child: AmountKeypad(
                    expression: _expression,
                    onExpressionChanged: _onExpressionChanged,
                    onSave: _save,
                    onSaveAgain: _saveAgain,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 二级面板展开时把其它区域模糊压暗；点模糊区收起面板。
  Widget _blurIf(bool blur, Widget child) {
    if (!blur) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _closePanel,
      child: AbsorbPointer(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
          child: Opacity(opacity: 0.45, child: child),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 二级分类展开面板（咔皮式：白卡 + 子类网格，常用子类排前）
// ─────────────────────────────────────────────────────────────────────────────

class _SubcategoryPanel extends StatelessWidget {
  final List<CategoryEntity> children;
  final int? selectedId;
  final ValueChanged<CategoryEntity> onSelected;

  const _SubcategoryPanel({
    required this.children,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: 10,
          crossAxisSpacing: 8,
          childAspectRatio: 0.82,
        ),
        itemCount: children.length,
        itemBuilder: (context, i) {
          final c = children[i];
          final sel = c.id == selectedId;
          return PressableScale(
            onPressed: () => onSelected(c),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: sel ? scheme.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: CatIcon(
                    categoryKey: c.key,
                    emoji: CategorySeed.emojiOf(c.key),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  c.nameZh,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color:
                            sel ? scheme.primary : scheme.onSurfaceVariant,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 芯片排：日期 / 账本 / 账户 / 标签 / 待报销（横滑）
// ─────────────────────────────────────────────────────────────────────────────

class _ChipsRow extends StatelessWidget {
  final TransactionKind kind;
  final DateTime date;
  final int? bookId;
  final int? accountId;
  final int tagCount;
  final bool reimbursable;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<int?> onBookChanged;
  final ValueChanged<int?> onAccountChanged;
  final VoidCallback onTagsTap;
  final VoidCallback onReimbursableToggle;

  const _ChipsRow({
    required this.kind,
    required this.date,
    required this.bookId,
    required this.accountId,
    required this.tagCount,
    required this.reimbursable,
    required this.onDateChanged,
    required this.onBookChanged,
    required this.onAccountChanged,
    required this.onTagsTap,
    required this.onReimbursableToggle,
  });

  String _dateLabel() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return '今天';
    if (d == today.subtract(const Duration(days: 1))) return '昨天';
    return '${date.month}月${date.day}日';
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final book = repo.books.where((b) => b.id == bookId).firstOrNull ??
        repo.currentBook;
    final account =
        repo.accounts.where((a) => a.id == accountId).firstOrNull ??
            repo.accounts.firstOrNull;

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          // 日期
          _Chip(
            icon: Icons.calendar_today_outlined,
            label: _dateLabel(),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
              );
              if (picked != null) onDateChanged(picked);
            },
          ),
          const SizedBox(width: 8),
          // 账本（多账本：这笔记到哪本）—— 弹 iOS 浮动菜单，与抽屉账本菜单同款
          if (repo.books.length > 1) ...[
            Builder(
              builder: (chipCtx) => _Chip(
                icon: Icons.menu_book_outlined,
                label: book?.name ?? '账本',
                onTap: () => showIosMenu(chipCtx, [
                  for (final b in repo.books)
                    IosMenuItem(
                      label: '${b.icon} ${b.name}',
                      icon: b.id == bookId
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      onTap: () => onBookChanged(b.id),
                    ),
                ]),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // 账户 —— 同款 iOS 浮动菜单
          if (repo.accounts.isNotEmpty) ...[
            Builder(
              builder: (chipCtx) => _Chip(
                icon: Icons.account_balance_wallet_outlined,
                label: account?.name ?? '账户',
                onTap: () => showIosMenu(chipCtx, [
                  for (final a in repo.accounts)
                    IosMenuItem(
                      label: a.name,
                      icon: a.id == account?.id
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      onTap: () => onAccountChanged(a.id),
                    ),
                ]),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // 标签
          _Chip(
            icon: Icons.label_outline,
            label: tagCount > 0 ? '$tagCount 个标签' : '标签',
            selected: tagCount > 0,
            onTap: onTagsTap,
          ),
          // 待报销（仅支出）
          if (kind == TransactionKind.expense) ...[
            const SizedBox(width: 8),
            _Chip(
              icon: Icons.receipt_long_outlined,
              label: '待报销',
              selected: reimbursable,
              selectedColor: AppColors.warning,
              onTap: onReimbursableToggle,
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color? selectedColor;
  final VoidCallback onTap;

  const _Chip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.selectedColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = selectedColor ?? scheme.primary;
    final fg = selected ? accent : scheme.onSurfaceVariant;
    return PressableScale(
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.12)
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.6)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 金额卡（输入框风格）：金额 + 细横线 + 备注 + 右下 相册/拍照
// ─────────────────────────────────────────────────────────────────────────────

class _AmountCard extends StatelessWidget {
  final AmountExpression expression;
  final int version;
  final TransactionKind kind;
  final TextEditingController noteController;
  final String? imagePath;
  final String? flash;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final VoidCallback onRemoveImage;

  const _AmountCard({
    required this.expression,
    required this.version,
    required this.kind,
    required this.noteController,
    required this.imagePath,
    required this.flash,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onRemoveImage,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final amountColor = kind == TransactionKind.income
        ? AppColors.income(scheme)
        : scheme.onSurface;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 2),
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 14,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 金额行（大小/粗度对齐咔皮：别太大太粗）──
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '¥',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  color: amountColor,
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  expression.displayText,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: amountColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (expression.isCompound)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '= ${expression.value.toStringAsFixed(2)}',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
          // ── 备注 + 照片/拍照（对齐咔皮：无分隔线、无输入框边线）──
          Row(
            children: [
              Expanded(
                child: flash != null
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          flash!,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: scheme.primary,
                          ),
                        ),
                      )
                    : TextField(
                        controller: noteController,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: '写备注',
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant
                                .withValues(alpha: 0.5),
                          ),
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
              ),
              if (imagePath != null) ...[
                ReceiptThumb(
                  path: imagePath!,
                  size: 30,
                  onRemove: onRemoveImage,
                ),
                const SizedBox(width: 4),
              ] else ...[
                _IconBtn(
                    icon: Icons.image_outlined, onTap: onPickGallery),
                _IconBtn(
                    icon: Icons.photo_camera_outlined, onTap: onPickCamera),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onPressed: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 19, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 拖动条
// ─────────────────────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: scheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 统一玻璃圆钮（与首页输入栏同款）—— iOS 按压手感
// ─────────────────────────────────────────────────────────────────────────────

class _ToolCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _ToolCircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onPressed: onTap,
      child: SizedBox(
        width: 38,
        height: 38,
        child: GlassSurface(
          circle: true,
          blur: 0, // 卡片是实底，无需模糊
          child: Center(
            child: Icon(icon, size: 19, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 模式胶囊（手动记账 → 点一下切 AI；图标与首页输入栏手动模式同款）
// ─────────────────────────────────────────────────────────────────────────────

class _ModePill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ModePill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 尺寸对齐 AI 面板的模式胶囊（同类同款）。
    return PressableScale(
      onPressed: onTap,
      child: GlassSurface(
        radius: 15,
        blur: 0, // 卡片是实底，无需模糊
        padding: const EdgeInsets.symmetric(horizontal: 11),
        child: SizedBox(
          height: 31,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_outlined,
                  size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
