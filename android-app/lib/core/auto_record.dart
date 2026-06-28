import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter/services.dart';

import 'ai/merchant_category.dart';
import 'meal_time.dart';
import 'models/transaction_kind.dart';
import 'notification_parse.dart';

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

      // 通知专用解析：挑最像本次支付的金额（避开余额）+ 收支方向。
      final amt = NotificationParse.pickAmount(text);
      if (amt == null || amt <= Decimal.zero) continue; // 没金额 → 丢弃
      final kind = NotificationParse.kindOf(text);
      // 分类：商户词典命中即用；笼统餐饮再按时段细化到餐次。
      final dictKey = MerchantCategory.classify(text, kind);
      final catKey = MealTime.refine(dictKey, time, text);

      out.add(AutoCandidate(
        app: app,
        text: text,
        time: time,
        amount: amt,
        kind: kind,
        categoryKey: catKey,
      ));
    }
    return out;
  }
}
