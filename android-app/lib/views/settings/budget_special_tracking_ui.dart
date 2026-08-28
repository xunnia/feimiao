import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../core/budget/budget_plan_v2.dart';
import '../../core/budget/budget_special_tracking.dart';
import '../../core/money_format.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_date_picker.dart';
import '../../widgets/budget_progress.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/settings_ui.dart';
import '../common/app_sheet.dart';

class BudgetSpecialBookOption {
  final int id;
  final String name;
  final String icon;

  const BudgetSpecialBookOption({
    required this.id,
    required this.name,
    this.icon = '📒',
  });
}

class BudgetSpecialCategoryOption {
  final String key;
  final String name;
  final String icon;

  const BudgetSpecialCategoryOption({
    required this.key,
    required this.name,
    this.icon = '📁',
  });
}

class BudgetSpecialTagOption {
  final int id;
  final String name;
  final int colorValue;

  const BudgetSpecialTagOption({
    required this.id,
    required this.name,
    this.colorValue = 0xFF8798A8,
  });
}

class BudgetSpecialTrackingDraft {
  final int? planId;
  final String name;
  final DateTime startInclusive;
  final DateTime endInclusive;
  final int totalCents;
  final int? bookId;
  final Set<String> categoryKeys;
  final Set<int> tagIds;

  BudgetSpecialTrackingDraft({
    this.planId,
    this.name = '',
    required DateTime startInclusive,
    required DateTime endInclusive,
    this.totalCents = 0,
    this.bookId,
    Iterable<String> categoryKeys = const [],
    Iterable<int> tagIds = const [],
  })  : startInclusive = _day(startInclusive),
        endInclusive = _day(endInclusive),
        categoryKeys = Set.unmodifiable(categoryKeys.toSet()),
        tagIds = Set.unmodifiable(tagIds.toSet()) {
    if (totalCents < 0 || this.endInclusive.isBefore(this.startInclusive)) {
      throw ArgumentError('专项追踪草稿的日期或金额不合法');
    }
  }
}

class BudgetSpecialTrackingSaveCommand {
  final int? planId;
  final String name;
  final DateTime startInclusive;
  final DateTime endInclusive;
  final int totalCents;
  final int bookId;
  final Set<String> categoryKeys;
  final Set<int> tagIds;

  BudgetSpecialTrackingSaveCommand({
    required this.planId,
    required this.name,
    required this.startInclusive,
    required this.endInclusive,
    required this.totalCents,
    required this.bookId,
    required Iterable<String> categoryKeys,
    required Iterable<int> tagIds,
  })  : categoryKeys = Set.unmodifiable(categoryKeys.toSet()),
        tagIds = Set.unmodifiable(tagIds.toSet());

  bool get isEdit => planId != null;

  BudgetExpenseScopeV2 get expenseScope => BudgetExpenseScopeV2(
        categoryKeys: categoryKeys,
        tagIds: tagIds,
      );
}

typedef BudgetSpecialTrackingSaveCallback = FutureOr<void> Function(
  BudgetSpecialTrackingSaveCommand command,
);

Future<void> showBudgetSpecialTrackingSheet(
  BuildContext context, {
  required List<BudgetSpecialBookOption> books,
  required List<BudgetSpecialCategoryOption> categories,
  required List<BudgetSpecialTagOption> tags,
  BudgetSpecialTrackingDraft? initialDraft,
  required BudgetSpecialTrackingSaveCallback onSave,
}) =>
    showBlurSheet<void>(
      context,
      child: BudgetSpecialTrackingSheet(
        books: books,
        categories: categories,
        tags: tags,
        initialDraft: initialDraft,
        onSave: onSave,
      ),
    );

class BudgetSpecialTrackingSheet extends StatefulWidget {
  final List<BudgetSpecialBookOption> books;
  final List<BudgetSpecialCategoryOption> categories;
  final List<BudgetSpecialTagOption> tags;
  final BudgetSpecialTrackingDraft? initialDraft;
  final BudgetSpecialTrackingSaveCallback onSave;
  final VoidCallback? onClose;

