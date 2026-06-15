import 'package:csv/csv.dart';
import 'package:decimal/decimal.dart';

import '../models/transaction_kind.dart';

/// 一条从外部账单解析出来的标准化记录。
class ImportedBillRow {
  final DateTime date;
  final TransactionKind kind;
  final String category; // 分类名（外部账单常没有，可能为空）
  final String note;
  final Decimal amount; // 恒为正

  const ImportedBillRow({
    required this.date,
    required this.kind,
    required this.category,
    required this.note,
    required this.amount,
  });
}

/// 解析结果：识别到的来源 + 解析出的行 + 跳过条数 + 诊断信息。
class BillParseResult {
  final String source; // 微信 / 支付宝 / 咔皮记账 / 木木记账 / 账单
  final List<ImportedBillRow> rows;
  final int skipped;
  final int totalRows; // 文件总行数（诊断用）
  final bool headerFound; // 是否定位到表头（诊断用）

  const BillParseResult({
    required this.source,
    required this.rows,
    required this.skipped,
    this.totalRows = 0,
    this.headerFound = false,
  });
}

/// 主流账单智能解析器（CSV/Excel 文本都先转成二维表格再喂进来）。
///
/// 能力：
///  - 跳过微信/支付宝账单顶部十几行说明，定位真正表头；
///  - 按「列名模糊匹配」适配不同 App（日期/收支/金额/分类/备注/交易对方…），
///    因此微信、支付宝、咔皮、木木等都能吃下；
///  - 收支方向：优先「收/支」列，其次「类型」列，再退化到金额正负号；
///    中性 / 不计收支的行会被跳过。
///
/// 注意：字节→文本的解码（含 GBK）放在界面层用系统原生解码完成，
/// 这里只处理已解码文本，保证纯 Dart 可单测。
class BillImporter {
  /// 从已解码 CSV 文本解析。
  static BillParseResult parseString(String raw) {
    final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final table = const CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(normalized);
    return parseRows(
      table.map((r) => r.map((c) => c.toString()).toList()).toList(),
    );
  }

  /// 从已解析的二维表格解析（CSV 与 xlsx 共用的核心）。
  static BillParseResult parseRows(List<List<String>> table) {
    final source = _detectSourceFromTable(table);
    final total = table.length;
    if (table.isEmpty) {
      return BillParseResult(
          source: source, rows: const [], skipped: 0, totalRows: total);
    }

    final headerIdx = _findHeaderRow(table);
    if (headerIdx < 0) {
      return BillParseResult(
          source: source,
          rows: const [],
          skipped: 0,
          totalRows: total,
          headerFound: false);
    }

    final header = table[headerIdx].map((e) => _norm(e)).toList();
    final cols = _ColumnMap.fromHeader(header);
    if (cols.amount < 0) {
      return BillParseResult(
          source: source,
          rows: const [],
          skipped: 0,
          totalRows: total,
          headerFound: true);
    }

    final rows = <ImportedBillRow>[];
    var skipped = 0;
    for (var i = headerIdx + 1; i < table.length; i++) {
      final raw = table[i];
      if (raw.every((c) => c.trim().isEmpty)) continue;
      final row = raw.map((e) => e.trim()).toList();
      final parsed = cols.parseRow(row);
      if (parsed == null) {
        skipped++;
        continue;
      }
      rows.add(parsed);
    }

    return BillParseResult(
      source: source,
      rows: rows,
      skipped: skipped,
      totalRows: total,
      headerFound: true,
    );
  }

  // ── 来源识别：扫描表格前若干行的文字 ────────────────────────────────────────
  static String _detectSourceFromTable(List<List<String>> table) {
    final buf = StringBuffer();
    final limit = table.length < 25 ? table.length : 25;
    for (var i = 0; i < limit; i++) {
      buf.write(table[i].join(','));
      buf.write('\n');
    }
    final head = buf.toString();
    if (head.contains('微信支付账单') || head.contains('微信昵称')) return '微信';
    if (head.contains('支付宝')) return '支付宝';
    if (head.contains('咔皮')) return '咔皮记账';
    if (head.contains('木木')) return '木木记账';
    return '账单';
  }

  // ── 表头定位：含「金额」类列名的那一行 ───────────────────────────────────────
  static int _findHeaderRow(List<List<String>> table) {
    final limit = table.length < 30 ? table.length : 30;
    for (var i = 0; i < limit; i++) {
      final cells = table[i].map(_norm).toList();
      final hasAmount = cells.any((c) => c.contains('金额'));
      final hasDateOrKind = cells.any((c) =>
          c.contains('时间') ||
          c.contains('日期') ||
          c.contains('收/支') ||
          c.contains('收支') ||
          c.contains('类型'));
      if (hasAmount && hasDateOrKind) return i;
    }
    // 退化：只要有「金额」就当表头
    for (var i = 0; i < limit; i++) {
      final cells = table[i].map(_norm).toList();
      if (cells.any((c) => c.contains('金额'))) return i;
    }
    return -1;
  }

