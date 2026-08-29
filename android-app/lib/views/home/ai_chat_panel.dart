import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:decimal/decimal.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RendererBinding;
import 'package:flutter/physics.dart' show SpringDescription;
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, SystemChannels;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ai/chat_intent.dart';
import '../../core/ai/ai_provider_config.dart';
import '../../core/ai/ai_attachment_pipeline.dart';
import '../../core/ai/ai_context.dart';
import '../../core/ai/ai_run.dart';
import '../../core/ai/ai_tool_registry.dart';
import '../../core/ai/ai_extensions.dart';
import '../../core/ai/chat_session.dart';
import '../../core/ai/category_query.dart';
import '../../core/ai/llm_entry_parser.dart';
import '../../core/ai/llm_query.dart';
import '../../core/ai/llm_query_v2.dart';
import '../../core/ai/web_search.dart';
import '../../core/ai/bill_categorizer.dart';
import '../../core/ai/merchant_category.dart';
import '../../core/ai/query_range.dart';
import '../../core/budget/budget_window_resolver.dart';
import '../../core/ai/refund_matcher.dart';
import '../../core/ai/report_execution_fence.dart';
import '../../core/ai/report_job_runtime.dart';
import '../../core/ai/report_task_scheduler.dart';
import '../../core/ai/smart_suggestions.dart';
import '../../core/ai/smart_tags.dart';
import '../../core/meal_time.dart';
import '../../core/spending_anomaly.dart';
import '../../core/ai/natural_language_entry_parser.dart';
import '../../core/haptics.dart';
import '../../core/models/cat_svg_icon.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/transaction_card_display.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/meow_insights.dart';
import '../../core/media/chat_attachment.dart';
import '../../core/money_format.dart';
import '../../core/statistics/metric_contract.dart';
import '../../core/statistics/statistics_engine.dart';
import '../../core/transaction_time.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_line_icon.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/glass.dart';
import '../../widgets/glass_input.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/mascot.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/refund_settlement_sheet.dart';
import '../../widgets/settings_ui.dart';
import '../common/category_picker_sheet.dart';
import '../common/app_sheet.dart';
import '../reports/report_views.dart';
import '../settings/ai_privacy_consent.dart';
import 'chat_add_sheet.dart';

const Duration kAiBackgroundResponseNoticeDelay = Duration(seconds: 15);
const double kAiResponseActionTouchExtent = 36;
const double kAiResponseActionIconExtent = 17.2;
// The transport has its own per-socket idle limits, but OAuth refresh, web
// search preparation and attachment decoding happen before that transport is
// opened. Keep the UI from waiting forever when one of those stages wedges.
const Duration _kAiChatRequestTimeout = Duration(seconds: 90);
const Duration _kAiChatPersistenceTimeout = Duration(seconds: 8);
const Duration _kAiForegroundThinkingTimeout = Duration(seconds: 120);
const int _kAiContextTokenBudget = 12000;
// Final ownership guard for work that happens before/after the transport
// (OAuth refresh, search preparation, attachment decoding and persistence).
// A stalled future must never leave the visible flow locked forever.
const Duration _kAiFlowTimeout = Duration(seconds: 120);
// A report may legitimately continue in WorkManager after the foreground
// panel is dismissed, but the foreground UI still needs a finite hand-off
// point.  Without this cap a queued worker (offline, quota-limited, or stuck
// during startup) leaves the only visible thinking row alive indefinitely.
const Duration _kAiBackgroundThinkingTimeout = Duration(seconds: 120);
// The selector labels are intentionally compact: one 15px whitespace glyph
// (about 4dp at the app font) separates the model from the effort value.
const double _aiChatSelectorFontSize = 15;
const double _aiChatSelectionGap = 4;

/// Maximum visual overscroll for the chat history. The content still springs
/// back to the real edge on release, but a long upward pull cannot expose a
/// full blank screen below a short reply.
const double kAiChatMaxOverscroll = 88;

enum _InputSelection { model, effort }

/// Shows the same Claude-style floating selector used by the live Chats input
/// bar. Settings pages use this entry point too, so model and effort selection
/// do not drift into a second visual implementation.
void showAiFloatingPopup({
  required BuildContext context,
  required BuildContext anchor,
  required double width,
  required Widget child,
  VoidCallback? onClosed,
}) {
  final box = anchor.findRenderObject() as RenderBox?;
  if (box == null) return;
  final pos = box.localToGlobal(Offset.zero);
  final anchorRect = pos & box.size;
  final anchorTop = pos.dy;
  final anchorLeft = pos.dx;
  // Resolve the viewport from the actual FlutterView rather than a potentially
  // stale route MediaQuery. During a surface-size/rotation transition the
  // latter can still report the test/default 800×600 view while the rendered
  // device is 390×844, placing the selector partly outside the hit-test root.
  final view = View.of(anchor);
  final renderViews = RendererBinding.instance.renderViews;
  final screen = renderViews.isEmpty
      ? Size(
          view.physicalSize.width / view.devicePixelRatio,
          view.physicalSize.height / view.devicePixelRatio,
        )
      : renderViews.first.size;
  const margin = 8.0;

  double left = anchorLeft;
  if (left + width > screen.width - margin) {
    left = screen.width - margin - width;
  }
  if (left < margin) left = margin;

  final popup = showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, __) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return Stack(
        children: [
          Positioned.fill(
            child: FadeTransition(
              opacity: anim,
              child: AppMenuScrim(
                highlightRect: anchorRect.inflate(2),
                radius: min(12, anchorRect.shortestSide / 2 + 4),
              ),
            ),
          ),
          Positioned(
            left: left,
            top: anchorTop - 8,
            child: FractionalTranslation(
              translation: const Offset(0, -1),
              child: FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                  alignment: Alignment.bottomLeft,
                  scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: width,
                      maxHeight: screen.height * 0.6,
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
  if (onClosed != null) unawaited(popup.whenComplete(onClosed));
}

/// Public bridge for settings pages to use the production model list card.
void showAiModelPickerPopup({
  required BuildContext context,
  required BuildContext anchor,
  required List<AiModelOption> options,
  required String currentKey,
  required ValueChanged<AiModelOption> onSelected,
  VoidCallback? onClosed,
}) {
  showAiFloatingPopup(
    context: context,
    anchor: anchor,
    width: 195,
    onClosed: onClosed,
    child: _ModelMenuCard(
      options: options,
      currentKey: currentKey,
      onSelected: onSelected,
    ),
  );
}

/// Public bridge for settings pages to use the production effort slider card.
void showAiEffortPickerPopup({
  required BuildContext context,
  required BuildContext anchor,
  required AiReasoningEffort currentEffort,
  required ValueChanged<AiReasoningEffort> onChanged,
  VoidCallback? onClosed,
}) {
  showAiFloatingPopup(
    context: context,
    anchor: anchor,
    width: 222,
    onClosed: onClosed,
    child: _EffortPopupCard(
      currentEffort: currentEffort,
      onChanged: onChanged,
    ),
  );
}

/// Chats use iOS-style bouncing, but a short capped overscroll.  The chat
/// history is allowed to move just enough to show the spring-back gesture;
/// it must not expose a full screen of blank space after the final message.
class _ChatBouncingScrollPhysics extends BouncingScrollPhysics {
  const _ChatBouncingScrollPhysics({
    super.parent = const AlwaysScrollableScrollPhysics(),
  });

  @override
  _ChatBouncingScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _ChatBouncingScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    final lower = position.minScrollExtent - kAiChatMaxOverscroll;
    final upper = position.maxScrollExtent + kAiChatMaxOverscroll;
    if (value < lower) return value - lower;
    if (value > upper) return value - upper;
    return 0;
  }

  @override
  double frictionFactor(double overscrollFraction) =>
      (0.24 * pow(1 - overscrollFraction.clamp(0.0, 1.0), 2)).toDouble();

  @override
  SpringDescription get spring => const SpringDescription(
        mass: 0.72,
        stiffness: 155,
        damping: 14.5,
      );
}

@visibleForTesting
int aiTypewriterLength(String text) => text.characters.length;

@visibleForTesting
String aiTypewriterPrefix(String text, int graphemeCount) {
  final graphemes = text.characters;
  final count = graphemeCount <= 0
      ? 0
      : graphemeCount >= graphemes.length
          ? graphemes.length
          : graphemeCount;
  return graphemes.take(count).join();
}

String aiThinkingStatusText({
  required Duration elapsed,
  required bool canContinueInBackground,
}) {
  if (elapsed.compareTo(kAiBackgroundResponseNoticeDelay) < 0) {
    return '正在思考';
  }
  return canContinueInBackground ? '喵会在后台继续处理，完成后会显示在这里。' : '喵还在思考，完成后会显示在这里。';
}

@visibleForTesting
double sentAttachmentTileWidth(double availableWidth, int attachmentCount) {
  if (attachmentCount <= 1) return availableWidth;
  final visibleCount = min(attachmentCount, 3);
  return (availableWidth - (visibleCount - 1) * 6) / visibleCount;
}

/// GPT/Claude 的三图消息使用内容区内等宽的方形缩略卡。三张图片共享
/// 同一行，保留聊天内容两侧的小边距和卡片之间的细间距，不把原图拉成
/// 竖长卡片，也不越过聊天视口的内容边界。
@visibleForTesting
double sentAttachmentTileHeight(double availableWidth, int attachmentCount) {
  final tileWidth = sentAttachmentTileWidth(availableWidth, attachmentCount);
  if (attachmentCount == 3) return tileWidth;
  return attachmentCount <= 1 ? min(availableWidth, 238) : tileWidth;
}

/// Draft attachments reserve exactly three equal image slots in the composer.
/// The fourth item starts outside the viewport and is reached by horizontal
/// scrolling instead of leaking a distracting partial tile into the first page.
@visibleForTesting
double draftAttachmentTileWidth(double availableWidth) =>
    max(0, (availableWidth - 16) / 3);

/// Returns only the incoming draft attachments that fit the per-message
/// budgets after [existing] has already been added.  Both the photo picker and
/// the generic file picker use this boundary, so an image chosen as a file
/// cannot bypass the three-image limit by being added in a later round.
@visibleForTesting
List<ChatAttachment> fitDraftAttachments(
  Iterable<ChatAttachment> existing,
  Iterable<ChatAttachment> incoming,
) {
  var remainingImages = AiAttachmentPipeline.maxImages -
      existing.where((attachment) => attachment.isImage).length;
  var remainingFiles = AiAttachmentPipeline.maxFiles -
      existing.where((attachment) => !attachment.isImage).length;
  final accepted = <ChatAttachment>[];
  for (final attachment in incoming) {
    if (attachment.isImage) {
      if (remainingImages <= 0) continue;
      remainingImages--;
    } else {
      if (remainingFiles <= 0) continue;
      remainingFiles--;
    }
    accepted.add(attachment);
  }
  return List.unmodifiable(accepted);
}

@visibleForTesting
bool aiThinkingShouldExpireForTest({
  required Duration elapsed,
  required bool canContinueInBackground,
}) =>
    elapsed.compareTo(
      canContinueInBackground
          ? _kAiBackgroundThinkingTimeout
          : _kAiForegroundThinkingTimeout,
    ) >=
    0;

@visibleForTesting
bool aiFlowKeepsBackgroundOwnershipForTest({
  required int flowId,
  required int? activeFlowId,
  required int? backgroundFlowId,
}) =>
    activeFlowId == flowId && backgroundFlowId == flowId;

@visibleForTesting
ScrollPhysics aiChatScrollPhysicsForTesting() =>
    const _ChatBouncingScrollPhysics();

/// 主页与普通 Chats 共用输入面板，但发送前的意图策略不同：主页的
/// 「AI 记账」入口必须把任何非空自然语言交给记账模型，不能先由本地
/// 规则把它判成闲聊或查账；普通 Chats 才使用本地意图分流。
@visibleForTesting
ChatIntentKind resolveAiPanelIntent({
  required bool recordOnly,
  required String text,
}) {
  if (recordOnly) return ChatIntentKind.record;
  return ChatIntent.classify(
    text,
    hasArabicAmount: NaturalLanguageEntryParser.extractAmount(text) != null,
  );
}

@visibleForTesting
String formatBudgetContextForAi(BudgetWindowResult result) {
  final start = result.viewWindow.startInclusive;
  final end = result.displayEndInclusive;
  final prefix = '【预算准确结果（直接引用，不要自行重算）】'
      '${start.year}-${start.month}-${start.day} 至 '
      '${end.year}-${end.month}-${end.day}：';
  final planned = result.plannedAmount;
  final spent = result.spentAmount;
  if (planned == null) {
    return '$prefix未设置可用预算，或预算计划存在冲突；'
        '不能把未知当作 0 元。';
  }
  if (spent == null) {
    return '$prefix预算 ${MoneyFormat.string(planned)}，'
        '支出结果当前不可用，不能推断剩余。';
  }
  final remaining = planned - spent;
  final foreign = result.excludedForeignTransactionCount > 0
      ? '；已排除 ${result.excludedForeignTransactionCount} 笔其他币种记录'
      : '';
  final daily = result.currentCycleDailyStatus;
  final asOfDay = DateUtils.dateOnly(result.query.asOf);
  final dailyUsable = result.viewWindow.contains(asOfDay) &&
      (result.dailyStatus == MetricStatus.available ||
          result.dailyStatus == MetricStatus.partial);
  final dailyText = daily == null || !dailyUsable
      ? ''
      : '；当前周期按预算平均今日可用 '
          '${MoneyFormat.string(daily.todayRemainingAllowanceAmount)}，'
          '剩余日均参考 '
          '${MoneyFormat.string(daily.plainBudgetDailyReferenceAmount)}';
  return '$prefix预算 ${MoneyFormat.string(planned)}，'
      '已用 ${MoneyFormat.string(spent)}，'
      '${remaining >= Decimal.zero ? '剩余' : '超出'} '
      '${MoneyFormat.string(remaining.abs())}$dailyText$foreign。'
      '当前旧预算缺少结构化固定承诺，以上是消费预算平均参考，不是安全可花现金。';
}

/// 打开「来记一笔吧」AI 聊天面板（就地弹出，替代旧的跳全屏方案）。
Future<void> showAiChatPanel(
  BuildContext context, {
  required VoidCallback onSwitchToManual,
  String? initialText,
  bool fullScreen = false,
  bool fastSwitch = false,
  bool replaceCurrent = false,
  bool recordOnly = true,
  String sessionId = ChatSession.recordId,
}) async {
  final route = PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: true,
    barrierLabel: '记账',
    barrierColor: Colors.black.withValues(alpha: 0.12),
    transitionDuration: Duration(milliseconds: fastSwitch ? 160 : 220),
    reverseTransitionDuration: Duration(milliseconds: fastSwitch ? 120 : 150),
    pageBuilder: (_, __, ___) => AiChatPanel(
      onSwitchToManual: onSwitchToManual,
      initialText: initialText,
      fullScreen: fullScreen,
      fastSwitch: fastSwitch,
      recordOnly: recordOnly,
      sessionId: sessionId,
    ),
    transitionsBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset(0, fastSwitch ? 0.018 : 0.045),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
  final navigator = Navigator.of(context, rootNavigator: true);
  if (replaceCurrent) {
    await navigator.pushReplacement<void, void>(route);
  } else {
    await navigator.push<void>(route);
  }
}

class _ChatMemoryState {
  _ChatMemoryState(this.databaseGeneration);

  final List<_Msg> history = <_Msg>[];
  final Set<int> rowIdsInMemory = <int>{};
  final Map<String, int> pendingSignatures = <String, int>{};
  bool restored = false;
  bool restoreInProgress = false;
  int epoch = 0;
  int databaseGeneration;

  void reset({required bool restored, int? databaseGeneration}) {
    history.clear();
    rowIdsInMemory.clear();
    pendingSignatures.clear();
    epoch++;
    this.restored = restored;
    restoreInProgress = false;
    if (databaseGeneration != null) {
      this.databaseGeneration = databaseGeneration;
    }
  }
}

/// 会话内存同时以仓库实例和会话 id 隔离。普通会话不能共用「记一记」的
/// 行 id、恢复锁或 pending 签名，否则会在切换后把历史串到另一张会话里。
final Map<AppRepository, Map<String, _ChatMemoryState>>
    _chatMemoryByRepository =
    Map<AppRepository, Map<String, _ChatMemoryState>>.identity();

_ChatMemoryState _chatMemoryFor(AppRepository repository, String sessionId) {
  final sessions = _chatMemoryByRepository.putIfAbsent(
    repository,
    () => <String, _ChatMemoryState>{},
  );
  final normalizedId =
      sessionId.trim().isEmpty ? ChatSession.recordId : sessionId.trim();
  final state = sessions.putIfAbsent(
    normalizedId,
    () => _ChatMemoryState(repository.databaseGeneration),
  );
  if (state.databaseGeneration != repository.databaseGeneration) {
    state.reset(
      restored: false,
      databaseGeneration: repository.databaseGeneration,
    );
  }
  return state;
}

String _chatSignature(String role, String text, String question) =>
    '$role\u0000$text\u0000$question';

/// 只清空一个会话的内存历史。数据库和内存必须使用同一个 session id，
/// 否则在「记一记」清空记录时会误伤其他 Chats，或在当前运行中重新显示旧消息。
void clearChatHistoryMemory(AppRepository repository, String sessionId) {
  final normalizedId =
      sessionId.trim().isEmpty ? ChatSession.recordId : sessionId.trim();
  _chatMemoryByRepository[repository]?[normalizedId]?.reset(restored: true);
}

@visibleForTesting
void resetChatHistoryForTesting() {
  for (final sessions in _chatMemoryByRepository.values) {
    for (final state in sessions.values) {
      state.reset(restored: false);
    }
  }
  _chatMemoryByRepository.clear();
}

@visibleForTesting
bool aiQuestionMatchesTransaction(
    String question, TransactionEntity transaction) {
  final rawQuestion = question.trim().toLowerCase();
  if (rawQuestion.isEmpty) return false;
  final normalizedQuestion = rawQuestion.replaceAll(
    RegExp(r'[^a-z0-9\u4e00-\u9fff]'),
    '',
  );
  if (normalizedQuestion.isEmpty) return false;

  final fields = <String>[
    transaction.note,
    transaction.categoryNameZh,
    transaction.categoryNameEn,
    transaction.categoryKey,
    transaction.accountName,
    transaction.toAccountName,
  ];
  final latinTokens = RegExp(r'[a-z0-9]{2,}')
      .allMatches(rawQuestion)
      .map((match) => match.group(0)!)
      .toSet();
  for (final rawField in fields) {
    final field = rawField.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9\u4e00-\u9fff]'),
          '',
        );
    if (field.length < 2) continue;
    if (normalizedQuestion.contains(field)) return true;
    if (latinTokens.any(field.contains)) return true;

    final chinese = field.replaceAll(RegExp(r'[^\u4e00-\u9fff]'), '');
    if (chinese.length < 3) continue;
    for (var i = 0; i <= chinese.length - 3; i++) {
      if (normalizedQuestion.contains(chinese.substring(i, i + 3))) {
        return true;
      }
    }
  }
  final amount = transaction.amount.abs().toString();
  return amount.length >= 2 && rawQuestion.contains(amount);
}

AiCategoryScope? _aiCategoryScopeFor(
  AppRepository repo,
  String question,
) {
  final byId = {for (final category in repo.categories) category.id: category};
  final options = [
    for (final category in repo.categories)
      if (category.kind == TransactionKind.expense)
        AiCategoryOption(
          id: category.id,
          key: category.key,
          nameZh: category.nameZh,
          nameEn: category.nameEn,
          parentKey:
              category.parentId == null ? null : byId[category.parentId!]?.key,
        ),
  ];
  return resolveAiCategoryScope(question, options);
}

// ─────────────────────────────────────────────────────────────────────────────
// Claude 风格操作图标：小号线性图标，刻意控制画面占比，避免在正文下方显得笨重。
// 用 flutter_svg 内嵌渲染，再用 colorFilter 着色；和 Material 图标完全不同的观感。
// ─────────────────────────────────────────────────────────────────────────────
const String _lucideHeader =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
    'stroke="#000" stroke-width="1.85" stroke-linecap="round" stroke-linejoin="round">';
const String _icCopy =
    '$_lucideHeader<rect width="14" height="14" x="8" y="8" rx="2"/>'
    '<path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/></svg>';
const String _icRetry =
    '$_lucideHeader<path d="M21 12a9 9 0 1 1-2.64-6.36L21 8.27"/>'
    '<path d="M21 3v5.27h-5.27"/></svg>';
const String _icThumbUp = '$_lucideHeader<path d="M7 10v12"/>'
    '<path d="M15 5.88 14 10h5.83a2 2 0 0 1 1.92 2.56l-2.33 8A2 2 0 0 1 17.5 22H4a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2h2.76a2 2 0 0 0 1.79-1.11L12 2a3.13 3.13 0 0 1 3 3.88Z"/></svg>';
const String _icThumbDown = '$_lucideHeader<path d="M17 14V2"/>'
    '<path d="M9 18.12 10 14H4.17a2 2 0 0 1-1.92-2.56l2.33-8A2 2 0 0 1 6.5 2H20a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-2.76a2 2 0 0 0-1.79 1.11L12 22a3.13 3.13 0 0 1-3-3.88Z"/></svg>';
// 选中态：实心（fill）。
const String _lucideHeaderFill =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000" '
    'stroke="#000" stroke-width="1.85" stroke-linecap="round" stroke-linejoin="round">';
const String _icThumbUpFill = '$_lucideHeaderFill<path d="M7 10v12"/>'
    '<path d="M15 5.88 14 10h5.83a2 2 0 0 1 1.92 2.56l-2.33 8A2 2 0 0 1 17.5 22H4a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2h2.76a2 2 0 0 0 1.79-1.11L12 2a3.13 3.13 0 0 1 3 3.88Z"/></svg>';
const String _icThumbDownFill = '$_lucideHeaderFill<path d="M17 14V2"/>'
    '<path d="M9 18.12 10 14H4.17a2 2 0 0 1-1.92-2.56l2.33-8A2 2 0 0 1 6.5 2H20a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-2.76a2 2 0 0 0-1.79 1.11L12 22a3.13 3.13 0 0 1-3-3.88Z"/></svg>';
const String _icShare = '$_lucideHeader<circle cx="18" cy="5" r="3"/>'
    '<circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/>'
    '<path d="m8.59 13.51 6.83 3.98M15.41 6.51 8.59 10.49"/></svg>';
const String _icMore =
    '$_lucideHeader<circle cx="12" cy="5" r="1" fill="#000"/>'
    '<circle cx="12" cy="12" r="1" fill="#000"/>'
    '<circle cx="12" cy="19" r="1" fill="#000"/></svg>';

/// 「来记一笔吧」聊天面板：一句话 → AI 解析 → 记账确认卡（可保存/撤销）。
/// 语音用键盘自带听写打到输入框即可，不再内置录音识别。
class AiChatPanel extends StatefulWidget {
  final VoidCallback onSwitchToManual;

  /// 预填到输入框的文字，不自动发送，供校对再发。
  final String? initialText;

  /// 全屏模式（抽屉「喵助手」入口用）：铺满屏幕、方角、无拖拽条，靠关闭按钮退出。
  final bool fullScreen;

  /// 从手动面板切过来时延后聚焦，避免键盘弹起和路由动画抢同一帧。
  final bool fastSwitch;

  /// 保活切换容器会隐藏/显示 AI 面板。隐藏时暂停重视觉效果和焦点，
  /// 重新显示后再恢复，避免切换帧同时跑键盘、模糊和猫猫动画。
  final bool active;

  /// 主页的一句话入口只负责记账；全屏「喵助手」才允许查账和闲聊。
  /// 这个开关必须由入口显式传入，不能再靠 fullScreen/fastSwitch 猜用途。
  final bool recordOnly;

  /// 所属 Chats 会话。主页和唯一「记一记」会话都使用 record；普通会话
  /// 有独立的消息、模型和思考强度。
  final String sessionId;

  /// Optional prefilled attachment draft. Production entry points currently
  /// start empty; this also lets widget tests exercise the real composer state
  /// without mocking the platform photo picker.
  final List<ChatAttachment> initialDraftAttachments;

  const AiChatPanel({
    super.key,
    required this.onSwitchToManual,
    this.initialText,
    this.fullScreen = false,
    this.fastSwitch = false,
    this.active = true,
    required this.recordOnly,
    this.sessionId = ChatSession.recordId,
    this.initialDraftAttachments = const [],
  });

