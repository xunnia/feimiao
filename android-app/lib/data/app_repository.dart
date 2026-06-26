import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/models/category_seed.dart';
import '../core/models/recurring_rule.dart';
import '../core/models/transaction_kind.dart';
import '../core/models/transaction_record.dart';

// ---------------------------------------------------------------------------
// 领域实体
// ---------------------------------------------------------------------------

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

class BookEntity {
  final int id;
  final String name;
  final String icon;

  const BookEntity({required this.id, required this.name, this.icon = '📒'});

  factory BookEntity.fromMap(Map<String, Object?> m) => BookEntity(
        id: m['id'] as int,
        name: m['name'] as String,
        icon: m['icon'] as String? ?? '📒',
      );
}

class CategoryEntity {
  final int id;
  final String key;
  final String nameZh;
  final String nameEn;
  final String kindRaw;
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

class TransactionEntity {
  final int id;
  final String kind;
  final String amountStr;
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
  final int dateMs;
  final String tagsRaw;
  final bool reimbursable;
  final String imagePath;

  Decimal get amount => Decimal.parse(amountStr);
  DateTime get date => DateTime.fromMillisecondsSinceEpoch(dateMs);
  TransactionKind get txKind => TransactionKind.fromJson(kind);

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
    this.imagePath = '',
  });

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
        imagePath: m['image_path'] as String? ?? '',
      );
}

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

class SavingsGoalEntity {
  final int id;
  final String name;
  final String emoji;
  final String targetStr;
  final String savedStr;
  final int createdMs;

  Decimal get target => Decimal.parse(targetStr);
  Decimal get saved => Decimal.parse(savedStr);

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

class TagEntity {
  final int id;
  final String name;
  final int colorValue;

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

class AppRepository extends ChangeNotifier {
  static const _dbVersion = 11;
  static const _dbName = 'qingji.db';

  Database? _db;

  final List<BookEntity> _books = [];
  final List<AccountEntity> _accounts = [];
  final List<CategoryEntity> _categories = [];
  final List<TransactionEntity> _transactions = [];
  final List<SavingsGoalEntity> _savingsGoals = [];
  final List<TagEntity> _tags = [];

  int _currentBookId = 0;
  Decimal? _monthlyBudget;
  final Map<String, Decimal> _categoryBudgets = {}; // 分类 key -> 月预算
  String? _deepSeekApiKey;

  /// 记账模式偏好：true=AI 记账，false=手动记账（持久化）。
  bool _recordAiMode = false;
  int _chatRetentionDays = 30;

  /// 用户纠正记忆：(备注短语, 收支, 分类key)。AI 记账时按此覆盖模型的猜测。
  final List<({String phrase, TransactionKind kind, String key})> _catMemory =
      [];

  /// 周期记账规则(全部账本)。
  final List<RecurringRule> _recurringRules = [];

  List<BookEntity> get books => List.unmodifiable(_books);
  List<AccountEntity> get accounts => List.unmodifiable(_accounts);
  List<CategoryEntity> get categories => List.unmodifiable(_categories);
  List<TransactionEntity> get transactions => List.unmodifiable(_transactions);
  List<SavingsGoalEntity> get savingsGoals => List.unmodifiable(_savingsGoals);
  List<TagEntity> get tags => List.unmodifiable(_tags);

  String? tagName(int id) {
    for (final t in _tags) {
      if (t.id == id) return t.name;
    }
    return null;
  }

  int get currentBookId => _currentBookId;

  BookEntity? get currentBook {
    for (final b in _books) {
      if (b.id == _currentBookId) return b;
    }
    return null;
  }

  Decimal? get monthlyBudget => _monthlyBudget;

  /// 全部分类预算（key -> 月预算）。
  Map<String, Decimal> get categoryBudgets => Map.unmodifiable(_categoryBudgets);

  /// 某分类 key 的月预算（未设返回 null）。
  Decimal? categoryBudgetFor(String key) => _categoryBudgets[key];

  String? get deepSeekApiKey => _deepSeekApiKey;

