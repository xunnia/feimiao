import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter/services.dart';

import 'ai/merchant_category.dart';
import 'meal_time.dart';
import 'models/transaction_kind.dart';
import 'notification_parse.dart';

/// 自动记账的一条候选（来自一条支付通知，本地解析后）。
class AutoCandidate {
  final String sourceId; // 原生队列事件 ID，用于确认删除与防重复入账
  final String app; // 微信 / 支付宝
  final String text; // 原始通知文本
  final DateTime time;
  final Decimal amount;
  final TransactionKind kind;
  final String? categoryKey;
  final bool isRefund;

  AutoCandidate({
    required this.sourceId,
    required this.app,
    required this.text,
    required this.time,
    required this.amount,
    required this.kind,
    required this.categoryKey,
    this.isRefund = false,
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

  /// 读取原生通知队列，但不删除。只有用户明确保存或忽略后才按 ID 确认。
  static Future<List<AutoCandidate>> pending() async {
    String raw;
    try {
      raw = (await _ch.invokeMethod('peekPending')) as String? ?? '[]';
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
    final rejectedIds = <String>[];
    for (final e in list) {
      final m = Map<String, dynamic>.from(e as Map);
      final sourceId = (m['id'] ?? '').toString().trim();
      if (sourceId.isEmpty) continue;
      final app = (m['app'] ?? '').toString();
      final text = (m['text'] ?? '').toString();
      if (text.isEmpty) {
        rejectedIds.add(sourceId);
        continue;
      }
      final ms = m['time'];
      final millis = ms is int ? ms : int.tryParse('$ms') ?? 0;
      final time = millis > 0
          ? DateTime.fromMillisecondsSinceEpoch(millis)
          : DateTime.now();

      // 通知专用解析：挑最像本次支付的金额（避开余额）+ 收支方向。
      final amt = NotificationParse.pickAmount(text);
      if (amt == null || amt <= Decimal.zero) {
        rejectedIds.add(sourceId);
        continue;
      }
      final kind = NotificationParse.kindOf(text);
      // 分类：商户词典命中即用；笼统餐饮再按时段细化到餐次。
      final dictKey = MerchantCategory.classify(text, kind);
      final catKey = MealTime.refine(dictKey, time, text);

      out.add(AutoCandidate(
        sourceId: sourceId,
        app: app,
        text: text,
        time: time,
        amount: amt,
        kind: kind,
        categoryKey: catKey,
        isRefund: NotificationParse.isRefund(text),
      ));
    }
    if (rejectedIds.isNotEmpty) {
      try {
        await acknowledgeIds(rejectedIds);
      } catch (_) {
        // Keep valid candidates usable even if native cleanup is unavailable.
      }
    }
    return dedupeCandidates(out);
  }

  /// 用户已处理这些候选后，从原生队列精确删除；期间新到的通知不受影响。
  static Future<void> acknowledge(Iterable<AutoCandidate> items) =>
      acknowledgeIds(items.map((item) => item.sourceId));

  static Future<void> acknowledgeIds(Iterable<String> sourceIds) async {
    final ids = sourceIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return;
    await _ch.invokeMethod<void>('ackPending', {'ids': ids});
  }

  /// Only collapse the exact same native queue event. Text/time heuristics can
  /// swallow two legitimate same-price purchases and are deliberately avoided.
  static List<AutoCandidate> dedupeCandidates(Iterable<AutoCandidate> items) {
    final kept = <AutoCandidate>[];
    final seen = <String>{};
    for (final item in items) {
      if (seen.add(item.sourceId)) kept.add(item);
    }
    return kept;
  }
}