  /// 归一化表头：去空格、全角括号转半角，方便 contains 匹配。
  static String _norm(String s) => s
      .trim()
      .replaceAll(' ', '')
      .replaceAll('　', '')
      .replaceAll('（', '(')
      .replaceAll('）', ')');
}

/// 列下标映射 + 单行解析逻辑。
class _ColumnMap {
  final int date;
  final int amount;
  final int direction; // 收/支 或 收支 列
  final int kindType; // 「类型」列（值可能是 支出/收入）
  final int category;
  final int counterparty;
  final int product;
  final int note;

  const _ColumnMap({
    required this.date,
    required this.amount,
    required this.direction,
    required this.kindType,
    required this.category,
    required this.counterparty,
    required this.product,
    required this.note,
  });

  static int _find(List<String> header, List<String> keys,
      {List<String> avoid = const []}) {
    for (var i = 0; i < header.length; i++) {
      final h = header[i];
      if (avoid.any((a) => h.contains(a))) continue;
      if (keys.any((k) => h.contains(k))) return i;
    }
    return -1;
  }

  factory _ColumnMap.fromHeader(List<String> header) {
    return _ColumnMap(
      date: _find(header, ['交易时间', '交易创建时间', '付款时间', '日期', '记账时间', '时间', '创建时间']),
      amount: _find(header, ['金额']),
      direction: _find(header, ['收/支', '收支']),
      kindType: _find(header, ['类型', '收入/支出'], avoid: ['交易类型', '业务类型']),
      category: _find(header, ['分类', '类别']),
      counterparty: _find(header, ['交易对方', '对方', '商户']),
      product: _find(header, ['商品', '摘要']),
      note: _find(header, ['备注', '说明'], avoid: ['商品']),
    );
  }

  String _at(List<String> row, int idx) =>
      (idx >= 0 && idx < row.length) ? row[idx] : '';

  ImportedBillRow? parseRow(List<String> row) {
    final amountRaw = _at(row, amount);
    final amt = _parseAmount(amountRaw);
    if (amt == null || amt == Decimal.zero) return null;

    final kind = _resolveKind(row, amt);
    if (kind == null) return null; // 中性 / 不计收支

    final dt = _parseDate(_at(row, date)) ?? DateTime.now();

    // 分类：优先专门的分类列；没有就用交易对方/商品兜底，方便事后整理
    var cat = _at(row, category).trim();
    final party = _at(row, counterparty).trim();
    final prod = _at(row, product).trim();
    final noteText = _at(row, note).trim();

    if (cat.isEmpty) {
      // 外部账单（微信/支付宝）没有分类，交易对方就是最有用的信息
      cat = '';
    }

    // 备注：把交易对方/商品/原备注拼起来（去重去空）
    final parts = <String>[];
    for (final p in [party, prod, noteText]) {
      if (p.isNotEmpty && !parts.contains(p) && p != '/') parts.add(p);
    }
    final note0 = parts.join(' · ');

    return ImportedBillRow(
      date: dt,
      kind: kind,
      category: cat,
      note: note0.length > 60 ? note0.substring(0, 60) : note0,
      amount: amt.abs(),
    );
  }

  TransactionKind? _resolveKind(List<String> row, Decimal amt) {
    final dir = _at(row, direction).trim();
    if (dir.isNotEmpty) {
      if (dir.contains('不计') || dir.contains('中性') || dir == '/') return null;
      if (dir.contains('收')) return TransactionKind.income;
      if (dir.contains('支')) return TransactionKind.expense;
    }
    final kt = _at(row, kindType).trim();
    if (kt.isNotEmpty) {
      if (kt.contains('不计') || kt.contains('中性')) return null;
      if (kt.contains('收') && !kt.contains('支')) return TransactionKind.income;
      if (kt.contains('支') && !kt.contains('收')) return TransactionKind.expense;
    }
    // 退化：金额带负号 → 支出，正号 → 收入
    if (amt < Decimal.zero) return TransactionKind.expense;
    return TransactionKind.income;
  }

  static Decimal? _parseAmount(String s) {
    if (s.isEmpty) return null;
    // 去掉 ¥ ￥ 空格 千分位逗号 和其它非数字字符（保留负号与小数点）
    final cleaned = s.replaceAll(RegExp(r'[^0-9.\-]'), '');
    if (cleaned.isEmpty || cleaned == '-' || cleaned == '.') return null;
    return Decimal.tryParse(cleaned);
  }

  static DateTime? _parseDate(String s) {
    if (s.isEmpty) return null;
    final t = s.trim();
    // 直接 ISO / 常见格式
    final iso = DateTime.tryParse(t.replaceFirst(' ', 'T'));
    if (iso != null) return iso;
    // 手动匹配 yyyy-MM-dd 或 yyyy/MM/dd [HH:mm[:ss]]
    final m = RegExp(
      r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?:[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?',
    ).firstMatch(t);
    if (m == null) return null;
    int g(int i, [int d = 0]) => int.tryParse(m.group(i) ?? '') ?? d;
    return DateTime(g(1), g(2, 1), g(3, 1), g(4), g(5), g(6));
  }
}
