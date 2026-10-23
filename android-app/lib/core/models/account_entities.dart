import 'package:decimal/decimal.dart';
import '../account/account_movement_projection.dart';
import '../account/liability_balance_mode.dart';

enum AccountType {
  cash,
  debit,
  credit,
  savings,
  investment,
  loan,
  other,
}

enum AccountOpeningBalanceQuality { exact, legacyUnknown }

extension AccountOpeningBalanceQualityX on AccountOpeningBalanceQuality {
  String get storageKey => switch (this) {
        AccountOpeningBalanceQuality.exact => 'exact',
        AccountOpeningBalanceQuality.legacyUnknown => 'legacy_unknown',
      };

  static AccountOpeningBalanceQuality fromStorage(String? value) =>
      value == 'exact'
          ? AccountOpeningBalanceQuality.exact
          : AccountOpeningBalanceQuality.legacyUnknown;
}

enum AccountStatus { active, archived, legacyHidden }

extension AccountStatusX on AccountStatus {
  String get storageKey => switch (this) {
        AccountStatus.active => 'active',
        AccountStatus.archived => 'archived',
        AccountStatus.legacyHidden => 'legacy_hidden',
      };

  static AccountStatus fromStorage(String? value) => switch (value) {
        'archived' => AccountStatus.archived,
        'legacy_hidden' => AccountStatus.legacyHidden,
        _ => AccountStatus.active,
      };
}

extension AccountTypeX on AccountType {
  String get storageKey => switch (this) {
        AccountType.cash => 'cash',
        AccountType.debit => 'debit',
        AccountType.credit => 'credit',
        AccountType.savings => 'savings',
        AccountType.investment => 'investment',
        AccountType.loan => 'loan',
        AccountType.other => 'other',
      };

  String get label => switch (this) {
        AccountType.cash => '现金',
        AccountType.debit => '储蓄卡',
        AccountType.credit => '信用卡',
        AccountType.savings => '存款',
        AccountType.investment => '投资',
        AccountType.loan => '贷款',
        AccountType.other => '其他',
      };

  bool get liability => this == AccountType.credit || this == AccountType.loan;

  static AccountType fromStorage(String? value) {
    for (final type in AccountType.values) {
      if (type.storageKey == value) return type;
    }
    return AccountType.cash;
  }
}

class AccountEntity {
  final int id;
  final String uuid;
  final String name;
  final String currencyCode;
  final AccountType type;
  final Decimal openingBalance;
  final bool includeInNetWorth;
  final String institution;
  final int sortOrder;
  final bool isDeleted;
  final int createdMs;
  final int updatedMs;
  final int? openingBalanceEffectiveMs;
  final int openingBalanceSequence;
  final AccountOpeningBalanceQuality openingBalanceQuality;
  final AccountStatus status;
  final int? archivedMs;
  final int? lastVerifiedMs;
  final int? verificationIntervalDays;

  /// A5 负债余额口径。`legacyHybrid`（默认）= 正余额算资产且 active 档案
  /// 本金另算负债；`ledger` = 余额是唯一真相，档案本金不进总负债。
  /// 老库升级和老备份读入都必须回落 legacyHybrid，否则口径静默翻转。
  final LiabilityBalanceMode balanceMode;

  const AccountEntity({
    required this.id,
    this.uuid = '',
    required this.name,
    this.currencyCode = 'CNY',
    this.type = AccountType.cash,
    required this.openingBalance,
    this.includeInNetWorth = true,
    this.institution = '',
    this.sortOrder = 0,
    this.isDeleted = false,
    this.createdMs = 0,
    this.updatedMs = 0,
    this.openingBalanceEffectiveMs,
    this.openingBalanceSequence = 0,
    this.openingBalanceQuality = AccountOpeningBalanceQuality.legacyUnknown,
    this.status = AccountStatus.active,
    this.archivedMs,
    this.lastVerifiedMs,
    this.verificationIntervalDays,
    this.balanceMode = LiabilityBalanceMode.legacyHybrid,
  });

  bool get isArchived => status == AccountStatus.archived;
  bool get isLegacyHidden => isDeleted || status == AccountStatus.legacyHidden;

  Map<String, Object?> toMap() => {
        'id': id == 0 ? null : id,
        'uuid': uuid,
        'name': name,
        'currency_code': currencyCode,
        'type': type.storageKey,
        'opening_balance': openingBalance.toString(),
        'include_in_net_worth': includeInNetWorth ? 1 : 0,
        'institution': institution,
        'sort_order': sortOrder,
        'is_deleted': isDeleted ? 1 : 0,
        'created_ms': createdMs,
        'updated_ms': updatedMs,
        'opening_balance_effective_ms': openingBalanceEffectiveMs,
        'opening_balance_sequence': openingBalanceSequence,
        'opening_balance_quality': openingBalanceQuality.storageKey,
        'status': status.storageKey,
        'archived_ms': archivedMs,
        'last_verified_ms': lastVerifiedMs,
        'verification_interval_days': verificationIntervalDays,
        'balance_mode': balanceMode.storageKey,
      };

