import 'package:decimal/decimal.dart';

import 'natural_language_entry_parser.dart';

/// AI 退款只负责把一笔退款附着到已经存在的支出原单。
///
/// 这个类不读数据库，也不执行写入；调用方把当前可见的支出映射成
/// [RefundCandidate] 后再根据结果决定是否调用 repository。这样可以把
/// 「唯一强匹配才落账」的边界完整锁进纯逻辑测试里。
class RefundMatcher {
  RefundMatcher._();

  static final RegExp _refundWord = RegExp(
    r'退款|退回|已退|退了|退给我|退我|refund',
    caseSensitive: false,
  );

  static final RegExp _questionWord = RegExp(
    r'多少|几笔|几次|合计|总计|统计|明细|记录有哪些|有哪些|哪一笔|哪笔|'
    r'是什么|为什么|怎么|如何|是否|有没有|了吗|了没|吗[？?]?\s*$|'
    r'查一下|查询|帮我查|算一下|占比|趋势',
  );

  /// 提取退款金额前先移除日期，避免把「7月3日那笔退款」里的 3 误当成
  /// 退款金额。退款写入必须宁可追问，也不能靠日期数字猜金额。
  static Decimal? extractAmount(String text) {
    final withoutDates = text
        .replaceAll(RegExp(r'\d{4}[年./-]\d{1,2}[月./-]\d{1,2}日?'), '')
        .replaceAll(RegExp(r'\d{1,2}月\d{1,2}[日号]'), '')
        .replaceAll(RegExp(r'(?<!\d)\d{1,2}月(?!\d)'), '');
    return NaturalLanguageEntryParser.extractAmount(withoutDates);
  }

  /// 返回 [RefundMatchStatus.notRefundMutation] 时，上层继续原来的
  /// 记账/查账意图识别。特别地，「本月退款多少」属于查询，不在这里拦截。
  static RefundMatchResult match({
    required String text,
    required Iterable<RefundCandidate> candidates,
    required Decimal? amount,
    DateTime? now,
  }) {
    final raw = text.trim();
    if (raw.isEmpty || !_refundWord.hasMatch(raw)) {
      return const RefundMatchResult(RefundMatchStatus.notRefundMutation);
    }
    if (_questionWord.hasMatch(raw)) {
      return const RefundMatchResult(RefundMatchStatus.notRefundMutation);
    }
    if (amount == null || amount <= Decimal.zero) {
      return const RefundMatchResult(RefundMatchStatus.missingAmount);
    }

    final base = now ?? DateTime.now();
    final window = _dateWindow(raw, base);
    var pool = candidates.where((candidate) => candidate.amount > Decimal.zero);
    if (window != null) {
      pool = pool.where(
        (candidate) =>
            !candidate.date.isBefore(window.start) &&
            candidate.date.isBefore(window.endExclusive),
      );
    }
    final scoped = pool.toList(growable: false);
    if (scoped.isEmpty) {
      return RefundMatchResult(
        RefundMatchStatus.noMatch,
        amount: amount,
      );
    }

    final hint = _normalizedHint(raw);
    final ranked = <({RefundCandidate candidate, double score})>[];
    if (hint.length >= 2) {
      for (final candidate in scoped) {
        final candidateHint = _normalizedHint(candidate.label);
        final score =
            _similarity(hint, candidateHint) + (window == null ? 0 : 4);
        if (score >= 76) {
          ranked.add((candidate: candidate, score: score));
        }
      }
      ranked.sort((a, b) => b.score.compareTo(a.score));
    } else if (window != null &&
        RegExp(r'这笔|那笔|该笔|这一笔|那一笔').hasMatch(raw) &&
        scoped.length == 1) {
      ranked.add((candidate: scoped.single, score: 80));
    }

    if (ranked.isEmpty) {
      return RefundMatchResult(
        RefundMatchStatus.noMatch,
        amount: amount,
      );
    }

    final best = ranked.first;
    final close = ranked
        .skip(1)
        .where((item) => best.score - item.score < 8)
        .map((item) => item.candidate)
        .toList(growable: false);
    if (close.isNotEmpty) {
      return RefundMatchResult(
        RefundMatchStatus.ambiguous,
        amount: amount,
        candidates: [best.candidate, ...close],
      );
    }

    if (amount > best.candidate.remaining) {
      return RefundMatchResult(
        RefundMatchStatus.exceedsRemaining,
        amount: amount,
        candidate: best.candidate,
      );
    }
    return RefundMatchResult(
      RefundMatchStatus.matched,
      amount: amount,
      candidate: best.candidate,
    );
  }

  static double _similarity(String request, String candidate) {
    if (candidate.length < 2) return 0;
    if (request == candidate) return 100;
    if (request.contains(candidate) || candidate.contains(request)) {
      final difference = (request.length - candidate.length).abs();
      return (90 - difference.clamp(0, 8)).toDouble();
    }
    final left = _bigrams(request);
    final right = _bigrams(candidate);
    if (left.isEmpty || right.isEmpty) return 0;
    final overlap = left.intersection(right).length;
    final dice = (2 * overlap) / (left.length + right.length);
    return dice >= 0.5 ? 60 + dice * 40 : 0;
  }

