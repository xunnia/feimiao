import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:decimal/decimal.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, SystemChannels;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../core/ai/chat_intent.dart';
import '../../core/ai/ai_provider_config.dart';
import '../../core/ai/category_query.dart';
import '../../core/ai/llm_entry_parser.dart';
import '../../core/ai/llm_query.dart';
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
import '../../core/money_format.dart';
import '../../core/statistics/metric_contract.dart';
import '../../core/statistics/statistics_engine.dart';
import '../../core/transaction_time.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/glass.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/mascot.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/refund_settlement_sheet.dart';
import '../common/category_picker_sheet.dart';
import '../reports/report_views.dart';
import '../settings/ai_privacy_consent.dart';
import 'record_extras_sheet.dart';

const Duration kAiBackgroundResponseNoticeDelay = Duration(seconds: 15);
const double kAiResponseActionTouchExtent = 36;
const double kAiResponseActionIconExtent = 17.2;

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
    return '思考中…';
  }
  return canContinueInBackground ? '喵会在后台继续处理，完成后会显示在这里。' : '喵还在思考，完成后会显示在这里。';
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

/// 会话内存必须跟仓库实例绑定。测试、数据库恢复或未来切换用户时，不同
/// AppRepository 的行 id 都可能从 1 开始，不能共享恢复锁或去重集合。
final Map<AppRepository, _ChatMemoryState> _chatMemoryByRepository =
    Map<AppRepository, _ChatMemoryState>.identity();

