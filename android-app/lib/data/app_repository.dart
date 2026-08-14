import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../core/budget/budget_period.dart';
import '../core/budget/budget_plan_v2.dart';
import '../core/budget/budget_special_tracking.dart';
import '../core/budget/budget_transaction_family.dart';
import '../core/budget/budget_window_resolver.dart';
import '../core/budget/fixed_commitment.dart';
import '../core/account/account_activity.dart';
import '../core/account/account_balance_checkpoint.dart';
import '../core/account/account_movement_projection.dart';
import '../core/account/liability_balance_mode.dart';
import '../core/account/net_worth_snapshot.dart';
import '../core/account/net_worth_verified_checkpoint.dart';
import '../core/ai/ai_provider_config.dart';
import '../core/ai/report_execution_fence.dart';
import '../core/assets/asset_allocation.dart';
import '../core/assets/asset_enhancements.dart';
import '../core/backup/backup_package_codec.dart';
import '../core/import/bill_import.dart';
import '../core/ledger/ledger_policy.dart';
import '../core/money_format.dart';
import '../core/models/category_icon_style.dart';
import '../core/models/category_seed.dart';
import '../core/models/recurring_rule.dart';
import '../core/models/transaction_card_display.dart';
import '../core/models/transaction_kind.dart';
import '../core/models/transaction_record.dart';
import '../core/security/secure_key_store.dart';
import '../core/statistics/consumption_projection.dart';
import '../core/statistics/metric_contract.dart';
import '../core/transaction_time.dart';

// ---------------------------------------------------------------------------
// 领域实体
// ---------------------------------------------------------------------------

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

class BudgetFixedOccurrenceEntity {
  final int id;
  final String uuid;
  final int revisionId;
  final FixedCommitmentOccurrence occurrence;
  final int? resolvedMs;
  final int createdMs;
  final int updatedMs;

  const BudgetFixedOccurrenceEntity({
    required this.id,
    required this.uuid,
    required this.revisionId,
    required this.occurrence,
    required this.resolvedMs,
    required this.createdMs,
    required this.updatedMs,
  });

  String get templateId => occurrence.templateId;
  int get planId => occurrence.planId;
  int get plannedCents => occurrence.plannedCents;
  DateTime get dueDate => occurrence.dueDate;
  FixedCommitmentResolutionStatus get resolutionStatus =>
      occurrence.resolutionStatus;
  String? get matchedTransactionFamilyId =>
      occurrence.matchedTransactionFamilyId;
}

enum PhysicalAssetSourceType {
  historicalExisting,
  fromTransaction,
  newPurchaseWithAccount,
  giftReceived,
  inheritance,
  manualOther,
}

extension PhysicalAssetSourceTypeX on PhysicalAssetSourceType {
  String get storageKey => switch (this) {
        PhysicalAssetSourceType.historicalExisting => 'historical_existing',
        PhysicalAssetSourceType.fromTransaction => 'from_transaction',
        PhysicalAssetSourceType.newPurchaseWithAccount =>
          'new_purchase_with_account',
        PhysicalAssetSourceType.giftReceived => 'gift_received',
        PhysicalAssetSourceType.inheritance => 'inheritance',
        PhysicalAssetSourceType.manualOther => 'manual_other',
      };

  String get label => switch (this) {
        PhysicalAssetSourceType.historicalExisting => '历史已有，补录一个',
        PhysicalAssetSourceType.fromTransaction => '从已有账单加入',
        PhysicalAssetSourceType.newPurchaseWithAccount => '新购买，同时记账',
        PhysicalAssetSourceType.giftReceived => '别人赠送',
        PhysicalAssetSourceType.inheritance => '继承/转入',
        PhysicalAssetSourceType.manualOther => '其他来源',
      };

  static PhysicalAssetSourceType fromStorage(String? value) {
    for (final type in PhysicalAssetSourceType.values) {
      if (type.storageKey == value) return type;
    }
    return PhysicalAssetSourceType.historicalExisting;
  }
}

enum PhysicalAssetStatus {
  active,
  idle,
  sold,
  disposed,
  lost,
  gifted,
  archived,
}

enum PhysicalAssetEconomicStatus {
  owned,
  sold,
  returned,
  scrapped,
  lost,
  gifted,
}

extension PhysicalAssetEconomicStatusX on PhysicalAssetEconomicStatus {
  String get storageKey => switch (this) {
        PhysicalAssetEconomicStatus.owned => 'owned',
        PhysicalAssetEconomicStatus.sold => 'sold',
        PhysicalAssetEconomicStatus.returned => 'returned',
        PhysicalAssetEconomicStatus.scrapped => 'scrapped',
        PhysicalAssetEconomicStatus.lost => 'lost',
        PhysicalAssetEconomicStatus.gifted => 'gifted',
      };

  String get label => switch (this) {
        PhysicalAssetEconomicStatus.owned => '持有中',
        PhysicalAssetEconomicStatus.sold => '已出售',
        PhysicalAssetEconomicStatus.returned => '已退货',
        PhysicalAssetEconomicStatus.scrapped => '已报废',
        PhysicalAssetEconomicStatus.lost => '已丢失',
        PhysicalAssetEconomicStatus.gifted => '已赠送',
      };

  bool get ownsValue => this == PhysicalAssetEconomicStatus.owned;

  static PhysicalAssetEconomicStatus fromStorage(String? value) {
    for (final status in PhysicalAssetEconomicStatus.values) {
      if (status.storageKey == value) return status;
    }
    return PhysicalAssetEconomicStatus.owned;
  }
}

enum PhysicalAssetUsageStatus { active, idle, unknown }

extension PhysicalAssetUsageStatusX on PhysicalAssetUsageStatus {
  String get storageKey => switch (this) {
        PhysicalAssetUsageStatus.active => 'active',
        PhysicalAssetUsageStatus.idle => 'idle',
        PhysicalAssetUsageStatus.unknown => 'unknown',
      };

  String get label => switch (this) {
        PhysicalAssetUsageStatus.active => '使用中',
        PhysicalAssetUsageStatus.idle => '闲置',
        PhysicalAssetUsageStatus.unknown => '使用状态待确认',
      };

  static PhysicalAssetUsageStatus fromStorage(String? value) {
    for (final status in PhysicalAssetUsageStatus.values) {
      if (status.storageKey == value) return status;
    }
    return PhysicalAssetUsageStatus.unknown;
  }
}

enum AssetVisibilityStatus { active, archived }

extension AssetVisibilityStatusX on AssetVisibilityStatus {
  String get storageKey => switch (this) {
        AssetVisibilityStatus.active => 'active',
        AssetVisibilityStatus.archived => 'archived',
      };

  String get label => switch (this) {
        AssetVisibilityStatus.active => '显示中',
        AssetVisibilityStatus.archived => '已归档',
      };

  static AssetVisibilityStatus fromStorage(String? value) {
    return value == 'archived'
        ? AssetVisibilityStatus.archived
        : AssetVisibilityStatus.active;
  }
}

enum AssetInclusionQuality { confirmed, needsReview }

extension AssetInclusionQualityX on AssetInclusionQuality {
  String get storageKey => switch (this) {
        AssetInclusionQuality.confirmed => 'confirmed',
        AssetInclusionQuality.needsReview => 'needs_review',
      };

  String get label => switch (this) {
        AssetInclusionQuality.confirmed => '已确认',
        AssetInclusionQuality.needsReview => '待确认',
      };

  static AssetInclusionQuality fromStorage(String? value) {
    return value == 'needs_review'
        ? AssetInclusionQuality.needsReview
        : AssetInclusionQuality.confirmed;
  }
}

PhysicalAssetEconomicStatus _physicalEconomicFromLegacyStatus(
  PhysicalAssetStatus status,
) =>
    switch (status) {
      PhysicalAssetStatus.sold => PhysicalAssetEconomicStatus.sold,
      PhysicalAssetStatus.disposed => PhysicalAssetEconomicStatus.scrapped,
      PhysicalAssetStatus.lost => PhysicalAssetEconomicStatus.lost,
      PhysicalAssetStatus.gifted => PhysicalAssetEconomicStatus.gifted,
      PhysicalAssetStatus.active ||
      PhysicalAssetStatus.idle ||
      PhysicalAssetStatus.archived =>
        PhysicalAssetEconomicStatus.owned,
    };

PhysicalAssetUsageStatus _physicalUsageFromLegacyStatus(
  PhysicalAssetStatus status,
) =>
    switch (status) {
      PhysicalAssetStatus.active => PhysicalAssetUsageStatus.active,
      PhysicalAssetStatus.idle => PhysicalAssetUsageStatus.idle,
      _ => PhysicalAssetUsageStatus.unknown,
    };

PhysicalAssetStatus _legacyPhysicalStatusFor({
  required PhysicalAssetEconomicStatus economicStatus,
  required PhysicalAssetUsageStatus usageStatus,
  required AssetVisibilityStatus visibilityStatus,
}) {
  if (visibilityStatus == AssetVisibilityStatus.archived) {
    return PhysicalAssetStatus.archived;
  }
  return switch (economicStatus) {
    PhysicalAssetEconomicStatus.owned =>
      usageStatus == PhysicalAssetUsageStatus.idle
          ? PhysicalAssetStatus.idle
          : PhysicalAssetStatus.active,
    PhysicalAssetEconomicStatus.sold => PhysicalAssetStatus.sold,
    PhysicalAssetEconomicStatus.returned ||
    PhysicalAssetEconomicStatus.scrapped =>
      PhysicalAssetStatus.disposed,
    PhysicalAssetEconomicStatus.lost => PhysicalAssetStatus.lost,
    PhysicalAssetEconomicStatus.gifted => PhysicalAssetStatus.gifted,
  };
}

extension PhysicalAssetStatusX on PhysicalAssetStatus {
  String get storageKey => switch (this) {
        PhysicalAssetStatus.active => 'active',
        PhysicalAssetStatus.idle => 'idle',
        PhysicalAssetStatus.sold => 'sold',
        PhysicalAssetStatus.disposed => 'disposed',
        PhysicalAssetStatus.lost => 'lost',
        PhysicalAssetStatus.gifted => 'gifted',
        PhysicalAssetStatus.archived => 'archived',
      };

  String get label => switch (this) {
        PhysicalAssetStatus.active => '使用中',
        PhysicalAssetStatus.idle => '闲置',
        PhysicalAssetStatus.sold => '已出售',
        PhysicalAssetStatus.disposed => '已报废',
        PhysicalAssetStatus.lost => '已丢失',
        PhysicalAssetStatus.gifted => '已赠送',
        PhysicalAssetStatus.archived => '已归档',
      };

  bool get canCountInNetWorth =>
      this == PhysicalAssetStatus.active || this == PhysicalAssetStatus.idle;

  static PhysicalAssetStatus fromStorage(String? value) {
    for (final status in PhysicalAssetStatus.values) {
      if (status.storageKey == value) return status;
    }
    return PhysicalAssetStatus.active;
  }
}

enum AssetValueSource {
  opening,
  purchase,
  manual,
  sale,
  statusZero,
  autoDepreciation,
}

extension AssetValueSourceX on AssetValueSource {
  String get storageKey => switch (this) {
        AssetValueSource.opening => 'opening',
        AssetValueSource.purchase => 'purchase',
        AssetValueSource.manual => 'manual',
        AssetValueSource.sale => 'sale',
        AssetValueSource.statusZero => 'status_zero',
        AssetValueSource.autoDepreciation => 'auto_depreciation',
      };

  static AssetValueSource fromStorage(String? value) {
    for (final source in AssetValueSource.values) {
      if (source.storageKey == value) return source;
    }
    return AssetValueSource.manual;
  }
}

enum AssetType {
  digital,
  appliance,
  vehicle,
  property,
  valuables,
  collectibles,
  tools,
  other,
}

extension AssetTypeX on AssetType {
  String get storageKey => switch (this) {
        AssetType.digital => 'digital',
        AssetType.appliance => 'appliance',
        AssetType.vehicle => 'vehicle',
        AssetType.property => 'property',
        AssetType.valuables => 'valuables',
        AssetType.collectibles => 'collectibles',
        AssetType.tools => 'tools',
        AssetType.other => 'other',
      };

  String get label => switch (this) {
        AssetType.digital => '数码设备',
        AssetType.appliance => '家电家具',
        AssetType.vehicle => '车辆交通',
        AssetType.property => '房产',
        AssetType.valuables => '贵重物品',
        AssetType.collectibles => '收藏品',
        AssetType.tools => '工具设备',
        AssetType.other => '其他',
      };

  static AssetType fromStorage(String? value) {
    for (final type in AssetType.values) {
      if (type.storageKey == value) return type;
    }
    return AssetType.other;
  }
}

enum AssetObjectType {
  physical,
  receivable,
  investment,
  liability,
}

extension AssetObjectTypeX on AssetObjectType {
  String get storageKey => switch (this) {
        AssetObjectType.physical => 'physical',
        AssetObjectType.receivable => 'receivable',
        AssetObjectType.investment => 'investment',
        AssetObjectType.liability => 'liability',
      };

  String get label => switch (this) {
        AssetObjectType.physical => '实物资产',
        AssetObjectType.receivable => '权益资产',
        AssetObjectType.investment => '投资资产',
        AssetObjectType.liability => '负债',
      };

  static AssetObjectType fromStorage(String? value) {
    for (final type in AssetObjectType.values) {
      if (type.storageKey == value) return type;
    }
    return AssetObjectType.physical;
  }
}

enum ReceivableAssetType {
  rentalDeposit,
  loanOut,
  accountReceivable,
  prepaidCard,
  membershipCard,
  securityDeposit,
  other,
}

extension ReceivableAssetTypeX on ReceivableAssetType {
  String get storageKey => switch (this) {
        ReceivableAssetType.rentalDeposit => 'rental_deposit',
        ReceivableAssetType.loanOut => 'loan_out',
        ReceivableAssetType.accountReceivable => 'account_receivable',
        ReceivableAssetType.prepaidCard => 'prepaid_card',
        ReceivableAssetType.membershipCard => 'membership_card',
        ReceivableAssetType.securityDeposit => 'security_deposit',
        ReceivableAssetType.other => 'other',
      };

  String get label => switch (this) {
        ReceivableAssetType.rentalDeposit => '租房押金',
        ReceivableAssetType.loanOut => '借出款',
        ReceivableAssetType.accountReceivable => '应收款',
        ReceivableAssetType.prepaidCard => '预付卡余额',
        ReceivableAssetType.membershipCard => '会员卡余额',
        ReceivableAssetType.securityDeposit => '保证金',
        ReceivableAssetType.other => '其他权益',
      };

  static ReceivableAssetType fromStorage(String? value) {
    for (final type in ReceivableAssetType.values) {
      if (type.storageKey == value) return type;
    }
    return ReceivableAssetType.other;
  }
}

enum ReceivableAssetStatus {
  active,
  partialRecovered,
  recovered,
  lost,
  archived,
}

enum ReceivableEconomicStatus {
  active,
  partialRecovered,
  recovered,
  lost,
  unknown,
}

extension ReceivableEconomicStatusX on ReceivableEconomicStatus {
  String get storageKey => switch (this) {
        ReceivableEconomicStatus.active => 'active',
        ReceivableEconomicStatus.partialRecovered => 'partial_recovered',
        ReceivableEconomicStatus.recovered => 'recovered',
        ReceivableEconomicStatus.lost => 'lost',
        ReceivableEconomicStatus.unknown => 'unknown',
      };

  String get label => switch (this) {
        ReceivableEconomicStatus.active => '未收回',
        ReceivableEconomicStatus.partialRecovered => '部分收回',
        ReceivableEconomicStatus.recovered => '已收回',
        ReceivableEconomicStatus.lost => '已损失',
        ReceivableEconomicStatus.unknown => '状态待确认',
      };

  bool get canCountInNetWorth =>
      this == ReceivableEconomicStatus.active ||
      this == ReceivableEconomicStatus.partialRecovered;

  static ReceivableEconomicStatus fromStorage(String? value) {
    for (final status in ReceivableEconomicStatus.values) {
      if (status.storageKey == value) return status;
    }
    return ReceivableEconomicStatus.unknown;
  }
}

ReceivableEconomicStatus _receivableEconomicFromLegacyStatus(
  ReceivableAssetStatus status,
) =>
    switch (status) {
      ReceivableAssetStatus.active => ReceivableEconomicStatus.active,
      ReceivableAssetStatus.partialRecovered =>
        ReceivableEconomicStatus.partialRecovered,
      ReceivableAssetStatus.recovered => ReceivableEconomicStatus.recovered,
      ReceivableAssetStatus.lost => ReceivableEconomicStatus.lost,
      ReceivableAssetStatus.archived => ReceivableEconomicStatus.unknown,
    };

ReceivableAssetStatus _legacyReceivableStatusFor({
  required ReceivableEconomicStatus economicStatus,
  required AssetVisibilityStatus visibilityStatus,
}) {
  if (visibilityStatus == AssetVisibilityStatus.archived) {
    return ReceivableAssetStatus.archived;
  }
  return switch (economicStatus) {
    ReceivableEconomicStatus.active => ReceivableAssetStatus.active,
    ReceivableEconomicStatus.partialRecovered =>
      ReceivableAssetStatus.partialRecovered,
    ReceivableEconomicStatus.recovered => ReceivableAssetStatus.recovered,
    ReceivableEconomicStatus.lost => ReceivableAssetStatus.lost,
    ReceivableEconomicStatus.unknown => ReceivableAssetStatus.active,
  };
}

extension ReceivableAssetStatusX on ReceivableAssetStatus {
  String get storageKey => switch (this) {
        ReceivableAssetStatus.active => 'active',
        ReceivableAssetStatus.partialRecovered => 'partial_recovered',
        ReceivableAssetStatus.recovered => 'recovered',
        ReceivableAssetStatus.lost => 'lost',
        ReceivableAssetStatus.archived => 'archived',
      };

  String get label => switch (this) {
        ReceivableAssetStatus.active => '未收回',
        ReceivableAssetStatus.partialRecovered => '部分收回',
        ReceivableAssetStatus.recovered => '已收回',
        ReceivableAssetStatus.lost => '已损失',
        ReceivableAssetStatus.archived => '已归档',
      };

  bool get canCountInNetWorth =>
      this == ReceivableAssetStatus.active ||
      this == ReceivableAssetStatus.partialRecovered;

  static ReceivableAssetStatus fromStorage(String? value) {
    for (final status in ReceivableAssetStatus.values) {
      if (status.storageKey == value) return status;
    }
    return ReceivableAssetStatus.active;
  }
}

enum LiabilityProfileType {
  creditCard,
  mortgage,
  carLoan,
  consumerLoan,

  /// A2 借贷按人：向个人借入的钱（counterparty = 借入对象姓名）。
  personalBorrow,
  other,
}

extension LiabilityProfileTypeX on LiabilityProfileType {
  String get storageKey => switch (this) {
        LiabilityProfileType.creditCard => 'credit_card',
        LiabilityProfileType.mortgage => 'mortgage',
        LiabilityProfileType.carLoan => 'car_loan',
        LiabilityProfileType.consumerLoan => 'consumer_loan',
        LiabilityProfileType.personalBorrow => 'personal_borrow',
        LiabilityProfileType.other => 'other',
      };

  String get label => switch (this) {
        LiabilityProfileType.creditCard => '信用卡',
        LiabilityProfileType.mortgage => '房贷',
        LiabilityProfileType.carLoan => '车贷',
        LiabilityProfileType.consumerLoan => '消费贷',
        LiabilityProfileType.personalBorrow => '个人借入',
        LiabilityProfileType.other => '其他负债',
      };

  static LiabilityProfileType fromStorage(String? value) {
    for (final type in LiabilityProfileType.values) {
      if (type.storageKey == value) return type;
    }
    return LiabilityProfileType.other;
  }
}

enum LiabilityProfileStatus {
  active,
  paidOff,
  paused,
  archived,
}

extension LiabilityProfileStatusX on LiabilityProfileStatus {
  String get storageKey => switch (this) {
        LiabilityProfileStatus.active => 'active',
        LiabilityProfileStatus.paidOff => 'paid_off',
        LiabilityProfileStatus.paused => 'paused',
        LiabilityProfileStatus.archived => 'archived',
      };

  String get label => switch (this) {
        LiabilityProfileStatus.active => '还款中',
        LiabilityProfileStatus.paidOff => '已结清',
        LiabilityProfileStatus.paused => '暂停',
        LiabilityProfileStatus.archived => '已归档',
      };

  bool get countsAsLiability => this == LiabilityProfileStatus.active;

  static LiabilityProfileStatus fromStorage(String? value) {
    for (final status in LiabilityProfileStatus.values) {
      if (status.storageKey == value) return status;
    }
    return LiabilityProfileStatus.active;
  }
}

enum AssetEventType {
  openingAssetImport,
  createdFromTransaction,
  assetPurchased,
  assetCreated,
  assetEdited,
  valueUpdated,
  assetSold,
  assetSaleUndone,
  assetReturned,
  assetReturnUndone,
  assetTransactionUnlinked,
  assetDisposed,
  assetLost,
  assetGifted,
  assetTerminalUndone,
  assetCostLinked,
  assetCostUnlinked,
  assetUsageTrackingEnabled,
  assetUsageTrackingDisabled,
  assetSavingsGoalLinked,
  assetSavingsGoalUnlinked,
  assetArchived,
  assetUnarchived,
  depreciationConfigured,
  autoDepreciationApplied,
  evidenceUpdated,
  receivableCreated,
  receivableEdited,
  receivableRecovered,
  receivableRecoveryUndone,
  receivableLost,
  receivableArchived,
  receivableUnarchived,
}

extension AssetEventTypeX on AssetEventType {
  String get storageKey => switch (this) {
        AssetEventType.openingAssetImport => 'opening_asset_import',
        AssetEventType.createdFromTransaction => 'created_from_transaction',
        AssetEventType.assetPurchased => 'asset_purchased',
        AssetEventType.assetCreated => 'asset_created',
        AssetEventType.assetEdited => 'asset_edited',
        AssetEventType.valueUpdated => 'value_updated',
        AssetEventType.assetSold => 'asset_sold',
        AssetEventType.assetSaleUndone => 'asset_sale_undone',
        AssetEventType.assetReturned => 'asset_returned',
        AssetEventType.assetReturnUndone => 'asset_return_undone',
        AssetEventType.assetTransactionUnlinked => 'asset_transaction_unlinked',
        AssetEventType.assetDisposed => 'asset_disposed',
        AssetEventType.assetLost => 'asset_lost',
        AssetEventType.assetGifted => 'asset_gifted',
        AssetEventType.assetTerminalUndone => 'asset_terminal_undone',
        AssetEventType.assetCostLinked => 'asset_cost_linked',
        AssetEventType.assetCostUnlinked => 'asset_cost_unlinked',
        AssetEventType.assetUsageTrackingEnabled =>
          'asset_usage_tracking_enabled',
        AssetEventType.assetUsageTrackingDisabled =>
          'asset_usage_tracking_disabled',
        AssetEventType.assetSavingsGoalLinked => 'asset_savings_goal_linked',
        AssetEventType.assetSavingsGoalUnlinked =>
          'asset_savings_goal_unlinked',
        AssetEventType.assetArchived => 'asset_archived',
        AssetEventType.assetUnarchived => 'asset_unarchived',
        AssetEventType.depreciationConfigured => 'depreciation_configured',
        AssetEventType.autoDepreciationApplied => 'auto_depreciation_applied',
        AssetEventType.evidenceUpdated => 'evidence_updated',
        AssetEventType.receivableCreated => 'receivable_created',
        AssetEventType.receivableEdited => 'receivable_edited',
        AssetEventType.receivableRecovered => 'receivable_recovered',
        AssetEventType.receivableRecoveryUndone => 'receivable_recovery_undone',
        AssetEventType.receivableLost => 'receivable_lost',
        AssetEventType.receivableArchived => 'receivable_archived',
        AssetEventType.receivableUnarchived => 'receivable_unarchived',
      };

  String get label => switch (this) {
        AssetEventType.openingAssetImport => '历史补录',
        AssetEventType.createdFromTransaction => '从账单加入',
        AssetEventType.assetPurchased => '新购买',
        AssetEventType.assetCreated => '新增资产',
        AssetEventType.assetEdited => '编辑资料',
        AssetEventType.valueUpdated => '更新当前价值',
        AssetEventType.assetSold => '出售资产',
        AssetEventType.assetSaleUndone => '撤销出售',
        AssetEventType.assetReturned => '退货',
        AssetEventType.assetReturnUndone => '撤销退货',
        AssetEventType.assetTransactionUnlinked => '解除账单关联',
        AssetEventType.assetDisposed => '报废资产',
        AssetEventType.assetLost => '标记丢失',
        AssetEventType.assetGifted => '赠送资产',
        AssetEventType.assetTerminalUndone => '撤销结束持有',
        AssetEventType.assetCostLinked => '关联持有支出',
        AssetEventType.assetCostUnlinked => '解除持有支出',
        AssetEventType.assetUsageTrackingEnabled => '开启使用次数',
        AssetEventType.assetUsageTrackingDisabled => '关闭使用次数',
        AssetEventType.assetSavingsGoalLinked => '关联存钱目标',
        AssetEventType.assetSavingsGoalUnlinked => '解除存钱目标',
        AssetEventType.assetArchived => '归档资产',
        AssetEventType.assetUnarchived => '恢复归档',
        AssetEventType.depreciationConfigured => '折旧设置',
        AssetEventType.autoDepreciationApplied => '自动折旧',
        AssetEventType.evidenceUpdated => '凭证更新',
        AssetEventType.receivableCreated => '新增权益',
        AssetEventType.receivableEdited => '编辑权益',
        AssetEventType.receivableRecovered => '收回权益',
        AssetEventType.receivableRecoveryUndone => '撤销收回',
        AssetEventType.receivableLost => '权益损失',
        AssetEventType.receivableArchived => '归档权益',
        AssetEventType.receivableUnarchived => '恢复权益',
      };

  static AssetEventType fromStorage(String? value) {
    for (final type in AssetEventType.values) {
      if (type.storageKey == value) return type;
    }
    return AssetEventType.assetCreated;
  }
}

enum AssetTransactionLinkType {
  sourceTransaction,
  purchaseTransaction,
  saleAccountMovement,
  maintenance,
  accessory,
  insurance,
  otherCost,
}

extension AssetTransactionLinkTypeX on AssetTransactionLinkType {
  String get storageKey => switch (this) {
        AssetTransactionLinkType.sourceTransaction => 'source_transaction',
        AssetTransactionLinkType.purchaseTransaction => 'purchase_transaction',
        AssetTransactionLinkType.saleAccountMovement => 'sale_account_movement',
        AssetTransactionLinkType.maintenance => 'maintenance',
        AssetTransactionLinkType.accessory => 'accessory',
        AssetTransactionLinkType.insurance => 'insurance',
        AssetTransactionLinkType.otherCost => 'other_cost',
      };

  String get label => switch (this) {
        AssetTransactionLinkType.sourceTransaction => '购买账单',
        AssetTransactionLinkType.purchaseTransaction => '购置支出',
        AssetTransactionLinkType.saleAccountMovement => '出售到账',
        AssetTransactionLinkType.maintenance => '维修保养',
        AssetTransactionLinkType.accessory => '配件',
        AssetTransactionLinkType.insurance => '保险',
        AssetTransactionLinkType.otherCost => '其他支出',
      };

  bool get isAdditionalCost =>
      this == AssetTransactionLinkType.maintenance ||
      this == AssetTransactionLinkType.accessory ||
      this == AssetTransactionLinkType.insurance ||
      this == AssetTransactionLinkType.otherCost;

  static AssetTransactionLinkType fromStorage(String? value) {
    for (final type in AssetTransactionLinkType.values) {
      if (type.storageKey == value) return type;
    }
    return AssetTransactionLinkType.sourceTransaction;
  }
}

class PhysicalAssetEntity {
  final int id;
  final String uuid;
  final int? bookId;
  final String name;
  final AssetType assetType;

  /// v32 及资产 JSON v3 的兼容影子；v33 业务逻辑不得再读取它。
  final PhysicalAssetStatus status;
  final PhysicalAssetEconomicStatus economicStatus;
  final PhysicalAssetUsageStatus usageStatus;
  final AssetVisibilityStatus visibilityStatus;
  final AssetInclusionQuality inclusionQuality;
  final PhysicalAssetSourceType sourceType;
  final AssetAcquisitionCostSource acquisitionCostSource;
  final Decimal purchasePrice;
  final Decimal currentValue;
  final String currencyCode;
  final int? purchaseDateMs;
  final String brand;
  final String model;
  final String location;
  final int? warrantyUntilMs;
  final bool usageTrackingEnabled;
  final int? savingsGoalId;
  final String photoPath;
  final String thumbnailPath;
  final String invoicePath;
  final String depreciationMethod;
  final Decimal depreciationBase;
  final Decimal salvageValue;
  final int usefulLifeMonths;
  final int? depreciationStartMs;
  final bool depreciationPaused;
  final String note;
  final bool includeInNetWorth;
  final bool isDeleted;
  final int? endedMs;
  final int? archivedMs;
  final int createdMs;
  final int updatedMs;

  const PhysicalAssetEntity({
    required this.id,
    this.uuid = '',
    this.bookId,
    required this.name,
    this.assetType = AssetType.other,
    this.status = PhysicalAssetStatus.active,
    this.economicStatus = PhysicalAssetEconomicStatus.owned,
    this.usageStatus = PhysicalAssetUsageStatus.active,
    this.visibilityStatus = AssetVisibilityStatus.active,
    this.inclusionQuality = AssetInclusionQuality.confirmed,
    this.sourceType = PhysicalAssetSourceType.historicalExisting,
    this.acquisitionCostSource = AssetAcquisitionCostSource.manual,
    required this.purchasePrice,
    required this.currentValue,
    this.currencyCode = 'CNY',
    this.purchaseDateMs,
    this.brand = '',
    this.model = '',
    this.location = '',
    this.warrantyUntilMs,
    this.usageTrackingEnabled = false,
    this.savingsGoalId,
    this.photoPath = '',
    this.thumbnailPath = '',
    this.invoicePath = '',
    this.depreciationMethod = '',
    required this.depreciationBase,
    required this.salvageValue,
    this.usefulLifeMonths = 0,
    this.depreciationStartMs,
    this.depreciationPaused = false,
    this.note = '',
    this.includeInNetWorth = true,
    this.isDeleted = false,
    this.endedMs,
    this.archivedMs,
    this.createdMs = 0,
    this.updatedMs = 0,
  });

  DateTime? get purchaseDate => purchaseDateMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(purchaseDateMs!);
  DateTime? get warrantyUntil => warrantyUntilMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(warrantyUntilMs!);
  DateTime? get depreciationStartDate => depreciationStartMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(depreciationStartMs!);
  DateTime get updatedAt => DateTime.fromMillisecondsSinceEpoch(updatedMs);
  DateTime? get endedAt =>
      endedMs == null ? null : DateTime.fromMillisecondsSinceEpoch(endedMs!);
  DateTime? get archivedAt => archivedMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(archivedMs!);
  bool get isArchived => visibilityStatus == AssetVisibilityStatus.archived;
  bool get isOwned => economicStatus == PhysicalAssetEconomicStatus.owned;
  bool get hasLinearDepreciation =>
      depreciationMethod == 'linear' &&
      usefulLifeMonths > 0 &&
      depreciationBase > Decimal.zero;
  bool get countsInNetWorth =>
      !isDeleted && includeInNetWorth && economicStatus.ownsValue;

  factory PhysicalAssetEntity.fromMap(Map<String, Object?> m) {
    final legacyStatus =
        PhysicalAssetStatusX.fromStorage(m['status'] as String?);
    return PhysicalAssetEntity(
      id: m['id'] as int,
      uuid: m['uuid'] as String? ?? '',
      bookId: m['book_id'] as int?,
      name: m['name'] as String? ?? '',
      assetType: AssetTypeX.fromStorage(m['asset_type'] as String?),
      status: legacyStatus,
      economicStatus: m.containsKey('economic_status')
          ? PhysicalAssetEconomicStatusX.fromStorage(
              m['economic_status'] as String?,
            )
          : _physicalEconomicFromLegacyStatus(legacyStatus),
      usageStatus: m.containsKey('usage_status')
          ? PhysicalAssetUsageStatusX.fromStorage(
              m['usage_status'] as String?,
            )
          : _physicalUsageFromLegacyStatus(legacyStatus),
      visibilityStatus: m.containsKey('visibility_status')
          ? AssetVisibilityStatusX.fromStorage(
              m['visibility_status'] as String?,
            )
          : legacyStatus == PhysicalAssetStatus.archived
              ? AssetVisibilityStatus.archived
              : AssetVisibilityStatus.active,
      inclusionQuality: m.containsKey('inclusion_quality')
          ? AssetInclusionQualityX.fromStorage(
              m['inclusion_quality'] as String?,
            )
          : legacyStatus == PhysicalAssetStatus.archived
              ? AssetInclusionQuality.needsReview
              : AssetInclusionQuality.confirmed,
      sourceType:
          PhysicalAssetSourceTypeX.fromStorage(m['source_type'] as String?),
      acquisitionCostSource: AssetAcquisitionCostSourceX.fromStorage(
        m['acquisition_cost_source'] as String?,
      ),
      purchasePrice: Decimal.tryParse(m['purchase_price'] as String? ?? '') ??
          Decimal.zero,
      currentValue:
          Decimal.tryParse(m['current_value'] as String? ?? '') ?? Decimal.zero,
      currencyCode: m['currency_code'] as String? ?? 'CNY',
      purchaseDateMs: m['purchase_date_ms'] as int?,
      brand: m['brand'] as String? ?? '',
      model: m['model'] as String? ?? '',
      location: m['location'] as String? ?? '',
      warrantyUntilMs: m['warranty_until_ms'] as int?,
      usageTrackingEnabled: ((m['usage_tracking_enabled'] as int?) ?? 0) == 1,
      savingsGoalId: m['savings_goal_id'] as int?,
      photoPath: m['photo_path'] as String? ?? '',
      thumbnailPath: m['thumbnail_path'] as String? ?? '',
      invoicePath: m['invoice_path'] as String? ?? '',
      depreciationMethod: m['depreciation_method'] as String? ?? '',
      depreciationBase:
          Decimal.tryParse(m['depreciation_base'] as String? ?? '') ??
              Decimal.zero,
      salvageValue:
          Decimal.tryParse(m['salvage_value'] as String? ?? '') ?? Decimal.zero,
      usefulLifeMonths: m['useful_life_months'] as int? ?? 0,
      depreciationStartMs: m['depreciation_start_ms'] as int?,
      depreciationPaused: ((m['depreciation_paused'] as int?) ?? 0) == 1,
      note: m['note'] as String? ?? '',
      includeInNetWorth: ((m['include_in_net_worth'] as int?) ?? 1) == 1,
      isDeleted: ((m['is_deleted'] as int?) ?? 0) == 1,
      endedMs: m['ended_ms'] as int?,
      archivedMs: m['archived_ms'] as int?,
      createdMs: m['created_ms'] as int? ?? 0,
      updatedMs: m['updated_ms'] as int? ?? 0,
    );
  }
}

class AssetEventEntity {
  final int id;
  final String uuid;
  final int assetId;
  final AssetObjectType assetType;
  final AssetEventType eventType;
  final int occurredMs;
  final Decimal? value;
  final String note;
  final String metadata;
  final int createdMs;

  const AssetEventEntity({
    required this.id,
    this.uuid = '',
    required this.assetId,
    this.assetType = AssetObjectType.physical,
    required this.eventType,
    required this.occurredMs,
    this.value,
    this.note = '',
    this.metadata = '',
    this.createdMs = 0,
  });

  DateTime get occurredAt => DateTime.fromMillisecondsSinceEpoch(occurredMs);

  factory AssetEventEntity.fromMap(Map<String, Object?> m) => AssetEventEntity(
        id: m['id'] as int,
        uuid: m['uuid'] as String? ?? '',
        assetId: m['asset_id'] as int,
        assetType: AssetObjectTypeX.fromStorage(m['asset_type'] as String?),
        eventType: AssetEventTypeX.fromStorage(m['event_type'] as String?),
        occurredMs: m['occurred_ms'] as int? ?? 0,
        value: Decimal.tryParse(m['value'] as String? ?? ''),
        note: m['note'] as String? ?? '',
        metadata: m['metadata'] as String? ?? '',
        createdMs: m['created_ms'] as int? ?? 0,
      );
}

class AssetValuationEntity {
  final int id;
  final String uuid;
  final int assetId;
  final Decimal value;
  final AssetValueSource source;
  final int valuedAtMs;
  final String note;
  final int createdMs;

  const AssetValuationEntity({
    required this.id,
    this.uuid = '',
    required this.assetId,
    required this.value,
    this.source = AssetValueSource.manual,
    required this.valuedAtMs,
    this.note = '',
    this.createdMs = 0,
  });

  DateTime get valuedAt => DateTime.fromMillisecondsSinceEpoch(valuedAtMs);

  factory AssetValuationEntity.fromMap(Map<String, Object?> m) =>
      AssetValuationEntity(
        id: m['id'] as int,
        uuid: m['uuid'] as String? ?? '',
        assetId: m['asset_id'] as int,
        value: Decimal.tryParse(m['value'] as String? ?? '') ?? Decimal.zero,
        source: AssetValueSourceX.fromStorage(m['source'] as String?),
        valuedAtMs: m['valued_at_ms'] as int? ?? 0,
        note: m['note'] as String? ?? '',
        createdMs: m['created_ms'] as int? ?? 0,
      );
}

class AssetTransactionLinkEntity {
  final int id;
  final String uuid;
  final int assetId;
  final AssetObjectType assetObjectType;
  final int transactionId;
  final AssetTransactionLinkType linkType;
  final Decimal amount;
  final int allocatedGrossCents;
  final int allocatedRefundCents;
  final AssetAllocationCostQuality costQuality;
  final String note;
  final int createdMs;
  final int updatedMs;

  const AssetTransactionLinkEntity({
    required this.id,
    this.uuid = '',
    required this.assetId,
    this.assetObjectType = AssetObjectType.physical,
    required this.transactionId,
    required this.linkType,
    required this.amount,
    this.allocatedGrossCents = 0,
    this.allocatedRefundCents = 0,
    this.costQuality = AssetAllocationCostQuality.partial,
    this.note = '',
    this.createdMs = 0,
    this.updatedMs = 0,
  });

  int get allocatedNetCents => allocatedGrossCents - allocatedRefundCents;

  factory AssetTransactionLinkEntity.fromMap(Map<String, Object?> m) =>
      AssetTransactionLinkEntity(
        id: m['id'] as int,
        uuid: m['uuid'] as String? ?? '',
        assetId: m['asset_id'] as int,
        assetObjectType:
            AssetObjectTypeX.fromStorage(m['asset_object_type'] as String?),
        transactionId: m['transaction_id'] as int,
        linkType:
            AssetTransactionLinkTypeX.fromStorage(m['link_type'] as String?),
        amount: Decimal.tryParse(m['amount'] as String? ?? '') ?? Decimal.zero,
        allocatedGrossCents: m['allocated_gross_cents'] as int? ?? 0,
        allocatedRefundCents: m['allocated_refund_cents'] as int? ?? 0,
        costQuality: AssetAllocationCostQualityX.fromStorage(
          m['cost_quality'] as String?,
        ),
        note: m['note'] as String? ?? '',
        createdMs: m['created_ms'] as int? ?? 0,
        updatedMs: m['updated_ms'] as int? ?? 0,
      );
}

class AssetUsageEventEntity {
  final int id;
  final String uuid;
  final int assetId;
  final int countDelta;
  final int? reversalOf;
  final int occurredMs;
  final String note;
  final int createdMs;
  final int updatedMs;

  const AssetUsageEventEntity({
    required this.id,
    required this.uuid,
    required this.assetId,
    required this.countDelta,
    this.reversalOf,
    required this.occurredMs,
    this.note = '',
    required this.createdMs,
    required this.updatedMs,
  });

  factory AssetUsageEventEntity.fromMap(Map<String, Object?> map) =>
      AssetUsageEventEntity(
        id: map['id'] as int,
        uuid: map['uuid'] as String? ?? '',
        assetId: map['asset_id'] as int,
        countDelta: map['count_delta'] as int? ?? 0,
        reversalOf: map['reversal_of'] as int?,
        occurredMs: map['occurred_ms'] as int? ?? 0,
        note: map['note'] as String? ?? '',
        createdMs: map['created_ms'] as int? ?? 0,
        updatedMs: map['updated_ms'] as int? ?? 0,
      );

  AssetUsageEventPoint toPoint(Map<int, String> uuidById) =>
      AssetUsageEventPoint(
        id: uuid.isEmpty ? id.toString() : uuid,
        countDelta: countDelta,
        occurredMs: occurredMs,
        sequence: id,
        reversalOf: reversalOf == null
            ? null
            : (uuidById[reversalOf!] ?? reversalOf.toString()),
      );
}

class AssetPurchaseAllocationCandidate {
  final TransactionEntity transaction;
  final int orderGrossCents;
  final int validRefundCents;
  final int allocatedGrossCents;
  final int allocatedRefundCents;

  const AssetPurchaseAllocationCandidate({
    required this.transaction,
    required this.orderGrossCents,
    required this.validRefundCents,
    required this.allocatedGrossCents,
    required this.allocatedRefundCents,
  });

  int get remainingGrossCents => orderGrossCents - allocatedGrossCents;
  int get remainingRefundCents => validRefundCents - allocatedRefundCents;
  int get orderNetCents => orderGrossCents - validRefundCents;
}

class PhysicalAssetRefundAllocationTarget {
  final int assetId;
  final String name;
  final int grossCents;
  final int currentAllocatedRefundCents;
  final int totalAllocatedRefundCents;

  const PhysicalAssetRefundAllocationTarget({
    required this.assetId,
    required this.name,
    required this.grossCents,
    required this.currentAllocatedRefundCents,
    required this.totalAllocatedRefundCents,
  });
}

class PendingPhysicalAssetRefundAllocation {
  final int refundTransactionId;
  final int originalTransactionId;
  final int refundDateMs;
  final String orderLabel;
  final int refundCents;
  final List<PhysicalAssetRefundAllocationTarget> targets;

  /// 本次退款还能归到「订单未跟踪部分」的上限（订单毛额减去已入库物品
  /// 毛额、再扣掉别的退款已占用的未跟踪额度；含本退款当前已归的部分）。
  /// 0 = 订单全额都在已跟踪物品上，弹层不显示该选项。
  final int untrackedLimitCents;

  /// 本退款当前已归到未跟踪部分的金额（重新分配时回显用）。
  final int currentUntrackedCents;

  const PendingPhysicalAssetRefundAllocation({
    required this.refundTransactionId,
    required this.originalTransactionId,
    required this.refundDateMs,
    required this.orderLabel,
    required this.refundCents,
    required this.targets,
    this.untrackedLimitCents = 0,
    this.currentUntrackedCents = 0,
  });

  int get allocatedCents => targets.fold<int>(
        0,
        (sum, target) => sum + target.currentAllocatedRefundCents,
      );

  int get remainingCents => refundCents - allocatedCents;
}

enum PhysicalAssetAcquisitionCostQuality { exact, partial, conflict }

class PhysicalAssetAcquisitionCostResult {
  final PhysicalAssetAcquisitionCostQuality quality;
  final Decimal? amount;
  final String reason;

  const PhysicalAssetAcquisitionCostResult({
    required this.quality,
    required this.amount,
    required this.reason,
  });

  bool get isExact => quality == PhysicalAssetAcquisitionCostQuality.exact;
}

class PhysicalAssetAdditionalCostResult {
  final Decimal amount;
  final bool isExact;
  final String reason;

  const PhysicalAssetAdditionalCostResult({
    required this.amount,
    required this.isExact,
    this.reason = '',
  });
}

class ReceivableAssetEntity {
  final int id;
  final String uuid;
  final int? bookId;
  final String name;
  final ReceivableAssetType type;

  /// v32 及资产 JSON v3 的兼容影子；v33 业务逻辑不得再读取它。
  final ReceivableAssetStatus status;
  final ReceivableEconomicStatus economicStatus;
  final AssetVisibilityStatus visibilityStatus;
  final AssetInclusionQuality inclusionQuality;
  final Decimal originalAmount;
  final Decimal remainingAmount;
  final String currencyCode;
  final String counterparty;
  final int? dueDateMs;
  final bool includeInNetWorth;
  final String note;
  final bool isDeleted;
  final int? endedMs;
  final int? archivedMs;
  final int createdMs;
  final int updatedMs;

  const ReceivableAssetEntity({
    required this.id,
    this.uuid = '',
    this.bookId,
    required this.name,
    this.type = ReceivableAssetType.other,
    this.status = ReceivableAssetStatus.active,
    this.economicStatus = ReceivableEconomicStatus.active,
    this.visibilityStatus = AssetVisibilityStatus.active,
    this.inclusionQuality = AssetInclusionQuality.confirmed,
    required this.originalAmount,
    required this.remainingAmount,
    this.currencyCode = 'CNY',
    this.counterparty = '',
    this.dueDateMs,
    this.includeInNetWorth = true,
    this.note = '',
    this.isDeleted = false,
    this.endedMs,
    this.archivedMs,
    this.createdMs = 0,
    this.updatedMs = 0,
  });

  DateTime? get dueDate => dueDateMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(dueDateMs!);

  DateTime? get endedAt =>
      endedMs == null ? null : DateTime.fromMillisecondsSinceEpoch(endedMs!);
  DateTime? get archivedAt => archivedMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(archivedMs!);
  bool get isArchived => visibilityStatus == AssetVisibilityStatus.archived;
  bool get countsInNetWorth =>
      !isDeleted &&
      includeInNetWorth &&
      economicStatus.canCountInNetWorth &&
      remainingAmount > Decimal.zero;

  factory ReceivableAssetEntity.fromMap(Map<String, Object?> m) {
    final legacyStatus =
        ReceivableAssetStatusX.fromStorage(m['status'] as String?);
    return ReceivableAssetEntity(
      id: m['id'] as int,
      uuid: m['uuid'] as String? ?? '',
      bookId: m['book_id'] as int?,
      name: m['name'] as String? ?? '',
      type: ReceivableAssetTypeX.fromStorage(m['receivable_type'] as String?),
      status: legacyStatus,
      economicStatus: m.containsKey('economic_status')
          ? ReceivableEconomicStatusX.fromStorage(
              m['economic_status'] as String?,
            )
          : _receivableEconomicFromLegacyStatus(legacyStatus),
      visibilityStatus: m.containsKey('visibility_status')
          ? AssetVisibilityStatusX.fromStorage(
              m['visibility_status'] as String?,
            )
          : legacyStatus == ReceivableAssetStatus.archived
              ? AssetVisibilityStatus.archived
              : AssetVisibilityStatus.active,
      inclusionQuality: m.containsKey('inclusion_quality')
          ? AssetInclusionQualityX.fromStorage(
              m['inclusion_quality'] as String?,
            )
          : legacyStatus == ReceivableAssetStatus.archived
              ? AssetInclusionQuality.needsReview
              : AssetInclusionQuality.confirmed,
      originalAmount: Decimal.tryParse(m['original_amount'] as String? ?? '') ??
          Decimal.zero,
      remainingAmount:
          Decimal.tryParse(m['remaining_amount'] as String? ?? '') ??
              Decimal.zero,
      currencyCode: m['currency_code'] as String? ?? 'CNY',
      counterparty: m['counterparty'] as String? ?? '',
      dueDateMs: m['due_date_ms'] as int?,
      includeInNetWorth: ((m['include_in_net_worth'] as int?) ?? 1) == 1,
      note: m['note'] as String? ?? '',
      isDeleted: ((m['is_deleted'] as int?) ?? 0) == 1,
      endedMs: m['ended_ms'] as int?,
      archivedMs: m['archived_ms'] as int?,
      createdMs: m['created_ms'] as int? ?? 0,
      updatedMs: m['updated_ms'] as int? ?? 0,
    );
  }
}

class ReceivableRecoveryEntity {
  final int id;
  final String uuid;
  final int receivableAssetId;
  final Decimal amount;
  final int recoveredMs;
  final int? targetAccountId;
  final int? eventId;
  final int? transactionId;
  final String note;
  final int createdMs;

  const ReceivableRecoveryEntity({
    required this.id,
    this.uuid = '',
    required this.receivableAssetId,
    required this.amount,
    required this.recoveredMs,
    this.targetAccountId,
    this.eventId,
    this.transactionId,
    this.note = '',
    this.createdMs = 0,
  });

  DateTime get recoveredAt => DateTime.fromMillisecondsSinceEpoch(recoveredMs);

  factory ReceivableRecoveryEntity.fromMap(Map<String, Object?> m) =>
      ReceivableRecoveryEntity(
        id: m['id'] as int,
        uuid: m['uuid'] as String? ?? '',
        receivableAssetId: m['receivable_asset_id'] as int,
        amount: Decimal.tryParse(m['amount'] as String? ?? '') ?? Decimal.zero,
        recoveredMs: m['recovered_ms'] as int? ?? 0,
        targetAccountId: m['target_account_id'] as int?,
        eventId: m['event_id'] as int?,
        transactionId: m['transaction_id'] as int?,
        note: m['note'] as String? ?? '',
        createdMs: m['created_ms'] as int? ?? 0,
      );
}

class NetWorthSnapshotEntity {
  final int id;
  final String scopeKey;
  final String snapshotDate;
  final Decimal totalAssets;
  final Decimal totalLiabilities;
  final Decimal netWorth;
  final Decimal cashAssets;
  final Decimal investmentAssets;
  final Decimal physicalAssets;
  final Decimal receivableAssets;
  final String snapshotType;
  final String lineageKey;
  final int asOfMs;
  final int knowledgeCutoffMs;
  final String timezone;
  final int scopeVersion;
  final int calculationVersion;
  final String currencyCoverageJson;
  final NetWorthSnapshotQuality quality;
  final String causeSetJson;
  final String reasonsJson;
  final String valuationCoverageJson;
  final bool provisional;
  final int createdMs;

  const NetWorthSnapshotEntity({
    required this.id,
    this.scopeKey = 'global',
    required this.snapshotDate,
    required this.totalAssets,
    required this.totalLiabilities,
    required this.netWorth,
    required this.cashAssets,
    required this.investmentAssets,
    required this.physicalAssets,
    required this.receivableAssets,
    this.snapshotType = 'legacy_unverified',
    this.lineageKey = 'legacy:global',
    this.asOfMs = 0,
    this.knowledgeCutoffMs = 0,
    this.timezone = 'device_local',
    this.scopeVersion = 1,
    this.calculationVersion = 1,
    this.currencyCoverageJson = '',
    this.quality = NetWorthSnapshotQuality.legacyUnverified,
    this.causeSetJson = '',
    this.reasonsJson = '',
    this.valuationCoverageJson = '',
    this.provisional = false,
    this.createdMs = 0,
  });

  bool get isComputed => snapshotType == 'computed_snapshot';

  ComputedNetWorthSnapshot toComputedSnapshot() {
    final parsedDate = DateTime.tryParse(snapshotDate) ??
        DateTime.fromMillisecondsSinceEpoch(
          asOfMs == 0 ? createdMs : asOfMs,
        );
    // snapshot_date is the civil-day truth. Epoch midnight can map to another
    // day after the device travels to a different timezone.
    final asOf = parsedDate;
    final coverage = _decodeNetWorthCurrencyCoverage(currencyCoverageJson);
    final causes = _decodeNetWorthSnapshotCauses(causeSetJson);
    final reasons = _decodeNetWorthSnapshotReasons(reasonsJson);
    final valuation = _decodeNetWorthValuationCoverage(valuationCoverageJson);
    final effectiveQuality =
        isComputed ? quality : NetWorthSnapshotQuality.legacyUnverified;
    return ComputedNetWorthSnapshot.rehydrate(
      lineage: NetWorthSnapshotLineage(
        asOf: asOf,
        knowledgeCutoff: DateTime.fromMillisecondsSinceEpoch(
          knowledgeCutoffMs == 0 ? createdMs : knowledgeCutoffMs,
        ),
        timezone: timezone.isEmpty ? 'device_local' : timezone,
        scopeKey: scopeKey,
        scopeVersion: max(1, scopeVersion),
        calculationVersion: max(1, calculationVersion),
        currencyCoverage: coverage,
        quality: effectiveQuality,
        reasons: effectiveQuality == NetWorthSnapshotQuality.available
            ? const []
            : reasons.isEmpty
                ? [
                    NetWorthSnapshotReason(
                      code: effectiveQuality.storageKey,
                      message: isComputed ? '快照数据不完整' : '旧快照未经当前口径验证',
                    ),
                  ]
                : reasons,
        provisional: provisional,
        causes:
            causes.isEmpty ? const {NetWorthSnapshotCause.migration} : causes,
      ),
      components: NetWorthSnapshotComponents(
        cashAssetsMinor: decimalToBudgetCents(cashAssets),
        investmentAssetsMinor: decimalToBudgetCents(investmentAssets),
        physicalAssetsMinor: decimalToBudgetCents(physicalAssets),
        receivableAssetsMinor: decimalToBudgetCents(receivableAssets),
        liabilitiesMinor: decimalToBudgetCents(totalLiabilities),
      ),
      valuationCoverage: valuation,
    );
  }

  factory NetWorthSnapshotEntity.fromMap(Map<String, Object?> m) =>
      NetWorthSnapshotEntity(
        id: m['id'] as int,
        scopeKey: m['scope_key'] as String? ?? 'global',
        snapshotDate: m['snapshot_date'] as String? ?? '',
        totalAssets: Decimal.tryParse(m['total_assets'] as String? ?? '') ??
            Decimal.zero,
        totalLiabilities:
            Decimal.tryParse(m['total_liabilities'] as String? ?? '') ??
                Decimal.zero,
        netWorth:
            Decimal.tryParse(m['net_worth'] as String? ?? '') ?? Decimal.zero,
        cashAssets:
            Decimal.tryParse(m['cash_assets'] as String? ?? '') ?? Decimal.zero,
        investmentAssets:
            Decimal.tryParse(m['investment_assets'] as String? ?? '') ??
                Decimal.zero,
        physicalAssets:
            Decimal.tryParse(m['physical_assets'] as String? ?? '') ??
                Decimal.zero,
        receivableAssets:
            Decimal.tryParse(m['receivable_assets'] as String? ?? '') ??
                Decimal.zero,
        snapshotType: m['snapshot_type'] as String? ?? 'legacy_unverified',
        lineageKey: m['lineage_key'] as String? ?? 'legacy:global',
        asOfMs: m['as_of_ms'] as int? ?? 0,
        knowledgeCutoffMs: m['knowledge_cutoff_ms'] as int? ?? 0,
        timezone: m['timezone'] as String? ?? 'device_local',
        scopeVersion: m['scope_version'] as int? ?? 1,
        calculationVersion: m['calculation_version'] as int? ?? 1,
        currencyCoverageJson: m['currency_coverage_json'] as String? ?? '',
        quality: NetWorthSnapshotQualityX.fromStorage(
          m['quality'] as String?,
        ),
        causeSetJson: m['cause_set_json'] as String? ?? '',
        reasonsJson: m['reasons_json'] as String? ?? '',
        valuationCoverageJson: m['valuation_coverage_json'] as String? ?? '',
        provisional: (m['provisional'] as int? ?? 0) == 1,
        createdMs: m['created_ms'] as int? ?? 0,
      );
}

NetWorthCurrencyCoverage _decodeNetWorthCurrencyCoverage(String raw) {
  try {
    final value = jsonDecode(raw);
    if (value is Map) {
      return NetWorthCurrencyCoverage(
        baseCurrency: value['base_currency']?.toString() ?? 'CNY',
        coveredCurrencies:
            (value['covered'] as List? ?? const ['CNY']).map((e) => '$e'),
        uncoveredCurrencies:
            (value['uncovered'] as List? ?? const []).map((e) => '$e'),
      );
    }
  } catch (_) {}
  return NetWorthCurrencyCoverage.single('CNY');
}

Set<NetWorthSnapshotCause> _decodeNetWorthSnapshotCauses(String raw) {
  try {
    final value = jsonDecode(raw);
    if (value is List) {
      return value
          .map((item) => NetWorthSnapshotCauseX.fromStorage('$item'))
          .toSet();
    }
  } catch (_) {}
  return const {};
}

List<NetWorthSnapshotReason> _decodeNetWorthSnapshotReasons(String raw) {
  try {
    final value = jsonDecode(raw);
    if (value is List) {
      return [
        for (final item in value)
          if (item is Map && (item['code']?.toString().isNotEmpty ?? false))
            NetWorthSnapshotReason(
              code: item['code'].toString(),
              message: item['message']?.toString() ?? '',
              details: item['details'] is Map
                  ? Map<String, Object?>.from(item['details'] as Map)
                  : const {},
            ),
      ];
    }
  } catch (_) {}
  return const [];
}

NetWorthValuationCoverage _decodeNetWorthValuationCoverage(String raw) {
  try {
    final value = jsonDecode(raw);
    if (value is Map) {
      return NetWorthValuationCoverage(
        missingValuationCount: value['missing_count'] as int? ?? 0,
        staleValuationCount: value['stale_count'] as int? ?? 0,
      );
    }
  } catch (_) {}
  return const NetWorthValuationCoverage();
}

class NetWorthBreakdown {
  final Decimal totalAssets;
  final Decimal totalLiabilities;
  final Decimal netWorth;
  final Decimal cashAssets;
  final Decimal investmentAssets;
  final Decimal physicalAssets;
  final Decimal receivableAssets;

  const NetWorthBreakdown({
    required this.totalAssets,
    required this.totalLiabilities,
    required this.netWorth,
    required this.cashAssets,
    required this.investmentAssets,
    required this.physicalAssets,
    required this.receivableAssets,
  });
}

class LiabilityProfileEntity {
  final int id;
  final String uuid;
  final int accountId;
  final LiabilityProfileType type;
  final Decimal originalAmount;
  final Decimal currentPrincipal;
  final Decimal interestRate;
  final int? repaymentDay;
  final int? repaymentAccountId;
  final int? startDateMs;
  final int? endDateMs;
  final LiabilityProfileStatus status;
  final String note;

  /// 信用卡账单日（每月 1-31）；null = 未设置。
  final int? statementDay;

  /// 信用卡额度；null = 未设置（Decimal 字符串存储）。
  final Decimal? creditLimit;

  /// 借入对象姓名（personalBorrow 用）；空 = 无对象。
  final String counterparty;
  final int createdMs;
  final int updatedMs;

  LiabilityProfileEntity({
    required this.id,
    this.uuid = '',
    required this.accountId,
    this.type = LiabilityProfileType.other,
    required this.originalAmount,
    required this.currentPrincipal,
    Decimal? interestRate,
    this.repaymentDay,
    this.repaymentAccountId,
    this.startDateMs,
    this.endDateMs,
    this.status = LiabilityProfileStatus.active,
    this.note = '',
    this.statementDay,
    this.creditLimit,
    this.counterparty = '',
    this.createdMs = 0,
    this.updatedMs = 0,
  }) : interestRate = interestRate ?? Decimal.zero;

  DateTime? get startDate => startDateMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(startDateMs!);
  DateTime? get endDate => endDateMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(endDateMs!);

  bool get countsAsLiability =>
      status.countsAsLiability && currentPrincipal > Decimal.zero;

  DateTime? nextRepaymentDate({DateTime? now}) {
    final day = repaymentDay;
    if (day == null || day < 1 || day > 31) {
      // A2 个人借入：没设每月还款日、但约了一次性还款日（endDate）时，
      // 到期日就是它。到期已过也照样返回（daysUntilRepayment 会是负数），
      // 逾期的欠款该被看见，不该悄悄消失。只对 personalBorrow 生效——
      // 房贷/车贷的 endDate 是「贷款结清日」，不是单次还款日。
      if (type == LiabilityProfileType.personalBorrow && endDateMs != null) {
        final due = endDate!;
        return DateTime(due.year, due.month, due.day);
      }
      return null;
    }
    final base = now ?? DateTime.now();
    DateTime candidate(int year, int month) {
      final last = DateTime(year, month + 1, 0).day;
      return DateTime(year, month, min(day, last));
    }

    var next = candidate(base.year, base.month);
    if (next.isBefore(DateTime(base.year, base.month, base.day))) {
      next = candidate(base.year, base.month + 1);
    }
    return next;
  }

  int? daysUntilRepayment({DateTime? now}) {
    final next = nextRepaymentDate(now: now);
    if (next == null) return null;
    final base = now ?? DateTime.now();
    final today = DateTime(base.year, base.month, base.day);
    return next.difference(today).inDays;
  }

  factory LiabilityProfileEntity.fromMap(Map<String, Object?> m) =>
      LiabilityProfileEntity(
        id: m['id'] as int,
        uuid: m['uuid'] as String? ?? '',
        accountId: m['account_id'] as int,
        type: LiabilityProfileTypeX.fromStorage(m['liability_type'] as String?),
        originalAmount:
            Decimal.tryParse(m['original_amount'] as String? ?? '') ??
                Decimal.zero,
        currentPrincipal:
            Decimal.tryParse(m['current_principal'] as String? ?? '') ??
                Decimal.zero,
        interestRate: Decimal.tryParse(m['interest_rate'] as String? ?? '') ??
            Decimal.zero,
        repaymentDay: m['repayment_day'] as int?,
        repaymentAccountId: m['repayment_account_id'] as int?,
        startDateMs: m['start_date_ms'] as int?,
        endDateMs: m['end_date_ms'] as int?,
        status: LiabilityProfileStatusX.fromStorage(m['status'] as String?),
        note: m['note'] as String? ?? '',
        statementDay: m['statement_day'] as int?,
        creditLimit: Decimal.tryParse(m['credit_limit'] as String? ?? ''),
        counterparty: m['counterparty'] as String? ?? '',
        createdMs: m['created_ms'] as int? ?? 0,
        updatedMs: m['updated_ms'] as int? ?? 0,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'uuid': uuid,
        'account_id': accountId,
        'liability_type': type.storageKey,
        'original_amount': originalAmount.toString(),
        'current_principal': currentPrincipal.toString(),
        'interest_rate': interestRate.toString(),
        'repayment_day': repaymentDay,
        'repayment_account_id': repaymentAccountId,
        'start_date_ms': startDateMs,
        'end_date_ms': endDateMs,
        'status': status.storageKey,
        'note': note,
        'statement_day': statementDay,
        'credit_limit': creditLimit?.toString(),
        'counterparty': counterparty,
        'created_ms': createdMs,
        'updated_ms': updatedMs,
      };
}

class BookEntity {
  final int id;
  final String name;
  final String icon;

  /// 封面图资源路径（assets/book_covers/*.png）；空 = 无封面（显示 emoji）。
  final String cover;

  /// 备注（抽屉账本行名称下方的灰小字）；空 = 不显示。
  final String remark;

  /// 加星账本排在列表前面（总账本永远第一）。
  final bool starred;

  /// 该账本的账单是否并入「总账本」视图（默认并入）。
  final bool includeInTotal;

  const BookEntity({
    required this.id,
    required this.name,
    this.icon = '📒',
    this.cover = '',
    this.remark = '',
    this.starred = false,
    this.includeInTotal = true,
  });

  factory BookEntity.fromMap(Map<String, Object?> m) => BookEntity(
        id: m['id'] as int,
        name: m['name'] as String,
        icon: m['icon'] as String? ?? '📒',
        cover: m['cover'] as String? ?? '',
        remark: m['remark'] as String? ?? '',
        starred: ((m['starred'] as int?) ?? 0) == 1,
        includeInTotal: ((m['include_in_total'] as int?) ?? 1) == 1,
      );
}

class CategoryEntity {
  final int id;
  final String key;
  final String nameZh;
  final String nameEn;
  final String kindRaw;
  final int? parentId;

  /// 已隐藏：不再出现在记账面板/编辑的分类网格里（历史账单不受影响）。
  final bool hidden;

  TransactionKind get kind => TransactionKind.fromJson(kindRaw);
  bool get isTopLevel => parentId == null;

  const CategoryEntity({
    required this.id,
    required this.key,
    required this.nameZh,
    required this.nameEn,
    required this.kindRaw,
    this.parentId,
    this.hidden = false,
  });

  String localizedName(String languageCode) =>
      languageCode.toLowerCase().startsWith('zh') ? nameZh : nameEn;

  Map<String, Object?> toMap() => {
        'id': id == 0 ? null : id,
        'key': key,
        'name_zh': nameZh,
        'name_en': nameEn,
        'kind': kindRaw,
        'parent_id': parentId,
        'hidden': hidden ? 1 : 0,
      };

  factory CategoryEntity.fromMap(Map<String, Object?> m) => CategoryEntity(
        id: m['id'] as int,
        key: m['key'] as String,
        nameZh: m['name_zh'] as String,
        nameEn: m['name_en'] as String,
        kindRaw: m['kind'] as String,
        parentId: m['parent_id'] as int?,
        hidden: ((m['hidden'] as int?) ?? 0) == 1,
      );
}

class TransactionEntity {
  final int id;
  final int? bookId;
  final String uuid;
  final String kind;
  final String amountStr;
  final String currencyCode;
  final int? categoryId;
  final String categoryKey;
  final String categoryNameZh;
  final String categoryNameEn;
  final int? accountId;
  final String accountName;
  final int? toAccountId;
  final String toAccountName;
  final String note;
  final int dateMs;
  final TransactionTimePrecision timePrecision;
  final int createdMs;
  final int? settledMs;
  final SettlementQuality settlementQuality;
  final int? settlementAccountId;
  final SettlementQuality settlementAccountQuality;
  final TransactionEventType eventType;
  final String tagsRaw;
  final bool reimbursable;
  final String imagePath;
  final int? recurringRuleId;

  /// 不计入收支：仍在账单列表里，但统计/预算/洞察都跳过它。
  final bool excluded;

  /// 附着式退款：非空 = 这是某笔原账单的退款行（负支出），
  /// 不在时间线单独显示，改挂到 refundOf 那笔的详情/净额里。
  final int? refundOf;

  Decimal get amount => Decimal.parse(amountStr);
  DateTime get date => DateTime.fromMillisecondsSinceEpoch(dateMs);
  DateTime? get settledAt => settledMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(settledMs!);
  TransactionKind get txKind => TransactionKind.fromJson(kind);

  List<int> get tagIds => tagsRaw.isEmpty
      ? const []
      : tagsRaw
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .toList();

  const TransactionEntity({
    required this.id,
    this.bookId,
    this.uuid = '',
    required this.kind,
    required this.amountStr,
    this.currencyCode = 'CNY',
    this.categoryId,
    this.categoryKey = '',
    this.categoryNameZh = '',
    this.categoryNameEn = '',
    this.accountId,
    this.accountName = '',
    this.toAccountId,
    this.toAccountName = '',
    this.note = '',
    required this.dateMs,
    this.timePrecision = TransactionTimePrecision.legacyUnknown,
    this.createdMs = 0,
    this.settledMs,
    this.settlementQuality = SettlementQuality.unknown,
    this.settlementAccountId,
    this.settlementAccountQuality = SettlementQuality.unknown,
    this.eventType = TransactionEventType.legacyAdjustment,
    this.tagsRaw = '',
    this.reimbursable = false,
    this.imagePath = '',
    this.recurringRuleId,
    this.excluded = false,
    this.refundOf,
  });

  TransactionRecord toRecord({String languageCode = 'zh'}) => TransactionRecord(
        id: id.toString(),
        kind: txKind,
        amount: amount,
        currencyCode: currencyCode,
        categoryName:
            languageCode.startsWith('zh') ? categoryNameZh : categoryNameEn,
        categoryKey: categoryKey,
        accountId: accountId,
        accountName: accountName,
        toAccountId: toAccountId,
        toAccountName: toAccountName,
        note: note,
        date: date,
        timePrecision: timePrecision,
      );

  factory TransactionEntity.fromMap(Map<String, Object?> m) =>
      TransactionEntity(
        id: m['id'] as int,
        bookId: m['book_id'] as int?,
        uuid: m['uuid'] as String? ?? '',
        kind: m['kind'] as String,
        amountStr: m['amount'] as String,
        currencyCode: m['currency_code'] as String? ?? 'CNY',
        categoryId: m['category_id'] as int?,
        categoryKey: m['category_key'] as String? ?? '',
        categoryNameZh: m['category_name_zh'] as String? ?? '',
        categoryNameEn: m['category_name_en'] as String? ?? '',
        accountId: m['account_id'] as int?,
        accountName: m['account_name'] as String? ?? '',
        toAccountId: m['to_account_id'] as int?,
        toAccountName: m['to_account_name'] as String? ?? '',
        note: m['note'] as String? ?? '',
        dateMs: m['date_ms'] as int,
        timePrecision: TransactionTimePrecisionX.fromStorage(
          m['time_precision'] as String?,
        ),
        createdMs: m['created_ms'] as int? ?? 0,
        settledMs: m['settled_ms'] as int?,
        settlementQuality: SettlementQualityX.fromStorage(
          m['settlement_quality'] as String?,
        ),
        settlementAccountId: m['settlement_account_id'] as int?,
        settlementAccountQuality: SettlementQualityX.fromStorage(
          m['settlement_account_quality'] as String?,
        ),
        eventType: TransactionEventTypeX.fromStorage(
          m['event_type'] as String?,
        ),
        tagsRaw: m['tags'] as String? ?? '',
        reimbursable: ((m['reimbursable'] as int?) ?? 0) == 1,
        imagePath: m['image_path'] as String? ?? '',
        recurringRuleId: m['recurring_rule_id'] as int?,
        excluded: ((m['excluded'] as int?) ?? 0) == 1,
        refundOf: m['refund_of'] as int?,
      );
}

class TransactionDraft {
  final TransactionKind kind;
  final Decimal amount;
  final int? categoryId;
  final int accountId;
  final String note;
  final DateTime date;
  final TransactionTimePrecision timePrecision;
  final List<int> tagIds;

  const TransactionDraft({
    required this.kind,
    required this.amount,
    this.categoryId,
    required this.accountId,
    this.note = '',
    required this.date,
    this.timePrecision = TransactionTimePrecision.legacyUnknown,
    this.tagIds = const [],
  });
}

class FeimiaoImportRow {
  final String uuid;
  final String refundOfUuid;
  final String role;
  final TransactionKind kind;
  final Decimal amount;
  final Decimal refunded;
  final String categoryKey;
  final String categoryName;
  final String accountName;
  final String toAccountName;
  final List<String> tagNames;
  final String note;
  final DateTime date;
  final TransactionTimePrecision timePrecision;
  final DateTime? settledAt;
  final SettlementQuality? settlementQuality;
  final String settlementAccountName;
  final SettlementQuality? settlementAccountQuality;
  final TransactionEventType? eventType;
  final bool excluded;
  final bool reimbursable;

  const FeimiaoImportRow({
    this.uuid = '',
    this.refundOfUuid = '',
    this.role = 'transaction',
    required this.kind,
    required this.amount,
    required this.refunded,
    this.categoryKey = '',
    this.categoryName = '',
    this.accountName = '',
    this.toAccountName = '',
    this.tagNames = const [],
    this.note = '',
    required this.date,
    this.timePrecision = TransactionTimePrecision.legacyUnknown,
    this.settledAt,
    this.settlementQuality,
    this.settlementAccountName = '',
    this.settlementAccountQuality,
    this.eventType,
    this.excluded = false,
    this.reimbursable = false,
  });
}

class FeimiaoImportResult {
  final int inserted;
  final int skippedDuplicates;
  final int refundsAttached;

  const FeimiaoImportResult({
    required this.inserted,
    required this.skippedDuplicates,
    required this.refundsAttached,
  });
}

class FeimiaoAssetImportResult {
  final int assets;
  final int receivables;
  final int events;
  final int usages;
  final int valuations;
  final int links;
  final int recoveries;
  final int snapshots;
  final int liabilities;
  final int unresolvedTransactionLinks;
  final int unresolvedSavingsGoalLinks;
  final int rejectedLinks;

  const FeimiaoAssetImportResult({
    required this.assets,
    this.receivables = 0,
    required this.events,
    this.usages = 0,
    required this.valuations,
    required this.links,
    this.recoveries = 0,
    this.snapshots = 0,
    this.liabilities = 0,
    this.unresolvedTransactionLinks = 0,
    this.unresolvedSavingsGoalLinks = 0,
    this.rejectedLinks = 0,
  });

  int get total =>
      assets +
      receivables +
      events +
      usages +
      valuations +
      links +
      recoveries +
      snapshots +
      liabilities;
}

class ImportBatchResult {
  final int inserted;
  final int skippedDuplicates;
  final int refundsAttached;
  final int unresolvedRefunds;

  const ImportBatchResult({
    required this.inserted,
    required this.skippedDuplicates,
    required this.refundsAttached,
    this.unresolvedRefunds = 0,
  });
}

class SavingsGoalEntity {
  final int id;
  final String uuid;
  final String name;
  final String emoji;
  final String targetStr;
  final String savedStr;
  final int createdMs;
  final int updatedMs;

  Decimal get target => Decimal.parse(targetStr);
  Decimal get saved => Decimal.parse(savedStr);

  double get progress {
    final t = target;
    if (t <= Decimal.zero) return 0;
    final r = (saved / t).toDouble();
    return r.clamp(0.0, 1.0);
  }

  bool get isDone => saved >= target && target > Decimal.zero;

  const SavingsGoalEntity({
    required this.id,
    required this.uuid,
    required this.name,
    this.emoji = '🐷',
    required this.targetStr,
    this.savedStr = '0',
    this.createdMs = 0,
    this.updatedMs = 0,
  });

  factory SavingsGoalEntity.fromMap(Map<String, Object?> m) =>
      SavingsGoalEntity(
        id: m['id'] as int,
        uuid: m['uuid'] as String? ?? '',
        name: m['name'] as String,
        emoji: m['emoji'] as String? ?? '🐷',
        targetStr: m['target_amount'] as String? ?? '0',
        savedStr: m['saved_amount'] as String? ?? '0',
        createdMs: m['created_ms'] as int? ?? 0,
        updatedMs: m['updated_ms'] as int? ?? 0,
      );
}

class TagEntity {
  final int id;
  final String name;
  final int colorValue;

  const TagEntity({
    required this.id,
    required this.name,
    required this.colorValue,
  });

  factory TagEntity.fromMap(Map<String, Object?> m) => TagEntity(
        id: m['id'] as int,
        name: m['name'] as String,
        colorValue: m['color'] as int? ?? 0xFF7D8B9B,
      );
}

class ReportEntity {
  final int id;
  final int? bookId;
  final String type;
  final String title;
  final String summary;
  final String markdown;
  final int periodStartMs;
  final int periodEndMs;
  final int createdMs;
  final int pinnedMs;

  const ReportEntity({
    required this.id,
    this.bookId,
    required this.type,
    required this.title,
    required this.summary,
    required this.markdown,
    required this.periodStartMs,
    required this.periodEndMs,
    required this.createdMs,
    this.pinnedMs = 0,
  });

  DateTime get periodStart =>
      DateTime.fromMillisecondsSinceEpoch(periodStartMs);
  DateTime get periodEnd => DateTime.fromMillisecondsSinceEpoch(periodEndMs);
  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdMs);
  bool get pinned => pinnedMs > 0;

  factory ReportEntity.fromMap(Map<String, Object?> m) => ReportEntity(
        id: m['id'] as int,
        bookId: m['book_id'] as int?,
        type: m['type'] as String? ?? 'monthly',
        title: m['title'] as String? ?? '',
        summary: m['summary'] as String? ?? '',
        markdown: m['markdown'] as String? ?? '',
        periodStartMs: m['period_start_ms'] as int? ?? 0,
        periodEndMs: m['period_end_ms'] as int? ?? 0,
        createdMs: m['created_ms'] as int? ?? 0,
        pinnedMs: m['pinned_ms'] as int? ?? 0,
      );
}

class ReportJobEntity {
  final int id;
  final String uuid;
  final int? bookId;
  final int? reportId;
  final String question;
  final String type;
  final String title;
  final int periodStartMs;
  final int periodEndMs;
  final String status;
  final String stage;
  final String error;
  final int createdMs;
  final int updatedMs;

  const ReportJobEntity({
    required this.id,
    required this.uuid,
    this.bookId,
    this.reportId,
    required this.question,
    required this.type,
    required this.title,
    required this.periodStartMs,
    required this.periodEndMs,
    required this.status,
    required this.stage,
    required this.error,
    required this.createdMs,
    required this.updatedMs,
  });

  DateTime get periodStart =>
      DateTime.fromMillisecondsSinceEpoch(periodStartMs);
  DateTime get periodEnd => DateTime.fromMillisecondsSinceEpoch(periodEndMs);
  bool get isPending => status == 'queued' || status == 'running';

  factory ReportJobEntity.fromMap(Map<String, Object?> row) => ReportJobEntity(
        id: row['id'] as int,
        uuid: row['uuid'] as String? ?? '',
        bookId: row['book_id'] as int?,
        reportId: row['report_id'] as int?,
        question: row['question'] as String? ?? '',
        type: row['type'] as String? ?? 'monthly',
        title: row['title'] as String? ?? '',
        periodStartMs: row['period_start_ms'] as int? ?? 0,
        periodEndMs: row['period_end_ms'] as int? ?? 0,
        status: row['status'] as String? ?? 'queued',
        stage: row['stage'] as String? ?? 'collect',
        error: row['error'] as String? ?? '',
        createdMs: row['created_ms'] as int? ?? 0,
        updatedMs: row['updated_ms'] as int? ?? 0,
      );
}

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

class AppRepository extends ChangeNotifier {
  static const _dbVersion = 43;
  static const _dbName = 'qingji.db';

  AppRepository({ReportExecutionFence? reportExecutionFence})
      : _reportExecutionFence =
            reportExecutionFence ?? ReportExecutionFence.shared;

  final ReportExecutionFence _reportExecutionFence;
  int _databaseGeneration = 0;

  /// Changes only after a different database snapshot is committed.
  /// View-level caches use this to drop rows that belonged to the old file.
  int get databaseGeneration => _databaseGeneration;

  /// 全局数据版本号：每次 notifyListeners()（= 任何写路径收尾）自动 +1。
  /// 余额 / 净资产 / 趋势 memo 拿它当缓存 key——版本一变旧结果自动作废，
  /// 121 处 notifyListeners 调用点零改动就全部接入失效。
  int _revision = 0;

  @override
  void notifyListeners() {
    _revision++;
    super.notifyListeners();
  }

  /// 行级 uuid（多人共享账本的同步地基）：32 位小写 hex，无需三方库。
  static String _newUuid() {
    final r = Random();
    return List.generate(
        16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  /// 新行的同步字段：uuid + 变更时间戳。
  static Map<String, Object?> _syncStampNew() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return {'uuid': _newUuid(), 'created_ms': now, 'updated_ms': now};
  }

  static TransactionEventType _eventTypeForKind(TransactionKind kind) =>
      switch (kind) {
        TransactionKind.expense => TransactionEventType.expense,
        TransactionKind.income => TransactionEventType.income,
        TransactionKind.transfer => TransactionEventType.transfer,
      };

  static Map<String, Object?> _settlementFields({
    required DateTime settledAt,
    required int settlementAccountId,
    required TransactionEventType eventType,
    SettlementQuality dateQuality = SettlementQuality.userConfirmed,
    SettlementQuality accountQuality = SettlementQuality.userConfirmed,
  }) =>
      {
        'settled_ms': settledAt.millisecondsSinceEpoch,
        'settlement_quality': dateQuality.storageKey,
        'settlement_account_id': settlementAccountId,
        'settlement_account_quality': accountQuality.storageKey,
        'event_type': eventType.storageKey,
      };

  Database? _db;

  // `_db != null` only means that SQLite has opened the file.  The home page
  // still cannot safely use accounts/categories/transactions until the
  // convergence pass has finished.  Keep that distinction explicit so cold
  // start can paint first without allowing a tap to race the loader.
  Future<void>? _initFuture;
  Future<void>? _deferredInitFuture;
  Completer<void> _readyCompleter = Completer<void>();
  Completer<void> _fullyReadyCompleter = Completer<void>();
  bool _isReady = false;
  bool _isFullyReady = false;
  bool _deferredInitPending = false;
  String? _deferredAutoBackupPath;
  bool _deferredRefundNormalization = false;
  Object? _initializationError;
  StackTrace? _initializationErrorStack;

  bool get isInitialized => _db != null;

  /// True only after the complete in-memory repository snapshot is usable.
  bool get isReady => _isReady;

  /// True while the first database snapshot is being assembled. A freshly
  /// constructed repository used by a widget test is not considered loading;
  /// this keeps the UI components usable without forcing tests to open SQLite.
  bool get isInitializing => _initFuture != null && !_isReady;

  /// True after the full ledger, assets and maintenance convergence pass.
  /// The home page only needs [isReady]; heavier pages can opt into this.
  bool get isFullyReady => _isFullyReady;

  bool get isHydrating => _deferredInitPending && !_isFullyReady;

  /// Completes after startup convergence, even if initialization failed.
  /// Callers should check [isReady] afterwards; completing normally prevents a
  /// background startup task from becoming an unhandled Future error.
  Future<void> get ready => _readyCompleter.future;

  Future<void> get fullyReady => _fullyReadyCompleter.future;

  Object? get initializationError => _initializationError;

  @visibleForTesting
  StackTrace? get initializationErrorStack => _initializationErrorStack;

  final List<BookEntity> _books = [];
  final List<AccountEntity> _accounts = [];
  final List<AccountBalanceCheckpointEntity> _accountBalanceCheckpoints = [];
  final Map<int, Set<String>> _checkpointCoveredUnknownEventIds = {};
  final List<CategoryEntity> _categories = [];
  final List<TransactionEntity> _transactions = [];
  final List<TransactionEntity> _allTransactions = [];
  final List<PhysicalAssetEntity> _physicalAssets = [];
  final List<PhysicalAssetEntity> _allPhysicalAssets = [];
  final List<ReceivableAssetEntity> _receivableAssets = [];
  final List<ReceivableAssetEntity> _allReceivableAssets = [];
  final List<ReceivableRecoveryEntity> _receivableRecoveries = [];
  final List<NetWorthSnapshotEntity> _netWorthSnapshots = [];
  final List<NetWorthVerifiedCheckpoint> _verifiedNetWorthCheckpoints = [];
  int _netWorthScopeVersion = 1;
  final List<LiabilityProfileEntity> _liabilityProfiles = [];
  final List<AssetEventEntity> _assetEvents = [];
  final List<AssetValuationEntity> _assetValuations = [];
  final List<AssetTransactionLinkEntity> _assetTransactionLinks = [];
  final List<AssetUsageEventEntity> _assetUsageEvents = [];
  final List<SavingsGoalEntity> _savingsGoals = [];
  final List<TagEntity> _tags = [];
  final List<ReportEntity> _reports = [];

  int _currentBookId = 0;

  /// 全部预算期间（新模型：阶段性预算，见 core/budget/budget_period.dart）。
  final List<BudgetPeriod> _budgetPeriods = [];
  final List<BudgetPlanV2> _budgetPlansV2 = [];
  final List<BudgetPlanRevisionV2> _budgetPlanRevisionsV2 = [];
  final List<BudgetCycleOverrideV2> _budgetCycleOverridesV2 = [];
  final List<BudgetFixedOccurrenceEntity> _budgetFixedOccurrencesV2 = [];
  AiProviderType _aiProviderType = AiProviderType.deepseek;
  String? _deepSeekApiKey;
  String? _customAiApiKey;
  String _customAiDisplayName = '自定义';
  String _customAiBaseUrl = AiProviderConfig.customDefaultBaseUrl;
  String _customAiModel = AiProviderConfig.customDefaultModel;
  String _reportAiModel = AiProviderConfig.customReportDefaultModel;

  /// 用户筛选后保留的可用模型列表（逗号分隔持久化）
  List<String> _availableModels = [];

  /// 多服务商配置。API Key 只保存在安全存储中，列表本身仅含元数据。
  final List<AiConfiguredProvider> _aiProviders = [];
  String? _recordAiProviderId;
  String? _chatCurrentProviderId;
  String? _chatCurrentModel;
  AiProviderType _recordAiProviderType = AiProviderType.deepseek;
  AiProviderType _chatAiProviderType = AiProviderType.deepseek;
  AiProviderType _reportAiProviderType = AiProviderType.custom;
  AiRouteMode _recordAiRouteMode = AiRouteMode.auto;
  AiRouteMode _chatAiRouteMode = AiRouteMode.auto;
  AiRouteMode _reportAiRouteMode = AiRouteMode.auto;
  AiEndpointType _recordAiEndpointType = AiEndpointType.chatCompletions;
  AiEndpointType _chatAiEndpointType = AiEndpointType.auto;
  AiEndpointType _reportAiEndpointType = AiEndpointType.responses;
  AiReasoningEffort _recordAiReasoningEffort = AiReasoningEffort.none;
  AiReasoningEffort _chatAiReasoningEffort = AiReasoningEffort.low;
  AiReasoningEffort _reportAiReasoningEffort = AiReasoningEffort.xhigh;

  /// 记账模式偏好：true=AI 记账，false=手动记账（持久化）。
  bool _recordAiMode = false;
  int _chatRetentionDays = 30;
  bool _aiPrivacyAccepted = false;
  bool _widgetPrivacyMode = false;

  /// 还款提醒本地通知开关（A 批第 5 段），默认开。
  bool _repaymentReminderEnabled = true;
  int _moneyDecimalPlaces = 2;
  MoneyIntegerRoundingMode _moneyIntegerRoundingMode =
      MoneyIntegerRoundingMode.round;
  CategoryIconStyle _categoryIconStyle = CategoryIconStyle.filled;
  TransactionCardDisplayMode _transactionCardDisplayMode =
      TransactionCardDisplayMode.contentFirst;
  UserMessageBubbleStyle _userMessageBubbleStyle =
      UserMessageBubbleStyle.followCardOpacity;
  // 资产管理上次选中的 tab（0=总览, 1=资金, 2=物品），默认物品。
  int _lastAssetViewTabIndex = 2;
  String _profileNickname = '';
  String _profileAvatarPath = '';

  /// 用户纠正记忆：(备注短语, 收支, 分类key)。AI 记账时按此覆盖模型的猜测。
  final List<({String phrase, TransactionKind kind, String key})> _catMemory =
      [];

  /// 周期记账规则(全部账本)。
  final List<RecurringRule> _recurringRules = [];

  /// 总账本 id（最早建的那本，聚合视图、不可删）。
  int _defaultBookId = 0;

  /// 抽屉功能项的用户自定义顺序（key 列表，见 main.dart 注册表）。
  final List<String> _drawerOrder = [];

  /// 统计页卡片的用户自定义顺序/可见集（key 列表，见 statistics_view 注册表）。
  final List<String> _statCardOrder = [];
  bool _statCardOrderConfigured = false;

  List<BookEntity> get books => _booksViewCache ??= List.unmodifiable(_books);
  List<AccountEntity> get accounts => List.unmodifiable(_accounts);
  List<AccountEntity> get activeAccounts => List.unmodifiable(
        _accounts.where((account) => !account.isArchived),
      );
  List<AccountEntity> get archivedAccounts => List.unmodifiable(
        _accounts.where((account) => account.isArchived),
      );
  List<AccountEntity> get transactionAccounts => List.unmodifiable(
        _accounts.where(
          (account) =>
              !account.isDeleted &&
              !account.isArchived &&
              account.currencyCode == 'CNY',
        ),
      );
  List<CategoryEntity> get categories =>
      _categoriesViewCache ??= List.unmodifiable(_categories);
  List<TransactionEntity> get transactions =>
      _transactionsViewCache ??= List.unmodifiable(_transactions);
  TransactionEntity? transactionById(int id) => _txById[id];
  int get transactionCount => _transactions.length;
  Iterable<TransactionEntity> get transactionsView => _transactions;
  List<TransactionEntity> transactionsForRecurringRule(int ruleId) =>
      _transactions.where((t) => t.recurringRuleId == ruleId).toList()
        ..sort((a, b) => a.dateMs.compareTo(b.dateMs));
  List<PhysicalAssetEntity> get physicalAssets =>
      List.unmodifiable(_physicalAssets);
  List<ReceivableAssetEntity> get receivableAssets =>
      List.unmodifiable(_receivableAssets);
  List<ReceivableRecoveryEntity> get receivableRecoveries =>
      List.unmodifiable(_receivableRecoveries);
  List<NetWorthSnapshotEntity> get netWorthSnapshots =>
      List.unmodifiable(_netWorthSnapshots);
  List<NetWorthVerifiedCheckpoint> get verifiedNetWorthCheckpoints =>
      List.unmodifiable(_verifiedNetWorthCheckpoints);
  List<LiabilityProfileEntity> get liabilityProfiles =>
      List.unmodifiable(_liabilityProfiles);
  List<AssetEventEntity> get assetEvents => List.unmodifiable(_assetEvents);
  List<AssetValuationEntity> get assetValuations =>
      List.unmodifiable(_assetValuations);
  List<AssetTransactionLinkEntity> get assetTransactionLinks =>
      List.unmodifiable(_assetTransactionLinks);
  List<AssetUsageEventEntity> get assetUsageEvents =>
      List.unmodifiable(_assetUsageEvents);
  List<PhysicalAssetEntity> get visiblePhysicalAssets => _physicalAssets
      .where((a) =>
          !a.isDeleted && a.visibilityStatus == AssetVisibilityStatus.active)
      .toList();
  List<PhysicalAssetEntity> get archivedPhysicalAssets => _physicalAssets
      .where((a) =>
          !a.isDeleted && a.visibilityStatus == AssetVisibilityStatus.archived)
      .toList();
  List<PhysicalAssetEntity> get globalActivePhysicalAssets => _allPhysicalAssets
      .where((a) =>
          !a.isDeleted && a.visibilityStatus == AssetVisibilityStatus.active)
      .toList(growable: false);
  List<PhysicalAssetEntity> get globalArchivedPhysicalAssets =>
      _allPhysicalAssets
          .where((a) =>
              !a.isDeleted &&
              a.visibilityStatus == AssetVisibilityStatus.archived)
          .toList(growable: false);
  PhysicalAssetEntity? physicalAssetDetailById(int id) =>
      _allPhysicalAssets.where((asset) => asset.id == id).firstOrNull;
  List<PhysicalAssetEntity> get physicalAssetsCountedInNetWorth =>
      _allPhysicalAssets
          .where((a) => a.countsInNetWorth && a.currencyCode == 'CNY')
          .toList();
  Decimal get physicalAssetNetWorthTotal =>
      physicalAssetsCountedInNetWorth.fold<Decimal>(
        Decimal.zero,
        (sum, asset) => sum + asset.currentValue,
      );
  int stalePhysicalValuationCount({
    DateTime? asOf,
    int staleAfterDays = 90,
  }) {
    final cutoff = (asOf ?? DateTime.now()).subtract(
      Duration(days: staleAfterDays),
    );
    var count = 0;
    for (final asset in physicalAssetsCountedInNetWorth) {
      final valuations = _assetValuations
          .where((point) => point.assetId == asset.id)
          .toList()
        ..sort((left, right) => left.valuedAtMs.compareTo(right.valuedAtMs));
      final latest = valuations.lastOrNull;
      if (latest != null && latest.valuedAt.isBefore(cutoff)) count++;
    }
    return count;
  }

  List<ReceivableAssetEntity> get visibleReceivableAssets => _receivableAssets
      .where((a) =>
          !a.isDeleted && a.visibilityStatus == AssetVisibilityStatus.active)
      .toList();
  List<ReceivableAssetEntity> get archivedReceivableAssets => _receivableAssets
      .where((a) =>
          !a.isDeleted && a.visibilityStatus == AssetVisibilityStatus.archived)
      .toList();
  List<ReceivableAssetEntity> get globalActiveReceivables =>
      _allReceivableAssets
          .where(
              (a) =>
                  !a.isDeleted &&
                  a.visibilityStatus == AssetVisibilityStatus.active)
          .toList(growable: false);
  List<ReceivableAssetEntity> get globalArchivedReceivables =>
      _allReceivableAssets
          .where(
              (a) =>
                  !a.isDeleted &&
                  a.visibilityStatus == AssetVisibilityStatus.archived)
          .toList(growable: false);
  ReceivableAssetEntity? receivableDetailById(int id) =>
      _allReceivableAssets.where((asset) => asset.id == id).firstOrNull;
  List<ReceivableAssetEntity> get receivableAssetsCountedInNetWorth =>
      _allReceivableAssets
          .where((a) => a.countsInNetWorth && a.currencyCode == 'CNY')
          .toList();
  Decimal get receivableAssetNetWorthTotal =>
      receivableAssetsCountedInNetWorth.fold<Decimal>(
        Decimal.zero,
        (sum, asset) => sum + asset.remainingAmount,
      );
  LiabilityProfileEntity? liabilityProfileForAccount(int accountId) =>
      _liabilityProfiles
          .where((profile) => profile.accountId == accountId)
          .firstOrNull;
  Set<String> get unsupportedNetWorthCurrencyCodes => {
        for (final account in _accounts)
          if (!account.isDeleted &&
              account.includeInNetWorth &&
              account.currencyCode != 'CNY')
            account.currencyCode,
        for (final asset in _allPhysicalAssets)
          if (asset.countsInNetWorth && asset.currencyCode != 'CNY')
            asset.currencyCode,
        for (final asset in _allReceivableAssets)
          if (asset.countsInNetWorth && asset.currencyCode != 'CNY')
            asset.currencyCode,
      };
  List<SavingsGoalEntity> get savingsGoals => List.unmodifiable(_savingsGoals);
  SavingsGoalEntity? savingsGoalById(int id) =>
      _savingsGoals.where((goal) => goal.id == id).firstOrNull;
  List<TagEntity> get tags => List.unmodifiable(_tags);
  List<ReportEntity> get reports =>
      _reportsViewCache ??= List.unmodifiable(_reports);

  String? tagName(int id) {
    for (final t in _tags) {
      if (t.id == id) return t.name;
    }
    return null;
  }

  int get currentBookId => _currentBookId;

  /// 总账本（最早建的那本）的 id：聚合视图、不可删除。
  int get defaultBookId => _defaultBookId;

  BookEntity? get currentBook {
    for (final b in _books) {
      if (b.id == _currentBookId) return b;
    }
    return null;
  }

  /// 抽屉功能项顺序（key 列表）；空 = 用默认顺序。
  List<String> get drawerOrder => List.unmodifiable(_drawerOrder);

  /// 保存抽屉功能项顺序（长按拖动排序后持久化）。
  Future<void> setDrawerOrder(List<String> keys) async {
    _drawerOrder
      ..clear()
      ..addAll(keys);
    await _db!.insert(
      'app_settings',
      {'key': 'drawer_order', 'value': keys.join(',')},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  Future<void> _loadDrawerOrder() async {
    final rows = await _db!.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['drawer_order'],
      limit: 1,
    );
    _drawerOrder.clear();
    final raw = rows.isEmpty ? '' : (rows.first['value'] as String? ?? '');
    if (raw.isNotEmpty) {
      _drawerOrder.addAll(raw.split(',').where((s) => s.isNotEmpty));
    }
  }

  /// 统计页卡片顺序/可见集（key 列表）。
  /// 未配置时空列表表示用默认；用户明确全关时空列表保持为空。
  List<String> get statCardOrder => List.unmodifiable(_statCardOrder);
  bool get hasStatCardOrderConfig => _statCardOrderConfigured;

  static const int _statCardsConfigVersion = 6;
  static const String _statCardsConfigVersionKey = 'stat_cards_config_version';
  static const List<String> _statCardsV2NewDefaults = [];
  static const Set<String> _removedStatCards = {
    'pace',
    'budget',
    'budget_cat',
  };

  /// 保存统计卡片顺序/可见集（长按排序、移除、添加后持久化）。
  Future<void> setStatCardOrder(List<String> keys) async {
    _statCardOrderConfigured = true;
    _statCardOrder
      ..clear()
      ..addAll(keys.where((k) => !_removedStatCards.contains(k)));
    final batch = _db!.batch();
    batch.insert('app_settings',
        {'key': 'stat_cards', 'value': _statCardOrder.join(',')},
        conflictAlgorithm: ConflictAlgorithm.replace);
    batch.insert(
        'app_settings',
        {
          'key': _statCardsConfigVersionKey,
          'value': '$_statCardsConfigVersion'
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    await batch.commit(noResult: true);
    notifyListeners();
  }

  Future<void> _loadStatCardOrder() async {
    final rows = await _db!.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['stat_cards'],
      limit: 1,
    );
    _statCardOrder.clear();
    _statCardOrderConfigured = rows.isNotEmpty;
    final raw = rows.isEmpty ? '' : (rows.first['value'] as String? ?? '');
    if (raw.isNotEmpty) {
      _statCardOrder.addAll(raw
          .split(',')
          .where((s) => s.isNotEmpty && !_removedStatCards.contains(s)));
    }
    if (raw.isNotEmpty) {
      await _migrateStatCardOrderIfNeeded();
    }
  }

  Future<void> _migrateStatCardOrderIfNeeded() async {
    final rows = await _db!.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [_statCardsConfigVersionKey],
      limit: 1,
    );
    final rawVersion = rows.isEmpty ? '' : rows.first['value'] as String? ?? '';
    final version = int.tryParse(rawVersion) ?? 1;
    var changed = false;
    final beforeLen = _statCardOrder.length;
    _statCardOrder.removeWhere(_removedStatCards.contains);
    changed = changed || _statCardOrder.length != beforeLen;
    if (version >= _statCardsConfigVersion) {
      if (!changed) return;
      await _db!.insert(
        'app_settings',
        {'key': 'stat_cards', 'value': _statCardOrder.join(',')},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return;
    }

    for (final key in _statCardsV2NewDefaults.reversed) {
      if (_statCardOrder.contains(key)) continue;
      final insightsIndex = _statCardOrder.indexOf('insights');
      final insertAt = insightsIndex >= 0 ? insightsIndex + 1 : 0;
      _statCardOrder.insert(insertAt, key);
      changed = true;
    }

    final batch = _db!.batch();
    if (changed) {
      batch.insert('app_settings',
          {'key': 'stat_cards', 'value': _statCardOrder.join(',')},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    batch.insert(
        'app_settings',
        {
          'key': _statCardsConfigVersionKey,
          'value': '$_statCardsConfigVersion'
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    await batch.commit(noResult: true);
  }

  // 统计页「自定义」区间：记住上次选择，再次进入不用重选。
  // 用记录类型 (start,end) 避免数据层依赖 Flutter 的 DateTimeRange；视图侧再转。
  (DateTime, DateTime)? _statCustomRange;
  (DateTime, DateTime)? get statCustomRange => _statCustomRange;

  Future<void> setStatCustomRange(DateTime start, DateTime end) async {
    _statCustomRange = (start, end);
    await _db!.insert(
      'app_settings',
      {
        'key': 'stat_custom_range',
        'value': '${start.millisecondsSinceEpoch},'
            '${end.millisecondsSinceEpoch}',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  Future<void> _loadStatCustomRange() async {
    final rows = await _db!.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['stat_custom_range'],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final parts = (rows.first['value'] as String? ?? '').split(',');
    if (parts.length != 2) return;
    final s = int.tryParse(parts[0]);
    final e = int.tryParse(parts[1]);
    if (s == null || e == null) return;
    _statCustomRange = (
      DateTime.fromMillisecondsSinceEpoch(s),
      DateTime.fromMillisecondsSinceEpoch(e),
    );
  }

  /// 全部预算期间（新建在前面显示用，按生效起点降序）。
  List<BudgetPeriod> get budgetPeriods {
    final list = List<BudgetPeriod>.of(_budgetPeriods)
      ..sort((a, b) => b.start.compareTo(a.start));
    return List.unmodifiable(list);
  }

  List<BudgetPlanV2> get budgetPlansV2 => List.unmodifiable(
        _budgetPlansV2.toList()
          ..sort(
              (left, right) => right.anchorStart.compareTo(left.anchorStart)),
      );

  List<BudgetPlanV2> get budgetSpecialPlansV2 => List.unmodifiable(
        _budgetPlansV2.where((plan) => plan.isSpecial).toList()
          ..sort(
            (left, right) => left.anchorStart.compareTo(right.anchorStart),
          ),
      );

  List<BudgetPlanRevisionV2> budgetPlanRevisionsV2For(int planId) =>
      List.unmodifiable(
        _budgetPlanRevisionsV2.where((item) => item.planId == planId).toList()
          ..sort((left, right) =>
              left.effectiveCycleStart.compareTo(right.effectiveCycleStart)),
      );

  List<BudgetFixedOccurrenceEntity> budgetFixedOccurrencesV2For(
    int planId, {
    DateTime? cycleStart,
  }) =>
      List.unmodifiable(
        _budgetFixedOccurrencesV2.where((item) {
          if (item.planId != planId) return false;
          return cycleStart == null ||
              budgetCivilDayKey(item.occurrence.cycleStart) ==
                  budgetCivilDayKey(cycleStart);
        }).toList()
          ..sort((left, right) => left.dueDate.compareTo(right.dueDate)),
      );

  List<ConsumptionExpenseFamily> _budgetExpenseFamiliesForBook(
    int logicalBookId,
  ) {
    final allowedBooks = _bookIdsForView(logicalBookId).toSet();
    final transactionById = {
      for (final transaction in _allTransactions) transaction.id: transaction,
    };
    final categoryById = {
      for (final category in _categories) category.id: category
    };
    final events = <BudgetTransactionFamilyEvent>[];
    for (final transaction in _allTransactions) {
      if (transaction.bookId == null ||
          !allowedBooks.contains(transaction.bookId)) {
        continue;
      }
      final category = transaction.categoryId == null
          ? null
          : categoryById[transaction.categoryId];
      final top = category?.parentId == null
          ? category
          : categoryById[category!.parentId!];
      final root = transaction.refundOf == null
          ? null
          : transactionById[transaction.refundOf!];
      events.add(BudgetTransactionFamilyEvent(
        id: transaction.uuid.isEmpty
            ? transaction.id.toString()
            : transaction.uuid,
        refundOfId: root == null
            ? null
            : (root.uuid.isEmpty ? root.id.toString() : root.uuid),
        isExpense: transaction.txKind == TransactionKind.expense,
        bookId: logicalBookId,
        currencyCode: transaction.currencyCode,
        attributionDate: transaction.date,
        createdAt: transaction.createdMs > 0
            ? DateTime.fromMillisecondsSinceEpoch(transaction.createdMs)
            : DateTime.fromMillisecondsSinceEpoch(0),
        amountMinor: decimalToBudgetCents(transaction.amount),
        countsInIncomeExpense: !transaction.excluded,
        countsInBudget: !transaction.excluded,
        categoryKey: top?.key ?? category?.key ?? '',
        categoryName: top?.nameZh ?? category?.nameZh ?? '',
      ));
    }
    return BudgetTransactionFamilyAdapter.build(events);
  }

  /// Resolves one explicit budget window for a logical book view. V2 receives
  /// the original expense family plus refund events, including fully-refunded
  /// orders, so knowledge-cutoff and fixed-commitment review remain replayable.
  BudgetWindowResult budgetWindow(BudgetWindowQuery query) {
    final families = _budgetExpenseFamiliesForBook(query.bookId);
    return BudgetWindowResolver.resolve(
      query: query,
      periods: _budgetPeriods,
      expenseFamilies: families,
      plansV2: _budgetPlansV2,
      revisionsV2: _budgetPlanRevisionsV2,
      overridesV2: _budgetCycleOverridesV2,
      fixedOccurrencesV2:
          _budgetFixedOccurrencesV2.map((item) => item.occurrence),
    );
  }

  List<BudgetSpecialTrackingResult> budgetSpecialTrackings({
    required int bookId,
    required DateTime windowStartInclusive,
    required DateTime windowEndExclusive,
    DateTime? asOf,
    DateTime? knowledgeCutoff,
    bool includeArchived = false,
  }) {
    final cutoff = knowledgeCutoff ?? DateTime.now();
    final families = _budgetExpenseFamiliesForBook(bookId);
    final rootByFamilyId = <String, TransactionEntity>{
      for (final transaction in _allTransactions)
        if (transaction.refundOf == null)
          transaction.uuid.isEmpty
              ? transaction.id.toString()
              : transaction.uuid: transaction,
    };
    final inputs = <BudgetSpecialExpenseFamilyInput>[
      for (final family in families)
        BudgetSpecialExpenseFamilyInput(
          id: family.id,
          bookId: bookId,
          currencyCode: family.currencyCode,
          attributionDate: family.attributionDate,
          createdAt: family.createdAt,
          netAmountCents: _familyNetAt(family, cutoff),
          countsInBudget: family.countsInBudget,
          categoryKey:
              family.categoryAllocations.firstOrNull?.categoryKey ?? '',
          tagIds: rootByFamilyId[family.id]?.tagIds ?? const [],
        ),
    ];
    return BudgetSpecialTrackingResolver.resolveWindow(
      windowStartInclusive: windowStartInclusive,
      windowEndExclusive: windowEndExclusive,
      bookId: bookId,
      asOf: asOf ?? DateTime.now(),
      knowledgeCutoff: cutoff,
      plans: _budgetPlansV2,
      revisions: _budgetPlanRevisionsV2,
      expenseFamilies: inputs,
      includeArchived: includeArchived,
    );
  }

  BudgetWindowResult budgetForCalendarMonth(
    DateTime month, {
    int? bookId,
    DateTime? asOf,
    DateTime? knowledgeCutoff,
  }) {
    final queryAsOf = asOf ?? DateTime.now();
    return budgetWindow(BudgetWindowQuery(
      viewKind: BudgetViewKind.calendarMonth,
      bookId: bookId ?? _currentBookId,
      referenceDate: month,
      asOf: queryAsOf,
      knowledgeCutoff: knowledgeCutoff ?? DateTime.now(),
    ));
  }

  BudgetWindowResult currentBudgetCycle({
    int? bookId,
    DateTime? now,
    DateTime? knowledgeCutoff,
  }) {
    final queryNow = now ?? DateTime.now();
    return budgetWindow(BudgetWindowQuery(
      viewKind: BudgetViewKind.cycle,
      bookId: bookId ?? _currentBookId,
      referenceDate: queryNow,
      asOf: queryNow,
      knowledgeCutoff: knowledgeCutoff ?? DateTime.now(),
    ));
  }

  /// 某年某月生效的月预算总额（当前账本口径）；没设过返回 null。
  Decimal? budgetTotalFor(int year, int month) =>
      budgetForCalendarMonth(DateTime(year, month)).plannedAmount;

  /// 现在生效的月预算总额（老调用方无感兼容）。
  Decimal? get monthlyBudget {
    final n = DateTime.now();
    return budgetTotalFor(n.year, n.month);
  }

  /// 现在生效的分类预算明细（key -> 月预算）。
  Map<String, Decimal> get categoryBudgets {
    final result = budgetForCalendarMonth(DateTime.now());
    return Map.unmodifiable({
      for (final category in result.categoryResults)
        if (category.plannedCents > 0)
          category.categoryKey: category.plannedAmount,
    });
  }

  /// 某分类 key 的月预算（未设返回 null）。
  Decimal? categoryBudgetFor(String key) => categoryBudgets[key];

  AiProviderType get aiProviderType => _aiProviderType;
  String? get deepSeekApiKey => _deepSeekApiKey;
  String? get customAiApiKey => _customAiApiKey;
  String get customAiDisplayName => _customAiDisplayName;
  String get customAiBaseUrl => _customAiBaseUrl;
  String get customAiModel => _customAiModel;
  String get reportAiModel => _reportAiModel;

  /// 用户筛选后保留的可用模型列表，空表示未获取过
  List<String> get availableModels => List.unmodifiable(_availableModels);

  /// 所有已配置服务商（API Key 不会写入该对象的持久化 JSON）。
  List<AiConfiguredProvider> get aiProviders => List.unmodifiable(_aiProviders);

  AiConfiguredProvider? aiProviderById(String? id) {
    final key = id?.trim();
    if (key == null || key.isEmpty) return null;
    for (final provider in _aiProviders) {
      if (provider.id == key) return provider;
    }
    return null;
  }

  String? get recordAiProviderId => _recordAiProviderId;
  String? get chatCurrentProviderId => _chatCurrentProviderId;
  String? get chatCurrentModel => _chatCurrentModel;

  /// 模型身份必须包含 providerId，允许不同服务商提供同名模型。
  List<AiModelOption> get aiChatModelOptions {
    final result = <AiModelOption>[];
    final seen = <String>{};
    for (final provider in _aiProviders) {
      if (!provider.hasKey) continue;
      for (final model in provider.models) {
        final option = AiModelOption(
          providerId: provider.id,
          providerLabel: provider.label,
          model: model,
        );
        if (seen.add(option.key)) result.add(option);
      }
    }
    return List.unmodifiable(result);
  }

  AiProviderType aiProviderTypeFor(AiTaskType task) => switch (task) {
        AiTaskType.recordParse => _recordAiProviderType,
        AiTaskType.chatQuery =>
          aiProviderById(_chatCurrentProviderId)?.type ?? _chatAiProviderType,
        AiTaskType.report =>
          aiProviderById(_chatCurrentProviderId)?.type ?? _chatAiProviderType,
      };

  AiRouteMode aiRouteModeFor(AiTaskType task) => switch (task) {
        AiTaskType.recordParse => _recordAiRouteMode,
        AiTaskType.chatQuery => _chatAiRouteMode,
        AiTaskType.report => _reportAiRouteMode,
      };

  AiProviderType aiResolvedProviderTypeFor(AiTaskType task) {
    if (aiRouteModeFor(task) == AiRouteMode.fixed) {
      return aiProviderTypeFor(task);
    }
    return _autoAiProviderTypeFor(task);
  }

  AiProviderType _autoAiProviderTypeFor(AiTaskType task) {
    final hasDeepSeek = _deepSeekApiKey?.trim().isNotEmpty ?? false;
    final hasCustom = _customAiApiKey?.trim().isNotEmpty ?? false;
    if (task == AiTaskType.report) {
      if (hasCustom) return AiProviderType.custom;
      if (hasDeepSeek) return AiProviderType.deepseek;
      return AiProviderType.custom;
    }
    if (hasDeepSeek) return AiProviderType.deepseek;
    if (hasCustom) return AiProviderType.custom;
    return AiProviderType.deepseek;
  }

  String aiProviderLabel(AiProviderType type) =>
      type == AiProviderType.custom ? _customAiDisplayName : type.label;

  String aiResolvedProviderLabelFor(AiTaskType task) =>
      task == AiTaskType.recordParse
          ? (aiProviderById(_recordAiProviderId)?.label ??
              aiProviderLabel(aiResolvedProviderTypeFor(task)))
          : (aiProviderById(_chatCurrentProviderId)?.label ??
              aiProviderLabel(aiResolvedProviderTypeFor(task)));

  AiEndpointType aiEndpointTypeFor(AiTaskType task) => switch (task) {
        AiTaskType.recordParse => _recordAiEndpointType,
        AiTaskType.chatQuery => _chatAiEndpointType,
        AiTaskType.report => _reportAiEndpointType,
      };

  AiReasoningEffort aiReasoningEffortFor(AiTaskType task) => switch (task) {
        AiTaskType.recordParse => _recordAiReasoningEffort,
        AiTaskType.chatQuery => _chatAiReasoningEffort,
        AiTaskType.report => _chatAiReasoningEffort,
      };

  AiProviderConfig get aiProviderConfig =>
      aiProviderConfigFor(AiTaskType.recordParse);

  AiProviderConfig aiProviderConfigFor(AiTaskType task) {
    if (task == AiTaskType.recordParse) {
      final selected = aiProviderById(_recordAiProviderId);
      if (selected != null) {
        return selected.toConfig(
          effortOverride: _recordAiReasoningEffort,
        );
      }
    }
    if (task == AiTaskType.chatQuery || task == AiTaskType.report) {
      final selected = aiProviderById(_chatCurrentProviderId) ??
          _firstUsableProvider() ??
          aiProviderById(_chatAiProviderType.storageKey);
      if (selected != null) {
        final selectedModel = _chatCurrentModel?.trim();
        return selected.toConfig(
          modelOverride: selectedModel == null || selectedModel.isEmpty
              ? selected.model
              : selectedModel,
          effortOverride: _chatAiReasoningEffort,
        );
      }
    }
    final type = aiResolvedProviderTypeFor(task);
    if (type == AiProviderType.custom) {
      return AiProviderConfig.custom(
        apiKey: _customAiApiKey ?? '',
        baseUrl: _customAiBaseUrl,
        model: task == AiTaskType.report ? _reportAiModel : _customAiModel,
        endpointType: aiEndpointTypeFor(task),
        reasoningEffort: aiReasoningEffortFor(task),
        displayName: _customAiDisplayName,
      );
    }
    return AiProviderConfig.deepSeek(
      apiKey: _deepSeekApiKey ?? '',
      displayName: AiProviderType.deepseek.label,
    );
  }

  bool get hasAiApiKey => aiProviderConfig.hasKey;
  bool get hasAnyAiApiKey =>
      (_deepSeekApiKey?.trim().isNotEmpty ?? false) ||
      (_customAiApiKey?.trim().isNotEmpty ?? false) ||
      _aiProviders.any((provider) => provider.hasKey);

  bool get recordAiMode => _recordAiMode;
  bool get aiPrivacyAccepted => _aiPrivacyAccepted;
  bool get widgetPrivacyMode => _widgetPrivacyMode;
  bool get repaymentReminderEnabled => _repaymentReminderEnabled;
  int get moneyDecimalPlaces => _moneyDecimalPlaces;
  MoneyIntegerRoundingMode get moneyIntegerRoundingMode =>
      _moneyIntegerRoundingMode;
  CategoryIconStyle get categoryIconStyle => _categoryIconStyle;
  TransactionCardDisplayMode get transactionCardDisplayMode =>
      _transactionCardDisplayMode;
  UserMessageBubbleStyle get userMessageBubbleStyle => _userMessageBubbleStyle;
  int get lastAssetViewTabIndex => _lastAssetViewTabIndex;

  // ---------------------------------------------------------------------------
  // 初始化
  // ---------------------------------------------------------------------------

  Future<void> init({bool fastStartup = false}) {
    final running = _initFuture;
    if (running != null) return running;

    // A failed first attempt may be retried by a caller-facing recovery flow.
    // Give that attempt a fresh barrier while preserving the already completed
    // Future handed to listeners of the previous attempt.
    if (_readyCompleter.isCompleted && !_isReady) {
      _readyCompleter = Completer<void>();
    }
    if (_fullyReadyCompleter.isCompleted && !_isFullyReady) {
      _fullyReadyCompleter = Completer<void>();
    }
    final future = _initInternal(fastStartup: fastStartup);
    _initFuture = future;
    return future;
  }

  Future<void> _initInternal({required bool fastStartup}) async {
    try {
      final dbPath = p.join(await getDatabasesPath(), _dbName);
      final databaseAlreadyExisted = await File(dbPath).exists();
      await _backupBeforeMigration(dbPath);
      await _backupBeforeB3A4V39Compat(dbPath);
      _db = await openDatabase(
        dbPath,
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
      await _runB3A4V39Compat(_db!);
      await _ensureTransactionIndexes(_db!);
      await _seedIfNeeded();
      await _ensureDefaultBook();
      // v13 预算搬迁失败的幂等自愈（只在首次检查时真正查表，之后有标记直接跳过）。
      await _selfHealLegacyBudgetMigration();
      if (fastStartup) {
        // The home only needs the current book, accounts, categories, budget
        // definition and this month's transactions. Keep the expensive asset,
        // report, backup and full-history maintenance out of the splash window.
        await _loadStartupSnapshot();
        _deferredAutoBackupPath = databaseAlreadyExisted ? dbPath : null;
        _deferredRefundNormalization = true;
        _deferredInitPending = true;
        _markReady();
        return;
      }

      if (databaseAlreadyExisted) await _autoPeriodicBackup(dbPath);
      await _normalizeStandaloneRefunds();
      await _convergeOpenedDatabase(notify: false);
      _markReady();
      _markFullyReady();
      notifyListeners();
    } catch (error, stackTrace) {
      _isReady = false;
      _isFullyReady = false;
      _initializationError = error;
      _initializationErrorStack = stackTrace;
      if (!_readyCompleter.isCompleted) _readyCompleter.complete();
      if (!_fullyReadyCompleter.isCompleted) _fullyReadyCompleter.complete();
      notifyListeners();
      _initFuture = null;
      rethrow;
    }
  }

  void _markReady() {
    _isReady = true;
    _initializationError = null;
    _initializationErrorStack = null;
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
  }

  void _markFullyReady() {
    _isFullyReady = true;
    _deferredInitPending = false;
    if (!_fullyReadyCompleter.isCompleted) _fullyReadyCompleter.complete();
  }

  /// Completes the non-critical half of a fast startup. The caller schedules
  /// this after the first Flutter frame so a large historical database cannot
  /// steal time from the first raster.
  Future<void> finishDeferredInitialization() {
    if (!_deferredInitPending) return fullyReady;
    final running = _deferredInitFuture;
    if (running != null) return running;
    final future = _finishDeferredInitialization();
    _deferredInitFuture = future;
    return future;
  }

  Future<void> _finishDeferredInitialization() async {
    try {
      if (!_isReady || _db == null) {
        _markFullyReady();
        return;
      }
      final backupPath = _deferredAutoBackupPath;
      _deferredAutoBackupPath = null;
      if (backupPath != null) await _autoPeriodicBackup(backupPath);
      if (_deferredRefundNormalization) {
        _deferredRefundNormalization = false;
        await _normalizeStandaloneRefunds();
      }
      await _convergeOpenedDatabase(notify: false);
      _markFullyReady();
      notifyListeners();
    } catch (error, stackTrace) {
      _initializationError = error;
      _initializationErrorStack = stackTrace;
      if (!_fullyReadyCompleter.isCompleted) _fullyReadyCompleter.complete();
      rethrow;
    }
  }

  Future<void> _loadStartupSnapshot() async {
    await _loadBooks();
    await _loadCurrentBook();
    await Future.wait([
      _loadAccounts(),
      _loadCategories(),
      _loadBudgetPeriods(),
      _loadBudgetV2(),
      _loadRecordMode(),
      _loadMoneyDisplaySettings(),
      _loadTransactionDisplayPreferences(),
    ]);
    await _loadTransactionsForStartupMonth();
  }

  Future<void> _convergeOpenedDatabase({bool notify = true}) async {
    await _loadAll(notify: false);
    await _materializeBudgetV2Occurrences();
    await applyPhysicalAssetDepreciation(notify: false);
    await _materializeRecurring();
    await _loadTransactions();
    await _persistCurrentNetWorthSnapshot(
      causes: const {NetWorthSnapshotCause.scheduledRebuild},
      notify: false,
    );
    if (notify) notifyListeners();
  }

  /// v13 预算搬迁的核心逻辑（版本迁移和启动自愈共用）：
  /// 把旧 budget 表的单一预算搬成一条「2000 年起每月循环」的预算期间。
  /// 调用方保证 budget_periods 表已存在；budget 表不存在时查询抛错由调用方兜。
  Future<void> _migrateLegacyBudgetIntoPeriods(DatabaseExecutor db) async {
    final totalRows =
        await db.query('budget', where: 'category_key IS NULL', limit: 1);
    if (totalRows.isEmpty) return;
    final total = Decimal.tryParse(totalRows.first['amount'] as String? ?? '');
    if (total == null || total <= Decimal.zero) return;
    final catRows = await db.query('budget', where: 'category_key IS NOT NULL');
    final cats = <String, String>{};
    for (final r in catRows) {
      final k = r['category_key'] as String?;
      final v = Decimal.tryParse(r['amount'] as String? ?? '');
      if (k != null && k.isNotEmpty && v != null && v > Decimal.zero) {
        cats[k] = v.toString();
      }
    }
    await db.insert('budget_periods', {
      'book_id': null,
      'start_ms': DateTime(2000, 1, 1).millisecondsSinceEpoch,
      'end_ms': null,
      'recurring_monthly': 1,
      'total': total.toString(),
      'category_budgets': cats.isEmpty ? '' : jsonEncode(cats),
      'monthly_income': '',
      'fixed_expenses': '',
      'created_ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static const _kLegacyBudgetMigrationCheckedKey =
      'v13_budget_migration_checked';

  /// v13 预算搬迁失败的幂等自愈：迁移时那段 try/catch 一旦吞了异常，
  /// 老预算就永远搬不过来。启动收尾处补一次检查——budget_periods 还是空
  /// 且旧 budget 表有数据时重跑搬迁；结果无论如何写一个「已检查」标记，
  /// 避免用户日后删光预算期间时把老预算又复活出来。失败不拦启动、下次再试。
  Future<void> _selfHealLegacyBudgetMigration() async {
    try {
      final db = _db;
      if (db == null) return;
      final flag = await db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: [_kLegacyBudgetMigrationCheckedKey],
        limit: 1,
      );
      if (flag.isNotEmpty) return;
      final existing = await db.query('budget_periods', limit: 1);
      if (existing.isEmpty) {
        final legacyTable = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'budget'",
        );
        if (legacyTable.isNotEmpty) {
          await _migrateLegacyBudgetIntoPeriods(db);
        }
      }
      await db.insert(
        'app_settings',
        {'key': _kLegacyBudgetMigrationCheckedKey, 'value': '1'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      // 自愈只是兜底，失败不拦启动。
    }
  }

  /// 每周静默本地备份一次（qingji.db.auto-日期.bak，最多保留 3 份）。
  /// 不依赖任何设置表——看最近一份自动备份的日期决定要不要备，
  /// 在 openDatabase 之前做，复制的是磁盘上完整落定的库文件。
  Future<void> _autoPeriodicBackup(String dbPath) async {
    try {
      final f = File(dbPath);
      if (!await f.exists()) return; // 新装机没得备
      final dir = f.parent;
      final autos = <File>[];
      await for (final e in dir.list()) {
        if (e is File &&
            p.basename(e.path).startsWith('$_dbName.auto-') &&
            e.path.endsWith('.bak')) {
          autos.add(e);
        }
      }
      autos.sort((a, b) => b.path.compareTo(a.path)); // 文件名含日期，倒序=最新在前
      if (autos.isNotEmpty) {
        final newest = await autos.first.lastModified();
        if (DateTime.now().difference(newest).inDays < 7) {
          return;
        }
      }
      final now = DateTime.now();
      final stamp = '${now.year}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}';
      await _createConsistentDatabaseCopy(
        dbPath,
        p.join(dir.path, '$_dbName.auto-$stamp.bak'),
        sourceDb: _db,
      );
      await _pruneLocalBackups(dir);
    } catch (_) {
      // 备份失败不拦启动。
    }
  }

  /// 本机现有的备份文件（自动 / 手动 / 迁移前等），最新在前。给「备份/恢复」页展示用。
  Future<List<File>> localBackupFiles() async {
    final dbPath = p.join(await getDatabasesPath(), _dbName);
    final dir = File(dbPath).parent;
    final out = <File>[];
    try {
      await for (final e in dir.list()) {
        if (e is File &&
            p.basename(e.path).startsWith('$_dbName.') &&
            e.path.endsWith('.bak')) {
          out.add(e);
        }
      }
      final times = <String, DateTime>{};
      for (final f in out) {
        times[f.path] = await f.lastModified();
      }
      out.sort((a, b) => times[b.path]!.compareTo(times[a.path]!));
    } catch (_) {}
    return out;
  }

  /// 用户手动点击「立即备份」时，马上在本机生成一份数据库备份。
  Future<File?> createLocalBackupNow() async {
    try {
      final dbPath = p.join(await getDatabasesPath(), _dbName);
      final f = File(dbPath);
      if (!await f.exists()) return null;
      final now = DateTime.now();
      final stamp = '${now.year}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}-'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}'
          '${now.second.toString().padLeft(2, '0')}';
      final out = File(p.join(f.parent.path, '$_dbName.manual-$stamp.bak'));
      final copied = await _createConsistentDatabaseCopy(
        dbPath,
        out.path,
        sourceDb: _db,
      );
      await _pruneLocalBackups(f.parent);
      return copied;
    } catch (_) {
      return null;
    }
  }

  /// DB 要升版本时，先把旧库原样复制一份（qingji.db.pre-v旧版本.bak）再迁移。
  /// 迁移代码万一有 bug，用户的真实账本还有救——「备份/恢复」页选这个文件即可。
  /// 版本没变或新装机则什么都不做；备份失败也不拦启动。
  Future<void> _backupBeforeMigration(String dbPath) async {
    try {
      final f = File(dbPath);
      if (!await f.exists()) return;
      final probe = await openReadOnlyDatabase(dbPath);
      final int old;
      try {
        // 库文件损坏时这句会抛错；必须 finally 关掉 probe，
        // 否则泄漏的句柄会挡住之后「备份恢复」对库文件的改名/替换。
        final rows = await probe.rawQuery('PRAGMA user_version');
        old = (rows.first.values.first as int?) ?? 0;
      } finally {
        await probe.close();
      }
      if (old <= 0 || old >= _dbVersion) return;
      await _createConsistentDatabaseCopy(
        dbPath,
        '$dbPath.pre-v$old.bak',
      );
      await _pruneLocalBackups(f.parent);
    } catch (_) {
      // 备份是兜底，不能因为它失败（磁盘满等）挡住正常启动。
    }
  }

  /// Some development builds already used user_version 39 before every B3/A4
  /// column and index had landed. Preserve that exact database before applying
  /// the idempotent same-version compatibility repair.
  Future<void> _backupBeforeB3A4V39Compat(String dbPath) async {
    Database? probe;
    try {
      final source = File(dbPath);
      if (!await source.exists()) return;
      probe = await openReadOnlyDatabase(dbPath);
      final version = Sqflite.firstIntValue(
            await probe.rawQuery('PRAGMA user_version'),
          ) ??
          0;
      if (version != 39 || !await _needsB3A4V39Compat(probe)) return;
      await probe.close();
      probe = null;
      final destination = File('$dbPath.pre-v39-compat.bak');
      if (await destination.exists()) return;
      final pending = File('${destination.path}.pending');
      if (await pending.exists()) await pending.delete();
      await _createConsistentDatabaseCopy(
        dbPath,
        pending.path,
      );
      if (await destination.exists()) {
        await pending.delete();
      } else {
        await pending.rename(destination.path);
      }
    } catch (_) {
      // Like normal migration backups, failure here must not strand startup.
    } finally {
      await probe?.close();
    }
  }

  Future<void> _pruneLocalBackups(Directory dir, {int keep = 3}) async {
    if (keep <= 0) return;
    final manualFiles = <File>[];
    final autoFiles = <File>[];
    try {
      await for (final e in dir.list()) {
        if (e is File &&
            p.basename(e.path).startsWith('$_dbName.') &&
            e.path.endsWith('.bak')) {
          final name = p.basename(e.path);
          if (name.startsWith('$_dbName.manual-')) {
            manualFiles.add(e);
          } else if (name.startsWith('$_dbName.auto-')) {
            autoFiles.add(e);
          }
        }
      }
      final times = <String, DateTime>{};
      for (final f in [...manualFiles, ...autoFiles]) {
        times[f.path] = await f.lastModified();
      }
      Future<void> pruneBucket(List<File> files) async {
        files.sort((a, b) => times[b.path]!.compareTo(times[a.path]!));
        for (final old in files.skip(keep)) {
          try {
            await old.delete();
          } catch (_) {}
        }
      }

      await pruneBucket(manualFiles);
      await pruneBucket(autoFiles);
    } catch (_) {
      // 清理失败不影响启动、备份或恢复。
    }
  }

  Future<File> _createConsistentDatabaseCopy(
    String sourcePath,
    String destinationPath, {
    Database? sourceDb,
    bool forceCheckpointCopyForTest = false,
  }) async {
    final destination = File(destinationPath);
    await destination.parent.create(recursive: true);
    if (await destination.exists()) await destination.delete();

    Database? ownedDb;
    final db = sourceDb ??
        (ownedDb = await openDatabase(
          sourcePath,
          singleInstance: false,
        ));
    try {
      if (forceCheckpointCopyForTest) {
        await _copyDatabaseAfterCheckpoint(
          db,
          sourcePath,
          destinationPath,
        );
      } else {
        final escaped = destinationPath.replaceAll("'", "''");
        try {
          await db.execute("VACUUM INTO '$escaped'");
        } catch (error) {
          if (!_isVacuumIntoUnsupported(error)) rethrow;
          if (await destination.exists()) await destination.delete();
          await _copyDatabaseAfterCheckpoint(
            db,
            sourcePath,
            destinationPath,
          );
        }
      }
    } finally {
      await ownedDb?.close();
    }

    final check = await openReadOnlyDatabase(destinationPath);
    try {
      final rows = await check.rawQuery('PRAGMA quick_check');
      final result = rows.isEmpty ? '' : rows.first.values.first.toString();
      if (result.toLowerCase() != 'ok') {
        throw StateError('database snapshot integrity check failed: $result');
      }
    } finally {
      await check.close();
    }
    return destination;
  }

  static bool _isVacuumIntoUnsupported(Object error) {
    if (error is! DatabaseException) return false;
    final message = error.toString().toLowerCase();
    return message.contains('vacuum') &&
        message.contains('into') &&
        message.contains('syntax error');
  }

  static Future<void> _copyDatabaseAfterCheckpoint(
    Database db,
    String sourcePath,
    String destinationPath,
  ) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('database snapshot source does not exist');
    }

    // VACUUM INTO arrived in SQLite 3.27 and is unavailable on some devices
    // supported by minSdk 24. Flush WAL first, then hold an exclusive database
    // transaction for the whole file copy so no app write can race the copy.
    for (var attempt = 0; attempt < 3; attempt++) {
      final checkpoint = await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      final busyValue = checkpoint.isEmpty
          ? 1
          : checkpoint.first['busy'] ?? checkpoint.first.values.first;
      final busy = busyValue is int
          ? busyValue
          : int.tryParse(busyValue.toString()) ?? 1;
      if (busy != 0) continue;

      var racedWithWriter = false;
      await db.transaction<void>((txn) async {
        await txn.rawQuery('SELECT 1');
        final wal = File('$sourcePath-wal');
        if (await wal.exists() && await wal.length() > 0) {
          racedWithWriter = true;
          return;
        }
        await source.copy(destinationPath);
      }, exclusive: true);
      if (!racedWithWriter) return;

      final partial = File(destinationPath);
      if (await partial.exists()) await partial.delete();
    }
    throw StateError('database remained busy while creating snapshot');
  }

  @visibleForTesting
  Future<File> createCheckpointDatabaseCopyForTest(
    String destinationPath,
  ) async {
    final db = _db;
    if (db == null) throw StateError('repository is not initialized');
    final sourcePath = p.join(await getDatabasesPath(), _dbName);
    return _createConsistentDatabaseCopy(
      sourcePath,
      destinationPath,
      sourceDb: db,
      forceCheckpointCopyForTest: true,
    );
  }

  /// 测试用：关掉底层数据库连接（不然临时目录删不掉）。
  @visibleForTesting
  Future<void> closeForTest() async {
    await _db?.close();
    _db = null;
  }

  /// 测试用：暴露内部 DB 实例（用于测试需要绕过 repo API 直接插数据的场景，
  /// 如外币账户——真实 app 还不支持新增，但老数据可能有）。
  @visibleForTesting
  Database get debugDb => _db!;

  /// 测试用：重新加载账户列表（插入后需要调用）。
  @visibleForTesting
  Future<void> reloadForTest() async {
    await _loadAccounts();
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE accounts (
        id                    INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid                  TEXT NOT NULL DEFAULT '',
        name                  TEXT NOT NULL,
        currency_code         TEXT NOT NULL DEFAULT 'CNY',
        type                  TEXT NOT NULL DEFAULT 'cash',
        opening_balance       TEXT NOT NULL DEFAULT '0',
        include_in_net_worth  INTEGER NOT NULL DEFAULT 1,
        institution           TEXT NOT NULL DEFAULT '',
        sort_order            INTEGER NOT NULL DEFAULT 0,
        is_deleted            INTEGER NOT NULL DEFAULT 0,
        deleted_at_ms         INTEGER,
        created_ms            INTEGER NOT NULL DEFAULT 0,
        updated_ms            INTEGER NOT NULL DEFAULT 0,
        opening_balance_effective_ms INTEGER,
        opening_balance_sequence INTEGER NOT NULL DEFAULT 0,
        opening_balance_quality TEXT NOT NULL DEFAULT 'legacy_unknown',
        status                TEXT NOT NULL DEFAULT 'active',
        archived_ms           INTEGER,
        last_verified_ms      INTEGER,
        verification_interval_days INTEGER,
        balance_mode          TEXT NOT NULL DEFAULT 'legacy_hybrid'
      )
    ''');
    await _ensureAccountCheckpointTables(db);
    await _ensureNetWorthVerifiedCheckpointTables(db);

    await db.execute('''
      CREATE TABLE categories (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        key       TEXT NOT NULL UNIQUE,
        name_zh   TEXT NOT NULL,
        name_en   TEXT NOT NULL,
        kind      TEXT NOT NULL,
        parent_id INTEGER,
        hidden    INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE books (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        name             TEXT NOT NULL,
        icon             TEXT NOT NULL DEFAULT '📒',
        cover            TEXT NOT NULL DEFAULT '',
        remark           TEXT NOT NULL DEFAULT '',
        sort_order       INTEGER NOT NULL DEFAULT 0,
        created_ms       INTEGER NOT NULL DEFAULT 0,
        starred          INTEGER NOT NULL DEFAULT 0,
        include_in_total INTEGER NOT NULL DEFAULT 1,
        uuid             TEXT NOT NULL DEFAULT '',
        updated_ms       INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.insert('books', {
      'name': '总账本',
      'icon': '📒',
      'sort_order': 0,
      'created_ms': DateTime.now().millisecondsSinceEpoch,
      'uuid': _newUuid(),
      'updated_ms': DateTime.now().millisecondsSinceEpoch,
    });

    await db.execute('''
      CREATE TABLE transactions (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id         INTEGER,
        kind            TEXT NOT NULL,
        amount          TEXT NOT NULL,
        currency_code   TEXT NOT NULL DEFAULT 'CNY',
        category_id     INTEGER REFERENCES categories(id),
        account_id      INTEGER REFERENCES accounts(id),
        to_account_id   INTEGER REFERENCES accounts(id),
        note            TEXT NOT NULL DEFAULT '',
        date_ms         INTEGER NOT NULL,
        time_precision  TEXT NOT NULL DEFAULT 'legacy_unknown',
        tags            TEXT NOT NULL DEFAULT '',
        reimbursable    INTEGER NOT NULL DEFAULT 0,
        image_path      TEXT NOT NULL DEFAULT '',
        recurring_rule_id INTEGER,
        excluded        INTEGER NOT NULL DEFAULT 0,
        uuid            TEXT NOT NULL DEFAULT '',
        updated_ms      INTEGER NOT NULL DEFAULT 0,
        refund_of       INTEGER,
        created_ms      INTEGER NOT NULL DEFAULT 0,
        settled_ms      INTEGER,
        settlement_quality TEXT NOT NULL DEFAULT 'unknown',
        settlement_account_id INTEGER,
        settlement_account_quality TEXT NOT NULL DEFAULT 'unknown',
        event_type      TEXT NOT NULL DEFAULT 'legacy_adjustment',
        order_no        TEXT NOT NULL DEFAULT ''
      )
    ''');
    await _ensureTransactionIndexes(db);

    await db.execute('''
      CREATE TABLE savings_goals (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid          TEXT NOT NULL UNIQUE,
        name          TEXT NOT NULL,
        emoji         TEXT NOT NULL DEFAULT '🐷',
        target_amount TEXT NOT NULL DEFAULT '0',
        saved_amount  TEXT NOT NULL DEFAULT '0',
        created_ms    INTEGER NOT NULL DEFAULT 0,
        updated_ms    INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE tags (
        id    INTEGER PRIMARY KEY AUTOINCREMENT,
        name  TEXT NOT NULL,
        color INTEGER NOT NULL DEFAULT 4286351771
      )
    ''');

    await db.execute('''
      CREATE TABLE budget (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        category_key TEXT,
        amount       TEXT NOT NULL
      )
    ''');

    await db.execute(_createBudgetPeriodsSql);
    await _ensureBudgetV2Tables(db);

    await db.execute('''
      CREATE TABLE app_settings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE chat_messages (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        role       TEXT NOT NULL,
        text       TEXT NOT NULL DEFAULT '',
        question   TEXT NOT NULL DEFAULT '',
        created_ms INTEGER NOT NULL
      )
    ''');

    await db.execute(_createReportsSql);
    await _ensureAssetTables(db);
    await _ensureLiabilityTables(db);

    await db.execute('''
      CREATE TABLE category_memory (
        phrase       TEXT NOT NULL,
        kind         TEXT NOT NULL,
        category_key TEXT NOT NULL,
        updated_ms   INTEGER NOT NULL,
        PRIMARY KEY (phrase, kind)
      )
    ''');

    await db.execute('''
      CREATE TABLE recurring_rules (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id     INTEGER,
        kind        TEXT NOT NULL,
        amount      TEXT NOT NULL,
        category_id INTEGER,
        account_id  INTEGER,
        to_account_id INTEGER,
        note        TEXT NOT NULL DEFAULT '',
        period      TEXT NOT NULL,
        start_date_ms INTEGER NOT NULL DEFAULT 0,
        next_due_ms INTEGER NOT NULL,
        enabled     INTEGER NOT NULL DEFAULT 1,
        anchor_day  INTEGER NOT NULL DEFAULT 0,
        end_date_ms INTEGER,
        total_count INTEGER,
        generated_count INTEGER NOT NULL DEFAULT 0,
        created_ms  INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await _ensureRecurringOccurrences(db);
    await _ensureAutoRecordOccurrences(db);
    await _ensureReportJobs(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE budget ADD COLUMN category_key TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_settings (
          key   TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS books (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          name       TEXT NOT NULL,
          icon       TEXT NOT NULL DEFAULT '📒',
          sort_order INTEGER NOT NULL DEFAULT 0,
          created_ms INTEGER NOT NULL DEFAULT 0
        )
      ''');
      final defaultBookId = await db.insert('books', {
        'name': '总账本',
        'icon': '📒',
        'sort_order': 0,
        'created_ms': DateTime.now().millisecondsSinceEpoch,
      });
      try {
        await db.execute('ALTER TABLE transactions ADD COLUMN book_id INTEGER');
      } catch (_) {}
      await db.execute(
          'UPDATE transactions SET book_id = $defaultBookId WHERE book_id IS NULL');
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS savings_goals (
          id            INTEGER PRIMARY KEY AUTOINCREMENT,
          name          TEXT NOT NULL,
          emoji         TEXT NOT NULL DEFAULT '🐷',
          target_amount TEXT NOT NULL DEFAULT '0',
          saved_amount  TEXT NOT NULL DEFAULT '0',
          created_ms    INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS tags (
          id    INTEGER PRIMARY KEY AUTOINCREMENT,
          name  TEXT NOT NULL,
          color INTEGER NOT NULL DEFAULT 4286351771
        )
      ''');
      try {
        await db.execute(
            "ALTER TABLE transactions ADD COLUMN tags TEXT NOT NULL DEFAULT ''");
      } catch (_) {}
    }
    if (oldVersion < 6) {
      try {
        try {
          await db
              .execute('ALTER TABLE categories ADD COLUMN parent_id INTEGER');
        } catch (_) {}
        await _applyCategoryTree(db);
      } catch (_) {}
    }
    if (oldVersion < 7) {
      try {
        await db.execute(
            'ALTER TABLE transactions ADD COLUMN reimbursable INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
    }
    if (oldVersion < 8) {
      try {
        await db.execute(
            "ALTER TABLE transactions ADD COLUMN image_path TEXT NOT NULL DEFAULT ''");
      } catch (_) {}
    }
    if (oldVersion < 9) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS chat_messages (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          role       TEXT NOT NULL,
          text       TEXT NOT NULL DEFAULT '',
          question   TEXT NOT NULL DEFAULT '',
          created_ms INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 10) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS category_memory (
          phrase       TEXT NOT NULL,
          kind         TEXT NOT NULL,
          category_key TEXT NOT NULL,
          updated_ms   INTEGER NOT NULL,
          PRIMARY KEY (phrase, kind)
        )
      ''');
    }
    if (oldVersion < 11) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS recurring_rules (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          book_id     INTEGER,
          kind        TEXT NOT NULL,
          amount      TEXT NOT NULL,
          category_id INTEGER,
          account_id  INTEGER,
          to_account_id INTEGER,
          note        TEXT NOT NULL DEFAULT '',
          period      TEXT NOT NULL,
          start_date_ms INTEGER NOT NULL DEFAULT 0,
          next_due_ms INTEGER NOT NULL,
          enabled     INTEGER NOT NULL DEFAULT 1,
          anchor_day  INTEGER NOT NULL DEFAULT 0,
          end_date_ms INTEGER,
          total_count INTEGER,
          generated_count INTEGER NOT NULL DEFAULT 0,
          created_ms  INTEGER NOT NULL DEFAULT 0
        )
      ''');
    }
    if (oldVersion < 12) {
      // 账本加星 + 是否计入总账本（默认计入）。
      try {
        await db.execute(
            'ALTER TABLE books ADD COLUMN starred INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute(
            'ALTER TABLE books ADD COLUMN include_in_total INTEGER NOT NULL DEFAULT 1');
      } catch (_) {}
    }
    if (oldVersion < 13) {
      // 预算改「预算期间」模型：阶段性预算，历史月显示当时生效的那份。
      await db.execute(_createBudgetPeriodsSql);
      // 老的单一预算自动搬成一条「从很久以前开始的每月循环期间」，
      // 行为与之前完全一致；旧 budget 表保留不动（只加不删）。
      // 搬迁失败不拦迁移，init 收尾处还有一次幂等自愈兜底。
      try {
        await _migrateLegacyBudgetIntoPeriods(db);
      } catch (_) {}
    }
    if (oldVersion < 14) {
      // 账本封面图（模板成品插画的资源路径）。
      try {
        await db.execute(
            "ALTER TABLE books ADD COLUMN cover TEXT NOT NULL DEFAULT ''");
      } catch (_) {}
    }
    if (oldVersion < 15) {
      // 「不计入收支」：帮人代付等不想进统计/预算的账（记录仍在列表里）。
      try {
        await db.execute(
            'ALTER TABLE transactions ADD COLUMN excluded INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
    }
    if (oldVersion < 16) {
      // ① 分类可隐藏：删除保护的出路——有历史账单的分类建议隐藏/合并，不硬删。
      try {
        await db.execute(
            'ALTER TABLE categories ADD COLUMN hidden INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
      // ② 多人共享账本的地基：行级 uuid + 变更时间戳。现在先落库并回填，
      //    以后接后端同步时就不用再全表迁移（越晚加越疼）。
      for (final table in ['transactions', 'books']) {
        try {
          await db.execute(
              "ALTER TABLE $table ADD COLUMN uuid TEXT NOT NULL DEFAULT ''");
        } catch (_) {}
        try {
          await db.execute(
              'ALTER TABLE $table ADD COLUMN updated_ms INTEGER NOT NULL DEFAULT 0');
        } catch (_) {}
        // 存量行回填：uuid 用 SQLite 自带 randomblob，无需三方库。
        await db.execute(
            "UPDATE $table SET uuid = lower(hex(randomblob(16))) WHERE uuid = ''");
        await db.execute(
            'UPDATE $table SET updated_ms = ? WHERE updated_ms = 0',
            [DateTime.now().millisecondsSinceEpoch]);
      }
    }
    if (oldVersion < 17) {
      // 附着式退款：退款行挂到原账单（refund_of=原id），不再作为独立条目
      // 出现在时间线里。老的独立冲账行 refund_of 保持 NULL，仍按旧样显示。
      try {
        await db
            .execute('ALTER TABLE transactions ADD COLUMN refund_of INTEGER');
      } catch (_) {}
    }
    if (oldVersion < 18) {
      // Phase A 分类大改：重跑分类树（幂等 upsert）——新分类插入、改名/重挂父类
      // 更新，**绝不动 transactions**，历史账单靠 category_id 不变、分类不丢。
      await _applyCategoryTree(db);
    }
    if (oldVersion < 19) {
      // 退款日期修复：早期版本把退款/报销冲减行记成「记账当天」而非原订单日期，
      // 导致跨月退款把当月支出算错、表头合计与列表净额对不上。
      // ① 把已挂账的退款行日期改回原订单日期；
      await db.execute('''
        UPDATE transactions
        SET date_ms = (SELECT o.date_ms FROM transactions o
                       WHERE o.id = transactions.refund_of)
        WHERE refund_of IS NOT NULL
          AND refund_of IN (SELECT id FROM transactions)
      ''');
      // ② 删除「孤儿退款」（原订单已不存在）——它们是隐藏的幽灵负数，
      //    会让合计凭空少一截、AI 无中生有。删掉即可（退款本就无所依附）。
      await db.execute('''
        DELETE FROM transactions
        WHERE refund_of IS NOT NULL
          AND refund_of NOT IN (SELECT id FROM transactions)
      ''');
    }
    if (oldVersion < 20) {
      // 账本加「备注」列（抽屉账本行放大后显示在名称下方）。
      try {
        await db.execute(
            "ALTER TABLE books ADD COLUMN remark TEXT NOT NULL DEFAULT ''");
      } catch (_) {}
    }
    if (oldVersion < 21) {
      // 账户软删除：保留历史交易 join 到旧账户名，避免删除账户后历史展示空掉。
      try {
        await db.execute(
            'ALTER TABLE accounts ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
      try {
        await db
            .execute('ALTER TABLE accounts ADD COLUMN deleted_at_ms INTEGER');
      } catch (_) {}
    }
    if (oldVersion < 22) {
      await db.execute(_createReportsSql);
    }
    if (oldVersion < 23) {
      await db.execute(_createReportsSql);
      try {
        await db.execute(
            'ALTER TABLE reports ADD COLUMN pinned_ms INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
    }
    if (oldVersion < 24) {
      try {
        await db.execute(
            "ALTER TABLE accounts ADD COLUMN type TEXT NOT NULL DEFAULT 'cash'");
      } catch (_) {}
      try {
        await db.execute(
            "ALTER TABLE accounts ADD COLUMN opening_balance TEXT NOT NULL DEFAULT '0'");
      } catch (_) {}
      try {
        await db.execute(
            'ALTER TABLE accounts ADD COLUMN include_in_net_worth INTEGER NOT NULL DEFAULT 1');
      } catch (_) {}
      try {
        await db.execute(
            "ALTER TABLE accounts ADD COLUMN institution TEXT NOT NULL DEFAULT ''");
      } catch (_) {}
      try {
        await db.execute(
            'ALTER TABLE accounts ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
    }
    if (oldVersion < 25) {
      try {
        await db.execute(
            'ALTER TABLE recurring_rules ADD COLUMN anchor_day INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute('''
          UPDATE recurring_rules
          SET anchor_day = CAST(strftime('%d', next_due_ms / 1000, 'unixepoch', 'localtime') AS INTEGER)
          WHERE anchor_day = 0
        ''');
      } catch (_) {}
    }
    if (oldVersion < 26) {
      await _ensureAssetTables(db);
    }
    if (oldVersion < 27) {
      await _ensureAssetTables(db);
    }
    if (oldVersion < 28) {
      await _ensureLiabilityTables(db);
    }
    if (oldVersion < 29) {
      await _ensurePhysicalAssetAdvancedColumns(db);
    }
    if (oldVersion < 30) {
      await _ensureRecurringEndColumns(db);
    }
    if (oldVersion < 31) {
      await _ensureRecurringOccurrences(db);
      await _ensureNetWorthSnapshotScope(db);
    }
    if (oldVersion < 32) {
      await _ensureAutoRecordOccurrences(db);
      await _ensureReportJobs(db);
    }
    if (oldVersion < 33) {
      await _migrateAssetStateV33(db);
    }
    if (oldVersion < 34) {
      await _migrateTransactionSettlementV34(db);
    }
    if (oldVersion < 35) {
      await _migrateAssetAllocationsV35(db);
    }
    if (oldVersion < 36) {
      await _migrateNetWorthSnapshotsV36(db);
    }
    if (oldVersion < 37) {
      await _migrateAccountCheckpointsV37(db);
    }
    if (oldVersion < 38) {
      await _ensureBudgetV2Tables(db);
    }
    if (oldVersion < 39) {
      await _ensureB3A4V39Compat(db);
    }
    if (oldVersion < 40) {
      final transactionColumns = await _columnNamesFor(db, 'transactions');
      if (!transactionColumns.contains('time_precision')) {
        await db.execute(
          "ALTER TABLE transactions ADD COLUMN time_precision TEXT NOT NULL DEFAULT 'legacy_unknown'",
        );
      }
    }
    if (oldVersion < 41) {
      // v41：transactions 加 order_no（商户订单号）。只服务账单导入时
      // 退款跨批/跨月挂回原单的配对，不进任何统计查询。
      final v41Columns = await _columnNamesFor(db, 'transactions');
      if (!v41Columns.contains('order_no')) {
        await db.execute(
          "ALTER TABLE transactions ADD COLUMN order_no TEXT NOT NULL DEFAULT ''",
        );
      }
    }
    if (oldVersion < 42) {
      // v42（资产 A 批）：liability_profiles 加信用卡账期两列 + 借入对象。
      // statement_day = 账单日(1-31)；credit_limit = 额度（Decimal 字符串）；
      // counterparty = 借入对象姓名（personalBorrow 用）。幂等：老库若已被
      // _ensureLiabilityTables 用新版建表 SQL 建出全列，这里逐列检查后跳过。
      final v42Columns = await _columnNamesFor(db, 'liability_profiles');
      if (v42Columns.isNotEmpty) {
        if (!v42Columns.contains('statement_day')) {
          await db.execute(
            'ALTER TABLE liability_profiles ADD COLUMN statement_day INTEGER',
          );
        }
        if (!v42Columns.contains('credit_limit')) {
          await db.execute(
            'ALTER TABLE liability_profiles ADD COLUMN credit_limit TEXT',
          );
        }
        if (!v42Columns.contains('counterparty')) {
          await db.execute(
            "ALTER TABLE liability_profiles ADD COLUMN counterparty TEXT NOT NULL DEFAULT ''",
          );
        }
      } else {
        // 极老库还没有 liability_profiles 表：直接按新版全列建。
        await _ensureLiabilityTables(db);
      }
      // v42（资产 A 批·A3）：recurring_rules 加 to_account_id，周期记账
      // 支持转账（房贷向导的每月自动还款）。同样逐列检查保持幂等。
      final v42RecurringColumns = await _columnNamesFor(db, 'recurring_rules');
      if (v42RecurringColumns.isNotEmpty &&
          !v42RecurringColumns.contains('to_account_id')) {
        await db.execute(
          'ALTER TABLE recurring_rules ADD COLUMN to_account_id INTEGER',
        );
      }
    }
    if (oldVersion < 43) {
      // v43（A5 负债单一真相源）：accounts 加 balance_mode。
      //
      // 默认值必须是 'legacy_hybrid' —— 老库升级后净资产三项逐分不变，
      // 这是等价迁移的前提。切 ledger 只能由用户走迁移流程显式触发，
      // 绝不能因为升级而静默发生（口径翻转会让净资产悄悄变化）。
      //
      // 挂 accounts 而非 liability_profiles 是有意的：模式规定的是「余额」
      // 怎么解释，而余额是账户的属性；且 deleteLiabilityProfileForAccount
      // 存在，模式挂档案上会被删档案带走、已迁移账户静默退回旧解释。
      // 详见 core/account/liability_balance_mode.dart 的类文档。
      final v43Columns = await _columnNamesFor(db, 'accounts');
      if (v43Columns.isNotEmpty && !v43Columns.contains('balance_mode')) {
        await db.execute(
          "ALTER TABLE accounts ADD COLUMN balance_mode TEXT NOT NULL DEFAULT 'legacy_hybrid'",
        );
      }
    }
    await _ensureTransactionIndexes(db);
  }

  static Future<bool> _tableExists(
    DatabaseExecutor db,
    String table,
  ) async {
    final rows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      [table],
    );
    return rows.isNotEmpty;
  }

  static Future<Set<String>> _columnNamesFor(
    DatabaseExecutor db,
    String table,
  ) async {
    if (!await _tableExists(db, table)) return const <String>{};
    return (await db.rawQuery('PRAGMA table_info($table)'))
        .map((row) => row['name'])
        .whereType<String>()
        .toSet();
  }

  static Future<bool> _indexMatches(
    DatabaseExecutor db, {
    required String table,
    required String name,
    required List<String> columns,
    required bool unique,
    bool partial = false,
    String? wherePredicate,
  }) async {
    if (!await _tableExists(db, table)) return false;
    final indexes = await db.rawQuery("PRAGMA index_list('$table')");
    final row = indexes.where((item) => item['name'] == name).firstOrNull;
    if (row == null ||
        ((row['unique'] as int? ?? 0) == 1) != unique ||
        ((row['partial'] as int? ?? 0) == 1) != partial) {
      return false;
    }
    final actual = (await db.rawQuery("PRAGMA index_info('$name')"))
        .map((item) => item['name'])
        .whereType<String>()
        .toList(growable: false);
    if (!listEquals(actual, columns)) return false;
    if (wherePredicate == null) return true;
    final definitions = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = ? LIMIT 1",
      [name],
    );
    if (definitions.isEmpty) return false;
    String normalize(String value) => value
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r';$'), '')
        .toLowerCase();
    final definition = normalize(definitions.single['sql'] as String? ?? '');
    final whereOffset = definition.indexOf(' where ');
    if (whereOffset < 0) return false;
    final actualPredicate = definition.substring(whereOffset + 7).trim();
    return actualPredicate == normalize(wherePredicate);
  }

  static Future<void> _ensureNamedIndex(
    DatabaseExecutor db, {
    required String table,
    required String name,
    required List<String> columns,
    required bool unique,
    bool partial = false,
    String? wherePredicate,
    required String createSql,
  }) async {
    if (await _indexMatches(
      db,
      table: table,
      name: name,
      columns: columns,
      unique: unique,
      partial: partial,
      wherePredicate: wherePredicate,
    )) {
      return;
    }
    await db.execute('DROP INDEX IF EXISTS $name');
    await db.execute(createSql);
  }

  static Future<bool> _needsB3A4V39Compat(DatabaseExecutor db) async {
    final planColumns = await _columnNamesFor(db, 'budget_plans');
    final assetColumns = await _columnNamesFor(db, 'physical_assets');
    final goalColumns = await _columnNamesFor(db, 'savings_goals');
    final usageColumns = await _columnNamesFor(db, 'asset_usage_events');
    if (!planColumns.contains('expense_scope_json') ||
        !assetColumns.containsAll(
          const {'usage_tracking_enabled', 'savings_goal_id'},
        ) ||
        !goalColumns.containsAll(const {'uuid', 'updated_ms'}) ||
        !usageColumns.containsAll(
          const {
            'id',
            'uuid',
            'asset_id',
            'count_delta',
            'reversal_of',
            'occurred_ms',
            'note',
            'created_ms',
            'updated_ms',
          },
        )) {
      return true;
    }
    final incompleteGoalCount = Sqflite.firstIntValue(await db.rawQuery('''
          SELECT COUNT(*)
          FROM savings_goals
          WHERE trim(uuid) = '' OR updated_ms = 0
        ''')) ?? 0;
    final duplicateGoalUuidCount = Sqflite.firstIntValue(await db.rawQuery('''
          SELECT COUNT(*)
          FROM (
            SELECT uuid
            FROM savings_goals
            WHERE trim(uuid) <> ''
            GROUP BY uuid
            HAVING COUNT(*) > 1
          )
        ''')) ?? 0;
    if (incompleteGoalCount > 0 || duplicateGoalUuidCount > 0) return true;
    final usageInfo = await db.rawQuery(
      'PRAGMA table_info(asset_usage_events)',
    );
    if (!usageInfo.any(
      (row) => row['name'] == 'id' && (row['pk'] as int? ?? 0) == 1,
    )) {
      return true;
    }
    final incompleteUsageCount = Sqflite.firstIntValue(await db.rawQuery('''
          SELECT COUNT(*)
          FROM asset_usage_events
          WHERE trim(uuid) = '' OR updated_ms = 0
        ''')) ?? 0;
    final duplicateUsageUuidCount = Sqflite.firstIntValue(await db.rawQuery('''
          SELECT COUNT(*)
          FROM (
            SELECT uuid
            FROM asset_usage_events
            WHERE trim(uuid) <> ''
            GROUP BY uuid
            HAVING COUNT(*) > 1
          )
        ''')) ?? 0;
    if (incompleteUsageCount > 0 || duplicateUsageUuidCount > 0) return true;
    final invalidUsageReversalCount =
        Sqflite.firstIntValue(await db.rawQuery('''
          SELECT COUNT(*)
          FROM asset_usage_events reversal
          WHERE reversal.reversal_of IS NOT NULL
            AND (
              reversal.count_delta <> 0
              OR NOT EXISTS (
                SELECT 1
                FROM asset_usage_events target
                WHERE target.id = reversal.reversal_of
                  AND target.asset_id = reversal.asset_id
                  AND target.id <> reversal.id
                  AND (
                    target.occurred_ms < reversal.occurred_ms
                    OR (
                      target.occurred_ms = reversal.occurred_ms
                      AND target.id < reversal.id
                    )
                  )
              )
            )
        ''')) ?? 0;
    if (invalidUsageReversalCount > 0) return true;
    return !await _indexMatches(
          db,
          table: 'savings_goals',
          name: 'idx_savings_goals_uuid',
          columns: const ['uuid'],
          unique: true,
        ) ||
        !await _indexMatches(
          db,
          table: 'asset_usage_events',
          name: 'idx_asset_usage_events_uuid',
          columns: const ['uuid'],
          unique: true,
        ) ||
        !await _indexMatches(
          db,
          table: 'asset_usage_events',
          name: 'idx_asset_usage_events_asset',
          columns: const ['asset_id', 'occurred_ms', 'id'],
          unique: false,
        ) ||
        !await _indexMatches(
          db,
          table: 'asset_usage_events',
          name: 'idx_asset_usage_events_reversal',
          columns: const ['reversal_of'],
          unique: true,
          partial: true,
          wherePredicate: 'reversal_of IS NOT NULL',
        ) ||
        !await _indexMatches(
          db,
          table: 'physical_assets',
          name: 'idx_physical_assets_savings_goal',
          columns: const ['savings_goal_id'],
          unique: false,
        );
  }

  static Future<void> _removeInvalidAssetUsageReversals(
    DatabaseExecutor db,
  ) async {
    while (true) {
      final removed = await db.rawDelete('''
        DELETE FROM asset_usage_events
        WHERE reversal_of IS NOT NULL
          AND (
            count_delta <> 0
            OR NOT EXISTS (
              SELECT 1
              FROM asset_usage_events target
              WHERE target.id = asset_usage_events.reversal_of
                AND target.asset_id = asset_usage_events.asset_id
                AND target.id <> asset_usage_events.id
                AND (
                  target.occurred_ms < asset_usage_events.occurred_ms
                  OR (
                    target.occurred_ms = asset_usage_events.occurred_ms
                    AND target.id < asset_usage_events.id
                  )
                )
            )
          )
      ''');
      if (removed == 0) break;
    }
  }

  static Future<void> _ensureAssetUsageReversalIndex(
    DatabaseExecutor db,
  ) async {
    await _removeInvalidAssetUsageReversals(db);
    if (await _indexMatches(
      db,
      table: 'asset_usage_events',
      name: 'idx_asset_usage_events_reversal',
      columns: const ['reversal_of'],
      unique: true,
      partial: true,
      wherePredicate: 'reversal_of IS NOT NULL',
    )) {
      return;
    }
    await db.execute('DROP INDEX IF EXISTS idx_asset_usage_events_reversal');
    // Intermediate v39 builds could record two reversals for one event. Keep
    // the earliest event-time/id pair so the audit chain stays deterministic.
    await db.execute('''
      DELETE FROM asset_usage_events
      WHERE reversal_of IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM asset_usage_events earlier
          WHERE earlier.reversal_of = asset_usage_events.reversal_of
            AND (
              earlier.occurred_ms < asset_usage_events.occurred_ms
              OR (
                earlier.occurred_ms = asset_usage_events.occurred_ms
                AND earlier.id < asset_usage_events.id
              )
            )
        )
    ''');
    await _removeInvalidAssetUsageReversals(db);
    await db.execute('''
      CREATE UNIQUE INDEX idx_asset_usage_events_reversal
      ON asset_usage_events(reversal_of)
      WHERE reversal_of IS NOT NULL
    ''');
  }

  static Future<void> _ensureAssetUsageEventsV39Schema(
    DatabaseExecutor db,
  ) async {
    await db.execute(_createAssetUsageEventsSql);
    var info = await db.rawQuery('PRAGMA table_info(asset_usage_events)');
    var columns = info.map((row) => row['name']).whereType<String>().toSet();
    final hasPrimaryId = info.any(
      (row) => row['name'] == 'id' && (row['pk'] as int? ?? 0) == 1,
    );
    if (!hasPrimaryId) {
      await db.execute('DROP TABLE IF EXISTS asset_usage_events_v39_compat');
      await db.execute('''
        CREATE TABLE asset_usage_events_v39_compat (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          uuid        TEXT NOT NULL DEFAULT '',
          asset_id    INTEGER NOT NULL DEFAULT 0,
          count_delta INTEGER NOT NULL DEFAULT 0,
          reversal_of INTEGER,
          occurred_ms INTEGER NOT NULL DEFAULT 0,
          note        TEXT NOT NULL DEFAULT '',
          created_ms  INTEGER NOT NULL DEFAULT 0,
          updated_ms  INTEGER NOT NULL DEFAULT 0
        )
      ''');
      String valueOr(String column, String fallback) =>
          columns.contains(column) ? column : fallback;
      final idExpression = columns.contains('id') ? 'id' : 'rowid';
      await db.execute('''
        INSERT INTO asset_usage_events_v39_compat (
          id, uuid, asset_id, count_delta, reversal_of, occurred_ms, note,
          created_ms, updated_ms
        )
        SELECT
          $idExpression,
          ${valueOr('uuid', "''")},
          ${valueOr('asset_id', '0')},
          ${valueOr('count_delta', '0')},
          ${valueOr('reversal_of', 'NULL')},
          ${valueOr('occurred_ms', '0')},
          ${valueOr('note', "''")},
          ${valueOr('created_ms', '0')},
          ${valueOr('updated_ms', '0')}
        FROM asset_usage_events
        ORDER BY rowid
      ''');
      await db.execute('DROP TABLE asset_usage_events');
      await db.execute('''
        ALTER TABLE asset_usage_events_v39_compat
        RENAME TO asset_usage_events
      ''');
      info = await db.rawQuery('PRAGMA table_info(asset_usage_events)');
      columns = info.map((row) => row['name']).whereType<String>().toSet();
    }
    for (final entry in const <(String, String)>[
      ('uuid', "TEXT NOT NULL DEFAULT ''"),
      ('asset_id', 'INTEGER NOT NULL DEFAULT 0'),
      ('count_delta', 'INTEGER NOT NULL DEFAULT 0'),
      ('reversal_of', 'INTEGER'),
      ('occurred_ms', 'INTEGER NOT NULL DEFAULT 0'),
      ('note', "TEXT NOT NULL DEFAULT ''"),
      ('created_ms', 'INTEGER NOT NULL DEFAULT 0'),
      ('updated_ms', 'INTEGER NOT NULL DEFAULT 0'),
    ]) {
      if (columns.contains(entry.$1)) continue;
      await db.execute(
        'ALTER TABLE asset_usage_events ADD COLUMN ${entry.$1} ${entry.$2}',
      );
      columns.add(entry.$1);
    }
    await db.execute('''
      UPDATE asset_usage_events
      SET uuid = lower(hex(randomblob(16)))
      WHERE trim(uuid) = ''
    ''');
    await db.execute('''
      UPDATE asset_usage_events
      SET uuid = lower(hex(randomblob(16)))
      WHERE id IN (
        SELECT duplicate.id
        FROM asset_usage_events duplicate
        JOIN asset_usage_events keeper
          ON duplicate.uuid = keeper.uuid
         AND duplicate.id > keeper.id
      )
    ''');
    await db.rawUpdate('''
      UPDATE asset_usage_events
      SET updated_ms = CASE WHEN created_ms > 0 THEN created_ms ELSE ? END
      WHERE updated_ms = 0
    ''', [DateTime.now().millisecondsSinceEpoch]);
    await _ensureNamedIndex(
      db,
      table: 'asset_usage_events',
      name: 'idx_asset_usage_events_uuid',
      columns: const ['uuid'],
      unique: true,
      createSql: '''
        CREATE UNIQUE INDEX idx_asset_usage_events_uuid
        ON asset_usage_events(uuid)
      ''',
    );
  }

  static Future<void> _runB3A4V39Compat(Database db) =>
      db.transaction(_ensureB3A4V39Compat);

  static Future<void> _ensureB3A4V39Compat(DatabaseExecutor db) async {
    await _ensureBudgetV2Tables(db);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS savings_goals (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid          TEXT NOT NULL DEFAULT '',
        name          TEXT NOT NULL,
        emoji         TEXT NOT NULL DEFAULT '🐷',
        target_amount TEXT NOT NULL DEFAULT '0',
        saved_amount  TEXT NOT NULL DEFAULT '0',
        created_ms    INTEGER NOT NULL DEFAULT 0,
        updated_ms    INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await _ensureAssetTables(db);
    for (final sql in [
      "ALTER TABLE budget_plans ADD COLUMN expense_scope_json TEXT NOT NULL DEFAULT ''",
      'ALTER TABLE physical_assets ADD COLUMN usage_tracking_enabled INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE physical_assets ADD COLUMN savings_goal_id INTEGER',
      "ALTER TABLE savings_goals ADD COLUMN uuid TEXT NOT NULL DEFAULT ''",
      'ALTER TABLE savings_goals ADD COLUMN updated_ms INTEGER NOT NULL DEFAULT 0',
    ]) {
      try {
        await db.execute(sql);
      } catch (_) {}
    }
    await db.execute('''
      UPDATE savings_goals
      SET uuid = lower(hex(randomblob(16)))
      WHERE trim(uuid) = ''
    ''');
    await db.execute('''
      UPDATE savings_goals
      SET uuid = lower(hex(randomblob(16)))
      WHERE id IN (
        SELECT duplicate.id
        FROM savings_goals duplicate
        JOIN savings_goals keeper
          ON duplicate.uuid = keeper.uuid
         AND duplicate.id > keeper.id
      )
    ''');
    await db.rawUpdate('''
      UPDATE savings_goals
      SET updated_ms = CASE WHEN created_ms > 0 THEN created_ms ELSE ? END
      WHERE updated_ms = 0
    ''', [DateTime.now().millisecondsSinceEpoch]);
    await _ensureNamedIndex(
      db,
      table: 'savings_goals',
      name: 'idx_savings_goals_uuid',
      columns: const ['uuid'],
      unique: true,
      createSql: '''
        CREATE UNIQUE INDEX idx_savings_goals_uuid
        ON savings_goals(uuid)
      ''',
    );
    await _ensureNamedIndex(
      db,
      table: 'asset_usage_events',
      name: 'idx_asset_usage_events_asset',
      columns: const ['asset_id', 'occurred_ms', 'id'],
      unique: false,
      createSql: '''
        CREATE INDEX idx_asset_usage_events_asset
        ON asset_usage_events(asset_id, occurred_ms DESC, id DESC)
      ''',
    );
    await _ensureAssetUsageReversalIndex(db);
    await _ensureNamedIndex(
      db,
      table: 'physical_assets',
      name: 'idx_physical_assets_savings_goal',
      columns: const ['savings_goal_id'],
      unique: false,
      createSql: '''
        CREATE INDEX idx_physical_assets_savings_goal
        ON physical_assets(savings_goal_id)
      ''',
    );
  }

  static Future<void> _ensureBudgetV2Tables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS budget_plans (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid              TEXT NOT NULL UNIQUE,
        book_id           INTEGER NOT NULL,
        currency_code     TEXT NOT NULL DEFAULT 'CNY',
        timezone          TEXT NOT NULL DEFAULT 'device_local',
        name              TEXT NOT NULL DEFAULT '',
        role              TEXT NOT NULL DEFAULT 'primary',
        cadence           TEXT NOT NULL,
        anchor_start_day  INTEGER NOT NULL,
        month_start_day   INTEGER,
        week_start        INTEGER,
        end_day           INTEGER,
        expense_scope_json TEXT NOT NULL DEFAULT '',
        status            TEXT NOT NULL DEFAULT 'active',
        created_ms        INTEGER NOT NULL,
        updated_ms        INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS budget_plan_revisions (
        id                          INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid                        TEXT NOT NULL UNIQUE,
        plan_id                     INTEGER NOT NULL,
        effective_cycle_start_day   INTEGER NOT NULL,
        effective_to_cycle_start_day INTEGER,
        amount_cents                INTEGER NOT NULL,
        category_budgets_json       TEXT NOT NULL DEFAULT '{}',
        monthly_income_cents        INTEGER,
        fixed_templates_json        TEXT NOT NULL DEFAULT '[]',
        legacy_source_period_id     INTEGER,
        created_ms                  INTEGER NOT NULL,
        updated_ms                  INTEGER NOT NULL,
        UNIQUE(plan_id, effective_cycle_start_day)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS budget_cycle_overrides (
        id                    INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid                  TEXT NOT NULL UNIQUE,
        plan_id               INTEGER NOT NULL,
        cycle_start_day       INTEGER NOT NULL,
        cycle_end_day         INTEGER NOT NULL,
        target_amount_cents   INTEGER NOT NULL,
        category_budgets_json TEXT,
        input_intent          TEXT NOT NULL DEFAULT 'replace_total',
        input_delta_cents     INTEGER,
        created_ms            INTEGER NOT NULL,
        updated_ms            INTEGER NOT NULL,
        UNIQUE(plan_id, cycle_start_day)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS budget_fixed_commitment_occurrences (
        id                              INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid                            TEXT NOT NULL UNIQUE,
        plan_id                         INTEGER NOT NULL,
        revision_id                     INTEGER NOT NULL,
        template_id                     TEXT NOT NULL,
        cycle_start_day                 INTEGER NOT NULL,
        cycle_end_day                   INTEGER NOT NULL,
        due_day                         INTEGER NOT NULL,
        planned_cents                   INTEGER NOT NULL,
        resolution_status               TEXT NOT NULL DEFAULT 'planned',
        review_reason                   TEXT NOT NULL DEFAULT '',
        matched_transaction_family_uuid TEXT,
        resolved_ms                     INTEGER,
        created_ms                      INTEGER NOT NULL,
        updated_ms                      INTEGER NOT NULL,
        UNIQUE(plan_id, template_id, cycle_start_day)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS budget_change_events (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid        TEXT NOT NULL UNIQUE,
        plan_id     INTEGER NOT NULL,
        event_type  TEXT NOT NULL,
        before_json TEXT NOT NULL DEFAULT '',
        after_json  TEXT NOT NULL DEFAULT '',
        created_ms  INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_budget_plans_scope
      ON budget_plans(book_id, role, status, anchor_start_day, end_day)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_budget_revisions_effective
      ON budget_plan_revisions(
        plan_id, effective_cycle_start_day, effective_to_cycle_start_day
      )
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_budget_occurrence_family_unique
      ON budget_fixed_commitment_occurrences(
        plan_id, matched_transaction_family_uuid
      )
      WHERE matched_transaction_family_uuid IS NOT NULL
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_budget_occurrences_cycle
      ON budget_fixed_commitment_occurrences(
        plan_id, cycle_start_day, resolution_status
      )
    ''');
  }

  static Future<void> _ensureAccountCheckpointTables(
    DatabaseExecutor db,
  ) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS account_balance_checkpoints (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid                TEXT NOT NULL UNIQUE,
        account_id          INTEGER NOT NULL,
        event_kind          TEXT NOT NULL DEFAULT 'anchor',
        effective_ms        INTEGER NOT NULL,
        sequence            INTEGER NOT NULL DEFAULT 0,
        timezone            TEXT NOT NULL DEFAULT 'device_local',
        knowledge_cutoff_ms INTEGER NOT NULL,
        target_balance      TEXT NOT NULL DEFAULT '0',
        calculated_before   TEXT NOT NULL DEFAULT '0',
        delta_at_creation   TEXT NOT NULL DEFAULT '0',
        reason              TEXT NOT NULL DEFAULT 'manual',
        note                TEXT NOT NULL DEFAULT '',
        status              TEXT NOT NULL DEFAULT 'active',
        reversal_of         INTEGER,
        created_ms          INTEGER NOT NULL,
        updated_ms          INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS account_checkpoint_covered_unknown_events (
        checkpoint_id     INTEGER NOT NULL,
        account_event_uuid TEXT NOT NULL,
        created_ms        INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (checkpoint_id, account_event_uuid)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_account_checkpoints_lookup
      ON account_balance_checkpoints(
        account_id, status, effective_ms DESC, sequence DESC, id DESC
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_account_checkpoint_reversal
      ON account_balance_checkpoints(reversal_of)
    ''');
  }

  static Future<void> _ensureNetWorthVerifiedCheckpointTables(
    DatabaseExecutor db,
  ) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS net_worth_verified_checkpoints (
        id                    INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid                  TEXT NOT NULL UNIQUE,
        as_of_ms              INTEGER NOT NULL,
        knowledge_cutoff_ms   INTEGER NOT NULL,
        scope_version         INTEGER NOT NULL,
        calculation_version   INTEGER NOT NULL,
        currency_coverage_json TEXT NOT NULL DEFAULT '',
        total_assets          TEXT NOT NULL DEFAULT '0',
        total_liabilities     TEXT NOT NULL DEFAULT '0',
        net_worth             TEXT NOT NULL DEFAULT '0',
        completeness          TEXT NOT NULL DEFAULT 'partial',
        reasons_json          TEXT NOT NULL DEFAULT '',
        status                TEXT NOT NULL DEFAULT 'active',
        supersedes_id         INTEGER,
        created_ms            INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS net_worth_verified_checkpoint_items (
        checkpoint_id       INTEGER NOT NULL,
        object_type         TEXT NOT NULL,
        object_uuid         TEXT NOT NULL,
        confirmed_amount    TEXT NOT NULL DEFAULT '0',
        currency_code       TEXT NOT NULL DEFAULT 'CNY',
        value_effective_ms  INTEGER NOT NULL,
        value_source        TEXT NOT NULL,
        quality             TEXT NOT NULL,
        PRIMARY KEY (checkpoint_id, object_type, object_uuid)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_verified_net_worth_as_of
      ON net_worth_verified_checkpoints(
        status, completeness, as_of_ms DESC, id DESC
      )
    ''');
  }

  static Future<void> _migrateAccountCheckpointsV37(
    DatabaseExecutor db,
  ) async {
    for (final sql in [
      "ALTER TABLE accounts ADD COLUMN uuid TEXT NOT NULL DEFAULT ''",
      'ALTER TABLE accounts ADD COLUMN created_ms INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE accounts ADD COLUMN updated_ms INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE accounts ADD COLUMN opening_balance_effective_ms INTEGER',
      'ALTER TABLE accounts ADD COLUMN opening_balance_sequence INTEGER NOT NULL DEFAULT 0',
      "ALTER TABLE accounts ADD COLUMN opening_balance_quality TEXT NOT NULL DEFAULT 'legacy_unknown'",
      "ALTER TABLE accounts ADD COLUMN status TEXT NOT NULL DEFAULT 'active'",
      'ALTER TABLE accounts ADD COLUMN archived_ms INTEGER',
      'ALTER TABLE accounts ADD COLUMN last_verified_ms INTEGER',
      'ALTER TABLE accounts ADD COLUMN verification_interval_days INTEGER',
    ]) {
      try {
        await db.execute(sql);
      } catch (_) {}
    }
    await db.execute(
      "UPDATE accounts SET uuid = lower(hex(randomblob(16))) WHERE uuid = ''",
    );
    await db.execute('''
      UPDATE accounts
      SET status = CASE
        WHEN is_deleted = 1 THEN 'legacy_hidden'
        ELSE 'active'
      END,
      opening_balance_effective_ms = NULL,
      opening_balance_sequence = 0,
      opening_balance_quality = 'legacy_unknown'
    ''');
    await _ensureAccountCheckpointTables(db);
    await _ensureNetWorthVerifiedCheckpointTables(db);
  }

  static Future<void> _migrateNetWorthSnapshotsV36(
    DatabaseExecutor db,
  ) async {
    await db.execute(_createNetWorthSnapshotsSql);
    for (final sql in [
      "ALTER TABLE net_worth_snapshots ADD COLUMN snapshot_type TEXT NOT NULL DEFAULT 'legacy_unverified'",
      "ALTER TABLE net_worth_snapshots ADD COLUMN lineage_key TEXT NOT NULL DEFAULT 'legacy:global'",
      'ALTER TABLE net_worth_snapshots ADD COLUMN as_of_ms INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE net_worth_snapshots ADD COLUMN knowledge_cutoff_ms INTEGER NOT NULL DEFAULT 0',
      "ALTER TABLE net_worth_snapshots ADD COLUMN timezone TEXT NOT NULL DEFAULT 'device_local'",
      'ALTER TABLE net_worth_snapshots ADD COLUMN scope_version INTEGER NOT NULL DEFAULT 1',
      'ALTER TABLE net_worth_snapshots ADD COLUMN calculation_version INTEGER NOT NULL DEFAULT 1',
      "ALTER TABLE net_worth_snapshots ADD COLUMN currency_coverage_json TEXT NOT NULL DEFAULT ''",
      "ALTER TABLE net_worth_snapshots ADD COLUMN quality TEXT NOT NULL DEFAULT 'legacy_unverified'",
      "ALTER TABLE net_worth_snapshots ADD COLUMN cause_set_json TEXT NOT NULL DEFAULT ''",
      "ALTER TABLE net_worth_snapshots ADD COLUMN reasons_json TEXT NOT NULL DEFAULT ''",
      "ALTER TABLE net_worth_snapshots ADD COLUMN valuation_coverage_json TEXT NOT NULL DEFAULT ''",
      'ALTER TABLE net_worth_snapshots ADD COLUMN provisional INTEGER NOT NULL DEFAULT 0',
    ]) {
      try {
        await db.execute(sql);
      } catch (_) {}
    }
    final rows = await db.query(
      'net_worth_snapshots',
      columns: ['id', 'scope_key', 'snapshot_date', 'created_ms'],
    );
    for (final row in rows) {
      final parsed = DateTime.tryParse(row['snapshot_date'] as String? ?? '');
      final asOf = parsed == null
          ? 0
          : DateTime(parsed.year, parsed.month, parsed.day)
              .millisecondsSinceEpoch;
      final scope = row['scope_key'] as String? ?? 'global';
      await db.update(
        'net_worth_snapshots',
        {
          'snapshot_type': 'legacy_unverified',
          'lineage_key': 'legacy:$scope',
          'as_of_ms': asOf,
          'knowledge_cutoff_ms': row['created_ms'] as int? ?? 0,
          'timezone': 'device_local',
          'scope_version': 1,
          'calculation_version': statisticsCalculationVersion,
          'currency_coverage_json': jsonEncode(
            NetWorthCurrencyCoverage.single('CNY').toJson(),
          ),
          'quality': NetWorthSnapshotQuality.legacyUnverified.storageKey,
          'cause_set_json': jsonEncode(
            [NetWorthSnapshotCause.migration.storageKey],
          ),
          'reasons_json': jsonEncode([
            NetWorthSnapshotReason(
              code: 'legacy_unverified',
              message: '旧快照缺少当前统计口径和覆盖证据',
            ).toJson(),
          ]),
          'valuation_coverage_json': jsonEncode(
            const NetWorthValuationCoverage().toJson(),
          ),
          'provisional': 0,
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_net_worth_snapshot_lineage
      ON net_worth_snapshots(
        snapshot_type, quality, scope_key, scope_version,
        calculation_version, snapshot_date
      )
    ''');
  }

  static Future<void> _ensureAssetAllocationV35(DatabaseExecutor db) async {
    for (final sql in [
      "ALTER TABLE physical_assets ADD COLUMN acquisition_cost_source TEXT NOT NULL DEFAULT 'manual'",
      "ALTER TABLE physical_assets ADD COLUMN thumbnail_path TEXT NOT NULL DEFAULT ''",
      "ALTER TABLE asset_transaction_links ADD COLUMN asset_object_type TEXT NOT NULL DEFAULT 'physical'",
      'ALTER TABLE asset_transaction_links ADD COLUMN allocated_gross_cents INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE asset_transaction_links ADD COLUMN allocated_refund_cents INTEGER NOT NULL DEFAULT 0',
      "ALTER TABLE asset_transaction_links ADD COLUMN cost_quality TEXT NOT NULL DEFAULT 'partial'",
      'ALTER TABLE asset_transaction_links ADD COLUMN updated_ms INTEGER NOT NULL DEFAULT 0',
    ]) {
      try {
        await db.execute(sql);
      } catch (_) {}
    }
    await db.execute(_createAssetRefundAllocationsSql);
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_asset_links_transaction
      ON asset_transaction_links(transaction_id, link_type)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_asset_refund_allocations_refund
      ON asset_refund_allocations(refund_transaction_id, status)
    ''');
  }

  static Future<void> _migrateAssetAllocationsV35(
    DatabaseExecutor db,
  ) async {
    final beforeRows = await db.query(
      'physical_assets',
      columns: ['current_value', 'include_in_net_worth', 'is_deleted'],
    );
    final beforeNetWorth = beforeRows
        .where(
            (row) => row['include_in_net_worth'] == 1 && row['is_deleted'] != 1)
        .fold<Decimal>(
          Decimal.zero,
          (sum, row) =>
              sum +
              (Decimal.tryParse(row['current_value'] as String? ?? '') ??
                  Decimal.zero),
        );
    await _ensureAssetAllocationV35(db);
    await db.execute('''
      UPDATE physical_assets
      SET acquisition_cost_source = CASE
        WHEN id IN (
          SELECT asset_id
          FROM asset_transaction_links
          WHERE link_type IN ('source_transaction', 'purchase_transaction')
        ) THEN 'transaction_allocations'
        ELSE 'manual'
      END
    ''');

    final transactionRows = await db.rawQuery('''
      SELECT DISTINCT transaction_id
      FROM asset_transaction_links
      WHERE link_type IN ('source_transaction', 'purchase_transaction')
    ''');
    for (final transactionRow in transactionRows) {
      final transactionId = transactionRow['transaction_id'] as int;
      final links = await db.query(
        'asset_transaction_links',
        where:
            "transaction_id = ? AND link_type IN ('source_transaction', 'purchase_transaction')",
        whereArgs: [transactionId],
        orderBy: 'id ASC',
      );
      final orderRows = await db.query(
        'transactions',
        columns: ['amount'],
        where: 'id = ?',
        whereArgs: [transactionId],
        limit: 1,
      );
      if (orderRows.isEmpty) {
        for (final link in links) {
          await db.update(
            'asset_transaction_links',
            {
              'asset_object_type': 'physical',
              'allocated_gross_cents': 0,
              'allocated_refund_cents': 0,
              'cost_quality': 'partial',
              'updated_ms': link['created_ms'] as int? ?? 0,
            },
            where: 'id = ?',
            whereArgs: [link['id']],
          );
        }
        continue;
      }
      final orderGross = decimalToBudgetCents(
        Decimal.tryParse(orderRows.first['amount'] as String? ?? '') ??
            Decimal.zero,
      ).abs();
      final refundRows = await db.query(
        'transactions',
        columns: ['id', 'uuid', 'amount', 'created_ms', 'updated_ms'],
        where: 'refund_of = ?',
        whereArgs: [transactionId],
        orderBy: 'id ASC',
      );
      final validRefund = refundRows.fold<int>(0, (sum, row) {
        final amount =
            Decimal.tryParse(row['amount'] as String? ?? '') ?? Decimal.zero;
        return sum + decimalToBudgetCents(amount).abs();
      });
      if (links.length == 1) {
        final link = links.single;
        final legacyAmount = decimalToBudgetCents(
          Decimal.tryParse(link['amount'] as String? ?? '') ?? Decimal.zero,
        ).abs();
        final gross = legacyAmount <= orderGross ? legacyAmount : orderGross;
        final fullyCoversOrder = gross == orderGross;
        final refund =
            fullyCoversOrder ? validRefund.clamp(0, gross).toInt() : 0;
        await db.update(
          'asset_transaction_links',
          {
            'asset_object_type': 'physical',
            'allocated_gross_cents': gross,
            'allocated_refund_cents': refund,
            'cost_quality': fullyCoversOrder ? 'exact' : 'partial',
            'updated_ms': link['created_ms'] as int? ?? 0,
          },
          where: 'id = ?',
          whereArgs: [link['id']],
        );
        if (fullyCoversOrder) {
          var capacity = gross;
          for (final refundRow in refundRows) {
            final cents = decimalToBudgetCents(
              Decimal.tryParse(refundRow['amount'] as String? ?? '') ??
                  Decimal.zero,
            ).abs();
            final allocated = cents.clamp(0, capacity).toInt();
            if (allocated == 0) continue;
            final createdMs = refundRow['created_ms'] as int? ?? 0;
            await db.insert('asset_refund_allocations', {
              'uuid': _newUuid(),
              'asset_transaction_link_id': link['id'],
              'refund_transaction_id': refundRow['id'],
              'allocated_refund_cents': allocated,
              'status': 'active',
              'created_ms': createdMs,
              'updated_ms': refundRow['updated_ms'] as int? ?? createdMs,
            });
            capacity -= allocated;
          }
        }
      } else {
        for (final link in links) {
          await db.update(
            'asset_transaction_links',
            {
              'asset_object_type': 'physical',
              'allocated_gross_cents': 0,
              'allocated_refund_cents': 0,
              'cost_quality':
                  validRefund > 0 ? 'pending_refund_allocation' : 'partial',
              'updated_ms': link['created_ms'] as int? ?? 0,
            },
            where: 'id = ?',
            whereArgs: [link['id']],
          );
        }
      }
    }

    final afterRows = await db.query(
      'physical_assets',
      columns: ['current_value', 'include_in_net_worth', 'is_deleted'],
    );
    final afterNetWorth = afterRows
        .where(
            (row) => row['include_in_net_worth'] == 1 && row['is_deleted'] != 1)
        .fold<Decimal>(
          Decimal.zero,
          (sum, row) =>
              sum +
              (Decimal.tryParse(row['current_value'] as String? ?? '') ??
                  Decimal.zero),
        );
    if (beforeNetWorth != afterNetWorth) {
      throw StateError('v35 物品分配迁移改变了净资产合计');
    }
  }

  static Future<void> _ensureTransactionSettlementColumns(
    DatabaseExecutor db,
  ) async {
    for (final sql in [
      'ALTER TABLE transactions ADD COLUMN created_ms INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE transactions ADD COLUMN settled_ms INTEGER',
      "ALTER TABLE transactions ADD COLUMN settlement_quality TEXT NOT NULL DEFAULT 'unknown'",
      'ALTER TABLE transactions ADD COLUMN settlement_account_id INTEGER',
      "ALTER TABLE transactions ADD COLUMN settlement_account_quality TEXT NOT NULL DEFAULT 'unknown'",
      "ALTER TABLE transactions ADD COLUMN event_type TEXT NOT NULL DEFAULT 'legacy_adjustment'",
    ]) {
      try {
        await db.execute(sql);
      } catch (_) {}
    }
  }

  static Future<void> _migrateTransactionSettlementV34(
    DatabaseExecutor db,
  ) async {
    await _ensureTransactionSettlementColumns(db);
    await db.execute('''
      UPDATE transactions
      SET settled_ms = date_ms,
          settlement_quality = 'legacy_assumed',
          settlement_account_id = account_id,
          settlement_account_quality = CASE
            WHEN account_id IS NULL THEN 'unknown'
            ELSE 'legacy_assumed'
          END,
          event_type = CASE kind
            WHEN 'expense' THEN 'expense'
            WHEN 'income' THEN 'income'
            WHEN 'transfer' THEN 'transfer'
            ELSE 'legacy_adjustment'
          END,
          created_ms = 0
    ''');
    await db.execute('''
      UPDATE transactions
      SET event_type = 'asset_purchase'
      WHERE id IN (
        SELECT transaction_id
        FROM asset_transaction_links
        WHERE link_type IN ('source_transaction', 'purchase_transaction')
      )
    ''');
    await db.execute('''
      UPDATE transactions
      SET event_type = 'asset_sale'
      WHERE id IN (
        SELECT transaction_id
        FROM asset_transaction_links
        WHERE link_type = 'sale_account_movement'
      )
    ''');
    await db.execute('''
      UPDATE transactions
      SET event_type = 'receivable_recovery'
      WHERE id IN (
        SELECT transaction_id
        FROM receivable_recoveries
        WHERE transaction_id IS NOT NULL
      )
    ''');
    await db.execute('''
      UPDATE transactions
      SET event_type = CASE
            WHEN note = '报销到账' THEN 'reimbursement'
            ELSE 'refund'
          END,
          settled_ms = NULL,
          settlement_quality = 'unknown',
          settlement_account_id = CASE
            WHEN note = '报销到账' THEN NULL
            ELSE account_id
          END,
          settlement_account_quality = CASE
            WHEN note = '报销到账' OR account_id IS NULL THEN 'unknown'
            ELSE 'legacy_assumed'
          END
      WHERE refund_of IS NOT NULL
    ''');
    await db.execute('''
      UPDATE transactions
      SET event_type = 'legacy_adjustment'
      WHERE refund_of IS NULL AND CAST(amount AS REAL) < 0
    ''');
  }

  static Future<void> _ensureTransactionIndexes(DatabaseExecutor db) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_transactions_book_date
      ON transactions(book_id, date_ms DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_transactions_refund_of
      ON transactions(refund_of)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_transactions_book_refund
      ON transactions(book_id, refund_of)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_transactions_book_category_date
      ON transactions(book_id, category_id, date_ms DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_transactions_book_account_date
      ON transactions(book_id, account_id, date_ms DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_transactions_settlement_account_date
      ON transactions(settlement_account_id, settled_ms, id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_transactions_event_settled
      ON transactions(event_type, settled_ms)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_transactions_settlement_quality
      ON transactions(settlement_quality, id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_transactions_settlement_account_quality
      ON transactions(settlement_account_quality, id)
    ''');
  }

  static const _createReportsSql = '''
      CREATE TABLE IF NOT EXISTS reports (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id         INTEGER,
        type            TEXT NOT NULL,
        title           TEXT NOT NULL,
        summary         TEXT NOT NULL DEFAULT '',
        markdown        TEXT NOT NULL DEFAULT '',
        period_start_ms INTEGER NOT NULL DEFAULT 0,
        period_end_ms   INTEGER NOT NULL DEFAULT 0,
        created_ms      INTEGER NOT NULL DEFAULT 0,
        pinned_ms       INTEGER NOT NULL DEFAULT 0
      )
    ''';

  static const _createBudgetPeriodsSql = '''
      CREATE TABLE IF NOT EXISTS budget_periods (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id           INTEGER,
        start_ms          INTEGER NOT NULL,
        end_ms            INTEGER,
        recurring_monthly INTEGER NOT NULL DEFAULT 1,
        total             TEXT NOT NULL,
        category_budgets  TEXT NOT NULL DEFAULT '',
        monthly_income    TEXT NOT NULL DEFAULT '',
        fixed_expenses    TEXT NOT NULL DEFAULT '',
        created_ms        INTEGER NOT NULL DEFAULT 0
      )
    ''';

  static const _createPhysicalAssetsSql = '''
      CREATE TABLE IF NOT EXISTS physical_assets (
        id                    INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid                  TEXT NOT NULL UNIQUE,
        book_id               INTEGER,
        name                  TEXT NOT NULL,
        asset_type            TEXT NOT NULL DEFAULT 'other',
        status                TEXT NOT NULL DEFAULT 'active',
        economic_status       TEXT NOT NULL DEFAULT 'owned',
        usage_status          TEXT NOT NULL DEFAULT 'active',
        visibility_status     TEXT NOT NULL DEFAULT 'active',
        inclusion_quality     TEXT NOT NULL DEFAULT 'confirmed',
        source_type           TEXT NOT NULL DEFAULT 'historical_existing',
        acquisition_cost_source TEXT NOT NULL DEFAULT 'manual',
        purchase_price        TEXT NOT NULL DEFAULT '0',
        current_value         TEXT NOT NULL DEFAULT '0',
        currency_code         TEXT NOT NULL DEFAULT 'CNY',
        purchase_date_ms      INTEGER,
        brand                 TEXT NOT NULL DEFAULT '',
        model                 TEXT NOT NULL DEFAULT '',
        location              TEXT NOT NULL DEFAULT '',
        warranty_until_ms     INTEGER,
        usage_tracking_enabled INTEGER NOT NULL DEFAULT 0,
        savings_goal_id       INTEGER,
        photo_path            TEXT NOT NULL DEFAULT '',
        thumbnail_path        TEXT NOT NULL DEFAULT '',
        invoice_path          TEXT NOT NULL DEFAULT '',
        depreciation_method   TEXT NOT NULL DEFAULT '',
        depreciation_base     TEXT NOT NULL DEFAULT '0',
        salvage_value         TEXT NOT NULL DEFAULT '0',
        useful_life_months    INTEGER NOT NULL DEFAULT 0,
        depreciation_start_ms INTEGER,
        depreciation_paused   INTEGER NOT NULL DEFAULT 0,
        note                  TEXT NOT NULL DEFAULT '',
        include_in_net_worth  INTEGER NOT NULL DEFAULT 1,
        is_deleted            INTEGER NOT NULL DEFAULT 0,
        ended_ms              INTEGER,
        archived_ms           INTEGER,
        created_ms            INTEGER NOT NULL DEFAULT 0,
        updated_ms            INTEGER NOT NULL DEFAULT 0
      )
    ''';

  static const _createAssetEventsSql = '''
      CREATE TABLE IF NOT EXISTS asset_events (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid        TEXT NOT NULL UNIQUE,
        asset_id    INTEGER NOT NULL,
        asset_type  TEXT NOT NULL DEFAULT 'physical',
        event_type  TEXT NOT NULL,
        occurred_ms INTEGER NOT NULL,
        value       TEXT NOT NULL DEFAULT '',
        note        TEXT NOT NULL DEFAULT '',
        metadata    TEXT NOT NULL DEFAULT '',
        created_ms  INTEGER NOT NULL DEFAULT 0
      )
    ''';

  static const _createAssetUsageEventsSql = '''
      CREATE TABLE IF NOT EXISTS asset_usage_events (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid        TEXT NOT NULL UNIQUE,
        asset_id    INTEGER NOT NULL,
        count_delta INTEGER NOT NULL DEFAULT 0,
        reversal_of INTEGER,
        occurred_ms INTEGER NOT NULL,
        note        TEXT NOT NULL DEFAULT '',
        created_ms  INTEGER NOT NULL DEFAULT 0,
        updated_ms  INTEGER NOT NULL DEFAULT 0
      )
    ''';

  static const _createReceivableAssetsSql = '''
      CREATE TABLE IF NOT EXISTS receivable_assets (
        id                    INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid                  TEXT NOT NULL UNIQUE,
        book_id               INTEGER,
        name                  TEXT NOT NULL,
        receivable_type       TEXT NOT NULL DEFAULT 'other',
        status                TEXT NOT NULL DEFAULT 'active',
        economic_status       TEXT NOT NULL DEFAULT 'active',
        visibility_status     TEXT NOT NULL DEFAULT 'active',
        inclusion_quality     TEXT NOT NULL DEFAULT 'confirmed',
        original_amount       TEXT NOT NULL DEFAULT '0',
        remaining_amount      TEXT NOT NULL DEFAULT '0',
        currency_code         TEXT NOT NULL DEFAULT 'CNY',
        counterparty          TEXT NOT NULL DEFAULT '',
        due_date_ms           INTEGER,
        include_in_net_worth  INTEGER NOT NULL DEFAULT 1,
        note                  TEXT NOT NULL DEFAULT '',
        is_deleted            INTEGER NOT NULL DEFAULT 0,
        ended_ms              INTEGER,
        archived_ms           INTEGER,
        created_ms            INTEGER NOT NULL DEFAULT 0,
        updated_ms            INTEGER NOT NULL DEFAULT 0
      )
    ''';

  static const _createReceivableRecoveriesSql = '''
      CREATE TABLE IF NOT EXISTS receivable_recoveries (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid                TEXT NOT NULL UNIQUE,
        receivable_asset_id INTEGER NOT NULL,
        amount              TEXT NOT NULL DEFAULT '0',
        recovered_ms        INTEGER NOT NULL,
        target_account_id   INTEGER,
        event_id            INTEGER,
        transaction_id      INTEGER,
        note                TEXT NOT NULL DEFAULT '',
        created_ms          INTEGER NOT NULL DEFAULT 0
      )
    ''';

  static const _createNetWorthSnapshotsSql = '''
      CREATE TABLE IF NOT EXISTS net_worth_snapshots (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        scope_key         TEXT NOT NULL DEFAULT 'global',
        snapshot_date     TEXT NOT NULL,
        total_assets      TEXT NOT NULL DEFAULT '0',
        total_liabilities TEXT NOT NULL DEFAULT '0',
        net_worth         TEXT NOT NULL DEFAULT '0',
        cash_assets       TEXT NOT NULL DEFAULT '0',
        investment_assets TEXT NOT NULL DEFAULT '0',
        physical_assets   TEXT NOT NULL DEFAULT '0',
        receivable_assets TEXT NOT NULL DEFAULT '0',
        snapshot_type     TEXT NOT NULL DEFAULT 'legacy_unverified',
        lineage_key       TEXT NOT NULL DEFAULT 'legacy:global',
        as_of_ms          INTEGER NOT NULL DEFAULT 0,
        knowledge_cutoff_ms INTEGER NOT NULL DEFAULT 0,
        timezone          TEXT NOT NULL DEFAULT 'device_local',
        scope_version     INTEGER NOT NULL DEFAULT 1,
        calculation_version INTEGER NOT NULL DEFAULT 1,
        currency_coverage_json TEXT NOT NULL DEFAULT '',
        quality           TEXT NOT NULL DEFAULT 'legacy_unverified',
        cause_set_json    TEXT NOT NULL DEFAULT '',
        reasons_json      TEXT NOT NULL DEFAULT '',
        valuation_coverage_json TEXT NOT NULL DEFAULT '',
        provisional       INTEGER NOT NULL DEFAULT 0,
        created_ms        INTEGER NOT NULL DEFAULT 0,
        UNIQUE(scope_key, snapshot_date)
      )
    ''';

  static Future<void> _ensureNetWorthSnapshotScope(DatabaseExecutor db) async {
    final table = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table' AND name = 'net_worth_snapshots'
      LIMIT 1
    ''');
    if (table.isEmpty) {
      await db.execute(_createNetWorthSnapshotsSql);
      return;
    }

    final columns = await db.rawQuery(
      'PRAGMA table_info(net_worth_snapshots)',
    );
    final hasScope = columns.any((row) => row['name'] == 'scope_key');

    // snapshot_date used to carry a column-level UNIQUE constraint. SQLite
    // cannot drop that constraint in-place, so v31 must rebuild the table.
    // INSERT OR IGNORE deliberately keeps the oldest id if an intermediate
    // development build ever produced duplicate rows for one scope and day.
    await db.execute('DROP TABLE IF EXISTS net_worth_snapshots_v31');
    await db.execute('''
      CREATE TABLE net_worth_snapshots_v31 (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        scope_key         TEXT NOT NULL DEFAULT 'global',
        snapshot_date     TEXT NOT NULL,
        total_assets      TEXT NOT NULL DEFAULT '0',
        total_liabilities TEXT NOT NULL DEFAULT '0',
        net_worth         TEXT NOT NULL DEFAULT '0',
        cash_assets       TEXT NOT NULL DEFAULT '0',
        investment_assets TEXT NOT NULL DEFAULT '0',
        physical_assets   TEXT NOT NULL DEFAULT '0',
        receivable_assets TEXT NOT NULL DEFAULT '0',
        snapshot_type     TEXT NOT NULL DEFAULT 'legacy_unverified',
        lineage_key       TEXT NOT NULL DEFAULT 'legacy:global',
        as_of_ms          INTEGER NOT NULL DEFAULT 0,
        knowledge_cutoff_ms INTEGER NOT NULL DEFAULT 0,
        timezone          TEXT NOT NULL DEFAULT 'device_local',
        scope_version     INTEGER NOT NULL DEFAULT 1,
        calculation_version INTEGER NOT NULL DEFAULT 1,
        currency_coverage_json TEXT NOT NULL DEFAULT '',
        quality           TEXT NOT NULL DEFAULT 'legacy_unverified',
        cause_set_json    TEXT NOT NULL DEFAULT '',
        reasons_json      TEXT NOT NULL DEFAULT '',
        valuation_coverage_json TEXT NOT NULL DEFAULT '',
        provisional       INTEGER NOT NULL DEFAULT 0,
        created_ms        INTEGER NOT NULL DEFAULT 0,
        UNIQUE(scope_key, snapshot_date)
      )
    ''');
    final scopeExpression =
        hasScope ? "COALESCE(NULLIF(scope_key, ''), 'global')" : "'global'";
    await db.execute('''
      INSERT OR IGNORE INTO net_worth_snapshots_v31 (
        id,
        scope_key,
        snapshot_date,
        total_assets,
        total_liabilities,
        net_worth,
        cash_assets,
        investment_assets,
        physical_assets,
        receivable_assets,
        created_ms
      )
      SELECT
        id,
        $scopeExpression,
        snapshot_date,
        total_assets,
        total_liabilities,
        net_worth,
        cash_assets,
        investment_assets,
        physical_assets,
        receivable_assets,
        created_ms
      FROM net_worth_snapshots
      ORDER BY id
    ''');
    await db.execute('DROP TABLE net_worth_snapshots');
    await db.execute(
      'ALTER TABLE net_worth_snapshots_v31 RENAME TO net_worth_snapshots',
    );
  }

  static const _createLiabilityProfilesSql = '''
      CREATE TABLE IF NOT EXISTS liability_profiles (
        id                   INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid                 TEXT NOT NULL UNIQUE,
        account_id           INTEGER NOT NULL UNIQUE,
        liability_type       TEXT NOT NULL DEFAULT 'other',
        original_amount      TEXT NOT NULL DEFAULT '0',
        current_principal    TEXT NOT NULL DEFAULT '0',
        interest_rate        TEXT NOT NULL DEFAULT '0',
        repayment_day        INTEGER,
        repayment_account_id INTEGER,
        start_date_ms        INTEGER,
        end_date_ms          INTEGER,
        status               TEXT NOT NULL DEFAULT 'active',
        note                 TEXT NOT NULL DEFAULT '',
        statement_day        INTEGER,
        credit_limit         TEXT,
        counterparty         TEXT NOT NULL DEFAULT '',
        created_ms           INTEGER NOT NULL DEFAULT 0,
        updated_ms           INTEGER NOT NULL DEFAULT 0
      )
    ''';

  static const _createAssetValuationsSql = '''
      CREATE TABLE IF NOT EXISTS asset_valuations (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid         TEXT NOT NULL UNIQUE,
        asset_id     INTEGER NOT NULL,
        value        TEXT NOT NULL,
        source       TEXT NOT NULL DEFAULT 'manual',
        valued_at_ms INTEGER NOT NULL,
        note         TEXT NOT NULL DEFAULT '',
        created_ms   INTEGER NOT NULL DEFAULT 0
      )
    ''';

  static const _createAssetTransactionLinksSql = '''
      CREATE TABLE IF NOT EXISTS asset_transaction_links (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid           TEXT NOT NULL UNIQUE,
        asset_id       INTEGER NOT NULL,
        asset_object_type TEXT NOT NULL DEFAULT 'physical',
        transaction_id INTEGER NOT NULL,
        link_type      TEXT NOT NULL,
        amount         TEXT NOT NULL DEFAULT '0',
        allocated_gross_cents INTEGER NOT NULL DEFAULT 0,
        allocated_refund_cents INTEGER NOT NULL DEFAULT 0,
        cost_quality   TEXT NOT NULL DEFAULT 'partial',
        note           TEXT NOT NULL DEFAULT '',
        created_ms     INTEGER NOT NULL DEFAULT 0,
        updated_ms     INTEGER NOT NULL DEFAULT 0,
        UNIQUE(asset_object_type, asset_id, transaction_id, link_type)
      )
    ''';

  static const _createAssetRefundAllocationsSql = '''
      CREATE TABLE IF NOT EXISTS asset_refund_allocations (
        id                        INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid                      TEXT NOT NULL UNIQUE,
        asset_transaction_link_id INTEGER NOT NULL,
        refund_transaction_id     INTEGER NOT NULL,
        allocated_refund_cents    INTEGER NOT NULL,
        status                    TEXT NOT NULL DEFAULT 'active',
        created_ms                INTEGER NOT NULL DEFAULT 0,
        updated_ms                INTEGER NOT NULL DEFAULT 0
      )
    ''';

  static Future<void> _ensureRecurringEndColumns(DatabaseExecutor db) async {
    Future<void> addColumn(String sql) async {
      try {
        await db.execute(sql);
      } catch (_) {}
    }

    await addColumn(
        'ALTER TABLE recurring_rules ADD COLUMN start_date_ms INTEGER NOT NULL DEFAULT 0');
    await addColumn(
        'ALTER TABLE recurring_rules ADD COLUMN end_date_ms INTEGER');
    await addColumn(
        'ALTER TABLE recurring_rules ADD COLUMN total_count INTEGER');
    await addColumn(
        'ALTER TABLE recurring_rules ADD COLUMN generated_count INTEGER NOT NULL DEFAULT 0');
    await addColumn(
        'ALTER TABLE transactions ADD COLUMN recurring_rule_id INTEGER');
    try {
      await db.execute('''
        UPDATE recurring_rules
        SET start_date_ms = next_due_ms
        WHERE start_date_ms = 0
      ''');
    } catch (_) {}
  }

  static Future<void> _ensureRecurringOccurrences(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recurring_occurrences (
        rule_id        INTEGER NOT NULL,
        due_ms         INTEGER NOT NULL,
        transaction_id INTEGER,
        created_ms     INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (rule_id, due_ms)
      )
    ''');
    await db.execute('''
      INSERT OR IGNORE INTO recurring_occurrences (
        rule_id,
        due_ms,
        transaction_id,
        created_ms
      )
      SELECT
        recurring_rule_id,
        date_ms,
        MIN(id),
        MIN(updated_ms)
      FROM transactions
      WHERE recurring_rule_id IS NOT NULL
      GROUP BY recurring_rule_id, date_ms
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_recurring_occurrences_transaction
      ON recurring_occurrences(transaction_id)
    ''');
  }

  static Future<void> _ensureAutoRecordOccurrences(
    DatabaseExecutor db,
  ) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS auto_record_occurrences (
        source_id      TEXT PRIMARY KEY,
        transaction_id INTEGER,
        created_ms     INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_auto_record_occurrences_transaction
      ON auto_record_occurrences(transaction_id)
    ''');
  }

  static Future<void> _ensureReportJobs(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS report_jobs (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid            TEXT NOT NULL UNIQUE,
        book_id         INTEGER,
        report_id       INTEGER,
        question        TEXT NOT NULL DEFAULT '',
        type            TEXT NOT NULL,
        title           TEXT NOT NULL,
        period_start_ms INTEGER NOT NULL,
        period_end_ms   INTEGER NOT NULL,
        status          TEXT NOT NULL DEFAULT 'queued',
        stage           TEXT NOT NULL DEFAULT 'collect',
        error           TEXT NOT NULL DEFAULT '',
        created_ms      INTEGER NOT NULL DEFAULT 0,
        updated_ms      INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_report_jobs_status_updated
      ON report_jobs(status, updated_ms DESC)
    ''');
  }

  static Future<void> _ensureAssetTables(DatabaseExecutor db) async {
    await db.execute(_createPhysicalAssetsSql);
    await _ensurePhysicalAssetAdvancedColumns(db);
    await db.execute(_createAssetEventsSql);
    await _ensureAssetUsageEventsV39Schema(db);
    try {
      await db.execute(
          "ALTER TABLE asset_events ADD COLUMN asset_type TEXT NOT NULL DEFAULT 'physical'");
    } catch (_) {}
    await db.execute(_createAssetValuationsSql);
    await db.execute(_createAssetTransactionLinksSql);
    await _ensureAssetAllocationV35(db);
    await db.execute(_createReceivableAssetsSql);
    await _ensureAssetStateColumns(db);
    await db.execute(_createReceivableRecoveriesSql);
    await db.execute(_createNetWorthSnapshotsSql);
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_physical_assets_book_status
      ON physical_assets(book_id, status, is_deleted)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_asset_events_asset
      ON asset_events(asset_type, asset_id, occurred_ms DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_asset_usage_events_asset
      ON asset_usage_events(asset_id, occurred_ms DESC, id DESC)
    ''');
    await _ensureAssetUsageReversalIndex(db);
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_asset_valuations_asset
      ON asset_valuations(asset_id, valued_at_ms DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_asset_links_asset
      ON asset_transaction_links(asset_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_receivable_assets_book_status
      ON receivable_assets(book_id, status, is_deleted)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_receivable_recoveries_asset
      ON receivable_recoveries(receivable_asset_id, recovered_ms DESC)
    ''');
  }

  static Future<void> _ensureAssetStateColumns(DatabaseExecutor db) async {
    for (final sql in [
      "ALTER TABLE physical_assets ADD COLUMN economic_status TEXT NOT NULL DEFAULT 'owned'",
      "ALTER TABLE physical_assets ADD COLUMN usage_status TEXT NOT NULL DEFAULT 'active'",
      "ALTER TABLE physical_assets ADD COLUMN visibility_status TEXT NOT NULL DEFAULT 'active'",
      "ALTER TABLE physical_assets ADD COLUMN inclusion_quality TEXT NOT NULL DEFAULT 'confirmed'",
      'ALTER TABLE physical_assets ADD COLUMN ended_ms INTEGER',
      'ALTER TABLE physical_assets ADD COLUMN archived_ms INTEGER',
      "ALTER TABLE receivable_assets ADD COLUMN economic_status TEXT NOT NULL DEFAULT 'active'",
      "ALTER TABLE receivable_assets ADD COLUMN visibility_status TEXT NOT NULL DEFAULT 'active'",
      "ALTER TABLE receivable_assets ADD COLUMN inclusion_quality TEXT NOT NULL DEFAULT 'confirmed'",
      'ALTER TABLE receivable_assets ADD COLUMN ended_ms INTEGER',
      'ALTER TABLE receivable_assets ADD COLUMN archived_ms INTEGER',
    ]) {
      try {
        await db.execute(sql);
      } catch (_) {}
    }
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_physical_assets_global_visibility
      ON physical_assets(is_deleted, visibility_status, economic_status, updated_ms DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_physical_assets_book_visibility
      ON physical_assets(book_id, is_deleted, visibility_status, updated_ms DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_receivable_assets_global_visibility
      ON receivable_assets(is_deleted, visibility_status, economic_status, updated_ms DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_receivable_assets_book_visibility
      ON receivable_assets(book_id, is_deleted, visibility_status, updated_ms DESC)
    ''');
  }

  static Decimal _assetAmount(Map<String, Object?> row, String column) =>
      Decimal.tryParse(row[column] as String? ?? '') ?? Decimal.zero;

  static ({Decimal physical, Decimal receivable}) _legacyAssetTotals(
    List<Map<String, Object?>> physicalRows,
    List<Map<String, Object?>> receivableRows,
  ) {
    var physical = Decimal.zero;
    for (final row in physicalRows) {
      final status = row['status'] as String? ?? 'active';
      if ((row['is_deleted'] as int? ?? 0) == 0 &&
          (row['include_in_net_worth'] as int? ?? 1) == 1 &&
          (row['currency_code'] as String? ?? 'CNY') == 'CNY' &&
          (status == 'active' || status == 'idle')) {
        physical += _assetAmount(row, 'current_value');
      }
    }
    var receivable = Decimal.zero;
    for (final row in receivableRows) {
      final status = row['status'] as String? ?? 'active';
      final remaining = _assetAmount(row, 'remaining_amount');
      if ((row['is_deleted'] as int? ?? 0) == 0 &&
          (row['include_in_net_worth'] as int? ?? 1) == 1 &&
          (row['currency_code'] as String? ?? 'CNY') == 'CNY' &&
          (status == 'active' || status == 'partial_recovered') &&
          remaining > Decimal.zero) {
        receivable += remaining;
      }
    }
    return (physical: physical, receivable: receivable);
  }

  static ({Decimal physical, Decimal receivable}) _v33AssetTotals(
    List<Map<String, Object?>> physicalRows,
    List<Map<String, Object?>> receivableRows,
  ) {
    var physical = Decimal.zero;
    for (final row in physicalRows) {
      if ((row['is_deleted'] as int? ?? 0) == 0 &&
          (row['include_in_net_worth'] as int? ?? 1) == 1 &&
          (row['currency_code'] as String? ?? 'CNY') == 'CNY' &&
          row['economic_status'] == 'owned') {
        physical += _assetAmount(row, 'current_value');
      }
    }
    var receivable = Decimal.zero;
    for (final row in receivableRows) {
      final remaining = _assetAmount(row, 'remaining_amount');
      final economicStatus = row['economic_status'];
      if ((row['is_deleted'] as int? ?? 0) == 0 &&
          (row['include_in_net_worth'] as int? ?? 1) == 1 &&
          (row['currency_code'] as String? ?? 'CNY') == 'CNY' &&
          (economicStatus == 'active' ||
              economicStatus == 'partial_recovered') &&
          remaining > Decimal.zero) {
        receivable += remaining;
      }
    }
    return (physical: physical, receivable: receivable);
  }

  static Future<void> _migrateAssetStateV33(DatabaseExecutor db) async {
    final oldPhysical = await db.query('physical_assets');
    final oldReceivable = await db.query('receivable_assets');
    final before = _legacyAssetTotals(oldPhysical, oldReceivable);

    await _ensureAssetStateColumns(db);
    await db.execute('''
      UPDATE physical_assets
      SET economic_status = CASE status
            WHEN 'sold' THEN 'sold'
            WHEN 'disposed' THEN 'scrapped'
            WHEN 'lost' THEN 'lost'
            WHEN 'gifted' THEN 'gifted'
            ELSE 'owned'
          END,
          usage_status = CASE status
            WHEN 'active' THEN 'active'
            WHEN 'idle' THEN 'idle'
            ELSE 'unknown'
          END,
          visibility_status = CASE status
            WHEN 'archived' THEN 'archived'
            ELSE 'active'
          END,
          inclusion_quality = CASE
            WHEN status = 'archived' THEN 'needs_review'
            WHEN status IN ('active', 'idle', 'sold', 'disposed', 'lost', 'gifted')
              THEN 'confirmed'
            ELSE 'needs_review'
          END,
          ended_ms = CASE status
            WHEN 'sold' THEN (
              SELECT MAX(e.occurred_ms) FROM asset_events e
              WHERE e.asset_type = 'physical'
                AND e.asset_id = physical_assets.id
                AND e.event_type = 'asset_sold'
            )
            WHEN 'disposed' THEN (
              SELECT MAX(e.occurred_ms) FROM asset_events e
              WHERE e.asset_type = 'physical'
                AND e.asset_id = physical_assets.id
                AND e.event_type = 'asset_disposed'
            )
            WHEN 'lost' THEN (
              SELECT MAX(e.occurred_ms) FROM asset_events e
              WHERE e.asset_type = 'physical'
                AND e.asset_id = physical_assets.id
                AND e.event_type = 'asset_lost'
            )
            WHEN 'gifted' THEN (
              SELECT MAX(e.occurred_ms) FROM asset_events e
              WHERE e.asset_type = 'physical'
                AND e.asset_id = physical_assets.id
                AND e.event_type = 'asset_gifted'
            )
            ELSE NULL
          END,
          archived_ms = CASE status
            WHEN 'archived' THEN (
              SELECT MAX(e.occurred_ms) FROM asset_events e
              WHERE e.asset_type = 'physical'
                AND e.asset_id = physical_assets.id
                AND e.event_type = 'asset_archived'
            )
            ELSE NULL
          END
    ''');
    await db.execute('''
      UPDATE receivable_assets
      SET economic_status = CASE status
            WHEN 'partial_recovered' THEN 'partial_recovered'
            WHEN 'recovered' THEN 'recovered'
            WHEN 'lost' THEN 'lost'
            WHEN 'archived' THEN 'unknown'
            ELSE 'active'
          END,
          visibility_status = CASE status
            WHEN 'archived' THEN 'archived'
            ELSE 'active'
          END,
          inclusion_quality = CASE
            WHEN status = 'archived' THEN 'needs_review'
            WHEN status IN ('active', 'partial_recovered', 'recovered', 'lost')
              THEN 'confirmed'
            ELSE 'needs_review'
          END,
          ended_ms = CASE status
            WHEN 'recovered' THEN (
              SELECT MAX(r.recovered_ms) FROM receivable_recoveries r
              WHERE r.receivable_asset_id = receivable_assets.id
            )
            WHEN 'lost' THEN (
              SELECT MAX(e.occurred_ms) FROM asset_events e
              WHERE e.asset_type = 'receivable'
                AND e.asset_id = receivable_assets.id
                AND e.event_type = 'receivable_lost'
            )
            ELSE NULL
          END,
          archived_ms = CASE status
            WHEN 'archived' THEN (
              SELECT MAX(e.occurred_ms) FROM asset_events e
              WHERE e.asset_type = 'receivable'
                AND e.asset_id = receivable_assets.id
                AND e.event_type = 'receivable_archived'
            )
            ELSE NULL
          END
    ''');

    final archivedRows = await db.query(
      'receivable_assets',
      where: "status = 'archived'",
    );
    for (final row in archivedRows) {
      final id = row['id'] as int;
      final original = _assetAmount(row, 'original_amount');
      final remaining = _assetAmount(row, 'remaining_amount');
      final recoveryRows = await db.query(
        'receivable_recoveries',
        where: 'receivable_asset_id = ?',
        whereArgs: [id],
      );
      var recovered = Decimal.zero;
      var recoveriesValid = true;
      var latestRecoveryMs = 0;
      for (final recovery in recoveryRows) {
        final amount = _assetAmount(recovery, 'amount');
        if (amount <= Decimal.zero) recoveriesValid = false;
        recovered += amount;
        final recoveredMs = recovery['recovered_ms'] as int? ?? 0;
        if (recoveredMs > latestRecoveryMs) latestRecoveryMs = recoveredMs;
      }
      final lostEvents = await db.query(
        'asset_events',
        columns: ['occurred_ms'],
        where:
            "asset_type = 'receivable' AND asset_id = ? AND event_type = 'receivable_lost'",
        whereArgs: [id],
        orderBy: 'occurred_ms DESC, id DESC',
      );
      final lostMs =
          lostEvents.isEmpty ? null : lostEvents.first['occurred_ms'] as int?;
      final recoveryAfterLoss = lostMs != null &&
          recoveryRows.any((recovery) {
            final recoveredMs = recovery['recovered_ms'] as int? ?? 0;
            return recoveredMs > lostMs;
          });
      final amountsValid = original >= Decimal.zero &&
          remaining >= Decimal.zero &&
          remaining <= original &&
          recoveriesValid &&
          recovered <= original;
      var economicStatus = ReceivableEconomicStatus.unknown;
      int? endedMs;
      if (amountsValid && lostMs != null && !recoveryAfterLoss) {
        if (remaining == Decimal.zero) {
          economicStatus = ReceivableEconomicStatus.lost;
          endedMs = lostMs;
        }
      } else if (amountsValid && lostMs == null) {
        if (original > Decimal.zero &&
            remaining == Decimal.zero &&
            recovered == original) {
          economicStatus = ReceivableEconomicStatus.recovered;
          endedMs = latestRecoveryMs == 0 ? null : latestRecoveryMs;
        } else if (remaining > Decimal.zero &&
            remaining < original &&
            recovered == original - remaining) {
          economicStatus = ReceivableEconomicStatus.partialRecovered;
        } else if (remaining == original && recovered == Decimal.zero) {
          economicStatus = ReceivableEconomicStatus.active;
        }
      }
      await db.update(
        'receivable_assets',
        {
          'economic_status': economicStatus.storageKey,
          'visibility_status': AssetVisibilityStatus.archived.storageKey,
          'inclusion_quality': AssetInclusionQuality.needsReview.storageKey,
          'ended_ms': endedMs,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    final migratedPhysical = await db.query('physical_assets');
    final migratedReceivable = await db.query('receivable_assets');
    final after = _v33AssetTotals(migratedPhysical, migratedReceivable);
    if (before.physical != after.physical ||
        before.receivable != after.receivable) {
      throw StateError(
        'v33 asset migration changed net worth: '
        'physical ${before.physical}->${after.physical}, '
        'receivable ${before.receivable}->${after.receivable}',
      );
    }
  }

  static Future<void> _ensurePhysicalAssetAdvancedColumns(
    DatabaseExecutor db,
  ) async {
    for (final sql in [
      "ALTER TABLE physical_assets ADD COLUMN photo_path TEXT NOT NULL DEFAULT ''",
      "ALTER TABLE physical_assets ADD COLUMN invoice_path TEXT NOT NULL DEFAULT ''",
      "ALTER TABLE physical_assets ADD COLUMN depreciation_method TEXT NOT NULL DEFAULT ''",
      "ALTER TABLE physical_assets ADD COLUMN depreciation_base TEXT NOT NULL DEFAULT '0'",
      "ALTER TABLE physical_assets ADD COLUMN salvage_value TEXT NOT NULL DEFAULT '0'",
      'ALTER TABLE physical_assets ADD COLUMN useful_life_months INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE physical_assets ADD COLUMN depreciation_start_ms INTEGER',
      'ALTER TABLE physical_assets ADD COLUMN depreciation_paused INTEGER NOT NULL DEFAULT 0',
    ]) {
      try {
        await db.execute(sql);
      } catch (_) {}
    }
  }

  static Future<void> _ensureLiabilityTables(DatabaseExecutor db) async {
    await db.execute(_createLiabilityProfilesSql);
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_liability_profiles_status
      ON liability_profiles(status, repayment_day)
    ''');
  }

  Future<void> _applyCategoryTree(DatabaseExecutor db) async {
    for (final s in CategorySeed.all) {
      await db.insert(
        'categories',
        {
          'key': s.key,
          'name_zh': s.nameZh,
          'name_en': s.nameEn,
          'kind': s.kind.toJson(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    for (final s in CategorySeed.all) {
      int? parentId;
      if (s.parentKey != null) {
        parentId = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT id FROM categories WHERE key = ? LIMIT 1', [s.parentKey]));
      }
      await db.update(
        'categories',
        {
          'name_zh': s.nameZh,
          'name_en': s.nameEn,
          'parent_id': parentId,
        },
        where: 'key = ?',
        whereArgs: [s.key],
      );
    }
  }

  Future<void> _seedIfNeeded() async {
    final db = _db!;
    final accountCount = Sqflite.firstIntValue(await db
            .rawQuery('SELECT COUNT(*) FROM accounts WHERE is_deleted = 0')) ??
        0;
    if (accountCount > 0) return;

    await db.insert('accounts', {
      'uuid': _newUuid(),
      'name': '现金',
      'currency_code': 'CNY',
      'type': AccountType.cash.storageKey,
      'opening_balance': '0',
      'include_in_net_worth': 1,
      'created_ms': DateTime.now().millisecondsSinceEpoch,
      'updated_ms': DateTime.now().millisecondsSinceEpoch,
      'opening_balance_effective_ms': DateTime.now().millisecondsSinceEpoch,
      'opening_balance_quality': AccountOpeningBalanceQuality.exact.storageKey,
      'status': AccountStatus.active.storageKey,
    });
    await _applyCategoryTree(db);
  }

  Future<void> _loadAll({bool notify = true}) async {
    await _loadBooks();
    await _loadCurrentBook();
    await Future.wait([
      _loadAccounts(),
      _loadAccountBalanceCheckpoints(),
      _loadVerifiedNetWorthCheckpoints(),
      _loadCategories(),
      _loadTransactions(),
      _loadPhysicalAssetData(refreshSnapshot: false),
      _loadLiabilityProfiles(),
      _loadBudgetPeriods(),
      _loadBudgetV2(),
      _loadApiKey(),
      _loadRecordMode(),
      _loadAiPrivacyAccepted(),
      _loadWidgetPrivacyMode(),
      _loadRepaymentReminderEnabled(),
      _loadMoneyDisplaySettings(),
      _loadCategoryIconStyle(),
      _loadTransactionDisplayPreferences(),
      _loadProfileSettings(),
      _loadChatRetention(),
      _loadCategoryMemory(),
      _loadRecurringRules(),
      _loadSavingsGoals(),
      _loadTags(),
      _loadReports(),
      _loadDrawerOrder(),
      _loadStatCardOrder(),
      _loadStatCustomRange(),
    ]);
    if (notify) notifyListeners();
  }

  Future<void> _loadSavingsGoals() async {
    final rows =
        await _db!.query('savings_goals', orderBy: 'created_ms ASC, id ASC');
    _savingsGoals
      ..clear()
      ..addAll(rows.map(SavingsGoalEntity.fromMap));
  }

  Future<void> _loadTags() async {
    final rows = await _db!.query('tags', orderBy: 'id ASC');
    _tags
      ..clear()
      ..addAll(rows.map(TagEntity.fromMap));
  }

  Future<void> _loadReports() async {
    final rows = await _db!.query(
      'reports',
      orderBy: 'pinned_ms DESC, created_ms DESC, id DESC',
    );
    _reports
      ..clear()
      ..addAll(rows.map(ReportEntity.fromMap));
    _reportsViewCache = null;
  }

  Future<void> _loadBooks() async {
    final rows = await _db!.query('books', orderBy: 'sort_order ASC, id ASC');
    final loaded = rows.map(BookEntity.fromMap).toList();
    // 总账本 = 最早建的那本（id 最小），不可删、永远排第一。
    _defaultBookId = loaded.isEmpty
        ? 0
        : loaded.map((b) => b.id).reduce((a, b) => a < b ? a : b);
    // 排序：总账本 → 加星 → 其它（同组保持原顺序，稳定排序）。
    int rank(BookEntity b) => b.id == _defaultBookId ? 0 : (b.starred ? 1 : 2);
    final indexed = [for (var i = 0; i < loaded.length; i++) (i, loaded[i])];
    indexed.sort((a, b) {
      final r = rank(a.$2).compareTo(rank(b.$2));
      return r != 0 ? r : a.$1.compareTo(b.$1);
    });
    _books
      ..clear()
      ..addAll(indexed.map((e) => e.$2));
    _booksViewCache = null;
    _invalidateBalanceDerived();
  }

  Future<void> _ensureDefaultBook() async {
    final count = Sqflite.firstIntValue(
            await _db!.rawQuery('SELECT COUNT(*) FROM books')) ??
        0;
    if (count == 0) {
      await _db!.insert('books', {
        ..._syncStampNew(),
        'name': '总账本',
        'icon': '📒',
        'sort_order': 0,
        'created_ms': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  Future<void> _loadCurrentBook() async {
    final rows = await _db!.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['current_book_id'],
      limit: 1,
    );
    final saved = rows.isEmpty
        ? null
        : int.tryParse((rows.first['value'] as String?) ?? '');
    _currentBookId = saved != null && _books.any((b) => b.id == saved)
        ? saved
        : (_books.isNotEmpty ? _books.first.id : 1);
  }

  Future<void> _loadAccounts() async {
    final rows = await _db!.query(
      'accounts',
      where: "is_deleted = 0 AND status <> 'legacy_hidden'",
      orderBy: 'sort_order ASC, id ASC',
    );
    _accounts
      ..clear()
      ..addAll(rows.map(AccountEntity.fromMap));
    _invalidateBalanceDerived();
  }

  Future<void> _loadAccountBalanceCheckpoints() async {
    final rows = await _db!.query(
      'account_balance_checkpoints',
      orderBy: 'effective_ms ASC, sequence ASC, id ASC',
    );
    final coverageRows = await _db!.query(
      'account_checkpoint_covered_unknown_events',
    );
    _accountBalanceCheckpoints
      ..clear()
      ..addAll(rows.map(AccountBalanceCheckpointEntity.fromMap));
    _checkpointCoveredUnknownEventIds.clear();
    for (final row in coverageRows) {
      final checkpointId = row['checkpoint_id'] as int;
      final eventId = row['account_event_uuid'] as String? ?? '';
      if (eventId.isEmpty) continue;
      _checkpointCoveredUnknownEventIds
          .putIfAbsent(checkpointId, () => <String>{})
          .add(eventId);
    }
    _invalidateBalanceDerived();
  }

  NetWorthCurrencyCoverage _decodeCurrencyCoverage(String raw) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return NetWorthCurrencyCoverage(
        baseCurrency: decoded['base_currency'] as String? ?? 'CNY',
        coveredCurrencies: (decoded['covered'] as List<dynamic>? ?? const [])
            .map((value) => value.toString()),
        uncoveredCurrencies:
            (decoded['uncovered'] as List<dynamic>? ?? const [])
                .map((value) => value.toString()),
      );
    } catch (_) {
      return NetWorthCurrencyCoverage.single('CNY');
    }
  }

  Future<void> _loadVerifiedNetWorthCheckpoints() async {
    final headers = await _db!.query(
      'net_worth_verified_checkpoints',
      orderBy: 'as_of_ms ASC, id ASC',
    );
    final itemRows = await _db!.query(
      'net_worth_verified_checkpoint_items',
      orderBy: 'checkpoint_id ASC, object_type ASC, object_uuid ASC',
    );
    final itemsByCheckpoint = <int, List<NetWorthVerifiedCheckpointItem>>{};
    for (final row in itemRows) {
      final checkpointId = row['checkpoint_id'] as int;
      itemsByCheckpoint
          .putIfAbsent(checkpointId, () => [])
          .add(NetWorthVerifiedCheckpointItem(
            objectType: row['object_type'] as String? ?? 'unknown',
            objectUuid: row['object_uuid'] as String? ?? 'unknown',
            confirmedAmountMinor: decimalToBudgetCents(
              Decimal.tryParse(row['confirmed_amount'] as String? ?? '') ??
                  Decimal.zero,
            ),
            currencyCode: row['currency_code'] as String? ?? 'CNY',
            valueEffectiveAt: DateTime.fromMillisecondsSinceEpoch(
              row['value_effective_ms'] as int? ?? 0,
              isUtc: true,
            ),
            valueSource: row['value_source'] as String? ?? 'unknown',
            quality: row['quality'] as String? ?? 'partial',
          ));
    }
    _verifiedNetWorthCheckpoints.clear();
    for (final row in headers) {
      final reasons = <NetWorthVerifiedCheckpointReason>[];
      try {
        final decoded =
            jsonDecode(row['reasons_json'] as String? ?? '') as List;
        for (final value in decoded.whereType<Map>()) {
          reasons.add(NetWorthVerifiedCheckpointReason(
            code: value['code']?.toString() ?? 'partial',
            message: value['message']?.toString() ?? '核对范围不完整',
            details: {
              for (final entry
                  in (value['details'] as Map? ?? const {}).entries)
                entry.key.toString(): entry.value,
            },
          ));
        }
      } catch (_) {}
      final totalAssets = decimalToBudgetCents(
        Decimal.tryParse(row['total_assets'] as String? ?? '') ?? Decimal.zero,
      );
      final totalLiabilities = decimalToBudgetCents(
        Decimal.tryParse(row['total_liabilities'] as String? ?? '') ??
            Decimal.zero,
      );
      final netWorth = decimalToBudgetCents(
        Decimal.tryParse(row['net_worth'] as String? ?? '') ?? Decimal.zero,
      );
      _verifiedNetWorthCheckpoints.add(NetWorthVerifiedCheckpoint(
        header: NetWorthVerifiedCheckpointHeader(
          id: row['id'] as int,
          uuid: row['uuid'] as String? ?? 'legacy-${row['id']}',
          asOf: DateTime.fromMillisecondsSinceEpoch(
            row['as_of_ms'] as int,
            isUtc: true,
          ),
          knowledgeCutoff: DateTime.fromMillisecondsSinceEpoch(
            row['knowledge_cutoff_ms'] as int,
            isUtc: true,
          ),
          scopeVersion: row['scope_version'] as int? ?? 1,
          calculationVersion: row['calculation_version'] as int? ?? 1,
          currencyCoverage: _decodeCurrencyCoverage(
            row['currency_coverage_json'] as String? ?? '',
          ),
          totals: NetWorthVerifiedCheckpointTotals.checked(
            totalAssetsMinor: totalAssets,
            totalLiabilitiesMinor: totalLiabilities,
            netWorthMinor: netWorth,
          ),
          completeness: NetWorthVerifiedCheckpointCompletenessX.fromStorage(
            row['completeness'] as String?,
          ),
          incompletenessReasons: reasons,
          status: NetWorthVerifiedCheckpointStatusX.fromStorage(
            row['status'] as String?,
          ),
          supersedesId: row['supersedes_id'] as int?,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            row['created_ms'] as int,
            isUtc: true,
          ),
        ),
        items: itemsByCheckpoint[row['id'] as int] ?? const [],
      ));
    }
  }

  Future<void> _loadCategories() async {
    final rows = await _db!.query('categories');
    _categories
      ..clear()
      ..addAll(rows.map(CategoryEntity.fromMap));
    _allRecordsCache = null;
    _categoriesViewCache = null;
  }

  Future<void> _loadBudgetPeriods() async {
    final rows =
        await _db!.query('budget_periods', orderBy: 'start_ms ASC, id ASC');
    _budgetPeriods
      ..clear()
      ..addAll(rows.map(BudgetPeriod.fromMap));
  }

  List<BudgetFixedTemplateV2> _decodeBudgetFixedTemplates(String raw) {
    try {
      final decoded = jsonDecode(raw) as List;
      return [
        for (final value in decoded.whereType<Map>())
          BudgetFixedTemplateV2(
            id: value['id']?.toString() ?? '',
            name: value['name']?.toString() ?? '',
            plannedCents: int.tryParse(value['planned_cents'].toString()) ?? 0,
            dueValue: int.tryParse(value['due_value'].toString()) ?? 1,
          ),
      ].where((item) => item.id.isNotEmpty && item.plannedCents >= 0).toList();
    } catch (_) {
      return const [];
    }
  }

  Map<String, int> _decodeBudgetCategoryCents(String? raw) {
    if (raw == null) return const {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in decoded.entries)
          if ((int.tryParse(entry.value.toString()) ?? -1) >= 0)
            entry.key: int.parse(entry.value.toString()),
      };
    } catch (_) {
      return const {};
    }
  }

  Future<void> _loadBudgetV2() async {
    final planRows = await _db!.query('budget_plans', orderBy: 'id ASC');
    final revisionRows =
        await _db!.query('budget_plan_revisions', orderBy: 'id ASC');
    final overrideRows =
        await _db!.query('budget_cycle_overrides', orderBy: 'id ASC');
    final occurrenceRows = await _db!.query(
      'budget_fixed_commitment_occurrences',
      orderBy: 'cycle_start_day ASC, due_day ASC, id ASC',
    );
    _budgetPlansV2
      ..clear()
      ..addAll(planRows.map((row) => BudgetPlanV2(
            id: row['id'] as int,
            uuid: row['uuid'] as String,
            bookId: row['book_id'] as int,
            currencyCode: row['currency_code'] as String? ?? 'CNY',
            timezone: row['timezone'] as String? ?? 'device_local',
            name: row['name'] as String? ?? '',
            role: row['role'] as String? ?? 'primary',
            cadence:
                BudgetPlanCadenceV2X.fromStorage(row['cadence'] as String?),
            anchorStart: budgetCivilDayFromKey(row['anchor_start_day'] as int),
            monthStartDay: row['month_start_day'] as int?,
            weekStart: row['week_start'] as int?,
            endInclusive: row['end_day'] == null
                ? null
                : budgetCivilDayFromKey(row['end_day'] as int),
            expenseScope: BudgetExpenseScopeV2.fromJsonString(
              row['expense_scope_json'] as String?,
            ),
            status: BudgetPlanStatusV2X.fromStorage(row['status'] as String?),
            createdMs: row['created_ms'] as int? ?? 0,
            updatedMs: row['updated_ms'] as int? ?? 0,
          )));
    _budgetPlanRevisionsV2
      ..clear()
      ..addAll(revisionRows.map((row) => BudgetPlanRevisionV2(
            id: row['id'] as int,
            uuid: row['uuid'] as String,
            planId: row['plan_id'] as int,
            effectiveCycleStart: budgetCivilDayFromKey(
              row['effective_cycle_start_day'] as int,
            ),
            effectiveToCycleStart: row['effective_to_cycle_start_day'] == null
                ? null
                : budgetCivilDayFromKey(
                    row['effective_to_cycle_start_day'] as int,
                  ),
            amountCents: row['amount_cents'] as int,
            categoryBudgetsCents: _decodeBudgetCategoryCents(
              row['category_budgets_json'] as String?,
            ),
            monthlyIncomeCents: row['monthly_income_cents'] as int?,
            fixedTemplates: _decodeBudgetFixedTemplates(
              row['fixed_templates_json'] as String? ?? '[]',
            ),
            legacySourcePeriodId: row['legacy_source_period_id'] as int?,
            createdMs: row['created_ms'] as int? ?? 0,
            updatedMs: row['updated_ms'] as int? ?? 0,
          )));
    _budgetCycleOverridesV2
      ..clear()
      ..addAll(overrideRows.map((row) => BudgetCycleOverrideV2(
            id: row['id'] as int,
            uuid: row['uuid'] as String,
            planId: row['plan_id'] as int,
            cycleStart: budgetCivilDayFromKey(row['cycle_start_day'] as int),
            cycleEndInclusive:
                budgetCivilDayFromKey(row['cycle_end_day'] as int),
            targetAmountCents: row['target_amount_cents'] as int,
            categoryBudgetsCents: row['category_budgets_json'] == null
                ? null
                : _decodeBudgetCategoryCents(
                    row['category_budgets_json'] as String?,
                  ),
            inputIntent: BudgetOverrideIntent.fromStorage(
              row['input_intent'] as String?,
            ),
            inputDeltaCents: row['input_delta_cents'] as int?,
            createdMs: row['created_ms'] as int? ?? 0,
            updatedMs: row['updated_ms'] as int? ?? 0,
          )));
    final plansById = {for (final plan in _budgetPlansV2) plan.id: plan};
    _budgetFixedOccurrencesV2.clear();
    for (final row in occurrenceRows) {
      final plan = plansById[row['plan_id'] as int];
      if (plan == null) continue;
      FixedCommitmentResolutionStatus status;
      try {
        status = FixedCommitmentResolutionStatus.fromStorage(
          row['resolution_status'] as String? ?? 'planned',
        );
      } catch (_) {
        status = FixedCommitmentResolutionStatus.requiresReview;
      }
      FixedCommitmentReviewReason? reviewReason;
      final reviewRaw = row['review_reason'] as String? ?? '';
      if (reviewRaw.isNotEmpty) {
        try {
          reviewReason = FixedCommitmentReviewReason.fromStorage(reviewRaw);
        } catch (_) {
          reviewReason = FixedCommitmentReviewReason.invalidScope;
        }
      }
      _budgetFixedOccurrencesV2.add(BudgetFixedOccurrenceEntity(
        id: row['id'] as int,
        uuid: row['uuid'] as String,
        revisionId: row['revision_id'] as int,
        occurrence: FixedCommitmentOccurrence(
          id: row['id'] as int,
          planId: plan.id,
          bookId: plan.bookId,
          currencyCode: plan.currencyCode,
          templateId: row['template_id'] as String,
          cycleStart: budgetCivilDayFromKey(row['cycle_start_day'] as int),
          cycleEnd: budgetCivilDayFromKey(row['cycle_end_day'] as int),
          dueDate: budgetCivilDayFromKey(row['due_day'] as int),
          plannedCents: row['planned_cents'] as int,
          resolutionStatus: status,
          reviewReason: reviewReason,
          matchedTransactionFamilyId:
              row['matched_transaction_family_uuid'] as String?,
          resolvedMs: row['resolved_ms'] as int?,
        ),
        resolvedMs: row['resolved_ms'] as int?,
        createdMs: row['created_ms'] as int? ?? 0,
        updatedMs: row['updated_ms'] as int? ?? 0,
      ));
    }
  }

  Future<void> _materializeBudgetV2Occurrences() async {
    if (_budgetPlansV2.isEmpty) return;
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    await _db!.transaction((txn) async {
      for (final plan in _budgetPlansV2) {
        if (!plan.isPrimary) continue;
        final reference =
            now.isBefore(plan.anchorStart) ? plan.anchorStart : now;
        final current = plan.cycleFor(reference);
        final cycles = [
          current,
          plan.cycleFor(current.endExclusive),
        ];
        for (final cycle in cycles) {
          if (cycle.start.isBefore(plan.anchorStart) ||
              (plan.endInclusive != null &&
                  cycle.start.isAfter(plan.endInclusive!))) {
            continue;
          }
          final revisions = _budgetPlanRevisionsV2
              .where((revision) => revision.appliesTo(cycle))
              .toList()
            ..sort((left, right) =>
                left.effectiveCycleStart.compareTo(right.effectiveCycleStart));
          final revision = revisions.lastOrNull;
          if (revision == null) continue;
          await _insertBudgetOccurrencesForRevision(
            txn,
            plan: plan,
            revisionId: revision.id,
            cycle: cycle,
            templates: revision.fixedTemplates,
            nowMs: nowMs,
          );
        }
      }
    });
    await _loadBudgetV2();
  }

  Future<void> _loadApiKey() async {
    const keys = [
      'ai_provider_type',
      'custom_ai_display_name',
      'custom_ai_base_url',
      'custom_ai_model',
      'report_ai_model',
      'available_ai_models',
      'deepseek_api_key',
      'custom_ai_api_key',
      'ai_providers_json',
      'ai_record_provider_id',
      'chat_current_provider_id',
      'chat_current_model',
      'ai_record_provider_type',
      'ai_chat_provider_type',
      'ai_report_provider_type',
      'ai_record_route_mode',
      'ai_chat_route_mode',
      'ai_report_route_mode',
      'ai_record_endpoint_type',
      'ai_chat_endpoint_type',
      'ai_report_endpoint_type',
      'ai_record_reasoning_effort',
      'ai_chat_reasoning_effort',
      'ai_report_reasoning_effort',
      'ai_task_config_version',
    ];
    final rows = await _db!.query(
      'app_settings',
      where: 'key IN (${List.filled(keys.length, '?').join(', ')})',
      whereArgs: keys,
    );
    final settings = {
      for (final row in rows)
        row['key'] as String: (row['value'] as String?) ?? '',
    };
    _aiProviderType = AiProviderTypeX.fromStorage(settings['ai_provider_type']);
    _customAiDisplayName =
        (settings['custom_ai_display_name'] ?? '').trim().isEmpty
            ? '自定义'
            : settings['custom_ai_display_name']!.trim();
    _customAiBaseUrl = (settings['custom_ai_base_url'] ?? '').trim().isEmpty
        ? AiProviderConfig.customDefaultBaseUrl
        : settings['custom_ai_base_url']!.trim();
    _customAiModel = (settings['custom_ai_model'] ?? '').trim().isEmpty
        ? AiProviderConfig.customDefaultModel
        : settings['custom_ai_model']!.trim();
    _reportAiModel = (settings['report_ai_model'] ?? '').trim().isEmpty
        ? AiProviderConfig.customReportDefaultModel
        : settings['report_ai_model']!.trim();
    final rawModels = settings['available_ai_models'] ?? '';
    _availableModels = rawModels.isEmpty
        ? []
        : rawModels.split(',').where((s) => s.isNotEmpty).toList();

    _deepSeekApiKey = await _loadSecretWithLegacyFallback(
      secureKey: 'deepseek_api_key',
      legacySettingKey: 'deepseek_api_key',
      configuredSettingKey: 'deepseek_api_key_configured',
      legacyValue: settings['deepseek_api_key'],
    );
    _customAiApiKey = await _loadSecretWithLegacyFallback(
      secureKey: 'custom_ai_api_key',
      legacySettingKey: 'custom_ai_api_key',
      configuredSettingKey: 'custom_ai_api_key_configured',
      legacyValue: settings['custom_ai_api_key'],
    );

    final hasCustomKey = _customAiApiKey?.trim().isNotEmpty ?? false;
    final reportFallback =
        hasCustomKey ? AiProviderType.custom : _aiProviderType;
    _recordAiProviderType = AiProviderTypeX.fromStorage(
      settings['ai_record_provider_type'] ?? _aiProviderType.storageKey,
    );
    _chatAiProviderType = AiProviderTypeX.fromStorage(
      settings['ai_chat_provider_type'] ?? _aiProviderType.storageKey,
    );
    _reportAiProviderType = AiProviderTypeX.fromStorage(
      settings['ai_report_provider_type'] ?? reportFallback.storageKey,
    );
    _recordAiRouteMode = AiRouteModeX.fromStorage(
      settings['ai_record_route_mode'],
    );
    _chatAiRouteMode = AiRouteModeX.fromStorage(
      settings['ai_chat_route_mode'],
    );
    _reportAiRouteMode = AiRouteModeX.fromStorage(
      settings['ai_report_route_mode'],
    );
    _recordAiEndpointType = AiEndpointTypeX.fromStorage(
      settings['ai_record_endpoint_type'] ??
          AiEndpointType.chatCompletions.storageKey,
    );
    _chatAiEndpointType = AiEndpointTypeX.fromStorage(
      settings['ai_chat_endpoint_type'] ?? AiEndpointType.auto.storageKey,
    );
    _reportAiEndpointType = AiEndpointTypeX.fromStorage(
      settings['ai_report_endpoint_type'] ??
          AiEndpointType.responses.storageKey,
    );
    _recordAiReasoningEffort = AiReasoningEffortX.fromStorage(
      settings['ai_record_reasoning_effort'],
      fallback: AiReasoningEffort.none,
    );
    _chatAiReasoningEffort = AiReasoningEffortX.fromStorage(
      settings['ai_chat_reasoning_effort'],
      fallback: AiReasoningEffort.low,
    );
    _reportAiReasoningEffort = AiReasoningEffortX.fromStorage(
      settings['ai_report_reasoning_effort'],
      fallback: AiReasoningEffort.xhigh,
    );
    await _loadConfiguredAiProviders(settings);
  }

  AiConfiguredProvider? _firstUsableProvider({String? excludingId}) {
    final candidates = _aiProviders.where(
      (provider) => provider.id != excludingId,
    );
    return candidates.where((provider) => provider.hasKey).firstOrNull ??
        candidates.firstOrNull;
  }

  Future<void> _loadConfiguredAiProviders(Map<String, String> settings) async {
    final decodedProviders = <AiConfiguredProvider>[];
    final raw = settings['ai_providers_json']?.trim() ?? '';
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final entry in decoded.whereType<Map>()) {
            final metadata = Map<String, dynamic>.from(entry);
            final id = (metadata['id'] as String? ?? '').trim();
            if (id.isEmpty || decodedProviders.any((item) => item.id == id)) {
              continue;
            }
            final key = await _loadConfiguredProviderSecret(id);
            final legacyKey = id == 'legacy-custom' ? _customAiApiKey : null;
            decodedProviders.add(
              AiConfiguredProvider.fromJson(
                metadata,
                apiKey: key ?? legacyKey ?? '',
              ).copyWith(builtIn: id == 'deepseek'),
            );
          }
        }
      } catch (_) {
        // Malformed metadata fails closed into the legacy migration below.
      }
    }

    var deepSeek = decodedProviders
        .where((provider) => provider.id == 'deepseek')
        .firstOrNull;
    if (deepSeek == null) {
      final legacyModels = _aiProviderType == AiProviderType.deepseek
          ? _availableModels
          : const <String>[];
      deepSeek = AiConfiguredProvider(
        id: 'deepseek',
        type: AiProviderType.deepseek,
        displayName: 'DeepSeek',
        baseUrl: AiProviderConfig.deepSeekBaseUrl,
        apiKey: _deepSeekApiKey ?? '',
        model: AiProviderConfig.deepSeekModel,
        models: legacyModels,
        endpointType: AiEndpointType.chatCompletions,
        builtIn: true,
      );
      decodedProviders.insert(0, deepSeek);
    } else {
      deepSeek = deepSeek.copyWith(
        type: AiProviderType.deepseek,
        displayName: 'DeepSeek',
        baseUrl: AiProviderConfig.deepSeekBaseUrl,
        apiKey: deepSeek.apiKey.trim().isEmpty
            ? (_deepSeekApiKey ?? '')
            : deepSeek.apiKey,
        builtIn: true,
      );
      decodedProviders[decodedProviders
          .indexWhere((item) => item.id == 'deepseek')] = deepSeek;
    }
    // The legacy DeepSeek secret predates provider-scoped storage. Seed the
    // new namespace once so future provider metadata reloads do not depend on
    // the compatibility key.
    if (deepSeek.apiKey.trim().isNotEmpty) {
      await _saveSecret(
        secureKey: _providerSecretKey(deepSeek.id),
        legacySettingKey: _providerSecretKey(deepSeek.id),
        configuredSettingKey: '${_providerSecretKey(deepSeek.id)}_configured',
        value: deepSeek.apiKey,
      );
    }

    final hasLegacyCustom = (_customAiApiKey?.trim().isNotEmpty ?? false) ||
        _aiProviderType == AiProviderType.custom ||
        _customAiDisplayName != '自定义' ||
        _customAiBaseUrl != AiProviderConfig.customDefaultBaseUrl ||
        _customAiModel != AiProviderConfig.customDefaultModel;
    if (hasLegacyCustom &&
        !decodedProviders.any((provider) => provider.id == 'legacy-custom')) {
      final legacyCustom = AiConfiguredProvider(
        id: 'legacy-custom',
        type: AiProviderType.custom,
        displayName: _customAiDisplayName,
        baseUrl: _customAiBaseUrl,
        apiKey: _customAiApiKey ?? '',
        model: _customAiModel,
        models: _aiProviderType == AiProviderType.custom
            ? _availableModels
            : const <String>[],
        endpointType: AiEndpointType.auto,
      );
      decodedProviders.add(legacyCustom);
      if (legacyCustom.apiKey.trim().isNotEmpty) {
        await _saveSecret(
          secureKey: _providerSecretKey(legacyCustom.id),
          legacySettingKey: _providerSecretKey(legacyCustom.id),
          configuredSettingKey:
              '${_providerSecretKey(legacyCustom.id)}_configured',
          value: legacyCustom.apiKey,
        );
      }
    }

    _aiProviders
      ..clear()
      ..addAll(decodedProviders);

    String? providerIdForLegacyType(AiProviderType type) {
      if (type == AiProviderType.deepseek) return 'deepseek';
      return _aiProviders
          .where((provider) => provider.type == AiProviderType.custom)
          .firstOrNull
          ?.id;
    }

    final requestedRecordId = settings['ai_record_provider_id']?.trim();
    _recordAiProviderId = aiProviderById(requestedRecordId) != null
        ? requestedRecordId
        : providerIdForLegacyType(_recordAiProviderType);
    _recordAiProviderId ??= _firstUsableProvider()?.id;

    final requestedChatId = settings['chat_current_provider_id']?.trim();
    _chatCurrentProviderId = aiProviderById(requestedChatId) != null
        ? requestedChatId
        : providerIdForLegacyType(_chatAiProviderType);
    _chatCurrentProviderId ??= _firstUsableProvider()?.id;
    final chatProvider = aiProviderById(_chatCurrentProviderId);
    final requestedModel = settings['chat_current_model']?.trim();
    _chatCurrentModel = requestedModel != null &&
            requestedModel.isNotEmpty &&
            (chatProvider?.models.contains(requestedModel) ?? false)
        ? requestedModel
        : chatProvider?.model;

    // Persist the normalized representation once. This keeps migrations
    // idempotent while retaining all legacy settings for downgrade safety.
    await _persistAiProviderMetadata(notify: false);
  }

  Future<String?> _loadConfiguredProviderSecret(String id) async {
    final secureKey = 'ai_provider_api_key_$id';
    final secure = await SecureKeyStore.read(secureKey);
    if (secure != null && secure.trim().isNotEmpty) return secure.trim();
    final rows = await _db!.query(
      'app_settings',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: [secureKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final fallback = (rows.first['value'] as String? ?? '').trim();
    return fallback.isEmpty ? null : fallback;
  }

  Future<String?> _loadSecretWithLegacyFallback({
    required String secureKey,
    required String legacySettingKey,
    required String configuredSettingKey,
    String? legacyValue,
  }) async {
    final secure = await SecureKeyStore.read(secureKey);
    if (secure != null && secure.isNotEmpty) return secure;

    final legacy = legacyValue?.trim();
    if (legacy == null || legacy.isEmpty) return null;
    final moved = await SecureKeyStore.write(secureKey, legacy);
    if (moved) {
      await _db!.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: [legacySettingKey],
      );
      await _db!.insert(
        'app_settings',
        {'key': configuredSettingKey, 'value': '1'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    return legacy;
  }

  Future<void> _loadRecordMode() async {
    final rows = await _db!.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['record_ai_mode'],
      limit: 1,
    );
    _recordAiMode = rows.isNotEmpty && (rows.first['value'] as String?) == '1';
  }

  Future<void> _loadAiPrivacyAccepted() async {
    final rows = await _db!.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['ai_privacy_accepted'],
      limit: 1,
    );
    _aiPrivacyAccepted =
        rows.isNotEmpty && (rows.first['value'] as String?) == '1';
  }

  Future<void> setAiPrivacyAccepted(bool accepted) async {
    _aiPrivacyAccepted = accepted;
    await _db!.insert(
      'app_settings',
      {'key': 'ai_privacy_accepted', 'value': accepted ? '1' : '0'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  Future<void> _loadWidgetPrivacyMode() async {
    final rows = await _db!.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['widget_privacy_mode'],
      limit: 1,
    );
    _widgetPrivacyMode =
        rows.isNotEmpty && (rows.first['value'] as String?) == '1';
  }

  Future<void> setWidgetPrivacyMode(bool enabled) async {
    if (_widgetPrivacyMode == enabled) return;
    _widgetPrivacyMode = enabled;
    await _db!.insert(
      'app_settings',
      {'key': 'widget_privacy_mode', 'value': enabled ? '1' : '0'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  Future<void> _loadRepaymentReminderEnabled() async {
    final rows = await _db!.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['repayment_reminder_enabled'],
      limit: 1,
    );
    // 没存过=老用户/新建库：默认开（还款提醒方案拍板的默认值）。
    _repaymentReminderEnabled =
        rows.isEmpty || (rows.first['value'] as String?) == '1';
  }

  Future<void> setRepaymentReminderEnabled(bool enabled) async {
    if (_repaymentReminderEnabled == enabled) return;
    _repaymentReminderEnabled = enabled;
    await _db!.insert(
      'app_settings',
      {'key': 'repayment_reminder_enabled', 'value': enabled ? '1' : '0'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  Future<void> _loadMoneyDisplaySettings() async {
    final rows = await _db!.query(
      'app_settings',
      where: 'key IN (?, ?)',
      whereArgs: ['money_decimal_places', 'money_integer_rounding_mode'],
    );
    final map = {
      for (final row in rows)
        row['key'] as String: (row['value'] as String?) ?? '',
    };
    _moneyDecimalPlaces =
        (int.tryParse(map['money_decimal_places'] ?? '') ?? 2).clamp(0, 2);
    _moneyIntegerRoundingMode =
        _parseMoneyIntegerRoundingMode(map['money_integer_rounding_mode']);
    MoneyFormat.configure(
      decimalPlaces: _moneyDecimalPlaces,
      integerRoundingMode: _moneyIntegerRoundingMode,
    );
  }

  Future<void> setMoneyDecimalPlaces(int places) async {
    final next = places.clamp(0, 2);
    if (_moneyDecimalPlaces == next) return;
    _moneyDecimalPlaces = next;
    MoneyFormat.configure(
      decimalPlaces: _moneyDecimalPlaces,
      integerRoundingMode: _moneyIntegerRoundingMode,
    );
    await _db!.insert(
      'app_settings',
      {'key': 'money_decimal_places', 'value': '$next'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  Future<void> setMoneyIntegerRoundingMode(
    MoneyIntegerRoundingMode mode,
  ) async {
    if (_moneyIntegerRoundingMode == mode) return;
    _moneyIntegerRoundingMode = mode;
    MoneyFormat.configure(
      decimalPlaces: _moneyDecimalPlaces,
      integerRoundingMode: _moneyIntegerRoundingMode,
    );
    await _db!.insert(
      'app_settings',
      {
        'key': 'money_integer_rounding_mode',
        'value': _moneyIntegerRoundingMode.name,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  MoneyIntegerRoundingMode _parseMoneyIntegerRoundingMode(String? raw) {
    for (final mode in MoneyIntegerRoundingMode.values) {
      if (mode.name == raw) return mode;
    }
    return MoneyIntegerRoundingMode.round;
  }

  Future<void> _loadCategoryIconStyle() async {
    final rows = await _db!.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['category_icon_style'],
      limit: 1,
    );
    _categoryIconStyle = CategoryIconStyleX.fromStorage(
      rows.isEmpty ? null : rows.first['value'] as String?,
    );
  }

  Future<void> setCategoryIconStyle(CategoryIconStyle style) async {
    if (_categoryIconStyle == style) return;
    _categoryIconStyle = style;
    await _db!.insert(
      'app_settings',
      {'key': 'category_icon_style', 'value': style.storageKey},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  Future<void> _loadTransactionDisplayPreferences() async {
    const keys = [
      'transaction_card_display_mode',
      'user_message_bubble_style',
      'asset_view_tab',
    ];
    final rows = await _db!.query(
      'app_settings',
      where: 'key IN (?, ?, ?)',
      whereArgs: keys,
    );
    final settings = {
      for (final row in rows)
        row['key'] as String: (row['value'] as String?) ?? '',
    };
    _transactionCardDisplayMode = TransactionCardDisplayModeX.fromStorage(
      settings['transaction_card_display_mode'],
    );
    _userMessageBubbleStyle = UserMessageBubbleStyleX.fromStorage(
      settings['user_message_bubble_style'],
    );
    final tabIdx = int.tryParse(settings['asset_view_tab'] ?? '');
    if (tabIdx != null && tabIdx >= 0 && tabIdx <= 2) {
      _lastAssetViewTabIndex = tabIdx;
    }
  }

  Future<void> setTransactionCardDisplayMode(
    TransactionCardDisplayMode mode,
  ) async {
    if (_transactionCardDisplayMode == mode) return;
    _transactionCardDisplayMode = mode;
    await _db!.insert(
      'app_settings',
      {'key': 'transaction_card_display_mode', 'value': mode.storageKey},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  Future<void> setUserMessageBubbleStyle(
    UserMessageBubbleStyle style,
  ) async {
    if (_userMessageBubbleStyle == style) return;
    _userMessageBubbleStyle = style;
    await _db!.insert(
      'app_settings',
      {'key': 'user_message_bubble_style', 'value': style.storageKey},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  Future<void> setLastAssetViewTabIndex(int index) async {
    if (_lastAssetViewTabIndex == index) return;
    _lastAssetViewTabIndex = index;
    // 纯导航偏好，fire-and-forget；数据库已关闭时静默忽略（测试 teardown 时序）。
    try {
      await _db!.insert(
        'app_settings',
        {'key': 'asset_view_tab', 'value': index.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  String get profileNickname => _profileNickname;
  String get profileAvatarPath => _profileAvatarPath;

  Future<void> _loadProfileSettings() async {
    const keys = ['profile_nickname', 'profile_avatar_path'];
    final rows = await _db!.query(
      'app_settings',
      where: 'key IN (?, ?)',
      whereArgs: keys,
    );
    final map = {
      for (final row in rows)
        row['key'] as String: (row['value'] as String?) ?? '',
    };
    final nickname = (map['profile_nickname'] ?? '').trim();
    // 昵称是「用户的名字」不是 App 的名字：没设置就留空（UI 显示引导文案），
    // 旧版曾把 App 名当默认值写进库，读到它一律视为未设置。
    _profileNickname = nickname == '肥喵记账' ? '' : nickname;
    _profileAvatarPath = (map['profile_avatar_path'] ?? '').trim();
  }

  Future<void> setProfileNickname(String nickname) async {
    final trimmed = nickname.trim();
    final normalized = trimmed.length > 12 ? trimmed.substring(0, 12) : trimmed;
    if (_profileNickname == normalized) return;
    _profileNickname = normalized;
    await _db!.insert(
      'app_settings',
      {'key': 'profile_nickname', 'value': normalized},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  Future<String> saveProfileAvatarBytes(
    Uint8List bytes, {
    Directory? documentsDir,
  }) async {
    final docs = documentsDir ?? await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'profile'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final dest = File(p.join(dir.path, 'avatar.png'));
    final tmp = File(p.join(
      dir.path,
      'avatar.${DateTime.now().millisecondsSinceEpoch}.tmp',
    ));
    await tmp.writeAsBytes(bytes, flush: true);
    if (await dest.exists()) {
      final old = File(p.join(dir.path, 'avatar.old.tmp'));
      try {
        if (await old.exists()) await old.delete();
        await dest.rename(old.path);
        await tmp.rename(dest.path);
        await old.delete();
      } catch (_) {
        if (await dest.exists()) await dest.delete();
        await tmp.rename(dest.path);
      }
    } else {
      await tmp.rename(dest.path);
    }
    _profileAvatarPath = dest.path;
    await _db!.insert(
      'app_settings',
      {'key': 'profile_avatar_path', 'value': dest.path},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
    return dest.path;
  }

  /// 记住记账模式（AI / 手动），下次启动沿用。
  Future<void> setRecordAiMode(bool ai) async {
    if (_recordAiMode == ai) return;
    _recordAiMode = ai;
    await _db!.insert(
      'app_settings',
      {'key': 'record_ai_mode', 'value': ai ? '1' : '0'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------------------------------------------------------------------------
  // AI 对话历史（跨重启持久化 + 按「保存时长」自动清理）
  // ---------------------------------------------------------------------------

  /// 对话保存天数（30 = 一个月，180 = 半年）。
  int get chatRetentionDays => _chatRetentionDays;

  Future<void> _loadChatRetention() async {
    final rows = await _db!.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['chat_retention_days'],
      limit: 1,
    );
    final v = rows.isEmpty
        ? null
        : int.tryParse((rows.first['value'] as String?) ?? '');
    _chatRetentionDays = (v != null && v > 0) ? v : 30;
  }

  /// 设置对话保存时长（天）。设置后立即清理超期对话。
  Future<void> setChatRetentionDays(int days) async {
    if (days <= 0) return;
    _chatRetentionDays = days;
    await _db!.insert(
      'app_settings',
      {'key': 'chat_retention_days', 'value': '$days'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _pruneChatMessages();
    notifyListeners();
  }

  /// 删除超过保存时长的对话。
  Future<void> _pruneChatMessages() async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: _chatRetentionDays))
        .millisecondsSinceEpoch;
    await _db!
        .delete('chat_messages', where: 'created_ms < ?', whereArgs: [cutoff]);
  }

  /// 读取保存的对话（先清理超期，再按时间正序返回）。
  Future<List<Map<String, Object?>>> loadChatMessages() async {
    await _pruneChatMessages();
    return _db!.query('chat_messages', orderBy: 'created_ms ASC, id ASC');
  }

  /// 追加一条对话消息。
  Future<int> addChatMessage({
    required String role,
    String text = '',
    String question = '',
  }) async {
    return _db!.insert('chat_messages', {
      'role': role,
      'text': text,
      'question': question,
      'created_ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<int> addReport({
    required String type,
    required String title,
    required String summary,
    required String markdown,
    DateTime? periodStart,
    DateTime? periodEnd,
    int? bookId,
  }) async {
    final id = await _db!.insert('reports', {
      'book_id': bookId ?? _currentBookId,
      'type': type,
      'title': title,
      'summary': summary,
      'markdown': markdown,
      'period_start_ms': (periodStart ?? DateTime.now()).millisecondsSinceEpoch,
      'period_end_ms': (periodEnd ?? DateTime.now()).millisecondsSinceEpoch,
      'created_ms': DateTime.now().millisecondsSinceEpoch,
      'pinned_ms': 0,
    });
    await _loadReports();
    notifyListeners();
    return id;
  }

  Future<ReportGenerationLease> acquireReportGenerationLease() =>
      _reportExecutionFence.acquire();

  Future<T> guardReportGeneration<T>(
    ReportGenerationLease lease,
    Future<T> Function() action,
  ) =>
      lease.guard(
        action,
        readJobUuid: _reportJobUuidById,
      );

  Future<String?> _reportJobUuidById(int id) async {
    final db = _db;
    if (db == null) return null;
    final rows = await db.query(
      'report_jobs',
      columns: ['uuid'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final uuid = (rows.single['uuid'] as String? ?? '').trim();
    return uuid.isEmpty ? null : uuid;
  }

  Future<ReportJobEntity> createReportJob({
    required String question,
    required String type,
    required String title,
    required DateTime periodStart,
    required DateTime periodEnd,
    int? bookId,
    int? reportId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db!.delete(
      'report_jobs',
      where: "status IN ('completed', 'failed') AND updated_ms < ?",
      whereArgs: [now - const Duration(days: 14).inMilliseconds],
    );
    final id = await _db!.insert('report_jobs', {
      'uuid': _newUuid(),
      'book_id': bookId ?? _currentBookId,
      'report_id': reportId,
      'question': question,
      'type': type,
      'title': title,
      'period_start_ms': periodStart.millisecondsSinceEpoch,
      'period_end_ms': periodEnd.millisecondsSinceEpoch,
      'status': 'queued',
      'stage': 'collect',
      'error': '',
      'created_ms': now,
      'updated_ms': now,
    });
    final rows = await _db!.query(
      'report_jobs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return ReportJobEntity.fromMap(rows.single);
  }

  Future<List<ReportJobEntity>> pendingReportJobs() async {
    final db = _db;
    if (db == null) return const <ReportJobEntity>[];
    final rows = await db.query(
      'report_jobs',
      where: "status IN ('queued', 'running')",
      orderBy: 'created_ms ASC, id ASC',
    );
    return rows.map(ReportJobEntity.fromMap).toList(growable: false);
  }

  Future<ReportJobEntity?> reportJobById(int id) async {
    final db = _db;
    if (db == null) return null;
    final rows = await db.query(
      'report_jobs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : ReportJobEntity.fromMap(rows.first);
  }

  Future<void> updateReportJob(
    int id, {
    String? expectedUuid,
    String? status,
    String? stage,
    String? error,
    int? reportId,
  }) async {
    final values = <String, Object?>{
      'updated_ms': DateTime.now().millisecondsSinceEpoch,
    };
    if (status != null) values['status'] = status;
    if (stage != null) values['stage'] = stage;
    if (error != null) values['error'] = error;
    if (reportId != null) values['report_id'] = reportId;
    final where = expectedUuid == null ? 'id = ?' : 'id = ? AND uuid = ?';
    final whereArgs = <Object?>[id, if (expectedUuid != null) expectedUuid];
    final updated = await _db!.update(
      'report_jobs',
      values,
      where: where,
      whereArgs: whereArgs,
    );
    if (updated != 1) {
      throw StateError('report job does not exist or UUID does not match');
    }
  }

  /// 报告正文、聊天报告卡和 job 完成状态原子提交。
  /// WorkManager 在进程被杀后可能重试；只要这个事务成功，再次执行同一 job
  /// 会直接返回既有报告，不会生成第二份文档或第二张聊天卡。
  Future<ReportEntity> completeReportJob({
    required int jobId,
    String? expectedJobUuid,
    required String summary,
    required String markdown,
  }) async {
    final reportId = await _db!.transaction<int>((txn) async {
      final jobRows = await txn.query(
        'report_jobs',
        where: expectedJobUuid == null ? 'id = ?' : 'id = ? AND uuid = ?',
        whereArgs: [jobId, if (expectedJobUuid != null) expectedJobUuid],
        limit: 1,
      );
      if (jobRows.isEmpty) {
        throw StateError('report job does not exist or UUID does not match');
      }
      final job = jobRows.first;
      final existingReportId = job['report_id'] as int?;
      if (job['status'] == 'completed' && existingReportId != null) {
        return existingReportId;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      late final int id;
      if (existingReportId == null) {
        id = await txn.insert('reports', {
          'book_id': job['book_id'] as int?,
          'type': job['type'] as String,
          'title': job['title'] as String,
          'summary': summary,
          'markdown': markdown,
          'period_start_ms': job['period_start_ms'] as int,
          'period_end_ms': job['period_end_ms'] as int,
          'created_ms': now,
          'pinned_ms': 0,
        });
        await txn.insert('chat_messages', {
          'role': 'report',
          'text': jsonEncode({'reportId': id, 'summary': summary}),
          'question': job['question'] as String? ?? '',
          'created_ms': now,
        });
      } else {
        id = existingReportId;
        await txn.update(
          'reports',
          {
            'title': job['title'] as String,
            'summary': summary,
            'markdown': markdown,
            'created_ms': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        final chatRows = await txn.query(
          'chat_messages',
          columns: ['id', 'text'],
          where: 'role = ?',
          whereArgs: ['report'],
        );
        for (final row in chatRows) {
          try {
            final decoded = jsonDecode(row['text'] as String? ?? '');
            if (decoded is! Map ||
                (decoded['reportId'] as num?)?.toInt() != id) {
              continue;
            }
            final updated = Map<String, Object?>.from(decoded)
              ..['summary'] = summary;
            await txn.update(
              'chat_messages',
              {'text': jsonEncode(updated)},
              where: 'id = ?',
              whereArgs: [row['id']],
            );
          } catch (_) {}
        }
      }

      final updated = await txn.update(
        'report_jobs',
        {
          'status': 'completed',
          'stage': 'save',
          'report_id': id,
          'error': '',
          'updated_ms': now,
        },
        where: expectedJobUuid == null ? 'id = ?' : 'id = ? AND uuid = ?',
        whereArgs: [jobId, if (expectedJobUuid != null) expectedJobUuid],
      );
      if (updated != 1) {
        throw StateError('report job does not exist or UUID does not match');
      }
      return id;
    });
    await _loadReports();
    notifyListeners();
    final report = _reports.where((item) => item.id == reportId).firstOrNull;
    if (report == null) throw StateError('report row missing after commit');
    return report;
  }

  Future<void> reloadReportsFromStorage() async {
    await _loadReports();
    notifyListeners();
  }

  Future<ReportEntity?> getReport(int id) async {
    for (final report in _reports) {
      if (report.id == id) return report;
    }
    final rows = await _db!.query(
      'reports',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : ReportEntity.fromMap(rows.first);
  }

  Future<void> setReportPinned(int id, bool pinned) async {
    await _db!.update(
      'reports',
      {'pinned_ms': pinned ? DateTime.now().millisecondsSinceEpoch : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _loadReports();
    notifyListeners();
  }

  Future<void> updateReportContent(
    int id, {
    required String summary,
    required String markdown,
    String? title,
  }) async {
    final values = <String, Object?>{
      'summary': summary,
      'markdown': markdown,
      'created_ms': DateTime.now().millisecondsSinceEpoch,
    };
    if (title != null && title.trim().isNotEmpty) {
      values['title'] = title.trim();
    }
    await _db!.transaction((txn) async {
      await txn.update(
        'reports',
        values,
        where: 'id = ?',
        whereArgs: [id],
      );
      final chatRows = await txn.query(
        'chat_messages',
        columns: ['id', 'text'],
        where: 'role = ?',
        whereArgs: ['report'],
      );
      for (final row in chatRows) {
        try {
          final decoded = jsonDecode(row['text'] as String? ?? '');
          if (decoded is! Map || (decoded['reportId'] as num?)?.toInt() != id) {
            continue;
          }
          final updated = Map<String, Object?>.from(decoded)
            ..['summary'] = summary;
          await txn.update(
            'chat_messages',
            {'text': jsonEncode(updated)},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        } catch (_) {}
      }
    });
    await _loadReports();
    notifyListeners();
  }

  Future<void> deleteReport(int id) async {
    await _db!.transaction((txn) async {
      await txn.delete('reports', where: 'id = ?', whereArgs: [id]);
      final rows = await txn.query(
        'chat_messages',
        columns: ['id', 'text'],
        where: 'role = ?',
        whereArgs: ['report'],
      );
      final orphanIds = <int>[];
      for (final row in rows) {
        try {
          final decoded = jsonDecode(row['text'] as String? ?? '');
          final reportId =
              decoded is Map ? (decoded['reportId'] as num?)?.toInt() : null;
          if (reportId == id) orphanIds.add(row['id'] as int);
        } catch (_) {
          // Ignore malformed historical rows; they simply remain hidden by UI restore.
        }
      }
      if (orphanIds.isNotEmpty) {
        await txn.delete(
          'chat_messages',
          where: 'id IN (${List.filled(orphanIds.length, '?').join(',')})',
          whereArgs: orphanIds,
        );
      }
    });
    await _loadReports();
    notifyListeners();
  }

  Future<List<ReportEntity>> loadReports({
    int? bookId,
    String? type,
  }) async {
    await _loadReports();
    Iterable<ReportEntity> out = _reports;
    if (bookId != null) {
      out = out.where((r) => r.bookId == null || r.bookId == bookId);
    }
    if (type != null && type.isNotEmpty) {
      out = out.where((r) => r.type == type);
    }
    return List.unmodifiable(out);
  }

  /// 追加一条「记账明细卡」消息（role='record'，结构化数据 JSON 存在 text 列，
  /// 复用现有列免迁移）。返回新行 id，供之后改分类/删除时更新这张卡。
  Future<int> addChatRecordMessage(String json) async {
    return _db!.insert('chat_messages', {
      'role': 'record',
      'text': json,
      'question': '',
      'created_ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 更新某张记账卡的持久化 JSON（用户改分类/删条目后写回最新状态）。
  Future<void> updateChatRecordMessage(int rowId, String json) async {
    await _db!.update('chat_messages', {'text': json},
        where: 'id = ?', whereArgs: [rowId]);
  }

  /// 清空全部对话。
  Future<void> clearChatMessages() async {
    await _db!.delete('chat_messages');
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // AI 学习用户纠正：改了某笔分类就记住，下次同备注/商户自动套用
  // ---------------------------------------------------------------------------

  Future<void> _loadCategoryMemory() async {
    final rows = await _db!.query('category_memory');
    _catMemory
      ..clear()
      ..addAll(rows.map((r) => (
            phrase: r['phrase'] as String,
            kind: TransactionKind.fromJson(r['kind'] as String),
            key: r['category_key'] as String,
          )));
  }

  /// 记住一条「备注短语 → 分类」的纠正（编辑里改了分类时调用）。
  Future<void> learnCategory({
    required String phrase,
    required TransactionKind kind,
    required String categoryKey,
  }) async {
    final p = phrase.trim();
    if (p.length < 2 || categoryKey.isEmpty) return;
    await _db!.insert(
      'category_memory',
      {
        'phrase': p,
        'kind': kind.toJson(),
        'category_key': categoryKey,
        'updated_ms': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _catMemory.removeWhere((m) => m.phrase == p && m.kind == kind);
    _catMemory.add((phrase: p, kind: kind, key: categoryKey));
  }

  /// 喵学过的全部「备注短语 → 分类」记忆（管理页展示用），按短语排序。
  List<({String phrase, TransactionKind kind, String key})>
      get categoryMemories =>
          List.of(_catMemory)..sort((a, b) => a.phrase.compareTo(b.phrase));

  /// 给 DeepSeek 提示词用：某收支下**未隐藏**的分类选项（key + 中文名，含自建分类）。
  List<({String key, String name})> llmCategoryOptions(TransactionKind kind) =>
      [
        for (final c in _categories)
          if (c.kind == kind && !c.hidden) (key: c.key, name: c.nameZh)
      ];

  /// 给 DeepSeek 提示词用：用户的学习记忆（历史纠正），让模型模仿其分类习惯。
  List<({String phrase, String categoryKey})> get llmLearnedHints =>
      [for (final m in _catMemory) (phrase: m.phrase, categoryKey: m.key)];

  /// 删除一条学过的记忆（学错了/过时了，用户在管理页手动清）。
  Future<void> forgetCategory(String phrase, TransactionKind kind) async {
    await _db!.delete('category_memory',
        where: 'phrase = ? AND kind = ?', whereArgs: [phrase, kind.toJson()]);
    _catMemory.removeWhere((m) => m.phrase == phrase && m.kind == kind);
    notifyListeners();
  }

  /// 按备注召回学过的分类 key：取被备注包含的「最长」短语对应的分类；无则 null。
  String? recallCategoryKey(String note, TransactionKind kind) {
    final n = note.trim();
    if (n.isEmpty) return null;
    String? best;
    int bestLen = 0;
    for (final m in _catMemory) {
      if (m.kind != kind) continue;
      if (m.phrase.length > bestLen && n.contains(m.phrase)) {
        best = m.key;
        bestLen = m.phrase.length;
      }
    }
    return best;
  }

  // ---------------------------------------------------------------------------
  // 周期记账
  // ---------------------------------------------------------------------------

  /// 当前账本的周期规则(按下次到期升序)。
  List<RecurringRule> get recurringRules =>
      _recurringRules.where((r) => r.bookId == _currentBookId).toList()
        ..sort((a, b) => a.nextDueMs.compareTo(b.nextDueMs));

  int recurringRuleCountForAccount(int accountId) =>
      _recurringRules.where((rule) => rule.accountId == accountId).length;

  Future<void> _loadRecurringRules() async {
    final rows = await _db!.query('recurring_rules');
    _recurringRules
      ..clear()
      ..addAll(rows.map(RecurringRule.fromMap));
  }

  Future<void> _assertRecurringAccountAvailable(
    DatabaseExecutor db,
    int? accountId,
  ) async {
    if (accountId == null) throw ArgumentError('定时记账必须选择账户');
    if (!await _isSupportedTransactionAccountInDb(db, accountId)) {
      throw ArgumentError('定时记账账户不存在、已归档或币种不受支持');
    }
  }

  /// kind=transfer 的周期规则必须有可用的转入账户（且不能和转出相同）。
  Future<void> _assertRecurringTransferTarget(
    DatabaseExecutor db, {
    required TransactionKind kind,
    required int? accountId,
    required int? toAccountId,
  }) async {
    if (kind != TransactionKind.transfer) return;
    if (toAccountId == null ||
        toAccountId == accountId ||
        !await _isSupportedTransactionAccountInDb(db, toAccountId)) {
      throw ArgumentError('转入账户不存在、已归档或与转出账户相同');
    }
  }

  Future<bool> _isSupportedTransactionAccountInDb(
    DatabaseExecutor db,
    int? accountId,
  ) async {
    if (accountId == null) return false;
    final rows = await db.query(
      'accounts',
      columns: ['id'],
      where: 'id = ? AND is_deleted = 0 AND status = ? AND currency_code = ?',
      whereArgs: [accountId, AccountStatus.active.storageKey, 'CNY'],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> addRecurringRule({
    required TransactionKind kind,
    required Decimal amount,
    int? categoryId,
    int? accountId,
    int? toAccountId,
    int? bookId,
    String note = '',
    required RecurPeriod period,
    required DateTime startDate,
    DateTime? endDate,
    int? totalCount,
  }) async {
    amount = normalizeMoneyAmount(amount);
    final normalizedTotalCount =
        totalCount != null && totalCount > 0 ? totalCount : null;
    final targetBookId = bookId != null && _books.any((b) => b.id == bookId)
        ? bookId
        : _currentBookId;
    await _db!.transaction((txn) async {
      await _assertRecurringAccountAvailable(txn, accountId);
      await _assertRecurringTransferTarget(
        txn,
        kind: kind,
        accountId: accountId,
        toAccountId: toAccountId,
      );
      await txn.insert('recurring_rules', {
        'book_id': targetBookId,
        'kind': kind.toJson(),
        'amount': amount.toString(),
        'category_id': kind == TransactionKind.transfer ? null : categoryId,
        'account_id': accountId,
        'to_account_id': kind == TransactionKind.transfer ? toAccountId : null,
        'note': note,
        'period': period.toJson(),
        'start_date_ms': startDate.millisecondsSinceEpoch,
        'next_due_ms': startDate.millisecondsSinceEpoch,
        'enabled': 1,
        'anchor_day': startDate.day,
        'end_date_ms': endDate?.millisecondsSinceEpoch,
        'total_count': normalizedTotalCount,
        'generated_count': 0,
        'created_ms': DateTime.now().millisecondsSinceEpoch,
      });
    });
    await _loadRecurringRules();
    await _materializeRecurring(); // 起始日若已过则立即补记
    await _loadTransactions();
    await _refreshCurrentNetWorthSnapshotBestEffort(
      const {NetWorthSnapshotCause.scheduledRebuild},
    );
    notifyListeners();
  }

  Future<void> updateRecurringRule({
    required int id,
    required TransactionKind kind,
    required Decimal amount,
    int? categoryId,
    int? accountId,
    int? toAccountId,
    int? bookId,
    String note = '',
    required RecurPeriod period,
    required DateTime nextDue,
    DateTime? startDate,
    DateTime? endDate,
    int? totalCount,
  }) async {
    amount = normalizeMoneyAmount(amount);
    final normalizedTotalCount =
        totalCount != null && totalCount > 0 ? totalCount : null;
    final targetBookId =
        bookId != null && _books.any((b) => b.id == bookId) ? bookId : null;
    await _db!.transaction((txn) async {
      await _assertRecurringAccountAvailable(txn, accountId);
      await _assertRecurringTransferTarget(
        txn,
        kind: kind,
        accountId: accountId,
        toAccountId: toAccountId,
      );
      await txn.update(
        'recurring_rules',
        {
          if (targetBookId != null) 'book_id': targetBookId,
          'kind': kind.toJson(),
          'amount': amount.toString(),
          'category_id': kind == TransactionKind.transfer ? null : categoryId,
          'account_id': accountId,
          'to_account_id':
              kind == TransactionKind.transfer ? toAccountId : null,
          'note': note,
          'period': period.toJson(),
          'start_date_ms': (startDate ?? nextDue).millisecondsSinceEpoch,
          'next_due_ms': nextDue.millisecondsSinceEpoch,
          'anchor_day': (startDate ?? nextDue).day,
          'end_date_ms': endDate?.millisecondsSinceEpoch,
          'total_count': normalizedTotalCount,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    await _loadRecurringRules();
    notifyListeners();
  }

  Future<void> deleteRecurringRule(int id) async {
    await _db!.delete('recurring_rules', where: 'id = ?', whereArgs: [id]);
    await _loadRecurringRules();
    notifyListeners();
  }

  Future<void> setRecurringEnabled(int id, bool enabled) async {
    await _db!.update('recurring_rules', {'enabled': enabled ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
    await _loadRecurringRules();
    if (enabled) {
      await _materializeRecurring();
      await _loadTransactions();
      await _persistCurrentNetWorthSnapshot(
        causes: const {NetWorthSnapshotCause.scheduledRebuild},
        notify: false,
      );
    }
    notifyListeners();
  }

  /// 到期生成:启用规则中凡 nextDue<=今天 就补记一笔并推进 nextDue。
  /// guard 上限防止极端情况(长期没打开 App)跑飞。
  Future<void> _materializeRecurring() async {
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month, now.day, 23, 59, 59)
        .millisecondsSinceEpoch;
    var changed = false;
    await _db!.transaction((txn) async {
      final supportedAccountRows = await txn.query(
        'accounts',
        columns: ['id'],
        where: 'is_deleted = 0 AND status = ? AND currency_code = ?',
        whereArgs: [AccountStatus.active.storageKey, 'CNY'],
      );
      final supportedAccountIds =
          supportedAccountRows.map((row) => row['id'] as int).toSet();
      for (final rule in List<RecurringRule>.from(_recurringRules)) {
        if (!rule.enabled) continue;
        // A recurring rule represents an explicit payment source. If that
        // source is no longer available, keep the occurrence pending until
        // the user repairs the rule instead of charging another account.
        if (!supportedAccountIds.contains(rule.accountId)) continue;
        // 转账规则同理：转入账户失效时不落单腿流水（钱会凭空消失），
        // 挂起等用户修规则。
        if (rule.txKind == TransactionKind.transfer &&
            !supportedAccountIds.contains(rule.toAccountId)) {
          continue;
        }
        var due = rule.nextDue;
        var generatedCount = rule.generatedCount;
        final totalCount = rule.totalCount;
        final endDate = rule.endDate;
        final endCutoff = endDate == null
            ? null
            : DateTime(
                endDate.year,
                endDate.month,
                endDate.day,
                23,
                59,
                59,
                999,
              ).millisecondsSinceEpoch;
        var guard = 0;
        while (due.millisecondsSinceEpoch <= cutoff && guard < 400) {
          if (totalCount != null &&
              totalCount > 0 &&
              generatedCount >= totalCount) {
            break;
          }
          final dueMs = due.millisecondsSinceEpoch;
          if (endCutoff != null && dueMs > endCutoff) break;

          final existing = await txn.query(
            'recurring_occurrences',
            columns: ['transaction_id'],
            where: 'rule_id = ? AND due_ms = ?',
            whereArgs: [rule.id, dueMs],
            limit: 1,
          );
          if (existing.isEmpty) {
            final accountId = rule.accountId!;
            final kind = TransactionKind.fromJson(rule.kind);
            final transactionId = await txn.insert('transactions', {
              ..._syncStampNew(),
              'book_id': rule.bookId,
              'kind': rule.kind,
              'amount': rule.amountStr,
              'currency_code': 'CNY',
              'category_id':
                  kind == TransactionKind.transfer ? null : rule.categoryId,
              'account_id': accountId,
              'to_account_id':
                  kind == TransactionKind.transfer ? rule.toAccountId : null,
              'note': rule.note.isEmpty ? '周期记账' : rule.note,
              'date_ms': dueMs,
              'time_precision': TransactionTimePrecision.dateOnly.storageKey,
              'tags': '',
              'reimbursable': 0,
              'image_path': '',
              'recurring_rule_id': rule.id,
              'settled_ms': dueMs,
              'settlement_quality': SettlementQuality.legacyAssumed.storageKey,
              'settlement_account_id': accountId,
              'settlement_account_quality':
                  SettlementQuality.legacyAssumed.storageKey,
              'event_type': _eventTypeForKind(kind).storageKey,
            });
            await txn.insert('recurring_occurrences', {
              'rule_id': rule.id,
              'due_ms': dueMs,
              'transaction_id': transactionId,
              'created_ms': DateTime.now().millisecondsSinceEpoch,
            });
          }
          due = rule.recurPeriod.advance(
            due,
            anchorDay: rule.anchorDay > 0 ? rule.anchorDay : null,
          );
          generatedCount++;
          guard++;
        }
        if (guard > 0) {
          await txn.update(
            'recurring_rules',
            {
              'next_due_ms': due.millisecondsSinceEpoch,
              'generated_count': generatedCount,
            },
            where: 'id = ?',
            whereArgs: [rule.id],
          );
          changed = true;
        }
      }
    });
    if (changed) await _loadRecurringRules();
  }

  List<int> _bookIdsForView(int bookId) {
    final isTotal = bookId == _defaultBookId;
    final ids = isTotal
        ? [
            for (final b in _books)
              if (b.id == _defaultBookId || b.includeInTotal) b.id
          ]
        : [bookId];
    if (ids.isEmpty) ids.add(-1);
    return ids;
  }

  List<int> _bookIdsForCurrentView() => _bookIdsForView(_currentBookId);

  Future<void> _loadTransactions() async {
    // 总账本 = 聚合视图：显示自己的账单 + 所有「计入总账本」账本的账单；
    // 其它账本只显示自己的。
    _transactionFullReloadCount++;
    final all = await _queryTransactions();
    _allTransactions
      ..clear()
      ..addAll(all);
    _applyCurrentBookTransactionView();
  }

  /// Fast-start query for the only ledger window visible on the first home
  /// frame. The full query still runs in [finishDeferredInitialization].
  Future<void> _loadTransactionsForStartupMonth() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1);
    final bookIds = _bookIdsForCurrentView();
    final placeholders = List.filled(bookIds.length, '?').join(',');
    final rows = await _queryTransactions(
      where: 't.date_ms >= ? AND t.date_ms < ? AND '
          't.book_id IN ($placeholders)',
      args: [
        start.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
        ...bookIds,
      ],
    );
    _allTransactions
      ..clear()
      ..addAll(rows);
    _applyCurrentBookTransactionView();
  }

  static const String _transactionSelectSql = '''
      SELECT
        t.id,
        t.book_id,
        t.uuid,
        t.kind,
        t.amount,
        t.currency_code,
        t.category_id,
        c.key      AS category_key,
        c.name_zh  AS category_name_zh,
        c.name_en  AS category_name_en,
        t.account_id,
        a.name     AS account_name,
        t.to_account_id,
        ta.name    AS to_account_name,
        t.note,
        t.date_ms,
        t.time_precision,
        t.created_ms,
        t.settled_ms,
        t.settlement_quality,
        t.settlement_account_id,
        t.settlement_account_quality,
        t.event_type,
        t.tags,
        t.reimbursable,
        t.image_path,
        t.recurring_rule_id,
        t.excluded,
        t.refund_of
      FROM transactions t
      LEFT JOIN categories c  ON c.id = t.category_id
      LEFT JOIN accounts   a  ON a.id = t.account_id
      LEFT JOIN accounts   ta ON ta.id = t.to_account_id
  ''';

  int _transactionFullReloadCount = 0;

  @visibleForTesting
  int get transactionFullReloadCount => _transactionFullReloadCount;

  Future<List<TransactionEntity>> _queryTransactions({
    String where = '',
    List<Object?> args = const [],
  }) async {
    final whereSql = where.isEmpty ? '' : ' WHERE $where';
    final rows = await _db!.rawQuery(
      '$_transactionSelectSql$whereSql ORDER BY t.date_ms DESC, t.id DESC',
      args,
    );
    return rows.map(TransactionEntity.fromMap).toList(growable: false);
  }

  void _applyCurrentBookTransactionView() {
    final ids = _bookIdsForCurrentView();
    final allowedBookIds = ids.toSet();
    _transactions
      ..clear()
      ..addAll(_allTransactions.where((transaction) =>
          transaction.bookId != null &&
          allowedBookIds.contains(transaction.bookId)));
    _invalidateTxDerived();
  }

  /// 常规单笔写入只回读受影响的原单和退款子行，不再全表 SELECT。
  /// [familyRoots] 中的 id 会同时匹配 `t.id` 与 `t.refund_of`，用于退款、
  /// 改分类和删除原单；数据库仍是唯一真相，内存只在事务成功后更新。
  Future<void> _refreshTransactionRows({
    Set<int> ids = const <int>{},
    Set<int> familyRoots = const <int>{},
  }) async {
    if (ids.isEmpty && familyRoots.isEmpty) return;

    final conditions = <String>[];
    final args = <Object?>[];
    String placeholders(int count) => List.filled(count, '?').join(',');
    if (ids.isNotEmpty) {
      conditions.add('t.id IN (${placeholders(ids.length)})');
      args.addAll(ids);
    }
    if (familyRoots.isNotEmpty) {
      final roots = placeholders(familyRoots.length);
      conditions.add('(t.id IN ($roots) OR t.refund_of IN ($roots))');
      args
        ..addAll(familyRoots)
        ..addAll(familyRoots);
    }

    final fresh = await _queryTransactions(
      where: conditions.join(' OR '),
      args: args,
    );
    final affectedIds = <int>{...ids, ...familyRoots};
    for (final transaction in _allTransactions) {
      if (familyRoots.contains(transaction.refundOf)) {
        affectedIds.add(transaction.id);
      }
    }
    affectedIds.addAll(fresh.map((transaction) => transaction.id));
    _allTransactions
      ..removeWhere((transaction) => affectedIds.contains(transaction.id))
      ..addAll(fresh)
      ..sort((a, b) {
        final byDate = b.dateMs.compareTo(a.dateMs);
        return byDate != 0 ? byDate : b.id.compareTo(a.id);
      });
    _applyCurrentBookTransactionView();
  }

  // 账单派生数据缓存：退款索引 / 可见列表 / 统计记录流。
  // 都是纯内存派生，_transactions 一变（重载或原地删）就整体作废、
  // 下次访问时懒重建——把原来「每次访问全表扫」的 O(n²) 压到 O(n)。
  Map<int, Decimal>? _refundTotalsCache;
  Map<int, Decimal>? _globalRefundTotalsCache;
  List<TransactionEntity>? _visibleTxCache;
  List<TransactionEntity>? _globalVisibleTxCache;
  List<TransactionRecord>? _allRecordsCache;
  List<TransactionEntity>? _visibleTxViewCache; // 稳定引用，供 select<> 用
  List<TransactionRecord>? _allRecordsViewCache; // 稳定引用，供 select<> 用

  // 稳定引用缓存：对应 _books/_categories/_transactions/_reports 的
  // UnmodifiableListView 包装。只在底层列表被整体重载（clear+addAll）
  // 时置 null，让 select<AppRepository, List<T>>(r=>r.xxx) 能通过
  // 对象标识判断是否真正变化，避免每次 notifyListeners 都触发重建。
  List<BookEntity>? _booksViewCache;
  List<CategoryEntity>? _categoriesViewCache;
  List<TransactionEntity>? _transactionsViewCache;
  List<ReportEntity>? _reportsViewCache;

  void _invalidateTxDerived() {
    _refundTotalsCache = null;
    _globalRefundTotalsCache = null;
    _visibleTxCache = null;
    _globalVisibleTxCache = null;
    _allRecordsCache = null;
    _transactionsViewCache = null;
    _visibleTxViewCache = null;
    _allRecordsViewCache = null;
    _txByIdCache = null;
    _invalidateBalanceDerived();
  }

  Map<int, TransactionEntity>? _txByIdCache;

  /// 惰性 by-id 索引：把 transactionById / physicalAssetAdditionalCost
  /// 里对 _allTransactions 的线性查压成 O(1)。随 _invalidateTxDerived() 作废。
  Map<int, TransactionEntity> get _txById => _txByIdCache ??= {
        for (final transaction in _allTransactions) transaction.id: transaction,
      };

  // ---- 资产页性能 memo（余额 / 净资产 / 趋势）----
  // accountBalanceResultOf / currentNetWorth* / accountBalanceTrend 的结果
  // 只依赖 (数据版本, 当天日期)：asOf/knowledgeCutoff 都固定取 now，
  // 却每次调用都做全量结算重放。这里按 (revision, 当天 yyyymmdd) memo：
  //  · revision 一变（任何写路径 notifyListeners）自动失效；
  //  · 跨午夜（当天变了）也失效——「今天到账」等窗口端点会移动；
  //  · 双保险：账户 / 校准锚点 / 账本 / 资产 / 负债档案等 _loadXxx 重载时
  //    显式清空，防止「写路径中途、notifyListeners 之前」的内部读
  //    （如 _persistCurrentNetWorthSnapshot）拿到脏缓存。
  // 只缓存无参数的「今天」路径；historical / 自定义 asOf 一律现算。
  final Map<int, MetricResult<AccountBalanceValue>> _accountBalanceCache = {};
  final Map<(int, int), AccountBalanceTrendValue?> _accountBalanceTrendCache =
      {};
  MetricResult<NetWorthBreakdown>? _netWorthResultCache;
  NetWorthBreakdown? _netWorthBreakdownCache;
  int? _balanceCacheRevision;
  int? _balanceCacheDayStamp;

  int _balanceRecomputeCount = 0;
  int _netWorthRecomputeCount = 0;
  int _trendRecomputeCount = 0;

  /// 「今天」余额真正重算的次数（缓存命中不增），供缓存回归测试断言。
  @visibleForTesting
  int get balanceRecomputeCount => _balanceRecomputeCount;

  @visibleForTesting
  int get netWorthRecomputeCount => _netWorthRecomputeCount;

  @visibleForTesting
  int get trendRecomputeCount => _trendRecomputeCount;

  static int _dayStampOf(DateTime now) =>
      now.year * 10000 + now.month * 100 + now.day;

  void _invalidateBalanceDerived() {
    _accountBalanceCache.clear();
    _accountBalanceTrendCache.clear();
    _netWorthResultCache = null;
    _netWorthBreakdownCache = null;
    _balanceCacheRevision = null;
    _balanceCacheDayStamp = null;
  }

  /// memo 只在 (revision, 当天) 都没变时有效；否则整体清空重建。
  void _ensureBalanceCacheFresh() {
    final today = _dayStampOf(DateTime.now());
    if (_balanceCacheRevision == _revision && _balanceCacheDayStamp == today) {
      return;
    }
    _accountBalanceCache.clear();
    _accountBalanceTrendCache.clear();
    _netWorthResultCache = null;
    _netWorthBreakdownCache = null;
    _balanceCacheRevision = _revision;
    _balanceCacheDayStamp = today;
  }

  Map<int, Decimal> get _refundTotals =>
      _refundTotalsCache ??= LedgerPolicy.refundTotals(_transactions);
  Map<int, Decimal> get _globalRefundTotals =>
      _globalRefundTotalsCache ??= LedgerPolicy.refundTotals(_allTransactions);
  List<TransactionEntity> get _globalVisibleTransactions =>
      _globalVisibleTxCache ??= _allTransactions
          .where((transaction) => transaction.refundOf == null)
          .toList();

  Future<void> _loadPhysicalAssetData({bool refreshSnapshot = true}) async {
    await _loadPhysicalAssets();
    await _loadReceivableAssets();
    await Future.wait([
      _loadAssetEvents(),
      _loadAssetUsageEvents(),
      _loadAssetValuations(),
      _loadAssetTransactionLinks(),
      _loadReceivableRecoveries(),
      _loadNetWorthSnapshots(),
    ]);
    if (refreshSnapshot) {
      await _refreshCurrentNetWorthSnapshotBestEffort(
        const {NetWorthSnapshotCause.other},
      );
    }
  }

  Future<void> _loadPhysicalAssets() async {
    final ids = _bookIdsForCurrentView();
    final rows = await _db!.query(
      'physical_assets',
      orderBy:
          "is_deleted ASC, CASE visibility_status WHEN 'active' THEN 0 ELSE 1 END ASC, CASE economic_status WHEN 'owned' THEN 0 ELSE 1 END ASC, CASE usage_status WHEN 'active' THEN 0 WHEN 'idle' THEN 1 ELSE 2 END ASC, CAST(current_value AS REAL) DESC, updated_ms DESC, id DESC",
    );
    final allowedBookIds = ids.toSet();
    final all = rows.map(PhysicalAssetEntity.fromMap).toList(growable: false);
    _allPhysicalAssets
      ..clear()
      ..addAll(all);
    _physicalAssets
      ..clear()
      ..addAll(all.where((asset) =>
          asset.bookId != null && allowedBookIds.contains(asset.bookId)));
    _invalidateBalanceDerived();
  }

  Future<void> _loadReceivableAssets() async {
    final ids = _bookIdsForCurrentView();
    final rows = await _db!.query(
      'receivable_assets',
      orderBy:
          "is_deleted ASC, CASE visibility_status WHEN 'active' THEN 0 ELSE 1 END ASC, CASE economic_status WHEN 'active' THEN 0 WHEN 'partial_recovered' THEN 1 WHEN 'unknown' THEN 2 ELSE 3 END ASC, CAST(remaining_amount AS REAL) DESC, updated_ms DESC, id DESC",
    );
    final allowedBookIds = ids.toSet();
    final all = rows.map(ReceivableAssetEntity.fromMap).toList(growable: false);
    _allReceivableAssets
      ..clear()
      ..addAll(all);
    _receivableAssets
      ..clear()
      ..addAll(all.where((asset) =>
          asset.bookId != null && allowedBookIds.contains(asset.bookId)));
    _invalidateBalanceDerived();
  }

  Future<void> _loadAssetEvents() async {
    final rows = await _db!.query(
      'asset_events',
      orderBy: 'occurred_ms DESC, id DESC',
    );
    _assetEvents
      ..clear()
      ..addAll(rows.map(AssetEventEntity.fromMap));
  }

  Future<void> _loadAssetUsageEvents() async {
    final rows = await _db!.query(
      'asset_usage_events',
      orderBy: 'occurred_ms ASC, id ASC',
    );
    _assetUsageEvents
      ..clear()
      ..addAll(rows.map(AssetUsageEventEntity.fromMap));
  }

  Future<void> _loadAssetValuations() async {
    final rows = await _db!.query(
      'asset_valuations',
      orderBy: 'valued_at_ms DESC, id DESC',
    );
    _assetValuations
      ..clear()
      ..addAll(rows.map(AssetValuationEntity.fromMap));
    _invalidateBalanceDerived();
  }

  Future<void> _loadAssetTransactionLinks() async {
    final rows = await _db!.query(
      'asset_transaction_links',
      orderBy: 'created_ms DESC, id DESC',
    );
    _assetTransactionLinks
      ..clear()
      ..addAll(rows.map(AssetTransactionLinkEntity.fromMap));
  }

  Future<void> _loadReceivableRecoveries() async {
    final rows = await _db!.query(
      'receivable_recoveries',
      orderBy: 'recovered_ms DESC, id DESC',
    );
    _receivableRecoveries
      ..clear()
      ..addAll(rows.map(ReceivableRecoveryEntity.fromMap));
    _invalidateBalanceDerived();
  }

  Future<void> _loadNetWorthSnapshots() async {
    final scopeRows = await _db!.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: const ['net_worth_scope_version'],
      limit: 1,
    );
    _netWorthScopeVersion = max(
      1,
      int.tryParse(scopeRows.firstOrNull?['value'] as String? ?? '') ?? 1,
    );
    final rows = await _db!.query(
      'net_worth_snapshots',
      where: 'scope_key = ?',
      whereArgs: const ['global'],
      orderBy: 'snapshot_date DESC, id DESC',
    );
    _netWorthSnapshots
      ..clear()
      ..addAll(rows.map(NetWorthSnapshotEntity.fromMap));
  }

  Future<void> _loadLiabilityProfiles() async {
    final rows = await _db!.query(
      'liability_profiles',
      orderBy:
          "CASE status WHEN 'active' THEN 0 WHEN 'paused' THEN 1 WHEN 'paid_off' THEN 2 ELSE 3 END ASC, repayment_day IS NULL, repayment_day ASC, id DESC",
    );
    _liabilityProfiles
      ..clear()
      ..addAll(rows.map(LiabilityProfileEntity.fromMap));
    _invalidateBalanceDerived();
  }

  // ---------------------------------------------------------------------------
  // 备份 / 恢复
  // ---------------------------------------------------------------------------

  Future<String> databaseFilePath() async =>
      p.join(await getDatabasesPath(), _dbName);

  Future<File> _sanitizedDatabaseCopy(Directory dir) async {
    final dest = File(p.join(dir.path, _dbName));
    final sourcePath = await databaseFilePath();
    await _createConsistentDatabaseCopy(
      sourcePath,
      dest.path,
      sourceDb: _db,
    );
    final db = await openDatabase(dest.path, singleInstance: false);
    try {
      await db.delete(
        'app_settings',
        where: "key IN (?, ?) OR key LIKE 'ai_provider_api_key_%'",
        whereArgs: ['deepseek_api_key', 'custom_ai_api_key'],
      );
    } finally {
      await db.close();
    }
    return dest;
  }

  Future<File> exportBackupPackage({
    @visibleForTesting Directory? temporaryDirectory,
    @visibleForTesting Directory? documentsDirectory,
  }) async {
    final tmp = temporaryDirectory ?? await getTemporaryDirectory();
    final work = await Directory(p.join(
      tmp.path,
      'feimiao_backup_${DateTime.now().millisecondsSinceEpoch}',
    )).create(recursive: true);
    try {
      final dbCopy = await _sanitizedDatabaseCopy(work);
      final docs =
          documentsDirectory ?? await getApplicationDocumentsDirectory();
      final receiptsDir = Directory(p.join(docs.path, 'receipts'));
      final assetMediaDir = Directory(p.join(docs.path, 'asset_media'));

      final files = <BackupPayloadFile>[
        BackupPayloadFile(archivePath: 'database/$_dbName', file: dbCopy),
      ];
      await _collectBackupDirectory(
        source: receiptsDir,
        archiveRoot: 'receipts',
        output: files,
      );
      await _collectBackupDirectory(
        source: assetMediaDir,
        archiveRoot: 'asset_media',
        output: files,
      );
      final stamp = DateTime.now();
      final name = 'feimiao-backup-${stamp.year}'
          '${stamp.month.toString().padLeft(2, '0')}'
          '${stamp.day.toString().padLeft(2, '0')}-'
          '${stamp.hour.toString().padLeft(2, '0')}'
          '${stamp.minute.toString().padLeft(2, '0')}.zip';
      final out = File(p.join(tmp.path, name));
      // 流式打包：收据/照片多的库不再把全部字节 + 整包 zip 同时读进内存。
      await BackupPackageCodec.encodeToFile(
        files: files,
        outputPath: out.path,
        databaseVersion: _dbVersion,
        createdAt: stamp,
      );
      return out;
    } finally {
      try {
        if (await work.exists()) {
          await work.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  Future<void> _collectBackupDirectory({
    required Directory source,
    required String archiveRoot,
    required List<BackupPayloadFile> output,
  }) async {
    if (!await source.exists()) return;
    await for (final entry
        in source.list(recursive: true, followLinks: false)) {
      if (entry is! File) continue;
      final relative = p.relative(entry.path, from: source.path);
      final archivePath = p.posix.join(
        archiveRoot,
        p.split(relative).join('/'),
      );
      // 只登记文件引用，内容由流式打包器逐个读取。
      output.add(BackupPayloadFile(archivePath: archivePath, file: entry));
    }
  }

  Future<bool> restoreBackupPackage(
    String srcPath, {
    @visibleForTesting Directory? temporaryDirectory,
    @visibleForTesting Directory? documentsDirectory,
    @visibleForTesting void Function(String step)? onRestoreStep,
  }) async {
    late final DecodedBackupPackage package;
    try {
      package = BackupPackageCodec.decode(await File(srcPath).readAsBytes());
    } catch (_) {
      return false;
    }
    final databaseBytes = package.files['database/$_dbName'];
    if (databaseBytes == null) return false;

    final tmp = temporaryDirectory ?? await getTemporaryDirectory();
    final work = await Directory(p.join(
      tmp.path,
      'feimiao_restore_${DateTime.now().millisecondsSinceEpoch}',
    )).create(recursive: true);
    try {
      final dbPath = p.join(work.path, _dbName);
      await File(dbPath).writeAsBytes(databaseBytes, flush: true);

      // 先做完整性校验，再打开包内库改写附件路径：合法 zip 里塞非法 db
      // 字节时必须走干净的失败分支，不能让 DatabaseException 从这里裸穿。
      try {
        final check = await openReadOnlyDatabase(dbPath);
        try {
          final quick = await check.rawQuery('PRAGMA quick_check');
          if (quick.isEmpty ||
              quick.first.values.first.toString().toLowerCase() != 'ok') {
            return false;
          }
        } finally {
          await check.close();
        }
      } catch (_) {
        return false;
      }

      final docs =
          documentsDirectory ?? await getApplicationDocumentsDirectory();
      final finalReceiptsDir = Directory(p.join(docs.path, 'receipts'));
      final finalAssetMediaDir = Directory(p.join(docs.path, 'asset_media'));
      final stagedReceiptsDir = await Directory(p.join(work.path, 'receipts'))
          .create(recursive: true);
      final stagedAssetMediaDir = await Directory(
        p.join(work.path, 'asset_media'),
      ).create(recursive: true);
      final receiptPathByName = <String, String>{};
      final originalPathByName = <String, String>{};
      final thumbnailPathByName = <String, String>{};
      for (final entry in package.files.entries) {
        final segments = p.posix.split(entry.key);
        if (segments.length < 2) continue;
        final root = segments.first;
        final relativeSegments = segments.skip(1).toList(growable: false);
        if (root != 'receipts' && root != 'asset_media') continue;
        final stagedRoot =
            root == 'receipts' ? stagedReceiptsDir : stagedAssetMediaDir;
        final destination = File(
          p.joinAll([stagedRoot.path, ...relativeSegments]),
        );
        await destination.parent.create(recursive: true);
        await destination.writeAsBytes(entry.value, flush: true);
        final name = relativeSegments.last;
        if (root == 'receipts') {
          receiptPathByName[name] = p.joinAll(
            [finalReceiptsDir.path, ...relativeSegments],
          );
        } else if (relativeSegments.first == 'thumbnails') {
          thumbnailPathByName[name] = p.joinAll(
            [finalAssetMediaDir.path, ...relativeSegments],
          );
        } else {
          originalPathByName[name] = p.joinAll(
            [finalAssetMediaDir.path, ...relativeSegments],
          );
        }
      }

      if (receiptPathByName.isNotEmpty ||
          originalPathByName.isNotEmpty ||
          thumbnailPathByName.isNotEmpty) {
        // 包内库虽过了 quick_check，也可能缺表/缺列（人为构造的包）。
        // 改写失败一律当作「包不合法」干净返回 false，异常不裸穿。
        try {
          final db = await openDatabase(dbPath, singleInstance: false);
          try {
            final transactionRows = await db.query(
              'transactions',
              columns: ['id', 'image_path'],
              where: "image_path <> ''",
            );
            for (final row in transactionRows) {
              final oldPath = row['image_path'] as String? ?? '';
              final mapped = receiptPathByName[p.basename(oldPath)];
              if (mapped != null) {
                await db.update(
                  'transactions',
                  {'image_path': mapped},
                  where: 'id = ?',
                  whereArgs: [row['id']],
                );
              }
            }
            final tables = await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'physical_assets'",
            );
            if (tables.isNotEmpty) {
              final columns =
                  (await db.rawQuery('PRAGMA table_info(physical_assets)'))
                      .map((row) => row['name'])
                      .whereType<String>()
                      .toSet();
              final selectedColumns = <String>[
                'id',
                'photo_path',
                'invoice_path'
              ];
              if (columns.contains('thumbnail_path')) {
                selectedColumns.add('thumbnail_path');
              }
              final assetRows = await db.query(
                'physical_assets',
                columns: selectedColumns,
              );
              for (final row in assetRows) {
                final changes = <String, Object?>{};
                final photo = row['photo_path'] as String? ?? '';
                final invoice = row['invoice_path'] as String? ?? '';
                final thumbnail = row['thumbnail_path'] as String? ?? '';
                final mappedPhoto = originalPathByName[p.basename(photo)];
                final mappedInvoice = originalPathByName[p.basename(invoice)] ??
                    receiptPathByName[p.basename(invoice)];
                final mappedThumbnail =
                    thumbnailPathByName[p.basename(thumbnail)];
                if (mappedPhoto != null) changes['photo_path'] = mappedPhoto;
                if (mappedInvoice != null) {
                  changes['invoice_path'] = mappedInvoice;
                }
                if (columns.contains('thumbnail_path') &&
                    mappedThumbnail != null) {
                  changes['thumbnail_path'] = mappedThumbnail;
                }
                if (changes.isNotEmpty) {
                  await db.update(
                    'physical_assets',
                    changes,
                    where: 'id = ?',
                    whereArgs: [row['id']],
                  );
                }
              }
            }
          } finally {
            await db.close();
          }
        } catch (_) {
          return false;
        }
      }

      final replaceEmptyDirectories = package.version >= 2;
      return await _restoreDatabaseFromFile(
        dbPath,
        replacementReceipts:
            replaceEmptyDirectories || receiptPathByName.isNotEmpty
                ? stagedReceiptsDir
                : null,
        replacementAssetMedia: replaceEmptyDirectories ||
                originalPathByName.isNotEmpty ||
                thumbnailPathByName.isNotEmpty
            ? stagedAssetMediaDir
            : null,
        documentsDirectory: docs,
        onRestoreStep: onRestoreStep,
      );
    } finally {
      try {
        if (await work.exists()) {
          await work.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  Future<bool> restoreDatabaseFromFile(String srcPath) =>
      _restoreDatabaseFromFile(srcPath);

  Future<bool> _restoreDatabaseFromFile(
    String srcPath, {
    Directory? replacementReceipts,
    Directory? replacementAssetMedia,
    Directory? documentsDirectory,
    void Function(String step)? onRestoreStep,
  }) =>
      _reportExecutionFence.withRestoreBarrier(
        () => _replaceDatabaseFromFile(
          srcPath,
          replacementReceipts: replacementReceipts,
          replacementAssetMedia: replacementAssetMedia,
          documentsDirectory: documentsDirectory,
          onRestoreStep: onRestoreStep,
        ),
      );

  Future<bool> _replaceDatabaseFromFile(
    String srcPath, {
    Directory? replacementReceipts,
    Directory? replacementAssetMedia,
    Directory? documentsDirectory,
    void Function(String step)? onRestoreStep,
  }) async {
    final dbPath = p.join(await getDatabasesPath(), _dbName);
    final bakPath = '$dbPath.bak';
    final token = DateTime.now().microsecondsSinceEpoch;
    final stagedPath = '$dbPath.restore-new-$token';
    final oldPath = '$dbPath.restore-old-$token';
    Directory? liveReceipts;
    Directory? stagedReceipts;
    Directory? oldReceipts;
    Directory? liveAssetMedia;
    Directory? stagedAssetMedia;
    Directory? oldAssetMedia;
    var databaseMovedToOld = false;
    var databaseInstalled = false;
    var receiptsMovedToOld = false;
    var receiptsInstalled = false;
    var assetMediaMovedToOld = false;
    var assetMediaInstalled = false;

    try {
      await File(srcPath).copy(stagedPath);
      if (!await _validateAndMigrateRestoreCandidate(stagedPath)) {
        await File(stagedPath).delete();
        return false;
      }
      if (replacementReceipts != null) {
        final docs =
            documentsDirectory ?? await getApplicationDocumentsDirectory();
        liveReceipts = Directory(p.join(docs.path, 'receipts'));
        stagedReceipts = Directory('${liveReceipts.path}.restore-new-$token');
        oldReceipts = Directory('${liveReceipts.path}.restore-old-$token');
        await _copyDirectoryTree(replacementReceipts, stagedReceipts);
      }
      if (replacementAssetMedia != null) {
        final docs =
            documentsDirectory ?? await getApplicationDocumentsDirectory();
        liveAssetMedia = Directory(p.join(docs.path, 'asset_media'));
        stagedAssetMedia =
            Directory('${liveAssetMedia.path}.restore-new-$token');
        oldAssetMedia = Directory('${liveAssetMedia.path}.restore-old-$token');
        await _copyDirectoryTree(replacementAssetMedia, stagedAssetMedia);
      }
      final current = File(dbPath);
      if (await current.exists()) {
        // 恢复前给当前库留一份安全副本。当前库已损坏时一致性快照必然失败，
        // 但副本只是兜底动作，绝不能反过来卡死恢复本身：先降级成普通文件
        // 复制（连同 -wal/-shm），再失败就跳过副本，恢复流程照常继续。
        try {
          await _createConsistentDatabaseCopy(
            dbPath,
            bakPath,
            sourceDb: _db,
          );
        } catch (_) {
          try {
            await current.copy(bakPath);
            for (final suffix in ['-wal', '-shm']) {
              final sidecar = File('$dbPath$suffix');
              if (await sidecar.exists()) {
                await sidecar.copy('$bakPath$suffix');
              }
            }
          } catch (_) {
            // 副本实在做不出来就只能跳过：宁可少一份兜底，也不能放弃恢复。
          }
        }
      }
    } catch (_) {
      try {
        if (await File(stagedPath).exists()) await File(stagedPath).delete();
        if (stagedReceipts != null && await stagedReceipts.exists()) {
          await stagedReceipts.delete(recursive: true);
        }
        if (stagedAssetMedia != null && await stagedAssetMedia.exists()) {
          await stagedAssetMedia.delete(recursive: true);
        }
      } catch (_) {}
      return false;
    }

    try {
      await _db?.close();
      _db = null;

      final cur = File(dbPath);
      if (await cur.exists()) {
        await cur.rename(oldPath);
        databaseMovedToOld = true;
      }
      for (final suffix in ['-wal', '-shm']) {
        final sidecar = File('$dbPath$suffix');
        if (await sidecar.exists()) await sidecar.delete();
      }
      onRestoreStep?.call('before_database_install');
      await File(stagedPath).rename(dbPath);
      databaseInstalled = true;
      if (stagedReceipts != null &&
          liveReceipts != null &&
          oldReceipts != null) {
        if (await liveReceipts.exists()) {
          await liveReceipts.rename(oldReceipts.path);
          receiptsMovedToOld = true;
        }
        onRestoreStep?.call('before_receipts_install');
        await stagedReceipts.rename(liveReceipts.path);
        receiptsInstalled = true;
      }
      if (stagedAssetMedia != null &&
          liveAssetMedia != null &&
          oldAssetMedia != null) {
        if (await liveAssetMedia.exists()) {
          await liveAssetMedia.rename(oldAssetMedia.path);
          assetMediaMovedToOld = true;
        }
        onRestoreStep?.call('before_asset_media_install');
        await stagedAssetMedia.rename(liveAssetMedia.path);
        assetMediaInstalled = true;
      }

      onRestoreStep?.call('before_database_open');
      _db = await openDatabase(
        dbPath,
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
      await _runB3A4V39Compat(_db!);
      await _ensureDefaultBook();
      await _normalizeStandaloneRefunds();
      await _convergeOpenedDatabase(notify: false);
      await _cleanupCommittedRestore(
        dbPath: dbPath,
        oldPath: oldPath,
        oldReceipts: oldReceipts,
        oldAssetMedia: oldAssetMedia,
      );
      _databaseGeneration++;
      notifyListeners();
      return true;
    } catch (_) {
      try {
        await _db?.close();
      } catch (_) {
      } finally {
        _db = null;
      }
      try {
        final current = File(dbPath);
        if (databaseInstalled && await current.exists()) {
          await current.delete();
        }
        final old = File(oldPath);
        if (databaseMovedToOld && await old.exists()) {
          await old.rename(dbPath);
        } else if (!await current.exists()) {
          final bak = File(bakPath);
          if (await bak.exists()) await bak.copy(dbPath);
        }
      } catch (_) {}
      try {
        if (liveReceipts != null && oldReceipts != null) {
          if (receiptsInstalled && await liveReceipts.exists()) {
            await liveReceipts.delete(recursive: true);
          }
          if (receiptsMovedToOld && await oldReceipts.exists()) {
            await oldReceipts.rename(liveReceipts.path);
          }
        }
      } catch (_) {}
      try {
        if (liveAssetMedia != null && oldAssetMedia != null) {
          if (assetMediaInstalled && await liveAssetMedia.exists()) {
            await liveAssetMedia.delete(recursive: true);
          }
          if (assetMediaMovedToOld && await oldAssetMedia.exists()) {
            await oldAssetMedia.rename(liveAssetMedia.path);
          }
        }
      } catch (_) {}
      try {
        final staged = File(stagedPath);
        if (await staged.exists()) await staged.delete();
      } catch (_) {}
      try {
        if (stagedReceipts != null && await stagedReceipts.exists()) {
          await stagedReceipts.delete(recursive: true);
        }
      } catch (_) {}
      try {
        if (stagedAssetMedia != null && await stagedAssetMedia.exists()) {
          await stagedAssetMedia.delete(recursive: true);
        }
      } catch (_) {}
      try {
        _db = await openDatabase(
          dbPath,
          version: _dbVersion,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        );
        await _runB3A4V39Compat(_db!);
        await _ensureDefaultBook();
        await _normalizeStandaloneRefunds();
        await _convergeOpenedDatabase(notify: false);
        notifyListeners();
      } catch (_) {}
      return false;
    }
  }

  Future<void> _cleanupCommittedRestore({
    required String dbPath,
    required String oldPath,
    Directory? oldReceipts,
    Directory? oldAssetMedia,
  }) async {
    try {
      await _pruneLocalBackups(File(dbPath).parent);
    } catch (_) {}
    try {
      final old = File(oldPath);
      if (await old.exists()) await old.delete();
    } catch (_) {}
    try {
      if (oldReceipts != null && await oldReceipts.exists()) {
        await oldReceipts.delete(recursive: true);
      }
    } catch (_) {}
    try {
      if (oldAssetMedia != null && await oldAssetMedia.exists()) {
        await oldAssetMedia.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<void> _copyDirectoryTree(Directory source, Directory target) async {
    await target.create(recursive: true);
    if (!await source.exists()) return;
    await for (final entry
        in source.list(recursive: true, followLinks: false)) {
      if (entry is! File) continue;
      final relative = p.relative(entry.path, from: source.path);
      final destination = File(p.join(target.path, relative));
      await destination.parent.create(recursive: true);
      await entry.copy(destination.path);
    }
  }

  Future<bool> _validateAndMigrateRestoreCandidate(String path) async {
    Database? probe;
    Database? migrated;
    try {
      probe = await openReadOnlyDatabase(path);
      final quick = await probe.rawQuery('PRAGMA quick_check');
      if (quick.isEmpty ||
          quick.first.values.first.toString().toLowerCase() != 'ok') {
        return false;
      }
      final version = Sqflite.firstIntValue(
            await probe.rawQuery('PRAGMA user_version'),
          ) ??
          0;
      if (version <= 0 || version > _dbVersion) return false;
      final tables = (await probe.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      ))
          .map((row) => row['name'])
          .whereType<String>()
          .toSet();
      if (!tables.containsAll(
        const {
          'accounts',
          'categories',
          'books',
          'transactions',
          'app_settings'
        },
      )) {
        return false;
      }
      await probe.close();
      probe = null;

      migrated = await openDatabase(
        path,
        version: _dbVersion,
        onUpgrade: _onUpgrade,
        singleInstance: false,
      );
      await _runB3A4V39Compat(migrated);
      final migratedQuick = await migrated.rawQuery('PRAGMA quick_check');
      return migratedQuick.isNotEmpty &&
          migratedQuick.first.values.first.toString().toLowerCase() == 'ok';
    } catch (_) {
      return false;
    } finally {
      await probe?.close();
      await migrated?.close();
    }
  }

  // ---------------------------------------------------------------------------
  // 旧退款归并
  // ---------------------------------------------------------------------------

  /// 把「游离的负数支出行」（v17 之前老版本产生的独立冲账行、或导入残留）
  /// 归并成挂在原订单上的附着式退款（refund_of），净额与月份归属才正确。
  ///
  /// ⚠️ 数据安全铁律（2026-07-09 复审后收紧，别再放宽）：
  /// - 只处理**负数支出行**。收入行一律不碰——用户记的「押金退回」等收入
  ///   是不是退款只有用户知道，猜错=收入凭空消失，宁可不归并。
  /// - 只在**无歧义的高置信匹配**时才挂：分类一致或金额精确等于原单金额，
  ///   且这样的候选恰好一个；候选多于一个直接放弃。归并是锦上添花，
  ///   改错账是信任崩塌。
  /// - 挂上后日期归属原订单（和 refundTransaction 口径一致），非空备注保留。
  Future<void> _normalizeStandaloneRefunds() async {
    final db = _db;
    if (db == null) return;
    final rows = await db.query(
      'transactions',
      columns: [
        'id',
        'book_id',
        'kind',
        'amount',
        'category_id',
        'account_id',
        'note',
        'date_ms',
        'time_precision',
        'refund_of',
      ],
      orderBy: 'id ASC',
    );
    final positiveExpenses = <Map<String, Object?>>[];
    final refundRows = <Map<String, Object?>>[];
    final attached = <int, Decimal>{};

    for (final row in rows) {
      final kind = row['kind'] as String? ?? '';
      // 收入/转账一律不参与归并（也不当原单）。
      if (kind != TransactionKind.expense.toJson()) continue;
      final amount = Decimal.tryParse(row['amount'] as String? ?? '');
      if (amount == null) continue;
      final refundOf = row['refund_of'] as int?;
      if (refundOf != null) {
        attached[refundOf] =
            (attached[refundOf] ?? Decimal.zero) + amount.abs();
        continue;
      }
      if (amount > Decimal.zero) {
        positiveExpenses.add(row);
      } else if (amount < Decimal.zero) {
        refundRows.add(row);
      }
    }

    for (final refund in refundRows) {
      final refundId = refund['id'] as int;
      final refundAmount = Decimal.parse(refund['amount'] as String).abs();
      final refundDate =
          DateTime.fromMillisecondsSinceEpoch(refund['date_ms'] as int);
      final note = (refund['note'] as String? ?? '').trim();
      final looksRefund = note.contains('退款') ||
          note.contains('退回') ||
          note.contains('退货') ||
          note.toLowerCase().contains('refund');
      // 带正经备注（不像退款）的负数行是用户有意为之，不猜。
      if (note.isNotEmpty && !looksRefund) continue;

      final candidates = <Map<String, Object?>>[];
      final strong = <Map<String, Object?>>[];
      for (final orig in positiveExpenses) {
        if (orig['book_id'] != refund['book_id']) continue;
        if (orig['account_id'] != refund['account_id']) continue;
        final origId = orig['id'] as int;
        final origAmount = Decimal.parse(orig['amount'] as String);
        final remaining = origAmount - (attached[origId] ?? Decimal.zero);
        if (remaining < refundAmount) continue; // 剩余可退必须装得下

        final origDate =
            DateTime.fromMillisecondsSinceEpoch(orig['date_ms'] as int);
        final diff = refundDate.difference(origDate);
        // 退款不会发生在下单之前（留 1 天时钟余量），超 90 天也不猜。
        if (diff.inDays < -1 || diff.inDays > 90) continue;

        candidates.add(orig);
        final sameCategory = orig['category_id'] != null &&
            orig['category_id'] == refund['category_id'];
        final exactAmount = origAmount == refundAmount; // 全额退，最常见形态
        if (sameCategory || exactAmount) strong.add(orig);
      }

      Map<String, Object?>? target;
      if (strong.length == 1) {
        target = strong.first;
      } else if (strong.isEmpty && candidates.length == 1 && looksRefund) {
        // 备注明说是退款、且区间内只有唯一一笔装得下 → 也算无歧义。
        target = candidates.first;
      }
      if (target == null) continue; // 有歧义或无匹配：原样保留，绝不猜。

      final origId = target['id'] as int;
      await db.update(
        'transactions',
        {
          'category_id': target['category_id'],
          'account_id': target['account_id'],
          if (note.isEmpty) 'note': '退款',
          'date_ms': target['date_ms'],
          'time_precision': (target['time_precision'] as String?) ??
              TransactionTimePrecision.legacyUnknown.storageKey,
          'refund_of': origId,
          'event_type': TransactionEventType.refund.storageKey,
          'updated_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [refundId],
      );
      // 归并出来的退款和手动退款同口径：原单挂着实物资产时更新资产分摊
      // （标待分配 / 单资产全额自动分配）并刷新购置价缓存。
      await _applyNewRefundToAssetAllocations(
        db,
        originalTransactionId: origId,
        refundTransactionId: refundId,
        refundCents: decimalToBudgetCents(refundAmount).abs(),
      );
      attached[origId] = (attached[origId] ?? Decimal.zero) + refundAmount;
    }
  }

  // ---------------------------------------------------------------------------
  // 收据图片清理
  // ---------------------------------------------------------------------------

  void _deleteReceiptFileIfOwned(String path) {
    if (path.isEmpty || !path.contains('/receipts/')) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  Future<String> _imagePathOf(int id) async {
    final rows = await _db!.query(
      'transactions',
      columns: ['image_path'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? '' : (rows.first['image_path'] as String? ?? '');
  }

  // ---------------------------------------------------------------------------
  // 写操作
  // ---------------------------------------------------------------------------

  Future<String?> transactionMutationBlockReason(int transactionId) async {
    final physicalLinks = await _db!.query(
      'asset_transaction_links',
      columns: ['link_type'],
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
      limit: 1,
    );
    if (physicalLinks.isNotEmpty) {
      final type = AssetTransactionLinkTypeX.fromStorage(
        physicalLinks.first['link_type'] as String?,
      );
      return switch (type) {
        AssetTransactionLinkType.saleAccountMovement =>
          '这笔流水来自资产出售，请先在资产详情中撤销出售。',
        AssetTransactionLinkType.sourceTransaction ||
        AssetTransactionLinkType.purchaseTransaction =>
          '这笔流水已关联实物资产，请先在资产详情中解除关联。',
        AssetTransactionLinkType.maintenance ||
        AssetTransactionLinkType.accessory ||
        AssetTransactionLinkType.insurance ||
        AssetTransactionLinkType.otherCost =>
          '这笔流水已关联物品持有支出，请先在物品详情中解除关联。',
      };
    }
    final recoveries = await _db!.query(
      'receivable_recoveries',
      columns: ['id'],
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
      limit: 1,
    );
    if (recoveries.isNotEmpty) {
      return '这笔流水来自权益收回，请先在资产详情中撤销收回。';
    }
    return null;
  }

  Future<void> _assertTransactionMutable(int transactionId) async {
    final reason = await transactionMutationBlockReason(transactionId);
    if (reason != null) throw StateError(reason);
  }

  static Future<Decimal> _refundedAmountInDb(
    DatabaseExecutor db,
    int transactionId,
  ) async {
    final rows = await db.query(
      'transactions',
      columns: ['amount'],
      where: 'refund_of = ?',
      whereArgs: [transactionId],
    );
    return rows.fold<Decimal>(Decimal.zero, (sum, row) {
      final amount =
          Decimal.tryParse(row['amount'] as String? ?? '') ?? Decimal.zero;
      return sum + amount.abs();
    });
  }

  /// 新增一笔，返回新记录的 id（供记账卡保存后按条目改分类用）。
  /// [bookId] 不传则记到当前账本（手动卡的「账本」芯片可指定记到别的账本）。
  Future<int> addTransaction({
    required TransactionKind kind,
    required Decimal amount,
    String currencyCode = 'CNY',
    int? categoryId,
    required int accountId,
    int? toAccountId,
    String note = '',
    required DateTime date,
    TransactionTimePrecision timePrecision =
        TransactionTimePrecision.entryClock,
    List<int> tagIds = const [],
    bool reimbursable = false,
    String imagePath = '',
    bool excluded = false,
    int? bookId,
    String? autoRecordSourceId,
  }) async {
    final normalizedCurrency = currencyCode.trim().toUpperCase();
    if (normalizedCurrency != 'CNY') {
      throw UnsupportedError('当前版本仅支持新增人民币流水。');
    }
    if (!_isSupportedTransactionAccountId(accountId)) {
      throw ArgumentError('记账账户不存在或币种不受支持');
    }
    if (kind == TransactionKind.transfer) {
      if (toAccountId == null ||
          toAccountId == accountId ||
          !_isSupportedTransactionAccountId(toAccountId)) {
        throw ArgumentError('转入账户不存在、币种不受支持或与转出账户相同');
      }
    } else if (toAccountId != null &&
        !_isSupportedTransactionAccountId(toAccountId)) {
      throw ArgumentError('到账账户不存在或币种不受支持');
    }
    final sourceId = autoRecordSourceId?.trim();
    final values = <String, Object?>{
      'book_id': bookId ?? _currentBookId,
      'kind': kind.toJson(),
      'amount': normalizeMoneyAmount(amount).toString(),
      'currency_code': normalizedCurrency,
      'category_id': categoryId,
      'account_id': accountId,
      'to_account_id': toAccountId,
      'note': note,
      'date_ms': date.millisecondsSinceEpoch,
      'time_precision': timePrecision.storageKey,
      'tags': tagIds.join(','),
      'reimbursable': reimbursable ? 1 : 0,
      'image_path': imagePath,
      'excluded': excluded ? 1 : 0,
      ..._settlementFields(
        settledAt: date,
        settlementAccountId: accountId,
        eventType: _eventTypeForKind(kind),
      ),
      ..._syncStampNew(),
    };
    final newId = sourceId == null || sourceId.isEmpty
        ? await _db!.insert('transactions', values)
        : await _db!.transaction<int>((txn) async {
            final existing = await txn.query(
              'auto_record_occurrences',
              columns: ['transaction_id'],
              where: 'source_id = ?',
              whereArgs: [sourceId],
              limit: 1,
            );
            if (existing.isNotEmpty) {
              final transactionId = existing.first['transaction_id'] as int?;
              if (transactionId != null) return transactionId;
              // A null claim cannot survive the transaction that creates it,
              // but self-heal malformed development data instead of blocking.
              await txn.delete(
                'auto_record_occurrences',
                where: 'source_id = ?',
                whereArgs: [sourceId],
              );
            }
            await txn.insert('auto_record_occurrences', {
              'source_id': sourceId,
              'transaction_id': null,
              'created_ms': DateTime.now().millisecondsSinceEpoch,
            });
            final transactionId = await txn.insert('transactions', values);
            await txn.update(
              'auto_record_occurrences',
              {'transaction_id': transactionId},
              where: 'source_id = ?',
              whereArgs: [sourceId],
            );
            return transactionId;
          });
    await _refreshTransactionRows(ids: {newId});
    await _refreshCurrentNetWorthSnapshotBestEffort({
      kind == TransactionKind.transfer
          ? NetWorthSnapshotCause.transfer
          : NetWorthSnapshotCause.transaction,
    });
    notifyListeners();
    return newId;
  }

  bool _isSupportedTransactionAccountId(int? accountId) =>
      accountId != null &&
      _accounts.any(
        (account) =>
            account.id == accountId &&
            !account.isDeleted &&
            !account.isArchived &&
            account.currencyCode == 'CNY',
      );

  /// 当前账本视角下所有「待报销」的支出（净额大的在前）。
  ///
  /// 过滤和排序都按**净额**：一笔账先收到退款、净额归 0 之后就没有待报销
  /// 金额了，不该继续占一笔（口径标准 §7.1）。按原额过滤会让「N 笔」和用
  /// 净额算出来的合计对不上，明细页和待报销页也会给出不同的笔数。
  ///
  /// 注意：这里用 [LedgerPolicy.netAmountWith]（净额）而不是
  /// [LedgerPolicy.userAmountWith]（用户可见金额）。`excluded: true` 的行
  /// 不计入统计，但只要净额仍为正，就仍需要被报销——两者是独立语义。
  List<TransactionEntity> get reimbursableTransactions {
    final refundTotals = _refundTotals;
    return _transactions
        .where((t) =>
            t.reimbursable &&
            t.txKind == TransactionKind.expense &&
            LedgerPolicy.netAmountWith(t, refundTotals) > Decimal.zero)
        .toList()
      ..sort((a, b) => LedgerPolicy.netAmountWith(b, refundTotals)
          .compareTo(LedgerPolicy.netAmountWith(a, refundTotals)));
  }

  /// 标记一笔已报销：钱报销回来了 = 这笔不算自己的支出，
  /// 所以像退款一样给它补一笔「补满净额」的退款让净额归 0（用户 0703 拍板），
  /// 同时清掉待报销标。原账单仍在列表里，显示成划线原价 + 净额 0。
  Future<void> markReimbursed(
    int id, {
    required DateTime settledAt,
    required int settlementAccountId,
  }) async {
    // 刻意不做 _assertTransactionMutable（与 refundTransaction 对齐）：
    // 报销和退款一样只是给原单挂冲减行，不改写原单本身；资产关联账单的
    // 分摊由下面的 _applyNewRefundToAssetAllocations 处理，断言反而会把
    // 「资产关联账单报销」这条路径整个堵死。
    if (!_accounts.any((account) =>
        account.id == settlementAccountId &&
        !account.isDeleted &&
        account.currencyCode == 'CNY')) {
      throw ArgumentError('报销到账账户不存在或币种不受支持');
    }
    await _db!.transaction((txn) async {
      final rows = await txn.query(
        'transactions',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final original = rows.first;
      final amount =
          Decimal.tryParse(original['amount'] as String? ?? '') ?? Decimal.zero;
      final refunded = await _refundedAmountInDb(txn, id);
      final net = amount - refunded;
      if (net > Decimal.zero) {
        final accountId =
            original['account_id'] as int? ?? _accounts.firstOrNull?.id;
        final reimbursementId = await txn.insert('transactions', {
          'book_id': original['book_id'] as int? ?? _currentBookId,
          'kind': TransactionKind.expense.toJson(),
          'amount': (Decimal.zero - net).toString(),
          'currency_code': original['currency_code'] as String? ?? 'CNY',
          'category_id': original['category_id'] as int?,
          'account_id': accountId,
          'note': '报销到账',
          'date_ms': original['date_ms'] as int,
          'time_precision': (original['time_precision'] as String?) ??
              TransactionTimePrecision.legacyUnknown.storageKey,
          'refund_of': id,
          ..._settlementFields(
            settledAt: settledAt,
            settlementAccountId: settlementAccountId,
            eventType: TransactionEventType.reimbursement,
          ),
          ..._syncStampNew(),
        });
        await _applyNewRefundToAssetAllocations(
          txn,
          originalTransactionId: id,
          refundTransactionId: reimbursementId,
          refundCents: decimalToBudgetCents(net).abs(),
        );
      }
      await txn.update(
        'transactions',
        {
          'reimbursable': 0,
          'updated_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    await _refreshTransactionRows(familyRoots: {id});
    // 与 refundTransaction 对齐：报销同样是一笔冲减，已匹配这笔账单的
    // 固定支出 occurrence 需要回到待复核状态，不能带着旧金额继续算。
    final reimbursedRoot =
        _allTransactions.where((t) => t.id == id).firstOrNull;
    if (reimbursedRoot != null) {
      await _markBudgetOccurrenceRefundReview(reimbursedRoot);
    }
    await _loadPhysicalAssetData(refreshSnapshot: false);
    await _refreshCurrentNetWorthSnapshotBestEffort(
      const {NetWorthSnapshotCause.refund},
    );
    notifyListeners();
  }

  /// 只改某笔的分类（记账卡「一键改分类」用，轻量、不动其它字段）。
  Future<void> setTransactionCategory(int id, int? categoryId) async {
    await _assertTransactionMutable(id);
    final updatedMs = DateTime.now().millisecondsSinceEpoch;
    await _db!.transaction((txn) async {
      await txn.update(
        'transactions',
        {'category_id': categoryId, 'updated_ms': updatedMs},
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.update(
        'transactions',
        {'category_id': categoryId, 'updated_ms': updatedMs},
        where: 'refund_of = ?',
        whereArgs: [id],
      );
    });
    await _refreshTransactionRows(familyRoots: {id});
    notifyListeners();
  }

  /// 退款：记一笔挂在原账单上的「负支出」（refund_of=原id）。
  /// 退款行不在时间线单独显示，改挂到原账单的净额/详情里（对齐咔皮）；
  /// 统计/预算/结余因负数累加自动按净额计算，无需改引擎。
  Future<int> refundTransaction(
    TransactionEntity original,
    Decimal refundAmount, {
    required DateTime settledAt,
    required int settlementAccountId,
  }) async {
    refundAmount = normalizeMoneyAmount(refundAmount);
    if (refundAmount <= Decimal.zero) {
      throw ArgumentError('refund amount must be greater than zero');
    }
    if (!_accounts.any((account) =>
        account.id == settlementAccountId &&
        !account.isDeleted &&
        account.currencyCode == original.currencyCode)) {
      throw ArgumentError('退款到账账户不存在或币种不受支持');
    }
    final refundId = await _db!.transaction<int>((txn) async {
      final rows = await txn.query(
        'transactions',
        where: 'id = ?',
        whereArgs: [original.id],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('original transaction does not exist');
      }
      final stored = rows.first;
      final amount =
          Decimal.tryParse(stored['amount'] as String? ?? '') ?? Decimal.zero;
      final kind = TransactionKind.fromJson(stored['kind'] as String);
      if (stored['refund_of'] != null ||
          kind != TransactionKind.expense ||
          amount <= Decimal.zero) {
        throw StateError('only positive expense transactions can be refunded');
      }
      final refunded = await _refundedAmountInDb(txn, original.id);
      if (refundAmount > amount - refunded) {
        throw StateError('refund amount exceeds remaining refundable amount');
      }
      final accountId =
          stored['account_id'] as int? ?? _accounts.firstOrNull?.id;
      if (accountId == null) {
        throw StateError('refund account does not exist');
      }
      final refundId = await txn.insert('transactions', {
        'book_id': stored['book_id'] as int? ?? _currentBookId,
        'kind': TransactionKind.expense.toJson(),
        'amount': (Decimal.zero - refundAmount).toString(),
        'currency_code': stored['currency_code'] as String? ?? 'CNY',
        'category_id': stored['category_id'] as int?,
        'account_id': accountId,
        'note': '退款',
        'date_ms': stored['date_ms'] as int,
        'time_precision': (stored['time_precision'] as String?) ??
            TransactionTimePrecision.legacyUnknown.storageKey,
        'refund_of': original.id,
        ..._settlementFields(
          settledAt: settledAt,
          settlementAccountId: settlementAccountId,
          eventType: TransactionEventType.refund,
        ),
        ..._syncStampNew(),
      });
      await _applyNewRefundToAssetAllocations(
        txn,
        originalTransactionId: original.id,
        refundTransactionId: refundId,
        refundCents: decimalToBudgetCents(refundAmount).abs(),
      );
      return refundId;
    });
    await _refreshTransactionRows(familyRoots: {original.id});
    await _markBudgetOccurrenceRefundReview(original);
    await _loadPhysicalAssetData(refreshSnapshot: false);
    await _refreshCurrentNetWorthSnapshotBestEffort(
      const {NetWorthSnapshotCause.refund},
    );
    notifyListeners();
    return refundId;
  }

  /// 补确认历史退款/报销的真实到账信息。迁移后的 unknown 只能通过这个
  /// 显式入口升级为 user_confirmed，普通账单编辑不得顺带改写这些字段。
  Future<void> confirmTransactionSettlement(
    int transactionId, {
    required DateTime settledAt,
    required int settlementAccountId,
  }) async {
    final rows = await _db!.query(
      'transactions',
      // uuid 必须在列里：锚点吸收集合存的是事务 uuid，漏了它下面的
      // eventUuid 恒退化成 id 字符串，两个 StateError 护栏全部变死代码。
      columns: ['refund_of', 'event_type', 'currency_code', 'uuid'],
      where: 'id = ?',
      whereArgs: [transactionId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('结算事件不存在');
    final row = rows.first;
    final rootId = row['refund_of'] as int?;
    final eventType = TransactionEventTypeX.fromStorage(
      row['event_type'] as String?,
    );
    if (rootId == null ||
        (eventType != TransactionEventType.refund &&
            eventType != TransactionEventType.reimbursement)) {
      throw StateError('只有退款或报销到账事件可以补确认');
    }
    final currencyCode = row['currency_code'] as String? ?? 'CNY';
    if (!_accounts.any((account) =>
        account.id == settlementAccountId &&
        !account.isDeleted &&
        account.currencyCode == currencyCode)) {
      throw ArgumentError('到账账户不存在或币种不受支持');
    }
    final rawUuid = row['uuid'] as String? ?? '';
    // 与 createAccountBalanceCheckpoint 存吸收集合时的口径一致。
    final eventUuid = rawUuid.isEmpty ? transactionId.toString() : rawUuid;
    final coveringCheckpoints = _checkpointCoveredUnknownEventIds.entries
        .where((entry) => entry.value.contains(eventUuid))
        .map((entry) => _accountBalanceCheckpoints
            .where((checkpoint) => checkpoint.id == entry.key)
            .firstOrNull)
        .whereType<AccountBalanceCheckpointEntity>()
        .where((checkpoint) => checkpoint.isAnchor)
        .toList();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    for (final checkpoint
        in coveringCheckpoints.where((item) => !_reversedAccountCheckpointIds(
              item.accountId,
              asOfMs: nowMs,
              knowledgeCutoffMs: nowMs,
            ).contains(item.id))) {
      if (checkpoint.accountId != settlementAccountId) {
        throw StateError('这笔到账已被其他账户的余额核对吸收，请先撤销原校准再修改到账账户。');
      }
      if (settledAt.millisecondsSinceEpoch > checkpoint.effectiveMs) {
        throw StateError('确认的到账时间晚于吸收它的余额核对时点，请先撤销原校准后重新核对。');
      }
    }
    await _db!.update(
      'transactions',
      {
        'settled_ms': settledAt.millisecondsSinceEpoch,
        'settlement_quality': SettlementQuality.userConfirmed.storageKey,
        'settlement_account_id': settlementAccountId,
        'settlement_account_quality':
            SettlementQuality.userConfirmed.storageKey,
        'updated_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [transactionId],
    );
    await _refreshTransactionRows(familyRoots: {rootId});
    await _refreshCurrentNetWorthSnapshotBestEffort(
      const {NetWorthSnapshotCause.refund, NetWorthSnapshotCause.account},
    );
    notifyListeners();
  }

  /// 时间线可见账单：隐藏「附着式退款行」（它们挂在原账单里）。
  /// 老的独立冲账行 refundOf==null，仍照常显示（不破坏历史）。
  /// 返回副本：调用方可随意 sort/filter，不会弄脏缓存。
  List<TransactionEntity> get visibleTransactions => List.of(
      _visibleTxCache ??= _transactions.where((t) => t.refundOf == null).toList(
            growable: false,
          ));

  /// 稳定引用版本，供 select<AppRepository, List<TransactionEntity>>() 使用。
  /// 底层列表变化时随 _invalidateTxDerived() 一起失效。
  /// 调用方不得对返回值排序或修改——需要可变副本请用 List.of(repo.visibleTransactionsRef)。
  List<TransactionEntity> get visibleTransactionsRef =>
      _visibleTxViewCache ??= List.unmodifiable(
        _visibleTxCache ??=
            _transactions.where((t) => t.refundOf == null).toList(
                  growable: false,
                ),
      );

  /// 某笔账单的退款明细行（按时间正序）。
  List<TransactionEntity> refundsOf(int id) =>
      (_transactions.where((t) => t.refundOf == id).toList())
        ..sort((a, b) => a.dateMs.compareTo(b.dateMs));

  /// 某笔账单已退款合计（正数）。退款行全是负数，索引合计取绝对值即可。
  Decimal refundedAmountOf(int id) => (_refundTotals[id] ?? Decimal.zero).abs();

  /// 某笔账单的净额 = 原额 − 已退（退款行是负数，直接累加即净额）。O(1)。
  Decimal netAmountOf(TransactionEntity t) =>
      LedgerPolicy.netAmountWith(t, _refundTotals);

  /// 指定账本视图/历史报告使用：不依赖当前账本，退款索引覆盖全部账本。
  Decimal netAmountAcrossBooks(TransactionEntity t) =>
      LedgerPolicy.netAmountWith(t, _globalRefundTotals);

  /// 用户可见统计金额：排除不计入行，附着式退款归并到原账单净额。O(1)。
  Decimal userAmountOf(TransactionEntity t) =>
      LedgerPolicy.userAmountWith(t, _refundTotals);

  /// 一批账单里算几笔支出（口径标准 §7.1 的 `expenseCount`）：只数净额为正的
  /// 原始消费家族。页面要显示「N 笔」一律走这里，别自己 `.length`，
  /// 否则全额退款家族会把笔数撑大、和统计页对不上。
  int expenseFamilyCountOf(Iterable<TransactionEntity> transactions) =>
      LedgerPolicy.expenseFamilyCount(transactions, _refundTotals);

  AccountSettlementEvent _accountSettlementEvent(
    TransactionEntity transaction,
  ) =>
      AccountSettlementEvent(
        id: transaction.uuid.isEmpty
            ? transaction.id.toString()
            : transaction.uuid,
        bookId: transaction.bookId ?? _defaultBookId,
        currencyCode: transaction.currencyCode,
        eventType: transaction.eventType,
        legacyKind: transaction.txKind,
        amountMinor: decimalToBudgetCents(transaction.amount),
        attributionAt: transaction.date,
        settledAt: transaction.settledAt,
        settlementQuality: transaction.settlementQuality,
        settlementAccountId: transaction.settlementAccountId,
        settlementAccountQuality: transaction.settlementAccountQuality,
        toAccountId: transaction.toAccountId,
        createdMs: transaction.createdMs,
      );

  List<AccountBalanceMovement> _accountBalanceMovementLegs(
    TransactionEntity transaction,
  ) {
    final eventId =
        transaction.uuid.isEmpty ? transaction.id.toString() : transaction.uuid;
    final amount = decimalToBudgetCents(transaction.amount);
    final absolute = amount.abs();
    AccountBalanceMovement leg({
      required String id,
      required int? accountId,
      required int delta,
      Set<int> candidates = const {},
    }) =>
        AccountBalanceMovement(
          id: id,
          accountId: accountId,
          candidateAccountIds: candidates,
          deltaMinor: delta,
          settledMs: transaction.settledMs,
          sequence: transaction.id,
          createdMs: transaction.createdMs,
        );

    final accountId = transaction.settlementAccountId;
    switch (transaction.eventType) {
      case TransactionEventType.expense ||
            TransactionEventType.assetPurchase ||
            TransactionEventType.principalPayment ||
            TransactionEventType.interest:
        return [leg(id: eventId, accountId: accountId, delta: -absolute)];
      case TransactionEventType.income ||
            TransactionEventType.refund ||
            TransactionEventType.reimbursement ||
            TransactionEventType.assetSale ||
            TransactionEventType.receivableRecovery:
        return [leg(id: eventId, accountId: accountId, delta: absolute)];
      case TransactionEventType.transfer:
        final toAccountId = transaction.toAccountId;
        if (accountId == null ||
            toAccountId == null ||
            accountId == toAccountId) {
          return [
            leg(
              id: eventId,
              accountId: null,
              delta: 0,
              candidates: {
                if (accountId != null) accountId,
                if (toAccountId != null) toAccountId,
              },
            ),
          ];
        }
        return [
          leg(id: '$eventId:out', accountId: accountId, delta: -absolute),
          leg(id: '$eventId:in', accountId: toAccountId, delta: absolute),
        ];
      case TransactionEventType.legacyAdjustment:
        return switch (transaction.txKind) {
          TransactionKind.expense => [
              leg(id: eventId, accountId: accountId, delta: -amount)
            ],
          TransactionKind.income => [
              leg(id: eventId, accountId: accountId, delta: amount)
            ],
          TransactionKind.transfer => transaction.toAccountId == null ||
                  accountId == null ||
                  transaction.toAccountId == accountId
              ? [
                  leg(
                    id: eventId,
                    accountId: null,
                    delta: 0,
                    candidates: {
                      if (accountId != null) accountId,
                      if (transaction.toAccountId != null)
                        transaction.toAccountId!,
                    },
                  ),
                ]
              : [
                  leg(
                    id: '$eventId:out',
                    accountId: accountId,
                    delta: -absolute,
                  ),
                  leg(
                    id: '$eventId:in',
                    accountId: transaction.toAccountId,
                    delta: absolute,
                  ),
                ],
        };
    }
  }

  List<AccountBalanceCheckpointEntity> accountBalanceCheckpointsFor(
    int accountId,
  ) =>
      List.unmodifiable(
        _accountBalanceCheckpoints
            .where((checkpoint) => checkpoint.accountId == accountId)
            .toList()
          ..sort((left, right) {
            final effective = right.effectiveMs.compareTo(left.effectiveMs);
            if (effective != 0) return effective;
            final sequence = right.sequence.compareTo(left.sequence);
            return sequence != 0 ? sequence : right.id.compareTo(left.id);
          }),
      );

  bool isAccountBalanceCheckpointReversed(int checkpointId) {
    final checkpoint = _accountBalanceCheckpoints
        .where((item) => item.id == checkpointId)
        .firstOrNull;
    if (checkpoint == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    return _reversedAccountCheckpointIds(
      checkpoint.accountId,
      asOfMs: now,
      knowledgeCutoffMs: now,
    ).contains(checkpointId);
  }

  Set<int> _reversedAccountCheckpointIds(
    int accountId, {
    required int asOfMs,
    required int knowledgeCutoffMs,
  }) {
    final visible = _accountBalanceCheckpoints
        .where((checkpoint) =>
            checkpoint.accountId == accountId &&
            checkpoint.status == 'active' &&
            checkpoint.createdMs <= knowledgeCutoffMs &&
            checkpoint.effectiveMs <= asOfMs)
        .toList()
      ..sort((left, right) {
        final effective = left.effectiveMs.compareTo(right.effectiveMs);
        if (effective != 0) return effective;
        final sequence = left.sequence.compareTo(right.sequence);
        return sequence != 0 ? sequence : left.id.compareTo(right.id);
      });
    final inactive = <int>{};
    for (final checkpoint in visible.reversed) {
      if (inactive.contains(checkpoint.id)) continue;
      if (checkpoint.isReversal && checkpoint.reversalOf != null) {
        inactive.add(checkpoint.reversalOf!);
      }
    }
    return inactive;
  }

  AccountBalanceCheckpointEntity? _effectiveAccountCheckpoint({
    required int accountId,
    required int asOfMs,
    required int knowledgeCutoffMs,
  }) {
    final reversed = _reversedAccountCheckpointIds(
      accountId,
      asOfMs: asOfMs,
      knowledgeCutoffMs: knowledgeCutoffMs,
    );
    final candidates = _accountBalanceCheckpoints.where(
      (checkpoint) =>
          checkpoint.accountId == accountId &&
          checkpoint.isAnchor &&
          checkpoint.status == 'active' &&
          checkpoint.createdMs <= knowledgeCutoffMs &&
          checkpoint.effectiveMs <= asOfMs &&
          !reversed.contains(checkpoint.id),
    );
    AccountBalanceCheckpointEntity? best;
    for (final candidate in candidates) {
      if (best == null ||
          candidate.effectiveMs > best.effectiveMs ||
          (candidate.effectiveMs == best.effectiveMs &&
              (candidate.sequence > best.sequence ||
                  (candidate.sequence == best.sequence &&
                      candidate.id > best.id)))) {
        best = candidate;
      }
    }
    return best;
  }

  MetricResult<AccountBalanceValue> accountBalanceResultOf(
    AccountEntity account,
  ) {
    _ensureBalanceCacheFresh();
    final cached = _accountBalanceCache[account.id];
    if (cached != null) return cached;
    _balanceRecomputeCount++;
    final result = _accountBalanceResultAt(
      account,
      asOf: DateTime.now(),
      knowledgeCutoff: DateTime.now(),
      historical: false,
    );
    _accountBalanceCache[account.id] = result;
    return result;
  }

  MetricResult<AccountBalanceValue> _accountBalanceResultAt(
    AccountEntity account, {
    required DateTime asOf,
    required DateTime knowledgeCutoff,
    required bool historical,
  }) {
    final bookIds = _books.map((book) => book.id).toList();
    if (bookIds.isEmpty) bookIds.add(_defaultBookId == 0 ? 1 : _defaultBookId);
    final metricQuery = MetricQuery(
      metricId: 'F-ACC-001:${account.id}',
      window: MetricWindow(
        startInclusive: DateTime(1900),
        endExclusive: asOf.add(const Duration(days: 1)),
      ),
      dateAxis: MetricDateAxis.settlement,
      timezone: 'device_local',
      bookScope: MetricBookScope(bookIds: bookIds, scopeVersion: 1),
      currencyScope: MetricCurrencyScope.single(account.currencyCode),
      asOf: asOf,
      knowledgeCutoff: knowledgeCutoff,
    );
    final asOfMs = asOf.millisecondsSinceEpoch;
    final cutoffMs = knowledgeCutoff.millisecondsSinceEpoch;
    final checkpoint = _effectiveAccountCheckpoint(
      accountId: account.id,
      asOfMs: asOfMs,
      knowledgeCutoffMs: cutoffMs,
    );
    final trustedFromMs = checkpoint?.effectiveMs ??
        (account.openingBalanceQuality == AccountOpeningBalanceQuality.exact
            ? account.openingBalanceEffectiveMs
            : null);
    final baselineCutoffMs = checkpoint?.knowledgeCutoffMs ?? account.createdMs;
    final covered = checkpoint == null
        ? const <String>{}
        : _checkpointCoveredUnknownEventIds[checkpoint.id] ?? const <String>{};
    var unresolvedAbsorbedUnknown = 0;
    var backfilledBeforeOpeningCount = 0;
    final events = <AccountSettlementEvent>[];
    for (final transaction in _allTransactions) {
      final event = _accountSettlementEvent(transaction);
      if (trustedFromMs == null) {
        events.add(event);
        continue;
      }
      final settledMs = transaction.settledMs;
      if (settledMs != null &&
          transaction.settlementQuality != SettlementQuality.unknown) {
        if (settledMs > trustedFromMs ||
            (settledMs == trustedFromMs &&
                transaction.createdMs > baselineCutoffMs)) {
          events.add(event);
        } else if (checkpoint == null &&
            transaction.createdMs >= baselineCutoffMs &&
            transaction.createdMs <= asOfMs) {
          // Compatibility for a transaction entered after a newly-created
          // account but attributed to an earlier day. It changes the current
          // balance at knowledge time, while the trusted trend still starts
          // at account creation instead of drawing a fake earlier history.
          events.add(event);
          backfilledBeforeOpeningCount++;
        }
        continue;
      }
      final eventId = event.id;
      final knownAtBaseline = transaction.createdMs == 0 ||
          transaction.createdMs <= baselineCutoffMs;
      if (knownAtBaseline) {
        if (!covered.contains(eventId) &&
            (transaction.settlementAccountId == account.id ||
                transaction.settlementAccountId == null)) {
          unresolvedAbsorbedUnknown++;
        }
        continue;
      }
      events.add(event);
    }
    final coreMovements = <AccountBalanceMovement>[];
    for (final transaction in _allTransactions) {
      final legs = _accountBalanceMovementLegs(transaction);
      final unknownDate = transaction.settledMs == null ||
          transaction.settlementQuality == SettlementQuality.unknown;
      final knownAtBaseline = checkpoint != null &&
          (transaction.createdMs == 0 ||
              transaction.createdMs <= checkpoint.knowledgeCutoffMs);
      for (final leg in legs) {
        final backfilledBeforeOpening = checkpoint == null &&
            account.openingBalanceQuality ==
                AccountOpeningBalanceQuality.exact &&
            transaction.settledMs != null &&
            account.openingBalanceEffectiveMs != null &&
            transaction.settledMs! < account.openingBalanceEffectiveMs! &&
            transaction.createdMs >= account.createdMs;
        if (backfilledBeforeOpening) {
          coreMovements.add(AccountBalanceMovement(
            id: leg.id,
            accountId: leg.accountId,
            candidateAccountIds: leg.candidateAccountIds,
            deltaMinor: leg.deltaMinor,
            settledMs: transaction.createdMs,
            sequence: leg.sequence,
            createdMs: leg.createdMs,
          ));
          continue;
        }
        if (unknownDate &&
            knownAtBaseline &&
            !covered.contains(leg.id) &&
            leg.mayAffect(account.id)) {
          coreMovements.add(AccountBalanceMovement(
            id: leg.id,
            accountId: leg.accountId,
            candidateAccountIds: leg.candidateAccountIds,
            deltaMinor: 0,
            settledMs: null,
            sequence: leg.sequence,
            createdMs: leg.createdMs,
          ));
        } else {
          coreMovements.add(leg);
        }
      }
    }
    final coreResult = AccountBalanceCheckpointResolver.resolve(
      query: AccountBalanceQuery(
        accountId: account.id,
        asOfMs: asOfMs,
        knowledgeCutoffMs: cutoffMs,
        mode: historical
            ? AccountBalanceQueryMode.historical
            : AccountBalanceQueryMode.current,
      ),
      openingBalance: AccountOpeningBalance(
        amountMinor: decimalToBudgetCents(account.openingBalance),
        effectiveMs:
            account.openingBalanceQuality == AccountOpeningBalanceQuality.exact
                ? account.openingBalanceEffectiveMs
                : null,
        sequence: account.openingBalanceSequence,
      ),
      checkpoints: [
        for (final item in _accountBalanceCheckpoints)
          if (item.accountId == account.id && item.status == 'active')
            AccountBalanceCheckpoint(
              id: item.id.toString(),
              accountId: item.accountId,
              effectiveMs: item.effectiveMs,
              sequence: item.sequence,
              knowledgeCutoffMs: item.knowledgeCutoffMs,
              targetBalanceMinor: decimalToBudgetCents(item.targetBalance),
              reversalOf: item.reversalOf?.toString(),
              coveredUnknownEventIds:
                  _checkpointCoveredUnknownEventIds[item.id] ?? const {},
            ),
      ],
      movements: coreMovements,
    );
    final movement = AccountMovementProjection.resolve(
      query: historical
          ? AccountMovementQuery.historicalBalanceAsOf(
              metricQuery: metricQuery,
              balanceAsOf: asOf,
              accountId: account.id,
            )
          : AccountMovementQuery.currentBalance(
              metricQuery: metricQuery,
              accountId: account.id,
            ),
      events: events,
    );
    final movementValue = movement.value!;
    final balance = budgetDecimalFromCents(coreResult.balanceMinor!)!;
    final value = AccountBalanceValue(
      balance: balance,
      movement: movementValue,
      checkpoint: checkpoint,
      trustedFrom: coreResult.trustedFromMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(coreResult.trustedFromMs!),
    );
    final reasons = [...movement.reasons];
    if (coreResult.partialReasons.contains(
      AccountBalancePartialReason.unknownOpeningBalanceEffectiveTime,
    )) {
      reasons.add(MetricReason(
        code: MetricReasonCode.invalidInput,
        message: '历史账户缺少可证明的期初时点，校准前不生成可信余额趋势。',
        details: {'account_id': account.id, 'domain': 'opening_balance'},
      ));
    }
    if (coreResult.partialReasons.contains(
          AccountBalancePartialReason.unknownSettlementAccount,
        ) &&
        !reasons.any((reason) =>
            reason.code == MetricReasonCode.unknownSettlementAccount)) {
      reasons.add(MetricReason(
        code: MetricReasonCode.unknownSettlementAccount,
        message: '仍有到账账户待确认的变动，当前余额只能部分核对。',
        details: {'account_id': account.id},
      ));
    }
    if (coreResult.partialReasons.contains(
          AccountBalancePartialReason.unknownSettlementDate,
        ) &&
        !reasons.any((reason) =>
            reason.code == MetricReasonCode.unknownSettlementDate)) {
      reasons.add(MetricReason(
        code: MetricReasonCode.unknownSettlementDate,
        message: '仍有到账日期待确认的变动，历史余额不能精确分配。',
        details: {'account_id': account.id},
      ));
    }
    if (coreResult.partialReasons.contains(
      AccountBalancePartialReason.missingReversalTarget,
    )) {
      reasons.add(MetricReason(
        code: MetricReasonCode.invalidInput,
        message: '一条余额校准撤销记录缺少目标，结果需要复核。',
        details: {'account_id': account.id, 'domain': 'checkpoint'},
      ));
    }
    if (unresolvedAbsorbedUnknown > 0) {
      reasons.add(MetricReason(
        code: MetricReasonCode.unknownSettlementDate,
        message: '$unresolvedAbsorbedUnknown 笔旧账户变动已被余额锚点吸收，但到账信息仍待确认。',
        details: {
          'account_id': account.id,
          'count': unresolvedAbsorbedUnknown,
          'absorbed_by_checkpoint': checkpoint?.id,
        },
      ));
    }
    if (backfilledBeforeOpeningCount > 0) {
      reasons.add(MetricReason(
        code: MetricReasonCode.assumedSettlementDate,
        message: '$backfilledBeforeOpeningCount 笔早于账户起点的后补流水按录入时点影响余额。',
        details: {
          'account_id': account.id,
          'count': backfilledBeforeOpeningCount,
          'domain': 'backfilled_before_opening',
        },
      ));
    }
    return reasons.isEmpty
        ? MetricResult.available(
            value: value,
            query: movement.query,
            resolver: AccountMovementProjection.resolverName,
          )
        : MetricResult.partial(
            value: value,
            reasons: reasons,
            query: movement.query,
            resolver: AccountMovementProjection.resolverName,
          );
  }

  Decimal accountBalanceOf(AccountEntity account) =>
      accountBalanceResultOf(account).value!.balance;

  MetricResult<AccountBalanceValue> accountBalanceAsOfResult(
    AccountEntity account, {
    required DateTime asOf,
    DateTime? knowledgeCutoff,
  }) =>
      _accountBalanceResultAt(
        account,
        asOf: asOf,
        knowledgeCutoff: knowledgeCutoff ?? DateTime.now(),
        historical: true,
      );

  AccountBalanceTrendValue? accountBalanceTrend(
    AccountEntity account, {
    int days = 90,
  }) {
    // 账户详情页一次 build 会触发 ~91 次全量结算重放，是单点最重的路径，
    // 按 (accountId, days) + (revision, 当天) memo。
    _ensureBalanceCacheFresh();
    final key = (account.id, days);
    if (_accountBalanceTrendCache.containsKey(key)) {
      return _accountBalanceTrendCache[key];
    }
    _trendRecomputeCount++;
    final value = _computeAccountBalanceTrend(account, days: days);
    _accountBalanceTrendCache[key] = value;
    return value;
  }

  AccountBalanceTrendValue? _computeAccountBalanceTrend(
    AccountEntity account, {
    required int days,
  }) {
    final now = DateTime.now();
    final current = accountBalanceResultOf(account).value!;
    final trustedFrom = current.trustedFrom;
    if (trustedFrom == null) return null;
    final requestedStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: max(1, days) - 1));
    var cursor = DateTime(
      trustedFrom.year,
      trustedFrom.month,
      trustedFrom.day,
    );
    if (cursor.isBefore(requestedStart)) cursor = requestedStart;
    final points = <AccountBalanceTrendPoint>[];
    while (!cursor.isAfter(now)) {
      final endOfDay = DateTime(
        cursor.year,
        cursor.month,
        cursor.day,
        23,
        59,
        59,
        999,
      );
      final asOf = endOfDay.isAfter(now) ? now : endOfDay;
      if (!asOf.isBefore(trustedFrom)) {
        final result = accountBalanceAsOfResult(
          account,
          asOf: asOf,
          knowledgeCutoff: now,
        );
        points.add(AccountBalanceTrendPoint(
          asOf: asOf,
          balance: result.value!.balance,
          trusted: result.status == MetricStatus.available,
        ));
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return AccountBalanceTrendValue(
      trustedFrom: trustedFrom,
      points: List.unmodifiable(points),
    );
  }

  List<AccountActivityItem> accountActivitiesFor(
    int accountId, {
    int limit = 12,
  }) {
    final bookNames = {for (final book in _books) book.id: book.name};
    final categoryNames = {
      for (final category in _categories) category.id: category.nameZh,
    };
    final accountCurrency = _accounts
        .where((account) => account.id == accountId)
        .firstOrNull
        ?.currencyCode;
    return AccountActivityProjection.forAccount(
      accountId: accountId,
      limit: limit,
      events: _allTransactions
          .where((transaction) =>
              accountCurrency == null ||
              transaction.currencyCode == accountCurrency)
          .map(
            (transaction) => AccountActivityEvent(
              id: transaction.uuid.isEmpty
                  ? transaction.id.toString()
                  : transaction.uuid,
              bookId: transaction.bookId ?? _defaultBookId,
              currencyCode: transaction.currencyCode,
              eventType: transaction.eventType,
              legacyKind: transaction.txKind,
              amountMinor: decimalToBudgetCents(transaction.amount),
              attributionAt: transaction.date,
              settledAt: transaction.settledAt,
              settlementQuality: transaction.settlementQuality,
              settlementAccountId: transaction.settlementAccountId,
              settlementAccountQuality: transaction.settlementAccountQuality,
              toAccountId: transaction.toAccountId,
              createdMs: transaction.createdMs,
              title: transaction.note.trim().isEmpty
                  ? categoryNames[transaction.categoryId] ?? '账户变动'
                  : transaction.note.trim(),
              categoryName: categoryNames[transaction.categoryId] ?? '',
              bookName: bookNames[transaction.bookId] ?? '总账本',
            ),
          ),
    );
  }

  NetWorthBreakdown currentNetWorthBreakdown() {
    _ensureBalanceCacheFresh();
    return _netWorthBreakdownCache ??= _computeCurrentNetWorthBreakdown();
  }

  NetWorthBreakdown _computeCurrentNetWorthBreakdown() {
    var cashAssets = Decimal.zero;
    var investmentAssets = Decimal.zero;
    var liabilities = Decimal.zero;
    final accountBalances = <int, Decimal>{};
    for (final account in _accounts) {
      if (!account.includeInNetWorth ||
          account.isDeleted ||
          account.currencyCode != 'CNY') {
        continue;
      }
      final balance = accountBalanceOf(account);
      accountBalances[account.id] = balance;
      if (balance >= Decimal.zero) {
        if (account.type == AccountType.investment) {
          investmentAssets += balance;
        } else {
          cashAssets += balance;
        }
      } else {
        liabilities -= balance;
      }
    }
    for (final profile in _liabilityProfiles) {
      if (!profile.countsAsLiability) continue;
      final account =
          _accounts.where((a) => a.id == profile.accountId).firstOrNull;
      if (account == null || account.isDeleted || !account.includeInNetWorth) {
        continue;
      }
      // 外币负债不计入 CNY 净资产（与第一轮循环的币种过滤一致）
      if (account.currencyCode != 'CNY') {
        continue;
      }
      // A5：ledger 口径下余额是唯一真相，档案本金只作合同资料，不进总负债。
      // legacyHybrid（默认）保留老算法：正余额算资产、本金另算负债（双算）。
      if (account.balanceMode.isLedger) continue;
      final accountBalance = accountBalances[account.id] ?? Decimal.zero;
      if (accountBalance >= Decimal.zero) {
        liabilities += profile.currentPrincipal;
      }
    }
    final physical = physicalAssetNetWorthTotal;
    final receivable = receivableAssetNetWorthTotal;
    final totalAssets = cashAssets + investmentAssets + physical + receivable;
    return NetWorthBreakdown(
      totalAssets: totalAssets,
      totalLiabilities: liabilities,
      netWorth: totalAssets - liabilities,
      cashAssets: cashAssets,
      investmentAssets: investmentAssets,
      physicalAssets: physical,
      receivableAssets: receivable,
    );
  }

  MetricResult<NetWorthBreakdown> currentNetWorthResult() {
    _ensureBalanceCacheFresh();
    final cached = _netWorthResultCache;
    if (cached != null) return cached;
    _netWorthRecomputeCount++;
    final result = _computeCurrentNetWorthResult();
    _netWorthResultCache = result;
    return result;
  }

  MetricResult<NetWorthBreakdown> _computeCurrentNetWorthResult() {
    final now = DateTime.now();
    final bookIds = _books.map((book) => book.id).toList();
    if (bookIds.isEmpty) bookIds.add(_defaultBookId == 0 ? 1 : _defaultBookId);
    final query = MetricQuery(
      metricId: 'F-NW-001',
      window: MetricWindow(
        startInclusive: DateTime(1900),
        endExclusive: now.add(const Duration(days: 1)),
      ),
      dateAxis: MetricDateAxis.asOf,
      timezone: 'device_local',
      bookScope: MetricBookScope(bookIds: bookIds, scopeVersion: 1),
      currencyScope: MetricCurrencyScope.single('CNY'),
      asOf: now,
      knowledgeCutoff: now,
    );
    final reasons = <MetricReason>[];

    void addReason(MetricReason reason) {
      if (!reasons.contains(reason)) reasons.add(reason);
    }

    for (final account in _accounts.where(
      (item) => item.includeInNetWorth && !item.isDeleted,
    )) {
      if (account.currencyCode != 'CNY') {
        addReason(MetricReason(
          code: MetricReasonCode.unsupportedCurrencyAggregation,
          message: '外币账户未折算进人民币净资产',
          details: {'account_id': account.id, 'currency': account.currencyCode},
        ));
        continue;
      }
      final balance = accountBalanceResultOf(account);
      for (final reason in balance.reasons) {
        addReason(reason);
      }
    }
    for (final asset in _allPhysicalAssets.where(
      (item) => item.countsInNetWorth,
    )) {
      if (asset.currencyCode != 'CNY') {
        addReason(MetricReason(
          code: MetricReasonCode.unsupportedCurrencyAggregation,
          message: '外币物品未折算进人民币净资产',
          details: {'asset_id': asset.id, 'currency': asset.currencyCode},
        ));
      }
      if (asset.inclusionQuality == AssetInclusionQuality.needsReview) {
        addReason(MetricReason(
          code: MetricReasonCode.invalidInput,
          message: '部分物品的净资产计入口径待确认',
          details: {'asset_id': asset.id, 'domain': 'physical_asset'},
        ));
      }
      if (!_assetValuations.any((point) => point.assetId == asset.id)) {
        addReason(MetricReason(
          code: MetricReasonCode.invalidInput,
          message: '部分物品缺少可追溯估值',
          details: {'asset_id': asset.id, 'domain': 'valuation'},
        ));
      }
    }
    for (final asset in _allReceivableAssets.where(
      (item) => item.countsInNetWorth,
    )) {
      if (asset.currencyCode != 'CNY') {
        addReason(MetricReason(
          code: MetricReasonCode.unsupportedCurrencyAggregation,
          message: '外币权益未折算进人民币净资产',
          details: {'asset_id': asset.id, 'currency': asset.currencyCode},
        ));
      }
      if (asset.inclusionQuality == AssetInclusionQuality.needsReview) {
        addReason(MetricReason(
          code: MetricReasonCode.invalidInput,
          message: '部分权益的净资产计入口径待确认',
          details: {'asset_id': asset.id, 'domain': 'receivable'},
        ));
      }
    }
    for (final profile in _liabilityProfiles.where(
      (item) => item.countsAsLiability,
    )) {
      final account =
          _accounts.where((a) => a.id == profile.accountId).firstOrNull;
      if (account != null && account.currencyCode != 'CNY') {
        addReason(MetricReason(
          code: MetricReasonCode.unsupportedCurrencyAggregation,
          message: '外币负债未折算进人民币净资产',
          details: {'account_id': account.id, 'currency': account.currencyCode},
        ));
      }
    }
    final value = currentNetWorthBreakdown();
    return reasons.isEmpty
        ? MetricResult.available(
            value: value,
            query: query,
            resolver: 'NetWorthAsOfResolver.current',
          )
        : MetricResult.partial(
            value: value,
            reasons: reasons,
            query: query,
            resolver: 'NetWorthAsOfResolver.current',
          );
  }

  NetWorthVerifiedCheckpointComparison? get latestVerifiedNetWorthComparison {
    final complete = _verifiedNetWorthCheckpoints
        .where((checkpoint) =>
            checkpoint.header.status ==
                NetWorthVerifiedCheckpointStatus.active &&
            checkpoint.header.completeness ==
                NetWorthVerifiedCheckpointCompleteness.complete)
        .toList()
      ..sort((left, right) => left.header.asOf.compareTo(right.header.asOf));
    if (complete.length < 2) return null;
    return compareNetWorthVerifiedCheckpoints(
      complete[complete.length - 2],
      complete.last,
    );
  }

  Future<NetWorthVerifiedCheckpoint> createVerifiedNetWorthCheckpoint({
    int? supersedesId,
    bool acceptStaleValuations = false,
  }) async {
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final result = currentNetWorthResult();
    final breakdown = result.value!;
    final uncoveredCurrencies = unsupportedNetWorthCurrencyCodes;
    final currencyCoverage = NetWorthCurrencyCoverage(
      baseCurrency: 'CNY',
      coveredCurrencies: const ['CNY'],
      uncoveredCurrencies: uncoveredCurrencies,
    );
    final reasons = <NetWorthVerifiedCheckpointReason>[
      for (final reason in result.reasons)
        NetWorthVerifiedCheckpointReason(
          code: reason.code.name,
          message: reason.message,
          details: reason.details,
        ),
    ];
    final staleValuationCount = stalePhysicalValuationCount(asOf: now);
    if (staleValuationCount > 0 && !acceptStaleValuations) {
      reasons.add(NetWorthVerifiedCheckpointReason(
        code: 'stale_valuation_not_accepted',
        message: '$staleValuationCount 件物品的估值超过 90 天，尚未明确接受该估值日期。',
        details: {'count': staleValuationCount, 'days': 90},
      ));
    }
    final completeness = reasons.isEmpty && currencyCoverage.isComplete
        ? NetWorthVerifiedCheckpointCompleteness.complete
        : NetWorthVerifiedCheckpointCompleteness.partial;
    if (completeness == NetWorthVerifiedCheckpointCompleteness.partial &&
        reasons.isEmpty) {
      reasons.add(NetWorthVerifiedCheckpointReason(
        code: 'currency_coverage',
        message: '仍有未纳入人民币口径的外币对象。',
        details: {'currencies': uncoveredCurrencies.toList()..sort()},
      ));
    }
    final items = <NetWorthVerifiedCheckpointItem>[];
    final accountBalances = <int, Decimal>{};
    for (final account in _accounts.where(
      (item) => item.includeInNetWorth && !item.isDeleted,
    )) {
      if (account.currencyCode != 'CNY') continue;
      final balanceResult = accountBalanceResultOf(account);
      final value = balanceResult.value!;
      accountBalances[account.id] = value.balance;
      items.add(NetWorthVerifiedCheckpointItem(
        objectType: 'account',
        objectUuid:
            account.uuid.isEmpty ? 'account-${account.id}' : account.uuid,
        confirmedAmountMinor: decimalToBudgetCents(value.balance),
        currencyCode: account.currencyCode,
        valueEffectiveAt: now,
        valueSource:
            value.checkpoint == null ? 'ledger_balance' : 'balance_checkpoint',
        quality: balanceResult.status == MetricStatus.available
            ? 'confirmed'
            : 'partial',
      ));
    }
    for (final profile in _liabilityProfiles.where(
      (item) => item.countsAsLiability,
    )) {
      final account =
          _accounts.where((item) => item.id == profile.accountId).firstOrNull;
      if (account == null ||
          account.isDeleted ||
          !account.includeInNetWorth ||
          account.currencyCode != 'CNY' ||
          (accountBalances[account.id] ?? Decimal.zero) < Decimal.zero) {
        continue;
      }
      // A5：ledger 口径下档案本金不进总负债（余额是唯一真相），因此
      // 也不该在核对快照里留一条 liability_profile 项——否则核对总额
      // 会和 breakdown 对不上。必须与 _computeCurrentNetWorthBreakdown
      // 第二轮的分流条件保持一致。
      if (account.balanceMode.isLedger) continue;
      items.add(NetWorthVerifiedCheckpointItem(
        objectType: 'liability_profile',
        objectUuid:
            profile.uuid.isEmpty ? 'liability-${profile.id}' : profile.uuid,
        confirmedAmountMinor: -decimalToBudgetCents(profile.currentPrincipal),
        currencyCode: account.currencyCode,
        valueEffectiveAt: now,
        valueSource: 'liability_profile',
        quality: 'legacy_hybrid',
      ));
    }
    for (final asset in physicalAssetsCountedInNetWorth) {
      final valuations = _assetValuations
          .where((point) => point.assetId == asset.id)
          .toList()
        ..sort((left, right) => left.valuedAtMs.compareTo(right.valuedAtMs));
      final latest = valuations.lastOrNull;
      final stale = latest != null &&
          latest.valuedAt.isBefore(now.subtract(const Duration(days: 90)));
      items.add(NetWorthVerifiedCheckpointItem(
        objectType: 'physical_asset',
        objectUuid: asset.uuid,
        confirmedAmountMinor: decimalToBudgetCents(asset.currentValue),
        currencyCode: asset.currencyCode,
        valueEffectiveAt: latest?.valuedAt ?? now,
        valueSource: latest?.source.storageKey ?? 'missing_valuation',
        quality: latest == null
            ? 'partial'
            : stale
                ? (acceptStaleValuations ? 'accepted_stale' : 'partial')
                : 'confirmed',
      ));
    }
    for (final asset in receivableAssetsCountedInNetWorth) {
      items.add(NetWorthVerifiedCheckpointItem(
        objectType: 'receivable_asset',
        objectUuid: asset.uuid,
        confirmedAmountMinor: decimalToBudgetCents(asset.remainingAmount),
        currencyCode: asset.currencyCode,
        valueEffectiveAt: now,
        valueSource: 'receivable_ledger',
        quality: asset.inclusionQuality == AssetInclusionQuality.confirmed
            ? 'confirmed'
            : 'partial',
      ));
    }

    late final int id;
    final uuid = _newUuid();
    await _db!.transaction((txn) async {
      if (supersedesId != null) {
        await txn.update(
          'net_worth_verified_checkpoints',
          {'status': NetWorthVerifiedCheckpointStatus.superseded.storageKey},
          where: 'id = ? AND status = ?',
          whereArgs: [
            supersedesId,
            NetWorthVerifiedCheckpointStatus.active.storageKey,
          ],
        );
      }
      id = await txn.insert('net_worth_verified_checkpoints', {
        'uuid': uuid,
        'as_of_ms': nowMs,
        'knowledge_cutoff_ms': nowMs,
        'scope_version': _netWorthScopeVersion,
        'calculation_version': statisticsCalculationVersion,
        'currency_coverage_json': jsonEncode(currencyCoverage.toJson()),
        'total_assets': breakdown.totalAssets.toString(),
        'total_liabilities': breakdown.totalLiabilities.toString(),
        'net_worth': breakdown.netWorth.toString(),
        'completeness': completeness.storageKey,
        'reasons_json': jsonEncode([
          for (final reason in reasons)
            {
              'code': reason.code,
              'message': reason.message,
              if (reason.details.isNotEmpty) 'details': reason.details,
            },
        ]),
        'status': NetWorthVerifiedCheckpointStatus.active.storageKey,
        'supersedes_id': supersedesId,
        'created_ms': nowMs,
      });
      for (final item in items) {
        await txn.insert('net_worth_verified_checkpoint_items', {
          'checkpoint_id': id,
          'object_type': item.key.objectType,
          'object_uuid': item.key.objectUuid,
          'confirmed_amount':
              budgetDecimalFromCents(item.confirmedAmountMinor)!.toString(),
          'currency_code': item.currencyCode,
          'value_effective_ms': item.valueEffectiveAt.millisecondsSinceEpoch,
          'value_source': item.valueSource,
          'quality': item.quality,
        });
      }
      await txn.update(
        'accounts',
        {'last_verified_ms': nowMs, 'updated_ms': nowMs},
        where: "is_deleted = 0 AND status <> 'legacy_hidden'",
      );
    });
    await Future.wait([
      _loadAccounts(),
      _loadVerifiedNetWorthCheckpoints(),
    ]);
    notifyListeners();
    return _verifiedNetWorthCheckpoints
        .where((checkpoint) => checkpoint.header.id == id)
        .first;
  }

  Future<void> revokeVerifiedNetWorthCheckpoint(int id) async {
    await _db!.update(
      'net_worth_verified_checkpoints',
      {'status': NetWorthVerifiedCheckpointStatus.revoked.storageKey},
      where: 'id = ? AND status = ?',
      whereArgs: [id, NetWorthVerifiedCheckpointStatus.active.storageKey],
    );
    await _loadVerifiedNetWorthCheckpoints();
    notifyListeners();
  }

  NetWorthTrendResult get netWorthEstimatedTrend => resolveNetWorthTrend(
        _netWorthSnapshots.map((snapshot) => snapshot.toComputedSnapshot()),
      );

  String _snapshotDateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> recordNetWorthSnapshot({DateTime? date}) async {
    final now = DateTime.now();
    final requested = date ?? now;
    if (_snapshotDateKey(requested) != _snapshotDateKey(now)) {
      throw StateError('当前解析器只能生成今天的计算快照，不能把当前值写成历史日期');
    }
    await _persistCurrentNetWorthSnapshot(
      causes: const {NetWorthSnapshotCause.scheduledRebuild},
      notify: true,
    );
  }

  Future<void> _persistCurrentNetWorthSnapshot({
    required Set<NetWorthSnapshotCause> causes,
    required bool notify,
  }) async {
    if (_db == null) return;
    final mergedCauses = Set<NetWorthSnapshotCause>.from(causes);
    final now = DateTime.now();
    final result = currentNetWorthResult();
    final b = result.value!;
    final missingValuationCount = _allPhysicalAssets
        .where((asset) =>
            asset.countsInNetWorth &&
            !_assetValuations.any((point) => point.assetId == asset.id))
        .length;
    final uncoveredCurrencies = <String>{
      for (final account in _accounts)
        if (account.includeInNetWorth &&
            !account.isDeleted &&
            account.currencyCode != 'CNY')
          account.currencyCode,
      for (final asset in _allPhysicalAssets)
        if (asset.countsInNetWorth && asset.currencyCode != 'CNY')
          asset.currencyCode,
      for (final asset in _allReceivableAssets)
        if (asset.countsInNetWorth && asset.currencyCode != 'CNY')
          asset.currencyCode,
    };
    final currencyCoverage = NetWorthCurrencyCoverage(
      baseCurrency: 'CNY',
      coveredCurrencies: const ['CNY'],
      uncoveredCurrencies: uncoveredCurrencies,
    );
    final valuationCoverage = NetWorthValuationCoverage(
      missingValuationCount: missingValuationCount,
    );
    final quality = result.status == MetricStatus.available
        ? NetWorthSnapshotQuality.available
        : NetWorthSnapshotQuality.partial;
    final reasons = result.reasons
        .map(
          (reason) => NetWorthSnapshotReason(
            code: reason.code.name,
            message: reason.message,
            details: reason.details,
          ),
        )
        .toList(growable: false);
    final dateKey = _snapshotDateKey(now);
    final existing = _netWorthSnapshots
        .where((snapshot) =>
            snapshot.snapshotDate == dateKey && snapshot.isComputed)
        .firstOrNull;
    if (existing != null) {
      mergedCauses.addAll(_decodeNetWorthSnapshotCauses(existing.causeSetJson));
    }
    final previous = _netWorthSnapshots
        .where((snapshot) => snapshot.isComputed)
        .map((snapshot) => snapshot.toComputedSnapshot())
        .firstOrNull;
    if (previous != null) {
      if (previous.lineage.scopeVersion != _netWorthScopeVersion) {
        mergedCauses.add(NetWorthSnapshotCause.scope);
      }
      final components = previous.components;
      if (components.cashAssetsMinor != decimalToBudgetCents(b.cashAssets) ||
          components.investmentAssetsMinor !=
              decimalToBudgetCents(b.investmentAssets)) {
        mergedCauses.add(NetWorthSnapshotCause.account);
      }
      if (components.physicalAssetsMinor !=
          decimalToBudgetCents(b.physicalAssets)) {
        mergedCauses.add(NetWorthSnapshotCause.physicalAsset);
      }
      if (components.receivableAssetsMinor !=
          decimalToBudgetCents(b.receivableAssets)) {
        mergedCauses.add(NetWorthSnapshotCause.receivable);
      }
      if (components.liabilitiesMinor !=
          decimalToBudgetCents(b.totalLiabilities)) {
        mergedCauses.add(NetWorthSnapshotCause.liability);
      }
    }
    if (mergedCauses.isEmpty) {
      mergedCauses.add(NetWorthSnapshotCause.scheduledRebuild);
    }
    final sortedCauses = mergedCauses.map((cause) => cause.storageKey).toList()
      ..sort();
    final asOf = DateTime.utc(now.year, now.month, now.day);
    final timezone = _snapshotTimezoneIdentity(now);
    final lineageKey = 'global|scope=$_netWorthScopeVersion|'
        'calc=$statisticsCalculationVersion|'
        'currency=${currencyCoverage.baseCurrency}|tz=$timezone';
    await _db!.insert(
      'net_worth_snapshots',
      {
        'scope_key': 'global',
        'snapshot_date': dateKey,
        'total_assets': b.totalAssets.toString(),
        'total_liabilities': b.totalLiabilities.toString(),
        'net_worth': b.netWorth.toString(),
        'cash_assets': b.cashAssets.toString(),
        'investment_assets': b.investmentAssets.toString(),
        'physical_assets': b.physicalAssets.toString(),
        'receivable_assets': b.receivableAssets.toString(),
        'snapshot_type': 'computed_snapshot',
        'lineage_key': lineageKey,
        'as_of_ms': asOf.millisecondsSinceEpoch,
        'knowledge_cutoff_ms': now.millisecondsSinceEpoch,
        'timezone': timezone,
        'scope_version': _netWorthScopeVersion,
        'calculation_version': statisticsCalculationVersion,
        'currency_coverage_json': jsonEncode(currencyCoverage.toJson()),
        'quality': quality.storageKey,
        'cause_set_json': jsonEncode(sortedCauses),
        'reasons_json': jsonEncode(
          reasons.map((reason) => reason.toJson()).toList(),
        ),
        'valuation_coverage_json': jsonEncode(valuationCoverage.toJson()),
        'provisional': 1,
        'created_ms': now.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _loadNetWorthSnapshots();
    // 走 override（而非 super.）让 revision 一起 +1，保住「每次通知 = 版本+1」
    // 的失效不变量。
    if (notify) notifyListeners();
  }

  String _snapshotTimezoneIdentity(DateTime value) {
    final offset = value.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final totalMinutes = offset.inMinutes.abs();
    final hours = (totalMinutes ~/ 60).toString().padLeft(2, '0');
    final minutes = (totalMinutes % 60).toString().padLeft(2, '0');
    return 'device_local@UTC$sign$hours:$minutes';
  }

  Future<void> _refreshCurrentNetWorthSnapshotBestEffort(
    Set<NetWorthSnapshotCause> causes,
  ) async {
    try {
      await _persistCurrentNetWorthSnapshot(causes: causes, notify: false);
    } catch (_) {
      // A computed snapshot is a rebuildable cache. User mutations remain
      // committed and the next mutation or startup will repair today's point.
    }
  }

  Future<void> _bumpNetWorthScopeVersion() async {
    final next = _netWorthScopeVersion + 1;
    await _db!.insert(
      'app_settings',
      {'key': 'net_worth_scope_version', 'value': next.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _netWorthScopeVersion = next;
  }

  Future<int> createAssetReport({DateTime? date}) async {
    final at = date ?? DateTime.now();
    final b = currentNetWorthBreakdown();
    final liabilityRate = b.totalAssets <= Decimal.zero
        ? '暂无资产数据'
        : '${(b.totalLiabilities.toDouble() / b.totalAssets.toDouble() * 100).toStringAsFixed(1)}%';
    final title =
        '资产分析报告 ${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
    final summary =
        '当前净资产 ${b.netWorth}，总资产 ${b.totalAssets}，总负债 ${b.totalLiabilities}。';
    final physicalTop = [...physicalAssetsCountedInNetWorth]
      ..sort((a, b) => b.currentValue.compareTo(a.currentValue));
    final receivableTop = [...receivableAssetsCountedInNetWorth]
      ..sort((a, b) => b.remainingAmount.compareTo(a.remainingAmount));
    final markdown = StringBuffer()
      ..writeln('# $title')
      ..writeln()
      ..writeln('## 核心指标')
      ..writeln()
      ..writeln('- 净资产：${b.netWorth}')
      ..writeln('- 总资产：${b.totalAssets}')
      ..writeln('- 总负债：${b.totalLiabilities}')
      ..writeln('- 负债率：$liabilityRate')
      ..writeln()
      ..writeln('## 资产结构')
      ..writeln()
      ..writeln('- 流动资产：${b.cashAssets}')
      ..writeln('- 投资账户：${b.investmentAssets}')
      ..writeln('- 实物资产：${b.physicalAssets}')
      ..writeln('- 权益资产：${b.receivableAssets}')
      ..writeln()
      ..writeln('## 重点实物资产')
      ..writeln();
    if (physicalTop.isEmpty) {
      markdown.writeln('- 暂无计入净资产的实物资产。');
    } else {
      for (final asset in physicalTop.take(5)) {
        markdown.writeln(
          '- ${asset.name}：${asset.currentValue}（${asset.assetType.label}）',
        );
      }
    }
    markdown
      ..writeln()
      ..writeln('## 重点权益资产')
      ..writeln();
    if (receivableTop.isEmpty) {
      markdown.writeln('- 暂无计入净资产的权益资产。');
    } else {
      for (final asset in receivableTop.take(5)) {
        markdown.writeln(
          '- ${asset.name}：剩余 ${asset.remainingAmount}（${asset.type.label}）',
        );
      }
    }
    markdown
      ..writeln()
      ..writeln('## 说明')
      ..writeln()
      ..writeln('资产出售、权益收回属于资产形态转换，不进入普通收入统计。');
    return addReport(
      type: 'asset',
      title: title,
      summary: summary,
      markdown: markdown.toString(),
      periodStart: DateTime(at.year, at.month, at.day),
      periodEnd: DateTime(at.year, at.month, at.day, 23, 59, 59),
    );
  }

  Future<void> updateTransaction({
    required int id,
    required TransactionKind kind,
    required Decimal amount,
    int? categoryId,
    required int accountId,
    int? toAccountId,
    String note = '',
    required DateTime date,
    TransactionTimePrecision? timePrecision,
    List<int> tagIds = const [],
    bool reimbursable = false,
    String imagePath = '',
    bool excluded = false,
  }) async {
    amount = normalizeMoneyAmount(amount);
    if (amount <= Decimal.zero) {
      throw ArgumentError('transaction amount must be greater than zero');
    }
    await _assertTransactionMutable(id);
    final oldPath = await _imagePathOf(id);
    final updatedMs = DateTime.now().millisecondsSinceEpoch;
    await _db!.transaction((txn) async {
      final rows = await txn.query(
        'transactions',
        columns: ['kind', 'account_id', 'to_account_id', 'refund_of'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('transaction does not exist');
      if (rows.first['refund_of'] != null) {
        throw StateError('退款明细不能直接编辑，请在原账单中管理退款。');
      }
      final previousKind =
          TransactionKind.fromJson(rows.first['kind'] as String);
      final accountChanged = rows.first['account_id'] != accountId;
      final toAccountChanged = rows.first['to_account_id'] != toAccountId;
      final changedToTransfer = previousKind != TransactionKind.transfer &&
          kind == TransactionKind.transfer;
      if ((accountChanged || changedToTransfer) &&
          !(await _isSupportedTransactionAccountInDb(txn, accountId))) {
        throw ArgumentError('记账账户不存在、已归档或币种不受支持');
      }
      if (kind == TransactionKind.transfer) {
        if (toAccountId == null || toAccountId == accountId) {
          throw ArgumentError('转入账户不存在或与转出账户相同');
        }
        if ((toAccountChanged || changedToTransfer) &&
            !(await _isSupportedTransactionAccountInDb(txn, toAccountId))) {
          throw ArgumentError('转入账户不存在、已归档或币种不受支持');
        }
      } else if (toAccountId != null &&
          toAccountChanged &&
          !(await _isSupportedTransactionAccountInDb(txn, toAccountId))) {
        throw ArgumentError('到账账户不存在、已归档或币种不受支持');
      }
      final refunded = await _refundedAmountInDb(txn, id);
      if (refunded > Decimal.zero) {
        if (kind != TransactionKind.expense) {
          throw StateError('已有退款的账单不能改为收入或转账。');
        }
        if (amount < refunded) {
          throw StateError('账单金额不能小于已退款金额。');
        }
      }

      final values = <String, Object?>{
        'kind': kind.toJson(),
        'amount': amount.toString(),
        'category_id': categoryId,
        'account_id': accountId,
        'to_account_id': toAccountId,
        'note': note,
        'date_ms': date.millisecondsSinceEpoch,
        'tags': tagIds.join(','),
        'reimbursable': reimbursable ? 1 : 0,
        'image_path': imagePath,
        'excluded': excluded ? 1 : 0,
        // Preserve independent settlement evidence for ordinary edits. An
        // explicit source-account change (or conversion to a transfer) is
        // itself user confirmation of the account that actually settled it.
        'event_type': _eventTypeForKind(kind).storageKey,
        if (accountChanged || changedToTransfer)
          'settlement_account_id': accountId,
        if (accountChanged || changedToTransfer)
          'settlement_account_quality':
              SettlementQuality.userConfirmed.storageKey,
        'updated_ms': updatedMs,
      };
      if (timePrecision != null) {
        values['time_precision'] = timePrecision.storageKey;
      }
      await txn.update(
        'transactions',
        values,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (refunded > Decimal.zero) {
        await txn.update(
          'transactions',
          {
            'category_id': categoryId,
            'date_ms': date.millisecondsSinceEpoch,
            if (timePrecision != null)
              'time_precision': timePrecision.storageKey,
            'updated_ms': updatedMs,
          },
          where: 'refund_of = ?',
          whereArgs: [id],
        );
      }
    });
    if (oldPath != imagePath) _deleteReceiptFileIfOwned(oldPath);
    await _refreshTransactionRows(familyRoots: {id});
    await _refreshCurrentNetWorthSnapshotBestEffort({
      kind == TransactionKind.transfer
          ? NetWorthSnapshotCause.transfer
          : NetWorthSnapshotCause.transaction,
    });
    notifyListeners();
  }

  Future<int> importTransactions(List<TransactionDraft> drafts) async {
    if (drafts.isEmpty) return 0;
    final batch = _db!.batch();
    for (final d in drafts) {
      batch.insert('transactions', {
        'book_id': _currentBookId,
        'kind': d.kind.toJson(),
        'amount': d.amount.toString(),
        'currency_code': 'CNY',
        'category_id': d.categoryId,
        'account_id': d.accountId,
        'to_account_id': null,
        'note': d.note,
        'date_ms': d.date.millisecondsSinceEpoch,
        'time_precision': d.timePrecision.storageKey,
        'tags': d.tagIds.join(','),
        ..._settlementFields(
          settledAt: d.date,
          settlementAccountId: d.accountId,
          eventType: _eventTypeForKind(d.kind),
          dateQuality: SettlementQuality.legacyAssumed,
          accountQuality: SettlementQuality.legacyAssumed,
        ),
        ..._syncStampNew(),
      });
    }
    await batch.commit(noResult: true);
    // 批量导入会一次新增任意数量的行；提交后只做一次全量刷新，避免
    // 为几千个 id 生成超长 IN 查询，也不会退化成“每插一行就全表重载”。
    await _loadTransactions();
    await _refreshCurrentNetWorthSnapshotBestEffort(
      const {NetWorthSnapshotCause.transaction},
    );
    notifyListeners();
    return drafts.length;
  }

  Future<FeimiaoImportResult> importFeimiaoExportRows(
    List<FeimiaoImportRow> rows,
  ) async {
    if (rows.isEmpty) {
      return const FeimiaoImportResult(
        inserted: 0,
        skippedDuplicates: 0,
        refundsAttached: 0,
      );
    }

    final existingUuids = (await _db!.query(
      'transactions',
      columns: ['uuid'],
      where: "uuid <> ''",
    ))
        .map((r) => r['uuid'] as String)
        .toSet();
    final existingFingerprints = await _existingImportFingerprints();
    final uuidToId = <String, int>{};
    var inserted = 0;
    var skipped = 0;
    var refundsAttached = 0;

    String normalizedName(String name) => name.trim().toLowerCase();

    final accountIdsByName = <String, int>{
      for (final account in transactionAccounts)
        normalizedName(account.name): account.id,
    };
    var createdAccounts = false;
    var nextAccountSort = _accounts.fold<int>(
          0,
          (maxSort, account) => max(maxSort, account.sortOrder),
        ) +
        1;
    final accountNames = <String>{
      for (final row in rows) ...[
        if (row.accountName.trim().isNotEmpty) row.accountName.trim(),
        if (row.toAccountName.trim().isNotEmpty) row.toAccountName.trim(),
        if (row.settlementAccountName.trim().isNotEmpty)
          row.settlementAccountName.trim(),
      ],
    };
    var createdTags = false;
    // 整个逐行导入（含新建账户/标签、账单、退款行）包在一个事务里：
    // 中途任何一行失败都整体回滚，不会留下半截导入的脏数据。
    await _db!.transaction((txn) async {
      for (final name in accountNames) {
        final key = normalizedName(name);
        if (accountIdsByName.containsKey(key)) continue;
        final id = await txn.insert('accounts', {
          'uuid': _newUuid(),
          'name': name,
          'currency_code': 'CNY',
          'type': AccountType.cash.storageKey,
          'opening_balance': '0',
          'include_in_net_worth': 1,
          'institution': '',
          'sort_order': nextAccountSort++,
          'created_ms': 0,
          'updated_ms': DateTime.now().millisecondsSinceEpoch,
          'opening_balance_effective_ms': null,
          'opening_balance_sequence': 0,
          'opening_balance_quality':
              AccountOpeningBalanceQuality.legacyUnknown.storageKey,
          'status': AccountStatus.active.storageKey,
        });
        accountIdsByName[key] = id;
        createdAccounts = true;
      }

      int? accountIdByName(String name) {
        final key = normalizedName(name);
        if (key.isEmpty) return transactionAccounts.firstOrNull?.id;
        return accountIdsByName[key];
      }

      final tagIdsByName = <String, int>{
        for (final tag in _tags) normalizedName(tag.name): tag.id,
      };
      final tagNames = <String>{
        for (final row in rows)
          for (final name in row.tagNames)
            if (name.trim().isNotEmpty) name.trim(),
      };
      for (final name in tagNames) {
        final key = normalizedName(name);
        if (tagIdsByName.containsKey(key)) continue;
        final id = await txn.insert('tags', {
          'name': name,
          'color': 0xFF7D8B9B,
        });
        tagIdsByName[key] = id;
        createdTags = true;
      }

      String tagIdsFor(FeimiaoImportRow row) => row.tagNames
          .map((name) => tagIdsByName[normalizedName(name)])
          .whereType<int>()
          .toSet()
          .join(',');

      int? categoryIdFor(FeimiaoImportRow row) {
        if (row.categoryKey.isNotEmpty) {
          final byKey = _categories
              .where((c) => c.key == row.categoryKey && c.kind == row.kind)
              .firstOrNull;
          if (byKey != null) return byKey.id;
        }
        if (row.categoryName.isNotEmpty) {
          final byName = _categories
              .where((c) => c.nameZh == row.categoryName && c.kind == row.kind)
              .firstOrNull;
          if (byName != null) return byName.id;
        }
        return null;
      }

      String nextUuid(String raw) {
        final u = raw.trim();
        if (u.length == 32) return u;
        return _newUuid();
      }

      Map<String, Object?> baseMap(FeimiaoImportRow row) {
        final accountId = accountIdByName(row.accountName);
        final toAccountId = row.toAccountName.trim().isEmpty
            ? null
            : accountIdByName(row.toAccountName);
        final hasExplicitSettlementDate = row.settlementQuality != null;
        final hasExplicitSettlementAccount =
            row.settlementAccountQuality != null;
        final settlementAccountId = row.settlementAccountName.trim().isEmpty
            ? null
            : accountIdByName(row.settlementAccountName);
        final now = DateTime.now().millisecondsSinceEpoch;
        return {
          'book_id': _currentBookId,
          'kind': row.kind.toJson(),
          // 金额写库前统一归一（2 位小数），和手动记账口径一致。
          'amount': normalizeMoneyAmount(row.amount).toString(),
          'currency_code': 'CNY',
          'category_id': categoryIdFor(row),
          'account_id': accountId,
          'to_account_id': toAccountId,
          'note': row.note,
          'date_ms': row.date.millisecondsSinceEpoch,
          'time_precision': row.timePrecision.storageKey,
          'tags': tagIdsFor(row),
          'reimbursable': row.reimbursable ? 1 : 0,
          'image_path': '',
          'excluded': row.excluded ? 1 : 0,
          'created_ms': now,
          'settled_ms': hasExplicitSettlementDate
              ? row.settledAt?.millisecondsSinceEpoch
              : row.date.millisecondsSinceEpoch,
          'settlement_quality':
              (row.settlementQuality ?? SettlementQuality.legacyAssumed)
                  .storageKey,
          'settlement_account_id':
              hasExplicitSettlementAccount ? settlementAccountId : accountId,
          'settlement_account_quality':
              (row.settlementAccountQuality ?? SettlementQuality.legacyAssumed)
                  .storageKey,
          'event_type':
              (row.eventType ?? _eventTypeForKind(row.kind)).storageKey,
          'updated_ms': now,
        };
      }

      final explicitRefundParents = {
        for (final r in rows)
          if (r.refundOfUuid.trim().isNotEmpty) r.refundOfUuid.trim(),
      };
      final originals =
          rows.where((r) => r.refundOfUuid.trim().isEmpty).toList();
      for (final row in originals) {
        final uuid = nextUuid(row.uuid);
        if (existingUuids.contains(uuid)) {
          final existing = await txn.query(
            'transactions',
            columns: ['id'],
            where: 'uuid = ?',
            whereArgs: [uuid],
            limit: 1,
          );
          if (existing.isNotEmpty) {
            uuidToId[uuid] = existing.first['id'] as int;
          }
          skipped++;
          continue;
        }
        final fp = _importFingerprint(
          kind: row.kind,
          amount: normalizeMoneyAmount(row.amount),
          date: row.date,
          note: row.note,
        );
        if (row.uuid.isEmpty &&
            _consumeExistingImportFingerprint(existingFingerprints, fp) !=
                null) {
          skipped++;
          continue;
        }
        final id = await txn.insert('transactions', {
          ...baseMap(row),
          'uuid': uuid,
          'refund_of': null,
        });
        uuidToId[uuid] = id;
        existingUuids.add(uuid);
        inserted++;

        if (row.refunded > Decimal.zero &&
            row.amount > Decimal.zero &&
            !explicitRefundParents.contains(uuid)) {
          if (row.refunded > row.amount) {
            skipped++;
            continue;
          }
          final refunded = normalizeMoneyAmount(row.refunded);
          final refundId = await txn.insert('transactions', {
            ...baseMap(row),
            'amount': (Decimal.zero - refunded).toString(),
            'note': '退款',
            'uuid': _newUuid(),
            'refund_of': id,
            'settled_ms': null,
            'settlement_quality': SettlementQuality.unknown.storageKey,
            'event_type': TransactionEventType.refund.storageKey,
          });
          // 和手动退款同口径：原单挂着实物资产时更新资产分摊并刷新
          // 购置价缓存（资产页「分配退款」入口才会出现）。
          await _applyNewRefundToAssetAllocations(
            txn,
            originalTransactionId: id,
            refundTransactionId: refundId,
            refundCents: decimalToBudgetCents(refunded).abs(),
          );
          refundsAttached++;
        }
      }

      final refunds = rows.where((r) => r.refundOfUuid.trim().isNotEmpty);
      for (final row in refunds) {
        final uuid = nextUuid(row.uuid);
        if (existingUuids.contains(uuid)) {
          skipped++;
          continue;
        }
        final originalId = uuidToId[row.refundOfUuid.trim()];
        if (originalId == null) {
          skipped++;
          continue;
        }
        final requestedRefund = normalizeMoneyAmount(row.amount.abs());
        final originalRows = await txn.query(
          'transactions',
          columns: ['amount'],
          where: 'id = ?',
          whereArgs: [originalId],
          limit: 1,
        );
        if (originalRows.isEmpty) {
          skipped++;
          continue;
        }
        final originalAmount =
            Decimal.tryParse(originalRows.first['amount'] as String? ?? '') ??
                Decimal.zero;
        var existingRefunded = Decimal.zero;
        final existingRefundRows = await txn.query(
          'transactions',
          columns: ['amount'],
          where: 'refund_of = ?',
          whereArgs: [originalId],
        );
        for (final existingRefund in existingRefundRows) {
          existingRefunded +=
              (Decimal.tryParse(existingRefund['amount'] as String? ?? '') ??
                      Decimal.zero)
                  .abs();
        }
        if (requestedRefund > originalAmount - existingRefunded) {
          skipped++;
          continue;
        }
        final inferredEventType = row.eventType ??
            (row.note.trim() == '报销到账'
                ? TransactionEventType.reimbursement
                : TransactionEventType.refund);
        final refundMap = <String, Object?>{
          ...baseMap(row),
          'amount': (Decimal.zero - requestedRefund).toString(),
          'note': row.note.trim().isEmpty ? '退款' : row.note,
          'uuid': uuid,
          'refund_of': originalId,
          'event_type': inferredEventType.storageKey,
        };
        if (row.settlementQuality == null) {
          refundMap['settled_ms'] = null;
          refundMap['settlement_quality'] =
              SettlementQuality.unknown.storageKey;
        }
        if (row.settlementAccountQuality == null &&
            inferredEventType == TransactionEventType.reimbursement) {
          refundMap['settlement_account_id'] = null;
          refundMap['settlement_account_quality'] =
              SettlementQuality.unknown.storageKey;
        }
        final refundId = await txn.insert('transactions', refundMap);
        // 同上：导入的退款也要参与原单的资产分摊。
        await _applyNewRefundToAssetAllocations(
          txn,
          originalTransactionId: originalId,
          refundTransactionId: refundId,
          refundCents: decimalToBudgetCents(requestedRefund).abs(),
        );
        existingUuids.add(uuid);
        refundsAttached++;
      }
    });

    if (createdAccounts) await _loadAccounts();
    if (createdTags) await _loadTags();
    await _loadTransactions();
    if (refundsAttached > 0) {
      // 退款可能改动了资产分摊/购置价缓存，把内存态一并刷新。
      await _loadPhysicalAssetData(refreshSnapshot: false);
    }
    await _refreshCurrentNetWorthSnapshotBestEffort(
      const {
        NetWorthSnapshotCause.transaction,
        NetWorthSnapshotCause.refund,
      },
    );
    notifyListeners();
    return FeimiaoImportResult(
      inserted: inserted,
      skippedDuplicates: skipped,
      refundsAttached: refundsAttached,
    );
  }

  /// 导入去重指纹。只用「账单本身」的稳定字段（方向+金额+分钟+备注）：
  /// 分类/账户是用户本次导入时选的，重复导入同一份账单时常常不同，
  /// 掺进指纹会让去重失效、整批翻倍。
  String _importFingerprint({
    required TransactionKind kind,
    required Decimal amount,
    required DateTime date,
    required String note,
  }) {
    final minute = DateTime(
      date.year,
      date.month,
      date.day,
      date.hour,
      date.minute,
    );
    return [
      kind.toJson(),
      amount.toString(),
      minute.millisecondsSinceEpoch.toString(),
      note.trim(),
    ].join('|');
  }

  int? _consumeExistingImportFingerprint(
    Map<String, List<int>> existing,
    String fingerprint,
  ) {
    final ids = existing[fingerprint];
    if (ids == null || ids.isEmpty) return null;
    return ids.removeLast();
  }

  Future<Map<String, List<int>>> _existingImportFingerprints() async {
    final rows = await _db!.query(
      'transactions',
      columns: [
        'id',
        'kind',
        'amount',
        'date_ms',
        'note',
        'category_id',
        'account_id',
      ],
      where: 'book_id = ?',
      whereArgs: [_currentBookId],
    );
    final result = <String, List<int>>{};
    for (final r in rows) {
      final fp = _importFingerprint(
        kind: TransactionKind.fromJson(r['kind'] as String),
        amount: Decimal.parse(r['amount'] as String),
        date: DateTime.fromMillisecondsSinceEpoch(r['date_ms'] as int),
        note: r['note'] as String? ?? '',
      );
      (result[fp] ??= <int>[]).add(r['id'] as int);
    }
    return result;
  }

  String _refundMatchKey(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'退款|退回|退货|成功|订单|商户|备注|微信转账'), '')
        .replaceAll(RegExp(r'[\s·,，。:：;；()（）\-_]+'), '')
        .trim();
  }

  Future<ImportBatchResult> importReviewedBillBatch({
    required int accountId,
    required List<({ImportedBillRow row, String? categoryKey})> rows,
    required List<ImportedBillRow> refunds,
  }) async {
    if (rows.isEmpty && refunds.isEmpty) {
      return const ImportBatchResult(
        inserted: 0,
        skippedDuplicates: 0,
        refundsAttached: 0,
      );
    }
    if (!_isSupportedTransactionAccountId(accountId)) {
      throw ArgumentError('导入账户不存在或币种不受支持');
    }

    int? idOf(String? key, TransactionKind k) => key == null
        ? null
        : _categories.where((c) => c.key == key && c.kind == k).firstOrNull?.id;

    final existing = await _existingImportFingerprints();
    final orderToId = <String, int>{};
    final insertedRows = <({int id, ImportedBillRow row, int? categoryId})>[];
    final attachedRefunds = <int, Decimal>{};
    var inserted = 0;
    var skipped = 0;
    var refundsAttached = 0;
    var unresolvedRefunds = 0;

    final normalRows = <({ImportedBillRow row, String? categoryKey})>[];
    final refundRows = <ImportedBillRow>[...refunds];
    for (final item in rows) {
      // 只信解析阶段的 isRefund 判定。以前这里还按「退款/退货」关键词
      // 二次抓捕，会把用户在复核页已归好类的正常支出（退货运费险等）
      // 重新抢进退款队列。
      if (item.row.isRefund) {
        refundRows.add(item.row);
      } else {
        normalRows.add(item);
      }
    }

    await _db!.transaction((txn) async {
      Future<void> insertRow(ImportedBillRow r, String? key) async {
        final categoryId = idOf(key, r.kind);
        // 金额统一走 normalizeMoneyAmount（保留 2 位小数），和手动记账口径一致；
        // 指纹也用归一后的金额，保证和库里已存行的指纹能对上。
        final amount = normalizeMoneyAmount(r.amount);
        final fp = _importFingerprint(
          kind: r.kind,
          amount: amount,
          date: r.date,
          note: r.note,
        );
        final existingId = _consumeExistingImportFingerprint(existing, fp);
        if (existingId != null) {
          skipped++;
          if (r.orderNo.isNotEmpty) orderToId[r.orderNo] = existingId;
          insertedRows.add((id: existingId, row: r, categoryId: categoryId));
          return;
        }
        final id = await txn.insert('transactions', {
          'book_id': _currentBookId,
          'kind': r.kind.toJson(),
          'amount': amount.toString(),
          'currency_code': 'CNY',
          'category_id': categoryId,
          'account_id': accountId,
          'to_account_id': null,
          'note': r.note,
          'date_ms': r.date.millisecondsSinceEpoch,
          'time_precision': r.timePrecision.storageKey,
          'tags': '',
          // 商户订单号落库：以后跨批/跨月导入的退款靠它挂回这笔原单。
          'order_no': r.orderNo,
          ..._settlementFields(
            settledAt: r.date,
            settlementAccountId: accountId,
            eventType: _eventTypeForKind(r.kind),
            dateQuality: SettlementQuality.exact,
          ),
          ..._syncStampNew(),
        });
        inserted++;
        if (r.orderNo.isNotEmpty) orderToId[r.orderNo] = id;
        insertedRows.add((id: id, row: r, categoryId: categoryId));
      }

      Future<int?> findRefundOriginalId(ImportedBillRow r) async {
        if (r.orderNo.isNotEmpty) {
          final exact = orderToId[r.orderNo];
          if (exact != null) return exact;
          // 跨批/跨月配对：原单可能是之前某次导入落库的（order_no 已持久化）。
          // 只认同账本、非退款的支出行；金额上限仍由调用方的 remaining 校验兜底。
          final historical = await txn.query(
            'transactions',
            columns: ['id'],
            where: 'order_no = ? AND refund_of IS NULL AND kind = ? '
                'AND book_id = ?',
            whereArgs: [
              r.orderNo,
              TransactionKind.expense.toJson(),
              _currentBookId,
            ],
            orderBy: 'id ASC',
            limit: 1,
          );
          if (historical.isNotEmpty) return historical.first['id'] as int;
        }
        final rMerchant = _refundMatchKey(r.merchant);
        final rText = _refundMatchKey('${r.product} ${r.note}');
        var bestScore = -1;
        var bestScoreCount = 0;
        int? bestId;
        for (final c in insertedRows) {
          if (c.row.kind != TransactionKind.expense) continue;
          final attached = attachedRefunds[c.id] ?? Decimal.zero;
          final remaining = c.row.amount - attached;
          if (remaining <= Decimal.zero) continue;
          final cMerchant = _refundMatchKey(c.row.merchant);
          final cText = _refundMatchKey('${c.row.product} ${c.row.note}');
          var score = 0;
          if (rMerchant.isNotEmpty && rMerchant == cMerchant) score += 8;
          if (rText.isNotEmpty &&
              cText.isNotEmpty &&
              (rText.contains(cText) || cText.contains(rText))) {
            score += 3;
          }
          final days = r.date.difference(c.row.date).inDays.abs();
          if (days <= 1) {
            score += 3;
          } else if (days <= 45) {
            score += 1;
          }
          if (remaining >= r.amount) score += 2;
          if (score > bestScore) {
            bestScore = score;
            bestScoreCount = 1;
            bestId = c.id;
          } else if (score == bestScore) {
            bestScoreCount++;
          }
        }
        // 同分并列 = 有歧义：即使商户名强匹配（≥8 分）也拒绝配对，
        // 走 unresolved 收入兜底——错挂到别的订单比配不上更伤信任。
        final uniqueStrongMatch = bestScore >= 8 && bestScoreCount == 1;
        final uniqueSameDayAmountFit = bestScore >= 5 && bestScoreCount == 1;
        return uniqueStrongMatch || uniqueSameDayAmountFit ? bestId : null;
      }

      for (final item in normalRows) {
        await insertRow(item.row, item.categoryKey);
      }

      for (final r in refundRows) {
        final origId = await findRefundOriginalId(r);
        if (origId == null) {
          // 配不上原单的退款不再静默丢弃（那是真实到账的钱）：按收入入库，
          // 分类落收入侧「退款报销」（兜底其他收入），备注保留原文，
          // 用户可事后手改；unresolvedRefunds 仍计数，供导入完成提示用。
          unresolvedRefunds++;
          final incomeAmount = normalizeMoneyAmount(r.amount.abs());
          final fallbackNote = r.note.trim().isEmpty ? '退款' : r.note;
          final fallbackFp = _importFingerprint(
            kind: TransactionKind.income,
            amount: incomeAmount,
            date: r.date,
            note: fallbackNote,
          );
          if (_consumeExistingImportFingerprint(existing, fallbackFp) != null) {
            skipped++;
            continue;
          }
          final fallbackCategoryId = idOf('refund', TransactionKind.income) ??
              idOf('otherIncome', TransactionKind.income);
          await txn.insert('transactions', {
            'book_id': _currentBookId,
            'kind': TransactionKind.income.toJson(),
            'amount': incomeAmount.toString(),
            'currency_code': 'CNY',
            'category_id': fallbackCategoryId,
            'account_id': accountId,
            'to_account_id': null,
            'note': fallbackNote,
            'date_ms': r.date.millisecondsSinceEpoch,
            'time_precision': r.timePrecision.storageKey,
            'tags': '',
            'order_no': r.orderNo,
            ..._settlementFields(
              settledAt: r.date,
              settlementAccountId: accountId,
              eventType: TransactionEventType.income,
              dateQuality: SettlementQuality.exact,
            ),
            ..._syncStampNew(),
          });
          inserted++;
          continue;
        }
        final origRows = await txn.query(
          'transactions',
          columns: ['amount', 'category_id', 'date_ms', 'time_precision'],
          where: 'id = ?',
          whereArgs: [origId],
          limit: 1,
        );
        if (origRows.isEmpty) continue;
        final orig = origRows.first;
        final originalAmount =
            Decimal.tryParse(orig['amount'] as String? ?? '') ?? Decimal.zero;
        final categoryId = orig['category_id'] as int?;
        final dateMs = orig['date_ms'] as int;
        final timePrecision = TransactionTimePrecisionX.fromStorage(
          orig['time_precision'] as String?,
        );
        final requestedRefund = normalizeMoneyAmount(r.amount.abs());
        var dbRefunded = Decimal.zero;
        final refundRowsForOriginal = await txn.query(
          'transactions',
          columns: ['amount'],
          where: 'refund_of = ?',
          whereArgs: [origId],
        );
        for (final row in refundRowsForOriginal) {
          dbRefunded +=
              (Decimal.tryParse(row['amount'] as String? ?? '') ?? Decimal.zero)
                  .abs();
        }
        // 剩余可退只认库里的事实：事务内 query 已能看到本批刚插入的退款行，
        // 再叠加 attachedRefunds 会把同一笔退款扣两次（同批多笔退款被误拒）。
        final remaining = originalAmount - dbRefunded;
        if (remaining <= Decimal.zero || requestedRefund > remaining) {
          unresolvedRefunds++;
          continue;
        }
        final refundAmount = Decimal.zero - requestedRefund;
        final fp = _importFingerprint(
          kind: TransactionKind.expense,
          amount: refundAmount,
          date: DateTime.fromMillisecondsSinceEpoch(dateMs),
          note: '退款',
        );
        if (_consumeExistingImportFingerprint(existing, fp) != null) {
          skipped++;
          continue;
        }
        final refundId = await txn.insert('transactions', {
          'book_id': _currentBookId,
          'kind': TransactionKind.expense.toJson(),
          'amount': refundAmount.toString(),
          'currency_code': 'CNY',
          'category_id': categoryId,
          'account_id': accountId,
          'note': '退款',
          'date_ms': dateMs,
          'time_precision': timePrecision.storageKey,
          'refund_of': origId,
          'order_no': r.orderNo,
          ..._settlementFields(
            settledAt: r.date,
            settlementAccountId: accountId,
            eventType: TransactionEventType.refund,
            dateQuality: SettlementQuality.exact,
          ),
          ..._syncStampNew(),
        });
        // 和手动退款（refundTransaction）同口径：原单挂着实物资产时，
        // 把退款摊进资产分摊（单资产全额场景自动分配，否则标待分配）
        // 并刷新购置价缓存，资产页「分配退款」入口才会出现。
        await _applyNewRefundToAssetAllocations(
          txn,
          originalTransactionId: origId,
          refundTransactionId: refundId,
          refundCents: decimalToBudgetCents(requestedRefund).abs(),
        );
        attachedRefunds[origId] =
            (attachedRefunds[origId] ?? Decimal.zero) + requestedRefund;
        refundsAttached++;
      }
    });

    await _normalizeStandaloneRefunds();
    await _loadTransactions();
    if (refundsAttached > 0) {
      // 退款可能改动了资产分摊/购置价缓存，把内存态一并刷新。
      await _loadPhysicalAssetData(refreshSnapshot: false);
    }
    await _refreshCurrentNetWorthSnapshotBestEffort(
      const {
        NetWorthSnapshotCause.transaction,
        NetWorthSnapshotCause.refund,
      },
    );
    notifyListeners();
    return ImportBatchResult(
      inserted: inserted,
      skippedDuplicates: skipped,
      refundsAttached: refundsAttached,
      unresolvedRefunds: unresolvedRefunds,
    );
  }

  Future<void> deleteTransaction(int id) async {
    final deleting = _allTransactions
        .where((transaction) => transaction.id == id)
        .firstOrNull;
    final originalId = deleting?.refundOf;
    if (originalId != null) {
      final returnedAssetIds = _allPhysicalAssets
          .where((asset) =>
              !asset.isDeleted &&
              asset.economicStatus == PhysicalAssetEconomicStatus.returned)
          .map((asset) => asset.id)
          .toSet();
      final touchesReturnedAsset = _assetTransactionLinks.any(
        (link) =>
            link.transactionId == originalId &&
            returnedAssetIds.contains(link.assetId) &&
            link.allocatedRefundCents > 0,
      );
      if (touchesReturnedAsset) {
        throw StateError('这笔退款已经用于确认物品退货，请先撤销退货');
      }
    }
    await _assertTransactionMutable(id);
    final path = await _imagePathOf(id);
    var familyRoot = id;
    await _db!.transaction((txn) async {
      final rows = await txn.query(
        'transactions',
        columns: ['id', 'refund_of', 'event_type'],
        where: 'id = ? OR refund_of = ?',
        whereArgs: [id, id],
      );
      final selected = rows.where((row) => row['id'] == id).firstOrNull;
      familyRoot = selected?['refund_of'] as int? ?? id;
      if (familyRoot != id) {
        await _assertRefundDeletionAllowed(txn, id);
      }
      final refundIds = rows
          .where((row) => row['refund_of'] != null)
          .map((row) => row['id'] as int)
          .toList();
      await _reverseRefundAllocationAudit(txn, refundIds);
      // 删原账单时连它的退款行一起删，退款分配审计只反转、不删除。
      await txn.delete('transactions',
          where: 'id = ? OR refund_of = ?', whereArgs: [id, id]);
      if (familyRoot != id) {
        // 撤销报销：删除的是「报销到账」冲减行时，原单要回到待报销队列，
        // 否则这笔钱既没真报销回来、又从待报销列表里消失了。
        if ((selected?['event_type'] as String?) ==
            TransactionEventType.reimbursement.storageKey) {
          await txn.update(
            'transactions',
            {
              'reimbursable': 1,
              'updated_ms': DateTime.now().millisecondsSinceEpoch,
            },
            where: 'id = ?',
            whereArgs: [familyRoot],
          );
        }
        // 退款行删除后再按剩余有效退款重算；若在删除前计算，会把
        // 即将删除的退款误判成“尚未分配”。
        await _refreshOrderAllocationQuality(txn, familyRoot);
      }
    });
    _deleteReceiptFileIfOwned(path);
    await _refreshTransactionRows(familyRoots: {familyRoot});
    await _refreshBudgetOccurrenceRefundReview(familyRoot);
    await _loadPhysicalAssetData(refreshSnapshot: false);
    await _refreshCurrentNetWorthSnapshotBestEffort(
      const {
        NetWorthSnapshotCause.transaction,
        NetWorthSnapshotCause.refund,
      },
    );
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 查询辅助
  // ---------------------------------------------------------------------------

  List<CategoryEntity> categoriesForKind(TransactionKind kind) =>
      _categories.where((c) => c.kind == kind).toList();

  List<CategoryEntity> categoriesForKindRanked(TransactionKind kind) {
    final all = categoriesForKind(kind);
    // 记账面板不展示已隐藏的分类（管理页用 categoriesForKind 能看到全部）。
    final tops = all.where((c) => c.isTopLevel && !c.hidden).toList();
    final counts = <int, int>{};
    for (final t in _transactions) {
      final cid = t.categoryId;
      if (cid == null || t.txKind != kind) continue;
      counts[cid] = (counts[cid] ?? 0) + 1;
    }
    final rolled = <int, int>{};
    for (final c in all) {
      final n = counts[c.id] ?? 0;
      if (n == 0) continue;
      final top = c.isTopLevel ? c.id : (c.parentId ?? c.id);
      rolled[top] = (rolled[top] ?? 0) + n;
    }
    final indexed = [for (var i = 0; i < tops.length; i++) (i, tops[i])];
    indexed.sort((a, b) {
      final ca = rolled[a.$2.id] ?? 0;
      final cb = rolled[b.$2.id] ?? 0;
      return ca != cb ? cb.compareTo(ca) : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  List<CategoryEntity> childrenOf(int parentId) =>
      _categories.where((c) => c.parentId == parentId).toList();

  /// 未隐藏的子分类（记账面板判断「可不可展开」用它，管理页用 childrenOf）。
  List<CategoryEntity> visibleChildrenOf(int parentId) =>
      _categories.where((c) => c.parentId == parentId && !c.hidden).toList();

  /// 子分类按「这个人用得多不多」排序：记过的次数多在前，没记过的保持原顺序。
  /// 手动卡的二级分类展开面板用它，让常用子类排前面少翻找。已隐藏的不出现。
  List<CategoryEntity> childrenOfRanked(int parentId) {
    final children = visibleChildrenOf(parentId);
    if (children.length < 2) return children;
    final counts = <int, int>{};
    for (final t in _transactions) {
      final cid = t.categoryId;
      if (cid != null) counts[cid] = (counts[cid] ?? 0) + 1;
    }
    final indexed = [
      for (var i = 0; i < children.length; i++) (i, children[i])
    ];
    indexed.sort((a, b) {
      final ca = counts[a.$2.id] ?? 0;
      final cb = counts[b.$2.id] ?? 0;
      return ca != cb ? cb.compareTo(ca) : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  /// 某大类本月支出合计（含其子类）。用于分类预算进度。
  Decimal monthSpentForTopCategory(int topCategoryId, {DateTime? month}) {
    final m = month ?? DateTime.now();
    final ids = <int>{topCategoryId};
    for (final c in _categories) {
      if (c.parentId == topCategoryId) ids.add(c.id);
    }
    var sum = Decimal.zero;
    for (final t in _transactions) {
      if (t.txKind != TransactionKind.expense) continue;
      if (t.excluded || t.refundOf != null) continue;
      if (t.categoryId == null || !ids.contains(t.categoryId)) continue;
      if (t.date.year != m.year || t.date.month != m.month) continue;
      final net = netAmountOf(t);
      if (net > Decimal.zero) sum += net;
    }
    return sum;
  }

  /// 供统计/预算/洞察消费的记录流：**跳过「不计入收支」的账**。
  /// 账单列表要显示全部请用 [transactions]。
  /// 结果按 _transactions 版本缓存（主页/统计/小组件每次 rebuild 都要它，
  /// 以前每次访问都是全量 O(n²) 重算）；返回副本防调用方 sort 弄脏缓存。
  List<TransactionRecord> get allRecords =>
      List.of(_allRecordsCache ??= _buildAllRecords());

  /// 稳定引用版本，供 select<> / identical() 缓存判断使用。
  /// 底层 _transactions 变化时随 _invalidateTxDerived() 一起失效。
  /// 调用方不得排序或修改返回值。
  List<TransactionRecord> get allRecordsRef =>
      _allRecordsViewCache ??= List.unmodifiable(
        _allRecordsCache ??= _buildAllRecords(),
      );

  List<TransactionRecord> _buildAllRecords() =>
      _buildUserRecords(_transactions, _refundTotals);

  List<TransactionEntity> visibleTransactionsForBookView(int bookId) {
    final allowed = _bookIdsForView(bookId).toSet();
    return _globalVisibleTransactions
        .where((transaction) =>
            transaction.bookId != null && allowed.contains(transaction.bookId))
        .toList(growable: false);
  }

  List<TransactionRecord> recordsForBookView(int bookId) {
    final allowed = _bookIdsForView(bookId).toSet();
    final transactions = _allTransactions.where((transaction) =>
        transaction.bookId != null && allowed.contains(transaction.bookId));
    return _buildUserRecords(transactions, _globalRefundTotals);
  }

  List<TransactionRecord> _buildUserRecords(
    Iterable<TransactionEntity> transactions,
    Map<int, Decimal> refundTotals,
  ) {
    final categoryById = {for (final c in _categories) c.id: c};
    return [
      for (final t in transactions)
        if (!t.excluded && t.refundOf == null)
          (() {
            final category =
                t.categoryId == null ? null : categoryById[t.categoryId];
            final topCategory = category?.parentId == null
                ? category
                : categoryById[category!.parentId!];
            final effectiveTop = topCategory ?? category;
            return LedgerPolicy.toUserRecordWith(t, refundTotals).copyWith(
              topCategoryName: effectiveTop?.nameZh ?? '',
              topCategoryKey: effectiveTop?.key ?? '',
            );
          })(),
    ];
  }

  // ---------------------------------------------------------------------------
  // 预算期间（新模型：阶段性预算）
  // ---------------------------------------------------------------------------

  String _encodeBudgetCategoryCents(Map<String, int> categories) =>
      jsonEncode(categories);

  String _encodeBudgetFixedTemplates(
    Iterable<BudgetFixedTemplateV2> templates,
  ) =>
      jsonEncode([
        for (final template in templates)
          {
            'id': template.id,
            'name': template.name,
            'planned_cents': template.plannedCents,
            'due_value': template.dueValue,
          },
      ]);

  BudgetPlanCycleV2 _budgetCycleForStartChoice({
    required BudgetPlanCadenceV2 cadence,
    required DateTime now,
    required int monthStartDay,
    required int weekStart,
    required bool nextCycle,
  }) {
    final day = DateTime(now.year, now.month, now.day);
    late DateTime start;
    late DateTime end;
    if (cadence == BudgetPlanCadenceV2.monthly) {
      start = DateTime(day.year, day.month, monthStartDay);
      if (day.isBefore(start)) {
        start = DateTime(day.year, day.month - 1, monthStartDay);
      }
      if (nextCycle) {
        start = DateTime(start.year, start.month + 1, monthStartDay);
      }
      end = DateTime(start.year, start.month + 1, monthStartDay);
    } else {
      final offset = (day.weekday - weekStart + 7) % 7;
      start = day.subtract(Duration(days: offset));
      if (nextCycle) start = start.add(const Duration(days: 7));
      end = start.add(const Duration(days: 7));
    }
    return BudgetPlanCycleV2(planId: 0, start: start, endExclusive: end);
  }

  DateTime _fixedTemplateDueDate(
    BudgetPlanV2 plan,
    BudgetPlanCycleV2 cycle,
    BudgetFixedTemplateV2 template,
  ) {
    if (plan.cadence == BudgetPlanCadenceV2.weekly) {
      final offset = (template.dueValue - cycle.start.weekday + 7) % 7;
      return cycle.start.add(Duration(days: offset));
    }
    var due = DateTime(cycle.start.year, cycle.start.month, template.dueValue);
    if (due.isBefore(cycle.start)) {
      due =
          DateTime(cycle.start.year, cycle.start.month + 1, template.dueValue);
    }
    if (!due.isBefore(cycle.endExclusive)) {
      due = cycle.endInclusive;
    }
    return due;
  }

  Future<void> _insertBudgetOccurrencesForRevision(
    DatabaseExecutor txn, {
    required BudgetPlanV2 plan,
    required int revisionId,
    required BudgetPlanCycleV2 cycle,
    required Iterable<BudgetFixedTemplateV2> templates,
    required int nowMs,
  }) async {
    for (final template in templates) {
      await txn.insert(
        'budget_fixed_commitment_occurrences',
        {
          'uuid': _newUuid(),
          'plan_id': plan.id,
          'revision_id': revisionId,
          'template_id': template.id,
          'cycle_start_day': cycle.startDayKey,
          'cycle_end_day': cycle.endDayKey,
          'due_day': budgetCivilDayKey(
            _fixedTemplateDueDate(plan, cycle, template),
          ),
          'planned_cents': template.plannedCents,
          'resolution_status':
              FixedCommitmentResolutionStatus.planned.storageValue,
          'review_reason': '',
          'matched_transaction_family_uuid': null,
          'resolved_ms': null,
          'created_ms': nowMs,
          'updated_ms': nowMs,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> _syncBudgetOccurrencesForRevision(
    DatabaseExecutor txn, {
    required BudgetPlanV2 plan,
    required int revisionId,
    required BudgetPlanCycleV2 cycle,
    required Iterable<BudgetFixedTemplateV2> templates,
    required int nowMs,
  }) async {
    final remaining = {
      for (final template in templates) template.id: template,
    };
    final rows = await txn.query(
      'budget_fixed_commitment_occurrences',
      where: 'plan_id = ? AND cycle_start_day = ?',
      whereArgs: [plan.id, cycle.startDayKey],
    );
    for (final row in rows) {
      final id = row['id'] as int;
      final templateId = row['template_id'] as String;
      final template = remaining.remove(templateId);
      final status = row['resolution_status'] as String? ?? 'planned';
      final linked = row['matched_transaction_family_uuid'] as String?;
      final untouched =
          status == FixedCommitmentResolutionStatus.planned.storageValue &&
              linked == null;
      if (template == null) {
        if (untouched) {
          await txn.delete(
            'budget_fixed_commitment_occurrences',
            where: 'id = ?',
            whereArgs: [id],
          );
        } else {
          await txn.update(
            'budget_fixed_commitment_occurrences',
            {
              'revision_id': revisionId,
              'resolution_status':
                  FixedCommitmentResolutionStatus.requiresReview.storageValue,
              'review_reason':
                  FixedCommitmentReviewReason.amountConflict.storageValue,
              'matched_transaction_family_uuid': null,
              'resolved_ms': null,
              'updated_ms': nowMs,
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
        continue;
      }
      final dueDay = budgetCivilDayKey(
        _fixedTemplateDueDate(plan, cycle, template),
      );
      final amountChanged = row['planned_cents'] != template.plannedCents ||
          row['due_day'] != dueDay;
      final updates = <String, Object?>{
        'revision_id': revisionId,
        'planned_cents': template.plannedCents,
        'due_day': dueDay,
        'updated_ms': nowMs,
      };
      if (amountChanged && !untouched) {
        updates.addAll({
          'resolution_status':
              FixedCommitmentResolutionStatus.requiresReview.storageValue,
          'review_reason':
              FixedCommitmentReviewReason.amountConflict.storageValue,
          'matched_transaction_family_uuid': null,
          'resolved_ms': null,
        });
      }
      await txn.update(
        'budget_fixed_commitment_occurrences',
        updates,
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await _insertBudgetOccurrencesForRevision(
      txn,
      plan: plan,
      revisionId: revisionId,
      cycle: cycle,
      templates: remaining.values,
      nowMs: nowMs,
    );
  }

  Future<int> addBudgetPlanV2({
    required int bookId,
    required String name,
    required BudgetPlanCadenceV2 cadence,
    required int totalCents,
    Map<String, int> categoryBudgetsCents = const {},
    int? monthlyIncomeCents,
    List<BudgetFixedTemplateV2> fixedTemplates = const [],
    int monthStartDay = 1,
    int weekStart = DateTime.monday,
    bool startNextCycle = true,
  }) async {
    if (cadence == BudgetPlanCadenceV2.oneOff) {
      throw ArgumentError('一次性计划请使用专项追踪。');
    }
    if (!_books.any((book) => book.id == bookId)) {
      throw ArgumentError('预算必须选择一个明确账本');
    }
    if (totalCents <= 0 ||
        categoryBudgetsCents.values.fold<int>(0, (a, b) => a + b) >
            totalCents ||
        fixedTemplates.fold<int>(0, (sum, item) => sum + item.plannedCents) >
            totalCents) {
      throw ArgumentError('预算总额、分类额度或固定支出不合法');
    }
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final cycle = _budgetCycleForStartChoice(
      cadence: cadence,
      now: now,
      monthStartDay: monthStartDay,
      weekStart: weekStart,
      nextCycle: startNextCycle,
    );
    final alreadyCoversStart = _budgetPlansV2.any((plan) =>
        plan.isPrimary && plan.bookId == bookId && plan.covers(cycle.start));
    if (alreadyCoversStart) {
      throw StateError('这个周期已有主预算记录，请调整现有计划，或选择下周期生效。');
    }
    final futurePlans = _budgetPlansV2
        .where((plan) =>
            plan.isPrimary &&
            plan.bookId == bookId &&
            plan.status == BudgetPlanStatusV2.active &&
            plan.anchorStart.isAfter(cycle.start) &&
            (plan.endInclusive == null ||
                !plan.endInclusive!.isBefore(cycle.start)))
        .toList();
    // A plan scheduled for the next cycle must not lock the current cycle out.
    // Keep that future plan intact and make this one a bounded bridge ending
    // the day before the earliest scheduled plan starts.
    DateTime? nextPlanStart;
    for (final plan in futurePlans) {
      if (nextPlanStart == null || plan.anchorStart.isBefore(nextPlanStart)) {
        nextPlanStart = plan.anchorStart;
      }
    }
    final bridgeEndInclusive = nextPlanStart?.subtract(const Duration(days: 1));
    late final int planId;
    await _db!.transaction((txn) async {
      planId = await txn.insert('budget_plans', {
        'uuid': _newUuid(),
        'book_id': bookId,
        'currency_code': 'CNY',
        'timezone': 'device_local',
        'name': name.trim(),
        'role': 'primary',
        'cadence': cadence.storageKey,
        'anchor_start_day': cycle.startDayKey,
        'month_start_day':
            cadence == BudgetPlanCadenceV2.monthly ? monthStartDay : null,
        'week_start': cadence == BudgetPlanCadenceV2.weekly ? weekStart : null,
        'end_day': bridgeEndInclusive == null
            ? null
            : budgetCivilDayKey(bridgeEndInclusive),
        'status': BudgetPlanStatusV2.active.storageKey,
        'created_ms': nowMs,
        'updated_ms': nowMs,
      });
      final revisionId = await txn.insert('budget_plan_revisions', {
        'uuid': _newUuid(),
        'plan_id': planId,
        'effective_cycle_start_day': cycle.startDayKey,
        'effective_to_cycle_start_day': null,
        'amount_cents': totalCents,
        'category_budgets_json':
            _encodeBudgetCategoryCents(categoryBudgetsCents),
        'monthly_income_cents': monthlyIncomeCents,
        'fixed_templates_json': _encodeBudgetFixedTemplates(fixedTemplates),
        'legacy_source_period_id': null,
        'created_ms': nowMs,
        'updated_ms': nowMs,
      });
      final persistedPlan = BudgetPlanV2(
        id: planId,
        uuid: 'pending-$planId',
        bookId: bookId,
        cadence: cadence,
        anchorStart: cycle.start,
        monthStartDay:
            cadence == BudgetPlanCadenceV2.monthly ? monthStartDay : null,
        weekStart: cadence == BudgetPlanCadenceV2.weekly ? weekStart : null,
        endInclusive: bridgeEndInclusive,
      );
      await _insertBudgetOccurrencesForRevision(
        txn,
        plan: persistedPlan,
        revisionId: revisionId,
        cycle: BudgetPlanCycleV2(
          planId: planId,
          start: cycle.start,
          endExclusive: cycle.endExclusive,
        ),
        templates: fixedTemplates,
        nowMs: nowMs,
      );
      await txn.insert('budget_change_events', {
        'uuid': _newUuid(),
        'plan_id': planId,
        'event_type': 'plan_created',
        'before_json': '',
        'after_json': jsonEncode({
          'total_cents': totalCents,
          'effective_cycle_start_day': cycle.startDayKey,
        }),
        'created_ms': nowMs,
      });
    });
    await _loadBudgetV2();
    notifyListeners();
    return planId;
  }

  Future<int> saveBudgetSpecialTrackingV2({
    int? planId,
    required int bookId,
    required String name,
    required DateTime startInclusive,
    required DateTime endInclusive,
    required int totalCents,
    required BudgetExpenseScopeV2 expenseScope,
    Map<String, int> categoryBudgetsCents = const {},
  }) async {
    if (!_books.any((book) => book.id == bookId)) {
      throw ArgumentError('专项追踪必须选择一个明确账本');
    }
    final start = DateTime(
      startInclusive.year,
      startInclusive.month,
      startInclusive.day,
    );
    final end = DateTime(
      endInclusive.year,
      endInclusive.month,
      endInclusive.day,
    );
    final normalizedName = name.trim();
    final categoryTotal =
        categoryBudgetsCents.values.fold<int>(0, (sum, value) => sum + value);
    if (normalizedName.isEmpty ||
        end.isBefore(start) ||
        totalCents < 0 ||
        expenseScope.isEmpty ||
        categoryBudgetsCents.values.any((value) => value < 0) ||
        categoryTotal > totalCents ||
        categoryBudgetsCents.keys
            .any((key) => !expenseScope.categoryKeys.contains(key))) {
      throw ArgumentError('专项名称、日期、额度或消费范围不合法');
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    late final int savedPlanId;
    await _db!.transaction((txn) async {
      if (planId == null) {
        savedPlanId = await txn.insert('budget_plans', {
          'uuid': _newUuid(),
          'book_id': bookId,
          'currency_code': 'CNY',
          'timezone': 'device_local',
          'name': normalizedName,
          'role': 'special',
          'cadence': BudgetPlanCadenceV2.oneOff.storageKey,
          'anchor_start_day': budgetCivilDayKey(start),
          'month_start_day': null,
          'week_start': null,
          'end_day': budgetCivilDayKey(end),
          'expense_scope_json': expenseScope.toJsonString(),
          'status': BudgetPlanStatusV2.active.storageKey,
          'created_ms': nowMs,
          'updated_ms': nowMs,
        });
        await txn.insert('budget_plan_revisions', {
          'uuid': _newUuid(),
          'plan_id': savedPlanId,
          'effective_cycle_start_day': budgetCivilDayKey(start),
          'effective_to_cycle_start_day': null,
          'amount_cents': totalCents,
          'category_budgets_json':
              _encodeBudgetCategoryCents(categoryBudgetsCents),
          'monthly_income_cents': null,
          'fixed_templates_json': '[]',
          'legacy_source_period_id': null,
          'created_ms': nowMs,
          'updated_ms': nowMs,
        });
        await txn.insert('budget_change_events', {
          'uuid': _newUuid(),
          'plan_id': savedPlanId,
          'event_type': 'special_created',
          'before_json': '',
          'after_json': jsonEncode({
            'start_day': budgetCivilDayKey(start),
            'end_day': budgetCivilDayKey(end),
            'total_cents': totalCents,
            'expense_scope': expenseScope.toJson(),
          }),
          'created_ms': nowMs,
        });
        return;
      }

      final existingPlanRows = await txn.query(
        'budget_plans',
        where: "id = ? AND role = 'special'",
        whereArgs: [planId],
        limit: 1,
      );
      if (existingPlanRows.isEmpty) {
        throw StateError('专项追踪不存在');
      }
      final existingPlan = existingPlanRows.first;
      if (existingPlan['status'] == BudgetPlanStatusV2.archived.storageKey) {
        throw StateError('已归档专项追踪不能再修改');
      }
      final versionMs = max(
        nowMs,
        (existingPlan['updated_ms'] as int? ?? 0) + 1,
      );
      final revisionRows = await txn.query(
        'budget_plan_revisions',
        where: 'plan_id = ?',
        whereArgs: [planId],
        orderBy: 'id ASC',
      );
      if (revisionRows.isEmpty) {
        throw StateError('专项追踪缺少额度记录');
      }
      final revision = revisionRows.first;
      savedPlanId = await txn.insert('budget_plans', {
        'uuid': _newUuid(),
        'book_id': bookId,
        'currency_code': 'CNY',
        'timezone': 'device_local',
        'name': normalizedName,
        'role': 'special',
        'cadence': BudgetPlanCadenceV2.oneOff.storageKey,
        'anchor_start_day': budgetCivilDayKey(start),
        'month_start_day': null,
        'week_start': null,
        'end_day': budgetCivilDayKey(end),
        'expense_scope_json': expenseScope.toJsonString(),
        'status': BudgetPlanStatusV2.active.storageKey,
        'created_ms': versionMs,
        'updated_ms': versionMs,
      });
      await txn.insert('budget_plan_revisions', {
        'uuid': _newUuid(),
        'plan_id': savedPlanId,
        'effective_cycle_start_day': budgetCivilDayKey(start),
        'effective_to_cycle_start_day': null,
        'amount_cents': totalCents,
        'category_budgets_json':
            _encodeBudgetCategoryCents(categoryBudgetsCents),
        'monthly_income_cents': null,
        'fixed_templates_json': '[]',
        'legacy_source_period_id': null,
        'created_ms': versionMs,
        'updated_ms': versionMs,
      });
      await txn.update(
        'budget_plans',
        {
          'status': BudgetPlanStatusV2.archived.storageKey,
          'updated_ms': versionMs,
        },
        where: 'id = ?',
        whereArgs: [planId],
      );
      await txn.insert('budget_change_events', {
        'uuid': _newUuid(),
        'plan_id': planId,
        'event_type': 'special_superseded',
        'before_json': jsonEncode({
          'plan': existingPlan,
          'revision': revision,
        }),
        'after_json': jsonEncode({'successor_plan_id': savedPlanId}),
        'created_ms': versionMs,
      });
      await txn.insert('budget_change_events', {
        'uuid': _newUuid(),
        'plan_id': savedPlanId,
        'event_type': 'special_created',
        'before_json': jsonEncode({'supersedes_plan_id': planId}),
        'after_json': jsonEncode({
          'start_day': budgetCivilDayKey(start),
          'end_day': budgetCivilDayKey(end),
          'total_cents': totalCents,
          'expense_scope': expenseScope.toJson(),
        }),
        'created_ms': versionMs,
      });
    });
    await _loadBudgetV2();
    notifyListeners();
    return savedPlanId;
  }

  Future<int> addBudgetPlanRevisionV2({
    required int planId,
    required int totalCents,
    Map<String, int> categoryBudgetsCents = const {},
    int? monthlyIncomeCents,
    List<BudgetFixedTemplateV2> fixedTemplates = const [],
    DateTime? effectiveCycleStart,
  }) async {
    final plan = _budgetPlansV2.where((item) => item.id == planId).firstOrNull;
    if (plan == null) throw StateError('预算计划不存在');
    final current = plan.cycleFor(DateTime.now());
    final start = effectiveCycleStart ?? current.endExclusive;
    final cycle = plan.cycleFor(start);
    if (cycle.start != DateTime(start.year, start.month, start.day)) {
      throw ArgumentError('预算修订只能从完整周期边界生效');
    }
    if (totalCents <= 0 ||
        categoryBudgetsCents.values.fold<int>(0, (a, b) => a + b) >
            totalCents ||
        fixedTemplates.fold<int>(0, (sum, item) => sum + item.plannedCents) >
            totalCents) {
      throw ArgumentError('预算修订金额不合法');
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    late final int revisionId;
    await _db!.transaction((txn) async {
      final existing = await txn.query(
        'budget_plan_revisions',
        where: 'plan_id = ? AND effective_cycle_start_day = ?',
        whereArgs: [planId, cycle.startDayKey],
        limit: 1,
      );
      final revisionPayload = <String, Object?>{
        'amount_cents': totalCents,
        'category_budgets_json':
            _encodeBudgetCategoryCents(categoryBudgetsCents),
        'monthly_income_cents': monthlyIncomeCents,
        'fixed_templates_json': _encodeBudgetFixedTemplates(fixedTemplates),
        'updated_ms': nowMs,
      };
      if (existing.isEmpty) {
        await txn.update(
          'budget_plan_revisions',
          {
            'effective_to_cycle_start_day': cycle.startDayKey,
            'updated_ms': nowMs,
          },
          where:
              'plan_id = ? AND effective_to_cycle_start_day IS NULL AND effective_cycle_start_day < ?',
          whereArgs: [planId, cycle.startDayKey],
        );
        revisionId = await txn.insert('budget_plan_revisions', {
          'uuid': _newUuid(),
          'plan_id': planId,
          'effective_cycle_start_day': cycle.startDayKey,
          'effective_to_cycle_start_day': null,
          ...revisionPayload,
          'legacy_source_period_id': null,
          'created_ms': nowMs,
        });
      } else {
        revisionId = existing.first['id'] as int;
        await txn.update(
          'budget_plan_revisions',
          revisionPayload,
          where: 'id = ?',
          whereArgs: [revisionId],
        );
      }
      await _syncBudgetOccurrencesForRevision(
        txn,
        plan: plan,
        revisionId: revisionId,
        cycle: cycle,
        templates: fixedTemplates,
        nowMs: nowMs,
      );
      await txn.insert('budget_change_events', {
        'uuid': _newUuid(),
        'plan_id': planId,
        'event_type':
            existing.isEmpty ? 'revision_created' : 'revision_updated',
        'before_json': existing.isEmpty ? '' : jsonEncode(existing.first),
        'after_json': jsonEncode({
          'revision_id': revisionId,
          'total_cents': totalCents,
          'effective_cycle_start_day': cycle.startDayKey,
        }),
        'created_ms': nowMs,
      });
    });
    await _loadBudgetV2();
    notifyListeners();
    return revisionId;
  }

  Future<void> upsertBudgetCycleOverrideV2({
    required int planId,
    required DateTime cycleStart,
    required int targetAmountCents,
    Map<String, int>? categoryBudgetsCents,
    BudgetOverrideIntent inputIntent = BudgetOverrideIntent.replaceTotal,
    int? inputDeltaCents,
  }) async {
    final plan = _budgetPlansV2.where((item) => item.id == planId).firstOrNull;
    if (plan == null) throw StateError('预算计划不存在');
    final cycle = plan.cycleFor(cycleStart);
    if (cycle.start !=
        DateTime(cycleStart.year, cycleStart.month, cycleStart.day)) {
      throw ArgumentError('本周期调整必须指向完整周期起点');
    }
    final categories = categoryBudgetsCents ??
        _budgetPlanRevisionsV2
            .where((revision) => revision.appliesTo(cycle))
            .lastOrNull
            ?.categoryBudgetsCents ??
        const <String, int>{};
    if (targetAmountCents < 0 ||
        categories.values.fold<int>(0, (a, b) => a + b) > targetAmountCents) {
      throw ArgumentError('调整后的分类额度超过了周期总额');
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _db!.transaction((txn) async {
      final existing = await txn.query(
        'budget_cycle_overrides',
        where: 'plan_id = ? AND cycle_start_day = ?',
        whereArgs: [planId, cycle.startDayKey],
        limit: 1,
      );
      final payload = {
        'uuid': existing.isEmpty ? _newUuid() : existing.first['uuid'],
        'plan_id': planId,
        'cycle_start_day': cycle.startDayKey,
        'cycle_end_day': cycle.endDayKey,
        'target_amount_cents': targetAmountCents,
        'category_budgets_json': categoryBudgetsCents == null
            ? null
            : _encodeBudgetCategoryCents(categoryBudgetsCents),
        'input_intent': inputIntent.storageKey,
        'input_delta_cents': inputDeltaCents,
        'created_ms': existing.isEmpty
            ? nowMs
            : existing.first['created_ms'] as int? ?? nowMs,
        'updated_ms': nowMs,
      };
      await txn.insert(
        'budget_cycle_overrides',
        payload,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert('budget_change_events', {
        'uuid': _newUuid(),
        'plan_id': planId,
        'event_type': 'cycle_override_saved',
        'before_json': existing.isEmpty ? '' : jsonEncode(existing.first),
        'after_json': jsonEncode(payload),
        'created_ms': nowMs,
      });
    });
    await _loadBudgetV2();
    notifyListeners();
  }

  Future<void> archiveBudgetPlanV2(int planId) async {
    final plan = _budgetPlansV2.where((item) => item.id == planId).firstOrNull;
    if (plan == null || plan.status == BudgetPlanStatusV2.archived) return;
    final today = DateTime.now();
    final cycle = plan.cycleFor(today);
    final archiveEnd = plan.isSpecial
        ? budgetCivilDayKey(plan.endInclusive!)
        : today.isBefore(plan.anchorStart)
            ? null
            : cycle.endDayKey;
    final nowMs = max(
      DateTime.now().millisecondsSinceEpoch,
      plan.updatedMs + 1,
    );
    await _db!.transaction((txn) async {
      await txn.update(
        'budget_plans',
        {
          'status': BudgetPlanStatusV2.archived.storageKey,
          'end_day': archiveEnd,
          'updated_ms': nowMs,
        },
        where: 'id = ?',
        whereArgs: [planId],
      );
      await txn.insert('budget_change_events', {
        'uuid': _newUuid(),
        'plan_id': planId,
        'event_type': 'plan_archived',
        'before_json': jsonEncode({'status': plan.status.storageKey}),
        'after_json': jsonEncode({
          'status': BudgetPlanStatusV2.archived.storageKey,
          'end_day': archiveEnd,
        }),
        'created_ms': nowMs,
      });
    });
    await _loadBudgetV2();
    notifyListeners();
  }

  int _familyNetAt(
    ConsumptionExpenseFamily family,
    DateTime knowledgeCutoff,
  ) {
    if (family.createdAt.isAfter(knowledgeCutoff)) return 0;
    final refunds = family.refunds
        .where((refund) => !refund.createdAt.isAfter(knowledgeCutoff))
        .fold<int>(0, (sum, refund) => sum + refund.amountMinor);
    return max(0, family.originalAmountMinor - refunds);
  }

  List<FixedCommitmentEvaluation> budgetFixedEvaluationsForCycle(
    int planId,
    DateTime cycleStart, {
    DateTime? asOf,
    DateTime? knowledgeCutoff,
  }) {
    final plan = _budgetPlansV2.where((item) => item.id == planId).firstOrNull;
    if (plan == null) return const [];
    final queryAsOf = asOf ?? DateTime.now();
    final cutoff = knowledgeCutoff ?? DateTime.now();
    final families = _budgetExpenseFamiliesForBook(plan.bookId);
    final familyById = {for (final family in families) family.id: family};
    final entities = budgetFixedOccurrencesV2For(
      planId,
      cycleStart: cycleStart,
    );
    final coreOccurrences = entities.map((item) => item.occurrence).toList();
    return [
      for (final entity in entities)
        (() {
          final occurrence = entity.occurrence;
          final familyId = occurrence.matchedTransactionFamilyId;
          final family = familyId == null ? null : familyById[familyId];
          var exclusive = false;
          var familyNet = 0;
          var attributionOccurred = false;
          var refundReview = occurrence.reviewReason ==
              FixedCommitmentReviewReason.refundAfterMatch;
          if (family != null) {
            final candidate = FixedCommitmentFamilyCandidate(
              familyId: family.id,
              bookId: plan.bookId,
              currencyCode: family.currencyCode,
              attributionDate: family.attributionDate,
            );
            exclusive = FixedCommitmentLinkValidator.validateLink(
              occurrence: occurrence,
              candidate: candidate,
              existingOccurrences: coreOccurrences,
            ).isValid;
            familyNet = _familyNetAt(family, cutoff);
            attributionOccurred = !family.attributionDate.isAfter(queryAsOf);
            final resolvedMs = occurrence.resolvedMs ?? 0;
            if (family.refunds.any((refund) =>
                refund.createdAt.millisecondsSinceEpoch > resolvedMs &&
                !refund.createdAt.isAfter(cutoff))) {
              refundReview = true;
            }
          }
          return FixedCommitmentCalculator.evaluate(
            occurrence: occurrence,
            asOf: queryAsOf,
            exclusiveLinked: exclusive,
            familyNetCents: familyNet,
            attributionOccurred: attributionOccurred,
            refundAfterMatchReview: refundReview,
          );
        })(),
    ];
  }

  List<TransactionEntity> budgetFixedMatchCandidates(
    BudgetFixedOccurrenceEntity entity,
  ) {
    final plan =
        _budgetPlansV2.where((item) => item.id == entity.planId).firstOrNull;
    if (plan == null) return const [];
    final allowedBooks = _bookIdsForView(plan.bookId).toSet();
    final linkedFamilies = {
      for (final item in _budgetFixedOccurrencesV2)
        if (item.planId == plan.id &&
            item.id != entity.id &&
            item.matchedTransactionFamilyId != null)
          item.matchedTransactionFamilyId!,
    };
    final candidates = _globalVisibleTransactions.where((transaction) {
      if (transaction.txKind != TransactionKind.expense ||
          transaction.amount <= Decimal.zero ||
          transaction.bookId == null ||
          !allowedBooks.contains(transaction.bookId) ||
          transaction.currencyCode != plan.currencyCode) {
        return false;
      }
      final day = DateTime(
        transaction.date.year,
        transaction.date.month,
        transaction.date.day,
      );
      if (day.isBefore(entity.occurrence.cycleStart) ||
          day.isAfter(entity.occurrence.cycleEnd)) {
        return false;
      }
      final familyId = transaction.uuid.isEmpty
          ? transaction.id.toString()
          : transaction.uuid;
      return !linkedFamilies.contains(familyId);
    }).toList()
      ..sort((left, right) => right.dateMs.compareTo(left.dateMs));
    return List.unmodifiable(candidates);
  }

  Future<void> matchBudgetFixedOccurrence(
    int occurrenceId,
    String familyId,
  ) async {
    final entity = _budgetFixedOccurrencesV2
        .where((item) => item.id == occurrenceId)
        .firstOrNull;
    if (entity == null) throw StateError('固定支出周期记录不存在');
    final plan =
        _budgetPlansV2.where((item) => item.id == entity.planId).firstOrNull;
    if (plan == null) throw StateError('预算计划不存在');
    final family = _budgetExpenseFamiliesForBook(plan.bookId)
        .where((item) => item.id == familyId)
        .firstOrNull;
    if (family == null) throw StateError('匹配账单不存在');
    final validation = FixedCommitmentLinkValidator.validateLink(
      occurrence: entity.occurrence,
      candidate: FixedCommitmentFamilyCandidate(
        familyId: family.id,
        bookId: plan.bookId,
        currencyCode: family.currencyCode,
        attributionDate: family.attributionDate,
      ),
      existingOccurrences:
          _budgetFixedOccurrencesV2.map((item) => item.occurrence),
    );
    if (!validation.isValid) {
      throw StateError('这笔账不在固定支出的账本、币种或周期范围内，或已匹配其他承诺。');
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _db!.transaction((txn) async {
      await txn.update(
        'budget_fixed_commitment_occurrences',
        {
          'resolution_status':
              FixedCommitmentResolutionStatus.matched.storageValue,
          'review_reason': '',
          'matched_transaction_family_uuid': familyId,
          'resolved_ms': nowMs,
          'updated_ms': nowMs,
        },
        where: 'id = ?',
        whereArgs: [occurrenceId],
      );
      await txn.insert('budget_change_events', {
        'uuid': _newUuid(),
        'plan_id': entity.planId,
        'event_type': 'occurrence_matched',
        'before_json': jsonEncode({
          'occurrence_id': occurrenceId,
          'family_id': entity.matchedTransactionFamilyId,
        }),
        'after_json': jsonEncode({
          'occurrence_id': occurrenceId,
          'family_id': familyId,
        }),
        'created_ms': nowMs,
      });
    });
    await _loadBudgetV2();
    notifyListeners();
  }

  Future<void> skipBudgetFixedOccurrence(int occurrenceId) =>
      _setBudgetFixedOccurrenceResolution(
        occurrenceId,
        status: FixedCommitmentResolutionStatus.skipped,
        eventType: 'occurrence_skipped',
      );

  Future<void> resetBudgetFixedOccurrence(int occurrenceId) =>
      _setBudgetFixedOccurrenceResolution(
        occurrenceId,
        status: FixedCommitmentResolutionStatus.planned,
        eventType: 'occurrence_reset',
      );

  Future<void> acceptBudgetFixedRefundReview(int occurrenceId) async {
    final entity = _budgetFixedOccurrencesV2
        .where((item) => item.id == occurrenceId)
        .firstOrNull;
    if (entity == null ||
        entity.occurrence.reviewReason !=
            FixedCommitmentReviewReason.refundAfterMatch ||
        entity.matchedTransactionFamilyId == null) {
      throw StateError('这条固定支出没有可确认的退款差额');
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _db!.update(
      'budget_fixed_commitment_occurrences',
      {
        'resolution_status':
            FixedCommitmentResolutionStatus.matched.storageValue,
        'review_reason': '',
        'resolved_ms': nowMs,
        'updated_ms': nowMs,
      },
      where: 'id = ?',
      whereArgs: [occurrenceId],
    );
    await _loadBudgetV2();
    notifyListeners();
  }

  Future<void> _setBudgetFixedOccurrenceResolution(
    int occurrenceId, {
    required FixedCommitmentResolutionStatus status,
    required String eventType,
  }) async {
    final entity = _budgetFixedOccurrencesV2
        .where((item) => item.id == occurrenceId)
        .firstOrNull;
    if (entity == null) throw StateError('固定支出周期记录不存在');
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _db!.transaction((txn) async {
      await txn.update(
        'budget_fixed_commitment_occurrences',
        {
          'resolution_status': status.storageValue,
          'review_reason': '',
          'matched_transaction_family_uuid': null,
          'resolved_ms':
              status == FixedCommitmentResolutionStatus.skipped ? nowMs : null,
          'updated_ms': nowMs,
        },
        where: 'id = ?',
        whereArgs: [occurrenceId],
      );
      await txn.insert('budget_change_events', {
        'uuid': _newUuid(),
        'plan_id': entity.planId,
        'event_type': eventType,
        'before_json': jsonEncode({
          'status': entity.resolutionStatus.storageValue,
          'family_id': entity.matchedTransactionFamilyId,
        }),
        'after_json': jsonEncode({'status': status.storageValue}),
        'created_ms': nowMs,
      });
    });
    await _loadBudgetV2();
    notifyListeners();
  }

  Future<void> _markBudgetOccurrenceRefundReview(
    TransactionEntity root,
  ) async {
    final familyId = root.uuid.isEmpty ? root.id.toString() : root.uuid;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _db!.update(
      'budget_fixed_commitment_occurrences',
      {
        'resolution_status':
            FixedCommitmentResolutionStatus.requiresReview.storageValue,
        'review_reason':
            FixedCommitmentReviewReason.refundAfterMatch.storageValue,
        'updated_ms': nowMs,
      },
      where: 'matched_transaction_family_uuid = ? AND resolution_status = ?',
      whereArgs: [
        familyId,
        FixedCommitmentResolutionStatus.matched.storageValue,
      ],
    );
    await _loadBudgetV2();
  }

  Future<void> _refreshBudgetOccurrenceRefundReview(int rootId) async {
    final root = _allTransactions
        .where((transaction) => transaction.id == rootId)
        .firstOrNull;
    if (root == null) return;
    final familyId = root.uuid.isEmpty ? root.id.toString() : root.uuid;
    final refunds = _allTransactions
        .where((transaction) => transaction.refundOf == rootId)
        .toList();
    final occurrences = _budgetFixedOccurrencesV2.where((item) =>
        item.matchedTransactionFamilyId == familyId &&
        (item.resolutionStatus == FixedCommitmentResolutionStatus.matched ||
            item.occurrence.reviewReason ==
                FixedCommitmentReviewReason.refundAfterMatch));
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _db!.transaction((txn) async {
      for (final occurrence in occurrences) {
        final resolvedMs = occurrence.resolvedMs ?? 0;
        final hasUnreviewedRefund = refunds.any(
          (refund) => refund.createdMs > resolvedMs,
        );
        await txn.update(
          'budget_fixed_commitment_occurrences',
          {
            'resolution_status': (hasUnreviewedRefund
                    ? FixedCommitmentResolutionStatus.requiresReview
                    : FixedCommitmentResolutionStatus.matched)
                .storageValue,
            'review_reason': hasUnreviewedRefund
                ? FixedCommitmentReviewReason.refundAfterMatch.storageValue
                : '',
            'updated_ms': nowMs,
          },
          where: 'id = ?',
          whereArgs: [occurrence.id],
        );
      }
    });
    await _loadBudgetV2();
  }

  /// 新建一条预算期间，返回 id。
  Future<int> addBudgetPeriod({
    int? bookId,
    required DateTime start,
    DateTime? end,
    bool recurringMonthly = true,
    required Decimal total,
    Map<String, Decimal> categoryBudgets = const {},
    Decimal? monthlyIncome,
    List<(String, Decimal)> fixedExpenses = const [],
  }) async {
    final p = BudgetPeriod(
      id: 0,
      bookId: bookId,
      start: DateTime(start.year, start.month, start.day),
      end: end == null ? null : DateTime(end.year, end.month, end.day),
      recurringMonthly: recurringMonthly,
      total: total,
      categoryBudgets: categoryBudgets,
      monthlyIncome: monthlyIncome,
      fixedExpenses: fixedExpenses,
    );
    final id = await _db!.insert('budget_periods', {
      'book_id': bookId,
      'start_ms': p.start.millisecondsSinceEpoch,
      'end_ms': p.end?.millisecondsSinceEpoch,
      'recurring_monthly': recurringMonthly ? 1 : 0,
      'total': total.toString(),
      'category_budgets':
          categoryBudgets.isEmpty ? '' : p.categoryBudgetsJson(),
      'monthly_income': monthlyIncome?.toString() ?? '',
      'fixed_expenses': fixedExpenses.isEmpty ? '' : p.fixedExpensesJson(),
      'created_ms': DateTime.now().millisecondsSinceEpoch,
    });
    await _loadBudgetPeriods();
    notifyListeners();
    return id;
  }

  /// 编辑既有预算计划（整条覆盖式更新，id 不变）。
  Future<void> updateBudgetPeriod(
    int id, {
    int? bookId,
    required DateTime start,
    DateTime? end,
    bool recurringMonthly = true,
    required Decimal total,
    Map<String, Decimal> categoryBudgets = const {},
    Decimal? monthlyIncome,
    List<(String, Decimal)> fixedExpenses = const [],
  }) async {
    final p = BudgetPeriod(
      id: id,
      bookId: bookId,
      start: DateTime(start.year, start.month, start.day),
      end: end == null ? null : DateTime(end.year, end.month, end.day),
      recurringMonthly: recurringMonthly,
      total: total,
      categoryBudgets: categoryBudgets,
      monthlyIncome: monthlyIncome,
      fixedExpenses: fixedExpenses,
    );
    await _db!.update(
      'budget_periods',
      {
        'book_id': bookId,
        'start_ms': p.start.millisecondsSinceEpoch,
        'end_ms': p.end?.millisecondsSinceEpoch,
        'recurring_monthly': recurringMonthly ? 1 : 0,
        'total': total.toString(),
        'category_budgets':
            categoryBudgets.isEmpty ? '' : p.categoryBudgetsJson(),
        'monthly_income': monthlyIncome?.toString() ?? '',
        'fixed_expenses': fixedExpenses.isEmpty ? '' : p.fixedExpensesJson(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _loadBudgetPeriods();
    notifyListeners();
  }

  Future<void> deleteBudgetPeriod(int id) async {
    await _db!.delete('budget_periods', where: 'id = ?', whereArgs: [id]);
    await _loadBudgetPeriods();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // AI 设置
  // ---------------------------------------------------------------------------

  Future<void> saveApiKey(String key) async {
    final provider = aiProviderById('deepseek');
    if (provider != null) {
      await saveAiConfiguredProvider(provider.copyWith(apiKey: key));
      return;
    }
    await saveAiProviderConfig(type: AiProviderType.deepseek, apiKey: key);
  }

  String _providerSecretKey(String providerId) =>
      'ai_provider_api_key_${providerId.trim()}';

  /// Persist the provider catalog and the two task selections in one place.
  /// API keys are deliberately kept outside this JSON payload.
  Future<void> _persistAiProviderMetadata({
    bool notify = true,
    bool resetPrivacyConsent = false,
  }) async {
    final batch = _db!.batch();
    void setting(String key, String value) => batch.insert(
          'app_settings',
          {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

    setting(
      'ai_providers_json',
      jsonEncode(_aiProviders.map((provider) => provider.toJson()).toList()),
    );
    setting('ai_record_provider_id', _recordAiProviderId ?? '');
    setting('chat_current_provider_id', _chatCurrentProviderId ?? '');
    setting('chat_current_model', _chatCurrentModel ?? '');
    setting('ai_provider_type', _aiProviderType.storageKey);
    setting('custom_ai_display_name', _customAiDisplayName);
    setting('custom_ai_base_url', _customAiBaseUrl);
    setting('custom_ai_model', _customAiModel);
    setting('report_ai_model', _reportAiModel);
    setting('ai_record_provider_type', _recordAiProviderType.storageKey);
    setting('ai_chat_provider_type', _chatAiProviderType.storageKey);
    setting('ai_report_provider_type', _reportAiProviderType.storageKey);
    setting('ai_record_route_mode', _recordAiRouteMode.storageKey);
    setting('ai_chat_route_mode', _chatAiRouteMode.storageKey);
    setting('ai_report_route_mode', _reportAiRouteMode.storageKey);
    setting('ai_record_endpoint_type', _recordAiEndpointType.storageKey);
    setting('ai_chat_endpoint_type', _chatAiEndpointType.storageKey);
    setting('ai_report_endpoint_type', _reportAiEndpointType.storageKey);
    setting('ai_record_reasoning_effort', _recordAiReasoningEffort.storageKey);
    setting('ai_chat_reasoning_effort', _chatAiReasoningEffort.storageKey);
    setting('ai_report_reasoning_effort', _reportAiReasoningEffort.storageKey);
    setting('ai_task_config_version', '3');
    if (resetPrivacyConsent) {
      _aiPrivacyAccepted = false;
      setting('ai_privacy_accepted', '0');
    }
    await batch.commit(noResult: true);
    if (notify) notifyListeners();
  }

  /// Add or edit one configured provider. The DeepSeek entry is always kept as
  /// the built-in provider and cannot be renamed into a custom entry.
  Future<void> saveAiConfiguredProvider(AiConfiguredProvider provider) async {
    var id = provider.id.trim();
    if (provider.type == AiProviderType.deepseek) id = 'deepseek';
    if (id.isEmpty) id = _newUuid();

    final existing = aiProviderById(id);
    if (existing?.builtIn == true && provider.type != AiProviderType.deepseek) {
      throw StateError('内置服务商不能改为自定义服务商');
    }

    final isDeepSeek =
        id == 'deepseek' || provider.type == AiProviderType.deepseek;
    final type = isDeepSeek ? AiProviderType.deepseek : AiProviderType.custom;
    final displayName = isDeepSeek
        ? AiProviderType.deepseek.label
        : (provider.displayName.trim().isEmpty
            ? AiProviderType.custom.label
            : provider.displayName.trim());
    final baseUrl = isDeepSeek
        ? AiProviderConfig.deepSeekBaseUrl
        : (provider.baseUrl.trim().isEmpty
            ? AiProviderConfig.customDefaultBaseUrl
            : provider.baseUrl.trim());
    final model = provider.model.trim().isEmpty
        ? (isDeepSeek
            ? AiProviderConfig.deepSeekModel
            : AiProviderConfig.customDefaultModel)
        : provider.model.trim();
    final models = <String>{
      model,
      ...provider.models
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty),
    }.toList();
    final storedKey = await _saveSecret(
      secureKey: _providerSecretKey(id),
      legacySettingKey: _providerSecretKey(id),
      configuredSettingKey: '${_providerSecretKey(id)}_configured',
      value: provider.apiKey,
    );

    if (isDeepSeek) {
      _deepSeekApiKey = await _saveSecret(
        secureKey: 'deepseek_api_key',
        legacySettingKey: 'deepseek_api_key',
        configuredSettingKey: 'deepseek_api_key_configured',
        value: provider.apiKey,
      );
      _aiProviderType = AiProviderType.deepseek;
    } else if (id == 'legacy-custom') {
      _customAiApiKey = storedKey;
      _customAiDisplayName = displayName;
      _customAiBaseUrl = baseUrl;
      _customAiModel = model;
      _aiProviderType = AiProviderType.custom;
    }

    final updated = AiConfiguredProvider(
      id: id,
      type: type,
      displayName: displayName,
      baseUrl: baseUrl,
      apiKey: storedKey ?? '',
      model: model,
      models: models,
      endpointType:
          isDeepSeek ? AiEndpointType.chatCompletions : provider.endpointType,
      reasoningEffort: provider.reasoningEffort,
      builtIn: isDeepSeek,
    );
    final index = _aiProviders.indexWhere((item) => item.id == id);
    if (index == -1) {
      _aiProviders.add(updated);
    } else {
      _aiProviders[index] = updated;
    }

    _recordAiProviderId ??= id;
    _chatCurrentProviderId ??= id;
    if (aiProviderById(_recordAiProviderId) == null) _recordAiProviderId = id;
    if (aiProviderById(_chatCurrentProviderId) == null) {
      _chatCurrentProviderId = id;
    }
    final selected = aiProviderById(_chatCurrentProviderId);
    if (selected != null &&
        (_chatCurrentModel == null ||
            !selected.models.contains(_chatCurrentModel))) {
      _chatCurrentModel = selected.model;
    }
    _recordAiProviderType = aiProviderById(_recordAiProviderId)?.type ?? type;
    _chatAiProviderType = aiProviderById(_chatCurrentProviderId)?.type ?? type;
    _reportAiProviderType = _chatAiProviderType;
    await _persistAiProviderMetadata(
      notify: false,
      resetPrivacyConsent: true,
    );
    notifyListeners();
  }

  Future<AiConfiguredProvider> addAiConfiguredProvider({
    String displayName = '自定义服务商',
    String baseUrl = AiProviderConfig.customDefaultBaseUrl,
    String apiKey = '',
    String model = AiProviderConfig.customDefaultModel,
    Iterable<String> models = const [],
    AiEndpointType endpointType = AiEndpointType.auto,
    AiReasoningEffort reasoningEffort = AiReasoningEffort.none,
  }) async {
    final provider = AiConfiguredProvider(
      id: _newUuid(),
      type: AiProviderType.custom,
      displayName: displayName,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      models: models,
      endpointType: endpointType,
      reasoningEffort: reasoningEffort,
    );
    await saveAiConfiguredProvider(provider);
    return aiProviderById(provider.id) ?? provider;
  }

  Future<void> deleteAiConfiguredProvider(String providerId) async {
    final id = providerId.trim();
    final provider = aiProviderById(id);
    if (provider == null) return;
    if (provider.builtIn || id == 'deepseek') {
      throw StateError('内置 DeepSeek 不能删除');
    }
    _aiProviders.removeWhere((item) => item.id == id);
    await SecureKeyStore.delete(_providerSecretKey(id));
    await _db!.delete(
      'app_settings',
      where: 'key IN (?, ?)',
      whereArgs: [
        _providerSecretKey(id),
        '${_providerSecretKey(id)}_configured',
      ],
    );
    if (id == 'legacy-custom') {
      await _saveSecret(
        secureKey: 'custom_ai_api_key',
        legacySettingKey: 'custom_ai_api_key',
        configuredSettingKey: 'custom_ai_api_key_configured',
        value: '',
      );
      _customAiApiKey = null;
    }
    final changedActiveProvider =
        _recordAiProviderId == id || _chatCurrentProviderId == id;
    final fallback = _firstUsableProvider();
    if (_recordAiProviderId == id) _recordAiProviderId = fallback?.id;
    if (_chatCurrentProviderId == id) {
      _chatCurrentProviderId = fallback?.id;
      _chatCurrentModel = fallback?.model;
    }
    _recordAiProviderType =
        aiProviderById(_recordAiProviderId)?.type ?? AiProviderType.deepseek;
    _chatAiProviderType =
        aiProviderById(_chatCurrentProviderId)?.type ?? AiProviderType.deepseek;
    _reportAiProviderType = _chatAiProviderType;
    await _persistAiProviderMetadata(
      notify: false,
      resetPrivacyConsent: changedActiveProvider,
    );
    notifyListeners();
  }

  Future<void> saveAiProviderModels(
    String providerId,
    List<String> models, {
    String? selectedModel,
  }) async {
    final provider = aiProviderById(providerId);
    if (provider == null) throw StateError('服务商不存在');
    final normalized = <String>[];
    final seen = <String>{};
    for (final raw in models) {
      final model = raw.trim();
      if (model.isNotEmpty && seen.add(model)) normalized.add(model);
    }
    final chosen = selectedModel?.trim();
    final primary = chosen != null && chosen.isNotEmpty && seen.contains(chosen)
        ? chosen
        : (normalized.firstOrNull ?? provider.model);
    final updated = provider.copyWith(model: primary, models: normalized);
    _aiProviders[_aiProviders.indexWhere((item) => item.id == provider.id)] =
        updated;
    _availableModels = List<String>.from(updated.models);
    if (_chatCurrentProviderId == provider.id &&
        !_chatCurrentModelIn(updated)) {
      _chatCurrentModel = updated.model;
    }
    await _persistAiProviderMetadata(notify: false);
    await _db!.insert(
      'app_settings',
      {'key': 'available_ai_models', 'value': _availableModels.join(',')},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  bool _chatCurrentModelIn(AiConfiguredProvider provider) =>
      _chatCurrentModel != null && provider.models.contains(_chatCurrentModel);

  Future<void> setRecordAiProvider(String providerId) async {
    final provider = aiProviderById(providerId.trim());
    if (provider == null) throw StateError('服务商不存在');
    if (!provider.hasKey) throw StateError('请先配置该服务商的 API Key');
    final providerChanged = _recordAiProviderId != provider.id;
    _recordAiProviderId = provider.id;
    _recordAiProviderType = provider.type;
    _recordAiRouteMode = AiRouteMode.fixed;
    await _persistAiProviderMetadata(
      notify: false,
      resetPrivacyConsent: providerChanged,
    );
    notifyListeners();
  }

  Future<void> saveChatModelSelection({
    required String providerId,
    required String model,
    AiReasoningEffort? reasoningEffort,
  }) async {
    final provider = aiProviderById(providerId.trim());
    if (provider == null) throw StateError('服务商不存在');
    if (!provider.hasKey) throw StateError('请先配置该服务商的 API Key');
    final selectedModel = model.trim();
    if (selectedModel.isEmpty ||
        (provider.models.isNotEmpty &&
            !provider.models.contains(selectedModel))) {
      throw StateError('模型不在该服务商的已保存列表中');
    }
    final providerChanged = _chatCurrentProviderId != provider.id;
    _chatCurrentProviderId = provider.id;
    _chatCurrentModel = selectedModel;
    _chatAiProviderType = provider.type;
    _reportAiProviderType = provider.type;
    _chatAiRouteMode = AiRouteMode.fixed;
    _reportAiRouteMode = AiRouteMode.fixed;
    if (reasoningEffort != null) {
      _chatAiReasoningEffort = reasoningEffort;
      _reportAiReasoningEffort = reasoningEffort;
    }
    await _persistAiProviderMetadata(
      notify: false,
      resetPrivacyConsent: providerChanged,
    );
    notifyListeners();
  }

  Future<void> saveAiProviderConfig({
    required AiProviderType type,
    required String apiKey,
    String? customDisplayName,
    String? customBaseUrl,
    String? customModel,
    String? reportModel,
    AiProviderType? recordProviderType,
    AiProviderType? chatProviderType,
    AiProviderType? reportProviderType,
    AiRouteMode? recordRouteMode,
    AiRouteMode? chatRouteMode,
    AiRouteMode? reportRouteMode,
    AiEndpointType? recordEndpointType,
    AiEndpointType? chatEndpointType,
    AiEndpointType? reportEndpointType,
    AiReasoningEffort? recordReasoningEffort,
    AiReasoningEffort? chatReasoningEffort,
    AiReasoningEffort? reportReasoningEffort,
  }) async {
    final oldRouteSignature = [
      _aiProviderType.storageKey,
      _customAiDisplayName,
      _customAiBaseUrl,
      _recordAiProviderType.storageKey,
      _chatAiProviderType.storageKey,
      _reportAiProviderType.storageKey,
      _recordAiRouteMode.storageKey,
      _chatAiRouteMode.storageKey,
      _reportAiRouteMode.storageKey,
      _recordAiEndpointType.storageKey,
      _chatAiEndpointType.storageKey,
      _reportAiEndpointType.storageKey,
    ].join('|');

    _aiProviderType = type;
    _customAiDisplayName =
        (customDisplayName ?? _customAiDisplayName).trim().isEmpty
            ? '自定义'
            : (customDisplayName ?? _customAiDisplayName).trim();
    _customAiBaseUrl = (customBaseUrl ?? _customAiBaseUrl).trim().isEmpty
        ? AiProviderConfig.customDefaultBaseUrl
        : (customBaseUrl ?? _customAiBaseUrl).trim();
    _customAiModel = (customModel ?? _customAiModel).trim().isEmpty
        ? AiProviderConfig.customDefaultModel
        : (customModel ?? _customAiModel).trim();
    _reportAiModel = (reportModel ?? _reportAiModel).trim().isEmpty
        ? AiProviderConfig.customReportDefaultModel
        : (reportModel ?? _reportAiModel).trim();
    _recordAiProviderType = recordProviderType ?? _recordAiProviderType;
    _chatAiProviderType = chatProviderType ?? _chatAiProviderType;
    _reportAiProviderType = reportProviderType ?? _reportAiProviderType;
    _recordAiRouteMode = recordRouteMode ?? _recordAiRouteMode;
    _chatAiRouteMode = chatRouteMode ?? _chatAiRouteMode;
    _reportAiRouteMode = reportRouteMode ?? _reportAiRouteMode;
    _recordAiEndpointType = recordEndpointType ?? _recordAiEndpointType;
    _chatAiEndpointType = chatEndpointType ?? _chatAiEndpointType;
    _reportAiEndpointType = reportEndpointType ?? _reportAiEndpointType;
    _recordAiReasoningEffort =
        recordReasoningEffort ?? _recordAiReasoningEffort;
    _chatAiReasoningEffort = chatReasoningEffort ?? _chatAiReasoningEffort;
    _reportAiReasoningEffort =
        reportReasoningEffort ?? _reportAiReasoningEffort;

    if (type == AiProviderType.custom) {
      _customAiApiKey = await _saveSecret(
        secureKey: 'custom_ai_api_key',
        legacySettingKey: 'custom_ai_api_key',
        configuredSettingKey: 'custom_ai_api_key_configured',
        value: apiKey,
      );
    } else {
      _deepSeekApiKey = await _saveSecret(
        secureKey: 'deepseek_api_key',
        legacySettingKey: 'deepseek_api_key',
        configuredSettingKey: 'deepseek_api_key_configured',
        value: apiKey,
      );
    }

    final batch = _db!.batch();
    void setting(String key, String value) => batch.insert(
          'app_settings',
          {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

    setting('ai_provider_type', _aiProviderType.storageKey);
    setting('custom_ai_display_name', _customAiDisplayName);
    setting('custom_ai_base_url', _customAiBaseUrl);
    setting('custom_ai_model', _customAiModel);
    setting('report_ai_model', _reportAiModel);
    setting('ai_record_provider_type', _recordAiProviderType.storageKey);
    setting('ai_chat_provider_type', _chatAiProviderType.storageKey);
    setting('ai_report_provider_type', _reportAiProviderType.storageKey);
    setting('ai_record_route_mode', _recordAiRouteMode.storageKey);
    setting('ai_chat_route_mode', _chatAiRouteMode.storageKey);
    setting('ai_report_route_mode', _reportAiRouteMode.storageKey);
    setting('ai_record_endpoint_type', _recordAiEndpointType.storageKey);
    setting('ai_chat_endpoint_type', _chatAiEndpointType.storageKey);
    setting('ai_report_endpoint_type', _reportAiEndpointType.storageKey);
    setting('ai_record_reasoning_effort', _recordAiReasoningEffort.storageKey);
    setting('ai_chat_reasoning_effort', _chatAiReasoningEffort.storageKey);
    setting('ai_report_reasoning_effort', _reportAiReasoningEffort.storageKey);
    setting('ai_task_config_version', '2');

    final newRouteSignature = [
      _aiProviderType.storageKey,
      _customAiDisplayName,
      _customAiBaseUrl,
      _recordAiProviderType.storageKey,
      _chatAiProviderType.storageKey,
      _reportAiProviderType.storageKey,
      _recordAiRouteMode.storageKey,
      _chatAiRouteMode.storageKey,
      _reportAiRouteMode.storageKey,
      _recordAiEndpointType.storageKey,
      _chatAiEndpointType.storageKey,
      _reportAiEndpointType.storageKey,
    ].join('|');
    if (oldRouteSignature != newRouteSignature) {
      _aiPrivacyAccepted = false;
      setting('ai_privacy_accepted', '0');
    }
    await batch.commit(noResult: true);
    notifyListeners();
  }

  Future<void> saveAiTaskRouting({
    required AiRouteMode recordRouteMode,
    required AiRouteMode chatRouteMode,
    required AiRouteMode reportRouteMode,
    required AiProviderType recordProviderType,
    required AiProviderType chatProviderType,
    required AiProviderType reportProviderType,
  }) async {
    final oldRouteSignature = [
      _recordAiProviderType.storageKey,
      _chatAiProviderType.storageKey,
      _reportAiProviderType.storageKey,
      _recordAiRouteMode.storageKey,
      _chatAiRouteMode.storageKey,
      _reportAiRouteMode.storageKey,
    ].join('|');

    _recordAiRouteMode = recordRouteMode;
    _chatAiRouteMode = chatRouteMode;
    _reportAiRouteMode = reportRouteMode;
    _recordAiProviderType = recordProviderType;
    _chatAiProviderType = chatProviderType;
    _reportAiProviderType = reportProviderType;

    final batch = _db!.batch();
    void setting(String key, String value) => batch.insert(
          'app_settings',
          {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
    setting('ai_record_route_mode', _recordAiRouteMode.storageKey);
    setting('ai_chat_route_mode', _chatAiRouteMode.storageKey);
    setting('ai_report_route_mode', _reportAiRouteMode.storageKey);
    setting('ai_record_provider_type', _recordAiProviderType.storageKey);
    setting('ai_chat_provider_type', _chatAiProviderType.storageKey);
    setting('ai_report_provider_type', _reportAiProviderType.storageKey);
    setting('ai_task_config_version', '2');

    final newRouteSignature = [
      _recordAiProviderType.storageKey,
      _chatAiProviderType.storageKey,
      _reportAiProviderType.storageKey,
      _recordAiRouteMode.storageKey,
      _chatAiRouteMode.storageKey,
      _reportAiRouteMode.storageKey,
    ].join('|');
    if (oldRouteSignature != newRouteSignature) {
      _aiPrivacyAccepted = false;
      setting('ai_privacy_accepted', '0');
    }
    await batch.commit(noResult: true);
    notifyListeners();
  }

  Future<void> saveAiAdvancedConfig({
    String? customModel,
    String? reportModel,
    AiEndpointType? chatEndpointType,
    AiEndpointType? reportEndpointType,
    AiReasoningEffort? chatReasoningEffort,
    AiReasoningEffort? reportReasoningEffort,
  }) async {
    _customAiModel = (customModel ?? _customAiModel).trim().isEmpty
        ? AiProviderConfig.customDefaultModel
        : (customModel ?? _customAiModel).trim();
    _reportAiModel = (reportModel ?? _reportAiModel).trim().isEmpty
        ? AiProviderConfig.customReportDefaultModel
        : (reportModel ?? _reportAiModel).trim();
    _chatAiEndpointType = chatEndpointType ?? _chatAiEndpointType;
    _reportAiEndpointType = reportEndpointType ?? _reportAiEndpointType;
    _chatAiReasoningEffort = chatReasoningEffort ?? _chatAiReasoningEffort;
    _reportAiReasoningEffort =
        reportReasoningEffort ?? _reportAiReasoningEffort;

    final batch = _db!.batch();
    void setting(String key, String value) => batch.insert(
          'app_settings',
          {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
    setting('custom_ai_model', _customAiModel);
    setting('report_ai_model', _reportAiModel);
    setting('available_ai_models', _availableModels.join(','));
    setting('ai_chat_endpoint_type', _chatAiEndpointType.storageKey);
    setting('ai_report_endpoint_type', _reportAiEndpointType.storageKey);
    setting('ai_chat_reasoning_effort', _chatAiReasoningEffort.storageKey);
    setting('ai_report_reasoning_effort', _reportAiReasoningEffort.storageKey);
    setting('ai_task_config_version', '2');
    await batch.commit(noResult: true);
    notifyListeners();
  }

  /// 保存用户筛选后的可用模型列表
  Future<void> saveAvailableModels(List<String> models) async {
    _availableModels = List<String>.from(models);
    await _db!.insert(
      'app_settings',
      {'key': 'available_ai_models', 'value': _availableModels.join(',')},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  Future<String?> _saveSecret({
    required String secureKey,
    required String legacySettingKey,
    required String configuredSettingKey,
    required String value,
  }) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await SecureKeyStore.delete(secureKey);
      await _db!.delete(
        'app_settings',
        where: 'key IN (?, ?)',
        whereArgs: [legacySettingKey, configuredSettingKey],
      );
      return null;
    } else {
      final stored = await SecureKeyStore.write(secureKey, trimmed);
      if (stored) {
        await _db!.delete(
          'app_settings',
          where: 'key = ?',
          whereArgs: [legacySettingKey],
        );
        await _db!.insert(
          'app_settings',
          {'key': configuredSettingKey, 'value': '1'},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } else {
        // Desktop tests and unsupported platforms do not provide the native
        // secure channel. Keep the app usable there, but Android release builds
        // use Keystore through MainActivity.
        await _db!.insert(
          'app_settings',
          {'key': legacySettingKey, 'value': trimmed},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      return trimmed;
    }
  }

  // ---------------------------------------------------------------------------
  // 账本（多账本）
  // ---------------------------------------------------------------------------

  Future<void> switchBook(int bookId) async {
    if (bookId == _currentBookId) return;
    if (!_books.any((b) => b.id == bookId)) return;
    _currentBookId = bookId;
    await _db!.insert(
      'app_settings',
      {'key': 'current_book_id', 'value': bookId.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _applyCurrentBookTransactionView();
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<int> addBook({
    required String name,
    String icon = '📒',
    String cover = '',
    String remark = '',
    bool includeInTotal = true,
  }) async {
    final id = await _db!.insert('books', {
      ..._syncStampNew(),
      'name': name,
      'icon': icon,
      'cover': cover,
      'remark': remark,
      'sort_order': _books.length,
      'created_ms': DateTime.now().millisecondsSinceEpoch,
      'starred': 0,
      'include_in_total': includeInTotal ? 1 : 0,
    });
    await _loadBooks();
    notifyListeners();
    return id;
  }

  Future<void> renameBook(int id, {required String name, String? icon}) async {
    final updates = <String, Object?>{
      'name': name,
      'updated_ms': DateTime.now().millisecondsSinceEpoch,
    };
    if (icon != null) updates['icon'] = icon;
    await _db!.update('books', updates, where: 'id = ?', whereArgs: [id]);
    await _loadBooks();
    notifyListeners();
  }

  /// 编辑账本（名称/图标/封面/是否计入总账本）。计入开关变了会刷新聚合视图。
  Future<void> updateBook(
    int id, {
    String? name,
    String? icon,
    String? cover,
    String? remark,
    bool? includeInTotal,
  }) async {
    final updates = <String, Object?>{};
    if (name != null && name.isNotEmpty) updates['name'] = name;
    if (icon != null) updates['icon'] = icon;
    if (cover != null) updates['cover'] = cover;
    if (remark != null) updates['remark'] = remark;
    if (includeInTotal != null) {
      updates['include_in_total'] = includeInTotal ? 1 : 0;
    }
    if (updates.isEmpty) return;
    updates['updated_ms'] = DateTime.now().millisecondsSinceEpoch;
    await _db!.update('books', updates, where: 'id = ?', whereArgs: [id]);
    await _loadBooks();
    _applyCurrentBookTransactionView();
    notifyListeners();
  }

  /// 加星 / 取消加星（加星账本排前面）。
  Future<void> setBookStarred(int id, bool starred) async {
    await _db!.update('books', {'starred': starred ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
    await _loadBooks();
    notifyListeners();
  }

  /// 这个账本名下有多少笔账单（删除前的保护检查用）。
  Future<int> transactionCountForBook(int id) async =>
      Sqflite.firstIntValue(await _db!.rawQuery(
          'SELECT COUNT(*) FROM transactions WHERE book_id = ?', [id])) ??
      0;

  /// 删账本。[moveRecordsToDefault] = true 时先把账单转移到总账本再删，
  /// 记录不丢；false = 连账单一起删（UI 层要走更深的二次确认）。
  Future<void> deleteBook(int id, {bool moveRecordsToDefault = false}) async {
    if (_books.length <= 1) return;
    if (id == _defaultBookId) return; // 总账本不可删
    final receiptPaths = <String>[];
    await _db!.transaction((txn) async {
      if (moveRecordsToDefault) {
        final now = DateTime.now().millisecondsSinceEpoch;
        await txn.update(
          'transactions',
          {'book_id': _defaultBookId, 'updated_ms': now},
          where: 'book_id = ?',
          whereArgs: [id],
        );
        for (final table in [
          'recurring_rules',
          'budget_periods',
          'reports',
          'report_jobs',
          'physical_assets',
          'receivable_assets',
        ]) {
          await txn.update(
            table,
            {'book_id': _defaultBookId},
            where: 'book_id = ?',
            whereArgs: [id],
          );
        }
        await txn.update(
          'budget_plans',
          {'book_id': _defaultBookId, 'updated_ms': now},
          where: 'book_id = ?',
          whereArgs: [id],
        );
      } else {
        final txRows = await txn.query(
          'transactions',
          columns: ['image_path'],
          where: 'book_id = ?',
          whereArgs: [id],
        );
        receiptPaths.addAll(txRows
            .map((row) => row['image_path'] as String? ?? '')
            .where((path) => path.isNotEmpty));

        final ruleIds = (await txn.query(
          'recurring_rules',
          columns: ['id'],
          where: 'book_id = ?',
          whereArgs: [id],
        ))
            .map((row) => row['id'] as int)
            .toList();
        if (ruleIds.isNotEmpty) {
          await txn.delete(
            'recurring_occurrences',
            where: 'rule_id IN (${List.filled(ruleIds.length, '?').join(',')})',
            whereArgs: ruleIds,
          );
        }

        final physicalIds = (await txn.query(
          'physical_assets',
          columns: ['id'],
          where: 'book_id = ?',
          whereArgs: [id],
        ))
            .map((row) => row['id'] as int)
            .toList();
        if (physicalIds.isNotEmpty) {
          final marks = List.filled(physicalIds.length, '?').join(',');
          await txn.delete('asset_transaction_links',
              where: 'asset_id IN ($marks)', whereArgs: physicalIds);
          await txn.delete('asset_valuations',
              where: 'asset_id IN ($marks)', whereArgs: physicalIds);
          await txn.delete('asset_events',
              where: "asset_type = 'physical' AND asset_id IN ($marks)",
              whereArgs: physicalIds);
          await txn.delete('asset_usage_events',
              where: 'asset_id IN ($marks)', whereArgs: physicalIds);
        }

        final receivableIds = (await txn.query(
          'receivable_assets',
          columns: ['id'],
          where: 'book_id = ?',
          whereArgs: [id],
        ))
            .map((row) => row['id'] as int)
            .toList();
        if (receivableIds.isNotEmpty) {
          final marks = List.filled(receivableIds.length, '?').join(',');
          await txn.delete('receivable_recoveries',
              where: 'receivable_asset_id IN ($marks)',
              whereArgs: receivableIds);
          await txn.delete('asset_events',
              where: "asset_type = 'receivable' AND asset_id IN ($marks)",
              whereArgs: receivableIds);
        }

        final reportIds = (await txn.query(
          'reports',
          columns: ['id'],
          where: 'book_id = ?',
          whereArgs: [id],
        ))
            .map((row) => row['id'] as int)
            .toSet();
        if (reportIds.isNotEmpty) {
          final chatRows = await txn.query(
            'chat_messages',
            columns: ['id', 'text'],
            where: 'role = ?',
            whereArgs: ['report'],
          );
          final chatIds = <int>[];
          for (final row in chatRows) {
            try {
              final decoded = jsonDecode(row['text'] as String? ?? '');
              final reportId = decoded is Map
                  ? (decoded['reportId'] as num?)?.toInt()
                  : null;
              if (reportId != null && reportIds.contains(reportId)) {
                chatIds.add(row['id'] as int);
              }
            } catch (_) {}
          }
          if (chatIds.isNotEmpty) {
            await txn.delete(
              'chat_messages',
              where: 'id IN (${List.filled(chatIds.length, '?').join(',')})',
              whereArgs: chatIds,
            );
          }
        }

        final budgetPlanIds = (await txn.query(
          'budget_plans',
          columns: ['id'],
          where: 'book_id = ?',
          whereArgs: [id],
        ))
            .map((row) => row['id'] as int)
            .toList();
        if (budgetPlanIds.isNotEmpty) {
          final marks = List.filled(budgetPlanIds.length, '?').join(',');
          for (final table in [
            'budget_fixed_commitment_occurrences',
            'budget_cycle_overrides',
            'budget_plan_revisions',
            'budget_change_events',
          ]) {
            await txn.delete(
              table,
              where: 'plan_id IN ($marks)',
              whereArgs: budgetPlanIds,
            );
          }
          await txn.delete(
            'budget_plans',
            where: 'id IN ($marks)',
            whereArgs: budgetPlanIds,
          );
        }

        for (final table in [
          'transactions',
          'recurring_rules',
          'budget_periods',
          'reports',
          'report_jobs',
          'physical_assets',
          'receivable_assets',
        ]) {
          await txn.delete(table, where: 'book_id = ?', whereArgs: [id]);
        }
      }
      await txn.delete('books', where: 'id = ?', whereArgs: [id]);
      if (_currentBookId == id) {
        _currentBookId = _defaultBookId;
        await txn.insert(
          'app_settings',
          {'key': 'current_book_id', 'value': _currentBookId.toString()},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    for (final path in receiptPaths) {
      _deleteReceiptFileIfOwned(path);
    }
    await _loadAll();
    await _refreshCurrentNetWorthSnapshotBestEffort(
      const {
        NetWorthSnapshotCause.transaction,
        NetWorthSnapshotCause.refund,
        NetWorthSnapshotCause.physicalAsset,
        NetWorthSnapshotCause.receivable,
      },
    );
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 实物资产 CRUD / 生命周期
  // ---------------------------------------------------------------------------

  List<AssetEventEntity> eventsForAsset(int assetId) => _assetEvents
      .where((event) =>
          event.assetType == AssetObjectType.physical &&
          event.assetId == assetId)
      .toList()
    ..sort((a, b) => b.occurredMs.compareTo(a.occurredMs));

  AssetEventType? _terminalEventTypeFor(
    PhysicalAssetEconomicStatus status,
  ) =>
      switch (status) {
        PhysicalAssetEconomicStatus.scrapped => AssetEventType.assetDisposed,
        PhysicalAssetEconomicStatus.lost => AssetEventType.assetLost,
        PhysicalAssetEconomicStatus.gifted => AssetEventType.assetGifted,
        _ => null,
      };

  bool _hasPhysicalTerminalUndoEvidence(Map<String, dynamic> metadata) {
    final economicRaw = metadata['previous_economic_status']?.toString();
    final usageRaw = metadata['previous_usage_status']?.toString();
    final qualityRaw = metadata['previous_inclusion_quality']?.toString();
    final value = Decimal.tryParse(
      metadata['previous_value']?.toString() ?? '',
    );
    if (economicRaw == null ||
        usageRaw == null ||
        qualityRaw == null ||
        value == null ||
        value < Decimal.zero ||
        metadata['previous_include_in_net_worth'] is! bool ||
        !metadata.containsKey('previous_ended_ms')) {
      return false;
    }
    final economic = PhysicalAssetEconomicStatusX.fromStorage(economicRaw);
    return PhysicalAssetEconomicStatus.values
            .any((status) => status.storageKey == economicRaw) &&
        economic.ownsValue &&
        PhysicalAssetUsageStatus.values
            .any((status) => status.storageKey == usageRaw) &&
        AssetInclusionQuality.values
            .any((quality) => quality.storageKey == qualityRaw);
  }

  AssetEventEntity? _latestUnreversedTerminalEvent(
    Iterable<AssetEventEntity> events,
    AssetEventType terminalType,
  ) {
    final reversedIds = <int>{};
    final reversedUuids = <String>{};
    for (final event in events) {
      if (event.eventType != AssetEventType.assetTerminalUndone) continue;
      final metadata = _assetEventMetadata(event.metadata);
      final reversedId = int.tryParse(
        metadata['reversal_of_event_id']?.toString() ?? '',
      );
      final reversedUuid =
          metadata['reversal_of_event_uuid']?.toString().trim() ?? '';
      if (reversedId != null) reversedIds.add(reversedId);
      if (reversedUuid.isNotEmpty) reversedUuids.add(reversedUuid);
    }
    final candidates = events
        .where((event) =>
            event.eventType == terminalType &&
            !reversedIds.contains(event.id) &&
            (event.uuid.isEmpty || !reversedUuids.contains(event.uuid)))
        .toList()
      ..sort((left, right) {
        final created = right.createdMs.compareTo(left.createdMs);
        return created != 0 ? created : right.id.compareTo(left.id);
      });
    return candidates.firstOrNull;
  }

  bool canUndoPhysicalAssetTerminalStatus(int assetId) {
    final asset = physicalAssetDetailById(assetId);
    if (asset == null || asset.isDeleted) return false;
    final terminalType = _terminalEventTypeFor(asset.economicStatus);
    if (terminalType == null) return false;
    final event = _latestUnreversedTerminalEvent(
      _assetEvents.where((candidate) =>
          candidate.assetType == AssetObjectType.physical &&
          candidate.assetId == assetId),
      terminalType,
    );
    if (event == null) return false;
    return _hasPhysicalTerminalUndoEvidence(
      _assetEventMetadata(event.metadata),
    );
  }

  List<AssetValuationEntity> valuationsForAsset(int assetId) =>
      _assetValuations.where((value) => value.assetId == assetId).toList()
        ..sort((a, b) => b.valuedAtMs.compareTo(a.valuedAtMs));

  List<AssetTransactionLinkEntity> transactionLinksForAsset(int assetId) =>
      _assetTransactionLinks.where((link) => link.assetId == assetId).toList()
        ..sort((a, b) => b.createdMs.compareTo(a.createdMs));

  List<AssetTransactionLinkEntity> additionalCostLinksForAsset(int assetId) =>
      _assetTransactionLinks
          .where((link) =>
              link.assetObjectType == AssetObjectType.physical &&
              link.assetId == assetId &&
              link.linkType.isAdditionalCost)
          .toList()
        ..sort((a, b) => b.createdMs.compareTo(a.createdMs));

  int? _transactionFamilyNetCents(int transactionId) {
    final transaction = _allTransactions
        .where((item) => item.id == transactionId && item.refundOf == null)
        .firstOrNull;
    if (transaction == null) return null;
    final gross = decimalToBudgetCents(transaction.amount).abs();
    final refunds = decimalToBudgetCents(
      (_globalRefundTotals[transactionId] ?? Decimal.zero).abs(),
    ).abs();
    return max(0, gross - refunds);
  }

  int physicalAssetTransactionFamilyNetCents(int transactionId) =>
      _transactionFamilyNetCents(transactionId) ?? 0;

  Decimal physicalAssetLinkCurrentAmount(AssetTransactionLinkEntity link) {
    if (link.linkType.isAdditionalCost) {
      final cents = _transactionFamilyNetCents(link.transactionId);
      if (cents != null) return budgetDecimalFromCents(cents) ?? Decimal.zero;
    }
    if (link.linkType == AssetTransactionLinkType.sourceTransaction ||
        link.linkType == AssetTransactionLinkType.purchaseTransaction) {
      return budgetDecimalFromCents(max(0, link.allocatedNetCents)) ??
          Decimal.zero;
    }
    return link.amount;
  }

  List<AssetUsageEventEntity> usageEventsForAsset(int assetId) =>
      _assetUsageEvents.where((event) => event.assetId == assetId).toList()
        ..sort((left, right) {
          final occurred = left.occurredMs.compareTo(right.occurredMs);
          return occurred != 0 ? occurred : left.id.compareTo(right.id);
        });

  AssetUsageAggregation physicalAssetUsage(int assetId) {
    final events = usageEventsForAsset(assetId);
    final uuidById = {
      for (final event in events)
        event.id: event.uuid.isEmpty ? event.id.toString() : event.uuid,
    };
    return aggregateAssetUsage(
      events.map((event) => event.toPoint(uuidById)),
    );
  }

  AssetReminderState warrantyReminderForAsset(
    PhysicalAssetEntity asset, {
    DateTime? asOf,
  }) =>
      resolveWarrantyReminder(
        warrantyUntil: asset.warrantyUntil,
        isEconomicallyOwned: asset.isOwned && !asset.isDeleted,
        asOf: asOf,
      );

  AssetReminderState dueReminderForReceivable(
    ReceivableAssetEntity asset, {
    DateTime? asOf,
  }) =>
      resolveReceivableDueReminder(
        dueAt: asset.dueDate,
        isCollectible: !asset.isDeleted &&
            (asset.economicStatus == ReceivableEconomicStatus.active ||
                asset.economicStatus ==
                    ReceivableEconomicStatus.partialRecovered),
        asOf: asOf,
      );

  PhysicalAssetAdditionalCostResult physicalAssetAdditionalCost(
    int assetId, {
    DateTime? asOf,
  }) {
    final asset = physicalAssetDetailById(assetId);
    if (asset == null || asset.isDeleted) {
      return PhysicalAssetAdditionalCostResult(
        amount: Decimal.zero,
        isExact: false,
        reason: '物品不存在',
      );
    }
    final cutoff = asOf ?? DateTime.now();
    var cents = 0;
    final issues = <String>{};
    for (final link in additionalCostLinksForAsset(assetId)) {
      final transaction = _txById[link.transactionId];
      if (transaction == null) {
        issues.add('关联支出已不存在');
        continue;
      }
      if (transaction.txKind != TransactionKind.expense ||
          transaction.refundOf != null ||
          transaction.excluded ||
          transaction.currencyCode != asset.currencyCode) {
        issues.add('关联支出口径不一致');
        continue;
      }
      if (transaction.date.isAfter(cutoff)) continue;
      final gross = decimalToBudgetCents(transaction.amount).abs();
      final refunds = decimalToBudgetCents(
        (_globalRefundTotals[transaction.id] ?? Decimal.zero).abs(),
      ).abs();
      if (refunds > gross) {
        issues.add('关联支出退款超过原金额');
        continue;
      }
      cents += gross - refunds;
    }
    return PhysicalAssetAdditionalCostResult(
      amount: budgetDecimalFromCents(cents) ?? Decimal.zero,
      isExact: issues.isEmpty,
      reason: issues.join('；'),
    );
  }

  List<AssetPurchaseAllocationCandidate>
      eligiblePhysicalAssetPurchaseTransactions({
    int? bookId,
    String query = '',
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    final candidates = <AssetPurchaseAllocationCandidate>[];
    for (final transaction in _globalVisibleTransactions) {
      if ((bookId != null && transaction.bookId != bookId) ||
          transaction.txKind != TransactionKind.expense ||
          transaction.refundOf != null ||
          transaction.amount <= Decimal.zero ||
          transaction.currencyCode != 'CNY') {
        continue;
      }
      if (normalizedQuery.isNotEmpty &&
          !transaction.note.toLowerCase().contains(normalizedQuery) &&
          !transaction.categoryNameZh.toLowerCase().contains(normalizedQuery) &&
          !transaction.amountStr.contains(normalizedQuery)) {
        continue;
      }
      final links = _assetTransactionLinks.where((link) =>
          link.assetObjectType == AssetObjectType.physical &&
          link.transactionId == transaction.id &&
          (link.linkType == AssetTransactionLinkType.sourceTransaction ||
              link.linkType == AssetTransactionLinkType.purchaseTransaction));
      final gross = links.fold<int>(
        0,
        (sum, link) => sum + link.allocatedGrossCents,
      );
      final refund = links.fold<int>(
        0,
        (sum, link) => sum + link.allocatedRefundCents,
      );
      final orderGross = decimalToBudgetCents(transaction.amount).abs();
      final validRefund = decimalToBudgetCents(
        (_globalRefundTotals[transaction.id] ?? Decimal.zero).abs(),
      ).abs();
      if (orderGross - gross <= 0) continue;
      candidates.add(AssetPurchaseAllocationCandidate(
        transaction: transaction,
        orderGrossCents: orderGross,
        validRefundCents: validRefund,
        allocatedGrossCents: gross,
        allocatedRefundCents: refund,
      ));
    }
    candidates.sort((a, b) {
      final byDate = b.transaction.dateMs.compareTo(a.transaction.dateMs);
      return byDate != 0
          ? byDate
          : b.transaction.id.compareTo(a.transaction.id);
    });
    return candidates;
  }

  List<TransactionEntity> eligiblePhysicalAssetCostTransactions({
    required int assetId,
    String query = '',
  }) {
    final asset = physicalAssetDetailById(assetId);
    if (asset == null || asset.isDeleted || asset.bookId == null) {
      return const [];
    }
    final allowedBooks = _bookIdsForView(asset.bookId!).toSet();
    final normalized = query.trim().toLowerCase();
    final purchaseIds = _assetTransactionLinks
        .where((link) =>
            link.assetObjectType == AssetObjectType.physical &&
            link.assetId == assetId &&
            (link.linkType == AssetTransactionLinkType.sourceTransaction ||
                link.linkType == AssetTransactionLinkType.purchaseTransaction))
        .map((link) => link.transactionId)
        .toSet();
    final result = _globalVisibleTransactions.where((transaction) {
      if (transaction.txKind != TransactionKind.expense ||
          transaction.refundOf != null ||
          transaction.amount <= Decimal.zero ||
          transaction.excluded ||
          transaction.bookId == null ||
          !allowedBooks.contains(transaction.bookId) ||
          transaction.currencyCode != asset.currencyCode ||
          purchaseIds.contains(transaction.id)) {
        return false;
      }
      return normalized.isEmpty ||
          transaction.note.toLowerCase().contains(normalized) ||
          transaction.categoryNameZh.toLowerCase().contains(normalized) ||
          transaction.amountStr.contains(normalized);
    }).toList()
      ..sort((left, right) {
        final byDate = right.dateMs.compareTo(left.dateMs);
        return byDate != 0 ? byDate : right.id.compareTo(left.id);
      });
    return List.unmodifiable(result);
  }

  bool isTransactionLinkedAsPhysicalAssetCost(int transactionId) =>
      _assetTransactionLinks.any((link) =>
          link.assetObjectType == AssetObjectType.physical &&
          link.transactionId == transactionId &&
          (link.linkType.isAdditionalCost ||
              link.linkType == AssetTransactionLinkType.sourceTransaction ||
              link.linkType == AssetTransactionLinkType.purchaseTransaction));

  Future<void> linkPhysicalAssetCost({
    required int assetId,
    required int transactionId,
    required AssetTransactionLinkType type,
  }) async {
    if (!type.isAdditionalCost) {
      throw ArgumentError('关联类型不是物品持有支出');
    }
    final asset = physicalAssetDetailById(assetId);
    if (asset == null || asset.isDeleted || asset.bookId == null) {
      throw StateError('物品不存在');
    }
    final transaction =
        _allTransactions.where((item) => item.id == transactionId).firstOrNull;
    final allowedBooks = _bookIdsForView(asset.bookId!).toSet();
    if (transaction == null ||
        transaction.txKind != TransactionKind.expense ||
        transaction.refundOf != null ||
        transaction.amount <= Decimal.zero ||
        transaction.excluded ||
        transaction.bookId == null ||
        !allowedBooks.contains(transaction.bookId) ||
        transaction.currencyCode != asset.currencyCode) {
      throw StateError('只能关联同账本、同币种的普通支出');
    }
    if (isTransactionLinkedAsPhysicalAssetCost(transactionId)) {
      throw StateError('这笔支出已经关联了其他物品');
    }
    if (_assetTransactionLinks.any((link) =>
        link.assetObjectType == AssetObjectType.physical &&
        link.assetId == assetId &&
        link.transactionId == transactionId)) {
      throw StateError('这笔支出已经关联当前物品');
    }
    final net = max(
      0,
      decimalToBudgetCents(transaction.amount).abs() -
          decimalToBudgetCents(
            (_globalRefundTotals[transaction.id] ?? Decimal.zero).abs(),
          ).abs(),
    );
    await _db!.transaction((txn) async {
      await _insertAssetTransactionLink(
        txn,
        assetId: assetId,
        transactionId: transactionId,
        type: type,
        amount: budgetDecimalFromCents(net) ?? Decimal.zero,
        allocatedGrossCents: 0,
        costQuality: AssetAllocationCostQuality.exact,
        note: type.label,
      );
      await _insertAssetEvent(
        txn,
        assetId: assetId,
        type: AssetEventType.assetCostLinked,
        occurredAt: DateTime.now(),
        value: budgetDecimalFromCents(net),
        note: '${type.label} · 交易 #$transactionId',
        metadata: {
          'transaction_id': transactionId,
          'link_type': type.storageKey,
        },
      );
    });
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<List<PendingPhysicalAssetRefundAllocation>>
      pendingPhysicalAssetRefundAllocationsForAsset(int assetId) async {
    final purchaseLinks = _assetTransactionLinks
        .where((link) =>
            link.assetObjectType == AssetObjectType.physical &&
            link.assetId == assetId &&
            (link.linkType == AssetTransactionLinkType.sourceTransaction ||
                link.linkType == AssetTransactionLinkType.purchaseTransaction))
        .toList(growable: false);
    if (purchaseLinks.isEmpty) return const [];
    final orderIds = purchaseLinks.map((link) => link.transactionId).toSet();
    final assetsById = {
      for (final asset in _allPhysicalAssets) asset.id: asset,
    };
    final result = <PendingPhysicalAssetRefundAllocation>[];
    for (final refund in _allTransactions.where(
      (transaction) =>
          transaction.refundOf != null &&
          orderIds.contains(transaction.refundOf),
    )) {
      final orderLinks = _assetTransactionLinks
          .where((link) =>
              link.assetObjectType == AssetObjectType.physical &&
              link.transactionId == refund.refundOf &&
              (link.linkType == AssetTransactionLinkType.sourceTransaction ||
                  link.linkType ==
                      AssetTransactionLinkType.purchaseTransaction))
          .toList(growable: false);
      if (orderLinks.isEmpty) continue;
      final audits = await _db!.query(
        'asset_refund_allocations',
        columns: [
          'asset_transaction_link_id',
          'allocated_refund_cents',
        ],
        where: "refund_transaction_id = ? AND status = 'active'",
        whereArgs: [refund.id],
      );
      final allocatedByLink = <int, int>{};
      for (final audit in audits) {
        final linkId = audit['asset_transaction_link_id'] as int;
        allocatedByLink[linkId] = (allocatedByLink[linkId] ?? 0) +
            (audit['allocated_refund_cents'] as int? ?? 0);
      }
      final refundCents = decimalToBudgetCents(refund.amount).abs();
      final allocated = allocatedByLink.values.fold<int>(0, (a, b) => a + b);
      if (allocated >= refundCents) continue;
      final orderTx = _allTransactions
          .where((transaction) => transaction.id == refund.refundOf)
          .firstOrNull;
      final orderLabel = (orderTx?.note.trim().isNotEmpty ?? false)
          ? orderTx!.note.trim()
          : '账单 #${refund.refundOf}';
      // 订单里没被物品跟踪的部分也能吃退款：算出本退款还能归多少给它。
      final orderGrossCents =
          orderTx == null ? 0 : decimalToBudgetCents(orderTx.amount).abs();
      final trackedGross = orderLinks.fold<int>(
          0, (sum, link) => sum + link.allocatedGrossCents);
      final currentUntracked = allocatedByLink[_untrackedRefundLinkId] ?? 0;
      final orderUntracked =
          await _untrackedRefundCentsForOrder(_db!, refund.refundOf!);
      final untrackedLimit = max(0,
          orderGrossCents - trackedGross - (orderUntracked - currentUntracked));
      result.add(PendingPhysicalAssetRefundAllocation(
        refundTransactionId: refund.id,
        originalTransactionId: refund.refundOf!,
        refundDateMs: refund.settledMs ?? refund.dateMs,
        orderLabel: orderLabel,
        refundCents: refundCents,
        untrackedLimitCents: untrackedLimit,
        currentUntrackedCents: currentUntracked,
        targets: [
          for (final link in orderLinks)
            PhysicalAssetRefundAllocationTarget(
              assetId: link.assetId,
              name: assetsById[link.assetId]?.name ?? '物品 #${link.assetId}',
              grossCents: link.allocatedGrossCents,
              currentAllocatedRefundCents: allocatedByLink[link.id] ?? 0,
              totalAllocatedRefundCents: link.allocatedRefundCents,
            ),
        ],
      ));
    }
    result.sort(
      (a, b) => b.refundTransactionId.compareTo(a.refundTransactionId),
    );
    return result;
  }

  PhysicalAssetAcquisitionCostResult physicalAssetAcquisitionCost(
    int assetId,
  ) {
    final asset = physicalAssetDetailById(assetId);
    if (asset == null || asset.isDeleted) {
      return const PhysicalAssetAcquisitionCostResult(
        quality: PhysicalAssetAcquisitionCostQuality.conflict,
        amount: null,
        reason: '物品不存在或已删除',
      );
    }
    if (asset.acquisitionCostSource ==
        AssetAcquisitionCostSource.manualUnknown) {
      return const PhysicalAssetAcquisitionCostResult(
        quality: PhysicalAssetAcquisitionCostQuality.partial,
        amount: null,
        reason: '手工购置成本未知',
      );
    }
    if (asset.acquisitionCostSource == AssetAcquisitionCostSource.manual) {
      return PhysicalAssetAcquisitionCostResult(
        quality: PhysicalAssetAcquisitionCostQuality.exact,
        amount: asset.purchasePrice,
        reason: '手工购置成本',
      );
    }
    final purchaseLinks = transactionLinksForAsset(assetId)
        .where((link) =>
            link.assetObjectType == AssetObjectType.physical &&
            (link.linkType == AssetTransactionLinkType.sourceTransaction ||
                link.linkType == AssetTransactionLinkType.purchaseTransaction))
        .toList(growable: false);
    if (purchaseLinks.isEmpty) {
      return const PhysicalAssetAcquisitionCostResult(
        quality: PhysicalAssetAcquisitionCostQuality.conflict,
        amount: null,
        reason: '账单分配来源物品缺少购置账单关联',
      );
    }
    if (purchaseLinks.any((link) =>
        link.allocatedGrossCents < 0 ||
        link.allocatedRefundCents < 0 ||
        link.allocatedRefundCents > link.allocatedGrossCents)) {
      return const PhysicalAssetAcquisitionCostResult(
        quality: PhysicalAssetAcquisitionCostQuality.conflict,
        amount: null,
        reason: '购置账单分配金额不合法',
      );
    }
    final netCents = purchaseLinks.fold<int>(
      0,
      (sum, link) => sum + link.allocatedNetCents,
    );
    final hasPending = purchaseLinks
        .any((link) => link.costQuality != AssetAllocationCostQuality.exact);
    if (hasPending) {
      return PhysicalAssetAcquisitionCostResult(
        quality: PhysicalAssetAcquisitionCostQuality.partial,
        amount: budgetDecimalFromCents(netCents),
        reason: purchaseLinks.any((link) =>
                link.costQuality ==
                AssetAllocationCostQuality.pendingRefundAllocation)
            ? '有退款尚未分配到具体物品'
            : '购置账单仍有未确认分配',
      );
    }
    return PhysicalAssetAcquisitionCostResult(
      quality: PhysicalAssetAcquisitionCostQuality.exact,
      amount: budgetDecimalFromCents(netCents),
      reason: '账单逐物品分配后的净购置成本',
    );
  }

  List<AssetEventEntity> eventsForReceivableAsset(int assetId) => _assetEvents
      .where((event) =>
          event.assetType == AssetObjectType.receivable &&
          event.assetId == assetId)
      .toList()
    ..sort((a, b) => b.occurredMs.compareTo(a.occurredMs));

  List<ReceivableRecoveryEntity> recoveriesForReceivableAsset(int assetId) =>
      _receivableRecoveries
          .where((recovery) => recovery.receivableAssetId == assetId)
          .toList()
        ..sort((a, b) => b.recoveredMs.compareTo(a.recoveredMs));

  Future<int> _insertAssetEvent(
    DatabaseExecutor db, {
    required int assetId,
    AssetObjectType assetType = AssetObjectType.physical,
    required AssetEventType type,
    required DateTime occurredAt,
    Decimal? value,
    String note = '',
    Map<String, Object?> metadata = const {},
  }) async {
    return db.insert('asset_events', {
      'uuid': _newUuid(),
      'asset_id': assetId,
      'asset_type': assetType.storageKey,
      'event_type': type.storageKey,
      'occurred_ms': occurredAt.millisecondsSinceEpoch,
      'value': value?.toString() ?? '',
      'note': note,
      'metadata': metadata.isEmpty ? '' : jsonEncode(metadata),
      'created_ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _insertAssetValuation(
    DatabaseExecutor db, {
    required int assetId,
    required Decimal value,
    required AssetValueSource source,
    required DateTime valuedAt,
    String note = '',
  }) async {
    await db.insert('asset_valuations', {
      'uuid': _newUuid(),
      'asset_id': assetId,
      'value': value.toString(),
      'source': source.storageKey,
      'valued_at_ms': valuedAt.millisecondsSinceEpoch,
      'note': note,
      'created_ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _insertAssetTransactionLink(
    DatabaseExecutor db, {
    required int assetId,
    required int transactionId,
    required AssetTransactionLinkType type,
    required Decimal amount,
    int? allocatedGrossCents,
    int allocatedRefundCents = 0,
    AssetAllocationCostQuality costQuality = AssetAllocationCostQuality.exact,
    String note = '',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'asset_transaction_links',
      {
        'uuid': _newUuid(),
        'asset_id': assetId,
        'asset_object_type': AssetObjectType.physical.storageKey,
        'transaction_id': transactionId,
        'link_type': type.storageKey,
        'amount': amount.toString(),
        'allocated_gross_cents':
            allocatedGrossCents ?? decimalToBudgetCents(amount).abs(),
        'allocated_refund_cents': allocatedRefundCents,
        'cost_quality': costQuality.storageKey,
        'note': note,
        'created_ms': now,
        'updated_ms': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int> _validOrderRefundCents(
    DatabaseExecutor db,
    int transactionId,
  ) async {
    final rows = await db.query(
      'transactions',
      columns: ['amount'],
      where: 'refund_of = ?',
      whereArgs: [transactionId],
    );
    return rows.fold<int>(0, (sum, row) {
      final amount =
          Decimal.tryParse(row['amount'] as String? ?? '') ?? Decimal.zero;
      return sum + decimalToBudgetCents(amount).abs();
    });
  }

  Future<void> _validateOrderAllocations(
    DatabaseExecutor db,
    int transactionId, {
    int? excludingLinkId,
    AssetAllocationLine? proposed,
  }) async {
    final orderRows = await db.query(
      'transactions',
      columns: ['amount', 'kind', 'refund_of'],
      where: 'id = ?',
      whereArgs: [transactionId],
      limit: 1,
    );
    if (orderRows.isEmpty) throw StateError('购置账单不存在');
    final order = orderRows.first;
    final orderAmount =
        Decimal.tryParse(order['amount'] as String? ?? '') ?? Decimal.zero;
    if (order['kind'] != TransactionKind.expense.toJson() ||
        order['refund_of'] != null ||
        orderAmount <= Decimal.zero) {
      throw StateError('只能分配正数支出原账单');
    }
    final rows = await db.query(
      'asset_transaction_links',
      columns: [
        'id',
        'asset_id',
        'allocated_gross_cents',
        'allocated_refund_cents'
      ],
      where:
          "transaction_id = ? AND asset_object_type = 'physical' AND link_type IN ('source_transaction', 'purchase_transaction')",
      whereArgs: [transactionId],
    );
    final lines = <AssetAllocationLine>[
      for (final row in rows)
        if (row['id'] != excludingLinkId)
          AssetAllocationLine(
            assetId: row['asset_id'] as int,
            grossCents: row['allocated_gross_cents'] as int? ?? 0,
            refundCents: row['allocated_refund_cents'] as int? ?? 0,
          ),
      if (proposed != null) proposed,
    ];
    AssetAllocationPolicy.validate(
      orderGrossCents: decimalToBudgetCents(orderAmount).abs(),
      validOrderRefundCents: await _validOrderRefundCents(db, transactionId),
      lines: lines,
    );
  }

  Future<void> _auditRefundAllocation(
    DatabaseExecutor db, {
    required int linkId,
    required int refundTransactionId,
    required int cents,
  }) async {
    if (cents <= 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'asset_refund_allocations',
      {
        'uuid': _newUuid(),
        'asset_transaction_link_id': linkId,
        'refund_transaction_id': refundTransactionId,
        'allocated_refund_cents': cents,
        'status': 'active',
        'created_ms': now,
        'updated_ms': now,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> _allocateHistoricalRefundsToLink(
    DatabaseExecutor db, {
    required int transactionId,
    required int linkId,
    required int requestedCents,
  }) async {
    var remaining = requestedCents;
    if (remaining == 0) return;
    final refunds = await db.query(
      'transactions',
      columns: ['id', 'amount'],
      where: 'refund_of = ?',
      whereArgs: [transactionId],
      orderBy: 'id ASC',
    );
    for (final refund in refunds) {
      if (remaining == 0) break;
      final refundId = refund['id'] as int;
      final total = decimalToBudgetCents(
        Decimal.tryParse(refund['amount'] as String? ?? '') ?? Decimal.zero,
      ).abs();
      final allocated = Sqflite.firstIntValue(await db.rawQuery('''
        SELECT COALESCE(SUM(allocated_refund_cents), 0)
        FROM asset_refund_allocations
        WHERE refund_transaction_id = ? AND status = 'active'
      ''', [refundId])) ?? 0;
      final available = total - allocated;
      if (available <= 0) continue;
      final take = remaining < available ? remaining : available;
      await _auditRefundAllocation(
        db,
        linkId: linkId,
        refundTransactionId: refundId,
        cents: take,
      );
      remaining -= take;
    }
    if (remaining != 0) {
      throw StateError('退款分配缺少对应的有效退款事件');
    }
  }

  /// 「归属未跟踪部分」的哨兵 link id：订单里退款属于没被任何物品跟踪的
  /// 那部分时，审计行的 asset_transaction_link_id 记 0（真实 link id 从 1 起，
  /// 撤销/改派路径查不到 id=0 的 link 会自然跳过 link 侧回退）。
  static const int _untrackedRefundLinkId = 0;

  /// 某订单全部退款里已归到「未跟踪部分」的合计（active 审计行）。
  Future<int> _untrackedRefundCentsForOrder(
    DatabaseExecutor db,
    int transactionId,
  ) async {
    return Sqflite.firstIntValue(await db.rawQuery('''
          SELECT COALESCE(SUM(ara.allocated_refund_cents), 0)
          FROM asset_refund_allocations ara
          JOIN transactions t ON t.id = ara.refund_transaction_id
          WHERE t.refund_of = ? AND ara.status = 'active'
            AND ara.asset_transaction_link_id = ?
        ''', [transactionId, _untrackedRefundLinkId])) ?? 0;
  }

  Future<void> _refreshOrderAllocationQuality(
    DatabaseExecutor db,
    int transactionId,
  ) async {
    final orderRows = await db.query(
      'transactions',
      columns: ['amount'],
      where: 'id = ?',
      whereArgs: [transactionId],
      limit: 1,
    );
    if (orderRows.isEmpty) return;
    final links = await db.query(
      'asset_transaction_links',
      where:
          "transaction_id = ? AND asset_object_type = 'physical' AND link_type IN ('source_transaction', 'purchase_transaction')",
      whereArgs: [transactionId],
    );
    final allocatedRefund = links.fold<int>(
      0,
      (sum, row) => sum + (row['allocated_refund_cents'] as int? ?? 0),
    );
    // 归到「未跟踪部分」的退款也算已解决：不能让这类订单永远卡在待分配。
    final untrackedRefund =
        await _untrackedRefundCentsForOrder(db, transactionId);
    final validRefund = await _validOrderRefundCents(db, transactionId);
    final quality = allocatedRefund + untrackedRefund < validRefund
        ? AssetAllocationCostQuality.pendingRefundAllocation
        : links.any(
            (row) => (row['allocated_gross_cents'] as int? ?? 0) <= 0,
          )
            ? AssetAllocationCostQuality.partial
            : AssetAllocationCostQuality.exact;
    await db.update(
      'asset_transaction_links',
      {
        'cost_quality': quality.storageKey,
        'updated_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where:
          "transaction_id = ? AND asset_object_type = 'physical' AND link_type IN ('source_transaction', 'purchase_transaction')",
      whereArgs: [transactionId],
    );
  }

  Future<void> _syncAssetPurchasePriceCache(
    DatabaseExecutor db,
    Iterable<int> assetIds,
  ) async {
    for (final assetId in assetIds.toSet()) {
      final rows = await db.query(
        'asset_transaction_links',
        columns: ['allocated_gross_cents', 'allocated_refund_cents'],
        where:
            "asset_object_type = 'physical' AND asset_id = ? AND link_type IN ('source_transaction', 'purchase_transaction')",
        whereArgs: [assetId],
      );
      final netCents = rows.fold<int>(
        0,
        (sum, row) =>
            sum +
            (row['allocated_gross_cents'] as int? ?? 0) -
            (row['allocated_refund_cents'] as int? ?? 0),
      );
      await db.update(
        'physical_assets',
        {
          'purchase_price': budgetDecimalFromCents(netCents).toString(),
          'acquisition_cost_source':
              AssetAcquisitionCostSource.transactionAllocations.storageKey,
          'updated_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [assetId],
      );
    }
  }

  Future<void> _autoAllocateAllRefundsForSingleFullLink(
    DatabaseExecutor db,
    int transactionId,
  ) async {
    final links = await db.query(
      'asset_transaction_links',
      where:
          "transaction_id = ? AND asset_object_type = 'physical' AND link_type IN ('source_transaction', 'purchase_transaction')",
      whereArgs: [transactionId],
    );
    final orderRows = await db.query(
      'transactions',
      columns: ['amount'],
      where: 'id = ?',
      whereArgs: [transactionId],
      limit: 1,
    );
    if (links.length != 1 || orderRows.isEmpty) {
      await _refreshOrderAllocationQuality(db, transactionId);
      return;
    }
    final link = links.single;
    final gross = link['allocated_gross_cents'] as int? ?? 0;
    final orderGross = decimalToBudgetCents(
      Decimal.tryParse(orderRows.first['amount'] as String? ?? '') ??
          Decimal.zero,
    ).abs();
    final currentRefund = link['allocated_refund_cents'] as int? ?? 0;
    final validRefund = await _validOrderRefundCents(db, transactionId);
    final missing = validRefund - currentRefund;
    final uniquelyCoversTrackedItem = currentRefund + missing == gross;
    if (missing > 0 &&
        currentRefund + missing <= gross &&
        (gross == orderGross || uniquelyCoversTrackedItem)) {
      await _allocateHistoricalRefundsToLink(
        db,
        transactionId: transactionId,
        linkId: link['id'] as int,
        requestedCents: missing,
      );
      await db.update(
        'asset_transaction_links',
        {'allocated_refund_cents': currentRefund + missing},
        where: 'id = ?',
        whereArgs: [link['id']],
      );
    }
    await _refreshOrderAllocationQuality(db, transactionId);
    await _syncAssetPurchasePriceCache(db, [link['asset_id'] as int]);
  }

  Future<void> _applyNewRefundToAssetAllocations(
    DatabaseExecutor db, {
    required int originalTransactionId,
    required int refundTransactionId,
    required int refundCents,
  }) async {
    final links = await db.query(
      'asset_transaction_links',
      where:
          "transaction_id = ? AND asset_object_type = 'physical' AND link_type IN ('source_transaction', 'purchase_transaction')",
      whereArgs: [originalTransactionId],
    );
    if (links.isEmpty) return;
    final orderRows = await db.query(
      'transactions',
      columns: ['amount'],
      where: 'id = ?',
      whereArgs: [originalTransactionId],
      limit: 1,
    );
    final orderGross = orderRows.isEmpty
        ? 0
        : decimalToBudgetCents(
            Decimal.tryParse(orderRows.first['amount'] as String? ?? '') ??
                Decimal.zero,
          ).abs();
    if (links.length == 1) {
      final link = links.single;
      final gross = link['allocated_gross_cents'] as int? ?? 0;
      final currentRefund = link['allocated_refund_cents'] as int? ?? 0;
      final validRefund =
          await _validOrderRefundCents(db, originalTransactionId);
      final priorRefundsFullyAllocated =
          currentRefund == validRefund - refundCents;
      final uniquelyCoversTrackedItem = currentRefund + refundCents == gross;
      if (priorRefundsFullyAllocated &&
          currentRefund + refundCents <= gross &&
          (gross == orderGross || uniquelyCoversTrackedItem)) {
        await _validateOrderAllocations(
          db,
          originalTransactionId,
          excludingLinkId: link['id'] as int,
          proposed: AssetAllocationLine(
            assetId: link['asset_id'] as int,
            grossCents: gross,
            refundCents: currentRefund + refundCents,
          ),
        );
        await db.update(
          'asset_transaction_links',
          {
            'allocated_refund_cents': currentRefund + refundCents,
            'cost_quality': AssetAllocationCostQuality.exact.storageKey,
            'updated_ms': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [link['id']],
        );
        await _auditRefundAllocation(
          db,
          linkId: link['id'] as int,
          refundTransactionId: refundTransactionId,
          cents: refundCents,
        );
        await _syncAssetPurchasePriceCache(db, [link['asset_id'] as int]);
        return;
      }
    }
    await db.update(
      'asset_transaction_links',
      {
        'cost_quality':
            AssetAllocationCostQuality.pendingRefundAllocation.storageKey,
        'updated_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where:
          "transaction_id = ? AND asset_object_type = 'physical' AND link_type IN ('source_transaction', 'purchase_transaction')",
      whereArgs: [originalTransactionId],
    );
  }

  Future<void> allocatePhysicalAssetRefund({
    required int refundTransactionId,
    required Map<int, int> allocationsByAssetId,
    int untrackedCents = 0,
  }) async {
    if (allocationsByAssetId.values.any((cents) => cents < 0) ||
        untrackedCents < 0) {
      throw ArgumentError('退款分配不能包含负数');
    }
    int? originalId;
    await _db!.transaction((txn) async {
      final refundRows = await txn.query(
        'transactions',
        columns: ['refund_of', 'amount'],
        where: 'id = ?',
        whereArgs: [refundTransactionId],
        limit: 1,
      );
      if (refundRows.isEmpty || refundRows.first['refund_of'] == null) {
        throw StateError('退款事件不存在');
      }
      originalId = refundRows.first['refund_of'] as int;
      final refundCents = decimalToBudgetCents(
        Decimal.tryParse(refundRows.first['amount'] as String? ?? '') ??
            Decimal.zero,
      ).abs();
      final requested =
          allocationsByAssetId.values.fold<int>(0, (a, b) => a + b);
      // 退款可以部分（甚至全部）属于订单里没入库跟踪的部分——强制全摊到
      // 已跟踪物品会污染资产成本。物品分配 + 未跟踪归属必须恰好等于退款额。
      if (requested + untrackedCents != refundCents) {
        throw StateError('物品分配与未跟踪归属合计必须等于本次退款金额');
      }

      final oldAudit = await txn.query(
        'asset_refund_allocations',
        where: "refund_transaction_id = ? AND status = 'active'",
        whereArgs: [refundTransactionId],
      );
      final affectedAssets = <int>{};
      for (final audit in oldAudit) {
        final linkId = audit['asset_transaction_link_id'] as int;
        final cents = audit['allocated_refund_cents'] as int;
        final linkRows = await txn.query(
          'asset_transaction_links',
          columns: ['asset_id', 'allocated_refund_cents'],
          where: 'id = ?',
          whereArgs: [linkId],
          limit: 1,
        );
        if (linkRows.isNotEmpty) {
          final link = linkRows.first;
          affectedAssets.add(link['asset_id'] as int);
          await txn.update(
            'asset_transaction_links',
            {
              'allocated_refund_cents':
                  (link['allocated_refund_cents'] as int? ?? 0) - cents,
            },
            where: 'id = ?',
            whereArgs: [linkId],
          );
        }
        await txn.update(
          'asset_refund_allocations',
          {
            'status': 'reversed',
            'updated_ms': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [audit['id']],
        );
      }

      final proposedByLink = <int, AssetAllocationLine>{};
      for (final entry in allocationsByAssetId.entries) {
        if (entry.value == 0) continue;
        final linkRows = await txn.query(
          'asset_transaction_links',
          where:
              "transaction_id = ? AND asset_object_type = 'physical' AND asset_id = ? AND link_type IN ('source_transaction', 'purchase_transaction')",
          whereArgs: [originalId, entry.key],
        );
        if (linkRows.length != 1) {
          throw StateError('退款物品缺少唯一的购置账单关联');
        }
        final link = linkRows.single;
        final nextRefund =
            (link['allocated_refund_cents'] as int? ?? 0) + entry.value;
        proposedByLink[link['id'] as int] = AssetAllocationLine(
          assetId: entry.key,
          grossCents: link['allocated_gross_cents'] as int? ?? 0,
          refundCents: nextRefund,
        );
      }
      final allLinks = await txn.query(
        'asset_transaction_links',
        where:
            "transaction_id = ? AND asset_object_type = 'physical' AND link_type IN ('source_transaction', 'purchase_transaction')",
        whereArgs: [originalId],
      );
      final orderRows = await txn.query(
        'transactions',
        columns: ['amount'],
        where: 'id = ?',
        whereArgs: [originalId],
        limit: 1,
      );
      final orderGrossCents = decimalToBudgetCents(
        Decimal.tryParse(orderRows.first['amount'] as String? ?? '') ??
            Decimal.zero,
      ).abs();
      AssetAllocationPolicy.validate(
        orderGrossCents: orderGrossCents,
        validOrderRefundCents: await _validOrderRefundCents(txn, originalId!),
        lines: [
          for (final link in allLinks)
            proposedByLink[link['id'] as int] ??
                AssetAllocationLine(
                  assetId: link['asset_id'] as int,
                  grossCents: link['allocated_gross_cents'] as int? ?? 0,
                  refundCents: link['allocated_refund_cents'] as int? ?? 0,
                )
        ],
      );
      if (untrackedCents > 0) {
        // 未跟踪归属的容量 = 订单毛额 − 已跟踪物品毛额 − 别的退款已占用的
        // 未跟踪额度（本退款旧的未跟踪审计行刚在上面被置 reversed，不重算）。
        final trackedGross = allLinks.fold<int>(
          0,
          (sum, row) => sum + (row['allocated_gross_cents'] as int? ?? 0),
        );
        final alreadyUntracked =
            await _untrackedRefundCentsForOrder(txn, originalId!);
        if (untrackedCents + alreadyUntracked >
            orderGrossCents - trackedGross) {
          throw StateError('归到未跟踪部分的退款超过订单里未跟踪的金额');
        }
        await _auditRefundAllocation(
          txn,
          linkId: _untrackedRefundLinkId,
          refundTransactionId: refundTransactionId,
          cents: untrackedCents,
        );
      }
      for (final entry in allocationsByAssetId.entries) {
        if (entry.value == 0) continue;
        final link =
            allLinks.singleWhere((row) => row['asset_id'] == entry.key);
        final proposed = proposedByLink[link['id'] as int]!;
        await txn.update(
          'asset_transaction_links',
          {'allocated_refund_cents': proposed.refundCents},
          where: 'id = ?',
          whereArgs: [link['id']],
        );
        await _auditRefundAllocation(
          txn,
          linkId: link['id'] as int,
          refundTransactionId: refundTransactionId,
          cents: entry.value,
        );
        affectedAssets.add(entry.key);
      }
      await _assertReturnedAssetsKeepZeroAllocatedCost(txn, affectedAssets);
      await _refreshOrderAllocationQuality(txn, originalId!);
      await _syncAssetPurchasePriceCache(txn, affectedAssets);
    });
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<void> _reverseRefundAllocationAudit(
    DatabaseExecutor db,
    Iterable<int> refundTransactionIds,
  ) async {
    final ids = refundTransactionIds.toSet();
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    final audits = await db.query(
      'asset_refund_allocations',
      where: "refund_transaction_id IN ($placeholders) AND status = 'active'",
      whereArgs: ids.toList(),
    );
    final affectedAssets = <int>{};
    final affectedOrders = <int>{};
    for (final audit in audits) {
      final linkRows = await db.query(
        'asset_transaction_links',
        where: 'id = ?',
        whereArgs: [audit['asset_transaction_link_id']],
        limit: 1,
      );
      if (linkRows.isNotEmpty) {
        final link = linkRows.first;
        final current = link['allocated_refund_cents'] as int? ?? 0;
        final cents = audit['allocated_refund_cents'] as int;
        await db.update(
          'asset_transaction_links',
          {'allocated_refund_cents': current - cents},
          where: 'id = ?',
          whereArgs: [link['id']],
        );
        affectedAssets.add(link['asset_id'] as int);
        affectedOrders.add(link['transaction_id'] as int);
      } else if ((audit['asset_transaction_link_id'] as int? ?? -1) ==
          _untrackedRefundLinkId) {
        // 未跟踪归属行没有 link 可回退，但订单的分配质量仍要重算
        //（退款事件此刻可能已删，查不到就留给下次分配动作刷新）。
        final txRows = await db.query(
          'transactions',
          columns: ['refund_of'],
          where: 'id = ?',
          whereArgs: [audit['refund_transaction_id']],
          limit: 1,
        );
        final orderId =
            txRows.isEmpty ? null : txRows.first['refund_of'] as int?;
        if (orderId != null) affectedOrders.add(orderId);
      }
      await db.update(
        'asset_refund_allocations',
        {
          'status': 'reversed',
          'updated_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [audit['id']],
      );
    }
    for (final orderId in affectedOrders) {
      await _refreshOrderAllocationQuality(db, orderId);
    }
    await _syncAssetPurchasePriceCache(db, affectedAssets);
  }

  Future<void> _assertReturnedAssetsKeepZeroAllocatedCost(
    DatabaseExecutor db,
    Iterable<int> assetIds,
  ) async {
    for (final assetId in assetIds.toSet()) {
      final assetRows = await db.query(
        'physical_assets',
        columns: ['economic_status'],
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [assetId],
        limit: 1,
      );
      if (assetRows.isEmpty ||
          assetRows.first['economic_status'] !=
              PhysicalAssetEconomicStatus.returned.storageKey) {
        continue;
      }
      final links = await db.query(
        'asset_transaction_links',
        columns: ['allocated_gross_cents', 'allocated_refund_cents'],
        where:
            "asset_object_type = 'physical' AND asset_id = ? AND link_type IN ('source_transaction', 'purchase_transaction')",
        whereArgs: [assetId],
      );
      final netCents = links.fold<int>(
        0,
        (sum, link) =>
            sum +
            (link['allocated_gross_cents'] as int? ?? 0) -
            (link['allocated_refund_cents'] as int? ?? 0),
      );
      if (netCents != 0) {
        throw StateError('已确认退货的物品必须保持净购置成本为 0，请先撤销退货');
      }
    }
  }

  Future<void> _assertRefundDeletionAllowed(
    DatabaseExecutor db,
    int refundTransactionId,
  ) async {
    final refundRows = await db.query(
      'transactions',
      columns: ['refund_of'],
      where: 'id = ?',
      whereArgs: [refundTransactionId],
      limit: 1,
    );
    final originalId = refundRows.firstOrNull?['refund_of'] as int?;
    if (originalId == null) return;
    final returned = await db.rawQuery('''
      SELECT p.id
      FROM asset_transaction_links l
      JOIN physical_assets p ON p.id = l.asset_id
      WHERE l.transaction_id = ?
        AND l.asset_object_type = 'physical'
        AND l.link_type IN ('source_transaction', 'purchase_transaction')
        AND l.allocated_refund_cents > 0
        AND p.is_deleted = 0
        AND p.economic_status = ?
      LIMIT 1
    ''', [
      originalId,
      PhysicalAssetEconomicStatus.returned.storageKey,
    ]);
    if (returned.isNotEmpty) {
      throw StateError('这笔退款已经用于确认物品退货，请先撤销退货');
    }
  }

  static Map<String, dynamic> _assetEventMetadata(String raw) {
    if (raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  static DateTime _assetCalendarDay(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  static bool _assetDayIsBefore(DateTime value, DateTime reference) =>
      _assetCalendarDay(value).isBefore(_assetCalendarDay(reference));

  static bool _sameAssetCalendarDay(DateTime left, DateTime right) =>
      _assetCalendarDay(left) == _assetCalendarDay(right);

  AssetEventType _createEventForSource(PhysicalAssetSourceType source) =>
      switch (source) {
        PhysicalAssetSourceType.historicalExisting =>
          AssetEventType.openingAssetImport,
        PhysicalAssetSourceType.fromTransaction =>
          AssetEventType.createdFromTransaction,
        PhysicalAssetSourceType.newPurchaseWithAccount =>
          AssetEventType.assetPurchased,
        PhysicalAssetSourceType.giftReceived ||
        PhysicalAssetSourceType.inheritance ||
        PhysicalAssetSourceType.manualOther =>
          AssetEventType.assetCreated,
      };

  AssetValueSource _initialValueSourceFor(PhysicalAssetSourceType source) =>
      switch (source) {
        PhysicalAssetSourceType.historicalExisting => AssetValueSource.opening,
        PhysicalAssetSourceType.newPurchaseWithAccount ||
        PhysicalAssetSourceType.fromTransaction =>
          AssetValueSource.purchase,
        PhysicalAssetSourceType.giftReceived ||
        PhysicalAssetSourceType.inheritance ||
        PhysicalAssetSourceType.manualOther =>
          AssetValueSource.manual,
      };

  Future<void> linkPhysicalAssetPurchaseAllocation({
    required int assetId,
    required int transactionId,
    required int allocatedGrossCents,
    int allocatedRefundCents = 0,
    bool replaceManualCost = false,
  }) async {
    if (allocatedGrossCents <= 0 ||
        allocatedRefundCents < 0 ||
        allocatedRefundCents > allocatedGrossCents) {
      throw ArgumentError('物品分配金额不合法');
    }
    await _db!.transaction((txn) async {
      final assetRows = await txn.query(
        'physical_assets',
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [assetId],
        limit: 1,
      );
      if (assetRows.isEmpty) throw StateError('物品不存在');
      final asset = PhysicalAssetEntity.fromMap(assetRows.first);
      if (asset.acquisitionCostSource == AssetAcquisitionCostSource.manual &&
          !replaceManualCost) {
        throw StateError('请先确认用账单分配替换手工成本');
      }
      final transactionRows = await txn.query(
        'transactions',
        columns: ['book_id', 'kind', 'amount', 'currency_code', 'refund_of'],
        where: 'id = ?',
        whereArgs: [transactionId],
        limit: 1,
      );
      if (transactionRows.isEmpty) throw StateError('购置账单不存在');
      final transaction = transactionRows.first;
      if (transaction['book_id'] != asset.bookId ||
          transaction['kind'] != TransactionKind.expense.toJson() ||
          transaction['refund_of'] != null ||
          transaction['currency_code'] != asset.currencyCode) {
        throw StateError('物品和购置账单的账本、类型或币种不一致');
      }
      await _validateOrderAllocations(
        txn,
        transactionId,
        proposed: AssetAllocationLine(
          assetId: assetId,
          grossCents: allocatedGrossCents,
          refundCents: allocatedRefundCents,
        ),
      );
      await _insertAssetTransactionLink(
        txn,
        assetId: assetId,
        transactionId: transactionId,
        type: AssetTransactionLinkType.sourceTransaction,
        amount: budgetDecimalFromCents(allocatedGrossCents)!,
        allocatedGrossCents: allocatedGrossCents,
        allocatedRefundCents: allocatedRefundCents,
        costQuality: AssetAllocationCostQuality.partial,
        note: '从已有账单分配',
      );
      final linkId = Sqflite.firstIntValue(await txn.rawQuery('''
        SELECT id FROM asset_transaction_links
        WHERE asset_object_type = 'physical'
          AND asset_id = ? AND transaction_id = ?
          AND link_type = 'source_transaction'
        LIMIT 1
      ''', [assetId, transactionId]));
      if (linkId == null) throw StateError('保存物品账单关联失败');
      await _allocateHistoricalRefundsToLink(
        txn,
        transactionId: transactionId,
        linkId: linkId,
        requestedCents: allocatedRefundCents,
      );
      await _refreshOrderAllocationQuality(txn, transactionId);
      await _syncAssetPurchasePriceCache(txn, [assetId]);
    });
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<int> addPhysicalAssetFromTransaction({
    required int transactionId,
    required String name,
    AssetType assetType = AssetType.other,
    required int allocatedGrossCents,
    int allocatedRefundCents = 0,
    Decimal? currentValue,
    PhysicalAssetStatus status = PhysicalAssetStatus.active,
    String brand = '',
    String model = '',
    String location = '',
    DateTime? warrantyUntil,
    String photoPath = '',
    String thumbnailPath = '',
    String note = '',
    bool includeInNetWorth = true,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) throw ArgumentError('资产名称不能为空');
    if (!status.canCountInNetWorth) {
      throw ArgumentError('新增资产只能从使用中或闲置状态开始');
    }
    if (allocatedGrossCents <= 0 ||
        allocatedRefundCents < 0 ||
        allocatedRefundCents > allocatedGrossCents) {
      throw ArgumentError('物品分配金额不合法');
    }
    final initialNet = budgetDecimalFromCents(
      allocatedGrossCents - allocatedRefundCents,
    )!;
    final initialValue = currentValue ?? initialNet;
    if (initialValue < Decimal.zero) throw ArgumentError('资产金额不能为负');
    late int assetId;
    await _db!.transaction((txn) async {
      final transactionRows = await txn.query(
        'transactions',
        where: 'id = ?',
        whereArgs: [transactionId],
        limit: 1,
      );
      if (transactionRows.isEmpty) throw StateError('购置账单不存在');
      final transaction = transactionRows.first;
      final amount = Decimal.tryParse(transaction['amount'] as String? ?? '') ??
          Decimal.zero;
      if (transaction['kind'] != TransactionKind.expense.toJson() ||
          transaction['refund_of'] != null ||
          amount <= Decimal.zero ||
          transaction['currency_code'] != 'CNY') {
        throw StateError('只能从人民币正数支出原账单加入物品');
      }
      await _validateOrderAllocations(
        txn,
        transactionId,
        proposed: AssetAllocationLine(
          assetId: -1,
          grossCents: allocatedGrossCents,
          refundCents: allocatedRefundCents,
        ),
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      final dateMs = transaction['date_ms'] as int;
      final purchaseDate = DateTime.fromMillisecondsSinceEpoch(dateMs);
      if (warrantyUntil != null &&
          _assetDayIsBefore(warrantyUntil, purchaseDate)) {
        throw ArgumentError('保修到期日不能早于购买日期');
      }
      final usageStatus = status == PhysicalAssetStatus.idle
          ? PhysicalAssetUsageStatus.idle
          : PhysicalAssetUsageStatus.active;
      assetId = await txn.insert('physical_assets', {
        'uuid': _newUuid(),
        'book_id': transaction['book_id'] as int?,
        'name': trimmedName,
        'asset_type': assetType.storageKey,
        'status': status.storageKey,
        'economic_status': PhysicalAssetEconomicStatus.owned.storageKey,
        'usage_status': usageStatus.storageKey,
        'visibility_status': AssetVisibilityStatus.active.storageKey,
        'inclusion_quality': AssetInclusionQuality.confirmed.storageKey,
        'source_type': PhysicalAssetSourceType.fromTransaction.storageKey,
        'acquisition_cost_source':
            AssetAcquisitionCostSource.transactionAllocations.storageKey,
        'purchase_price': initialNet.toString(),
        'current_value': initialValue.toString(),
        'currency_code': 'CNY',
        'purchase_date_ms': dateMs,
        'brand': brand.trim(),
        'model': model.trim(),
        'location': location.trim(),
        'warranty_until_ms': warrantyUntil?.millisecondsSinceEpoch,
        'photo_path': photoPath.trim(),
        'thumbnail_path': thumbnailPath.trim(),
        'invoice_path': '',
        'depreciation_method': '',
        'depreciation_base': '0',
        'salvage_value': '0',
        'useful_life_months': 0,
        'depreciation_start_ms': null,
        'depreciation_paused': 0,
        'note': note.trim(),
        'include_in_net_worth': includeInNetWorth ? 1 : 0,
        'is_deleted': 0,
        'ended_ms': null,
        'archived_ms': null,
        'created_ms': now,
        'updated_ms': now,
      });
      await _insertAssetEvent(
        txn,
        assetId: assetId,
        type: AssetEventType.createdFromTransaction,
        occurredAt: purchaseDate,
        value: initialValue,
        note: note.trim(),
        metadata: {'transaction_id': transactionId},
      );
      await _insertAssetValuation(
        txn,
        assetId: assetId,
        value: initialValue,
        source: AssetValueSource.purchase,
        valuedAt: purchaseDate,
        note: '初始当前价值',
      );
      await _insertAssetTransactionLink(
        txn,
        assetId: assetId,
        transactionId: transactionId,
        type: AssetTransactionLinkType.sourceTransaction,
        amount: budgetDecimalFromCents(allocatedGrossCents)!,
        allocatedGrossCents: allocatedGrossCents,
        allocatedRefundCents: allocatedRefundCents,
        costQuality: AssetAllocationCostQuality.partial,
        note: '从已有账单分配',
      );
      final linkId = Sqflite.firstIntValue(await txn.rawQuery('''
        SELECT id FROM asset_transaction_links
        WHERE asset_object_type = 'physical'
          AND asset_id = ? AND transaction_id = ?
          AND link_type = 'source_transaction'
        LIMIT 1
      ''', [assetId, transactionId]));
      if (linkId == null) throw StateError('保存物品账单关联失败');
      await _allocateHistoricalRefundsToLink(
        txn,
        transactionId: transactionId,
        linkId: linkId,
        requestedCents: allocatedRefundCents,
      );
      await _refreshOrderAllocationQuality(txn, transactionId);
      await _syncAssetPurchasePriceCache(txn, [assetId]);
    });
    await _loadPhysicalAssetData();
    notifyListeners();
    return assetId;
  }

  Future<int> addPhysicalAsset({
    required String name,
    AssetType assetType = AssetType.other,
    required Decimal currentValue,
    Decimal? purchasePrice,
    String currencyCode = 'CNY',
    PhysicalAssetSourceType sourceType =
        PhysicalAssetSourceType.historicalExisting,
    PhysicalAssetStatus status = PhysicalAssetStatus.active,
    DateTime? purchaseDate,
    String brand = '',
    String model = '',
    String location = '',
    DateTime? warrantyUntil,
    String note = '',
    bool includeInNetWorth = true,
    int? sourceTransactionId,
    int? paymentAccountId,
    int? purchaseCategoryId,
    DateTime? occurredAt,
    bool purchasePriceKnown = true,
  }) async {
    final trimmedName = name.trim();
    final normalizedCurrency = currencyCode.trim().toUpperCase();
    final initialPrice =
        purchasePriceKnown ? (purchasePrice ?? currentValue) : Decimal.zero;
    if (trimmedName.isEmpty) throw ArgumentError('资产名称不能为空');
    if (currentValue < Decimal.zero || initialPrice < Decimal.zero) {
      throw ArgumentError('资产金额不能为负');
    }
    if (normalizedCurrency != 'CNY') {
      throw UnsupportedError('当前版本仅支持新增人民币资产。');
    }
    if (!status.canCountInNetWorth) {
      throw ArgumentError('新增资产只能从使用中或闲置状态开始');
    }
    if (sourceType == PhysicalAssetSourceType.newPurchaseWithAccount &&
        paymentAccountId == null) {
      throw ArgumentError('新购买资产必须选择付款账户');
    }
    if (sourceType == PhysicalAssetSourceType.newPurchaseWithAccount &&
        purchaseDate == null) {
      throw ArgumentError('新购买资产必须明确购买日期');
    }
    if (sourceType == PhysicalAssetSourceType.fromTransaction &&
        sourceTransactionId == null) {
      throw ArgumentError('从已有账单加入资产必须提供账单 ID');
    }
    if (!purchasePriceKnown &&
        (sourceType == PhysicalAssetSourceType.newPurchaseWithAccount ||
            sourceType == PhysicalAssetSourceType.fromTransaction)) {
      throw ArgumentError('账单来源的物品不能把购置成本标记为未知');
    }

    final now = DateTime.now();
    var effectivePurchaseDate = purchaseDate;
    var eventAt = sourceType == PhysicalAssetSourceType.newPurchaseWithAccount
        ? purchaseDate!
        : occurredAt ?? effectivePurchaseDate ?? now;
    late int assetId;

    await _db!.transaction((txn) async {
      int? linkedTransactionId;
      var linkedAmount = initialPrice;
      if (sourceType == PhysicalAssetSourceType.newPurchaseWithAccount) {
        if (initialPrice <= Decimal.zero) {
          throw ArgumentError('新购买资产的购买价必须大于 0');
        }
        final account = _accounts
            .where((item) => item.id == paymentAccountId && !item.isDeleted)
            .firstOrNull;
        if (account == null || account.currencyCode != 'CNY') {
          throw ArgumentError('付款账户不存在或币种不受支持');
        }
        linkedTransactionId = await txn.insert('transactions', {
          'book_id': _currentBookId,
          'kind': TransactionKind.expense.toJson(),
          'amount': initialPrice.toString(),
          'currency_code': normalizedCurrency,
          'category_id': purchaseCategoryId,
          'account_id': paymentAccountId,
          'to_account_id': null,
          'note': note.trim().isEmpty ? name : note.trim(),
          'date_ms': eventAt.millisecondsSinceEpoch,
          'time_precision': TransactionTimePrecision.dateOnly.storageKey,
          'tags': '',
          'reimbursable': 0,
          'image_path': '',
          'excluded': 0,
          ..._settlementFields(
            settledAt: eventAt,
            settlementAccountId: paymentAccountId!,
            eventType: TransactionEventType.assetPurchase,
          ),
          ..._syncStampNew(),
        });
        linkedAmount = initialPrice;
      } else if (sourceType == PhysicalAssetSourceType.fromTransaction) {
        final sourceRows = await txn.query(
          'transactions',
          columns: [
            'book_id',
            'kind',
            'amount',
            'currency_code',
            'refund_of',
            'date_ms',
          ],
          where: 'id = ?',
          whereArgs: [sourceTransactionId],
          limit: 1,
        );
        if (sourceRows.isEmpty) throw ArgumentError('关联账单不存在');
        final source = sourceRows.first;
        final sourceAmount =
            Decimal.tryParse(source['amount'] as String? ?? '') ?? Decimal.zero;
        if (source['book_id'] != _currentBookId ||
            source['kind'] != TransactionKind.expense.toJson() ||
            source['refund_of'] != null ||
            sourceAmount <= Decimal.zero ||
            source['currency_code'] != 'CNY') {
          throw ArgumentError('只能关联当前账本中的人民币支出账单');
        }
        linkedTransactionId = sourceTransactionId;
        linkedAmount = sourceAmount;
        effectivePurchaseDate = DateTime.fromMillisecondsSinceEpoch(
          source['date_ms'] as int,
        );
        eventAt = effectivePurchaseDate!;
      }

      if (warrantyUntil != null &&
          effectivePurchaseDate != null &&
          _assetDayIsBefore(warrantyUntil, effectivePurchaseDate!)) {
        throw ArgumentError('保修到期日不能早于购买日期');
      }

      if (linkedTransactionId != null) {
        await _validateOrderAllocations(
          txn,
          linkedTransactionId,
          proposed: AssetAllocationLine(
            assetId: -1,
            grossCents: decimalToBudgetCents(linkedAmount).abs(),
            refundCents: 0,
          ),
        );
      }

      final createdMs = now.millisecondsSinceEpoch;
      final usageStatus = status == PhysicalAssetStatus.idle
          ? PhysicalAssetUsageStatus.idle
          : PhysicalAssetUsageStatus.active;
      assetId = await txn.insert('physical_assets', {
        'uuid': _newUuid(),
        'book_id': _currentBookId,
        'name': trimmedName,
        'asset_type': assetType.storageKey,
        'status': status.storageKey,
        'economic_status': PhysicalAssetEconomicStatus.owned.storageKey,
        'usage_status': usageStatus.storageKey,
        'visibility_status': AssetVisibilityStatus.active.storageKey,
        'inclusion_quality': AssetInclusionQuality.confirmed.storageKey,
        'source_type': sourceType.storageKey,
        'acquisition_cost_source': linkedTransactionId == null
            ? (purchasePriceKnown
                ? AssetAcquisitionCostSource.manual.storageKey
                : AssetAcquisitionCostSource.manualUnknown.storageKey)
            : AssetAcquisitionCostSource.transactionAllocations.storageKey,
        'purchase_price': initialPrice.toString(),
        'current_value': currentValue.toString(),
        'currency_code': normalizedCurrency,
        'purchase_date_ms': effectivePurchaseDate?.millisecondsSinceEpoch,
        'brand': brand.trim(),
        'model': model.trim(),
        'location': location.trim(),
        'warranty_until_ms': warrantyUntil?.millisecondsSinceEpoch,
        'photo_path': '',
        'thumbnail_path': '',
        'invoice_path': '',
        'depreciation_method': '',
        'depreciation_base': '0',
        'salvage_value': '0',
        'useful_life_months': 0,
        'depreciation_start_ms': null,
        'depreciation_paused': 0,
        'note': note.trim(),
        'include_in_net_worth': includeInNetWorth ? 1 : 0,
        'is_deleted': 0,
        'ended_ms': null,
        'archived_ms': null,
        'created_ms': createdMs,
        'updated_ms': createdMs,
      });

      await _insertAssetEvent(
        txn,
        assetId: assetId,
        type: _createEventForSource(sourceType),
        occurredAt: eventAt,
        value: currentValue,
        note: note.trim(),
        metadata: {'source_type': sourceType.storageKey},
      );
      await _insertAssetValuation(
        txn,
        assetId: assetId,
        value: currentValue,
        source: _initialValueSourceFor(sourceType),
        valuedAt: eventAt,
        note: '初始当前价值',
      );
      if (linkedTransactionId != null) {
        await _insertAssetTransactionLink(
          txn,
          assetId: assetId,
          transactionId: linkedTransactionId,
          type: sourceType == PhysicalAssetSourceType.fromTransaction
              ? AssetTransactionLinkType.sourceTransaction
              : AssetTransactionLinkType.purchaseTransaction,
          amount: linkedAmount,
          note: sourceType.label,
        );
        await _autoAllocateAllRefundsForSingleFullLink(
          txn,
          linkedTransactionId,
        );
      }
    });

    await _loadTransactions();
    await _loadPhysicalAssetData();
    notifyListeners();
    return assetId;
  }

  Future<void> updatePhysicalAsset({
    required int id,
    required String name,
    required AssetType assetType,
    required Decimal purchasePrice,
    required Decimal currentValue,
    required String currencyCode,
    required PhysicalAssetStatus status,
    DateTime? purchaseDate,
    bool clearPurchaseDate = false,
    String brand = '',
    String model = '',
    String location = '',
    DateTime? warrantyUntil,
    bool clearWarrantyUntil = false,
    String note = '',
    required bool includeInNetWorth,
    bool? purchasePriceKnown,
  }) async {
    final existing =
        _allPhysicalAssets.where((asset) => asset.id == id).firstOrNull;
    if (existing == null) throw StateError('资产不存在');
    if (name.trim().isEmpty) throw ArgumentError('资产名称不能为空');
    if (purchasePrice < Decimal.zero || currentValue < Decimal.zero) {
      throw ArgumentError('资产金额不能为负');
    }
    if (currencyCode.trim().toUpperCase() != existing.currencyCode) {
      throw UnsupportedError('当前版本不能转换资产币种。');
    }
    if (clearPurchaseDate && purchaseDate != null) {
      throw ArgumentError('清空购买日期时不能同时提供新日期');
    }
    if (clearWarrantyUntil && warrantyUntil != null) {
      throw ArgumentError('清空保修日期时不能同时提供新日期');
    }
    final editingArchivedShadow =
        status == PhysicalAssetStatus.archived && existing.isArchived;
    if (!editingArchivedShadow &&
        (!existing.economicStatus.ownsValue || !status.canCountInNetWorth)) {
      throw StateError('出售、报废、丢失、赠送和归档必须从资产详情执行。');
    }
    if (!existing.economicStatus.ownsValue &&
        currentValue != existing.currentValue) {
      throw StateError('已结束资产不能通过普通编辑修改价值。');
    }
    final usageStatus = editingArchivedShadow
        ? existing.usageStatus
        : status == PhysicalAssetStatus.idle
            ? PhysicalAssetUsageStatus.idle
            : PhysicalAssetUsageStatus.active;
    final legacyStatus = _legacyPhysicalStatusFor(
      economicStatus: existing.economicStatus,
      usageStatus: usageStatus,
      visibilityStatus: existing.visibilityStatus,
    );
    final allocatedCost = existing.acquisitionCostSource ==
        AssetAcquisitionCostSource.transactionAllocations;
    if (allocatedCost && purchasePriceKnown != null) {
      throw StateError('账单分配成本不能改成手工成本口径');
    }
    int? canonicalPurchaseDateMs;
    if (allocatedCost) {
      final purchaseLinks = transactionLinksForAsset(id)
          .where((link) =>
              link.assetObjectType == AssetObjectType.physical &&
              (link.linkType == AssetTransactionLinkType.sourceTransaction ||
                  link.linkType ==
                      AssetTransactionLinkType.purchaseTransaction))
          .toList(growable: false);
      final purchaseTransactions = purchaseLinks
          .map((link) => transactionById(link.transactionId))
          .whereType<TransactionEntity>()
          .toList(growable: false);
      if (purchaseLinks.isEmpty ||
          purchaseTransactions.length != purchaseLinks.length) {
        throw StateError('账单分配来源物品缺少有效购置账单关联');
      }
      canonicalPurchaseDateMs = purchaseTransactions
          .map((transaction) => transaction.dateMs)
          .reduce(min);
      final canonicalPurchaseDate =
          DateTime.fromMillisecondsSinceEpoch(canonicalPurchaseDateMs);
      if (clearPurchaseDate) {
        throw StateError('账单来源物品不能清空购买日期');
      }
      if (purchaseDate != null &&
          !_sameAssetCalendarDay(purchaseDate, canonicalPurchaseDate)) {
        throw StateError('账单来源物品的购买日期必须与原账单一致');
      }
    }
    final nextPurchaseDate = allocatedCost
        ? DateTime.fromMillisecondsSinceEpoch(canonicalPurchaseDateMs!)
        : clearPurchaseDate
            ? null
            : purchaseDate ?? existing.purchaseDate;
    final nextWarrantyUntil =
        clearWarrantyUntil ? null : warrantyUntil ?? existing.warrantyUntil;
    if (nextPurchaseDate != null &&
        nextWarrantyUntil != null &&
        _assetDayIsBefore(nextWarrantyUntil, nextPurchaseDate)) {
      throw ArgumentError('保修到期日不能早于购买日期');
    }
    final scopeChanged = existing.includeInNetWorth != includeInNetWorth;
    if (scopeChanged) {
      await _bumpNetWorthScopeVersion();
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final nextCostSource = allocatedCost
        ? AssetAcquisitionCostSource.transactionAllocations
        : purchasePriceKnown == null
            ? existing.acquisitionCostSource
            : purchasePriceKnown
                ? AssetAcquisitionCostSource.manual
                : AssetAcquisitionCostSource.manualUnknown;
    await _db!.transaction((txn) async {
      await txn.update(
        'physical_assets',
        {
          'name': name.trim(),
          'asset_type': assetType.storageKey,
          'status': legacyStatus.storageKey,
          'economic_status': existing.economicStatus.storageKey,
          'usage_status': usageStatus.storageKey,
          'visibility_status': existing.visibilityStatus.storageKey,
          'acquisition_cost_source': nextCostSource.storageKey,
          'purchase_price': allocatedCost
              ? existing.purchasePrice.toString()
              : nextCostSource == AssetAcquisitionCostSource.manualUnknown
                  ? Decimal.zero.toString()
                  : purchasePrice.toString(),
          'current_value': currentValue.toString(),
          'currency_code': currencyCode,
          'purchase_date_ms': nextPurchaseDate?.millisecondsSinceEpoch,
          'brand': brand.trim(),
          'model': model.trim(),
          'location': location.trim(),
          'warranty_until_ms': nextWarrantyUntil?.millisecondsSinceEpoch,
          'note': note.trim(),
          'include_in_net_worth':
              includeInNetWorth && existing.economicStatus.ownsValue ? 1 : 0,
          'updated_ms': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await _insertAssetEvent(
        txn,
        assetId: id,
        type: AssetEventType.assetEdited,
        occurredAt: DateTime.now(),
        value: currentValue,
        note: '编辑资产资料',
      );
      if (currentValue != existing.currentValue) {
        await _insertAssetValuation(
          txn,
          assetId: id,
          value: currentValue,
          source: AssetValueSource.manual,
          valuedAt: DateTime.now(),
          note: '编辑资产时更新当前价值',
        );
        await txn.update(
          'physical_assets',
          {'depreciation_paused': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      if (allocatedCost) {
        await _syncAssetPurchasePriceCache(txn, [id]);
      }
    });
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<void> updatePhysicalAssetValue(
    int id,
    Decimal value, {
    DateTime? valuedAt,
    String note = '',
  }) async {
    if (value < Decimal.zero) throw ArgumentError('资产当前价值不能为负');
    final asset = _allPhysicalAssets.where((item) => item.id == id).firstOrNull;
    if (asset == null) throw StateError('资产不存在');
    if (!asset.economicStatus.ownsValue) {
      throw StateError('当前资产状态不能更新价值');
    }
    final at = valuedAt ?? DateTime.now();
    await _db!.transaction((txn) async {
      final latestRows = await txn.query(
        'asset_valuations',
        columns: ['valued_at_ms'],
        where: 'asset_id = ?',
        whereArgs: [id],
        orderBy: 'valued_at_ms DESC, id DESC',
        limit: 1,
      );
      final becomesCurrent = latestRows.isEmpty ||
          at.millisecondsSinceEpoch >=
              (latestRows.first['valued_at_ms'] as int? ?? 0);
      await _insertAssetValuation(
        txn,
        assetId: id,
        value: value,
        source: AssetValueSource.manual,
        valuedAt: at,
        note: note,
      );
      await txn.update(
        'physical_assets',
        {
          if (becomesCurrent) 'current_value': value.toString(),
          if (becomesCurrent) 'depreciation_paused': 1,
          'updated_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await _insertAssetEvent(
        txn,
        assetId: id,
        type: AssetEventType.valueUpdated,
        occurredAt: at,
        value: value,
        note: note,
      );
    });
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<void> updatePhysicalAssetEvidence(
    int id, {
    String photoPath = '',
    String? thumbnailPath,
    String invoicePath = '',
    String note = '',
  }) async {
    final now = DateTime.now();
    await _db!.transaction((txn) async {
      await txn.update(
        'physical_assets',
        {
          'photo_path': photoPath.trim(),
          if (thumbnailPath != null) 'thumbnail_path': thumbnailPath.trim(),
          'invoice_path': invoicePath.trim(),
          'updated_ms': now.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await _insertAssetEvent(
        txn,
        assetId: id,
        type: AssetEventType.evidenceUpdated,
        occurredAt: now,
        note: note.trim().isEmpty ? '凭证信息更新' : note.trim(),
      );
    });
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<void> configurePhysicalAssetDepreciation({
    required int id,
    required bool enabled,
    Decimal? depreciationBase,
    Decimal? salvageValue,
    int? usefulLifeMonths,
    DateTime? startAt,
    String note = '',
  }) async {
    final now = DateTime.now();
    final base = depreciationBase ?? Decimal.zero;
    final salvage = salvageValue ?? Decimal.zero;
    final lifeMonths = usefulLifeMonths ?? 0;
    if (enabled) {
      if (base <= Decimal.zero) {
        throw ArgumentError('折旧基准金额必须大于 0');
      }
      if (salvage < Decimal.zero || salvage > base) {
        throw ArgumentError('残值必须在 0 到折旧基准金额之间');
      }
      if (lifeMonths <= 0) {
        throw ArgumentError('使用寿命月份必须大于 0');
      }
      if (startAt == null) {
        throw ArgumentError('开启折旧必须明确开始日期');
      }
    }
    await _db!.transaction((txn) async {
      await txn.update(
        'physical_assets',
        {
          'depreciation_method': enabled ? 'linear' : '',
          'depreciation_base': enabled ? base.toString() : '0',
          'salvage_value': enabled ? salvage.toString() : '0',
          'useful_life_months': enabled ? lifeMonths : 0,
          'depreciation_start_ms':
              enabled ? startAt!.millisecondsSinceEpoch : null,
          'depreciation_paused': 0,
          'updated_ms': now.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await _insertAssetEvent(
        txn,
        assetId: id,
        type: AssetEventType.depreciationConfigured,
        occurredAt: now,
        value: enabled ? base : null,
        note:
            note.trim().isEmpty ? (enabled ? '设置线性折旧' : '关闭自动折旧') : note.trim(),
        metadata: enabled
            ? {
                'method': 'linear',
                'base': base.toString(),
                'salvage_value': salvage.toString(),
                'useful_life_months': lifeMonths,
                'start_ms': startAt!.millisecondsSinceEpoch,
              }
            : {'method': ''},
      );
    });
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<int> applyPhysicalAssetDepreciation({
    DateTime? asOf,
    bool notify = true,
  }) async {
    final at = asOf ?? DateTime.now();
    var changed = 0;
    final candidates = _allPhysicalAssets.where(
      (asset) =>
          !asset.isDeleted &&
          asset.economicStatus.ownsValue &&
          asset.hasLinearDepreciation &&
          !asset.depreciationPaused &&
          asset.depreciationStartMs != null,
    );
    await _db!.transaction((txn) async {
      for (final asset in candidates) {
        final start = asset.depreciationStartDate;
        if (start == null || at.isBefore(start)) continue;
        final latestValuation = await txn.query(
          'asset_valuations',
          columns: ['valued_at_ms'],
          where: 'asset_id = ?',
          whereArgs: [asset.id],
          orderBy: 'valued_at_ms DESC, id DESC',
          limit: 1,
        );
        if (latestValuation.isNotEmpty &&
            at.millisecondsSinceEpoch <
                (latestValuation.first['valued_at_ms'] as int? ?? 0)) {
          continue;
        }
        final elapsedMonths = _wholeMonthsBetween(start, at)
            .clamp(0, asset.usefulLifeMonths)
            .toInt();
        final depreciable = asset.depreciationBase - asset.salvageValue;
        if (elapsedMonths <= 0 || depreciable <= Decimal.zero) continue;
        final monthly = (depreciable / Decimal.fromInt(asset.usefulLifeMonths))
            .toDecimal(scaleOnInfinitePrecision: 8);
        final nextRaw =
            asset.depreciationBase - (monthly * Decimal.fromInt(elapsedMonths));
        final nextValue =
            nextRaw < asset.salvageValue ? asset.salvageValue : nextRaw;
        if (nextValue == asset.currentValue) continue;
        await txn.update(
          'physical_assets',
          {
            'current_value': nextValue.toString(),
            'updated_ms': at.millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [asset.id],
        );
        await _insertAssetValuation(
          txn,
          assetId: asset.id,
          value: nextValue,
          source: AssetValueSource.autoDepreciation,
          valuedAt: at,
          note: '线性折旧自动更新',
        );
        await _insertAssetEvent(
          txn,
          assetId: asset.id,
          type: AssetEventType.autoDepreciationApplied,
          occurredAt: at,
          value: nextValue,
          note: '线性折旧自动更新',
          metadata: {
            'elapsed_months': elapsedMonths,
            'base': asset.depreciationBase.toString(),
            'salvage_value': asset.salvageValue.toString(),
          },
        );
        changed++;
      }
    });
    if (changed > 0) {
      await _loadPhysicalAssetData(refreshSnapshot: notify);
      if (notify) notifyListeners();
    }
    return changed;
  }

  static int _wholeMonthsBetween(DateTime start, DateTime end) {
    var months = (end.year - start.year) * 12 + end.month - start.month;
    if (end.day < start.day) months--;
    return max(0, months);
  }

  Future<void> returnPhysicalAsset({
    required int assetId,
    DateTime? returnedAt,
    String note = '',
  }) async {
    final resolved = physicalAssetAcquisitionCost(assetId);
    if (!resolved.isExact || resolved.amount != Decimal.zero) {
      throw StateError('只有已精确分配且净购置成本为 0 的物品可以确认退货');
    }
    final at = returnedAt ?? DateTime.now();
    await _db!.transaction((txn) async {
      final rows = await txn.query(
        'physical_assets',
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [assetId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('物品不存在');
      final asset = PhysicalAssetEntity.fromMap(rows.first);
      if (!asset.economicStatus.ownsValue) {
        throw StateError('只有仍持有的物品可以确认退货');
      }
      await txn.update(
        'physical_assets',
        {
          'status': _legacyPhysicalStatusFor(
            economicStatus: PhysicalAssetEconomicStatus.returned,
            usageStatus: asset.usageStatus,
            visibilityStatus: asset.visibilityStatus,
          ).storageKey,
          'economic_status': PhysicalAssetEconomicStatus.returned.storageKey,
          'current_value': '0',
          'include_in_net_worth': 0,
          'ended_ms': at.millisecondsSinceEpoch,
          'updated_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [assetId],
      );
      await _insertAssetValuation(
        txn,
        assetId: assetId,
        value: Decimal.zero,
        source: AssetValueSource.statusZero,
        valuedAt: at,
        note: '退货后价值归零',
      );
      await _insertAssetEvent(
        txn,
        assetId: assetId,
        type: AssetEventType.assetReturned,
        occurredAt: at,
        note: note.trim(),
        metadata: {
          'previous_current_value': asset.currentValue.toString(),
          'previous_include_in_net_worth': asset.includeInNetWorth,
          'previous_ended_ms': asset.endedMs,
          'previous_usage_status': asset.usageStatus.storageKey,
          'previous_visibility_status': asset.visibilityStatus.storageKey,
          'previous_inclusion_quality': asset.inclusionQuality.storageKey,
        },
      );
    });
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<void> undoPhysicalAssetReturn(int assetId) async {
    await _db!.transaction((txn) async {
      final rows = await txn.query(
        'physical_assets',
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [assetId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('物品不存在');
      final asset = PhysicalAssetEntity.fromMap(rows.first);
      if (asset.economicStatus != PhysicalAssetEconomicStatus.returned) {
        throw StateError('只有已退货物品可以撤销退货');
      }
      final events = await txn.query(
        'asset_events',
        where: "asset_type = 'physical' AND asset_id = ? AND event_type = ?",
        whereArgs: [assetId, AssetEventType.assetReturned.storageKey],
        orderBy: 'occurred_ms DESC, id DESC',
        limit: 1,
      );
      if (events.isEmpty) throw StateError('缺少可撤销的退货事件');
      final metadata = _assetEventMetadata(
        events.first['metadata'] as String? ?? '',
      );
      final value = Decimal.tryParse(
            metadata['previous_current_value']?.toString() ?? '',
          ) ??
          Decimal.zero;
      final usage = PhysicalAssetUsageStatusX.fromStorage(
        metadata['previous_usage_status']?.toString(),
      );
      final visibility = AssetVisibilityStatusX.fromStorage(
        metadata['previous_visibility_status']?.toString(),
      );
      final inclusion = AssetInclusionQualityX.fromStorage(
        metadata['previous_inclusion_quality']?.toString(),
      );
      final include = metadata['previous_include_in_net_worth'] is bool
          ? metadata['previous_include_in_net_worth'] as bool
          : true;
      await txn.update(
        'physical_assets',
        {
          'status': _legacyPhysicalStatusFor(
            economicStatus: PhysicalAssetEconomicStatus.owned,
            usageStatus: usage,
            visibilityStatus: visibility,
          ).storageKey,
          'economic_status': PhysicalAssetEconomicStatus.owned.storageKey,
          'usage_status': usage.storageKey,
          'visibility_status': visibility.storageKey,
          'inclusion_quality': inclusion.storageKey,
          'current_value': value.toString(),
          'include_in_net_worth': include ? 1 : 0,
          'ended_ms': int.tryParse(
            metadata['previous_ended_ms']?.toString() ?? '',
          ),
          'updated_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [assetId],
      );
      await _insertAssetValuation(
        txn,
        assetId: assetId,
        value: value,
        source: AssetValueSource.manual,
        valuedAt: DateTime.now(),
        note: '撤销退货，恢复退货前价值',
      );
      await _insertAssetEvent(
        txn,
        assetId: assetId,
        type: AssetEventType.assetReturnUndone,
        occurredAt: DateTime.now(),
        value: value,
        note: '撤销退货',
      );
    });
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<void> sellPhysicalAsset({
    required int id,
    required Decimal saleAmount,
    Decimal? saleFee,
    int? accountId,
    DateTime? soldAt,
    String note = '',
  }) async {
    final fee = saleFee ?? Decimal.zero;
    if (saleAmount < Decimal.zero || fee < Decimal.zero || fee > saleAmount) {
      throw ArgumentError('成交价和出售费用不合法');
    }
    final netProceeds = saleAmount - fee;
    final at = soldAt ?? DateTime.now();
    final timePrecision = soldAt == null
        ? TransactionTimePrecision.exact
        : TransactionTimePrecision.dateOnly;
    await _db!.transaction((txn) async {
      final rows = await txn.query(
        'physical_assets',
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('资产不存在');
      final asset = PhysicalAssetEntity.fromMap(rows.first);
      if (!asset.economicStatus.ownsValue) {
        throw StateError('当前资产状态不能出售');
      }
      if (asset.currencyCode != 'CNY') {
        throw UnsupportedError('当前版本暂不支持外币资产出售入账。');
      }
      if (accountId != null &&
          !_accounts.any((account) =>
              account.id == accountId &&
              !account.isDeleted &&
              account.currencyCode == 'CNY')) {
        throw ArgumentError('收款账户不存在或币种不受支持');
      }
      int? transactionId;
      if (accountId != null && netProceeds > Decimal.zero) {
        transactionId = await txn.insert('transactions', {
          'book_id': asset.bookId ?? _currentBookId,
          'kind': TransactionKind.income.toJson(),
          'amount': netProceeds.toString(),
          'currency_code': asset.currencyCode,
          'category_id': null,
          'account_id': accountId,
          'to_account_id': null,
          'note': note.trim().isEmpty ? '资产出售：${asset.name}' : note.trim(),
          'date_ms': at.millisecondsSinceEpoch,
          'time_precision': timePrecision.storageKey,
          'tags': '',
          'reimbursable': 0,
          'image_path': '',
          'excluded': 1,
          ..._settlementFields(
            settledAt: at,
            settlementAccountId: accountId,
            eventType: TransactionEventType.assetSale,
          ),
          ..._syncStampNew(),
        });
      }
      await txn.update(
        'physical_assets',
        {
          'status': _legacyPhysicalStatusFor(
            economicStatus: PhysicalAssetEconomicStatus.sold,
            usageStatus: asset.usageStatus,
            visibilityStatus: asset.visibilityStatus,
          ).storageKey,
          'economic_status': PhysicalAssetEconomicStatus.sold.storageKey,
          'current_value': '0',
          'include_in_net_worth': 0,
          'ended_ms': at.millisecondsSinceEpoch,
          'updated_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await _insertAssetValuation(
        txn,
        assetId: id,
        value: Decimal.zero,
        source: AssetValueSource.sale,
        valuedAt: at,
        note: note.trim(),
      );
      await _insertAssetEvent(
        txn,
        assetId: id,
        type: AssetEventType.assetSold,
        occurredAt: at,
        value: netProceeds,
        note: note.trim(),
        metadata: {
          'gross_sale_amount': saleAmount.toString(),
          'sale_fee': fee.toString(),
          'net_proceeds': netProceeds.toString(),
          'previous_value': asset.currentValue.toString(),
          'previous_status': asset.status.storageKey,
          'previous_economic_status': asset.economicStatus.storageKey,
          'previous_usage_status': asset.usageStatus.storageKey,
          'previous_visibility_status': asset.visibilityStatus.storageKey,
          'previous_inclusion_quality': asset.inclusionQuality.storageKey,
          'previous_ended_ms': asset.endedMs,
          'previous_include_in_net_worth': asset.includeInNetWorth,
          if (transactionId != null) 'transaction_id': transactionId,
        },
      );
      if (transactionId != null) {
        await _insertAssetTransactionLink(
          txn,
          assetId: id,
          transactionId: transactionId,
          type: AssetTransactionLinkType.saleAccountMovement,
          amount: netProceeds,
          note: '出售入账，不计入普通收入',
        );
      }
    });
    await _loadTransactions();
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<void> undoPhysicalAssetSale(int id) async {
    await _db!.transaction((txn) async {
      final assetRows = await txn.query(
        'physical_assets',
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [id],
        limit: 1,
      );
      if (assetRows.isEmpty) throw StateError('资产不存在');
      final asset = PhysicalAssetEntity.fromMap(assetRows.first);
      if (asset.economicStatus != PhysicalAssetEconomicStatus.sold) {
        throw StateError('只有已出售资产可以撤销出售');
      }
      final eventRows = await txn.query(
        'asset_events',
        where: "asset_type = 'physical' AND asset_id = ? AND event_type = ?",
        whereArgs: [id, AssetEventType.assetSold.storageKey],
        orderBy: 'occurred_ms DESC, id DESC',
        limit: 1,
      );
      final metadata = eventRows.isEmpty
          ? const <String, dynamic>{}
          : _assetEventMetadata(eventRows.first['metadata'] as String? ?? '');
      var previousValue =
          Decimal.tryParse(metadata['previous_value']?.toString() ?? '');
      if (previousValue == null) {
        final valuationRows = await txn.query(
          'asset_valuations',
          columns: ['value'],
          where: 'asset_id = ? AND source <> ?',
          whereArgs: [id, AssetValueSource.sale.storageKey],
          orderBy: 'valued_at_ms DESC, id DESC',
          limit: 1,
        );
        previousValue = valuationRows.isEmpty
            ? Decimal.zero
            : Decimal.tryParse(valuationRows.first['value'] as String? ?? '') ??
                Decimal.zero;
      }
      final previousStatus = PhysicalAssetStatusX.fromStorage(
        metadata['previous_status']?.toString(),
      );
      final restoredEconomic = metadata.containsKey('previous_economic_status')
          ? PhysicalAssetEconomicStatusX.fromStorage(
              metadata['previous_economic_status']?.toString(),
            )
          : _physicalEconomicFromLegacyStatus(previousStatus);
      final restoredUsage = metadata.containsKey('previous_usage_status')
          ? PhysicalAssetUsageStatusX.fromStorage(
              metadata['previous_usage_status']?.toString(),
            )
          : _physicalUsageFromLegacyStatus(previousStatus);
      final restoredVisibility =
          metadata.containsKey('previous_visibility_status')
              ? AssetVisibilityStatusX.fromStorage(
                  metadata['previous_visibility_status']?.toString(),
                )
              : previousStatus == PhysicalAssetStatus.archived
                  ? AssetVisibilityStatus.archived
                  : AssetVisibilityStatus.active;
      final restoredQuality = metadata.containsKey('previous_inclusion_quality')
          ? AssetInclusionQualityX.fromStorage(
              metadata['previous_inclusion_quality']?.toString(),
            )
          : AssetInclusionQuality.confirmed;
      final restoredStatus = _legacyPhysicalStatusFor(
        economicStatus: restoredEconomic,
        usageStatus: restoredUsage,
        visibilityStatus: restoredVisibility,
      );
      final previousIncluded = metadata['previous_include_in_net_worth'] is bool
          ? metadata['previous_include_in_net_worth'] as bool
          : true;
      final saleLinks = await txn.query(
        'asset_transaction_links',
        where: 'asset_id = ? AND link_type = ?',
        whereArgs: [
          id,
          AssetTransactionLinkType.saleAccountMovement.storageKey
        ],
        orderBy: 'created_ms DESC, id DESC',
        limit: 1,
      );
      if (saleLinks.isNotEmpty) {
        final transactionId = saleLinks.first['transaction_id'] as int;
        await txn.delete('asset_transaction_links',
            where: 'id = ?', whereArgs: [saleLinks.first['id']]);
        await txn.delete('transactions',
            where: 'id = ? OR refund_of = ?',
            whereArgs: [transactionId, transactionId]);
      }
      await txn.update(
        'physical_assets',
        {
          'status': restoredStatus.storageKey,
          'economic_status': restoredEconomic.storageKey,
          'usage_status': restoredUsage.storageKey,
          'visibility_status': restoredVisibility.storageKey,
          'inclusion_quality': restoredQuality.storageKey,
          'current_value': previousValue.toString(),
          'include_in_net_worth': previousIncluded ? 1 : 0,
          'ended_ms': int.tryParse(
            metadata['previous_ended_ms']?.toString() ?? '',
          ),
          'updated_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await _insertAssetValuation(
        txn,
        assetId: id,
        value: previousValue,
        source: AssetValueSource.manual,
        valuedAt: DateTime.now(),
        note: '撤销出售，恢复出售前价值',
      );
      await _insertAssetEvent(
        txn,
        assetId: id,
        type: AssetEventType.assetSaleUndone,
        occurredAt: DateTime.now(),
        value: previousValue,
        note: '撤销出售',
      );
    });
    await _loadTransactions();
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<void> unlinkPhysicalAssetTransaction({
    required int assetId,
    required int transactionId,
  }) async {
    await _db!.transaction((txn) async {
      final links = await txn.query(
        'asset_transaction_links',
        where: 'asset_id = ? AND transaction_id = ?',
        whereArgs: [assetId, transactionId],
        limit: 1,
      );
      if (links.isEmpty) throw StateError('资产账单关联不存在');
      final type = AssetTransactionLinkTypeX.fromStorage(
        links.first['link_type'] as String?,
      );
      if (type == AssetTransactionLinkType.saleAccountMovement) {
        throw StateError('出售流水必须通过撤销出售解除');
      }
      if (type.isAdditionalCost) {
        await txn.delete(
          'asset_transaction_links',
          where: 'id = ?',
          whereArgs: [links.first['id']],
        );
        await _insertAssetEvent(
          txn,
          assetId: assetId,
          type: AssetEventType.assetCostUnlinked,
          occurredAt: DateTime.now(),
          note: '解除${type.label} · 交易 #$transactionId',
          metadata: {
            'transaction_id': transactionId,
            'link_type': type.storageKey,
          },
        );
        return;
      }
      final assetRows = await txn.query(
        'physical_assets',
        columns: ['economic_status'],
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [assetId],
        limit: 1,
      );
      if (assetRows.isEmpty) throw StateError('物品不存在');
      if (assetRows.first['economic_status'] ==
          PhysicalAssetEconomicStatus.returned.storageKey) {
        throw StateError('已确认退货的物品请先撤销退货，再解除账单关联');
      }
      final link = links.first;
      final preservedNetCents = (link['allocated_gross_cents'] as int? ?? 0) -
          (link['allocated_refund_cents'] as int? ?? 0);
      await txn.update(
        'asset_refund_allocations',
        {
          'status': 'reversed',
          'updated_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: "asset_transaction_link_id = ? AND status = 'active'",
        whereArgs: [link['id']],
      );
      await txn.delete('asset_transaction_links',
          where: 'id = ?', whereArgs: [link['id']]);
      await _refreshOrderAllocationQuality(txn, transactionId);
      final remainingLinks = await txn.query(
        'asset_transaction_links',
        columns: ['id'],
        where:
            "asset_object_type = 'physical' AND asset_id = ? AND link_type IN ('source_transaction', 'purchase_transaction')",
        whereArgs: [assetId],
      );
      if (remainingLinks.isEmpty) {
        await txn.update(
          'physical_assets',
          {
            'source_type':
                PhysicalAssetSourceType.historicalExisting.storageKey,
            'purchase_price':
                budgetDecimalFromCents(preservedNetCents).toString(),
            'acquisition_cost_source':
                AssetAcquisitionCostSource.manual.storageKey,
            'updated_ms': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [assetId],
        );
      } else {
        await _syncAssetPurchasePriceCache(txn, [assetId]);
      }
      await _insertAssetEvent(
        txn,
        assetId: assetId,
        type: AssetEventType.assetTransactionUnlinked,
        occurredAt: DateTime.now(),
        note: '解除交易 #$transactionId 的关联',
      );
    });
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<void> setPhysicalAssetUsageTracking(
    int assetId, {
    required bool enabled,
  }) async {
    final asset = physicalAssetDetailById(assetId);
    if (asset == null || asset.isDeleted) throw StateError('物品不存在');
    if (asset.usageTrackingEnabled == enabled) return;
    final now = DateTime.now();
    await _db!.transaction((txn) async {
      await txn.update(
        'physical_assets',
        {
          'usage_tracking_enabled': enabled ? 1 : 0,
          'updated_ms': now.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [assetId],
      );
      await _insertAssetEvent(
        txn,
        assetId: assetId,
        type: enabled
            ? AssetEventType.assetUsageTrackingEnabled
            : AssetEventType.assetUsageTrackingDisabled,
        occurredAt: now,
      );
    });
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<int> recordPhysicalAssetUsage(
    int assetId, {
    int count = 1,
    DateTime? occurredAt,
    String note = '',
  }) async {
    final asset = physicalAssetDetailById(assetId);
    if (asset == null || asset.isDeleted) throw StateError('物品不存在');
    if (!asset.usageTrackingEnabled) {
      throw StateError('请先开启使用次数');
    }
    if (!asset.isOwned) throw StateError('已结束持有的物品不能再记录使用');
    if (count <= 0) throw ArgumentError('使用次数必须大于 0');
    final now = DateTime.now();
    final effectiveAt = occurredAt ?? now;
    final id = await _db!.insert('asset_usage_events', {
      'uuid': _newUuid(),
      'asset_id': assetId,
      'count_delta': count,
      'reversal_of': null,
      'occurred_ms': effectiveAt.millisecondsSinceEpoch,
      'note': note.trim(),
      'created_ms': now.millisecondsSinceEpoch,
      'updated_ms': now.millisecondsSinceEpoch,
    });
    await _loadAssetUsageEvents();
    notifyListeners();
    return id;
  }

  Future<void> undoLatestPhysicalAssetUsage(int assetId) async {
    final asset = physicalAssetDetailById(assetId);
    if (asset == null || asset.isDeleted) throw StateError('物品不存在');
    final now = DateTime.now();
    await _db!.transaction((txn) async {
      final targets = await txn.rawQuery('''
        SELECT original.id
        FROM asset_usage_events original
        WHERE original.asset_id = ?
          AND original.reversal_of IS NULL
          AND original.count_delta > 0
          AND NOT EXISTS (
            SELECT 1
            FROM asset_usage_events reversal
            WHERE reversal.reversal_of = original.id
          )
        ORDER BY original.occurred_ms DESC, original.id DESC
        LIMIT 1
      ''', [assetId]);
      if (targets.isEmpty) throw StateError('没有可撤销的使用记录');
      final targetId = targets.single['id'] as int;
      await txn.insert(
        'asset_usage_events',
        {
          'uuid': _newUuid(),
          'asset_id': assetId,
          'count_delta': 0,
          'reversal_of': targetId,
          'occurred_ms': now.millisecondsSinceEpoch,
          'note': '撤销使用记录 #$targetId',
          'created_ms': now.millisecondsSinceEpoch,
          'updated_ms': now.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    });
    await _loadAssetUsageEvents();
    notifyListeners();
  }

  Future<void> setPhysicalAssetSavingsGoal(
    int assetId,
    int? savingsGoalId,
  ) async {
    final asset = physicalAssetDetailById(assetId);
    if (asset == null || asset.isDeleted) throw StateError('物品不存在');
    if (savingsGoalId != null && savingsGoalById(savingsGoalId) == null) {
      throw StateError('存钱目标不存在');
    }
    if (asset.savingsGoalId == savingsGoalId) return;
    final now = DateTime.now();
    await _db!.transaction((txn) async {
      await txn.update(
        'physical_assets',
        {
          'savings_goal_id': savingsGoalId,
          'updated_ms': now.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [assetId],
      );
      await _insertAssetEvent(
        txn,
        assetId: assetId,
        type: savingsGoalId == null
            ? AssetEventType.assetSavingsGoalUnlinked
            : AssetEventType.assetSavingsGoalLinked,
        occurredAt: now,
        note: savingsGoalId == null
            ? '解除存钱目标'
            : '关联存钱目标：${savingsGoalById(savingsGoalId)?.name ?? ''}',
        metadata: {
          'previous_savings_goal_id': asset.savingsGoalId,
          'savings_goal_id': savingsGoalId,
        },
      );
    });
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<void> setPhysicalAssetStatus({
    required int id,
    required PhysicalAssetStatus status,
    DateTime? occurredAt,
    String note = '',
    bool? includeInNetWorth,
  }) async {
    if (status == PhysicalAssetStatus.sold) {
      throw StateError('出售资产必须使用出售流程。');
    }
    final asset = _allPhysicalAssets.where((item) => item.id == id).firstOrNull;
    if (asset == null) throw StateError('资产不存在');
    if (status == PhysicalAssetStatus.archived) {
      await archivePhysicalAsset(id, note: note);
      return;
    }
    final at = occurredAt ?? DateTime.now();
    if (!asset.economicStatus.ownsValue) {
      throw StateError('终止状态的资产不能直接改状态。');
    }
    final usageChange = status == PhysicalAssetStatus.active ||
        status == PhysicalAssetStatus.idle;
    final nextUsage = usageChange
        ? status == PhysicalAssetStatus.idle
            ? PhysicalAssetUsageStatus.idle
            : PhysicalAssetUsageStatus.active
        : asset.usageStatus;
    final nextEconomic = switch (status) {
      PhysicalAssetStatus.disposed => PhysicalAssetEconomicStatus.scrapped,
      PhysicalAssetStatus.lost => PhysicalAssetEconomicStatus.lost,
      PhysicalAssetStatus.gifted => PhysicalAssetEconomicStatus.gifted,
      _ => asset.economicStatus,
    };
    final eventType = switch (status) {
      PhysicalAssetStatus.disposed => AssetEventType.assetDisposed,
      PhysicalAssetStatus.lost => AssetEventType.assetLost,
      PhysicalAssetStatus.gifted => AssetEventType.assetGifted,
      _ => AssetEventType.assetEdited,
    };
    final economicTermination = !nextEconomic.ownsValue;
    if (!economicTermination &&
        includeInNetWorth != null &&
        includeInNetWorth != asset.includeInNetWorth) {
      await _bumpNetWorthScopeVersion();
    }
    final legacyStatus = _legacyPhysicalStatusFor(
      economicStatus: nextEconomic,
      usageStatus: nextUsage,
      visibilityStatus: asset.visibilityStatus,
    );
    await _db!.transaction((txn) async {
      await txn.update(
        'physical_assets',
        {
          'status': legacyStatus.storageKey,
          'economic_status': nextEconomic.storageKey,
          'usage_status': nextUsage.storageKey,
          if (economicTermination) 'current_value': '0',
          'include_in_net_worth': economicTermination
              ? 0
              : (includeInNetWorth ?? asset.includeInNetWorth)
                  ? 1
                  : 0,
          if (includeInNetWorth != null)
            'inclusion_quality': AssetInclusionQuality.confirmed.storageKey,
          'ended_ms': economicTermination ? at.millisecondsSinceEpoch : null,
          'updated_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      if (economicTermination) {
        await _insertAssetValuation(
          txn,
          assetId: id,
          value: Decimal.zero,
          source: AssetValueSource.statusZero,
          valuedAt: at,
          note: note.trim(),
        );
      }
      await _insertAssetEvent(
        txn,
        assetId: id,
        type: eventType,
        occurredAt: at,
        value: economicTermination ? Decimal.zero : null,
        note: note.trim(),
        metadata: {
          'previous_economic_status': asset.economicStatus.storageKey,
          'previous_usage_status': asset.usageStatus.storageKey,
          'previous_visibility_status': asset.visibilityStatus.storageKey,
          'previous_inclusion_quality': asset.inclusionQuality.storageKey,
          'previous_include_in_net_worth': asset.includeInNetWorth,
          'previous_value': asset.currentValue.toString(),
          'previous_ended_ms': asset.endedMs,
        },
      );
    });
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<void> undoPhysicalAssetTerminalStatus(int id) async {
    final asset = physicalAssetDetailById(id);
    if (asset == null || asset.isDeleted) throw StateError('物品不存在');
    final terminalType = _terminalEventTypeFor(asset.economicStatus);
    if (terminalType == null) {
      throw StateError('当前状态不能使用这个撤销操作');
    }
    final now = DateTime.now();
    await _db!.transaction((txn) async {
      final currentRows = await txn.query(
        'physical_assets',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (currentRows.isEmpty) throw StateError('物品不存在');
      final current = PhysicalAssetEntity.fromMap(currentRows.single);
      if (current.isDeleted) throw StateError('物品不存在');
      final currentTerminalType = _terminalEventTypeFor(current.economicStatus);
      if (currentTerminalType == null) {
        throw StateError('当前状态不能使用这个撤销操作');
      }
      final eventRows = await txn.query(
        'asset_events',
        where: "asset_type = 'physical' AND asset_id = ?",
        whereArgs: [id],
      );
      final event = _latestUnreversedTerminalEvent(
        eventRows.map(AssetEventEntity.fromMap),
        currentTerminalType,
      );
      if (event == null) throw StateError('缺少可撤销的结束持有事件');
      final metadata = _assetEventMetadata(event.metadata);
      if (!_hasPhysicalTerminalUndoEvidence(metadata)) {
        throw StateError('这条历史结束记录缺少结束前价值或计入口径证据，不能自动撤销');
      }
      final restoredEconomic = PhysicalAssetEconomicStatusX.fromStorage(
        metadata['previous_economic_status']?.toString(),
      );
      if (!restoredEconomic.ownsValue) {
        throw StateError('结束持有前的经济状态无法恢复');
      }
      final restoredUsage = PhysicalAssetUsageStatusX.fromStorage(
        metadata['previous_usage_status']?.toString(),
      );
      final restoredQuality = AssetInclusionQualityX.fromStorage(
        metadata['previous_inclusion_quality']?.toString(),
      );
      final restoredValue = Decimal.parse(
        metadata['previous_value'].toString(),
      );
      final restoredIncluded =
          metadata['previous_include_in_net_worth'] as bool;
      await txn.update(
        'physical_assets',
        {
          'status': _legacyPhysicalStatusFor(
            economicStatus: restoredEconomic,
            usageStatus: restoredUsage,
            visibilityStatus: current.visibilityStatus,
          ).storageKey,
          'economic_status': restoredEconomic.storageKey,
          'usage_status': restoredUsage.storageKey,
          'inclusion_quality': restoredQuality.storageKey,
          'current_value': restoredValue.toString(),
          'include_in_net_worth': restoredIncluded ? 1 : 0,
          'ended_ms': int.tryParse(
            metadata['previous_ended_ms']?.toString() ?? '',
          ),
          'updated_ms': now.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await _insertAssetValuation(
        txn,
        assetId: id,
        value: restoredValue,
        source: AssetValueSource.manual,
        valuedAt: now,
        note: '撤销${currentTerminalType.label}，恢复结束前价值',
      );
      await _insertAssetEvent(
        txn,
        assetId: id,
        type: AssetEventType.assetTerminalUndone,
        occurredAt: now,
        value: restoredValue,
        note: '撤销${currentTerminalType.label}',
        metadata: {
          'reversal_of_event_id': event.id,
          'reversal_of_event_uuid': event.uuid,
          'reversal_of_type': currentTerminalType.storageKey,
        },
      );
    });
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<void> archivePhysicalAsset(int id, {String note = ''}) async {
    final asset = physicalAssetDetailById(id);
    if (asset == null || asset.isDeleted) throw StateError('资产不存在');
    if (asset.isArchived) return;
    final now = DateTime.now();
    await _db!.transaction((txn) async {
      await txn.update(
        'physical_assets',
        {
          'status': PhysicalAssetStatus.archived.storageKey,
          'visibility_status': AssetVisibilityStatus.archived.storageKey,
          'archived_ms': now.millisecondsSinceEpoch,
          'updated_ms': now.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await _insertAssetEvent(
        txn,
        assetId: id,
        type: AssetEventType.assetArchived,
        occurredAt: now,
        note: note.trim(),
      );
    });
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<void> restorePhysicalAsset(
    int id, {
    bool includeInNetWorth = true,
    PhysicalAssetStatus status = PhysicalAssetStatus.active,
    String note = '',
  }) async {
    final existing =
        _allPhysicalAssets.where((asset) => asset.id == id).firstOrNull;
    if (existing == null) throw StateError('资产不存在');
    if (!existing.isArchived) {
      throw StateError('只有已归档资产可以恢复');
    }
    final restoredStatus = _legacyPhysicalStatusFor(
      economicStatus: existing.economicStatus,
      usageStatus: existing.usageStatus,
      visibilityStatus: AssetVisibilityStatus.active,
    );
    await _db!.transaction((txn) async {
      await txn.update(
        'physical_assets',
        {
          'status': restoredStatus.storageKey,
          'visibility_status': AssetVisibilityStatus.active.storageKey,
          'archived_ms': null,
          'updated_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await _insertAssetEvent(
        txn,
        assetId: id,
        type: AssetEventType.assetUnarchived,
        occurredAt: DateTime.now(),
        note: note.trim(),
      );
    });
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<void> confirmPhysicalAssetState(
    int id, {
    required PhysicalAssetUsageStatus usageStatus,
    required bool includeInNetWorth,
  }) async {
    final asset = physicalAssetDetailById(id);
    if (asset == null || asset.isDeleted) throw StateError('资产不存在');
    if (asset.inclusionQuality != AssetInclusionQuality.needsReview) {
      throw StateError('这件物品没有待确认的迁移状态');
    }
    if (!asset.economicStatus.ownsValue) {
      throw StateError('已结束物品不能通过迁移确认恢复为持有中');
    }
    if (asset.includeInNetWorth != includeInNetWorth) {
      await _bumpNetWorthScopeVersion();
    }
    final now = DateTime.now();
    await _db!.transaction((txn) async {
      await txn.update(
        'physical_assets',
        {
          'status': _legacyPhysicalStatusFor(
            economicStatus: asset.economicStatus,
            usageStatus: usageStatus,
            visibilityStatus: asset.visibilityStatus,
          ).storageKey,
          'usage_status': usageStatus.storageKey,
          'include_in_net_worth': includeInNetWorth ? 1 : 0,
          'inclusion_quality': AssetInclusionQuality.confirmed.storageKey,
          'updated_ms': now.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await _insertAssetEvent(
        txn,
        assetId: id,
        type: AssetEventType.assetEdited,
        occurredAt: now,
        note: '确认迁移状态与净资产口径',
        metadata: {
          'usage_status': usageStatus.storageKey,
          'include_in_net_worth': includeInNetWorth,
        },
      );
    });
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<void> softDeletePhysicalAsset(int id) async {
    final asset = physicalAssetDetailById(id);
    if (asset?.includeInNetWorth ?? false) {
      await _bumpNetWorthScopeVersion();
    }
    await _db!.update(
      'physical_assets',
      {
        'is_deleted': 1,
        'include_in_net_worth': 0,
        'updated_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 权益资产 CRUD / 收回
  // ---------------------------------------------------------------------------

  ReceivableEconomicStatus _receivableEconomicStatusForRemaining(
    Decimal remaining,
    Decimal original,
  ) =>
      remaining <= Decimal.zero
          ? ReceivableEconomicStatus.recovered
          : remaining < original
              ? ReceivableEconomicStatus.partialRecovered
              : ReceivableEconomicStatus.active;

  Future<int> addReceivableAsset({
    required String name,
    ReceivableAssetType type = ReceivableAssetType.other,
    required Decimal originalAmount,
    Decimal? remainingAmount,
    String currencyCode = 'CNY',
    String counterparty = '',
    DateTime? dueDate,
    bool includeInNetWorth = true,
    ReceivableAssetStatus status = ReceivableAssetStatus.active,
    String note = '',
    DateTime? occurredAt,
  }) async {
    if (name.trim().isEmpty) throw ArgumentError('权益名称不能为空');
    final normalizedCurrency = currencyCode.trim().toUpperCase();
    if (normalizedCurrency != 'CNY') {
      throw UnsupportedError('当前版本仅支持新增人民币权益资产。');
    }
    if (originalAmount < Decimal.zero) {
      throw ArgumentError('权益资产原始金额不能为负');
    }
    final remaining = remainingAmount ?? originalAmount;
    if (remaining < Decimal.zero || remaining > originalAmount) {
      throw ArgumentError('权益资产剩余金额必须在 0 到原始金额之间');
    }
    final normalizedStatus = remaining <= Decimal.zero
        ? ReceivableAssetStatus.recovered
        : status == ReceivableAssetStatus.recovered
            ? ReceivableAssetStatus.active
            : status;
    if (normalizedStatus == ReceivableAssetStatus.lost ||
        normalizedStatus == ReceivableAssetStatus.archived) {
      throw ArgumentError('新增权益资产不能从损失或归档状态开始');
    }
    final now = DateTime.now();
    final createdMs = now.millisecondsSinceEpoch;
    final economicStatus = _receivableEconomicStatusForRemaining(
      remaining,
      originalAmount,
    );
    const visibilityStatus = AssetVisibilityStatus.active;
    late int assetId;
    await _db!.transaction((txn) async {
      assetId = await txn.insert('receivable_assets', {
        'uuid': _newUuid(),
        'book_id': _currentBookId,
        'name': name.trim(),
        'receivable_type': type.storageKey,
        'status': _legacyReceivableStatusFor(
          economicStatus: economicStatus,
          visibilityStatus: visibilityStatus,
        ).storageKey,
        'economic_status': economicStatus.storageKey,
        'visibility_status': visibilityStatus.storageKey,
        'inclusion_quality': AssetInclusionQuality.confirmed.storageKey,
        'original_amount': originalAmount.toString(),
        'remaining_amount': remaining.toString(),
        'currency_code': normalizedCurrency,
        'counterparty': counterparty.trim(),
        'due_date_ms': dueDate?.millisecondsSinceEpoch,
        'include_in_net_worth': includeInNetWorth &&
                economicStatus.canCountInNetWorth &&
                remaining > Decimal.zero
            ? 1
            : 0,
        'note': note.trim(),
        'is_deleted': 0,
        'ended_ms': economicStatus == ReceivableEconomicStatus.recovered
            ? (occurredAt ?? now).millisecondsSinceEpoch
            : null,
        'archived_ms': null,
        'created_ms': createdMs,
        'updated_ms': createdMs,
      });
      await _insertAssetEvent(
        txn,
        assetId: assetId,
        assetType: AssetObjectType.receivable,
        type: AssetEventType.receivableCreated,
        occurredAt: occurredAt ?? now,
        value: remaining,
        note: note.trim(),
        metadata: {'receivable_type': type.storageKey},
      );
    });
    await _loadPhysicalAssetData();
    notifyListeners();
    return assetId;
  }

  Future<void> updateReceivableAsset({
    required int id,
    required String name,
    required ReceivableAssetType type,
    required Decimal originalAmount,
    required Decimal remainingAmount,
    required ReceivableAssetStatus status,
    String currencyCode = 'CNY',
    String counterparty = '',
    DateTime? dueDate,
    required bool includeInNetWorth,
    String note = '',
  }) async {
    final existing =
        _allReceivableAssets.where((asset) => asset.id == id).firstOrNull;
    if (existing == null) throw StateError('权益资产不存在');
    if (name.trim().isEmpty) throw ArgumentError('权益名称不能为空');
    if (originalAmount < Decimal.zero ||
        remainingAmount < Decimal.zero ||
        remainingAmount > originalAmount) {
      throw ArgumentError('权益资产金额不合法');
    }
    if (currencyCode.trim().toUpperCase() != existing.currencyCode) {
      throw UnsupportedError('当前版本不能转换权益资产币种。');
    }
    if (remainingAmount != existing.remainingAmount ||
        status != existing.status) {
      throw StateError('剩余金额和状态必须通过收回、损失、归档或恢复流程修改。');
    }
    if (_receivableRecoveries
            .any((recovery) => recovery.receivableAssetId == id) &&
        originalAmount != existing.originalAmount) {
      throw StateError('已有收回记录后不能修改原始金额。');
    }
    if (existing.includeInNetWorth != includeInNetWorth) {
      await _bumpNetWorthScopeVersion();
    }
    final normalizedStatus = existing.status;
    await _db!.transaction((txn) async {
      await txn.update(
        'receivable_assets',
        {
          'name': name.trim(),
          'receivable_type': type.storageKey,
          'status': normalizedStatus.storageKey,
          'economic_status': existing.economicStatus.storageKey,
          'visibility_status': existing.visibilityStatus.storageKey,
          'original_amount': originalAmount.toString(),
          'remaining_amount': remainingAmount.toString(),
          'currency_code': currencyCode,
          'counterparty': counterparty.trim(),
          'due_date_ms': (dueDate ?? existing.dueDate)?.millisecondsSinceEpoch,
          'include_in_net_worth': includeInNetWorth &&
                  existing.economicStatus.canCountInNetWorth &&
                  remainingAmount > Decimal.zero
              ? 1
              : 0,
          'inclusion_quality': existing.inclusionQuality.storageKey,
          'note': note.trim(),
          'updated_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await _insertAssetEvent(
        txn,
        assetId: id,
        assetType: AssetObjectType.receivable,
        type: AssetEventType.receivableEdited,
        occurredAt: DateTime.now(),
        value: remainingAmount,
        note: note.trim(),
      );
    });
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  /// [interestAmount]（A2 借贷按人）：收回时对方多还的利息部分。
  ///
  /// 现有收回语义对「amount 超过剩余金额」有明确拒绝（撤销链依赖
  /// amount ≤ remaining），A 批不破坏它：本金收回仍走 [amount]（≤剩余），
  /// 超本金差额由调用方拆出来放 [interestAmount]，这里另记一笔**收入**
  /// （分类=投资理财-利息，见 [_interestCategoryFor]，入 [targetAccountId]），
  /// 其流水 id 写进收回事件 metadata（interest_transaction_id），撤销收回时
  /// 一并删除，审计链闭合。interestAmount > 0 时必须给 targetAccountId
  /// （利息是真钱，必须有到账账户，否则就是编数）。
  Future<void> recoverReceivableAsset({
    required int id,
    required Decimal amount,
    int? targetAccountId,
    DateTime? recoveredAt,
    String note = '',
    Decimal? interestAmount,
  }) async {
    if (amount <= Decimal.zero) {
      throw ArgumentError('收回金额必须大于 0');
    }
    final interest = interestAmount == null
        ? Decimal.zero
        : normalizeMoneyAmount(interestAmount);
    if (interest < Decimal.zero) {
      throw ArgumentError('利息金额不能为负');
    }
    if (interest > Decimal.zero && targetAccountId == null) {
      throw ArgumentError('记利息收入需要指定到账账户');
    }
    final at = recoveredAt ?? DateTime.now();
    final timePrecision = recoveredAt == null
        ? TransactionTimePrecision.exact
        : TransactionTimePrecision.dateOnly;
    await _db!.transaction((txn) async {
      final rows = await txn.query(
        'receivable_assets',
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('权益资产不存在');
      final asset = ReceivableAssetEntity.fromMap(rows.first);
      if (!asset.economicStatus.canCountInNetWorth ||
          asset.remainingAmount <= Decimal.zero) {
        throw StateError('当前权益状态不能收回');
      }
      if (amount > asset.remainingAmount) {
        throw ArgumentError('收回金额不能超过剩余金额');
      }
      if (asset.currencyCode != 'CNY') {
        throw UnsupportedError('当前版本暂不支持外币权益收回入账。');
      }
      if (targetAccountId != null &&
          !_accounts.any((account) =>
              account.id == targetAccountId &&
              !account.isDeleted &&
              account.currencyCode == 'CNY')) {
        throw ArgumentError('到账账户不存在或币种不受支持');
      }
      final newRemaining = asset.remainingAmount - amount;
      final newEconomicStatus = _receivableEconomicStatusForRemaining(
        newRemaining,
        asset.originalAmount,
      );
      int? transactionId;
      int? interestTransactionId;
      if (targetAccountId != null) {
        transactionId = await txn.insert('transactions', {
          'book_id': asset.bookId ?? _currentBookId,
          'kind': TransactionKind.income.toJson(),
          'amount': amount.toString(),
          'currency_code': asset.currencyCode,
          'category_id': null,
          'account_id': targetAccountId,
          'to_account_id': null,
          'note': note.trim().isEmpty ? '权益收回：${asset.name}' : note.trim(),
          'date_ms': at.millisecondsSinceEpoch,
          'time_precision': timePrecision.storageKey,
          'tags': '',
          'reimbursable': 0,
          'image_path': '',
          'excluded': 1,
          ..._settlementFields(
            settledAt: at,
            settlementAccountId: targetAccountId,
            eventType: TransactionEventType.receivableRecovery,
          ),
          ..._syncStampNew(),
        });
        if (interest > Decimal.zero) {
          // 超本金的利息是真收入（不像本金收回那样 excluded），单独一笔，
          // 分类=投资理财-利息（容错查找），撤销收回时随收回记录一并删除。
          interestTransactionId = await txn.insert('transactions', {
            'book_id': asset.bookId ?? _currentBookId,
            'kind': TransactionKind.income.toJson(),
            'amount': interest.toString(),
            'currency_code': asset.currencyCode,
            'category_id': _interestCategoryFor(TransactionKind.income)?.id,
            'account_id': targetAccountId,
            'to_account_id': null,
            'note': '借出利息：${asset.name}',
            'date_ms': at.millisecondsSinceEpoch,
            'time_precision': timePrecision.storageKey,
            'tags': '',
            'reimbursable': 0,
            'image_path': '',
            'excluded': 0,
            // 事件类型必须是 income：三套结算引擎（movement legs /
            // projection / activity）对 interest 事件一律按流出记账（那是
            // 还款利息=支出的契约，UI 标签也是「利息费用」）。这笔是收进来
            // 的利息，打 interest 会让账户余额反向少两倍。利息语义由
            // 分类（投资理财-利息）、备注和收回事件 metadata 的
            // interest_transaction_id 承载，审计不丢。
            ..._settlementFields(
              settledAt: at,
              settlementAccountId: targetAccountId,
              eventType: TransactionEventType.income,
            ),
            ..._syncStampNew(),
          });
        }
      }
      await txn.update(
        'receivable_assets',
        {
          'remaining_amount': newRemaining.toString(),
          'status': _legacyReceivableStatusFor(
            economicStatus: newEconomicStatus,
            visibilityStatus: asset.visibilityStatus,
          ).storageKey,
          'economic_status': newEconomicStatus.storageKey,
          'include_in_net_worth':
              newRemaining > Decimal.zero && asset.includeInNetWorth ? 1 : 0,
          'ended_ms':
              newRemaining <= Decimal.zero ? at.millisecondsSinceEpoch : null,
          'updated_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      final eventId = await _insertAssetEvent(
        txn,
        assetId: id,
        assetType: AssetObjectType.receivable,
        type: AssetEventType.receivableRecovered,
        occurredAt: at,
        value: amount,
        note: note.trim(),
        metadata: {
          'previous_remaining': asset.remainingAmount.toString(),
          'previous_status': asset.status.storageKey,
          'previous_economic_status': asset.economicStatus.storageKey,
          'previous_visibility_status': asset.visibilityStatus.storageKey,
          'previous_inclusion_quality': asset.inclusionQuality.storageKey,
          'previous_ended_ms': asset.endedMs,
          'previous_include_in_net_worth': asset.includeInNetWorth,
          if (targetAccountId != null) 'target_account_id': targetAccountId,
          if (transactionId != null) 'transaction_id': transactionId,
          if (interestTransactionId != null)
            'interest_transaction_id': interestTransactionId,
          if (interest > Decimal.zero) 'interest_amount': interest.toString(),
        },
      );
      await txn.insert('receivable_recoveries', {
        'uuid': _newUuid(),
        'receivable_asset_id': id,
        'amount': amount.toString(),
        'recovered_ms': at.millisecondsSinceEpoch,
        'target_account_id': targetAccountId,
        'event_id': eventId,
        'transaction_id': transactionId,
        'note': note.trim(),
        'created_ms': DateTime.now().millisecondsSinceEpoch,
      });
    });
    await _loadTransactions();
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<void> undoReceivableRecovery(int recoveryId) async {
    await _db!.transaction((txn) async {
      final recoveryRows = await txn.query(
        'receivable_recoveries',
        where: 'id = ?',
        whereArgs: [recoveryId],
        limit: 1,
      );
      if (recoveryRows.isEmpty) throw StateError('收回记录不存在');
      final recovery = ReceivableRecoveryEntity.fromMap(recoveryRows.first);
      final latestRows = await txn.query(
        'receivable_recoveries',
        columns: ['id'],
        where: 'receivable_asset_id = ?',
        whereArgs: [recovery.receivableAssetId],
        orderBy: 'recovered_ms DESC, id DESC',
        limit: 1,
      );
      if (latestRows.isEmpty || latestRows.first['id'] != recoveryId) {
        throw StateError('只能从最近一次收回开始撤销');
      }
      final assetRows = await txn.query(
        'receivable_assets',
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [recovery.receivableAssetId],
        limit: 1,
      );
      if (assetRows.isEmpty) throw StateError('权益资产不存在');
      final asset = ReceivableAssetEntity.fromMap(assetRows.first);
      final restoredRemaining = asset.remainingAmount + recovery.amount;
      if (restoredRemaining > asset.originalAmount) {
        throw StateError('撤销后金额会超过原始金额');
      }
      Map<String, dynamic> metadata = const {};
      if (recovery.eventId != null) {
        final eventRows = await txn.query(
          'asset_events',
          columns: ['metadata'],
          where: 'id = ?',
          whereArgs: [recovery.eventId],
          limit: 1,
        );
        if (eventRows.isNotEmpty) {
          metadata = _assetEventMetadata(
            eventRows.first['metadata'] as String? ?? '',
          );
        }
      }
      final previousStatus = ReceivableAssetStatusX.fromStorage(
        metadata['previous_status']?.toString(),
      );
      final restoredEconomic = metadata.containsKey('previous_economic_status')
          ? ReceivableEconomicStatusX.fromStorage(
              metadata['previous_economic_status']?.toString(),
            )
          : previousStatus.canCountInNetWorth
              ? _receivableEconomicFromLegacyStatus(previousStatus)
              : _receivableEconomicStatusForRemaining(
                  restoredRemaining,
                  asset.originalAmount,
                );
      final restoredVisibility =
          metadata.containsKey('previous_visibility_status')
              ? AssetVisibilityStatusX.fromStorage(
                  metadata['previous_visibility_status']?.toString(),
                )
              : asset.visibilityStatus;
      final restoredQuality = metadata.containsKey('previous_inclusion_quality')
          ? AssetInclusionQualityX.fromStorage(
              metadata['previous_inclusion_quality']?.toString(),
            )
          : asset.inclusionQuality;
      final restoredStatus = _legacyReceivableStatusFor(
        economicStatus: restoredEconomic,
        visibilityStatus: restoredVisibility,
      );
      final previousIncluded = metadata['previous_include_in_net_worth'] is bool
          ? metadata['previous_include_in_net_worth'] as bool
          : true;
      if (recovery.transactionId != null) {
        await txn.delete(
          'transactions',
          where: 'id = ? OR refund_of = ?',
          whereArgs: [recovery.transactionId, recovery.transactionId],
        );
      }
      // A2：这笔收回若带了利息收入（超本金部分），撤销时一并删，审计闭合。
      final interestTxId = int.tryParse(
        metadata['interest_transaction_id']?.toString() ?? '',
      );
      if (interestTxId != null) {
        await txn.delete(
          'transactions',
          where: 'id = ?',
          whereArgs: [interestTxId],
        );
      }
      await txn.delete('receivable_recoveries',
          where: 'id = ?', whereArgs: [recoveryId]);
      await txn.update(
        'receivable_assets',
        {
          'remaining_amount': restoredRemaining.toString(),
          'status': restoredStatus.storageKey,
          'economic_status': restoredEconomic.storageKey,
          'visibility_status': restoredVisibility.storageKey,
          'inclusion_quality': restoredQuality.storageKey,
          'include_in_net_worth': previousIncluded ? 1 : 0,
          'ended_ms': int.tryParse(
            metadata['previous_ended_ms']?.toString() ?? '',
          ),
          'updated_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [asset.id],
      );
      await _insertAssetEvent(
        txn,
        assetId: asset.id,
        assetType: AssetObjectType.receivable,
        type: AssetEventType.receivableRecoveryUndone,
        occurredAt: DateTime.now(),
        value: recovery.amount,
        note: '撤销收回',
      );
    });
    await _loadTransactions();
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<void> markReceivableAssetLost(int id, {String note = ''}) async {
    final asset = receivableDetailById(id);
    if (asset == null || asset.isDeleted) {
      throw StateError('权益资产不存在');
    }
    if (!asset.economicStatus.canCountInNetWorth) {
      throw StateError('当前权益状态不能标记损失');
    }
    final now = DateTime.now();
    await _db!.transaction((txn) async {
      await txn.update(
        'receivable_assets',
        {
          'remaining_amount': '0',
          'status': _legacyReceivableStatusFor(
            economicStatus: ReceivableEconomicStatus.lost,
            visibilityStatus: asset.visibilityStatus,
          ).storageKey,
          'economic_status': ReceivableEconomicStatus.lost.storageKey,
          'include_in_net_worth': 0,
          'ended_ms': now.millisecondsSinceEpoch,
          'updated_ms': now.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await _insertAssetEvent(
        txn,
        assetId: id,
        assetType: AssetObjectType.receivable,
        type: AssetEventType.receivableLost,
        occurredAt: now,
        value: Decimal.zero,
        note: note.trim(),
        metadata: {
          'previous_economic_status': asset.economicStatus.storageKey,
          'previous_remaining': asset.remainingAmount.toString(),
          'previous_include_in_net_worth': asset.includeInNetWorth,
          'previous_ended_ms': asset.endedMs,
        },
      );
    });
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<void> archiveReceivableAsset(int id, {String note = ''}) async {
    final asset = receivableDetailById(id);
    if (asset == null || asset.isDeleted) {
      throw StateError('权益资产不存在');
    }
    if (asset.isArchived) return;
    final now = DateTime.now();
    await _db!.transaction((txn) async {
      await txn.update(
        'receivable_assets',
        {
          'status': ReceivableAssetStatus.archived.storageKey,
          'visibility_status': AssetVisibilityStatus.archived.storageKey,
          'archived_ms': now.millisecondsSinceEpoch,
          'updated_ms': now.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await _insertAssetEvent(
        txn,
        assetId: id,
        assetType: AssetObjectType.receivable,
        type: AssetEventType.receivableArchived,
        occurredAt: now,
        note: note.trim(),
      );
    });
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<void> restoreReceivableAsset(
    int id, {
    bool includeInNetWorth = true,
  }) async {
    final asset =
        _allReceivableAssets.where((item) => item.id == id).firstOrNull;
    if (asset == null) throw StateError('权益资产不存在');
    if (!asset.isArchived) {
      throw StateError('只有已归档权益可以恢复');
    }
    final status = _legacyReceivableStatusFor(
      economicStatus: asset.economicStatus,
      visibilityStatus: AssetVisibilityStatus.active,
    );
    await _db!.transaction((txn) async {
      await txn.update(
        'receivable_assets',
        {
          'status': status.storageKey,
          'visibility_status': AssetVisibilityStatus.active.storageKey,
          'archived_ms': null,
          'updated_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await _insertAssetEvent(
        txn,
        assetId: id,
        assetType: AssetObjectType.receivable,
        type: AssetEventType.receivableUnarchived,
        occurredAt: DateTime.now(),
      );
    });
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<void> confirmReceivableAssetState(
    int id, {
    required ReceivableEconomicStatus economicStatus,
    required bool includeInNetWorth,
  }) async {
    final asset = receivableDetailById(id);
    if (asset == null || asset.isDeleted) {
      throw StateError('权益资产不存在');
    }
    if (asset.inclusionQuality != AssetInclusionQuality.needsReview) {
      throw StateError('这项权益没有待确认的迁移状态');
    }
    final remaining = asset.remainingAmount;
    switch (economicStatus) {
      case ReceivableEconomicStatus.active:
        if (remaining <= Decimal.zero) {
          throw ArgumentError('剩余金额为 0 的权益不能确认为未收回');
        }
      case ReceivableEconomicStatus.partialRecovered:
        if (remaining <= Decimal.zero || remaining >= asset.originalAmount) {
          throw ArgumentError('部分收回状态与当前剩余金额不一致');
        }
      case ReceivableEconomicStatus.recovered || ReceivableEconomicStatus.lost:
        if (remaining != Decimal.zero) {
          throw ArgumentError('已收回或已损失权益的剩余金额必须为 0');
        }
      case ReceivableEconomicStatus.unknown:
        break;
    }
    final now = DateTime.now();
    final normalizedInclude = includeInNetWorth &&
        economicStatus.canCountInNetWorth &&
        remaining > Decimal.zero;
    if (asset.includeInNetWorth != normalizedInclude) {
      await _bumpNetWorthScopeVersion();
    }
    await _db!.transaction((txn) async {
      await txn.update(
        'receivable_assets',
        {
          'status': _legacyReceivableStatusFor(
            economicStatus: economicStatus,
            visibilityStatus: asset.visibilityStatus,
          ).storageKey,
          'economic_status': economicStatus.storageKey,
          'include_in_net_worth': normalizedInclude ? 1 : 0,
          'inclusion_quality': AssetInclusionQuality.confirmed.storageKey,
          'updated_ms': now.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await _insertAssetEvent(
        txn,
        assetId: id,
        assetType: AssetObjectType.receivable,
        type: AssetEventType.receivableEdited,
        occurredAt: now,
        value: remaining,
        note: '确认迁移状态与净资产口径',
        metadata: {
          'economic_status': economicStatus.storageKey,
          'include_in_net_worth': normalizedInclude,
        },
      );
    });
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<void> softDeleteReceivableAsset(int id) async {
    final asset = receivableDetailById(id);
    if (asset?.includeInNetWorth ?? false) {
      await _bumpNetWorthScopeVersion();
    }
    await _db!.update(
      'receivable_assets',
      {
        'is_deleted': 1,
        'include_in_net_worth': 0,
        'updated_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // P3 负债档案
  // ---------------------------------------------------------------------------

  Future<int> upsertLiabilityProfile({
    required int accountId,
    LiabilityProfileType type = LiabilityProfileType.other,
    required Decimal originalAmount,
    required Decimal currentPrincipal,
    Decimal? interestRate,
    int? repaymentDay,
    int? repaymentAccountId,
    DateTime? startDate,
    DateTime? endDate,
    LiabilityProfileStatus status = LiabilityProfileStatus.active,
    String note = '',
    int? statementDay,
    Decimal? creditLimit,
    String counterparty = '',
  }) async {
    originalAmount = normalizeMoneyAmount(originalAmount);
    currentPrincipal = normalizeMoneyAmount(currentPrincipal);
    final rate = interestRate ?? Decimal.zero;
    if (originalAmount < Decimal.zero ||
        currentPrincipal < Decimal.zero ||
        rate < Decimal.zero) {
      throw ArgumentError('负债金额和利率不能为负');
    }
    if (repaymentDay != null && (repaymentDay < 1 || repaymentDay > 31)) {
      throw ArgumentError('还款日必须在 1 到 31 之间');
    }
    if (statementDay != null && (statementDay < 1 || statementDay > 31)) {
      throw ArgumentError('账单日必须在 1 到 31 之间');
    }
    if (creditLimit != null && creditLimit < Decimal.zero) {
      throw ArgumentError('额度不能为负');
    }
    final existing = liabilityProfileForAccount(accountId);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final map = {
      'account_id': accountId,
      'liability_type': type.storageKey,
      'original_amount': originalAmount.toString(),
      'current_principal': currentPrincipal.toString(),
      'interest_rate': rate.toString(),
      'repayment_day': repaymentDay,
      'repayment_account_id': repaymentAccountId,
      'start_date_ms': startDate?.millisecondsSinceEpoch,
      'end_date_ms': endDate?.millisecondsSinceEpoch,
      'status': status.storageKey,
      'note': note.trim(),
      'statement_day': statementDay,
      'credit_limit': creditLimit == null
          ? null
          : normalizeMoneyAmount(creditLimit).toString(),
      'counterparty': counterparty.trim(),
      'updated_ms': nowMs,
    };
    late int id;
    if (existing == null) {
      id = await _db!.insert('liability_profiles', {
        'uuid': _newUuid(),
        ...map,
        'created_ms': nowMs,
      });
    } else {
      id = existing.id;
      await _db!.update(
        'liability_profiles',
        map,
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await _loadLiabilityProfiles();
    await _refreshCurrentNetWorthSnapshotBestEffort(
      const {NetWorthSnapshotCause.liability},
    );
    notifyListeners();
    return id;
  }

  Future<void> deleteLiabilityProfileForAccount(int accountId) async {
    await _db!.delete(
      'liability_profiles',
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
    await _loadLiabilityProfiles();
    await _refreshCurrentNetWorthSnapshotBestEffort(
      const {NetWorthSnapshotCause.liability},
    );
    notifyListeners();
  }

  /// 利息/手续费类分类查找（A 批还款/收回超本金部分入账用）。
  ///
  /// 查找顺序（诚实可回答「这笔数落在哪」）：
  /// - 收入侧：key 含 interest（种子=investment 下的 inc_interest「利息」）
  ///   → 名称含「利息」→ 顶级「其他收入」→ null（未分类）。
  /// - 支出侧：key 含 interest → 「其他-手续费」(other_fee / 名称含手续费)
  ///   → 顶级「其他」→ null。种子里没有独立「利息支出」分类，唯一带
  ///   「利息」字样的是「房贷利息」(house_loan)，非房贷场景挂它会说谎，
  ///   所以支出侧不按名称匹配利息、直接落手续费。
  CategoryEntity? _interestCategoryFor(TransactionKind kind) {
    final all = categoriesForKind(kind);
    for (final c in all) {
      if (c.key.toLowerCase().contains('interest') && !c.hidden) return c;
    }
    if (kind == TransactionKind.income) {
      for (final c in all) {
        if (c.nameZh.contains('利息') && !c.hidden) return c;
      }
      for (final c in all) {
        if (c.isTopLevel && c.key == 'otherIncome') return c;
      }
    } else {
      for (final c in all) {
        if ((c.key == 'other_fee' || c.nameZh.contains('手续费')) && !c.hidden) {
          return c;
        }
      }
      for (final c in all) {
        if (c.isTopLevel && c.key == 'other') return c;
      }
    }
    return null;
  }

  /// A 批「还款」动作（守 V2.1 锁定：不做本息 ledger 化、不改历史数据）。
  ///
  /// 语义：从 [fromAccountId] 划 [amount] 去还 [profileId] 挂的负债账户。
  /// - 本金部分 = min(amount, currentPrincipal)：记一笔转账
  ///   （还款账户 → 负债账户），档案 currentPrincipal 同额递减（减到 0 为止）。
  /// - 超出本金的差额：自动追加一笔支出（分类=利息/手续费，见
  ///   [_interestCategoryFor]），从还款账户出——总划扣 = amount，账户余额
  ///   与档案本金都能对上账。
  /// - 档案 currentPrincipal 本来就是 0（如信用卡：欠款在账户负余额上，
  ///   档案不跟踪本金）：整笔按转账处理，不产生利息支出——此时没有
  ///   「本金基准」，把差额说成利息就是编数。
  /// - 本金减到 0 且类型是 personalBorrow：status 置 paidOff（已结清，
  ///   复用现有枚举，不新造状态）。
  ///
  /// 返回各部分金额与流水 id，调用方（UI）据此给出诚实的结果提示。
  Future<
      ({
        int? transferTransactionId,
        int? interestTransactionId,
        Decimal principalPaid,
        Decimal interestPaid,
      })> repayLiabilityProfile({
    required int profileId,
    required Decimal amount,
    required int fromAccountId,
    DateTime? date,
    String note = '',
  }) async {
    amount = normalizeMoneyAmount(amount);
    if (amount <= Decimal.zero) {
      throw ArgumentError('还款金额必须大于 0');
    }
    final profile =
        _liabilityProfiles.where((p) => p.id == profileId).firstOrNull;
    if (profile == null) throw StateError('负债档案不存在');
    if (!_isSupportedTransactionAccountId(fromAccountId)) {
      throw ArgumentError('还款账户不存在或币种不受支持');
    }
    if (!_isSupportedTransactionAccountId(profile.accountId)) {
      throw ArgumentError('负债账户不存在或币种不受支持');
    }
    if (fromAccountId == profile.accountId) {
      throw ArgumentError('还款账户不能是负债账户本身');
    }
    final at = date ?? DateTime.now();
    final timePrecision = date == null
        ? TransactionTimePrecision.entryClock
        : TransactionTimePrecision.dateOnly;
    final hasPrincipal = profile.currentPrincipal > Decimal.zero;
    final principalPaid = hasPrincipal
        ? (amount < profile.currentPrincipal
            ? amount
            : profile.currentPrincipal)
        : Decimal.zero;
    final interestPaid = hasPrincipal ? amount - principalPaid : Decimal.zero;
    final transferAmount = hasPrincipal ? principalPaid : amount;
    final liabilityAccountName =
        _accounts.where((a) => a.id == profile.accountId).firstOrNull?.name ??
            '负债账户';
    final interestCategory = interestPaid > Decimal.zero
        ? _interestCategoryFor(TransactionKind.expense)
        : null;
    int? transferTxId;
    int? interestTxId;
    await _db!.transaction((txn) async {
      if (transferAmount > Decimal.zero) {
        transferTxId = await txn.insert('transactions', {
          'book_id': _currentBookId,
          'kind': TransactionKind.transfer.toJson(),
          'amount': transferAmount.toString(),
          'currency_code': 'CNY',
          'category_id': null,
          'account_id': fromAccountId,
          'to_account_id': profile.accountId,
          'note':
              note.trim().isEmpty ? '还款：$liabilityAccountName' : note.trim(),
          'date_ms': at.millisecondsSinceEpoch,
          'time_precision': timePrecision.storageKey,
          'tags': '',
          'reimbursable': 0,
          'image_path': '',
          'excluded': 0,
          // 事件类型必须是 transfer：三套结算引擎（movement projection /
          // balance legs / activity）对 principalPayment 都只记付款账户的
          // 单腿流出，负债账户收不到入账、钱会凭空消失；kind=transfer 的
          // 行走 transfer 事件才是双腿记账（付款账户出、负债账户入）。
          ..._settlementFields(
            settledAt: at,
            settlementAccountId: fromAccountId,
            eventType: TransactionEventType.transfer,
          ),
          ..._syncStampNew(),
        });
      }
      if (interestPaid > Decimal.zero) {
        interestTxId = await txn.insert('transactions', {
          'book_id': _currentBookId,
          'kind': TransactionKind.expense.toJson(),
          'amount': interestPaid.toString(),
          'currency_code': 'CNY',
          'category_id': interestCategory?.id,
          'account_id': fromAccountId,
          'to_account_id': null,
          'note': '还款利息：$liabilityAccountName',
          'date_ms': at.millisecondsSinceEpoch,
          'time_precision': timePrecision.storageKey,
          'tags': '',
          'reimbursable': 0,
          'image_path': '',
          'excluded': 0,
          ..._settlementFields(
            settledAt: at,
            settlementAccountId: fromAccountId,
            eventType: TransactionEventType.interest,
          ),
          ..._syncStampNew(),
        });
      }
      if (principalPaid > Decimal.zero) {
        final newPrincipal = profile.currentPrincipal - principalPaid;
        final settled = newPrincipal <= Decimal.zero &&
            profile.type == LiabilityProfileType.personalBorrow;
        await txn.update(
          'liability_profiles',
          {
            'current_principal': newPrincipal.toString(),
            if (settled) 'status': LiabilityProfileStatus.paidOff.storageKey,
            'updated_ms': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [profileId],
        );
      }
    });
    await _loadTransactions();
    await _loadLiabilityProfiles();
    await _refreshCurrentNetWorthSnapshotBestEffort(const {
      NetWorthSnapshotCause.transfer,
      NetWorthSnapshotCause.transaction,
      NetWorthSnapshotCause.liability,
    });
    notifyListeners();
    return (
      transferTransactionId: transferTxId,
      interestTransactionId: interestTxId,
      principalPaid: principalPaid,
      interestPaid: interestPaid,
    );
  }

  /// 「最近要还」：活跃负债档案里设了还款日的，按下次还款日升序。
  ///
  /// 只含 [withinDays] 天内到期的（含今天，daysLeft 0..withinDays）。
  /// account 可能为 null（档案挂的账户被删/归档时不瞎编账户名，交 UI 兜底）。
  List<
      ({
        LiabilityProfileEntity profile,
        AccountEntity? account,
        DateTime nextDate,
        int daysLeft,
      })> upcomingRepayments({int withinDays = 10, DateTime? now}) {
    final base = now ?? DateTime.now();
    final result = <({
      LiabilityProfileEntity profile,
      AccountEntity? account,
      DateTime nextDate,
      int daysLeft,
    })>[];
    for (final profile in _liabilityProfiles) {
      if (profile.status != LiabilityProfileStatus.active) continue;
      final next = profile.nextRepaymentDate(now: base);
      final daysLeft = profile.daysUntilRepayment(now: base);
      if (next == null || daysLeft == null) continue;
      if (daysLeft > withinDays) continue;
      result.add((
        profile: profile,
        account: _accounts
            .where((a) => a.id == profile.accountId && !a.isDeleted)
            .firstOrNull,
        nextDate: next,
        daysLeft: daysLeft,
      ));
    }
    result.sort((a, b) => a.nextDate.compareTo(b.nextDate));
    return result;
  }

  /// A5：构建迁移计划——对所有「未删除、计入净资产、人民币」账户分类。
  ///
  /// 纯 in-memory，无 IO，调用频率可以高。
  /// 结果包含 [LiabilityMigrationBranch.alreadyLedger]，UI 用它判断「全部完成」。
  List<LiabilityMigrationPlanItem> buildMigrationPlan() {
    final plan = <LiabilityMigrationPlanItem>[];
    for (final account in _accounts) {
      if (account.isDeleted ||
          !account.includeInNetWorth ||
          account.currencyCode != 'CNY') {
        continue;
      }
      final profile = liabilityProfileForAccount(account.id);
      final balance = accountBalanceOf(account);
      final principal = profile?.currentPrincipal ?? Decimal.zero;
      final countsAsLiability = profile?.countsAsLiability ?? false;
      plan.add(LiabilityMigrationClassifier.classify(
        accountId: account.id,
        balance: balance,
        principal: principal,
        principalCountsAsLiability: countsAsLiability,
        currentMode: account.balanceMode,
      ));
    }
    return plan;
  }

  /// A5：将账户切换到指定余额口径并刷新净资产快照。
  ///
  /// [bumpScope]：切换口径是「净资产计入政策变化」，需要 bump scope version，
  /// 否则历史快照会和新口径混在同一 lineage 里显得跳变。批量迁移时传 false，
  /// 由 [runAllSafeMigrations] 统一 bump 一次。
  Future<void> setAccountBalanceMode(
    int accountId,
    LiabilityBalanceMode mode, {
    bool bumpScope = true,
  }) async {
    await _db!.update(
      'accounts',
      {
        'balance_mode': mode.storageKey,
        'updated_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [accountId],
    );
    await _loadAccounts();
    if (bumpScope) {
      await _bumpNetWorthScopeVersion();
      await _refreshCurrentNetWorthSnapshotBestEffort(
        const {
          NetWorthSnapshotCause.liability,
          NetWorthSnapshotCause.migration
        },
      );
    }
    notifyListeners();
  }

  /// A5：对单个账户执行等价迁移（仅接受安全分支）。
  ///
  /// - [zeroBalanceCalibrate]：先创建 checkpoint 把余额校准到 `-P`，再切 ledger。
  ///   checkpoint 的「现在」时点要求满足——此方法在当前时点即时执行，符合。
  /// - 其余安全分支：直接切 ledger，余额不变，三项合计逐分不变。
  ///
  /// [bumpScope] 传 false 时，调用方负责在批量结束后统一 bump。
  Future<void> executeSafeMigration(
    LiabilityMigrationPlanItem item, {
    bool bumpScope = false,
  }) async {
    assert(item.branch.isAutoSafe, '仅安全分支可自动迁移');
    if (item.branch == LiabilityMigrationBranch.zeroBalanceCalibrate) {
      // 先把余额校准到 -P，使后续 ledger 口径下负余额直接代表欠款。
      // note 写明迁移来源，方便审计时区分「用户手动校准」和「系统迁移校准」。
      await createAccountBalanceCheckpoint(
        accountId: item.accountId,
        targetBalance: item.calibrationTarget!,
        note: 'A5 迁移：余额从 ${item.balance} 校准到 ${item.calibrationTarget}',
      );
    }
    await setAccountBalanceMode(
      item.accountId,
      LiabilityBalanceMode.ledger,
      bumpScope: bumpScope,
    );
  }

  /// A5：批量执行所有安全分支的等价迁移。
  ///
  /// 返回实际迁移的账户数。完成后统一 bump scope version 并刷新快照，
  /// 历史曲线在今天这个节点会看到口径切换的断代标注。
  /// 歧义账户（[LiabilityMigrationBranch.ambiguousNeedsUser]）不在此处理，
  /// 由 UI 逐一引导。
  Future<int> runAllSafeMigrations() async {
    final plan =
        buildMigrationPlan().where((item) => item.branch.isAutoSafe).toList();
    if (plan.isEmpty) return 0;
    for (final item in plan) {
      await executeSafeMigration(item, bumpScope: false);
    }
    // 统一 bump scope + 重算今天快照（A5-7）。
    await _bumpNetWorthScopeVersion();
    await _refreshCurrentNetWorthSnapshotBestEffort(
      const {NetWorthSnapshotCause.liability, NetWorthSnapshotCause.migration},
    );
    notifyListeners();
    return plan.length;
  }

  /// A5 §11.4 选项②：歧义账户「余额就是真实资产，不再双算本金」。
  ///
  /// 操作：保持余额不变，直接切 ledger——正余额仍算资产，profile 本金不再
  /// 另算进负债。净资产变化 = +P（少了一条本金负债）。
  /// 适用场景：信用卡溢缴款、押金账户、档案本金已过期/不再有效。
  /// A5：全批迁移收口——统一 bump scope version + 刷新快照（A5-7）。
  ///
  /// UI 在所有歧义账户都处理完后调用一次。若只有安全分支，[runAllSafeMigrations]
  /// 内部已 bump，调用方无需再调此方法；但重复调用无害（多 bump 一次版本号）。
  Future<void> finalizeA5Migration() async {
    await _bumpNetWorthScopeVersion();
    await _refreshCurrentNetWorthSnapshotBestEffort(
      const {NetWorthSnapshotCause.liability, NetWorthSnapshotCause.migration},
    );
    notifyListeners();
  }

  Future<void> resolveAmbiguousBalanceIsAsset(
    int accountId, {
    bool bumpScope = true,
  }) async {
    await setAccountBalanceMode(
      accountId,
      LiabilityBalanceMode.ledger,
      bumpScope: bumpScope,
    );
  }

  /// A5 §11.4 选项③：歧义账户「正余额不是资产，以档案本金为准切 ledger」。
  ///
  /// 操作：用 absolute checkpoint 把余额校准到 `-P` 再切 ledger。
  /// 净资产变化 = -B（少了 B 这笔虚增资产），三项明确变化，**必须由用户确认**。
  /// 适用场景：账户余额正数是录反了（应是欠款）或维修记录缺失。
  Future<void> resolveAmbiguousCalibrateToDebt(
    int accountId,
    Decimal targetBalance, {
    bool bumpScope = true,
  }) async {
    assert(targetBalance <= Decimal.zero, '校准目标余额必须 ≤ 0');
    await createAccountBalanceCheckpoint(
      accountId: accountId,
      targetBalance: targetBalance,
      note: 'A5 迁移：歧义账户余额校准到 $targetBalance（选项③）',
    );
    await setAccountBalanceMode(
      accountId,
      LiabilityBalanceMode.ledger,
      bumpScope: bumpScope,
    );
  }

  /// A2 借贷按人：记一笔向个人的借入。
  ///
  /// 取舍（数据诚实性优先）：
  /// - **每笔借入 = 一个独立的 loan 账户「借入·对象名」+ 一份 personalBorrow
  ///   档案**。不往同一对象的旧档案里合并追加——合并会把两笔不同日期的借入
  ///   压成一条「金额相加、日期取旧」的假记录；且档案与账户一一对应
  ///   （upsert 按 accountId），同一对象再借就再建一个账户（名字加序号），
  ///   借贷往来页按 counterparty 聚合，对用户仍是「一个人一张卡」。
  /// - 选了入账账户 [toAccountId]：记一笔转账（借入账户 → 入账账户），
  ///   钱的去向有账可查；没选：借入账户期初余额直接记 -金额——欠款是真的，
  ///   但钱去了记账之外，不编造一笔不存在的到账流水。
  /// - [dueDate]（约定还款日）存进档案 endDate，作为一次性到期日进
  ///   「最近要还」（见 [LiabilityProfileEntity.nextRepaymentDate]）。
  ///
  /// 返回负债档案 id。
  Future<int> addPersonalBorrow({
    required String counterparty,
    required Decimal amount,
    int? toAccountId,
    DateTime? dueDate,
    String note = '',
  }) async {
    final person = counterparty.trim();
    if (person.isEmpty) throw ArgumentError('借入对象姓名不能为空');
    amount = normalizeMoneyAmount(amount);
    if (amount <= Decimal.zero) throw ArgumentError('借入金额必须大于 0');
    if (toAccountId != null && !_isSupportedTransactionAccountId(toAccountId)) {
      throw ArgumentError('入账账户不存在或币种不受支持');
    }
    final baseName = '借入·$person';
    final usedNames =
        _accounts.where((a) => !a.isDeleted).map((a) => a.name).toSet();
    var name = baseName;
    var suffix = 2;
    while (usedNames.contains(name)) {
      name = '$baseName·${suffix++}';
    }
    final now = DateTime.now();
    final loanAccountId = await addAccount(
      name: name,
      type: AccountType.loan,
      openingBalance: toAccountId == null ? -amount : Decimal.zero,
    );
    if (toAccountId != null) {
      await addTransaction(
        kind: TransactionKind.transfer,
        amount: amount,
        accountId: loanAccountId,
        toAccountId: toAccountId,
        note: note.trim().isEmpty ? '借入：$person' : note.trim(),
        date: now,
      );
    }
    return upsertLiabilityProfile(
      accountId: loanAccountId,
      type: LiabilityProfileType.personalBorrow,
      originalAmount: amount,
      currentPrincipal: amount,
      startDate: now,
      endDate: dueDate,
      counterparty: person,
      note: note,
    );
  }

  /// A3 房贷/大额分期向导：一次事务里建齐「loan 账户 + 负债档案 + 每月
  /// 自动还款的周期转账规则」三件套——要么全建成，要么全不建。
  ///
  /// 数据语义（守 V2.1 锁定，不做本息拆分）：
  /// - loan 账户期初余额 = -剩余本金，欠款如实进净资产；
  /// - 周期规则 = 每月还款日从 [fromAccountId] 转 [monthlyPayment] 到
  ///   loan 账户；首期取「今天起最近的还款日」（含今天，当天到期立即记）；
  ///   anchor_day = 还款日，短月自动落月末、长月回到原日。
  /// - [annualRate] 只存进档案展示，不参与任何计算；月供含息，自动转账
  ///   会按月供全额抵减贷款账户余额——本息拆分是独立批（A5）的范围，
  ///   这里不冒充。手动「还款」路径（repayLiabilityProfile）才做档案本金
  ///   递减+超额记利息。
  Future<({int accountId, int profileId, int ruleId})> createLoanWizardSetup({
    required LiabilityProfileType type,
    required String name,
    required Decimal totalAmount,
    required Decimal remainingPrincipal,
    Decimal? annualRate,
    required Decimal monthlyPayment,
    required int repaymentDay,
    required int fromAccountId,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) throw ArgumentError('名称不能为空');
    totalAmount = normalizeMoneyAmount(totalAmount);
    remainingPrincipal = normalizeMoneyAmount(remainingPrincipal);
    monthlyPayment = normalizeMoneyAmount(monthlyPayment);
    final rate = annualRate ?? Decimal.zero;
    if (totalAmount <= Decimal.zero) throw ArgumentError('贷款总额必须大于 0');
    if (remainingPrincipal <= Decimal.zero) {
      throw ArgumentError('剩余本金必须大于 0');
    }
    if (monthlyPayment <= Decimal.zero) throw ArgumentError('每月还款额必须大于 0');
    if (rate < Decimal.zero) throw ArgumentError('年利率不能为负');
    if (repaymentDay < 1 || repaymentDay > 31) {
      throw ArgumentError('还款日必须在 1 到 31 之间');
    }
    if (!_isSupportedTransactionAccountId(fromAccountId)) {
      throw ArgumentError('扣款账户不存在、已归档或币种不受支持');
    }
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final firstDue = _nextDueForDayOfMonth(repaymentDay, now);
    late int accountId;
    late int profileId;
    late int ruleId;
    await _db!.transaction((txn) async {
      accountId = await txn.insert('accounts', {
        'uuid': _newUuid(),
        'name': trimmedName,
        'currency_code': 'CNY',
        'type': AccountType.loan.storageKey,
        'opening_balance': (-remainingPrincipal).toString(),
        'include_in_net_worth': 1,
        'institution': '',
        'created_ms': nowMs,
        'updated_ms': nowMs,
        'opening_balance_effective_ms': nowMs,
        'opening_balance_sequence': 0,
        'opening_balance_quality':
            AccountOpeningBalanceQuality.exact.storageKey,
        'status': AccountStatus.active.storageKey,
      });
      profileId = await txn.insert('liability_profiles', {
        'uuid': _newUuid(),
        'account_id': accountId,
        'liability_type': type.storageKey,
        'original_amount': totalAmount.toString(),
        'current_principal': remainingPrincipal.toString(),
        'interest_rate': rate.toString(),
        'repayment_day': repaymentDay,
        'repayment_account_id': fromAccountId,
        'start_date_ms': null,
        'end_date_ms': null,
        'status': LiabilityProfileStatus.active.storageKey,
        'note': '',
        'statement_day': null,
        'credit_limit': null,
        'counterparty': '',
        'created_ms': nowMs,
        'updated_ms': nowMs,
      });
      ruleId = await txn.insert('recurring_rules', {
        'book_id': _currentBookId,
        'kind': TransactionKind.transfer.toJson(),
        'amount': monthlyPayment.toString(),
        'category_id': null,
        'account_id': fromAccountId,
        'to_account_id': accountId,
        'note': '$trimmedName还款',
        'period': RecurPeriod.monthly.toJson(),
        'start_date_ms': firstDue.millisecondsSinceEpoch,
        'next_due_ms': firstDue.millisecondsSinceEpoch,
        'enabled': 1,
        'anchor_day': repaymentDay,
        'end_date_ms': null,
        'total_count': null,
        'generated_count': 0,
        'created_ms': nowMs,
      });
    });
    await _loadAccounts();
    await _loadLiabilityProfiles();
    await _loadRecurringRules();
    await _materializeRecurring(); // 首期若今天到期则立即记账
    await _loadTransactions();
    await _refreshCurrentNetWorthSnapshotBestEffort(const {
      NetWorthSnapshotCause.account,
      NetWorthSnapshotCause.liability,
      NetWorthSnapshotCause.scheduledRebuild,
    });
    notifyListeners();
    return (accountId: accountId, profileId: profileId, ruleId: ruleId);
  }

  /// 从 [now] 起最近一个「每月第 [day] 日」（含今天）。短月夹取到月末，
  /// 与 [RecurPeriod.advance] 的夹取规则一致。
  static DateTime _nextDueForDayOfMonth(int day, DateTime now) {
    DateTime clampToMonth(int year, int month) {
      final lastDay = DateTime(year, month + 1, 0).day;
      return DateTime(year, month, day < lastDay ? day : lastDay);
    }

    final today = DateTime(now.year, now.month, now.day);
    final thisMonth = clampToMonth(now.year, now.month);
    if (!thisMonth.isBefore(today)) return thisMonth;
    final nextYear = now.month == 12 ? now.year + 1 : now.year;
    final nextMonth = now.month == 12 ? 1 : now.month + 1;
    return clampToMonth(nextYear, nextMonth);
  }

  /// A2 借贷往来时间线：某负债账户名下的转账流水（跨账本查全量）。
  /// 转入该账户（to_account_id 命中）= 还款；从该账户转出 = 借入到账。
  List<TransactionEntity> transfersInvolvingAccount(int accountId) =>
      _allTransactions
          .where((t) =>
              t.txKind == TransactionKind.transfer &&
              (t.accountId == accountId || t.toAccountId == accountId))
          .toList();

  Future<String> exportAssetTablesJson() async {
    final assetIds = _physicalAssets.map((a) => a.id).toSet();
    final receivableIds = _receivableAssets.map((a) => a.id).toSet();
    final txRows = await _db!.query('transactions', columns: ['id', 'uuid']);
    final txUuidById = {
      for (final row in txRows) row['id'] as int: row['uuid'] as String? ?? ''
    };
    final linkUuidById = {
      for (final link in _assetTransactionLinks) link.id: link.uuid,
    };
    final refundAllocations = await _db!.query(
      'asset_refund_allocations',
      orderBy: 'created_ms ASC, id ASC',
    );
    final accountById = {for (final a in _accounts) a.id: a};
    final savingsGoalById = {for (final goal in _savingsGoals) goal.id: goal};
    final usageUuidById = {
      for (final event in _assetUsageEvents) event.id: event.uuid,
    };
    String accountNameOf(int? id) =>
        id == null ? '' : accountById[id]?.name ?? '';
    Map<String, Object?> assetMap(PhysicalAssetEntity a) => {
          'id': a.id,
          'uuid': a.uuid,
          'book_id': a.bookId,
          'name': a.name,
          'asset_type': a.assetType.storageKey,
          'status': a.status.storageKey,
          'economic_status': a.economicStatus.storageKey,
          'usage_status': a.usageStatus.storageKey,
          'visibility_status': a.visibilityStatus.storageKey,
          'inclusion_quality': a.inclusionQuality.storageKey,
          'source_type': a.sourceType.storageKey,
          'acquisition_cost_source': a.acquisitionCostSource.storageKey,
          'purchase_price': a.purchasePrice.toString(),
          'current_value': a.currentValue.toString(),
          'currency_code': a.currencyCode,
          'purchase_date_ms': a.purchaseDateMs,
          'brand': a.brand,
          'model': a.model,
          'location': a.location,
          'warranty_until_ms': a.warrantyUntilMs,
          'usage_tracking_enabled': a.usageTrackingEnabled ? 1 : 0,
          'savings_goal_id': a.savingsGoalId,
          'savings_goal_uuid': a.savingsGoalId == null
              ? ''
              : savingsGoalById[a.savingsGoalId]?.uuid ?? '',
          'savings_goal_name': a.savingsGoalId == null
              ? ''
              : savingsGoalById[a.savingsGoalId]?.name ?? '',
          'photo_path': a.photoPath,
          'thumbnail_path': a.thumbnailPath,
          'invoice_path': a.invoicePath,
          'depreciation_method': a.depreciationMethod,
          'depreciation_base': a.depreciationBase.toString(),
          'salvage_value': a.salvageValue.toString(),
          'useful_life_months': a.usefulLifeMonths,
          'depreciation_start_ms': a.depreciationStartMs,
          'depreciation_paused': a.depreciationPaused ? 1 : 0,
          'note': a.note,
          'include_in_net_worth': a.includeInNetWorth ? 1 : 0,
          'is_deleted': a.isDeleted ? 1 : 0,
          'ended_ms': a.endedMs,
          'archived_ms': a.archivedMs,
          'created_ms': a.createdMs,
          'updated_ms': a.updatedMs,
        };
    Map<String, Object?> receivableMap(ReceivableAssetEntity a) => {
          'id': a.id,
          'uuid': a.uuid,
          'book_id': a.bookId,
          'name': a.name,
          'receivable_type': a.type.storageKey,
          'status': a.status.storageKey,
          'economic_status': a.economicStatus.storageKey,
          'visibility_status': a.visibilityStatus.storageKey,
          'inclusion_quality': a.inclusionQuality.storageKey,
          'original_amount': a.originalAmount.toString(),
          'remaining_amount': a.remainingAmount.toString(),
          'currency_code': a.currencyCode,
          'counterparty': a.counterparty,
          'due_date_ms': a.dueDateMs,
          'include_in_net_worth': a.includeInNetWorth ? 1 : 0,
          'note': a.note,
          'is_deleted': a.isDeleted ? 1 : 0,
          'ended_ms': a.endedMs,
          'archived_ms': a.archivedMs,
          'created_ms': a.createdMs,
          'updated_ms': a.updatedMs,
        };
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'feimiao-assets',
      'version': 6,
      'databaseVersion': _dbVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'assets': [for (final a in _physicalAssets) assetMap(a)],
      'receivable_assets': [
        for (final a in _receivableAssets) receivableMap(a)
      ],
      'events': [
        for (final e in _assetEvents)
          if ((e.assetType == AssetObjectType.physical &&
                  assetIds.contains(e.assetId)) ||
              (e.assetType == AssetObjectType.receivable &&
                  receivableIds.contains(e.assetId)))
            {
              'id': e.id,
              'uuid': e.uuid,
              'asset_id': e.assetId,
              'asset_type': e.assetType.storageKey,
              'event_type': e.eventType.storageKey,
              'occurred_ms': e.occurredMs,
              'value': e.value?.toString() ?? '',
              'note': e.note,
              'metadata': e.metadata,
              'created_ms': e.createdMs,
            }
      ],
      'usage_events': [
        for (final event in _assetUsageEvents)
          if (assetIds.contains(event.assetId))
            {
              'id': event.id,
              'uuid': event.uuid,
              'asset_id': event.assetId,
              'count_delta': event.countDelta,
              'reversal_of': event.reversalOf,
              'reversal_of_uuid': event.reversalOf == null
                  ? ''
                  : usageUuidById[event.reversalOf] ?? '',
              'occurred_ms': event.occurredMs,
              'note': event.note,
              'created_ms': event.createdMs,
              'updated_ms': event.updatedMs,
            },
      ],
      'valuations': [
        for (final v in _assetValuations)
          if (assetIds.contains(v.assetId))
            {
              'id': v.id,
              'uuid': v.uuid,
              'asset_id': v.assetId,
              'value': v.value.toString(),
              'source': v.source.storageKey,
              'valued_at_ms': v.valuedAtMs,
              'note': v.note,
              'created_ms': v.createdMs,
            }
      ],
      'links': [
        for (final link in _assetTransactionLinks)
          if (link.assetObjectType == AssetObjectType.physical &&
              assetIds.contains(link.assetId))
            {
              'id': link.id,
              'uuid': link.uuid,
              'asset_id': link.assetId,
              'asset_object_type': link.assetObjectType.storageKey,
              'transaction_id': link.transactionId,
              'transaction_uuid': txUuidById[link.transactionId] ?? '',
              'link_type': link.linkType.storageKey,
              'amount': physicalAssetLinkCurrentAmount(link).toString(),
              'allocated_gross_cents': link.allocatedGrossCents,
              'allocated_refund_cents': link.allocatedRefundCents,
              'cost_quality': link.costQuality.storageKey,
              'note': link.note,
              'created_ms': link.createdMs,
              'updated_ms': link.updatedMs,
            }
      ],
      'refund_allocations': [
        for (final allocation in refundAllocations)
          if (linkUuidById.containsKey(
            allocation['asset_transaction_link_id'] as int,
          ))
            {
              'uuid': allocation['uuid'],
              'asset_transaction_link_uuid':
                  linkUuidById[allocation['asset_transaction_link_id'] as int],
              'refund_transaction_uuid':
                  txUuidById[allocation['refund_transaction_id'] as int] ?? '',
              'allocated_refund_cents': allocation['allocated_refund_cents'],
              'status': allocation['status'],
              'created_ms': allocation['created_ms'],
              'updated_ms': allocation['updated_ms'],
            }
      ],
      'recoveries': [
        for (final recovery in _receivableRecoveries)
          if (receivableIds.contains(recovery.receivableAssetId))
            {
              'id': recovery.id,
              'uuid': recovery.uuid,
              'receivable_asset_id': recovery.receivableAssetId,
              'amount': recovery.amount.toString(),
              'recovered_ms': recovery.recoveredMs,
              'target_account_id': recovery.targetAccountId,
              'target_account_name': accountNameOf(recovery.targetAccountId),
              'event_id': recovery.eventId,
              'transaction_id': recovery.transactionId,
              'transaction_uuid': recovery.transactionId == null
                  ? ''
                  : txUuidById[recovery.transactionId] ?? '',
              'note': recovery.note,
              'created_ms': recovery.createdMs,
            }
      ],
    });
  }

  Future<FeimiaoAssetImportResult> importAssetTablesJson(
    String jsonText,
  ) async {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'feimiao-assets') {
      throw ArgumentError('不是肥喵资产导出文件');
    }
    final formatVersion =
        int.tryParse(decoded['version']?.toString() ?? '') ?? 3;
    if (formatVersion < 1 || formatVersion > 6) {
      throw UnsupportedError('不支持的肥喵资产文件版本：$formatVersion');
    }
    final isLegacyStateFormat = formatVersion < 4;
    final assets = (decoded['assets'] as List? ?? const [])
        .whereType<Map>()
        .cast<Map<dynamic, dynamic>>()
        .toList();
    final receivableAssets = (decoded['receivable_assets'] as List? ?? const [])
        .whereType<Map>()
        .cast<Map<dynamic, dynamic>>()
        .toList();
    final events = (decoded['events'] as List? ?? const [])
        .whereType<Map>()
        .cast<Map<dynamic, dynamic>>()
        .toList();
    final usageEvents = (decoded['usage_events'] as List? ?? const [])
        .whereType<Map>()
        .cast<Map<dynamic, dynamic>>()
        .toList();
    final valuations = (decoded['valuations'] as List? ?? const [])
        .whereType<Map>()
        .cast<Map<dynamic, dynamic>>()
        .toList();
    final links = (decoded['links'] as List? ?? const [])
        .whereType<Map>()
        .cast<Map<dynamic, dynamic>>()
        .toList();
    final refundAllocations =
        (decoded['refund_allocations'] as List? ?? const [])
            .whereType<Map>()
            .cast<Map<dynamic, dynamic>>()
            .toList();
    final recoveries = (decoded['recoveries'] as List? ?? const [])
        .whereType<Map>()
        .cast<Map<dynamic, dynamic>>()
        .toList();
    final snapshots = (decoded['net_worth_snapshots'] as List? ?? const [])
        .whereType<Map>()
        .cast<Map<dynamic, dynamic>>()
        .toList();
    final liabilityProfiles =
        (decoded['liability_profiles'] as List? ?? const [])
            .whereType<Map>()
            .cast<Map<dynamic, dynamic>>()
            .toList();

    String str(Map<dynamic, dynamic> m, String key, [String fallback = '']) =>
        (m[key] ?? fallback).toString();
    int? intOrNull(Object? value) =>
        value == null ? null : int.tryParse(value.toString());
    int intOr(Object? value, int fallback) =>
        int.tryParse(value?.toString() ?? '') ?? fallback;
    String uuidOf(Map<dynamic, dynamic> m) {
      final raw = str(m, 'uuid').trim();
      return raw.length == 32 ? raw : _newUuid();
    }

    bool isUsageReversal(Map<dynamic, dynamic> event) =>
        str(event, 'reversal_of_uuid').trim().isNotEmpty ||
        intOrNull(event['reversal_of']) != null;
    usageEvents.sort((left, right) {
      final byKind = (isUsageReversal(left) ? 1 : 0)
          .compareTo(isUsageReversal(right) ? 1 : 0);
      if (byKind != 0) return byKind;
      final occurred = intOr(left['occurred_ms'], 0)
          .compareTo(intOr(right['occurred_ms'], 0));
      return occurred != 0
          ? occurred
          : intOr(left['id'], 0).compareTo(intOr(right['id'], 0));
    });

    int? accountIdFromAssetJson(
      Map<dynamic, dynamic> m, {
      required String idKey,
      required String nameKey,
    }) {
      final name = str(m, nameKey).trim();
      if (name.isNotEmpty) {
        final active = _accounts
            .where((a) => !a.isDeleted && a.name.trim() == name)
            .firstOrNull;
        if (active != null) return active.id;
        final any = _accounts.where((a) => a.name.trim() == name).firstOrNull;
        if (any != null) return any.id;
      }
      final rawId = intOrNull(m[idKey]);
      if (rawId == null) return null;
      final exists = _accounts.any((a) => a.id == rawId && !a.isDeleted);
      return exists ? rawId : null;
    }

    ({int? id, bool requested, bool unresolved}) savingsGoalIdFromAssetJson(
        Map<dynamic, dynamic> map) {
      final uuid = str(map, 'savings_goal_uuid').trim();
      final name = str(map, 'savings_goal_name').trim();
      final rawId = intOrNull(map['savings_goal_id']);
      final requested = uuid.isNotEmpty || name.isNotEmpty || rawId != null;
      if (!requested) {
        return (id: null, requested: false, unresolved: false);
      }
      if (uuid.isNotEmpty) {
        final byUuid =
            _savingsGoals.where((goal) => goal.uuid == uuid).firstOrNull;
        if (byUuid != null) {
          return (id: byUuid.id, requested: true, unresolved: false);
        }
      } else if (rawId != null) {
        final byId =
            _savingsGoals.where((goal) => goal.id == rawId).firstOrNull;
        if (byId != null && (name.isEmpty || byId.name.trim() == name)) {
          return (id: byId.id, requested: true, unresolved: false);
        }
      }
      if (name.isNotEmpty) {
        final byName =
            _savingsGoals.where((goal) => goal.name.trim() == name).toList();
        if (byName.length == 1) {
          return (id: byName.single.id, requested: true, unresolved: false);
        }
      }
      return (id: null, requested: true, unresolved: true);
    }

    final existingAssets = await _db!.query(
      'physical_assets',
      columns: ['id', 'uuid'],
      where: "uuid <> ''",
    );
    final assetIdByUuid = {
      for (final row in existingAssets) row['uuid'] as String: row['id'] as int
    };
    final existingReceivables = await _db!.query(
      'receivable_assets',
      columns: ['id', 'uuid'],
      where: "uuid <> ''",
    );
    final receivableIdByUuid = {
      for (final row in existingReceivables)
        row['uuid'] as String: row['id'] as int
    };
    final oldAssetIdToNew = <int, int>{};
    final oldReceivableIdToNew = <int, int>{};
    final oldEventIdToNew = <int, int>{};
    final oldUsageIdToNew = <int, int>{};
    final importedLinkIdByUuid = <String, int>{};
    final insertedLegacyAssetIds = <int>{};
    final insertedLegacyReceivableIds = <int>{};
    var assetCount = 0;
    var receivableCount = 0;
    var eventCount = 0;
    var usageCount = 0;
    var valuationCount = 0;
    var linkCount = 0;
    var recoveryCount = 0;
    var snapshotCount = 0;
    var liabilityCount = 0;
    var unresolvedTransactionLinkCount = 0;
    var unresolvedSavingsGoalLinkCount = 0;
    var rejectedLinkCount = 0;

    await _db!.transaction((txn) async {
      for (final raw in assets) {
        final uuid = uuidOf(raw);
        final oldId = intOrNull(raw['id']);
        final legacyStatus =
            PhysicalAssetStatusX.fromStorage(str(raw, 'status'));
        final rawEconomic = str(raw, 'economic_status');
        final rawUsage = str(raw, 'usage_status');
        final rawVisibility = str(raw, 'visibility_status');
        final rawQuality = str(raw, 'inclusion_quality');
        final economicStatus = isLegacyStateFormat
            ? _physicalEconomicFromLegacyStatus(legacyStatus)
            : PhysicalAssetEconomicStatusX.fromStorage(rawEconomic);
        final usageStatus = isLegacyStateFormat
            ? _physicalUsageFromLegacyStatus(legacyStatus)
            : PhysicalAssetUsageStatusX.fromStorage(rawUsage);
        final visibilityStatus = isLegacyStateFormat
            ? legacyStatus == PhysicalAssetStatus.archived
                ? AssetVisibilityStatus.archived
                : AssetVisibilityStatus.active
            : AssetVisibilityStatusX.fromStorage(rawVisibility);
        final validEconomic = PhysicalAssetEconomicStatus.values
            .any((value) => value.storageKey == rawEconomic);
        final validUsage = PhysicalAssetUsageStatus.values
            .any((value) => value.storageKey == rawUsage);
        final validVisibility = AssetVisibilityStatus.values
            .any((value) => value.storageKey == rawVisibility);
        final validQuality = AssetInclusionQuality.values
            .any((value) => value.storageKey == rawQuality);
        final inclusionQuality = isLegacyStateFormat
            ? legacyStatus == PhysicalAssetStatus.archived
                ? AssetInclusionQuality.needsReview
                : AssetInclusionQuality.confirmed
            : !validEconomic || !validUsage || !validVisibility || !validQuality
                ? AssetInclusionQuality.needsReview
                : AssetInclusionQualityX.fromStorage(rawQuality);
        final status = _legacyPhysicalStatusFor(
          economicStatus: economicStatus,
          usageStatus: usageStatus,
          visibilityStatus: visibilityStatus,
        );
        final existingId = assetIdByUuid[uuid];
        final goalResolution = formatVersion >= 6
            ? savingsGoalIdFromAssetJson(raw)
            : (id: null, requested: false, unresolved: false);
        if (goalResolution.unresolved) {
          unresolvedSavingsGoalLinkCount++;
        }
        final existingGoalId = existingId == null
            ? null
            : _allPhysicalAssets
                .where((asset) => asset.id == existingId)
                .firstOrNull
                ?.savingsGoalId;
        final map = {
          'uuid': uuid,
          'book_id': _currentBookId,
          'name': str(raw, 'name', '未命名资产'),
          'asset_type':
              AssetTypeX.fromStorage(str(raw, 'asset_type')).storageKey,
          'status': status.storageKey,
          'economic_status': economicStatus.storageKey,
          'usage_status': usageStatus.storageKey,
          'visibility_status': visibilityStatus.storageKey,
          'inclusion_quality': inclusionQuality.storageKey,
          'source_type': PhysicalAssetSourceTypeX.fromStorage(
            str(raw, 'source_type'),
          ).storageKey,
          'acquisition_cost_source': formatVersion >= 5
              ? AssetAcquisitionCostSourceX.fromStorage(
                  str(raw, 'acquisition_cost_source'),
                ).storageKey
              : AssetAcquisitionCostSource.manual.storageKey,
          'purchase_price': str(raw, 'purchase_price', '0'),
          'current_value': str(raw, 'current_value', '0'),
          'currency_code': str(raw, 'currency_code', 'CNY'),
          'purchase_date_ms': intOrNull(raw['purchase_date_ms']),
          'brand': str(raw, 'brand'),
          'model': str(raw, 'model'),
          'location': str(raw, 'location'),
          'warranty_until_ms': intOrNull(raw['warranty_until_ms']),
          'usage_tracking_enabled':
              formatVersion >= 6 ? intOr(raw['usage_tracking_enabled'], 0) : 0,
          'savings_goal_id':
              goalResolution.unresolved ? existingGoalId : goalResolution.id,
          'photo_path': str(raw, 'photo_path'),
          'thumbnail_path': str(raw, 'thumbnail_path'),
          'invoice_path': str(raw, 'invoice_path'),
          'depreciation_method': str(raw, 'depreciation_method'),
          'depreciation_base': str(raw, 'depreciation_base', '0'),
          'salvage_value': str(raw, 'salvage_value', '0'),
          'useful_life_months': intOr(raw['useful_life_months'], 0),
          'depreciation_start_ms': intOrNull(raw['depreciation_start_ms']),
          'depreciation_paused': intOr(raw['depreciation_paused'], 0),
          'note': str(raw, 'note'),
          'include_in_net_worth': intOr(raw['include_in_net_worth'], 1) == 1 &&
                  economicStatus.ownsValue &&
                  (!isLegacyStateFormat ||
                      legacyStatus != PhysicalAssetStatus.archived)
              ? 1
              : 0,
          'is_deleted': intOr(raw['is_deleted'], 0),
          'ended_ms': isLegacyStateFormat ? null : intOrNull(raw['ended_ms']),
          'archived_ms':
              isLegacyStateFormat ? null : intOrNull(raw['archived_ms']),
          'created_ms': intOr(
            raw['created_ms'],
            DateTime.now().millisecondsSinceEpoch,
          ),
          'updated_ms': intOr(
            raw['updated_ms'],
            DateTime.now().millisecondsSinceEpoch,
          ),
        };
        final newId = existingId ?? await txn.insert('physical_assets', map);
        if (existingId != null) {
          if (isLegacyStateFormat) {
            for (final key in [
              'status',
              'economic_status',
              'usage_status',
              'visibility_status',
              'inclusion_quality',
              'include_in_net_worth',
              'ended_ms',
              'archived_ms',
            ]) {
              map.remove(key);
            }
          }
          await txn.update(
            'physical_assets',
            map,
            where: 'id = ?',
            whereArgs: [existingId],
          );
        }
        if (existingId == null && isLegacyStateFormat) {
          insertedLegacyAssetIds.add(newId);
        }
        assetIdByUuid[uuid] = newId;
        if (oldId != null) oldAssetIdToNew[oldId] = newId;
        assetCount++;
      }

      for (final raw in receivableAssets) {
        final uuid = uuidOf(raw);
        final oldId = intOrNull(raw['id']);
        final legacyStatus =
            ReceivableAssetStatusX.fromStorage(str(raw, 'status'));
        final remaining = Decimal.tryParse(
              str(raw, 'remaining_amount', '0'),
            ) ??
            Decimal.zero;
        final rawEconomic = str(raw, 'economic_status');
        final rawVisibility = str(raw, 'visibility_status');
        final rawQuality = str(raw, 'inclusion_quality');
        final economicStatus = isLegacyStateFormat
            ? _receivableEconomicFromLegacyStatus(legacyStatus)
            : ReceivableEconomicStatusX.fromStorage(rawEconomic);
        final visibilityStatus = isLegacyStateFormat
            ? legacyStatus == ReceivableAssetStatus.archived
                ? AssetVisibilityStatus.archived
                : AssetVisibilityStatus.active
            : AssetVisibilityStatusX.fromStorage(rawVisibility);
        final validEconomic = ReceivableEconomicStatus.values
            .any((value) => value.storageKey == rawEconomic);
        final validVisibility = AssetVisibilityStatus.values
            .any((value) => value.storageKey == rawVisibility);
        final validQuality = AssetInclusionQuality.values
            .any((value) => value.storageKey == rawQuality);
        final inclusionQuality = isLegacyStateFormat
            ? legacyStatus == ReceivableAssetStatus.archived
                ? AssetInclusionQuality.needsReview
                : AssetInclusionQuality.confirmed
            : !validEconomic || !validVisibility || !validQuality
                ? AssetInclusionQuality.needsReview
                : AssetInclusionQualityX.fromStorage(rawQuality);
        final status = _legacyReceivableStatusFor(
          economicStatus: economicStatus,
          visibilityStatus: visibilityStatus,
        );
        final map = {
          'uuid': uuid,
          'book_id': _currentBookId,
          'name': str(raw, 'name', '未命名权益'),
          'receivable_type': ReceivableAssetTypeX.fromStorage(
            str(raw, 'receivable_type'),
          ).storageKey,
          'status': status.storageKey,
          'economic_status': economicStatus.storageKey,
          'visibility_status': visibilityStatus.storageKey,
          'inclusion_quality': inclusionQuality.storageKey,
          'original_amount': str(raw, 'original_amount', '0'),
          'remaining_amount': remaining.toString(),
          'currency_code': str(raw, 'currency_code', 'CNY'),
          'counterparty': str(raw, 'counterparty'),
          'due_date_ms': intOrNull(raw['due_date_ms']),
          'include_in_net_worth': intOr(raw['include_in_net_worth'], 1) == 1 &&
                  economicStatus.canCountInNetWorth &&
                  (!isLegacyStateFormat ||
                      legacyStatus != ReceivableAssetStatus.archived) &&
                  remaining > Decimal.zero
              ? 1
              : 0,
          'note': str(raw, 'note'),
          'is_deleted': intOr(raw['is_deleted'], 0),
          'ended_ms': isLegacyStateFormat ? null : intOrNull(raw['ended_ms']),
          'archived_ms':
              isLegacyStateFormat ? null : intOrNull(raw['archived_ms']),
          'created_ms': intOr(
            raw['created_ms'],
            DateTime.now().millisecondsSinceEpoch,
          ),
          'updated_ms': intOr(
            raw['updated_ms'],
            DateTime.now().millisecondsSinceEpoch,
          ),
        };
        final existingId = receivableIdByUuid[uuid];
        final newId = existingId ?? await txn.insert('receivable_assets', map);
        if (existingId != null) {
          if (isLegacyStateFormat) {
            for (final key in [
              'status',
              'economic_status',
              'visibility_status',
              'inclusion_quality',
              'include_in_net_worth',
              'ended_ms',
              'archived_ms',
            ]) {
              map.remove(key);
            }
          }
          await txn.update(
            'receivable_assets',
            map,
            where: 'id = ?',
            whereArgs: [existingId],
          );
        }
        if (existingId == null && isLegacyStateFormat) {
          insertedLegacyReceivableIds.add(newId);
        }
        receivableIdByUuid[uuid] = newId;
        if (oldId != null) oldReceivableIdToNew[oldId] = newId;
        receivableCount++;
      }

      Future<bool> existsByUuid(String table, String uuid) async {
        if (uuid.isEmpty) return false;
        final rows = await txn.query(
          table,
          columns: ['id'],
          where: 'uuid = ?',
          whereArgs: [uuid],
          limit: 1,
        );
        return rows.isNotEmpty;
      }

      Future<int?> idByUuid(String table, String uuid) async {
        if (uuid.isEmpty) return null;
        final rows = await txn.query(
          table,
          columns: ['id'],
          where: 'uuid = ?',
          whereArgs: [uuid],
          limit: 1,
        );
        return rows.isEmpty ? null : rows.first['id'] as int;
      }

      for (final raw in events) {
        final assetType =
            AssetObjectTypeX.fromStorage(str(raw, 'asset_type', 'physical'));
        final oldAssetId = intOrNull(raw['asset_id']);
        final assetId = oldAssetId == null
            ? null
            : assetType == AssetObjectType.receivable
                ? oldReceivableIdToNew[oldAssetId]
                : oldAssetIdToNew[oldAssetId];
        if (assetId == null) continue;
        final uuid = uuidOf(raw);
        final oldEventId = intOrNull(raw['id']);
        final existingEventId = await idByUuid('asset_events', uuid);
        if (existingEventId != null) {
          if (oldEventId != null) oldEventIdToNew[oldEventId] = existingEventId;
          continue;
        }
        final newEventId = await txn.insert('asset_events', {
          'uuid': uuid,
          'asset_id': assetId,
          'asset_type': assetType.storageKey,
          'event_type': str(raw, 'event_type', 'asset_created'),
          'occurred_ms':
              intOr(raw['occurred_ms'], DateTime.now().millisecondsSinceEpoch),
          'value': str(raw, 'value'),
          'note': str(raw, 'note'),
          'metadata': str(raw, 'metadata'),
          'created_ms':
              intOr(raw['created_ms'], DateTime.now().millisecondsSinceEpoch),
        });
        if (oldEventId != null) oldEventIdToNew[oldEventId] = newEventId;
        eventCount++;
      }

      for (final raw in usageEvents) {
        final oldAssetId = intOrNull(raw['asset_id']);
        final assetId = oldAssetId == null ? null : oldAssetIdToNew[oldAssetId];
        if (assetId == null) continue;
        final uuid = uuidOf(raw);
        final oldUsageId = intOrNull(raw['id']);
        final existingUsageId = await idByUuid('asset_usage_events', uuid);
        if (existingUsageId != null) {
          if (oldUsageId != null) {
            oldUsageIdToNew[oldUsageId] = existingUsageId;
          }
          continue;
        }
        int? reversalOf;
        final reversalUuid = str(raw, 'reversal_of_uuid').trim();
        if (reversalUuid.isNotEmpty) {
          reversalOf = await idByUuid('asset_usage_events', reversalUuid);
        }
        final oldReversalId = intOrNull(raw['reversal_of']);
        reversalOf ??=
            oldReversalId == null ? null : oldUsageIdToNew[oldReversalId];
        if ((reversalUuid.isNotEmpty || oldReversalId != null) &&
            reversalOf == null) {
          continue;
        }
        final countDelta = intOr(raw['count_delta'], 0);
        final occurredMs =
            intOr(raw['occurred_ms'], DateTime.now().millisecondsSinceEpoch);
        if (reversalOf != null) {
          if (countDelta != 0) continue;
          final targetRows = await txn.query(
            'asset_usage_events',
            columns: ['id', 'asset_id', 'occurred_ms'],
            where: 'id = ?',
            whereArgs: [reversalOf],
            limit: 1,
          );
          if (targetRows.isEmpty ||
              (targetRows.single['asset_id'] as int) != assetId) {
            continue;
          }
          final targetOccurredMs =
              targetRows.single['occurred_ms'] as int? ?? 0;
          if (occurredMs < targetOccurredMs) continue;
          final existingReversals = await txn.query(
            'asset_usage_events',
            columns: ['id'],
            where: 'reversal_of = ?',
            whereArgs: [reversalOf],
            orderBy: 'occurred_ms ASC, id ASC',
            limit: 1,
          );
          if (existingReversals.isNotEmpty) {
            if (oldUsageId != null) {
              oldUsageIdToNew[oldUsageId] =
                  existingReversals.single['id'] as int;
            }
            continue;
          }
        }
        final newUsageId = await txn.insert('asset_usage_events', {
          'uuid': uuid,
          'asset_id': assetId,
          'count_delta': countDelta,
          'reversal_of': reversalOf,
          'occurred_ms': occurredMs,
          'note': str(raw, 'note'),
          'created_ms':
              intOr(raw['created_ms'], DateTime.now().millisecondsSinceEpoch),
          'updated_ms': intOr(
            raw['updated_ms'],
            intOr(raw['created_ms'], DateTime.now().millisecondsSinceEpoch),
          ),
        });
        if (oldUsageId != null) oldUsageIdToNew[oldUsageId] = newUsageId;
        usageCount++;
      }

      for (final raw in valuations) {
        final oldAssetId = intOrNull(raw['asset_id']);
        final assetId = oldAssetId == null ? null : oldAssetIdToNew[oldAssetId];
        if (assetId == null) continue;
        final uuid = uuidOf(raw);
        if (await existsByUuid('asset_valuations', uuid)) continue;
        await txn.insert('asset_valuations', {
          'uuid': uuid,
          'asset_id': assetId,
          'value': str(raw, 'value', '0'),
          'source': str(raw, 'source', 'manual'),
          'valued_at_ms':
              intOr(raw['valued_at_ms'], DateTime.now().millisecondsSinceEpoch),
          'note': str(raw, 'note'),
          'created_ms':
              intOr(raw['created_ms'], DateTime.now().millisecondsSinceEpoch),
        });
        valuationCount++;
      }

      for (final raw in links) {
        final oldAssetId = intOrNull(raw['asset_id']);
        final assetId = oldAssetId == null ? null : oldAssetIdToNew[oldAssetId];
        if (assetId == null) {
          rejectedLinkCount++;
          continue;
        }
        final transactionUuid = str(raw, 'transaction_uuid');
        if (transactionUuid.isEmpty) {
          rejectedLinkCount++;
          continue;
        }
        final txRows = await txn.query(
          'transactions',
          columns: [
            'id',
            'book_id',
            'kind',
            'amount',
            'currency_code',
            'refund_of',
            'excluded',
            'event_type',
          ],
          where: 'uuid = ?',
          whereArgs: [transactionUuid],
          limit: 1,
        );
        if (txRows.isEmpty) {
          unresolvedTransactionLinkCount++;
          continue;
        }
        final transaction = txRows.single;
        final transactionId = transaction['id'] as int;
        final uuid = uuidOf(raw);
        final rawLinkType = str(raw, 'link_type', 'source_transaction');
        if (!AssetTransactionLinkType.values
            .any((type) => type.storageKey == rawLinkType)) {
          rejectedLinkCount++;
          continue;
        }
        final linkType = AssetTransactionLinkTypeX.fromStorage(rawLinkType);
        if (str(raw, 'asset_object_type', 'physical') !=
            AssetObjectType.physical.storageKey) {
          rejectedLinkCount++;
          continue;
        }
        final assetRows = await txn.query(
          'physical_assets',
          columns: ['book_id', 'currency_code', 'is_deleted'],
          where: 'id = ?',
          whereArgs: [assetId],
          limit: 1,
        );
        if (assetRows.isEmpty || assetRows.single['is_deleted'] == 1) {
          rejectedLinkCount++;
          continue;
        }
        final asset = assetRows.single;
        final existingByUuid = await txn.query(
          'asset_transaction_links',
          columns: ['id', 'asset_id', 'transaction_id', 'link_type'],
          where: 'uuid = ?',
          whereArgs: [uuid],
          limit: 1,
        );
        if (existingByUuid.isNotEmpty) {
          final existing = existingByUuid.single;
          if (existing['asset_id'] == assetId &&
              existing['transaction_id'] == transactionId &&
              existing['link_type'] == linkType.storageKey) {
            importedLinkIdByUuid[uuid] = existing['id'] as int;
          } else {
            rejectedLinkCount++;
          }
          continue;
        }
        final existingByRelation = await txn.query(
          'asset_transaction_links',
          columns: ['id'],
          where:
              'asset_object_type = ? AND asset_id = ? AND transaction_id = ? AND link_type = ?',
          whereArgs: [
            AssetObjectType.physical.storageKey,
            assetId,
            transactionId,
            linkType.storageKey,
          ],
          limit: 1,
        );
        if (existingByRelation.isNotEmpty) {
          importedLinkIdByUuid[uuid] = existingByRelation.single['id'] as int;
          continue;
        }
        final transactionAmount =
            Decimal.tryParse(transaction['amount'] as String? ?? '') ??
                Decimal.zero;
        final sameCurrency = transaction['currency_code'] ==
            (asset['currency_code'] as String? ?? 'CNY');
        final sameBook = transaction['book_id'] == asset['book_id'];
        var amount = str(raw, 'amount', '0');
        final legacyGross = decimalToBudgetCents(
          Decimal.tryParse(amount) ?? Decimal.zero,
        ).abs();
        var allocatedGrossCents = formatVersion >= 5
            ? intOr(raw['allocated_gross_cents'], 0)
            : legacyGross;
        var allocatedRefundCents =
            formatVersion >= 5 ? intOr(raw['allocated_refund_cents'], 0) : 0;
        var costQuality = formatVersion >= 5
            ? AssetAllocationCostQualityX.fromStorage(
                str(raw, 'cost_quality'),
              )
            : AssetAllocationCostQuality.partial;
        var valid = true;
        if (linkType.isAdditionalCost) {
          final assetBookId = asset['book_id'] as int?;
          final allowedBooks = assetBookId == null
              ? const <int>{}
              : _bookIdsForView(assetBookId).toSet();
          final occupied = await txn.query(
            'asset_transaction_links',
            columns: ['id'],
            where:
                "asset_object_type = 'physical' AND transaction_id = ? AND link_type IN ('source_transaction','purchase_transaction','maintenance','accessory','insurance','other_cost')",
            whereArgs: [transactionId],
            limit: 1,
          );
          valid = transaction['kind'] == TransactionKind.expense.toJson() &&
              transaction['refund_of'] == null &&
              transactionAmount > Decimal.zero &&
              transaction['excluded'] != 1 &&
              transaction['book_id'] != null &&
              allowedBooks.contains(transaction['book_id']) &&
              sameCurrency &&
              occupied.isEmpty;
          if (valid) {
            final gross = decimalToBudgetCents(transactionAmount).abs();
            final refunds = await _validOrderRefundCents(txn, transactionId);
            amount = (budgetDecimalFromCents(max(0, gross - refunds)) ??
                    Decimal.zero)
                .toString();
            allocatedGrossCents = 0;
            allocatedRefundCents = 0;
            costQuality = AssetAllocationCostQuality.exact;
          }
        } else if (linkType == AssetTransactionLinkType.sourceTransaction ||
            linkType == AssetTransactionLinkType.purchaseTransaction) {
          final otherAcquisition = await txn.query(
            'asset_transaction_links',
            columns: ['id'],
            where:
                "asset_object_type = 'physical' AND asset_id = ? AND transaction_id = ? AND link_type IN ('source_transaction','purchase_transaction')",
            whereArgs: [assetId, transactionId],
            limit: 1,
          );
          valid = sameBook &&
              sameCurrency &&
              transaction['kind'] == TransactionKind.expense.toJson() &&
              transaction['refund_of'] == null &&
              transactionAmount > Decimal.zero &&
              allocatedGrossCents > 0 &&
              allocatedRefundCents >= 0 &&
              allocatedRefundCents <= allocatedGrossCents &&
              otherAcquisition.isEmpty;
          if (valid) {
            try {
              await _validateOrderAllocations(
                txn,
                transactionId,
                proposed: AssetAllocationLine(
                  assetId: assetId,
                  grossCents: allocatedGrossCents,
                  refundCents: allocatedRefundCents,
                ),
              );
            } on StateError {
              valid = false;
            } on ArgumentError {
              valid = false;
            }
          }
          amount = (budgetDecimalFromCents(allocatedGrossCents) ?? Decimal.zero)
              .toString();
        } else if (linkType == AssetTransactionLinkType.saleAccountMovement) {
          valid = sameBook &&
              sameCurrency &&
              transaction['kind'] == TransactionKind.income.toJson() &&
              transaction['refund_of'] == null &&
              transactionAmount > Decimal.zero &&
              transaction['excluded'] == 1 &&
              transaction['event_type'] ==
                  TransactionEventType.assetSale.storageKey;
        }
        if (!valid) {
          rejectedLinkCount++;
          continue;
        }
        final linkId = await txn.insert(
          'asset_transaction_links',
          {
            'uuid': uuid,
            'asset_id': assetId,
            'asset_object_type': AssetObjectType.physical.storageKey,
            'transaction_id': transactionId,
            'link_type': linkType.storageKey,
            'amount': amount,
            'allocated_gross_cents': allocatedGrossCents,
            'allocated_refund_cents': allocatedRefundCents,
            'cost_quality': costQuality.storageKey,
            'note': str(raw, 'note'),
            'created_ms':
                intOr(raw['created_ms'], DateTime.now().millisecondsSinceEpoch),
            'updated_ms': intOr(
              raw['updated_ms'],
              intOr(raw['created_ms'], DateTime.now().millisecondsSinceEpoch),
            ),
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        if (linkId <= 0) throw StateError('资产账单关联导入失败');
        importedLinkIdByUuid[uuid] = linkId;
        if (linkType == AssetTransactionLinkType.sourceTransaction ||
            linkType == AssetTransactionLinkType.purchaseTransaction) {
          await txn.update(
            'physical_assets',
            {
              'acquisition_cost_source':
                  AssetAcquisitionCostSource.transactionAllocations.storageKey,
            },
            where: 'id = ?',
            whereArgs: [assetId],
          );
        }
        linkCount++;
      }

      for (final raw in refundAllocations) {
        final linkUuid = str(raw, 'asset_transaction_link_uuid');
        final linkId = importedLinkIdByUuid[linkUuid] ??
            await idByUuid('asset_transaction_links', linkUuid);
        final refundUuid = str(raw, 'refund_transaction_uuid');
        if (linkId == null || linkId <= 0 || refundUuid.isEmpty) continue;
        final parentLinks = await txn.query(
          'asset_transaction_links',
          columns: [
            'transaction_id',
            'link_type',
            'allocated_refund_cents',
          ],
          where: 'id = ?',
          whereArgs: [linkId],
          limit: 1,
        );
        if (parentLinks.isEmpty) continue;
        final parentLink = parentLinks.single;
        final parentType = AssetTransactionLinkTypeX.fromStorage(
          parentLink['link_type'] as String?,
        );
        if (parentType != AssetTransactionLinkType.sourceTransaction &&
            parentType != AssetTransactionLinkType.purchaseTransaction) {
          rejectedLinkCount++;
          continue;
        }
        final refundRows = await txn.query(
          'transactions',
          columns: ['id', 'refund_of', 'amount'],
          where: 'uuid = ?',
          whereArgs: [refundUuid],
          limit: 1,
        );
        if (refundRows.isEmpty) {
          unresolvedTransactionLinkCount++;
          continue;
        }
        final uuid = uuidOf(raw);
        if (await existsByUuid('asset_refund_allocations', uuid)) continue;
        final refund = refundRows.single;
        final cents = intOr(raw['allocated_refund_cents'], 0);
        final allocationStatus = str(raw, 'status', 'active');
        final refundTotal = decimalToBudgetCents(
          Decimal.tryParse(refund['amount'] as String? ?? '') ?? Decimal.zero,
        ).abs();
        final alreadyForRefund = Sqflite.firstIntValue(await txn.rawQuery('''
          SELECT COALESCE(SUM(allocated_refund_cents), 0)
          FROM asset_refund_allocations
          WHERE refund_transaction_id = ? AND status = 'active'
        ''', [refund['id']])) ?? 0;
        final alreadyForLink = Sqflite.firstIntValue(await txn.rawQuery('''
          SELECT COALESCE(SUM(allocated_refund_cents), 0)
          FROM asset_refund_allocations
          WHERE asset_transaction_link_id = ? AND status = 'active'
        ''', [linkId])) ?? 0;
        if ((allocationStatus != 'active' && allocationStatus != 'reversed') ||
            refund['refund_of'] != parentLink['transaction_id'] ||
            cents <= 0 ||
            (allocationStatus == 'active' &&
                (alreadyForRefund + cents > refundTotal ||
                    alreadyForLink + cents >
                        (parentLink['allocated_refund_cents'] as int? ?? 0)))) {
          rejectedLinkCount++;
          continue;
        }
        await txn.insert('asset_refund_allocations', {
          'uuid': uuid,
          'asset_transaction_link_id': linkId,
          'refund_transaction_id': refund['id'] as int,
          'allocated_refund_cents': cents,
          'status': allocationStatus,
          'created_ms':
              intOr(raw['created_ms'], DateTime.now().millisecondsSinceEpoch),
          'updated_ms':
              intOr(raw['updated_ms'], DateTime.now().millisecondsSinceEpoch),
        });
      }

      for (final raw in recoveries) {
        final oldAssetId = intOrNull(raw['receivable_asset_id']);
        final assetId =
            oldAssetId == null ? null : oldReceivableIdToNew[oldAssetId];
        if (assetId == null) continue;
        final uuid = uuidOf(raw);
        if (await existsByUuid('receivable_recoveries', uuid)) continue;
        int? transactionId;
        var targetAccountId = accountIdFromAssetJson(
          raw,
          idKey: 'target_account_id',
          nameKey: 'target_account_name',
        );
        final transactionUuid = str(raw, 'transaction_uuid');
        if (transactionUuid.isNotEmpty) {
          final txRows = await txn.query(
            'transactions',
            columns: ['id', 'account_id'],
            where: 'uuid = ?',
            whereArgs: [transactionUuid],
            limit: 1,
          );
          if (txRows.isNotEmpty) {
            transactionId = txRows.first['id'] as int;
            targetAccountId ??= txRows.first['account_id'] as int?;
          }
        }
        final oldEventId = intOrNull(raw['event_id']);
        await txn.insert('receivable_recoveries', {
          'uuid': uuid,
          'receivable_asset_id': assetId,
          'amount': str(raw, 'amount', '0'),
          'recovered_ms':
              intOr(raw['recovered_ms'], DateTime.now().millisecondsSinceEpoch),
          'target_account_id': targetAccountId,
          'event_id': oldEventId == null ? null : oldEventIdToNew[oldEventId],
          'transaction_id': transactionId,
          'note': str(raw, 'note'),
          'created_ms':
              intOr(raw['created_ms'], DateTime.now().millisecondsSinceEpoch),
        });
        recoveryCount++;
      }

      if (isLegacyStateFormat) {
        Future<int?> latestEventMs(
          String assetType,
          int assetId,
          String eventType,
        ) async {
          final rows = await txn.rawQuery(
            '''
            SELECT MAX(occurred_ms) AS occurred_ms
            FROM asset_events
            WHERE asset_type = ? AND asset_id = ? AND event_type = ?
            ''',
            [assetType, assetId, eventType],
          );
          return rows.isEmpty ? null : rows.first['occurred_ms'] as int?;
        }

        for (final assetId in insertedLegacyAssetIds) {
          final rows = await txn.query(
            'physical_assets',
            columns: ['economic_status', 'visibility_status'],
            where: 'id = ?',
            whereArgs: [assetId],
            limit: 1,
          );
          if (rows.isEmpty) continue;
          final economic = rows.first['economic_status'] as String? ?? 'owned';
          final visibility =
              rows.first['visibility_status'] as String? ?? 'active';
          final endedEvent = switch (economic) {
            'sold' => AssetEventType.assetSold.storageKey,
            'scrapped' => AssetEventType.assetDisposed.storageKey,
            'lost' => AssetEventType.assetLost.storageKey,
            'gifted' => AssetEventType.assetGifted.storageKey,
            _ => null,
          };
          await txn.update(
            'physical_assets',
            {
              'ended_ms': endedEvent == null
                  ? null
                  : await latestEventMs('physical', assetId, endedEvent),
              'archived_ms': visibility == 'archived'
                  ? await latestEventMs(
                      'physical',
                      assetId,
                      AssetEventType.assetArchived.storageKey,
                    )
                  : null,
            },
            where: 'id = ?',
            whereArgs: [assetId],
          );
        }

        for (final assetId in insertedLegacyReceivableIds) {
          final rows = await txn.query(
            'receivable_assets',
            where: 'id = ?',
            whereArgs: [assetId],
            limit: 1,
          );
          if (rows.isEmpty) continue;
          final row = rows.first;
          final visibility = row['visibility_status'] as String? ?? 'active';
          final original = _assetAmount(row, 'original_amount');
          final remaining = _assetAmount(row, 'remaining_amount');
          final recoveryRows = await txn.query(
            'receivable_recoveries',
            where: 'receivable_asset_id = ?',
            whereArgs: [assetId],
          );
          var recovered = Decimal.zero;
          var recoveriesValid = true;
          var latestRecoveryMs = 0;
          for (final recovery in recoveryRows) {
            final amount = _assetAmount(recovery, 'amount');
            if (amount <= Decimal.zero) recoveriesValid = false;
            recovered += amount;
            final recoveredMs = recovery['recovered_ms'] as int? ?? 0;
            if (recoveredMs > latestRecoveryMs) {
              latestRecoveryMs = recoveredMs;
            }
          }
          final lostMs = await latestEventMs(
            'receivable',
            assetId,
            AssetEventType.receivableLost.storageKey,
          );
          ReceivableEconomicStatus economicStatus;
          int? endedMs;
          if (visibility != 'archived') {
            economicStatus = ReceivableEconomicStatusX.fromStorage(
              row['economic_status'] as String?,
            );
            endedMs = switch (economicStatus) {
              ReceivableEconomicStatus.recovered =>
                latestRecoveryMs == 0 ? null : latestRecoveryMs,
              ReceivableEconomicStatus.lost => lostMs,
              _ => null,
            };
          } else {
            economicStatus = ReceivableEconomicStatus.unknown;
            endedMs = null;
            final recoveryAfterLoss = lostMs != null &&
                recoveryRows.any((recovery) =>
                    (recovery['recovered_ms'] as int? ?? 0) > lostMs);
            final amountsValid = original >= Decimal.zero &&
                remaining >= Decimal.zero &&
                remaining <= original &&
                recoveriesValid &&
                recovered <= original;
            if (amountsValid && lostMs != null && !recoveryAfterLoss) {
              if (remaining == Decimal.zero) {
                economicStatus = ReceivableEconomicStatus.lost;
                endedMs = lostMs;
              }
            } else if (amountsValid && lostMs == null) {
              if (original > Decimal.zero &&
                  remaining == Decimal.zero &&
                  recovered == original) {
                economicStatus = ReceivableEconomicStatus.recovered;
                endedMs = latestRecoveryMs == 0 ? null : latestRecoveryMs;
              } else if (remaining > Decimal.zero &&
                  remaining < original &&
                  recovered == original - remaining) {
                economicStatus = ReceivableEconomicStatus.partialRecovered;
              } else if (remaining == original && recovered == Decimal.zero) {
                economicStatus = ReceivableEconomicStatus.active;
              }
            }
          }
          await txn.update(
            'receivable_assets',
            {
              'economic_status': economicStatus.storageKey,
              'ended_ms': endedMs,
              'archived_ms': visibility == 'archived'
                  ? await latestEventMs(
                      'receivable',
                      assetId,
                      AssetEventType.receivableArchived.storageKey,
                    )
                  : null,
            },
            where: 'id = ?',
            whereArgs: [assetId],
          );
        }
      }

      for (final raw in snapshots) {
        final snapshotDate = str(raw, 'snapshot_date');
        if (snapshotDate.isEmpty) continue;
        await txn.insert(
          'net_worth_snapshots',
          {
            'scope_key': str(raw, 'scope_key', 'global'),
            'snapshot_date': snapshotDate,
            'total_assets': str(raw, 'total_assets', '0'),
            'total_liabilities': str(raw, 'total_liabilities', '0'),
            'net_worth': str(raw, 'net_worth', '0'),
            'cash_assets': str(raw, 'cash_assets', '0'),
            'investment_assets': str(raw, 'investment_assets', '0'),
            'physical_assets': str(raw, 'physical_assets', '0'),
            'receivable_assets': str(raw, 'receivable_assets', '0'),
            'snapshot_type': str(raw, 'snapshot_type', 'legacy_unverified'),
            'lineage_key': str(raw, 'lineage_key', 'legacy:global'),
            'as_of_ms': intOr(raw['as_of_ms'], 0),
            'knowledge_cutoff_ms': intOr(
              raw['knowledge_cutoff_ms'],
              intOr(raw['created_ms'], 0),
            ),
            'timezone': str(raw, 'timezone', 'device_local'),
            'scope_version': intOr(raw['scope_version'], 1),
            'calculation_version':
                intOr(raw['calculation_version'], statisticsCalculationVersion),
            'currency_coverage_json': str(raw, 'currency_coverage_json'),
            'quality': str(raw, 'quality', 'legacy_unverified'),
            'cause_set_json': str(raw, 'cause_set_json'),
            'reasons_json': str(raw, 'reasons_json'),
            'valuation_coverage_json': str(raw, 'valuation_coverage_json'),
            'provisional': intOr(raw['provisional'], 0),
            'created_ms':
                intOr(raw['created_ms'], DateTime.now().millisecondsSinceEpoch),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        snapshotCount++;
      }

      for (final raw in liabilityProfiles) {
        final uuid = uuidOf(raw);
        if (await existsByUuid('liability_profiles', uuid)) continue;
        final accountId = accountIdFromAssetJson(
          raw,
          idKey: 'account_id',
          nameKey: 'account_name',
        );
        if (accountId == null) continue;
        final repaymentAccountId = accountIdFromAssetJson(
          raw,
          idKey: 'repayment_account_id',
          nameKey: 'repayment_account_name',
        );
        await txn.insert(
          'liability_profiles',
          {
            'uuid': uuid,
            'account_id': accountId,
            'liability_type': LiabilityProfileTypeX.fromStorage(
              str(raw, 'liability_type'),
            ).storageKey,
            'original_amount': str(raw, 'original_amount', '0'),
            'current_principal': str(raw, 'current_principal', '0'),
            'interest_rate': str(raw, 'interest_rate', '0'),
            'repayment_day': intOrNull(raw['repayment_day']),
            'repayment_account_id': repaymentAccountId,
            'start_date_ms': intOrNull(raw['start_date_ms']),
            'end_date_ms': intOrNull(raw['end_date_ms']),
            'status': LiabilityProfileStatusX.fromStorage(
              str(raw, 'status'),
            ).storageKey,
            'note': str(raw, 'note'),
            'statement_day': intOrNull(raw['statement_day']),
            'credit_limit': raw['credit_limit'] == null
                ? null
                : Decimal.tryParse(str(raw, 'credit_limit'))?.toString(),
            'counterparty': str(raw, 'counterparty'),
            'created_ms':
                intOr(raw['created_ms'], DateTime.now().millisecondsSinceEpoch),
            'updated_ms':
                intOr(raw['updated_ms'], DateTime.now().millisecondsSinceEpoch),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        liabilityCount++;
      }
    });

    await _loadTransactions();
    await _loadPhysicalAssetData();
    await _loadNetWorthSnapshots();
    await _loadLiabilityProfiles();
    notifyListeners();
    return FeimiaoAssetImportResult(
      assets: assetCount,
      receivables: receivableCount,
      events: eventCount,
      usages: usageCount,
      valuations: valuationCount,
      links: linkCount,
      recoveries: recoveryCount,
      snapshots: snapshotCount,
      liabilities: liabilityCount,
      unresolvedTransactionLinks: unresolvedTransactionLinkCount,
      unresolvedSavingsGoalLinks: unresolvedSavingsGoalLinkCount,
      rejectedLinks: rejectedLinkCount,
    );
  }

  // ---------------------------------------------------------------------------
  // 账户 CRUD
  // ---------------------------------------------------------------------------

  Future<int> addAccount({
    required String name,
    String currencyCode = 'CNY',
    AccountType type = AccountType.cash,
    Decimal? openingBalance,
    bool includeInNetWorth = true,
    String institution = '',
  }) async {
    final normalizedCurrency = currencyCode.trim().toUpperCase();
    if (normalizedCurrency != 'CNY') {
      throw UnsupportedError('当前版本仅支持新增人民币账户。');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await _db!.insert('accounts', {
      'uuid': _newUuid(),
      'name': name,
      'currency_code': normalizedCurrency,
      'type': type.storageKey,
      'opening_balance':
          normalizeMoneyAmount(openingBalance ?? Decimal.zero).toString(),
      'include_in_net_worth': includeInNetWorth ? 1 : 0,
      'institution': institution,
      'created_ms': now,
      'updated_ms': now,
      'opening_balance_effective_ms': now,
      'opening_balance_sequence': 0,
      'opening_balance_quality': AccountOpeningBalanceQuality.exact.storageKey,
      'status': AccountStatus.active.storageKey,
    });
    await _loadAccounts();
    await _refreshCurrentNetWorthSnapshotBestEffort(
      const {NetWorthSnapshotCause.account},
    );
    notifyListeners();
    return id;
  }

  Future<void> renameAccount(int id, String newName) async {
    await _db!.update(
      'accounts',
      {
        'name': newName,
        'updated_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _loadAccounts();
    notifyListeners();
  }

  Future<void> updateAccount({
    required int id,
    required String name,
    required String currencyCode,
    required AccountType type,
    required Decimal openingBalance,
    required bool includeInNetWorth,
    required String institution,
  }) async {
    final existing = _accounts.where((account) => account.id == id).firstOrNull;
    if (existing == null) throw StateError('账户不存在');
    final normalizedCurrency = currencyCode.trim().toUpperCase();
    final allowedCurrency = existing.currencyCode == 'CNY'
        ? 'CNY'
        : existing.currencyCode.toUpperCase();
    if (normalizedCurrency != allowedCurrency) {
      throw UnsupportedError('当前版本不能新增或转换外币账户。');
    }
    if (existing.includeInNetWorth != includeInNetWorth) {
      await _bumpNetWorthScopeVersion();
    }
    await _db!.update(
      'accounts',
      {
        'name': name,
        'currency_code': allowedCurrency,
        'type': type.storageKey,
        'include_in_net_worth': includeInNetWorth ? 1 : 0,
        'institution': institution,
        'updated_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _loadAccounts();
    await _refreshCurrentNetWorthSnapshotBestEffort(
      const {NetWorthSnapshotCause.account},
    );
    notifyListeners();
  }

  Future<void> deleteAccount(int id) async {
    await archiveAccount(id);
  }

  Future<void> archiveAccount(int id) async {
    final existing = _accounts.where((account) => account.id == id).firstOrNull;
    if (existing == null || existing.isArchived) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db!.transaction((txn) async {
      final referencedRuleCount = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM recurring_rules WHERE account_id = ?',
              [id],
            ),
          ) ??
          0;
      if (referencedRuleCount > 0) {
        throw StateError('该账户仍被定时记账使用，请先修改或删除相关规则。');
      }
      await txn.update(
        'accounts',
        {
          'status': AccountStatus.archived.storageKey,
          'archived_ms': now,
          'updated_ms': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    await _loadAccounts();
    await _refreshCurrentNetWorthSnapshotBestEffort(
      const {NetWorthSnapshotCause.account},
    );
    notifyListeners();
  }

  Future<void> restoreArchivedAccount(int id) async {
    final existing = _accounts.where((account) => account.id == id).firstOrNull;
    if (existing == null || !existing.isArchived) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db!.update(
      'accounts',
      {
        'status': AccountStatus.active.storageKey,
        'archived_ms': null,
        'updated_ms': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _loadAccounts();
    await _refreshCurrentNetWorthSnapshotBestEffort(
      const {NetWorthSnapshotCause.account},
    );
    notifyListeners();
  }

  Future<int> createAccountBalanceCheckpoint({
    required int accountId,
    required Decimal targetBalance,
    String note = '',
    DateTime? effectiveAt,
  }) async {
    targetBalance = normalizeMoneyAmount(targetBalance);
    final account =
        _accounts.where((candidate) => candidate.id == accountId).firstOrNull;
    if (account == null) throw StateError('账户不存在');
    final now = DateTime.now();
    final effective = effectiveAt ?? now;
    if (effective.isAfter(now.add(const Duration(seconds: 1)))) {
      throw ArgumentError('核对时点不能晚于现在');
    }
    final historical =
        now.difference(effective).abs() > const Duration(minutes: 1);
    if (historical) {
      throw UnsupportedError('当前版本只支持“现在核对”，历史日终需逐项确认未知到账事件后再开放。');
    }
    final calculated = accountBalanceResultOf(account).value!.balance;
    final effectiveMs = effective.millisecondsSinceEpoch;
    final cutoffMs = now.millisecondsSinceEpoch;
    final checkpointSequence = _accountBalanceCheckpoints
        .where((checkpoint) =>
            checkpoint.accountId == accountId &&
            checkpoint.effectiveMs == effectiveMs)
        .map((checkpoint) => checkpoint.sequence)
        .fold<int>(0, max);
    final movementSequence = _allTransactions
        .where((transaction) =>
            transaction.settledMs == effectiveMs &&
            (transaction.createdMs == 0 || transaction.createdMs <= cutoffMs))
        .map((transaction) => transaction.id)
        .fold<int>(0, max);
    final sequence = max(checkpointSequence, movementSequence) + 1;
    final coveredUnknownIds = <String>{};
    for (final transaction in _allTransactions) {
      final unknownDate = transaction.settledMs == null ||
          transaction.settlementQuality == SettlementQuality.unknown;
      final knownAtCutoff =
          transaction.createdMs == 0 || transaction.createdMs <= cutoffMs;
      final confirmedSource =
          transaction.settlementAccountQuality == SettlementQuality.exact ||
              transaction.settlementAccountQuality ==
                  SettlementQuality.userConfirmed;
      if (!unknownDate || !knownAtCutoff || !confirmedSource) continue;
      final eventId = transaction.uuid.isEmpty
          ? transaction.id.toString()
          : transaction.uuid;
      if (transaction.eventType == TransactionEventType.transfer) {
        if (transaction.settlementAccountId == accountId) {
          coveredUnknownIds.add('$eventId:out');
        }
        if (transaction.toAccountId == accountId) {
          coveredUnknownIds.add('$eventId:in');
        }
      } else if (transaction.settlementAccountId == accountId) {
        coveredUnknownIds.add(eventId);
      }
    }
    late final int checkpointId;
    await _db!.transaction((txn) async {
      checkpointId = await txn.insert('account_balance_checkpoints', {
        'uuid': _newUuid(),
        'account_id': accountId,
        'event_kind': AccountBalanceCheckpointKind.anchor.storageKey,
        'effective_ms': effectiveMs,
        'sequence': sequence,
        'timezone': 'device_local',
        'knowledge_cutoff_ms': cutoffMs,
        'target_balance': targetBalance.toString(),
        'calculated_before': calculated.toString(),
        'delta_at_creation': (targetBalance - calculated).toString(),
        'reason': 'manual',
        'note': note.trim(),
        'status': 'active',
        'reversal_of': null,
        'created_ms': cutoffMs,
        'updated_ms': cutoffMs,
      });
      for (final eventId in coveredUnknownIds) {
        await txn.insert(
          'account_checkpoint_covered_unknown_events',
          {
            'checkpoint_id': checkpointId,
            'account_event_uuid': eventId,
            'created_ms': cutoffMs,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await txn.update(
        'accounts',
        {
          'last_verified_ms': effectiveMs,
          'updated_ms': cutoffMs,
        },
        where: 'id = ?',
        whereArgs: [accountId],
      );
    });
    await Future.wait([
      _loadAccounts(),
      _loadAccountBalanceCheckpoints(),
    ]);
    await _refreshCurrentNetWorthSnapshotBestEffort(
      const {NetWorthSnapshotCause.account},
    );
    notifyListeners();
    return checkpointId;
  }

  Future<void> reverseAccountBalanceCheckpoint(
    int checkpointId, {
    String note = '',
  }) async {
    final original = _accountBalanceCheckpoints
        .where((checkpoint) => checkpoint.id == checkpointId)
        .firstOrNull;
    if (original == null || !original.isAnchor) {
      throw StateError('校准记录不存在');
    }
    final alreadyReversed = _accountBalanceCheckpoints.any(
      (checkpoint) =>
          checkpoint.isReversal &&
          checkpoint.reversalOf == checkpointId &&
          checkpoint.status == 'active',
    );
    if (alreadyReversed) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final sequence = _accountBalanceCheckpoints
            .where((checkpoint) =>
                checkpoint.accountId == original.accountId &&
                checkpoint.effectiveMs == now)
            .map((checkpoint) => checkpoint.sequence)
            .fold<int>(0, max) +
        1;
    await _db!.insert('account_balance_checkpoints', {
      'uuid': _newUuid(),
      'account_id': original.accountId,
      'event_kind': AccountBalanceCheckpointKind.reversal.storageKey,
      'effective_ms': now,
      'sequence': sequence,
      'timezone': 'device_local',
      'knowledge_cutoff_ms': now,
      'target_balance': original.targetBalance.toString(),
      'calculated_before': original.calculatedBefore.toString(),
      'delta_at_creation': original.deltaAtCreation.toString(),
      'reason': 'manual_reversal',
      'note': note.trim(),
      'status': 'active',
      'reversal_of': checkpointId,
      'created_ms': now,
      'updated_ms': now,
    });
    await _loadAccountBalanceCheckpoints();
    await _refreshCurrentNetWorthSnapshotBestEffort(
      const {NetWorthSnapshotCause.account},
    );
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 分类 CRUD
  // ---------------------------------------------------------------------------

  Future<int> addCategory({
    required String key,
    required String nameZh,
    required String nameEn,
    required TransactionKind kind,
    int? parentId,
  }) async {
    final id = await _db!.insert('categories', {
      'key': key,
      'name_zh': nameZh,
      'name_en': nameEn,
      'kind': kind.toJson(),
      'parent_id': parentId,
    });
    await _loadCategories();
    notifyListeners();
    return id;
  }

  Future<void> renameCategory(int id,
      {required String nameZh, String? nameEn}) async {
    final updates = <String, Object?>{'name_zh': nameZh};
    if (nameEn != null) updates['name_en'] = nameEn;
    await _db!.update('categories', updates, where: 'id = ?', whereArgs: [id]);
    await _loadCategories();
    notifyListeners();
  }

  /// 删除分类（连同它的子分类，防止留下挂着失效 parent_id 的幽灵行）。
  /// 有历史账单的分类别直接删——UI 层用 [transactionCountForCategory]
  /// 检查后引导「隐藏」或「合并」。
  Future<void> deleteCategory(int id) async {
    final targets = <CategoryEntity>[
      for (final category in _categories)
        if (category.id == id || category.parentId == id) category,
    ];
    if (targets.isEmpty) return;
    final ids = targets.map((category) => category.id).toList();
    final marks = List.filled(ids.length, '?').join(',');
    final transactionCount = Sqflite.firstIntValue(await _db!.rawQuery(
          'SELECT COUNT(*) FROM transactions WHERE category_id IN ($marks)',
          ids,
        )) ??
        0;
    final recurringCount = Sqflite.firstIntValue(await _db!.rawQuery(
          'SELECT COUNT(*) FROM recurring_rules WHERE category_id IN ($marks)',
          ids,
        )) ??
        0;
    final budgetKeys = targets.map((category) => category.key).toSet();
    var hasBudget = false;
    final budgetRows = await _db!.query(
      'budget_periods',
      columns: ['category_budgets'],
      where: "category_budgets <> ''",
    );
    for (final row in budgetRows) {
      try {
        final decoded = jsonDecode(row['category_budgets'] as String);
        if (decoded is Map &&
            decoded.keys.any((key) => budgetKeys.contains(key))) {
          hasBudget = true;
          break;
        }
      } catch (_) {}
    }
    final revisionRows = await _db!.query(
      'budget_plan_revisions',
      columns: ['category_budgets_json'],
      where: "category_budgets_json <> '{}'",
    );
    for (final row in revisionRows) {
      try {
        final decoded = jsonDecode(row['category_budgets_json'] as String);
        if (decoded is Map &&
            decoded.keys.any((key) => budgetKeys.contains(key))) {
          hasBudget = true;
          break;
        }
      } catch (_) {}
    }
    if (_budgetPlansV2.any((plan) =>
        plan.isSpecial &&
        plan.expenseScope.categoryKeys.any(budgetKeys.contains))) {
      hasBudget = true;
    }
    if (transactionCount > 0 || recurringCount > 0 || hasBudget) {
      throw StateError('这个分类仍被账单、定时记账、分类预算或专项追踪使用，请先隐藏或合并。');
    }
    await _db!.transaction((txn) async {
      await txn.delete('category_memory',
          where:
              'category_key IN (${List.filled(budgetKeys.length, '?').join(',')})',
          whereArgs: budgetKeys.toList());
      await txn.delete('categories', where: 'id IN ($marks)', whereArgs: ids);
    });
    await _loadCategories();
    await _loadCategoryMemory();
    notifyListeners();
  }

  /// 这个分类（含子分类）名下有多少笔账单——跨全部账本查 DB，不是只看当前账本。
  Future<int> transactionCountForCategory(int id) async {
    final ids = <int>[id, ...childrenOf(id).map((c) => c.id)];
    final marks = List.filled(ids.length, '?').join(',');
    return Sqflite.firstIntValue(await _db!.rawQuery(
            'SELECT COUNT(*) FROM transactions WHERE category_id IN ($marks)',
            ids)) ??
        0;
  }

  /// 隐藏 / 恢复显示分类（隐藏后不再出现在记账面板，历史账单不动）。
  Future<void> setCategoryHidden(int id, bool hidden) async {
    await _db!.update('categories', {'hidden': hidden ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
    await _loadCategories();
    notifyListeners();
  }

  /// 把分类 [fromId] 合并进 [toId]：账单改挂、子分类改挂、
  /// AI 纠正记忆（category_memory）迁移，然后删掉 from。不可撤销。
  Future<void> mergeCategory(int fromId, int toId) async {
    if (fromId == toId) return;
    final from = _categories.where((c) => c.id == fromId).firstOrNull;
    final to = _categories.where((c) => c.id == toId).firstOrNull;
    if (from == null || to == null) return;
    if (from.kind != to.kind) {
      throw ArgumentError('支出和收入分类不能互相合并');
    }
    final targetScopeKey = to.parentId == null
        ? to.key
        : _categories
                .where((category) => category.id == to.parentId)
                .firstOrNull
                ?.key ??
            to.key;

    final now = DateTime.now().millisecondsSinceEpoch;
    await _db!.transaction((txn) async {
      await txn.update('transactions', {'category_id': toId, 'updated_ms': now},
          where: 'category_id = ?', whereArgs: [fromId]);
      await txn.update('recurring_rules', {'category_id': toId},
          where: 'category_id = ?', whereArgs: [fromId]);
      final budgetRows = await txn.query(
        'budget_periods',
        columns: ['id', 'category_budgets'],
        where: "category_budgets <> ''",
      );
      for (final row in budgetRows) {
        try {
          final decoded = jsonDecode(row['category_budgets'] as String);
          if (decoded is! Map || !decoded.containsKey(from.key)) continue;
          final budgets = <String, dynamic>{
            for (final entry in decoded.entries)
              entry.key.toString(): entry.value,
          };
          final fromAmount =
              Decimal.tryParse(budgets.remove(from.key).toString()) ??
                  Decimal.zero;
          final toAmount =
              Decimal.tryParse(budgets[to.key]?.toString() ?? '') ??
                  Decimal.zero;
          budgets[to.key] = (fromAmount + toAmount).toString();
          await txn.update(
            'budget_periods',
            {'category_budgets': jsonEncode(budgets)},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        } catch (_) {}
      }
      final revisionRows = await txn.query(
        'budget_plan_revisions',
        columns: ['id', 'category_budgets_json'],
        where: "category_budgets_json <> '{}'",
      );
      for (final row in revisionRows) {
        try {
          final decoded = jsonDecode(row['category_budgets_json'] as String);
          if (decoded is! Map || !decoded.containsKey(from.key)) continue;
          final budgets = <String, dynamic>{
            for (final entry in decoded.entries)
              entry.key.toString(): entry.value,
          };
          final fromAmount =
              int.tryParse(budgets.remove(from.key).toString()) ?? 0;
          final toAmount = int.tryParse(budgets[to.key]?.toString() ?? '') ?? 0;
          budgets[to.key] = fromAmount + toAmount;
          await txn.update(
            'budget_plan_revisions',
            {'category_budgets_json': jsonEncode(budgets)},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        } catch (_) {}
      }
      final specialRows = await txn.query(
        'budget_plans',
        columns: ['id', 'expense_scope_json'],
        where: "role = 'special' AND expense_scope_json <> ''",
      );
      for (final row in specialRows) {
        try {
          final scope = BudgetExpenseScopeV2.fromJsonString(
            row['expense_scope_json'] as String?,
          );
          if (!scope.categoryKeys.contains(from.key)) continue;
          final categoryKeys = scope.categoryKeys.toSet()
            ..remove(from.key)
            ..add(targetScopeKey);
          await txn.update(
            'budget_plans',
            {
              'expense_scope_json': BudgetExpenseScopeV2(
                categoryKeys: categoryKeys,
                tagIds: scope.tagIds,
              ).toJsonString(),
            },
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        } catch (_) {}
      }
      // from 的子分类改认 to 当父类（to 是子分类时挂到 to 的父类下，别出现三级）。
      final newParent = to.isTopLevel ? to.id : to.parentId!;
      await txn.update('categories', {'parent_id': newParent},
          where: 'parent_id = ?', whereArgs: [fromId]);
      await txn.update('category_memory', {'category_key': to.key},
          where: 'category_key = ?', whereArgs: [from.key]);
      await txn.delete('categories', where: 'id = ?', whereArgs: [fromId]);
    });

    await _loadCategories();
    await _loadCategoryMemory();
    await _loadRecurringRules();
    await _loadBudgetPeriods();
    await _loadBudgetV2();
    await _loadTransactions();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 存钱目标 CRUD
  // ---------------------------------------------------------------------------

  Future<int> addSavingsGoal({
    required String name,
    required Decimal target,
    String emoji = '🐷',
    Decimal? initialSaved,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final id = await _db!.insert('savings_goals', {
      'uuid': _newUuid(),
      'name': name,
      'emoji': emoji,
      'target_amount': target.toString(),
      'saved_amount': (initialSaved ?? Decimal.zero).toString(),
      'created_ms': nowMs,
      'updated_ms': nowMs,
    });
    await _loadSavingsGoals();
    notifyListeners();
    return id;
  }

  Future<void> updateSavingsGoal(
    int id, {
    required String name,
    required Decimal target,
    String? emoji,
  }) async {
    final updates = <String, Object?>{
      'name': name,
      'target_amount': target.toString(),
      'updated_ms': DateTime.now().millisecondsSinceEpoch,
    };
    if (emoji != null) updates['emoji'] = emoji;
    await _db!
        .update('savings_goals', updates, where: 'id = ?', whereArgs: [id]);
    await _loadSavingsGoals();
    notifyListeners();
  }

  Future<void> deleteSavingsGoal(int id) async {
    final now = DateTime.now();
    await _db!.transaction((txn) async {
      final linked = await txn.query(
        'physical_assets',
        columns: ['id'],
        where: 'savings_goal_id = ? AND is_deleted = 0',
        whereArgs: [id],
      );
      await txn.update(
        'physical_assets',
        {
          'savings_goal_id': null,
          'updated_ms': now.millisecondsSinceEpoch,
        },
        where: 'savings_goal_id = ?',
        whereArgs: [id],
      );
      for (final row in linked) {
        await _insertAssetEvent(
          txn,
          assetId: row['id'] as int,
          type: AssetEventType.assetSavingsGoalUnlinked,
          occurredAt: now,
          note: '存钱目标已删除，自动解除关联',
          metadata: {'previous_savings_goal_id': id},
        );
      }
      await txn.delete('savings_goals', where: 'id = ?', whereArgs: [id]);
    });
    await _loadSavingsGoals();
    await _loadPhysicalAssetData();
    notifyListeners();
  }

  Future<void> adjustSavingsGoal(int id, Decimal delta) async {
    final goal = _savingsGoals.where((g) => g.id == id).firstOrNull;
    if (goal == null) return;
    var next = goal.saved + delta;
    if (next < Decimal.zero) next = Decimal.zero;
    await _db!.update(
      'savings_goals',
      {
        'saved_amount': next.toString(),
        'updated_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _loadSavingsGoals();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 标签 CRUD
  // ---------------------------------------------------------------------------

  Future<int> addTag({required String name, required int colorValue}) async {
    final id = await _db!.insert('tags', {'name': name, 'color': colorValue});
    await _loadTags();
    notifyListeners();
    return id;
  }

  Future<void> updateTag(int id,
      {required String name, int? colorValue}) async {
    final updates = <String, Object?>{'name': name};
    if (colorValue != null) updates['color'] = colorValue;
    await _db!.update('tags', updates, where: 'id = ?', whereArgs: [id]);
    await _loadTags();
    notifyListeners();
  }

  Future<void> deleteTag(int id) async {
    if (_budgetPlansV2.any(
        (plan) => plan.isSpecial && plan.expenseScope.tagIds.contains(id))) {
      throw StateError('这个标签仍被专项追踪历史使用，暂时不能删除。');
    }
    // 删标签 + 从所有账单 tags 里摘除要在同一事务里完成（要么全成要么全不成），
    // 摘除过的账单同步 bump updated_ms（同步戳），别留「内容变了戳没变」的行。
    await _db!.transaction((txn) async {
      await txn.delete('tags', where: 'id = ?', whereArgs: [id]);
      final rows = await txn.rawQuery(
        "SELECT id, tags FROM transactions WHERE tags LIKE ?",
        ['%$id%'],
      );
      final updatedMs = DateTime.now().millisecondsSinceEpoch;
      for (final r in rows) {
        final raw = (r['tags'] as String?) ?? '';
        if (raw.isEmpty) continue;
        final kept = raw
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .whereType<int>()
            .where((tid) => tid != id)
            .join(',');
        if (kept != raw) {
          await txn.update(
            'transactions',
            {'tags': kept, 'updated_ms': updatedMs},
            where: 'id = ?',
            whereArgs: [r['id']],
          );
        }
      }
    });
    await _loadTags();
    await _loadTransactions();
    notifyListeners();
  }
}
