import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

import '../tooling/opaque_parity_screenshot.dart';

Future<void> _writeParityResponse(Map<String, dynamic>? data) async {
  final payload = data?['p0BusinessJson'];
  if (payload is! Map<String, dynamic>) {
    throw StateError('Android parity test did not return p0BusinessJson');
  }
  final directory = Directory('outputs/parity');
  await directory.create(recursive: true);
  final file = File('${directory.path}/p0-business-android.json');
  const encoder = JsonEncoder.withIndent('  ');
  await file.writeAsString('${encoder.convert(payload)}\n', flush: true);
}

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (
      String screenshotName,
      List<int> screenshotBytes, [
      Map<String, Object?>? args,
    ]) async {
      final directory = Directory('outputs/parity');
      await directory.create(recursive: true);
      final image = File('${directory.path}/$screenshotName.png');
      final opaqueBytes = makeOpaqueParityScreenshot(screenshotBytes);
      await image.writeAsBytes(opaqueBytes, flush: true);
      return true;
    },
    responseDataCallback: _writeParityResponse,
    writeResponseOnFailure: true,
  );
}
