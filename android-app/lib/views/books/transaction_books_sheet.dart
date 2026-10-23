import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_date_picker.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/settings_ui.dart';
import '../../widgets/sliding_segment.dart';
import '../common/app_sheet.dart';

/// 返回明确确认的关联集合；取消返回 null。总账本是全量视图，不参与勾选。
Future<Set<int>?> showTransactionBooksSheet(
  BuildContext context, {
  required Iterable<int> selectedIds,
}) =>
    showBlurSheet<Set<int>>(
      context,
      child: TransactionBooksSheet(selectedIds: selectedIds.toSet()),
    );

class TransactionBooksSheet extends StatefulWidget {
  final Set<int> selectedIds;

  const TransactionBooksSheet({super.key, required this.selectedIds});

  @override
  State<TransactionBooksSheet> createState() => _TransactionBooksSheetState();
}

class _TransactionBooksSheetState extends State<TransactionBooksSheet> {
  late final Set<int> _selected = Set.of(widget.selectedIds);

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final scheme = Theme.of(context).colorScheme;
    final books = repo.books.where((b) => b.id != repo.defaultBookId).toList();
    final validIds = books.map((b) => b.id).toSet();
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(
              title: MediaQuery.textScalerOf(context).scale(16) > 22
                  ? '账本'
                  : '选择账本',
              subtitle: '总账本自动包含全部账单',
              onClose: () => Navigator.pop(context),
              actionLabel: '确定',
              onAction: () =>
                  Navigator.pop(context, _selected.intersection(validIds)),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (books.isNotEmpty)
                      SettingsGroup(children: [
                        for (final book in books)
                          SettingsRow(
                            title: book.name,
                            subtitle: book.remark.isEmpty ? null : book.remark,
                            leading: AppCheckmark(
                              value: _selected.contains(book.id),
                              interactive: false,
                              onChanged: null,
                            ),
                            onTap: () {
                              Haptics.selection();
                              setState(() {
                                if (!_selected.add(book.id)) {
                                  _selected.remove(book.id);
                                }
                              });
                            },
                          ),
                      ]),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                      child: Text(
                        books.isEmpty
                            ? '还没有场景账本，可以在抽屉中新建。当前账单保留在总账本。'
                            : '可同时选择多个账本。不选场景账本时，仅保留在总账本；不会复制账单或重复扣款。',
                        style: AppType.secondary(scheme),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
              subtitle: widget.book.name,
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
    final validIds = repo.allTransactions.map((t) => t.id).toSet();
    final selected = _selected.intersection(validIds);
    final allVisibleSelected = transactions.isNotEmpty &&
        transactions.every((t) => selected.contains(t.id));
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
              subtitle: widget.book.name,
              onClose: _saving ? null : () => Navigator.pop(context),
              actionLabel: _removing ? '移出' : '添加',
              onAction: _saving || selected.isEmpty ? null : _save,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SlidingSegment<bool>(
                items: const [(false, '添加已有'), (true, '移出关联')],
                height: MediaQuery.textScalerOf(context).scale(13) + 21,
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                key: const ValueKey('book-transactions-search'),
                controller: _search,
                enabled: !_saving,
                style: AppType.body(scheme),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                decoration: iosInputDecoration(context, hint: '搜索备注、分类、账户或金额'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Wrap(spacing: 12, runSpacing: 4, children: [
                Builder(
                    builder: (anchor) => TextButton(
                          onPressed: _saving
                              ? null
                              : () => showIosMenu(anchor, [
                                    for (final option
                                        in <(TransactionKind?, String)>[
                                      (null, '全部类型'),
                                      (TransactionKind.expense, '支出'),
                                      (TransactionKind.income, '收入'),
                                      (TransactionKind.transfer, '转账'),
                                    ])
                                      IosMenuItem(
                                          label: option.$2,
                                          selected: _kind == option.$1,
                                          onTap: () => setState(
                                              () => _kind = option.$1)),
                                  ]),
                          child:
                              Text(kindLabel, style: AppType.secondary(scheme)),
                        )),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          final result = await showAppDateRangePicker(context,
                              initial: _range,
                              first: DateTime(2000),
                              last: DateTime(2100));
                          if (mounted && result != null) {
                            setState(() => _range = result);
                          }
                        },
                  child: Text(
                      _range == null
                          ? '全部日期'
                          : '${_range!.start.month}/${_range!.start.day}—${_range!.end.month}/${_range!.end.day}',
                      style: AppType.secondary(scheme)),
                ),
                if (_range != null || _kind != null || _search.text.isNotEmpty)
                  TextButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                                _range = null;
                                _kind = null;
                                _search.clear();
                              }),
                      child: Text('清除筛选', style: AppType.secondary(scheme))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Expanded(
                    child: Text(
                        _saving
                            ? '保存中，请稍候'
                            : '已选 ${selected.length} 笔 · 筛选出 ${transactions.length} 笔',
                        style: AppType.secondary(scheme))),
                TextButton(
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
                  child: Text(allVisibleSelected ? '取消全选' : '全选',
                      style: AppType.secondary(scheme)),
                ),
              ]),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                itemCount: transactions.length,
                itemBuilder: (context, index) {
                  final t = transactions[index];
                  final value = selected.contains(t.id);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SettingsGroup(children: [
                      SettingsRow(
                        title: t.note.isNotEmpty
                            ? t.note
                            : (t.categoryNameZh.isEmpty
                                ? '转账'
                                : t.categoryNameZh),
                        subtitle:
                            '${t.date.year}年${t.date.month}月${t.date.day}日 · '
                            '${t.txKind == TransactionKind.income ? '收入' : t.txKind == TransactionKind.transfer ? '转账' : '支出'} '
                            '${MoneyFormat.string(t.amount, currencyCode: t.currencyCode)}',
                        leading: AppCheckmark(
                            value: value, onChanged: null, interactive: false),
                        onTap: _saving
                            ? null
                            : () {
                                Haptics.selection();
                                setState(() {
                                  if (!_selected.add(t.id)) {
                                    _selected.remove(t.id);
                                  }
                                });
                              },
                      )
                    ]),
                  );
                },
              ),
            ),
            if (MediaQuery.viewInsetsOf(context).bottom == 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                child: Text(
                    _removing
                        ? '仅解除当前账本关联。总账本、其他账本、账户余额和退款记录不变。'
                        : '总账本自动包含全部账单；添加后不会复制账单，也不会重复扣款。',
                    style: AppType.caption(scheme)),
              ),
          ]),
        ),
      ),
    );
  }
}
