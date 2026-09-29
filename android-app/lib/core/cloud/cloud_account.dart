import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'cloud_api.dart';
import 'cloud_config.dart';
import 'cloud_errors.dart';
import 'cloud_models.dart';
import 'cloud_session_store.dart';

/// 登录结果：要么登录成功，要么设备数超限、需要用户选一台下线。
sealed class LoginOutcome {
  const LoginOutcome();
}

class LoginSucceeded extends LoginOutcome {
  const LoginSucceeded({required this.isNewUser});
  final bool isNewUser;
}

class LoginNeedsDeviceChoice extends LoginOutcome {
  const LoginNeedsDeviceChoice(this.info);
  final DeviceLimitInfo info;
}

/// 账号状态（登录、资料、权益），给界面 `watch` 用。
///
/// 没登录、断网、服务端出错都不会影响本地账本；这里只管账号。
/// [CloudConfig.accountEnabled] 关闭时什么都不做，也不读写存储、不联网。
class CloudAccount extends ChangeNotifier with WidgetsBindingObserver {
  CloudAccount({CloudApi? api, bool? enabled, DateTime Function()? clock})
      : _api = api ?? CloudApi(),
        enabled = enabled ?? CloudConfig.accountEnabled,
        _now = clock ?? DateTime.now {
    _api.onSessionEnded = _handleSessionEnded;
  }

  final CloudApi _api;
  final bool enabled;
  final DateTime Function() _now;

  bool _ready = false;
  bool _signedIn = false;
  CloudMe? _me;
  CachedEntitlements? _entitlements;
  String? _signOutNotice;
  Future<void>? _entitlementsInFlight;
  bool _observing = false;

  bool get ready => _ready;
  bool get signedIn => _signedIn;
  CloudMe? get me => _me;
  Entitlements? get entitlements => _entitlements?.value;

  /// 权益最后一次成功拉取的时间，离线时显示"更新于…"。
  DateTime? get entitlementsFetchedAt => _entitlements?.fetchedAt;

  /// 被动掉登录的原因（被踢下线、封号、登录过期），界面提示一次后调 [clearSignOutNotice]。
  String? get signOutNotice => _signOutNotice;

  CloudApi get api => _api;

  Future<void> init() async {
    if (!enabled) {
      _ready = true;
      notifyListeners();
      return;
    }
    _signedIn = await _api.restore();
    if (_signedIn) {
      _me = await _readMeCache();
      _entitlements = await _api.store.readEntitlements();
    }
    _ready = true;
    notifyListeners();
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    if (_signedIn) unawaited(refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _signedIn) {
      unawaited(refreshEntitlements());
    }
  }

