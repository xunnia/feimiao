import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/share_intake.dart';

void main() {
  testWidgets(
      'failed startup retains queued opens until recovery without spinning',
      (tester) async {
    var ready = false;
    ShareIntake.init(
        repositoryReady: Future<void>.value(),
        repositoryReadyCheck: () => ready);
    await tester.pumpWidget(MaterialApp(
        navigatorKey: ShareIntake.navigatorKey, home: const SizedBox()));
    final reply = Completer<void>();
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'feimiao/share',
      const StandardMethodCodec()
          .encodeMethodCall(const MethodCall('onOpen', {'target': 'unknown'})),
      (_) => reply.complete(),
    );
    await tester.pump();
    await reply.future;
    expect(ShareIntake.pendingActionCount, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(ShareIntake.pendingActionCount, 1);
    ready = true;
    ShareIntake.resumePendingAfterRecovery();
    await tester.pump();
    expect(ShareIntake.pendingActionCount, 0);
    ShareIntake.resumePendingAfterRecovery();
    await tester.pump();
    expect(ShareIntake.pendingActionCount, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
