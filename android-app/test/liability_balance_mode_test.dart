import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/account/liability_balance_mode.dart';

Decimal d(int value) => Decimal.fromInt(value);

LiabilityMigrationPlanItem classify({
  int accountId = 1,
  required int balance,
  required int principal,
  bool countsAsLiability = true,
  LiabilityBalanceMode mode = LiabilityBalanceMode.legacyHybrid,
}) =>
    LiabilityMigrationClassifier.classify(
      accountId: accountId,
      balance: d(balance),
      principal: d(principal),
      principalCountsAsLiability: countsAsLiability,
      currentMode: mode,
    );

void main() {
  group('A5 balance_mode 存储回落', () {
    test('未知/缺失一律回落 legacyHybrid，不能静默变 ledger', () {
      expect(LiabilityBalanceModeX.fromStorage(null),
          LiabilityBalanceMode.legacyHybrid);
      expect(LiabilityBalanceModeX.fromStorage(''),
          LiabilityBalanceMode.legacyHybrid);
      expect(LiabilityBalanceModeX.fromStorage('legacy_hybrid'),
          LiabilityBalanceMode.legacyHybrid);
      expect(LiabilityBalanceModeX.fromStorage('未来某个新值'),
          LiabilityBalanceMode.legacyHybrid);
      expect(LiabilityBalanceModeX.fromStorage('ledger'),
          LiabilityBalanceMode.ledger);
    });

    test('storageKey 往返稳定', () {
      for (final mode in LiabilityBalanceMode.values) {
        expect(LiabilityBalanceModeX.fromStorage(mode.storageKey), mode);
      }
    });
  });

  group('A5 §11.3 分支判定', () {
    test('B < 0：直接切 ledger，不改数值', () {
      final item = classify(balance: -3000, principal: 3000);
      expect(item.branch, LiabilityMigrationBranch.negativeBalanceSafe);
      expect(item.branch.isAutoSafe, isTrue);
      expect(item.branch.needsCalibration, isFalse);
      expect(item.calibrationTarget, isNull);
      expect(item.balanceAfter, d(-3000));
      expect(item.contractMismatch, isFalse);
    });

    test('B < 0 且 abs(B) != P：仍可切，但标记合同不符', () {
      final item = classify(balance: -2500, principal: 3000);
      expect(item.branch, LiabilityMigrationBranch.negativeBalanceSafe);
      expect(item.contractMismatch, isTrue);
      // §11.3：提示但不改合计。
      expect(item.balanceAfter, d(-2500));
    });

    test('B = 0 且 P > 0：校准到 -P 再切', () {
      final item = classify(balance: 0, principal: 780000);
      expect(item.branch, LiabilityMigrationBranch.zeroBalanceCalibrate);
      expect(item.branch.needsCalibration, isTrue);
      expect(item.calibrationTarget, d(-780000));
      expect(item.balanceAfter, d(-780000));
    });

    test('P = 0：无本金可算，直接切', () {
      final item = classify(balance: 0, principal: 0);
      expect(item.branch, LiabilityMigrationBranch.noPrincipalSafe);
      expect(item.countedPrincipal, Decimal.zero);
    });

    test('档案非 active：本金不计入，直接切', () {
      final item =
          classify(balance: 0, principal: 5000, countsAsLiability: false);
      expect(item.branch, LiabilityMigrationBranch.noPrincipalSafe);
      expect(item.countedPrincipal, Decimal.zero);
      // 合同资料仍保留展示。
      expect(item.principal, d(5000));
    });

    test('B > 0 且 P > 0：歧义，必须问用户', () {
      final item = classify(balance: 1200, principal: 3000);
      expect(item.branch, LiabilityMigrationBranch.ambiguousNeedsUser);
      expect(item.branch.isAutoSafe, isFalse);
      expect(item.calibrationTarget, isNull);
    });

    test('B > 0 但档案非 active：不是歧义，直接切', () {
      final item = classify(
          balance: 1200, principal: 3000, countsAsLiability: false);
      expect(item.branch, LiabilityMigrationBranch.noPrincipalSafe);
    });

    test('已是 ledger：不重复迁移', () {
      final item = classify(
        balance: -3000,
        principal: 3000,
        mode: LiabilityBalanceMode.ledger,
      );
      expect(item.branch, LiabilityMigrationBranch.alreadyLedger);
      expect(item.branch.isAutoSafe, isFalse);
    });

    test('判定顺序：P=0 的正余额账户不能被误判成歧义', () {
      // 若先按余额符号分流，这个账户会掉进 ambiguous，白问用户一遍。
      final item = classify(balance: 9999, principal: 0);
      expect(item.branch, LiabilityMigrationBranch.noPrincipalSafe);
    });
  });

  group('A5 口径贡献函数（与 repository 两轮循环等价）', () {
    test('legacy_hybrid：正余额算资产且本金另算负债（双算）', () {
      final c = LiabilityMigrationClassifier.contribution(
        balance: d(1200),
        countedPrincipal: d(3000),
        mode: LiabilityBalanceMode.legacyHybrid,
      );
      expect(c.assets, d(1200));
      expect(c.liabilities, d(3000));
    });

    test('legacy_hybrid：负余额算负债，本金不再叠加', () {
      final c = LiabilityMigrationClassifier.contribution(
        balance: d(-3000),
        countedPrincipal: d(3000),
        mode: LiabilityBalanceMode.legacyHybrid,
      );
      expect(c.assets, Decimal.zero);
      expect(c.liabilities, d(3000));
    });

    test('legacy_hybrid：B=0 时本金进负债', () {
      final c = LiabilityMigrationClassifier.contribution(
        balance: Decimal.zero,
        countedPrincipal: d(780000),
        mode: LiabilityBalanceMode.legacyHybrid,
      );
      expect(c.assets, Decimal.zero);
      expect(c.liabilities, d(780000));
    });

    test('ledger：只看余额，本金完全不进负债', () {
      final c = LiabilityMigrationClassifier.contribution(
        balance: d(1200),
        countedPrincipal: d(3000),
        mode: LiabilityBalanceMode.ledger,
      );
      expect(c.assets, d(1200));
      expect(c.liabilities, Decimal.zero);
    });

    test('ledger：负余额算负债', () {
      final c = LiabilityMigrationClassifier.contribution(
        balance: d(-780000),
        countedPrincipal: d(780000),
        mode: LiabilityBalanceMode.ledger,
      );
      expect(c.assets, Decimal.zero);
      expect(c.liabilities, d(780000));
    });
  });

  group('A5 等价性：安全分支迁移后三项逐分不变', () {
    test('B < 0 分支等价（对齐 app_repository_test 资产 P3 信用卡用例）', () {
      final preview = LiabilityMigrationClassifier.preview([
        classify(balance: -3000, principal: 3000),
      ]);
      expect(preview.autoSafeCount, 1);
      expect(preview.assetsDelta, Decimal.zero);
      expect(preview.liabilitiesDelta, Decimal.zero);
      expect(preview.netWorthDelta, Decimal.zero);
      expect(preview.isEquivalent, isTrue);
    });

    test('B = 0 分支等价（对齐 app_repository_test 资产 P3 房贷用例）', () {
      final preview = LiabilityMigrationClassifier.preview([
        classify(balance: 0, principal: 780000),
      ]);
      expect(preview.autoSafeCount, 1);
      // 迁移前：assets 0 / liabilities 780000
      // 迁移后：余额校准到 -780000 → assets 0 / liabilities 780000
      expect(preview.assetsDelta, Decimal.zero);
      expect(preview.liabilitiesDelta, Decimal.zero);
      expect(preview.isEquivalent, isTrue);
    });

    test('P = 0 分支等价', () {
      final preview = LiabilityMigrationClassifier.preview([
        classify(balance: 5000, principal: 0),
        classify(balance: -200, principal: 0),
        classify(balance: 0, principal: 0),
      ]);
      expect(preview.autoSafeCount, 3);
      expect(preview.isEquivalent, isTrue);
      expect(preview.netWorthDelta, Decimal.zero);
    });

    test('歧义分支不迁移，因此也不产生任何合计变化', () {
      final preview = LiabilityMigrationClassifier.preview([
        classify(balance: 1200, principal: 3000),
      ]);
      expect(preview.ambiguousCount, 1);
      expect(preview.autoSafeCount, 0);
      expect(preview.isEquivalent, isTrue);
    });

    test('混合库：只迁安全分支，三项仍逐分不变', () {
      final preview = LiabilityMigrationClassifier.preview([
        classify(accountId: 1, balance: -3000, principal: 3000),
        classify(accountId: 2, balance: 0, principal: 780000),
        classify(accountId: 3, balance: 1200, principal: 3000),
        classify(accountId: 4, balance: 5000, principal: 0),
        classify(
          accountId: 5,
          balance: -100,
          principal: 100,
          mode: LiabilityBalanceMode.ledger,
        ),
      ]);
      expect(preview.autoSafeCount, 3);
      expect(preview.ambiguousCount, 1);
      expect(preview.alreadyLedgerCount, 1);
      expect(preview.assetsDelta, Decimal.zero);
      expect(preview.liabilitiesDelta, Decimal.zero);
      expect(preview.netWorthDelta, Decimal.zero);
      expect(preview.isEquivalent, isTrue);
    });

    test('空库不炸', () {
      final preview = LiabilityMigrationClassifier.preview(const []);
      expect(preview.autoSafeCount, 0);
      expect(preview.isEquivalent, isTrue);
      expect(preview.netWorthDelta, Decimal.zero);
    });
  });

  group('A5 分数金额（角分）不丢精度', () {
    test('B = 0 校准到带小数的 -P', () {
      final item = LiabilityMigrationClassifier.classify(
        accountId: 1,
        balance: Decimal.zero,
        principal: Decimal.parse('1234.56'),
        principalCountsAsLiability: true,
        currentMode: LiabilityBalanceMode.legacyHybrid,
      );
      expect(item.calibrationTarget, Decimal.parse('-1234.56'));
      final preview = LiabilityMigrationClassifier.preview([item]);
      expect(preview.isEquivalent, isTrue);
    });

    test('abs(B) 与 P 差 1 分也算合同不符', () {
      final item = LiabilityMigrationClassifier.classify(
        accountId: 1,
        balance: Decimal.parse('-3000.00'),
        principal: Decimal.parse('3000.01'),
        principalCountsAsLiability: true,
        currentMode: LiabilityBalanceMode.legacyHybrid,
      );
      expect(item.contractMismatch, isTrue);
    });
  });
}
