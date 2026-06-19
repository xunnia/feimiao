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

/// 账本实体（多账本）。
class BookEntity {
  final int id;
  final String name;
  final String icon; // emoji 或图标标记

  const BookEntity({required this.id, required this.name, this.icon = '📒'});

  factory BookEntity.fromMap(Map<String, Object?> m) => BookEntity(
        id: m['id'] as int,
        name: m['name'] as String,
        icon: m['icon'] as String? ?? '📒',
      );
}

/// 分类实体。
class CategoryEntity {
  final int id;
  final String key;
  final String nameZh;
  final String nameEn;
  final String kindRaw;

  /// 所属大类 id；null 表示自身就是大类（顶级）。
  final int? parentId;

  TransactionKind get kind => TransactionKind.fromJson(kindRaw);
  bool get isTopLevel => parentId == null;

  const CategoryEntity({
    required this.id,
    required this.key,
    required this.nameZh,
    required this.nameEn,
    required this.kindRaw,
    this.parentId,
  });

  String localizedName(String languageCode) =>
      languageCode.toLowerCase().startsWith('zh') ? nameZh : nameEn;

  Map<String, Object?> toMap() => {
        'id': id == 0 ? null : id,
        'key': key,
        'name_zh': nameZh,
        'name_en': nameEn,
        'kind': kindRaw,
        'parent_id': parentId,
      };

  factory CategoryEntity.fromMap(Map<String, Object?> m) => CategoryEntity(
        id: m['id'] as int,
        key: m['key'] as String,
        nameZh: m['name_zh'] as String,
        nameEn: m['name_en'] as String,
        kindRaw: m['kind'] as String,
        parentId: m['parent_id'] as int?,
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
  final String tagsRaw;        // 逗号分隔的标签 id 串，如 "1,3,5"
  final bool reimbursable;     // 待报销标记

  Decimal get amount => Decimal.parse(amountStr);
  DateTime get date => DateTime.fromMillisecondsSinceEpoch(dateMs);
  TransactionKind get txKind => TransactionKind.fromJson(kind);

  /// 解析出标签 id 列表（空串返回空列表）。
  List<int> get tagIds => tagsRaw.isEmpty
      ? const []
      : tagsRaw
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .toList();

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
    this.tagsRaw = '',
    this.reimbursable = false,
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
        tagsRaw: m['tags'] as String? ?? '',
        reimbursable: ((m['reimbursable'] as int?) ?? 0) == 1,
      );
}

/// CSV 导入用的一条交易草稿（id 由数据库分配）。
class TransactionDraft {
  final TransactionKind kind;
  final Decimal amount;
  final int? categoryId;
  final int accountId;
  final String note;
  final DateTime date;
  final List<int> tagIds;

  const TransactionDraft({
    required this.kind,
    required this.amount,
    this.categoryId,
    required this.accountId,
    this.note = '',
    required this.date,
    this.tagIds = const [],
  });
}

/// 存钱目标实体。
class SavingsGoalEntity {
  final int id;
  final String name;
  final String emoji;
  final String targetStr; // 目标金额（Decimal 字符串）
  final String savedStr;  // 已存金额（Decimal 字符串）
  final int createdMs;

  Decimal get target => Decimal.parse(targetStr);
  Decimal get saved => Decimal.parse(savedStr);

  /// 完成比例 0~1（目标为 0 时返回 0）。
  double get progress {
    final t = target;
    if (t <= Decimal.zero) return 0;
    final r = (saved / t).toDouble();
    return r.clamp(0.0, 1.0);
  }

  bool get isDone => saved >= target && target > Decimal.zero;

  const SavingsGoalEntity({
    required this.id,
    required this.name,
    this.emoji = '🐷',
    required this.targetStr,
    this.savedStr = '0',
    this.createdMs = 0,
  });

  factory SavingsGoalEntity.fromMap(Map<String, Object?> m) =>
      SavingsGoalEntity(
        id: m['id'] as int,
        name: m['name'] as String,
        emoji: m['emoji'] as String? ?? '🐷',
        targetStr: m['target_amount'] as String? ?? '0',
        savedStr: m['saved_amount'] as String? ?? '0',
        createdMs: m['created_ms'] as int? ?? 0,
      );
}

