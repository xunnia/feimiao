import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureKeyStore {
  SecureKeyStore._();

  static const MethodChannel _channel = MethodChannel('feimiao/secure_store');
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(migrateWithBackup: true),
  );

  static Future<String?> read(String key) async {
    try {
      final value = await _storage.read(key: key);
      if (value != null && value.isNotEmpty) return value;
    } catch (_) {
      // Unsupported desktop test runners fall through to the legacy channel.
    }

    try {
      final legacy = await _channel.invokeMethod<String>('read', {'key': key});
      if (legacy == null || legacy.isEmpty) return null;
      try {
        await _storage.write(key: key, value: legacy);
        await _channel.invokeMethod<bool>('delete', {'key': key});
      } catch (_) {
        // Keep the legacy encrypted value when migration cannot be completed.
      }
      return legacy;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on FlutterError {
      return null;
    }
  }

  static Future<bool> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
      try {
        await _channel.invokeMethod<bool>('delete', {'key': key});
      } catch (_) {}
      return true;
    } catch (_) {
      // Fall back to the app's original Android Keystore bridge.
    }
    try {
      return await _channel.invokeMethod<bool>(
            'write',
            {'key': key, 'value': value},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } on FlutterError {
      return false;
    }
  }

  static Future<bool> delete(String key) async {
    var deleted = false;
    try {
      await _storage.delete(key: key);
      deleted = true;
    } catch (_) {}
    try {
      final legacyDeleted =
          await _channel.invokeMethod<bool>('delete', {'key': key}) ?? false;
      return deleted || legacyDeleted;
    } on MissingPluginException {
      return deleted;
    } on PlatformException {
      return deleted;
    } on FlutterError {
      return deleted;
    }
  }
}
