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
import '../../widgets/app_date_picker.dart';
import '../../widgets/glass.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/sliding_segment.dart';
import '../../widgets/tag_selector.dart';
import '../common/receipt_picker.dart';
import '../quick_add/amount_keypad.dart';
import '../quick_add/category_grid.dart';

/// 打开手动记账 / 编辑账目大卡（**统一入口**：背景高斯模糊 + 底部上滑，
/// 与 AI 记账面板同一套出场，别再用无模糊的 showModalBottomSheet）。
/// [edit] 传已有账目 = 编辑模式（同一套界面，避免记账/编辑两套设计割裂）。
Future<void> showManualAddSheet(
  BuildContext context, {
  VoidCallback? onSwitchToAi,
  TransactionEntity? edit,
}) async {
  // 键盘开着（如从 AI 面板切过来）先收掉再弹卡：
  // 否则卡片会先被键盘位置顶高、键盘收起后再落下来（"先上再下"的抖动）。
  if (MediaQuery.viewInsetsOf(context).bottom > 0) {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 130));
  }
  if (!context.mounted) return;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '记账',
    barrierColor: Colors.black.withValues(alpha: 0.12),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (ctx, _, __) => SafeArea(
      top: false,
      // 键盘弹起时整卡上移，备注不会被挡（对齐咔皮）。
      // 时长/曲线与卡内数字键盘收起动画一致，合成"一次上移"，无中间抖动。
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            child: Material(
              color: Theme.of(ctx).colorScheme.surface,
              child: ManualAddSheet(onSwitchToAi: onSwitchToAi, edit: edit),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      // 与 AI 面板同款：背景高斯模糊渐入 + 浮层上滑淡入。
      return BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 10 * anim.value,
          sigmaY: 10 * anim.value,
        ),
        child: FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

/// 手动记账大卡片。
///
/// 布局对齐咔皮（自上而下）：
///   支出/收入 分段（Telegram 胶囊）+ 模式胶囊 + 关闭
///   分类网格（点有子类的大类 → 原位展开二级面板，其余区域模糊）
///   芯片排：日期 / 账本 / 账户 / 标签 / 待报销
///   金额卡（输入框风格）：左上金额 + 细横线 + 备注 + 右下相册/拍照
///   数字键盘：1-9 / ⌫ / + / − / 再记 / 0 / . / 完成
/// 「再记」保存后不关卡片继续记；「完成」保存并关闭。
/// 编辑模式（[edit] 非空）：预填原账目、完成键=保存、无「再记」、不切账本。
class ManualAddSheet extends StatefulWidget {
  /// 点击"AI助手"时的回调；null（编辑模式）则不显示模式胶囊。
  final VoidCallback? onSwitchToAi;

  /// 要编辑的账目；null = 新记一笔。
  final TransactionEntity? edit;

  const ManualAddSheet({super.key, this.onSwitchToAi, this.edit});

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
  int? _toAccountId; // 转账的「入款账户」
  int? _bookId; // 记到哪个账本（默认当前账本）
  DateTime _date = DateTime.now();
  final TextEditingController _noteController = TextEditingController();
  List<int> _tagIds = [];
  bool _reimbursable = false;
  bool _excluded = false; // 不计入收支（帮人代付等，统计/预算跳过）
  String? _imagePath;
  int _expressionVersion = 0;

  /// 「再记」后的短暂提示文案（如「已记 ¥30」），1.6 秒后消失。
  String? _flash;
  Timer? _flashTimer;

  /// 备注输入焦点：聚焦时收起数字键盘，让位给系统键盘（对齐咔皮）。
  final FocusNode _noteFocus = FocusNode();

  /// 二级面板浮层的锚点：挂在被点的那行分类上，浮层跟着行走。
  final LayerLink _panelLink = LayerLink();

  bool get _isEdit => widget.edit != null;

  @override
  void initState() {
    super.initState();
    _noteFocus.addListener(() => setState(() {}));
    final t = widget.edit;
    if (t != null) {
      // 编辑模式：预填原账目。
      _kind = t.txKind;
      _expression.loadAmount(t.amount);
      _selectedCategoryId = t.categoryId;
      _selectedAccountId = t.accountId;
      _toAccountId = t.toAccountId;
      _date = t.date;
      _noteController.text = t.note;
      _tagIds = List<int>.of(t.tagIds);
      _reimbursable = t.reimbursable;
      _excluded = t.excluded;
      _imagePath = t.imagePath.isEmpty ? null : t.imagePath;
      final repo = context.read<AppRepository>();
      final cat = repo.categories
          .where((c) => c.id == _selectedCategoryId)
          .firstOrNull;
      _activeParentId = cat == null ? null : (cat.parentId ?? cat.id);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyDefaults());
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _noteFocus.dispose();
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
      _panelParentId = null;
      if (kind == TransactionKind.transfer) {
        // 转账不占分类；默认给一个和扣款不同的入款账户。
        _toAccountId ??= repo.accounts
            .where((a) => a.id != (_selectedAccountId ?? -1))
            .firstOrNull
            ?.id;
      } else {
        final cats = repo.categoriesForKindRanked(kind);
        _selectedCategoryId = cats.firstOrNull?.id;
        _activeParentId = _selectedCategoryId;
      }
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
    final note = _noteController.text.trim();

    // 转账：要两个不同账户；不占分类，也不进统计（引擎本来就跳过转账）。
    if (_kind == TransactionKind.transfer) {
      final to = _toAccountId;
      if (to == null || to == accountId) return false;
      final edit = widget.edit;
      if (edit != null) {
        await repo.updateTransaction(
          id: edit.id,
          kind: TransactionKind.transfer,
          amount: amount,
          categoryId: null,
          accountId: accountId,
          toAccountId: to,
          note: note,
          date: _date,
          imagePath: _imagePath ?? '',
        );
      } else {
        await repo.addTransaction(
          kind: TransactionKind.transfer,
          amount: amount,
          categoryId: null,
          accountId: accountId,
          toAccountId: to,
          note: note,
          date: _date,
          imagePath: _imagePath ?? '',
          bookId: _bookId,
        );
      }
      return true;
    }

    final edit = widget.edit;
    if (edit != null) {
      await repo.updateTransaction(
        id: edit.id,
        kind: _kind,
        amount: amount,
        categoryId: _selectedCategoryId,
        accountId: accountId,
        note: note,
        date: _date,
        tagIds: _tagIds,
        reimbursable:
            _kind == TransactionKind.expense ? _reimbursable : false,
        imagePath: _imagePath ?? '',
        excluded: _excluded,
      );
      // 学习用户纠正：改了分类且有备注 → 记住「备注 → 新分类」，下次 AI 自动套用。
      if (_selectedCategoryId != null &&
          _selectedCategoryId != edit.categoryId &&
          note.isNotEmpty) {
        final newKey = repo.categories
            .where((c) => c.id == _selectedCategoryId)
            .firstOrNull
            ?.key;
        if (newKey != null) {
          await repo.learnCategory(
              phrase: note, kind: _kind, categoryKey: newKey);
        }
      }
      return true;
    }

    await repo.addTransaction(
      kind: _kind,
      amount: amount,
      categoryId: _selectedCategoryId,
      accountId: accountId,
      note: note,
      date: _date,
      tagIds: _tagIds,
      reimbursable: _kind == TransactionKind.expense ? _reimbursable : false,
      imagePath: _imagePath ?? '',
      excluded: _excluded,
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
      // 整卡包一层 Stack：二级面板作为最后一个孩子挂在锚点行下方，
      // 保证它画在芯片/金额/键盘**之上**——之前面板画在分类区里，
      // 被后画的半透明底部区盖住，产生裁切和叠影（用户 0703 截图反馈）。
      child: LayoutBuilder(
        builder: (context, outer) => Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 顶部栏：支出/收入 分段（对齐主页大小）+ 模式胶囊 + 关闭 ──
          // （拖动把手已删——用处小还占地方；下滑关卡手势保留在顶栏空白区。）
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) > 300) Navigator.pop(context);
            },
            child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
            child: Row(
              children: [
                if (_isEdit && _kind == TransactionKind.transfer)
                  // 编辑转账不允许改类型（和分类账互转要重录，容易出错）
                  const Text('编辑转账',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600))
                else
                  SizedBox(
                    width: _isEdit ? 150 : 216,
                    child: SlidingSegment<TransactionKind>(
                      items: [
                        (TransactionKind.expense, '支出'),
                        (TransactionKind.income, '收入'),
                        // 新记一笔才给转账入口；编辑保持原类型二选一
                        if (!_isEdit) (TransactionKind.transfer, '转账'),
                      ],
                      value: _kind,
                      onChanged: _onKindChanged,
                    ),
                  ),
                const Spacer(),
                if (widget.onSwitchToAi != null) ...[
                  _ModePill(label: '手动记账', onTap: widget.onSwitchToAi!),
                  const SizedBox(width: 8),
                ],
                _ToolCircleButton(
                  icon: Icons.close,
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
            ),
          ),

          // ── 转账：扣款 ⇄ 入款 账户选择（不占分类）──
          if (_kind == TransactionKind.transfer)
            Consumer<AppRepository>(
              builder: (context, repo, _) {
                String? nameOf(int? id) =>
                    repo.accounts.where((a) => a.id == id).firstOrNull?.name;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 26, 16, 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: _AccountBox(
                          hint: '扣款账户',
                          name: nameOf(_selectedAccountId),
                          accounts: repo.accounts,
                          selectedId: _selectedAccountId,
                          onPick: (id) =>
                              setState(() => _selectedAccountId = id),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.swap_horiz,
                            size: 18,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                      ),
                      Expanded(
                        child: _AccountBox(
                          hint: '入款账户',
                          name: nameOf(_toAccountId),
                          accounts: repo.accounts,
                          selectedId: _toAccountId,
                          onPick: (id) => setState(() => _toAccountId = id),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

          // ── 分类区（内容多高就多高，放不下才滚动）──
          // 二级面板是**浮层**：锚在被点的那行下面、悬浮在网格上方，
          // 不占布局位置，所以卡片整体高度纹丝不动（用户 0703 要求）。
          if (_kind != TransactionKind.transfer)
          Flexible(
            child: Consumer<AppRepository>(
              builder: (context, repo, _) {
                final cats = repo.categoriesForKindRanked(_kind);
                final expandable = <int>{
                  for (final c in cats)
                    if (repo.visibleChildrenOf(c.id).isNotEmpty) c.id,
                };
                const cols = 5;
                final rows = <List<CategoryEntity>>[];
                for (var i = 0; i < cats.length; i += cols) {
                  rows.add(cats.sublist(
                      i, i + cols > cats.length ? cats.length : i + cols));
                }
                final activeRow = !panelOpen
                    ? -1
                    : rows.indexWhere(
                        (r) => r.any((c) => c.id == _panelParentId));

                // 选了二级分类时，在一级名字后缀「·二级名」缩略显示。
                final selCat = repo.categories
                    .where((c) => c.id == _selectedCategoryId)
                    .firstOrNull;
                final subLabels = selCat != null && selCat.parentId != null
                    ? {selCat.parentId!: selCat.nameZh}
                    : const <int, String>{};

                Widget grid(List<CategoryEntity> row) => CategoryGrid(
                      categories: row,
                      selectedId: _activeParentId,
                      expandableIds: expandable,
                      expandedId: _panelParentId,
                      subLabels: subLabels,
                      onSelected: (c) => _onCategoryTap(c, repo),
                    );

                // 面板本体在整卡 Stack 的最顶层（见 build 外层），这里只负责
                // 网格本身：被点的那行保持原样清晰（挂锚点），其余行轻模糊让位。
                return SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length; i++)
                        i == activeRow
                            ? CompositedTransformTarget(
                                link: _panelLink,
                                child: grid(rows[i]),
                              )
                            : _blurIf(panelOpen, grid(rows[i])),
                      const SizedBox(height: 4),
                    ],
                  ),
                );
              },
            ),
          ),

          // ── 底部固定区：芯片排 + 金额卡 + 键盘 ──
          // 面板展开时整片重雾压白（比网格行狠，芯片不再半遮半露），点击收起。
          _blurIf(
            panelOpen,
            sigma: 3.0,
            opacity: 0.3,
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ChipsRow(
                  kind: _kind,
                  date: _date,
                  bookId: _bookId,
                  showBook: !_isEdit, // 编辑不换账本
                  // 转账只留日期/账本（账户在上方选，报销/标签/不计入不适用）
                  showExtras: _kind != TransactionKind.transfer,
                  accountId: _selectedAccountId,
                  tagCount: _tagIds.length,
                  reimbursable: _reimbursable,
                  excluded: _excluded,
                  onDateChanged: (d) => setState(() => _date = d),
                  onBookChanged: (id) => setState(() => _bookId = id),
                  onAccountChanged: (id) =>
                      setState(() => _selectedAccountId = id),
                  onTagsTap: _pickTags,
                  onReimbursableToggle: () =>
                      setState(() => _reimbursable = !_reimbursable),
                  onExcludedToggle: () =>
                      setState(() => _excluded = !_excluded),
                ),
                _AmountCard(
                  expression: _expression,
                  version: _expressionVersion,
                  kind: _kind,
                  noteController: _noteController,
                  noteFocus: _noteFocus,
                  imagePath: _imagePath,
                  flash: _flash,
                  onPickGallery: () => _pickImage(ImageSource.gallery),
                  onPickCamera: () => _pickImage(ImageSource.camera),
                  onRemoveImage: () => setState(() => _imagePath = null),
                ),
                // 备注聚焦时收起数字键盘，让系统键盘顶上来也挡不住备注（对齐咔皮）。
                // 收放动画与整卡上移的 AnimatedPadding 同时长同曲线，合成一次过渡。
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _noteFocus.hasFocus
                      ? const SizedBox(width: double.infinity, height: 10)
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 14, top: 6),
                          child: AmountKeypad(
                            expression: _expression,
                            onExpressionChanged: _onExpressionChanged,
                            onSave: _save,
                            onSaveAgain: _isEdit ? null : _saveAgain,
                            saveLabel: _isEdit ? '保存' : '完成',
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
            ),
            // ── 二级面板：整卡最顶层，锚点行正下方，不占布局位置 ──
            // 实底白卡 + 限高内部滚动，永远不会被底部区盖住或裁切。
            if (panelOpen && _kind != TransactionKind.transfer)
              CompositedTransformFollower(
                link: _panelLink,
                showWhenUnlinked: false,
                targetAnchor: Alignment.bottomCenter,
                followerAnchor: Alignment.topCenter,
                child: SizedBox(
                  width: outer.maxWidth,
                  child: Consumer<AppRepository>(
                    builder: (context, repo, _) => _SubcategoryPanel(
                      children: repo.childrenOfRanked(_panelParentId!),
                      selectedId: _selectedCategoryId,
                      onSelected: (c) => setState(() {
                        _selectedCategoryId = c.id;
                        _panelParentId = null;
                      }),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 二级面板展开时把其它区域模糊让位；点模糊区收起面板。
  /// 网格行用默认轻雾（0.65 保持可读，用户 0703 反馈）；
  /// 底部芯片/金额/键盘用重雾压白（sigma/opacity 调狠些）。
  Widget _blurIf(bool blur, Widget child,
      {double sigma = 1.8, double opacity = 0.65}) {
    if (!blur) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _closePanel,
      child: AbsorbPointer(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: Opacity(opacity: opacity, child: child),
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
        // 实底（不透明），底下的雾一点都不许透上来。
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline(scheme)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      // 最多三行高，再多在面板里滚动（不许伸到键盘外面去）。
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 268),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            mainAxisSpacing: 10,
            crossAxisSpacing: 8,
            childAspectRatio: 0.92,
          ),
          itemCount: children.length,
          itemBuilder: (context, i) {
            final c = children[i];
            final sel = c.id == selectedId;
            // 二级用「白底圆 + 小一号图标」，和一级的圆角方块拉开层级（对齐咔皮）。
            return PressableScale(
              onPressed: () => onSelected(c),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.card(scheme),
                      border: Border.all(
                        color: sel
                            ? scheme.primary
                            : AppColors.hairline(scheme, strength: 1.3),
                        width: sel ? 2 : 1,
                      ),
                    ),
                    child: ClipOval(
                      child: CatIcon(
                        categoryKey: c.key,
                        emoji: CategorySeed.emojiOf(c.key),
                        size: 34,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    c.nameZh,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color:
                              sel ? scheme.primary : scheme.onSurfaceVariant,
                          fontWeight:
                              sel ? FontWeight.w600 : FontWeight.normal,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 转账的账户选择块（扣款 / 入款，白卡 + iOS 浮动菜单，对齐咔皮）
// ─────────────────────────────────────────────────────────────────────────────

class _AccountBox extends StatelessWidget {
  final String hint;
  final String? name;
  final List<AccountEntity> accounts;
  final int? selectedId;
  final ValueChanged<int> onPick;

  const _AccountBox({
    required this.hint,
    required this.name,
    required this.accounts,
    required this.selectedId,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Builder(
      builder: (boxCtx) => PressableScale(
        onPressed: () => showIosMenu(boxCtx, [
          for (final a in accounts)
            IosMenuItem(
              label: a.name,
              icon: a.id == selectedId
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              onTap: () => onPick(a.id),
            ),
        ]),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.card(scheme),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: AppColors.hairline(scheme, strength: 1.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  name ?? hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: name == null
                        ? scheme.onSurfaceVariant
                        : scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
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
  final bool showBook;
  final bool showExtras;
  final int? accountId;
  final int tagCount;
  final bool reimbursable;
  final bool excluded;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<int?> onBookChanged;
  final ValueChanged<int?> onAccountChanged;
  final VoidCallback onTagsTap;
  final VoidCallback onReimbursableToggle;
  final VoidCallback onExcludedToggle;

  const _ChipsRow({
    required this.kind,
    required this.date,
    required this.bookId,
    this.showBook = true,
    this.showExtras = true,
    required this.accountId,
    required this.tagCount,
    required this.reimbursable,
    required this.excluded,
    required this.onDateChanged,
    required this.onBookChanged,
    required this.onAccountChanged,
    required this.onTagsTap,
    required this.onReimbursableToggle,
    required this.onExcludedToggle,
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
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          // 日期
          _Chip(
            icon: Icons.calendar_today_outlined,
            label: _dateLabel(),
            onTap: () async {
              final picked = await showAppDatePicker(
                context,
                initial: date,
                first: DateTime(2000),
                last: DateTime.now(),
                title: '选择日期',
              );
              if (picked != null) onDateChanged(picked);
            },
          ),
          const SizedBox(width: 8),
          // 账本（多账本：这笔记到哪本）—— 弹 iOS 浮动菜单，与抽屉账本菜单同款
          if (showBook && repo.books.length > 1) ...[
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
          if (showExtras && repo.accounts.isNotEmpty) ...[
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
          if (showExtras) ...[
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
            // 不计入收支（帮人代付等：留在账单里，统计/预算跳过）
            const SizedBox(width: 8),
            _Chip(
              icon: Icons.visibility_off_outlined,
              label: '不计入',
              selected: excluded,
              onTap: onExcludedToggle,
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
    // 与全 App 按钮同一套设计：白底 + 发丝边 + 淡影；全圆角胶囊、小巧（-20%）。
    return PressableScale(
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.12)
              : AppColors.card(scheme),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.6)
                : AppColors.hairline(scheme),
          ),
          boxShadow: selected
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
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
  final FocusNode noteFocus;
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
    required this.noteFocus,
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
        border: Border.all(color: AppColors.hairline(scheme)),
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
          // ── 金额和备注之间的细灰分隔线（对齐咔皮）──
          Container(
            height: 0.6,
            margin: const EdgeInsets.only(top: 8, right: 8),
            color: scheme.outlineVariant,
          ),
          // ── 备注 + 照片/拍照（备注无输入框边线，对齐咔皮）──
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
                        focusNode: noteFocus,
                        textInputAction: TextInputAction.done,
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
