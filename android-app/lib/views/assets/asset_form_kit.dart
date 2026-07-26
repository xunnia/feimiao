// 资产模块共用表单基件：下拉/日期字段/提示框/明细区块等小零件与金额、日期工具函数。
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../core/assets/asset_enhancements.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_picker_field.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/settings_ui.dart';

Decimal parseAssetDecimalInput(String raw) {
  final normalized = raw.trim().replaceAll(',', '').replaceAll('¥', '');
  if (normalized.isEmpty) return Decimal.zero;
  return Decimal.tryParse(normalized) ?? Decimal.zero;
}

bool assetDecimalInputValid(String raw, {bool required = false}) {
  final normalized = raw.trim().replaceAll(',', '').replaceAll('¥', '');
  if (normalized.isEmpty) return !required;
  return Decimal.tryParse(normalized) != null;
}

String assetDateText(DateTime? date) {
  if (date == null) return '未填写';
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

DateTime assetToday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DateTime assetCalendarDay(DateTime date) =>
    DateTime(date.year, date.month, date.day);

String assetShortDateTime(int milliseconds) {
  final value = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  return '${value.month}/${value.day} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

/// 中文混排文案里只给数字子串套 Nunito（UI 标准：Nunito 只准用于纯数字/金额）。
TextSpan digitAwareAmountSpan(String text, TextStyle base) {
  final spans = <TextSpan>[];
  var cursor = 0;
  for (final match in RegExp(r'[0-9][0-9,.]*').allMatches(text)) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start)));
    }
    spans.add(TextSpan(
      text: text.substring(match.start, match.end),
      style: base.copyWith(fontFamily: 'Nunito'),
    ));
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor)));
  }
  return TextSpan(style: base, children: spans);
}

String assetReminderDetailText(
  AssetReminderState reminder, {
  required String upcomingLabel,
  required String dueTodayLabel,
  required String expiredLabel,
  required String inactiveLabel,
}) {
  return switch (reminder.status) {
    AssetReminderStatus.upcoming => '$upcomingLabel ${reminder.daysUntilDue} 天',
    AssetReminderStatus.dueToday => dueTodayLabel,
    AssetReminderStatus.expired =>
      '$expiredLabel ${reminder.daysUntilDue!.abs()} 天',
    AssetReminderStatus.none => reminder.daysUntilDue == null
        ? '未填写'
        : '$upcomingLabel ${reminder.daysUntilDue} 天',
    AssetReminderStatus.inactive => inactiveLabel,
  };
}

class AssetEnumDropdown<T> extends StatelessWidget {
  final T value;
  final List<T> values;
  final String Function(T value) labelOf;
  final String hint;
  final ValueChanged<T> onChanged;

  const AssetEnumDropdown({
    super.key,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppPickerField(
      key: ValueKey(value),
      text: labelOf(value),
      hint: hint,
      onTap: (menuCtx) => showPickerMenu(
        menuCtx,
        [
          for (final item in values)
            IosMenuItem(
              label: labelOf(item),
              icon: Icons.tune_rounded,
              selected: item == value,
              onTap: () => onChanged(item),
            ),
        ],
      ),
    );
  }
}

class AssetAccountDropdown extends StatelessWidget {
  final int? value;
  final List<AccountEntity> accounts;
  final String hint;
  final ValueChanged<int?> onChanged;

  const AssetAccountDropdown({
    super.key,
    required this.value,
    required this.accounts,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected =
        accounts.where((account) => account.id == value).firstOrNull;
    return AppPickerField(
      key: ValueKey(value),
      text: selected?.name,
      hint: hint,
      onTap: (menuCtx) => showPickerMenu(
        menuCtx,
        [
          for (final account in accounts)
            IosMenuItem(
              label: account.name,
              icon: Icons.account_balance_wallet_outlined,
              selected: account.id == value,
              onTap: () => onChanged(account.id),
            ),
        ],
      ),
    );
  }
}

class AssetNullableDateField extends StatelessWidget {
  final Key fieldKey;
  final DateTime? value;
  final String emptyText;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const AssetNullableDateField({
    super.key,
    required this.fieldKey,
    required this.value,
    required this.emptyText,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AppPickerField(
            key: fieldKey,
            text: value == null ? null : assetDateText(value),
            hint: emptyText,
            onTap: (_) => onTap(),
          ),
        ),
        if (onClear != null) ...[
          const SizedBox(width: 8),
          Tooltip(
            message: '清除日期',
            child: AppCircleButton(
              icon: Icons.close,
              size: 38,
              iconSize: 18,
              onPressed: onClear,
            ),
          ),
        ],
      ],
    );
  }
}

class AssetHintBox extends StatelessWidget {
  final String text;
  const AssetHintBox({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.iconCircleFill(scheme),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: AppType.secondary(scheme),
      ),
    );
  }
}

class AssetDetailSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const AssetDetailSection(
      {super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: appCardDecoration(scheme),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) appCardDivider(scheme),
            children[i],
          ],
        ],
      ),
    );
  }
}

class AssetDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const AssetDetailRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: AppType.secondary(scheme),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppType.trailingValue(scheme),
            ),
          ),
        ],
      ),
    );
  }
}

class AssetActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const AssetActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: onTap == null ? 0.42 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.card(scheme),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.hairline(scheme)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: AppTextColor.secondary(scheme)),
              const SizedBox(height: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w400,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AssetMenuFilterButton<T> extends StatelessWidget {
  final T value;
  final List<T> values;
  final String Function(T value) labelOf;
  final IconData Function(T value) iconOf;
  final ValueChanged<T> onChanged;

  const AssetMenuFilterButton({
    super.key,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.iconOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (menuContext) => AppPillButton(
        label: labelOf(value),
        onPressed: () => showIosMenu(
          menuContext,
          [
            for (final item in values)
              IosMenuItem(
                label: labelOf(item),
                icon: iconOf(item),
                selected: item == value,
                onTap: () => onChanged(item),
              ),
          ],
        ),
      ),
    );
  }
}