  const BudgetSpecialTrackingSheet({
    super.key,
    required this.books,
    required this.categories,
    required this.tags,
    this.initialDraft,
    required this.onSave,
    this.onClose,
  });

  @override
  State<BudgetSpecialTrackingSheet> createState() =>
      _BudgetSpecialTrackingSheetState();
}

class _BudgetSpecialTrackingSheetState
    extends State<BudgetSpecialTrackingSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _totalController;
  late DateTime _start;
  late DateTime _end;
  late int? _bookId;
  late Set<String> _categoryKeys;
  late Set<int> _tagIds;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.initialDraft?.planId != null;

  @override
  void initState() {
    super.initState();
    final now = _day(DateTime.now());
    final draft = widget.initialDraft;
    _nameController = TextEditingController(text: draft?.name ?? '');
    _totalController = TextEditingController(
      text: draft == null ? '' : _centsInput(draft.totalCents),
    );
    _start = draft?.startInclusive ?? now;
    _end = draft?.endInclusive ?? now.add(const Duration(days: 6));
    _bookId = draft?.bookId ?? widget.books.firstOrNull?.id;
    final categoryOptions = widget.categories.map((item) => item.key).toSet();
    final tagOptions = widget.tags.map((item) => item.id).toSet();
    _categoryKeys = {
      for (final key in draft?.categoryKeys ?? const <String>{})
        if (categoryOptions.contains(key)) key,
    };
    _tagIds = {
      for (final id in draft?.tagIds ?? const <int>{})
        if (tagOptions.contains(id)) id,
    };
  }

  @override
  void dispose() {
    _nameController.dispose();
    _totalController.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final range = await showAppDateRangePicker(
      context,
      initial: DateTimeRange(start: _start, end: _end),
      first: DateTime(2000),
      last: DateTime(DateTime.now().year + 10, 12, 31),
    );
    if (range == null || !mounted) return;
    setState(() {
      _start = _day(range.start);
      _end = _day(range.end);
      _error = null;
    });
  }

  void _showBookMenu(BuildContext menuContext) {
    showIosMenu(menuContext, [
      for (final book in widget.books)
        IosMenuItem(
          label: '${book.icon} ${book.name}',
          icon: book.id == _bookId
              ? Icons.check_circle
              : Icons.radio_button_unchecked,
          onTap: () => setState(() {
            _bookId = book.id;
            _error = null;
          }),
        ),
    ]);
  }

  void _toggleCategory(String key) {
    setState(() {
      _categoryKeys.contains(key)
          ? _categoryKeys.remove(key)
          : _categoryKeys.add(key);
      _error = null;
    });
  }

  void _toggleTag(int id) {
    setState(() {
      _tagIds.contains(id) ? _tagIds.remove(id) : _tagIds.add(id);
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    final total = _parseCents(_totalController.text);
    if (name.isEmpty) {
      setState(() => _error = '请填写专项追踪名称');
      return;
    }
    if (_bookId == null ||
        !widget.books.any((option) => option.id == _bookId)) {
      setState(() => _error = '请选择所属账本');
      return;
    }
    if (total == null || total < 0) {
      setState(() => _error = '请填写不小于 0 且最多两位小数的总额');
      return;
    }
    if (_end.isBefore(_start)) {
      setState(() => _error = '结束日期不能早于开始日期');
      return;
    }
    if (_categoryKeys.isEmpty && _tagIds.isEmpty) {
      setState(() => _error = '至少选择一个分类或标签');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Future<void>.sync(() => widget.onSave(
            BudgetSpecialTrackingSaveCommand(
              planId: widget.initialDraft?.planId,
              name: name,
              startInclusive: _start,
              endInclusive: _end,
              totalCents: total,
              bookId: _bookId!,
              categoryKeys: _categoryKeys,
              tagIds: _tagIds,
            ),
          ));
      if (mounted) Navigator.of(context).maybePop();
    } catch (error) {
      if (mounted) {
        setState(() => _error = _friendlyError(error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedBook =
        widget.books.where((option) => option.id == _bookId).firstOrNull;
    final selectedCount = _categoryKeys.length + _tagIds.length;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: _editing ? '编辑专项追踪' : '新建专项追踪',
            subtitle: '专项只观察所选支出，不增加日常可花额度',
            onClose: widget.onClose ?? () => Navigator.maybePop(context),
            actionLabel: '保存',
            actionKey: const ValueKey('budget-special-save'),
            onAction: _saving ? null : _submit,
          ),
          Flexible(
            child: ListView(
              key: const ValueKey('budget-special-form'),
              padding: const EdgeInsets.only(bottom: 28),
              children: [
                const SettingsSectionLabel('基本信息'),
                SettingsGroup(
                  children: [
                    _FieldRow(
                      label: '名称',
                      child: TextField(
                        key: const ValueKey('budget-special-name'),
                        controller: _nameController,
                        maxLength: 30,
                        textInputAction: TextInputAction.next,
                        decoration: iosInputDecoration(
                          context,
                          hint: '例如：国庆旅行',
                        ),
                      ),
                    ),
                    SettingsRow(
                      title: '起止日期',
                      subtitle: '${_date(_start)} - ${_date(_end)}',
                      trailing: const Icon(Icons.calendar_month_outlined),
                      onTap: _pickRange,
                    ),
                    _FieldRow(
                      label: '总额',
                      child: TextField(
                        key: const ValueKey('budget-special-total'),
                        controller: _totalController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: iosInputDecoration(
                          context,
                          hint: '0.00',
                          prefix: '¥ ',
                        ),
                      ),
                    ),
                    Builder(
                      builder: (menuContext) => SettingsRow(
                        title: '所属账本',
                        subtitle: selectedBook == null
                            ? '请选择'
                            : '${selectedBook.icon} ${selectedBook.name}',
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showBookMenu(menuContext),
                      ),
                    ),
                  ],
                ),
                SettingsSectionLabel(
                  selectedCount == 0
                      ? '消费范围（至少选择一项）'
                      : '消费范围（已选 $selectedCount 项）',
                ),
                if (widget.categories.isNotEmpty) ...[
                  SettingsGroup(
                    children: [
                      for (final category in widget.categories)
                        SettingsRow(
                          leading: Text(
                            category.icon,
                            style: const TextStyle(fontSize: 20),
                          ),
                          title: category.name,
                          trailing: AppCheckmark(
                            interactive: false,
                            key: ValueKey(
                              'budget-special-category-${category.key}',
                            ),
                            value: _categoryKeys.contains(category.key),
                            onChanged: null,
                          ),
                          onTap: () => _toggleCategory(category.key),
                        ),
                    ],
                  ),
                ],
                if (widget.tags.isNotEmpty) ...[
                  const SettingsSectionLabel('标签'),
                  SettingsGroup(
                    children: [
                      for (final tag in widget.tags)
                        SettingsRow(
                          leading: _TagSwatch(color: Color(tag.colorValue)),
                          title: tag.name,
                          trailing: AppCheckmark(
                            interactive: false,
                            key: ValueKey('budget-special-tag-${tag.id}'),
                            value: _tagIds.contains(tag.id),
                            onChanged: null,
                          ),
                          onTap: () => _toggleTag(tag.id),
                        ),
                    ],
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: Text(
                      _error!,
                      key: const ValueKey('budget-special-error'),
                      style: AppType.secondary(scheme).copyWith(
                        color: AppColors.warning,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BudgetSpecialTrackingCard extends StatelessWidget {
  final String name;
  final DateTime startInclusive;
  final DateTime endInclusive;
  final int totalCents;
  final int spentCents;
  final String scopeSummary;
  final BudgetSpecialLifecycleStatus lifecycleStatus;
  final VoidCallback? onEdit;
  final VoidCallback? onArchive;

  const BudgetSpecialTrackingCard({
    super.key,
    required this.name,
    required this.startInclusive,
    required this.endInclusive,
    required this.totalCents,
    required this.spentCents,
    required this.scopeSummary,
    required this.lifecycleStatus,
    this.onEdit,
    this.onArchive,
  });

  int get remainingCents => totalCents - spentCents;
  bool get isOverBudget => spentCents > totalCents;
  bool get isNearLimit =>
      totalCents > 0 &&
      spentCents <= totalCents &&
      spentCents * 100 >= totalCents * 80;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = isOverBudget
        ? AppColors.warning
        : isNearLimit
            ? AppColors.income(scheme)
            : AppColors.budgetHealthy(scheme);
    final status = _statusLabel(
      lifecycleStatus,
      overBudget: isOverBudget,
      nearLimit: isNearLimit,
    );
    final progress = totalCents <= 0
        ? (spentCents > 0 ? 1.0 : 0.0)
        : (spentCents / totalCents).clamp(0.0, 1.0);
    return Container(
      key: const ValueKey('budget-special-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.hairline(scheme)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowTitle(scheme),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_date(startInclusive)} - ${_date(endInclusive)}',
                      style: AppType.caption(scheme),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _StatusLabel(label: status, color: accent),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '已用 ${_money(spentCents)} / ${_money(totalCents)}',
            key: const ValueKey('budget-special-card-amount'),
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          BudgetProgressBar(
            value: progress,
            height: 6,
            activeColor: accent,
          ),
          const SizedBox(height: 8),
          Text(
            remainingCents < 0
                ? '已超出 ${_money(-remainingCents)}'
                : '剩余 ${_money(remainingCents)}',
            style: AppType.secondary(scheme).copyWith(
              color: remainingCents < 0 ? AppColors.warning : null,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.filter_alt_outlined,
                size: 16,
                color: AppTextColor.secondary(scheme),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  scopeSummary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption(scheme),
                ),
              ),
              if (onEdit != null) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: '编辑专项追踪',
                  child: AppCircleButton(
                    icon: Icons.edit_outlined,
                    size: 34,
                    iconSize: 18,
                    onPressed: onEdit,
                  ),
                ),
              ],
              if (onArchive != null) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: '归档专项追踪',
                  child: AppCircleButton(
                    icon: Icons.archive_outlined,
                    size: 34,
                    iconSize: 18,
                    onPressed: onArchive,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _FieldRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: AppLabeledField(label: label, child: child),
      );
}

class _TagSwatch extends StatelessWidget {
  final Color color;

  const _TagSwatch({required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _StatusLabel extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppType.caption(Theme.of(context).colorScheme).copyWith(
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
}

String _statusLabel(
  BudgetSpecialLifecycleStatus lifecycle, {
  required bool overBudget,
  required bool nearLimit,
}) =>
    switch (lifecycle) {
      BudgetSpecialLifecycleStatus.archived => '已归档',
      BudgetSpecialLifecycleStatus.upcoming => '即将开始',
      BudgetSpecialLifecycleStatus.ended => '已结束',
      BudgetSpecialLifecycleStatus.inProgress => overBudget
          ? '已超支'
          : nearLimit
              ? '接近上限'
              : '使用中',
    };

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

String _date(DateTime value) => '${value.year}/${value.month}/${value.day}';

String _centsInput(int cents) {
  final negative = cents < 0;
  final absolute = cents.abs();
  return '${negative ? '-' : ''}${absolute ~/ 100}.'
      '${(absolute % 100).toString().padLeft(2, '0')}';
}

int? _parseCents(String raw) {
  final value = raw.trim();
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(value);
  if (match == null) return null;
  final whole = int.tryParse(match.group(1)!);
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  if (whole == null) return null;
  return whole * 100 + int.parse(fraction);
}

String _money(int cents) => MoneyFormat.string(
      _decimalFromCents(cents),
    );

Decimal _decimalFromCents(int cents) {
  final negative = cents < 0;
  final absolute = cents.abs();
  return Decimal.parse(
    '${negative ? '-' : ''}${absolute ~/ 100}.'
    '${(absolute % 100).toString().padLeft(2, '0')}',
  );
}

String _friendlyError(Object error) => error
    .toString()
    .replaceFirst('Bad state: ', '')
    .replaceFirst('Invalid argument(s): ', '');
