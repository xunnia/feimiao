import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'cloud_config.dart';
import 'cloud_errors.dart';
import 'cloud_models.dart';
import 'cloud_session_store.dart';

typedef CloudClock = DateTime Function();

/// 本机型号和系统版本，登录时上报，方便用户在设备列表里认出是哪台。
/// 读不到就不报（两个字段都是可选的）。
typedef CloudDeviceInfoReader = Future<Map<String, String>> Function();

const MethodChannel _deviceChannel = MethodChannel('feimiao/device');

Future<Map<String, String>> readPlatformDeviceInfo() async {
  try {
    final raw = await _deviceChannel.invokeMapMethod<String, Object?>('info');
    return {
      for (final entry in (raw ?? const {}).entries)
        if (entry.value is String && (entry.value as String).isNotEmpty)
          entry.key: entry.value as String,
    };
  } catch (_) {
    return const {};
  }
}

/// 权益接口的结果：304 时 [notModified] 为 true，其余字段为空。
class EntitlementsFetch {
  const EntitlementsFetch.notModified()
      : notModified = true,
        json = null,
        etag = null;

  const EntitlementsFetch.fresh(Map<String, Object?> this.json, this.etag)
      : notModified = false;

  final bool notModified;
  final Map<String, Object?>? json;
  final String? etag;
}

class _Response {
  const _Response(this.status, this.headers, this.body, this.text);

  final int status;
  final Map<String, String> headers;
  final Object? body;
  final String text;

  bool get ok => status >= 200 && status < 300;
  Map<String, Object?> get json =>
      body is Map ? Map<String, Object?>.from(body as Map) : const {};
}

/// 肥喵后端的统一 HTTP 客户端。
///
/// - 每个请求都带 `X-Install-Id`、`X-Platform`、`X-App-Version`；
///   写操作另带 `X-Request-Id`（重试时沿用同一个，服务端据此去重）。
/// - 需要登录的请求：访问令牌快过期先刷新；遇到 401 `UNAUTHENTICATED`
///   刷新一次再重试。多个请求同时 401 只刷新一次。
/// - 刷新失败、`SESSION_REVOKED`、`ACCOUNT_BANNED`：清掉本机令牌，
///   调 [onSessionEnded] 回到未登录。本地账本完全不受影响。
/// - 断网或 5xx 不会让用户掉登录，也不自动重试（后端 docs/03 要求）。
class CloudApi {
  CloudApi({
    http.Client? client,
    CloudSessionStore? store,
    String? baseUrl,
    CloudClock? clock,
    CloudDeviceInfoReader? deviceInfo,
    Duration? timeout,
  })  : _client = client ?? http.Client(),
        store = store ?? CloudSessionStore(),
        _base = _normalizeBase(baseUrl ?? CloudConfig.baseUrl),
        _now = clock ?? DateTime.now,
        _deviceInfo = deviceInfo ?? readPlatformDeviceInfo,
        _timeout = timeout ?? CloudConfig.requestTimeout;

  final http.Client _client;
  final CloudSessionStore store;
  final String _base;
  final CloudClock _now;
  final CloudDeviceInfoReader _deviceInfo;
  final Duration _timeout;

  /// 登录被动失效时调用（被踢下线、封号、刷新令牌过期）。主动退出不调用。
  void Function(CloudApiException reason)? onSessionEnded;

  CloudTokens? _tokens;
  Future<void>? _refreshing;

  bool get hasSession => _tokens != null;

  static String _normalizeBase(String base) =>
      base.endsWith('/') ? base.substring(0, base.length - 1) : base;

  /// 启动时从安全存储恢复登录状态。
  Future<bool> restore() async {
    final tokens = await store.readTokens();
    if (tokens == null) return false;
    if (!tokens.refreshExpiresAt.isAfter(_now())) {
      await store.clearSession();
      return false;
    }
    _tokens = tokens;
    return true;
  }

