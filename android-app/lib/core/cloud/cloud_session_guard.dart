import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Non-secret logout intent, independent of the credential store. A failed
/// Keystore deletion must not make an old login restorable after a restart.
abstract class CloudSessionGuard {
  Future<bool> isBlocked();
  Future<void> setBlocked(bool blocked);
}

class FileCloudSessionGuard implements CloudSessionGuard {
  FileCloudSessionGuard({Future<Directory> Function()? directory})
      : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  Future<File> _file() async =>
      File(p.join((await _directory()).path, 'cloud-session-signed-out-v1'));

  @override
  Future<bool> isBlocked() async => (await _file()).exists();

  @override
  Future<void> setBlocked(bool blocked) async {
    final file = await _file();
    if (blocked) {
      await file.parent.create(recursive: true);
      // Existence alone blocks restore, even if writing is interrupted. This
      // file never holds a token, account identifier or any ledger data.
      await file.writeAsString('signed-out', flush: true);
    } else if (await file.exists()) {
      await file.delete();
    }
  }
}

class MemoryCloudSessionGuard implements CloudSessionGuard {
  bool blocked = false;

  @override
  Future<bool> isBlocked() async => blocked;

  @override
  Future<void> setBlocked(bool value) async => blocked = value;
}