  @override
  State<AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatPanelState extends State<AiChatPanel> with WidgetsBindingObserver {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();
  final GlobalKey _latestUserMsgKey = GlobalKey(
    debugLabel: 'latest-user-message',
  );
  late final AppRepository _chatRepository;
  late final _ChatMemoryState _chatMemory;
  late final List<_Msg> _msgs;
  _UserMsg? _latestUserMsg;
  _UserMsg? _selectedUserMsg;
  _UserMsg? _textSelectingUserMsg;
  OverlayEntry? _textSelectionScrim;
  late final List<ChatAttachment> _draftAttachments;
  bool _busy = false;
  // Every send/retry owns one monotonically increasing flow.  A timed-out or
  // detached request may still deliver a late callback; that callback must
  // never complete, mutate, or clear the thinking state belonging to a newer
  // flow.
  int _nextFlowId = 0;
  int? _activeFlowId;
  // A report handed to WorkManager outlives the synchronous send future. Keep
  // its flow ownership until the persisted job completes or the UI timeout
  // hands it off, otherwise the thinking ticker and completion poll stop with
  // the send callback and leave a permanent "正在思考" row.
  int? _backgroundFlowId;
  // Production sends always provide a flow id. Keep a one-shot nonce for
  // legacy/test callers that do not, so independent sends are not merged
  // while retries within one flow remain idempotent.
  int _unscopedRunNonce = 0;
  int? _thinkingTickerFlowId;
  final ValueNotifier<bool> _visualsReady = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _hasInputText = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _imeVisualsActive = ValueNotifier<bool>(false);
  Timer? _openSettleTimer;
  Timer? _focusTimer;
  Timer? _focusKeepAliveTimer;
  Timer? _focusStabilizeTimer;
  Timer? _latestUserAnchorTimer;
  Timer? _restoreTimer;
  Timer? _suggestionTimer;
  Timer? _thinkingStatusTimer;
  Timer? _reportPollTimer;
  Future<void>? _pendingUserPersistence;
  int? _observedReportJobId;
  int? _observedReportFlowId;
  bool _reportStatusSyncing = false;
  DateTime? _lastFocusRequestAt;
  DateTime? _inputFocusGuardUntil;
  double _lastKeyboardInset = 0;
  int _focusEpoch = 0;
  int _focusRepairAttempts = 0;
  bool _autoFocusPending = false;
  bool _inputSessionActive = false;
  _InputSelection? _activeInputSelection;
  bool _keyboardHadOpened = false;
  late bool _historyViewportReady;
  bool _historyRevealScheduled = false;
  late int _observedDatabaseGeneration;

  String get _sessionId {
    final value = widget.sessionId.trim();
    return value.isEmpty ? ChatSession.recordId : value;
  }

  List<_Msg> get _chatHistory => _chatMemory.history;
  Set<int> get _chatRowIdsInMemory => _chatMemory.rowIdsInMemory;
  Map<String, int> get _pendingChatSignatures => _chatMemory.pendingSignatures;
  int get _chatHistoryEpoch => _chatMemory.epoch;
  bool get _chatRestored => _chatMemory.restored;
  set _chatRestored(bool value) => _chatMemory.restored = value;
  bool get _chatRestoreInProgress => _chatMemory.restoreInProgress;
  set _chatRestoreInProgress(bool value) =>
      _chatMemory.restoreInProgress = value;

  int _beginFlow() {
    final id = ++_nextFlowId;
    _activeFlowId = id;
    return id;
  }

  bool _ownsFlow(int? flowId) => flowId == null || _activeFlowId == flowId;

  void _finishFlow(int flowId) {
    if (_backgroundFlowId == flowId) {
      _backgroundFlowId = null;
    }
    if (_activeFlowId == flowId) {
      _activeFlowId = null;
      if (_thinkingTickerFlowId == flowId) {
        _thinkingTickerFlowId = null;
      }
    }
  }

  bool _keepsBackgroundFlow(int flowId) =>
      aiFlowKeepsBackgroundOwnershipForTest(
        flowId: flowId,
        activeFlowId: _activeFlowId,
        backgroundFlowId: _backgroundFlowId,
      );

  Future<void> _handleUnexpectedFlowError(
    int flowId,
    Object error,
    StackTrace stackTrace,
  ) async {
    // A late failure from an older request is deliberately ignored.  The
    // current flow owns the only visible thinking row and is responsible for
    // its own completion.
    if (!_ownsFlow(flowId)) return;
    if (!_busy && _currentThinkingMsg(flowId) == null) return;
    // A transport/DB failure must release a previously handed-off flow too.
    // The background job may still finish and be picked up by polling, but it
    // no longer owns a foreground thinking row after this visible error.
    if (_backgroundFlowId == flowId) _backgroundFlowId = null;
    if (kDebugMode) {
      debugPrint('ai chat flow $flowId failed: $error');
      debugPrint('$stackTrace');
    }
    const prompt = '喵这次处理失败了，请检查网络后重试';
    _completeThinking(flowId: flowId);
    if (mounted) {
      setState(() {
        _msgs.add(_InfoMsg(prompt, error: true));
        _busy = false;
      });
      _scrollToLatestUserMessage();
    } else {
      _busy = false;
    }
    try {
      await _addChatMessage(
        _chatRepository,
        role: 'info_err',
        text: prompt,
      );
    } catch (_) {
      // A database failure must not turn a visible, recoverable UI error into
      // another unhandled exception.
    }
  }

  AiProviderConfig _chatConfig(AppRepository repository) =>
      repository.aiProviderConfigForChatSession(_sessionId).forChatStreaming();

  AiReasoningEffort _chatEffort(AppRepository repository) =>
      repository.chatReasoningEffortForSession(_sessionId);

  String? _chatProviderId(AppRepository repository) =>
      repository.chatProviderIdForSession(_sessionId);

  String _aiInputDigest(
    String text,
    Iterable<ChatAttachment> attachments,
  ) {
    final material = StringBuffer(text.trim());
    for (final attachment in attachments) {
      material
        ..write('\u0000')
        ..write(attachment.path)
        ..write('\u0000')
        ..write(attachment.mimeType)
        ..write('\u0000')
        ..write(attachment.isImage);
    }
    return sha256.convert(utf8.encode(material.toString())).toString();
  }

  Future<AiRun?> _beginAiRun({
    required AppRepository repository,
    required AiRunMode mode,
    required AiProviderConfig config,
    required String input,
    List<ChatAttachment> attachments = const [],
    int? flowId,
    String contextDigest = '',
  }) async {
    if (!config.hasCredential) return null;
    final inputDigest = _aiInputDigest(input, attachments);
    // The flow id is the logical-send boundary. Including wall-clock time
    // here made an accidental duplicate impossible to deduplicate because
    // every retry generated a different key. Keep the key stable for one
    // flow; independent unscoped callers get a one-shot nonce instead.
    final flowScope = flowId?.toString() ?? 'unscoped-${++_unscopedRunNonce}';
    final idempotencyKey = sha256
        .convert(utf8.encode(
          '${_sessionId}|${mode.storageKey}|$inputDigest|$flowScope',
        ))
        .toString();
    final run = await repository.createOrGetAiRun(
      sessionId: _sessionId,
      mode: mode,
      config: config,
      idempotencyKey: idempotencyKey,
      inputDigest: inputDigest,
      contextDigest: contextDigest,
    );
    await repository.updateAiRun(run.id, status: AiRunStatus.preparing);
    await repository.appendAiRunEvent(
      run.id,
      AiRunEventType.stageChanged,
      payload: {
        'stage': 'preparing',
        'flowId': flowId,
        'attachmentCount': attachments.length,
      },
    );
    return run;
  }

  void _recordRunEvent(
    AppRepository repository,
    String? runId,
    AiRunEventType type, {
    Map<String, Object?> payload = const {},
  }) {
    if (runId == null || runId.isEmpty) return;
    unawaited(() async {
      try {
        await repository.appendAiRunEvent(runId, type, payload: payload);
      } catch (_) {}
    }());
  }

  void _setRunStatus(
    AppRepository? repository,
    String? runId,
    AiRunStatus status, {
    String? resultJson,
  }) {
    if (repository == null || runId == null || runId.isEmpty) return;
    unawaited(() async {
      try {
        await repository.updateAiRun(
          runId,
          status: status,
          resultJson: resultJson,
        );
      } catch (_) {}
    }());
  }

  Future<void> _saveChatSelection(
    AppRepository repository, {
    required String providerId,
    required String model,
    required AiReasoningEffort effort,
  }) async {
    if (_sessionId == ChatSession.recordId) {
      await repository.saveChatModelSelection(
        providerId: providerId,
        model: model,
        reasoningEffort: effort,
      );
    }
    await repository.saveChatSessionSelection(
      sessionId: _sessionId,
      providerId: providerId,
      model: model,
      effort: effort,
    );
  }

  // 对话态聊天窗高度占比（半屏 0.58 / 全屏 0.94），及拖拽中标记。
  double _heightFrac = 0.58;
  bool _dragging = false;
  // 本次打开是否已经发过消息：未发=建议页；发过=半屏对话窗(可下拉看历史)。
  bool _started = false;

  static const List<String> _defaultSuggestions = [];
  static List<String>? _suggestionCache;
  static AppRepository? _suggestionCacheRepository;
  static int _suggestionCacheDataRevision = -1;
  static bool? _suggestionCacheHasActiveBudget;
  static int _suggestionCacheTimeKey = -1;
  static bool? _suggestionCacheRecordOnly;

  List<String> _picked = _defaultSuggestions;
  bool _pickInit = false;

  Duration get _focusRequestDelay =>
      widget.fastSwitch ? Duration.zero : const Duration(milliseconds: 16);
  Duration get _visualSettleDelay => widget.fastSwitch
      ? const Duration(milliseconds: 96)
      : const Duration(milliseconds: 120);
  Duration get _postKeyboardWorkDelay => widget.fastSwitch
      ? const Duration(milliseconds: 420)
      : const Duration(milliseconds: 360);

  /// 只展示有账本证据的确定性建议；证据不足时宁可少展示，也不随机补满。
  List<String> _pickSuggestions(AppRepository repo) {
    // 普通 Chats 是自由对话，不显示主页「记一记」快捷提醒。主页 AI
    // 记账仍走下面完整的智能建议链路。
    if (!widget.recordOnly) return const [];
    final now = DateTime.now();
    final suggestions = SmartSuggestionEngine.build(
      records: repo.allRecordsRef,
      now: now,
      hasActiveBudget: _hasSuggestionBudget(repo),
    );
    final visible = widget.recordOnly
        ? suggestions.where((s) => s.kind == SmartSuggestionKind.record)
        : suggestions;
    return visible.map((suggestion) => suggestion.text).toList(growable: false);
  }

  bool _hasSuggestionBudget(AppRepository repo) =>
      repo.currentBook != null && repo.monthlyBudget != null;

  @override
  void initState() {
    super.initState();
    _draftAttachments = List<ChatAttachment>.of(widget.initialDraftAttachments);
    _hasInputText.value = _draftAttachments.isNotEmpty;
    _chatRepository = context.read<AppRepository>();
    _chatMemory = _chatMemoryFor(_chatRepository, _sessionId);
    _observedDatabaseGeneration = _chatRepository.databaseGeneration;
    _msgs = _chatMemory.history;
    _historyViewportReady = _chatRestored && _msgs.isEmpty;
    WidgetsBinding.instance.addObserver(this);
    _chatRepository.addListener(_onRepositoryChanged);
    ReportJobRuntime.revision.addListener(_onReportJobRevision);
    final init = widget.initialText?.trim();
    if (init != null && init.isNotEmpty) {
      _ctrl.text = init;
      _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
      _hasInputText.value = true;
    }
    _ctrl.addListener(_onInputChanged);
    _focus.addListener(_onFocusChanged);
    _syncActiveState(initial: true);
    // 复用会话历史：清掉残留的"思考中"，滚到底显示最新。
    _msgs.removeWhere((m) => m is _ThinkingMsg);
    _busy = false;
    // 首次打开恢复完整历史；再次打开增量读取 Worker 在后台写入的新报告卡。
    if (!_chatRestoreInProgress) {
      final appendNew = _chatRestored;
      _chatRestoreInProgress = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_restoreHistory(appendNew: appendNew));
      });
    } else {
      _waitForSharedHistoryRestore();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_resumePendingReportJob());
    });
  }

  void _waitForSharedHistoryRestore() {
    _restoreTimer?.cancel();
    _restoreTimer = Timer(const Duration(milliseconds: 16), () {
      if (!mounted) return;
      if (_chatRestoreInProgress) {
        _waitForSharedHistoryRestore();
        return;
      }
      // The owner may have been dismissed before either an initial or an
      // incremental read could commit. Re-read from the mounted waiter; row and
      // report-id deduplication keeps this safe if the owner did finish.
      _chatRestoreInProgress = true;
      unawaited(_restoreHistory(appendNew: _chatRestored));
    });
  }

  void _onRepositoryChanged() {
    final generation = _chatRepository.databaseGeneration;
    if (generation == _observedDatabaseGeneration) return;
    _observedDatabaseGeneration = generation;
    _activeFlowId = null;
    _thinkingTickerFlowId = null;
    _chatMemory.reset(
      restored: false,
      databaseGeneration: generation,
    );
    _observedReportJobId = null;
    _observedReportFlowId = null;
    _thinkingStatusTimer?.cancel();
    _thinkingStatusTimer = null;
    _reportPollTimer?.cancel();
    _reportPollTimer = null;
    if (!mounted) return;
    setState(() {
      _latestUserMsg = null;
      _busy = false;
      _historyViewportReady = false;
      _historyRevealScheduled = false;
    });
    if (!_chatRestoreInProgress) {
      _chatRestoreInProgress = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_restoreHistory());
      });
    } else {
      _waitForSharedHistoryRestore();
    }
  }

  @override
  void didUpdateWidget(covariant AiChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active ||
        widget.fullScreen != oldWidget.fullScreen ||
        widget.fastSwitch != oldWidget.fastSwitch) {
      _syncActiveState();
    }
  }

  void _syncActiveState({bool initial = false}) {
    _openSettleTimer?.cancel();
    _focusTimer?.cancel();

    if (!widget.active && !widget.fullScreen) {
      _autoFocusPending = false;
      _clearInputFocusIntent();
      _focus.unfocus();
      if (_visualsReady.value) _visualsReady.value = false;
      return;
    }

    if (widget.fullScreen) {
      if (!_visualsReady.value) _visualsReady.value = true;
      return;
    }

    if (!initial && _visualsReady.value) _visualsReady.value = false;
    _autoFocusPending = true;
    // The AI sheet opens directly into typing. Request focus in the first
    // frame, then bring back expensive blur/animation layers after IME startup.
    _scheduleVisualsReady(_visualSettleDelay);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.active) return;
      void requestWhenRouteIsCurrent([int attempts = 0]) {
        if (!mounted || !widget.active) return;
        final route = ModalRoute.of(context);
        if (route == null || route.isCurrent) {
          _requestInputFocus(bypassThrottle: true);
          return;
        }
        if (attempts < 4) {
          _focusTimer = Timer(
            const Duration(milliseconds: 16),
            () => requestWhenRouteIsCurrent(attempts + 1),
          );
          return;
        }
        _autoFocusPending = false;
        _scheduleVisualsReady(const Duration(milliseconds: 80));
      }

      if (_focusRequestDelay == Duration.zero) {
        requestWhenRouteIsCurrent();
      } else {
        _focusTimer = Timer(_focusRequestDelay, requestWhenRouteIsCurrent);
      }
    });
  }

  bool get _canKeepInputFocused =>
      mounted && (widget.active || widget.fullScreen);

  void _scheduleVisualsReady(Duration delay) {
    _openSettleTimer?.cancel();
    _openSettleTimer = Timer(delay, _settleVisualsReady);
  }

  void _settleVisualsReady() {
    if (!mounted || !widget.active) return;
    // Do not toggle blur/animation layers while Android owns an active input
    // connection. Focus can survive that rebuild while the IME connection
    // itself drops, which looks like "keyboard opens, then hides a few seconds
    // later" on Xiaomi/Android devices.
    if (_autoFocusPending || _inputConnectionCritical) {
      _scheduleVisualsReady(const Duration(milliseconds: 240));
      return;
    }
    if (!_visualsReady.value) _visualsReady.value = true;
  }

  void _requestInputFocus({bool bypassThrottle = false}) {
    if (!_canKeepInputFocused) {
      _autoFocusPending = false;
      return;
    }
    if (_focus.hasFocus) {
      _autoFocusPending = false;
      _markInputFocusIntent();
      _stabilizeInputFocus();
      return;
    }
    if (!_focus.canRequestFocus) {
      _autoFocusPending = false;
      return;
    }
    final now = DateTime.now();
    final last = _lastFocusRequestAt;
    if (!bypassThrottle &&
        last != null &&
        now.difference(last) < const Duration(milliseconds: 160)) {
      return;
    }
    _lastFocusRequestAt = now;
    _focusEpoch++;
    _autoFocusPending = false;
    _markInputFocusIntent();
    FocusScope.of(context).requestFocus(_focus);
    _showKeyboardNow();
    _stabilizeInputFocus();
    _scheduleFocusKeepAlive();
  }

  void _showKeyboardNow() {
    unawaited(
      SystemChannels.textInput
          .invokeMethod<void>('TextInput.show')
          .catchError((_) {}),
    );
  }

  void _hideKeyboardNow() {
    unawaited(
      SystemChannels.textInput
          .invokeMethod<void>('TextInput.hide')
          .catchError((_) {}),
    );
  }

  void _markInputFocusIntent({bool resetAttempts = true}) {
    final now = DateTime.now();
    _inputSessionActive = true;
    if (!_imeVisualsActive.value) _imeVisualsActive.value = true;
    _inputFocusGuardUntil = now.add(const Duration(milliseconds: 3600));
    if (resetAttempts) {
      _focusRepairAttempts = 0;
      _keyboardHadOpened = false;
    }
  }

  void _clearInputFocusIntent() {
    _inputSessionActive = false;
    if (_imeVisualsActive.value) _imeVisualsActive.value = false;
    _inputFocusGuardUntil = null;
    _autoFocusPending = false;
    _focusKeepAliveTimer?.cancel();
    _focusStabilizeTimer?.cancel();
    _focusEpoch++;
    _focusRepairAttempts = 0;
    if (mounted && widget.active && !_visualsReady.value) {
      _scheduleVisualsReady(const Duration(milliseconds: 80));
    }
  }

  bool get _inputFocusGuardActive {
    final until = _inputFocusGuardUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  bool get _inputConnectionCritical =>
      _inputSessionActive &&
      (_focus.hasFocus || _lastKeyboardInset > 24 || _inputFocusGuardActive);

  bool get _shouldKeepInputSessionAlive =>
      _inputSessionActive && _canKeepInputFocused && _focus.canRequestFocus;

  void _scheduleFocusKeepAlive() {
    _focusKeepAliveTimer?.cancel();
    final epoch = _focusEpoch;
    var checksLeft = _keyboardHadOpened ? 4 : 10;
    void tick() {
      if (!_canKeepInputFocused) return;
      if (epoch != _focusEpoch) return;
      if (!_inputSessionActive) return;
      // Once the keyboard has really opened, a later close is treated as user
      // intent. This prevents Android back from being fought by our repair loop.
      if (_keyboardHadOpened && _lastKeyboardInset <= 24) return;
      if (!_focus.hasFocus &&
          _focus.canRequestFocus &&
          !_keyboardHadOpened &&
          _focusRepairAttempts < 4) {
        _focusRepairAttempts++;
        FocusScope.of(context).requestFocus(_focus);
        _showKeyboardNow();
      }
      checksLeft--;
      if (checksLeft > 0) {
        _focusKeepAliveTimer = Timer(const Duration(milliseconds: 120), tick);
      }
    }

    _focusKeepAliveTimer = Timer(const Duration(milliseconds: 80), tick);
  }

  void _stabilizeInputFocus() {
    if (!_shouldKeepInputSessionAlive) return;
    _focusStabilizeTimer?.cancel();
    final epoch = _focusEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_canKeepInputFocused ||
          !_shouldKeepInputSessionAlive ||
          epoch != _focusEpoch) {
        return;
      }
      _focusStabilizeTimer?.cancel();
      _focusStabilizeTimer = Timer(const Duration(milliseconds: 80), () {
        if (!_canKeepInputFocused ||
            !_shouldKeepInputSessionAlive ||
            epoch != _focusEpoch) {
          return;
        }
        if (!_focus.hasFocus && _focus.canRequestFocus) {
          _focusRepairAttempts++;
          FocusScope.of(context).requestFocus(_focus);
        }
      });
    });
  }

  void _observeKeyboardInset(double bottomInset) {
    final previous = _lastKeyboardInset;
    _lastKeyboardInset = bottomInset;
    final keyboardOpeningNow = previous <= 24 && bottomInset > 24;
    final keyboardClosedNow = previous > 24 && bottomInset <= 24;
    if (keyboardOpeningNow && _inputSessionActive) {
      _keyboardHadOpened = true;
      _focusKeepAliveTimer?.cancel();
      return;
    }
    if (keyboardClosedNow && _keyboardHadOpened) {
      _acceptSystemKeyboardDismissal();
    }
  }

  void _acceptSystemKeyboardDismissal() {
    _clearInputFocusIntent();
    if (_focus.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_inputSessionActive && _focus.hasFocus) {
          _focus.unfocus();
        }
      });
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!_inputSessionActive) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_inputSessionActive) return;
      final inset = MediaQuery.maybeOf(context)?.viewInsets.bottom ?? 0;
      if (_keyboardHadOpened && inset <= 24) {
        _acceptSystemKeyboardDismissal();
      }
    });
  }

  void _dismissKeyboardOnly() {
    _clearInputFocusIntent();
    _focus.unfocus();
    _hideKeyboardNow();
  }

  void _handleSystemBack() {
    final keyboardOpen =
        _lastKeyboardInset > 24 || MediaQuery.viewInsetsOf(context).bottom > 24;
    if (_inputSessionActive || _focus.hasFocus || keyboardOpen) {
      _dismissKeyboardOnly();
      return;
    }
    Navigator.pop(context);
  }

  void _handleBackdropTap() {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (!widget.fullScreen) {
      if (_inputFocusGuardActive && !keyboardOpen) return;
      _dismissKeyboardOnly();
      Navigator.pop(context);
      return;
    }
    if (_inputSessionActive || _focus.hasFocus || keyboardOpen) {
      _dismissKeyboardOnly();
      return;
    }
    Navigator.pop(context);
  }

  /// 从数据库恢复历史对话（超期的已在 loadChatMessages 内清理）。
  Future<void> _restoreHistory({bool appendNew = false}) async {
    final restoreEpoch = _chatHistoryEpoch;
    final appendIndex = _chatHistory.length;
    var keepLatestUserAnchored = false;
    try {
      if (!mounted) return;
      final repo = _chatRepository;
      if (!repo.isInitialized) return;
      final rows = _sessionId == ChatSession.recordId
          ? await repo.loadChatMessages()
          : await repo.loadChatSessionMessages(_sessionId);
      if (!mounted || restoreEpoch != _chatHistoryEpoch) return;
      if (appendNew &&
          rows.any((row) => (row['role'] as String?) == 'report')) {
        // A WorkManager isolate owns a different repository cache. Refresh the
        // main isolate before rebuilding report cards from rows it just wrote.
        await repo.reloadReportsFromStorage();
        if (!mounted || restoreEpoch != _chatHistoryEpoch) return;
      }
      final restored = <({int id, _Msg message})>[];
      final pendingSignatures = Map<String, int>.of(_pendingChatSignatures);
      for (final r in rows) {
        final rowId = (r['id'] as num?)?.toInt();
        if (rowId == null) continue;
        final role = (r['role'] as String?) ?? 'info';
        final rowAlreadyKnown = _chatRowIdsInMemory.contains(rowId);
        // Background regeneration updates the original report row in place.
        if (rowAlreadyKnown && role != 'report') continue;
        final text = (r['text'] as String?) ?? '';
        final question = (r['question'] as String?) ?? '';
        final signature = _chatSignature(role, text, question);
        final pendingCount = pendingSignatures[signature] ?? 0;
        if (pendingCount > 0) {
          if (pendingCount == 1) {
            pendingSignatures.remove(signature);
          } else {
            pendingSignatures[signature] = pendingCount - 1;
          }
          continue;
        }
        _Msg? message;
        if (role == 'user') {
          message = _UserMsg(
            text,
            attachments: ChatAttachment.decodeList(r['attachments_json']),
            chatRowId: rowId,
            sentAt: DateTime.fromMillisecondsSinceEpoch(
              (r['created_ms'] as num?)?.toInt() ?? 0,
            ),
          );
        } else if (role == 'answer' || role == 'assistant') {
          message = _AnswerMsg(
            text,
            question: question,
            shown: true,
            chatRowId: rowId,
            sources: AiWebSearchContext.decodeSources(r['attachments_json']),
          );
        } else if (role == 'report') {
          message = await _restoreReportMessage(
            text,
            repo,
            question: question,
          );
        } else if (role == 'record') {
          // 记账明细卡跨重启恢复：重建卡 + 芯片（改分类/删除）继续可用。
          message = _rebuildRecordCard(text, rowId, repo);
        } else if (role == 'refund') {
          message = _rebuildRefundCard(text);
        } else if (role == 'info_err') {
          message = _InfoMsg(text, error: true);
        } else {
          message = _InfoMsg(text);
        }
        if (message != null) restored.add((id: rowId, message: message));
      }
      if (!mounted || restoreEpoch != _chatHistoryEpoch) return;
      // 消息可能在上面的异步报告恢复期间刚刚入库；提交 UI 前再去重一次。
      restored.removeWhere(
        (item) =>
            _chatRowIdsInMemory.contains(item.id) &&
            item.message is! _ReportMsg,
      );
      keepLatestUserAnchored = _latestUserMsg != null;
      if (restored.isNotEmpty) {
        setState(() {
          final messages = <_Msg>[];
          final reportIndexes = <int, int>{
            for (var i = 0; i < _chatHistory.length; i++)
              if (_chatHistory[i] case final _ReportMsg reportMessage)
                reportMessage.report.id: i,
          };
          final queuedReportIds = <int>{};
          for (final item in restored) {
            final message = item.message;
            if (message is _ReportMsg) {
              _chatRowIdsInMemory.add(item.id);
              final existingIndex = reportIndexes[message.report.id];
              if (existingIndex != null) {
                _chatHistory[existingIndex] = message;
                continue;
              }
              if (!queuedReportIds.add(message.report.id)) continue;
            } else if (_chatRowIdsInMemory.contains(item.id)) {
              continue;
            }
            _chatRowIdsInMemory.add(item.id);
            messages.add(message);
          }
          if (appendNew) {
            _chatHistory.insertAll(
              min(appendIndex, _chatHistory.length),
              messages,
            );
          } else {
            _chatHistory.insertAll(0, messages);
          }
        });
      }
      _chatRestored = true;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('chat history restore failed: $error');
        debugPrint('$stackTrace');
      }
    } finally {
      _chatRestoreInProgress = false;
      if (mounted && restoreEpoch == _chatHistoryEpoch) {
        _scheduleInitialHistoryReveal(
          keepLatestUserAnchored: keepLatestUserAnchored,
        );
      }
    }
  }

  Future<int> _addChatMessage(
    AppRepository repo, {
    required String role,
    String text = '',
    String question = '',
    List<ChatAttachment> attachments = const [],
    List<AiWebSource> sources = const [],
  }) async {
    if (role != 'user') {
      // A locked/slow SQLite write must not hold every subsequent assistant
      // message forever. The user bubble is already visible, so after this
      // short ordering barrier we can continue rendering and let the late
      // write finish in the background.
      try {
        await _pendingUserPersistence?.timeout(_kAiChatPersistenceTimeout);
      } catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('chat user persistence barrier timed out/failed: $error');
          debugPrint('$stackTrace');
        }
      }
    }
    final signature = _chatSignature(role, text, question);
    _pendingChatSignatures.update(signature, (count) => count + 1,
        ifAbsent: () => 1);
    try {
      final id = _sessionId == ChatSession.recordId &&
              attachments.isEmpty &&
              sources.isEmpty
          ? await repo.addChatMessage(
              role: role,
              text: text,
              question: question,
            )
          : await repo.addChatSessionMessage(
              sessionId: _sessionId,
              role: role,
              text: text,
              question: question,
              attachmentsJson: attachments.isNotEmpty
                  ? ChatAttachment.encodeList(attachments)
                  : AiWebSearchContext.encodeSources(sources),
            );
      _chatRowIdsInMemory.add(id);
      return id;
    } finally {
      final count = _pendingChatSignatures[signature] ?? 0;
      if (count <= 1) {
        _pendingChatSignatures.remove(signature);
      } else {
        _pendingChatSignatures[signature] = count - 1;
      }
    }
  }

  /// Keep the user-before-answer write ordering, but put a finite bound on it.
  /// A blocked SQLite write must not leave the visible response in thinking
  /// forever; the timed future still observes failures from the source.
  Future<int?> _awaitChatPersistence(Future<int> persistence) async {
    try {
      return await persistence.timeout(_kAiChatPersistenceTimeout);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('chat response persistence timed out/failed: $error');
        debugPrint('$stackTrace');
      }
      return null;
    }
  }

  Future<int> _addChatRecordMessage(
    AppRepository repo,
    String json,
  ) async {
    await _pendingUserPersistence;
    final signature = _chatSignature('record', json, '');
    _pendingChatSignatures.update(signature, (count) => count + 1,
        ifAbsent: () => 1);
    try {
      final id = _sessionId == ChatSession.recordId
          ? await repo.addChatRecordMessage(json)
          : await repo.addChatRecordMessage(json, sessionId: _sessionId);
      _chatRowIdsInMemory.add(id);
      return id;
    } finally {
      final count = _pendingChatSignatures[signature] ?? 0;
      if (count <= 1) {
        _pendingChatSignatures.remove(signature);
      } else {
        _pendingChatSignatures[signature] = count - 1;
      }
    }
  }

  Future<_ReportMsg?> _restoreReportMessage(
    String json,
    AppRepository repo, {
    required String question,
  }) async {
    final decoded = decodeReportChatMessage(json);
    if (decoded == null) return null;
    final report = await repo.getReport(decoded.reportId);
    if (report == null) return null;
    final summary = report.summary.trim().isNotEmpty
        ? report.summary.trim()
        : decoded.summary;
    return _ReportMsg(
      report,
      summary: summary,
      question: question,
      shown: true,
    );
  }

  /// 从持久化 JSON 重建一张记账卡（catId 用 repo 查回分类，行 id 灌回供之后写回）。
  /// 坏数据容错：解析失败返回 null，跳过这张卡而不是整个恢复流程崩掉。
  _RecordMsg? _rebuildRecordCard(String json, int? rowId, AppRepository repo) {
    try {
      final d = decodeRecordCard(json);
      final cats = <CategoryEntity?>[
        for (final id in d.catIds)
          id == null
              ? null
              : repo.categories.where((c) => c.id == id).firstOrNull,
      ];
      final msg = _RecordMsg(
        entries: d.entries,
        cats: cats,
        saved: d.saved,
        txnIds: d.txnIds,
        savedIds: d.txnIds.whereType<int>().toList(),
        savedFeedback: d.feedback,
        aiRunId: d.aiRunId,
        rolledBack: d.rolledBack,
        chatRowId: rowId,
      );
      msg.deletedIdx.addAll(d.deleted);
      return msg;
    } catch (_) {
      return null;
    }
  }

  _RefundMsg? _rebuildRefundCard(String json) {
    try {
      return _RefundMsg.fromDecoded(decodeRefundCard(json));
    } catch (_) {
      return null;
    }
  }

  void _onFocusChanged() {
    final lostDuringGuard = !_focus.hasFocus && _inputFocusGuardActive;
    if (_focus.hasFocus) {
      _markInputFocusIntent(resetAttempts: false);
    } else if (_inputSessionActive) {
      if (_keyboardHadOpened) {
        _clearInputFocusIntent();
      } else {
        _scheduleFocusKeepAlive();
      }
    }
    if (mounted && _started && !lostDuringGuard) setState(() {});
  }

  void _onInputChanged() {
    final hasText =
        _ctrl.text.trim().isNotEmpty || _draftAttachments.isNotEmpty;
    if (_hasInputText.value != hasText) {
      _hasInputText.value = hasText;
    }
  }

  void _handleInputPointerDown() {
    // Let TextField own the tap and create the input connection first. Then
    // repair focus on the next frame if Android dropped it during IME startup.
    _focusTimer?.cancel();
    _autoFocusPending = false;
    _focusEpoch++;
    _markInputFocusIntent();
    _stabilizeInputFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_canKeepInputFocused || !_shouldKeepInputSessionAlive) return;
      if (!_focus.hasFocus && _focus.canRequestFocus) {
        _focusRepairAttempts++;
        FocusScope.of(context).requestFocus(_focus);
      }
      _scheduleFocusKeepAlive();
    });
  }

  void _switchToManual() {
    // Fast switching keeps the old route alive during the replacement
    // animation. Turn off the outgoing full-screen blur/mascot animation first
    // so the incoming manual sheet is not competing with it on the same frames.
    _clearInputFocusIntent();
    _focus.unfocus();
    if (_visualsReady.value) _visualsReady.value = false;
    widget.onSwitchToManual();
  }

  void _showModelPicker(BuildContext anchor) {
    final repo = context.read<AppRepository>();
    final options = repo.aiChatModelOptions;
    if (options.isEmpty) {
      showAppToast(context, '先去 AI 账号设置获取模型列表', icon: Icons.info_outline);
      return;
    }
    final currentConfig = _chatConfig(repo);
    final currentKey =
        '${_chatProviderId(repo) ?? ''}\u0000${currentConfig.model}';

    if (mounted) {
      setState(() => _activeInputSelection = _InputSelection.model);
    }

    // 小气泡弹窗：对齐 Claude 桌面端 Models 列表
    _showFloatingPopup(
      anchor: anchor,
      width: 195,
      onClosed: _clearActiveInputSelection,
      child: _ModelMenuCard(
        options: options,
        currentKey: currentKey,
        onSelected: (option) async {
          final effort = _chatEffort(repo);
          await _saveChatSelection(
            repo,
            providerId: option.providerId,
            model: option.model,
            effort: effort,
          );
        },
      ),
    );
  }

  /// Effort 小气泡弹窗：对齐 Claude 桌面端 Effort 滑块面板
  void _showEffortMenu(BuildContext anchor) {
    final repo = context.read<AppRepository>();
    final current = _chatEffort(repo);

    if (mounted) {
      setState(() => _activeInputSelection = _InputSelection.effort);
    }

    _showFloatingPopup(
      anchor: anchor,
      width: 222,
      onClosed: _clearActiveInputSelection,
      child: _EffortPopupCard(
        currentEffort: current,
        onChanged: (effort) async {
          final providerId = _chatProviderId(repo) ?? '';
          final model = _chatConfig(repo).model;
          if (providerId.isEmpty || model.isEmpty) return;
          await _saveChatSelection(
            repo,
            providerId: providerId,
            model: model,
            effort: effort,
          );
        },
      ),
    );
  }

  void _clearActiveInputSelection() {
    if (!mounted || _activeInputSelection == null) return;
    setState(() => _activeInputSelection = null);
  }

  /// 通用浮动气泡：计算锚点位置，从下方向上弹出
  void _showFloatingPopup({
    required BuildContext anchor,
    required double width,
    required Widget child,
    VoidCallback? onClosed,
  }) {
    showAiFloatingPopup(
      context: context,
      anchor: anchor,
      width: width,
      child: child,
      onClosed: onClosed,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_pickInit) {
      _pickInit = true;
      _primeSuggestions();
    }
  }

  void _primeSuggestions() {
    final repo = context.read<AppRepository>();
    final recordOnly = widget.recordOnly;
    final now = DateTime.now();
    final timeKey =
        (now.year * 10000 + now.month * 100 + now.day) * 100 + now.hour;
    final hasActiveBudget = _hasSuggestionBudget(repo);
    final cached = _suggestionCache;
    if (cached != null &&
        identical(_suggestionCacheRepository, repo) &&
        _suggestionCacheDataRevision == repo.dataRevision &&
        _suggestionCacheHasActiveBudget == hasActiveBudget &&
        _suggestionCacheTimeKey == timeKey &&
        _suggestionCacheRecordOnly == recordOnly) {
      _picked = cached;
      return;
    }

    _picked = _defaultSuggestions;
    _suggestionTimer?.cancel();
    _suggestionTimer = Timer(_postKeyboardWorkDelay, () {
      if (!mounted) return;
      final latestRepo = context.read<AppRepository>();
      final latestNow = DateTime.now();
      final latestTimeKey =
          (latestNow.year * 10000 + latestNow.month * 100 + latestNow.day) *
                  100 +
              latestNow.hour;
      final next = _pickSuggestions(latestRepo);
      final latestHasActiveBudget = _hasSuggestionBudget(latestRepo);
      _suggestionCache = next;
      _suggestionCacheRecordOnly = widget.recordOnly;
      _suggestionCacheRepository = latestRepo;
      _suggestionCacheDataRevision = latestRepo.dataRevision;
      _suggestionCacheHasActiveBudget = latestHasActiveBudget;
      _suggestionCacheTimeKey = latestTimeKey;
      if (mounted) setState(() => _picked = next);
    });
  }

  @override
  void dispose() {
    _textSelectionScrim?.remove();
    _textSelectionScrim = null;
    WidgetsBinding.instance.removeObserver(this);
    _chatRepository.removeListener(_onRepositoryChanged);
    ReportJobRuntime.revision.removeListener(_onReportJobRevision);
    _openSettleTimer?.cancel();
    _focusTimer?.cancel();
    _latestUserAnchorTimer?.cancel();
    _restoreTimer?.cancel();
    _suggestionTimer?.cancel();
    _thinkingStatusTimer?.cancel();
    _reportPollTimer?.cancel();
    _focusKeepAliveTimer?.cancel();
    _focusStabilizeTimer?.cancel();
    _visualsReady.dispose();
    _hasInputText.dispose();
    _imeVisualsActive.dispose();
    _ctrl.removeListener(_onInputChanged);
    _ctrl.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onReportJobRevision() {
    if (!mounted) return;
    unawaited(_syncReportJobState());
  }

  void _startReportPolling() {
    if (_reportPollTimer != null || _observedReportJobId == null) return;
    _reportPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _observedReportJobId == null) {
        _reportPollTimer?.cancel();
        _reportPollTimer = null;
        return;
      }
      unawaited(_syncReportJobState());
    });
  }

  void _stopReportPolling() {
    _reportPollTimer?.cancel();
    _reportPollTimer = null;
  }

  Future<void> _syncReportJobState() async {
    if (!mounted || widget.recordOnly || _reportStatusSyncing) return;
    _reportStatusSyncing = true;
    try {
      final repo = context.read<AppRepository>();
      final jobs = await repo.pendingReportJobs(sessionId: _sessionId);
      if (!mounted) return;
      final observedFlowId = _observedReportFlowId;
      final currentThinking =
          observedFlowId == null ? null : _currentThinkingMsg(observedFlowId);
      if (jobs.isNotEmpty) {
        final job = jobs.first;
        _observedReportJobId = job.id;
        final kind = switch (job.stage) {
          'generate' => _ThinkingKind.reportGenerate,
          'fallback' => _ThinkingKind.reportFallback,
          'save' => _ThinkingKind.reportSave,
          _ => _ThinkingKind.reportCollect,
        };
        // A completed foreground flow may have handed the job to
        // WorkManager. Never retag a newer, unrelated send just because the
        // old report is still pending.
        if (currentThinking != null && currentThinking.kind != kind) {
          setState(() {
            currentThinking.kind = kind;
          });
        }
        final startedMs = job.modelStartedMs;
        if (currentThinking != null &&
            startedMs != null &&
            currentThinking.modelStartedAt == null) {
          setState(() {
            currentThinking.markModelStarted(
              DateTime.fromMillisecondsSinceEpoch(startedMs),
            );
          });
        }
        _startReportPolling();
        return;
      }

      final observedId = _observedReportJobId;
      final observed =
          observedId == null ? null : await repo.reportJobById(observedId);
      if (observed?.status == 'completed' && observed?.reportId != null) {
        await repo.reloadReportsFromStorage();
        final report = await repo.getReport(observed!.reportId!);
        if (!mounted || report == null) return;
        final ownsObservedFlow = observedFlowId != null &&
            _ownsFlow(observedFlowId) &&
            _currentThinkingMsg(observedFlowId) != null;
        if (ownsObservedFlow) {
          _completeThinking(flowId: observedFlowId);
          _finishFlow(observedFlowId!);
        }
        setState(() {
          _msgs.removeWhere(
            (message) =>
                message is _ReportMsg && message.report.id == report.id,
          );
          _msgs.add(
            _ReportMsg(
              report,
              summary: report.summary,
              question: observed.question,
              shown: true,
            ),
          );
          if (ownsObservedFlow) _busy = false;
        });
        _observedReportJobId = null;
        _observedReportFlowId = null;
        _stopReportPolling();
        _scrollToLatestUserMessage();
        return;
      }
      if (observed?.status == 'failed') {
        if (!mounted) return;
        final ownsObservedFlow = observedFlowId != null &&
            _ownsFlow(observedFlowId) &&
            _currentThinkingMsg(observedFlowId) != null;
        if (ownsObservedFlow) {
          _completeThinking(flowId: observedFlowId);
          _finishFlow(observedFlowId!);
        }
        setState(() {
          _msgs.add(_InfoMsg('报告生成失败，请检查 AI 设置后重新生成', error: true));
          if (ownsObservedFlow) _busy = false;
        });
        _observedReportJobId = null;
        _observedReportFlowId = null;
        _stopReportPolling();
      }
    } on Object catch (error, stackTrace) {
      // This method is called from timers and revision listeners. A transient
      // SQLite/restore failure must not become an unhandled asynchronous error
      // or strand a visible flow in its previous thinking state; the next
      // poll/reopen can retry from the persisted job.
      if (kDebugMode) {
        debugPrint('report status sync failed: $error');
        debugPrint('$stackTrace');
      }
    } finally {
      _reportStatusSyncing = false;
    }
  }

  Future<void> _resumePendingReportJob() async {
    if (!mounted || widget.recordOnly) return;
    final repo = context.read<AppRepository>();
    late final List<ReportJobEntity> jobs;
    try {
      jobs = await repo.pendingReportJobs(sessionId: _sessionId);
    } on Object catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('pending report lookup failed: $error');
        debugPrint('$stackTrace');
      }
      return;
    }
    if (!mounted || jobs.isEmpty) return;
    final job = jobs.first;
    final jobConfig = repo.aiProviderConfigForReportJob(job);
    if (jobConfig == null) {
      const prompt = '报告使用的服务商或模型已失效，请修复该账号后重试。';
      if (!_msgs.any((m) => m is _InfoMsg && m.text == prompt)) {
        setState(() {
          _started = true;
          _msgs.add(_InfoMsg(prompt, error: true));
        });
      }
      return;
    }
    // 未同意 AI 隐私说明：恢复的任务不上传账本内容，保持 pending 并提示，
    // 等用户在喵助手里重新发起（走同意弹窗）后再继续。
    if (!repo.aiPrivacyAcceptedFor(jobConfig)) {
      const prompt = '有一份报告在等待生成：先同意 AI 隐私说明（重新发起一次报告即可确认）后才会继续。';
      final alreadyPrompted =
          _msgs.any((m) => m is _InfoMsg && m.text == prompt);
      if (!alreadyPrompted) {
        setState(() {
          _started = true;
          _msgs.add(_InfoMsg(prompt));
        });
      }
      return;
    }
    final flowId = _beginFlow();
    _observedReportJobId = job.id;
    _observedReportFlowId = flowId;
    final kind = switch (job.stage) {
      'generate' => _ThinkingKind.reportGenerate,
      'fallback' => _ThinkingKind.reportFallback,
      'save' => _ThinkingKind.reportSave,
      _ => _ThinkingKind.reportCollect,
    };
    final currentThinking = _currentThinkingMsg(flowId);
    if (currentThinking == null) {
      setState(() {
        _started = true;
        _busy = true;
        _msgs.add(
          _ThinkingMsg(
            kind,
            flowId: flowId,
          ),
        );
      });
      _restartThinkingTicker(flowId: flowId);
    } else if (currentThinking.kind != kind) {
      setState(() {
        currentThinking.kind = kind;
      });
    }
    // A persisted timestamp is authoritative when a worker has already
    // reached the model. Queued/collecting jobs intentionally stay without a
    // model start until the foreground path is about to call the model.
    final persistedModelStartMs = job.modelStartedMs;
    if (persistedModelStartMs != null) {
      _markModelThinkingStarted(
        flowId,
        value: DateTime.fromMillisecondsSinceEpoch(persistedModelStartMs),
      );
    }
    late final ReportGenerationLease lease;
    try {
      lease = (await repo.acquireReportGenerationLease()).bind(
        jobId: job.id,
        jobUuid: job.uuid,
      );
    } on Object catch (error, stackTrace) {
      await _handleUnexpectedFlowError(flowId, error, stackTrace);
      _finishFlow(flowId);
      return;
    }
    final scheduled = await ReportTaskScheduler.schedule(
      repo,
      job,
      lease: lease,
    );
    if (scheduled) {
      _setThinkingCanContinueInBackground(true, flowId: flowId);
      _startReportPolling();
      return;
    }
    if (ReportJobRuntime.isActive(lease.runtimeKey)) {
      _setThinkingCanContinueInBackground(true, flowId: flowId);
      _startReportPolling();
      return;
    }
    unawaited(
      _runQuerySafely(
        flowId,
        job.question,
        repository: repo,
        resumeJob: job,
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _scheduleInitialHistoryReveal({
    bool keepLatestUserAnchored = false,
    int positioningPass = 0,
    double? previousMaxScrollExtent,
    double? previousPixels,
  }) {
    if (_historyViewportReady || _historyRevealScheduled) return;
    _historyRevealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _historyRevealScheduled = false;
      if (!mounted) return;
      if (_scroll.hasClients) {
        var targetIsBuilt = true;
        if (keepLatestUserAnchored) {
          final latestContext = _latestUserMsgKey.currentContext;
          if (latestContext != null) {
            Scrollable.ensureVisible(
              latestContext,
              alignment: 0.0,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              duration: Duration.zero,
            );
          } else {
            targetIsBuilt = false;
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        } else {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
        final position = _scroll.position;
        final maxScrollExtent = position.maxScrollExtent;
        final extentIsStable = previousMaxScrollExtent != null &&
            (maxScrollExtent - previousMaxScrollExtent).abs() <= 0.5;
        final pixelsAreStable = previousPixels != null &&
            (position.pixels - previousPixels).abs() <= 0.5;
        final positionIsStable = keepLatestUserAnchored ||
            (position.pixels - maxScrollExtent).abs() <= 0.5;
        if (positioningPass < 6 &&
            (!targetIsBuilt ||
                !extentIsStable ||
                !pixelsAreStable ||
                !positionIsStable)) {
          _scheduleInitialHistoryReveal(
            keepLatestUserAnchored: keepLatestUserAnchored,
            positioningPass: positioningPass + 1,
            previousMaxScrollExtent: maxScrollExtent,
            previousPixels: position.pixels,
          );
          return;
        }
      } else if (_msgs.isNotEmpty && positioningPass < 6) {
        _scheduleInitialHistoryReveal(
          keepLatestUserAnchored: keepLatestUserAnchored,
          positioningPass: positioningPass + 1,
          previousMaxScrollExtent: previousMaxScrollExtent,
          previousPixels: previousPixels,
        );
        return;
      }
      setState(() => _historyViewportReady = true);
    });
  }

  Widget _historyViewport(Widget child) => IgnorePointer(
        ignoring: !_historyViewportReady,
        child: Opacity(
          key: const ValueKey('ai-chat-history-viewport'),
          opacity: _historyViewportReady ? 1 : 0,
          child: child,
        ),
      );

  void _ensureLatestUserVisible(Duration duration) {
    if (!mounted || !_scroll.hasClients) return;
    final ctx = _latestUserMsgKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.0,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        duration: duration,
        curve: Curves.easeOutCubic,
      );
      return;
    }
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final ctx = _latestUserMsgKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.0,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        duration: duration,
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _scrollToLatestUserMessage() {
    _latestUserAnchorTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureLatestUserVisible(const Duration(milliseconds: 220));
    });
    _latestUserAnchorTimer = Timer(const Duration(milliseconds: 260), () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureLatestUserVisible(const Duration(milliseconds: 160));
      });
    });
  }

  double _latestUserAnchorBottomPadding(double viewportHeight) {
    if (_latestUserMsg == null) return 8;
    // Keep a small breathing room below the last user message while the
    // response is being generated.  Once the response is complete, do not
    // reserve a viewport-sized spacer that turns a normal upward drag into a
    // large blank region.
    if (_busy) return min(96.0, max(24.0, viewportHeight - 180.0));
    return 8.0;
  }

  /// Keep a short conversation visually attached to the composer instead of
  /// leaving the response/action row stranded at the top of a tall viewport.
  /// Once the messages are taller than the viewport the constrained column
  /// naturally grows and the normal scroll position is unchanged.
  Widget _messageHistoryList(BoxConstraints constraints) {
    const topPadding = 2.0;
    const horizontalPadding = 16.0;
    final bottomPadding = _latestUserAnchorBottomPadding(constraints.maxHeight);
    final minContentHeight = max(
      0.0,
      constraints.maxHeight - topPadding - bottomPadding,
    );
    return ListView(
      controller: _scroll,
      physics: const _ChatBouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        topPadding,
        horizontalPadding,
        bottomPadding,
      ),
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: minContentHeight),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (var i = 0; i < _msgs.length; i++)
                _buildMsg(_msgs[i], isLast: i == _msgs.length - 1),
            ],
          ),
        ),
      ],
    );
  }

  // 轻提示统一走全局 app_toast（同类功能同一种设计）。
  void _snack(String msg) =>
      showAppToast(context, msg, icon: Icons.info_outline);

  _ThinkingMsg? _currentThinkingMsg([int? flowId]) {
    for (final msg in _msgs.reversed) {
      if (msg is _ThinkingMsg && (flowId == null || msg.flowId == flowId)) {
        return msg;
      }
    }
    return null;
  }

  void _markModelThinkingStarted(int? flowId, {DateTime? value}) {
    _currentThinkingMsg(flowId)?.markModelStarted(value);
  }

  void _restartThinkingTicker({int? flowId}) {
    final tickerFlowId = flowId ?? _activeFlowId;
    _thinkingTickerFlowId = tickerFlowId;
    _thinkingStatusTimer?.cancel();
    _thinkingStatusTimer = Timer.periodic(const Duration(seconds: 1), (
      _,
    ) {
      final msg = _currentThinkingMsg(tickerFlowId);
      if (!mounted ||
          !_ownsFlow(tickerFlowId) ||
          msg == null ||
          msg.completed) {
        _thinkingStatusTimer?.cancel();
        _thinkingStatusTimer = null;
        return;
      }
      setState(() {});
      // A request can stall before the HTTP stream is opened (OAuth refresh,
      // search preparation, or attachment decoding). The transport timeout
      // cannot see those stages, so release the foreground UI explicitly.
      if (aiThinkingShouldExpireForTest(
        elapsed: msg.elapsed,
        canContinueInBackground: msg.canContinueInBackground,
      )) {
        _finishStalledThinking(flowId: tickerFlowId);
        return;
      }
      if (_observedReportJobId != null) {
        unawaited(_syncReportJobState());
      }
    });
  }

  void _finishStalledThinking({int? flowId}) {
    final msg = _currentThinkingMsg(flowId);
    if (msg == null || msg.completed) return;
    final continuesInBackground = msg.canContinueInBackground;
    _completeThinking(flowId: flowId);
    // The transport/DB future may finish later. Release this flow now so its
    // late callbacks cannot consume a newer send.
    if (flowId != null) _finishFlow(flowId);
    if (!mounted) return;
    setState(() {
      _msgs.add(
        _InfoMsg(
          continuesInBackground ? '喵会在后台继续处理，完成后会显示在这里。' : '喵这次处理超时了，请检查网络后重试',
          error: !continuesInBackground,
        ),
      );
      _busy = false;
    });
    if (continuesInBackground) {
      // Keep polling the persisted job after the foreground flow has been
      // released. A later report completion must not mutate a newer send's
      // thinking row, but it should still appear in this open conversation.
      _observedReportFlowId = null;
      _startReportPolling();
    }
    _scrollToLatestUserMessage();
  }

  void _setThinkingKind(_ThinkingKind kind, {int? flowId}) {
    if (!_ownsFlow(flowId)) return;
    final msg = _currentThinkingMsg(flowId);
    if (msg == null) return;
    if (msg.kind == kind && msg.steps.isNotEmpty) {
      _restartThinkingTicker(flowId: flowId);
      return;
    }
    final now = DateTime.now();
    final previous = msg.steps.lastOrNull;
    if (previous != null && previous.completedAt == null) {
      previous.completedAt = now;
    }
    msg.steps.add(_ThinkingStep(kind: kind, startedAt: now));
    if (!mounted) {
      msg.kind = kind;
      return;
    }
    setState(() {
      msg.kind = kind;
    });
    _restartThinkingTicker(flowId: flowId);
  }

  void _completeThinking({
    Iterable<AiWebSource> sources = const [],
    int? flowId,
  }) {
    if (!_ownsFlow(flowId)) return;
    final msg = _currentThinkingMsg(flowId);
    if (msg == null || msg.completed) return;
    final now = DateTime.now();
    final current = msg.steps.lastOrNull;
    if (current != null && current.completedAt == null) {
      current.completedAt = now;
    }
    msg.completedAt = now;
    _addThinkingSources(msg, sources);
    final hasProviderSummary = msg.steps.any(
      (step) => step.detail.trim().isNotEmpty,
    );
    msg.hidden = msg.elapsed < const Duration(seconds: 3) &&
        !hasProviderSummary &&
        msg.sources.isEmpty;
    // Longer or tool-backed work stays as a tappable elapsed summary. Short
    // answers transition directly from the status label to body text.
    if (mounted) setState(() {});
    _thinkingStatusTimer?.cancel();
    _thinkingStatusTimer = null;
  }

  void _addThinkingSources(
    _ThinkingMsg msg,
    Iterable<AiWebSource> sources,
  ) {
    var changed = false;
    for (final source in sources) {
      final url = source.url.trim();
      if (url.isEmpty || msg.sources.any((item) => item.url == url)) continue;
      msg.sources.add(source);
      changed = true;
    }
    if (changed && msg.completed) msg.hidden = false;
    if (changed && mounted) setState(() {});
  }

  void _setThinkingCanContinueInBackground(bool value, {int? flowId}) {
    if (!_ownsFlow(flowId)) return;
    // The synchronous send future is allowed to finish once the report is
    // owned by WorkManager, but this flow remains the owner of its thinking
    // row until polling observes completion or the capped hand-off fires.
    if (flowId != null) {
      if (value) {
        _backgroundFlowId = flowId;
      } else if (_backgroundFlowId == flowId) {
        _backgroundFlowId = null;
      }
    }
    final msg = _currentThinkingMsg(flowId);
    if (msg == null || msg.canContinueInBackground == value) return;
    if (!mounted) {
      msg.canContinueInBackground = value;
      return;
    }
    setState(() => msg.canContinueInBackground = value);
  }

  // ── 发送：主页直接交给 AI 记账，普通 Chats 再按意图分流 ────────────────
  Future<void> _addDraftAttachments(
    List<ChatAttachment> attachments,
  ) async {
    if (!mounted || attachments.isEmpty || _busy) return;
    // The picker limits one selection to three images, but users can open it
    // repeatedly (and the generic file picker can return image files too).
    // Enforce the same per-message budget at the draft boundary so a later
    // send cannot be rejected because the UI allowed an impossible 3+1 draft.
    final accepted = fitDraftAttachments(_draftAttachments, attachments);
    final acceptedImages =
        accepted.where((attachment) => attachment.isImage).length;
    final acceptedFiles = accepted.length - acceptedImages;
    final incomingImages =
        attachments.where((attachment) => attachment.isImage).length;
    final incomingFiles = attachments.length - incomingImages;
    final rejectedImages = incomingImages - acceptedImages;
    final rejectedFiles = incomingFiles - acceptedFiles;
    if (accepted.isNotEmpty) {
      setState(() => _draftAttachments.addAll(accepted));
      _hasInputText.value = true;
      _requestInputFocus(bypassThrottle: true);
    }
    if (mounted && (rejectedImages > 0 || rejectedFiles > 0)) {
      final parts = <String>[];
      if (rejectedImages > 0) parts.add('最多添加 3 张图片');
      if (rejectedFiles > 0) parts.add('最多添加 10 个文件');
      _snack('${parts.join('，')}，超出的附件未添加');
    }
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _ctrl.text).trim();
    final attachments = List<ChatAttachment>.unmodifiable(_draftAttachments);
    if ((text.isEmpty && attachments.isEmpty) || _busy) return;
    final flowId = _beginFlow();
    try {
      await _sendImpl(preset, flowId).timeout(_kAiFlowTimeout);
    } catch (error, stackTrace) {
      await _handleUnexpectedFlowError(flowId, error, stackTrace);
    } finally {
      if (!_keepsBackgroundFlow(flowId)) _finishFlow(flowId);
    }
  }

  Future<void> _sendImpl(String? preset, int flowId) async {
    final text = (preset ?? _ctrl.text).trim();
    final requestedAttachments =
        List<ChatAttachment>.unmodifiable(_draftAttachments);
    if ((text.isEmpty && requestedAttachments.isEmpty) || _busy) return;

    final repo = context.read<AppRepository>();
    // The send button can be tapped during the fast-start hydration window.
    // Wait for the ready snapshot before resolving the record provider too;
    // otherwise this branch (unlike _runQuery) could still fall back locally
    // on the very first message and only use AI from the second one onward.
    if (repo.isInitializing) {
      await repo.ready;
      if (!mounted) return;
    }
    if (widget.recordOnly &&
        !repo.aiSkillAllowsTool('ledger_assistant', 'create_transactions')) {
      _snack('记账助手已关闭，请先在 AI 设置中重新开启');
      return;
    }
    final attachmentBatch =
        await AiAttachmentPipeline.validate(requestedAttachments);
    if (!attachmentBatch.isValid) {
      final reason = attachmentBatch.rejected
          .map((check) => check.error)
          .where((error) => error.trim().isNotEmpty)
          .join('、');
      _snack(reason.isEmpty ? '附件无法发送，请重新选择' : '附件无法发送：$reason');
      return;
    }
    final attachments = attachmentBatch.accepted;
    // 主页的 AI 记账入口不做本地意图拦截。用户输入的任何自然语言都
    // 先交给记账模型，由 forceRecord 提示词决定如何提取；否则“没被
    // 本地规则识别”的表达会根本没有发到 AI。
    final localIntent = attachments.isNotEmpty && !widget.recordOnly
        ? ChatIntentKind.chat
        : resolveAiPanelIntent(recordOnly: widget.recordOnly, text: text);
    final refund = widget.recordOnly ? null : _matchRefund(repo, text);
    // Chats 中的普通会话是闲聊/问答上下文；账本变更始终归入唯一的
    // 「记一记」会话，不能因用户在某个聊天里顺口提到一笔消费就把它
    // 分散到多个会话中。
    if (!widget.recordOnly &&
        (localIntent == ChatIntentKind.record || refund!.isRefundMutation)) {
      Haptics.light();
      _snack('记账请使用置顶的「记一记」会话');
      return;
    }

    Haptics.light();
    _ctrl.clear();
    _draftAttachments.clear();
    _hasInputText.value = false;
    _clearInputFocusIntent();
    _focus.unfocus();
    final userMsg = _UserMsg(
      text,
      attachments: attachments,
      sentAt: DateTime.now(),
    );
    setState(() {
      _started = true;
      _latestUserMsg = userMsg;
      _msgs.add(userMsg);
      _msgs.add(_ThinkingMsg(_ThinkingKind.intent, flowId: flowId));
      _busy = true;
    });
    _restartThinkingTicker(flowId: flowId);
    _scrollToLatestUserMessage();
    final userPersistence = _addChatMessage(
      repo,
      role: 'user',
      text: text,
      attachments: attachments,
    );
    late final Future<void> persistenceBarrier;
    persistenceBarrier = userPersistence.then<void>(
      (rowId) => userMsg.chatRowId = rowId,
      onError: (Object error, StackTrace stackTrace) {
        if (kDebugMode) {
          debugPrint('chat user message persistence failed: $error');
          debugPrint('$stackTrace');
        }
      },
    ).whenComplete(() {
      if (identical(_pendingUserPersistence, persistenceBarrier)) {
        _pendingUserPersistence = null;
      }
    });
    _pendingUserPersistence = persistenceBarrier;

    if (attachments.isNotEmpty && !widget.recordOnly) {
      await _runQuery(
        text.isEmpty ? '请查看我发送的附件并直接回答。' : text,
        repository: repo,
        chatOnly: true,
        attachments: attachments,
        flowId: flowId,
      ).timeout(_kAiFlowTimeout);
      return;
    }

    // 历史订单退款不是一笔新收入。先用本地确定性规则匹配原支出，只有
    // 唯一强匹配且金额合法时才附着退款；所有不确定情况都停下来追问。
    if (!widget.recordOnly && refund!.isRefundMutation) {
      await _applyRefund(refund, repo, flowId: flowId);
      return;
    }

    if (localIntent == ChatIntentKind.query) {
      await _runQuery(
        text,
        repository: repo,
        flowId: flowId,
      ).timeout(_kAiFlowTimeout);
      return;
    }
    if (localIntent == ChatIntentKind.chat) {
      await _runQuery(
        text,
        repository: repo,
        chatOnly: true,
        flowId: flowId,
      ).timeout(_kAiFlowTimeout);
      return;
    }

    final aiConfig = repo.aiProviderConfigFor(AiTaskType.recordParse);
    AiRun? recordRun;
    // 主页输入已经进入记账模型路径；普通 Chats 的闲聊/查账才会在
    // 上面的 localIntent 分支提前转到聊天链路。
    if (aiConfig.hasCredential) {
      final consented = await ensureAiPrivacyConsent(
        context,
        config: aiConfig,
      );
      if (!mounted) return;
      try {
        if (consented) {
          _markModelThinkingStarted(flowId);
          recordRun = await _beginAiRun(
            repository: repo,
            mode: AiRunMode.record,
            config: aiConfig,
            input: text,
            attachments: attachments,
            flowId: flowId,
          );
          _setThinkingKind(_ThinkingKind.recordParse, flowId: flowId);
          final startedAt = DateTime.now();
          final res = await LlmEntryParser.parseWithLLM(
            text: text.isEmpty
                ? '请识别附件中的消费或收入；有多笔就逐笔提取，没有可记账内容就返回空 entries。'
                : text,
            attachments: attachments,
            config: aiConfig,
            // 用户真实分类（含自建、去隐藏）+ 学习习惯，AI 往用户的分类里归、模仿其选择。
            expenseCats: repo.llmCategoryOptions(TransactionKind.expense),
            incomeCats: repo.llmCategoryOptions(TransactionKind.income),
            learnedHints: repo.llmLearnedHints,
            forceRecord: widget.recordOnly,
          ).timeout(_kAiChatRequestTimeout);
          if (recordRun != null) {
            await repo.recordAiProviderSuccess(
              recordRun!.config.providerId,
              DateTime.now().difference(startedAt).inMilliseconds,
            );
            await repo.updateAiRun(recordRun!.id, status: AiRunStatus.thinking);
            _recordRunEvent(
              repo,
              recordRun!.id,
              AiRunEventType.stageChanged,
              payload: {'stage': 'parsed', 'entries': res.entries.length},
            );
          }
          // 主页始终把模型结果当作记账结果；即使模型误写 intent，也不
          // 能把主页输入转去闲聊或查账。
          if (widget.recordOnly || res.intent == LlmIntent.record) {
            final homeRefund =
                widget.recordOnly ? _matchRefund(repo, text) : null;
            if (homeRefund?.isRefundMutation == true) {
              await _applyRefund(homeRefund!, repo, flowId: flowId);
            } else {
              await _applyRecord(
                res.entries,
                repository: repo,
                flowId: flowId,
                runId: recordRun?.id,
              );
            }
          } else if (res.intent == LlmIntent.query) {
            await _runQuery(
              text,
              repository: repo,
              flowId: flowId,
            ).timeout(_kAiFlowTimeout);
          } else if (res.intent == LlmIntent.chat) {
            // 闲聊：直接走 LlmQuery.ask，不带账目上下文
            await _runQuery(
              text,
              repository: repo,
              chatOnly: true,
              flowId: flowId,
            ).timeout(_kAiFlowTimeout);
          }
          return;
        }
      } catch (error) {
        if (recordRun != null) {
          await repo.recordAiProviderFailure(
            recordRun!.config.providerId,
            _shortAiError(error),
          );
          await repo.markAiRunFailed(
            recordRun!.id,
            code: error is LlmQueryException
                ? 'llm_request_failed'
                : 'parse_failed',
            message: _shortAiError(error),
          );
        }
        // 图片/文件已经持久化到会话，不能把真实上传失败伪装成“本地规则
        // 记好了”。本地解析器看不到附件内容，明确告诉用户失败原因并保留
        // 原消息，用户可直接重试；纯文字仍保留原有离线单笔兜底。
        if (attachments.isNotEmpty) {
          final prompt = _attachmentFailureText(error);
          await _addChatMessage(
            repo,
            role: 'info_err',
            text: prompt,
          );
          _completeThinking(flowId: flowId);
          if (mounted && _ownsFlow(flowId)) {
            setState(() {
              _msgs.add(_InfoMsg(prompt, error: true));
              _busy = false;
            });
            _scrollToLatestUserMessage();
          }
          return;
        }
        // 纯文字调用失败 → 落到下面的离线兜底。
      }
    }
    // 无 key、拒绝上传或调用失败：只在本机解析这笔记录。若是明确退款，
    // 仍使用确定性附着流程，避免离线兜底把退款写成普通收入。
    final homeRefund = widget.recordOnly ? _matchRefund(repo, text) : null;
    if (homeRefund?.isRefundMutation == true) {
      await _applyRefund(homeRefund!, repo, flowId: flowId);
      return;
    }
    final hint = !aiConfig.hasCredential
        ? '还没配 AI key，喵先用本地规则记（单笔）'
        : 'AI 没连上，喵先用本地规则记了（单笔）';
    await _applyRecord(
      [NaturalLanguageEntryParser.parse(text)],
      hint: hint,
      repository: repo,
      flowId: flowId,
      runId: recordRun?.id,
    );
  }

  RefundMatchResult _matchRefund(AppRepository repo, String text) {
    return RefundMatcher.match(
      text: text,
      amount: RefundMatcher.extractAmount(text),
      candidates: [
        for (final transaction in repo.visibleTransactions)
          if (transaction.txKind == TransactionKind.expense &&
              transaction.amount > Decimal.zero)
            RefundCandidate(
              id: transaction.id,
              label: '${transaction.note} ${transaction.categoryNameZh}',
              amount: transaction.amount,
              refunded: repo.refundedAmountOf(transaction.id),
              date: transaction.date,
            ),
      ],
    );
  }

  String _refundPrompt(RefundMatchResult result) {
    switch (result.status) {
      case RefundMatchStatus.missingAmount:
        return '喵知道这是退款，但还缺退款金额。可以说「7月3日淘宝衣服退款 30」';
      case RefundMatchStatus.noMatch:
        return '喵没找到唯一对应的原订单，先不落账。请补充商户或商品和原订单日期';
      case RefundMatchStatus.ambiguous:
        final labels = result.candidates
            .take(2)
            .map((candidate) => candidate.label.trim())
            .where((label) => label.isNotEmpty)
            .join('、');
        return labels.isEmpty
            ? '找到了多笔可能的原订单，先不落账。请再补充商户、商品或日期'
            : '找到了多笔可能的原订单（$labels），先不落账。请再补充日期或商品';
      case RefundMatchStatus.exceedsRemaining:
        final candidate = result.candidate!;
        return '这笔原订单只剩 ${MoneyFormat.string(candidate.remaining)} 可退，'
            '不能登记 ${MoneyFormat.string(result.amount!)}。请核对金额';
      case RefundMatchStatus.notRefundMutation:
      case RefundMatchStatus.matched:
        return '';
    }
  }

  Future<void> _applyRefund(RefundMatchResult result, AppRepository repo,
      {int? flowId}) async {
    _setThinkingKind(_ThinkingKind.recordMatch, flowId: flowId);
    if (result.status != RefundMatchStatus.matched) {
      final prompt = _refundPrompt(result);
      if (mounted) {
        _completeThinking(flowId: flowId);
        setState(() {
          _msgs.add(_InfoMsg(prompt));
          _busy = false;
        });
      }
      await _addChatMessage(repo, role: 'info', text: prompt);
      if (mounted) _scrollToLatestUserMessage();
      return;
    }

    final candidate = result.candidate!;
    final amount = result.amount!;
    final original = repo.visibleTransactions
        .where((transaction) => transaction.id == candidate.id)
        .firstOrNull;
    if (original == null) {
      const prompt = '原订单刚刚发生了变化，退款没有写入。请重新说一次';
      if (mounted) {
        _completeThinking(flowId: flowId);
        setState(() {
          _msgs.add(_InfoMsg(prompt));
          _busy = false;
        });
      }
      await _addChatMessage(repo, role: 'info', text: prompt);
      if (mounted) _scrollToLatestUserMessage();
      return;
    }

    final settlement = await showRefundSettlementSheet(
      context,
      original: original,
      initialAmount: amount,
      maxAmount: candidate.remaining,
      amountEditable: false,
      title: '确认退款到账',
      confirmLabel: '确认退款',
      existingRefunds: repo.refundsOf(original.id),
    );
    if (!mounted) return;
    if (settlement == null) {
      const prompt = '已取消这笔退款，本次没有写入账本';
      _completeThinking(flowId: flowId);
      setState(() {
        _msgs.add(_InfoMsg(prompt));
        _busy = false;
      });
      await _addChatMessage(repo, role: 'info', text: prompt);
      _scrollToLatestUserMessage();
      return;
    }

    late final int refundId;
    try {
      refundId = await repo.refundTransaction(
        original,
        settlement.amount,
        settledAt: settlement.settledAt,
        settlementAccountId: settlement.settlementAccountId,
      );
    } on Object catch (_) {
      const prompt = '原订单或可退金额刚刚发生了变化，退款没有写入。请核对后重试';
      if (mounted) {
        _completeThinking(flowId: flowId);
        setState(() {
          _msgs.add(_InfoMsg(prompt));
          _busy = false;
        });
      }
      await _addChatMessage(repo, role: 'info', text: prompt);
      if (mounted) _scrollToLatestUserMessage();
      return;
    }

    final refundedAfter = repo.refundedAmountOf(original.id);
    final bookName = repo.books
            .where((book) => book.id == original.bookId)
            .firstOrNull
            ?.name ??
        '总账本';
    final message = _RefundMsg(
      originalId: original.id,
      refundId: refundId,
      title: original.note.trim().isEmpty ? '原支出' : original.note.trim(),
      categoryName: original.categoryNameZh,
      bookName: bookName,
      amount: settlement.amount,
      originalAmount: original.amount,
      refundedAfter: refundedAfter,
      date: settlement.settledAt,
      timePrecision: TransactionTimePrecision.dateOnly,
    );
    try {
      await _addChatMessage(
        repo,
        role: 'refund',
        text: _encodeRefundCard(message),
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('refund chat card persistence failed: $error');
      }
    }
    if (mounted && _ownsFlow(flowId)) {
      _completeThinking(flowId: flowId);
      setState(() {
        _msgs.add(message);
        _busy = false;
      });
      _snack('退款已挂到原订单');
      _scrollToLatestUserMessage();
    }
  }

  // ── 记账流：给定解析结果，匹配分类 → 高置信自动入库/否则确认卡 ──────────────
  /// [repository] 由调用方在 await LLM 之前捕获传入：解析期间用户关掉面板后
  /// context.read 会抛，导致整批解析结果被静默丢掉。unmounted 时高置信条目
  /// 仍然入库落库（对齐查账路径 !mounted 也落库的做法），低置信至少留一条
  /// 聊天消息提示，只跳过 setState/UI 部分。
  Future<void> _applyRecord(
    List<ParsedEntry> results, {
    String? hint,
    AppRepository? repository,
    int? flowId,
    String? runId,
  }) async {
    final repo = repository ?? context.read<AppRepository>();
    _setThinkingKind(_ThinkingKind.recordMatch, flowId: flowId);
    final cats = results.map((e) => _matchCat(repo, e)).toList();

    // 高置信且当前工具策略允许时直接入库；多笔、低置信或“按需确认”
    // 策略始终停在提案卡，用户明确点击后才写账。
    final confidenceOk = hint == null &&
        results.length <= 5 &&
        results.every(
          (e) =>
              e.amount != null &&
              e.amount! > Decimal.zero &&
              e.confidence >= 0.9,
        );
    final highConfidence = !AiToolRegistry.needsConfirmation(
      'create_transactions',
      policy: AiToolRegistry.policyFromChatAccess(repo.chatToolAccess),
      recordMode: widget.recordOnly,
      highConfidence: confidenceOk,
      itemCount: results.length,
    );
    _RecordMsg? autoMsg;
    String persistText = '';
    String persistRole = 'info';
    void applyMessages() {
      if (results.isEmpty) {
        _msgs.add(_InfoMsg('喵没看懂这句，换个说法试试？', error: true));
        persistText = '喵没看懂这句，换个说法试试？';
        persistRole = 'info_err';
      } else if (!results.any(
        (e) => e.amount != null && e.amount! > Decimal.zero,
      )) {
        // 认出了内容但没金额 → 追问，而不是弹一张存不了的死卡
        _msgs.add(_InfoMsg('喵没认出金额～再说一句金额吧，比如「奶茶 18」'));
        persistText = '喵没认出金额～再说一句金额吧，比如「奶茶 18」';
      } else if (!mounted && !highConfidence) {
        // 面板已关且这批需要确认卡：不静默丢，留一条提示进聊天历史。
        final n = results.where((e) => e.amount != null).length;
        persistText = '刚才有 $n 笔解析结果因页面关闭未确认，请重新发送';
        _msgs.add(_InfoMsg(persistText));
      } else {
        if (hint != null) _msgs.add(_InfoMsg(hint));
        final msg = _RecordMsg(entries: results, cats: cats, aiRunId: runId);
        _msgs.add(msg);
        if (highConfidence) autoMsg = msg;
        final n = results.where((e) => e.amount != null).length;
        persistText = hint != null ? '$hint · 已记 $n 笔' : '已记 $n 笔';
      }
      _busy = false;
    }

    _completeThinking(flowId: flowId);
    if (mounted) {
      setState(applyMessages);
    } else {
      applyMessages();
    }
    if (persistText.isNotEmpty) {
      await _addChatMessage(repo, role: persistRole, text: persistText);
    }
    if (runId != null && runId.isNotEmpty) {
      if (results.isEmpty) {
        await repo.updateAiRun(
          runId,
          status: AiRunStatus.completed,
          resultJson: jsonEncode({'entries': 0}),
          requiresConfirmation: false,
        );
        _recordRunEvent(
          repo,
          runId,
          AiRunEventType.completed,
          payload: {'entries': 0},
        );
      } else {
        final proposal = AiLedgerProposal(
          runId: runId,
          items: [
            for (var i = 0; i < results.length; i++)
              AiLedgerProposalItem(
                amount: results[i].amount?.toString() ?? '',
                kind: results[i].kind.toJson(),
                categoryKey: cats[i]?.key ?? '',
                date: results[i].date.toIso8601String(),
                note: results[i].note,
                confidence: results[i].confidence,
              ),
          ],
          requiresConfirmation: !highConfidence,
          explanation: hint ?? '',
          createdMs: DateTime.now().millisecondsSinceEpoch,
        );
        await repo.saveAiRunProposal(runId, proposal);
      }
    }
    // 高置信：自动保存（卡片随即进入已存/可撤销态；unmounted 也照样入库）
    if (autoMsg != null) {
      await _save(autoMsg!, repository: repo);
      if (mounted) _snack('喵直接记好了，不对就点卡片上的撤销');
    }
    if (mounted) _scrollToLatestUserMessage();
  }

  // ── 查账流 ──────────────────────────────────────────────────────────────
  /// 喵助手的正常问答统一走 V2 流式链路。Responses 服务商强制使用
  /// `/v1/responses`，DeepSeek 原生和 Claude 原生仍保留各自协议。
  Future<_StreamingAnswer> _askStreamingAnswer({
    required String question,
    required AiProviderConfig config,
    required String transactionsText,
    List<Map<String, String>> priorTurns = const [],
    String? imagePath,
    List<ChatAttachment> attachments = const [],
    int? flowId,
    String? runId,
    AppRepository? repository,
  }) async {
    final result = Completer<_StreamingAnswer>();
    final chunks = StringBuffer();
    final receivedSources = <AiWebSource>[];
    _AnswerMsg? liveMessage;
    var requestExpired = false;
    final runStartedAt = DateTime.now();

    void rememberSources(Iterable<AiWebSource> sources) {
      if (requestExpired || !_ownsFlow(flowId)) return;
      final seen = receivedSources.map((source) => source.url).toSet();
      for (final source in sources) {
        if (source.url.trim().isEmpty || !seen.add(source.url)) continue;
        receivedSources.add(source);
      }
      if (liveMessage != null) {
        liveMessage!.sources
          ..clear()
          ..addAll(receivedSources);
      }
    }

    void showChunk(String chunk) {
      if (requestExpired || !_ownsFlow(flowId) || chunk.isEmpty) return;
      if (chunks.isEmpty) {
        _completeThinking(sources: receivedSources, flowId: flowId);
        _setRunStatus(repository, runId, AiRunStatus.streaming);
        _recordRunEvent(
          repository ?? _chatRepository,
          runId,
          AiRunEventType.stageChanged,
          payload: {'stage': 'streaming'},
        );
      }
      chunks.write(chunk);
      if (!mounted) return;
      if (liveMessage == null) {
        final message = _AnswerMsg(
          chunks.toString(),
          question: question,
          // 内容已经由 SSE 抵达，不能再从头播放一次本地打字机动画。
          shown: true,
          streaming: true,
        );
        liveMessage = message;
        setState(() {
          _msgs.add(message);
        });
        _scrollToLatestUserMessage();
        return;
      }
      setState(() => liveMessage!.text = chunks.toString());
    }

    await LlmQueryV2.askStream(
      question: question,
      config: config,
      transactionsText: transactionsText,
      priorTurns: priorTurns,
      imagePath: imagePath,
      attachments: attachments,
      onChunk: showChunk,
      onSources: (sources) {
        if (requestExpired || !_ownsFlow(flowId)) return;
        rememberSources(sources);
        final thinking = _currentThinkingMsg();
        if (thinking != null && _ownsFlow(flowId)) {
          _addThinkingSources(thinking, sources);
        }
        _recordRunEvent(
          repository ?? _chatRepository,
          runId,
          AiRunEventType.source,
          payload: {'count': sources.length},
        );
      },
      onReasoningSummary: (summary) {
        if (requestExpired || !_ownsFlow(flowId)) return;
        final thinking = _currentThinkingMsg(flowId);
        if (thinking == null || thinking.completed) return;
        final normalized = summary.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (normalized.isEmpty) return;
        final current = thinking.steps.lastOrNull;
        if (current == null) return;
        final combined = '${current.detail} $normalized'.trim();
        current.detail = combined.length > 420
            ? combined.substring(combined.length - 420)
            : combined;
        if (mounted) setState(() {});
        _recordRunEvent(
          repository ?? _chatRepository,
          runId,
          AiRunEventType.reasoning,
          payload: {
            'characters': normalized.length,
          },
        );
      },
      onDone: (answer) {
        if (requestExpired) return;
        // 以服务端最终文本为准。大多数 Responses 网关会发 delta；若没有
        // delta，保留旧路径在调用方完整展示最终回答。
        final completed = answer.isEmpty ? chunks.toString() : answer;
        if (repository != null) {
          unawaited(() async {
            try {
              final providerId = runId == null || runId.isEmpty
                  ? (config.providerId ?? config.type.storageKey)
                  : (await repository.aiRunById(runId))?.config.providerId ??
                      config.providerId ??
                      config.type.storageKey;
              await repository.recordAiProviderSuccess(
                providerId,
                DateTime.now().difference(runStartedAt).inMilliseconds,
              );
            } catch (_) {}
          }());
        }
        if (_ownsFlow(flowId)) {
          _completeThinking(sources: receivedSources, flowId: flowId);
        }
        if (liveMessage != null && mounted && _ownsFlow(flowId)) {
          setState(() {
            liveMessage!
              ..text = completed
              ..streaming = false;
          });
        }
        _setRunStatus(
          repository,
          runId,
          AiRunStatus.completed,
          resultJson: jsonEncode({
            'characters': completed.length,
            'sources': receivedSources.length,
          }),
        );
        _recordRunEvent(
          repository ?? _chatRepository,
          runId,
          AiRunEventType.completed,
          payload: {
            'characters': completed.length,
            'sources': receivedSources.length,
          },
        );
        if (!result.isCompleted) {
          result.complete(
            _StreamingAnswer(
              completed,
              renderedInUi: liveMessage != null,
              sources: List<AiWebSource>.unmodifiable(receivedSources),
              message: liveMessage,
            ),
          );
        }
      },
      onError: (error) {
        if (requestExpired) return;
        if (repository != null) {
          unawaited(() async {
            try {
              final providerId = runId == null || runId.isEmpty
                  ? (config.providerId ?? config.type.storageKey)
                  : (await repository.aiRunById(runId))?.config.providerId ??
                      config.providerId ??
                      config.type.storageKey;
              await repository.recordAiProviderFailure(
                  providerId, error.message);
            } catch (_) {}
          }());
        }
        if (runId != null && runId.isNotEmpty) {
          unawaited(() async {
            try {
              await (repository ?? _chatRepository).markAiRunFailed(
                runId,
                code: 'stream_failed',
                message: error.message,
              );
            } catch (_) {}
          }());
        }
        if (_ownsFlow(flowId)) _completeThinking(flowId: flowId);
        final partial = chunks.toString();
        // A dropped SSE connection must never erase text the user has already
        // read. Finish the visible bubble as an interrupted partial answer;
        // the normal answer actions still expose retry/continue generation.
        if (partial.trim().isNotEmpty) {
          if (liveMessage != null && mounted && _ownsFlow(flowId)) {
            setState(() {
              liveMessage!
                ..text = partial
                ..streaming = false
                ..interrupted = true;
            });
          }
          if (!result.isCompleted) {
            result.complete(_StreamingAnswer(
              partial,
              renderedInUi: liveMessage != null,
              sources: List<AiWebSource>.unmodifiable(receivedSources),
              message: liveMessage,
            ));
          }
          return;
        }
        if (!result.isCompleted) {
          result.completeError(
            LlmQueryException(error.message, statusCode: error.statusCode),
          );
        }
      },
    ).timeout(
      _kAiChatRequestTimeout,
      onTimeout: () {
        requestExpired = true;
        _completeThinking(flowId: flowId);
        if (runId != null && runId.isNotEmpty) {
          unawaited(() async {
            try {
              await (repository ?? _chatRepository).markAiRunFailed(
                runId,
                code: 'timeout',
                message: 'AI 请求超时，请检查网络后重试',
              );
            } catch (_) {}
          }());
        }
        if (!result.isCompleted) {
          result.completeError(
            const LlmQueryException('AI 请求超时，请检查网络后重试'),
          );
        }
      },
    );
    // 某些兼容网关可能在 HTTP 流结束时既不发 completed/DONE，也不触发
    // 解析器回调。不能把这个异常状态传成永久的「思考中」；已有正文就收尾，
    // 没有正文则交给上层统一显示可重试的错误卡。
    if (!result.isCompleted) {
      final partial = chunks.toString();
      if (partial.trim().isNotEmpty) {
        result.complete(
          _StreamingAnswer(
            partial,
            renderedInUi: liveMessage != null,
            sources: List<AiWebSource>.unmodifiable(receivedSources),
            message: liveMessage,
          ),
        );
      } else {
        if (_ownsFlow(flowId)) _completeThinking(flowId: flowId);
        if (runId != null && runId.isNotEmpty) {
          unawaited(() async {
            try {
              await (repository ?? _chatRepository).markAiRunFailed(
                runId,
                code: 'stream_incomplete',
                message: 'AI 流式响应未完成',
              );
            } catch (_) {}
          }());
        }
        result.completeError(const LlmQueryException('AI 流式响应未完成'));
      }
    }
    return result.future;
  }

  Future<void> _runQuery(
    String text, {
    AppRepository? repository,
    ReportJobEntity? resumeJob,
    bool chatOnly = false,
    String? imagePath,
    List<ChatAttachment> attachments = const [],
    int? flowId,
  }) async {
    if (!_ownsFlow(flowId)) return;
    final repo = repository ?? context.read<AppRepository>();
    // A fast-start home can become interactive while the repository is still
    // hydrating.  Do not resolve the provider from its pre-hydration defaults:
    // that made the first tap report "没连上 AI" while the second tap worked
    // after the deferred settings load completed.
    if (repo.isInitializing) {
      await repo.ready;
      if (!mounted || !_ownsFlow(flowId)) return;
    }
    // Claude's Tool access control applies to the whole Chats session, not
    // to a provider. With tools off, a query/report must stay a plain chat
    // request and must not read ledger context or create a report document.
    // A persisted report job owns the provider/model/Effort captured when it
    // was queued.  Foreground recovery must use that snapshot too; otherwise
    // a later Chats selection silently changes which service receives the
    // report.
    final resumedReportConfig =
        resumeJob == null ? null : repo.aiProviderConfigForReportJob(resumeJob);
    if (resumeJob != null && resumedReportConfig == null) {
      const prompt = '报告使用的服务商或模型已失效，请修复该账号后重试。';
      _completeThinking(flowId: flowId);
      if (mounted && _ownsFlow(flowId)) {
        setState(() {
          _msgs.add(_InfoMsg(prompt, error: true));
          _busy = false;
        });
        _scrollToLatestUserMessage();
      }
      return;
    }
    var aiConfig = resumeJob == null ? _chatConfig(repo) : resumedReportConfig!;

    // 闲聊模式：直接发送，不带账目上下文，不走报告流程
    if (chatOnly) {
      if (!aiConfig.hasCredential) {
        if (mounted && _ownsFlow(flowId)) {
          _completeThinking(flowId: flowId);
          setState(() {
            _msgs.add(_InfoMsg('还没有可用的喵助手模型，请先到 AI 账号设置中配置'));
            _busy = false;
          });
        }
        return;
      }
      // 即使闲聊不带账本，用户的文字/图片仍会发送给实际服务商；隐私
      // 同意按接收方隔离，不能因为没有账本上下文就绕过授权。
      if (!repo.aiPrivacyAcceptedFor(aiConfig)) {
        final consented = mounted &&
            await ensureAiPrivacyConsent(
              context,
              config: aiConfig,
            );
        if (!consented) {
          const prompt = '未同意 AI 隐私说明，喵不会把这条消息发出去。';
          _completeThinking(flowId: flowId);
          if (mounted && _ownsFlow(flowId)) {
            setState(() {
              _msgs.add(_InfoMsg(prompt));
              _busy = false;
            });
            _scrollToLatestUserMessage();
          }
          return;
        }
      }
      _setThinkingKind(_ThinkingKind.queryAnswer, flowId: flowId);
      _markModelThinkingStarted(flowId);
      final queryRun = await _beginAiRun(
        repository: repo,
        mode: AiRunMode.chat,
        config: aiConfig,
        input: text,
        attachments: attachments,
        flowId: flowId,
      );
      final memoryPrompt = repo.aiMemoryPromptBlock(
        text,
        sessionId: _sessionId,
      );
      final matchedMemories = repo.aiMemoriesForPrompt(
        text,
        sessionId: _sessionId,
      );
      String answer;
      var answerAlreadyRendered = false;
      var answerSources = <AiWebSource>[];
      _AnswerMsg? streamedMessage;
      try {
        final streamed = await _askStreamingAnswer(
          question: text,
          config: aiConfig,
          transactionsText: memoryPrompt,
          // _send 已把本轮用户消息放进 _msgs；askStream 会在请求末尾
          // 自己追加 [question]，因此上下文只带此前轮次，不能重复当前问题。
          priorTurns: _recentTurns(excludeNewestUser: true),
          imagePath: imagePath,
          attachments: attachments,
          flowId: flowId,
          runId: queryRun?.id,
          repository: repo,
        );
        answer = streamed.text;
        answerAlreadyRendered = streamed.renderedInUi;
        answerSources = streamed.sources;
        streamedMessage = streamed.message;
        for (final memory in matchedMemories) {
          unawaited(repo.markAiMemoryUsed(memory.id));
        }
      } on LlmQueryException catch (e) {
        answer = _friendlyAiError(e);
        if (queryRun != null) {
          await repo.markAiRunFailed(
            queryRun.id,
            code: 'llm_request_failed',
            message: e.message,
          );
        }
      } catch (e) {
        answer = '喵没连上 AI（${_shortAiError(e)}），待会儿再问问？';
        if (queryRun != null) {
          await repo.markAiRunFailed(
            queryRun.id,
            code: 'request_failed',
            message: _shortAiError(e),
          );
        }
      }
      if (!_ownsFlow(flowId)) return;
      final answerRowId = await _awaitChatPersistence(_addChatMessage(
        repo,
        role: 'answer',
        text: answer,
        question: text,
        sources: answerSources,
      ));
      _AnswerMsg? createdMessage;
      void attachRowId(int rowId) {
        streamedMessage?.chatRowId = rowId;
        createdMessage?.chatRowId = rowId;
      }

      if (mounted && _ownsFlow(flowId)) {
        _completeThinking(flowId: flowId);
        setState(() {
          if (!answerAlreadyRendered) {
            createdMessage = _AnswerMsg(
              answer,
              question: text,
              sources: answerSources,
            );
            _msgs.add(createdMessage!);
          }
          _busy = false;
        });
        _scrollToLatestUserMessage();
      }
      if (answerRowId != null) attachRowId(answerRowId);
      return;
    }
    final reportType = resumeJob?.type ?? _reportTypeOf(text);
    final reportPeriod = resumeJob != null
        ? DateTimeRange(start: resumeJob.periodStart, end: resumeJob.periodEnd)
        : (reportType == null
            ? null
            : _reportPeriodOf(reportType, DateTime.now(), question: text));
    final reportTitle = resumeJob?.title ??
        (reportType == null ? null : _reportTitleOf(reportType, reportPeriod!));
    final reportBookId = resumeJob != null
        ? resumeJob.bookId
        : (reportType == null ? null : repo.currentBook?.id);
    if (reportType != null && !repo.aiSkillEnabled('report_writer')) {
      const prompt = '报告生成助手已关闭，请先在 AI 设置中重新开启。';
      _completeThinking(flowId: flowId);
      if (mounted && _ownsFlow(flowId)) {
        setState(() {
          _msgs.add(_InfoMsg(prompt));
          _busy = false;
        });
        _scrollToLatestUserMessage();
      }
      return;
    }
    if (!chatOnly &&
        reportType == null &&
        !repo.aiSkillAllowsTool('ledger_analyst', 'read_ledger')) {
      const prompt = '账本分析助手已关闭，请先在 AI 设置中重新开启。';
      _completeThinking(flowId: flowId);
      if (mounted && _ownsFlow(flowId)) {
        setState(() {
          _msgs.add(_InfoMsg(prompt));
          _busy = false;
        });
        _scrollToLatestUserMessage();
      }
      return;
    }
    // 报告也跟随喵助手当前选中的服务商和模型；普通记账解析仍使用独立配置。
    // 隐私闸门下沉到每个真正上传数据的入口：查账/报告都要先同意，不能只靠
    // _send 的记账分支拦。未同意就不发起请求；resume 的任务保持 pending
    // （启动恢复路径已在 _resumePendingReportJob 里提前拦掉，不会到这弹窗）。
    if (aiConfig.hasCredential && !repo.aiPrivacyAcceptedFor(aiConfig)) {
      final consented = mounted &&
          await ensureAiPrivacyConsent(
            context,
            config: aiConfig,
          );
      if (!consented) {
        const prompt = '未同意 AI 隐私说明，喵不会把账本内容发出去。';
        void declineUi() {
          _msgs.add(_InfoMsg(prompt));
          _busy = false;
        }

        _completeThinking(flowId: flowId);
        if (mounted && _ownsFlow(flowId)) {
          setState(declineUi);
          _scrollToLatestUserMessage();
        } else {
          declineUi();
        }
        return;
      }
    }
    final queryRun = aiConfig.hasCredential
        ? await _beginAiRun(
            repository: repo,
            mode: reportType == null ? AiRunMode.query : AiRunMode.report,
            config: aiConfig,
            input: text,
            attachments: attachments,
            flowId: flowId,
          )
        : null;
    var reportJob = resumeJob;
    ReportGenerationLease? reportLease;
    if (reportType != null && aiConfig.hasCredential) {
      try {
        final baseLease = await repo.acquireReportGenerationLease();
        reportJob ??= await repo.guardReportGeneration(
          baseLease,
          () => repo.createReportJob(
            question: text,
            type: reportType,
            title: reportTitle!,
            periodStart: reportPeriod!.start,
            periodEnd: reportPeriod.end,
            bookId: reportBookId,
            sessionId: _sessionId,
          ),
        );
        final activeJob = reportJob;
        if (activeJob == null) {
          throw StateError('report job was not created');
        }
        reportLease = baseLease.bind(
          jobId: activeJob.id,
          jobUuid: activeJob.uuid,
        );
      } on ReportGenerationInvalidated {
        _handleInvalidatedReport(flowId: flowId);
        return;
      }
      final activeJob = reportJob;
      if (activeJob == null) {
        _handleInvalidatedReport(flowId: flowId);
        return;
      }
      _observedReportJobId = activeJob.id;
      _observedReportFlowId = flowId;
      final scheduled = await ReportTaskScheduler.schedule(
        repo,
        activeJob,
        lease: reportLease,
      );
      if (scheduled) {
        _setRunStatus(repo, queryRun?.id, AiRunStatus.background);
        _recordRunEvent(
          repo,
          queryRun?.id,
          AiRunEventType.stageChanged,
          payload: {'stage': 'background'},
        );
        _setThinkingKind(_ThinkingKind.reportCollect, flowId: flowId);
        _setThinkingCanContinueInBackground(true, flowId: flowId);
        _restartThinkingTicker(flowId: flowId);
        _startReportPolling();
        return;
      }
      if (!ReportJobRuntime.claim(reportLease.runtimeKey)) {
        // Another foreground/worker owner is already generating this report.
        // Keep observing its persisted job, but do not leave this flow in an
        // unowned, permanently spinning state.
        _setThinkingCanContinueInBackground(true, flowId: flowId);
        _setRunStatus(repo, queryRun?.id, AiRunStatus.background);
        _restartThinkingTicker(flowId: flowId);
        _startReportPolling();
        return;
      }
      await _setReportJobStage(
        repo,
        reportJob,
        lease: reportLease,
        status: 'running',
        stage: 'collect',
      );
    }
    _setThinkingKind(
      reportType == null
          ? _ThinkingKind.queryCollect
          : _ThinkingKind.reportCollect,
      flowId: flowId,
    );
    var aiAnswered = false;
    var answerAlreadyRendered = false;
    var answerSources = <AiWebSource>[];
    _AnswerMsg? streamedMessage;
    final priorTurns = _recentTurns(excludeNewestUser: true);
    String answer;
    if (!aiConfig.hasCredential) {
      answer = '查账要先配 AI key 哦～去「我的 → AI 记账设置」填一下，喵就能帮你分析啦';
    } else {
      try {
        late final String transactionsText;
        late final AiContextSnapshot contextSnapshot;
        final memoryMatches = reportType == null
            ? repo.aiMemoriesForPrompt(text, sessionId: _sessionId)
            : const <AiMemory>[];
        if (reportType == null) {
          final ledgerContext = _buildTxnContext(repo, question: text);
          final memoryPrompt = repo.aiMemoryPromptBlock(
            text,
            sessionId: _sessionId,
          );
          transactionsText = [ledgerContext, memoryPrompt]
              .where((value) => value.trim().isNotEmpty)
              .join('\n\n');
          contextSnapshot = AiContextInspector.inspect(
            question: text,
            historyTurns: priorTurns.length,
            ledgerRows: repo.visibleTransactions.length,
            memoryItems: memoryMatches.length,
            attachmentCount: attachments.length,
            estimatedPromptCharacters: transactionsText.length +
                text.length +
                priorTurns.fold<int>(
                    0, (sum, turn) => sum + (turn['content']?.length ?? 0)),
            maxTokens: _kAiContextTokenBudget,
          );
        } else {
          await repo.guardReportGeneration(reportLease!, () async {
            transactionsText = _buildReportContext(
              repo,
              title: reportTitle!,
              type: reportType,
              period: reportPeriod!,
              bookId: reportBookId,
            );
          });
          contextSnapshot = AiContextInspector.inspect(
            question: text,
            historyTurns: priorTurns.length,
            ledgerRows: repo.visibleTransactions.length,
            memoryItems: repo.categoryMemories.length,
            attachmentCount: attachments.length,
            estimatedPromptCharacters: transactionsText.length +
                text.length +
                priorTurns.fold<int>(
                    0, (sum, turn) => sum + (turn['content']?.length ?? 0)),
            maxTokens: _kAiContextTokenBudget,
          );
        }
        if (queryRun != null) {
          await repo.updateAiRun(
            queryRun.id,
            contextDigest: contextSnapshot.digest,
          );
          _recordRunEvent(
            repo,
            queryRun.id,
            AiRunEventType.contextReady,
            payload: {
              'estimatedTokens': contextSnapshot.estimatedTokens,
              'blocks': contextSnapshot.blocks.length,
              'truncated': contextSnapshot.truncated,
            },
          );
        }
        if (reportType == null) {
          _setThinkingKind(_ThinkingKind.queryAnswer, flowId: flowId);
          final streamed = await _askStreamingAnswer(
            question: text,
            config: aiConfig,
            transactionsText: transactionsText,
            // 同上：避免把刚发送的问题作为历史又追加一遍。
            priorTurns: priorTurns,
            imagePath: imagePath,
            flowId: flowId,
            runId: queryRun?.id,
            repository: repo,
          );
          answer = streamed.text;
          answerAlreadyRendered = streamed.renderedInUi;
          answerSources = streamed.sources;
          streamedMessage = streamed.message;
          for (final memory in memoryMatches) {
            unawaited(repo.markAiMemoryUsed(memory.id));
          }
        } else {
          _setThinkingKind(_ThinkingKind.reportGenerate, flowId: flowId);
          await _setReportJobStage(
            repo,
            reportJob,
            lease: reportLease,
            stage: 'generate',
          );
          answer = await _askReportOrBuildLocalFallback(
            repo: repo,
            reportTitle: reportTitle!,
            reportType: reportType,
            reportPeriod: reportPeriod!,
            reportBookId: reportBookId,
            reportJob: reportJob,
            reportLease: reportLease,
            config: aiConfig,
            transactionsText: transactionsText,
            flowId: flowId,
          );
        }
        // 报告类本地兜底也应该生成文档卡片，避免用户只看到“没连上”。
        aiAnswered = true;
      } on ReportGenerationInvalidated {
        _releaseReportJob(reportJob, reportLease);
        _handleInvalidatedReport(flowId: flowId);
        return;
      } on LlmQueryException catch (e) {
        answer = _friendlyAiError(e);
        if (queryRun != null) {
          await repo.markAiRunFailed(
            queryRun.id,
            code: 'llm_request_failed',
            message: e.message,
          );
        }
      } catch (e) {
        answer = '喵没连上 AI（${_shortAiError(e)}），待会儿再问问？';
        if (queryRun != null) {
          await repo.markAiRunFailed(
            queryRun.id,
            code: 'request_failed',
            message: _shortAiError(e),
          );
        }
      }
    }
    // 保留 markdown 原文，交给 _AnswerBubble 轻量渲染（**加粗** / 列表 / 标题）。
    // 报告生成时间较长，用户切换页面时也要先落库，不能因为页面 dispose 就丢结果。
    if (reportType != null &&
        _shouldCreateReportDocument(
          reportType: reportType,
          aiAnswered: aiAnswered,
        )) {
      await _saveGeneratedReport(
        repo: repo,
        reportJob: reportJob,
        reportLease: reportLease,
        reportTitle: reportTitle!,
        answer: answer,
        question: text,
        flowId: flowId,
      );
      _setRunStatus(
        repo,
        queryRun?.id,
        AiRunStatus.completed,
        resultJson: jsonEncode({'report': true}),
      );
      _recordRunEvent(
        repo,
        queryRun?.id,
        AiRunEventType.completed,
        payload: {'report': true},
      );
      return;
    }
    if (reportJob != null) {
      await _setReportJobStage(
        repo,
        reportJob,
        lease: reportLease,
        status: 'failed',
        error: answer,
      );
    }
    try {
      if (!_ownsFlow(flowId)) return;
      final answerRowId = await _awaitChatPersistence(_addChatMessage(
        repo,
        role: 'answer',
        text: answer,
        question: text,
        sources: answerSources,
      ));
      _AnswerMsg? createdMessage;
      void attachRowId(int rowId) {
        streamedMessage?.chatRowId = rowId;
        createdMessage?.chatRowId = rowId;
      }

      _completeThinking(flowId: flowId);
      void addAnswerMessage({required bool animate}) {
        if (!answerAlreadyRendered) {
          createdMessage = _AnswerMsg(
            answer,
            question: text,
            shown: !animate,
            sources: answerSources,
          );
          _msgs.add(createdMessage!);
        }
        _busy = false;
      }

      if (!_ownsFlow(flowId)) return;
      if (!mounted) {
        addAnswerMessage(animate: false);
        return;
      }
      setState(() => addAnswerMessage(animate: !answerAlreadyRendered));
      _scrollToLatestUserMessage();
      if (answerRowId != null) attachRowId(answerRowId);
    } finally {
      _releaseReportJob(reportJob, reportLease);
    }
  }

  Future<void> _runQuerySafely(
    int flowId,
    String text, {
    AppRepository? repository,
    ReportJobEntity? resumeJob,
    bool chatOnly = false,
    String? imagePath,
    List<ChatAttachment> attachments = const [],
  }) async {
    try {
      await _runQuery(
        text,
        repository: repository,
        resumeJob: resumeJob,
        chatOnly: chatOnly,
        imagePath: imagePath,
        attachments: attachments,
        flowId: flowId,
      ).timeout(_kAiFlowTimeout);
    } catch (error, stackTrace) {
      await _handleUnexpectedFlowError(flowId, error, stackTrace);
    } finally {
      if (!_keepsBackgroundFlow(flowId)) _finishFlow(flowId);
    }
  }

  Future<void> _saveGeneratedReport({
    required AppRepository repo,
    required ReportJobEntity? reportJob,
    required ReportGenerationLease? reportLease,
    required String reportTitle,
    required String answer,
    required String question,
    int? flowId,
  }) async {
    try {
      if (!_ownsFlow(flowId)) return;
      if (reportJob == null || reportLease == null) {
        throw StateError('report job lease is missing');
      }
      _setThinkingKind(_ThinkingKind.reportSave, flowId: flowId);
      await _setReportJobStage(
        repo,
        reportJob,
        lease: reportLease,
        stage: 'save',
      );
      final markdown = _reportMarkdown(reportTitle, answer);
      final summary = _reportSummary(markdown);
      final uiDatabaseGeneration = repo.databaseGeneration;
      final report = await repo.guardReportGeneration(
        reportLease,
        () => repo.completeReportJob(
          jobId: reportJob.id,
          expectedJobUuid: reportJob.uuid,
          summary: summary,
          markdown: markdown,
        ),
      );
      if (repo.databaseGeneration != uiDatabaseGeneration) {
        _handleInvalidatedReport(flowId: flowId);
        return;
      }
      if (!_ownsFlow(flowId)) return;
      void addReportMessage({required bool animate}) {
        _msgs.add(
          _ReportMsg(
            report,
            summary: summary,
            question: question,
            shown: !animate,
          ),
        );
        _busy = false;
      }

      _completeThinking(flowId: flowId);
      if (!mounted) {
        addReportMessage(animate: false);
        _observedReportJobId = null;
        _observedReportFlowId = null;
        _stopReportPolling();
        return;
      }
      setState(() => addReportMessage(animate: true));
      _observedReportJobId = null;
      _observedReportFlowId = null;
      _stopReportPolling();
      _scrollToLatestUserMessage();
    } on ReportGenerationInvalidated {
      _handleInvalidatedReport(flowId: flowId);
    } catch (error) {
      if (!_ownsFlow(flowId)) return;
      await _setReportJobStage(
        repo,
        reportJob,
        lease: reportLease,
        status: 'failed',
        error: error.toString(),
      );
      void addFailureMessage() {
        _msgs.add(_InfoMsg('报告保存失败，请稍后重新生成', error: true));
        _busy = false;
      }

      _completeThinking(flowId: flowId);
      if (mounted) {
        setState(addFailureMessage);
      } else {
        addFailureMessage();
      }
      _observedReportJobId = null;
      _observedReportFlowId = null;
      _stopReportPolling();
    } finally {
      _releaseReportJob(reportJob, reportLease);
    }
  }

  Future<void> _setReportJobStage(
    AppRepository repo,
    ReportJobEntity? job, {
    ReportGenerationLease? lease,
    String? status,
    String? stage,
    String? error,
    int? reportId,
  }) async {
    if (job == null) return;
    try {
      Future<void> update() => repo.updateReportJob(
            job.id,
            expectedUuid: job.uuid,
            status: status,
            stage: stage,
            error: error,
            reportId: reportId,
          );
      if (lease == null) {
        await update();
      } else {
        await repo.guardReportGeneration(lease, update);
      }
    } catch (_) {
      // Job metadata must never block generation or saving the report itself.
    }
  }

  Future<void> _persistReportModelStarted(
    AppRepository repo,
    ReportJobEntity? job,
    ReportGenerationLease? lease,
    int? flowId,
  ) async {
    if (job == null) return;
    final startedAt = _currentThinkingMsg(flowId)?.modelStartedAt;
    if (startedAt == null) return;
    Future<int?> write() => repo.markReportJobModelStarted(
          job.id,
          expectedUuid: job.uuid,
          startedMs: startedAt.millisecondsSinceEpoch,
        );
    try {
      late final int? persistedMs;
      if (lease == null) {
        persistedMs = await write();
      } else {
        persistedMs = await repo.guardReportGeneration(lease, write);
      }
      // Another foreground/worker owner may win the compare-and-set with an
      // earlier timestamp. Reflect the durable winner locally so this panel's
      // summary agrees with the next poll/reopen.
      final current = _currentThinkingMsg(flowId);
      if (current != null && persistedMs != null) {
        current.modelStartedAt =
            DateTime.fromMillisecondsSinceEpoch(persistedMs);
        if (mounted && _ownsFlow(flowId)) setState(() {});
      }
    } catch (_) {
      // The worker/service also records a missing timestamp immediately before
      // its model call. A transient foreground write failure must not prevent
      // the report from running or turn a recoverable UI into an error.
    }
  }

  void _releaseReportJob(
    ReportJobEntity? job,
    ReportGenerationLease? lease,
  ) {
    if (job == null || lease == null) return;
    ReportJobRuntime.release(lease.runtimeKey);
  }

  void _handleInvalidatedReport({int? flowId}) {
    if (!_ownsFlow(flowId)) return;
    void clearPendingUi() {
      _busy = false;
      _observedReportJobId = null;
      _observedReportFlowId = null;
      _stopReportPolling();
    }

    _completeThinking(flowId: flowId);
    if (mounted) {
      setState(clearPendingUi);
    } else {
      clearPendingUi();
    }
  }

  Future<String> _askReportOrBuildLocalFallback({
    required AppRepository repo,
    required String reportTitle,
    required String reportType,
    required DateTimeRange reportPeriod,
    required int? reportBookId,
    required ReportJobEntity? reportJob,
    required ReportGenerationLease? reportLease,
    required AiProviderConfig config,
    required String transactionsText,
    int? flowId,
  }) async {
    LlmQueryException? firstError;
    // This is the first point where the foreground flow is about to let a
    // provider process the report. Do not timestamp queueing, privacy
    // confirmation, context collection, or WorkManager hand-off as model
    // thinking time. The worker applies the same rule in
    // ReportGenerationService.generate().
    final modelStartedAt = DateTime.now();
    _markModelThinkingStarted(flowId, value: modelStartedAt);
    await _persistReportModelStarted(
      repo,
      reportJob,
      reportLease,
      flowId,
    );
    try {
      return await LlmQuery.askReport(
        reportTitle: reportTitle,
        reportType: reportType,
        config: config,
        transactionsText: transactionsText,
      );
    } on LlmQueryException catch (e) {
      firstError = e;
      debugPrint('askReport failed: ${e.message}');
    }

    _setThinkingKind(_ThinkingKind.reportFallback, flowId: flowId);
    await _setReportJobStage(
      repo,
      reportJob,
      lease: reportLease,
      stage: 'fallback',
    );
    try {
      return await LlmQuery.ask(
        question: '请生成一份完整 Markdown 报告：$reportTitle。'
            '不要只写聊天短回复，要包含摘要、核心指标、分类分析、异常关注和行动建议。',
        config: config,
        transactionsText: transactionsText,
      );
    } on LlmQueryException catch (e) {
      debugPrint('report fallback ask failed: ${e.message}');
      return _buildLocalReportFallback(
        repo,
        title: reportTitle,
        type: reportType,
        period: reportPeriod,
        aiError: e.message,
        firstAiError: firstError.message,
        bookId: reportBookId,
      );
    }
  }

  /// 把账目整理成给 LLM 的上下文。
  /// 口径和统计页一致：「不计入收支」的记录不喂给 AI，答数才对得上统计。
  /// 问题里带时间（上个月/今年/5月/近30天…）就只喂那段的账（最多 240 条）。
  /// 没带时间时先对全库做关键词检索，再用最近账目补足上下文；因此旧备注不会
  /// 因为不在最近 80 条里就被误判为“不存在”。
  String _buildTxnContext(AppRepository repo, {required String question}) {
    final now = DateTime.now();
    final range = QueryRange.parse(question, now);
    final categoryScope = _aiCategoryScopeFor(repo, question);
    final comparisonBlock = _buildMonthComparisonBlock(
      repo,
      question,
      now,
      categoryScope: categoryScope,
    );
    // 只喂「可见订单」（退款行已挂到原订单里，不单独喂），且金额取**净额**
    // （原额−已退）。否则 AI 会看到散落的退款负数行 → 无中生有「某某退款」、
    // 又把已退到 140 的订单仍当 150 算。喂净额=AI 看到的就是用户实际花的。
    // The repository's visible reference is already ordered by
    // date-desc/id-desc at the SQL/incremental-refresh boundary. Re-sorting
    // this full list for every AI question was an avoidable O(n log n) stall;
    // preserve that invariant while filtering excluded rows.
    final visible = repo.visibleTransactionsRef
        .where((t) => !t.excluded)
        .toList(growable: false);
    // 时间范围和分类范围是两个正交筛选条件；之前只应用了前者，导致
    // “这个月购物花了多少”把餐饮、交通等全月支出也算进来了。
    final allTxns = categoryScope == null
        ? visible
        : visible
            .where((t) => categoryScope.matches(
                  categoryId: t.categoryId,
                  categoryKey: t.categoryKey,
                ))
            .toList(growable: false);
    var txns = allTxns;
    List<TransactionEntity> historicalMatches = const [];
    var limit = 240;
    if (range != null) {
      txns = txns.where((t) => range.covers(t.date)).toList();
    } else if (categoryScope != null) {
      // 没有时间词时，分类本身就是全库检索条件；绝不能再用最近账目补
      // 其它分类，否则模型又会看到与问题无关的流水。
      historicalMatches = allTxns;
      txns = historicalMatches.take(limit).toList(growable: false);
    } else {
      historicalMatches = allTxns
          .where((t) => aiQuestionMatchesTransaction(question, t))
          .toList(growable: false);
      if (historicalMatches.isEmpty) {
        limit = 80;
      } else {
        final selected = <TransactionEntity>[];
        final selectedIds = <int>{};
        for (final transaction in historicalMatches) {
          if (selected.length >= limit) break;
          selected.add(transaction);
          selectedIds.add(transaction.id);
        }
        for (final transaction in visible) {
          if (selected.length >= limit) break;
          if (selectedIds.add(transaction.id)) selected.add(transaction);
        }
        txns = selected;
      }
    }
    final sb = StringBuffer();
    sb.writeln('今天是 ${now.year}-${now.month}-${now.day}。');
    if (categoryScope != null) {
      sb.writeln(
        '【分类筛选已锁定】本次只统计支出分类「${categoryScope.labels.join('、')}」'
        '及其子分类；其它分类一律不计入下面的金额和明细。',
      );
    }
    sb.writeln(_buildBudgetContextBlock(
      repo,
      question: question,
      now: now,
      rangeStart: range?.start,
      rangeEndInclusive: range?.end,
    ));
    if (comparisonBlock.isNotEmpty) {
      sb.writeln(comparisonBlock);
    }
    if (range != null) {
      sb.writeln(
        '以下是 ${range.start.year}-${range.start.month}-${range.start.day} '
        '至 ${range.end.year}-${range.end.month}-${range.end.day} 的账目'
        '${txns.length > limit ? '（明细超长已截断只列最近 $limit 条，但下面的合计是全量算的）' : ''}。',
      );
      // 合计在代码里按净额算准（和统计页完全一致）。LLM 自己加几十个数会算错，
      // 所以回答"总共花了多少"必须直接引用这个数，不要自己重新加总。
      var totalExp = Decimal.zero;
      var totalInc = Decimal.zero;
      for (final t in txns) {
        if (t.txKind == TransactionKind.expense) {
          totalExp += repo.netAmountOf(t);
        } else if (t.txKind == TransactionKind.income) {
          totalInc += t.amount;
        }
      }
      sb.writeln(
        '【${categoryScope == null ? '本期' : '本期分类'}准确合计（务必直接引用，不要自己再加总明细）】'
        '支出 ${MoneyFormat.string(totalExp)}，'
        '收入 ${MoneyFormat.string(totalInc)}。',
      );
    } else if (categoryScope != null) {
      var matchedExpense = Decimal.zero;
      var matchedIncome = Decimal.zero;
      for (final transaction in historicalMatches) {
        if (transaction.txKind == TransactionKind.expense) {
          matchedExpense += repo.netAmountOf(transaction);
        } else if (transaction.txKind == TransactionKind.income) {
          matchedIncome += transaction.amount;
        }
      }
      sb.writeln(
        '未指定日期，已检索全库符合分类范围的 ${historicalMatches.length} 笔账目。',
      );
      sb.writeln(
        '【分类查询准确合计（务必直接引用）】支出 ${MoneyFormat.string(matchedExpense)}，'
        '收入 ${MoneyFormat.string(matchedIncome)}。',
      );
    } else if (historicalMatches.isNotEmpty) {
      var matchedExpense = Decimal.zero;
      var matchedIncome = Decimal.zero;
      for (final transaction in historicalMatches) {
        if (transaction.txKind == TransactionKind.expense) {
          matchedExpense += repo.netAmountOf(transaction);
        } else if (transaction.txKind == TransactionKind.income) {
          matchedIncome += transaction.amount;
        }
      }
      sb.writeln(
        '未指定日期，已检索全部 ${allTxns.length} 笔可见账目，'
        '关键词命中 ${historicalMatches.length} 笔；下面优先列出命中项，再补最近账目。',
      );
      sb.writeln(
        '【全库关键词命中准确合计】支出 ${MoneyFormat.string(matchedExpense)}，'
        '收入 ${MoneyFormat.string(matchedIncome)}。',
      );
    } else {
      sb.writeln(
        '未指定日期，已检索全部 ${allTxns.length} 笔可见账目，但没有识别到明确关键词；'
        '下面仅列最近 $limit 笔，不能据此断言更早记录不存在。',
      );
    }
    sb.writeln(
      '账目数据（金额均为退款后的净额，直接用即可，不必再减退款）'
      '（格式：日期|收支|分类|金额元|备注）：',
    );
    for (final t in txns.take(limit)) {
      final k = t.txKind == TransactionKind.income
          ? '收'
          : (t.txKind == TransactionKind.transfer ? '转' : '支');
      final d =
          '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}-${t.date.day.toString().padLeft(2, '0')}';
      // 净额：支出订单扣掉已退部分；收入/转账无退款，net==原额。
      final net =
          t.txKind == TransactionKind.expense ? repo.netAmountOf(t) : t.amount;
      sb.writeln(
        '$d|$k|${t.categoryNameZh}|${MoneyFormat.string(net)}'
        '|${sanitizeNoteForLlm(t.note)}',
      );
    }
    return sb.toString();
  }

  String _buildBudgetContextBlock(
    AppRepository repo, {
    required String question,
    required DateTime now,
    DateTime? rangeStart,
    DateTime? rangeEndInclusive,
  }) {
    late final BudgetWindowResult result;
    if (question.contains('周期')) {
      result = repo.currentBudgetCycle(now: now);
    } else if (question.contains('周')) {
      result = repo.budgetWindow(BudgetWindowQuery(
        viewKind: BudgetViewKind.calendarWeek,
        bookId: repo.currentBookId,
        referenceDate: rangeStart ?? now,
        asOf: now,
        knowledgeCutoff: now,
        calendarTimezone: 'device-local',
      ));
    } else if (rangeStart != null && rangeEndInclusive != null) {
      final isCalendarMonth = rangeStart.day == 1 &&
          rangeStart.year == rangeEndInclusive.year &&
          rangeStart.month == rangeEndInclusive.month &&
          rangeEndInclusive.day ==
              DateTime(rangeStart.year, rangeStart.month + 1, 0).day;
      result = isCalendarMonth
          ? repo.budgetForCalendarMonth(rangeStart, asOf: now)
          : repo.budgetWindow(BudgetWindowQuery(
              viewKind: BudgetViewKind.custom,
              bookId: repo.currentBookId,
              referenceDate: rangeStart,
              customEndExclusive:
                  rangeEndInclusive.add(const Duration(days: 1)),
              asOf: now,
              knowledgeCutoff: now,
              calendarTimezone: 'device-local',
            ));
    } else {
      result = repo.budgetForCalendarMonth(now, asOf: now);
    }
    return _formatBudgetContext(result);
  }

  String _formatBudgetContext(BudgetWindowResult result) {
    return formatBudgetContextForAi(result);
  }

  String _buildReportContext(
    AppRepository repo, {
    required String title,
    required String type,
    required DateTimeRange period,
    int? bookId,
  }) {
    final start = DateTime(
      period.start.year,
      period.start.month,
      period.start.day,
    );
    final endInclusive = DateTime(
      period.end.year,
      period.end.month,
      period.end.day,
    );
    final endExclusive = endInclusive.add(const Duration(days: 1));
    final days = endExclusive.difference(start).inDays.clamp(1, 366);
    final prevStart = start.subtract(Duration(days: days));
    final prevEnd = start;

    bool inRange(TransactionEntity t, DateTime s, DateTime e) =>
        !t.excluded && !t.date.isBefore(s) && t.date.isBefore(e);

    final visibleTransactions = bookId == null
        ? repo.visibleTransactions
        : repo.visibleTransactionsForBookView(bookId);
    final records =
        bookId == null ? repo.allRecordsRef : repo.recordsForBookView(bookId);
    Decimal netOf(TransactionEntity transaction) => bookId == null
        ? repo.netAmountOf(transaction)
        : repo.netAmountAcrossBooks(transaction);
    final current = visibleTransactions
        .where((t) => inRange(t, start, endExclusive))
        .toList(growable: false);
    final previous = visibleTransactions.where(
      (t) => inRange(t, prevStart, prevEnd),
    );
    final categorySummary = StatisticsEngine.rangeSummary(
      records,
      start: start,
      end: endInclusive,
    );
    final reportNow = DateTime.now();
    final reportBudget = repo.budgetWindow(BudgetWindowQuery(
      viewKind: BudgetViewKind.custom,
      bookId: bookId ?? repo.currentBookId,
      referenceDate: start,
      customEndExclusive: endExclusive,
      asOf: reportNow,
      knowledgeCutoff: reportNow,
      calendarTimezone: 'device-local',
    ));

    ({Decimal expense, Decimal income, int expenseCount}) summarize(
      Iterable<TransactionEntity> rows,
    ) {
      var expense = Decimal.zero;
      var income = Decimal.zero;
      var expenseCount = 0;
      for (final t in rows) {
        if (t.txKind == TransactionKind.expense) {
          final net = netOf(t);
          if (net > Decimal.zero) {
            expense += net;
            expenseCount++;
          }
        } else if (t.txKind == TransactionKind.income) {
          income += t.amount;
        }
      }
      return (expense: expense, income: income, expenseCount: expenseCount);
    }

    final curSummary = summarize(current);
    final prevSummary = summarize(previous);
    final avgExpense = curSummary.expenseCount == 0
        ? Decimal.zero
        : Decimal.parse(
            (curSummary.expense.toDouble() / curSummary.expenseCount)
                .toStringAsFixed(2),
          );

    final weekTotals = <int, Decimal>{};
    for (final t in current) {
      if (t.txKind != TransactionKind.expense) continue;
      final net = netOf(t);
      if (net <= Decimal.zero) continue;
      final week = t.date.difference(start).inDays ~/ 7 + 1;
      weekTotals[week] = (weekTotals[week] ?? Decimal.zero) + net;
    }

    final cats = categorySummary.expenseByCategory;
    final topTxns = current
        .where((t) => t.txKind == TransactionKind.expense)
        .map((t) => (txn: t, net: netOf(t)))
        .where((e) => e.net > Decimal.zero)
        .toList()
      ..sort((a, b) => b.net.compareTo(a.net));

    String fmtDate(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    String percent(Decimal part, Decimal total) {
      if (total <= Decimal.zero) return '0.0%';
      return '${(part.toDouble() / total.toDouble() * 100).toStringAsFixed(1)}%';
    }

    final sb = StringBuffer()
      ..writeln('报告标题：$title')
      ..writeln('报告类型：$type')
      ..writeln('报告周期：${fmtDate(start)} 至 ${fmtDate(endInclusive)}')
      ..writeln()
      ..writeln('【本期准确合计】')
      ..writeln('- 支出：${MoneyFormat.string(curSummary.expense)}')
      ..writeln('- 收入：${MoneyFormat.string(curSummary.income)}')
      ..writeln(
        '- 结余：${MoneyFormat.string(curSummary.income - curSummary.expense)}',
      )
      ..writeln('- 支出笔数：${curSummary.expenseCount}')
      ..writeln('- 笔均支出：${MoneyFormat.string(avgExpense)}')
      ..writeln(_formatBudgetContext(reportBudget))
      ..writeln()
      ..writeln('【上一等长周期参考】')
      ..writeln(
        '- 周期：${fmtDate(prevStart)} 至 ${fmtDate(prevEnd.subtract(const Duration(days: 1)))}',
      )
      ..writeln('- 支出：${MoneyFormat.string(prevSummary.expense)}')
      ..writeln('- 收入：${MoneyFormat.string(prevSummary.income)}')
      ..writeln('- 支出笔数：${prevSummary.expenseCount}')
      ..writeln()
      ..writeln('【分类支出明细】');

    if (cats.isEmpty) {
      sb.writeln('无支出分类数据。');
    } else {
      for (final e in cats.take(20)) {
        sb.writeln(
          '- ${e.name}：${MoneyFormat.string(e.total)}（${percent(e.total, curSummary.expense)}）',
        );
      }
    }

    sb
      ..writeln()
      ..writeln('【周度/分段支出】');
    if (weekTotals.isEmpty) {
      sb.writeln('无分段支出数据。');
    } else {
      final weeks = weekTotals.keys.toList()..sort();
      for (final week in weeks) {
        sb.writeln('- 第 $week 周：${MoneyFormat.string(weekTotals[week]!)}');
      }
    }

    sb
      ..writeln()
      ..writeln('【最大支出明细（最多 20 笔）】');
    if (topTxns.isEmpty) {
      sb.writeln('无支出明细。');
    } else {
      for (final e in topTxns.take(20)) {
        final t = e.txn;
        sb.writeln(
          '- ${fmtDate(t.date)}｜${t.categoryNameZh}｜${MoneyFormat.string(e.net)}'
          '｜${sanitizeNoteForLlm(t.note)}',
        );
      }
    }

    sb
      ..writeln()
      ..writeln('【全部可见明细（最多 240 笔，金额为退款后的净额）】');
    for (final t in current.take(240)) {
      final kind = t.txKind == TransactionKind.income
          ? '收入'
          : (t.txKind == TransactionKind.transfer ? '转账' : '支出');
      final amount = t.txKind == TransactionKind.expense ? netOf(t) : t.amount;
      sb.writeln(
        '${fmtDate(t.date)}|$kind|${t.categoryNameZh}|${MoneyFormat.string(amount)}'
        '|${sanitizeNoteForLlm(t.note)}',
      );
    }
    return sb.toString();
  }

  String _buildLocalReportFallback(
    AppRepository repo, {
    required String title,
    required String type,
    required DateTimeRange period,
    String? aiError,
    String? firstAiError,
    int? bookId,
  }) {
    final start = DateTime(
      period.start.year,
      period.start.month,
      period.start.day,
    );
    final endInclusive = DateTime(
      period.end.year,
      period.end.month,
      period.end.day,
    );
    final endExclusive = endInclusive.add(const Duration(days: 1));
    final days = endExclusive.difference(start).inDays.clamp(1, 366);
    final prevStart = start.subtract(Duration(days: days));
    final prevEnd = start;

    bool inRange(TransactionEntity t, DateTime s, DateTime e) =>
        !t.excluded && !t.date.isBefore(s) && t.date.isBefore(e);

    final visibleTransactions = bookId == null
        ? repo.visibleTransactions
        : repo.visibleTransactionsForBookView(bookId);
    final records =
        bookId == null ? repo.allRecordsRef : repo.recordsForBookView(bookId);
    Decimal netOf(TransactionEntity transaction) => bookId == null
        ? repo.netAmountOf(transaction)
        : repo.netAmountAcrossBooks(transaction);
    final current = visibleTransactions
        .where((t) => inRange(t, start, endExclusive))
        .toList(growable: false);
    final previous = visibleTransactions
        .where((t) => inRange(t, prevStart, prevEnd))
        .toList();
    final categorySummary = StatisticsEngine.rangeSummary(
      records,
      start: start,
      end: endInclusive,
    );

    ({Decimal expense, Decimal income, int expenseCount, int incomeCount})
        summarize(Iterable<TransactionEntity> rows) {
      var expense = Decimal.zero;
      var income = Decimal.zero;
      var expenseCount = 0;
      var incomeCount = 0;
      for (final t in rows) {
        if (t.txKind == TransactionKind.expense) {
          final net = netOf(t);
          if (net > Decimal.zero) {
            expense += net;
            expenseCount++;
          }
        } else if (t.txKind == TransactionKind.income) {
          income += t.amount;
          incomeCount++;
        }
      }
      return (
        expense: expense,
        income: income,
        expenseCount: expenseCount,
        incomeCount: incomeCount,
      );
    }

    final cur = summarize(current);
    final prev = summarize(previous);
    final avgExpense = cur.expenseCount == 0
        ? Decimal.zero
        : Decimal.parse(
            (cur.expense.toDouble() / cur.expenseCount).toStringAsFixed(2),
          );
    final dayTotals = <DateTime, Decimal>{};
    final topTxns = <({TransactionEntity txn, Decimal net})>[];
    for (final t in current) {
      if (t.txKind != TransactionKind.expense) continue;
      final net = netOf(t);
      if (net <= Decimal.zero) continue;
      final day = DateTime(t.date.year, t.date.month, t.date.day);
      dayTotals[day] = (dayTotals[day] ?? Decimal.zero) + net;
      topTxns.add((txn: t, net: net));
    }
    final cats = categorySummary.expenseByCategory;
    topTxns.sort((a, b) => b.net.compareTo(a.net));
    final busiestDay = dayTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    String fmtDate(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    String pct(Decimal part, Decimal total) {
      if (total <= Decimal.zero) return '0.0%';
      return '${(part.toDouble() / total.toDouble() * 100).toStringAsFixed(1)}%';
    }

    String change(Decimal now, Decimal before) {
      final diff = now - before;
      if (diff == Decimal.zero) return '持平';
      final dir = diff > Decimal.zero ? '增加' : '减少';
      return '$dir ${MoneyFormat.string(diff.abs())}';
    }

    final topCat = cats.isEmpty ? null : cats.first;
    final topTxn = topTxns.isEmpty ? null : topTxns.first;
    final busyDay = busiestDay.isEmpty ? null : busiestDay.first;
    final reportTypeName = switch (type) {
      'weekly' => '周报',
      'yearly' => '年报',
      _ => '月报',
    };
    final aiNote = _shortAiError(aiError ?? firstAiError ?? 'AI 暂时无返回');

    final sb = StringBuffer()
      ..writeln('# $title')
      ..writeln()
      ..writeln('> DeepSeek 暂时没有返回完整报告，喵先用本地账本生成基础版$reportTypeName；')
      ..writeln('> 口径与首页/统计一致，后续可在报告卡片长按「重新生成」。')
      ..writeln()
      ..writeln('## 摘要')
      ..writeln()
      ..writeln('- 报告周期：${fmtDate(start)} 至 ${fmtDate(endInclusive)}。')
      ..writeln(
        '- 本期支出 **${MoneyFormat.string(cur.expense)}**，收入 **${MoneyFormat.string(cur.income)}**，结余 **${MoneyFormat.string(cur.income - cur.expense)}**。',
      )
      ..writeln(
        '- 上一等长周期支出 **${MoneyFormat.string(prev.expense)}**，本期支出${change(cur.expense, prev.expense)}。',
      );
    if (topCat != null) {
      sb.writeln(
        '- 最大支出分类是 **${topCat.name}**，金额 **${MoneyFormat.string(topCat.total)}**，占本期支出 **${pct(topCat.total, cur.expense)}**。',
      );
    } else {
      sb.writeln('- 本期没有可计入统计的支出记录。');
    }

    sb
      ..writeln()
      ..writeln('## 一、核心指标')
      ..writeln()
      ..writeln('| 指标 | 本期 | 上一等长周期 | 变化 |')
      ..writeln('| --- | ---: | ---: | --- |')
      ..writeln(
        '| 支出 | ${MoneyFormat.string(cur.expense)} | ${MoneyFormat.string(prev.expense)} | ${change(cur.expense, prev.expense)} |',
      )
      ..writeln(
        '| 收入 | ${MoneyFormat.string(cur.income)} | ${MoneyFormat.string(prev.income)} | ${change(cur.income, prev.income)} |',
      )
      ..writeln(
        '| 结余 | ${MoneyFormat.string(cur.income - cur.expense)} | ${MoneyFormat.string(prev.income - prev.expense)} | ${change(cur.income - cur.expense, prev.income - prev.expense)} |',
      )
      ..writeln(
        '| 支出笔数 | ${cur.expenseCount} | ${prev.expenseCount} | ${cur.expenseCount - prev.expenseCount} |',
      )
      ..writeln('| 笔均支出 | ${MoneyFormat.string(avgExpense)} | - | - |')
      ..writeln()
      ..writeln('## 二、分类支出深度分析')
      ..writeln();
    if (cats.isEmpty) {
      sb.writeln('- 暂无分类支出数据。');
    } else {
      for (final e in cats.take(6)) {
        sb.writeln(
          '- **${e.name}**：${MoneyFormat.string(e.total)}，占 ${pct(e.total, cur.expense)}。',
        );
      }
    }

    sb
      ..writeln()
      ..writeln('## 三、消费行为模式')
      ..writeln();
    if (busyDay != null) {
      sb.writeln(
        '- 支出最高的一天是 ${fmtDate(busyDay.key)}，当天支出 ${MoneyFormat.string(busyDay.value)}。',
      );
    }
    sb
      ..writeln(
        '- 本期共有 ${cur.expenseCount} 笔支出，笔均支出 ${MoneyFormat.string(avgExpense)}。',
      )
      ..writeln('- 如果笔均支出明显高于日常小额消费，建议优先复盘大额订单，而不是只盯小额零花。')
      ..writeln()
      ..writeln('## 四、异常与重点关注事项')
      ..writeln();
    if (topTxns.isEmpty) {
      sb.writeln('- 本期没有可列出的支出明细。');
    } else {
      for (final e in topTxns.take(5)) {
        final t = e.txn;
        sb.writeln(
          '- ${fmtDate(t.date)}｜${t.categoryNameZh}｜${MoneyFormat.string(e.net)}｜${t.note.isEmpty ? '无备注' : t.note}',
        );
      }
    }

    sb
      ..writeln()
      ..writeln('## 五、下阶段行动建议')
      ..writeln();
    if (topCat != null) {
      sb.writeln(
        '- 先给 **${topCat.name}** 设置一个提醒线：当本周期累计超过 ${MoneyFormat.string(topCat.total)} 的 80% 时主动复盘。',
      );
    }
    if (topTxn != null) {
      sb.writeln(
        '- 单笔超过 ${MoneyFormat.string(topTxn.net)} 的订单建议在备注里写清原因，方便月末区分一次性支出和长期习惯。',
      );
    }
    sb
      ..writeln('- 报告卡片可长按重新生成；如果连续失败，请检查 API Key、余额或网络。')
      ..writeln()
      ..writeln('<!-- AI fallback: $aiNote -->');
    return sb.toString();
  }

  String _friendlyAiError(LlmQueryException e) {
    final code = e.statusCode;
    final message = e.message.trim();
    if (RegExp(r'(图片|附件)文件(不存在|为空)').hasMatch(message)) {
      return '附件读取失败：${_shortAiError(message)}。图片仍保留在消息里，请重新选择后再试。';
    }
    if (code == 413 || message.toLowerCase().contains('too large')) {
      return '附件发送失败：文件超过当前服务商允许的大小，请压缩图片或减少一次发送的数量。';
    }
    if (code == 400 ||
        code == 415 ||
        RegExp(r'(image|vision|附件|图片).*(unsupported|不支持|invalid)',
                caseSensitive: false)
            .hasMatch(message)) {
      return '当前模型或上游格式没有接受这次附件，请换用支持图片的模型，或检查服务商的上游格式。';
    }
    if (code == 401 || code == 403) {
      return '喵没连上 AI：API Key 可能无效或没有权限，去「我的 → AI 记账设置」检查一下。';
    }
    if (code == 402 || code == 429) {
      return '喵没连上 AI：DeepSeek 余额、额度或频率限制可能不够了，稍后再试或检查控制台。';
    }
    if (e.message.contains('TimeoutException') || e.message.contains('超时')) {
      return '喵没连上 AI：这次请求超时了，账单多的时候可以稍后重试。';
    }
    if (code != null && code >= 500) {
      return 'AI 服务暂时异常（HTTP $code），消息和附件都已保留，稍后可以直接重试。';
    }
    if (message.contains('响应解析') || message.contains('响应结构')) {
      return 'AI 已返回内容，但应用没能正确读取响应（${_shortAiError(message)}）。';
    }
    return '喵没连上 AI（${_shortAiError(e.message)}），待会儿再问问？';
  }

  String _attachmentFailureText(Object error) {
    if (error is LlmParseException) {
      final message = error.message.trim();
      final code = error.statusCode;
      if (RegExp(r'(图片|附件)文件(不存在|为空)').hasMatch(message)) {
        return '附件读取失败：${_shortAiError(message)}。请重新选择后再试。';
      }
      if (code == 413 || message.toLowerCase().contains('too large')) {
        return '附件发送失败：文件超过当前服务商允许的大小，请压缩图片或减少一次发送的数量。';
      }
      if (code == 400 || code == 415) {
        return '当前模型或上游格式没有接受这次附件，请换用支持图片的模型，或检查服务商的上游格式。';
      }
      if (code == 401 || code == 403) {
        return '附件发送失败：当前 AI 账号没有权限或登录已失效，请检查 AI 账号设置。';
      }
      if (message.startsWith('网络请求失败')) {
        return '附件已保留，但发送时网络连接失败；请检查网络后直接重试。';
      }
      if (code != null && code >= 500) {
        return '附件已保留，但 AI 服务暂时异常（HTTP $code），稍后可以直接重试。';
      }
      return 'AI 没能处理这次附件（${_shortAiError(message)}），图片仍保留在消息里。';
    }
    return '附件已保留，但 AI 处理失败（${_shortAiError(error)}），请稍后直接重试。';
  }

  String _shortAiError(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return '未知错误';
    if (text.length <= 80) return text;
    return '${text.substring(0, 80)}…';
  }

  String _buildMonthComparisonBlock(
    AppRepository repo,
    String question,
    DateTime now, {
    AiCategoryScope? categoryScope,
  }) {
    final q = question.trim();
    final asksMonthCompare = (q.contains('上月') || q.contains('上个月')) &&
        (q.contains('本月') ||
            q.contains('这个月') ||
            q.contains('这月') ||
            q.contains('比'));
    if (!asksMonthCompare) return '';

    final thisStart = DateTime(now.year, now.month, 1);
    final nextMonth = DateTime(now.year, now.month + 1, 1);
    final todayEnd = DateTime(now.year, now.month, now.day + 1);
    final thisEnd = todayEnd.isBefore(nextMonth) ? todayEnd : nextMonth;
    final lastStart = DateTime(now.year, now.month - 1, 1);
    final lastEnd = thisStart;
    final lastMonthDays = DateTime(now.year, now.month, 0).day;
    final sameDay = min(now.day, lastMonthDays);
    final lastSameDayEnd = DateTime(now.year, now.month - 1, sameDay + 1);

    final visible = repo.visibleTransactions
        .where((t) => !t.excluded)
        .where(
          (t) =>
              categoryScope == null ||
              categoryScope.matches(
                categoryId: t.categoryId,
                categoryKey: t.categoryKey,
              ),
        )
        .toList();
    final thisMonth = _periodSummary(repo, visible, thisStart, thisEnd);
    final lastMonth = _periodSummary(repo, visible, lastStart, lastEnd);
    final lastSameDay = _periodSummary(
      repo,
      visible,
      lastStart,
      lastSameDayEnd,
    );

    String fmtDate(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    String line(
      String label,
      DateTime start,
      DateTime end,
      _PeriodSummary summary,
    ) =>
        '$label（${fmtDate(start)} 至 ${fmtDate(end.subtract(const Duration(days: 1)))})：'
        '支出 ${MoneyFormat.string(summary.expense)}，'
        '收入 ${MoneyFormat.string(summary.income)}，'
        '净额 ${MoneyFormat.string(summary.income - summary.expense)}，'
        '${summary.count} 笔';

    final diffFull = thisMonth.expense - lastMonth.expense;
    final diffSameDay = thisMonth.expense - lastSameDay.expense;
    return '''

 【本月/上月比较的准确汇总${categoryScope == null ? '' : '（仅${categoryScope.labels.join('、')}分类）'}】
下面这些数字由本地账本全量计算，和首页/统计口径一致，必须优先使用；不要因为明细列表截断就说没有上月数据。
${line('本月截至今天', thisStart, thisEnd, thisMonth)}
${line('上月全月', lastStart, lastEnd, lastMonth)}
${line('上月同期', lastStart, lastSameDayEnd, lastSameDay)}
本月截至今天 vs 上月全月：支出差额 ${MoneyFormat.string(diffFull.abs())}（${diffFull >= Decimal.zero ? '本月更多' : '本月更少'}）。
本月截至今天 vs 上月同期：支出差额 ${MoneyFormat.string(diffSameDay.abs())}（${diffSameDay >= Decimal.zero ? '本月同期更多' : '本月同期更少'}）。
''';
  }

  _PeriodSummary _periodSummary(
    AppRepository repo,
    List<TransactionEntity> txns,
    DateTime start,
    DateTime endExclusive,
  ) {
    var expense = Decimal.zero;
    var income = Decimal.zero;
    var count = 0;
    for (final t in txns) {
      if (t.date.isBefore(start) || !t.date.isBefore(endExclusive)) continue;
      count++;
      if (t.txKind == TransactionKind.expense) {
        final net = repo.netAmountOf(t);
        if (net > Decimal.zero) expense += net;
      } else if (t.txKind == TransactionKind.income) {
        income += t.amount;
      }
    }
    return _PeriodSummary(count: count, expense: expense, income: income);
  }

  CategoryEntity? _matchCat(AppRepository repo, ParsedEntry e) {
    CategoryEntity? cat;
    // 分类优先级:用户纠正记忆 > 商户/关键词词典 > 大模型猜测 > 兜底。
    // 记忆=最懂你;词典=高频商户确定性命中(瑞幸→饮料、滴滴→打车),比模型稳。
    final learned = repo.recallCategoryKey(e.note, e.kind);
    final dict = MerchantCategory.classify(e.note, e.kind);
    // 笼统餐饮按时段细化到早/午/晚餐（更聪明）。
    final wantKey = MealTime.refine(
      learned ?? dict ?? e.categoryKey,
      e.date,
      e.note,
    );
    if (wantKey != null) {
      cat = repo.categories
          .where((c) => c.kind == e.kind && c.key == wantKey)
          .firstOrNull;
    }
    cat ??= repo.categories
        .where(
          (c) =>
              c.kind == e.kind &&
              (c.key == CategorySeed.fallbackExpenseKey ||
                  c.key == 'otherIncome'),
        )
        .firstOrNull;
    return cat;
  }

  // ── 保存这张卡里的账目 ──────────────────────────────────────────────────
  /// msg 活在跨面板共享内存里：写库循环开始后，saved/txnIds 回填和
  /// _persistRecord 必须无条件执行（中途 unmount 也一样），否则卡片会
  /// 永远停在「保存中」、已入库的账目丢掉卡片状态。只有 setState 受
  /// mounted 保护。[repository] 供 unmounted 调用方（_applyRecord）传入。
  Future<void> _save(_RecordMsg msg, {AppRepository? repository}) async {
    if (msg.saved || msg.saving) return;
    msg.saving = true;
    if (mounted) setState(() {});
    final repo = repository ?? context.read<AppRepository>();
    var aiRunCommitted = false;
    try {
      final accountId = repo.transactionAccounts.firstOrNull?.id;
      if (accountId == null) {
        if (mounted) _snack('请先在「资产管理」里加一个账户');
        if (msg.aiRunId != null) {
          await repo.markAiRunFailed(
            msg.aiRunId!,
            code: 'missing_account',
            message: '没有可用记账账户',
          );
        }
        return;
      }
      // 入库前先算「异常提醒」（用当前历史，尚不含本次）：只提醒第一笔明显偏高的支出。
      String? anomalyNote;
      for (int i = 0; i < msg.entries.length; i++) {
        final e = msg.entries[i];
        final cat = msg.cats[i];
        if (e.amount == null ||
            e.amount! <= Decimal.zero ||
            e.kind != TransactionKind.expense ||
            cat == null) {
          continue;
        }
        final past = <Decimal>[];
        for (final t in repo.transactions) {
          if (!t.excluded &&
              t.txKind == TransactionKind.expense &&
              t.categoryNameZh == cat.nameZh &&
              t.amount > Decimal.zero) {
            past.add(t.amount);
          }
        }
        anomalyNote = SpendingAnomaly.note(past, e.amount!, cat.nameZh);
        if (anomalyNote != null) break;
      }

      // 先组装草稿，再一次性写入 SQLite。这样多笔提案不会在中途
      // 异常时留下半批账；有 AI run 时，run 终态也和账单在同一事务中提交。
      final ids = List<int?>.filled(msg.entries.length, null);
      final drafts = <TransactionDraft>[];
      final draftIndexes = <int>[];
      CategoryEntity? feedbackCat;
      DateTime? feedbackDate;
      CategoryEntity? fallbackCat;
      DateTime? fallbackDate;
      for (int i = 0; i < msg.entries.length; i++) {
        final e = msg.entries[i];
        final amt = e.amount;
        if (amt == null || amt <= Decimal.zero) {
          continue;
        }
        drafts.add(TransactionDraft(
          kind: e.kind,
          amount: amt,
          categoryId: msg.cats[i]?.id,
          accountId: accountId,
          note: e.note,
          date: e.date,
          timePrecision: e.timePrecision,
          reimbursable: SmartTags.isReimbursable(e.note), // 出差/报销自动标待报销
        ));
        draftIndexes.add(i);
        final cat = msg.cats[i];
        if (cat != null) {
          fallbackCat ??= cat;
          fallbackDate ??= e.date;
          if (e.kind == TransactionKind.expense) {
            feedbackCat ??= cat;
            feedbackDate ??= e.date;
          }
        }
      }
      if (drafts.isEmpty) {
        if (mounted) _snack('这几笔没认出金额，先补上金额再存～');
        return;
      }
      final insertedIds = await repo.addTransactionDraftsAtomically(
        drafts,
        runId: msg.aiRunId,
      );
      if (insertedIds.length != draftIndexes.length) {
        throw StateError('AI 记账提交结果数量不一致');
      }
      for (var i = 0; i < draftIndexes.length; i++) {
        ids[draftIndexes[i]] = insertedIds[i];
      }
      aiRunCommitted = msg.aiRunId != null && msg.aiRunId!.trim().isNotEmpty;
      // 记完反馈:按实际入账日期统计，避免跨天/补记时次数锚到今天。
      final mainCat = feedbackCat ?? fallbackCat;
      final feedback = MeowInsights.recordFeedback(
        repo,
        mainCat?.nameZh ?? '',
        date: feedbackDate ?? fallbackDate,
      );
      // 账已经写进库了：卡片状态回填/落库无条件执行，unmount 只跳过 UI。
      msg.saved = true;
      msg.txnIds = ids;
      msg.savedIds = ids.whereType<int>().toList();
      msg.savedFeedback = feedback;
      if (anomalyNote != null) _msgs.add(_InfoMsg(anomalyNote));
      if (mounted) {
        Haptics.of(Haptic.success);
        setState(() {});
      }
      if (anomalyNote != null) {
        await _addChatMessage(repo, role: 'info', text: anomalyNote);
      }
      await _persistRecord(msg, repository: repo);
    } catch (error) {
      // 原子提交已经完成后，聊天卡持久化失败不应把一个已完成的 run
      // 改写成失败；下次打开仍可从账本和任务中心恢复。
      if (msg.aiRunId != null && !aiRunCommitted) {
        await repo.markAiRunFailed(
          msg.aiRunId!,
          code: 'commit_failed',
          message: error.toString(),
        );
      }
      if (mounted) _snack('保存失败：$error');
    } finally {
      msg.saving = false;
      if (mounted) setState(() {});
    }
  }

  /// 把一张记账卡持久化到 chat_messages（首次 insert 拿行 id，之后 update），
  /// 供关 App 重开后重建卡片、芯片（改分类/删除）继续可用。只持久化已保存的卡。
  Future<void> _persistRecord(
    _RecordMsg msg, {
    AppRepository? repository,
  }) async {
    if (!msg.saved) return;
    final repo = repository ?? context.read<AppRepository>();
    final json = encodeRecordCard(
      entries: msg.entries,
      catIds: [for (final c in msg.cats) c?.id],
      txnIds: msg.txnIds,
      saved: msg.saved,
      feedback: msg.savedFeedback,
      deleted: msg.deletedIdx,
      aiRunId: msg.aiRunId,
      rolledBack: msg.rolledBack,
    );
    if (msg.chatRowId == null) {
      msg.chatRowId = await _addChatRecordMessage(repo, json);
    } else {
      await repo.updateChatRecordMessage(msg.chatRowId!, json);
    }
  }

  /// 一键改分类：把第 [i] 笔改成 [newCat]，并记住这次纠正(下次自动用)；
  /// 若已入库则同步改库。
  Future<void> _pickCategory(
    _RecordMsg msg,
    int i,
    CategoryEntity newCat,
  ) async {
    final repo = context.read<AppRepository>();
    Haptics.light();
    // 学习:把"短语 → 分类"记下,下次同类自动命中。
    // 优先学「归一化商户主体」(顺丰/中国电信…)——一次改，以后同商户都对；
    // 是平台商户(京东/淘宝…)或无明确商户时才退回学整条备注(避免错学平台→子类)。
    final note = msg.entries[i].note;
    final learnPhrase = BillCategorizer.learnKeyFor(note) ?? note;
    if (learnPhrase.trim().isNotEmpty) {
      await repo.learnCategory(
        phrase: learnPhrase,
        kind: newCat.kind,
        categoryKey: newCat.key,
      );
    }
    // 已入库 → 改库
    if (msg.saved && i < msg.txnIds.length && msg.txnIds[i] != null) {
      await repo.setTransactionCategory(msg.txnIds[i]!, newCat.id);
    }
    if (!mounted) return;
    setState(() => msg.cats[i] = newCat);
    await _persistRecord(msg); // 把改后的分类写回持久化卡
  }

  Future<void> _showCategoryPicker(_RecordMsg msg, int i) async {
    if (i < 0 || i >= msg.entries.length) return;
    final entry = msg.entries[i];
    final current = i < msg.cats.length ? msg.cats[i] : null;
    final picked = await showCategoryPickerSheet(
      context,
      kind: entry.kind,
      selectedId: current?.id,
      title: entry.kind == TransactionKind.income ? '选择收入分类' : '选择支出分类',
    );
    if (picked == null || !mounted) return;
    await _pickCategory(msg, i, picked);
  }

  // ── 删除单笔：明细卡上的「删除」芯片（带确认，替代旧的整条撤销）────────────
  Future<void> _deleteEntry(_RecordMsg msg, int i) async {
    final id = i < msg.txnIds.length ? msg.txnIds[i] : null;
    if (id == null) return;
    final ok = await showConfirmDialog(
      context,
      title: '删除这笔账？',
      message: '删除后不可恢复。',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await context.read<AppRepository>().deleteTransaction(id);
    if (!mounted) return;
    Haptics.selection();
    setState(() => msg.deletedIdx.add(i));
    await _persistRecord(msg); // 把删除状态写回持久化卡
  }

  Future<void> _undoRecord(_RecordMsg msg) async {
    final runId = msg.aiRunId;
    if (runId == null || runId.trim().isEmpty || msg.rolledBack) return;
    final ok = await showConfirmDialog(
      context,
      title: '撤销本次 AI 记账？',
      message: '只会撤销这次 AI 实际写入的账单，不影响其他记录。',
      confirmText: '撤销',
      destructive: true,
    );
    if (!ok) return;
    final repo = context.read<AppRepository>();
    final changed = await repo.undoAiRun(runId);
    if (!changed) {
      if (mounted) _snack('这次记账已经撤销，或没有可撤销的记录');
      return;
    }
    msg.rolledBack = true;
    msg.deletedIdx.addAll(
      [
        for (var i = 0; i < msg.txnIds.length; i++)
          if (msg.txnIds[i] != null) i
      ],
    );
    msg.savedFeedback = '本次 AI 记账已撤销';
    await _persistRecord(msg, repository: repo);
    if (mounted) {
      Haptics.selection();
      setState(() {});
      _snack('本次 AI 记账已撤销');
    }
  }

  // ── build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    _observeKeyboardInset(bottomInset);
    final Widget body;
    // 全屏（抽屉「喵助手」入口）：一条独立的整屏不透明页，恒定铺满，状态栏也盖住。
    if (widget.fullScreen) {
      body = ValueListenableBuilder<bool>(
        valueListenable: _imeVisualsActive,
        builder: (context, imeActive, _) => _fullScreenPage(
          context,
          bottomInset,
          imeActive: imeActive,
        ),
      );
    } else {
      final scheme = Theme.of(context).colorScheme;
      body = ValueListenableBuilder<bool>(
        valueListenable: _imeVisualsActive,
        builder: (context, imeActive, _) {
          final imeTransitioning = imeActive || bottomInset > 0;
          final content = _started
              ? _chatMode(context, blurEnabled: !imeTransitioning)
              : _emptyMode(
                  context,
                  bottomInset,
                  animatePosition: !imeTransitioning,
                  blurEnabled: !imeTransitioning,
                );
          final layer = Material(
            type: MaterialType.transparency,
            child: ColoredBox(
              color: scheme.surface.withValues(
                alpha: imeTransitioning ? 0.30 : (_started ? 0.18 : 0.20),
              ),
              child: RepaintBoundary(
                child: _started
                    ? Padding(
                        padding: EdgeInsets.only(bottom: bottomInset),
                        child: SafeArea(top: false, child: content),
                      )
                    : SafeArea(top: false, child: content),
              ),
            ),
          );
          return ClipRect(
            child: BackdropFilter(
              key: const ValueKey('ai-chat-backdrop-blur'),
              enabled: !imeTransitioning,
              filter: ImageFilter.blur(
                sigmaX: _started ? 16 : 22,
                sigmaY: _started ? 16 : 22,
              ),
              child: layer,
            ),
          );
        },
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleSystemBack();
      },
      child: body,
    );
  }

  // 全屏聊天页：不透明 surface 铺满整屏（含状态栏），SafeArea 垫内容。
  // 顶部头部、中间内容（建议 or 对话）、底部输入；空态/对话态都恒定全屏。
  Widget _fullScreenPage(
    BuildContext context,
    double bottomInset, {
    required bool imeActive,
  }) {
    final scheme = Theme.of(context).colorScheme;
    const headerHeight = 56.0;
    final content = _historyViewport(
      _msgs.isEmpty
          ? SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 预算/记账提示只属于主页「记一记」入口；普通 Chats
                    // 是独立聊天，不在进入会话时插入本月预算洞察。
                    if (widget.recordOnly)
                      const _GreetingLine(
                        key: ValueKey('ai-chat-greeting'),
                      ),
                    if (widget.recordOnly) ...[
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.only(left: 0),
                        child:
                            _SuggestionGrid(items: _picked, onTap: _fillInput),
                      ),
                    ],
                  ],
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) => _messageHistoryList(
                constraints,
              ),
            ),
    );
    final imeTransitioning = imeActive || bottomInset > 0;
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: AppColors.pageBackground(scheme.brightness),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: headerHeight),
                    Expanded(child: content),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: _inputBox(
                        context,
                        blurEnabled: !imeTransitioning,
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 108,
                  child: IgnorePointer(
                    child: _TopChromeBlur(
                      blurEnabled: !imeTransitioning,
                    ),
                  ),
                ),
                Positioned(left: 0, right: 0, top: 0, child: _header(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 点建议：把文字填进输入框（不直接发），让用户改了再发。
  void _fillInput(String s) {
    setState(() {
      _ctrl.text = s;
      _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    });
    _requestInputFocus();
  }

  // 空态：建议浮在模糊背景上 + 底部白卡输入。
  Widget _emptyMode(
    BuildContext context,
    double bottomInset, {
    required bool animatePosition,
    required bool blurEnabled,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 520;
        final inputReserve = compact ? 104.0 : 116.0;
        final keyboardLift =
            bottomInset.clamp(0.0, constraints.maxHeight).toDouble();
        final settleDuration =
            animatePosition ? const Duration(milliseconds: 180) : Duration.zero;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: inputReserve + keyboardLift,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _handleBackdropTap,
                child: const SizedBox.expand(),
              ),
            ),
            AnimatedPositioned(
              duration: settleDuration,
              curve: Curves.easeOutCubic,
              left: 6,
              right: 16,
              bottom: inputReserve + keyboardLift,
              child: ValueListenableBuilder<bool>(
                valueListenable: _visualsReady,
                builder: (context, ready, _) => ValueListenableBuilder<bool>(
                  valueListenable: _hasInputText,
                  builder: (context, hasInputText, _) => AnimatedSwitcher(
                    duration: const Duration(milliseconds: 140),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeOutCubic,
                    child: !hasInputText
                        ? Column(
                            key: const ValueKey('ai-empty-suggestions'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IgnorePointer(
                                child: Mascot(
                                  mood: MascotMood.empty,
                                  size: compact ? 74 : 86,
                                  animate: widget.fullScreen || ready,
                                ),
                              ),
                              SizedBox(height: compact ? 8 : 12),
                              if (widget.recordOnly)
                                _SuggestionGrid(
                                  items: _picked,
                                  onTap: _fillInput,
                                ),
                            ],
                          )
                        : const SizedBox(
                            key: ValueKey('ai-empty-suggestions-hidden'),
                            height: 0,
                          ),
                  ),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: settleDuration,
              curve: Curves.easeOutCubic,
              left: 12,
              right: 12,
              bottom: 10 + keyboardLift,
              child: _inputBox(context, blurEnabled: blurEnabled),
            ),
          ],
        );
      },
    );
  }

  // 对话态：半屏/全屏可拖拽的白色聊天窗。
  Widget _chatMode(BuildContext context, {required bool blurEnabled}) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (ctx, c) {
        final availH = c.maxHeight;
        // 聚焦(键盘弹起)时铺满键盘上方区域，避免溢出；否则用半/全屏档位。
        final focused =
            _focus.hasFocus || _inputFocusGuardActive || _inputSessionActive;
        final frac = (focused ? 1.0 : _heightFrac).clamp(0.35, 1.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _handleBackdropTap,
                child: const SizedBox.expand(),
              ),
            ),
            AnimatedContainer(
              duration: (_dragging || focused)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              height: availH * frac,
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 24,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _dragHandle(availH),
                  _header(context),
                  Expanded(
                    child: _historyViewport(
                      LayoutBuilder(
                        builder: (context, constraints) =>
                            _messageHistoryList(constraints),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: _inputBox(context, blurEnabled: blurEnabled),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // 顶部横条：跟手缩放 + 松手吸附半/全屏 + 点击切换。
  Widget _dragHandle(double availH) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => _dragging = true,
      onVerticalDragUpdate: (d) {
        setState(() {
          _heightFrac = (_heightFrac - d.delta.dy / availH).clamp(0.35, 0.96);
        });
      },
      onVerticalDragEnd: (_) {
        setState(() {
          _dragging = false;
          if (_heightFrac < 0.45) {
            Navigator.pop(context);
            return;
          }
          _heightFrac = _heightFrac < 0.74 ? 0.58 : 0.94;
        });
      },
      onTap: () =>
          setState(() => _heightFrac = _heightFrac > 0.74 ? 0.58 : 0.94),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 5),
        alignment: Alignment.center,
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  // 头部：左上角返回、中间放大的睡觉猫、右上角 ⋯（聊天记录管理 / 删除）。
  Widget _header(BuildContext context) {
    final full = widget.fullScreen;
    final compactChat = !full && _started;
    return Padding(
      padding: full
          ? const EdgeInsets.fromLTRB(12, 0, 12, 0)
          : compactChat
              ? const EdgeInsets.fromLTRB(12, 0, 12, 0)
              : const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: SizedBox(
        height: full ? 56 : (compactChat ? 36 : 72),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (widget.fullScreen)
              Align(
                alignment: Alignment.centerLeft,
                child: AppCircleButton(
                  icon: CupertinoIcons.chevron_back,
                  iconSize: 22,
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ValueListenableBuilder<bool>(
              valueListenable: _visualsReady,
              builder: (context, ready, _) => Transform.translate(
                offset: Offset(0, compactChat ? -5 : 0),
                child: Mascot(
                  mood: MascotMood.empty,
                  size: full ? 58 : (compactChat ? 50 : 72),
                  animate: widget.fullScreen || ready,
                ),
              ),
            ),
            if (widget.fullScreen)
              Align(
                alignment: Alignment.centerRight,
                child: _HeaderActionCluster(
                  onReports: () => showReportLibrarySheet(context),
                  onMenu: (btnCtx) => _showChatMenu(btnCtx),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ⋯ 菜单：聊天记录管理（保存时长）/ 删除对话记录。以后可再加功能。
  void _showChatMenu(BuildContext anchor) {
    showIosMenu(anchor, [
      IosMenuItem(
        label: '聊天记录管理',
        icon: Icons.schedule,
        onTap: () => WidgetsBinding.instance.addPostFrameCallback(
          (_) => _showRetentionMenu(anchor),
        ),
      ),
      IosMenuItem(
        label: '删除对话记录',
        icon: Icons.delete_outline,
        destructive: true,
        onTap: _confirmClearChat,
      ),
    ]);
  }

  void _showRetentionMenu(BuildContext anchor) {
    if (!mounted) return;
    final repo = context.read<AppRepository>();
    final days = repo.chatRetentionDays;
    const opts = [
      (7, '一周'),
      (30, '一个月'),
      (90, '三个月'),
      (180, '半年'),
      (36500, '永不删除'),
    ];
    showIosMenu(anchor, [
      for (final (d, label) in opts)
        IosMenuItem(
          label: label,
          icon: days == d ? Icons.check : Icons.schedule,
          onTap: () => repo.setChatRetentionDays(d),
        ),
    ]);
  }

  Future<void> _confirmClearChat() async {
    final ok = await showConfirmDialog(
      context,
      title: '删除对话记录？',
      message: '只会清空当前会话的聊天记录，不会影响其他会话。删除后不可恢复。',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final repo = context.read<AppRepository>();
    await repo.clearChatSessionMessages(_sessionId);
    if (mounted) {
      setState(() => clearChatHistoryMemory(repo, _sessionId));
    }
  }

  Future<void> _setChatWebSearchEnabled(bool enabled) async {
    final repo = context.read<AppRepository>();
    await repo.setChatWebSearchEnabled(enabled);
  }

  // 卡中卡输入框：浅底圆角框 + 工具行。
  // 输入框：与首页那条完全统一（玻璃圆角卡 + 细黑边）。
  Widget _inputBox(BuildContext context, {bool blurEnabled = true}) {
    final scheme = Theme.of(context).colorScheme;
    return TextFieldTapRegion(
      child: AppGlassInputShell(
        key: const ValueKey('ai-chat-input-shell'),
        // Keep the denser blur used by the assistant input before the shell
        // unification. Opacity and dimensions remain shared with the home bar.
        blur: 10,
        blurEnabled: blurEnabled,
        opacity: 0.4,
        padding: AppGlassInputShell.standardPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_draftAttachments.isNotEmpty) ...[
              _AttachmentDraftStrip(
                attachments: _draftAttachments,
                onRemove: (index) {
                  setState(() => _draftAttachments.removeAt(index));
                  _onInputChanged();
                },
              ),
              const SizedBox(height: 10),
            ],
            Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _handleInputPointerDown(),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 24),
                  child: TextField(
                    key: const ValueKey('ai-chat-input-field'),
                    controller: _ctrl,
                    focusNode: _focus,
                    autofocus: false,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onTap: () => _requestInputFocus(bypassThrottle: true),
                    onSubmitted: (_) => _send(),
                    style: const TextStyle(
                      fontSize: 17,
                      height: 1.2,
                      fontWeight: FontWeight.w400,
                      fontFamilyFallback: _cjkFontFallback,
                      fontVariations: [FontVariation('wght', 350)],
                    ),
                    decoration: InputDecoration(
                      hintText: widget.recordOnly ? '记一记' : '聊点什么',
                      hintStyle: AppGlassInputShell.standardHintStyle(scheme),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Transform.translate(
                  offset: const Offset(-4, 2),
                  child: _CircleBtn(
                    key: const ValueKey('ai-chat-plus-button'),
                    icon: Icons.add,
                    // The home record composer keeps its original circular
                    // plus background; ordinary Chats keeps the Claude-style
                    // bare rounded glyph. These branches intentionally stay
                    // independent so a home keyboard transition cannot alter
                    // the Chats attachment control.
                    plain: widget.fullScreen || !widget.recordOnly,
                    onTap: () {
                      final repo = context.read<AppRepository>();
                      showChatAddSheet(
                        context,
                        webSearchEnabled: repo.chatWebSearchAllowed,
                        onWebSearchChanged: _setChatWebSearchEnabled,
                        toolAccess: repo.chatToolAccess,
                        onToolAccessChanged: repo.setChatToolAccess,
                        onAttachmentsPicked: _addDraftAttachments,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 4),
                if (widget.fullScreen) ...[
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          fit: FlexFit.loose,
                          child: Transform.translate(
                            offset: const Offset(-4, 2),
                            child: Builder(
                              builder: (btnCtx) => _ModelPill(
                                model: _chatConfig(
                                  context.watch<AppRepository>(),
                                ).model,
                                selected: _activeInputSelection ==
                                    _InputSelection.model,
                                onTap: () => _showModelPicker(btnCtx),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: _aiChatSelectionGap),
                        Transform.translate(
                          offset: const Offset(-4, 2),
                          child: Builder(
                            builder: (btnCtx) => _EffortLabel(
                              effort: _chatEffort(
                                context.watch<AppRepository>(),
                              ),
                              selected: _activeInputSelection ==
                                  _InputSelection.effort,
                              onTap: () => _showEffortMenu(btnCtx),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else
                  _AiModeSwitchPill(
                    key: const ValueKey('ai-chat-mode-switch-pill'),
                    onTap: _switchToManual,
                  ),
                if (!widget.fullScreen) const Spacer(),
                ValueListenableBuilder<bool>(
                  valueListenable: _hasInputText,
                  builder: (context, hasText, _) => _CircleBtn(
                    key: const ValueKey('ai-chat-send-button'),
                    icon: Icons.arrow_upward,
                    onTap: (hasText && !_busy) ? () => _send() : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 取最近 N 轮对话（user+assistant 交替），用于多轮上下文。
  /// 只取 _UserMsg / _AnswerMsg，跳过记账卡/报告/信息提示等。
  List<Map<String, String>> _recentTurns({
    int maxTurns = 6,
    bool excludeNewestUser = false,
  }) {
    final result = <Map<String, String>>[];
    var newestUserExcluded = !excludeNewestUser;
    for (final msg in _msgs.reversed) {
      if (result.length >= maxTurns * 2) break;
      if (msg is _AnswerMsg) {
        result.insert(0, {'role': 'assistant', 'content': msg.text});
      } else if (msg is _UserMsg) {
        if (!newestUserExcluded) {
          newestUserExcluded = true;
          continue;
        }
        result.insert(0, {'role': 'user', 'content': msg.text});
      }
    }
    return AiContextCompressor.compactTurns(result);
  }

  Future<void> _regenerate(_AnswerMsg m) async {
    if (_busy || m.question.isEmpty) return;
    final flowId = _beginFlow();
    final answerIndex = _msgs.indexOf(m);
    _ThinkingMsg? oldThinking;
    if (answerIndex > 0 && _msgs[answerIndex - 1] is _ThinkingMsg) {
      oldThinking = _msgs[answerIndex - 1] as _ThinkingMsg;
    }
    setState(() {
      _msgs.remove(m);
      if (oldThinking != null) _msgs.remove(oldThinking);
      _msgs.add(_ThinkingMsg(_ThinkingKind.queryCollect, flowId: flowId));
      _busy = true;
    });
    final rowId = m.chatRowId;
    try {
      if (rowId != null) {
        _chatRowIdsInMemory.remove(rowId);
        await context.read<AppRepository>().deleteChatSessionMessage(
              sessionId: _sessionId,
              messageId: rowId,
            );
      }
    } catch (error, stackTrace) {
      await _handleUnexpectedFlowError(flowId, error, stackTrace);
      _finishFlow(flowId);
      return;
    }
    if (!mounted || !_ownsFlow(flowId)) {
      _finishFlow(flowId);
      return;
    }
    _restartThinkingTicker(flowId: flowId);
    _scrollToBottom();
    unawaited(_runQuerySafely(flowId, m.question));
  }

  void _continueAnswer(_AnswerMsg m) {
    if (_busy || m.question.isEmpty || m.text.trim().isEmpty) return;
    final flowId = _beginFlow();
    setState(() {
      _msgs.add(_ThinkingMsg(_ThinkingKind.queryAnswer, flowId: flowId));
      _busy = true;
    });
    _restartThinkingTicker(flowId: flowId);
    _scrollToBottom();
    unawaited(
      _runQuerySafely(
        flowId,
        '上一次回答因网络中断停在下面，请直接从中断处继续，不要重复已经给出的内容。\n\n'
        '原问题：${m.question}\n\n已完成部分：${m.text}',
        chatOnly: true,
      ),
    );
  }

  String _messageTimeLabel(DateTime time) {
    final local = time.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final now = DateTime.now();
    final today = DateUtils.isSameDay(local, now);
    final yesterday = DateUtils.isSameDay(
      local,
      now.subtract(const Duration(days: 1)),
    );
    if (today) return '今天 $hh:$mm';
    if (yesterday) return '昨天 $hh:$mm';
    return '${local.month}月${local.day}日 $hh:$mm';
  }

  void _dismissTextSelection(_UserMsg message) {
    if (!identical(_textSelectingUserMsg, message)) return;
    _textSelectionScrim?.remove();
    _textSelectionScrim = null;
    if (mounted) setState(() => _textSelectingUserMsg = null);
  }

  Future<void> _showTextSelection(
    _UserMsg message,
    Rect anchor,
  ) async {
    if (!mounted || message.text.trim().isEmpty) return;
    _textSelectionScrim?.remove();
    _textSelectionScrim = null;
    setState(() => _textSelectingUserMsg = message);
    // Paint a neutral scrim above the page with a cut-out for the actual
    // message. The read-only EditableText remains in the original bubble and
    // inserts its native handles/toolbar above this entry on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_textSelectingUserMsg, message)) return;
      final overlay = Overlay.of(context, rootOverlay: true);
      final highlight = _scaledMessageRect(anchor).inflate(1.5);
      final entry = OverlayEntry(
        builder: (_) => Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _dismissTextSelection(message),
              ),
            ),
            Positioned.fill(
              child: AppMenuScrim(
                highlightRect: highlight,
                radius: 21,
              ),
            ),
          ],
        ),
      );
      _textSelectionScrim = entry;
      overlay.insert(entry);
    });
  }

  Future<void> _showUserMessageMenu(
    BuildContext anchor,
    _UserMsg message,
  ) async {
    final text = message.text.trim();
    if (text.isEmpty) return;
    Haptics.medium();
    final box = anchor.findRenderObject() as RenderBox?;
    if (box == null) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (mounted) setState(() => _selectedUserMsg = message);
    try {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: '消息操作',
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 170),
        pageBuilder: (_, __, ___) => _MessageActionOverlay(
          anchor: rect,
          timeLabel: _messageTimeLabel(message.sentAt),
          onCopy: () {
            Clipboard.setData(ClipboardData(text: message.text));
            if (mounted) showAppToast(context, '已复制');
          },
          onEdit: () {
            if (_busy) {
              _snack('当前正在处理，请稍候再编辑');
              return;
            }
            _ctrl.value = TextEditingValue(
              text: message.text,
              selection: TextSelection.collapsed(offset: message.text.length),
            );
            _requestInputFocus(bypassThrottle: true);
          },
          onSelectText: () => unawaited(_showTextSelection(message, rect)),
        ),
        transitionBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation,
          child: child,
        ),
      );
    } finally {
      if (mounted && identical(_selectedUserMsg, message)) {
        setState(() => _selectedUserMsg = null);
      }
    }
  }

  Future<void> _regenerateReport(_ReportMsg m) async {
    if (_busy || m.question.isEmpty) return;
    final repo = context.read<AppRepository>();
    final aiConfig = _chatConfig(repo);
    if (!aiConfig.hasCredential) {
      showAppToast(context, '先去「我的 → AI 记账设置」填写 API Key');
      return;
    }
    final report = m.report;
    final flowId = _beginFlow();
    late final ReportJobEntity job;
    try {
      final baseLease = await repo.acquireReportGenerationLease();
      job = await repo.guardReportGeneration(
        baseLease,
        () => repo.createReportJob(
          question: m.question,
          type: report.type,
          title: report.title,
          periodStart: report.periodStart,
          periodEnd: report.periodEnd,
          bookId: report.bookId,
          reportId: report.id,
          sessionId: _sessionId,
        ),
      );
    } on ReportGenerationInvalidated {
      _handleInvalidatedReport();
      return;
    }
    if (!mounted) return;
    setState(() {
      _msgs.remove(m);
      _msgs.add(_ThinkingMsg(_ThinkingKind.reportCollect, flowId: flowId));
      _busy = true;
    });
    _restartThinkingTicker(flowId: flowId);
    _scrollToBottom();
    try {
      await _runQuery(
        m.question,
        repository: repo,
        resumeJob: job,
        flowId: flowId,
      ).timeout(_kAiFlowTimeout);
    } catch (error, stackTrace) {
      await _handleUnexpectedFlowError(flowId, error, stackTrace);
      if (!mounted || !_ownsFlow(flowId)) {
        _finishFlow(flowId);
        return;
      }
      _completeThinking(flowId: flowId);
      setState(() {
        _msgs.add(m);
        _msgs.add(_InfoMsg('报告重新生成失败，稍后再试', error: true));
        _busy = false;
      });
    }
    _finishFlow(flowId);
    _scrollToBottom();
  }

  Widget _buildMsg(_Msg m, {bool isLast = false}) {
    // 首页只展示本次记账输入及其账卡；全屏喵助手的历史问答/报告不在这里
    // 重新出现，避免用户误以为主页仍支持聊天或查账。
    if (widget.recordOnly &&
        ((m is _UserMsg && !identical(m, _latestUserMsg)) ||
            m is _AnswerMsg ||
            m is _ReportMsg)) {
      return const SizedBox.shrink();
    }
    if (m is _UserMsg) {
      final bubble = _UserBubble(
        text: m.text,
        attachments: m.attachments,
        fullBleedAttachments: true,
        selected: identical(_selectedUserMsg, m) ||
            identical(_textSelectingUserMsg, m),
        textSelectionMode: identical(_textSelectingUserMsg, m),
        onSelectionDismissed: () => _dismissTextSelection(m),
        onLongPress: (anchor) => unawaited(_showUserMessageMenu(anchor, m)),
      );
      return identical(m, _latestUserMsg)
          ? KeyedSubtree(key: _latestUserMsgKey, child: bubble)
          : bubble;
    }
    if (m is _ThinkingMsg) return _ThinkingBubble(msg: m);
    if (m is _InfoMsg) return _InfoBubble(text: m.text, error: m.error);
    if (m is _AnswerMsg) {
      return _AnswerBubble(
        text: m.text,
        animate: !m.shown,
        streaming: m.streaming,
        interrupted: m.interrupted,
        sources: m.sources,
        onShown: () => m.shown = true,
        onRegenerate: widget.recordOnly || m.question.isEmpty
            ? null
            : () => _regenerate(m),
        onContinue: widget.recordOnly || !m.interrupted || m.question.isEmpty
            ? null
            : () => _continueAnswer(m),
        // 猫只出现在最后一条回复下（对齐 Claude），历史回复不重复放猫。
        showMascot: isLast,
      );
    }
    if (m is _ReportMsg) {
      return _ReportBubble(
        msg: m,
        onRegenerate: widget.recordOnly || m.question.isEmpty
            ? null
            : () => _regenerateReport(m),
        showMascot: isLast,
      );
    }
    if (m is _RecordMsg) {
      final repo = context.read<AppRepository>();
      return _RecordBubble(
        msg: m,
        bookName: repo.currentBook?.name ?? '总账本',
        onSave: m.saving ? null : () => _save(m),
        onChangeCategory: (i) => _showCategoryPicker(m, i),
        onDeleteEntry: (i) => _deleteEntry(m, i),
        onUndo: m.rolledBack ? null : () => _undoRecord(m),
      );
    }
    if (m is _RefundMsg) return _RefundBubble(msg: m);
    return const SizedBox.shrink();
  }
}

class _TopChromeBlur extends StatelessWidget {
  final bool blurEnabled;

  const _TopChromeBlur({this.blurEnabled = true});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = AppColors.topFrostTint(scheme);
    final layer = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tint.withValues(alpha: 0.98),
            tint.withValues(alpha: 0.78),
            tint.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.58, 1.0],
        ),
      ),
    );
    return ClipRect(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black, Colors.black, Colors.transparent],
          stops: [0.0, 0.58, 1.0],
        ).createShader(bounds),
        child: BackdropFilter(
          enabled: blurEnabled,
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: layer,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 消息模型
// ─────────────────────────────────────────────────────────────────────────────

class _PeriodSummary {
  final int count;
  final Decimal expense;
  final Decimal income;

  const _PeriodSummary({
    required this.count,
    required this.expense,
    required this.income,
  });
}

abstract class _Msg {}

class _UserMsg extends _Msg {
  final String text;
  final DateTime sentAt;
  final List<ChatAttachment> attachments;
  int? chatRowId;
  _UserMsg(
    this.text, {
    this.attachments = const [],
    this.chatRowId,
    DateTime? sentAt,
  }) : sentAt = sentAt ?? DateTime.now();
}

class _ThinkingMsg extends _Msg {
  _ThinkingKind kind;
  final int? flowId;
  bool canContinueInBackground;
  final DateTime startedAt;
  DateTime? modelStartedAt;
  DateTime? completedAt;
  bool expanded = false;
  bool hidden = false;
  final List<_ThinkingStep> steps;
  final List<AiWebSource> sources = <AiWebSource>[];

  _ThinkingMsg(
    this.kind, {
    this.flowId,
    DateTime? startedAt,
    List<_ThinkingStep>? steps,
  })  : canContinueInBackground = false,
        startedAt = startedAt ?? DateTime.now(),
        steps = steps ?? <_ThinkingStep>[] {
    if (this.steps.isEmpty) {
      this.steps.add(_ThinkingStep(kind: kind, startedAt: this.startedAt));
    }
  }

  bool get completed => completedAt != null;

  void markModelStarted([DateTime? value]) {
    modelStartedAt ??= value ?? DateTime.now();
  }

  Duration get elapsed =>
      (completedAt ?? DateTime.now()).difference(modelStartedAt ?? startedAt);
}

class _ThinkingStep {
  final _ThinkingKind kind;
  final DateTime startedAt;
  DateTime? completedAt;
  String detail;

  _ThinkingStep({
    required this.kind,
    required this.startedAt,
    this.completedAt,
    this.detail = '',
  });

  Duration get elapsed => (completedAt ?? DateTime.now()).difference(startedAt);
}

enum _ThinkingKind {
  intent,
  recordParse,
  recordMatch,
  queryCollect,
  queryAnswer,
  reportCollect,
  reportGenerate,
  reportFallback,
  reportSave,
  webSearch,
}

class _InfoMsg extends _Msg {
  final String text;
  final bool error;
  _InfoMsg(this.text, {this.error = false});
}

class _AnswerMsg extends _Msg {
  String text;
  final String question;
  final List<AiWebSource> sources;
  bool shown;
  bool streaming;
  int? chatRowId;
  bool interrupted = false;
  _AnswerMsg(
    this.text, {
    this.question = '',
    List<AiWebSource>? sources,
    this.shown = false,
    this.streaming = false,
    this.chatRowId,
  }) : sources = sources ?? <AiWebSource>[];
}

class _StreamingAnswer {
  final String text;
  final bool renderedInUi;
  final List<AiWebSource> sources;
  final _AnswerMsg? message;

  const _StreamingAnswer(
    this.text, {
    required this.renderedInUi,
    this.sources = const [],
    this.message,
  });
}

class _ReportMsg extends _Msg {
  final ReportEntity report;
  final String summary;
  final String question;
  bool shown;
  _ReportMsg(
    this.report, {
    required this.summary,
    this.question = '',
    this.shown = false,
  });
}

class _RecordMsg extends _Msg {
  final List<ParsedEntry> entries;
  final List<CategoryEntity?> cats;
  bool saved;
  bool saving = false;
  List<int> savedIds;
  List<int?> txnIds; // 已入库时,每个条目对应的记录 id(无金额为 null);供按条目改分类

  /// 已被用户从明细卡上删除的条目下标（跨重启持久化，恢复时从 JSON 灌回）。
  final Set<int> deletedIdx = <int>{};
  String savedFeedback; // 记完后猫给的一句数据反馈

  /// 这张卡在 chat_messages 表里的行 id（已保存的卡才有）；改分类/删条目后
  /// 用它把最新状态写回，跨重启恢复。null=还没持久化。
  int? chatRowId;

  /// Durable AI operation which produced this card. Used for one-tap undo and
  /// diagnostics; legacy cards leave this null.
  final String? aiRunId;
  bool rolledBack = false;

  _RecordMsg({
    required this.entries,
    required this.cats,
    this.saved = false,
    this.savedIds = const [],
    this.txnIds = const [],
    this.savedFeedback = '',
    this.aiRunId,
    this.rolledBack = false,
    this.chatRowId,
  });
}

class _RefundMsg extends _Msg {
  final int originalId;
  final int refundId;
  final String title;
  final String categoryName;
  final String bookName;
  final Decimal amount;
  final Decimal originalAmount;
  final Decimal refundedAfter;
  final DateTime date;
  final TransactionTimePrecision timePrecision;

  _RefundMsg({
    required this.originalId,
    required this.refundId,
    required this.title,
    required this.categoryName,
    required this.bookName,
    required this.amount,
    required this.originalAmount,
    required this.refundedAfter,
    required this.date,
    required this.timePrecision,
  });

  factory _RefundMsg.fromDecoded(DecodedRefundCard decoded) => _RefundMsg(
        originalId: decoded.originalId,
        refundId: decoded.refundId,
        title: decoded.title,
        categoryName: decoded.categoryName,
        bookName: decoded.bookName,
        amount: decoded.amount,
        originalAmount: decoded.originalAmount,
        refundedAfter: decoded.refundedAfter,
        date: decoded.date,
        timePrecision: decoded.timePrecision,
      );
}

@visibleForTesting
class DecodedRefundCard {
  final int originalId;
  final int refundId;
  final String title;
  final String categoryName;
  final String bookName;
  final Decimal amount;
  final Decimal originalAmount;
  final Decimal refundedAfter;
  final DateTime date;
  final TransactionTimePrecision timePrecision;

  const DecodedRefundCard({
    required this.originalId,
    required this.refundId,
    required this.title,
    required this.categoryName,
    required this.bookName,
    required this.amount,
    required this.originalAmount,
    required this.refundedAfter,
    required this.date,
    required this.timePrecision,
  });
}

String _encodeRefundCard(_RefundMsg message) => jsonEncode({
      'originalId': message.originalId,
      'refundId': message.refundId,
      'title': message.title,
      'categoryName': message.categoryName,
      'bookName': message.bookName,
      'amount': message.amount.toString(),
      'originalAmount': message.originalAmount.toString(),
      'refundedAfter': message.refundedAfter.toString(),
      'date': message.date.millisecondsSinceEpoch,
      'timePrecision': message.timePrecision.storageKey,
    });

@visibleForTesting
DecodedRefundCard decodeRefundCard(String json) {
  final map = jsonDecode(json) as Map<String, dynamic>;
  Decimal money(String key) =>
      Decimal.tryParse(map[key] as String? ?? '') ?? Decimal.zero;
  return DecodedRefundCard(
    originalId: (map['originalId'] as num).toInt(),
    refundId: (map['refundId'] as num).toInt(),
    title: map['title'] as String? ?? '',
    categoryName: map['categoryName'] as String? ?? '',
    bookName: map['bookName'] as String? ?? '',
    amount: money('amount'),
    originalAmount: money('originalAmount'),
    refundedAfter: money('refundedAfter'),
    date: DateTime.fromMillisecondsSinceEpoch(
      (map['date'] as num?)?.toInt() ?? 0,
    ),
    timePrecision: TransactionTimePrecisionX.fromStorage(
      map['timePrecision'] as String?,
    ),
  );
}

/// 解码后的记账卡原始数据（catId 未解析成 CategoryEntity，恢复时用 repo 查回）。
class DecodedRecordCard {
  final List<ParsedEntry> entries;
  final List<int?> catIds;
  final List<int?> txnIds;
  final bool saved;
  final String feedback;
  final Set<int> deleted;
  final String? aiRunId;
  final bool rolledBack;
  const DecodedRecordCard({
    required this.entries,
    required this.catIds,
    required this.txnIds,
    required this.saved,
    required this.feedback,
    required this.deleted,
    this.aiRunId,
    this.rolledBack = false,
  });
}

/// 把一张记账卡的结构化数据编码成 JSON（跨重启恢复用）。
/// 抽成顶层纯函数便于单测（不依赖 Widget/BuildContext）。
String encodeRecordCard({
  required List<ParsedEntry> entries,
  required List<int?> catIds,
  required List<int?> txnIds,
  required bool saved,
  required String feedback,
  required Set<int> deleted,
  String? aiRunId,
  bool rolledBack = false,
}) {
  final list = <Map<String, dynamic>>[];
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    list.add({
      'amt': e.amount?.toString(),
      'kind': e.kind.toJson(),
      'catKey': e.categoryKey,
      'note': e.note,
      'date': e.date.millisecondsSinceEpoch,
      'timePrecision': e.timePrecision.storageKey,
      'conf': e.confidence,
      'catId': i < catIds.length ? catIds[i] : null,
      'txnId': i < txnIds.length ? txnIds[i] : null,
    });
  }
  return jsonEncode({
    'saved': saved,
    'feedback': feedback,
    'deleted': deleted.toList(),
    if (aiRunId != null && aiRunId.trim().isNotEmpty) 'aiRunId': aiRunId,
    if (rolledBack) 'rolledBack': true,
    'entries': list,
  });
}

/// 解码记账卡 JSON。坏数据尽量容错（跳过烂条目而不是整卡丢失）。
DecodedRecordCard decodeRecordCard(String json) {
  final map = jsonDecode(json) as Map<String, dynamic>;
  final rawEntries = (map['entries'] as List?) ?? const [];
  final entries = <ParsedEntry>[];
  final catIds = <int?>[];
  final txnIds = <int?>[];
  for (final raw in rawEntries) {
    final m = raw as Map<String, dynamic>;
    final amtStr = m['amt'] as String?;
    TransactionKind kind;
    try {
      kind = TransactionKind.fromJson(m['kind'] as String? ?? 'expense');
    } catch (_) {
      kind = TransactionKind.expense;
    }
    entries.add(
      ParsedEntry(
        amount: amtStr == null ? null : Decimal.tryParse(amtStr),
        kind: kind,
        categoryKey: m['catKey'] as String?,
        note: (m['note'] as String?) ?? '',
        date: DateTime.fromMillisecondsSinceEpoch(
          (m['date'] as num?)?.toInt() ?? 0,
        ),
        timePrecision: TransactionTimePrecisionX.fromStorage(
          m['timePrecision'] as String?,
        ),
        confidence: (m['conf'] as num?)?.toDouble() ?? 0.7,
      ),
    );
    catIds.add((m['catId'] as num?)?.toInt());
    txnIds.add((m['txnId'] as num?)?.toInt());
  }
  final deleted = <int>{
    for (final d in (map['deleted'] as List?) ?? const []) (d as num).toInt(),
  };
  return DecodedRecordCard(
    entries: entries,
    catIds: catIds,
    txnIds: txnIds,
    saved: (map['saved'] as bool?) ?? true,
    feedback: (map['feedback'] as String?) ?? '',
    deleted: deleted,
    aiRunId: (map['aiRunId'] as String?)?.trim(),
    rolledBack: map['rolledBack'] == true,
  );
}

class DecodedReportChatMessage {
  final int reportId;
  final String summary;

  const DecodedReportChatMessage({
    required this.reportId,
    required this.summary,
  });
}

String encodeReportChatMessage(ReportEntity report, String summary) {
  return jsonEncode({'reportId': report.id, 'summary': summary});
}

DecodedReportChatMessage? decodeReportChatMessage(String json) {
  try {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final id = (map['reportId'] as num?)?.toInt();
    if (id == null || id <= 0) return null;
    return DecodedReportChatMessage(
      reportId: id,
      summary: (map['summary'] as String?)?.trim() ?? '',
    );
  } catch (_) {
    return null;
  }
}

String? reportTypeOf(String text) => _reportTypeOf(text);

DateTimeRange reportPeriodOf(
  String type,
  DateTime now, {
  required String question,
}) =>
    _reportPeriodOf(type, now, question: question);

String reportTitleOf(String type, DateTimeRange period) =>
    _reportTitleOf(type, period);

String reportMarkdown(String title, String answer) =>
    _reportMarkdown(title, answer);

String reportSummary(String markdown) => _reportSummary(markdown);

bool shouldCreateReportDocument({
  required String? reportType,
  required bool aiAnswered,
}) =>
    _shouldCreateReportDocument(reportType: reportType, aiAnswered: aiAnswered);

String? _reportTypeOf(String text) {
  final q = text.trim().toLowerCase();
  if (q.isEmpty) return null;
  if (q.contains('年报') ||
      q.contains('年度报告') ||
      q.contains('年度总结') ||
      (q.contains('年度') && (q.contains('报告') || q.contains('总结'))) ||
      RegExp(r'\d{4}\s*年(?!\s*\d{1,2}\s*月).*?(报告|总结)').hasMatch(q) ||
      q.contains('yearly report') ||
      q.contains('annual report')) {
    return 'yearly';
  }
  if (q.contains('周报') ||
      q.contains('本周报告') ||
      q.contains('周总结') ||
      q.contains('weekly report')) {
    return 'weekly';
  }
  if (q.contains('月报') ||
      q.contains('月度报告') ||
      q.contains('月度总结') ||
      q.contains('消费报告') ||
      RegExp(r'(本月|这个月|上月|上个月|\d{1,2}\s*月).*?(报告|总结)').hasMatch(q) ||
      RegExp(r'(报告|总结).*?(本月|这个月|上月|上个月|\d{1,2}\s*月)').hasMatch(q) ||
      q.contains('monthly report')) {
    return 'monthly';
  }
  return null;
}

DateTimeRange _reportPeriodOf(
  String type,
  DateTime now, {
  required String question,
}) {
  final parsed = QueryRange.parse(question, now);
  if (parsed != null) {
    return DateTimeRange(start: parsed.start, end: parsed.end);
  }

  final today = DateTime(now.year, now.month, now.day);
  if (type == 'yearly') {
    final year = _explicitYearOf(question);
    if (year != null) {
      return DateTimeRange(
        start: DateTime(year, 1, 1),
        end: year == now.year ? today : DateTime(year, 12, 31),
      );
    }
  }
  return switch (type) {
    'weekly' => DateTimeRange(
        start: today.subtract(Duration(days: today.weekday - 1)),
        end: today,
      ),
    'yearly' => DateTimeRange(start: DateTime(now.year, 1, 1), end: today),
    _ => DateTimeRange(start: DateTime(now.year, now.month, 1), end: today),
  };
}

int? _explicitYearOf(String question) {
  final m = RegExp(r'((?:19|20)\d{2})\s*年').firstMatch(question);
  if (m == null) return null;
  return int.tryParse(m.group(1)!);
}

String _reportTitleOf(String type, DateTimeRange period) {
  final start = period.start;
  return switch (type) {
    'weekly' => '${start.year}年${start.month}月${start.day}日消费周报',
    'yearly' => '${start.year}年消费年报',
    _ => '${start.year}年${start.month}月消费月报',
  };
}

String _reportMarkdown(String title, String answer) {
  final trimmed = answer.trim();
  if (trimmed.startsWith('# ')) return trimmed;
  return '# $title\n\n$trimmed';
}

String _reportSummary(String markdown) {
  final summaryLines = <String>[];
  var inLeadSection = false;
  for (final raw in markdown.split('\n')) {
    final line = raw.trim();
    if (RegExp(r'^##\s+(本月一句话|摘要)').hasMatch(line)) {
      inLeadSection = true;
      continue;
    }
    if (inLeadSection && RegExp(r'^#{1,6}\s+').hasMatch(line)) break;
    if (!inLeadSection || line.isEmpty || line.startsWith('|')) continue;
    final cleaned = line
        .replaceFirst(RegExp(r'^\s*[-*]\s+'), '')
        .replaceAll('**', '')
        .trim();
    if (cleaned.isNotEmpty) summaryLines.add(cleaned);
  }

  final cleanedLines = summaryLines.isNotEmpty ? summaryLines : <String>[];
  if (cleanedLines.isEmpty) {
    for (final raw in markdown.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('|')) continue;
      if (RegExp(r'^#{1,6}\s+').hasMatch(line)) continue;
      final cleaned = line
          .replaceFirst(RegExp(r'^\s*#{1,6}\s+'), '')
          .replaceFirst(RegExp(r'^\s*[-*]\s+'), '')
          .replaceAll('**', '')
          .trim();
      if (cleaned.isNotEmpty) cleanedLines.add(cleaned);
    }
  }
  final cleaned = cleanedLines.join(' ');
  if (cleaned.length <= 160) return cleaned;
  return '${cleaned.substring(0, 160)}…';
}

bool _shouldCreateReportDocument({
  required String? reportType,
  required bool aiAnswered,
}) {
  return reportType != null && aiAnswered;
}

// ─────────────────────────────────────────────────────────────────────────────
// 消息气泡
// ─────────────────────────────────────────────────────────────────────────────

// Chat body copy is intentionally quieter than the input control. Keep the
// values in one place so user messages, answers, reports, and notices stay at
// the same visual scale when the panel is used as a full Chats conversation.
const double _chatBodyFontSize = 15.5;
const double _chatBodyLineHeight = 1.48;
const _cjkFontFallback = <String>['NotoSansSC'];

TextStyle _chatBodyStyle(
  ColorScheme scheme, {
  double fontSize = _chatBodyFontSize,
  double? height = _chatBodyLineHeight,
  FontWeight fontWeight = FontWeight.w400,
  double? variableWeight = 350,
  Color? color,
}) =>
    TextStyle(
      fontSize: fontSize,
      height: height,
      fontWeight: fontWeight,
      // Rich/SelectableText spans do not always inherit ThemeData.fontFamily
      // on the Windows screenshot engine. Set the app's Latin face explicitly
      // so CJK fallback is resolved consistently instead of painting a .notdef
      // block for otherwise valid characters.
      fontFamily: 'Nunito',
      fontFamilyFallback: _cjkFontFallback,
      fontVariations: variableWeight == null
          ? null
          : [FontVariation('wght', variableWeight)],
      color: color ?? scheme.onSurface.withValues(alpha: 0.9),
    );

List<InlineSpan> _chatNumberSpans(String text, TextStyle base) {
  final spans = <InlineSpan>[];
  final numberStyle = base.copyWith(
    fontFamily: 'Nunito',
    fontFeatures: const [FontFeature.tabularFigures()],
  );
  final numberPattern = RegExp(r'[+\-￥¥]?\d[\d,]*(?:\.\d+)?%?');
  var start = 0;
  for (final m in numberPattern.allMatches(text)) {
    if (m.start > start) {
      spans.add(TextSpan(text: text.substring(start, m.start)));
    }
    spans.add(TextSpan(text: m.group(0), style: numberStyle));
    start = m.end;
  }
  if (start < text.length) {
    spans.add(TextSpan(text: text.substring(start)));
  }
  return spans;
}

class _UserBubble extends StatefulWidget {
  final String text;
  final List<ChatAttachment> attachments;
  final bool fullBleedAttachments;
  final bool selected;
  final bool textSelectionMode;
  final VoidCallback? onSelectionDismissed;
  final ValueChanged<BuildContext>? onLongPress;

  const _UserBubble({
    required this.text,
    this.attachments = const [],
    this.fullBleedAttachments = false,
    this.selected = false,
    this.textSelectionMode = false,
    this.onSelectionDismissed,
    this.onLongPress,
  });

  @override
  State<_UserBubble> createState() => _UserBubbleState();
}

class _UserBubbleState extends State<_UserBubble> {
  late final TextEditingController _selectionController;
  final FocusNode _selectionFocus = FocusNode();
  final GlobalKey<EditableTextState> _editableKey =
      GlobalKey<EditableTextState>();

  @override
  void initState() {
    super.initState();
    _selectionController = TextEditingController(text: widget.text);
    if (widget.textSelectionMode) _scheduleNativeSelection();
  }

  @override
  void didUpdateWidget(covariant _UserBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _selectionController.text = widget.text;
    }
    if (!oldWidget.textSelectionMode && widget.textSelectionMode) {
      _scheduleNativeSelection();
    } else if (oldWidget.textSelectionMode && !widget.textSelectionMode) {
      _selectionFocus.unfocus();
    }
  }

  void _scheduleNativeSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.textSelectionMode || widget.text.isEmpty) return;
      _selectionController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.text.length,
      );
      _selectionFocus.requestFocus();
      _editableKey.currentState?.showToolbar();
    });
  }

  @override
  void dispose() {
    _selectionController.dispose();
    _selectionFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bubbleStyle = context.select<AppRepository, UserMessageBubbleStyle>(
      (repo) => repo.userMessageBubbleStyle,
    );
    final bubbleColor = widget.selected
        ? scheme.surface.withValues(alpha: 0.96)
        : bubbleStyle == UserMessageBubbleStyle.followCardOpacity
            ? AppColors.card(scheme)
            : scheme.surfaceContainerHighest;
    final textStyle = _chatBodyStyle(
      scheme,
      fontSize: 15,
      height: null,
      color: scheme.onSurface,
    );
    final hasAttachments = widget.attachments.isNotEmpty;
    final hasText = widget.text.trim().isNotEmpty;

    Widget buildTextContent() {
      if (!hasText) return const SizedBox.shrink();
      if (widget.textSelectionMode) {
        return DefaultSelectionStyle(
          selectionColor: const Color(0xFF0A84FF).withValues(alpha: 0.28),
          child: EditableText(
            key: _editableKey,
            controller: _selectionController,
            focusNode: _selectionFocus,
            readOnly: true,
            showCursor: false,
            forceLine: false,
            maxLines: null,
            style: textStyle,
            cursorColor: const Color(0xFF0A84FF),
            backgroundCursorColor: scheme.surface,
            selectionColor: const Color(0xFF0A84FF).withValues(alpha: 0.28),
            selectionControls: materialTextSelectionControls,
            onTapOutside: (_) {
              _selectionFocus.unfocus();
              widget.onSelectionDismissed?.call();
            },
            contextMenuBuilder: (context, state) =>
                AdaptiveTextSelectionToolbar.editableText(
              editableTextState: state,
            ),
          ),
        );
      }
      return Text.rich(
        TextSpan(children: _chatNumberSpans(widget.text, textStyle)),
        style: textStyle,
      );
    }

    BoxDecoration textSurfaceDecoration() => BoxDecoration(
          color: bubbleColor,
          border: widget.selected
              ? Border.all(
                  color: scheme.onSurface.withValues(alpha: 0.13),
                  width: 0.7,
                )
              : null,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
          boxShadow: widget.selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 24,
                    offset: const Offset(0, 9),
                  ),
                ]
              : null,
        );

    Widget buildTextSurface() => AnimatedContainer(
          key: const ValueKey('ai-chat-user-bubble-surface'),
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: textSurfaceDecoration(),
          child: buildTextContent(),
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        Widget bubble = Align(
          alignment: Alignment.centerRight,
          child: Padding(
            // Attachments follow the Claude/GPT layout: the image strip uses
            // the whole chat content width, while text remains a compact right
            // bubble.
            padding: EdgeInsets.only(bottom: 10, left: hasAttachments ? 0 : 40),
            child: Builder(
              builder: (bubbleContext) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress:
                    widget.textSelectionMode || widget.onLongPress == null
                        ? null
                        : () => widget.onLongPress!(bubbleContext),
                child: AnimatedScale(
                  key: const ValueKey('ai-chat-user-bubble-scale'),
                  scale: widget.selected ? 1.18 : 1,
                  alignment: Alignment.centerRight,
                  duration: const Duration(milliseconds: 170),
                  curve: Curves.easeOutBack,
                  child: hasAttachments
                      ? SizedBox(
                          width: double.infinity,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _SentAttachmentGrid(
                                attachments: widget.attachments,
                              ),
                              if (hasText) ...[
                                const SizedBox(height: 8),
                                buildTextSurface(),
                              ],
                            ],
                          ),
                        )
                      : buildTextSurface(),
                ),
              ),
            ),
          ),
        );

        // The history list already supplies the reference layout's small
        // horizontal content inset. Attachment rows use that full available
        // width directly, so three square cards fill the chat content area
        // without touching the physical screen edges.
        return bubble;
      },
    );
  }
}

