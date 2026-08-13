/// 负债余额口径与迁移分支判定（A5 负债单一真相源）。
/// 不依赖 Flutter，全部可单测。规格出处：
/// `docs/claude/BUDGET_ASSET_UX_PLAN_V2_1_2026-07-12.md` §11.2 / §11.3 / §11.4。
///
/// 背景（注释即契约）：历史上负债账户存在「双算」——账户正余额进总资产，
/// 同时 active 负债档案的 currentPrincipal 又进总负债。直接把余额改成
/// `-P` 会让总资产和净资产各少 `B`，所以不存在「静默改值且三项逐分不变」
/// 的迁移路径。解法是给每个账户一个 [LiabilityBalanceMode]：
/// - [LiabilityBalanceMode.legacyHybrid]：完全保留老算法（默认，升级不变行为）
/// - [LiabilityBalanceMode.ledger]：余额是唯一真相，档案本金只作合同资料
///
/// 迁移前先用 [LiabilityMigrationClassifier.classify] 把账户归类到
/// [LiabilityMigrationBranch]，安全分支可自动迁移，歧义分支必须问用户。
library;

import 'package:decimal/decimal.dart';

/// 负债账户的余额口径。存储在 `accounts.balance_mode`。
///
/// 挂在 accounts 而不是 liability_profiles 是有意的：模式规定的是「余额」
/// 怎么解释，而余额是账户的属性。且 `deleteLiabilityProfileForAccount`
/// 存在——模式若挂档案上，删档案会连模式一起删掉，已迁到 ledger 的账户
/// 会静默退回旧解释。
enum LiabilityBalanceMode {
  /// 余额是唯一真相：正余额算资产、负余额算负债；
  /// 档案 currentPrincipal 只作合同/上次核对资料，不进总负债。
  ledger,

  /// 老算法：正余额算资产，且 active 档案本金另算进总负债（双算）。
  /// 这是所有既有账户的默认值——升级后行为必须逐分不变。
  legacyHybrid,
}

extension LiabilityBalanceModeX on LiabilityBalanceMode {
  String get storageKey => switch (this) {
        LiabilityBalanceMode.ledger => 'ledger',
        LiabilityBalanceMode.legacyHybrid => 'legacy_hybrid',
      };

  String get label => switch (this) {
        LiabilityBalanceMode.ledger => '余额口径',
        LiabilityBalanceMode.legacyHybrid => '兼容口径',
      };

  bool get isLedger => this == LiabilityBalanceMode.ledger;

  /// 未知/缺失一律回落 legacyHybrid——老备份读进来不能变成 ledger，
  /// 否则口径静默翻转、净资产悄悄变化。
  static LiabilityBalanceMode fromStorage(String? value) =>
      value == 'ledger'
          ? LiabilityBalanceMode.ledger
          : LiabilityBalanceMode.legacyHybrid;
}

/// 单个负债账户的迁移分支（§11.3 四种可自动等价迁移 + §11.4 歧义）。
enum LiabilityMigrationBranch {
  /// 账户已经是 ledger 口径，无需迁移。
  alreadyLedger,

  /// `B < 0`：余额已经在算负债了，直接标 ledger，不改数值。
  /// 若 `abs(B) != P`，提示合同资料与账面欠款不同，但不改合计。
  negativeBalanceSafe,

  /// `B = 0 且 P > 0`：用 absolute checkpoint 把余额校准到 `-P` 再标 ledger。
  /// 迁移前后总资产/总负债/净资产三项逐分不变。
  zeroBalanceCalibrate,

  /// `P = 0` 或档案非 active（含无档案）：本金没进总负债，直接标 ledger。
  noPrincipalSafe,

  /// `B > 0 且 P > 0`：歧义。正数可能是真实溢缴款/押金，也可能是信用额度、
  /// 符号录反、过期档案。**一律保留 legacy_hybrid，不得静默改值**，
  /// 必须走 §11.4 的用户辅助校准。
  ambiguousNeedsUser,
}

extension LiabilityMigrationBranchX on LiabilityMigrationBranch {
  /// 能否在不问用户的前提下自动完成等价迁移。
  bool get isAutoSafe => switch (this) {
        LiabilityMigrationBranch.alreadyLedger => false,
        LiabilityMigrationBranch.negativeBalanceSafe => true,
        LiabilityMigrationBranch.zeroBalanceCalibrate => true,
        LiabilityMigrationBranch.noPrincipalSafe => true,
        LiabilityMigrationBranch.ambiguousNeedsUser => false,
      };

