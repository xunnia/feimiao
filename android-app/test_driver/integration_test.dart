import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

import '../tooling/opaque_parity_screenshot.dart';
import '../tooling/parity_capture_receipt.dart';

Future<void> _writeParityResponse(Map<String, dynamic>? data) async {
  final payload = data?['p0BusinessJson'];
  if (payload is! Map<String, dynamic>) {
    throw StateError('Android parity test did not return p0BusinessJson');
  }
  final directory = Directory('outputs/parity');
  await directory.create(recursive: true);
  final receipts = data?['screenshotFiles'];
  if (receipts is! List || receipts.isEmpty) {
    throw StateError('Missing screenshot file receipts');
  }
  final serial = Platform.environment['ANDROID_SERIAL'] ??
      Platform.environment['ANDROID_DEVICE_ID'];
  if (serial == null || serial.isEmpty) {
    throw StateError('Missing device serial');
  }
  for (final value in receipts) {
    final receipt = Map<String, dynamic>.from(value as Map);
    // Validate the app-private path before issuing any device command.
    validateCapturePath(receipt);
    final name = receipt['name'];
    final path = receipt['path'] as String;
    final result = await Process.run(
            'adb',
            [
              '-s',
              serial,
              'exec-out',
              'run-as',
              'com.qingji.qingji.codex',
              'cat',
              path,
            ],
            stdoutEncoding: null)
        .timeout(const Duration(seconds: 30));
    if (result.exitCode != 0) {
      throw StateError('ADB capture read failed: ${result.stderr}');
    }
    final bytes = result.stdout as List<int>;
    validateCaptureReceipt(receipt, bytes);
    await File('${directory.path}/$name.png').writeAsBytes(
      makeOpaqueParityScreenshot(bytes),
      flush: true,
    );
  }
  final file = File('${directory.path}/p0-business-android.json');
  const encoder = JsonEncoder.withIndent('  ');
  await file.writeAsString('${encoder.convert(payload)}\n', flush: true);
}

Future<void> main() async {
  await integrationDriver(
    responseDataCallback: _writeParityResponse,
    writeResponseOnFailure: false,
  );
}