class _ThinkingBubble extends StatefulWidget {
  final _ThinkingMsg msg;
  const _ThinkingBubble({required this.msg});

  @override
  State<_ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<_ThinkingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  _ThinkingMsg get msg => widget.msg;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    );
    if (!msg.completed) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _ThinkingBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (msg.completed) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _durationLabel(Duration duration) {
    final seconds = duration.inSeconds;
    if (seconds < 60) return '${seconds}s';
    return '${seconds ~/ 60}m ${seconds % 60}s';
  }

  @override
  Widget build(BuildContext context) {
    if (msg.hidden) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final secondary = AppTextColor.secondary(scheme);
    if (!msg.completed) {
      final thinkingColor = scheme.onSurfaceVariant.withValues(alpha: 0.84);
      final statusText = aiThinkingStatusText(
        elapsed: msg.elapsed,
        canContinueInBackground: msg.canContinueInBackground,
      );
      final displayStatus =
          statusText == '喵还在思考，完成后会显示在这里。' ? '正在思考 · 完成后会显示在这里。' : statusText;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment(-1.8 + _controller.value * 3.6, 0),
              end: Alignment(-0.8 + _controller.value * 3.6, 0),
              colors: [
                thinkingColor.withValues(alpha: 0.46),
                thinkingColor,
                thinkingColor.withValues(alpha: 0.46),
              ],
            ).createShader(bounds),
            child: child,
          ),
          child: Text(
            key: const ValueKey('ai-chat-thinking-label'),
            displayStatus,
            style: _chatBodyStyle(
              scheme,
              fontSize: 15,
              height: null,
              variableWeight: null,
              color: thinkingColor,
            ),
          ),
        ),
      );
    }
    final summaries = <String>[];
    for (final step in msg.steps) {
      final summary = step.detail.trim();
      if (summary.isNotEmpty && !summaries.contains(summary)) {
        summaries.add(summary);
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => msg.expanded = !msg.expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '思考了 ${_durationLabel(msg.elapsed)}',
                    style: _chatBodyStyle(scheme,
                        fontSize: 15,
                        height: null,
                        variableWeight: null,
                        color: scheme.onSurface.withValues(alpha: 0.46)),
                  ),
                  const SizedBox(width: 3),
                  AnimatedRotation(
                    turns: msg.expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 170),
                    child: Icon(Icons.chevron_right_rounded,
                        size: 18, color: secondary),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 190),
            curve: Curves.easeOutCubic,
            child: msg.expanded
                ? Padding(
                    key: const ValueKey('ai-chat-thinking-details'),
                    padding: const EdgeInsets.only(top: 7, right: 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (summaries.isEmpty && msg.sources.isEmpty)
                          Text(
                            '模型没有返回可展示的思考摘要。',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: secondary,
                            ),
                          ),
                        for (var index = 0;
                            index < summaries.length;
                            index++) ...[
                          if (index > 0) const SizedBox(height: 7),
                          Text(
                            summaries[index],
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: secondary,
                            ),
                          ),
                        ],
                        if (msg.sources.isNotEmpty) ...[
                          if (summaries.isNotEmpty) const SizedBox(height: 7),
                          Text(
                            '搜索并参考了 ${msg.sources.length} 个公开来源',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: secondary,
                            ),
                          ),
                        ],
                        const SizedBox(height: 9),
                        Divider(
                          height: 1,
                          thickness: 0.6,
                          color: scheme.outlineVariant.withValues(alpha: 0.62),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _AttachmentDraftStrip extends StatelessWidget {
  final List<ChatAttachment> attachments;
  final ValueChanged<int> onRemove;

  const _AttachmentDraftStrip({
    required this.attachments,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileSize = draftAttachmentTileWidth(constraints.maxWidth);
        return SizedBox(
          key: const ValueKey('ai-chat-attachment-draft-strip'),
          height: tileSize,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: attachments.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final attachment = attachments[index];
              return _AttachmentTile(
                key: ValueKey('ai-chat-draft-attachment-$index'),
                attachment: attachment,
                size: tileSize,
                onRemove: () => onRemove(index),
              );
            },
          ),
        );
      },
    );
  }
}

