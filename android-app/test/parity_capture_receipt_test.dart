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
