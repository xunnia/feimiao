import 'package:decimal/decimal.dart';
import '../account/account_movement_projection.dart';
import '../ledger/book_membership.dart';
import '../transaction_time.dart';
import 'transaction_kind.dart';
import 'transaction_record.dart';

class BookEntity {
  final String uuid;
  final int id;
  final String name;
  final String icon;

  /// 封面图资源路径（assets/book_covers/*.png）；空 = 无封面（显示 emoji）。
  final String cover;

  /// 备注（抽屉账本行名称下方的灰小字）；空 = 不显示。
  final String remark;

  /// 加星账本排在列表前面（总账本永远第一）。
  final bool starred;

  /// 该账本的账单是否并入「总账本」视图（默认并入）。
  final bool includeInTotal;

  const BookEntity({
    this.uuid = '',
    required this.id,
    required this.name,
    this.icon = '📒',
    this.cover = '',
    this.remark = '',
    this.starred = false,
    this.includeInTotal = true,
  });

  factory BookEntity.fromMap(Map<String, Object?> m) => BookEntity(
        uuid: m['uuid'] as String? ?? '',
        id: m['id'] as int,
        name: m['name'] as String,
        icon: m['icon'] as String? ?? '📒',
        cover: m['cover'] as String? ?? '',
        remark: m['remark'] as String? ?? '',
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
  final int? bookId;
  final Set<int>? _bookIds;
  Set<int> get bookIds => _bookIds == null
      ? {if (bookId != null) bookId!}
      : Set.unmodifiable(_bookIds);
  final String uuid;
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
  final TransactionTimePrecision timePrecision;
  final int createdMs;
  final int? settledMs;
  final SettlementQuality settlementQuality;
  final int? settlementAccountId;
  final SettlementQuality settlementAccountQuality;
  final TransactionEventType eventType;
  final String tagsRaw;
  final bool reimbursable;
  final String imagePath;
  final int? recurringRuleId;

  /// 不计入收支：仍在账单列表里，但统计/预算/洞察都跳过它。
  final bool excluded;

  /// 附着式退款：非空 = 这是某笔原账单的退款行（负支出），
  /// 不在时间线单独显示，改挂到 refundOf 那笔的详情/净额里。
  final int? refundOf;

  Decimal get amount => Decimal.parse(amountStr);
  DateTime get date => DateTime.fromMillisecondsSinceEpoch(dateMs);
  DateTime? get settledAt => settledMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(settledMs!);
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
    this.bookId,
    Set<int>? bookIds,
    this.uuid = '',
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
    this.timePrecision = TransactionTimePrecision.legacyUnknown,
    this.createdMs = 0,
    this.settledMs,
    this.settlementQuality = SettlementQuality.unknown,
    this.settlementAccountId,
    this.settlementAccountQuality = SettlementQuality.unknown,
    this.eventType = TransactionEventType.legacyAdjustment,
    this.tagsRaw = '',
    this.reimbursable = false,
    this.imagePath = '',
    this.recurringRuleId,
    this.excluded = false,
    this.refundOf,
  }) : _bookIds = bookIds;

  TransactionRecord toRecord({String languageCode = 'zh'}) => TransactionRecord(
        id: id.toString(),
        kind: txKind,
        amount: amount,
        currencyCode: currencyCode,
        categoryName:
            languageCode.startsWith('zh') ? categoryNameZh : categoryNameEn,
        categoryKey: categoryKey,
        accountId: accountId,
        accountName: accountName,
        toAccountId: toAccountId,
        toAccountName: toAccountName,
        note: note,
        date: date,
        timePrecision: timePrecision,
      );

  factory TransactionEntity.fromMap(Map<String, Object?> m) =>
      TransactionEntity(
        id: m['id'] as int,
        bookId: m['book_id'] as int?,
        bookIds: m['book_ids'] == null
            ? null
            : parseTransactionBookIds(m['book_ids']),
        uuid: m['uuid'] as String? ?? '',
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
        timePrecision: TransactionTimePrecisionX.fromStorage(
          m['time_precision'] as String?,
        ),
        createdMs: m['created_ms'] as int? ?? 0,
        settledMs: m['settled_ms'] as int?,
        settlementQuality: SettlementQualityX.fromStorage(
          m['settlement_quality'] as String?,
        ),
        settlementAccountId: m['settlement_account_id'] as int?,
        settlementAccountQuality: SettlementQualityX.fromStorage(
          m['settlement_account_quality'] as String?,
        ),
        eventType: TransactionEventTypeX.fromStorage(
          m['event_type'] as String?,
        ),
        tagsRaw: m['tags'] as String? ?? '',
        reimbursable: ((m['reimbursable'] as int?) ?? 0) == 1,
        imagePath: m['image_path'] as String? ?? '',
        recurringRuleId: m['recurring_rule_id'] as int?,
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
  final TransactionTimePrecision timePrecision;
  final List<int> tagIds;
  final bool reimbursable;
  final String imagePath;
  final bool excluded;
  final int? bookId;

  const TransactionDraft({
    required this.kind,
    required this.amount,
    this.categoryId,
    required this.accountId,
    this.note = '',
    required this.date,
    this.timePrecision = TransactionTimePrecision.legacyUnknown,
    this.tagIds = const [],
    this.reimbursable = false,
    this.imagePath = '',
    this.excluded = false,
    this.bookId,
  });

  TransactionDraft copyWith({
    TransactionKind? kind,
    Decimal? amount,
    int? categoryId,
    int? accountId,
    String? note,
    DateTime? date,
    TransactionTimePrecision? timePrecision,
    List<int>? tagIds,
    bool? reimbursable,
    String? imagePath,
    bool? excluded,
    int? bookId,
  }) =>
      TransactionDraft(
        kind: kind ?? this.kind,
        amount: amount ?? this.amount,
        categoryId: categoryId ?? this.categoryId,
        accountId: accountId ?? this.accountId,
        note: note ?? this.note,
        date: date ?? this.date,
        timePrecision: timePrecision ?? this.timePrecision,
        tagIds: tagIds ?? this.tagIds,
        reimbursable: reimbursable ?? this.reimbursable,
        imagePath: imagePath ?? this.imagePath,
        excluded: excluded ?? this.excluded,
        bookId: bookId ?? this.bookId,
      );
}

