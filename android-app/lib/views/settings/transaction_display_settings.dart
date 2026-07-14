import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/cat_svg_icon.dart';
import '../../core/models/transaction_card_display.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/transaction_time.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/settings_ui.dart';
import '../../widgets/sliding_segment.dart';
import '../common/app_sheet.dart';

Future<void> showTransactionDisplaySettings(BuildContext context) =>
    showBlurSheet<void>(
      context,
      child: const _TransactionDisplaySettingsSheet(),
    );

class _TransactionDisplaySettingsSheet extends StatelessWidget {
  const _TransactionDisplaySettingsSheet();

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final maxHeight = MediaQuery.sizeOf(context).height * 0.86;
    final followsCards =
        repo.userMessageBubbleStyle == UserMessageBubbleStyle.followCardOpacity;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetHeader(
                title: '账单与聊天显示',
                onClose: () => Navigator.pop(context),
              ),
              const SettingsSectionLabel('账单卡片'),
              _TransactionPreview(mode: repo.transactionCardDisplayMode),
              SettingsGroup(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: SlidingSegment<TransactionCardDisplayMode>(
                      items: const [
                        (TransactionCardDisplayMode.contentFirst, '内容优先'),
                        (TransactionCardDisplayMode.categoryFirst, '分类优先'),
                      ],
                      value: repo.transactionCardDisplayMode,
                      onChanged: (mode) => unawaited(
                        repo.setTransactionCardDisplayMode(mode),
                      ),
                    ),
                  ),
                ],
              ),
              const SettingsSectionLabel('用户消息气泡'),
              _UserBubblePreview(style: repo.userMessageBubbleStyle),
              SettingsGroup(
                children: [
                  SettingsRow(
                    leading: const Icon(CupertinoIcons.square_stack_3d_up),
                    title: '跟随卡片透明度',
                    subtitle:
                        followsCards ? '当前跟随主题中的卡片透明度' : '已使用固定灰底，不受卡片透明度影响',
                    trailing: AppSwitch(
                      value: followsCards,
                      onChanged: (enabled) => unawaited(
                        repo.setUserMessageBubbleStyle(
                          enabled
                              ? UserMessageBubbleStyle.followCardOpacity
                              : UserMessageBubbleStyle.fixedGray,
                        ),
                      ),
                    ),
                    onTap: () => unawaited(
                      repo.setUserMessageBubbleStyle(
                        followsCards
                            ? UserMessageBubbleStyle.fixedGray
                            : UserMessageBubbleStyle.followCardOpacity,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionPreview extends StatelessWidget {
  final TransactionCardDisplayMode mode;

  const _TransactionPreview({required this.mode});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = resolveTransactionCardText(
      mode: mode,
      kind: TransactionKind.expense,
      note: '原神充值',
      categoryName: '虚拟充值',
    );
    final detail = joinTransactionCardDetails([
      transactionCardTimeLabel(
        DateTime(2026, 7, 14, 21, 8),
        dateGrouped: true,
        precision: TransactionTimePrecision.exact,
      ),
      text.secondary,
    ]);
    return Container(
      key: const ValueKey('transaction-display-preview'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline(scheme)),
      ),
      child: Row(
        children: [
          const CatIcon(
            categoryKey: 'subscription',
            emoji: '🎮',
            size: 36,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text.title,
                  key: const ValueKey('transaction-display-preview-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  key: const ValueKey('transaction-display-preview-detail'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '-¥648.00',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Nunito',
                ),
          ),
        ],
      ),
    );
  }
}

class _UserBubblePreview extends StatelessWidget {
  final UserMessageBubbleStyle style;

  const _UserBubblePreview({required this.style});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = style == UserMessageBubbleStyle.followCardOpacity
        ? AppColors.card(scheme)
        : scheme.surfaceContainerHighest;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline(scheme)),
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          key: const ValueKey('user-bubble-style-preview'),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: const Text('原神充值 648 元', style: TextStyle(fontSize: 14)),
        ),
      ),
    );
  }
}
