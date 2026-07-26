import 'package:flutter/foundation.dart';

/// Process-local coordination for persisted report jobs.
///
/// The database is the source of truth across process restarts. This class only
/// prevents two screens in the same process from executing one job twice and
/// gives an open chat panel a lightweight completion signal.
class ReportJobRuntime {
  ReportJobRuntime._();

  static final Set<String> _activeKeys = <String>{};
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static bool isActive(String key) => _activeKeys.contains(key);

  static bool claim(String key) => _activeKeys.add(key);

  static void release(String key) {
    if (_activeKeys.remove(key)) revision.value++;
  }
}