  factory AccountEntity.fromMap(Map<String, Object?> m) => AccountEntity(
        id: m['id'] as int,
        uuid: m['uuid'] as String? ?? '',
        name: m['name'] as String,
        currencyCode: m['currency_code'] as String? ?? 'CNY',
        type: AccountTypeX.fromStorage(m['type'] as String?),
        openingBalance:
            Decimal.tryParse(m['opening_balance'] as String? ?? '') ??
                Decimal.zero,
        includeInNetWorth: ((m['include_in_net_worth'] as int?) ?? 1) == 1,
        institution: m['institution'] as String? ?? '',
        sortOrder: (m['sort_order'] as int?) ?? 0,
        isDeleted: ((m['is_deleted'] as int?) ?? 0) == 1,
        createdMs: (m['created_ms'] as int?) ?? 0,
        updatedMs: (m['updated_ms'] as int?) ?? 0,
        openingBalanceEffectiveMs: m['opening_balance_effective_ms'] as int?,
        openingBalanceSequence: (m['opening_balance_sequence'] as int?) ?? 0,
        openingBalanceQuality: AccountOpeningBalanceQualityX.fromStorage(
          m['opening_balance_quality'] as String?,
        ),
        status: AccountStatusX.fromStorage(m['status'] as String?),
        archivedMs: m['archived_ms'] as int?,
        lastVerifiedMs: m['last_verified_ms'] as int?,
        verificationIntervalDays: m['verification_interval_days'] as int?,
        // 缺列/未知值一律 legacyHybrid（见 LiabilityBalanceModeX.fromStorage）。
        balanceMode: LiabilityBalanceModeX.fromStorage(
          m['balance_mode'] as String?,
        ),
      );
}

class AccountBalanceValue {
  final Decimal balance;
  final AccountMovementProjectionValue movement;
  final AccountBalanceCheckpointEntity? checkpoint;
  final DateTime? trustedFrom;

  const AccountBalanceValue({
    required this.balance,
    required this.movement,
    this.checkpoint,
    this.trustedFrom,
  });
}

class AccountBalanceTrendPoint {
  final DateTime asOf;
  final Decimal balance;
  final bool trusted;

  const AccountBalanceTrendPoint({
    required this.asOf,
    required this.balance,
    required this.trusted,
  });
}

class AccountBalanceTrendValue {
  final DateTime trustedFrom;
  final List<AccountBalanceTrendPoint> points;

  const AccountBalanceTrendValue({
    required this.trustedFrom,
    required this.points,
  });

  bool get hasTrend => points.length >= 2;
}

enum AccountBalanceCheckpointKind { anchor, reversal }

extension AccountBalanceCheckpointKindX on AccountBalanceCheckpointKind {
  String get storageKey =>
      this == AccountBalanceCheckpointKind.anchor ? 'anchor' : 'reversal';

  static AccountBalanceCheckpointKind fromStorage(String? value) =>
      value == 'reversal'
          ? AccountBalanceCheckpointKind.reversal
          : AccountBalanceCheckpointKind.anchor;
}

class AccountBalanceCheckpointEntity {
  final int id;
  final String uuid;
  final int accountId;
  final AccountBalanceCheckpointKind eventKind;
  final int effectiveMs;
  final int sequence;
  final String timezone;
  final int knowledgeCutoffMs;
  final Decimal targetBalance;
  final Decimal calculatedBefore;
  final Decimal deltaAtCreation;
  final String reason;
  final String note;
  final String status;
  final int? reversalOf;
  final int createdMs;
  final int updatedMs;

  const AccountBalanceCheckpointEntity({
    required this.id,
    required this.uuid,
    required this.accountId,
    required this.eventKind,
    required this.effectiveMs,
    required this.sequence,
    required this.timezone,
    required this.knowledgeCutoffMs,
    required this.targetBalance,
    required this.calculatedBefore,
    required this.deltaAtCreation,
    required this.reason,
    required this.note,
    required this.status,
    required this.reversalOf,
    required this.createdMs,
    required this.updatedMs,
  });

  bool get isAnchor => eventKind == AccountBalanceCheckpointKind.anchor;
  bool get isReversal => eventKind == AccountBalanceCheckpointKind.reversal;

  factory AccountBalanceCheckpointEntity.fromMap(Map<String, Object?> m) =>
      AccountBalanceCheckpointEntity(
        id: m['id'] as int,
        uuid: m['uuid'] as String? ?? '',
        accountId: m['account_id'] as int,
        eventKind: AccountBalanceCheckpointKindX.fromStorage(
          m['event_kind'] as String?,
        ),
        effectiveMs: m['effective_ms'] as int,
        sequence: (m['sequence'] as int?) ?? 0,
        timezone: m['timezone'] as String? ?? 'device_local',
        knowledgeCutoffMs: (m['knowledge_cutoff_ms'] as int?) ?? 0,
        targetBalance: Decimal.tryParse(m['target_balance'] as String? ?? '') ??
            Decimal.zero,
        calculatedBefore:
            Decimal.tryParse(m['calculated_before'] as String? ?? '') ??
                Decimal.zero,
        deltaAtCreation:
            Decimal.tryParse(m['delta_at_creation'] as String? ?? '') ??
                Decimal.zero,
        reason: m['reason'] as String? ?? 'manual',
        note: m['note'] as String? ?? '',
        status: m['status'] as String? ?? 'active',
        reversalOf: m['reversal_of'] as int?,
        createdMs: (m['created_ms'] as int?) ?? 0,
        updatedMs: (m['updated_ms'] as int?) ?? 0,
      );
}
