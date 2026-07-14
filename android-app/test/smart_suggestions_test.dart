import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/smart_suggestions.dart';
import 'package:qingji/core/ledger/ledger_policy.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/models/transaction_record.dart';
import 'package:qingji/core/transaction_time.dart';
import 'package:qingji/data/app_repository.dart';

void main() {
  final now = DateTime(2026, 7, 14, 12, 30);

  group('SmartSuggestionEngine record suggestions', () {
    test('requires a repeated leaf-category and normalized-note signature', () {
      final records = [
        _expense(1, DateTime(2026, 7, 10, 12, 10), '18', note: '记一笔 瑞幸咖啡 18元'),
        _expense(2, DateTime(2026, 7, 11, 12, 20), '18', note: '瑞幸咖啡 ¥18'),
        _expense(3, DateTime(2026, 7, 12, 12, 5), '18.3', note: '昨天 瑞幸咖啡18.3元'),
      ];

      final suggestions = SmartSuggestionEngine.build(
        records: records,
        now: now,
      );

      expect(_recordTexts(suggestions), ['记一笔 瑞幸咖啡 18']);
    });

    test('does not blend a broad category into a made-up typical amount', () {
      final records = [
        _expense(1, DateTime(2026, 7, 7, 12), '2',
            note: '记一笔 公共交通 2元',
            categoryKey: 'trans_public',
            categoryName: '公共交通',
            topCategoryKey: 'transport'),
        _expense(2, DateTime(2026, 7, 8, 12), '4.3',
            note: '公共交通4.3元',
            categoryKey: 'trans_public',
            categoryName: '公共交通',
            topCategoryKey: 'transport'),
        _expense(3, DateTime(2026, 7, 9, 12), '2',
            note: '公共交通 2',
            categoryKey: 'trans_public',
            categoryName: '公共交通',
            topCategoryKey: 'transport'),
        _expense(4, DateTime(2026, 7, 10, 12), '21.2',
            note: '食品餐饮21.2元',
            categoryKey: 'dining_lunch',
            categoryName: '食品餐饮',
            topCategoryKey: 'dining'),
      ];

      final suggestions = SmartSuggestionEngine.build(
        records: records,
        now: now,
      );

      expect(_recordTexts(suggestions), isEmpty);
    });

    test('keeps a useful signature but omits an unstable amount', () {
      final records = [
        _expense(1, DateTime(2026, 7, 10, 12), '12', note: '蒙自源'),
        _expense(2, DateTime(2026, 7, 11, 12), '28', note: '蒙自源'),
        _expense(3, DateTime(2026, 7, 12, 12), '53', note: '蒙自源'),
      ];

      final suggestions = SmartSuggestionEngine.build(
        records: records,
        now: now,
      );

      expect(_recordTexts(suggestions), ['记一笔 蒙自源']);
    });

    test('allows one amount outlier only after four observations', () {
      final records = [
        _expense(1, DateTime(2026, 7, 8, 12), '20', note: '公司咖啡机'),
        _expense(2, DateTime(2026, 7, 9, 12), '20', note: '公司咖啡机'),
        _expense(3, DateTime(2026, 7, 10, 12), '20', note: '公司咖啡机'),
        _expense(4, DateTime(2026, 7, 12, 12), '100', note: '公司咖啡机'),
      ];

      final suggestions = SmartSuggestionEngine.build(
        records: records,
        now: now,
      );

      expect(_recordTexts(suggestions), ['记一笔 公司咖啡机 20']);
    });

    test('never suggests a signature already recorded today', () {
      final records = [
        _expense(1, DateTime(2026, 7, 10, 12), '18', note: '瑞幸咖啡'),
        _expense(2, DateTime(2026, 7, 11, 12), '18', note: '瑞幸咖啡'),
        _expense(3, DateTime(2026, 7, 12, 12), '18', note: '瑞幸咖啡'),
        _expense(4, DateTime(2026, 7, 14, 8), '18', note: '瑞幸咖啡'),
      ];

      final suggestions = SmartSuggestionEngine.build(
        records: records,
        now: now,
      );

      expect(_recordTexts(suggestions), isEmpty);
    });

    test('date-only and legacy 00:00 values are not time-of-day evidence', () {
      final midnightNow = DateTime(2026, 7, 14, 0, 30);
      for (final precision in const [
        TransactionTimePrecision.dateOnly,
        TransactionTimePrecision.legacyUnknown,
      ]) {
        final records = [
          _expense(1, DateTime(2026, 7, 1), '18',
              note: '夜间便利店', timePrecision: precision),
          _expense(2, DateTime(2026, 7, 6), '18',
              note: '夜间便利店', timePrecision: precision),
          _expense(3, DateTime(2026, 7, 13), '18',
              note: '夜间便利店', timePrecision: precision),
        ];

        final suggestions = SmartSuggestionEngine.build(
          records: records,
          now: midnightNow,
        );

        expect(_recordTexts(suggestions), isEmpty, reason: precision.name);
      }
    });

    test('exact midnight is valid time-of-day evidence', () {
      final midnightNow = DateTime(2026, 7, 14, 0, 30);
      final records = [
        _expense(1, DateTime(2026, 7, 1), '18', note: '夜间便利店'),
        _expense(2, DateTime(2026, 7, 6), '18', note: '夜间便利店'),
        _expense(3, DateTime(2026, 7, 13), '18', note: '夜间便利店'),
      ];

      final suggestions = SmartSuggestionEngine.build(
        records: records,
        now: midnightNow,
      );

      expect(_recordTexts(suggestions), ['记一笔 夜间便利店 18']);
    });

    test('entry-clock evidence scores below exact occurrence time', () {
      final midnightNow = DateTime(2026, 7, 14, 0, 30);
      List<TransactionRecord> records(TransactionTimePrecision precision) => [
            _expense(1, DateTime(2026, 7, 1), '18',
                note: '夜间便利店', timePrecision: precision),
            _expense(2, DateTime(2026, 7, 6), '18',
                note: '夜间便利店', timePrecision: precision),
            _expense(3, DateTime(2026, 7, 13), '18',
                note: '夜间便利店', timePrecision: precision),
          ];

      final exact = SmartSuggestionEngine.build(
        records: records(TransactionTimePrecision.exact),
        now: midnightNow,
      ).firstWhere((item) => item.kind == SmartSuggestionKind.record);
      final entryClock = SmartSuggestionEngine.build(
        records: records(TransactionTimePrecision.entryClock),
        now: midnightNow,
      ).firstWhere((item) => item.kind == SmartSuggestionKind.record);

      expect(entryClock.evidenceScore, lessThan(exact.evidenceScore));
    });

    test('can use a real weekly cadence even when old rows are date-only', () {
      final tuesdayNow = DateTime(2026, 7, 14, 9);
      final records = [
        _expense(1, DateTime(2026, 6, 23), '30',
            note: '周二游泳', timePrecision: TransactionTimePrecision.dateOnly),
        _expense(2, DateTime(2026, 6, 30), '30',
            note: '周二游泳', timePrecision: TransactionTimePrecision.dateOnly),
        _expense(3, DateTime(2026, 7, 7), '30',
            note: '周二游泳', timePrecision: TransactionTimePrecision.dateOnly),
      ];

      final suggestions = SmartSuggestionEngine.build(
        records: records,
        now: tuesdayNow,
      );

      expect(_recordTexts(suggestions), ['记一笔 周二游泳 30']);
    });

    test('ignores repeated prices older than the 180-day learning window', () {
      final records = [
        _expense(1, DateTime(2025, 9, 2, 12), '12', note: '旧公司食堂'),
        _expense(2, DateTime(2025, 9, 9, 12), '12', note: '旧公司食堂'),
        _expense(3, DateTime(2025, 9, 16, 12), '12', note: '旧公司食堂'),
        _expense(4, DateTime(2025, 9, 23, 12), '12', note: '旧公司食堂'),
      ];

      final suggestions = SmartSuggestionEngine.build(
        records: records,
        now: now,
      );

      expect(_recordTexts(suggestions), isEmpty);
    });

    test('same-day duplicates cannot manufacture a stable typical amount', () {
      final records = [
        for (var index = 0; index < 8; index++)
          _expense(index, DateTime(2026, 7, 10, 11, index), '20',
              note: '共享打印机'),
        _expense(20, DateTime(2026, 7, 11, 11), '40', note: '共享打印机'),
        _expense(21, DateTime(2026, 7, 12, 11), '80', note: '共享打印机'),
      ];

      final suggestions = SmartSuggestionEngine.build(
        records: records,
        now: now,
      );

      expect(_recordTexts(suggestions), ['记一笔 共享打印机']);
    });

    test('does not pool different merchants or use a top-level category', () {
      final records = [
        _expense(1, DateTime(2026, 7, 9, 12), '18', note: '瑞幸咖啡'),
        _expense(2, DateTime(2026, 7, 10, 12), '18', note: '瑞幸咖啡'),
        _expense(3, DateTime(2026, 7, 11, 12), '30', note: '星巴克'),
        _expense(4, DateTime(2026, 7, 12, 12), '30', note: '星巴克'),
        _expense(5, DateTime(2026, 7, 9, 12), '15',
            note: '园区早餐',
            categoryKey: 'dining',
            categoryName: '食品餐饮',
            topCategoryKey: 'dining'),
        _expense(6, DateTime(2026, 7, 10, 12), '15',
            note: '园区早餐',
            categoryKey: 'dining',
            categoryName: '食品餐饮',
            topCategoryKey: 'dining'),
        _expense(7, DateTime(2026, 7, 11, 12), '15',
            note: '园区早餐',
            categoryKey: 'dining',
            categoryName: '食品餐饮',
            topCategoryKey: 'dining'),
      ];

      final suggestions = SmartSuggestionEngine.build(
        records: records,
        now: now,
      );

      expect(_recordTexts(suggestions), isEmpty);
    });

    test('is deterministic regardless of source ordering', () {
      final records = [
        _expense(1, DateTime(2026, 7, 8, 12), '18', note: '瑞幸咖啡'),
        _expense(2, DateTime(2026, 7, 10, 12), '18', note: '瑞幸咖啡'),
        _expense(3, DateTime(2026, 7, 12, 12), '18', note: '瑞幸咖啡'),
        _expense(4, DateTime(2026, 7, 8, 12), '12', note: '园区早餐'),
        _expense(5, DateTime(2026, 7, 10, 12), '12', note: '园区早餐'),
        _expense(6, DateTime(2026, 7, 12, 12), '12', note: '园区早餐'),
      ];

      final forward = SmartSuggestionEngine.build(records: records, now: now);
      final reversed = SmartSuggestionEngine.build(
        records: records.reversed,
        now: now,
      );

      expect(
        forward.map((suggestion) => suggestion.text),
        reversed.map((suggestion) => suggestion.text),
      );
    });
  });

  group('SmartSuggestionEngine query suggestions', () {
    test('returns no random filler when evidence is absent', () {
      expect(
        SmartSuggestionEngine.build(records: const [], now: now),
        isEmpty,
      );

      final oneRow = [
        _expense(1, DateTime(2026, 7, 14, 10), '20', note: ''),
      ];
      expect(
        SmartSuggestionEngine.build(records: oneRow, now: now),
        isEmpty,
      );
    });

    test('shows a budget query only when a budget really exists', () {
      final suggestions = SmartSuggestionEngine.build(
        records: const [],
        now: now,
        hasActiveBudget: true,
      );

      expect(_queryTexts(suggestions), ['本月预算还剩多少']);
    });

    test('ranks only queries supported by sufficient current ledger data', () {
      final records = <TransactionRecord>[
        _expense(1, DateTime(2026, 7, 2, 12), '20', note: ''),
        _expense(2, DateTime(2026, 7, 7, 12), '30', note: ''),
        _expense(3, DateTime(2026, 7, 13, 12), '40', note: ''),
        _income(4, DateTime(2026, 7, 5, 9), '5000'),
        _expense(5, DateTime(2026, 7, 13, 18), '25',
            note: '',
            categoryKey: 'dining_dinner',
            categoryName: '晚餐',
            topCategoryKey: 'dining'),
        _expense(6, DateTime(2026, 7, 14, 12), '18',
            note: '',
            categoryKey: 'dining_lunch',
            categoryName: '午餐',
            topCategoryKey: 'dining'),
        _expense(7, DateTime(2026, 6, 2, 12), '20', note: ''),
        _expense(8, DateTime(2026, 6, 7, 12), '30', note: ''),
        _expense(9, DateTime(2026, 6, 13, 12), '40', note: ''),
      ];

      final suggestions = SmartSuggestionEngine.build(
        records: records,
        now: now,
        hasActiveBudget: true,
      );

      expect(_queryTexts(suggestions), [
        '本月预算还剩多少',
        '本月比上月同期多吗',
        '本月收支结余多少',
        '这周吃饭花了多少',
      ]);
    });

    test('uses a single exact month-total query for a sparse month', () {
      final records = [
        _expense(1, DateTime(2026, 7, 2, 12), '20', note: ''),
        _expense(2, DateTime(2026, 7, 6, 12), '30', note: ''),
        _expense(3, DateTime(2026, 7, 10, 12), '40', note: ''),
      ];

      final suggestions = SmartSuggestionEngine.build(
        records: records,
        now: now,
      );

      expect(_queryTexts(suggestions), ['这个月花了多少']);
    });

    test('never exceeds the requested limit', () {
      final records = <TransactionRecord>[
        for (var day = 1; day <= 8; day++)
          _expense(day, DateTime(2026, 7, day, 12), '20',
              note: day.isEven ? '瑞幸咖啡' : ''),
        for (var day = 1; day <= 4; day++)
          _expense(20 + day, DateTime(2026, 6, day, 12), '20', note: ''),
        _income(40, DateTime(2026, 7, 5, 9), '5000'),
      ];

      final suggestions = SmartSuggestionEngine.build(
        records: records,
        now: now,
        hasActiveBudget: true,
        limit: 2,
      );

      expect(suggestions, hasLength(2));
    });

    test('content fingerprint changes after an in-place edit', () {
      final original = [
        _expense(1, DateTime(2026, 7, 10, 12), '18', note: '瑞幸咖啡'),
      ];
      final editedAmount = [
        _expense(1, DateTime(2026, 7, 10, 12), '21', note: '瑞幸咖啡'),
      ];
      final editedNote = [
        _expense(1, DateTime(2026, 7, 10, 12), '18', note: '星巴克'),
      ];
      final editedPrecision = [
        _expense(1, DateTime(2026, 7, 10, 12), '18',
            note: '瑞幸咖啡', timePrecision: TransactionTimePrecision.entryClock),
      ];

      final originalKey = SmartSuggestionEngine.contentFingerprint(
        records: original,
        hasActiveBudget: false,
      );

      expect(
        SmartSuggestionEngine.contentFingerprint(
          records: editedAmount,
          hasActiveBudget: false,
        ),
        isNot(originalKey),
      );
      expect(
        SmartSuggestionEngine.contentFingerprint(
          records: editedNote,
          hasActiveBudget: false,
        ),
        isNot(originalKey),
      );
      expect(
        SmartSuggestionEngine.contentFingerprint(
          records: editedPrecision,
          hasActiveBudget: false,
        ),
        isNot(originalKey),
      );
      expect(
        SmartSuggestionEngine.contentFingerprint(
          records: original,
          hasActiveBudget: true,
        ),
        isNot(originalKey),
      );
    });

    test('repository entity conversions retain time precision', () {
      final entity = TransactionEntity(
        id: 1,
        kind: TransactionKind.expense.toJson(),
        amountStr: '18',
        dateMs: DateTime(2026, 7, 13).millisecondsSinceEpoch,
        timePrecision: TransactionTimePrecision.exact,
      );

      expect(
        entity.toRecord().timePrecision,
        TransactionTimePrecision.exact,
      );
      expect(
        LedgerPolicy.toUserRecordWith(entity, <int, Decimal>{}).timePrecision,
        TransactionTimePrecision.exact,
      );
    });
  });
}