class FeimiaoImportRow {
  final String uuid;
  final String refundOfUuid;
  final String role;
  final TransactionKind kind;
  final Decimal amount;
  final Decimal refunded;
  final String categoryKey;
  final String categoryName;
  final String accountName;
  final String toAccountName;
  final List<String> tagNames;
  final String note;
  final DateTime date;
  final TransactionTimePrecision timePrecision;
  final DateTime? settledAt;
  final SettlementQuality? settlementQuality;
  final String settlementAccountName;
  final SettlementQuality? settlementAccountQuality;
  final TransactionEventType? eventType;
  final bool excluded;
  final bool reimbursable;
  final List<String>? bookUuids;
  final List<String>? bookNames;

  const FeimiaoImportRow({
    this.uuid = '',
    this.refundOfUuid = '',
    this.role = 'transaction',
    required this.kind,
    required this.amount,
    required this.refunded,
    this.categoryKey = '',
    this.categoryName = '',
    this.accountName = '',
    this.toAccountName = '',
    this.tagNames = const [],
    this.note = '',
    required this.date,
    this.timePrecision = TransactionTimePrecision.legacyUnknown,
    this.settledAt,
    this.settlementQuality,
    this.settlementAccountName = '',
    this.settlementAccountQuality,
    this.eventType,
    this.excluded = false,
    this.reimbursable = false,
    this.bookUuids,
    this.bookNames,
  });
}

class FeimiaoImportResult {
  final int inserted;
  final int skippedDuplicates;
  final int refundsAttached;

  const FeimiaoImportResult({
    required this.inserted,
    required this.skippedDuplicates,
    required this.refundsAttached,
  });
}

class FeimiaoAssetImportResult {
  final int assets;
  final int receivables;
  final int events;
  final int usages;
  final int valuations;
  final int links;
  final int recoveries;
  final int snapshots;
  final int liabilities;
  final int unresolvedTransactionLinks;
  final int unresolvedSavingsGoalLinks;
  final int rejectedLinks;

  const FeimiaoAssetImportResult({
    required this.assets,
    this.receivables = 0,
    required this.events,
    this.usages = 0,
    required this.valuations,
    required this.links,
    this.recoveries = 0,
    this.snapshots = 0,
    this.liabilities = 0,
    this.unresolvedTransactionLinks = 0,
    this.unresolvedSavingsGoalLinks = 0,
    this.rejectedLinks = 0,
  });

  int get total =>
      assets +
      receivables +
      events +
      usages +
      valuations +
      links +
      recoveries +
      snapshots +
      liabilities;
}

class ImportBatchResult {
  final int inserted;
  final int skippedDuplicates;
  final int refundsAttached;
  final int unresolvedRefunds;

  const ImportBatchResult({
    required this.inserted,
    required this.skippedDuplicates,
    required this.refundsAttached,
    this.unresolvedRefunds = 0,
  });
}

class SavingsGoalEntity {
  final int id;
  final String uuid;
  final String name;
  final String emoji;
  final String targetStr;
  final String savedStr;
  final int createdMs;
  final int updatedMs;

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
    required this.uuid,
    required this.name,
    this.emoji = '🐷',
    required this.targetStr,
    this.savedStr = '0',
    this.createdMs = 0,
    this.updatedMs = 0,
  });

  factory SavingsGoalEntity.fromMap(Map<String, Object?> m) =>
      SavingsGoalEntity(
        id: m['id'] as int,
        uuid: m['uuid'] as String? ?? '',
        name: m['name'] as String,
        emoji: m['emoji'] as String? ?? '🐷',
        targetStr: m['target_amount'] as String? ?? '0',
        savedStr: m['saved_amount'] as String? ?? '0',
        createdMs: m['created_ms'] as int? ?? 0,
        updatedMs: m['updated_ms'] as int? ?? 0,
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
