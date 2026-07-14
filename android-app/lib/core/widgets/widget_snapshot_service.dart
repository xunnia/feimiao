import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/budget/budget_engine.dart';
import '../../data/app_repository.dart';
import '../models/transaction_kind.dart';
import '../money_format.dart';
import '../statistics/statistics_engine.dart';
import '../../widgets/home_summary_card.dart';
import '../../widgets/monthly_pace_card.dart';
import 'native_widget_bridge.dart';
import 'widget_card_renderer.dart';
import 'widget_snapshot.dart';

class WidgetSnapshotService with WidgetsBindingObserver {
  WidgetSnapshotService._();

  static final WidgetSnapshotService instance = WidgetSnapshotService._();

  AppRepository? _repo;
  Timer? _debounce;
  String? _lastFingerprint;
  Future<void>? _refreshInFlight;
  int _requestedGeneration = 0;
  static int _renderSequence = 0;

  void attach(AppRepository repo) {
    if (_repo == repo) return;
    _repo?.removeListener(_scheduleRefresh);
    _repo = repo;
    _lastFingerprint = null;
    repo.addListener(_scheduleRefresh);
    WidgetsBinding.instance.addObserver(this);
    unawaited(refreshNow());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleRefresh();
    }
  }

  void _scheduleRefresh() {
    // notifyListeners 到达时立刻让正在渲染的旧代失效；真正重渲仍做 500ms 防抖。
    _requestedGeneration++;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      unawaited(_ensureRefreshLoop());
    });
  }

  Future<void> refreshNow() {
    _requestedGeneration++;
    return _ensureRefreshLoop();
  }

  Future<void> _ensureRefreshLoop() {
    final current = _refreshInFlight;
    if (current != null) return current;
    final future = _drainRefreshes();
    _refreshInFlight = future;
    return future;
  }

  Future<void> _drainRefreshes() async {
    try {
      while (_repo != null) {
        final generation = _requestedGeneration;
        await _refreshGeneration(generation);
        if (generation == _requestedGeneration) break;
      }
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<void> _refreshGeneration(int generation) async {
    final repo = _repo;
    if (repo == null) return;
    // 数据没变就整体跳过：repo 每次 notifyListeners（含和账单无关的设置变更）
    // 都会打到这里，不挡的话每次记账后都白白离屏渲两张 PNG + 写盘。
    // generatedAtMs 每次都变，指纹要把它剔掉再比。
    final today = DateTime.now();
    final sourceSnapshot = FeimiaoWidgetSnapshotBuilder.build(repo, now: today);
    final fingerprint = _fingerprintOf(sourceSnapshot.toJson());
    if (fingerprint == _lastFingerprint) return;
    final snapshot = await buildSnapshotJsonForRepo(
      repo,
      now: today,
      sourceSnapshot: sourceSnapshot,
      renderKey: '$generation',
    );
    if (_repo != repo || generation != _requestedGeneration) {
      await _deleteSnapshotRenders(snapshot);
      return;
    }
    final saved = await NativeWidgetBridge.saveSnapshot(snapshot);
    if (!saved) {
      await _deleteSnapshotRenders(snapshot);
      return;
    }
    _lastFingerprint = fingerprint; // 渲染+落盘都成功才记，失败下次重试
    await _cleanupOldRenders(snapshot);
  }

  static String _fingerprintOf(Map<String, Object?> json) {
    final copy = Map<String, Object?>.of(json)..remove('generatedAtMs');
    return jsonEncode(copy);
  }

  @visibleForTesting
  Future<Map<String, Object?>> buildSnapshotJsonForRepo(
    AppRepository repo, {
    DateTime? now,
    Directory? renderDirectory,
    String? renderKey,
    FeimiaoWidgetSnapshot? sourceSnapshot,
  }) async {
    final today = now ?? DateTime.now();
    final snapshot =
        sourceSnapshot ?? FeimiaoWidgetSnapshotBuilder.build(repo, now: today);
    final json = snapshot.toJson();
    try {
      final renderInfo = await _renderWidgetCards(
        repo,
        today: today,
        privacy: snapshot.privacyMode,
        renderDirectory: renderDirectory,
        renderKey: renderKey ??
            '${DateTime.now().microsecondsSinceEpoch}-${_renderSequence++}',
      );
      final modules = json['modules'];
      if (modules is Map<String, Object?>) {
        (modules['overview'] as Map<String, Object?>?)?['render'] =
            renderInfo.overview;
        (modules['pace'] as Map<String, Object?>?)?['render'] = renderInfo.pace;
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('widget card render failed: $error');
        debugPrint('$stackTrace');
      }
    }
    return json;
  }

  void dispose() {
    _debounce?.cancel();
    _repo?.removeListener(_scheduleRefresh);
    WidgetsBinding.instance.removeObserver(this);
    _repo = null;
    _requestedGeneration++;
    _lastFingerprint = null;
  }

  Future<_WidgetRenderInfo> _renderWidgetCards(
    AppRepository repo, {
    required DateTime today,
    required bool privacy,
    Directory? renderDirectory,
    required String renderKey,
  }) async {
    final targetDir = renderDirectory ??
        Directory(
          p.join(
              (await getApplicationSupportDirectory()).path, 'widget_render'),
        );
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final summary = StatisticsEngine.monthlySummary(
      repo.allRecords,
      year: today.year,
      month: today.month,
    );
    final budgetWindow = repo.budgetForCalendarMonth(
      DateTime(today.year, today.month),
      asOf: today,
    );
    final budget = budgetWindow.plannedAmount;
    final budgetStatus = BudgetEngine.fromWindowResult(budgetWindow);
    // 按设备真实像素密度渲染并留 1.25 倍超采样余量：显示端只缩不放
    //（缩不糊、放才糊）。写死 2.0 在 3.5x 屏上会被放大 1.75 倍、文字发糊。
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    final renderRatio =
        ((view?.devicePixelRatio ?? 3.0) * 1.25).clamp(2.0, 4.5).toDouble();
    // 渲染宽度=设备逻辑屏宽：卡片排版和 App 内逐像素一致
    //（渲窄了收入/支出两栏被挤、看着"横向压缩"，用户点名）。
    final screenW = view == null
        ? 400.0
        : (view.physicalSize.width / view.devicePixelRatio);
    final renderSize =
        Size(screenW.clamp(340.0, 480.0).toDouble(), screenW * 1.3);
    // 自然高度渲染（不再套 WidgetCardCanvas 的 FittedBox——
    // 预算卡比 2:1 高，被它整体缩小过一轮，字在桌面上小一大圈）。
    // 先让当前手势/键盘帧完成；Flutter Widget 树只能在根 isolate 绘制，
    // 但两张卡拆帧且 PNG 压缩已移到后台 isolate，不再连续占住 UI。
    await Future<void>.delayed(const Duration(milliseconds: 16));
    final overviewBytes = await renderWidgetToPng(
      HomeSummaryCard(
        monthDate: DateTime(today.year, today.month),
        isCurrentMonth: true,
        summary: summary,
        budgetStatus: budgetStatus,
        budget: budget,
        maskAmounts: privacy,
        compact: true,
      ),
      logicalSize: renderSize,
      naturalHeight: true,
      pixelRatio: renderRatio,
    );
    await Future<void>.delayed(const Duration(milliseconds: 16));
    final paceBytes = await renderWidgetToPng(
      MonthlyPaceCard(
        records: repo.allRecords,
        summary: summary,
        year: today.year,
        month: today.month,
        isCurrentMonth: true,
        maskAmounts: privacy,
        compact: true,
      ),
      logicalSize: renderSize,
      naturalHeight: true,
      pixelRatio: renderRatio,
    );

    final overviewFile = await _writePngAtomically(
      targetDir,
      'overview-$renderKey.png',
      overviewBytes,
    );
    final paceFile = await _writePngAtomically(
      targetDir,
      'pace-$renderKey.png',
      paceBytes,
    );
    final renderedAtMs = DateTime.now().millisecondsSinceEpoch;

    Map<String, Object?> infoFor(File file, Size logicalSize, Uint8List bytes) {
      return {
        'path': file.path,
        'renderedAtMs': renderedAtMs,
        'logicalWidth': logicalSize.width,
        'logicalHeight': logicalSize.height,
        'pixelRatio': renderRatio,
        'byteLength': bytes.length,
      };
    }

    return _WidgetRenderInfo(
      overview: infoFor(overviewFile, renderSize, overviewBytes),
      pace: infoFor(paceFile, renderSize, paceBytes),
    );
  }

  Future<File> _writePngAtomically(
    Directory dir,
    String fileName,
    Uint8List bytes,
  ) async {
    final out = File(p.join(dir.path, fileName));
    final tmp = File(
      '${out.path}.${DateTime.now().microsecondsSinceEpoch}-${_renderSequence++}.tmp',
    );
    await tmp.writeAsBytes(bytes, flush: true);
    try {
      return await tmp.rename(out.path);
    } on FileSystemException {
      if (await out.exists()) {
        await out.delete();
      }
      return tmp.rename(out.path);
    }
  }

  static Iterable<String> _renderPaths(Map<String, Object?> snapshot) sync* {
    final modules = snapshot['modules'];
    if (modules is! Map) return;
    for (final key in const ['overview', 'pace']) {
      final module = modules[key];
      if (module is! Map) continue;
      final render = module['render'];
      if (render is! Map) continue;
      final path = render['path'];
      if (path is String && path.isNotEmpty) yield path;
    }
  }

  Future<void> _deleteSnapshotRenders(Map<String, Object?> snapshot) async {
    for (final path in _renderPaths(snapshot)) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<void> _cleanupOldRenders(Map<String, Object?> snapshot) async {
    final keep = _renderPaths(snapshot).map(p.normalize).toSet();
    final directories = keep.map((path) => Directory(p.dirname(path))).toSet();
    for (final directory in directories) {
      try {
        if (!await directory.exists()) continue;
        await for (final entity in directory.list()) {
          if (entity is! File) continue;
          final name = p.basename(entity.path);
          final isRender =
              name.startsWith('overview-') || name.startsWith('pace-');
          if ((isRender || name.endsWith('.tmp')) &&
              !keep.contains(p.normalize(entity.path))) {
            await entity.delete();
          }
        }
      } catch (_) {}
    }
  }
}

class _WidgetRenderInfo {
  final Map<String, Object?> overview;
  final Map<String, Object?> pace;

  const _WidgetRenderInfo({required this.overview, required this.pace});
}

class FeimiaoWidgetSnapshotBuilder {
  FeimiaoWidgetSnapshotBuilder._();

  static FeimiaoWidgetSnapshot build(AppRepository repo, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final privacy = repo.widgetPrivacyMode;

    final summary = StatisticsEngine.monthlySummary(
      repo.allRecords,
      year: today.year,
      month: today.month,
    );
    final todayExpense = summary.dailyTotals[today.day - 1].expense;
    final monthExpense = summary.totalExpense;
    final monthIncome = summary.totalIncome;
    final topCategoryByKey = {
      for (final category in repo.categories)
        if (category.parentId == null) category.key: category,
    };
    final categoryTotals = [
      for (final total in summary.expenseByCategory)
        (() {
          final key = total.key.isEmpty ? 'other' : total.key;
          final category = topCategoryByKey[key];
          return WidgetCategoryTotal(
            id: category?.id ?? -1,
            key: key,
            name: total.name,
            colorValue: _categoryColor(key),
            total: total.total,
            count: total.count,
          );
        })(),
    ];

    final balance = monthIncome - monthExpense;
    final budgetWindow = repo.budgetForCalendarMonth(
      DateTime(today.year, today.month),
      asOf: today,
    );
    final budget = budgetWindow.plannedAmount;
    final budgetSpent = budgetWindow.spentAmount ?? monthExpense;
    final budgetProgress = _budgetProgress(budgetSpent, budget);
    final budgetText = _budgetText(budgetSpent, budget, privacy);
    final budgetHint = _budgetHint(
      budgetSpent,
      budget,
      privacy,
      excludedForeignCount: budgetWindow.excludedForeignTransactionCount,
    );
    final pace = _paceSnapshot(repo, today, monthExpense, privacy);
    final categories = _topCategories(categoryTotals, monthExpense, privacy);
    final bookName = repo.currentBook?.name ?? '肥喵记账';
    final dateText = '${today.month}月${today.day}日';
    final hasBudget = budget != null && budget > Decimal.zero;
    final overview = _overviewSnapshot(
      monthExpense: hasBudget ? budgetSpent : monthExpense,
      monthIncome: monthIncome,
      todayExpense: todayExpense,
      balance: balance,
      budget: budget,
      budgetText: budgetText,
      budgetProgress: budgetProgress,
      privacy: privacy,
    );
    final categoriesModule = FeimiaoWidgetCategoriesSnapshot(
      state: categories.isEmpty ? 'empty' : (privacy ? 'privacy' : 'normal'),
      title: '分类与支出活动',
      items: categories,
      showAllText: '查看所有',
    );

    return FeimiaoWidgetSnapshot(
      generatedAtMs: today.millisecondsSinceEpoch,
      bookId: repo.currentBook?.id,
      bookName: bookName,
      dateText: dateText,
      year: today.year,
      month: today.month,
      day: today.day,
      todayExpenseText: _money(todayExpense, privacy),
      monthExpenseText: _money(monthExpense, privacy),
      monthIncomeText: _money(monthIncome, privacy),
      balanceText: _money(balance, privacy),
      budgetTitle: hasBudget ? '预算剩余' : '本月支出',
      budgetText: budgetText,
      budgetHint: budgetHint,
      budgetProgress: budgetProgress,
      paceCaption: pace.caption,
      paceAverageText: pace.averageText,
      paceThisProgress: pace.thisProgress,
      paceAverageProgress: pace.averageProgress,
      privacyMode: privacy,
      categories: categories,
      overview: overview,
      pace: pace.module,
      categoriesModule: categoriesModule,
      // 副标题只放日期：账本名会被截断成「总...」，没信息量（用户点名）。
      quickAdd: FeimiaoWidgetQuickAddSnapshot(
        title: '记一笔',
        subtitle: dateText,
        openMode: 'manual',
      ),
    );
  }

  static FeimiaoWidgetOverviewSnapshot _overviewSnapshot({
    required Decimal monthExpense,
    required Decimal monthIncome,
    required Decimal todayExpense,
    required Decimal balance,
    required Decimal? budget,
    required String budgetText,
    required int budgetProgress,
    required bool privacy,
  }) {
    final hasBudget = budget != null && budget > Decimal.zero;
    final status = !hasBudget
        ? 'normal'
        : budgetProgress >= 100
            ? 'over'
            : budgetProgress >= 85
                ? 'nearLimit'
                : 'normal';

    if (hasBudget) {
      return FeimiaoWidgetOverviewSnapshot(
        mode: privacy ? 'privacy' : 'budget',
        title: '预算概览',
        primary: FeimiaoWidgetMetricSnapshot(
          label: '预算剩余',
          amountText: budgetText,
          semanticText: '预算剩余$budgetText',
        ),
        secondary: [
          FeimiaoWidgetMetricSnapshot(
            label: '支出',
            amountText: _money(monthExpense, privacy),
            semanticText: '本月支出${_money(monthExpense, privacy)}',
          ),
          FeimiaoWidgetMetricSnapshot(
            label: '今日',
            amountText: _money(todayExpense, privacy),
            semanticText: '今日支出${_money(todayExpense, privacy)}',
          ),
          FeimiaoWidgetMetricSnapshot(
            label: '收入',
            amountText: _money(monthIncome, privacy),
            semanticText: '本月收入${_money(monthIncome, privacy)}',
          ),
        ],
        progress: FeimiaoWidgetProgressSnapshot(
          visible: true,
          value: budgetProgress,
          status: status,
        ),
      );
    }

    return FeimiaoWidgetOverviewSnapshot(
      mode: privacy ? 'privacy' : 'normal',
      title: '本月概览',
      primary: FeimiaoWidgetMetricSnapshot(
        label: '支出',
        amountText: _money(monthExpense, privacy),
        semanticText: '本月支出${_money(monthExpense, privacy)}',
      ),
      secondary: [
        FeimiaoWidgetMetricSnapshot(
          label: '收入',
          amountText: _money(monthIncome, privacy),
          semanticText: '本月收入${_money(monthIncome, privacy)}',
        ),
        FeimiaoWidgetMetricSnapshot(
          label: '今日',
          amountText: _money(todayExpense, privacy),
          semanticText: '今日支出${_money(todayExpense, privacy)}',
        ),
        FeimiaoWidgetMetricSnapshot(
          label: '结余',
          amountText: _money(balance, privacy),
          semanticText: '本月结余${_money(balance, privacy)}',
        ),
      ],
      progress: const FeimiaoWidgetProgressSnapshot(
        visible: false,
        value: 0,
        status: 'normal',
      ),
    );
  }

  static _WidgetPaceSnapshot _paceSnapshot(
    AppRepository repo,
    DateTime today,
    Decimal currentExpense,
    bool privacy,
  ) {
    final months = <DateTime>[
      for (var offset = 6; offset >= 1; offset--)
        DateTime(today.year, today.month - offset),
    ];
    final sameProgressSlots = <int, Decimal>{};
    final fullMonthSlots = <int, Decimal>{};
    for (final month in months) {
      final key = month.year * 100 + month.month;
      sameProgressSlots[key] = Decimal.zero;
      fullMonthSlots[key] = Decimal.zero;
    }

    for (final transaction in repo.visibleTransactions) {
      if (transaction.txKind != TransactionKind.expense) continue;
      final key = transaction.date.year * 100 + transaction.date.month;
      if (!fullMonthSlots.containsKey(key)) continue;
      final amount = repo.userAmountOf(transaction);
      if (amount <= Decimal.zero) continue;
      fullMonthSlots[key] = fullMonthSlots[key]! + amount;
      final comparableDay = math.min(
        today.day,
        DateTime(transaction.date.year, transaction.date.month + 1, 0).day,
      );
      if (transaction.date.day <= comparableDay) {
        sameProgressSlots[key] = sameProgressSlots[key]! + amount;
      }
    }

    final samples =
        sameProgressSlots.values.where((v) => v > Decimal.zero).toList();
    final average = samples.isEmpty
        ? Decimal.zero
        : (samples.fold(Decimal.zero, (a, b) => a + b) /
                Decimal.fromInt(samples.length))
            .toDecimal(scaleOnInfinitePrecision: 2);
    final maxAmount = [
      currentExpense,
      average,
      ...sameProgressSlots.values,
      ...fullMonthSlots.values,
    ].fold<Decimal>(Decimal.zero, (max, item) => item > max ? item : max);
    final maxChartValue = math.max(MoneyFormat.toDouble(maxAmount), 0.01);
    final legacyMaxValue = math.max(
      math.max(
        MoneyFormat.toDouble(currentExpense),
        MoneyFormat.toDouble(average),
      ),
      0.01,
    );

    int legacyProgressOf(Decimal amount) =>
        ((MoneyFormat.toDouble(amount) / legacyMaxValue).clamp(0.0, 1.0) * 100)
            .round();

    final chartMonths = [
      for (final month in months)
        FeimiaoWidgetPaceMonthSnapshot(
          label: '${month.month}月',
          fullValue: MoneyFormat.toDouble(
              fullMonthSlots[month.year * 100 + month.month]!),
          sameProgressValue: MoneyFormat.toDouble(
              sameProgressSlots[month.year * 100 + month.month]!),
          isCurrent: false,
        ),
      FeimiaoWidgetPaceMonthSnapshot(
        label: '${today.month}月',
        fullValue: 0,
        sameProgressValue: MoneyFormat.toDouble(currentExpense),
        isCurrent: true,
      ),
    ];
    final state = currentExpense <= Decimal.zero && samples.isEmpty
        ? 'empty'
        : samples.length < 2
            ? 'insufficientData'
            : privacy
                ? 'privacy'
                : 'normal';
    final caption = '截至${today.month}月${today.day}日';
    final averageText = samples.length < 2 ? '--' : _money(average, privacy);
    final currentText = _money(currentExpense, privacy);

    return _WidgetPaceSnapshot(
      caption: caption,
      averageText: averageText,
      thisProgress: legacyProgressOf(currentExpense),
      averageProgress: samples.length < 2 ? 0 : legacyProgressOf(average),
      module: FeimiaoWidgetPaceSnapshot(
        state: state,
        title: caption,
        average: FeimiaoWidgetMetricSnapshot(
          label: '平均',
          amountText: averageText,
          semanticText: '历史同期平均$averageText',
        ),
        current: FeimiaoWidgetMetricSnapshot(
          label: '本月',
          amountText: currentText,
          semanticText: '本月截至今日支出$currentText',
        ),
        averageValue: MoneyFormat.toDouble(average),
        currentValue: MoneyFormat.toDouble(currentExpense),
        maxChartValue: maxChartValue,
        months: chartMonths,
        semanticText: '$caption，本月支出$currentText，历史同期平均$averageText',
      ),
    );
  }

  static int _budgetProgress(Decimal spent, Decimal? budget) {
    if (budget == null || budget <= Decimal.zero) return 0;
    final ratio = MoneyFormat.toDouble(spent) / MoneyFormat.toDouble(budget);
    return (ratio.clamp(0.0, 1.0) * 100).round();
  }

  static String _budgetText(Decimal spent, Decimal? budget, bool privacy) {
    if (budget == null || budget <= Decimal.zero) {
      return privacy ? '••••' : _money(spent, false);
    }
    final remain = budget - spent;
    if (remain >= Decimal.zero) return _money(remain, privacy);
    return '超 ${_money(remain.abs(), privacy)}';
  }

  static String _budgetHint(
    Decimal spent,
    Decimal? budget,
    bool privacy, {
    int excludedForeignCount = 0,
  }) {
    if (budget == null || budget <= Decimal.zero) {
      return '未设置预算 · 已展示本月支出';
    }
    if (privacy) return '金额已隐藏 · 进度仍保留';
    final currencyHint =
        excludedForeignCount > 0 ? ' · 已排除 $excludedForeignCount 笔其他币种' : '';
    final remain = budget - spent;
    if (remain >= Decimal.zero) {
      return '已用 ${_money(spent, false)} / ${_money(budget, false)}'
          '$currencyHint';
    }
    return '预算 ${_money(budget, false)} · 已超支$currencyHint';
  }

  static List<FeimiaoWidgetCategorySnapshot> _topCategories(
    Iterable<WidgetCategoryTotal> totals,
    Decimal monthExpense,
    bool privacy,
  ) {
    final sorted = totals.toList()..sort((a, b) => b.total.compareTo(a.total));
    if (sorted.isEmpty || monthExpense <= Decimal.zero) return const [];

    final denominator = math.max(MoneyFormat.toDouble(monthExpense), 0.01);
    return sorted.take(3).map((item) {
      final ratio = MoneyFormat.toDouble(item.total) / denominator;
      return FeimiaoWidgetCategorySnapshot(
        id: item.id,
        name: item.name,
        amountText: _money(item.total, privacy),
        percentText: '${(ratio * 100).clamp(0, 100).round()}%',
        progress: (ratio.clamp(0.0, 1.0) * 100).round(),
        count: item.count,
        colorValue: item.colorValue,
        semanticText:
            '${item.name}${_money(item.total, privacy)}，占本月支出${(ratio * 100).clamp(0, 100).round()}%',
      );
    }).toList();
  }

  static String _money(Decimal amount, bool privacy) {
    if (privacy) return '••••';
    return MoneyFormat.string(amount);
  }

  static int _categoryColor(String key) {
    if (key == 'other' || key.startsWith('other')) return 0xFF8A8D92;
    if (key == 'dining' || key == 'groceries' || key.startsWith('dining')) {
      return 0xFFD88A17;
    }
    if (key == 'shopping' || key.startsWith('shop')) return 0xFFE06A8A;
    if (key == 'transport' || key.startsWith('trans') || key == 'car') {
      return 0xFF4876E8;
    }
    if (key == 'housing' || key.startsWith('house')) return 0xFF7B61D1;
    if (key == 'medical' || key.startsWith('med')) return 0xFFD85C5C;
    if (key == 'education' || key.startsWith('edu')) return 0xFF2F80ED;
    if (key == 'entertainment' || key.startsWith('ent')) return 0xFF9B51E0;
    if (key == 'travel') return 0xFF00A7A7;
    if (key == 'gifts' || key.startsWith('gift')) return 0xFFEB5757;
    if (key == 'salary' || key.startsWith('inc_salary')) return 0xFF1F9A69;
    if (key == 'bonus' || key.startsWith('inc_bonus')) return 0xFF27AE60;
    if (key == 'investment' || key.startsWith('inc_')) return 0xFF0A84FF;
    return 0xFF2F3135;
  }
}

class _WidgetPaceSnapshot {
  final String caption;
  final String averageText;
  final int thisProgress;
  final int averageProgress;
  final FeimiaoWidgetPaceSnapshot module;

  const _WidgetPaceSnapshot({
    required this.caption,
    required this.averageText,
    required this.thisProgress,
    required this.averageProgress,
    required this.module,
  });
}
