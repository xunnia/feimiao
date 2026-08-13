import 'package:decimal/decimal.dart';

import '../models/transaction_kind.dart';
import '../models/transaction_record.dart';

/// AI 数据裁剪器：按需裁剪流水数据，降低 token 消耗 + 提升准确性。
///
/// 策略：
/// 1. 按任务类型智能筛选相关流水（月度分析只要当月、分类分析只要该分类）
/// 2. 去除冗余字段（uuid、created_ms 等）
/// 3. 金额四舍五入到整数（元）
/// 4. 备注脱敏（去掉手机号、身份证号等敏感信息）
/// 5. 限制最大条数（避免超 token limit）
class AiDataTrimmer {
  /// 针对「月度分析」任务裁剪数据
  static List<Map<String, dynamic>> trimForMonthlyAnalysis({
    required List<TransactionRecord> allRecords,
    required int year,
    required int month,
    int maxRecords = 500,
  }) {
    final filtered = allRecords.where((r) {
      return r.date.year == year && r.date.month == month;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final limited = filtered.take(maxRecords).toList();

    return limited.map((r) => {
          'date': '${r.date.year}-${r.date.month.toString().padLeft(2, '0')}-${r.date.day.toString().padLeft(2, '0')}',
          'kind': r.kind.name,
          'amount': _roundAmount(r.amount),
          'category': r.categoryName.isNotEmpty ? r.categoryName : '未分类',
          if (r.note.isNotEmpty) 'note': _sanitizeNote(r.note),
        }).toList();
  }

  /// 针对「分类深挖」任务裁剪数据
  static List<Map<String, dynamic>> trimForCategoryAnalysis({
    required List<TransactionRecord> allRecords,
    required String categoryName,
    int maxRecords = 300,
  }) {
    final filtered = allRecords.where((r) {
      return r.categoryName == categoryName;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final limited = filtered.take(maxRecords).toList();

    return limited.map((r) => {
          'date': '${r.date.year}-${r.date.month.toString().padLeft(2, '0')}-${r.date.day.toString().padLeft(2, '0')}',
          'amount': _roundAmount(r.amount),
          if (r.note.isNotEmpty) 'note': _sanitizeNote(r.note),
        }).toList();
  }

  /// 针对「智能问答」任务裁剪数据（需要全局上下文，但限制条数）
  static List<Map<String, dynamic>> trimForGeneralQuery({
    required List<TransactionRecord> allRecords,
    int maxRecords = 200,
  }) {
    final sorted = allRecords.toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final limited = sorted.take(maxRecords).toList();

    return limited.map((r) => {
          'date': '${r.date.year}-${r.date.month.toString().padLeft(2, '0')}-${r.date.day.toString().padLeft(2, '0')}',
          'kind': r.kind.name,
          'amount': _roundAmount(r.amount),
          'category': r.categoryName.isNotEmpty ? r.categoryName : '未分类',
          if (r.note.isNotEmpty) 'note': _sanitizeNote(r.note),
        }).toList();
  }

  /// 生成分类汇总（极简版本，给 AI 全局视角）
  static Map<String, dynamic> buildCategorySummary({
    required List<TransactionRecord> records,
    required int year,
    required int month,
  }) {
    final monthRecords = records.where((r) {
      return r.date.year == year && r.date.month == month;
    });

    final expenseByCategory = <String, Decimal>{};
    final incomeByCategory = <String, Decimal>{};

    for (final r in monthRecords) {
      final catName = r.categoryName.isNotEmpty ? r.categoryName : '未分类';
      if (r.kind == TransactionKind.expense) {
        expenseByCategory[catName] =
            (expenseByCategory[catName] ?? Decimal.zero) + r.amount;
      } else if (r.kind == TransactionKind.income) {
        incomeByCategory[catName] =
            (incomeByCategory[catName] ?? Decimal.zero) + r.amount;
      }
    }

    return {
      'year': year,
      'month': month,
      'expense_by_category': expenseByCategory.map(
        (k, v) => MapEntry(k, _roundAmount(v)),
      ),
      'income_by_category': incomeByCategory.map(
        (k, v) => MapEntry(k, _roundAmount(v)),
      ),
      'total_expense': _roundAmount(
        expenseByCategory.values.fold(Decimal.zero, (a, b) => a + b),
      ),
      'total_income': _roundAmount(
        incomeByCategory.values.fold(Decimal.zero, (a, b) => a + b),
      ),
    };
  }

  /// 金额四舍五入到整数（元）
  static int _roundAmount(Decimal amount) {
    return (amount / Decimal.fromInt(100)).round().toInt();
  }

  /// 备注脱敏：去掉手机号、身份证号
  static String _sanitizeNote(String note) {
    var sanitized = note;

    // 手机号脱敏：13812345678 → 138****5678
    // 添加负向前瞻/后顾，避免误伤订单号中的 11 位数字
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'(?<!\d)1[3-9]\d{9}(?!\d)'),
      (m) => '${m.group(0)!.substring(0, 3)}****${m.group(0)!.substring(7)}',
    );

    // 身份证号脱敏：前6后4
    // 添加边界检查，避免误伤更长的数字串
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'(?<!\d)\d{17}[\dXx](?!\d)'),
      (m) => '${m.group(0)!.substring(0, 6)}********${m.group(0)!.substring(14)}',
    );

    return sanitized.length > 50 ? '${sanitized.substring(0, 50)}...' : sanitized;
  }

  /// 估算 token 数（粗略）：中文 1 字 ≈ 2 token，英文 1 词 ≈ 1.3 token
  static int estimateTokens(String text) {
    final chineseCount = RegExp(r'[一-龥]').allMatches(text).length;
    final englishWords = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    return (chineseCount * 2 + englishWords * 1.3).round();
  }

  /// 估算数据的 token 消耗
  static int estimateDataTokens(List<Map<String, dynamic>> data) {
    final json = data.toString();
    return estimateTokens(json);
  }
}
