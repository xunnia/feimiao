import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show visibleForTesting;

/// AI 查询日志：结构化记录每次请求的关键信息，便于排查问题和优化成本。
///
/// 当前实现基于 dart:developer.log（开发环境可见），生产环境可替换为
/// 远程日志服务（如 Sentry / Firebase Crashlytics）。
///
/// 日志脱敏策略：
/// - API Key：完全隐藏，仅记录 provider/model
/// - 用户数据：不记录原始流水、备注、金额明细
/// - 错误信息：仅记录错误类型和 HTTP 状态码，不记录响应体
class AiLogger {
  AiLogger._();

  /// 记录查询开始
  static void logQueryStart({
    required String taskType,
    required String provider,
    required String model,
    int? estimatedTokens,
    Map<String, dynamic>? extra,
  }) {
    _log('ai_query_start', {
      'task_type': taskType,
      'provider': provider,
      'model': model,
      if (estimatedTokens != null) 'estimated_tokens': estimatedTokens,
      if (extra != null) ..._sanitizeMap(extra),
    });
  }

  /// 记录查询成功
  static void logQuerySuccess({
    required String taskType,
    required String provider,
    required String model,
    required int durationMs,
    int? promptTokens,
    int? completionTokens,
    int? totalTokens,
    Map<String, dynamic>? extra,
  }) {
    _log('ai_query_success', {
      'task_type': taskType,
      'provider': provider,
      'model': model,
      'duration_ms': durationMs,
      if (promptTokens != null) 'prompt_tokens': promptTokens,
      if (completionTokens != null) 'completion_tokens': completionTokens,
      if (totalTokens != null) 'total_tokens': totalTokens,
      if (extra != null) ..._sanitizeMap(extra),
    });
  }

  /// 记录查询失败
  static void logQueryFailure({
    required String taskType,
    required String provider,
    required String model,
    required String errorType,
    required String errorMessage,
    int? durationMs,
    int? statusCode,
    Map<String, dynamic>? extra,
  }) {
    _log('ai_query_failure', {
      'task_type': taskType,
      'provider': provider,
      'model': model,
      'error_type': errorType,
      'error_message': _sanitizeErrorMessage(errorMessage),
      if (durationMs != null) 'duration_ms': durationMs,
      if (statusCode != null) 'status_code': statusCode,
      if (extra != null) ..._sanitizeMap(extra),
    });
  }

  /// 记录重试
  static void logRetry({
    required String taskType,
    required String provider,
    required String fromModel,
    required String toModel,
    required String reason,
  }) {
    _log('ai_query_retry', {
      'task_type': taskType,
      'provider': provider,
      'from_model': fromModel,
      'to_model': toModel,
      'reason': _sanitizeErrorMessage(reason),
    });
  }

  /// 记录降级
  static void logFallback({
    required String taskType,
    required String fromProvider,
    required String toProvider,
    required String reason,
  }) {
    _log('ai_query_fallback', {
      'task_type': taskType,
      'from_provider': fromProvider,
      'to_provider': toProvider,
      'reason': _sanitizeErrorMessage(reason),
    });
  }

  /// 记录警告（非致命错误，如流式解析单条失败）
  static void logWarning({
    required String taskType,
    required String provider,
    required String model,
    required String warning,
    Map<String, dynamic>? extra,
  }) {
    _log('ai_query_warning', {
      'task_type': taskType,
      'provider': provider,
      'model': model,
      'warning': _sanitizeErrorMessage(warning),
      if (extra != null) ..._sanitizeMap(extra),
    });
  }

  /// 脱敏 Map：移除敏感字段
  static Map<String, dynamic> _sanitizeMap(Map<String, dynamic> map) {
    final sanitized = <String, dynamic>{};
    for (final entry in map.entries) {
      final key = entry.key.toLowerCase();

      // 跳过敏感字段
      if (key.contains('key') ||
          key.contains('token') ||
          key.contains('password') ||
          key.contains('secret')) {
        continue;
      }

      final value = entry.value;
      if (value is Map<String, dynamic>) {
        sanitized[entry.key] = _sanitizeMap(value);
      } else if (value is String) {
        sanitized[entry.key] = _sanitizeString(value);
      } else {
        sanitized[entry.key] = value;
      }
    }
    return sanitized;
  }

  /// 脱敏字符串：移除手机号、身份证号等
  static String _sanitizeString(String text) {
    var sanitized = text;

    // 身份证号脱敏：前6后4（先处理,避免被手机号正则误匹配）
    // 添加边界检查，避免误伤更长的数字串
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'(?<!\d)\d{17}[\dXx](?!\d)'),
      (m) => '${m.group(0)!.substring(0, 6)}********${m.group(0)!.substring(14, 18)}',
    );

    // 手机号脱敏：13812345678 → 138****5678
    // 添加负向前瞻/后顾，避免误伤订单号中的 11 位数字
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'(?<!\d)1[3-9]\d{9}(?!\d)'),
      (m) => '${m.group(0)!.substring(0, 3)}****${m.group(0)!.substring(7)}',
    );

    // 限制长度
    if (sanitized.length > 200) {
      sanitized = '${sanitized.substring(0, 200)}...';
    }

    return sanitized;
  }

  /// 脱敏错误信息：移除可能包含的敏感数据
  static String _sanitizeErrorMessage(String message) {
    var sanitized = _sanitizeString(message);

    // 移除可能的 API 响应体片段（通常包含敏感信息）
    if (sanitized.contains('{') || sanitized.contains('[')) {
      // 仅保留前 100 个字符作为上下文
      sanitized = sanitized.substring(0, sanitized.length > 100 ? 100 : sanitized.length);
      sanitized = '$sanitized... [响应体已隐藏]';
    }

    return sanitized;
  }

  static void _log(String event, Map<String, dynamic> data) {
    final message = '$event: ${data.entries.map((e) => '${e.key}=${e.value}').join(', ')}';
    developer.log(
      message,
      name: 'AiLogger',
      time: DateTime.now(),
    );
  }

  // ========== 测试辅助方法 ==========

  /// 测试辅助：暴露 _sanitizeString 供单测验证
  @visibleForTesting
  static String sanitizeStringForTest(String text) => _sanitizeString(text);

  /// 测试辅助：暴露 _sanitizeMap 供单测验证
  @visibleForTesting
  static Map<String, dynamic> sanitizeMapForTest(Map<String, dynamic> map) =>
      _sanitizeMap(map);

  /// 测试辅助：暴露 _sanitizeErrorMessage 供单测验证
  @visibleForTesting
  static String sanitizeErrorMessageForTest(String message) =>
      _sanitizeErrorMessage(message);
}