TransactionRecord _expense(
  int id,
  DateTime date,
  String amount, {
  required String note,
  String categoryKey = 'dining_drink',
  String categoryName = '饮料',
  String topCategoryKey = 'dining',
  TransactionTimePrecision timePrecision = TransactionTimePrecision.exact,
}) =>
    TransactionRecord(
      id: '$id',
      kind: TransactionKind.expense,
      amount: Decimal.parse(amount),
      categoryKey: categoryKey,
      categoryName: categoryName,
      topCategoryKey: topCategoryKey,
      topCategoryName: topCategoryKey == 'dining' ? '食品餐饮' : '出行交通',
      note: note,
      date: date,
      timePrecision: timePrecision,
    );

TransactionRecord _income(int id, DateTime date, String amount) =>
    TransactionRecord(
      id: '$id',
      kind: TransactionKind.income,
      amount: Decimal.parse(amount),
      categoryKey: 'salary_base',
      categoryName: '基本工资',
      topCategoryKey: 'salary',
      topCategoryName: '工资薪酬',
      note: '',
      date: date,
      timePrecision: TransactionTimePrecision.exact,
    );

List<String> _recordTexts(List<SmartSuggestion> suggestions) => suggestions
    .where((suggestion) => suggestion.kind == SmartSuggestionKind.record)
    .map((suggestion) => suggestion.text)
    .toList(growable: false);

List<String> _queryTexts(List<SmartSuggestion> suggestions) => suggestions
    .where((suggestion) => suggestion.kind == SmartSuggestionKind.query)
    .map((suggestion) => suggestion.text)
    .toList(growable: false);
