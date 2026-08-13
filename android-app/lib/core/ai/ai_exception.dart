/// AI 查询异常基类：细化错误类型，便于上层做差异化处理。
sealed class AiException implements Exception {
  final String message;
  final int? statusCode;
  final Object? originalError;

  const AiException(this.message, {this.statusCode, this.originalError});

  /// 用户友好的错误提示（显示在 toast / snackbar）
  String get userFriendlyMessage;

  /// 可选的操作建议（告诉用户该做什么）
  String? get actionHint => null;

  /// 是否应该重试（用于自动重试逻辑）
  bool get shouldRetry;

  /// 是否应该 fallback 到备用服务商
  bool get shouldFallback;

  /// 错误严重程度
  AiErrorSeverity get severity => AiErrorSeverity.medium;

  /// 获取可序列化的错误详情（用于日志和上报）
  Map<String, dynamic> toJson() => {
        'type': runtimeType.toString(),
        'message': message,
        'statusCode': statusCode,
        'shouldRetry': shouldRetry,
        'shouldFallback': shouldFallback,
        'severity': severity.name,
      };

  @override
  String toString() => '$runtimeType: $message';
}

/// 错误严重程度
enum AiErrorSeverity {
  low, // 可忽略的错误
  medium, // 需要注意但不影响核心功能
  high, // 影响功能但有降级方案
  critical, // 阻塞性错误
}

/// 网络错误：连接超时、DNS 解析失败等
class AiNetworkException extends AiException {
  const AiNetworkException(super.message, {super.originalError});

  @override
  String get userFriendlyMessage => '网络连接失败';

  @override
  String get actionHint => '请检查网络设置后重试';

  @override
  bool get shouldRetry => true;

  @override
  bool get shouldFallback => false;

  @override
  AiErrorSeverity get severity => AiErrorSeverity.high;
}

/// 认证错误：API key 无效、过期等
class AiAuthException extends AiException {
  const AiAuthException(super.message, {super.statusCode});

  @override
  String get userFriendlyMessage => 'API 密钥无效';

  @override
  String get actionHint => '请在设置中检查 AI 配置';

  @override
  bool get shouldRetry => false;

  @override
  bool get shouldFallback => true;

  @override
  AiErrorSeverity get severity => AiErrorSeverity.critical;
}

/// 限流错误：请求过于频繁
class AiRateLimitException extends AiException {
  final int? retryAfterSeconds;

  const AiRateLimitException(
    super.message, {
    super.statusCode,
    this.retryAfterSeconds,
  });

  @override
  String get userFriendlyMessage {
    if (retryAfterSeconds != null && retryAfterSeconds! > 0) {
      return '请求过于频繁，请 $retryAfterSeconds 秒后再试';
    }
    return '请求过于频繁，请稍后再试';
  }

  @override
  String get actionHint => '系统会自动重试';

  @override
  bool get shouldRetry => true;

  @override
  bool get shouldFallback => false;

  @override
  AiErrorSeverity get severity => AiErrorSeverity.medium;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'retryAfterSeconds': retryAfterSeconds,
      };
}

/// Token 超限：输入或输出 token 超过模型限制
class AiTokenLimitException extends AiException {
  const AiTokenLimitException(super.message, {super.statusCode});

  @override
  String get userFriendlyMessage => '账目数据太多，喵暂时看不过来';

  @override
  String get actionHint => '请尝试缩小查询范围或时间段';

  @override
  bool get shouldRetry => false;

  @override
  bool get shouldFallback => false;

  @override
  AiErrorSeverity get severity => AiErrorSeverity.high;
}

/// 服务器错误：5xx 状态码
class AiServerException extends AiException {
  const AiServerException(super.message, {super.statusCode});

  @override
  String get userFriendlyMessage => 'AI 服务暂时不可用，请稍后再试';

  @override
  bool get shouldRetry => true;

  @override
  bool get shouldFallback => true;

  @override
  AiErrorSeverity get severity => AiErrorSeverity.high;
}

/// 响应解析错误：返回格式不符合预期
class AiResponseParseException extends AiException {
  const AiResponseParseException(super.message, {super.originalError});

  @override
  String get userFriendlyMessage => 'AI 返回格式异常，请重试';

  @override
  bool get shouldRetry => true;

  @override
  bool get shouldFallback => false;

  @override
  AiErrorSeverity get severity => AiErrorSeverity.medium;
}

/// 配置错误：API key 未配置、baseUrl 无效等
class AiConfigException extends AiException {
  const AiConfigException(super.message);

  @override
  String get userFriendlyMessage => message;

  @override
  bool get shouldRetry => false;

  @override
  bool get shouldFallback => false;

  @override
  AiErrorSeverity get severity => AiErrorSeverity.critical;
}

/// 模型不支持：400/404 错误，通常需要切换兼容模型
class AiModelNotSupportedException extends AiException {
  const AiModelNotSupportedException(super.message, {super.statusCode});

  @override
  String get userFriendlyMessage => '当前模型不可用，正在尝试备用模型';

  @override
  bool get shouldRetry => false;

  @override
  bool get shouldFallback => false;

  @override
  AiErrorSeverity get severity => AiErrorSeverity.high;
}

/// 空回答：AI 返回成功但内容为空
class AiEmptyResponseException extends AiException {
  const AiEmptyResponseException(super.message);

  @override
  String get userFriendlyMessage => 'AI 未返回有效内容，请重试';

  @override
  bool get shouldRetry => true;

  @override
  bool get shouldFallback => false;

  @override
  AiErrorSeverity get severity => AiErrorSeverity.medium;
}

/// 未知错误：兜底类型
class AiUnknownException extends AiException {
  const AiUnknownException(super.message, {super.statusCode, super.originalError});

  @override
  String get userFriendlyMessage => '查询失败，请重试';

  @override
  bool get shouldRetry => true;

  @override
  bool get shouldFallback => false;

  @override
  AiErrorSeverity get severity => AiErrorSeverity.medium;
}

/// 请求参数错误：请求格式错误、必填参数缺失等（不应降级重试）
class AiBadRequestException extends AiException {
  const AiBadRequestException(
    super.message, {
    super.statusCode,
    super.originalError,
  });

  @override
  String get userFriendlyMessage => '请求参数错误';

  @override
  String get actionHint => '这是应用程序错误，请联系开发者';

  @override
  bool get shouldRetry => false;

  @override
  bool get shouldFallback => false;

  @override
  AiErrorSeverity get severity => AiErrorSeverity.high;
}
