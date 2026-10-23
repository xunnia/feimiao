import 'dart:io';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ledger/book_membership.dart';
import 'package:qingji/core/models/account_entities.dart' as domain;
import 'package:qingji/core/models/ledger_entities.dart';
import 'package:qingji/data/app_repository.dart' as legacy;

void main() {
  test(
      'legacy repository exports the same domain types, with no mapping or copies',
      () {
    final domain.AccountEntity account = legacy.AccountEntity(
        id: 1,
        name: '现金',
        currencyCode: 'CNY',
        type: domain.AccountType.cash,
        openingBalance: Decimal.fromInt(10));
    expect(account, isA<legacy.AccountEntity>());
    final transaction = TransactionEntity.fromMap({
      'id': 1,
      'kind': 'expense',
      'amount': '12.34',
      'date_ms': 0,
      'book_id': 9,
      'book_ids': '2,3,2'
    });
    expect(transaction, isA<legacy.TransactionEntity>());
    expect(transaction.bookIds, {2, 3});
    expect(
        TransactionEntity.fromMap({
          'id': 1,
          'kind': 'expense',
          'amount': '1',
          'date_ms': 0,
          'book_id': 9
        }).bookIds,
        {9});
    expect(parseTransactionBookIds(''), isEmpty);
    expect(parseTransactionBookIds(null), isEmpty);
  });

  test(
      'ledger domain dependency graph cannot import repository, SQLite or Flutter',
      () {
    final visited = <String>{};
    void visit(File file) {
      final path = file.absolute.uri.normalizePath().toFilePath();
      if (!visited.add(path)) {
        return;
      }
      final text = file.readAsStringSync();
      final imports =
          RegExp("(?:import|export)\\s+['\"]([^'\"]+)['\"]").allMatches(text);
      for (final match in imports) {
        final uri = match.group(1)!;
        expect(
            uri.contains('data/') ||
                uri.contains('sqflite') ||
                uri.startsWith('package:flutter/'),
            isFalse,
            reason: '${file.path} imports $uri');
        if (!uri.contains(':')) {
          visit(File.fromUri(file.absolute.uri.resolve(uri)));
        }
      }
    }

    for (final path in [
      'lib/core/ledger/ledger_policy.dart',
      'lib/core/models/account_entities.dart',
      'lib/core/models/asset_entities.dart',
      'lib/core/models/ledger_entities.dart'
    ]) {
      visit(File(path));
    }
  });
}
