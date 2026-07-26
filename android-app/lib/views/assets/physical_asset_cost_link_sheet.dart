import 'package:decimal/decimal.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/budget/budget_window_resolver.dart';
import '../../core/money_format.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/mascot.dart';
import '../../widgets/settings_ui.dart';
import '../../widgets/sliding_segment.dart';
import '../common/app_sheet.dart';

enum PhysicalAssetCostType {
  maintenance,
  accessory,
  insurance,
  otherCost,
}

extension PhysicalAssetCostTypeX on PhysicalAssetCostType {
  String get storageKey => switch (this) {
        PhysicalAssetCostType.maintenance => 'maintenance',
        PhysicalAssetCostType.accessory => 'accessory',
        PhysicalAssetCostType.insurance => 'insurance',
        PhysicalAssetCostType.otherCost => 'other_cost',
      };

  String get label => switch (this) {
        PhysicalAssetCostType.maintenance => '维修保养',
        PhysicalAssetCostType.accessory => '配件',
        PhysicalAssetCostType.insurance => '保险',
        PhysicalAssetCostType.otherCost => '其他支出',
      };
}

class PhysicalAssetCostLinkCandidateData {
  final int transactionId;
  final String title;
  final DateTime date;
  final int amountCents;
  final String bookName;
  final bool alreadyLinked;

  const PhysicalAssetCostLinkCandidateData({
    required this.transactionId,
    required this.title,
    required this.date,
    required this.amountCents,
    required this.bookName,
    this.alreadyLinked = false,
  });
}

typedef PhysicalAssetCostCandidateLoader
    = Future<List<PhysicalAssetCostLinkCandidateData>> Function();
typedef PhysicalAssetCostLinkCallback = Future<void> Function(
  int transactionId,
  PhysicalAssetCostType costType,
);

Future<void> showPhysicalAssetCostLinkSheet(
  BuildContext context, {
  required PhysicalAssetCostCandidateLoader loadCandidates,
  required PhysicalAssetCostLinkCallback onLink,
}) {
  return showBlurSheet<void>(
    context,
    child: PhysicalAssetCostLinkSheet(
      loadCandidates: loadCandidates,
      onLink: onLink,
    ),
  );
}

class PhysicalAssetCostLinkSheet extends StatefulWidget {
  final PhysicalAssetCostCandidateLoader loadCandidates;
  final PhysicalAssetCostLinkCallback onLink;

  const PhysicalAssetCostLinkSheet({
    super.key,
    required this.loadCandidates,
    required this.onLink,
  });

  @override
  State<PhysicalAssetCostLinkSheet> createState() =>
      _PhysicalAssetCostLinkSheetState();
}