  /// 迁移是否需要写 absolute checkpoint 改余额。
  bool get needsCalibration =>
      this == LiabilityMigrationBranch.zeroBalanceCalibrate;

  String get label => switch (this) {
        LiabilityMigrationBranch.alreadyLedger => '已是余额口径',
        LiabilityMigrationBranch.negativeBalanceSafe => '可直接切换',
        LiabilityMigrationBranch.zeroBalanceCalibrate => '需校准余额',
        LiabilityMigrationBranch.noPrincipalSafe => '可直接切换',
        LiabilityMigrationBranch.ambiguousNeedsUser => '需你确认',
      };
}

/// 单个账户的迁移计划项。纯数据，由 [LiabilityMigrationClassifier.classify] 产出。
class LiabilityMigrationPlanItem {
  final int accountId;
  final LiabilityMigrationBranch branch;

  /// 当前账面余额 `B`。
  final Decimal balance;

  /// 档案本金 `P` 原始值（不管是否计入总负债，展示合同资料用）。
  final Decimal principal;

  /// 当前**实际计入总负债**的本金：档案非 active 或本金为 0 时是 0。
  /// 对应 `LiabilityProfileEntity.countsAsLiability` 的判定结果。
  final Decimal countedPrincipal;

  /// [LiabilityMigrationBranch.zeroBalanceCalibrate] 要校准到的目标余额
  /// （= `-P`）；其余分支为 null。
  final Decimal? calibrationTarget;

  /// 仅 [LiabilityMigrationBranch.negativeBalanceSafe]：`abs(B) != P`。
  /// §11.3 要求提示「合同资料和账面欠款不同」但**不改合计**。
  final bool contractMismatch;

  const LiabilityMigrationPlanItem({
    required this.accountId,
    required this.branch,
    required this.balance,
    required this.principal,
    required this.countedPrincipal,
    this.calibrationTarget,
    this.contractMismatch = false,
  });

  /// 迁移后这个账户的余额（只有校准分支会变）。
  Decimal get balanceAfter => calibrationTarget ?? balance;
}

/// 迁移分支判定器（§11.3 + §11.4）。纯函数，无 IO。
class LiabilityMigrationClassifier {
  const LiabilityMigrationClassifier._();

  /// 把一个账户归类到 [LiabilityMigrationBranch]。
  ///
  /// [principalCountsAsLiability] 传 `LiabilityProfileEntity.countsAsLiability`
  /// （= status active 且 currentPrincipal > 0）。无档案的账户传 false + 本金 0。
  ///
  /// 判定顺序有意如此：先看是否已迁移，再看本金是否真的计入了总负债，
  /// 最后才按余额符号分流。**顺序不能改**——若先按余额分流，`P = 0` 的
  /// 正余额账户会被误判成歧义，白问用户一遍。
  static LiabilityMigrationPlanItem classify({
    required int accountId,
    required Decimal balance,
    required Decimal principal,
    required bool principalCountsAsLiability,
    required LiabilityBalanceMode currentMode,
  }) {
    final counted =
        principalCountsAsLiability ? principal : Decimal.zero;

    LiabilityMigrationPlanItem item(
      LiabilityMigrationBranch branch, {
      Decimal? calibrationTarget,
      bool contractMismatch = false,
    }) =>
        LiabilityMigrationPlanItem(
          accountId: accountId,
          branch: branch,
          balance: balance,
          principal: principal,
          countedPrincipal: counted,
          calibrationTarget: calibrationTarget,
          contractMismatch: contractMismatch,
        );

    if (currentMode.isLedger) {
      return item(LiabilityMigrationBranch.alreadyLedger);
    }
    if (counted == Decimal.zero) {
      // 本金没进总负债（无档案 / 已结清 / 本金为 0）→ 切模式后
      // 第二轮本来也不会加它，行为零变化。
      return item(LiabilityMigrationBranch.noPrincipalSafe);
    }
    if (balance < Decimal.zero) {
      // 余额已在算负债，档案本金当前**没有**被计入（老算法第二轮要求
      // 余额 >= 0），所以切 ledger 是零变化。
      return item(
        LiabilityMigrationBranch.negativeBalanceSafe,
        contractMismatch: -balance != principal,
      );
    }
    if (balance == Decimal.zero) {
      return item(
        LiabilityMigrationBranch.zeroBalanceCalibrate,
        calibrationTarget: -principal,
      );
    }
    return item(LiabilityMigrationBranch.ambiguousNeedsUser);
  }

