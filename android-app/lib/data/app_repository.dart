import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/budget/budget_period.dart';
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

  /// 封面图资源路径（assets/book_covers/*.png）；空 = 无封面（显示 emoji）。
  final String cover;

  /// 加星账本排在列表前面（总账本永远第一）。
  final bool starred;

  /// 该账本的账单是否并入「总账本」视图（默认并入）。
  final bool includeInTotal;

  const BookEntity({
    required this.id,
    required this.name,
    this.icon = '📒',
    this.cover = '',
    this.starred = false,
    this.includeInTotal = true,
  });

  factory BookEntity.fromMap(Map<String, Object?> m) => BookEntity(
        id: m['id'] as int,
        name: m['name'] as String,
        icon: m['icon'] as String? ?? '📒',
        cover: m['cover'] as String? ?? '',
        starred: ((m['starred'] as int?) ?? 0) == 1,
        includeInTotal: ((m['include_in_total'] as int?) ?? 1) == 1,
      );
}

class CategoryEntity {
  final int id;
  final String key;
  final String nameZh;
  final String nameEn;
  final String kindRaw;
  final int? parentId;

  /// 已隐藏：不再出现在记账面板/编辑的分类网格里（历史账单不受影响）。
  final bool hidden;

  TransactionKind get kind => TransactionKind.fromJson(kindRaw);
  bool get isTopLevel => parentId == null;