class _PhysicalAssetCostLinkSheetState
    extends State<PhysicalAssetCostLinkSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<PhysicalAssetCostLinkCandidateData> _candidates = const [];
  PhysicalAssetCostType _costType = PhysicalAssetCostType.maintenance;
  int? _selectedTransactionId;
  Object? _loadError;
  bool _loading = true;
  bool _submitting = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PhysicalAssetCostLinkCandidateData> get _filteredCandidates {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _candidates;
    return _candidates.where((candidate) {
      final haystack = <String>[
        candidate.title,
        candidate.bookName,
        _dateText(candidate.date),
        _plainAmount(candidate.amountCents),
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);
  }

  bool get _canSubmit {
    if (_loading || _submitting || _selectedTransactionId == null) {
      return false;
    }
    return _candidates.any(
      (candidate) =>
          candidate.transactionId == _selectedTransactionId &&
          !candidate.alreadyLinked,
    );
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
        _selectedTransactionId = null;
      });
    }
    try {
      final candidates = await widget.loadCandidates();
      if (!mounted) return;
      setState(() {
        _candidates = List.unmodifiable(candidates);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  void _updateQuery(String value) {
    setState(() {
      _query = value;
      final selected = _selectedTransactionId;
      if (selected != null &&
          !_filteredCandidates.any(
            (candidate) => candidate.transactionId == selected,
          )) {
        _selectedTransactionId = null;
      }
    });
  }

  void _select(PhysicalAssetCostLinkCandidateData candidate) {
    if (candidate.alreadyLinked || _submitting) return;
    setState(() => _selectedTransactionId = candidate.transactionId);
  }

  Future<void> _submit() async {
    if (!_canSubmit || _submitting) return;
    final transactionId = _selectedTransactionId!;
    setState(() => _submitting = true);
    try {
      await widget.onLink(transactionId, _costType);
      if (!mounted) return;
      showAppToast(context, '支出已关联');
      await Navigator.maybePop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showAppToast(context, '关联没有保存，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: '关联支出',
            subtitle: '选择一笔已有支出，记录这件物品后续发生的成本。',
            onClose: () => Navigator.pop(context),
            actionLabel: _submitting ? '关联中' : '关联',
            actionKey: const Key('physical-asset-cost-submit'),
            onAction: _canSubmit ? _submit : null,
          ),
          Flexible(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_loadError != null) {
      return _CostLinkMessage(
        icon: Icons.sync_problem_outlined,
        title: '暂时无法读取支出',
        message: '原账单和物品数据没有改变。',
        actionLabel: '重试',
        onAction: _load,
      );
    }
    if (_candidates.isEmpty) {
      return const _CostLinkMessage(
        mood: MascotMood.empty,
        title: '没有可关联的支出',
        message: '记下一笔支出后，再回来补充物品成本。',
      );
    }

    final filtered = _filteredCandidates;
    return ListView(
      key: const Key('physical-asset-cost-list'),
      padding: const EdgeInsets.only(bottom: 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: AppLabeledField(
            label: '搜索支出',
            child: TextField(
              key: const Key('physical-asset-cost-search'),
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: _updateQuery,
              decoration: iosInputDecoration(
                context,
                hint: '名称、账本、日期或金额',
              ).copyWith(
                prefixIcon: const Icon(CupertinoIcons.search, size: 18),
              ),
            ),
          ),
        ),
        const SettingsSectionLabel('支出类型'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SlidingSegment<PhysicalAssetCostType>(
            key: const Key('physical-asset-cost-type'),
            items: [
              for (final type in PhysicalAssetCostType.values)
                (type, type.label),
            ],
            value: _costType,
            onChanged: _submitting
                ? (_) {}
                : (value) => setState(() => _costType = value),
          ),
        ),
        SettingsSectionLabel('候选支出 · ${filtered.length}'),
        if (filtered.isEmpty)
          const _InlineEmptySearch()
        else
          SettingsGroup(
            key: const Key('physical-asset-cost-candidates'),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            children: [
              for (final candidate in filtered)
                _CostCandidateRow(
                  key: Key(
                    'physical-asset-cost-candidate-${candidate.transactionId}',
                  ),
                  candidate: candidate,
                  selected: candidate.transactionId == _selectedTransactionId,
                  onTap: () => _select(candidate),
                ),
            ],
          ),
      ],
    );
  }
}

class _CostCandidateRow extends StatelessWidget {
  final PhysicalAssetCostLinkCandidateData candidate;
  final bool selected;
  final VoidCallback onTap;

  const _CostCandidateRow({
    super.key,
    required this.candidate,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final disabled = candidate.alreadyLinked;
    return Semantics(
      button: !disabled,
      enabled: !disabled,
      selected: selected,
      label: '${candidate.title}，${_money(candidate.amountCents)}'
          '${disabled ? '，已关联' : ''}',
      child: SettingsRow(
        leading: Icon(
          selected ? Icons.check_circle : Icons.radio_button_unchecked,
          color: selected
              ? scheme.primary
              : AppTextColor.secondary(scheme).withValues(
                  alpha: disabled ? 0.42 : 0.8,
                ),
        ),
        title: candidate.title.trim().isEmpty ? '未命名支出' : candidate.title,
        subtitle: '${_dateText(candidate.date)} · '
            '${candidate.bookName.trim().isEmpty ? '未指定账本' : candidate.bookName}',
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _money(candidate.amountCents),
              style: AppType.rowTitle(scheme).copyWith(fontFamily: 'Nunito'),
            ),
            if (disabled) ...[
              const SizedBox(height: 2),
              Text('已关联', style: AppType.caption(scheme)),
            ],
          ],
        ),
        onTap: disabled ? null : onTap,
        titleColor: disabled ? AppTextColor.secondary(scheme) : null,
      ),
    );
  }
}

class _InlineEmptySearch extends StatelessWidget {
  const _InlineEmptySearch();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        children: [
          const Mascot(mood: MascotMood.empty, size: 64, animate: true),
          const SizedBox(height: 8),
          Text('没有匹配的支出', style: AppType.rowTitle(scheme)),
          const SizedBox(height: 4),
          Text('换个名称、账本或金额试试。', style: AppType.secondary(scheme)),
        ],
      ),
    );
  }
}

class _CostLinkMessage extends StatelessWidget {
  final IconData? icon;
  final MascotMood? mood;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _CostLinkMessage({
    this.icon,
    this.mood,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  }) : assert(icon != null || mood != null, '空态/异常态必须给图标或猫其一');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 空态用猫（守「空状态只放猫」标准）；加载失败等异常态仍用图标。
            if (mood != null)
              Mascot(mood: mood!, size: 72, animate: true)
            else
              Icon(icon, size: 38, color: AppTextColor.secondary(scheme)),
            const SizedBox(height: 12),
            Text(title, style: AppType.rowTitle(scheme)),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppType.secondary(scheme),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              AppPillButton(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

String _money(int cents) => MoneyFormat.string(
      budgetDecimalFromCents(cents) ?? Decimal.zero,
    );

String _plainAmount(int cents) {
  final amount = budgetDecimalFromCents(cents) ?? Decimal.zero;
  return amount.toStringAsFixed(2);
}

String _dateText(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
