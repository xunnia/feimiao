import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:charset_converter/charset_converter.dart';
import 'package:csv/csv.dart';
import 'package:decimal/decimal.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/account/account_movement_projection.dart';
import '../../core/export/export_range.dart';
import '../../core/import/bill_import.dart';
import '../../core/ledger/ledger_policy.dart';
import '../../core/transaction_time.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_date_picker.dart';
import '../../widgets/settings_ui.dart';
import '../../core/models/transaction_kind.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import 'bill_review_view.dart';
import '../common/app_sheet.dart';

/// 导入导出页：把当前账本导出成 CSV（可分享/备份），或从 CSV 批量导入。
///
/// CSV 表头（中文，方便用户用 Excel/WPS 打开）：
///   日期,时间精度,到账日期,到账日期质量,到账账户,到账账户质量,事件类型,...
/// 「日期」仍是消费/预算归属日，以兼容旧文件；到账日期为空代表未知，
/// 不得在重新导入时用归属日或导入当天补造。只有可靠时分才导出 HH:mm。
class ImportExportView extends StatefulWidget {
  const ImportExportView({super.key});

  @override
  State<ImportExportView> createState() => _ImportExportViewState();
}

class _ImportExportViewState extends State<ImportExportView> {
  static const _header = [
    '日期',
    '时间精度',
    '到账日期',
    '到账日期质量',
    '到账账户',
    '到账账户质量',
    '事件类型',
    '类型',
    '分类',
    '分类Key',
    '净额',
    '原始金额',
    '已退款',
    '计入收支',
    '账户',
    '转入账户',
    '备注',
    '标签',
    '可报销',
    '记录类型',
    '交易UUID',
    '退款归属UUID',
  ];
  final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');

  bool _busy = false;
  String? _message;

  void _setMessage(String m) {
    if (mounted) setState(() => _message = m);
  }

  Future<ExportRange?> _pickExportRange() async {
    final now = DateTime.now();
    final currentMonth = ExportRange.dayStart(DateTime(now.year, now.month, 1));
    final options = ExportRange.presets(now);

    return showBlurSheet<ExportRange>(
      context,
      child: ExportRangePickerSheet(
        options: options,
        defaultStart: currentMonth,
        defaultEnd: now,
      ),
    );
  }

