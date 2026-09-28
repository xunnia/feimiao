import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

class CaptureReceiptMismatch extends StateError {
  CaptureReceiptMismatch(super.message);
}

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
  final actualHash = sha256.convert(bytes).toString();
  if (bytes.isEmpty ||
      bytes.length != receipt['length'] ||
      actualHash != receipt['sha256']) {
    throw CaptureReceiptMismatch(
      'Capture receipt hash/length mismatch: name=${receipt['name']} '
      'expectedLength=${receipt['length']} actualLength=${bytes.length} '
      'expectedHash=${receipt['sha256']} actualHash=$actualHash',
    );
  }
}

Future<List<int>> readValidatedCaptureReceipt(
  Map<String, dynamic> receipt,
  Future<List<int>> Function(int attempt) readBytes, {
  int maxAttempts = 3,
  Duration retryDelay = const Duration(milliseconds: 300),
  void Function(int attempt, Object error)? onRetry,
}) async {
  validateCapturePath(receipt);
  if (maxAttempts < 1) throw ArgumentError.value(maxAttempts, 'maxAttempts');
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      final bytes = await readBytes(attempt);
      validateCaptureReceipt(receipt, bytes);
      return bytes;
    } catch (error) {
      if (attempt == maxAttempts ||
          (error is! CaptureReceiptMismatch &&
              error is! ProcessException &&
              error is! TimeoutException)) {
        rethrow;
      }
      onRetry?.call(attempt, error);
      await Future<void>.delayed(retryDelay);
    }
  }
  throw StateError('Capture read exhausted');
}