Rect _scaledMessageRect(Rect anchor, {double scale = 1.18}) {
  final width = anchor.width * scale;
  final height = anchor.height * scale;
  return Rect.fromLTWH(
    anchor.right - width,
    anchor.center.dy - height / 2,
    width,
    height,
  );
}

class _MessageActionOverlay extends StatelessWidget {
  final Rect anchor;
  final String timeLabel;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onSelectText;

  const _MessageActionOverlay({
    required this.anchor,
    required this.timeLabel,
    required this.onCopy,
    required this.onEdit,
    required this.onSelectText,
  });

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    const menuWidth = 218.0;
    const estimatedMenuHeight = 172.0;
    final highlighted = _scaledMessageRect(anchor).inflate(1.5);
    var menuTop = highlighted.bottom + 8;
    if (menuTop + estimatedMenuHeight > screen.height - 16) {
      menuTop = highlighted.top - estimatedMenuHeight - 8;
      if (menuTop < 16) {
        menuTop = 16;
      }
    }
    final menuLeft = (anchor.right - menuWidth)
        .clamp(12.0, screen.width - menuWidth - 12)
        .toDouble();
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: AppMenuScrim(
              highlightRect: highlighted,
              radius: 21,
            ),
          ),
          Positioned(
            left: menuLeft,
            top: menuTop,
            width: menuWidth,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.84, end: 1),
              duration: const Duration(milliseconds: 170),
              curve: Curves.easeOutBack,
              builder: (_, value, child) => Transform.scale(
                scale: value,
                alignment: menuTop < highlighted.top
                    ? Alignment.bottomRight
                    : Alignment.topRight,
                child: child,
              ),
              child: _MessageActionCard(
                timeLabel: timeLabel,
                onCopy: () {
                  Navigator.of(context).pop();
                  onCopy();
                },
                onEdit: () {
                  Navigator.of(context).pop();
                  onEdit();
                },
                onSelectText: () {
                  Navigator.of(context).pop();
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => onSelectText());
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageActionCard extends StatelessWidget {
  final String timeLabel;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onSelectText;

  const _MessageActionCard({
    required this.timeLabel,
    required this.onCopy,
    required this.onEdit,
    required this.onSelectText,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.52),
              width: 0.7,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 5),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(timeLabel,
                      style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w400)),
                ),
              ),
              _MessageActionRow(
                  icon: AppLineIcons.copy, label: '复制', onTap: onCopy),
              _MessageActionRow(
                  icon: AppLineIcons.pencil, label: '编辑', onTap: onEdit),
              _MessageActionRow(
                  icon: AppLineIcons.textSelect,
                  label: '选择文本',
                  onTap: onSelectText),
              const SizedBox(height: 5),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageActionRow extends StatelessWidget {
  final AppLineIconData icon;
  final String label;
  final VoidCallback onTap;

  const _MessageActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      splashFactory: NoSplash.splashFactory,
      highlightColor: scheme.onSurface.withValues(alpha: 0.055),
      child: Container(
        height: 42,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            AppLineIcon(icon, size: 20, color: scheme.onSurface),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: scheme.onSurface)),
          ],
        ),
      ),
    );
  }
}