  // ── 导出 ──────────────────────────────────────────────────────────────
  Future<void> _export() async {
    final repo = context.read<AppRepository>();
    final all = repo.transactions;
    final physicalAssetCount = repo.physicalAssets.length;
    final receivableAssetCount = repo.receivableAssets.length;
    final assetCount = physicalAssetCount + receivableAssetCount;
    if (all.isEmpty && assetCount == 0) {
      _setMessage('当前账本没有账目或资产可导出');
      return;
    }
    final range = await _pickExportRange();
    if (range == null || !mounted) return;
    final txs = all.where((t) => range.contains(t.date)).toList();
    if (txs.isEmpty && assetCount == 0) {
      _setMessage('${range.label}没有账目或资产可导出');
      return;
    }
    setState(() => _busy = true);
    try {
      final rows = <List<String>>[_header];
      final uuidOf = {for (final t in all) t.id: t.uuid};
      final refundTotals = LedgerPolicy.refundTotals(all);
      for (final t in txs) {
        final settlementAccountName = t.settlementAccountId == null
            ? ''
            : repo.accounts
                    .where((account) => account.id == t.settlementAccountId)
                    .firstOrNull
                    ?.name ??
                '';
        final tagNames = t.tagIds
            .map((id) => repo.tagName(id))
            .whereType<String>()
            .join('|');
        final net = LedgerPolicy.netAmountWith(t, refundTotals);
        final refunded = repo.refundedAmountOf(t.id);
        rows.add([
          _formatFeimiaoTransactionDate(t.date, t.timePrecision),
          t.timePrecision.storageKey,
          t.settledAt == null ? '' : _dateFmt.format(t.settledAt!),
          t.settlementQuality.storageKey,
          settlementAccountName,
          t.settlementAccountQuality.storageKey,
          t.eventType.storageKey,
          _kindZh(t.txKind),
          t.txKind == TransactionKind.transfer
              ? '${t.accountName}→${t.toAccountName}'
              : (t.categoryNameZh.isNotEmpty ? t.categoryNameZh : '未分类'),
          t.categoryKey,
          net.toString(),
          t.amount.toString(),
          refunded.toString(),
          t.excluded ? '否' : '是',
          t.accountName,
          t.toAccountName,
          t.note,
          tagNames,
          t.reimbursable ? '是' : '否',
          t.refundOf == null ? '账单' : '退款',
          t.uuid,
          t.refundOf == null ? '' : (uuidOf[t.refundOf] ?? ''),
        ]);
      }
      final csv = const ListToCsvConverter().convert(rows);

      final dir = await getTemporaryDirectory();
      final bookName = repo.currentBook?.name ?? '账本';
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final file = File(
        '${dir.path}/肥喵记账_${bookName}_${range.fileSuffix}_$stamp.csv',
      );
      // 加 UTF-8 BOM，Excel 打开不乱码
      await file.writeAsString('﻿$csv');

      final files = <XFile>[XFile(file.path, mimeType: 'text/csv')];
      if (assetCount > 0) {
        final assetFile = File(
          '${dir.path}/肥喵资产_${bookName}_$stamp.json',
        );
        await assetFile.writeAsString(await repo.exportAssetTablesJson());
        files.add(XFile(assetFile.path, mimeType: 'application/json'));
      }

      await Share.shareXFiles(
        files,
        subject: '肥喵账本导出',
        text:
            '肥喵「$bookName」导出：账单 ${txs.length} 行，实物资产 $physicalAssetCount 件，权益资产 $receivableAssetCount 项。',
      );
      _setMessage(
        '已导出账单 ${txs.length} 行、实物资产 $physicalAssetCount 件、权益资产 $receivableAssetCount 项，去分享面板里保存或发送吧',
      );
    } catch (e) {
      _setMessage('导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── 导入 ──────────────────────────────────────────────────────────────
  Future<void> _import() async {
    final repo = context.read<AppRepository>();
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt', 'xlsx', 'xls', 'json'],
        withData: false,
        withReadStream: true,
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
      if (bytes == null && f.readStream != null) {
        final builder = BytesBuilder(copy: false);
        await for (final chunk in f.readStream!) {
          builder.add(chunk);
        }
        bytes = builder.takeBytes();
      }
      if (bytes == null) {
        _setMessage('读不到文件内容');
        return;
      }

      final ext = (f.extension ?? '').toLowerCase();
      if (ext == 'json') {
        final text = utf8.decode(bytes, allowMalformed: true);
        final result = await repo.importAssetTablesJson(text);
        final warnings = [
          if (result.unresolvedTransactionLinks > 0)
            '${result.unresolvedTransactionLinks} 条账单关联尚未恢复，请先导入对应账单后重新导入资产 JSON',
          if (result.unresolvedSavingsGoalLinks > 0)
            '${result.unresolvedSavingsGoalLinks} 个存钱目标关联尚未恢复，请确认本机存在唯一的对应目标后重试',
          if (result.rejectedLinks > 0)
            '${result.rejectedLinks} 条不符合账本、币种或交易类型约束的关联已拒绝',
        ];
        final warningSuffix = warnings.isEmpty ? '' : "。${warnings.join('；')}";
        _setMessage(
          '已恢复实物资产 ${result.assets} 件、权益资产 ${result.receivables} 项，'
          '事件 ${result.events} 条、使用记录 ${result.usages} 条、估值 ${result.valuations} 条，'
          '账单关联 ${result.links} 条、收回历史 ${result.recoveries} 条、快照 ${result.snapshots} 条、负债档案 ${result.liabilities} 条$warningSuffix',
        );
        return;
      }
      final _ParsedImportFile parsed;
      if (ext == 'xlsx' || ext == 'xls') {
        final payload = TransferableTypedData.fromList([bytes]);
        parsed = await Isolate.run(
          () => _parseXlsxImport(payload.materialize().asUint8List()),
        );
      } else {
        final text = await _decodeCsvBytes(bytes);
        parsed = await Isolate.run(() => _parseCsvImport(text));
      }
      final feimiaoRows = parsed.feimiaoRows;
      if (feimiaoRows != null) {
        final restored = await repo.importFeimiaoExportRows(feimiaoRows);
        _setMessage(
          '已恢复 ${restored.inserted} 笔，退款 ${restored.refundsAttached} 笔'
          '${restored.skippedDuplicates > 0 ? '，跳过重复 ${restored.skippedDuplicates} 行' : ''}',
        );
        return;
      }
      final result = parsed.billResult!;
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
        final skip = result.skipped > 0 ? '，跳过 ${result.skipped} 笔（中性/无效）' : '';
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
      appBar: AppBar(
          leading: const AppBackButton(),
          title: const Text('导入导出'),
          centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ActionCard(
            icon: Icons.upload_file_outlined,
            color: scheme.primary,
            title: '导出为 CSV',
            subtitle: '选择时间范围，将当前账本导出为 CSV 文件。',
            buttonLabel: '导出',
            onPressed: _busy ? null : _export,
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.download_outlined,
            color: AppColors.income(scheme),
            title: '导入账单（CSV / Excel）',
            subtitle: '支持微信、支付宝、咔皮和木木账单，以及 CSV、Excel 文件。',
            buttonLabel: '导入',
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
                  Expanded(
                    child: Text(_message!, style: AppType.secondary(scheme)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Text(
            '导入只会新增账目，不会覆盖已有数据。想先核对时，可以新建一个账本再导入。\n\n'
            '无法识别的分类会暂存为「未分类」；不计收支的记录会自动跳过。账目会保存到当前账本的默认账户。',
            style: AppType.caption(scheme),
          ),
        ],
      ),
    );
  }
}

class ExportRangePickerSheet extends StatelessWidget {
  final List<ExportRange> options;
  final DateTime defaultStart;
  final DateTime defaultEnd;

  const ExportRangePickerSheet({
    super.key,
    required this.options,
    required this.defaultStart,
    required this.defaultEnd,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screenHeight = MediaQuery.sizeOf(context).height;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.82),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: '选择导出范围',
              subtitle: '默认导出本月。需要完整备份时再选择全部。',
              onClose: () => Navigator.pop(context),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.card(scheme),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.38),
                      width: 0.5,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final option in options)
                        _ExportRangeRow(
                          label: option.label,
                          detail: option.description,
                          showDivider: true,
                          onTap: () => Navigator.pop(context, option),
                        ),
                      _ExportRangeRow(
                        label: '自定义',
                        detail: '手动选择开始和结束日期',
                        showDivider: false,
                        onTap: () async {
                          final picked = await showAppDateRangePicker(
                            context,
                            defaultStart: defaultStart,
                            defaultEnd: defaultEnd,
                          );
                          if (picked == null || !context.mounted) return;
                          Navigator.pop(
                            context,
                            ExportRange.custom(
                              start: picked.start,
                              end: picked.end,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParsedImportFile {
  final BillParseResult? billResult;
  final List<FeimiaoImportRow>? feimiaoRows;

  const _ParsedImportFile.bill(this.billResult) : feimiaoRows = null;
  const _ParsedImportFile.feimiao(this.feimiaoRows) : billResult = null;
}

_ParsedImportFile _parseCsvImport(String text) {
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final table = const CsvToListConverter(
    shouldParseNumbers: false,
    eol: '\n',
  )
      .convert(normalized)
      .map((row) => row.map((cell) => cell.toString()).toList())
      .toList(growable: false);
  return _parseImportTable(table);
}

_ParsedImportFile _parseXlsxImport(Uint8List bytes) {
  final excel = Excel.decodeBytes(bytes);
  for (final name in excel.tables.keys) {
    final sheet = excel.tables[name];
    if (sheet == null || sheet.rows.isEmpty) continue;
    final table = <List<String>>[
      for (final row in sheet.rows)
        [for (final cell in row) (cell?.value?.toString() ?? '').trim()],
    ];
    if (table.isNotEmpty) return _parseImportTable(table);
  }
  return _parseImportTable(const <List<String>>[]);
}

_ParsedImportFile _parseImportTable(List<List<String>> table) {
  final feimiaoRows = _parseFeimiaoRows(table);
  if (feimiaoRows != null) {
    return _ParsedImportFile.feimiao(feimiaoRows);
  }
  return _ParsedImportFile.bill(BillImporter.parseRows(table));
}

@visibleForTesting
List<String> feimiaoCsvHeaderForTest() =>
    List.unmodifiable(_ImportExportViewState._header);

@visibleForTesting
String formatFeimiaoTransactionDateForTest(
  DateTime date,
  TransactionTimePrecision precision,
) =>
    _formatFeimiaoTransactionDate(date, precision);

@visibleForTesting
List<FeimiaoImportRow>? parseFeimiaoRowsForTest(List<List<String>> table) =>
    _parseFeimiaoRows(table);

String _formatFeimiaoTransactionDate(
  DateTime date,
  TransactionTimePrecision precision,
) {
  final pattern = shouldShowTransactionClock(date, precision)
      ? 'yyyy-MM-dd HH:mm'
      : 'yyyy-MM-dd';
  return DateFormat(pattern).format(date);
}

List<FeimiaoImportRow>? _parseFeimiaoRows(List<List<String>> table) {
  if (table.isEmpty) return null;

  String clean(String value) => value.replaceAll('\ufeff', '').trim();
  final headerIndex = table.indexWhere((row) {
    final cells = row.map(clean).toSet();
    return cells.contains('净额') &&
        cells.contains('原始金额') &&
        cells.contains('已退款');
  });
  if (headerIndex < 0) return null;

  final header = table[headerIndex].map(clean).toList(growable: false);
  final columns = <String, int>{
    for (var i = 0; i < header.length; i++) header[i]: i,
  };
  String cell(List<String> row, String name) {
    final index = columns[name] ?? -1;
    if (index < 0 || index >= row.length) return '';
    return clean(row[index]);
  }

  Decimal money(String raw) {
    final value = clean(raw)
        .replaceAll('¥', '')
        .replaceAll('￥', '')
        .replaceAll(',', '')
        .replaceAll(' ', '');
    return Decimal.tryParse(value) ?? Decimal.zero;
  }

  final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
  DateTime? dateOf(String raw) {
    try {
      return dateFormat.parseStrict(raw);
    } catch (_) {
      return DateTime.tryParse(raw);
    }
  }

  TransactionKind kindOf(String raw) {
    if (raw.contains('收入')) return TransactionKind.income;
    if (raw.contains('转账')) return TransactionKind.transfer;
    return TransactionKind.expense;
  }

  final rows = <FeimiaoImportRow>[];
  for (var i = headerIndex + 1; i < table.length; i++) {
    final raw = table[i];
    if (raw.every((value) => clean(value).isEmpty)) continue;
    final date = dateOf(cell(raw, '日期'));
    if (date == null) continue;
    final kind = kindOf(cell(raw, '类型'));
    final categoryText = cell(raw, '分类');
    var categoryName = categoryText;
    var toAccountName = cell(raw, '转入账户');
    if (kind == TransactionKind.transfer && categoryText.contains('→')) {
      final parts = categoryText.split('→');
      categoryName = '';
      if (toAccountName.isEmpty && parts.length > 1) {
        toAccountName = parts.last.trim();
      }
    }
    final originalAmount = cell(raw, '原始金额');
    final role = cell(raw, '记录类型');
    final refundOfUuid = cell(raw, '退款归属UUID');
    final settlementQualityRaw = cell(raw, '到账日期质量');
    final settlementAccountQualityRaw = cell(raw, '到账账户质量');
    final eventTypeRaw = cell(raw, '事件类型');
    final tagNames = cell(raw, '标签')
        .split('|')
        .map(clean)
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final reimbursable = cell(raw, '可报销').toLowerCase();
    rows.add(
      FeimiaoImportRow(
        uuid: cell(raw, '交易UUID'),
        refundOfUuid: refundOfUuid,
        role: role.isEmpty ? (refundOfUuid.isEmpty ? '账单' : '退款') : role,
        kind: kind,
        amount:
            money(originalAmount.isNotEmpty ? originalAmount : cell(raw, '净额')),
        refunded: money(cell(raw, '已退款')).abs(),
        categoryKey: cell(raw, '分类Key'),
        categoryName: categoryName,
        accountName: cell(raw, '账户'),
        toAccountName: toAccountName,
        tagNames: tagNames,
        note: cell(raw, '备注'),
        date: date,
        timePrecision: TransactionTimePrecisionX.fromStorage(
          cell(raw, '时间精度'),
        ),
        settledAt: dateOf(cell(raw, '到账日期')),
        settlementQuality: settlementQualityRaw.isEmpty
            ? null
            : SettlementQualityX.fromStorage(settlementQualityRaw),
        settlementAccountName: cell(raw, '到账账户'),
        settlementAccountQuality: settlementAccountQualityRaw.isEmpty
            ? null
            : SettlementQualityX.fromStorage(settlementAccountQualityRaw),
        eventType: eventTypeRaw.isEmpty
            ? null
            : TransactionEventTypeX.fromStorage(eventTypeRaw),
        excluded: cell(raw, '计入收支') == '否',
        reimbursable: reimbursable == '是' ||
            reimbursable == '1' ||
            reimbursable == 'true',
      ),
    );
  }
  return rows.isEmpty ? null : rows;
}

class _ExportRangeRow extends StatelessWidget {
  final String label;
  final String detail;
  final bool showDivider;
  final VoidCallback onTap;

  const _ExportRangeRow({
    required this.label,
    required this.detail,
    required this.showDivider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detail,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color:
                              scheme.onSurfaceVariant.withValues(alpha: 0.68),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16),
            child: Divider(
              height: 1,
              thickness: 0.5,
              color: scheme.outlineVariant.withValues(alpha: 0.38),
            ),
          ),
      ],
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
                  child: Text(title, style: AppType.rowTitle(scheme)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(subtitle, style: AppType.secondary(scheme)),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 108,
                height: 42,
                child: OutlinedButton(
                  onPressed: onPressed,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.onSurface,
                    backgroundColor: Colors.transparent,
                    side: BorderSide(color: AppColors.hairline(scheme)),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: Text(buttonLabel),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
