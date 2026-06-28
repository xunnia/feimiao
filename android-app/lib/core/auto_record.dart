import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter/services.dart';

import 'ai/merchant_category.dart';
import 'ai/natural_language_entry_parser.dart';
import 'models/transaction_kind.dart';

/// 自动记账的一条候选（来自一条支付通知，本地解析后）。
class AutoCandidate {
  final String app; // 微信 / 支付宝
  final String text; // 原始通知文本
  final DateTime time;
  final Decimal amount;
  final TransactionKind kind;
  final String? categoryKey;

  AutoCandidate({
    required this.app,
    required this.text,
    required this.time,
    required this.amount,
    required this.kind,
    required this.categoryKey,
  });
}

/// 自动记账：与原生 NotificationListenerService 对接（通道 feimiao/autorecord）。
class AutoRecord {
  AutoRecord._();

  static const MethodChannel _ch = MethodChannel('feimiao/autorecord');

  /// 是否已授予「通知使用权」。
  static Future<bool> isEnabled() async {
    try {
      return (await _ch.invokeMethod('isEnabled')) == true;
    } catch (_) {
      return false;
    }
  }

  /// 跳到系统「通知使用权」设置页。
  static Future<void> openSettings() async {
    try {
      await _ch.invokeMethod('openSettings');
    } catch (_) {}
  }

  /// 取出并清空原生抓到的通知队列，本地解析成候选（金额+方向+分类）。
  static Future<List<AutoCandidate>> drain() async {
    String raw;
    try {
      raw = (await _ch.invokeMethod('consumePending')) as String? ?? '[]';
    } catch (_) {
      return const [];
    }
    List<dynamic> list;
    try {
      list = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return const [];
    }

    final out = <AutoCandidate>[];
    for (final e in list) {
      final m = Map<String, dynamic>.from(e as Map);
      final app = (m['app'] ?? '').toString();
      final text = (m['text'] ?? '').toString();
      if (text.isEmpty) continue;
      final ms = m['time'];
      final millis = ms is int ? ms : int.tryParse('$ms') ?? 0;
      final time = millis > 0
          ? DateTime.fromMillisecondsSinceEpoch(millis)
          : DateTime.now();

      final parsed = NaturalLanguageEntryParser.parse(text, at: time);
      final amt = parsed.amount;
      if (amt == null || amt <= Decimal.zero) continue; // 没金额 → 丢弃

      // 收款/到账 视为收入，其余按解析（多数是支出）。
      var kind = parsed.kind;
      if (RegExp('到账|收款|收钱').hasMatch(text)) {
        kind = TransactionKind.income;
      }
      final dictKey = MerchantCategory.classify(text, kind);

      out.add(AutoCandidate(
        app: app,
        text: text,
        time: time,
        amount: amt,
        kind: kind,
        categoryKey: dictKey ?? parsed.categoryKey,
      ));
    }
    return out;
  }
}