class _SentAttachmentGrid extends StatelessWidget {
  final List<ChatAttachment> attachments;

  const _SentAttachmentGrid({required this.attachments});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallback = min(MediaQuery.sizeOf(context).width, 420.0);
        final width =
            constraints.hasBoundedWidth ? constraints.maxWidth : fallback;
        final tileWidth = sentAttachmentTileWidth(width, attachments.length);
        // Three-image messages follow the reference layout: equal square
        // cards, tiny gaps, and the full chat content width.
        final tileHeight = sentAttachmentTileHeight(width, attachments.length);
        if (attachments.length <= 3) {
          return SizedBox(
            width: width,
            height: tileHeight,
            child: Row(
              children: [
                for (var index = 0; index < attachments.length; index++) ...[
                  if (index > 0) const SizedBox(width: 6),
                  _AttachmentTile(
                    attachment: attachments[index],
                    width: tileWidth,
                    height: tileHeight,
                  ),
                ],
              ],
            ),
          );
        }
        return SizedBox(
          width: width,
          height: tileHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: attachments.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, index) => _AttachmentTile(
              attachment: attachments[index],
              width: tileWidth,
              height: tileHeight,
            ),
          ),
        );
      },
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  final ChatAttachment attachment;
  final double? size;
  final double? width;
  final double? height;
  final VoidCallback? onRemove;

  const _AttachmentTile({
    super.key,
    required this.attachment,
    this.size,
    this.width,
    this.height,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tileWidth = width ?? size ?? 78;
    final tileHeight = height ?? size ?? 78;
    final content = attachment.isImage
        ? Image.file(
            File(attachment.path),
            width: tileWidth,
            height: tileHeight,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fileFallback(scheme),
          )
        : _fileFallback(scheme);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(width: tileWidth, height: tileHeight, child: content),
        ),
        if (onRemove != null)
          Positioned(
            top: -5,
            right: -5,
            child: GestureDetector(
              key: const ValueKey('ai-chat-remove-attachment'),
              onTap: onRemove,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.78),
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 1.5),
                ),
                child:
                    Icon(Icons.close_rounded, size: 14, color: scheme.surface),
              ),
            ),
          ),
      ],
    );
  }

  Widget _fileFallback(ColorScheme scheme) => Container(
        color: scheme.surfaceContainerHighest,
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.insert_drive_file_outlined,
                size: 27, color: scheme.onSurfaceVariant),
            const SizedBox(height: 5),
            Text(
              attachment.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: scheme.onSurface),
            ),
          ],
        ),
      );
}

