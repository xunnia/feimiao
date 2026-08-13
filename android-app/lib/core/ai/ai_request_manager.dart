import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'ai_exception.dart';
import 'ai_logger.dart';

/// AI 查询请求管理器:处理并发控制、取消、重试。
class AiRequestManager {
  AiRequestManager._();

  static final _activeRequests = <String, _RequestController>{};

  /// 执行请求，自动处理并发控制和取消
  static Future<T> execute<T>({
    required String taskId,
    required Future<T> Function() request,
    bool allowConcurrent = false,
  }) async {
    if (!allowConcurrent) {
      final existing = _activeRequests[taskId];
      if (existing != null) {
        existing.cancel();
        await existing.completer.future.catchError((_) {});
      }
    }

    final controller = _RequestController<T>();
    _activeRequests[taskId] = controller;

    try {
      final result = await request();
      controller.completer.complete(result);
      return result;
    } catch (e) {
      controller.completer.completeError(e);
      rethrow;
    } finally {
      _activeRequests.remove(taskId);
    }
  }

  /// 取消指定任务
  static void cancel(String taskId) {
    final controller = _activeRequests[taskId];
    if (controller != null) {
      controller.cancel();
      _activeRequests.remove(taskId);
    }
  }

  /// 取消所有活跃请求
  static void cancelAll() {
    for (final controller in _activeRequests.values) {
      controller.cancel();
    }
    _activeRequests.clear();
  }

  /// 指数退避重试
  static Future<T> retryWithBackoff<T>({
    required Future<T> Function() request,
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 1),
    bool Function(Object error)? shouldRetry,
    String? taskType,
    String? provider,
    String? model,
  }) async {
    var retryCount = 0;
    var delay = initialDelay;

    while (true) {
      try {
        return await request();
      } catch (e) {
        if (retryCount >= maxRetries) {
          // 记录最终放弃
          if (taskType != null && provider != null && model != null) {
            AiLogger.logWarning(
              taskType: taskType,
              provider: provider,
              model: model,
              warning: '重试 $maxRetries 次后放弃: ${e is AiException ? e.message : e.toString()}',
            );
          }
          rethrow;
        }

        final canRetry = shouldRetry?.call(e) ??
          (e is AiException && e.shouldRetry);

        if (!canRetry) {
          // 记录不可重试错误
          if (taskType != null && provider != null && model != null) {
            AiLogger.logWarning(
              taskType: taskType,
              provider: provider,
              model: model,
              warning: '遇到不可重试错误: ${e is AiException ? e.message : e.toString()}',
            );
          }
          rethrow;
        }

        retryCount++;

        // 记录重试行为
        if (taskType != null && provider != null && model != null) {
          AiLogger.logRetry(
            taskType: taskType,
            provider: provider,
            fromModel: model,
            toModel: model,
            reason: e is AiException ? e.message : e.toString(),
          );
        }

        await Future.delayed(delay);
        delay *= 2;
      }
    }
  }

  /// 将原始异常转换为具体的 AiException
  static AiException wrapException(Object error, {int? statusCode}) {
    if (error is AiException) return error;

    if (error is TimeoutException) {
      return AiNetworkException('请求超时', originalError: error);
    }

    if (error is SocketException) {
      return AiNetworkException('网络连接失败', originalError: error);
    }

    if (error is http.ClientException) {
      return AiNetworkException('网络请求失败', originalError: error);
    }

    if (statusCode != null) {
      return _exceptionFromStatusCode(statusCode, error.toString());
    }

    return AiUnknownException(error.toString(), originalError: error);
  }

  static AiException _exceptionFromStatusCode(int code, String message) {
    if (code == 401 || code == 403) {
      return AiAuthException(message, statusCode: code);
    }
    if (code == 429) {
      final retryAfter = _parseRetryAfter(message);
      return AiRateLimitException(
        message,
        statusCode: code,
        retryAfterSeconds: retryAfter,
      );
    }
    if (code == 400) {
      if (message.toLowerCase().contains('token') &&
          (message.toLowerCase().contains('limit') ||
           message.toLowerCase().contains('exceed'))) {
        return AiTokenLimitException(message, statusCode: code);
      }
      return AiBadRequestException(message, statusCode: code);
    }
    if (code == 404) {
      return AiModelNotSupportedException(message, statusCode: code);
    }
    if (code >= 500) {
      return AiServerException(message, statusCode: code);
    }
    return AiUnknownException(message, statusCode: code);
  }

  static int? _parseRetryAfter(String message) {
    final match = RegExp(r'retry.{0,10}?(\d+)', caseSensitive: false)
        .firstMatch(message);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '');
    }
    return null;
  }
}

class _RequestController<T> {
  final completer = Completer<T>();
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (!_cancelled) {
      _cancelled = true;
      completer.completeError(
        const AiUnknownException('请求已取消'),
      );
    }
  }
}
