import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:decimal/decimal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/transaction_kind.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import 'tags_view.dart';

/// 导入导出页：把当前账本导出成 CSV（可分享/备份），或从 CSV 批量导入。
///
/// CSV 表头（中文，方便用户用 Excel/WPS 打开）：
///   日期,类型,分类,金额,账户,备注,标签
/// 日期格式 yyyy-MM-dd HH:mm；类型为 支出/收入/转账；标签用「|」分隔。
class ImportExportView extends StatefulWidget {
  const ImportExportView({super.key});

  @override
  State<ImportExportView> createState() => _ImportExportViewState();
}

class _ImportExportViewState extends State<ImportExportView> {
  static const _header = ['日期', '类型', '分类', '金额', '账户', '备注', '标签'];
  final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');

  bool _busy = false;
  String? _message;

  void _setMessage(String m) {
    if (mounted) setState(() => _message = m);
  }

  // ── 导出 ──────────────────────────────────────────────────────────────
  Future<void> _export() async {
    final repo = context.read<AppRepository>();
    final txs = repo.transactions;
    if (txs.isEmpty) {
      _setMessage('当前账本没有账目可导出');
      return;
    }
    setState(() => _busy = true);
    try {
      final rows = <List<String>>[_header];
      for (final t in txs) {
        final tagNames = t.tagIds
            .map((id) => repo.tagName(id))
            .whereType<String>()
            .join('|');
        rows.add([
          _dateFmt.format(t.date),
          _kindZh(t.txKind),
          t.txKind == TransactionKind.transfer
              ? '${t.accountName}→${t.toAccountName}'
              : (t.categoryNameZh.isNotEmpty ? t.categoryNameZh : '未分类'),
          t.amount.toString(),
          t.accountName,
          t.note,
          tagNames,
        ]);
      }
      final csv = const ListToCsvConverter().convert(rows);

      final dir = await getTemporaryDirectory();
      final bookName = repo.currentBook?.name ?? '账本';
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final file = File('${dir.path}/轻记_${bookName}_$stamp.csv');
      // 加 UTF-8 BOM，Excel 打开不乱码
      await file.writeAsString('﻿$csv');

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: '轻记账单导出',
        text: '轻记「$bookName」账单（共 ${txs.length} 笔）',
      );
      _setMessage('已导出 ${txs.length} 笔，去分享面板里保存或发送吧');
    } catch (e) {
      _setMessage('导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── 导入 ──────────────────────────────────────────────────────────────
  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) {
        _setMessage('已取消');
        return;
      }
      final f = picked.files.first;
      String content;
      if (f.bytes != null) {
        content = utf8.decode(f.bytes!, allowMalformed: true);
      } else if (f.path != null) {
        content = await File(f.path!).readAsString();
      } else {
        _setMessage('读不到文件内容');
        return;
      }
      // 去掉可能的 BOM
      if (content.isNotEmpty && content.codeUnitAt(0) == 0xFEFF) {
        content = content.substring(1);
      }

      final table = const CsvToListConverter(
        shouldParseNumbers: false,
        eol: '\n',
      ).convert(content.replaceAll('\r\n', '\n'));

      final count = await _ingest(table);
      _setMessage(count > 0 ? '成功导入 $count 笔账目 🎉' : '没有可导入的有效行');
    } catch (e) {
      _setMessage('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 解析表格行 → 解析分类/账户/标签 → 批量写库。返回导入条数。
  Future<int> _ingest(List<List<dynamic>> table) async {
    final repo = context.read<AppRepository>();
    if (table.isEmpty) return 0;

    // 跳过表头（首行含「日期」或「金额」字样即认作表头）
    var start = 0;
    final first = table.first.map((e) => e.toString()).join(',');
    if (first.contains('日期') || first.contains('金额')) start = 1;

    // 默认账户（导入时账户名匹配不到就用它）
    final fallbackAccountId = repo.accounts.firstOrNull?.id;
    if (fallbackAccountId == null) return 0;

    // 标签名 → id 缓存（缺失则新建）
    final tagCache = <String, int>{
      for (final t in repo.tags) t.name: t.id,
    };
    // 账户名 → id 缓存（缺失则新建）
    final accountCache = <String, int>{
      for (final a in repo.accounts) a.name: a.id,
    };

    final drafts = <TransactionDraft>[];
    for (var i = start; i < table.length; i++) {
      final row = table[i].map((e) => e.toString().trim()).toList();
      if (row.length < 4) continue; // 至少要日期/类型/分类/金额
      final dateStr = row[0];
      final kindStr = row.length > 1 ? row[1] : '';
      final categoryStr = row.length > 2 ? row[2] : '';
      final amountStr = row.length > 3 ? row[3] : '';
      final accountStr = row.length > 4 ? row[4] : '';
      final note = row.length > 5 ? row[5] : '';
      final tagStr = row.length > 6 ? row[6] : '';

      final amount = Decimal.tryParse(amountStr.replaceAll(',', ''));
      if (amount == null || amount <= Decimal.zero) continue;

      final kind = _kindFromZh(kindStr);
      if (kind == TransactionKind.transfer) continue; // 转账暂不导入

      final date = _parseDate(dateStr) ?? DateTime.now();

      // 分类：按当前类型的中文名匹配，匹配不到留空（未分类）
      int? categoryId;
      for (final c in repo.categoriesForKind(kind)) {
        if (c.nameZh == categoryStr) {
          categoryId = c.id;
          break;
        }
      }

      // 账户
      int accountId = fallbackAccountId;
      if (accountStr.isNotEmpty) {
        final cached = accountCache[accountStr];
        if (cached != null) {
          accountId = cached;
        } else {
          final newId = await repo.addAccount(name: accountStr);
          accountCache[accountStr] = newId;
          accountId = newId;
        }
      }

      // 标签
      final tagIds = <int>[];
      if (tagStr.isNotEmpty) {
        for (final name in tagStr.split(RegExp(r'[|，,]'))) {
          final n = name.trim();
          if (n.isEmpty) continue;
          var id = tagCache[n];
          if (id == null) {
            id = await repo.addTag(
                name: n, colorValue: kTagPalette.first.toARGB32());
            tagCache[n] = id;
          }
          tagIds.add(id);
        }
      }

      drafts.add(TransactionDraft(
        kind: kind,
        amount: amount,
        categoryId: categoryId,
        accountId: accountId,
        note: note,
        date: date,
        tagIds: tagIds,
      ));
    }

    return repo.importTransactions(drafts);
  }

  DateTime? _parseDate(String s) {
    for (final fmt in [
      'yyyy-MM-dd HH:mm',
      'yyyy-MM-dd HH:mm:ss',
      'yyyy-MM-dd',
      'yyyy/MM/dd HH:mm',
      'yyyy/MM/dd',
    ]) {
      try {
        return DateFormat(fmt).parseStrict(s);
      } catch (_) {}
    }
    return DateTime.tryParse(s);
  }

  String _kindZh(TransactionKind k) {
    switch (k) {
      case TransactionKind.expense:
        return '支出';
      case TransactionKind.income:
        return '收入';
      case TransactionKind.transfer:
        return '转账';
    }
  }

  TransactionKind _kindFromZh(String s) {
    if (s.contains('收')) return TransactionKind.income;
    if (s.contains('转')) return TransactionKind.transfer;
    return TransactionKind.expense;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('导入导出'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ActionCard(
            icon: Icons.upload_file_outlined,
            color: scheme.primary,
            title: '导出为 CSV',
            subtitle: '把当前账本的全部账目导出成表格，可分享、备份或用 Excel/WPS 打开',
            buttonLabel: '导出',
            onPressed: _busy ? null : _export,
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.download_outlined,
            color: AppColors.income(scheme),
            title: '从 CSV 导入',
            subtitle: '选一个 CSV 文件批量导入账目。表头：日期,类型,分类,金额,账户,备注,标签',
            buttonLabel: '选择文件导入',
            onPressed: _busy ? null : _import,
          ),
          const SizedBox(height: 20),
          if (_busy)
            const Center(child: CircularProgressIndicator())
          else if (_message != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_message!)),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Text(
            '小贴士',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '· 导入只增不删，不会覆盖已有账目。\n'
            '· 转账类型暂不支持导入。\n'
            '· 分类名能对上现有分类才会归类，否则记为「未分类」。\n'
            '· 账户/标签名匹配不到时会自动新建。',
            style: TextStyle(
                color: scheme.onSurfaceVariant, height: 1.6, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback? onPressed;

  const _ActionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(subtitle,
                style: TextStyle(
                    color: scheme.onSurfaceVariant, height: 1.5, fontSize: 13)),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: onPressed,
                child: Text(buttonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
