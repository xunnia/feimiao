/// 信用卡账期纯逻辑（A 批 A1）。不依赖 Flutter，全部可单测。
///
/// 口径（经典信用卡规则，注释即契约，UI 展示要跟这里一致）：
/// - 账单日 D：每月 D 号出账；短月（如 2 月）clamp 到当月最后一天。
/// - 账单周期：上个账单日的**次日**起，到本期账单日（含）止。
///   今天消费计入「今天所在周期」的账单——今天恰好是账单日时，消费仍入
///   今天出的这期账单（各行实操有差异，这里取常见口径并固定下来）。
/// - 还款日 R：若 R > D，还款日在账单日**当月**；若 R <= D，在账单日
///   **次月**（比较用配置的原始日数，不用 clamp 后的）。短月同样 clamp。
/// - 免息天数：今天消费 → 本期账单的还款日，`还款日 - 今天` 的天数差
///   （不含今天、含还款日）。这是可回答「哪来的」的确定性口径，不追各
///   银行营销话术的 ±1 天。
class CreditCardTerms {
  /// 当前账单周期起（含，上个账单日次日）。
  final DateTime cycleStart;

  /// 当前账单周期止（含，= 本期账单日）。
  final DateTime cycleEnd;

  /// 下一个要还钱的日子（>= 今天）：上期账单的还款日还没过就是它，
  /// 否则是本期账单的还款日。
  final DateTime nextRepaymentDate;

  /// 今天消费对应的还款日（本期账单的还款日）。
  final DateTime purchaseRepaymentDate;

  /// 今天消费的免息天数 = purchaseRepaymentDate - 今天（天数差）。
  final int interestFreeDays;

  const CreditCardTerms({
    required this.cycleStart,
    required this.cycleEnd,
    required this.nextRepaymentDate,
    required this.purchaseRepaymentDate,
    required this.interestFreeDays,
  });

  /// 账单日/还款日任一缺失或非法（不在 1..31）时返回 null——
  /// 没有完整账期配置就没有可诚实计算的周期，UI 自己降级展示。
  static CreditCardTerms? compute({
    required int? statementDay,
    required int? repaymentDay,
    required DateTime now,
  }) {
    if (statementDay == null || statementDay < 1 || statementDay > 31) {
      return null;
    }
    if (repaymentDay == null || repaymentDay < 1 || repaymentDay > 31) {
      return null;
    }
    final today = DateTime(now.year, now.month, now.day);

    // month 允许溢出（13 月 = 次年 1 月），DateTime 构造会自动归一。
    DateTime statementDateOf(int year, int month) =>
        _clampedDate(year, month, statementDay);

    // 本期账单日 = 第一个 >= 今天的账单日。
    var cycleEnd = statementDateOf(today.year, today.month);
    if (cycleEnd.isBefore(today)) {
      cycleEnd = statementDateOf(today.year, today.month + 1);
    }
    // 上个账单日：按月往前推一个月取账单日。注意不能用 cycleEnd 减 1 月
    // 后取日（clamp 语义会漂），直接用「cycleEnd 所在月 - 1」算。
    final prevStatement =
        statementDateOf(cycleEnd.year, cycleEnd.month - 1);
    final cycleStart = prevStatement.add(const Duration(days: 1));

    DateTime repaymentOf(DateTime statement) {
      // 用配置的原始日数比较：还款日 <= 账单日 → 次月还款。
      final monthOffset = repaymentDay > statementDay ? 0 : 1;
      return _clampedDate(
        statement.year,
        statement.month + monthOffset,
        repaymentDay,
      );
    }

    final purchaseRepayment = repaymentOf(cycleEnd);
    // 下个还款日：上期账单的还款日若还没过（>= 今天）先到期；
    // 否则就是本期账单的还款日（它必然 > 账单日 >= 今天）。
    final prevRepayment = repaymentOf(prevStatement);
    final nextRepayment =
        prevRepayment.isBefore(today) ? purchaseRepayment : prevRepayment;

    return CreditCardTerms(
      cycleStart: cycleStart,
      cycleEnd: cycleEnd,
      nextRepaymentDate: nextRepayment,
      purchaseRepaymentDate: purchaseRepayment,
      interestFreeDays: purchaseRepayment.difference(today).inDays,
    );
  }

  /// year/month 的 day 号，短月 clamp 到当月最后一天；month 可溢出/为 0，
  /// 交给 DateTime 归一（如 2026/13 → 2027/1）。
  static DateTime _clampedDate(int year, int month, int day) {
    final normalized = DateTime(year, month, 1);
    final lastDay = DateTime(normalized.year, normalized.month + 1, 0).day;
    return DateTime(
      normalized.year,
      normalized.month,
      day < lastDay ? day : lastDay,
    );
  }
}
