import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/models/category_seed.dart';
import '../core/models/transaction_kind.dart';
import '../core/models/transaction_record.dart';

// ---------------------------------------------------------------------------
// 领域实体（带数据库 id，方便 UI 层操作）
// ---------------------------------------------------------------------------

/// 账户实体。
class AccountEntity {
  final int id;
  final String name;
  final String currencyCode;

  const AccountEntity({
    required this.id,
    required this.name,
    this.currencyCode = 'CNY',
  });

  Map<String, Object?> toMap() => {
        'id': id == 0 ? null : id,
        'name': name,
        'currency_code': currencyCode,
      };

  factory AccountEntity.fromMap(Map<String, Object?> m) => AccountEntity(
        id: m['id'] as int,
        name: m['name'] as String,
        currencyCode: m['currency_code'] as String? ?? 'CNY',
      );
}

/// 分类实体。
class CategoryEntity {
  final int id;
  final String key;
  final String nameZh;
  final String nameEn;
  final String kindRaw;

  TransactionKind get kind => TransactionKind.fromJson(kindRaw);

  const CategoryEntity({
    required this.id,
    required this.key,
    required this.nameZh,
    required this.nameEn,
    required this.kindRaw,
  });

  String localizedName(String languageCode) =>
      languageCode.toLowerCase().startsWith('zh') ? nameZh : nameEn;

  Map<String, Object?> toMap() => {
        'id': id == 0 ? null : id,
        'key': key,
        'name_zh': nameZh,
        'name_en': nameEn,
        'kind': kindRaw,
      };

  factory CategoryEntity.fromMap(Map<String, Object?> m) => CategoryEntity(
        id: m['id'] as int,
        key: m['key'] as String,
        nameZh: m['name_zh'] as String,
        nameEn: m['name_en'] as String,
        kindRaw: m['kind'] as String,
      );
}

/// 交易实体（从数据库读出，包含关联对象冗余字段以避免 JOIN）。
class TransactionEntity {
  final int id;
  final String kind;           // TransactionKind.name
  final String amountStr;      // Decimal.toString() 字符串，保精度
  final String currencyCode;
  final int? categoryId;
  final String categoryKey;
  final String categoryNameZh;
  final String categoryNameEn;
  final int? accountId;
  final String accountName;
  final int? toAccountId;
  final String toAccountName;
  final String note;
  final int dateMs;            // DateTime.millisecondsSinceEpoch

  Decimal get amount => Decimal.parse(amountStr);
  DateTime get date => DateTime.fromMillisecondsSinceEpoch(dateMs);
  TransactionKind get txKind => TransactionKind.fromJson(kind);

  const TransactionEntity({
    required this.id,
    required this.kind,
    required this.amountStr,
    this.currencyCode = 'CNY',
    this.categoryId,
    this.categoryKey = '',
    this.categoryNameZh = '',
    this.categoryNameEn = '',
    this.accountId,
    this.accountName = '',
    this.toAccountId,
    this.toAccountName = '',
    this.note = '',
    required this.dateMs,
  });

  /// 转为 core 层的纯逻辑对象（用于统计引擎等）。
  TransactionRecord toRecord({String languageCode = 'zh'}) =>
      TransactionRecord(
        id: id.toString(),
        kind: txKind,
        amount: amount,
        currencyCode: currencyCode,
        categoryName: languageCode.startsWith('zh') ? categoryNameZh : categoryNameEn,
        accountName: accountName,
        toAccountName: toAccountName,
        note: note,
        date: date,
      );

  factory TransactionEntity.fromMap(Map<String, Object?> m) => TransactionEntity(
        id: m['id'] as int,
        kind: m['kind'] as String,
        amountStr: m['amount'] as String,
        currencyCode: m['currency_code'] as String? ?? 'CNY',
        categoryId: m['category_id'] as int?,
        categoryKey: m['category_key'] as String? ?? '',
        categoryNameZh: m['category_name_zh'] as String? ?? '',
        categoryNameEn: m['category_name_en'] as String? ?? '',
        accountId: m['account_id'] as int?,
        accountName: m['account_name'] as String? ?? '',
        toAccountId: m['to_account_id'] as int?,
        toAccountName: m['to_account_name'] as String? ?? '',
        note: m['note'] as String? ?? '',
        dateMs: m['date_ms'] as int,
      );
}

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

