import 'package:decimal/decimal.dart';

import '../money_cents.dart';
import 'liability_balance_mode.dart';

class LiabilityRepaymentPlan {
  final Decimal principalPaid;
  final Decimal interestPaid;
  final Decimal transferAmount;
  final Decimal principalAfter;

  const LiabilityRepaymentPlan({
    required this.principalPaid,
    required this.interestPaid,
    required this.transferAmount,
    required this.principalAfter,
  });
}

/// 余额口径决定真实欠款，合同本金只更新资料，不替代账户余额。
class LiabilityRepaymentPolicy {
  static LiabilityRepaymentPlan resolve({
    required Decimal amount,
    required Decimal accountBalance,
    required Decimal contractPrincipal,
    required LiabilityBalanceMode mode,
    bool allowZeroPrincipalTransfer = false,
  }) {
    final payment = normalizeMoneyAmount(amount);
    final balance = normalizeMoneyAmount(accountBalance);
    final principal = normalizeMoneyAmount(contractPrincipal);

    if (payment <= Decimal.zero) {
      throw ArgumentError('还款金额必须大于零');
    }
    if (principal < Decimal.zero) {
      throw ArgumentError('合同本金不能为负数');
    }

    // 无合同本金的信用卡沿用账户转账；溢缴款不是利息支出。
    if (principal == Decimal.zero && allowZeroPrincipalTransfer) {
      return LiabilityRepaymentPlan(
        principalPaid: Decimal.zero,
        interestPaid: Decimal.zero,
        transferAmount: payment,
        principalAfter: Decimal.zero,
      );
    }

    if (balance >= Decimal.zero) {
      if (mode == LiabilityBalanceMode.legacyHybrid) {
        throw ArgumentError('请先核对负债余额并切换余额口径，再记录还款');
      }
      throw ArgumentError('当前账户没有账面欠款，请先核对合同本金，再记录还款');
    }

    final debt = -balance;
    if (mode == LiabilityBalanceMode.legacyHybrid && principal != debt) {
      throw ArgumentError('负债余额与合同本金不一致，请先核对并切换余额口径，再记录还款');
    }

    final principalPaid = payment < debt ? payment : debt;
    final principalAfter = principal - principalPaid;
    return LiabilityRepaymentPlan(
      principalPaid: principalPaid,
      interestPaid: payment - principalPaid,
      transferAmount: principalPaid,
      principalAfter:
          principalAfter > Decimal.zero ? principalAfter : Decimal.zero,
    );
  }
}
