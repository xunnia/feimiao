import 'dart:convert';
import 'package:http/http.dart' as http;

/// AI 模型信息
class AiModelInfo {
  final String id;
  final String? ownedBy;
  final int? created;

  const AiModelInfo({
    required this.id,
    this.ownedBy,
    this.created,
  });

  factory AiModelInfo.fromJson(Map<String, dynamic> json) {
    return AiModelInfo(
      id: json['id'] as String,
      ownedBy: json['owned_by'] as String?,
      created: json['created'] as int?,
    );
  }
}

/// AI 模型获取异常
class AiModelFetchException implements Exception {
  final String message;
  const AiModelFetchException(this.message);

  @override
  String toString() => message;
}

/// AI 模型获取器
class AiModelFetcher {
  /// 从 OpenAI 兼容的 API 获取可用模型列表
  static Future<List<AiModelInfo>> fetchAvailableModels({
    required String baseUrl,
    required String apiKey,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final uri = _buildModelsUri(baseUrl);
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      ).timeout(timeout);

      if (response.statusCode == 401) {
        throw const AiModelFetchException('API Key 无效或已过期');
      }

      if (response.statusCode == 403) {
        throw const AiModelFetchException('无权限访问该接口');
      }

      if (response.statusCode == 404) {
        throw const AiModelFetchException('接口不存在，请检查 Base URL 是否正确');
      }

      if (response.statusCode != 200) {
        throw AiModelFetchException('请求失败 (${response.statusCode})');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = json['data'];

      if (data == null) {
        throw const AiModelFetchException('响应格式错误：缺少 data 字段');
      }

      if (data is! List) {
        throw const AiModelFetchException('响应格式错误：data 不是数组');
      }

      final models = <AiModelInfo>[];
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          try {
            models.add(AiModelInfo.fromJson(item));
          } catch (_) {
            // 跳过解析失败的模型
          }
        }
      }

      if (models.isEmpty) {
        throw const AiModelFetchException('未获取到任何模型');
      }

      return models;
    } on AiModelFetchException {
      rethrow;
    } on http.ClientException {
      throw const AiModelFetchException('网络连接失败，请检查网络');
    } on FormatException {
      throw const AiModelFetchException('响应格式错误，不是有效的 JSON');
    } catch (e) {
      throw AiModelFetchException('未知错误：$e');
    }
  }

  /// 构建 /v1/models 接口 URI
  static Uri _buildModelsUri(String baseUrl) {
    var raw = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

    // 如果已经以 /v1 结尾，直接拼接 /models
    if (raw.endsWith('/v1')) {
      return Uri.parse('$raw/models');
    }

    // 否则拼接 /v1/models
    return Uri.parse('$raw/v1/models');
  }
}