  @override
  void dispose() {
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 拉取资料和权益。断网或服务端出错就保留上次的结果，不抛异常。
  Future<void> refresh() async {
    if (!_signedIn) return;
    await Future.wait([_loadMeQuietly(), refreshEntitlements()]);
  }

  /// 打开设置页、回到前台、AI 请求结束时调用。用 ETag，没变化时服务端回 304。
  Future<void> refreshEntitlements() {
    if (!_signedIn) return Future.value();
    return _entitlementsInFlight ??=
        _fetchEntitlements().whenComplete(() => _entitlementsInFlight = null);
  }

  Future<void> _fetchEntitlements() async {
    final cached = _entitlements;
    try {
      final result = await _api.entitlements(etag: cached?.etag);
      if (!_signedIn) return;
      if (result.notModified && cached != null) {
        _entitlements = CachedEntitlements(
            json: cached.json, etag: cached.etag, fetchedAt: _now());
      } else if (result.json != null) {
        _entitlements = CachedEntitlements(
            json: result.json!, etag: result.etag, fetchedAt: _now());
      } else {
        return;
      }
      await _api.store.writeEntitlements(_entitlements!);
      notifyListeners();
    } on CloudApiException catch (error) {
      debugPrint('entitlements refresh failed: $error');
    }
  }

  Future<void> _loadMeQuietly() async {
    try {
      await loadMe();
    } on CloudApiException catch (error) {
      debugPrint('me refresh failed: $error');
    }
  }

  Future<CloudMe> loadMe() async {
    final me = await _api.me();
    await _setMe(me);
    return me;
  }

  // -------------------------------------------------------------------------
  // 登录
  // -------------------------------------------------------------------------

  Future<Duration> sendLoginCode(String email) =>
      _api.sendOtp(OtpPurpose.login, email: email);

  Future<LoginOutcome> loginWithCode(String email, String code) =>
      _login(() => _api.verifyOtp(email, code));

  Future<LoginOutcome> loginWithPassword(String email, String password) =>
      _login(() => _api.passwordLogin(email, password));

  /// 设备超限时，用户选好要下线的设备后调用。票据过期会抛 `LOGIN_TICKET_EXPIRED`，
  /// 界面应回到登录页重新开始。
  Future<LoginOutcome> resolveDeviceLimit(
    DeviceLimitInfo info,
    List<String> revokeDeviceIds,
  ) =>
      _login(() => _api.resolveDeviceLimit(info.loginTicket, revokeDeviceIds));

  Future<LoginOutcome> _login(Future<LoginResult> Function() call) async {
    final LoginResult result;
    try {
      result = await call();
    } on CloudApiException catch (error) {
      final limit = _api.deviceLimitOf(error);
      if (limit != null) return LoginNeedsDeviceChoice(limit);
      rethrow;
    }
    _signedIn = true;
    _signOutNotice = null;
    _me = null;
    _entitlements = null;
    notifyListeners();
    await refresh();
    return LoginSucceeded(isNewUser: result.isNewUser);
  }

  /// 主动退出登录。只清账号信息，本地账本不动。
  Future<void> logout() async {
    await _api.logout();
    _clearState();
    _signOutNotice = null;
    notifyListeners();
  }

  void clearSignOutNotice() {
    if (_signOutNotice == null) return;
    _signOutNotice = null;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // 账号管理
  // -------------------------------------------------------------------------

  Future<Duration> sendCode(
    OtpPurpose purpose, {
    String? email,
    String? changeTicket,
  }) =>
      _api.sendOtp(purpose, email: email, changeTicket: changeTicket);

  Future<List<CloudDevice>> devices() => _api.devices();

  Future<void> revokeDevice(CloudDevice device) async {
    await _api.revokeDevice(device);
    if (device.isCurrent) {
      _clearState();
      notifyListeners();
    }
  }

  Future<void> revokeOtherDevices() => _api.revokeOtherDevices();

  Future<void> updateDisplayName(String name) async {
    final profile = await _api.updateProfile(displayName: name);
    final me = _me;
    if (me != null) {
      await _setMe(
        CloudMe(
          id: me.id,
          email: me.email,
          hasPassword: me.hasPassword,
          profile: profile,
          createdAt: me.createdAt,
          deletion: me.deletion,
        ),
      );
    }
  }

  /// 设置或修改密码（验证码来自 [OtpPurpose.setPassword]）。其他设备会下线。
  Future<void> setPassword(String otpCode, String newPassword) async {
    await _api.setPassword(otpCode, newPassword);
    await _loadMeQuietly();
  }

  Future<EmailChangeTicket> verifyOldEmail(String otpCode) =>
      _api.verifyOldEmail(otpCode);

  Future<void> confirmNewEmail(
    EmailChangeTicket ticket,
    String newEmail,
    String otpCode,
  ) async {
    final me = await _api.confirmNewEmail(ticket.ticket, newEmail, otpCode);
    await _setMe(me);
  }

  Future<DeletionStatus> requestDeletion(String otpCode) async {
    final status = await _api.requestDeletion(otpCode);
    await _loadMeQuietly();
    return status;
  }

  Future<DeletionStatus> cancelDeletion() async {
    final status = await _api.cancelDeletion();
    await _loadMeQuietly();
    return status;
  }

  Future<String> exportData() => _api.exportData();

  /// 兑换成功后直接用返回的最新权益，不用再拉一次。
  Future<RedeemGrant> redeem(String code) async {
    final (grant, json) = await _api.redeem(code);
    if (json.isNotEmpty) {
      _entitlements =
          CachedEntitlements(json: json, etag: null, fetchedAt: _now());
      await _api.store.writeEntitlements(_entitlements!);
      notifyListeners();
    } else {
      unawaited(refreshEntitlements());
    }
    return grant;
  }

  // -------------------------------------------------------------------------
  // 内部
  // -------------------------------------------------------------------------

  void _handleSessionEnded(CloudApiException reason) {
    _clearState();
    _signOutNotice = reason.message;
    notifyListeners();
  }

  void _clearState() {
    _signedIn = false;
    _me = null;
    _entitlements = null;
  }

  Future<void> _setMe(CloudMe me) async {
    if (!_signedIn) return;
    _me = me;
    await _api.store.writeRaw(CloudSessionStore.meKey, jsonEncode(_meToJson(me)));
    notifyListeners();
  }

  Future<CloudMe?> _readMeCache() async {
    final raw = await _api.store.readRaw(CloudSessionStore.meKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? CloudMe.fromJson(Map<String, Object?>.from(decoded))
          : null;
    } on FormatException {
      return null;
    }
  }

  /// 缓存只存展示需要的字段；头像临时地址不存（它会过期）。
  static Map<String, Object?> _meToJson(CloudMe me) => {
        'id': me.id,
        'email': me.email,
        'has_password': me.hasPassword,
        'created_at': me.createdAt?.toUtc().toIso8601String(),
        'profile': {
          'display_name': me.profile.displayName,
          'updated_at': me.profile.updatedAt?.toUtc().toIso8601String(),
        },
        if (me.deletion != null)
          'deletion': {
            'pending': me.deletion!.pending,
            'delete_after': me.deletion!.deleteAfter?.toUtc().toIso8601String(),
          },
      };
}
