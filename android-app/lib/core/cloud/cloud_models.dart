/// 后端接口的数据结构，字段和 feimiao-server `api/openapi.yaml` 一一对应。
///
/// 解析一律宽松：缺字段给默认值，认不出的枚举值归到 unknown，
/// 服务端以后加字段或加枚举值，老版本 App 也不会崩。
library;

String? _str(Object? v) => v is String ? v : null;
int _int(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;
int? _intOrNull(Object? v) => v is num ? v.toInt() : null;
double _double(Object? v, [double fallback = 0]) =>
    v is num ? v.toDouble() : fallback;
bool _bool(Object? v, [bool fallback = false]) => v is bool ? v : fallback;
DateTime? _date(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;
Map<String, Object?> _map(Object? v) =>
    v is Map ? Map<String, Object?>.from(v) : const {};
List<Object?> _list(Object? v) => v is List ? v : const [];

enum OtpPurpose {
  login('login'),
  changeEmailOld('change_email_old'),
  changeEmailNew('change_email_new'),
  setPassword('set_password'),
  deleteAccount('delete_account');

  const OtpPurpose(this.wire);
  final String wire;
}

/// 访问令牌和刷新令牌。过期时间按本机时钟换算成绝对时间保存。
class CloudTokens {
  const CloudTokens({
    required this.accessToken,
    required this.accessExpiresAt,
    required this.refreshToken,
    required this.refreshExpiresAt,
  });

  factory CloudTokens.fromResponse(Map<String, Object?> json, DateTime now) =>
      CloudTokens(
        accessToken: _str(json['access_token']) ?? '',
        accessExpiresAt:
            now.add(Duration(seconds: _int(json['access_expires_in']))),
        refreshToken: _str(json['refresh_token']) ?? '',
        refreshExpiresAt:
            now.add(Duration(seconds: _int(json['refresh_expires_in']))),
      );

  factory CloudTokens.fromStorage(Map<String, Object?> json) => CloudTokens(
        accessToken: _str(json['access_token']) ?? '',
        accessExpiresAt: DateTime.fromMillisecondsSinceEpoch(
            _int(json['access_expires_at_ms'])),
        refreshToken: _str(json['refresh_token']) ?? '',
        refreshExpiresAt: DateTime.fromMillisecondsSinceEpoch(
            _int(json['refresh_expires_at_ms'])),
      );

  final String accessToken;
  final DateTime accessExpiresAt;
  final String refreshToken;
  final DateTime refreshExpiresAt;

  bool get isUsable => accessToken.isNotEmpty && refreshToken.isNotEmpty;

  Map<String, Object?> toStorage() => {
        'access_token': accessToken,
        'access_expires_at_ms': accessExpiresAt.millisecondsSinceEpoch,
        'refresh_token': refreshToken,
        'refresh_expires_at_ms': refreshExpiresAt.millisecondsSinceEpoch,
      };
}

class LoginResult {
  const LoginResult({required this.tokens, required this.isNewUser});

  factory LoginResult.fromJson(Map<String, Object?> json, DateTime now) =>
      LoginResult(
        tokens: CloudTokens.fromResponse(json, now),
        isNewUser: _bool(json['is_new_user']),
      );

  final CloudTokens tokens;
  final bool isNewUser;
}

/// 登录设备。`/me/devices` 和 `DEVICE_LIMIT` 共用这一种结构和同一个列表组件。
class CloudDevice {
  const CloudDevice({
    required this.id,
    required this.platform,
    this.model,
    this.appVersion,
    this.lastSeenAt,
    this.lastLocation,
    this.createdAt,
    this.isCurrent = false,
  });

  factory CloudDevice.fromJson(Map<String, Object?> json) => CloudDevice(
        id: _str(json['id']) ?? '',
        platform: _str(json['platform']) ?? '',
        model: _str(json['model']),
        appVersion: _str(json['app_version']),
        lastSeenAt: _date(json['last_seen_at']),
        lastLocation: _str(json['last_location']),
        createdAt: _date(json['created_at']),
        isCurrent: _bool(json['is_current']),
      );

  final String id;
  final String platform;
  final String? model;
  final String? appVersion;
  final DateTime? lastSeenAt;
  final String? lastLocation;
  final DateTime? createdAt;
  final bool isCurrent;

  static List<CloudDevice> listFrom(Object? raw) => [
        for (final item in _list(raw))
          if (item is Map) CloudDevice.fromJson(_map(item)),
      ];
}

/// `DEVICE_LIMIT` 错误附带的信息：用它让用户选下线哪台，再调 resolve。
class DeviceLimitInfo {
  const DeviceLimitInfo({
    required this.loginTicket,
    required this.expiresAt,
    required this.maxDevices,
    required this.devices,
  });

  factory DeviceLimitInfo.fromDetails(
          Map<String, Object?> details, DateTime now) =>
      DeviceLimitInfo(
        loginTicket: _str(details['login_ticket']) ?? '',
        expiresAt: now.add(
            Duration(seconds: _int(details['login_ticket_expires_in'], 300))),
        maxDevices: _int(details['max_devices']),
        devices: CloudDevice.listFrom(details['devices']),
      );

  final String loginTicket;
  final DateTime expiresAt;
  final int maxDevices;
  final List<CloudDevice> devices;
}

class CloudProfile {
  const CloudProfile({this.displayName, this.avatarUrl, this.updatedAt});

  factory CloudProfile.fromJson(Map<String, Object?> json) => CloudProfile(
        displayName: _str(json['display_name']),
        avatarUrl: _str(json['avatar_url']),
        updatedAt: _date(json['updated_at']),
      );

  final String? displayName;

  /// 带签名的临时地址，只能用来马上下载，不要长期保存。
  final String? avatarUrl;
  final DateTime? updatedAt;
}

class DeletionStatus {
  const DeletionStatus({required this.pending, this.deleteAfter});

  factory DeletionStatus.fromJson(Map<String, Object?> json) => DeletionStatus(
        pending: _bool(json['pending']),
        deleteAfter: _date(json['delete_after']),
      );

  final bool pending;
  final DateTime? deleteAfter;
}

class CloudMe {
  const CloudMe({
    required this.id,
    required this.email,
    required this.hasPassword,
    required this.profile,
    this.createdAt,
    this.deletion,
  });

  factory CloudMe.fromJson(Map<String, Object?> json) {
    final deletion = json['deletion'];
    return CloudMe(
      id: _str(json['id']) ?? '',
      email: _str(json['email']) ?? '',
      hasPassword: _bool(json['has_password']),
      profile: CloudProfile.fromJson(_map(json['profile'])),
      createdAt: _date(json['created_at']),
      deletion: deletion is Map ? DeletionStatus.fromJson(_map(deletion)) : null,
    );
  }

  final String id;
  final String email;
  final bool hasPassword;
  final CloudProfile profile;
  final DateTime? createdAt;
  final DeletionStatus? deletion;
}

class EmailChangeTicket {
  const EmailChangeTicket({required this.ticket, required this.expiresAt});

  factory EmailChangeTicket.fromJson(Map<String, Object?> json, DateTime now) =>
      EmailChangeTicket(
        ticket: _str(json['change_ticket']) ?? '',
        expiresAt: now.add(Duration(seconds: _int(json['expires_in'], 900))),
      );

  final String ticket;
  final DateTime expiresAt;
}

// ---------------------------------------------------------------------------
// 权益
// ---------------------------------------------------------------------------

class TierInfo {
  const TierInfo({required this.key, required this.name, this.isInternal = false});

  factory TierInfo.fromJson(Map<String, Object?> json) => TierInfo(
        key: _str(json['key']) ?? '',
        name: _str(json['name']) ?? '',
        isInternal: _bool(json['is_internal']),
      );

  final String key;
  final String name;
  final bool isInternal;
}

enum MembershipStatus { none, active, grace, expired, unknown }

class Membership {
  const Membership({
    required this.status,
    this.endsAt,
    this.graceUntil,
    this.trial = false,
    this.source,
  });

  factory Membership.fromJson(Map<String, Object?> json) => Membership(
        status: switch (_str(json['status'])) {
          'none' => MembershipStatus.none,
          'active' => MembershipStatus.active,
          'grace' => MembershipStatus.grace,
          'expired' => MembershipStatus.expired,
          _ => MembershipStatus.unknown,
        },
        endsAt: _date(json['ends_at']),
        graceUntil: _date(json['grace_until']),
        trial: _bool(json['trial']),
        source: _str(json['source']),
      );

  final MembershipStatus status;
  final DateTime? endsAt;
  final DateTime? graceUntil;
  final bool trial;

  /// admin / redeem / trial / iap，只用于展示。
  final String? source;
}

class WeeklyQuota {
  const WeeklyQuota({required this.usedPct, this.resetsAt});

  factory WeeklyQuota.fromJson(Map<String, Object?> json) => WeeklyQuota(
        usedPct: _double(json['used_pct']).clamp(0, 100).toDouble(),
        resetsAt: _date(json['resets_at']),
      );

  /// 0~100。服务端保证不超过 100，这里再夹一次。
  final double usedPct;
  final DateTime? resetsAt;
}

class BonusQuota {
  const BonusQuota({required this.remainingPct, this.nextExpiryAt});

  factory BonusQuota.fromJson(Map<String, Object?> json) => BonusQuota(
        remainingPct: _double(json['remaining_pct']).clamp(0, 100).toDouble(),
        nextExpiryAt: _date(json['next_expiry_at']),
      );

  final double remainingPct;
  final DateTime? nextExpiryAt;
}

class Quota {
  const Quota({
    required this.showBar,
    this.weekly,
    this.bonus,
    this.warnPct = const [],
  });

  factory Quota.fromJson(Map<String, Object?> json) {
    final weekly = json['weekly'];
    final bonus = json['bonus'];
    return Quota(
      // 只有明确是 bar 才显示；hidden 或认不出的值都不显示（免费档默认）。
      showBar: _str(json['display']) == 'bar',
      weekly: weekly is Map ? WeeklyQuota.fromJson(_map(weekly)) : null,
      bonus: bonus is Map ? BonusQuota.fromJson(_map(bonus)) : null,
      warnPct: [
        for (final v in _list(json['warn_pct']))
          if (v is num) v.toInt(),
      ],
    );
  }

  final bool showBar;
  final WeeklyQuota? weekly;
  final BonusQuota? bonus;
  final List<int> warnPct;
}

class FeatureState {
  const FeatureState({
    required this.enabled,
    this.metering,
    this.remaining,
    this.period,
    this.resetsAt,
    this.lockedReason,
  });

  factory FeatureState.fromJson(Map<String, Object?> json) => FeatureState(
        enabled: _bool(json['enabled']),
        metering: _str(json['metering']),
        remaining: _intOrNull(json['remaining']),
        period: _str(json['period']),
        resetsAt: _date(json['resets_at']),
        lockedReason: _str(json['locked_reason']),
      );

  final bool enabled;
  final String? metering;
  final int? remaining;
  final String? period;
  final DateTime? resetsAt;
  final String? lockedReason;
}

class PaywallTier {
  const PaywallTier({
    required this.key,
    required this.name,
    this.highlights = const [],
  });

  factory PaywallTier.fromJson(Map<String, Object?> json) => PaywallTier(
        key: _str(json['key']) ?? '',
        name: _str(json['name']) ?? '',
        highlights: [
          for (final v in _list(json['highlights']))
            if (v is String) v,
        ],
      );

  final String key;
  final String name;
  final List<String> highlights;
}

class Entitlements {
  const Entitlements({
    required this.tier,
    required this.membership,
    required this.quota,
    this.features = const {},
    this.maxImages = 0,
    this.maxImageBytes = 0,
    this.redeemInApp = false,
    this.paywallTiers = const [],
    this.internalByokAllowed = false,
  });

  factory Entitlements.fromJson(Map<String, Object?> json) {
    final limits = _map(json['limits']);
    final internal = json['internal'];
    return Entitlements(
      tier: TierInfo.fromJson(_map(json['tier'])),
      membership: Membership.fromJson(_map(json['membership'])),
      quota: Quota.fromJson(_map(json['quota'])),
      features: {
        for (final entry in _map(json['features']).entries)
          if (entry.value is Map)
            entry.key: FeatureState.fromJson(_map(entry.value)),
      },
      maxImages: _int(limits['max_images']),
      maxImageBytes: _int(limits['max_image_bytes']),
      redeemInApp: _bool(_map(json['redeem'])['in_app']),
      paywallTiers: [
        for (final item in _list(_map(json['paywall'])['tiers']))
          if (item is Map) PaywallTier.fromJson(_map(item)),
      ],
      internalByokAllowed:
          internal is Map && _bool(_map(internal)['byok_allowed']),
    );
  }

  final TierInfo tier;
  final Membership membership;
  final Quota quota;
  final Map<String, FeatureState> features;
  final int maxImages;
  final int maxImageBytes;

  /// 是否显示兑换码入口。以服务端为准，不按平台自己判断。
  final bool redeemInApp;
  final List<PaywallTier> paywallTiers;
  final bool internalByokAllowed;

  bool get isInternal => tier.isInternal;
}

class RedeemGrant {
  const RedeemGrant({required this.kind, this.days, this.summary});

  factory RedeemGrant.fromJson(Map<String, Object?> json) => RedeemGrant(
        kind: _str(json['kind']) ?? '',
        days: _intOrNull(json['days']),
        summary: _str(json['summary']),
      );

  final String kind;
  final int? days;

  /// 可以直接展示，比如「获得普通会员 30 天」。
  final String? summary;
}
