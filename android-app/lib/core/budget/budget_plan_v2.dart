import 'dart:convert';

// 旧预算 V2 只剩这一个类型：合并分类时还要改写旧表 budget_plans 里的
// expense_scope_json（旧表保留不删，见 docs/08 §6.12）。其余 V2 计划、
// 周期、固定支出解析已在预算规则第三批删除。

/// The category/tag filter attached to a one-off special tracking plan.
///
/// Category keys refer to stable top-level expense category keys. A family
/// matches when either its category or any of its tags is selected. The JSON
/// representation is canonical so backups and future sync do not churn when
/// callers provide the same values in a different order.
class BudgetExpenseScopeV2 {
  static const empty = BudgetExpenseScopeV2._(
    categoryKeys: <String>{},
    tagIds: <int>{},
  );

  final Set<String> categoryKeys;
  final Set<int> tagIds;

  const BudgetExpenseScopeV2._({
    required this.categoryKeys,
    required this.tagIds,
  });

  factory BudgetExpenseScopeV2({
    Iterable<String> categoryKeys = const [],
    Iterable<int> tagIds = const [],
  }) {
    final normalizedCategories = categoryKeys
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final normalizedTagIds = tagIds.toSet();
    if (normalizedTagIds.any((value) => value <= 0)) {
      throw ArgumentError('Budget scope tag IDs must be positive.');
    }
    if (normalizedCategories.isEmpty && normalizedTagIds.isEmpty) {
      return empty;
    }
    return BudgetExpenseScopeV2._(
      categoryKeys: Set.unmodifiable(normalizedCategories),
      tagIds: Set.unmodifiable(normalizedTagIds),
    );
  }

  factory BudgetExpenseScopeV2.fromJson(Map<String, Object?> json) {
    final match = json['match']?.toString() ?? 'any';
    if (match != 'any') {
      throw const FormatException('Budget scope only supports match:any.');
    }
    final rawCategories = json['category_keys'];
    final rawTagIds = json['tag_ids'];
    if (rawCategories != null && rawCategories is! List) {
      throw const FormatException('category_keys must be a JSON array.');
    }
    if (rawTagIds != null && rawTagIds is! List) {
      throw const FormatException('tag_ids must be a JSON array.');
    }
    final categories = <String>[];
    for (final value in (rawCategories as List?) ?? const []) {
      if (value is! String) {
        throw const FormatException('Category keys must be strings.');
      }
      categories.add(value);
    }
    final tags = <int>[];
    for (final value in (rawTagIds as List?) ?? const []) {
      final parsed = value is int ? value : int.tryParse(value.toString());
      if (parsed == null || parsed <= 0) {
        throw const FormatException('Tag IDs must be positive integers.');
      }
      tags.add(parsed);
    }
    return BudgetExpenseScopeV2(categoryKeys: categories, tagIds: tags);
  }

  factory BudgetExpenseScopeV2.fromJsonString(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return empty;
    final decoded = jsonDecode(value);
    if (decoded is! Map) {
      throw const FormatException('Budget scope must be a JSON object.');
    }
    return BudgetExpenseScopeV2.fromJson(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  bool get isEmpty => categoryKeys.isEmpty && tagIds.isEmpty;
  bool get isNotEmpty => !isEmpty;

  bool matches({
    String categoryKey = '',
    Iterable<int> familyTagIds = const [],
  }) {
    final normalizedCategory = categoryKey.trim();
    if (normalizedCategory.isNotEmpty &&
        categoryKeys.contains(normalizedCategory)) {
      return true;
    }
    return familyTagIds.any(tagIds.contains);
  }

  Map<String, Object> toJson() {
    final categories = categoryKeys.toList()..sort();
    final tags = tagIds.toList()..sort();
    return {
      'category_keys': categories,
      'tag_ids': tags,
      'match': 'any',
    };
  }

  String toJsonString() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BudgetExpenseScopeV2 &&
          _setsEqual(categoryKeys, other.categoryKeys) &&
          _setsEqual(tagIds, other.tagIds);

  @override
  int get hashCode {
    final categories = categoryKeys.toList()..sort();
    final tags = tagIds.toList()..sort();
    return Object.hash(Object.hashAll(categories), Object.hashAll(tags));
  }

  static bool _setsEqual<T>(Set<T> left, Set<T> right) =>
      left.length == right.length && left.containsAll(right);
}