  const CategoryEntity({
    required this.id,
    required this.key,
    required this.nameZh,
    required this.nameEn,
    required this.kindRaw,
    this.parentId,
    this.hidden = false,
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
        'hidden': hidden ? 1 : 0,
      };

  factory CategoryEntity.fromMap(Map<String, Object?> m) => CategoryEntity(
        id: m['id'] as int,
        key: m['key'] as String,
        nameZh: m['name_zh'] as String,
        nameEn: m['name_en'] as String,
        kindRaw: m['kind'] as String,
        parentId: m['parent_id'] as int?,
        hidden: ((m['hidden'] as int?) ?? 0) == 1,
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

  /// 不计入收支：仍在账单列表里，但统计/预算/洞察都跳过它。
  final bool excluded;

  /// 附着式退款：非空 = 这是某笔原账单的退款行（负支出），
  /// 不在时间线单独显示，改挂到 refundOf 那笔的详情/净额里。
  final int? refundOf;

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
    this.excluded = false,
    this.refundOf,
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
        excluded: ((m['excluded'] as int?) ?? 0) == 1,
        refundOf: m['refund_of'] as int?,
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
  static const _dbVersion = 19;
  static const _dbName = 'qingji.db';

  /// 行级 uuid（多人共享账本的同步地基）：32 位小写 hex，无需三方库。
  static String _newUuid() {
    final r = Random();
    return List.generate(
        16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  /// 新行的同步字段：uuid + 变更时间戳。
  static Map<String, Object?> _syncStampNew() => {
        'uuid': _newUuid(),
        'updated_ms': DateTime.now().millisecondsSinceEpoch,
      };

  Database? _db;

  final List<BookEntity> _books = [];
  final List<AccountEntity> _accounts = [];
  final List<CategoryEntity> _categories = [];
  final List<TransactionEntity> _transactions = [];
  final List<SavingsGoalEntity> _savingsGoals = [];
  final List<TagEntity> _tags = [];

  int _currentBookId = 0;
  /// 全部预算期间（新模型：阶段性预算，见 core/budget/budget_period.dart）。
  final List<BudgetPeriod> _budgetPeriods = [];
  String? _deepSeekApiKey;

  /// 记账模式偏好：true=AI 记账，false=手动记账（持久化）。
  bool _recordAiMode = false;
  int _chatRetentionDays = 30;

  /// 用户纠正记忆：(备注短语, 收支, 分类key)。AI 记账时按此覆盖模型的猜测。
  final List<({String phrase, TransactionKind kind, String key})> _catMemory =
      [];

  /// 周期记账规则(全部账本)。
  final List<RecurringRule> _recurringRules = [];

  /// 总账本 id（最早建的那本，聚合视图、不可删）。
  int _defaultBookId = 0;

  /// 抽屉功能项的用户自定义顺序（key 列表，见 main.dart 注册表）。
  final List<String> _drawerOrder = [];

  /// 统计页卡片的用户自定义顺序/可见集（key 列表，见 statistics_view 注册表）。
  final List<String> _statCardOrder = [];

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

  /// 总账本（最早建的那本）的 id：聚合视图、不可删除。
  int get defaultBookId => _defaultBookId;

  BookEntity? get currentBook {
    for (final b in _books) {
      if (b.id == _currentBookId) return b;
    }
    return null;
  }

  /// 抽屉功能项顺序（key 列表）；空 = 用默认顺序。
  List<String> get drawerOrder => List.unmodifiable(_drawerOrder);

  /// 保存抽屉功能项顺序（长按拖动排序后持久化）。
  Future<void> setDrawerOrder(List<String> keys) async {
    _drawerOrder
      ..clear()
      ..addAll(keys);
    await _db!.insert(
      'app_settings',
      {'key': 'drawer_order', 'value': keys.join(',')},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  Future<void> _loadDrawerOrder() async {
    final rows = await _db!.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['drawer_order'],
      limit: 1,
    );
    _drawerOrder.clear();
    final raw = rows.isEmpty ? '' : (rows.first['value'] as String? ?? '');
    if (raw.isNotEmpty) {
      _drawerOrder.addAll(raw.split(',').where((s) => s.isNotEmpty));
    }
  }

  /// 统计页（月视图）卡片顺序（key 列表）；空 = 用默认。
  List<String> get statCardOrder => List.unmodifiable(_statCardOrder);

  /// 保存统计卡片顺序/可见集（长按排序、移除、添加后持久化）。
  Future<void> setStatCardOrder(List<String> keys) async {
    _statCardOrder
      ..clear()
      ..addAll(keys);
    await _db!.insert(
      'app_settings',
      {'key': 'stat_cards', 'value': keys.join(',')},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  Future<void> _loadStatCardOrder() async {
    final rows = await _db!.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['stat_cards'],
      limit: 1,
    );
    _statCardOrder.clear();
    final raw = rows.isEmpty ? '' : (rows.first['value'] as String? ?? '');
    if (raw.isNotEmpty) {
      _statCardOrder.addAll(raw.split(',').where((s) => s.isNotEmpty));
    }
  }

  // 统计页「自定义」区间：记住上次选择，再次进入不用重选。
  // 用记录类型 (start,end) 避免数据层依赖 Flutter 的 DateTimeRange；视图侧再转。
  (DateTime, DateTime)? _statCustomRange;
  (DateTime, DateTime)? get statCustomRange => _statCustomRange;

  Future<void> setStatCustomRange(DateTime start, DateTime end) async {
    _statCustomRange = (start, end);
    await _db!.insert(
      'app_settings',
      {
        'key': 'stat_custom_range',
        'value': '${start.millisecondsSinceEpoch},'
            '${end.millisecondsSinceEpoch}',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  Future<void> _loadStatCustomRange() async {
    final rows = await _db!.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['stat_custom_range'],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final parts = (rows.first['value'] as String? ?? '').split(',');
    if (parts.length != 2) return;
    final s = int.tryParse(parts[0]);
    final e = int.tryParse(parts[1]);
    if (s == null || e == null) return;
    _statCustomRange = (
      DateTime.fromMillisecondsSinceEpoch(s),
      DateTime.fromMillisecondsSinceEpoch(e),
    );
  }

  /// 全部预算期间（新建在前面显示用，按生效起点降序）。
  List<BudgetPeriod> get budgetPeriods {
    final list = List<BudgetPeriod>.of(_budgetPeriods)
      ..sort((a, b) => b.start.compareTo(a.start));
    return List.unmodifiable(list);
  }

  /// 某年某月生效的月预算总额（当前账本口径）；没设过返回 null。
  Decimal? budgetTotalFor(int year, int month) =>
      BudgetResolver.monthlyTotalFor(_budgetPeriods, year, month,
          bookId: _currentBookId);

  /// 现在生效的月预算总额（老调用方无感兼容）。
  Decimal? get monthlyBudget {
    final n = DateTime.now();
    return budgetTotalFor(n.year, n.month);
  }

  /// 现在生效的分类预算明细（key -> 月预算）。
  Map<String, Decimal> get categoryBudgets =>
      BudgetResolver.effectiveOn(_budgetPeriods, DateTime.now(),
              bookId: _currentBookId)
          ?.categoryBudgets ??
      const {};

  /// 某分类 key 的月预算（未设返回 null）。
  Decimal? categoryBudgetFor(String key) => categoryBudgets[key];

  String? get deepSeekApiKey => _deepSeekApiKey;

  bool get recordAiMode => _recordAiMode;

  // ---------------------------------------------------------------------------
  // 初始化
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    final dbPath = p.join(await getDatabasesPath(), _dbName);
    await _backupBeforeMigration(dbPath);
    await _autoPeriodicBackup(dbPath);
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

  /// 每周静默本地备份一次（qingji.db.auto-日期.bak，最多保留 3 份）。
  /// 不依赖任何设置表——看最近一份自动备份的日期决定要不要备，
  /// 在 openDatabase 之前做，复制的是磁盘上完整落定的库文件。
  Future<void> _autoPeriodicBackup(String dbPath) async {
    try {
      final f = File(dbPath);
      if (!await f.exists()) return; // 新装机没得备
      final dir = f.parent;
      final autos = <File>[];
      await for (final e in dir.list()) {
        if (e is File &&
            p.basename(e.path).startsWith('$_dbName.auto-') &&
            e.path.endsWith('.bak')) {
          autos.add(e);
        }
      }
      autos.sort((a, b) => b.path.compareTo(a.path)); // 文件名含日期，倒序=最新在前
      if (autos.isNotEmpty) {
        final newest = await autos.first.lastModified();
        if (DateTime.now().difference(newest).inDays < 7) return;
      }
      final now = DateTime.now();
      final stamp = '${now.year}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}';
      await f.copy(p.join(dir.path, '$_dbName.auto-$stamp.bak'));
      // 只留最近 3 份，旧的删掉。
      for (final old in autos.skip(2)) {
        try {
          await old.delete();
        } catch (_) {}
      }
    } catch (_) {
      // 备份失败不拦启动。
    }
  }

  /// 本机现有的备份文件（自动 + 迁移前），最新在前。给「备份/恢复」页展示用。
  Future<List<File>> localBackupFiles() async {
    final dbPath = p.join(await getDatabasesPath(), _dbName);
    final dir = File(dbPath).parent;
    final out = <File>[];
    try {
      await for (final e in dir.list()) {
        if (e is File &&
            p.basename(e.path).startsWith('$_dbName.') &&
            e.path.endsWith('.bak')) {
          out.add(e);
        }
      }
      final times = <String, DateTime>{};
      for (final f in out) {
        times[f.path] = await f.lastModified();
      }
      out.sort((a, b) => times[b.path]!.compareTo(times[a.path]!));
    } catch (_) {}
    return out;
  }

  /// DB 要升版本时，先把旧库原样复制一份（qingji.db.pre-v旧版本.bak）再迁移。
  /// 迁移代码万一有 bug，用户的真实账本还有救——「备份/恢复」页选这个文件即可。
  /// 版本没变或新装机则什么都不做；备份失败也不拦启动。
  Future<void> _backupBeforeMigration(String dbPath) async {
    try {
      final f = File(dbPath);
      if (!await f.exists()) return;
      final probe = await openReadOnlyDatabase(dbPath);
      final rows = await probe.rawQuery('PRAGMA user_version');
      await probe.close();
      final old = (rows.first.values.first as int?) ?? 0;
      if (old <= 0 || old >= _dbVersion) return;
      await f.copy('$dbPath.pre-v$old.bak');
    } catch (_) {
      // 备份是兜底，不能因为它失败（磁盘满等）挡住正常启动。
    }
  }

  /// 测试用：关掉底层数据库连接（不然临时目录删不掉）。
  @visibleForTesting
  Future<void> closeForTest() async {
    await _db?.close();
    _db = null;
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
        parent_id INTEGER,
        hidden    INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE books (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        name             TEXT NOT NULL,
        icon             TEXT NOT NULL DEFAULT '📒',
        cover            TEXT NOT NULL DEFAULT '',
        sort_order       INTEGER NOT NULL DEFAULT 0,
        created_ms       INTEGER NOT NULL DEFAULT 0,
        starred          INTEGER NOT NULL DEFAULT 0,
        include_in_total INTEGER NOT NULL DEFAULT 1,
        uuid             TEXT NOT NULL DEFAULT '',
        updated_ms       INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.insert('books', {
      'name': '总账本',
      'icon': '📒',
      'sort_order': 0,
      'created_ms': DateTime.now().millisecondsSinceEpoch,
      'uuid': _newUuid(),
      'updated_ms': DateTime.now().millisecondsSinceEpoch,
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
        image_path      TEXT NOT NULL DEFAULT '',
        excluded        INTEGER NOT NULL DEFAULT 0,
        uuid            TEXT NOT NULL DEFAULT '',
        updated_ms      INTEGER NOT NULL DEFAULT 0,
        refund_of       INTEGER
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

    await db.execute(_createBudgetPeriodsSql);

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
    if (oldVersion < 12) {
      // 账本加星 + 是否计入总账本（默认计入）。
      try {
        await db.execute(
            'ALTER TABLE books ADD COLUMN starred INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute(
            'ALTER TABLE books ADD COLUMN include_in_total INTEGER NOT NULL DEFAULT 1');
      } catch (_) {}
    }
    if (oldVersion < 13) {
      // 预算改「预算期间」模型：阶段性预算，历史月显示当时生效的那份。
      await db.execute(_createBudgetPeriodsSql);
      // 老的单一预算自动搬成一条「从很久以前开始的每月循环期间」，
      // 行为与之前完全一致；旧 budget 表保留不动（只加不删）。
      try {
        final totalRows = await db.query('budget',
            where: 'category_key IS NULL', limit: 1);
        if (totalRows.isNotEmpty) {
          final total =
              Decimal.tryParse(totalRows.first['amount'] as String? ?? '');
          if (total != null && total > Decimal.zero) {
            final catRows =
                await db.query('budget', where: 'category_key IS NOT NULL');
            final cats = <String, String>{};
            for (final r in catRows) {
              final k = r['category_key'] as String?;
              final v = Decimal.tryParse(r['amount'] as String? ?? '');
              if (k != null && k.isNotEmpty && v != null && v > Decimal.zero) {
                cats[k] = v.toString();
              }
            }
            await db.insert('budget_periods', {
              'book_id': null,
              'start_ms': DateTime(2000, 1, 1).millisecondsSinceEpoch,
              'end_ms': null,
              'recurring_monthly': 1,
              'total': total.toString(),
              'category_budgets': cats.isEmpty ? '' : jsonEncode(cats),
              'monthly_income': '',
              'fixed_expenses': '',
              'created_ms': DateTime.now().millisecondsSinceEpoch,
            });
          }
        }
      } catch (_) {}
    }
    if (oldVersion < 14) {
      // 账本封面图（模板成品插画的资源路径）。
      try {
        await db.execute(
            "ALTER TABLE books ADD COLUMN cover TEXT NOT NULL DEFAULT ''");
      } catch (_) {}
    }
    if (oldVersion < 15) {
      // 「不计入收支」：帮人代付等不想进统计/预算的账（记录仍在列表里）。
      try {
        await db.execute(
            'ALTER TABLE transactions ADD COLUMN excluded INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
    }
    if (oldVersion < 16) {
      // ① 分类可隐藏：删除保护的出路——有历史账单的分类建议隐藏/合并，不硬删。
      try {
        await db.execute(
            'ALTER TABLE categories ADD COLUMN hidden INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
      // ② 多人共享账本的地基：行级 uuid + 变更时间戳。现在先落库并回填，
      //    以后接后端同步时就不用再全表迁移（越晚加越疼）。
      for (final table in ['transactions', 'books']) {
        try {
          await db.execute(
              "ALTER TABLE $table ADD COLUMN uuid TEXT NOT NULL DEFAULT ''");
        } catch (_) {}
        try {
          await db.execute(
              'ALTER TABLE $table ADD COLUMN updated_ms INTEGER NOT NULL DEFAULT 0');
        } catch (_) {}
        // 存量行回填：uuid 用 SQLite 自带 randomblob，无需三方库。
        await db.execute(
            "UPDATE $table SET uuid = lower(hex(randomblob(16))) WHERE uuid = ''");
        await db.execute('UPDATE $table SET updated_ms = ? WHERE updated_ms = 0',
            [DateTime.now().millisecondsSinceEpoch]);
      }
    }
    if (oldVersion < 17) {
      // 附着式退款：退款行挂到原账单（refund_of=原id），不再作为独立条目
      // 出现在时间线里。老的独立冲账行 refund_of 保持 NULL，仍按旧样显示。
      try {
        await db.execute(
            'ALTER TABLE transactions ADD COLUMN refund_of INTEGER');
      } catch (_) {}
    }
    if (oldVersion < 18) {
      // Phase A 分类大改：重跑分类树（幂等 upsert）——新分类插入、改名/重挂父类
      // 更新，**绝不动 transactions**，历史账单靠 category_id 不变、分类不丢。
      await _applyCategoryTree(db);
    }
    if (oldVersion < 19) {
      // 退款日期修复：早期版本把退款/报销冲减行记成「记账当天」而非原订单日期，
      // 导致跨月退款把当月支出算错、表头合计与列表净额对不上。
      // ① 把已挂账的退款行日期改回原订单日期；
      await db.execute('''
        UPDATE transactions
        SET date_ms = (SELECT o.date_ms FROM transactions o
                       WHERE o.id = transactions.refund_of)
        WHERE refund_of IS NOT NULL
          AND refund_of IN (SELECT id FROM transactions)
      ''');
      // ② 删除「孤儿退款」（原订单已不存在）——它们是隐藏的幽灵负数，
      //    会让合计凭空少一截、AI 无中生有。删掉即可（退款本就无所依附）。
      await db.execute('''
        DELETE FROM transactions
        WHERE refund_of IS NOT NULL
          AND refund_of NOT IN (SELECT id FROM transactions)
      ''');
    }
  }

  static const _createBudgetPeriodsSql = '''
      CREATE TABLE IF NOT EXISTS budget_periods (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id           INTEGER,
        start_ms          INTEGER NOT NULL,
        end_ms            INTEGER,
        recurring_monthly INTEGER NOT NULL DEFAULT 1,
        total             TEXT NOT NULL,
        category_budgets  TEXT NOT NULL DEFAULT '',
        monthly_income    TEXT NOT NULL DEFAULT '',
        fixed_expenses    TEXT NOT NULL DEFAULT '',
        created_ms        INTEGER NOT NULL DEFAULT 0
      )
    ''';

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
      _loadBudgetPeriods(),
      _loadApiKey(),
      _loadRecordMode(),
      _loadChatRetention(),
      _loadCategoryMemory(),
      _loadRecurringRules(),
      _loadSavingsGoals(),
      _loadTags(),
      _loadDrawerOrder(),
      _loadStatCardOrder(),
      _loadStatCustomRange(),
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
    final loaded = rows.map(BookEntity.fromMap).toList();
    // 总账本 = 最早建的那本（id 最小），不可删、永远排第一。
    _defaultBookId = loaded.isEmpty
        ? 0
        : loaded.map((b) => b.id).reduce((a, b) => a < b ? a : b);
    // 排序：总账本 → 加星 → 其它（同组保持原顺序，稳定排序）。
    int rank(BookEntity b) =>
        b.id == _defaultBookId ? 0 : (b.starred ? 1 : 2);
    final indexed = [for (var i = 0; i < loaded.length; i++) (i, loaded[i])];
    indexed.sort((a, b) {
      final r = rank(a.$2).compareTo(rank(b.$2));
      return r != 0 ? r : a.$1.compareTo(b.$1);
    });
    _books
      ..clear()
      ..addAll(indexed.map((e) => e.$2));
  }

  Future<void> _ensureDefaultBook() async {
    final count =
        Sqflite.firstIntValue(await _db!.rawQuery('SELECT COUNT(*) FROM books')) ?? 0;
    if (count == 0) {
      await _db!.insert('books', {
        ..._syncStampNew(),
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

  Future<void> _loadBudgetPeriods() async {
    final rows = await _db!
        .query('budget_periods', orderBy: 'start_ms ASC, id ASC');
    _budgetPeriods
      ..clear()
      ..addAll(rows.map(BudgetPeriod.fromMap));
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

  /// 追加一条「记账明细卡」消息（role='record'，结构化数据 JSON 存在 text 列，
  /// 复用现有列免迁移）。返回新行 id，供之后改分类/删除时更新这张卡。
  Future<int> addChatRecordMessage(String json) async {
    return _db!.insert('chat_messages', {
      'role': 'record',
      'text': json,
      'question': '',
      'created_ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 更新某张记账卡的持久化 JSON（用户改分类/删条目后写回最新状态）。
  Future<void> updateChatRecordMessage(int rowId, String json) async {
    await _db!.update('chat_messages', {'text': json},
        where: 'id = ?', whereArgs: [rowId]);
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

  /// 喵学过的全部「备注短语 → 分类」记忆（管理页展示用），按短语排序。
  List<({String phrase, TransactionKind kind, String key})>
      get categoryMemories =>
          List.of(_catMemory)..sort((a, b) => a.phrase.compareTo(b.phrase));

  /// 给 DeepSeek 提示词用：某收支下**未隐藏**的分类选项（key + 中文名，含自建分类）。
  List<({String key, String name})> llmCategoryOptions(TransactionKind kind) => [
        for (final c in _categories)
          if (c.kind == kind && !c.hidden) (key: c.key, name: c.nameZh)
      ];

  /// 给 DeepSeek 提示词用：用户的学习记忆（历史纠正），让模型模仿其分类习惯。
  List<({String phrase, String categoryKey})> get llmLearnedHints =>
      [for (final m in _catMemory) (phrase: m.phrase, categoryKey: m.key)];

  /// 删除一条学过的记忆（学错了/过时了，用户在管理页手动清）。
  Future<void> forgetCategory(String phrase, TransactionKind kind) async {
    await _db!.delete('category_memory',
        where: 'phrase = ? AND kind = ?', whereArgs: [phrase, kind.toJson()]);
    _catMemory.removeWhere((m) => m.phrase == phrase && m.kind == kind);
    notifyListeners();
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
          ..._syncStampNew(),
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
    // 总账本 = 聚合视图：显示自己的账单 + 所有「计入总账本」账本的账单；
    // 其它账本只显示自己的。
    final isTotal = _currentBookId == _defaultBookId;
    final ids = isTotal
        ? [
            for (final b in _books)
              if (b.id == _defaultBookId || b.includeInTotal) b.id
          ]
        : [_currentBookId];
    if (ids.isEmpty) ids.add(-1); // 空保护，避免 IN () 语法错误
    final idList = ids.join(','); // 都是 DB 里来的 int，可安全拼接
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
        t.image_path,
        t.excluded,
        t.refund_of
      FROM transactions t
      LEFT JOIN categories c  ON c.id = t.category_id
      LEFT JOIN accounts   a  ON a.id = t.account_id
      LEFT JOIN accounts   ta ON ta.id = t.to_account_id
      WHERE t.book_id IN ($idList)
      ORDER BY t.date_ms DESC
    ''');
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

  /// 新增一笔，返回新记录的 id（供记账卡保存后按条目改分类用）。
  /// [bookId] 不传则记到当前账本（手动卡的「账本」芯片可指定记到别的账本）。
  Future<int> addTransaction({
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
    bool excluded = false,
    int? bookId,
  }) async {
    final newId = await _db!.insert('transactions', {
      'book_id': bookId ?? _currentBookId,
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
      'excluded': excluded ? 1 : 0,
      ..._syncStampNew(),
    });
    await _loadTransactions();
    notifyListeners();
    return newId;
  }

  /// 当前账本视角下所有「待报销」的支出（金额大的在前）。
  List<TransactionEntity> get reimbursableTransactions => _transactions
      .where((t) =>
          t.reimbursable &&
          t.txKind == TransactionKind.expense &&
          t.amount > Decimal.zero)
      .toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));

  /// 标记一笔已报销：钱报销回来了 = 这笔不算自己的支出，
  /// 所以像退款一样给它补一笔「补满净额」的退款让净额归 0（用户 0703 拍板），
  /// 同时清掉待报销标。原账单仍在列表里，显示成划线原价 + 净额 0。
  Future<void> markReimbursed(int id) async {
    final original = _transactions.where((t) => t.id == id).firstOrNull;
    if (original == null) return;
    final net = netAmountOf(original);
    if (net > Decimal.zero) {
      final accountId = original.accountId ?? _accounts.firstOrNull?.id;
      final bookId = Sqflite.firstIntValue(await _db!.rawQuery(
          'SELECT book_id FROM transactions WHERE id = ?', [id]));
      await _db!.insert('transactions', {
        'book_id': bookId ?? _currentBookId,
        'kind': TransactionKind.expense.toJson(),
        'amount': (Decimal.zero - net).toString(),
        'currency_code': 'CNY',
        'category_id': original.categoryId,
        'account_id': accountId,
        'note': '报销到账',
        // 同退款：冲减归属原订单那个月，保证表头合计=列表净额。
        'date_ms': original.dateMs,
        'refund_of': id,
        ..._syncStampNew(),
      });
    }
    await _db!.update(
      'transactions',
      {
        'reimbursable': 0,
        'updated_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _loadTransactions();
    notifyListeners();
  }

  /// 只改某笔的分类（记账卡「一键改分类」用，轻量、不动其它字段）。
  Future<void> setTransactionCategory(int id, int? categoryId) async {
    await _db!.update(
      'transactions',
      {
        'category_id': categoryId,
        'updated_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _loadTransactions();
    notifyListeners();
  }

  /// 退款：记一笔挂在原账单上的「负支出」（refund_of=原id）。
  /// 退款行不在时间线单独显示，改挂到原账单的净额/详情里（对齐咔皮）；
  /// 统计/预算/结余因负数累加自动按净额计算，无需改引擎。
  Future<void> refundTransaction(
      TransactionEntity original, Decimal refundAmount) async {
    if (refundAmount <= Decimal.zero) return;
    final accountId = original.accountId ?? _accounts.firstOrNull?.id;
    if (accountId == null) return;
    // 退款行跟原账单同一个账本，跨账本视图也待在一起。
    final bookId = Sqflite.firstIntValue(await _db!.rawQuery(
        'SELECT book_id FROM transactions WHERE id = ?', [original.id]));
    await _db!.insert('transactions', {
      'book_id': bookId ?? _currentBookId,
      'kind': TransactionKind.expense.toJson(),
      'amount': (Decimal.zero - refundAmount).toString(), // 负支出 = 冲账
      'currency_code': 'CNY',
      'category_id': original.categoryId,
      'account_id': accountId,
      'note': '退款',
      // 退款是原支出的冲减，日期归属原订单那个月（否则跨月退款会把当月
      // 支出算错、且表头合计与列表净额对不上 → 用户不信任）。
      'date_ms': original.dateMs,
      'refund_of': original.id,
      ..._syncStampNew(),
    });
    await _loadTransactions();
    notifyListeners();
  }

  /// 时间线可见账单：隐藏「附着式退款行」（它们挂在原账单里）。
  /// 老的独立冲账行 refundOf==null，仍照常显示（不破坏历史）。
  List<TransactionEntity> get visibleTransactions =>
      _transactions.where((t) => t.refundOf == null).toList();

  /// 某笔账单的退款明细行（按时间正序）。
  List<TransactionEntity> refundsOf(int id) =>
      (_transactions.where((t) => t.refundOf == id).toList())
        ..sort((a, b) => a.dateMs.compareTo(b.dateMs));

  /// 某笔账单已退款合计（正数）。
  Decimal refundedAmountOf(int id) {
    var sum = Decimal.zero;
    for (final t in _transactions) {
      if (t.refundOf == id) sum += t.amount.abs();
    }
    return sum;
  }

  /// 某笔账单的净额 = 原额 − 已退（退款行是负数，直接累加即净额）。
  Decimal netAmountOf(TransactionEntity t) {
    var net = t.amount;
    for (final r in _transactions) {
      if (r.refundOf == t.id) net += r.amount; // r.amount 为负
    }
    return net;
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
    bool excluded = false,
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
        'excluded': excluded ? 1 : 0,
        'updated_ms': DateTime.now().millisecondsSinceEpoch,
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
        ..._syncStampNew(),
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

    // 删原账单时连它的退款行一起删（不然会留下挂空的退款负数进统计）。
    await _db!.delete('transactions',
        where: 'id = ? OR refund_of = ?', whereArgs: [id, id]);
    _transactions.removeWhere((t) => t.id == id || t.refundOf == id);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 查询辅助
  // ---------------------------------------------------------------------------

  List<CategoryEntity> categoriesForKind(TransactionKind kind) =>
      _categories.where((c) => c.kind == kind).toList();

  List<CategoryEntity> categoriesForKindRanked(TransactionKind kind) {
    final all = categoriesForKind(kind);
    // 记账面板不展示已隐藏的分类（管理页用 categoriesForKind 能看到全部）。
    final tops = all.where((c) => c.isTopLevel && !c.hidden).toList();
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

  /// 未隐藏的子分类（记账面板判断「可不可展开」用它，管理页用 childrenOf）。
  List<CategoryEntity> visibleChildrenOf(int parentId) =>
      _categories.where((c) => c.parentId == parentId && !c.hidden).toList();

  /// 子分类按「这个人用得多不多」排序：记过的次数多在前，没记过的保持原顺序。
  /// 手动卡的二级分类展开面板用它，让常用子类排前面少翻找。已隐藏的不出现。
  List<CategoryEntity> childrenOfRanked(int parentId) {
    final children = visibleChildrenOf(parentId);
    if (children.length < 2) return children;
    final counts = <int, int>{};
    for (final t in _transactions) {
      final cid = t.categoryId;
      if (cid != null) counts[cid] = (counts[cid] ?? 0) + 1;
    }
    final indexed = [for (var i = 0; i < children.length; i++) (i, children[i])];
    indexed.sort((a, b) {
      final ca = counts[a.$2.id] ?? 0;
      final cb = counts[b.$2.id] ?? 0;
      return ca != cb ? cb.compareTo(ca) : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

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

  /// 供统计/预算/洞察消费的记录流：**跳过「不计入收支」的账**。
  /// 账单列表要显示全部请用 [transactions]。
  List<TransactionRecord> get allRecords => [
        for (final t in _transactions)
          if (!t.excluded) t.toRecord()
      ];

  // ---------------------------------------------------------------------------
  // 预算期间（新模型：阶段性预算）
  // ---------------------------------------------------------------------------

  /// 新建一条预算期间，返回 id。
  Future<int> addBudgetPeriod({
    int? bookId,
    required DateTime start,
    DateTime? end,
    bool recurringMonthly = true,
    required Decimal total,
    Map<String, Decimal> categoryBudgets = const {},
    Decimal? monthlyIncome,
    List<(String, Decimal)> fixedExpenses = const [],
  }) async {
    final p = BudgetPeriod(
      id: 0,
      bookId: bookId,
      start: DateTime(start.year, start.month, start.day),
      end: end == null ? null : DateTime(end.year, end.month, end.day),
      recurringMonthly: recurringMonthly,
      total: total,
      categoryBudgets: categoryBudgets,
      monthlyIncome: monthlyIncome,
      fixedExpenses: fixedExpenses,
    );
    final id = await _db!.insert('budget_periods', {
      'book_id': bookId,
      'start_ms': p.start.millisecondsSinceEpoch,
      'end_ms': p.end?.millisecondsSinceEpoch,
      'recurring_monthly': recurringMonthly ? 1 : 0,
      'total': total.toString(),
      'category_budgets':
          categoryBudgets.isEmpty ? '' : p.categoryBudgetsJson(),
      'monthly_income': monthlyIncome?.toString() ?? '',
      'fixed_expenses':
          fixedExpenses.isEmpty ? '' : p.fixedExpensesJson(),
      'created_ms': DateTime.now().millisecondsSinceEpoch,
    });
    await _loadBudgetPeriods();
    notifyListeners();
    return id;
  }

  /// 编辑既有预算计划（整条覆盖式更新，id 不变）。
  Future<void> updateBudgetPeriod(
    int id, {
    int? bookId,
    required DateTime start,
    DateTime? end,
    bool recurringMonthly = true,
    required Decimal total,
    Map<String, Decimal> categoryBudgets = const {},
    Decimal? monthlyIncome,
    List<(String, Decimal)> fixedExpenses = const [],
  }) async {
    final p = BudgetPeriod(
      id: id,
      bookId: bookId,
      start: DateTime(start.year, start.month, start.day),
      end: end == null ? null : DateTime(end.year, end.month, end.day),
      recurringMonthly: recurringMonthly,
      total: total,
      categoryBudgets: categoryBudgets,
      monthlyIncome: monthlyIncome,
      fixedExpenses: fixedExpenses,
    );
    await _db!.update(
      'budget_periods',
      {
        'book_id': bookId,
        'start_ms': p.start.millisecondsSinceEpoch,
        'end_ms': p.end?.millisecondsSinceEpoch,
        'recurring_monthly': recurringMonthly ? 1 : 0,
        'total': total.toString(),
        'category_budgets':
            categoryBudgets.isEmpty ? '' : p.categoryBudgetsJson(),
        'monthly_income': monthlyIncome?.toString() ?? '',
        'fixed_expenses': fixedExpenses.isEmpty ? '' : p.fixedExpensesJson(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _loadBudgetPeriods();
    notifyListeners();
  }

  Future<void> deleteBudgetPeriod(int id) async {
    await _db!.delete('budget_periods', where: 'id = ?', whereArgs: [id]);
    await _loadBudgetPeriods();
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

  Future<int> addBook({
    required String name,
    String icon = '📒',
    String cover = '',
    bool includeInTotal = true,
  }) async {
    final id = await _db!.insert('books', {
      ..._syncStampNew(),
      'name': name,
      'icon': icon,
      'cover': cover,
      'sort_order': _books.length,
      'created_ms': DateTime.now().millisecondsSinceEpoch,
      'starred': 0,
      'include_in_total': includeInTotal ? 1 : 0,
    });
    await _loadBooks();
    notifyListeners();
    return id;
  }

  Future<void> renameBook(int id, {required String name, String? icon}) async {
    final updates = <String, Object?>{
      'name': name,
      'updated_ms': DateTime.now().millisecondsSinceEpoch,
    };
    if (icon != null) updates['icon'] = icon;
    await _db!.update('books', updates, where: 'id = ?', whereArgs: [id]);
    await _loadBooks();
    notifyListeners();
  }

  /// 编辑账本（名称/图标/封面/是否计入总账本）。计入开关变了会刷新聚合视图。
  Future<void> updateBook(
    int id, {
    String? name,
    String? icon,
    String? cover,
    bool? includeInTotal,
  }) async {
    final updates = <String, Object?>{};
    if (name != null && name.isNotEmpty) updates['name'] = name;
    if (icon != null) updates['icon'] = icon;
    if (cover != null) updates['cover'] = cover;
    if (includeInTotal != null) {
      updates['include_in_total'] = includeInTotal ? 1 : 0;
    }
    if (updates.isEmpty) return;
    updates['updated_ms'] = DateTime.now().millisecondsSinceEpoch;
    await _db!.update('books', updates, where: 'id = ?', whereArgs: [id]);
    await _loadBooks();
    await _loadTransactions();
    notifyListeners();
  }

  /// 加星 / 取消加星（加星账本排前面）。
  Future<void> setBookStarred(int id, bool starred) async {
    await _db!.update('books', {'starred': starred ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
    await _loadBooks();
    notifyListeners();
  }

  /// 这个账本名下有多少笔账单（删除前的保护检查用）。
  Future<int> transactionCountForBook(int id) async =>
      Sqflite.firstIntValue(await _db!.rawQuery(
          'SELECT COUNT(*) FROM transactions WHERE book_id = ?', [id])) ??
      0;

  /// 删账本。[moveRecordsToDefault] = true 时先把账单转移到总账本再删，
  /// 记录不丢；false = 连账单一起删（UI 层要走更深的二次确认）。
  Future<void> deleteBook(int id, {bool moveRecordsToDefault = false}) async {
    if (_books.length <= 1) return;
    if (id == _defaultBookId) return; // 总账本不可删
    if (moveRecordsToDefault) {
      await _db!.update(
        'transactions',
        {
          'book_id': _defaultBookId,
          'updated_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'book_id = ?',
        whereArgs: [id],
      );
    } else {
      await _db!
          .delete('transactions', where: 'book_id = ?', whereArgs: [id]);
    }
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
    int? parentId,
  }) async {
    final id = await _db!.insert('categories', {
      'key': key,
      'name_zh': nameZh,
      'name_en': nameEn,
      'kind': kind.toJson(),
      'parent_id': parentId,
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

  /// 删除分类（连同它的子分类，防止留下挂着失效 parent_id 的幽灵行）。
  /// 有历史账单的分类别直接删——UI 层用 [transactionCountForCategory]
  /// 检查后引导「隐藏」或「合并」。
  Future<void> deleteCategory(int id) async {
    await _db!.delete('categories',
        where: 'id = ? OR parent_id = ?', whereArgs: [id, id]);
    await _loadCategories();
    notifyListeners();
  }

  /// 这个分类（含子分类）名下有多少笔账单——跨全部账本查 DB，不是只看当前账本。
  Future<int> transactionCountForCategory(int id) async {
    final ids = <int>[id, ...childrenOf(id).map((c) => c.id)];
    final marks = List.filled(ids.length, '?').join(',');
    return Sqflite.firstIntValue(await _db!.rawQuery(
            'SELECT COUNT(*) FROM transactions WHERE category_id IN ($marks)',
            ids)) ??
        0;
  }

  /// 隐藏 / 恢复显示分类（隐藏后不再出现在记账面板，历史账单不动）。
  Future<void> setCategoryHidden(int id, bool hidden) async {
    await _db!.update('categories', {'hidden': hidden ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
    await _loadCategories();
    notifyListeners();
  }

  /// 把分类 [fromId] 合并进 [toId]：账单改挂、子分类改挂、
  /// AI 纠正记忆（category_memory）迁移，然后删掉 from。不可撤销。
  Future<void> mergeCategory(int fromId, int toId) async {
    if (fromId == toId) return;
    final from = _categories.where((c) => c.id == fromId).firstOrNull;
    final to = _categories.where((c) => c.id == toId).firstOrNull;
    if (from == null || to == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    await _db!.update(
        'transactions', {'category_id': toId, 'updated_ms': now},
        where: 'category_id = ?', whereArgs: [fromId]);
    // from 的子分类改认 to 当父类（to 是子分类时挂到 to 的父类下，别出现三级）。
    final newParent = to.isTopLevel ? to.id : to.parentId!;
    await _db!.update('categories', {'parent_id': newParent},
        where: 'parent_id = ?', whereArgs: [fromId]);
    await _db!.update('category_memory', {'category_key': to.key},
        where: 'category_key = ?', whereArgs: [from.key]);
    await _db!.delete('categories', where: 'id = ?', whereArgs: [fromId]);

    await _loadCategories();
    await _loadCategoryMemory();
    await _loadTransactions();
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