/// Claude 手机端风格的来源面板：默认半屏，可上拉查看全部来源，松手由
/// DraggableScrollableSheet 自带弹簧回到最近的停靠位置；不会把来源挤进正文。
class _SourcesDraggableSheet extends StatelessWidget {
  final List<AiWebSource> sources;

  const _SourcesDraggableSheet({required this.sources});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.46,
      minChildSize: 0.30,
      maxChildSize: 0.92,
      builder: (sheetContext, controller) => Container(
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.98),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: 0.42)),
        ),
        child: SafeArea(
          top: false,
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 26),
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              SheetHeader(
                title: '来源',
                subtitle: '${sources.length} 个公开网页来源',
                onClose: () => Navigator.of(sheetContext).pop(),
              ),
              for (final source in sources) _SourcePanelRow(source: source),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourcePanelRow extends StatelessWidget {
  final AiWebSource source;

  const _SourcePanelRow({required this.source});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final uri = Uri.tryParse(source.url);
    final host = uri?.host.replaceFirst(RegExp(r'^www\.'), '') ?? '网页来源';
    final title = source.title.trim().isEmpty ? host : source.title.trim();
    final faviconUri = host.isEmpty
        ? null
        : Uri.parse(
            'https://www.google.com/s2/favicons?domain=${Uri.encodeComponent(host)}&sz=64',
          );
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')
          ? null
          : () => launchUrl(uri, mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: SizedBox(
                width: 30,
                height: 30,
                child: faviconUri == null
                    ? ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: Center(
                          child: Text(
                            _sourceInitial(host),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : Image.network(
                        faviconUri.toString(),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => ColoredBox(
                          color: scheme.surfaceContainerHighest,
                          child: Center(
                            child: Text(
                              _sourceInitial(host),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Text(host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                  if (source.snippet.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(source.snippet.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: scheme.onSurfaceVariant
                                .withValues(alpha: 0.82))),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(CupertinoIcons.arrow_up_right,
                size: 16, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  String _sourceInitial(String host) =>
      host.isEmpty ? '源' : host.characters.first.toUpperCase();
}

class _InfoBubble extends StatelessWidget {
  final String text;
  final bool error;
  const _InfoBubble({required this.text, this.error = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 守不用红铁律：错误提示用超支橙；普通说明走标准中灰。
    final textStyle = _chatBodyStyle(
      scheme,
      fontSize: 14,
      height: null,
      variableWeight: null,
      color: error ? AppColors.warning : AppTextColor.secondary(scheme),
    );
    // 去掉左边的小猫（记账确认这类信息太多猫了），只留文字。
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4, right: 40),
      child: Text.rich(
        TextSpan(children: _chatNumberSpans(text, textStyle)),
        style: textStyle,
      ),
    );
  }
}

class _ClaudeActionButton extends StatelessWidget {
  final String svg;
  final VoidCallback onTap;
  final String tooltip;
  final bool active;

  const _ClaudeActionButton({
    required this.svg,
    required this.onTap,
    required this.tooltip,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.primary : AppTextColor.secondary(scheme);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        selected: active,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: kAiResponseActionTouchExtent,
            height: kAiResponseActionTouchExtent,
            child: Center(
              child: SvgPicture.string(
                svg,
                width: kAiResponseActionIconExtent,
                height: kAiResponseActionIconExtent,
                colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceActionButton extends StatelessWidget {
  final List<AiWebSource> sources;
  final VoidCallback onTap;

  const _SourceActionButton({required this.sources, required this.onTap});

  Uri? _favicon(AiWebSource source) {
    final host = Uri.tryParse(source.url)?.host ?? '';
    if (host.isEmpty) return null;
    return Uri.parse(
      'https://www.google.com/s2/favicons?domain=${Uri.encodeComponent(host)}&sz=64',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = sources.take(3).toList(growable: false);
    final stackWidth = visible.isEmpty ? 0.0 : 18.0 + (visible.length - 1) * 11;
    return Tooltip(
      message: '${sources.length} 个来源',
      child: Semantics(
        container: true,
        button: true,
        label: '${sources.length} 个来源',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: kAiResponseActionTouchExtent,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: stackWidth,
                  height: 20,
                  child: Stack(
                    children: [
                      for (var index = 0; index < visible.length; index++)
                        Positioned(
                          left: index * 11,
                          child: Container(
                            width: 20,
                            height: 20,
                            padding: const EdgeInsets.all(1.2),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: scheme.outlineVariant
                                    .withValues(alpha: 0.72),
                                width: 0.6,
                              ),
                            ),
                            child: ClipOval(
                              child: _SourceFavicon(
                                uri: _favicon(visible[index]),
                                source: visible[index],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '${sources.length} 个来源',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                    color: AppTextColor.secondary(scheme),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceFavicon extends StatelessWidget {
  final Uri? uri;
  final AiWebSource source;

  const _SourceFavicon({required this.uri, required this.source});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget fallback() {
      final host =
          Uri.tryParse(source.url)?.host.replaceFirst('www.', '') ?? '';
      final initial = host.isEmpty ? '源' : host.characters.first.toUpperCase();
      return ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Center(
          child: Text(
            initial,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    if (uri == null) return fallback();
    return Image.network(
      uri.toString(),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => fallback(),
    );
  }
}

enum _MarkdownTableAlignment { left, center, right }

/// A real table block rather than a monospaced pipe-delimited paragraph.
/// Equal/flexible columns keep every row aligned; a horizontal scroll view
/// preserves long English values without squeezing the surrounding answer.
class _MarkdownTable extends StatelessWidget {
  final List<List<String>> rows;
  final List<_MarkdownTableAlignment> alignments;
  final TextStyle textStyle;
  final List<InlineSpan> Function(String text, TextStyle style) spanBuilder;

  const _MarkdownTable({
    required this.rows,
    required this.alignments,
    required this.textStyle,
    required this.spanBuilder,
  });

  Alignment _alignment(_MarkdownTableAlignment value) => switch (value) {
        _MarkdownTableAlignment.center => Alignment.center,
        _MarkdownTableAlignment.right => Alignment.centerRight,
        _MarkdownTableAlignment.left => Alignment.centerLeft,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final columnCount = rows.fold<int>(
      0,
      (count, row) => max(count, row.length),
    );
    if (columnCount < 2 || rows.isEmpty) return const SizedBox.shrink();
    final normalizedRows = [
      for (final row in rows)
        [
          for (var i = 0; i < columnCount; i++) i < row.length ? row[i] : '',
        ],
    ];
    return Padding(
      key: const ValueKey('ai-chat-markdown-table'),
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              // Intrinsic widths keep long headers/cells on one visual line;
              // the surrounding horizontal scroll view then behaves like
              // Claude instead of squeezing every column into the viewport.
              columnWidths: {
                for (var i = 0; i < columnCount; i++)
                  i: const IntrinsicColumnWidth(),
              },
              border: TableBorder(
                horizontalInside: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.58),
                  width: 0.7,
                ),
                bottom: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.72),
                  width: 0.8,
                ),
              ),
              children: [
                for (var rowIndex = 0;
                    rowIndex < normalizedRows.length;
                    rowIndex++)
                  TableRow(
                    decoration: rowIndex == 0
                        ? BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(
                              alpha: 0.28,
                            ),
                          )
                        : null,
                    children: [
                      for (var column = 0; column < columnCount; column++)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 8,
                          ),
                          child: Align(
                            alignment: _alignment(
                              column < alignments.length
                                  ? alignments[column]
                                  : _MarkdownTableAlignment.left,
                            ),
                            child: SelectableText.rich(
                              TextSpan(
                                style: rowIndex == 0
                                    ? textStyle.copyWith(
                                        fontWeight: FontWeight.w600,
                                      )
                                    : textStyle,
                                children: spanBuilder(
                                  normalizedRows[rowIndex][column],
                                  rowIndex == 0
                                      ? textStyle.copyWith(
                                          fontWeight: FontWeight.w600,
                                        )
                                      : textStyle,
                                ),
                              ),
                              maxLines: 1,
                              textAlign: switch (column < alignments.length
                                  ? alignments[column]
                                  : _MarkdownTableAlignment.left) {
                                _MarkdownTableAlignment.center =>
                                  TextAlign.center,
                                _MarkdownTableAlignment.right =>
                                  TextAlign.right,
                                _MarkdownTableAlignment.left => TextAlign.left,
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── 查账回答气泡（喵助手回答，打字机流式）────────────────────────────────────
class _AnswerBubble extends StatefulWidget {
  final String text;
  final List<AiWebSource> sources;
  final bool animate;
  final bool streaming;
  final bool interrupted;
  final VoidCallback? onShown;
  final VoidCallback? onRegenerate;
  final VoidCallback? onContinue;

  /// 是否在操作图标下放猫：只有列表最后一条回复为 true（对齐 Claude）。
  final bool showMascot;

  const _AnswerBubble({
    required this.text,
    this.sources = const [],
    this.animate = true,
    this.streaming = false,
    this.interrupted = false,
    this.onShown,
    this.onRegenerate,
    this.onContinue,
    this.showMascot = false,
  });

  @override
  State<_AnswerBubble> createState() => _AnswerBubbleState();
}

class _AnswerBubbleState extends State<_AnswerBubble> {
  int _shown = 0;
  int _graphemeCount = 0;
  bool _liked = false;
  bool _disliked = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _graphemeCount = aiTypewriterLength(widget.text);
    if (!widget.animate) {
      _shown = _graphemeCount;
      return;
    }
    _timer = Timer.periodic(const Duration(milliseconds: 28), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_shown >= _graphemeCount) {
        t.cancel();
        widget.onShown?.call();
        return;
      }
      setState(() {
        _shown = (_shown + 2).clamp(0, _graphemeCount);
      });
    });
  }

  @override
  void didUpdateWidget(covariant _AnswerBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text == widget.text &&
        oldWidget.animate == widget.animate &&
        oldWidget.streaming == widget.streaming) {
      return;
    }
    _graphemeCount = aiTypewriterLength(widget.text);
    if (!widget.animate) {
      _timer?.cancel();
      _timer = null;
      _shown = _graphemeCount;
    } else {
      _shown = _shown.clamp(0, _graphemeCount);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // 按回答语气挑一只猫。
  MascotMood _moodFor(String t) {
    if (t.contains('超支') || t.contains('超了') || t.contains('超出')) {
      return MascotMood.overspend;
    }
    if (t.contains('管住') || t.contains('继续保持') || t.contains('省钱')) {
      return MascotMood.celebrate;
    }
    return MascotMood.report;
  }

  // Claude 风格操作图标：Lucide 线性 SVG + 着色（选中态用主色）。
  Widget _action(
    String svg,
    String tooltip,
    VoidCallback onTap, {
    bool active = false,
  }) {
    return _ClaudeActionButton(
      svg: svg,
      tooltip: tooltip,
      onTap: onTap,
      active: active,
    );
  }

  // Claude-like emphasis: keep the same hierarchy after the body weight is
  // lowered by 50. Unsupported variable-font devices fall back to w500.
  TextStyle _boldOf(TextStyle base) => base.copyWith(
        fontWeight: FontWeight.w500,
        fontVariations: const [FontVariation('wght', 420)],
      );

  TextStyle _numberOf(TextStyle base, [TextStyle? style]) {
    final merged = style == null ? base : base.merge(style);
    return merged.copyWith(
      fontFamily: 'Nunito',
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  void _addTextWithNumberFont(
    List<InlineSpan> spans,
    String text,
    TextStyle base, [
    TextStyle? style,
  ]) {
    if (text.isEmpty) return;
    final numberPattern = RegExp(r'[+\-￥¥]?\d[\d,]*(?:\.\d+)?%?');
    var start = 0;
    for (final m in numberPattern.allMatches(text)) {
      if (m.start > start) {
        spans.add(TextSpan(text: text.substring(start, m.start), style: style));
      }
      spans.add(TextSpan(text: m.group(0), style: _numberOf(base, style)));
      start = m.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: style));
    }
  }

  /// 回答正文不直接铺开裸 URL。已知来源会在“处理摘要”里提供可点击
  /// 的来源卡；模型偶尔直接输出的链接从正文移除，避免把来源再次混进
  /// 正文（Markdown 链接仍保留用户可读的标签）。
  String _displaySafeLinks(String text) {
    final markdownLink = RegExp(
      r'\[([^\]]+)\]\((https?://[^)\s]+)\)',
      caseSensitive: false,
    );
    var result = text.replaceAllMapped(markdownLink, (match) {
      final label = match.group(1)?.trim() ?? '';
      return label.isEmpty ? '打开链接' : label;
    });
    final bareLink = RegExp(
      // Stop at both ASCII delimiters and common CJK punctuation. Without
      // the latter a URL followed by "，来源…" would consume the rest of the
      // sentence and silently remove legitimate answer text.
      r'https?://[^\s<>()[\]{}，。；：！？、]+',
      caseSensitive: false,
    );
    result = result.replaceAllMapped(bareLink, (_) => '');
    return result
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .replaceAllMapped(
          RegExp(r' +([，。；：！？])'),
          (match) => match.group(1)!,
        )
        .trim();
  }

  // 轻量 markdown → 富文本：处理 **加粗**、行首 - / * 列表、# 标题；保留可选中。
  List<InlineSpan> _mdSpans(String text, TextStyle base) {
    final spans = <InlineSpan>[];
    final lines = text.split('\n');
    final headerStyle = base.copyWith(
      fontSize: (base.fontSize ?? _chatBodyFontSize) + 0.4,
      fontWeight: FontWeight.w500,
      fontVariations: const [FontVariation('wght', 470)],
      color: base.color,
    );
    void newline() => spans.add(const TextSpan(text: '\n'));
    for (int li = 0; li < lines.length; li++) {
      var line = _displaySafeLinks(lines[li].replaceAll('__', ''));
      // 空行 = 段落间距（比普通换行大半行，给呼吸空间）。
      if (line.trim().isEmpty) {
        spans.add(const TextSpan(text: '\n', style: TextStyle(fontSize: 6)));
        continue;
      }
      // 标题：更大 + 更粗 + 上方留白（首行除外）。
      final h = RegExp(r'^\s*#{1,6}\s*').firstMatch(line);
      if (h != null) {
        if (li != 0) {
          spans.add(const TextSpan(text: '\n', style: TextStyle(fontSize: 4)));
        }
        _addTextWithNumberFont(spans, line.substring(h.end), base, headerStyle);
        if (li != lines.length - 1) newline();
        continue;
      }
      // 列表：无序 •、有序 1.（标记轻加粗，正文续行由 strutStyle 撑开行距）。
      final ul = RegExp(r'^\s*[-*]\s+').firstMatch(line);
      final ol = RegExp(r'^\s*(\d+)[.)]\s+').firstMatch(line);
      if (ul != null) {
        spans.add(TextSpan(text: '•  ', style: _boldOf(base)));
        line = line.substring(ul.end);
      } else if (ol != null) {
        spans.add(TextSpan(text: '${ol.group(1)}.  ', style: _boldOf(base)));
        line = line.substring(ol.end);
      }
      // 内联 **加粗**。
      final parts = line.split('**');
      for (int i = 0; i < parts.length; i++) {
        if (parts[i].isEmpty) continue;
        _addTextWithNumberFont(
          spans,
          parts[i],
          base,
          i.isOdd ? _boldOf(base) : null,
        );
      }
      if (li != lines.length - 1) newline();
    }
    return spans;
  }

  List<String> _tableCells(String line) {
    var value = line.trim();
    if (value.startsWith('|')) value = value.substring(1);
    if (value.endsWith('|') && !value.endsWith(r'\|')) {
      value = value.substring(0, value.length - 1);
    }
    if (!value.contains('|')) return const [];
    return value
        .split('|')
        .map((cell) => cell.trim().replaceAll(r'\|', '|'))
        .toList();
  }

  bool _isTableSeparator(String line) {
    final cells = _tableCells(line);
    if (cells.length < 2) return false;
    return cells.every(
      (cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell.replaceAll(' ', '')),
    );
  }

  List<_MarkdownTableAlignment> _tableAlignments(String line) {
    return [
      for (final cell in _tableCells(line))
        switch (cell.replaceAll(' ', '')) {
          final value when value.startsWith(':') && value.endsWith(':') =>
            _MarkdownTableAlignment.center,
          final value when value.endsWith(':') => _MarkdownTableAlignment.right,
          _ => _MarkdownTableAlignment.left,
        },
    ];
  }

  /// Splits prose and complete Markdown tables into separate render blocks.
  /// A pipe line is only promoted when the following line is a valid Markdown
  /// separator, so an in-progress streamed answer still renders as normal text.
  List<Widget> _markdownWidgets(String text, TextStyle baseStyle) {
    final widgets = <Widget>[];
    final prose = <String>[];
    final lines = text.split('\n');

    void flushProse() {
      if (prose.isEmpty) return;
      final proseText = prose.join('\n');
      widgets.add(
        SelectableText.rich(
          TextSpan(
            style: baseStyle,
            children: _mdSpans(proseText, baseStyle),
          ),
        ),
      );
      prose.clear();
    }

    var index = 0;
    while (index < lines.length) {
      final header = _tableCells(lines[index]);
      if (header.length >= 2 &&
          index + 1 < lines.length &&
          _isTableSeparator(lines[index + 1])) {
        flushProse();
        final alignments = _tableAlignments(lines[index + 1]);
        final rows = <List<String>>[header];
        index += 2;
        while (index < lines.length) {
          final row = _tableCells(lines[index]);
          if (row.length < 2) break;
          rows.add(row);
          index++;
        }
        widgets.add(
          _MarkdownTable(
            rows: rows,
            alignments: alignments,
            textStyle: baseStyle,
            spanBuilder: _mdSpans,
          ),
        );
        continue;
      }
      prose.add(lines[index]);
      index++;
    }
    flushProse();
    return widgets;
  }

  Future<void> _shareAnswer(BuildContext context) async {
    try {
      await Share.share(widget.text, subject: '喵助手回答');
    } catch (_) {
      if (context.mounted) showAppToast(context, '分享失败，请稍后再试');
    }
  }

  Future<void> _showSources(BuildContext context) async {
    if (widget.sources.isEmpty) return;
    await showDraggableAppSheet<void>(
      context,
      child: _SourcesDraggableSheet(sources: widget.sources),
    );
  }

  void _showMoreActions(BuildContext context) {
    showIosMenu(context, [
      IosMenuItem(
        label: '复制回答',
        icon: Icons.copy_outlined,
        onTap: () {
          Clipboard.setData(ClipboardData(text: widget.text));
          if (context.mounted) showAppToast(context, '已复制');
        },
      ),
      IosMenuItem(
        label: '分享回答',
        icon: Icons.ios_share_outlined,
        onTap: () => unawaited(_shareAnswer(context)),
      ),
      if (widget.onRegenerate != null)
        IosMenuItem(
          label: '重新生成',
          icon: Icons.refresh_rounded,
          onTap: widget.onRegenerate!,
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shownText = aiTypewriterPrefix(widget.text, _shown);
    final done = !widget.streaming && _shown >= _graphemeCount;
    // Claude-like answer typography: soft body text and restrained emphasis.
    final baseStyle = _chatBodyStyle(scheme);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 回答正文：全宽、无气泡（对标 Claude），轻量 markdown 渲染。
          ..._markdownWidgets(shownText, baseStyle),
          if (done) ...[
            if (widget.interrupted) ...[
              const SizedBox(height: 5),
              AppPillButton(
                key: const ValueKey('ai-chat-continue-answer'),
                label: '连接中断，继续生成',
                onPressed: widget.onContinue,
                leading: const Icon(Icons.refresh_rounded),
                foregroundColor: scheme.onSurfaceVariant,
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ],
            const SizedBox(height: 4),
            // 操作图标行（对标 Claude：裸图标、细线、浅灰）。
            Row(
              key: const ValueKey('ai-chat-answer-actions'),
              children: [
                _action(_icCopy, '复制', () {
                  Clipboard.setData(ClipboardData(text: widget.text));
                  showAppToast(context, '已复制');
                }),
                _action(
                  _liked ? _icThumbUpFill : _icThumbUp,
                  '赞同',
                  () => setState(() {
                    _liked = !_liked;
                    if (_liked) _disliked = false;
                  }),
                  active: _liked,
                ),
                _action(
                  _disliked ? _icThumbDownFill : _icThumbDown,
                  '不赞同',
                  () => setState(() {
                    _disliked = !_disliked;
                    if (_disliked) _liked = false;
                  }),
                  active: _disliked,
                ),
                if (widget.onRegenerate != null)
                  _action(_icRetry, '重新生成', widget.onRegenerate!),
                _action(_icShare, '分享', () => unawaited(_shareAnswer(context))),
                _action(_icMore, '更多', () => _showMoreActions(context)),
                if (widget.sources.isNotEmpty) ...[
                  const Spacer(),
                  _SourceActionButton(
                    sources: widget.sources,
                    onTap: () => unawaited(_showSources(context)),
                  ),
                ],
              ],
            ),
            if (widget.showMascot) ...[
              const SizedBox(height: 2),
              // 猫在操作图标下方、左侧；只跟着最后一条回复走。
              Mascot(mood: _moodFor(widget.text), size: 52, animate: true),
            ],
          ],
        ],
      ),
    );
  }
}

class _ReportBubble extends StatefulWidget {
  final _ReportMsg msg;
  final VoidCallback? onRegenerate;
  final bool showMascot;

  const _ReportBubble({
    required this.msg,
    this.onRegenerate,
    required this.showMascot,
  });

  @override
  State<_ReportBubble> createState() => _ReportBubbleState();
}

class _ReportBubbleState extends State<_ReportBubble> {
  bool _liked = false;
  bool _disliked = false;

  Widget _action(
    String svg,
    String tooltip,
    VoidCallback onTap, {
    bool active = false,
  }) {
    return _ClaudeActionButton(
      svg: svg,
      tooltip: tooltip,
      onTap: onTap,
      active: active,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final msg = widget.msg;
    final summary = msg.summary.isNotEmpty ? msg.summary : msg.report.summary;
    final textStyle = _chatBodyStyle(scheme);
    msg.shown = true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (summary.isNotEmpty) ...[
            SelectableText.rich(
              TextSpan(
                style: textStyle,
                children: _chatNumberSpans(summary, textStyle),
              ),
            ),
            const SizedBox(height: 10),
          ],
          ReportDocumentCard(report: msg.report, compact: true),
          const SizedBox(height: 4),
          Row(
            key: const ValueKey('ai-chat-report-actions'),
            children: [
              _action(_icCopy, '复制', () {
                Clipboard.setData(ClipboardData(text: msg.report.markdown));
                showAppToast(context, '已复制报告');
              }),
              _action(
                _liked ? _icThumbUpFill : _icThumbUp,
                '赞同',
                () => setState(() {
                  _liked = !_liked;
                  if (_liked) _disliked = false;
                }),
                active: _liked,
              ),
              _action(
                _disliked ? _icThumbDownFill : _icThumbDown,
                '不赞同',
                () => setState(() {
                  _disliked = !_disliked;
                  if (_disliked) _liked = false;
                }),
                active: _disliked,
              ),
              if (widget.onRegenerate != null)
                _action(_icRetry, '重新生成', widget.onRegenerate!),
              _action(
                _icShare,
                '分享',
                () => unawaited(
                  Share.share(msg.report.markdown, subject: msg.report.title),
                ),
              ),
              _action(
                _icMore,
                '更多',
                () => showIosMenu(context, [
                  IosMenuItem(
                    label: '复制报告',
                    icon: Icons.copy_outlined,
                    onTap: () {
                      Clipboard.setData(
                        ClipboardData(text: msg.report.markdown),
                      );
                      showAppToast(context, '已复制报告');
                    },
                  ),
                  IosMenuItem(
                    label: '分享报告',
                    icon: Icons.ios_share_outlined,
                    onTap: () => unawaited(
                      Share.share(
                        msg.report.markdown,
                        subject: msg.report.title,
                      ),
                    ),
                  ),
                ]),
              ),
            ],
          ),
          if (widget.showMascot) ...[
            const SizedBox(height: 2),
            const Mascot(mood: MascotMood.report, size: 52, animate: true),
          ],
        ],
      ),
    );
  }
}

/// Production message typography fixture used by screenshot tests. Keeping
/// this on the real bubble widgets catches regressions that an input-only
/// screenshot would miss.
@visibleForTesting
Widget buildAiChatMessageTypographyForTesting({
  String userText = '午饭花了 20 元',
  String answerText = '今天支出 **¥20.00**，记在餐饮。',
  String infoText = '已保存这笔记录',
}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      KeyedSubtree(
        key: const ValueKey('ai-chat-message-typography-user'),
        child: _UserBubble(text: userText),
      ),
      KeyedSubtree(
        key: const ValueKey('ai-chat-message-typography-answer'),
        child: _AnswerBubble(
          text: answerText,
          animate: false,
          streaming: false,
        ),
      ),
      KeyedSubtree(
        key: const ValueKey('ai-chat-message-typography-info'),
        child: _InfoBubble(text: infoText),
      ),
    ],
  );
}

/// Production fixtures for the two-stage GPT-style user-message interaction.
/// Tests use the real bubble and action overlay, so regressions cannot hide in
/// a separate mock implementation.
@visibleForTesting
Widget buildAiChatUserTextSelectionForTesting({
  String text = '点击启动计费就这样了',
  VoidCallback? onSelectionDismissed,
}) =>
    _UserBubble(
      text: text,
      selected: true,
      textSelectionMode: true,
      onSelectionDismissed: onSelectionDismissed,
    );

@visibleForTesting
Widget buildAiChatUserMessageForTesting({
  String text = '',
  List<ChatAttachment> attachments = const [],
}) =>
    _UserBubble(
      text: text,
      attachments: attachments,
      fullBleedAttachments: true,
    );

@visibleForTesting
Widget buildAiChatThinkingForTesting({
  bool completed = false,
  bool expanded = false,
  Duration elapsed = const Duration(seconds: 4),
  String summary = '核对了公开数据并整理出关键变化。',
  int sourceCount = 0,
}) {
  final started = DateTime.now().subtract(elapsed);
  final step = _ThinkingStep(
    kind: _ThinkingKind.queryAnswer,
    startedAt: started,
    completedAt: completed ? started.add(elapsed) : null,
    detail: summary,
  );
  final message = _ThinkingMsg(
    _ThinkingKind.queryAnswer,
    startedAt: started,
    steps: [step],
  )..expanded = expanded;
  if (completed) message.completedAt = started.add(elapsed);
  for (var i = 0; i < sourceCount; i++) {
    message.sources.add(
      AiWebSource(
        title: '公开来源 ${i + 1}',
        url: 'https://example$i.com/article',
      ),
    );
  }
  return _ThinkingBubble(msg: message);
}

@visibleForTesting
Widget buildAiChatMessageActionOverlayForTesting({
  required Rect anchor,
  String timeLabel = '今天 23:39',
}) =>
    _MessageActionOverlay(
      anchor: anchor,
      timeLabel: timeLabel,
      onCopy: () {},
      onEdit: () {},
      onSelectText: () {},
    );

@visibleForTesting
TextStyle aiChatMessageBodyStyleForTesting(ColorScheme scheme) =>
    _chatBodyStyle(scheme);

@visibleForTesting
Widget buildAiChatAnswerForTesting({
  String text =
      '| 指数 | 收盘 | 涨跌 |\n| --- | ---: | :---: |\n| 纳斯达克 | 25,980.19 | -0.76% |',
  List<AiWebSource> sources = const [],
}) {
  return _AnswerBubble(
    text: text,
    sources: sources,
    animate: false,
    streaming: false,
    showMascot: false,
  );
}

// ── 喵助手打开时主动说的一句洞察 ──────────────────────────────────────────────
class _GreetingLine extends StatelessWidget {
  const _GreetingLine({super.key});

  @override
  Widget build(BuildContext context) {
    final g = MeowInsights.greeting(context.read<AppRepository>());
    if (g == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Text(
      g,
      style: TextStyle(
        fontSize: 16,
        height: 1.45,
        fontWeight: FontWeight.w400,
        fontFamilyFallback: _cjkFontFallback,
        color: scheme.onSurface,
      ),
    );
  }
}

// ── 记账卡 ───────────────────────────────────────────────────────────────────
// 未保存 = 确认卡（看看对不对 + 记下按钮）；
// 已保存 = 每笔一张「记账明细卡」（对齐咔皮：图标+名称、灰字时间+账本、
// 右侧金额、底部 改分类/删除 芯片），替掉旧的「喵 + 已记一笔」。
class _RefundBubble extends StatelessWidget {
  final _RefundMsg msg;

  const _RefundBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remaining = msg.originalAmount - msg.refundedAfter;
    final safeRemaining = remaining > Decimal.zero ? remaining : Decimal.zero;
    final displayMode =
        context.select<AppRepository, TransactionCardDisplayMode>(
            (repo) => repo.transactionCardDisplayMode);
    final cardText = resolveTransactionCardText(
      mode: displayMode,
      kind: TransactionKind.expense,
      note: msg.title,
      categoryName: msg.categoryName,
    );
    final detailText = joinTransactionCardDetails([
      transactionCardTimeLabel(
        msg.date,
        dateGrouped: false,
        precision: msg.timePrecision,
      ),
      msg.bookName,
      cardText.secondary,
    ]);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, right: 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.card(scheme),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.hairline(scheme)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    Icons.keyboard_return_rounded,
                    size: 18,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cardText.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detailText,
                        style: AppType.caption(scheme),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '+${MoneyFormat.string(msg.amount)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Nunito',
                      ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Divider(height: 1, color: AppColors.hairline(scheme)),
            const SizedBox(height: 8),
            Text(
              '已附着到原订单 · 累计已退 ${MoneyFormat.string(msg.refundedAfter)} · '
              '剩余 ${MoneyFormat.string(safeRemaining)}',
              style: AppType.caption(scheme),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordBubble extends StatelessWidget {
  final _RecordMsg msg;
  final String bookName;
  final VoidCallback? onSave;
  final VoidCallback? onUndo;
  final void Function(int index) onChangeCategory;
  final void Function(int index) onDeleteEntry;

  const _RecordBubble({
    required this.msg,
    required this.bookName,
    required this.onSave,
    required this.onUndo,
    required this.onChangeCategory,
    required this.onDeleteEntry,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = msg.entries.length;

    if (!msg.saved) {
      // ── 确认卡 ──
      return Padding(
        padding: const EdgeInsets.only(bottom: 10, right: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              n > 1 ? '帮你拆成 $n 笔，看看对不对：' : '看看对不对：',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.card(scheme),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.hairline(scheme)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  for (int i = 0; i < msg.entries.length; i++)
                    _EntryRow(
                      entry: msg.entries[i],
                      cat: msg.cats[i],
                      showDivider: i > 0,
                      onChangeCategory: () => onChangeCategory(i),
                    ),
                  const SizedBox(height: 10),
                  AppPillButton(
                    width: double.infinity,
                    height: 44,
                    loading: msg.saving,
                    onPressed: msg.saving ? null : onSave,
                    label: n > 1 ? '记下这 $n 笔' : '记下',
                    fillColor: scheme.onSurface,
                    foregroundColor: scheme.surface,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ── 已保存：每笔一张明细卡 ──
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, right: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < msg.entries.length; i++)
            _SavedEntryCard(
              entry: msg.entries[i],
              cat: msg.cats[i],
              bookName: bookName,
              deleted: msg.deletedIdx.contains(i),
              canAct: i < msg.txnIds.length && msg.txnIds[i] != null,
              onChangeCategory: () => onChangeCategory(i),
              onDelete: () => onDeleteEntry(i),
            ),
          if (msg.aiRunId != null && msg.aiRunId!.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: _ActionChip(
                icon: CupertinoIcons.arrow_uturn_left,
                label: msg.rolledBack ? '本次已撤销' : '撤销本次 AI 记账',
                onTap: onUndo ?? () {},
              ),
            ),
          if (msg.savedFeedback.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                msg.savedFeedback,
                style: AppType.caption(scheme),
              ),
            ),
        ],
      ),
    );
  }
}

/// 已入库单笔的「记账明细卡」：左上分类图标+名称，灰字日期+账本，
/// 右侧金额，底部 改分类 / 删除 芯片。删除后整卡淡化。
class _SavedEntryCard extends StatelessWidget {
  final ParsedEntry entry;
  final CategoryEntity? cat;
  final String bookName;
  final bool deleted;
  final bool canAct;
  final VoidCallback onChangeCategory;
  final VoidCallback onDelete;

  const _SavedEntryCard({
    required this.entry,
    required this.cat,
    required this.bookName,
    required this.deleted,
    required this.canAct,
    required this.onChangeCategory,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isIncome = entry.kind == TransactionKind.income;
    final catName = cat?.nameZh ?? (isIncome ? '其他收入' : '其他支出');
    final displayMode =
        context.select<AppRepository, TransactionCardDisplayMode>(
            (repo) => repo.transactionCardDisplayMode);
    final cardText = resolveTransactionCardText(
      mode: displayMode,
      kind: entry.kind,
      note: entry.note,
      categoryName: catName,
    );
    final detailText = joinTransactionCardDetails([
      transactionCardTimeLabel(
        entry.date,
        dateGrouped: false,
        precision: entry.timePrecision,
      ),
      bookName,
      cardText.secondary,
    ]);
    final amountText = entry.amount != null
        ? '${isIncome ? '+' : '-'}${MoneyFormat.string(entry.amount!)}'
        : '—';

    return Opacity(
      opacity: deleted ? 0.45 : 1,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.card(scheme),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.hairline(scheme)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CatIcon(
                  categoryKey: cat?.key ?? '',
                  emoji: cat != null ? CategorySeed.emojiOf(cat!.key) : '🏷️',
                  size: 30,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cardText.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w400,
                              color: scheme.onSurface,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detailText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTextColor.secondary(scheme),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  amountText,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Nunito',
                    decoration: deleted ? TextDecoration.lineThrough : null,
                    color:
                        isIncome ? AppColors.income(scheme) : scheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (deleted)
              Text(
                '已删除',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTextColor.secondary(scheme),
                ),
              )
            else if (canAct)
              Row(
                children: [
                  _ActionChip(
                    icon: CupertinoIcons.tag,
                    label: '改分类',
                    onTap: onChangeCategory,
                  ),
                  const Spacer(),
                  // 删除挪到卡片右下角，只留图标（不要「删除」二字）。
                  PressableScale(
                    onPressed: onDelete,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        CupertinoIcons.delete,
                        size: 18,
                        color: AppTextColor.secondary(scheme),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// 明细卡底部小芯片（白底发丝边，与全 App 芯片同款语言）。
class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final actionColor = AppTextColor.secondary(scheme);
    return PressableScale(
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.card(scheme),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.hairline(scheme)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: actionColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: actionColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final ParsedEntry entry;
  final CategoryEntity? cat;
  final bool showDivider;
  final VoidCallback onChangeCategory;

  const _EntryRow({
    required this.entry,
    required this.cat,
    required this.showDivider,
    required this.onChangeCategory,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isIncome = entry.kind == TransactionKind.income;
    final catName = cat?.nameZh ?? (isIncome ? '其他收入' : '其他支出');
    final displayMode =
        context.select<AppRepository, TransactionCardDisplayMode>(
            (repo) => repo.transactionCardDisplayMode);
    final cardText = resolveTransactionCardText(
      mode: displayMode,
      kind: entry.kind,
      note: entry.note,
      categoryName: catName,
    );
    final detailText = joinTransactionCardDetails([
      transactionCardTimeLabel(
        entry.date,
        dateGrouped: false,
        precision: entry.timePrecision,
      ),
      cardText.secondary,
    ]);
    final amountText = entry.amount != null
        ? '${isIncome ? '+' : '-'}${MoneyFormat.string(entry.amount!)}'
        : '未识别金额';

    return Column(
      children: [
        if (showDivider)
          Divider(
            height: 16,
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cardText.title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w400,
                          color: scheme.onSurface,
                        ),
                  ),
                  if (detailText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        detailText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              amountText,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'Nunito',
                color: entry.amount == null
                    ? AppColors.warning // 守不用红铁律：缺金额提醒用橙
                    : (isIncome ? scheme.secondary : scheme.onSurface),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _ActionChip(
              icon: CupertinoIcons.tag,
              label: '改分类',
              onTap: onChangeCategory,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 空态：猜你想问气泡
// ─────────────────────────────────────────────────────────────────────────────

/// 建议 2×2 网格：浮在模糊背景上，与底部输入框同款玻璃透明底胶囊。
class _SuggestionGrid extends StatelessWidget {
  final List<String> items;
  final ValueChanged<String> onTap;

  const _SuggestionGrid({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in items)
          PressableScale(
            onPressed: () => onTap(s),
            child: GlassSurface(
              radius: 16,
              blur: 4,
              opacity: 0.86,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              child: Text(
                s,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 小组件：胶囊 + 圆形按钮
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderActionCluster extends StatelessWidget {
  final VoidCallback onReports;
  final ValueChanged<BuildContext> onMenu;

  const _HeaderActionCluster({required this.onReports, required this.onMenu});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 82,
      height: 38,
      child: GlassSurface(
        radius: 19,
        blur: 0,
        child: Row(
          children: [
            Expanded(
              child: PressableScale(
                onPressed: onReports,
                child: Center(
                  child: Icon(
                    CupertinoIcons.doc_text,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            Container(width: 1, height: 18, color: AppColors.hairline(scheme)),
            Expanded(
              child: Builder(
                builder: (btnCtx) => PressableScale(
                  onPressed: () => onMenu(btnCtx),
                  child: Center(
                    child: Icon(
                      Icons.more_horiz,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 主页嵌入式 AI 面板底栏：「AI 记账」胶囊，点击切回手动模式。
/// 只在 !fullScreen 时使用，fullScreen（喵助手）用 _ModelPill。
class _AiModeSwitchPill extends StatelessWidget {
  final VoidCallback onTap;
  const _AiModeSwitchPill({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onPressed: onTap,
      child: GlassSurface(
        radius: 15,
        blur: 0,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        child: SizedBox(
          height: 31,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome,
                  size: 13, color: scheme.onSurfaceVariant),
              const SizedBox(width: 5),
              Text(
                'AI 记账',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w300,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 模型切换胶囊：对齐 Claude 桌面端底栏的浅灰值标签。
class _ModelPill extends StatelessWidget {
  final String model;
  final bool selected;
  final VoidCallback onTap;

  const _ModelPill({
    required this.model,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currentModel = model.trim();
    final label = currentModel.isEmpty ? '选择模型' : currentModel;
    final textStyle = TextStyle(
      fontSize: _aiChatSelectorFontSize,
      height: 1.2,
      fontWeight: FontWeight.w400,
      fontFamilyFallback: _cjkFontFallback,
      color: scheme.onSurfaceVariant,
    );

    final content = Container(
      key: const ValueKey('ai-chat-model-pill'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: selected
          ? BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.075),
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      // A long gateway model must stay readable rather than being clipped
      // under the effort label. The scaler only changes size when the
      // available width is genuinely insufficient.
      child: _ScaledSingleLineText(
        key: const ValueKey('ai-chat-model-label'),
        text: label,
        style: textStyle,
      ),
    );

    return PressableScale(
      onPressed: onTap,
      child: content,
    );
  }
}

class _ScaledSingleLineText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const _ScaledSingleLineText({
    super.key,
    required this.text,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    // TextPainter does not automatically receive the ambient DefaultTextStyle
    // used by the Text widget below. Merge it explicitly so font fallbacks
    // (especially CJK glyphs in screenshot/desktop renderers) are respected
    // during both measurement and painting.
    final resolvedStyle = DefaultTextStyle.of(context).style.merge(style);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: resolvedStyle),
          textDirection: Directionality.of(context),
          maxLines: 1,
        )..layout();
        final available = constraints.maxWidth;
        // Flex may ask for an intrinsic pass with a zero/tiny max width. Do
        // not let that probe permanently collapse the label's natural size.
        final minimumUsefulWidth = style.fontSize ?? 14;
        if (!available.isFinite ||
            available <= minimumUsefulWidth ||
            painter.width <= available) {
          return Text(
            text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: resolvedStyle,
          );
        }
        final scale = available <= 0 ? 0.0 : available / painter.width;
        return SizedBox(
          width: available,
          height: painter.height,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Transform.scale(
              alignment: Alignment.centerLeft,
              scale: scale,
              child: SizedBox(
                width: painter.width,
                height: painter.height,
                child: Text(
                  text,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: resolvedStyle,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Effort 胶囊：对齐 Claude 桌面端底栏的当前值标签。
class _EffortLabel extends StatelessWidget {
  final AiReasoningEffort effort;
  final bool selected;
  final VoidCallback onTap;

  const _EffortLabel({
    required this.effort,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = effort == AiReasoningEffort.ultra
        ? 'Ultracode'
        : (effort == AiReasoningEffort.none ||
                effort == AiReasoningEffort.minimal
            ? 'Low'
            : effort.label);

    return PressableScale(
      onPressed: onTap,
      child: Container(
        key: const ValueKey('ai-chat-effort-pill'),
        padding: const EdgeInsets.symmetric(vertical: 2),
        decoration: selected
            ? BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.075),
                borderRadius: BorderRadius.circular(4),
              )
            : null,
        child: Text(
          label,
          style: TextStyle(
            fontSize: _aiChatSelectorFontSize,
            height: 1.2,
            fontWeight: FontWeight.w400,
            fontFamilyFallback: _cjkFontFallback,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Exposes the live bottom selection controls to focused visual tests without
/// booting chat history or the keyboard lifecycle.
@visibleForTesting
Widget buildClaudeInputPillsForTesting({
  required bool modelSelected,
  required bool effortSelected,
  String model = 'claude-sonnet-5',
  double? maxWidth,
}) {
  return SizedBox(
    width: maxWidth,
    child: Row(
      mainAxisSize: maxWidth == null ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (maxWidth == null)
          _ModelPill(
            model: model,
            selected: modelSelected,
            onTap: () {},
          )
        else
          Flexible(
            fit: FlexFit.loose,
            child: _ModelPill(
              model: model,
              selected: modelSelected,
              onTap: () {},
            ),
          ),
        const SizedBox(width: _aiChatSelectionGap),
        _EffortLabel(
          effort: AiReasoningEffort.max,
          selected: effortSelected,
          onTap: () {},
        ),
      ],
    ),
  );
}

/// 模型列表气泡卡：Claude 桌面端同款的紧凑白卡、右对齐编号和选中勾。
class _ModelMenuCard extends StatelessWidget {
  final List<AiModelOption> options;
  final String currentKey;
  final ValueChanged<AiModelOption> onSelected;

  const _ModelMenuCard({
    required this.options,
    required this.currentKey,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: _ClaudePopupSurface(
        captureKey: const ValueKey('ai-chat-model-popup'),
        width: 195,
        radius: 11,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 9, 11, 3),
              child: Text(
                'Models',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.15,
                  fontWeight: FontWeight.w400,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 5),
                physics: const BouncingScrollPhysics(),
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options[index];
                  return _ModelMenuRow(
                    option: option,
                    index: index + 1,
                    selected: option.key == currentKey,
                    onTap: () {
                      Navigator.of(context).pop();
                      onSelected(option);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Exposes the production Claude-style popup cards to focused visual tests.
/// The builders intentionally return the same private widgets used by the
/// live panel, so screenshot coverage does not need to boot the full chat
/// history, suggestion timers, or keyboard lifecycle.
@visibleForTesting
Widget buildClaudeModelPopupForTesting({
  required List<AiModelOption> options,
  required String currentKey,
  required ValueChanged<AiModelOption> onSelected,
}) =>
    _ModelMenuCard(
      options: options,
      currentKey: currentKey,
      onSelected: onSelected,
    );

class _ModelMenuRow extends StatefulWidget {
  final AiModelOption option;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  const _ModelMenuRow({
    required this.option,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_ModelMenuRow> createState() => _ModelMenuRowState();
}

class _ModelMenuRowState extends State<_ModelMenuRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highlighted = widget.selected || _hovered || _focused;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Focus(
          onFocusChange: (value) => setState(() => _focused = value),
          child: Material(
            color: highlighted
                ? scheme.onSurface.withValues(
                    alpha: widget.selected ? 0.065 : 0.04,
                  )
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(8),
              splashFactory: NoSplash.splashFactory,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              highlightColor: scheme.onSurface.withValues(alpha: 0.04),
              child: SizedBox(
                height: 24,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.option.model,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.1,
                            fontWeight: FontWeight.w400,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      if (widget.selected)
                        SizedBox(
                          width: 17,
                          child: Icon(
                            CupertinoIcons.checkmark,
                            size: 13,
                            color: scheme.primary,
                          ),
                        )
                      else
                        const SizedBox(width: 17),
                      SizedBox(
                        width: 12,
                        child: Text(
                          '${widget.index}',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.1,
                            color:
                                scheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Claude 式浮层底板：细边、白底和低扩散阴影。
class _ClaudePopupSurface extends StatelessWidget {
  final Key? captureKey;
  final double width;
  final double radius;
  final Widget child;

  const _ClaudePopupSurface({
    this.captureKey,
    required this.width,
    required this.radius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      key: captureKey,
      child: SizedBox(
        width: width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: const [
              BoxShadow(
                color: Color(0x29000000),
                blurRadius: 20,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.58),
                    width: 0.7,
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Effort 气泡卡：Claude 桌面端同款紧凑面板。
/// 保留全部内部档位，视觉标签只改变展示名，不改变实际请求参数。
class _EffortPopupCard extends StatefulWidget {
  final AiReasoningEffort currentEffort;
  final ValueChanged<AiReasoningEffort> onChanged;

  const _EffortPopupCard({
    required this.currentEffort,
    required this.onChanged,
  });

  @override
  State<_EffortPopupCard> createState() => _EffortPopupCardState();
}

class _EffortPopupCardState extends State<_EffortPopupCard>
    with TickerProviderStateMixin {
  // 喵助手从 Low 起步；旧数据库中的 none/minimal 会在仓储层归一到 Low。
  static const _levels = [
    (AiReasoningEffort.low, 'Low'),
    (AiReasoningEffort.medium, 'Medium'),
    (AiReasoningEffort.high, 'High'),
    (AiReasoningEffort.xhigh, 'Extra'),
    (AiReasoningEffort.max, 'Max'),
    (AiReasoningEffort.ultra, 'Ultracode'),
  ];

  late int _index;
  late AnimationController _ultraCtrl;

  @override
  void initState() {
    super.initState();
    _index = _levels.indexWhere((e) => e.$1 == widget.currentEffort);
    if (_index < 0) _index = 0; // 默认 Low
    _ultraCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (_isUltra) _ultraCtrl.repeat();
  }

  @override
  void dispose() {
    _ultraCtrl.dispose();
    super.dispose();
  }

  bool get _isUltra => _levels[_index].$1 == AiReasoningEffort.ultra;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currentLabel = _levels[_index].$2;
    final isUltra = _isUltra;

    return Material(
      type: MaterialType.transparency,
      child: _ClaudePopupSurface(
        captureKey: const ValueKey('ai-chat-effort-popup'),
        width: 222,
        radius: 11,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 13),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Effort',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.15,
                      fontWeight: FontWeight.w400,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    fit: FlexFit.loose,
                    child: isUltra
                        ? AnimatedBuilder(
                            animation: _ultraCtrl,
                            builder: (_, __) => ShaderMask(
                              shaderCallback: (bounds) => LinearGradient(
                                begin: Alignment(
                                  -1.0 + _ultraCtrl.value * 2,
                                  0,
                                ),
                                end: Alignment(
                                  1.0 + _ultraCtrl.value * 2,
                                  0,
                                ),
                                colors: const [
                                  Color(0xFF6152B8),
                                  Color(0xFF9C86E8),
                                  Color(0xFF5C4AA8),
                                  Color(0xFF6152B8),
                                ],
                              ).createShader(bounds),
                              child: Text(
                                currentLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.15,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          )
                        : Text(
                            currentLabel,
                            key: const ValueKey('ai-chat-effort-value'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.15,
                              fontWeight: FontWeight.w500,
                              color: scheme.onSurfaceVariant.withValues(
                                alpha: 0.78,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Faster',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.1,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                      ),
                    ),
                    Text(
                      'Smarter',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.1,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.48),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                key: const ValueKey('ai-chat-effort-slider'),
                height: 24,
                child: _EffortSlider(
                  index: _index,
                  count: _levels.length,
                  isUltra: isUltra,
                  ultraAnimation: _ultraCtrl,
                  onChanged: (i) {
                    final wasUltra = _isUltra;
                    setState(() => _index = i);
                    final nowUltra = _isUltra;
                    if (nowUltra && !wasUltra) {
                      _ultraCtrl.repeat();
                    } else if (!nowUltra && wasUltra) {
                      _ultraCtrl.stop();
                    }
                    widget.onChanged(_levels[i].$1);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
Widget buildClaudeEffortPopupForTesting({
  required AiReasoningEffort currentEffort,
  required ValueChanged<AiReasoningEffort> onChanged,
}) =>
    _EffortPopupCard(
      currentEffort: currentEffort,
      onChanged: onChanged,
    );

/// 自定义 Effort 滑条：圆角方形 thumb，深浅灰轨道，刻度点，Ultra 紫色动画
class _EffortSlider extends StatefulWidget {
  final int index;
  final int count;
  final bool isUltra;
  final Animation<double> ultraAnimation;
  final ValueChanged<int> onChanged;

  const _EffortSlider({
    required this.index,
    required this.count,
    required this.isUltra,
    required this.ultraAnimation,
    required this.onChanged,
  });

  @override
  State<_EffortSlider> createState() => _EffortSliderState();
}

class _EffortSliderState extends State<_EffortSlider> {
  late int _drag;

  @override
  void initState() {
    super.initState();
    _drag = widget.index;
  }

  @override
  void didUpdateWidget(_EffortSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) _drag = widget.index;
  }

  void _handleTapOrDrag(Offset local, double width) {
    const edgePad = 9.0;
    final usable = max(1.0, width - edgePad * 2);
    final step = usable / (widget.count - 1);
    final i = ((local.dx - edgePad) / step).round().clamp(0, widget.count - 1);
    if (i != _drag) {
      setState(() => _drag = i);
      widget.onChanged(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (d) =>
          _handleTapOrDrag(d.localPosition, context.size?.width ?? 200),
      onHorizontalDragUpdate: (d) =>
          _handleTapOrDrag(d.localPosition, context.size?.width ?? 200),
      child: AnimatedBuilder(
        animation: widget.ultraAnimation,
        builder: (_, __) => CustomPaint(
          painter: _EffortTrackPainter(
            index: _drag,
            count: widget.count,
            isUltra: widget.isUltra,
            ultraT: widget.ultraAnimation.value,
            scheme: Theme.of(context).colorScheme,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _EffortTrackPainter extends CustomPainter {
  final int index;
  final int count;
  final bool isUltra;
  final double ultraT;
  final ColorScheme scheme;

  const _EffortTrackPainter({
    required this.index,
    required this.count,
    required this.isUltra,
    required this.ultraT,
    required this.scheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const trackH = 22.0;
    const thumbW = 18.0;
    const thumbH = 18.0;
    const thumbR = 5.0;
    const edgePad = 9.0;
    final cy = size.height / 2;
    final usable = max(1.0, size.width - edgePad * 2);
    final step = usable / (count - 1);
    final thumbX = edgePad + index * step;

    // Claude 的滑条是完整的圆角灰色底轨，活动段只覆盖到滑块。
    final trackPaint = Paint()
      ..color = scheme.onSurface.withValues(alpha: 0.16)
      ..strokeCap = StrokeCap.round;
    final trackRect = Rect.fromLTWH(0, cy - trackH / 2, size.width, trackH);
    final trackRRect = RRect.fromRectAndRadius(
      trackRect,
      const Radius.circular(5),
    );
    canvas.drawRRect(trackRRect, trackPaint);

    // 已滑过部分（普通档位为柔和深灰，Ultracode 为像素化紫色高光）。
    if (thumbX > 0) {
      if (isUltra) {
        final activeRect = Rect.fromLTWH(0, cy - trackH / 2, thumbX, trackH);
        final activeRRect = RRect.fromRectAndRadius(
          activeRect,
          const Radius.circular(5),
        );
        canvas.save();
        canvas.clipRRect(activeRRect);
        final gradient = LinearGradient(
          begin: Alignment(-1 + ultraT * 1.4, 0),
          end: Alignment(1 + ultraT * 1.4, 0),
          colors: const [
            Color(0xFFC7B9EE),
            Color(0xFFE1DAF8),
            Color(0xFFA99AE0),
            Color(0xFFD2C8F3),
          ],
        );
        canvas.drawRect(
          activeRect,
          Paint()..shader = gradient.createShader(activeRect),
        );
        // 参考 Claude Ultracode 的颗粒高光，而不是平滑紫色渐变。
        const cell = 4.0;
        final cols = (activeRect.width / cell).ceil();
        final rows = (activeRect.height / cell).ceil();
        for (var row = 0; row < rows; row++) {
          for (var col = 0; col < cols; col++) {
            final phase = (col * 17 + row * 31) % 9;
            final shimmer = sin((col * 0.55) + ultraT * pi * 2 + row * 0.3);
            if ((phase + row) % 3 == 0 || shimmer > 0.82) {
              final alpha = (0.08 + (shimmer + 1) * 0.06).clamp(0.04, 0.2);
              canvas.drawRect(
                Rect.fromLTWH(col * cell, cy - trackH / 2 + row * cell,
                    cell - 0.5, cell - 0.5),
                Paint()..color = Colors.white.withValues(alpha: alpha),
              );
            }
          }
        }
        canvas.restore();
      } else {
        final activePaint = Paint()
          ..color = scheme.onSurface.withValues(alpha: 0.22)
          ..strokeCap = StrokeCap.round;
        final activeRect = Rect.fromLTWH(0, cy - trackH / 2, thumbX, trackH);
        canvas.drawRRect(
            RRect.fromRectAndRadius(activeRect, const Radius.circular(5)),
            activePaint);
      }
    }

    // 刻度点（参考截图的细小灰点）。
    final dotPaint = Paint()..color = scheme.onSurface.withValues(alpha: 0.30);
    for (var i = 0; i < count; i++) {
      final x = edgePad + i * step;
      if ((x - thumbX).abs() > thumbW / 2 + 3) {
        canvas.drawCircle(Offset(x, cy), 1.7, dotPaint);
      }
    }

    // 方形圆角 thumb
    final thumbRect = Rect.fromCenter(
        center: Offset(thumbX, cy), width: thumbW, height: thumbH);
    if (isUltra) {
      const gradient = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF9B59B6), Color(0xFF7E57C2)],
      );
      final thumbPaint = Paint()..shader = gradient.createShader(thumbRect);
      canvas.drawRRect(
          RRect.fromRectAndRadius(thumbRect, const Radius.circular(thumbR)),
          thumbPaint);
    } else {
      final thumbPaint = Paint()
        ..color = scheme.surface
        ..style = PaintingStyle.fill;
      final thumbShadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              thumbRect.inflate(1), const Radius.circular(thumbR + 1)),
          thumbShadowPaint);
      canvas.drawRRect(
          RRect.fromRectAndRadius(thumbRect, const Radius.circular(thumbR)),
          thumbPaint);
      // thumb 内部阴影线
      final innerPaint = Paint()
        ..color = scheme.onSurface.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              thumbRect.deflate(0.5), const Radius.circular(thumbR - 0.5)),
          innerPaint);
    }
  }

  @override
  bool shouldRepaint(_EffortTrackPainter old) =>
      old.index != index ||
      old.isUltra != isUltra ||
      old.ultraT != ultraT ||
      old.scheme != scheme;
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool plain;

  const _CircleBtn({
    super.key,
    required this.icon,
    required this.onTap,
    this.plain = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (plain) {
      return PressableScale(
        onPressed: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: icon == Icons.add
                ? SizedBox(
                    width: 26.4,
                    height: 26.4,
                    child: CustomPaint(
                      key: const ValueKey('ai-chat-plus-glyph'),
                      painter: _RoundedPlusPainter(
                        color: onTap == null
                            ? scheme.onSurfaceVariant.withValues(alpha: 0.38)
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : Icon(
                    icon,
                    size: 18,
                    color: onTap == null
                        ? scheme.onSurfaceVariant.withValues(alpha: 0.38)
                        : scheme.onSurfaceVariant,
                  ),
          ),
        ),
      );
    }

    // The send control keeps its glass circle; the assistant plus opts out
    // through [plain] while retaining the same touch extent.
    return AppGlassInputIconButton(
      icon: icon,
      onPressed: onTap,
      color: scheme.onSurfaceVariant,
    );
  }
}

/// GPT-style plus: a compact mark with a thin, rounded stroke and rounded
/// terminals. The 26.4px canvas and 15.4px visible line are 20% smaller than
/// the previous 33px Material glyph's roughly 19.2px visible mark; the
/// surrounding 36px box remains the touch target shared with the send button.
class _RoundedPlusPainter extends CustomPainter {
  final Color color;

  const _RoundedPlusPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round;
    final center = size.center(Offset.zero);
    const half = 7.7;
    canvas.drawLine(
      Offset(center.dx - half, center.dy),
      Offset(center.dx + half, center.dy),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - half),
      Offset(center.dx, center.dy + half),
      paint,
    );
  }

  @override
  bool shouldRepaint(_RoundedPlusPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 模型选择底部抽屉
class _ProviderModelPickerSheet extends StatefulWidget {
  final List<AiModelOption> options;
  final String? currentProviderId;
  final String currentModel;
  final AiReasoningEffort currentEffort;
  final Future<void> Function(
    AiModelOption option,
    AiReasoningEffort effort,
  ) onSelected;

  const _ProviderModelPickerSheet({
    required this.options,
    required this.currentProviderId,
    required this.currentModel,
    required this.currentEffort,
    required this.onSelected,
  });

  @override
  State<_ProviderModelPickerSheet> createState() =>
      _ProviderModelPickerSheetState();
}

class _ProviderModelPickerSheetState extends State<_ProviderModelPickerSheet> {
  late AiModelOption _selected;
  late AiReasoningEffort _effort;

  @override
  void initState() {
    super.initState();
    _selected = widget.options.firstWhere(
      (option) =>
          option.providerId == widget.currentProviderId &&
          option.model == widget.currentModel,
      orElse: () => widget.options.first,
    );
    _effort = widget.currentEffort;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const levels = [
      (AiReasoningEffort.low, 'Low'),
      (AiReasoningEffort.medium, 'Medium'),
      (AiReasoningEffort.high, 'High'),
      (AiReasoningEffort.xhigh, 'Extra'),
      (AiReasoningEffort.max, 'Max'),
      (AiReasoningEffort.ultra, 'Ultra'),
    ];
    var effortIndex = levels.indexWhere((entry) => entry.$1 == _effort);
    if (effortIndex < 0) effortIndex = 0;
    final groups = <String, List<AiModelOption>>{};
    for (final option in widget.options) {
      groups.putIfAbsent(option.providerId, () => []).add(option);
    }
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      child: Column(
        children: [
          SheetHeader(
            title: 'Models',
            subtitle: '${widget.options.length} 个可用模型',
            onClose: () => Navigator.pop(context),
            actionLabel: '完成',
            onAction: () async {
              Navigator.pop(context);
              await widget.onSelected(_selected, _effort);
            },
          ),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 3),
              children: [
                for (final group in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: Text(
                      group.value.first.providerLabel,
                      style: AppType.caption(scheme),
                    ),
                  ),
                  for (var index = 0; index < group.value.length; index++)
                    _ProviderModelOptionRow(
                      option: group.value[index],
                      index: index + 1,
                      selected: group.value[index].key == _selected.key,
                      onTap: () async {
                        final option = group.value[index];
                        setState(() => _selected = option);
                        await widget.onSelected(option, _effort);
                      },
                    ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.hairline(scheme)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
            child: Row(
              children: [
                Text('Effort', style: AppType.rowTitle(scheme)),
                const Spacer(),
                Text(levels[effortIndex].$2, style: AppType.secondary(scheme)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Text('Faster', style: AppType.caption(scheme)),
                Expanded(
                  child: Slider(
                    value: effortIndex.toDouble(),
                    min: 0,
                    max: (levels.length - 1).toDouble(),
                    divisions: levels.length - 1,
                    onChanged: (value) => setState(
                      () => _effort = levels[value.round()].$1,
                    ),
                  ),
                ),
                Text('Smarter', style: AppType.caption(scheme)),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 6),
        ],
      ),
    );
  }
}

class _ProviderModelOptionRow extends StatelessWidget {
  final AiModelOption option;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  const _ProviderModelOptionRow({
    required this.option,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: selected
                  ? Icon(
                      CupertinoIcons.checkmark,
                      size: 16,
                      color: scheme.primary,
                    )
                  : null,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                option.model,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  color: scheme.onSurface,
                ),
              ),
            ),
            Text('$index', style: AppType.caption(scheme)),
          ],
        ),
      ),
    );
  }
}

class _LegacyModelPickerSheet extends StatefulWidget {
  final List<String> models;
  final String currentModel;
  final AiReasoningEffort currentEffort;
  final Future<void> Function(String model, AiReasoningEffort effort)
      onSelected;

  const _LegacyModelPickerSheet({
    required this.models,
    required this.currentModel,
    required this.currentEffort,
    required this.onSelected,
  });

  @override
  State<_LegacyModelPickerSheet> createState() =>
      _LegacyModelPickerSheetState();
}

class _LegacyModelPickerSheetState extends State<_LegacyModelPickerSheet> {
  late String _selectedModel;
  late AiReasoningEffort _selectedEffort;

  @override
  void initState() {
    super.initState();
    _selectedModel = widget.currentModel;
    _selectedEffort = widget.currentEffort;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Effort 档位映射：参考 Claude 桌面端
    const effortLevels = [
      (AiReasoningEffort.low, 'Low'),
      (AiReasoningEffort.medium, 'Medium'),
      (AiReasoningEffort.high, 'High'),
      (AiReasoningEffort.xhigh, 'Extra'),
      (AiReasoningEffort.max, 'Max'),
      (AiReasoningEffort.ultra, 'Ultra'),
    ];
    final effortIndex = effortLevels.indexWhere((e) => e.$1 == _selectedEffort);
    final clampedIndex = effortIndex < 0 ? 0 : effortIndex;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: '选择模型',
            onClose: () => Navigator.pop(context),
            actionLabel: '完成',
            onAction: () async {
              Navigator.pop(context);
              await widget.onSelected(_selectedModel, _selectedEffort);
            },
          ),
          Divider(height: 1, color: AppColors.hairline(scheme)),
          // 模型列表（紧凑行）
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: widget.models.length,
              itemBuilder: (context, i) {
                final model = widget.models[i];
                final selected = model == _selectedModel;
                return InkWell(
                  onTap: () => setState(() => _selectedModel = model),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        if (selected)
                          Icon(CupertinoIcons.checkmark,
                              size: 15, color: scheme.primary)
                        else
                          const SizedBox(width: 15),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            model,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight:
                                  selected ? FontWeight.w500 : FontWeight.w400,
                              color:
                                  selected ? scheme.primary : scheme.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 13,
                            color:
                                scheme.onSurfaceVariant.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Divider(height: 1, color: AppColors.hairline(scheme)),
          // Effort 行
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                Text(
                  '思考强度',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    effortLevels[clampedIndex].$2,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Row(
              children: [
                Text(
                  '快',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 8),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 16),
                    ),
                    child: Slider(
                      value: clampedIndex.toDouble(),
                      min: 0,
                      max: (effortLevels.length - 1).toDouble(),
                      divisions: effortLevels.length - 1,
                      onChanged: (value) {
                        final idx = value.round();
                        setState(() => _selectedEffort = effortLevels[idx].$1);
                      },
                    ),
                  ),
                ),
                Text(
                  '强',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}