/// 本地 SQLite 数据仓库，暴露给 UI 层的状态管理入口。
///
/// 继承 [ChangeNotifier]，UI 通过 [provider] 订阅变化。
class AppRepository extends ChangeNotifier {
  static const _dbVersion = 2;
  static const _dbName = 'qingji.db';

  Database? _db;

  // 内存缓存
  final List<AccountEntity> _accounts = [];
  final List<CategoryEntity> _categories = [];
  final List<TransactionEntity> _transactions = [];

  /// 月度总预算（null = 未设置）。
  Decimal? _monthlyBudget;

  List<AccountEntity> get accounts => List.unmodifiable(_accounts);
  List<CategoryEntity> get categories => List.unmodifiable(_categories);
  List<TransactionEntity> get transactions => List.unmodifiable(_transactions);

  /// 当前月度预算，null 代表未设置。
  Decimal? get monthlyBudget => _monthlyBudget;

  // ---------------------------------------------------------------------------
  // 初始化
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    final dbPath = p.join(await getDatabasesPath(), _dbName);
    _db = await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    await _seedIfNeeded();
    await _loadAll();
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE accounts (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        name          TEXT NOT NULL,
        currency_code TEXT NOT NULL DEFAULT 'CNY'
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
        id      INTEGER PRIMARY KEY AUTOINCREMENT,
        key     TEXT NOT NULL UNIQUE,
        name_zh TEXT NOT NULL,
        name_en TEXT NOT NULL,
        kind    TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        kind            TEXT NOT NULL,
        amount          TEXT NOT NULL,
        currency_code   TEXT NOT NULL DEFAULT 'CNY',
        category_id     INTEGER REFERENCES categories(id),
        account_id      INTEGER REFERENCES accounts(id),
        to_account_id   INTEGER REFERENCES accounts(id),
        note            TEXT NOT NULL DEFAULT '',
        date_ms         INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE budget (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        category_key TEXT,
        amount       TEXT NOT NULL
      )
    ''');
  }

  /// 数据库升级：v1→v2 在 budget 表加 category_key 列。
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v1 的 budget 表没有 category_key 列，添加之。
      await db.execute(
          'ALTER TABLE budget ADD COLUMN category_key TEXT');
    }
  }

  /// 首次启动写入默认账户和分类种子数据。
  Future<void> _seedIfNeeded() async {
    final db = _db!;
    final accountCount =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM accounts')) ?? 0;
    if (accountCount > 0) return; // 已初始化，跳过

    // 默认账户：现金
    await db.insert('accounts', {'name': '现金', 'currency_code': 'CNY'});

    // 默认分类种子
    final batch = db.batch();
    for (final seed in CategorySeed.all) {
      batch.insert('categories', {
        'key': seed.key,
        'name_zh': seed.nameZh,
        'name_en': seed.nameEn,
        'kind': seed.kind.toJson(),
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadAccounts(),
      _loadCategories(),
      _loadTransactions(),
      _loadBudget(),
    ]);
    notifyListeners();
  }

  Future<void> _loadAccounts() async {
    final rows = await _db!.query('accounts');
    _accounts
      ..clear()
      ..addAll(rows.map(AccountEntity.fromMap));
  }

  Future<void> _loadCategories() async {
    final rows = await _db!.query('categories');
    _categories
      ..clear()
      ..addAll(rows.map(CategoryEntity.fromMap));
  }

  /// 读取 category_key 为 NULL 的那条预算行（月度总预算）。
  Future<void> _loadBudget() async {
    final rows = await _db!.query(
      'budget',
      where: 'category_key IS NULL',
      limit: 1,
    );
    if (rows.isEmpty) {
      _monthlyBudget = null;
    } else {
      final raw = rows.first['amount'] as String;
      final value = Decimal.parse(raw);
      _monthlyBudget = value > Decimal.zero ? value : null;
    }
  }

  /// 查询时做一次 LEFT JOIN 把分类/账户冗余字段带出来，避免后续多次查询。
  Future<void> _loadTransactions() async {
    final rows = await _db!.rawQuery('''
      SELECT
        t.id,
        t.kind,
        t.amount,
        t.currency_code,
        t.category_id,
        c.key      AS category_key,
        c.name_zh  AS category_name_zh,
        c.name_en  AS category_name_en,
        t.account_id,
        a.name     AS account_name,
        t.to_account_id,
        ta.name    AS to_account_name,
        t.note,
        t.date_ms
      FROM transactions t
      LEFT JOIN categories c  ON c.id = t.category_id
      LEFT JOIN accounts   a  ON a.id = t.account_id
      LEFT JOIN accounts   ta ON ta.id = t.to_account_id
      ORDER BY t.date_ms DESC
    ''');
    _transactions
      ..clear()
      ..addAll(rows.map(TransactionEntity.fromMap));
  }

  // ---------------------------------------------------------------------------
  // 写操作
  // ---------------------------------------------------------------------------

  /// 新增一笔交易。
  ///
  /// [categoryId] 支出/收入必须提供；[toAccountId] 转账必须提供。
  Future<void> addTransaction({
    required TransactionKind kind,
    required Decimal amount,
    String currencyCode = 'CNY',
    int? categoryId,
    required int accountId,
    int? toAccountId,
    String note = '',
    required DateTime date,
  }) async {
    await _db!.insert('transactions', {
      'kind': kind.toJson(),
      'amount': amount.toString(),
      'currency_code': currencyCode,
      'category_id': categoryId,
      'account_id': accountId,
      'to_account_id': toAccountId,
      'note': note,
      'date_ms': date.millisecondsSinceEpoch,
    });
    await _loadTransactions();
    notifyListeners();
  }

  /// 删除一笔交易（按数据库 id）。
  Future<void> deleteTransaction(int id) async {
    await _db!.delete('transactions', where: 'id = ?', whereArgs: [id]);
    _transactions.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 查询辅助
  // ---------------------------------------------------------------------------

  /// 返回指定 kind 的分类列表。
  List<CategoryEntity> categoriesForKind(TransactionKind kind) =>
      _categories.where((c) => c.kind == kind).toList();

  /// 返回所有交易转换为 core 的 [TransactionRecord]（用于统计引擎）。
  List<TransactionRecord> get allRecords =>
      _transactions.map((t) => t.toRecord()).toList();

  // ---------------------------------------------------------------------------
  // 月度预算
  // ---------------------------------------------------------------------------

  /// 保存月度总预算（[amount] 传 zero 视为删除预算）。
  Future<void> saveMonthlyBudget(Decimal amount) async {
    final rows = await _db!.query(
      'budget',
      where: 'category_key IS NULL',
      limit: 1,
    );
    if (rows.isEmpty) {
      await _db!.insert('budget', {
        'category_key': null,
        'amount': amount.toString(),
      });
    } else {
      final id = rows.first['id'] as int;
      await _db!.update(
        'budget',
        {'amount': amount.toString()},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await _loadBudget();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 账户 CRUD
  // ---------------------------------------------------------------------------

  /// 新增账户。返回新行的 id。
  Future<int> addAccount({required String name, String currencyCode = 'CNY'}) async {
    final id = await _db!.insert('accounts', {
      'name': name,
      'currency_code': currencyCode,
    });
    await _loadAccounts();
    notifyListeners();
    return id;
  }

  /// 修改账户名（只改名字，货币码暂不支持改动）。
  Future<void> renameAccount(int id, String newName) async {
    await _db!.update(
      'accounts',
      {'name': newName},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _loadAccounts();
    notifyListeners();
  }

  /// 删除账户。关联交易不级联删除（外键此处未开启），保持历史记录完整。
  Future<void> deleteAccount(int id) async {
    await _db!.delete('accounts', where: 'id = ?', whereArgs: [id]);
    await _loadAccounts();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 分类 CRUD
  // ---------------------------------------------------------------------------

  /// 新增自定义分类。[key] 建议用 UUID 或时间戳字符串保证唯一性。
  Future<int> addCategory({
    required String key,
    required String nameZh,
    required String nameEn,
    required TransactionKind kind,
  }) async {
    final id = await _db!.insert('categories', {
      'key': key,
      'name_zh': nameZh,
      'name_en': nameEn,
      'kind': kind.toJson(),
    });
    await _loadCategories();
    notifyListeners();
    return id;
  }

  /// 修改分类名称（中英文同时改，英文传空则维持原值）。
  Future<void> renameCategory(int id, {required String nameZh, String? nameEn}) async {
    final updates = <String, Object?>{'name_zh': nameZh};
    if (nameEn != null) updates['name_en'] = nameEn;
    await _db!.update('categories', updates, where: 'id = ?', whereArgs: [id]);
    await _loadCategories();
    notifyListeners();
  }

  /// 删除分类（关联交易的 category_id 由于外键未开启不会级联删除）。
  Future<void> deleteCategory(int id) async {
    await _db!.delete('categories', where: 'id = ?', whereArgs: [id]);
    await _loadCategories();
    notifyListeners();
  }
}
