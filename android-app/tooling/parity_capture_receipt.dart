import 'package:crypto/crypto.dart';

void validateCapturePath(Map<String, dynamic> receipt) {
  final name = receipt['name'];
  final path = receipt['path'];
  if (name is! String ||
      !RegExp(r'^[a-z0-9-]+$').hasMatch(name) ||
      path is! String ||
      !RegExp(r'^/data/(user/0|data)/com\.qingji\.qingji\.codex/cache/parity/[a-z0-9-]+\.png$')
          .hasMatch(path) ||
      !path.endsWith('/$name.png')) {
    throw StateError('Invalid capture receipt path');
  }
}

void validateCaptureReceipt(Map<String, dynamic> receipt, List<int> bytes) {
  validateCapturePath(receipt);
  if (bytes.isEmpty ||
      bytes.length != receipt['length'] ||
      sha256.convert(bytes).toString() != receipt['sha256']) {
    throw StateError('Capture receipt hash/length mismatch');
  }
}