  static Set<String> _bigrams(String value) => {
        for (var i = 0; i + 1 < value.length; i++) value.substring(i, i + 2),
      };

  static String _normalizedHint(String value) {
    var result = value.toLowerCase();
    result = result
        .replaceAll(RegExp(r'\d{4}[年./-]\d{1,2}[月./-]\d{1,2}日?'), '')
        .replaceAll(RegExp(r'\d{1,2}月\d{1,2}[日号]'), '')
        .replaceAll(RegExp(r'\d{1,2}月'), '')
        .replaceAll(RegExp(r'\d+(?:\.\d+)?\s*(?:元|块|块钱|人民币|￥|¥)?'), '')
        .replaceAll(RegExp(r'[零〇一二两三四五六七八九十百千万]+(?:元|块|块钱|钱)'), '')
        .replaceAll(_refundWord, '')
        .replaceAll(
          RegExp(
            r'请帮我|帮我|给我|把这笔|把那笔|这一笔|那一笔|这笔|那笔|该笔|'
            r'原来的|原订单|原单|订单|交易|消费|购买|买的|买了|买|付款了|支付了|'
            r'之前|以前|上一次|上次|过往|历史|对应|已经|成功|到账|收到|'
            r'记一下|记一笔|记上|入账|一下|今天|昨天|前天|大前天|'
            r'本月|这个月|上个月|今年|去年|的|我|了',
          ),
          '',
        )
        .replaceAll(RegExp(r'[^\u4e00-\u9fff a-z0-9]'), '')
        .replaceAll(' ', '');
    return result;
  }

  static _DateWindow? _dateWindow(String text, DateTime now) {
    DateTime day(DateTime value) =>
        DateTime(value.year, value.month, value.day);
    _DateWindow singleDay(DateTime value) {
      final start = day(value);
      return _DateWindow(start, start.add(const Duration(days: 1)));
    }

    final full = RegExp(r'(\d{4})年(\d{1,2})月(\d{1,2})[日号]?').firstMatch(text);
    if (full != null) {
      return singleDay(DateTime(
        int.parse(full.group(1)!),
        int.parse(full.group(2)!),
        int.parse(full.group(3)!),
      ));
    }
    final monthDay = RegExp(r'(\d{1,2})月(\d{1,2})[日号]').firstMatch(text);
    if (monthDay != null) {
      return singleDay(DateTime(
        now.year,
        int.parse(monthDay.group(1)!),
        int.parse(monthDay.group(2)!),
      ));
    }
    if (text.contains('大前天')) {
      return singleDay(now.subtract(const Duration(days: 3)));
    }
    if (text.contains('前天')) {
      return singleDay(now.subtract(const Duration(days: 2)));
    }
    if (text.contains('昨天')) {
      return singleDay(now.subtract(const Duration(days: 1)));
    }
    if (text.contains('今天')) return singleDay(now);

    DateTime monthStart(int year, int month) => DateTime(year, month);
    if (text.contains('上个月')) {
      final end = monthStart(now.year, now.month);
      return _DateWindow(DateTime(end.year, end.month - 1), end);
    }
    if (text.contains('本月') || text.contains('这个月')) {
      final start = monthStart(now.year, now.month);
      return _DateWindow(start, DateTime(start.year, start.month + 1));
    }
    final month = RegExp(r'(?<!\d)(\d{1,2})月(?!\d)').firstMatch(text);
    if (month != null) {
      final value = int.parse(month.group(1)!);
      if (value >= 1 && value <= 12) {
        final year = value > now.month ? now.year - 1 : now.year;
        final start = DateTime(year, value);
        return _DateWindow(start, DateTime(year, value + 1));
      }
    }
    return null;
  }
}

enum RefundMatchStatus {
  notRefundMutation,
  missingAmount,
  noMatch,
  ambiguous,
  exceedsRemaining,
  matched,
}

class RefundCandidate {
  final int id;
  final String label;
  final Decimal amount;
  final Decimal refunded;
  final DateTime date;

  const RefundCandidate({
    required this.id,
    required this.label,
    required this.amount,
    required this.refunded,
    required this.date,
  });

  Decimal get remaining {
    final value = amount - refunded;
    return value > Decimal.zero ? value : Decimal.zero;
  }
}

class RefundMatchResult {
  final RefundMatchStatus status;
  final Decimal? amount;
  final RefundCandidate? candidate;
  final List<RefundCandidate> candidates;

  const RefundMatchResult(
    this.status, {
    this.amount,
    this.candidate,
    this.candidates = const [],
  });

  bool get isRefundMutation => status != RefundMatchStatus.notRefundMutation;
}

class _DateWindow {
  final DateTime start;
  final DateTime endExclusive;

  const _DateWindow(this.start, this.endExclusive);
}
