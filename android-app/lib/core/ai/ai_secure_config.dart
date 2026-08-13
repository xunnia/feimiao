import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// AI 配置安全存储：使用平台 Keystore/Keychain 加密 API key。
///
/// Android: 使用 EncryptedSharedPreferences + Android Keystore
/// iOS: 使用 Keychain
class AiSecureConfig {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  static const _keyDeepSeekApiKey = 'ai_deepseek_api_key';
  static const _keyDeepSeekBaseUrl = 'ai_deepseek_base_url';
  static const _keyOpenAiApiKey = 'ai_openai_api_key';
  static const _keyOpenAiBaseUrl = 'ai_openai_base_url';
  static const _keySelectedProvider = 'ai_selected_provider';

  /// 读取 DeepSeek API Key
  static Future<String?> getDeepSeekApiKey() async {
    return _storage.read(key: _keyDeepSeekApiKey);
  }

  /// 保存 DeepSeek API Key
  static Future<void> setDeepSeekApiKey(String value) async {
    await _storage.write(key: _keyDeepSeekApiKey, value: value);
  }

  /// 删除 DeepSeek API Key
  static Future<void> deleteDeepSeekApiKey() async {
    await _storage.delete(key: _keyDeepSeekApiKey);
  }

  /// 读取 DeepSeek Base URL
  static Future<String?> getDeepSeekBaseUrl() async {
    return _storage.read(key: _keyDeepSeekBaseUrl);
  }

  /// 保存 DeepSeek Base URL
  static Future<void> setDeepSeekBaseUrl(String value) async {
    await _storage.write(key: _keyDeepSeekBaseUrl, value: value);
  }

  /// 删除 DeepSeek Base URL
  static Future<void> deleteDeepSeekBaseUrl() async {
    await _storage.delete(key: _keyDeepSeekBaseUrl);
  }

  /// 读取 OpenAI API Key
  static Future<String?> getOpenAiApiKey() async {
    return _storage.read(key: _keyOpenAiApiKey);
  }

  /// 保存 OpenAI API Key
  static Future<void> setOpenAiApiKey(String value) async {
    await _storage.write(key: _keyOpenAiApiKey, value: value);
  }

  /// 删除 OpenAI API Key
  static Future<void> deleteOpenAiApiKey() async {
    await _storage.delete(key: _keyOpenAiApiKey);
  }

  /// 读取 OpenAI Base URL
  static Future<String?> getOpenAiBaseUrl() async {
    return _storage.read(key: _keyOpenAiBaseUrl);
  }

  /// 保存 OpenAI Base URL
  static Future<void> setOpenAiBaseUrl(String value) async {
    await _storage.write(key: _keyOpenAiBaseUrl, value: value);
  }

  /// 删除 OpenAI Base URL
  static Future<void> deleteOpenAiBaseUrl() async {
    await _storage.delete(key: _keyOpenAiBaseUrl);
  }

  /// 读取当前选中的服务商（'deepseek' | 'openai'）
  static Future<String?> getSelectedProvider() async {
    return _storage.read(key: _keySelectedProvider);
  }

  /// 保存当前选中的服务商
  static Future<void> setSelectedProvider(String value) async {
    await _storage.write(key: _keySelectedProvider, value: value);
  }

  /// 检查 API 配置完整性
  static Future<bool> hasValidConfig() async {
    final provider = await getSelectedProvider();
    if (provider == 'deepseek') {
      final key = await getDeepSeekApiKey();
      return key != null && key.trim().isNotEmpty;
    } else if (provider == 'openai') {
      final key = await getOpenAiApiKey();
      return key != null && key.trim().isNotEmpty;
    }
    return false;
  }

  /// 清空所有 AI 配置
  static Future<void> clearAll() async {
    await Future.wait([
      _storage.delete(key: _keyDeepSeekApiKey),
      _storage.delete(key: _keyDeepSeekBaseUrl),
      _storage.delete(key: _keyOpenAiApiKey),
      _storage.delete(key: _keyOpenAiBaseUrl),
      _storage.delete(key: _keySelectedProvider),
    ]);
  }
}
