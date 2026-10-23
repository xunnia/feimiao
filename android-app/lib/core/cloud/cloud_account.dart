import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'cloud_api.dart';
import 'cloud_config.dart';
import 'cloud_errors.dart';
import 'cloud_models.dart';
import 'cloud_session_store.dart';
import 'profile_sync.dart';

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
  CloudAccount({
    CloudApi? api,
    bool? enabled,
    DateTime Function()? clock,
    this.profileStore,
  })  : _api = api ?? CloudApi(),
        enabled = enabled ?? CloudConfig.accountEnabled,
        _now = clock ?? DateTime.now {
    _api.onSessionEnded = _handleSessionEnded;
  }

  final CloudApi _api;
  final bool enabled;
  final DateTime Function() _now;

  /// 本机昵称。为 null 时不同步昵称（测试或没接账本时）。
  final LocalProfileStore? profileStore;
  Future<void>? _nicknameSyncTail;

  bool _ready = false;
  bool _signedIn = false;
  CloudMe? _me;
  CachedEntitlements? _entitlements;
  String? _signOutNotice;
  Future<void>? _entitlementsInFlight;
  bool _observing = false;
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _initializing;

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _checkCurrent(int generation) {
    if (!_isCurrent(generation)) throw CloudApiException.sessionChanged();
  }

  bool get ready => _ready;
  bool get signedIn => _signedIn;
  CloudMe? get me => _me;
  Entitlements? get entitlements => _entitlements?.value;

  /// 权益最后一次成功拉取的时间，离线时显示"更新于…"。
  DateTime? get entitlementsFetchedAt => _entitlements?.fetchedAt;

  /// 被动掉登录的原因（被踢下线、封号、登录过期），界面提示一次后调 [clearSignOutNotice]。
  String? get signOutNotice => _signOutNotice;

  CloudApi get api => _api;

  Future<void> init() => _initializing ??= _init();

  Future<void> _init() async {
    final generation = _generation;
    if (!enabled) {
      _ready = true;
      notifyListeners();
      return;
    }
    try {
      final restored = await _api.restore();
      if (!_isCurrent(generation)) return;
      _signedIn = restored;
      if (restored) {
        final me = await _readStartupCache(_readMeCache);
        if (!_isCurrent(generation)) return;
        final entitlements =
            await _readStartupCache(_api.store.readEntitlements);
        if (!_isCurrent(generation)) return;
        _me = me;
        _entitlements = entitlements;
      }
    } on CloudApiException catch (error) {
      // init is started without awaiting it. A login/logout may supersede its
      // storage reads; that is cancellation, not a startup failure.
      if (error.rawCode != 'LOCAL_SESSION_CHANGED') {
        // A local storage outage must not escape the unawaited startup task.
        // Keep the app usable offline; never expose cached credentials here.
        debugPrint('cloud restore unavailable: ${error.rawCode}');
      }
    } finally {
      if (!_disposed) {
        _ready = true;
        if (!_observing) {
          WidgetsBinding.instance.addObserver(this);
          _observing = true;
        }
        notifyListeners();
      }
    }
    if (_isCurrent(generation) && _signedIn) unawaited(refresh());
  }

  Future<T?> _readStartupCache<T>(Future<T?> Function() read) async {
    try {
      return await read();
    } on CloudApiException catch (error) {
      if (error.rawCode == 'LOCAL_SESSION_CHANGED') rethrow;
      return null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on RangeError {
      return null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _signedIn) {
      unawaited(refreshEntitlements());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _api.onSessionEnded = null;
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
    final inFlight = _entitlementsInFlight;
    if (inFlight != null) return inFlight;
    late final Future<void> future;
    future = _fetchEntitlements().whenComplete(() {
      if (identical(_entitlementsInFlight, future)) {
        _entitlementsInFlight = null;
      }
    });
    return _entitlementsInFlight = future;
  }

  Future<void> _fetchEntitlements() async {
    final generation = _generation;
    final session = _api.sessionGeneration;
    final cached = _entitlements;
    try {
      final result = await _api.entitlements(etag: cached?.etag);
      if (!_isCurrent(generation) || !_signedIn) return;
      final CachedEntitlements updated;
      if (result.notModified && cached != null) {
        updated = CachedEntitlements(
            json: cached.json, etag: cached.etag, fetchedAt: _now());
      } else if (result.json != null) {
        updated = CachedEntitlements(
            json: result.json!, etag: result.etag, fetchedAt: _now());
      } else {
        return;
      }
      await _api.store.writeEntitlements(updated, generation: session);
      if (!_isCurrent(generation)) return;
      _entitlements = updated;
      notifyListeners();
    } on CloudApiException catch (error) {
      debugPrint('entitlements refresh failed: $error');
    }
  }

  Future<void> _loadMeQuietly() async {
    final generation = _generation;
    try {
      await loadMe();
    } on CloudApiException catch (error) {
      debugPrint('me refresh failed: $error');
      return;
    }
    // 不等：本机资料可能还没读完，不能拖住登录和刷新。
    if (_isCurrent(generation)) unawaited(_syncNicknameQuietly(generation));
  }

  Future<void> _syncNicknameQuietly(int generation) async {
    final store = profileStore;
    if (store == null) return;
    // 本机资料读完再比，否则会把"还没读到"当成"没设置"而拉回服务端的名字。
    await store.whenProfileLoaded();
    if (!_isCurrent(generation)) return;
    try {
      await syncNickname();
    } on CloudApiException catch (error) {
      debugPrint('nickname sync failed: $error');
    }
  }

  /// 按 `updated_at` 把昵称同步到较旧的一边。本机刚改完昵称时调用，失败抛
  /// [CloudApiException]（比如服务端认为含敏感词），本机昵称保持不变。
  /// 没登录、没接本机存储、本机资料还没读完时什么都不做。
  /// 多次调用按顺序执行，每次都用调用时最新的本机昵称重新判断。
  Future<void> syncNickname() {
    final generation = _generation;
    final previous = _nicknameSyncTail;
    final run = previous == null
        ? _syncNickname(generation)
        : previous
            .then((_) {}, onError: (_) {})
            .then((_) => _syncNickname(generation));
    _nicknameSyncTail = run;
    return run;
  }

  Future<void> _syncNickname(int generation) async {
    if (!_isCurrent(generation)) return;
    final store = profileStore;
    final me = _me;
    if (store == null || !_signedIn || me == null || !store.profileLoaded) {
      return;
    }
    final action = decideNicknameSync(
      local: store.nickname,
      localUpdatedAt: store.nicknameUpdatedAt,
      remote: me.profile.displayName,
      remoteUpdatedAt: me.profile.updatedAt,
    );
    switch (action) {
      case NicknameSyncAction.none:
        return;
      case NicknameSyncAction.pull:
        await store.applyCloudNickname(
          normalizeNickname(me.profile.displayName ?? ''),
          me.profile.updatedAt,
        );
      case NicknameSyncAction.push:
        await updateDisplayName(normalizeNickname(store.nickname));
    }
  }

  Future<CloudMe> loadMe() async {
    final generation = _generation;
    final session = _api.sessionGeneration;
    final me = await _api.me();
    await _setMe(me, generation, session);
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
    _clearState();
    final generation = _generation;
    _signOutNotice = null;
    notifyListeners();
    final LoginResult result;
    try {
      result = await call();
    } on CloudApiException catch (error) {
      _checkCurrent(generation);
      final limit = _api.deviceLimitOf(error);
      if (limit != null) return LoginNeedsDeviceChoice(limit);
      rethrow;
    }
    _checkCurrent(generation);
    _signedIn = true;
    _signOutNotice = null;
    _me = null;
    _entitlements = null;
    notifyListeners();
    await refresh();
    _checkCurrent(generation);
    return LoginSucceeded(isNewUser: result.isNewUser);
  }

  /// 主动退出登录。只清账号信息，本地账本不动。
  Future<void> logout() async {
    _clearState();
    _signOutNotice = null;
    notifyListeners();
    await _api.logout();
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
    final generation = _generation;
    await _api.revokeDevice(device);
    if (device.isCurrent && _isCurrent(generation)) {
      _clearState();
      notifyListeners();
    }
  }

  Future<void> revokeOtherDevices() => _api.revokeOtherDevices();

  Future<void> updateDisplayName(String name) async {
    final generation = _generation;
    final session = _api.sessionGeneration;
    final profile = await _api.updateProfile(displayName: name);
    _checkCurrent(generation);
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
        generation,
        session,
      );
    }
  }

  /// 设置或修改密码（验证码来自 [OtpPurpose.setPassword]）。其他设备会下线。
  Future<void> setPassword(String otpCode, String newPassword) async {
    final generation = _generation;
    await _api.setPassword(otpCode, newPassword);
    _checkCurrent(generation);
    await _loadMeQuietly();
  }

  Future<EmailChangeTicket> verifyOldEmail(String otpCode) =>
      _api.verifyOldEmail(otpCode);

  Future<void> confirmNewEmail(
    EmailChangeTicket ticket,
    String newEmail,
    String otpCode,
  ) async {
    final generation = _generation;
    final session = _api.sessionGeneration;
    final me = await _api.confirmNewEmail(ticket.ticket, newEmail, otpCode);
    await _setMe(me, generation, session);
  }

  Future<DeletionStatus> requestDeletion(String otpCode) async {
    final generation = _generation;
    final status = await _api.requestDeletion(otpCode);
    _checkCurrent(generation);
    await _loadMeQuietly();
    return status;
  }

  Future<DeletionStatus> cancelDeletion() async {
    final generation = _generation;
    final status = await _api.cancelDeletion();
    _checkCurrent(generation);
    await _loadMeQuietly();
    return status;
  }

  Future<String> exportData() => _api.exportData();

  /// 兑换成功后直接用返回的最新权益，不用再拉一次。
  Future<RedeemGrant> redeem(String code) async {
    final generation = _generation;
    final session = _api.sessionGeneration;
    final (grant, json) = await _api.redeem(code);
    _checkCurrent(generation);
    if (json.isNotEmpty) {
      final updated =
          CachedEntitlements(json: json, etag: null, fetchedAt: _now());
      await _api.store.writeEntitlements(updated, generation: session);
      _checkCurrent(generation);
      _entitlements = updated;
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
    if (_disposed) return;
    _clearState();
    _signOutNotice = reason.message;
    notifyListeners();
  }

  void _clearState() {
    _generation++;
    _entitlementsInFlight = null;
    _nicknameSyncTail = null;
    _signedIn = false;
    _me = null;
    _entitlements = null;
  }

  Future<void> _setMe(CloudMe me, int generation, int session) async {
    _checkCurrent(generation);
    if (!_signedIn) return;
    if (!await _api.store.writeRaw(
        CloudSessionStore.meKey, jsonEncode(_meToJson(me)),
        generation: session)) {
      throw CloudApiException.storageFailure();
    }
    _checkCurrent(generation);
    _me = me;
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
