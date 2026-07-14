import 'transaction_kind.dart';
import '../transaction_time.dart';

enum TransactionCardDisplayMode {
  contentFirst,
  categoryFirst,
}

extension TransactionCardDisplayModeX on TransactionCardDisplayMode {
  String get storageKey => switch (this) {
        TransactionCardDisplayMode.contentFirst => 'content_first',
        TransactionCardDisplayMode.categoryFirst => 'category_first',
      };

  String get label => switch (this) {
        TransactionCardDisplayMode.contentFirst => '内容优先',
        TransactionCardDisplayMode.categoryFirst => '分类优先',
      };

  static TransactionCardDisplayMode fromStorage(String? value) {
    for (final mode in TransactionCardDisplayMode.values) {
      if (mode.storageKey == value) return mode;
    }
    return TransactionCardDisplayMode.contentFirst;
  }
}

enum UserMessageBubbleStyle {
  followCardOpacity,
  fixedGray,
}

extension UserMessageBubbleStyleX on UserMessageBubbleStyle {
  String get storageKey => switch (this) {
        UserMessageBubbleStyle.followCardOpacity => 'follow_card_opacity',
        UserMessageBubbleStyle.fixedGray => 'fixed_gray',
      };

  String get label => switch (this) {
        UserMessageBubbleStyle.followCardOpacity => '跟随卡片透明度',
        UserMessageBubbleStyle.fixedGray => '固定灰底',
      };

  static UserMessageBubbleStyle fromStorage(String? value) {
    for (final style in UserMessageBubbleStyle.values) {
      if (style.storageKey == value) return style;
    }
    return UserMessageBubbleStyle.followCardOpacity;
  }
}

class TransactionCardText {
  final String title;
  final String secondary;

  const TransactionCardText({required this.title, this.secondary = ''});
}

TransactionCardText resolveTransactionCardText({
  required TransactionCardDisplayMode mode,
  required TransactionKind kind,
  required String note,
  required String categoryName,
  String accountName = '',
  String toAccountName = '',
}) {
  final cleanNote = note.trim();
  final cleanCategory = categoryName.trim().isNotEmpty
      ? categoryName.trim()
      : kind == TransactionKind.income
          ? '其他收入'
          : '未分类';

  if (kind == TransactionKind.transfer) {
    final from = accountName.trim();
    final to = toAccountName.trim();
    final route = from.isNotEmpty && to.isNotEmpty
        ? '$from → $to'
        : (from.isNotEmpty ? from : (to.isNotEmpty ? to : '转账'));
    return TransactionCardText(title: route, secondary: cleanNote);
  }

  if (mode == TransactionCardDisplayMode.contentFirst && cleanNote.isNotEmpty) {
    return TransactionCardText(title: cleanNote, secondary: cleanCategory);
  }
  return TransactionCardText(
    title: cleanCategory,
    secondary: cleanNote,
  );
}

String transactionCardTimeLabel(
  DateTime date, {
  required bool dateGrouped,
  required TransactionTimePrecision precision,
}) {
  String two(int value) => value.toString().padLeft(2, '0');
  final showClock = shouldShowTransactionClock(date, precision);
  final time = '${two(date.hour)}:${two(date.minute)}';
  if (dateGrouped) return showClock ? time : '';
  final day = '${date.year}/${two(date.month)}/${two(date.day)}';
  return showClock ? '$day $time' : day;
}

String joinTransactionCardDetails(Iterable<String?> parts) => parts
    .map((part) => part?.trim() ?? '')
    .where((part) => part.isNotEmpty)
    .join(' · ');
