import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';
import '../../core/models/transaction_kind.dart';
import '../../data/app_repository.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_date_picker.dart';
import '../../widgets/app_line_icon.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/settings_ui.dart';
import '../../widgets/sliding_segment.dart';
import '../../widgets/transaction_day_list.dart';
import '../common/app_sheet.dart';

/// 锚定账本芯片的多选菜单，只更新记账表单草稿；原账仍由保存入口写入。
Future<void> showTransactionBooksMenu(
  BuildContext anchorContext, {
  required Iterable<int> selectedIds,
  required ValueChanged<Set<int>> onChanged,
}) {
  final repo = anchorContext.read<AppRepository>();
  final books = repo.books.where((b) => b.id != repo.defaultBookId).toList();
  return showIosMultiSelectMenu<int>(
    anchorContext,
    cardKey: const ValueKey('book-picker-menu'),
    selectedValues: selectedIds.toSet(),
    onChanged: onChanged,
    choices: [
      for (final book in books)
        IosMenuChoice(
          value: book.id,
          label: book.name,
          subtitle: book.remark.isEmpty ? null : book.remark,
          icon: AppLineIcons.book,
        ),
    ],
    actions: [
      if (books.isEmpty)
        IosMenuItem(
          label: '暂无场景账本',
          lineIcon: AppLineIcons.book,
          enabled: false,
          onTap: () {},
        ),
    ],
  );
}

Future<void> showBookTransactionsSheet(BuildContext context,
        {required BookEntity book, bool removeOnly = false}) =>
    showBlurSheet<void>(context,
        child: BookTransactionsSheet(book: book, removeOnly: removeOnly));

/// 历史账单批量归集只修改账本关联，绝不复制或删除原始账单。
class BookTransactionsSheet extends StatefulWidget {
  final BookEntity book;
  final bool removeOnly;

  const BookTransactionsSheet(
      {super.key, required this.book, this.removeOnly = false});

  @override
  State<BookTransactionsSheet> createState() => _BookTransactionsSheetState();
}

