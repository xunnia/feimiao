import 'package:intl/intl.dart';

/// Pure export date range logic used by the import/export page.
///
/// Keeping this outside the UI makes the privacy-sensitive export scope
/// testable: the default options should never silently fall back to exporting
/// every transaction.
class ExportRange {
  final String label;
  final DateTime? start;
  final DateTime? end;

  const ExportRange(this.label, {this.start, this.end});

  factory ExportRange.custom({
    required DateTime start,
    required DateTime end,
    String? label,
  }) {
    final normalizedStart = dayStart(start);
    final normalizedEnd = dayEnd(end);
    final f = DateFormat('M月d日');
    return ExportRange(
      label ?? '${f.format(normalizedStart)} - ${f.format(normalizedEnd)}',
      start: normalizedStart,
      end: normalizedEnd,
    );
  }

  static DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime dayEnd(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  static List<ExportRange> presets(DateTime now) {
    final currentMonth = dayStart(DateTime(now.year, now.month, 1));
    final lastMonthStart = dayStart(DateTime(now.year, now.month - 1, 1));
    final lastMonthEnd = dayEnd(DateTime(now.year, now.month, 0));
    final recent3Start = dayStart(DateTime(now.year, now.month - 2, 1));
    final yearStart = dayStart(DateTime(now.year, 1, 1));
    final todayEnd = dayEnd(now);

    return [
      ExportRange('本月', start: currentMonth, end: todayEnd),
      ExportRange('上月', start: lastMonthStart, end: lastMonthEnd),
      ExportRange('近 3 个月', start: recent3Start, end: todayEnd),
      ExportRange('今年', start: yearStart, end: todayEnd),
      const ExportRange('全部'),
    ];
  }

  bool get isAll => start == null && end == null;

  bool contains(DateTime date) {
    if (start != null && date.isBefore(start!)) return false;
    if (end != null && date.isAfter(end!)) return false;
    return true;
  }

  String get fileSuffix {
    if (isAll) return '全部';
    final f = DateFormat('yyyyMMdd');
    if (start == null) return 'until-${f.format(end!)}';
    if (end == null) return 'from-${f.format(start!)}';
    return '${f.format(start!)}-${f.format(end!)}';
  }

  String get description {
    if (start == null && end != null) {
      return 'until ${DateFormat('yyyyMMdd').format(end!)}';
    }
    if (end == null && start != null) {
      return 'from ${DateFormat('yyyyMMdd').format(start!)}';
    }
    if (isAll) return '导出当前账本的全部账目';
    final f = DateFormat('yyyy年M月d日');
    return '${f.format(start!)} 至 ${f.format(end!)}';
  }
}
