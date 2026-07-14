import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/views/home/ai_chat_panel.dart';

void main() {
  TransactionEntity transaction({
    String note = '',
    String category = '其他',
    String account = '现金',
    String toAccount = '',
    String amount = '12',
  }) {
    return TransactionEntity(
      id: 1,
      kind: 'expense',
      amountStr: amount,
      categoryNameZh: category,
      accountName: account,
      toAccountName: toAccount,
      note: note,
      dateMs: DateTime(2025, 1, 1).millisecondsSinceEpoch,
    );
  }

  test('无日期查账能从全库命中旧的字母数字备注', () {
    expect(
      aiQuestionMatchesTransaction(
        '我记账备注里有没有 k12？',
        transaction(note: '课程 k12'),
      ),
      isTrue,
    );
  });

  test('无日期查账能按中文备注中的连续语义片段命中', () {
    expect(
      aiQuestionMatchesTransaction(
        '我之前买过手机壳吗',
        transaction(note: '苹果手机壳'),
      ),
      isTrue,
    );
  });

  test('转入账户也参与无日期全库检索', () {
    expect(
      aiQuestionMatchesTransaction(
        '有哪些钱转进了旅行基金',
        transaction(toAccount: '旅行基金'),
      ),
      isTrue,
    );
  });

  test('没有字段或金额命中时不会把任意旧账塞进结果', () {
    expect(
      aiQuestionMatchesTransaction(
        '帮我看看以前有没有买过显示器',
        transaction(note: '午餐', amount: '28'),
      ),
      isFalse,
    );
  });
}