class _BookTransactionsSheetState extends State<BookTransactionsSheet> {
  final _search = TextEditingController();
  final Set<int> _selected = {};
  late bool _removing = widget.removeOnly;
  TransactionKind? _kind;
  DateTimeRange? _range;
  bool _saving = false;
  AppRepository? _repository;
  bool _historyReady = false;
  bool _historyLoading = false;
  bool _historyFailed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repository != null) return;
    _repository = context.read<AppRepository>();
    if (_repository!.isFullyReady) {
      _historyReady = true;
    } else {
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    if (_historyLoading) return;
    setState(() {
      _historyLoading = true;
      _historyFailed = false;
    });
    try {
      final repo = _repository!;
      await repo.finishDeferredInitialization();
      if (!repo.isFullyReady) throw StateError('历史账单尚未加载完成');
      if (mounted) setState(() => _historyReady = true);
    } catch (_) {
      if (mounted) setState(() => _historyFailed = true);
    } finally {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<TransactionEntity> _candidates(AppRepository repo) {
    final query = _search.text.trim().toLowerCase();
    final end = _range == null
        ? null
        : DateTime(_range!.end.year, _range!.end.month, _range!.end.day + 1);
    return repo.allTransactions.where((t) {
      if (t.refundOf != null) return false;
      final linked = repo.transactionBookIds(t).contains(widget.book.id);
      if (_removing != linked) return false;
      if (_kind != null && t.txKind != _kind) return false;
      if (_range != null &&
          (t.date.isBefore(_range!.start) || !t.date.isBefore(end!))) {
        return false;
      }
      return query.isEmpty ||
          '${t.note} ${t.categoryNameZh} ${t.accountName} ${t.amountStr}'
              .toLowerCase()
              .contains(query);
    }).toList()
      ..sort((a, b) => b.dateMs.compareTo(a.dateMs));
  }

  Future<void> _save() async {
    if (_saving || !_historyReady || _selected.isEmpty) return;
    final repo = context.read<AppRepository>();
    if (!repo.isFullyReady) return;
    final existingIds = repo.allTransactions
        .where((t) => t.refundOf == null)
        .map((t) => t.id)
        .toSet();
    final ids = _selected.intersection(existingIds);
    if (ids.isEmpty) return;
    setState(() => _saving = true);
    try {
      await repo.setTransactionBooks(ids, [widget.book.id],
          addOnly: !_removing, removeOnly: _removing);
      if (!mounted) return;
      Haptics.of(Haptic.success);
      showAppToast(
          context,
          _removing
              ? '已移出 ${ids.length} 笔，原始账单仍保留'
              : '已添加 ${ids.length} 笔已有账单');
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        showAppToast(context, error.toString().replaceFirst('Bad state: ', ''),
            icon: Icons.info_outline);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _filterBar(List<TransactionEntity> transactions, Set<int> selected,
      bool allVisibleSelected, String kindLabel, bool hasFilters) {
    final scheme = Theme.of(context).colorScheme;
    final style = AppType.secondary(scheme);
    final dateLabel = _range == null
        ? '全部日期'
        : '${_range!.start.month}/${_range!.start.day}—${_range!.end.month}/${_range!.end.day}';
    final status = _saving
        ? '保存中，请稍候'
        : selected.isNotEmpty
            ? '已选 ${selected.length} 笔'
            : hasFilters
                ? '筛选出 ${transactions.length} 笔'
                : null;
    final allLabel = allVisibleSelected ? '取消全选' : '全选';
    final buttonStyle = TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        alignment: Alignment.centerLeft);
    Widget filterLabel(String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: style),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded,
                size: 16, color: scheme.onSurface.withValues(alpha: .55)),
          ],
        );
    final kindFilter = Builder(
      builder: (anchor) => TextButton(
        key: const ValueKey('book-transactions-kind'),
        style: buttonStyle,
        onPressed: _saving
            ? null
            : () => showIosMenu(anchor, [
                  for (final option in <(TransactionKind?, String)>[
                    (null, '全部类型'),
                    (TransactionKind.expense, '支出'),
                    (TransactionKind.income, '收入'),
                    (TransactionKind.transfer, '转账'),
                  ])
                    IosMenuItem(
                      label: option.$2,
                      lineIcon: switch (option.$1) {
                        TransactionKind.expense => AppLineIcons.receipt,
                        TransactionKind.income => AppLineIcons.wallet,
                        TransactionKind.transfer => AppLineIcons.importExport,
                        _ => AppLineIcons.grid,
                      },
                      selected: _kind == option.$1,
                      onTap: () => setState(() => _kind = option.$1),
                    ),
                ]),
        child: filterLabel(kindLabel),
      ),
    );
    final dateFilter = TextButton(
      key: const ValueKey('book-transactions-date'),
      style: buttonStyle,
      onPressed: _saving
          ? null
          : () async {
              final result = await showAppDateRangePicker(context,
                  initial: _range, first: DateTime(2000), last: DateTime(2100));
              if (mounted && result != null) {
                setState(() => _range = result);
              }
            },
      child: filterLabel(dateLabel),
    );
    final selectAll = TextButton(
      key: const ValueKey('book-transactions-select-all'),
      style: buttonStyle,
      onPressed: _saving || transactions.isEmpty
          ? null
          : () => setState(() {
                for (final t in transactions) {
                  if (allVisibleSelected) {
                    _selected.remove(t.id);
                  } else {
                    _selected.add(t.id);
                  }
                }
              }),
      child: Text(allLabel, style: style),
    );
    final statusText = status == null
        ? null
        : Text(status,
            key: const ValueKey('book-transactions-status'), style: style);
    return Padding(
      key: const ValueKey('book-transactions-filter-bar'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: LayoutBuilder(builder: (context, constraints) {
        double textWidth(String text) {
          final painter = TextPainter(
            text: TextSpan(
                text: text,
                style: DefaultTextStyle.of(context).style.merge(style)),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            locale: Localizations.maybeLocaleOf(context),
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        }

        final requiredWidth = textWidth(kindLabel) +
            textWidth(dateLabel) +
            40 +
            24 +
            textWidth(allLabel) +
            (status == null ? 0 : textWidth(status) + 12);
        if (requiredWidth <= constraints.maxWidth) {
          return Row(children: [
            kindFilter,
            const SizedBox(width: 12),
            dateFilter,
            const Spacer(),
            if (statusText != null) ...[
              statusText,
              const SizedBox(width: 12),
            ],
            selectAll,
          ]);
        }
        // Preserve readable text at narrow widths and accessibility sizes.
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 12, children: [kindFilter, dateFilter]),
          Row(children: [
            if (statusText != null)
              Expanded(child: statusText)
            else
              const Spacer(),
            const SizedBox(width: 12),
            selectAll,
          ]),
        ]);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final scheme = Theme.of(context).colorScheme;
    // Fast startup exposes only the current-month window. Never present that
    // partial snapshot as the complete set of historical transactions.
    if (!_historyReady || !repo.isFullyReady) {
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .9,
          child: Column(children: [
            SheetHeader(
              title: MediaQuery.textScalerOf(context).scale(16) > 22
                  ? (_removing ? '移出' : '归集')
                  : (_removing ? '移出关联' : '已有账单'),
              onClose: () => Navigator.pop(context),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (!_historyFailed)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: CircularProgressIndicator.adaptive(),
                      ),
                    Text(
                      _historyFailed ? '历史账单加载失败，请重试' : '正在加载完整账单…',
                      textAlign: TextAlign.center,
                      style: AppType.body(scheme),
                    ),
                    if (_historyFailed)
                      TextButton(
                        onPressed: _historyLoading ? null : _loadHistory,
                        child: Text('重试', style: AppType.secondary(scheme)),
                      ),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      );
    }
    final transactions = _candidates(repo);
    final sections = groupTxnsByDay(transactions);
    final validIds = repo.allTransactions.map((t) => t.id).toSet();
    final selected = _selected.intersection(validIds);
    final allVisibleSelected = transactions.isNotEmpty &&
        transactions.every((t) => selected.contains(t.id));
    final hasFilters =
        _range != null || _kind != null || _search.text.trim().isNotEmpty;
    final kindLabel = switch (_kind) {
      TransactionKind.expense => '支出',
      TransactionKind.income => '收入',
      TransactionKind.transfer => '转账',
      _ => '全部类型',
    };
    return PopScope(
      canPop: !_saving,
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .9,
          child: Column(children: [
            SheetHeader(
              title: MediaQuery.textScalerOf(context).scale(16) > 22
                  ? (_removing ? '移出' : '归集')
                  : (_removing ? '移出关联' : '已有账单'),
              onClose: _saving ? null : () => Navigator.pop(context),
              actionLabel: _removing ? '移出' : '添加',
              onAction: _saving || selected.isEmpty ? null : _save,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: LayoutBuilder(builder: (context, constraints) {
                final scaler = MediaQuery.textScalerOf(context);
                final large = scaler.scale(13) > 18;
                // Keep room for search at 320dp / 200%, with two-line segment
                // labels instead of shrinking the user's preferred text size.
                final segmentWidth = (large ? 230.0 : 160.0)
                    .clamp(0.0, constraints.maxWidth - 108);
                return Row(children: [
                  SizedBox(
                    width: segmentWidth,
                    child: SlidingSegment<bool>(
                      key: const ValueKey('book-transactions-mode'),
                      items: large
                          ? const [(false, '添加\n已有'), (true, '移除\n关联')]
                          : const [(false, '添加已有'), (true, '移除关联')],
                      height: large ? scaler.scale(13) * 2.5 + 14 : 36,
                      value: _removing,
                      onChanged: (value) {
                        if (_saving) return;
                        setState(() {
                          _removing = value;
                          _selected.clear();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: TextField(
                    key: const ValueKey('book-transactions-search'),
                    controller: _search,
                    enabled: !_saving,
                    style: AppType.body(scheme),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    decoration:
                        iosInputDecoration(context, hint: '搜索').copyWith(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 9),
                      prefixIcon: large
                          ? null
                          : Icon(Icons.search_rounded,
                              size: 18,
                              color: scheme.onSurface.withValues(alpha: .45)),
                      prefixIconConstraints: const BoxConstraints(minWidth: 30),
                      suffixIconConstraints:
                          const BoxConstraints(minWidth: 32, maxWidth: 32),
                      suffixIcon: hasFilters
                          ? Tooltip(
                              message: '清除筛选',
                              child: PressableScale(
                                onPressed: _saving
                                    ? null
                                    : () => setState(() {
                                          _range = null;
                                          _kind = null;
                                          _search.clear();
                                        }),
                                child: SizedBox(
                                  width: 32,
                                  height: 40,
                                  child: Icon(Icons.close_rounded,
                                      size: 16,
                                      color: scheme.onSurface
                                          .withValues(alpha: .55)),
                                ),
                              ),
                            )
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  )),
                ]);
              }),
            ),
            _filterBar(transactions, selected, allVisibleSelected, kindLabel,
                hasFilters),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                itemCount: sections.length,
                itemBuilder: (context, index) {
                  return TxDayCard(
                    section: sections[index],
                    selectedIds: selected,
                    onSelectionChanged: _saving
                        ? null
                        : (t) {
                            setState(() {
                              if (!_selected.add(t.id)) {
                                _selected.remove(t.id);
                              }
                            });
                          },
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
