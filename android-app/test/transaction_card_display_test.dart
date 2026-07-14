import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/models/transaction_card_display.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/transaction_time.dart';

void main() {
  group('transaction card text', () {
    test('content-first uses note as title and category as secondary', () {
      final text = resolveTransactionCardText(
        mode: TransactionCardDisplayMode.contentFirst,
        kind: TransactionKind.expense,
        note: '原神充值',
        categoryName: '虚拟充值',
      );

      expect(text.title, '原神充值');
      expect(text.secondary, '虚拟充值');
    });

    test('category-first swaps the same two semantic fields', () {
      final text = resolveTransactionCardText(
        mode: TransactionCardDisplayMode.categoryFirst,
        kind: TransactionKind.expense,
        note: '原神充值',
        categoryName: '虚拟充值',
      );

      expect(text.title, '虚拟充值');
      expect(text.secondary, '原神充值');
    });

    test('empty note never repeats the category', () {
      for (final mode in TransactionCardDisplayMode.values) {
        final text = resolveTransactionCardText(
          mode: mode,
          kind: TransactionKind.expense,
          note: '  ',
          categoryName: '餐饮',
        );
        expect(text.title, '餐饮');
        expect(text.secondary, isEmpty);
      }
    });

    test('transfer keeps the account route under either preference', () {
      for (final mode in TransactionCardDisplayMode.values) {
        final text = resolveTransactionCardText(
          mode: mode,
          kind: TransactionKind.transfer,
          note: '还信用卡',
          categoryName: '',
          accountName: '储蓄卡',
          toAccountName: '信用卡',
        );
        expect(text.title, '储蓄卡 → 信用卡');
        expect(text.secondary, '还信用卡');
      }
    });
  });

  test('date-grouped and standalone cards use the required time scopes', () {
    final date = DateTime(2026, 7, 14, 9, 6);

    expect(
      transactionCardTimeLabel(
        date,
        dateGrouped: true,
        precision: TransactionTimePrecision.exact,
      ),
      '09:06',
    );
    expect(
      transactionCardTimeLabel(
        date,
        dateGrouped: false,
        precision: TransactionTimePrecision.exact,
      ),
      '2026/07/14 09:06',
    );
  });

  test('exact and entry-clock midnight remain visible', () {
    final midnight = DateTime(2026, 7, 14);

    for (final precision in const [
      TransactionTimePrecision.exact,
      TransactionTimePrecision.entryClock,
    ]) {
      expect(
        transactionCardTimeLabel(
          midnight,
          dateGrouped: true,
          precision: precision,
        ),
        '00:00',
      );
      expect(
        transactionCardTimeLabel(
          midnight,
          dateGrouped: false,
          precision: precision,
        ),
        '2026/07/14 00:00',
      );
    }
  });

  test('date-only clocks are omitted without losing a standalone date', () {
    final date = DateTime(2026, 7, 14);

    expect(
      transactionCardTimeLabel(
        date,
        dateGrouped: true,
        precision: TransactionTimePrecision.dateOnly,
      ),
      isEmpty,
    );
    expect(
      transactionCardTimeLabel(
        date,
        dateGrouped: false,
        precision: TransactionTimePrecision.dateOnly,
      ),
      '2026/07/14',
    );
  });

  test('legacy clocks hide only ambiguous midnight values', () {
    expect(
      transactionCardTimeLabel(
        DateTime(2026, 7, 14),
        dateGrouped: true,
        precision: TransactionTimePrecision.legacyUnknown,
      ),
      isEmpty,
    );
    expect(
      transactionCardTimeLabel(
        DateTime(2026, 7, 14),
        dateGrouped: false,
        precision: TransactionTimePrecision.legacyUnknown,
      ),
      '2026/07/14',
    );
    expect(
      transactionCardTimeLabel(
        DateTime(2026, 7, 14, 9, 6),
        dateGrouped: true,
        precision: TransactionTimePrecision.legacyUnknown,
      ),
      '09:06',
    );
  });

  test('detail joiner removes missing fields without stray separators', () {
    expect(
      joinTransactionCardDetails(['09:06', '', null, '虚拟充值']),
      '09:06 · 虚拟充值',
    );
  });

  test('unknown stored values preserve the new compatible defaults', () {
    expect(
      TransactionCardDisplayModeX.fromStorage('old_value'),
      TransactionCardDisplayMode.contentFirst,
    );
    expect(
      UserMessageBubbleStyleX.fromStorage('old_value'),
      UserMessageBubbleStyle.followCardOpacity,
    );
  });
}
