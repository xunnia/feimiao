import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:charset_converter/charset_converter.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/import/bill_import.dart';
import '../../widgets/app_buttons.dart';
import '../../core/models/transaction_kind.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import 'bill_review_view.dart';

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
      final file = File('${dir.path}/肥喵记账_${bookName}_$stamp.csv');
      // 加 UTF-8 BOM，Excel 打开不乱码
      await file.writeAsString('﻿$csv');

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: '肥喵账单导出',
        text: '肥喵「$bookName」账单（共 ${txs.length} 笔）',
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
        allowedExtensions: ['csv', 'txt', 'xlsx', 'xls'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) {
        _setMessage('已取消');
        return;
      }
      final f = picked.files.first;
      Uint8List? bytes = f.bytes;
      if (bytes == null && f.path != null) {
        bytes = await File(f.path!).readAsBytes();
      }
      if (bytes == null) {
        _setMessage('读不到文件内容');
        return;
      }

      final ext = (f.extension ?? '').toLowerCase();
      final BillParseResult result;
      if (ext == 'xlsx' || ext == 'xls') {
        final table = _xlsxToTable(bytes);
        result = BillImporter.parseRows(table);
      } else {
        final text = await _decodeCsvBytes(bytes);
        result = BillImporter.parseString(text);
      }
      if (result.rows.isEmpty) {
        final diag = result.totalRows == 0
            ? '文件读出来是空的（可能编码不对或不是表格）'
            : !result.headerFound
                ? '读到 ${result.totalRows} 行，但没找到「金额/时间」表头行'
                : '找到了表头，但没有可识别的账目行';
        _setMessage('导入失败：识别为「${result.source}」，$diag。把文件发我看看就能修。');
        return;
      }
      if (!mounted) return;
      // 进复核页：每行先自动归类，剩余按商户分组让用户确认/AI 兜底，确认后入库。
      final count = await Navigator.of(context).push<int>(
        MaterialPageRoute(
          builder: (_) => BillReviewView(
            rows: result.rows,
            source: result.source,
            skipped: result.skipped,
          ),
        ),
      );
      if (count != null) {
        final skip =
            result.skipped > 0 ? '，跳过 ${result.skipped} 笔（中性/无效）' : '';
        _setMessage('成功导入 $count 笔$skip 🎉');
      } else {
        _setMessage('已取消导入');
      }
    } catch (e) {
      _setMessage('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 把 CSV 字节解码成文本：先严格 UTF-8，失败则用系统原生 GBK 解码
  /// （支付宝账单是 GBK），再不行退化为宽松 UTF-8。
  Future<String> _decodeCsvBytes(Uint8List bytes) async {
    // 去掉 UTF-8 BOM
    var b = bytes;
    if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
      b = b.sublist(3);
    }
    try {
      return const Utf8Decoder(allowMalformed: false).convert(b);
    } catch (_) {/* 不是 UTF-8，试 GBK */}
    try {
      return await CharsetConverter.decode('GBK', b);
    } catch (_) {
      return utf8.decode(b, allowMalformed: true);
    }
  }

  /// 把 xlsx 字节解析成二维字符串表格（取第一个有数据的工作表）。
  List<List<String>> _xlsxToTable(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    for (final name in excel.tables.keys) {
      final sheet = excel.tables[name];
      if (sheet == null || sheet.rows.isEmpty) continue;
      final table = <List<String>>[];
      for (final row in sheet.rows) {
        table.add([
          for (final cell in row) (cell?.value?.toString() ?? '').trim(),
        ]);
      }
      if (table.isNotEmpty) return table;
    }
    return const [];
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(leading: const AppBackButton(), title: const Text('导入导出'), centerTitle: true),
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
            title: '导入账单（CSV / Excel）',
            subtitle: '支持微信、支付宝、咔皮、木木等主流账单，CSV 和 Excel(xlsx) 都能读，'
                '自动识别格式与编码',
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
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Text(
            '· 支持微信/支付宝/咔皮/木木等账单，自动跳过文件顶部说明行、识别 UTF-8/GBK 编码。\n'
            '· 导入只增不删，不会覆盖已有账目；导入前可先在抽屉新建一个账本隔离。\n'
            '· 中性/不计收支的记录（如理财、还款）会自动跳过。\n'
            '· 微信/支付宝没有分类，会先记为「未分类」，并把交易对方/商品写进备注，方便事后整理。\n'
            '· 导入的账目都归到当前账本的默认账户。',
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
    return Container(
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
                          ?.copyWith(fontWeight: FontWeight.w600)),
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