  // -------------------------------------------------------------------------
  // 登录
  // -------------------------------------------------------------------------

  /// 发送验证码，返回多久之后才能重发。`login` 不需要登录，其余用途需要。
  Future<Duration> sendOtp(
    OtpPurpose purpose, {
    String? email,
    String? changeTicket,
  }) async {
    final response = await _request(
      'POST',
      '/auth/otp/send',
      auth: purpose != OtpPurpose.login,
      body: {
        'purpose': purpose.wire,
        if (email != null) 'email': email.trim(),
        if (changeTicket != null) 'change_ticket': changeTicket,
      },
    );
    return Duration(seconds: _intField(response.json['resend_after_s']));
  }

  /// 验证码登录（新邮箱自动注册）。设备超限时抛 `DEVICE_LIMIT`，
  /// 用 [deviceLimitOf] 取出设备列表。
  Future<LoginResult> verifyOtp(String email, String code) async {
    final response = await _request('POST', '/auth/otp/verify', body: {
      'email': email.trim(),
      'code': code.trim(),
      'device': await _deviceBody(),
    });
    return _adoptLogin(response);
  }

  Future<LoginResult> passwordLogin(String email, String password) async {
    final response = await _request('POST', '/auth/password/login', body: {
      'email': email.trim(),
      'password': password,
      'device': await _deviceBody(),
    });
    return _adoptLogin(response);
  }

  Future<LoginResult> resolveDeviceLimit(
    String loginTicket,
    List<String> revokeDeviceIds,
  ) async {
    final response =
        await _request('POST', '/auth/device-limit/resolve', body: {
      'login_ticket': loginTicket,
      'revoke_device_ids': revokeDeviceIds,
    });
    return _adoptLogin(response);
  }

  DeviceLimitInfo? deviceLimitOf(CloudApiException error) =>
      error.code == CloudErrorCode.deviceLimit
          ? DeviceLimitInfo.fromDetails(error.details, _now())
          : null;

  /// 退出登录。先通知服务端（失败也不管），本机一定清掉。
  Future<void> logout() async {
    if (_tokens != null) {
      try {
        await _request('POST', '/auth/logout', auth: true, endOnFailure: false);
      } on CloudApiException {
        // 断网或令牌已失效：服务端的会话会自己过期，本机照样退出。
      }
    }
    await _clearLocal();
  }

  // -------------------------------------------------------------------------
  // 账号
  // -------------------------------------------------------------------------

  Future<CloudMe> me() async =>
      CloudMe.fromJson((await _request('GET', '/me', auth: true)).json);

  Future<CloudProfile> updateProfile({required String displayName}) async {
    final response = await _request('PATCH', '/me/profile',
        auth: true, body: {'display_name': displayName});
    return CloudProfile.fromJson(response.json);
  }

  /// 设置或修改密码。成功后其他设备全部下线。
  Future<void> setPassword(String otpCode, String newPassword) async {
    await _request('POST', '/me/password', auth: true, body: {
      'otp_code': otpCode.trim(),
      'new_password': newPassword,
    });
  }

  /// 换邮箱第一步：验证旧邮箱收到的码，拿到换绑票据。
  Future<EmailChangeTicket> verifyOldEmail(String otpCode) async {
    final response = await _request('POST', '/me/email/verify-old',
        auth: true, body: {'otp_code': otpCode.trim()});
    return EmailChangeTicket.fromJson(response.json, _now());
  }

  /// 换邮箱第二步：新邮箱收到的码 + 票据。
  Future<CloudMe> confirmNewEmail(
    String changeTicket,
    String newEmail,
    String otpCode,
  ) async {
    final response =
        await _request('POST', '/me/email/confirm-new', auth: true, body: {
      'change_ticket': changeTicket,
      'new_email': newEmail.trim(),
      'otp_code': otpCode.trim(),
    });
    return CloudMe.fromJson(response.json);
  }

  Future<List<CloudDevice>> devices() async {
    final response = await _request('GET', '/me/devices', auth: true);
    return CloudDevice.listFrom(response.json['devices']);
  }