_ChatMemoryState _chatMemoryFor(AppRepository repository) {
  final state = _chatMemoryByRepository.putIfAbsent(
    repository,
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

/// 清空内存中的会话历史（设置页「清空对话」时同步调用，避免本次运行还残留）。
void clearChatHistoryMemory(AppRepository repository) =>
    _chatMemoryFor(repository).reset(restored: true);

@visibleForTesting
void resetChatHistoryForTesting() {
  for (final state in _chatMemoryByRepository.values) {
    state.reset(restored: false);
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

  const AiChatPanel({
    super.key,
    required this.onSwitchToManual,
    this.initialText,
    this.fullScreen = false,
    this.fastSwitch = false,
    this.active = true,
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
  bool _busy = false;
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
  int? _observedReportJobId;
  bool _reportStatusSyncing = false;
  DateTime? _lastFocusRequestAt;
  DateTime? _inputFocusGuardUntil;
  double _lastKeyboardInset = 0;
  int _focusEpoch = 0;
  int _focusRepairAttempts = 0;
  bool _autoFocusPending = false;
  bool _inputSessionActive = false;
  bool _keyboardHadOpened = false;
  late bool _historyViewportReady;
  bool _historyRevealScheduled = false;
  late int _observedDatabaseGeneration;

  List<_Msg> get _chatHistory => _chatMemory.history;
  Set<int> get _chatRowIdsInMemory => _chatMemory.rowIdsInMemory;
  Map<String, int> get _pendingChatSignatures => _chatMemory.pendingSignatures;
  int get _chatHistoryEpoch => _chatMemory.epoch;
  bool get _chatRestored => _chatMemory.restored;
  set _chatRestored(bool value) => _chatMemory.restored = value;
  bool get _chatRestoreInProgress => _chatMemory.restoreInProgress;
  set _chatRestoreInProgress(bool value) =>
      _chatMemory.restoreInProgress = value;

  // 对话态聊天窗高度占比（半屏 0.58 / 全屏 0.94），及拖拽中标记。
  double _heightFrac = 0.58;
  bool _dragging = false;
  // 本次打开是否已经发过消息：未发=建议页；发过=半屏对话窗(可下拉看历史)。
  bool _started = false;

  static const List<String> _defaultSuggestions = [];
  static List<String>? _suggestionCache;
  static int _suggestionCacheContentFingerprint = -1;
  static int _suggestionCacheTimeKey = -1;

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
    final now = DateTime.now();
    return SmartSuggestionEngine.build(
      records: repo.allRecords,
      now: now,
      hasActiveBudget: _hasSuggestionBudget(repo),
    ).map((suggestion) => suggestion.text).toList(growable: false);
  }

  bool _hasSuggestionBudget(AppRepository repo) =>
      repo.currentBook != null && repo.monthlyBudget != null;

  @override
  void initState() {
    super.initState();
    _chatRepository = context.read<AppRepository>();
    _chatMemory = _chatMemoryFor(_chatRepository);
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
    _chatMemory.reset(
      restored: false,
      databaseGeneration: generation,
    );
    _observedReportJobId = null;
    _thinkingStatusTimer?.cancel();
    _thinkingStatusTimer = null;
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
      final rows = await repo.loadChatMessages();
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
          message = _UserMsg(text);
        } else if (role == 'answer') {
          message = _AnswerMsg(text, question: question, shown: true);
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
  }) async {
    final signature = _chatSignature(role, text, question);
    _pendingChatSignatures.update(signature, (count) => count + 1,
        ifAbsent: () => 1);
    try {
      final id = await repo.addChatMessage(
        role: role,
        text: text,
        question: question,
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

  Future<int> _addChatRecordMessage(
    AppRepository repo,
    String json,
  ) async {
    final signature = _chatSignature('record', json, '');
    _pendingChatSignatures.update(signature, (count) => count + 1,
        ifAbsent: () => 1);
    try {
      final id = await repo.addChatRecordMessage(json);
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
    final hasText = _ctrl.text.trim().isNotEmpty;
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
    final now = DateTime.now();
    final timeKey =
        (now.year * 10000 + now.month * 100 + now.day) * 100 + now.hour;
    final records = repo.allRecords;
    final hasActiveBudget = _hasSuggestionBudget(repo);
    final contentFingerprint = SmartSuggestionEngine.contentFingerprint(
      records: records,
      hasActiveBudget: hasActiveBudget,
    );
    final cached = _suggestionCache;
    if (cached != null &&
        _suggestionCacheContentFingerprint == contentFingerprint &&
        _suggestionCacheTimeKey == timeKey) {
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
      final latestRecords = latestRepo.allRecords;
      final latestHasActiveBudget = _hasSuggestionBudget(latestRepo);
      _suggestionCache = next;
      _suggestionCacheContentFingerprint =
          SmartSuggestionEngine.contentFingerprint(
        records: latestRecords,
        hasActiveBudget: latestHasActiveBudget,
      );
      _suggestionCacheTimeKey = latestTimeKey;
      if (mounted) setState(() => _picked = next);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chatRepository.removeListener(_onRepositoryChanged);
    ReportJobRuntime.revision.removeListener(_onReportJobRevision);
    _openSettleTimer?.cancel();
    _focusTimer?.cancel();
    _latestUserAnchorTimer?.cancel();
    _restoreTimer?.cancel();
    _suggestionTimer?.cancel();
    _thinkingStatusTimer?.cancel();
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

  Future<void> _syncReportJobState() async {
    if (!mounted || _reportStatusSyncing) return;
    _reportStatusSyncing = true;
    try {
      final repo = context.read<AppRepository>();
      final jobs = await repo.pendingReportJobs();
      if (!mounted) return;
      if (jobs.isNotEmpty) {
        final job = jobs.first;
        _observedReportJobId = job.id;
        final kind = switch (job.stage) {
          'generate' => _ThinkingKind.reportGenerate,
          'fallback' => _ThinkingKind.reportFallback,
          'save' => _ThinkingKind.reportSave,
          _ => _ThinkingKind.reportCollect,
        };
        final current = _currentThinkingMsg();
        if (current != null && current.kind != kind) {
          setState(() {
            current.kind = kind;
          });
        }
        return;
      }

      final observedId = _observedReportJobId;
      final observed =
          observedId == null ? null : await repo.reportJobById(observedId);
      if (observed?.status == 'completed' && observed?.reportId != null) {
        await repo.reloadReportsFromStorage();
        final report = await repo.getReport(observed!.reportId!);
        if (!mounted || report == null) return;
        setState(() {
          _msgs.removeWhere((message) => message is _ThinkingMsg);
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
          _busy = false;
        });
        _observedReportJobId = null;
        _scrollToLatestUserMessage();
        return;
      }
      if (observed?.status == 'failed') {
        if (!mounted) return;
        setState(() {
          _msgs.removeWhere((message) => message is _ThinkingMsg);
          _msgs.add(_InfoMsg('报告生成失败，请检查 AI 设置后重新生成', error: true));
          _busy = false;
        });
        _observedReportJobId = null;
      }
    } finally {
      _reportStatusSyncing = false;
    }
  }

  Future<void> _resumePendingReportJob() async {
    if (!mounted) return;
    final repo = context.read<AppRepository>();
    final jobs = await repo.pendingReportJobs();
    if (!mounted || jobs.isEmpty) return;
    // 未同意 AI 隐私说明：恢复的任务不上传账本内容，保持 pending 并提示，
    // 等用户在喵助手里重新发起（走同意弹窗）后再继续。
    if (!repo.aiPrivacyAccepted) {
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
    final job = jobs.first;
    _observedReportJobId = job.id;
    final kind = switch (job.stage) {
      'generate' => _ThinkingKind.reportGenerate,
      'fallback' => _ThinkingKind.reportFallback,
      'save' => _ThinkingKind.reportSave,
      _ => _ThinkingKind.reportCollect,
    };
    final currentThinking = _currentThinkingMsg();
    if (currentThinking == null) {
      setState(() {
        _started = true;
        _busy = true;
        _msgs.add(
          _ThinkingMsg(
            kind,
            startedAt: DateTime.fromMillisecondsSinceEpoch(job.createdMs),
          ),
        );
      });
      _restartThinkingTicker();
    } else if (currentThinking.kind != kind) {
      setState(() {
        currentThinking.kind = kind;
      });
    }
    final lease = (await repo.acquireReportGenerationLease()).bind(
      jobId: job.id,
      jobUuid: job.uuid,
    );
    final scheduled = await ReportTaskScheduler.schedule(
      repo,
      job,
      lease: lease,
    );
    if (scheduled) {
      _setThinkingCanContinueInBackground(true);
      return;
    }
    if (ReportJobRuntime.isActive(lease.runtimeKey)) return;
    unawaited(_runQuery(job.question, repository: repo, resumeJob: job));
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
    return max(140.0, viewportHeight - 104.0);
  }

  // 轻提示统一走全局 app_toast（同类功能同一种设计）。
  void _snack(String msg) =>
      showAppToast(context, msg, icon: Icons.info_outline);

  _ThinkingMsg? _currentThinkingMsg() {
    for (final msg in _msgs.reversed) {
      if (msg is _ThinkingMsg) return msg;
    }
    return null;
  }

  void _restartThinkingTicker() {
    _thinkingStatusTimer?.cancel();
    _thinkingStatusTimer = Timer.periodic(const Duration(seconds: 1), (
      _,
    ) {
      final msg = _currentThinkingMsg();
      if (!mounted || msg == null) {
        _thinkingStatusTimer?.cancel();
        _thinkingStatusTimer = null;
        return;
      }
      setState(() {});
      if (_observedReportJobId != null) {
        unawaited(_syncReportJobState());
      }
    });
  }

  void _setThinkingKind(_ThinkingKind kind) {
    final msg = _currentThinkingMsg();
    if (msg == null) return;
    if (!mounted) {
      msg.kind = kind;
      return;
    }
    setState(() {
      msg.kind = kind;
    });
    _restartThinkingTicker();
  }

  void _setThinkingCanContinueInBackground(bool value) {
    final msg = _currentThinkingMsg();
    if (msg == null || msg.canContinueInBackground == value) return;
    if (!mounted) {
      msg.canContinueInBackground = value;
      return;
    }
    setState(() => msg.canContinueInBackground = value);
  }

  // ── 发送：先判意图（查账 or 记账）再分流 ────────────────────────────────
  Future<void> _send([String? preset]) async {
    final text = (preset ?? _ctrl.text).trim();
    if (text.isEmpty || _busy) return;

    Haptics.light();
    final repo = context.read<AppRepository>();
    _ctrl.clear();
    _clearInputFocusIntent();
    _focus.unfocus();
    final userMsg = _UserMsg(text);
    setState(() {
      _started = true;
      _latestUserMsg = userMsg;
      _msgs.add(userMsg);
      _msgs.add(_ThinkingMsg(_ThinkingKind.intent));
      _busy = true;
    });
    _restartThinkingTicker();
    _scrollToLatestUserMessage();
    await _addChatMessage(repo, role: 'user', text: text);
    if (!mounted) return;

    // 历史订单退款不是一笔新收入。先用本地确定性规则匹配原支出，只有
    // 唯一强匹配且金额合法时才附着退款；所有不确定情况都停下来追问。
    final refund = _matchRefund(repo, text);
    if (refund.isRefundMutation) {
      await _applyRefund(refund, repo);
      return;
    }

    final aiConfig = repo.aiProviderConfigFor(AiTaskType.recordParse);
    // 有 key：让大模型在同一次调用里判「记账/查账」并解析（意图判断最准，
    // 不再靠脆弱的关键词，"坐公交花了一块"这类不会再被误当查账）。
    if (aiConfig.hasKey) {
      final consented = await ensureAiPrivacyConsent(context);
      if (!mounted) return;
      if (!consented && _looksLikeQuery(text)) {
        setState(() {
          _msgs.removeWhere((m) => m is _ThinkingMsg);
          _msgs.add(_InfoMsg('未同意 AI 隐私说明，喵不会把账本内容发出去。'));
          _busy = false;
        });
        _scrollToLatestUserMessage();
        return;
      }
      try {
        if (consented) {
          _setThinkingKind(_ThinkingKind.recordParse);
          final res = await LlmEntryParser.parseWithLLM(
            text: text,
            config: aiConfig,
            // 用户真实分类（含自建、去隐藏）+ 学习习惯，AI 往用户的分类里归、模仿其选择。
            expenseCats: repo.llmCategoryOptions(TransactionKind.expense),
            incomeCats: repo.llmCategoryOptions(TransactionKind.income),
            learnedHints: repo.llmLearnedHints,
          );
          if (res.intent == LlmIntent.query) {
            await _runQuery(text, repository: repo);
          } else {
            // repo 在 await 前已捕获传入：解析期间用户关掉面板也不能丢账。
            await _applyRecord(res.entries, repository: repo);
          }
          return;
        }
      } catch (_) {
        // 调用失败 → 落到下面的离线兜底
      }
    }
    // 无 key / 调用失败：关键词判意图（ChatIntent）+ 本地规则兜底。
    if (_looksLikeQuery(text)) {
      await _runQuery(text, repository: repo);
    } else {
      final hint = !aiConfig.hasKey
          ? '还没配 AI key，喵先用本地规则记（单笔）'
          : 'AI 没连上, 喵先用本地规则记了（单笔）';
      await _applyRecord(
        [NaturalLanguageEntryParser.parse(text)],
        hint: hint,
        repository: repo,
      );
    }
  }

  /// 意图判断：是「记账」还是「查账」。逻辑见 [ChatIntent]（纯逻辑，有单测）。
  /// 记账优先——"花了/吃/打车 + 金额(含口语一块)"都算记账，只有真在问数据才查账。
  bool _looksLikeQuery(String t) => ChatIntent.isQuery(
        t,
        hasArabicAmount: NaturalLanguageEntryParser.extractAmount(t) != null,
      );

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

  Future<void> _applyRefund(
    RefundMatchResult result,
    AppRepository repo,
  ) async {
    _setThinkingKind(_ThinkingKind.recordMatch);
    if (result.status != RefundMatchStatus.matched) {
      final prompt = _refundPrompt(result);
      if (mounted) {
        setState(() {
          _msgs.removeWhere((message) => message is _ThinkingMsg);
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
        setState(() {
          _msgs.removeWhere((message) => message is _ThinkingMsg);
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
      setState(() {
        _msgs.removeWhere((message) => message is _ThinkingMsg);
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
        setState(() {
          _msgs.removeWhere((message) => message is _ThinkingMsg);
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
    if (mounted) {
      setState(() {
        _msgs.removeWhere((item) => item is _ThinkingMsg);
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
  }) async {
    final repo = repository ?? context.read<AppRepository>();
    _setThinkingKind(_ThinkingKind.recordMatch);
    final cats = results.map((e) => _matchCat(repo, e)).toList();

    // 高置信(每笔>=0.9且金额有效) → 直接入库 + 撤销；否则弹确认卡
    final highConfidence = hint == null &&
        results.length <= 5 &&
        results.every(
          (e) =>
              e.amount != null &&
              e.amount! > Decimal.zero &&
              e.confidence >= 0.9,
        );
    _RecordMsg? autoMsg;
    String persistText = '';
    String persistRole = 'info';
    void applyMessages() {
      _msgs.removeWhere((m) => m is _ThinkingMsg);
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
        final msg = _RecordMsg(entries: results, cats: cats);
        _msgs.add(msg);
        if (highConfidence) autoMsg = msg;
        final n = results.where((e) => e.amount != null).length;
        persistText = hint != null ? '$hint · 已记 $n 笔' : '已记 $n 笔';
      }
      _busy = false;
    }

    if (mounted) {
      setState(applyMessages);
    } else {
      applyMessages();
    }
    if (persistText.isNotEmpty) {
      await _addChatMessage(repo, role: persistRole, text: persistText);
    }
    // 高置信：自动保存（卡片随即进入已存/可撤销态；unmounted 也照样入库）
    if (autoMsg != null) {
      await _save(autoMsg!, repository: repo);
      if (mounted) _snack('喵直接记好了，不对就点卡片上的撤销');
    }
    if (mounted) _scrollToLatestUserMessage();
  }

  // ── 查账流 ──────────────────────────────────────────────────────────────
  Future<void> _runQuery(
    String text, {
    AppRepository? repository,
    ReportJobEntity? resumeJob,
  }) async {
    final repo = repository ?? context.read<AppRepository>();
    var aiConfig = repo.aiProviderConfigFor(AiTaskType.chatQuery);
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
    if (reportType != null) {
      aiConfig = repo.aiProviderConfigFor(AiTaskType.report);
    }
    // 隐私闸门下沉到每个真正上传数据的入口：查账/报告都要先同意，不能只靠
    // _send 的记账分支拦。未同意就不发起请求；resume 的任务保持 pending
    // （启动恢复路径已在 _resumePendingReportJob 里提前拦掉，不会到这弹窗）。
    if (aiConfig.hasKey && !repo.aiPrivacyAccepted) {
      final consented = mounted && await ensureAiPrivacyConsent(context);
      if (!consented) {
        const prompt = '未同意 AI 隐私说明，喵不会把账本内容发出去。';
        void declineUi() {
          _msgs.removeWhere((m) => m is _ThinkingMsg);
          _msgs.add(_InfoMsg(prompt));
          _busy = false;
        }

        if (mounted) {
          setState(declineUi);
          _scrollToLatestUserMessage();
        } else {
          declineUi();
        }
        return;
      }
    }
    var reportJob = resumeJob;
    ReportGenerationLease? reportLease;
    if (reportType != null && aiConfig.hasKey) {
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
        _handleInvalidatedReport();
        return;
      }
      final activeJob = reportJob;
      if (activeJob == null) {
        _handleInvalidatedReport();
        return;
      }
      _observedReportJobId = activeJob.id;
      final scheduled = await ReportTaskScheduler.schedule(
        repo,
        activeJob,
        lease: reportLease,
      );
      if (scheduled) {
        _setThinkingKind(_ThinkingKind.reportCollect);
        _setThinkingCanContinueInBackground(true);
        _restartThinkingTicker();
        return;
      }
      if (!ReportJobRuntime.claim(reportLease.runtimeKey)) return;
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
    );
    var aiAnswered = false;
    String answer;
    if (!aiConfig.hasKey) {
      answer = '查账要先配 AI key 哦～去「我的 → AI 记账设置」填一下，喵就能帮你分析啦';
    } else {
      try {
        late final String transactionsText;
        if (reportType == null) {
          transactionsText = _buildTxnContext(repo, question: text);
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
        }
        if (reportType == null) {
          _setThinkingKind(_ThinkingKind.queryAnswer);
          answer = await LlmQuery.ask(
            question: text,
            config: aiConfig,
            transactionsText: transactionsText,
          );
        } else {
          _setThinkingKind(_ThinkingKind.reportGenerate);
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
          );
        }
        // 报告类本地兜底也应该生成文档卡片，避免用户只看到“没连上”。
        aiAnswered = true;
      } on ReportGenerationInvalidated {
        _releaseReportJob(reportJob, reportLease);
        _handleInvalidatedReport();
        return;
      } on LlmQueryException catch (e) {
        answer = _friendlyAiError(e);
      } catch (e) {
        answer = '喵没连上 AI（${_shortAiError(e)}），待会儿再问问？';
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
      await _addChatMessage(repo, role: 'answer', text: answer, question: text);
      void addAnswerMessage({required bool animate}) {
        _msgs.removeWhere((m) => m is _ThinkingMsg);
        _msgs.add(_AnswerMsg(answer, question: text, shown: !animate));
        _busy = false;
      }

      if (!mounted) {
        addAnswerMessage(animate: false);
        return;
      }
      setState(() => addAnswerMessage(animate: true));
      _scrollToLatestUserMessage();
    } finally {
      _releaseReportJob(reportJob, reportLease);
    }
  }

  Future<void> _saveGeneratedReport({
    required AppRepository repo,
    required ReportJobEntity? reportJob,
    required ReportGenerationLease? reportLease,
    required String reportTitle,
    required String answer,
    required String question,
  }) async {
    try {
      if (reportJob == null || reportLease == null) {
        throw StateError('report job lease is missing');
      }
      _setThinkingKind(_ThinkingKind.reportSave);
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
        _handleInvalidatedReport();
        return;
      }
      void addReportMessage({required bool animate}) {
        _msgs.removeWhere((message) => message is _ThinkingMsg);
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

      if (!mounted) {
        addReportMessage(animate: false);
        return;
      }
      setState(() => addReportMessage(animate: true));
      _scrollToLatestUserMessage();
    } on ReportGenerationInvalidated {
      _handleInvalidatedReport();
    } catch (error) {
      await _setReportJobStage(
        repo,
        reportJob,
        lease: reportLease,
        status: 'failed',
        error: error.toString(),
      );
      void addFailureMessage() {
        _msgs.removeWhere((message) => message is _ThinkingMsg);
        _msgs.add(_InfoMsg('报告保存失败，请稍后重新生成', error: true));
        _busy = false;
      }

      if (mounted) {
        setState(addFailureMessage);
      } else {
        addFailureMessage();
      }
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

  void _releaseReportJob(
    ReportJobEntity? job,
    ReportGenerationLease? lease,
  ) {
    if (job == null || lease == null) return;
    ReportJobRuntime.release(lease.runtimeKey);
  }

  void _handleInvalidatedReport() {
    void clearPendingUi() {
      _msgs.removeWhere((message) => message is _ThinkingMsg);
      _busy = false;
      _observedReportJobId = null;
    }

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
  }) async {
    LlmQueryException? firstError;
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

    _setThinkingKind(_ThinkingKind.reportFallback);
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
    final visible = repo.visibleTransactions.where((t) => !t.excluded).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
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
        bookId == null ? repo.allRecords : repo.recordsForBookView(bookId);
    Decimal netOf(TransactionEntity transaction) => bookId == null
        ? repo.netAmountOf(transaction)
        : repo.netAmountAcrossBooks(transaction);
    final current = visibleTransactions
        .where((t) => inRange(t, start, endExclusive))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
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
        bookId == null ? repo.allRecords : repo.recordsForBookView(bookId);
    Decimal netOf(TransactionEntity transaction) => bookId == null
        ? repo.netAmountOf(transaction)
        : repo.netAmountAcrossBooks(transaction);
    final current = visibleTransactions
        .where((t) => inRange(t, start, endExclusive))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
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
    if (code == 401 || code == 403) {
      return '喵没连上 AI：API Key 可能无效或没有权限，去「我的 → AI 记账设置」检查一下。';
    }
    if (code == 402 || code == 429) {
      return '喵没连上 AI：DeepSeek 余额、额度或频率限制可能不够了，稍后再试或检查控制台。';
    }
    if (e.message.contains('TimeoutException') || e.message.contains('超时')) {
      return '喵没连上 AI：这次请求超时了，账单多的时候可以稍后重试。';
    }
    return '喵没连上 AI（${_shortAiError(e.message)}），待会儿再问问？';
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
    try {
      final repo = repository ?? context.read<AppRepository>();
      final accountId = repo.transactionAccounts.firstOrNull?.id;
      if (accountId == null) {
        if (mounted) _snack('请先在「资产管理」里加一个账户');
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

      // 按条目逐笔入库,记下每笔的 id(无金额的占位 null),用于之后按条目改分类。
      final ids = <int?>[];
      CategoryEntity? feedbackCat;
      DateTime? feedbackDate;
      CategoryEntity? fallbackCat;
      DateTime? fallbackDate;
      int savedCount = 0;
      for (int i = 0; i < msg.entries.length; i++) {
        final e = msg.entries[i];
        final amt = e.amount;
        if (amt == null || amt <= Decimal.zero) {
          ids.add(null);
          continue;
        }
        final id = await repo.addTransaction(
          kind: e.kind,
          amount: amt,
          categoryId: msg.cats[i]?.id,
          accountId: accountId,
          note: e.note,
          date: e.date,
          timePrecision: e.timePrecision,
          reimbursable: SmartTags.isReimbursable(e.note), // 出差/报销自动标待报销
        );
        ids.add(id);
        savedCount++;
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
      if (savedCount == 0) {
        if (mounted) _snack('这几笔没认出金额，先补上金额再存～');
        return;
      }
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
                    const _GreetingLine(),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.only(left: 0),
                      child: _SuggestionGrid(items: _picked, onTap: _fillInput),
                    ),
                  ],
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) => ListView.builder(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(
                  16,
                  4,
                  16,
                  _latestUserAnchorBottomPadding(constraints.maxHeight),
                ),
                itemCount: _msgs.length,
                itemBuilder: (_, i) =>
                    _buildMsg(_msgs[i], isLast: i == _msgs.length - 1),
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
                        builder: (context, constraints) => ListView.builder(
                          controller: _scroll,
                          padding: EdgeInsets.fromLTRB(
                            16,
                            2,
                            16,
                            _latestUserAnchorBottomPadding(
                              constraints.maxHeight,
                            ),
                          ),
                          itemCount: _msgs.length,
                          itemBuilder: (_, i) => _buildMsg(
                            _msgs[i],
                            isLast: i == _msgs.length - 1,
                          ),
                        ),
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
      message: '喵助手的聊天记录会全部清空，不可恢复。',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final repo = context.read<AppRepository>();
    await repo.clearChatMessages();
    if (mounted) setState(() => clearChatHistoryMemory(repo));
  }

  // 卡中卡输入框：浅底圆角框 + 工具行。
  // 输入框：与首页那条完全统一（玻璃圆角卡 + 细黑边）。
  Widget _inputBox(BuildContext context, {bool blurEnabled = true}) {
    final scheme = Theme.of(context).colorScheme;
    return TextFieldTapRegion(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 14,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: GlassSurface(
          radius: 28,
          blur: 10,
          blurEnabled: blurEnabled,
          opacity: blurEnabled ? 0.55 : 0.9,
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _handleInputPointerDown(),
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
                    fontSize: 15,
                    fontWeight: FontWeight.w300,
                  ),
                  decoration: InputDecoration(
                    hintText: '记一记',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
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
              const SizedBox(height: 4),
              Row(
                children: [
                  _CircleBtn(
                    icon: Icons.add,
                    onTap: () => showRecordExtrasSheet(context),
                  ),
                  const SizedBox(width: 6),
                  _Pill(isAi: true, onTap: _switchToManual),
                  const Spacer(),
                  ValueListenableBuilder<bool>(
                    valueListenable: _hasInputText,
                    builder: (context, hasText, _) => _CircleBtn(
                      icon: Icons.arrow_upward,
                      filled: true,
                      onTap: (hasText && !_busy) ? () => _send() : null,
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

  void _regenerate(_AnswerMsg m) {
    if (_busy || m.question.isEmpty) return;
    setState(() {
      _msgs.remove(m);
      _msgs.add(_ThinkingMsg(_ThinkingKind.queryCollect));
      _busy = true;
    });
    _restartThinkingTicker();
    _scrollToBottom();
    _runQuery(m.question);
  }

  Future<void> _regenerateReport(_ReportMsg m) async {
    if (_busy || m.question.isEmpty) return;
    final repo = context.read<AppRepository>();
    final aiConfig = repo.aiProviderConfigFor(AiTaskType.report);
    if (!aiConfig.hasKey) {
      showAppToast(context, '先去「我的 → AI 记账设置」填写 API Key');
      return;
    }
    final report = m.report;
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
        ),
      );
    } on ReportGenerationInvalidated {
      _handleInvalidatedReport();
      return;
    }
    if (!mounted) return;
    setState(() {
      _msgs.remove(m);
      _msgs.add(_ThinkingMsg(_ThinkingKind.reportCollect));
      _busy = true;
    });
    _restartThinkingTicker();
    _scrollToBottom();
    try {
      await _runQuery(m.question, repository: repo, resumeJob: job);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _msgs.removeWhere((msg) => msg is _ThinkingMsg);
        _msgs.add(m);
        _msgs.add(_InfoMsg('报告重新生成失败，稍后再试', error: true));
        _busy = false;
      });
    }
    _scrollToBottom();
  }

  Widget _buildMsg(_Msg m, {bool isLast = false}) {
    if (m is _UserMsg) {
      final bubble = _UserBubble(text: m.text);
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
        onShown: () => m.shown = true,
        onRegenerate: m.question.isEmpty ? null : () => _regenerate(m),
        // 猫只出现在最后一条回复下（对齐 Claude），历史回复不重复放猫。
        showMascot: isLast,
      );
    }
    if (m is _ReportMsg) {
      return _ReportBubble(
        msg: m,
        onRegenerate: m.question.isEmpty ? null : () => _regenerateReport(m),
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
  _UserMsg(this.text);
}

class _ThinkingMsg extends _Msg {
  _ThinkingKind kind;
  bool canContinueInBackground;
  final DateTime startedAt;

  _ThinkingMsg(
    this.kind, {
    DateTime? startedAt,
  })  : canContinueInBackground = false,
        startedAt = startedAt ?? DateTime.now();
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
}

class _InfoMsg extends _Msg {
  final String text;
  final bool error;
  _InfoMsg(this.text, {this.error = false});
}

class _AnswerMsg extends _Msg {
  final String text;
  final String question;
  bool shown;
  _AnswerMsg(this.text, {this.question = '', this.shown = false});
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

  _RecordMsg({
    required this.entries,
    required this.cats,
    this.saved = false,
    this.savedIds = const [],
    this.txnIds = const [],
    this.savedFeedback = '',
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
  const DecodedRecordCard({
    required this.entries,
    required this.catIds,
    required this.txnIds,
    required this.saved,
    required this.feedback,
    required this.deleted,
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

class _UserBubble extends StatelessWidget {
  final String text;
  const _UserBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bubbleStyle = context.select<AppRepository, UserMessageBubbleStyle>(
      (repo) => repo.userMessageBubbleStyle,
    );
    final bubbleColor = bubbleStyle == UserMessageBubbleStyle.followCardOpacity
        ? AppColors.card(scheme)
        : scheme.surfaceContainerHighest;
    const textStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      fontVariations: [FontVariation('wght', 330)],
    );
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, left: 40),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text.rich(
          TextSpan(children: _chatNumberSpans(text, textStyle)),
          style: textStyle,
        ),
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  final _ThinkingMsg msg;
  const _ThinkingBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Mascot(
            mood: MascotMood.thinking,
            size: 32,
            animate: true,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              aiThinkingStatusText(
                elapsed: DateTime.now().difference(msg.startedAt),
                canContinueInBackground: msg.canContinueInBackground,
              ),
              style: AppType.secondary(scheme),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBubble extends StatelessWidget {
  final String text;
  final bool error;
  const _InfoBubble({required this.text, this.error = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textStyle = TextStyle(
      fontSize: 14,
      // 守不用红铁律：错误提示用超支橙；普通说明走标准中灰。
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

// ── 查账回答气泡（喵助手回答，打字机流式）────────────────────────────────────
class _AnswerBubble extends StatefulWidget {
  final String text;
  final bool animate;
  final VoidCallback? onShown;
  final VoidCallback? onRegenerate;

  /// 是否在操作图标下放猫：只有列表最后一条回复为 true（对齐 Claude）。
  final bool showMascot;

  const _AnswerBubble({
    required this.text,
    this.animate = true,
    this.onShown,
    this.onRegenerate,
    this.showMascot = false,
  });

  @override
  State<_AnswerBubble> createState() => _AnswerBubbleState();
}

class _AnswerBubbleState extends State<_AnswerBubble> {
  int _shown = 0;
  late final int _graphemeCount;
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

  // Claude-like emphasis: only one quiet step above body text.
  // 不支持可变字重的机型回退到 fontWeight w500。
  TextStyle _boldOf(TextStyle base) => base.copyWith(
        fontWeight: FontWeight.w500,
        fontVariations: const [FontVariation('wght', 470)],
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

  // 轻量 markdown → 富文本：处理 **加粗**、行首 - / * 列表、# 标题；保留可选中。
  List<InlineSpan> _mdSpans(String text, TextStyle base) {
    final spans = <InlineSpan>[];
    final lines = text.split('\n');
    final headerStyle = base.copyWith(
      fontSize: (base.fontSize ?? 15.5) + 0.4,
      fontWeight: FontWeight.w500,
      fontVariations: const [FontVariation('wght', 520)],
      color: base.color,
    );
    void newline() => spans.add(const TextSpan(text: '\n'));
    for (int li = 0; li < lines.length; li++) {
      var line = lines[li].replaceAll('__', '');
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shownText = aiTypewriterPrefix(widget.text, _shown);
    final done = _shown >= _graphemeCount;
    // Claude-like answer typography: soft body text and restrained emphasis.
    final baseStyle = TextStyle(
      fontSize: 15.5,
      height: 1.48,
      fontWeight: FontWeight.w400,
      fontVariations: const [FontVariation('wght', 350)],
      color: scheme.onSurface.withValues(alpha: 0.9),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 回答正文：全宽、无气泡（对标 Claude），轻量 markdown 渲染。
          SelectableText.rich(
            TextSpan(
              style: baseStyle,
              children: _mdSpans(shownText, baseStyle),
            ),
          ),
          if (done) ...[
            const SizedBox(height: 4),
            // 操作图标行（对标 Claude：裸图标、细线、浅灰）。
            Row(
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
    final textStyle = TextStyle(
      fontSize: 15.5,
      height: 1.48,
      fontWeight: FontWeight.w400,
      fontVariations: const [FontVariation('wght', 350)],
      color: scheme.onSurface.withValues(alpha: 0.9),
    );
    msg.shown = true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, right: 8),
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

// ── 喵助手打开时主动说的一句洞察 ──────────────────────────────────────────────
class _GreetingLine extends StatelessWidget {
  const _GreetingLine();

  @override
  Widget build(BuildContext context) {
    final g = MeowInsights.greeting(context.read<AppRepository>());
    if (g == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Text(
      g,
      style: TextStyle(
        fontSize: 15,
        height: 1.45,
        fontWeight: FontWeight.w400,
        fontVariations: const [FontVariation('wght', 330)],
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
  final void Function(int index) onChangeCategory;
  final void Function(int index) onDeleteEntry;

  const _RecordBubble({
    required this.msg,
    required this.bookName,
    required this.onSave,
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
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onSave,
                      child: Text(
                        msg.saving ? '正在保存' : (n > 1 ? '记下这 $n 笔' : '记下'),
                      ),
                    ),
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

class _Pill extends StatelessWidget {
  final bool isAi;
  final VoidCallback onTap;

  const _Pill({required this.isAi, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onPressed: onTap,
      child: GlassSurface(
        radius: 15,
        blur: 0, // 面板背景已经模糊过，无需叠加
        padding: const EdgeInsets.symmetric(horizontal: 11),
        child: SizedBox(
          height: 31,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isAi ? Icons.auto_awesome : Icons.edit_outlined,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                isAi ? 'AI 记账' : '手动记账',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;

  const _CircleBtn({
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (filled) {
      final active = onTap != null;
      return PressableScale(
        onPressed: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: active
                ? scheme.secondary
                : scheme.onSurface.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 18,
            color: active
                ? scheme.onSecondary
                : scheme.onSurface.withValues(alpha: 0.38),
          ),
        ),
      );
    }
    return PressableScale(
      onPressed: onTap,
      child: SizedBox(
        width: 34,
        height: 34,
        child: GlassSurface(
          circle: true,
          blur: 0, // 面板背景已经模糊过，无需叠加
          child: Center(
            child: Icon(icon, size: 17, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
