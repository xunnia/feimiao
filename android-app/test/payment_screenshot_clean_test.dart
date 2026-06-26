import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/natural_language_entry_parser.dart';

void main() {
  group('PaymentScreenshotParser.cleanOcr', () {
    test('剔除订单号/卡号/手机号/纯长数字，保留商户与金额', () {
      const raw = '''
支付成功
¥38.00
收款方
瑞幸咖啡
订单号
4200001234567890123
13800138000
交易时间 2026-06-20 12:30
''';
      final cleaned = PaymentScreenshotParser.cleanOcr(raw);
      // 保留
      expect(cleaned.contains('瑞幸咖啡'), isTrue);
      expect(cleaned.contains('¥38.00'), isTrue);
      expect(cleaned.contains('2026-06-20'), isTrue);
      // 剔除
      expect(cleaned.contains('订单号'), isFalse);
      expect(cleaned.contains('4200001234567890123'), isFalse); // 纯长数字
      expect(cleaned.contains('13800138000'), isFalse); // 手机号
    });

    test('含 ¥ 的余额行保守保留(交给提示词忽略)，不误删真金额', () {
      const raw = '实付 ¥58.00\n账户余额 ¥1234.56';
      final cleaned = PaymentScreenshotParser.cleanOcr(raw);
      expect(cleaned.contains('¥58.00'), isTrue); // 真金额必须在
    });
  });
}
