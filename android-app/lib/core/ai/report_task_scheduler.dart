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
      // 隐私闸门：用户没同意 AI 隐私说明时，后台绝不把账本上下文发出去。
      // 任务保持排队（不标失败、不弹 UI），等用户在前台确认后由面板续跑。
      if (!repo.aiPrivacyAccepted) return true;
      final job = await repo.guardReportGeneration(
        lease,
        () => repo.reportJobById(jobId),
      );
      if (job == null || job.status == 'completed' || job.status == 'failed') {
        return true;
      }
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
