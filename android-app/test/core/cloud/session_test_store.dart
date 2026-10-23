import 'package:qingji/core/cloud/cloud_session_guard.dart';
import 'package:qingji/core/cloud/cloud_session_store.dart';

final _guards = Expando<MemoryCloudSessionGuard>();

/// Recreating the session store simulates a restart while retaining logout
/// intent independently of the fake credential store's read/write failures.
CloudSessionStore testSessionStore(CloudSecretStore secrets) =>
    CloudSessionStore(
      store: secrets,
      guard: _guards[secrets] ??= MemoryCloudSessionGuard(),
    );
