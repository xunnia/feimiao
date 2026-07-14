import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeWidgetBridge {
  NativeWidgetBridge._();

  static const MethodChannel _channel = MethodChannel('feimiao/widget');

  static Future<bool> saveSnapshot(Map<String, Object?> snapshot) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        'saveSnapshot',
        {'snapshot': jsonEncode(snapshot)},
      );
      return ok ?? false;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('saveSnapshot failed: $error');
        debugPrint('$stackTrace');
      }
      return false;
    }
  }

  static Future<bool> requestUpdate() async {
    try {
      final ok = await _channel.invokeMethod<bool>('requestUpdate');
      return ok ?? false;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('requestUpdate failed: $error');
        debugPrint('$stackTrace');
      }
      return false;
    }
  }
}
