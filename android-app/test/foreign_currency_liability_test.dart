import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('qingji_currency_test_');
    await databaseFactory.setDatabasesPath(tmp.path);
  });

  tearDown(() async {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<AppRepository> freshRepo() async {
    final repo = AppRepository();
    await repo.init();
    return repo;
  }

  /// 直接插入外币账户（绕过 addAccount 的 CNY-only 检查）。
  /// 这是测试专用 hack——真实 app 还不支持新增外币账户，
  /// 但老数据可能有，且 breakdown 逻辑必须正确过滤。
  Future<int> _insertForeignAccount(
    AppRepository repo,
    String name,
    String currencyCode,
    String balance,
  ) async {
    final db = repo.debugDb;
    final now = DateTime.now().millisecondsSinceEpoch;
    return await db.insert('accounts', {
      'uuid': 'test-${DateTime.now().microsecondsSinceEpoch}',
      'name': name,
      'currency_code': currencyCode,
      'type': 'loan',
      'opening_balance': balance,
      'include_in_net_worth': 1,
      'institution': '',
      'created_ms': now,
      'updated_ms': now,
      'opening_balance_effective_ms': now,
      'opening_balance_sequence': 0,
      'opening_balance_quality': 'exact',
      'status': 'active',
      'balance_mode': 'legacy_hybrid',
    });
  }

  group('外币负债不应漏进 CNY 净资产', () {
    test('USD 借款本金不计入 CNY 总负债', () async {
      final repo = await freshRepo();

      // 1. 插入 USD 账户
      final usdAccountId =
          await _insertForeignAccount(repo, 'USD Loan', 'USD', '0');
      await repo.reloadForTest();

      // 2. 创建负债档案（本金 $1000）
      await repo.upsertLiabilityProfile(
        accountId: usdAccountId,
        type: LiabilityProfileType.personalBorrow,
        originalAmount: Decimal.fromInt(1000),
        currentPrincipal: Decimal.fromInt(1000),
        status: LiabilityProfileStatus.active,
        counterparty: 'Friend',
      );

      // 3. 验证：USD 本金不应出现在 CNY breakdown
      final breakdown = repo.currentNetWorthBreakdown();
      expect(breakdown.totalLiabilities, Decimal.zero,
          reason: 'USD 负债本金不应以 1:1 汇率计入 CNY 负债');
      expect(breakdown.netWorth, Decimal.zero);

      await repo.closeForTest();
    });

    test('CNY + USD 混合负债：只计 CNY', () async {
      final repo = await freshRepo();

      // 1. CNY 信用卡（B=0, P=2000）
      final cnyCardId = await repo.addAccount(name: 'CNY 信用卡');
      await repo.upsertLiabilityProfile(
        accountId: cnyCardId,
        type: LiabilityProfileType.creditCard,
        originalAmount: Decimal.fromInt(2000),
        currentPrincipal: Decimal.fromInt(2000),
        status: LiabilityProfileStatus.active,
      );

      // 2. USD 房贷（B=0, P=$50000）
      final usdMortgageId =
          await _insertForeignAccount(repo, 'USD Mortgage', 'USD', '0');
      await repo.reloadForTest();
      await repo.upsertLiabilityProfile(
        accountId: usdMortgageId,
        type: LiabilityProfileType.mortgage,
        originalAmount: Decimal.fromInt(50000),
        currentPrincipal: Decimal.fromInt(50000),
        status: LiabilityProfileStatus.active,
      );

      // 3. 验证：只计 CNY 的 2000，不计 USD 的 50000
      final breakdown = repo.currentNetWorthBreakdown();
      expect(breakdown.totalLiabilities, Decimal.fromInt(2000),
          reason: '只应计入 CNY 信用卡本金 2000，USD 房贷本金不应混入');
      expect(breakdown.netWorth, Decimal.fromInt(-2000));

      await repo.closeForTest();
    });

    test('外币负债正余额时：既不算资产也不算负债', () async {
      final repo = await freshRepo();

      // 场景：USD 信用卡存了 $100（正余额）
      final usdCardId =
          await _insertForeignAccount(repo, 'USD Credit Card', 'USD', '100');
      await repo.reloadForTest();
      await repo.upsertLiabilityProfile(
        accountId: usdCardId,
        type: LiabilityProfileType.creditCard,
        originalAmount: Decimal.zero,
        currentPrincipal: Decimal.zero,
        status: LiabilityProfileStatus.active,
      );

      // 验证：正余额因为是 USD，不进 CNY 资产；本金为0，也不进负债
      final breakdown = repo.currentNetWorthBreakdown();
      expect(breakdown.cashAssets, Decimal.zero,
          reason: 'USD 账户正余额不应计入 CNY 现金资产');
      expect(breakdown.totalLiabilities, Decimal.zero);
      expect(breakdown.netWorth, Decimal.zero);

      await repo.closeForTest();
    });

    test('A5 ledger 模式 + 外币：仍然过滤外币', () async {
      final repo = await freshRepo();

      // 外币账户切到 ledger 模式后，仍然应该因为币种不符被过滤
      final db = repo.debugDb;
      final now = DateTime.now().millisecondsSinceEpoch;
      final usdLoanId = await db.insert('accounts', {
        'uuid': 'test-ledger-usd',
        'name': 'USD Loan Ledger',
        'currency_code': 'USD',
        'type': 'loan',
        'opening_balance': '-800', // 负余额 = 欠 $800
        'include_in_net_worth': 1,
        'institution': '',
        'created_ms': now,
        'updated_ms': now,
        'opening_balance_effective_ms': now,
        'opening_balance_sequence': 0,
        'opening_balance_quality': 'exact',
        'status': 'active',
        'balance_mode': 'ledger', // ← ledger 模式
      });
      await repo.reloadForTest();

      await repo.upsertLiabilityProfile(
        accountId: usdLoanId,
        type: LiabilityProfileType.personalBorrow,
        originalAmount: Decimal.fromInt(800),
        currentPrincipal: Decimal.fromInt(800),
        status: LiabilityProfileStatus.active,
      );

      final breakdown = repo.currentNetWorthBreakdown();
      expect(breakdown.totalLiabilities, Decimal.zero,
          reason: 'ledger 模式的外币负债仍应被币种过滤');
      expect(breakdown.netWorth, Decimal.zero);

      await repo.closeForTest();
    });
  });
}