  /// 让除本机以外的所有设备下线。
  Future<void> revokeOtherDevices() async {
    await _request('DELETE', '/me/devices', auth: true);
  }

  /// 让某台设备下线。如果是本机，等于退出登录。
  Future<void> revokeDevice(CloudDevice device) async {
    await _request('DELETE', '/me/devices/${Uri.encodeComponent(device.id)}',
        auth: true);
    if (device.isCurrent) await _clearLocal();
  }

  Future<DeletionStatus> requestDeletion(String otpCode) async {
    final response = await _request('POST', '/me/deletion',
        auth: true, body: {'otp_code': otpCode.trim()});
    return DeletionStatus.fromJson(response.json);
  }

  Future<DeletionStatus> cancelDeletion() async {
    final response = await _request('DELETE', '/me/deletion', auth: true);
    return DeletionStatus.fromJson(response.json);
  }

  /// 导出个人信息，返回服务端给的 JSON 原文。
  Future<String> exportData() async =>
      (await _request('GET', '/me/export', auth: true)).text;

  // -------------------------------------------------------------------------
  // 权益
  // -------------------------------------------------------------------------

  Future<EntitlementsFetch> entitlements({String? etag}) async {
    final response = await _request(
      'GET',
      '/entitlements',
      auth: true,
      headers: {if (etag != null && etag.isNotEmpty) 'If-None-Match': etag},
    );
    if (response.status == 304) return const EntitlementsFetch.notModified();
    return EntitlementsFetch.fresh(response.json, response.headers['etag']);
  }

  /// 兑换码。返回兑换结果和最新权益。
  Future<(RedeemGrant, Map<String, Object?>)> redeem(String code) async {
    final response = await _request('POST', '/redeem',
        auth: true, body: {'code': code.trim()});
    final json = response.json;
    final granted = json['granted'];
    final entitlements = json['entitlements'];
    return (
      RedeemGrant.fromJson(
          granted is Map ? Map<String, Object?>.from(granted) : const {}),
      entitlements is Map
          ? Map<String, Object?>.from(entitlements)
          : const <String, Object?>{},
    );
  }

  // -------------------------------------------------------------------------
  // 内部
  // -------------------------------------------------------------------------

  Future<LoginResult> _adoptLogin(_Response response) async {
    final result = LoginResult.fromJson(response.json, _now());
    if (!result.tokens.isUsable) throw CloudApiException.unexpected(response.status);
    await _adoptTokens(result.tokens);
    return result;
  }

  Future<void> _adoptTokens(CloudTokens tokens) async {
    _tokens = tokens;
    await store.writeTokens(tokens);
  }

  Future<void> _clearLocal() async {
    _tokens = null;
    await store.clearSession();
  }

  Future<void> _endSession(CloudApiException reason) async {
    if (_tokens == null) return;
    await _clearLocal();
    onSessionEnded?.call(reason);
  }

  Future<Map<String, Object?>> _deviceBody() async {
    final info = await _deviceInfo();
    String? clip(String? value, int max) {
      final trimmed = value?.trim();
      if (trimmed == null || trimmed.isEmpty) return null;
      return trimmed.length <= max ? trimmed : trimmed.substring(0, max);
    }

    final model = clip(info['model'], 64);
    final osVersion = clip(info['os_version'], 32);
    return {
      'install_id': await store.installId(),
      'platform': CloudConfig.platform,
      'app_version': CloudConfig.appVersion,
      if (model != null) 'model': model,
      if (osVersion != null) 'os_version': osVersion,
    };
  }

