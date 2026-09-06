import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

import '../tooling/opaque_parity_screenshot.dart';

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
    writeResponseOnFailure: true,
  );
}