  /// 单个账户在给定口径下对「总资产 / 总负债」的贡献。
  ///
  /// 这是 `_computeCurrentNetWorthBreakdown` 两轮循环的等价提炼，
  /// 用于把等价性算出来而不是嘴上保证。改动这里必须同步改 repository，
  /// 反之亦然（§7.1 的两条用例是共同判据）。
  static ({Decimal assets, Decimal liabilities}) contribution({
    required Decimal balance,
    required Decimal countedPrincipal,
    required LiabilityBalanceMode mode,
  }) {
    final assets = balance > Decimal.zero ? balance : Decimal.zero;
    var liabilities =
        balance < Decimal.zero ? -balance : Decimal.zero;
    if (!mode.isLedger && balance >= Decimal.zero) {
      liabilities += countedPrincipal;
    }
    return (assets: assets, liabilities: liabilities);
  }

  /// 对一批计划项做「只迁移安全分支」的三项合计变化预览。
  ///
  /// 安全分支的设计目标就是三项全零变化。这里**从贡献函数实算**
  /// 而不是硬编码 0，这样单测能真正证明等价性，而不是复述断言。
  static LiabilityMigrationPreview preview(
    Iterable<LiabilityMigrationPlanItem> items,
  ) {
    var assetsBefore = Decimal.zero;
    var liabilitiesBefore = Decimal.zero;
    var assetsAfter = Decimal.zero;
    var liabilitiesAfter = Decimal.zero;
    var autoSafe = 0;
    var ambiguous = 0;
    var alreadyLedger = 0;

    for (final item in items) {
      switch (item.branch) {
        case LiabilityMigrationBranch.alreadyLedger:
          alreadyLedger++;
        case LiabilityMigrationBranch.ambiguousNeedsUser:
          ambiguous++;
        case LiabilityMigrationBranch.negativeBalanceSafe:
        case LiabilityMigrationBranch.zeroBalanceCalibrate:
        case LiabilityMigrationBranch.noPrincipalSafe:
          autoSafe++;
      }

      final before = contribution(
        balance: item.balance,
        countedPrincipal: item.countedPrincipal,
        mode: LiabilityBalanceMode.legacyHybrid,
      );
      assetsBefore += before.assets;
      liabilitiesBefore += before.liabilities;

      // 歧义分支和已迁移分支这一轮不动，after 用原状态算。
      final migrates = item.branch.isAutoSafe;
      final after = contribution(
        balance: migrates ? item.balanceAfter : item.balance,
        countedPrincipal: item.countedPrincipal,
        mode: migrates
            ? LiabilityBalanceMode.ledger
            : (item.branch == LiabilityMigrationBranch.alreadyLedger
                ? LiabilityBalanceMode.ledger
                : LiabilityBalanceMode.legacyHybrid),
      );
      assetsAfter += after.assets;
      liabilitiesAfter += after.liabilities;
    }

    return LiabilityMigrationPreview(
      autoSafeCount: autoSafe,
      ambiguousCount: ambiguous,
      alreadyLedgerCount: alreadyLedger,
      assetsDelta: assetsAfter - assetsBefore,
      liabilitiesDelta: liabilitiesAfter - liabilitiesBefore,
    );
  }
}

/// 迁移预览：各分支计数 + 三项合计变化。
class LiabilityMigrationPreview {
  final int autoSafeCount;
  final int ambiguousCount;
  final int alreadyLedgerCount;

  /// 总资产变化（安全分支应为 0）。
  final Decimal assetsDelta;

  /// 总负债变化（安全分支应为 0）。
  final Decimal liabilitiesDelta;

  const LiabilityMigrationPreview({
    required this.autoSafeCount,
    required this.ambiguousCount,
    required this.alreadyLedgerCount,
    required this.assetsDelta,
    required this.liabilitiesDelta,
  });

  /// 净资产变化 = 总资产变化 - 总负债变化。
  Decimal get netWorthDelta => assetsDelta - liabilitiesDelta;

  /// 三项是否逐分不变。等价迁移的判据。
  bool get isEquivalent =>
      assetsDelta == Decimal.zero && liabilitiesDelta == Decimal.zero;
}
