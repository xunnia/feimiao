// 资产页性能缓存回归（任务 P，2026-07-27）：
// accountBalanceResultOf / currentNetWorthResult / accountBalanceTrend 按
// (revision, 当天) memo——这里验证「命中不重算、任何写路径后失效重算且值正确」：
// ① 连续两次读命中缓存；② addTransaction 后重算；③ 余额校准锚点创建/撤销后
// 重算；④ 账户编辑后重算；⑤ 净资产与趋势同样命中/失效。
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('qingji_balance_cache_test_');
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

  test('① 连续两次读余额：第二次命中缓存，计数不增且返回同一对象', () async {
    final repo = await freshRepo();
    final accountId = await repo.addAccount(
      name: '缓存卡',
      openingBalance: Decimal.fromInt(100),
    );
    final account = repo.accounts.singleWhere((item) => item.id == accountId);

    final before = repo.balanceRecomputeCount;
    final first = repo.accountBalanceResultOf(account);
    expect(repo.balanceRecomputeCount, before + 1);
    expect(first.value!.balance, Decimal.fromInt(100));

    final second = repo.accountBalanceResultOf(account);
    expect(repo.balanceRecomputeCount, before + 1); // 命中缓存，没有重算
    expect(identical(first, second), isTrue);
    await repo.closeForTest();
  });

  test('② addTransaction 后缓存失效：重算且值正确', () async {
    final repo = await freshRepo();
    final accountId = await repo.addAccount(
      name: '记账失效卡',
      openingBalance: Decimal.fromInt(100),
    );
    final account = repo.accounts.singleWhere((item) => item.id == accountId);
    expect(repo.accountBalanceResultOf(account).value!.balance,
        Decimal.fromInt(100));

    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(30),
      accountId: accountId,
      note: '缓存失效用例',
      date: DateTime.now(),
    );
    // 写路径内部（净资产快照刷新）也会重算，所以只断言「写完后的下一次读
    // 必然重算一次、值是新的」。
    final afterWrite = repo.balanceRecomputeCount;
    final refreshed = repo.accountBalanceResultOf(
      repo.accounts.singleWhere((item) => item.id == accountId),
    );
    expect(repo.balanceRecomputeCount, afterWrite + 1);
    expect(refreshed.value!.balance, Decimal.fromInt(70));

    // 再读又回到命中。
    expect(
      identical(
        repo.accountBalanceResultOf(
          repo.accounts.singleWhere((item) => item.id == accountId),
        ),
        refreshed,
      ),
      isTrue,
    );
    expect(repo.balanceRecomputeCount, afterWrite + 1);
    await repo.closeForTest();
  });

  test('③ 余额校准锚点创建/撤销后缓存失效：重算且值正确', () async {
    final repo = await freshRepo();
    final accountId = await repo.addAccount(
      name: '校准失效卡',
      openingBalance: Decimal.fromInt(100),
    );
    final account = repo.accounts.singleWhere((item) => item.id == accountId);
    expect(repo.accountBalanceResultOf(account).value!.balance,
        Decimal.fromInt(100));

    final checkpointId = await repo.createAccountBalanceCheckpoint(
      accountId: accountId,
      targetBalance: Decimal.fromInt(500),
      note: '实际余额',
    );
    var count = repo.balanceRecomputeCount;
    expect(repo.accountBalanceResultOf(account).value!.balance,
        Decimal.fromInt(500));
    expect(repo.balanceRecomputeCount, count + 1); // 校准后必须重算
    expect(repo.accountBalanceResultOf(account).value!.balance,
        Decimal.fromInt(500));
    expect(repo.balanceRecomputeCount, count + 1); // 第二次命中

    await repo.reverseAccountBalanceCheckpoint(checkpointId);
    count = repo.balanceRecomputeCount;
    expect(repo.accountBalanceResultOf(account).value!.balance,
        Decimal.fromInt(100)); // 撤销校准回到开户余额基线
    expect(repo.balanceRecomputeCount, count + 1);
    await repo.closeForTest();
  });

  test('④ 账户编辑（updateAccount）后缓存失效：重算', () async {
    final repo = await freshRepo();
    final accountId = await repo.addAccount(
      name: '编辑失效卡',
      openingBalance: Decimal.fromInt(100),
    );
    final account = repo.accounts.singleWhere((item) => item.id == accountId);
    expect(repo.accountBalanceResultOf(account).value!.balance,
        Decimal.fromInt(100));

    await repo.updateAccount(
      id: accountId,
      name: '编辑失效卡·改名',
      currencyCode: 'CNY',
      type: AccountType.debit,
      openingBalance: Decimal.fromInt(100),
      includeInNetWorth: true,
      institution: '测试银行',
    );
    final count = repo.balanceRecomputeCount;
    final fresh = repo.accounts.singleWhere((item) => item.id == accountId);
    expect(repo.accountBalanceResultOf(fresh).value!.balance,
        Decimal.fromInt(100));
    expect(repo.balanceRecomputeCount, count + 1); // 账户编辑后必须重算
    await repo.closeForTest();
  });

  test('⑤ 净资产与趋势 memo：命中不重算，记一笔后失效重算且值正确', () async {
    final repo = await freshRepo();
    final accountId = await repo.addAccount(
      name: '净资产趋势卡',
      openingBalance: Decimal.fromInt(100),
    );
    final account = repo.accounts.singleWhere((item) => item.id == accountId);

    // 净资产：两次读第二次命中。
    final netFirst = repo.currentNetWorthResult();
    final netCount = repo.netWorthRecomputeCount;
    final netSecond = repo.currentNetWorthResult();
    expect(repo.netWorthRecomputeCount, netCount);
    expect(identical(netFirst, netSecond), isTrue);
    final netWorthBefore = netFirst.value!.netWorth;

    // 趋势：两次读第二次命中。
    final trendFirst = repo.accountBalanceTrend(account, days: 7);
    final trendCount = repo.trendRecomputeCount;
    final trendSecond = repo.accountBalanceTrend(account, days: 7);
    expect(repo.trendRecomputeCount, trendCount);
    expect(identical(trendFirst, trendSecond), isTrue);
    expect(trendFirst!.points.last.balance, Decimal.fromInt(100));

    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(30),
      accountId: accountId,
      note: '净资产趋势失效用例',
      date: DateTime.now(),
    );

    final netCountAfterWrite = repo.netWorthRecomputeCount;
    final netRefreshed = repo.currentNetWorthResult();
    expect(repo.netWorthRecomputeCount, netCountAfterWrite + 1);
    expect(
      netRefreshed.value!.netWorth,
      netWorthBefore - Decimal.fromInt(30),
    );

    // 双保险回归网（对抗审查发现）：写路径中途 _persistCurrentNetWorthSnapshot
    // 在 notifyListeners 之前读 memo 化的 currentNetWorthResult——若
    // _invalidateTxDerived 里的 _invalidateBalanceDerived() 被删，此处 memo
    // 已热（上面读过），当天快照会把写前的旧净资产静默落盘。断言快照=写后
    // 净资产，把这层失效兜进测试。
    final todaySnapshot =
        repo.netWorthSnapshots.where((snapshot) => snapshot.isComputed).first;
    expect(todaySnapshot.netWorth, netWorthBefore - Decimal.fromInt(30));

    final trendCountAfterWrite = repo.trendRecomputeCount;
    final trendRefreshed = repo.accountBalanceTrend(
      repo.accounts.singleWhere((item) => item.id == accountId),
      days: 7,
    );
    expect(repo.trendRecomputeCount, trendCountAfterWrite + 1);
    expect(trendRefreshed!.points.last.balance, Decimal.fromInt(70));
    await repo.closeForTest();
  });
}