/// 标签实体。
class TagEntity {
  final int id;
  final String name;
  final int colorValue; // Color.value（ARGB int）

  const TagEntity({
    required this.id,
    required this.name,
    required this.colorValue,
  });

  factory TagEntity.fromMap(Map<String, Object?> m) => TagEntity(
        id: m['id'] as int,
        name: m['name'] as String,
        colorValue: m['color'] as int? ?? 0xFF7D8B9B,
      );
}

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

/// 本地 SQLite 数据仓库，暴露给 UI 层的状态管理入口。
///
/// 继承 [ChangeNotifier]，UI 通过 [provider] 订阅变化。
class AppRepository extends ChangeNotifier {
  static const _dbVersion = 7;
  static const _dbName = 'qingji.db';

  Database? _db;

  // 内存缓存
  final List<BookEntity> _books = [];
  final List<AccountEntity> _accounts = [];
  final List<CategoryEntity> _categories = [];
  final List<TransactionEntity> _transactions = [];
  final List<SavingsGoalEntity> _savingsGoals = [];
  final List<TagEntity> _tags = [];

  /// 当前账本 id（0 = 未初始化，init 后必为有效值）。
  int _currentBookId = 0;

  /// 月度总预算（null = 未设置）。
  Decimal? _monthlyBudget;

  /// DeepSeek API Key（null = 未配置）。
  String? _deepSeekApiKey;

  List<BookEntity> get books => List.unmodifiable(_books);
  List<AccountEntity> get accounts => List.unmodifiable(_accounts);
  List<CategoryEntity> get categories => List.unmodifiable(_categories);
  List<TransactionEntity> get transactions => List.unmodifiable(_transactions);
  List<SavingsGoalEntity> get savingsGoals => List.unmodifiable(_savingsGoals);
  List<TagEntity> get tags => List.unmodifiable(_tags);

  /// 按 id 查标签名（找不到返回 null）。
  String? tagName(int id) {
    for (final t in _tags) {
      if (t.id == id) return t.name;
    }
    return null;
  }

  /// 当前账本 id。
  int get currentBookId => _currentBookId;

  /// 当前账本实体（找不到返回 null）。
  BookEntity? get currentBook {
    for (final b in _books) {
      if (b.id == _currentBookId) return b;
    }
    return null;
  }

  /// 当前月度预算，null 代表未设置。
  Decimal? get monthlyBudget => _monthlyBudget;

