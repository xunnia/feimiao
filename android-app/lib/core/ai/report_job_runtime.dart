import 'package:flutter/foundation.dart';

/// Process-local coordination for persisted report jobs.
///
/// The database is the source of truth across process restarts. This class only
/// prevents two screens in the same process from executing one job twice and
/// gives an open chat panel a lightweight completion signal.
class ReportJobRuntime {
  ReportJobRuntime._();

  static final Set<int> _activeIds = <int>{};
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static bool isActive(int id) => _activeIds.contains(id);

  static bool claim(int id) => _activeIds.add(id);

  static void release(int id) {
    if (_activeIds.remove(id)) revision.value++;
  }
}
