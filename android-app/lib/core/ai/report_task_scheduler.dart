import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import '../../data/app_repository.dart';
import 'report_execution_fence.dart';
import 'report_generation_service.dart';

const String _reportWorkerTask = 'feimiao.generate_report';
const String _reportWorkerTag = 'feimiao-report';

@pragma('vm:entry-point')
void reportWorkerCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    DartPluginRegistrant.ensureInitialized();
    if (task != _reportWorkerTask) return true;
    final lease = ReportGenerationLease.tryFromWorkerInput(inputData);
    if (lease == null) return true;
    final jobId = lease.jobId!;

    final repo = AppRepository();
    var repoReady = false;
    try {
      // Opening the live SQLite file must not overlap a restore replacement.
      await lease.guard(
        repo.init,
        readJobUuid: (_) async => lease.jobUuid,
      );
      repoReady = true;
      final job = await repo.guardReportGeneration(
        lease,
        () => repo.reportJobById(jobId),
      );
      if (job == null || job.status == 'completed' || job.status == 'failed') {
        return true;
      }
      // 隐私闸门：用户没同意当前任务实际接收方时，后台绝不把账本上下文发出去。
      // 任务保持排队（不标失败、不弹 UI），等用户在前台确认后由面板续跑。
      final config = repo.aiProviderConfigForReportJob(job);
      if (!repo.aiSkillAllowsTool('report_writer', 'read_ledger')) {
        return true;
      }
      if (config == null) return true;
      if (!repo.aiPrivacyAcceptedFor(config)) return true;
      final report = await ReportGenerationService.generate(
        repo,
        job,
        lease: lease,
      );
      await repo.guardReportGeneration(
        lease,
        () => ReportTaskScheduler.showCompletedNotification(
          jobId: job.id,
          reportId: report.id,
          title: report.title,
        ),
      );
      return true;
    } on ReportGenerationInvalidated {
      // A restore committed a different database generation. This stale work
      // must finish successfully without touching or retrying against it.
      return true;
    } on ReportJobConfigurationUnavailable {
      // The captured provider/model is unavailable. Keep the job queued until
      // the user repairs that exact account instead of retrying another one.
      return true;
    } catch (error) {
      // Database/plugin startup failures are transient. Returning success here
      // would leave the persisted job queued forever with no future worker.
      if (!repoReady) return false;
      ReportJobEntity? job;
      try {
        job = await repo.guardReportGeneration(
          lease,
          () => repo.reportJobById(jobId),
        );
      } on ReportGenerationInvalidated {
        return true;
      } catch (_) {
        return false;
      }
      if (job == null || job.status == 'completed' || job.status == 'failed') {
        return true;
      }
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(job.createdMs),
      );
      if (age >= const Duration(hours: 24)) {
        try {
          await repo.guardReportGeneration(
            lease,
            () => repo.updateReportJob(
              jobId,
              expectedUuid: job!.uuid,
              status: 'failed',
              error: '后台生成多次失败：$error',
            ),
          );
        } on ReportGenerationInvalidated {
          return true;
        }
        return true;
      }
      try {
        await repo.guardReportGeneration(
          lease,
          () => repo.updateReportJob(
            jobId,
            expectedUuid: job!.uuid,
            status: 'queued',
            error: '等待后台重试：$error',
          ),
        );
      } on ReportGenerationInvalidated {
        return true;
      }
      return false;
    }
  });
}

class ReportTaskScheduler {
  ReportTaskScheduler._();

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _notificationsInitialized = false;

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static String _uniqueName(String jobUuid) => 'feimiao-report-$jobUuid';

  static Future<bool> initialize() async {
    if (!isSupported) return false;
    if (_initialized) return true;
    try {
      await Workmanager().initialize(reportWorkerCallbackDispatcher);
      _initialized = true;
    } catch (error) {
      debugPrint('initialize report worker failed: $error');
      return false;
    }
    try {
      await _initializeNotifications();
    } catch (error) {
      // Notifications are optional; report persistence must still work.
      debugPrint('initialize report notifications failed: $error');
    }
    return true;
  }