  /// DeepSeek API Key，null 代表未配置。
  String? get deepSeekApiKey => _deepSeekApiKey;

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
    await _ensureDefaultBook();
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
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        key       TEXT NOT NULL UNIQUE,
        name_zh   TEXT NOT NULL,
        name_en   TEXT NOT NULL,
        kind      TEXT NOT NULL,
        parent_id INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE books (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        name       TEXT NOT NULL,
        icon       TEXT NOT NULL DEFAULT '📒',
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_ms INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.insert('books', {
      'name': '总账本',
      'icon': '📒',
      'sort_order': 0,
      'created_ms': DateTime.now().millisecondsSinceEpoch,
    });

    await db.execute('''
      CREATE TABLE transactions (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id         INTEGER,
        kind            TEXT NOT NULL,
        amount          TEXT NOT NULL,
        currency_code   TEXT NOT NULL DEFAULT 'CNY',
        category_id     INTEGER REFERENCES categories(id),
        account_id      INTEGER REFERENCES accounts(id),
        to_account_id   INTEGER REFERENCES accounts(id),
        note            TEXT NOT NULL DEFAULT '',
        date_ms         INTEGER NOT NULL,
        tags            TEXT NOT NULL DEFAULT '',
        reimbursable    INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE savings_goals (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        name          TEXT NOT NULL,
        emoji         TEXT NOT NULL DEFAULT '🐷',
        target_amount TEXT NOT NULL DEFAULT '0',
        saved_amount  TEXT NOT NULL DEFAULT '0',
        created_ms    INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE tags (
        id    INTEGER PRIMARY KEY AUTOINCREMENT,
        name  TEXT NOT NULL,
        color INTEGER NOT NULL DEFAULT 4286351771
      )
    ''');

    await db.execute('''
      CREATE TABLE budget (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        category_key TEXT,
        amount       TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  /// 数据库升级：
  ///   v1→v2 在 budget 表加 category_key 列；
  ///   v2→v3 新建 app_settings 表（用于存储 API Key 等键值对）；
  ///   v3→v4 多账本；v4→v5 存钱目标+标签；v5→v6 二级分类；
  ///   v6→v7 交易加 reimbursable（待报销）列。
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v1 的 budget 表没有 category_key 列，添加之。
      await db.execute(
          'ALTER TABLE budget ADD COLUMN category_key TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_settings (
          key   TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 4) {
      // 多账本：建 books 表 + 默认「总账本」，给 transactions 加 book_id 并迁入总账本
      await db.execute('''
        CREATE TABLE IF NOT EXISTS books (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          name       TEXT NOT NULL,
          icon       TEXT NOT NULL DEFAULT '📒',
          sort_order INTEGER NOT NULL DEFAULT 0,
          created_ms INTEGER NOT NULL DEFAULT 0
        )
      ''');
      final defaultBookId = await db.insert('books', {
        'name': '总账本',
        'icon': '📒',
        'sort_order': 0,
        'created_ms': DateTime.now().millisecondsSinceEpoch,
      });
      try {
        await db.execute('ALTER TABLE transactions ADD COLUMN book_id INTEGER');
      } catch (_) {
        // 列已存在则忽略
      }
      await db.execute(
          'UPDATE transactions SET book_id = $defaultBookId WHERE book_id IS NULL');
    }
    if (oldVersion < 5) {
      // 存钱目标 + 标签：建两张新表，给 transactions 加 tags 列
      await db.execute('''
        CREATE TABLE IF NOT EXISTS savings_goals (
          id            INTEGER PRIMARY KEY AUTOINCREMENT,
          name          TEXT NOT NULL,
          emoji         TEXT NOT NULL DEFAULT '🐷',
          target_amount TEXT NOT NULL DEFAULT '0',
          saved_amount  TEXT NOT NULL DEFAULT '0',
          created_ms    INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS tags (
          id    INTEGER PRIMARY KEY AUTOINCREMENT,
          name  TEXT NOT NULL,
          color INTEGER NOT NULL DEFAULT 4286351771
        )
      ''');
      try {
        await db.execute(
            "ALTER TABLE transactions ADD COLUMN tags TEXT NOT NULL DEFAULT ''");
      } catch (_) {
        // 列已存在则忽略
      }
    }
    if (oldVersion < 6) {
      // 二级分类：加 parent_id 列，并把分类升级成两级树。
      // 纯增量 + 幂等：只新增/改名/挂父级，绝不删分类、绝不动 transactions。
      // 整体 try-catch 兜底：即便出错也不致 DB 打不开（最坏子类不全，账目无损）。
      try {
        try {
          await db.execute(
              'ALTER TABLE categories ADD COLUMN parent_id INTEGER');
        } catch (_) {
          // 列已存在则忽略
        }
        await _applyCategoryTree(db);
      } catch (_) {
        // 迁移失败也不阻断 App 启动
      }
    }
    if (oldVersion < 7) {
      // 待报销：给 transactions 加 reimbursable 列。纯增量，绝不动已有账目数据。
      try {
        await db.execute(
            'ALTER TABLE transactions ADD COLUMN reimbursable INTEGER NOT NULL DEFAULT 0');
      } catch (_) {
        // 列已存在则忽略
      }
    }
  }

  /// 幂等地把两级分类树写入/更新到 categories 表（建库与升级共用）。
  /// 按 key 定位：缺则插入、有则回填名称与 parent_id；从不删除、从不改 id。
  Future<void> _applyCategoryTree(DatabaseExecutor db) async {
    // 1) 确保每个分类存在（key 唯一，冲突忽略）
    for (final s in CategorySeed.all) {
      await db.insert(
        'categories',
        {
          'key': s.key,
          'name_zh': s.nameZh,
          'name_en': s.nameEn,
          'kind': s.kind.toJson(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    // 2) 回填名称 + parent_id（按 parentKey 查父级 id）
    for (final s in CategorySeed.all) {
      int? parentId;
      if (s.parentKey != null) {
        parentId = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT id FROM categories WHERE key = ? LIMIT 1', [s.parentKey]));
      }
      await db.update(
        'categories',
        {
          'name_zh': s.nameZh,
          'name_en': s.nameEn,
          'parent_id': parentId,
        },
        where: 'key = ?',
        whereArgs: [s.key],
      );
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

    // 默认分类种子（两级树）
    await _applyCategoryTree(db);
  }

  Future<void> _loadAll() async {
    await _loadBooks();
    await _loadCurrentBook();
    await Future.wait([
      _loadAccounts(),
      _loadCategories(),
      _loadTransactions(),
      _loadBudget(),
      _loadApiKey(),
      _loadSavingsGoals(),
      _loadTags(),
    ]);
    notifyListeners();
  }

  Future<void> _loadSavingsGoals() async {
    final rows =
        await _db!.query('savings_goals', orderBy: 'created_ms ASC, id ASC');
    _savingsGoals
      ..clear()
      ..addAll(rows.map(SavingsGoalEntity.fromMap));
  }

  Future<void> _loadTags() async {
    final rows = await _db!.query('tags', orderBy: 'id ASC');
    _tags
      ..clear()
      ..addAll(rows.map(TagEntity.fromMap));
  }

  Future<void> _loadBooks() async {
    final rows = await _db!.query('books', orderBy: 'sort_order ASC, id ASC');
    _books
      ..clear()
      ..addAll(rows.map(BookEntity.fromMap));
  }

  /// 确保至少有一个账本（默认「总账本」）。
  Future<void> _ensureDefaultBook() async {
    final count =
        Sqflite.firstIntValue(await _db!.rawQuery('SELECT COUNT(*) FROM books')) ?? 0;
    if (count == 0) {
      await _db!.insert('books', {
        'name': '总账本',
        'icon': '📒',
        'sort_order': 0,
        'created_ms': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  /// 读取当前账本 id（无效则回退到第一个账本）。
  Future<void> _loadCurrentBook() async {
    final rows = await _db!.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['current_book_id'],
      limit: 1,
    );
    final saved = rows.isEmpty
        ? null
        : int.tryParse((rows.first['value'] as String?) ?? '');
    final valid = saved != null && _books.any((b) => b.id == saved);
    _currentBookId =
        valid ? saved! : (_books.isNotEmpty ? _books.first.id : 1);
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

  /// 从 app_settings 读取 DeepSeek API Key。
  Future<void> _loadApiKey() async {
    final rows = await _db!.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['deepseek_api_key'],
      limit: 1,
    );
    _deepSeekApiKey =
        rows.isEmpty ? null : rows.first['value'] as String?;
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
        t.date_ms,
        t.tags,
        t.reimbursable
      FROM transactions t
      LEFT JOIN categories c  ON c.id = t.category_id
      LEFT JOIN accounts   a  ON a.id = t.account_id
      LEFT JOIN accounts   ta ON ta.id = t.to_account_id
      WHERE t.book_id = ?
      ORDER BY t.date_ms DESC
    ''', [_currentBookId]);
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
    List<int> tagIds = const [],
    bool reimbursable = false,
  }) async {
    await _db!.insert('transactions', {
      'book_id': _currentBookId,
      'kind': kind.toJson(),
      'amount': amount.toString(),
      'currency_code': currencyCode,
      'category_id': categoryId,
      'account_id': accountId,
      'to_account_id': toAccountId,
      'note': note,
      'date_ms': date.millisecondsSinceEpoch,
      'tags': tagIds.join(','),
      'reimbursable': reimbursable ? 1 : 0,
    });
    await _loadTransactions();
    notifyListeners();
  }

