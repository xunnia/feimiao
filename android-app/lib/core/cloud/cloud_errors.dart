/// 后端统一错误（`ErrorResponse`）的客户端表示。
///
/// 规则（后端 docs/03 §0、openapi `ErrorCode`）：
/// - 服务端可能新增 code：认不出的 code 看 `action`；`action` 也认不出，
///   就按 HTTP 状态码兜底，并直接展示服务端给的 `message`，不能崩。
/// - `message` 是可以直接给用户看的文案。
library;

enum CloudErrorCode {
  unauthenticated('UNAUTHENTICATED'),
  sessionRevoked('SESSION_REVOKED'),
  invalidCredentials('INVALID_CREDENTIALS'),
  accountRestricted('ACCOUNT_RESTRICTED'),
  accountBanned('ACCOUNT_BANNED'),
  featureLocked('FEATURE_LOCKED'),
  quotaExhausted('QUOTA_EXHAUSTED'),
  rateLimited('RATE_LIMITED'),
  deviceLimit('DEVICE_LIMIT'),
  loginTicketExpired('LOGIN_TICKET_EXPIRED'),
  appOutdated('APP_OUTDATED'),
  integrityRequired('INTEGRITY_REQUIRED'),
  otpInvalid('OTP_INVALID'),
  otpExpired('OTP_EXPIRED'),
  otpTooFrequent('OTP_TOO_FREQUENT'),
  emailTaken('EMAIL_TAKEN'),
  redeemInvalid('REDEEM_INVALID'),
  redeemUsed('REDEEM_USED'),
  iapInvalid('IAP_INVALID'),
  iapOwnedByOther('IAP_OWNED_BY_OTHER'),
  aiUnavailable('AI_UNAVAILABLE'),
  aiSuspended('AI_SUSPENDED'),
  inputTooLarge('INPUT_TOO_LARGE'),
  consentRequired('CONSENT_REQUIRED'),
  requestInProgress('REQUEST_IN_PROGRESS'),
  invalidRequest('INVALID_REQUEST'),
  notFound('NOT_FOUND'),
  internal('INTERNAL'),

  /// 服务端新增、本版本还不认识的 code。原始字符串在 [CloudApiException.rawCode]。
  unknown('');

  const CloudErrorCode(this.wire);
  final String wire;

  static CloudErrorCode parse(String? raw) {
    for (final code in values) {
      if (code != unknown && code.wire == raw) return code;
    }
    return unknown;
  }
}

enum CloudErrorAction {
  refreshOrLogin('refresh_or_login'),
  login('login'),
  showMessage('show_message'),
  openPaywall('open_paywall'),
  retryLater('retry_later'),
  chooseDevice('choose_device'),
  forceUpdate('force_update'),
  reattest('reattest'),
  showConsent('show_consent'),
  wait('wait');

  const CloudErrorAction(this.wire);
  final String wire;

  static CloudErrorAction? parse(String? raw) {
    for (final action in values) {
      if (action.wire == raw) return action;
    }
    return null;
  }

  /// `action` 认不出时按 HTTP 状态码兜底。
  static CloudErrorAction fromStatus(int status) => switch (status) {
        401 => CloudErrorAction.refreshOrLogin,
        402 => CloudErrorAction.openPaywall,
        426 => CloudErrorAction.forceUpdate,
        429 || 503 => CloudErrorAction.retryLater,
        _ => CloudErrorAction.showMessage,
      };
}

/// 所有后端请求失败都抛这个类型（包括断网和超时，见 [isNetwork]）。
class CloudApiException implements Exception {
  CloudApiException({
    required this.status,
    required this.code,
    required this.rawCode,
    required this.action,
    required this.message,
    this.requestId,
    this.retryAfter,
    this.details = const {},
    this.cause,
  });

  /// 断网、超时、DNS 失败等：请求没有拿到服务端的回应。
  factory CloudApiException.network([Object? cause]) => CloudApiException(
        status: 0,
        code: CloudErrorCode.unknown,
        rawCode: 'NETWORK',
        action: CloudErrorAction.retryLater,
        message: '网络连接失败，请检查网络后重试',
        cause: cause,
      );

  /// 服务端回了非 2xx，但内容不是约定的错误格式（比如网关报错页）。
  factory CloudApiException.unexpected(int status) => CloudApiException(
        status: status,
        code: CloudErrorCode.unknown,
        rawCode: 'HTTP_$status',
        action: CloudErrorAction.fromStatus(status),
        message: status >= 500 ? '服务暂时不可用，请稍后再试' : '请求失败（$status）',
      );

  /// 解析服务端的 `ErrorResponse`。格式不对时退回 [CloudApiException.unexpected]。
  static CloudApiException fromResponse(int status, Object? body) {
    final error = body is Map ? body['error'] : null;
    if (error is! Map) return CloudApiException.unexpected(status);
    final rawCode = error['code'] is String ? error['code'] as String : '';
    final code = CloudErrorCode.parse(rawCode);
    final action = CloudErrorAction.parse(error['action'] as String?) ??
        CloudErrorAction.fromStatus(status);
    final message = error['message'];
    final retryAfter = error['retry_after'];
    final details = error['details'];
    return CloudApiException(
      status: status,
      code: code,
      rawCode: rawCode,
      action: action,
      message: message is String && message.trim().isNotEmpty
          ? message
          : CloudApiException.unexpected(status).message,
      requestId: error['request_id'] as String?,
      retryAfter: retryAfter is num && retryAfter > 0
          ? Duration(seconds: retryAfter.toInt())
          : null,
      details: details is Map ? Map<String, Object?>.from(details) : const {},
    );
  }

  /// HTTP 状态码；断网时为 0。
  final int status;
  final CloudErrorCode code;
  final String rawCode;
  final CloudErrorAction action;

  /// 可以直接展示给用户的文案。
  final String message;
  final String? requestId;
  final Duration? retryAfter;
  final Map<String, Object?> details;

  /// 断网时底层的异常，只用于日志。
  final Object? cause;

  bool get isNetwork => status == 0;

  /// 已登录的请求遇到它，说明这次登录已经失效，要回到未登录。
  /// `LOGIN_TICKET_EXPIRED` 的 action 也是 login，但它只是登录流程里的
  /// 票据过期，本来就没登录，不算。
  bool get endsSession =>
      code == CloudErrorCode.sessionRevoked ||
      code == CloudErrorCode.accountBanned ||
      (code == CloudErrorCode.unknown &&
          !isNetwork &&
          action == CloudErrorAction.login);

  @override
  String toString() =>
      'CloudApiException($status $rawCode ${action.wire}: $message'
      '${requestId == null ? '' : ' request_id=$requestId'})';
}
