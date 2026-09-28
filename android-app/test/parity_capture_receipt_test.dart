import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tooling/parity_capture_receipt.dart';

void main() {
  final bytes = [1, 2, 3];
  Map<String, dynamic> receipt() => {
        'name': 'ai-tasks-android',
        'path':
            '/data/user/0/com.qingji.qingji.codex/cache/parity/ai-tasks-android.png',
        'length': 3,
        'sha256': sha256.convert(bytes).toString(),
      };
  test('accepts exact bytes and private capture path', () {
    validateCaptureReceipt(receipt(), bytes);
  });
  test('rejects altered bytes', () {
    expect(
        () => validateCaptureReceipt(receipt(), [1, 2, 4]), throwsStateError);
  });
  test('rejects truncated data', () {
    expect(() => validateCaptureReceipt(receipt(), [1]), throwsStateError);
  });
  test('diagnostic identifies the mismatched capture and byte lengths', () {
    expect(
        () => validateCaptureReceipt(receipt(), [1]),
        throwsA(isA<CaptureReceiptMismatch>().having(
          (error) => error.message,
          'message',
          contains('expectedLength=3 actualLength=1'),
        )));
  });
  test('retries truncated read and accepts only exact verified bytes',
      () async {
    var reads = 0;
    final actual = await readValidatedCaptureReceipt(receipt(), (_) async {
      reads++;
      return reads == 1 ? [1] : bytes;
    }, retryDelay: Duration.zero);
    expect(actual, bytes);
    expect(reads, 2);
  });
  test('persistent mismatch fails after bounded reads', () async {
    var reads = 0;
    await expectLater(
        readValidatedCaptureReceipt(receipt(), (_) async {
          reads++;
          return [1, 2, 4];
        }, retryDelay: Duration.zero),
        throwsA(isA<CaptureReceiptMismatch>()));
    expect(reads, 3);
  });
  test('text transport roundtrip still requires the original receipt',
      () async {
    final actual =
        await readValidatedCaptureReceipt(receipt(), (attempt) async {
      if (attempt < 3) return [1];
      return base64.decode(base64.encode(bytes));
    }, retryDelay: Duration.zero);
    expect(actual, bytes);
  });
  test('retries bounded ADB failures and timeouts', () async {
    final actual =
        await readValidatedCaptureReceipt(receipt(), (attempt) async {
      if (attempt == 1) {
        throw const ProcessException('adb', [], 'device offline', 1);
      }
      if (attempt == 2) throw TimeoutException('read timeout');
      return bytes;
    }, retryDelay: Duration.zero);
    expect(actual, bytes);
  });
  test('invalid path is rejected before reading', () async {
    var reads = 0;
    await expectLater(
        readValidatedCaptureReceipt(
            receipt()..['path'] = '/data/local/tmp/x.png', (_) async {
          reads++;
          return bytes;
        }, retryDelay: Duration.zero),
        throwsStateError);
    expect(reads, 0);
  });
  test('unrelated reader failure is not retried', () async {
    var reads = 0;
    await expectLater(
        readValidatedCaptureReceipt(receipt(), (_) async {
          reads++;
          throw StateError('unexpected data');
        }, retryDelay: Duration.zero),
        throwsStateError);
    expect(reads, 1);
  });
  test('rejects path traversal and mismatched names', () {
    for (final path in [
      '/data/local/tmp/x.png',
      '/data/user/0/com.qingji.qingji.codex/cache/parity/../x.png',
      '/data/user/0/com.qingji.qingji.codex/cache/parity/other.png'
    ]) {
      expect(() => validateCapturePath(receipt()..['path'] = path),
          throwsStateError);
    }
  });
}