  Future<_Response> _request(
    String method,
    String path, {
    bool auth = false,
    Object? body,
    Map<String, String> headers = const {},
    bool endOnFailure = true,
  }) async {
    if (auth) await _ensureFreshAccess();
    final requestId = method == 'GET' ? null : CloudSessionStore.newUuidV4();
    final sentWith = _tokens?.accessToken;
    var response = await _send(method, path, auth, body, headers, requestId);

    if (auth && response.status == 401) {
      final error = CloudApiException.fromResponse(response.status, response.body);
      final canRefresh = error.code == CloudErrorCode.unauthenticated ||
          (error.code == CloudErrorCode.unknown &&
              error.action == CloudErrorAction.refreshOrLogin);
      if (canRefresh && _tokens != null) {
        await _refreshOnce(sentWith);
        response = await _send(method, path, auth, body, headers, requestId);
      }
    }

    if (response.ok || response.status == 304) return response;
    final error = CloudApiException.fromResponse(response.status, response.body);
    if (auth && endOnFailure && (error.endsSession || response.status == 401)) {
      await _endSession(error);
    }
    throw error;
  }

  Future<void> _ensureFreshAccess() async {
    final tokens = _tokens;
    if (tokens == null) {
      throw CloudApiException(
        status: 401,
        code: CloudErrorCode.unauthenticated,
        rawCode: CloudErrorCode.unauthenticated.wire,
        action: CloudErrorAction.login,
        message: '请先登录',
      );
    }
    final now = _now();
    if (!tokens.refreshExpiresAt.isAfter(now)) {
      final reason = CloudApiException(
        status: 401,
        code: CloudErrorCode.sessionRevoked,
        rawCode: CloudErrorCode.sessionRevoked.wire,
        action: CloudErrorAction.login,
        message: '登录已过期，请重新登录',
      );
      await _endSession(reason);
      throw reason;
    }
    if (tokens.accessExpiresAt.subtract(CloudConfig.refreshSkew).isBefore(now)) {
      await _refreshOnce(tokens.accessToken);
    }
  }

  /// 同一时间只刷新一次。[staleAccess] 是失败请求用的令牌：
  /// 如果别的请求已经换过新令牌，就不用再刷新了。
  Future<void> _refreshOnce(String? staleAccess) {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;
    final current = _tokens;
    if (current == null) return Future.value();
    if (staleAccess != null && current.accessToken != staleAccess) {
      return Future.value();
    }
    final future = _doRefresh(current).whenComplete(() => _refreshing = null);
    _refreshing = future;
    return future;
  }

  Future<void> _doRefresh(CloudTokens current) async {
    final response = await _send('POST', '/auth/refresh', false,
        {'refresh_token': current.refreshToken}, const {}, null);
    if (response.ok) {
      await _adoptTokens(CloudTokens.fromResponse(response.json, _now()));
      return;
    }
    final error = CloudApiException.fromResponse(response.status, response.body);
    // 只有服务端明确说这个登录不能用了才下线；5xx 之类保留登录，下次再试。
    if (response.status == 401 || response.status == 403 || error.endsSession) {
      await _endSession(error);
    }
    throw error;
  }

  Future<_Response> _send(
    String method,
    String path,
    bool auth,
    Object? body,
    Map<String, String> extraHeaders,
    String? requestId,
  ) async {
    final request = http.Request(method, Uri.parse('$_base$path'));
    request.headers.addAll({
      'Accept': 'application/json',
      'X-Install-Id': await store.installId(),
      'X-Platform': CloudConfig.platform,
      'X-App-Version': CloudConfig.appVersion,
      if (requestId != null) 'X-Request-Id': requestId,
      if (auth && _tokens != null)
        'Authorization': 'Bearer ${_tokens!.accessToken}',
      ...extraHeaders,
    });
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.bodyBytes = utf8.encode(jsonEncode(body));
    }

    final http.Response response;
    try {
      final streamed = await _client.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed).timeout(_timeout);
    } on Exception catch (error) {
      throw CloudApiException.network(error);
    }

    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    Object? decoded;
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        decoded = null;
      }
    }
    return _Response(response.statusCode, response.headers, decoded, text);
  }

  static int _intField(Object? value) => value is num ? value.toInt() : 0;
}