  bool get recordAiMode => _recordAiMode;

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
    // 启动时补记到期的周期账目,再刷新一次交易。
    await _materializeRecurring();
    await _loadTransactions();
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
        reimbursable    INTEGER NOT NULL DEFAULT 0,
        image_path      TEXT NOT NULL DEFAULT ''
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

    await db.execute('''
      CREATE TABLE chat_messages (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        role       TEXT NOT NULL,
        text       TEXT NOT NULL DEFAULT '',
        question   TEXT NOT NULL DEFAULT '',
        created_ms INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE category_memory (
        phrase       TEXT NOT NULL,
        kind         TEXT NOT NULL,
        category_key TEXT NOT NULL,
        updated_ms   INTEGER NOT NULL,
        PRIMARY KEY (phrase, kind)
      )
    ''');

    await db.execute('''
      CREATE TABLE recurring_rules (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id     INTEGER,
        kind        TEXT NOT NULL,
        amount      TEXT NOT NULL,
        category_id INTEGER,
        account_id  INTEGER,
        note        TEXT NOT NULL DEFAULT '',
        period      TEXT NOT NULL,
        next_due_ms INTEGER NOT NULL,
        enabled     INTEGER NOT NULL DEFAULT 1,
        created_ms  INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE budget ADD COLUMN category_key TEXT');
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
      } catch (_) {}
      await db.execute(
          'UPDATE transactions SET book_id = $defaultBookId WHERE book_id IS NULL');
    }
    if (oldVersion < 5) {
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
      } catch (_) {}
    }
    if (oldVersion < 6) {
      try {
        try {
          await db.execute(
              'ALTER TABLE categories ADD COLUMN parent_id INTEGER');
        } catch (_) {}
        await _applyCategoryTree(db);
      } catch (_) {}
    }
    if (oldVersion < 7) {
      try {
        await db.execute(
            'ALTER TABLE transactions ADD COLUMN reimbursable INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
    }
    if (oldVersion < 8) {
      try {
        await db.execute(
            "ALTER TABLE transactions ADD COLUMN image_path TEXT NOT NULL DEFAULT ''");
      } catch (_) {}
    }
    if (oldVersion < 9) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS chat_messages (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          role       TEXT NOT NULL,
          text       TEXT NOT NULL DEFAULT '',
          question   TEXT NOT NULL DEFAULT '',
          created_ms INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 10) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS category_memory (
          phrase       TEXT NOT NULL,
          kind         TEXT NOT NULL,
          category_key TEXT NOT NULL,
          updated_ms   INTEGER NOT NULL,
          PRIMARY KEY (phrase, kind)
        )
      ''');
    }
    if (oldVersion < 11) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS recurring_rules (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          book_id     INTEGER,
          kind        TEXT NOT NULL,
          amount      TEXT NOT NULL,
          category_id INTEGER,
          account_id  INTEGER,
          note        TEXT NOT NULL DEFAULT '',
          period      TEXT NOT NULL,
          next_due_ms INTEGER NOT NULL,
          enabled     INTEGER NOT NULL DEFAULT 1,
          created_ms  INTEGER NOT NULL DEFAULT 0
        )
      ''');
    }
  }

  Future<void> _applyCategoryTree(DatabaseExecutor db) async {
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

  Future<void> _seedIfNeeded() async {
    final db = _db!;
    final accountCount =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM accounts')) ?? 0;
    if (accountCount > 0) return;

    await db.insert('accounts', {'name': '现金', 'currency_code': 'CNY'});
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
      _loadCategoryBudgets(),
      _loadApiKey(),
      _loadRecordMode(),
      _loadChatRetention(),
      _loadCategoryMemory(),
      _loadRecurringRules(),
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

  /// 读取所有分类预算（budget 表里 category_key 非空的行）。
  Future<void> _loadCategoryBudgets() async {
    final rows = await _db!.query('budget', where: 'category_key IS NOT NULL');
    _categoryBudgets.clear();
    for (final r in rows) {
      final k = r['category_key'] as String?;
      if (k == null || k.isEmpty) continue;
      final v = Decimal.tryParse((r['amount'] as String?) ?? '');
      if (v != null && v > Decimal.zero) _categoryBudgets[k] = v;
    }
  }

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

  Future<void> _loadRecordMode() async {
    final rows = await _db!.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['record_ai_mode'],
      limit: 1,
    );
    _recordAiMode = rows.isNotEmpty && (rows.first['value'] as String?) == '1';
  }

  /// 记住记账模式（AI / 手动），下次启动沿用。
  Future<void> setRecordAiMode(bool ai) async {
    if (_recordAiMode == ai) return;
    _recordAiMode = ai;
    await _db!.insert(
      'app_settings',
      {'key': 'record_ai_mode', 'value': ai ? '1' : '0'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // AI 对话历史（跨重启持久化 + 按「保存时长」自动清理）
  // ---------------------------------------------------------------------------

  /// 对话保存天数（30 = 一个月，180 = 半年）。
  int get chatRetentionDays => _chatRetentionDays;

  Future<void> _loadChatRetention() async {
    final rows = await _db!.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['chat_retention_days'],
      limit: 1,
    );
    final v = rows.isEmpty
        ? null
        : int.tryParse((rows.first['value'] as String?) ?? '');
    _chatRetentionDays = (v != null && v > 0) ? v : 30;
  }

  /// 设置对话保存时长（天）。设置后立即清理超期对话。
  Future<void> setChatRetentionDays(int days) async {
    if (days <= 0) return;
    _chatRetentionDays = days;
    await _db!.insert(
      'app_settings',
      {'key': 'chat_retention_days', 'value': '$days'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _pruneChatMessages();
    notifyListeners();
  }

  /// 删除超过保存时长的对话。
  Future<void> _pruneChatMessages() async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: _chatRetentionDays))
        .millisecondsSinceEpoch;
    await _db!
        .delete('chat_messages', where: 'created_ms < ?', whereArgs: [cutoff]);
  }

  /// 读取保存的对话（先清理超期，再按时间正序返回）。
  Future<List<Map<String, Object?>>> loadChatMessages() async {
    await _pruneChatMessages();
    return _db!.query('chat_messages', orderBy: 'created_ms ASC, id ASC');
  }

  /// 追加一条对话消息。
  Future<void> addChatMessage({
    required String role,
    String text = '',
    String question = '',
  }) async {
    await _db!.insert('chat_messages', {
      'role': role,
      'text': text,
      'question': question,
      'created_ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 清空全部对话。
  Future<void> clearChatMessages() async {
    await _db!.delete('chat_messages');
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // AI 学习用户纠正：改了某笔分类就记住，下次同备注/商户自动套用
  // ---------------------------------------------------------------------------

  Future<void> _loadCategoryMemory() async {
    final rows = await _db!.query('category_memory');
    _catMemory
      ..clear()
      ..addAll(rows.map((r) => (
            phrase: r['phrase'] as String,
            kind: TransactionKind.fromJson(r['kind'] as String),
            key: r['category_key'] as String,
          )));
  }

  /// 记住一条「备注短语 → 分类」的纠正（编辑里改了分类时调用）。
  Future<void> learnCategory({
    required String phrase,
    required TransactionKind kind,
    required String categoryKey,
  }) async {
    final p = phrase.trim();
    if (p.length < 2 || categoryKey.isEmpty) return;
    await _db!.insert(
      'category_memory',
      {
        'phrase': p,
        'kind': kind.toJson(),
        'category_key': categoryKey,
        'updated_ms': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _catMemory.removeWhere((m) => m.phrase == p && m.kind == kind);
    _catMemory.add((phrase: p, kind: kind, key: categoryKey));
  }

  /// 按备注召回学过的分类 key：取被备注包含的「最长」短语对应的分类；无则 null。
  String? recallCategoryKey(String note, TransactionKind kind) {
    final n = note.trim();
    if (n.isEmpty) return null;
    String? best;
    int bestLen = 0;
    for (final m in _catMemory) {
      if (m.kind != kind) continue;
      if (m.phrase.length > bestLen && n.contains(m.phrase)) {
        best = m.key;
        bestLen = m.phrase.length;
      }
    }
    return best;
  }

  // ---------------------------------------------------------------------------
  // 周期记账
  // ---------------------------------------------------------------------------

  /// 当前账本的周期规则(按下次到期升序)。
  List<RecurringRule> get recurringRules => _recurringRules
      .where((r) => r.bookId == _currentBookId)
      .toList()
    ..sort((a, b) => a.nextDueMs.compareTo(b.nextDueMs));

  Future<void> _loadRecurringRules() async {
    final rows = await _db!.query('recurring_rules');
    _recurringRules
      ..clear()
      ..addAll(rows.map(RecurringRule.fromMap));
  }

  Future<void> addRecurringRule({
    required TransactionKind kind,
    required Decimal amount,
    int? categoryId,
    int? accountId,
    String note = '',
    required RecurPeriod period,
    required DateTime startDate,
  }) async {
    await _db!.insert('recurring_rules', {
      'book_id': _currentBookId,
      'kind': kind.toJson(),
      'amount': amount.toString(),
      'category_id': categoryId,
      'account_id': accountId,
      'note': note,
      'period': period.toJson(),
      'next_due_ms': startDate.millisecondsSinceEpoch,
      'enabled': 1,
      'created_ms': DateTime.now().millisecondsSinceEpoch,
    });
    await _loadRecurringRules();
    await _materializeRecurring(); // 起始日若已过则立即补记
    await _loadTransactions();
    notifyListeners();
  }

  Future<void> updateRecurringRule({
    required int id,
    required TransactionKind kind,
    required Decimal amount,
    int? categoryId,
    int? accountId,
    String note = '',
    required RecurPeriod period,
    required DateTime nextDue,
  }) async {
    await _db!.update(
      'recurring_rules',
      {
        'kind': kind.toJson(),
        'amount': amount.toString(),
        'category_id': categoryId,
        'account_id': accountId,
        'note': note,
        'period': period.toJson(),
        'next_due_ms': nextDue.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _loadRecurringRules();
    notifyListeners();
  }

  Future<void> deleteRecurringRule(int id) async {
    await _db!.delete('recurring_rules', where: 'id = ?', whereArgs: [id]);
    await _loadRecurringRules();
    notifyListeners();
  }

  Future<void> setRecurringEnabled(int id, bool enabled) async {
    await _db!.update('recurring_rules', {'enabled': enabled ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
    await _loadRecurringRules();
    if (enabled) {
      await _materializeRecurring();
      await _loadTransactions();
    }
    notifyListeners();
  }

  /// 到期生成:启用规则中凡 nextDue<=今天 就补记一笔并推进 nextDue。
  /// guard 上限防止极端情况(长期没打开 App)跑飞。
  Future<void> _materializeRecurring() async {
    final now = DateTime.now();
    final cutoff =
        DateTime(now.year, now.month, now.day, 23, 59, 59).millisecondsSinceEpoch;
    final fallbackAccount = _accounts.firstOrNull?.id;
    var changed = false;
    for (final rule in List<RecurringRule>.from(_recurringRules)) {
      if (!rule.enabled) continue;
      var due = rule.nextDue;
      var guard = 0;
      while (due.millisecondsSinceEpoch <= cutoff && guard < 400) {
        await _db!.insert('transactions', {
          'book_id': rule.bookId,
          'kind': rule.kind,
          'amount': rule.amountStr,
          'currency_code': 'CNY',
          'category_id': rule.categoryId,
          'account_id': rule.accountId ?? fallbackAccount,
          'to_account_id': null,
          'note': rule.note.isEmpty ? '周期记账' : rule.note,
          'date_ms': due.millisecondsSinceEpoch,
          'tags': '',
          'reimbursable': 0,
          'image_path': '',
        });
        due = rule.recurPeriod.advance(due);
        guard++;
      }
      if (guard > 0) {
        await _db!.update('recurring_rules',
            {'next_due_ms': due.millisecondsSinceEpoch},
            where: 'id = ?', whereArgs: [rule.id]);
        changed = true;
      }
    }
    if (changed) await _loadRecurringRules();
  }

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
        t.reimbursable,
        t.image_path
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
  // 备份 / 恢复
  // ---------------------------------------------------------------------------

  Future<String> databaseFilePath() async =>
      p.join(await getDatabasesPath(), _dbName);

  Future<bool> restoreDatabaseFromFile(String srcPath) async {
    final dbPath = p.join(await getDatabasesPath(), _dbName);
    final bakPath = '$dbPath.bak';
    try {
      await _db?.close();
      _db = null;

      final cur = File(dbPath);
      if (await cur.exists()) {
        await cur.copy(bakPath);
      }
      await File(srcPath).copy(dbPath);

      _db = await openDatabase(
        dbPath,
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
      await _ensureDefaultBook();
      await _loadAll();
      return true;
    } catch (_) {
      try {
        final bak = File(bakPath);
        if (await bak.exists()) {
          await bak.copy(dbPath);
        }
        _db = await openDatabase(
          dbPath,
          version: _dbVersion,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        );
        await _loadAll();
      } catch (_) {}
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // 收据图片清理
  // ---------------------------------------------------------------------------

  void _deleteReceiptFileIfOwned(String path) {
    if (path.isEmpty || !path.contains('/receipts/')) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  Future<String> _imagePathOf(int id) async {
    final rows = await _db!.query(
      'transactions',
      columns: ['image_path'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? '' : (rows.first['image_path'] as String? ?? '');
  }

  // ---------------------------------------------------------------------------
  // 写操作
  // ---------------------------------------------------------------------------

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
    String imagePath = '',
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
      'image_path': imagePath,
    });
    await _loadTransactions();
    notifyListeners();
  }

  /// 退款冲账(方案1):在同分类/账户记一笔「负支出」,
  /// 原记录不动;统计、预算、结余因负数累加自动按净额计算。
  Future<void> refundTransaction(
      TransactionEntity original, Decimal refundAmount) async {
    if (refundAmount <= Decimal.zero) return;
    final accountId = original.accountId ?? _accounts.firstOrNull?.id;
    if (accountId == null) return;
    final note = original.note.isNotEmpty
        ? '退款 · ${original.note}'
        : (original.categoryNameZh.isNotEmpty
            ? '退款 · ${original.categoryNameZh}'
            : '退款');
    await addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.zero - refundAmount, // 负支出 = 冲账
      categoryId: original.categoryId,
      accountId: accountId,
      note: note,
      date: DateTime.now(),
    );
  }

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
    String imagePath = '',
  }) async {
    final oldPath = await _imagePathOf(id);
    if (oldPath != imagePath) _deleteReceiptFileIfOwned(oldPath);

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
        'image_path': imagePath,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _loadTransactions();
    notifyListeners();
  }

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

  Future<void> deleteTransaction(int id) async {
    final path = await _imagePathOf(id);
    _deleteReceiptFileIfOwned(path);

    await _db!.delete('transactions', where: 'id = ?', whereArgs: [id]);
    _transactions.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 查询辅助
  // ---------------------------------------------------------------------------

  List<CategoryEntity> categoriesForKind(TransactionKind kind) =>
      _categories.where((c) => c.kind == kind).toList();

  List<CategoryEntity> categoriesForKindRanked(TransactionKind kind) {
    final all = categoriesForKind(kind);
    final tops = all.where((c) => c.isTopLevel).toList();
    final counts = <int, int>{};
    for (final t in _transactions) {
      final cid = t.categoryId;
      if (cid == null || t.txKind != kind) continue;
      counts[cid] = (counts[cid] ?? 0) + 1;
    }
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

  List<CategoryEntity> childrenOf(int parentId) =>
      _categories.where((c) => c.parentId == parentId).toList();

  /// 某大类本月支出合计（含其子类）。用于分类预算进度。
  Decimal monthSpentForTopCategory(int topCategoryId, {DateTime? month}) {
    final m = month ?? DateTime.now();
    final ids = <int>{topCategoryId};
    for (final c in _categories) {
      if (c.parentId == topCategoryId) ids.add(c.id);
    }
    var sum = Decimal.zero;
    for (final t in _transactions) {
      if (t.txKind != TransactionKind.expense) continue;
      if (t.categoryId == null || !ids.contains(t.categoryId)) continue;
      if (t.date.year != m.year || t.date.month != m.month) continue;
      sum += t.amount;
    }
    return sum;
  }

  List<TransactionRecord> get allRecords =>
      _transactions.map((t) => t.toRecord()).toList();

  // ---------------------------------------------------------------------------
  // 预算（总额 + 分类）
  // ---------------------------------------------------------------------------

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

  /// 保存/更新某分类的月预算（[amount] <= 0 视为删除该分类预算）。
  Future<void> saveCategoryBudget(String categoryKey, Decimal amount) async {
    if (amount <= Decimal.zero) {
      await _db!.delete('budget',
          where: 'category_key = ?', whereArgs: [categoryKey]);
    } else {
      final rows = await _db!.query('budget',
          where: 'category_key = ?', whereArgs: [categoryKey], limit: 1);
      if (rows.isEmpty) {
        await _db!.insert('budget', {
          'category_key': categoryKey,
          'amount': amount.toString(),
        });
      } else {
        await _db!.update(
          'budget',
          {'amount': amount.toString()},
          where: 'category_key = ?',
          whereArgs: [categoryKey],
        );
      }
    }
    await _loadCategoryBudgets();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // AI 设置
  // ---------------------------------------------------------------------------

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

  Future<void> renameBook(int id, {required String name, String? icon}) async {
    final updates = <String, Object?>{'name': name};
    if (icon != null) updates['icon'] = icon;
    await _db!.update('books', updates, where: 'id = ?', whereArgs: [id]);
    await _loadBooks();
    notifyListeners();
  }

  Future<void> deleteBook(int id) async {
    if (_books.length <= 1) return;
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

  Future<int> addAccount({required String name, String currencyCode = 'CNY'}) async {
    final id = await _db!.insert('accounts', {
      'name': name,
      'currency_code': currencyCode,
    });
    await _loadAccounts();
    notifyListeners();
    return id;
  }

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

  Future<void> deleteAccount(int id) async {
    await _db!.delete('accounts', where: 'id = ?', whereArgs: [id]);
    await _loadAccounts();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 分类 CRUD
  // ---------------------------------------------------------------------------

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

  Future<void> renameCategory(int id, {required String nameZh, String? nameEn}) async {
    final updates = <String, Object?>{'name_zh': nameZh};
    if (nameEn != null) updates['name_en'] = nameEn;
    await _db!.update('categories', updates, where: 'id = ?', whereArgs: [id]);
    await _loadCategories();
    notifyListeners();
  }

  Future<void> deleteCategory(int id) async {
    await _db!.delete('categories', where: 'id = ?', whereArgs: [id]);
    await _loadCategories();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 存钱目标 CRUD
  // ---------------------------------------------------------------------------

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

  Future<void> deleteSavingsGoal(int id) async {
    await _db!.delete('savings_goals', where: 'id = ?', whereArgs: [id]);
    await _loadSavingsGoals();
    notifyListeners();
  }

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

  Future<int> addTag({required String name, required int colorValue}) async {
    final id = await _db!.insert('tags', {'name': name, 'color': colorValue});
    await _loadTags();
    notifyListeners();
    return id;
  }

  Future<void> updateTag(int id, {required String name, int? colorValue}) async {
    final updates = <String, Object?>{'name': name};
    if (colorValue != null) updates['color'] = colorValue;
    await _db!.update('tags', updates, where: 'id = ?', whereArgs: [id]);
    await _loadTags();
    notifyListeners();
  }

  Future<void> deleteTag(int id) async {
    await _db!.delete('tags', where: 'id = ?', whereArgs: [id]);
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
