/// 查账问题中的分类范围解析。
///
/// 这是本地确定性规则：模型只负责表达，不负责决定“购物”到底包含哪些
/// 账目。一级分类命中时会展开它的所有子分类，避免把分类小计算成全库总额。
class AiCategoryOption {
  final int id;
  final String key;
  final String nameZh;
  final String nameEn;
  final String? parentKey;

  const AiCategoryOption({
    required this.id,
    required this.key,
    required this.nameZh,
    required this.nameEn,
    this.parentKey,
  });

  bool get isTopLevel => parentKey == null;
}

class AiCategoryScope {
  final Set<int> categoryIds;
  final Set<String> categoryKeys;
  final List<String> labels;

  const AiCategoryScope({
    required this.categoryIds,
    required this.categoryKeys,
    required this.labels,
  });

  bool matches({int? categoryId, String? categoryKey}) {
    return (categoryId != null && categoryIds.contains(categoryId)) ||
        (categoryKey != null && categoryKeys.contains(categoryKey));
  }
}

const _genericCategoryWords = <String>{
  '消费',
  '支出',
  '收入',
  '金额',
  '花费',
  '开销',
  '费用',
  '分类',
  '类别',
  '预算',
  '总额',
  'total',
  'expense',
  'income',
};

String _normalizeCategoryQueryText(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]'), '');

bool _isChineseOnly(String value) =>
    value.isNotEmpty && !RegExp(r'[^\u4e00-\u9fff]').hasMatch(value);

String _trimCategorySuffix(String value) {
  var result = value;
  const suffixes = ['消费', '支出', '收入', '费用', '开销', '类别', '分类'];
  for (final suffix in suffixes) {
    if (result.length > suffix.length + 1 && result.endsWith(suffix)) {
      result = result.substring(0, result.length - suffix.length);
      break;
    }
  }
  return result;
}

Set<String> _categoryAliases(AiCategoryOption option) {
  final aliases = <String>{};
  void add(String raw) {
    final value = _normalizeCategoryQueryText(raw);
    if (value.length < 2 || _genericCategoryWords.contains(value)) return;
    aliases.add(value);
    if (_isChineseOnly(value)) {
      final trimmed = _trimCategorySuffix(value);
      if (trimmed.length >= 2 && !_genericCategoryWords.contains(trimmed)) {
        aliases.add(trimmed);
      }
      // 允许用户说“购物”匹配“购物消费”、说“餐饮”匹配“食品餐饮”，
      // 同时保留完整名称优先，不依赖预置分类的固定中文文案。
      for (var length = 2; length <= value.length; length++) {
        for (var start = 0; start + length <= value.length; start++) {
          final part = value.substring(start, start + length);
          if (!_genericCategoryWords.contains(part)) aliases.add(part);
        }
      }
    }
  }

  add(option.nameZh);
  add(option.nameEn);
  add(option.key);
  return aliases;
}

/// 从自然语言问题中解析一个或多个支出分类范围。
///
/// 未命中明确分类时返回 null，调用方应保持原来的全量查询语义；不要把
/// “消费多少”“总支出”这类通用词误当成某个分类。
AiCategoryScope? resolveAiCategoryScope(
  String question,
  Iterable<AiCategoryOption> options,
) {
  final normalizedQuestion = _normalizeCategoryQueryText(question);
  if (normalizedQuestion.isEmpty) return null;

  final all = options.toList(growable: false);
  final matched = <AiCategoryOption>[];
  for (final option in all) {
    if (_categoryAliases(option)
        .any((alias) => normalizedQuestion.contains(alias))) {
      matched.add(option);
    }
  }
  if (matched.isEmpty) return null;

  final selected = <AiCategoryOption>{};
  final byParent = <String, List<AiCategoryOption>>{};
  for (final option in all) {
    final parent = option.parentKey;
    if (parent != null) {
      byParent.putIfAbsent(parent, () => []).add(option);
    }
  }
  void addWithChildren(AiCategoryOption option) {
    if (!selected.add(option)) return;
    for (final child in byParent[option.key] ?? const <AiCategoryOption>[]) {
      addWithChildren(child);
    }
  }

  for (final option in matched) {
    addWithChildren(option);
  }
  final labels = <String>[];
  for (final option in matched) {
    if (!labels.contains(option.nameZh)) labels.add(option.nameZh);
  }
  return AiCategoryScope(
    categoryIds: {for (final option in selected) option.id},
    categoryKeys: {for (final option in selected) option.key},
    labels: List.unmodifiable(labels),
  );
}
