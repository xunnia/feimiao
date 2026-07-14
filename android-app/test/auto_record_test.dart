import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/auto_record.dart';
import 'package:qingji/core/models/transaction_kind.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AutoCandidate c({
    required String text,
    required int second,
    String? sourceId,
    Decimal? amount,
    TransactionKind kind = TransactionKind.expense,
  }) {
    return AutoCandidate(
      sourceId: sourceId ?? 'event-$second',
      app: 'wechat',
      text: text,
      time: DateTime(2026, 7, 7, 12, 0, second),
      amount: amount ?? Decimal.parse('2.50'),
      kind: kind,
      categoryKey: 'transport',
    );
  }

  group('AutoRecord.dedupeCandidates', () {
    test('collapses only the exact same native event id', () {
      final items = AutoRecord.dedupeCandidates([
        c(text: 'paid 2.50 to metro', second: 1, sourceId: 'same-event'),
        c(text: 'paid 2.50 to metro', second: 8, sourceId: 'same-event'),
      ]);

      expect(items, hasLength(1));
      expect(items.single.time.second, 1);
    });

    test('keeps same text and amount even inside the old 60 second window', () {
      final items = AutoRecord.dedupeCandidates([
        c(text: 'paid 2.50 to metro', second: 1),
        c(text: 'paid 2.50 to metro', second: 3),
      ]);

      expect(items, hasLength(2));
    });

    test('keeps different directions even when text and amount match', () {
      final items = AutoRecord.dedupeCandidates([
        c(text: 'refund 2.50 from metro', second: 1),
        c(
          text: 'refund 2.50 from metro',
          second: 3,
          kind: TransactionKind.income,
        ),
      ]);

      expect(items, hasLength(2));
    });
  });

  group('AutoRecord native queue acknowledgement', () {
    const channel = MethodChannel('feimiao/autorecord');
    MethodCall? acknowledgement;

    setUp(() {
      acknowledgement = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'peekPending') {
          return jsonEncode([
            {
              'id': 'queue-a',
              'app': '微信',
              'text': '支付给地铁 2.50元',
              'time': DateTime(2026, 7, 11, 8).millisecondsSinceEpoch,
            },
            {
              'id': 'queue-b',
              'app': '微信',
              'text': '支付给地铁 2.50元',
              'time': DateTime(2026, 7, 11, 8, 0, 2).millisecondsSinceEpoch,
            },
            {
              'id': 'queue-refund',
              'app': '支付宝',
              'text': '淘宝退款到账 18.00元',
              'time': DateTime(2026, 7, 11, 9).millisecondsSinceEpoch,
            },
          ]);
        }
        if (call.method == 'ackPending') {
          acknowledgement = call;
          return 2;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('peek keeps two real same-price purchases and ack sends exact ids',
        () async {
      final items = await AutoRecord.pending();

      expect(items, hasLength(3));
      expect(
        items.map((item) => item.sourceId),
        ['queue-a', 'queue-b', 'queue-refund'],
      );
      expect(items.last.isRefund, isTrue);
      await AutoRecord.acknowledge(items);
      expect(acknowledgement?.method, 'ackPending');
      expect(
        (acknowledgement?.arguments as Map<Object?, Object?>)['ids'],
        ['queue-a', 'queue-b', 'queue-refund'],
      );
    });
  });
}
