/// 还款提醒本地通知（A 批第 5 段）。
///
/// 排两条：还款日前一天 20:00 + 还款日当天 10:00，标题「肥喵提醒还款」、
/// 正文「XX 账户 MM-dd 要还款啦喵」。inexact 调度（不申请 Android 特权的
/// 精确闹钟权限）。
///
/// 重排时机（选择「App 恢复时重算」，不逐个挂 repo mutation 监听——最简单
/// 可靠：还款提醒本身允许小误差，档案变化不频繁，App 启动/回前台重算一次
/// 足够覆盖；见 [RepaymentReminderScheduler.reschedule] 调用点 main.dart）。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../data/app_repository.dart';

/// 一条待还款：哪个档案、账户叫什么、下次还款日是哪天。
/// 不带 repo 实体类型，方便 [planRepaymentReminders] 脱离数据层单测。
typedef RepaymentDue = ({
  int profileId,
  String accountLabel,
  DateTime dueDate,
});

/// 已算好的一条提醒：什么时候发、发给哪个档案、文案是什么。
class RepaymentReminderItem {
  final int profileId;
  final String accountLabel;
  final DateTime dueDate;

  /// 该发出的本地时间（前一天 20:00 或当天 10:00）。
  final DateTime scheduledAt;

  /// true=还款日前一天 20:00 那条，false=还款日当天 10:00 那条。
  final bool isDayBefore;

  const RepaymentReminderItem({
    required this.profileId,
    required this.accountLabel,
    required this.dueDate,
    required this.scheduledAt,
    required this.isDayBefore,
  });

  /// 每个档案两个稳定 id（前一天/当天各一），避免重排时和别的通知撞号，
  /// 也不需要额外持久化 id 映射。
  int get notificationId => 741000 + profileId * 2 + (isDayBefore ? 0 : 1);

  String get title => '肥喵提醒还款';

  String get body {
    final mm = dueDate.month.toString().padLeft(2, '0');
    final dd = dueDate.day.toString().padLeft(2, '0');
    return '$accountLabel 账户 $mm-$dd 要还款啦喵';
  }
}

/// 纯函数：给定「谁、哪天要还」和当前时间，算出该排哪些提醒时刻。
/// 不碰通知插件，可直接单测。
///
/// 规则：
/// - 每笔 due 排两个候选——`due 前一天 20:00`、`due 当天 10:00`。
/// - 候选时刻已经过去（<= now）的不排——不补发「迟到」提醒，也不会因为
///   重排时把过去时刻交给 zonedSchedule 报错。
List<RepaymentReminderItem> planRepaymentReminders({
  required List<RepaymentDue> dues,
  required DateTime now,
}) {
  final items = <RepaymentReminderItem>[];
  for (final due in dues) {
    final day =
        DateTime(due.dueDate.year, due.dueDate.month, due.dueDate.day);
    final dayBeforeDate = day.subtract(const Duration(days: 1));
    final dayBeforeAt = DateTime(
      dayBeforeDate.year,
      dayBeforeDate.month,
      dayBeforeDate.day,
      20,
    );
    final dayOfAt = DateTime(day.year, day.month, day.day, 10);
    if (dayBeforeAt.isAfter(now)) {
      items.add(RepaymentReminderItem(
        profileId: due.profileId,
        accountLabel: due.accountLabel,
        dueDate: day,
        scheduledAt: dayBeforeAt,
        isDayBefore: true,
      ));
    }
    if (dayOfAt.isAfter(now)) {
      items.add(RepaymentReminderItem(
        profileId: due.profileId,
        accountLabel: due.accountLabel,
        dueDate: day,
        scheduledAt: dayOfAt,
        isDayBefore: false,
      ));
    }
  }
  return items;
}

/// 还款提醒的通知调度：复用 App 里唯一的 FlutterLocalNotificationsPlugin
/// 用法（对齐 report_task_scheduler.dart），独立 channel（还款提醒和报告
/// 完成通知语义不同）。
class RepaymentReminderScheduler {
  RepaymentReminderScheduler._();

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static bool _notificationsInitialized = false;
  static bool _timeZoneInitialized = false;

  /// 排进 payload 的前缀，重排时靠它从 pendingNotificationRequests 里
  /// 精确挑出「上一轮还款提醒」，不会误撤销报告完成通知等别的通知。
  static const String _payloadPrefix = 'repayment_reminder:';

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 根据 repo 当前的活跃负债档案重排全部还款提醒：先撤销上一轮排的，
  /// 开关关着就到此为止；开着才继续算新的一轮并排上去。
  static Future<void> reschedule(AppRepository repo) async {
    if (!isSupported) return;
    try {
      await _ensureInitialized();
      await _cancelScheduled();
      if (!repo.repaymentReminderEnabled) return;
      // Android 13+ 运行时权限：只在还没授权时申请，不会每次重排都弹窗
      // （已授权 areNotificationsEnabled 直接 true 跳过；被拒时系统自己
      // 会抑制重复弹窗，不用我们额外记"问过没"）。
      await _ensurePermission();
      final now = DateTime.now();
      // withinDays 给足够大的窗口：月循环还款日永远在下月之内（<=31
      // 天），但个人借入的一次性到期日可能约得更远，留一年余量，别让
      // 「App 好久没开」期间该排的提醒漏排。
      final upcoming = repo.upcomingRepayments(withinDays: 400, now: now);
      final dues = <RepaymentDue>[
        for (final u in upcoming)
          if (u.account != null)
            (profileId: u.profile.id, accountLabel: u.account!.name, dueDate: u.nextDate),
      ];
      final items = planRepaymentReminders(dues: dues, now: now);
      for (final item in items) {
        await _scheduleOne(item);
      }
    } catch (error) {
      debugPrint('reschedule repayment reminders failed: $error');
    }
  }

  /// 设置里关闭开关：撤销全部已排还款提醒，不重新算。
  static Future<void> cancelAll() async {
    if (!isSupported) return;
    try {
      await _ensureInitialized();
      await _cancelScheduled();
    } catch (error) {
      debugPrint('cancel repayment reminders failed: $error');
    }
  }

  static Future<void> _scheduleOne(RepaymentReminderItem item) async {
    final scheduled = tz.TZDateTime.from(item.scheduledAt, tz.UTC);
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'feimiao_repayment_reminders',
        '还款提醒',
        channelDescription: '信用卡/贷款/借入还款日到期前提醒',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );
    await _notifications.zonedSchedule(
      id: item.notificationId,
      title: item.title,
      body: item.body,
      scheduledDate: scheduled,
      notificationDetails: details,
      // 不申请 SCHEDULE_EXACT_ALARM：inexact 允许在低电耗模式下有延迟，
      // 对「提醒」这种非精确到分钟的场景足够，也不用向用户要特权权限。
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: '$_payloadPrefix${item.profileId}',
    );
  }

  static Future<void> _cancelScheduled() async {
    final pending = await _notifications.pendingNotificationRequests();
    for (final req in pending) {
      if (req.payload?.startsWith(_payloadPrefix) ?? false) {
        await _notifications.cancel(id: req.id);
      }
    }
  }

  static Future<void> _ensurePermission() async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    final enabled = await android.areNotificationsEnabled();
    if (enabled != true) {
      await android.requestNotificationsPermission();
    }
  }

  static Future<void> _ensureInitialized() async {
    if (!_timeZoneInitialized) {
      tz_data.initializeTimeZones();
      _timeZoneInitialized = true;
    }
    if (_notificationsInitialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_feimiao'),
    );
    await _notifications.initialize(settings: settings);
    _notificationsInitialized = true;
  }
}
