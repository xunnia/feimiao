import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/import/bill_import.dart';
import 'package:qingji/core/models/transaction_kind.dart';

void main() {
  group('BillImporter', () {
    test('微信账单：跳过说明行 + 中性记录', () {
      const csv = '''
微信支付账单明细
微信昵称：[喵喵]
起始时间：[2024-01-01 00:00:00] 终止时间：[2024-01-31 23:59:59]
共3笔记录
----------------------微信支付账单明细列表--------------------
交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
2024-01-05 12:30:00,商户消费,星巴克,拿铁,支出,¥35.00,零钱,支付成功,1,2,
2024-01-06 09:00:00,转账,朋友,转账,收入,¥100.00,零钱,已收钱,3,4,
2024-01-07 10:00:00,零钱提现,/,提现,/,¥50.00,零钱,提现成功,5,6,
''';
      final r = BillImporter.parseString(csv);
      expect(r.source, '微信');
      expect(r.rows.length, 2); // 提现(中性)被跳过
      expect(r.skipped, 1);

      final coffee = r.rows[0];
      expect(coffee.kind, TransactionKind.expense);
      expect(coffee.amount, Decimal.parse('35.00'));
      expect(coffee.note.contains('星巴克'), isTrue);

      expect(r.rows[1].kind, TransactionKind.income);
      expect(r.rows[1].amount, Decimal.parse('100.00'));
    });

    test('支付宝账单：全角括号表头 + 不计收支跳过', () {
      const csv = '''
支付宝交易记录明细查询
账号：[xxx]
---------------------------------交易记录明细列表---------------------------
交易号,商家订单号,交易创建时间,付款时间,最近修改时间,交易来源地,类型,交易对方,商品名称,金额（元）,收/支,交易状态,服务费（元）,成功退款（元）,备注,资金状态
1,2,2024-01-10 08:00:00,2024-01-10 08:00:00,2024-01-10 08:00:00,支付宝网站,即时到账,某超市,日用品,58.50,支出,交易成功,0.00,0.00,,已支出
3,4,2024-01-11 08:00:00,,,,余额宝,理财,收益,0.30,不计收支,交易成功,0.00,0.00,,资金转移
''';
      final r = BillImporter.parseString(csv);
      expect(r.source, '支付宝');
      expect(r.rows.length, 1); // 不计收支被跳过
      expect(r.rows[0].kind, TransactionKind.expense);
      expect(r.rows[0].amount, Decimal.parse('58.50'));
      expect(r.rows[0].note.contains('某超市'), isTrue);
    });

    test('通用 CSV：按列名匹配，类型列定方向', () {
      const csv = '''
日期,类型,金额,分类,备注
2024-02-01,支出,12.5,餐饮,午饭
2024-02-02,收入,3000,工资,
''';
      final r = BillImporter.parseString(csv);
      expect(r.rows.length, 2);
      expect(r.rows[0].kind, TransactionKind.expense);
      expect(r.rows[0].category, '餐饮');
      expect(r.rows[0].note, '午饭');
      expect(r.rows[0].amount, Decimal.parse('12.5'));
      expect(r.rows[1].kind, TransactionKind.income);
      expect(r.rows[1].category, '工资');
    });

    test('金额带千分位和符号也能解析', () {
      const csv = '''
日期,收/支,金额,备注
2024-03-01,支出,"¥1,234.56",大件
''';
      final r = BillImporter.parseString(csv);
      expect(r.rows.length, 1);
      expect(r.rows[0].amount, Decimal.parse('1234.56'));
    });
  });
}
