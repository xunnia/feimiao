import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/notification_parse.dart';
import 'package:qingji/core/models/transaction_kind.dart';

void main() {
  group('NotificationParse.pickAmount — 避开余额取本次支付', () {
    test('付款¥X 在前、余额在后', () {
      expect(NotificationParse.pickAmount('微信支付 你已成功付款¥23.50,余额¥1000.00'),
          Decimal.parse('23.50'));
    });
    test('余额在前、消费¥X 在后', () {
      expect(NotificationParse.pickAmount('账户余额¥1000.00 本次消费¥23.5'),
          Decimal.parse('23.5'));
    });
    test('「数字元」格式(支付宝)', () {
      expect(NotificationParse.pickAmount('支付宝 你有一笔23.50元的支出'),
          Decimal.parse('23.50'));
    });
    test('无金额返回 null', () {
      expect(NotificationParse.pickAmount('今天天气很好'), isNull);
    });
  });

  group('NotificationParse.kindOf — 收支方向', () {
    test('付款=支出', () {
      expect(NotificationParse.kindOf('付款成功¥10'), TransactionKind.expense);
    });
    test('收款=收入', () {
      expect(NotificationParse.kindOf('你已收款¥10'), TransactionKind.income);
    });
    test('退款=收入', () {
      expect(NotificationParse.kindOf('退款成功¥10'), TransactionKind.income);
    });
    test('向你转账=收入', () {
      expect(NotificationParse.kindOf('张三向你转账¥50'), TransactionKind.income);
    });
    test('转账给别人=支出', () {
      expect(NotificationParse.kindOf('转账给张三¥50'), TransactionKind.expense);
    });
  });

  group('NotificationParse.isRefund — 退款事件', () {
    test('识别退款到账通知', () {
      expect(NotificationParse.isRefund('淘宝退款到账 ￥23.50'), isTrue);
      expect(NotificationParse.isRefund('商家已退回 18 元'), isTrue);
    });

    test('普通收入不误判为退款', () {
      expect(NotificationParse.isRefund('工资到账 8000 元'), isFalse);
      expect(NotificationParse.isRefund('收到转账 50 元'), isFalse);
    });
  });
}