  static Future<bool> schedule(
    AppRepository repo,
    ReportJobEntity job, {
    ReportGenerationLease? lease,
    bool requestNotificationPermission = true,
  }) async {
    if (!isSupported) return false;
    try {
      final executionLease = lease ??
          (await repo.acquireReportGenerationLease()).bind(
            jobId: job.id,
            jobUuid: job.uuid,
          );
      if (!executionLease.matchesJob(jobId: job.id, jobUuid: job.uuid)) {
        throw const ReportGenerationInvalidated('report job lease mismatch');
      }
      await repo.guardReportGeneration(executionLease, () async {});
      if (!await initialize()) return false;
      if (requestNotificationPermission) {
        await _notifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
      await Workmanager().registerOneOffTask(
        _uniqueName(job.uuid),
        _reportWorkerTask,
        inputData: executionLease.toWorkerInput(),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.keep,
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(seconds: 15),
        tag: _reportWorkerTag,
        outOfQuotaPolicy: OutOfQuotaPolicy.runAsNonExpeditedWorkRequest,
      );
      return true;
    } catch (error) {
      debugPrint('schedule report worker failed: $error');
      return false;
    }
  }

  static Future<void> reschedulePending(AppRepository repo) async {
    if (!isSupported) return;
    final jobs = await repo.pendingReportJobs();
    for (final job in jobs) {
      await schedule(
        repo,
        job,
        requestNotificationPermission: false,
      );
    }
  }

  /// Materialize due user-created schedules into the same durable report job
  /// queue used by foreground Chats. Each schedule is advanced only after its
  /// job is created, so opening the app twice cannot duplicate a report.
  static Future<void> scheduleDueAiReports(AppRepository repo) async {
    if (!isSupported) return;
    // Keep a due schedule due while the user has intentionally disabled the
    // report skill.  Once re-enabled, the next startup can materialize it
    // without losing the scheduled occurrence.
    if (!repo.aiSkillAllowsTool('report_writer', 'read_ledger')) return;
    final due = await repo.dueAiReportSchedules();
    final now = DateTime.now();
    for (final schedule in due) {
      final period = _schedulePeriod(schedule.periodKind, now);
      try {
        final job = await repo.createReportJobFromSchedule(
          schedule: schedule,
          periodStart: period.$1,
          periodEnd: period.$2,
          now: now,
        );
        if (job != null) await scheduleJobSilently(repo, job);
      } catch (error) {
        debugPrint('schedule due AI report failed: $error');
      }
    }
  }

  static Future<void> scheduleJobSilently(
    AppRepository repo,
    ReportJobEntity job,
  ) =>
      schedule(
        repo,
        job,
        requestNotificationPermission: false,
      );

  static (DateTime, DateTime) _schedulePeriod(String kind, DateTime now) {
    if (kind == 'weekly') {
      final currentMonday = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
      final start = currentMonday.subtract(const Duration(days: 7));
      // ReportGenerationService treats periodEnd as an inclusive civil day;
      // the previous week's last day is Sunday, not the current Monday.
      return (start, start.add(const Duration(days: 6)));
    }
    final start = DateTime(now.year, now.month, 1);
    final end = start.subtract(const Duration(milliseconds: 1));
    final previous = DateTime(start.year, start.month - 1, 1);
    return (previous, end);
  }

  @visibleForTesting
  static (DateTime, DateTime) schedulePeriodForTest(
    String kind,
    DateTime now,
  ) =>
      _schedulePeriod(kind, now);

  static Future<void> cancel(ReportJobEntity job) async {
    if (!isSupported) return;
    try {
      await Workmanager().cancelByUniqueName(_uniqueName(job.uuid));
    } catch (_) {}
  }

  static Future<void> showCompletedNotification({
    required int jobId,
    required int reportId,
    required String title,
  }) async {
    if (!isSupported) return;
    try {
      await _initializeNotifications();
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'feimiao_reports',
          '报告生成',
          channelDescription: '周报、月报和年报生成完成提醒',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      );
      await _notifications.show(
        id: 730000 + (jobId % 10000),
        title: '报告生成完成',
        body: title,
        notificationDetails: details,
        payload: 'report:$reportId',
      );
    } catch (error) {
      debugPrint('show report notification failed: $error');
    }
  }

  static Future<void> _initializeNotifications() async {
    if (_notificationsInitialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_feimiao'),
    );
    await _notifications.initialize(settings: settings);
    _notificationsInitialized = true;
  }
}
