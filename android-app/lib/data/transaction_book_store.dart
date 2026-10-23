import 'package:sqflite/sqflite.dart';
import '../core/ledger/book_membership.dart';

/// Additive membership overlay. Absence means legacy `book_id`; a default-book
/// row marks an explicit selection even when no scene book is selected.
/// Original transactions and financial settlement evidence are never copied.
abstract final class TransactionBookStore {
  static Future<void> ensureSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS transaction_books (
        transaction_id INTEGER NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
        book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        PRIMARY KEY (transaction_id, book_id)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_transaction_books_book
      ON transaction_books(book_id, transaction_id)
    ''');
    // Existing installs do not consistently enable SQLite foreign_keys.
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS transaction_books_delete_transaction
      AFTER DELETE ON transactions BEGIN
        DELETE FROM transaction_books WHERE transaction_id = OLD.id;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS transaction_books_delete_book
      AFTER DELETE ON books BEGIN
        DELETE FROM transaction_books WHERE book_id = OLD.id;
      END
    ''');
  }

  /// Root membership is also used by every refund/reimbursement child.
  static const selectSql = '''
    COALESCE(
      (SELECT group_concat(tb.book_id) FROM transaction_books tb
       WHERE tb.transaction_id = COALESCE(t.refund_of, t.id)),
      CAST(COALESCE((SELECT original.book_id FROM transactions original
                     WHERE original.id = t.refund_of), t.book_id) AS TEXT)
    )
  ''';

  /// Two placeholders both receive the selected scene ID. Explicit overlays
  /// override legacy provenance, including when a scene has been removed.
  static const scopeSql = '''
    (EXISTS (SELECT 1 FROM transaction_books tb
             WHERE tb.transaction_id = COALESCE(t.refund_of, t.id)
               AND tb.book_id = ?)
     OR (NOT EXISTS (SELECT 1 FROM transaction_books tb
                     WHERE tb.transaction_id = COALESCE(t.refund_of, t.id))
         AND COALESCE((SELECT original.book_id FROM transactions original
                       WHERE original.id = t.refund_of), t.book_id) = ?))
  ''';

  static Set<int> parse(Object? value) => parseTransactionBookIds(value);

  static Future<Set<int>> read(
    DatabaseExecutor db,
    int rootID,
  ) async {
    final rows = await db.rawQuery('''
      SELECT $selectSql AS book_ids FROM transactions t WHERE t.id = ?
    ''', [rootID]);
    if (rows.isEmpty) throw StateError('账单已不存在，请刷新后重试。');
    return parse(rows.single['book_ids']);
  }

  static Future<void> replace(
    DatabaseExecutor db,
    int rootID,
    Iterable<int> sceneIDs, {
    required int defaultBookID,
  }) async {
    final ids = {defaultBookID, ...sceneIDs};
    for (final id in ids) {
      final found = await db.query('books',
          columns: ['id'], where: 'id = ?', whereArgs: [id], limit: 1);
      if (found.isEmpty) throw StateError('所选账本已不存在，请重新选择。');
    }
    await db.delete('transaction_books',
        where: 'transaction_id = ?', whereArgs: [rootID]);
    for (final id in ids) {
      await db.insert('transaction_books', {
        'transaction_id': rootID,
        'book_id': id,
      });
    }
    // Do not rewrite book_id: asset links, recurring origins and old financial
    // evidence still rely on that legacy provenance. The overlay owns scope.
  }

  static Iterable<List<int>> chunks(Iterable<int> ids) sync* {
    final list = ids.toList();
    for (var i = 0; i < list.length; i += 300) {
      yield list.sublist(i, i + 300 > list.length ? list.length : i + 300);
    }
  }

  /// Validate the entire selection first, then write one sqflite batch inside
  /// the caller's transaction. Thousands of old bills must not incur a platform
  /// round trip per membership or exceed SQLite's bound-variable limit.
  static Future<Set<int>> updateMany(
      Transaction txn, Set<int> transactionIDs, Set<int> selected,
      {required int defaultBookID,
      required int updatedMs,
      required bool addOnly,
      required bool removeOnly}) async {
    final valid = (await txn.query('books', columns: ['id']))
        .map((r) => r['id'] as int)
        .toSet();
    if (!{defaultBookID, ...selected}.every(valid.contains)) {
      throw StateError('所选账本已不存在，请重新选择。');
    }
    final roots = <int>{};
    for (final group in chunks(transactionIDs)) {
      final rows = await txn.query('transactions',
          columns: ['id', 'refund_of'],
          where: 'id IN (${List.filled(group.length, '?').join(',')})',
          whereArgs: group);
      if (rows.length != group.length) {
        throw StateError('部分账单已不存在，未修改任何关联。');
      }
      roots.addAll(rows.map((r) => r['refund_of'] as int? ?? r['id'] as int));
    }
    final batch = txn.batch();
    for (final group in chunks(roots)) {
      final rows = await txn.rawQuery('''
        SELECT t.id, $selectSql AS book_ids FROM transactions t
        WHERE t.id IN (${List.filled(group.length, '?').join(',')})
      ''', group);
      if (rows.length != group.length) throw StateError('找不到原账单，请刷新后重试。');
      for (final row in rows) {
        final root = row['id'] as int;
        final current = parse(row['book_ids']).intersection(valid);
        final next = addOnly
            ? {...current, ...selected}
            : removeOnly
                ? (current..removeAll(selected))
                : selected;
        batch.delete('transaction_books',
            where: 'transaction_id = ?', whereArgs: [root]);
        for (final book in {defaultBookID, ...next}) {
          batch.insert(
              'transaction_books', {'transaction_id': root, 'book_id': book});
        }
        batch.update('transactions', {'updated_ms': updatedMs},
            where: 'id = ? OR refund_of = ?', whereArgs: [root, root]);
      }
    }
    await batch.commit(noResult: true);
    return roots;
  }
}