  /// 编辑一笔已有交易（按数据库 id 覆盖更新）。
  Future<void> updateTransaction({
    required int id,
    required TransactionKind kind,
    required Decimal amount,
    int? categoryId,
    required int accountId,
    int? toAccountId,
    String note = '',
    required DateTime date,
    List<int> tagIds = const [],
    bool reimbursable = false,
  }) async {
    await _db!.update(
      'transactions',
      {
        'kind': kind.toJson(),
        'amount': amount.toString(),
        'category_id': categoryId,
        'account_id': accountId,
        'to_account_id': toAccountId,
        'note': note,
        'date_ms': date.millisecondsSinceEpoch,
        'tags': tagIds.join(','),
        'reimbursable': reimbursable ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _loadTransactions();
    notifyListeners();
  }

  /// 批量导入交易（CSV 导入用，一次性写入 + 单次刷新）。返回成功条数。
  Future<int> importTransactions(List<TransactionDraft> drafts) async {
    if (drafts.isEmpty) return 0;
    final batch = _db!.batch();
    for (final d in drafts) {
      batch.insert('transactions', {
        'book_id': _currentBookId,
        'kind': d.kind.toJson(),
        'amount': d.amount.toString(),
        'currency_code': 'CNY',
        'category_id': d.categoryId,
        'account_id': d.accountId,
        'to_account_id': null,
        'note': d.note,
        'date_ms': d.date.millisecondsSinceEpoch,
        'tags': d.tagIds.join(','),
      });
    }
    await batch.commit(noResult: true);
    await _loadTransactions();
    notifyListeners();
    return drafts.length;
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

  /// 按使用频次排序的分类：常用的冒到前排，同频次保持原种子序。
  /// 用于记账分类格 —— 减少翻找，默认也预选最常用的那个。
  /// 仅返回顶级大类，按使用频次排序（子类用量计入其父级）。
  List<CategoryEntity> categoriesForKindRanked(TransactionKind kind) {
    final all = categoriesForKind(kind);
    final tops = all.where((c) => c.isTopLevel).toList();
    final counts = <int, int>{};
    for (final t in _transactions) {
      final cid = t.categoryId;
      if (cid == null || t.txKind != kind) continue;
      counts[cid] = (counts[cid] ?? 0) + 1;
    }
    // 子类用量滚动到父级，让常用大类冒前
    final rolled = <int, int>{};
    for (final c in all) {
      final n = counts[c.id] ?? 0;
      if (n == 0) continue;
      final top = c.isTopLevel ? c.id : (c.parentId ?? c.id);
      rolled[top] = (rolled[top] ?? 0) + n;
    }
    final indexed = [for (var i = 0; i < tops.length; i++) (i, tops[i])];
    indexed.sort((a, b) {
      final ca = rolled[a.$2.id] ?? 0;
      final cb = rolled[b.$2.id] ?? 0;
      return ca != cb ? cb.compareTo(ca) : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  /// 某大类下的子类（按加载顺序）。
  List<CategoryEntity> childrenOf(int parentId) =>
      _categories.where((c) => c.parentId == parentId).toList();

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
  // AI 设置
  // ---------------------------------------------------------------------------

  /// 保存 DeepSeek API Key（传空字符串视为删除）。
  Future<void> saveApiKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await _db!.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['deepseek_api_key'],
      );
      _deepSeekApiKey = null;
    } else {
      await _db!.insert(
        'app_settings',
        {'key': 'deepseek_api_key', 'value': trimmed},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      _deepSeekApiKey = trimmed;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 账本（多账本）
  // ---------------------------------------------------------------------------

  /// 切换当前账本（持久化并重载该账本交易）。
  Future<void> switchBook(int bookId) async {
    if (bookId == _currentBookId) return;
    if (!_books.any((b) => b.id == bookId)) return;
    _currentBookId = bookId;
    await _db!.insert(
      'app_settings',
      {'key': 'current_book_id', 'value': bookId.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _loadTransactions();
    notifyListeners();
  }

  /// 新建账本，返回新行 id。
  Future<int> addBook({required String name, String icon = '📒'}) async {
    final id = await _db!.insert('books', {
      'name': name,
      'icon': icon,
      'sort_order': _books.length,
      'created_ms': DateTime.now().millisecondsSinceEpoch,
    });
    await _loadBooks();
    notifyListeners();
    return id;
  }

  /// 改账本名/图标。
  Future<void> renameBook(int id, {required String name, String? icon}) async {
    final updates = <String, Object?>{'name': name};
    if (icon != null) updates['icon'] = icon;
    await _db!.update('books', updates, where: 'id = ?', whereArgs: [id]);
    await _loadBooks();
    notifyListeners();
  }

  /// 删除账本（连同其下交易）。不允许删到一个不剩；删的是当前账本则切到剩余第一个。
  Future<void> deleteBook(int id) async {
    if (_books.length <= 1) return; // 至少保留一个账本
    await _db!.delete('transactions', where: 'book_id = ?', whereArgs: [id]);
    await _db!.delete('books', where: 'id = ?', whereArgs: [id]);
    await _loadBooks();
    if (_currentBookId == id) {
      _currentBookId = _books.isNotEmpty ? _books.first.id : 1;
      await _db!.insert(
        'app_settings',
        {'key': 'current_book_id', 'value': _currentBookId.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await _loadTransactions();
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

  // ---------------------------------------------------------------------------
  // 存钱目标 CRUD
  // ---------------------------------------------------------------------------

  /// 新建存钱目标，返回新行 id。
  Future<int> addSavingsGoal({
    required String name,
    required Decimal target,
    String emoji = '🐷',
    Decimal? initialSaved,
  }) async {
    final id = await _db!.insert('savings_goals', {
      'name': name,
      'emoji': emoji,
      'target_amount': target.toString(),
      'saved_amount': (initialSaved ?? Decimal.zero).toString(),
      'created_ms': DateTime.now().millisecondsSinceEpoch,
    });
    await _loadSavingsGoals();
    notifyListeners();
    return id;
  }

  /// 编辑目标的名称/图标/目标金额（已存金额不动）。
  Future<void> updateSavingsGoal(
    int id, {
    required String name,
    required Decimal target,
    String? emoji,
  }) async {
    final updates = <String, Object?>{
      'name': name,
      'target_amount': target.toString(),
    };
    if (emoji != null) updates['emoji'] = emoji;
    await _db!.update('savings_goals', updates, where: 'id = ?', whereArgs: [id]);
    await _loadSavingsGoals();
    notifyListeners();
  }

  /// 删除存钱目标。
  Future<void> deleteSavingsGoal(int id) async {
    await _db!.delete('savings_goals', where: 'id = ?', whereArgs: [id]);
    await _loadSavingsGoals();
    notifyListeners();
  }

  /// 给目标存入 [delta]（正数存入、负数取出），已存金额夹在 0 与目标无上限之间不为负。
  Future<void> adjustSavingsGoal(int id, Decimal delta) async {
    final goal = _savingsGoals.where((g) => g.id == id).firstOrNull;
    if (goal == null) return;
    var next = goal.saved + delta;
    if (next < Decimal.zero) next = Decimal.zero;
    await _db!.update(
      'savings_goals',
      {'saved_amount': next.toString()},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _loadSavingsGoals();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 标签 CRUD
  // ---------------------------------------------------------------------------

  /// 新建标签，返回新行 id。
  Future<int> addTag({required String name, required int colorValue}) async {
    final id = await _db!.insert('tags', {'name': name, 'color': colorValue});
    await _loadTags();
    notifyListeners();
    return id;
  }

  /// 改标签名/颜色。
  Future<void> updateTag(int id, {required String name, int? colorValue}) async {
    final updates = <String, Object?>{'name': name};
    if (colorValue != null) updates['color'] = colorValue;
    await _db!.update('tags', updates, where: 'id = ?', whereArgs: [id]);
    await _loadTags();
    notifyListeners();
  }

  /// 删除标签：同时把所有交易上引用它的 id 剔除（避免悬空引用）。
  Future<void> deleteTag(int id) async {
    await _db!.delete('tags', where: 'id = ?', whereArgs: [id]);
    // 扫描含该标签的交易，去掉这个 id 后回写
    final rows = await _db!.rawQuery(
      "SELECT id, tags FROM transactions WHERE tags LIKE ?",
      ['%$id%'],
    );
    for (final r in rows) {
      final raw = (r['tags'] as String?) ?? '';
      if (raw.isEmpty) continue;
      final kept = raw
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .where((tid) => tid != id)
          .join(',');
      if (kept != raw) {
        await _db!.update('transactions', {'tags': kept},
            where: 'id = ?', whereArgs: [r['id']]);
      }
    }
    await _loadTags();
    await _loadTransactions();
    notifyListeners();
  }
}
