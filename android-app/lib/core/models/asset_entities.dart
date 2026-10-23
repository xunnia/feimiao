import 'dart:convert';
import 'dart:math';
import 'package:decimal/decimal.dart';
import '../account/net_worth_snapshot.dart';
import '../assets/asset_allocation.dart';
import '../assets/asset_enhancements.dart';
import '../money_cents.dart';
import 'ledger_entities.dart';

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

PhysicalAssetEconomicStatus physicalEconomicFromLegacyStatus(
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

PhysicalAssetUsageStatus physicalUsageFromLegacyStatus(
  PhysicalAssetStatus status,
) =>
    switch (status) {
      PhysicalAssetStatus.active => PhysicalAssetUsageStatus.active,
      PhysicalAssetStatus.idle => PhysicalAssetUsageStatus.idle,
      _ => PhysicalAssetUsageStatus.unknown,
    };

PhysicalAssetStatus legacyPhysicalStatusFor({
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

ReceivableEconomicStatus receivableEconomicFromLegacyStatus(
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

ReceivableAssetStatus legacyReceivableStatusFor({
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
  liabilityRepaid,
  liabilityRepaymentUndone,
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
        AssetEventType.liabilityRepaid => 'liability_repaid',
        AssetEventType.liabilityRepaymentUndone => 'liability_repayment_undone',
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
        AssetEventType.liabilityRepaid => '记录还款',
        AssetEventType.liabilityRepaymentUndone => '撤销还款',
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
          : physicalEconomicFromLegacyStatus(legacyStatus),
      usageStatus: m.containsKey('usage_status')
          ? PhysicalAssetUsageStatusX.fromStorage(
              m['usage_status'] as String?,
            )
          : physicalUsageFromLegacyStatus(legacyStatus),
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
          : receivableEconomicFromLegacyStatus(legacyStatus),
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
    final causes = decodeNetWorthSnapshotCauses(causeSetJson);
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

Set<NetWorthSnapshotCause> decodeNetWorthSnapshotCauses(String raw) {
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
