import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/account/liability_balance_mode.dart';
import 'package:qingji/core/account/liability_repayment_policy.dart';

Decimal money(String value) => Decimal.parse(value);

LiabilityRepaymentPlan resolve({
  String amount = '200',
  String balance = '-1000',
  String principal = '1000',
  LiabilityBalanceMode mode = LiabilityBalanceMode.ledger,
  bool allowZeroPrincipalTransfer = false,
}) =>
    LiabilityRepaymentPolicy.resolve(
      amount: money(amount),
      accountBalance: money(balance),
      contractPrincipal: money(principal),
      mode: mode,
      allowZeroPrincipalTransfer: allowZeroPrincipalTransfer,
    );

void expectPlan(
  LiabilityRepaymentPlan plan, {
  required String principalPaid,
  required String interestPaid,
  required String transferAmount,
  required String principalAfter,
}) {
  expect(plan.principalPaid, money(principalPaid));
  expect(plan.interestPaid, money(interestPaid));
  expect(plan.transferAmount, money(transferAmount));
  expect(plan.principalAfter, money(principalAfter));
}

Matcher argumentMessage(String message) => throwsA(
      isA<ArgumentError>().having((error) => error.message, 'message', message),
    );

void main() {
  group('负债还款口径保护', () {
    for (final balance in ['0', '200']) {
      test('旧混合口径余额 $balance 且有本金时要求先核对', () {
        expect(
          () => resolve(
            balance: balance,
            mode: LiabilityBalanceMode.legacyHybrid,
          ),
          argumentMessage('请先核对负债余额并切换余额口径，再记录还款'),
        );
      });

      test('余额口径余额 $balance 且合同有本金时不伪造欠款', () {
        expect(
          () => resolve(balance: balance),
          argumentMessage('当前账户没有账面欠款，请先核对合同本金，再记录还款'),
        );
      });
    }

    for (final principal in ['800', '1200']) {
      test('旧混合口径本金 $principal 与负余额不符时要求核对', () {
        expect(
          () => resolve(
            principal: principal,
            mode: LiabilityBalanceMode.legacyHybrid,
          ),
          argumentMessage('负债余额与合同本金不一致，请先核对并切换余额口径，再记录还款'),
        );
      });
    }

    test('余额口径合同本金偏小，仍按真实欠款拆本金', () {
      expectPlan(
        resolve(principal: '100'),
        principalPaid: '200',
        interestPaid: '0',
        transferAmount: '200',
        principalAfter: '0',
      );
    });

    test('余额口径合同本金偏大，超出真实欠款的部分才计利息', () {
      expectPlan(
        resolve(amount: '1100', principal: '1500'),
        principalPaid: '1000',
        interestPaid: '100',
        transferAmount: '1000',
        principalAfter: '500',
      );
    });
  });

  group('正常本金与利息拆分', () {
    for (final mode in LiabilityBalanceMode.values) {
      test('$mode 部分还款', () {
        expectPlan(
          resolve(mode: mode),
          principalPaid: '200',
          interestPaid: '0',
          transferAmount: '200',
          principalAfter: '800',
        );
      });

      test('$mode 足额还款', () {
        expectPlan(
          resolve(amount: '1000', mode: mode),
          principalPaid: '1000',
          interestPaid: '0',
          transferAmount: '1000',
          principalAfter: '0',
        );
      });

      test('$mode 超额还款', () {
        final plan = resolve(amount: '1020', mode: mode);
        expectPlan(
          plan,
          principalPaid: '1000',
          interestPaid: '20',
          transferAmount: '1000',
          principalAfter: '0',
        );
        expect(plan.transferAmount + plan.interestPaid, money('1020'));
      });
    }

    test('本金转账保持净资产不变，只有利息减少净资产', () {
      final plan = resolve(amount: '1020');
      final cashBefore = money('2000');
      final debtBefore = money('1000');
      final cashAfter = cashBefore - plan.transferAmount - plan.interestPaid;
      final debtAfter = debtBefore - plan.transferAmount;
      expect(
        (cashAfter - debtAfter) - (cashBefore - debtBefore),
        -plan.interestPaid,
      );
    });
  });

  group('无合同本金的信用卡兼容', () {
    for (final mode in LiabilityBalanceMode.values) {
      for (final balance in ['-100', '0', '100']) {
        test('$mode 余额 $balance 保留整笔转账，不造本金或利息', () {
          expectPlan(
            resolve(
                balance: balance,
                principal: '0',
                mode: mode,
                allowZeroPrincipalTransfer: true),
            principalPaid: '0',
            interestPaid: '0',
            transferAmount: '200',
            principalAfter: '0',
          );
        });
      }
    }
  });

  group('分位与非法金额', () {
    test('贷款本金资料归零但仍欠700，付720只转700、利息20', () {
      expectPlan(resolve(amount: '720', balance: '-700', principal: '0'),
          principalPaid: '700',
          interestPaid: '20',
          transferAmount: '700',
          principalAfter: '0');
    });
    test('所有输入先归一到分，再拆分', () {
      expectPlan(
        resolve(
            amount: '1000.025', balance: '-1000.004', principal: '1000.004'),
        principalPaid: '1000',
        interestPaid: '0.03',
        transferAmount: '1000',
        principalAfter: '0',
      );
    });

    test('旧混合口径归一到分后相等，不误判资料冲突', () {
      expectPlan(
        resolve(
          amount: '0.014',
          balance: '-1000.001',
          principal: '1000.004',
          mode: LiabilityBalanceMode.legacyHybrid,
        ),
        principalPaid: '0.01',
        interestPaid: '0',
        transferAmount: '0.01',
        principalAfter: '999.99',
      );
    });

    test('不经过浮点，大金额分位仍精确', () {
      expectPlan(
        resolve(
          amount: '90071992547409.93',
          balance: '-90071992547409.92',
          principal: '90071992547409.92',
        ),
        principalPaid: '90071992547409.92',
        interestPaid: '0.01',
        transferAmount: '90071992547409.92',
        principalAfter: '0',
      );
    });

    for (final amount in ['0', '-1', '0.004']) {
      test('还款金额 $amount 归一后非正则拒绝', () {
        expect(
          () => resolve(amount: amount),
          argumentMessage('还款金额必须大于零'),
        );
      });
    }

    test('合同本金为负时拒绝', () {
      expect(
        () => resolve(principal: '-0.01'),
        argumentMessage('合同本金不能为负数'),
      );
    });
  });
}
