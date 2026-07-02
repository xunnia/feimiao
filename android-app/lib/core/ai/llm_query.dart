import 'dart:convert';

import 'package:http/http.dart' as http;

/// 查账问答：把账目数据 + 用户问题发给 DeepSeek，返回一段口语化回答。
///
/// 与 [LlmEntryParser] 共用 DeepSeek OpenAI 兼容接口，但这里要的是自由文本回答
/// （非 JSON），用于「喵助手」的查账 / 消费分析。
class LlmQuery {
  LlmQuery._();

  static const _endpoint = 'https://api.deepseek.com/chat/completions';
  static const _model = 'deepseek-chat';
  static const _timeoutSeconds = 30;

  /// 根据 [transactionsText]（账目上下文）回答 [question]。
  /// 失败抛 [LlmQueryException]。
  static Future<String> ask({
    required String question,
    required String apiKey,
    required String transactionsText,
  }) async {
    final systemPrompt =
        '''你是「喵助手」，一只蓝白英短猫记账助理。根据下面的账目数据回答用户的问题。
要求：口语化、简短亲切、可以带一点猫咪语气（偶尔用「喵」）；涉及金额要给具体数字（单位元）；
算不出或数据里没有就如实说不知道，绝不编造。

排版（对齐 Claude 的可读性）：
- 关键结论和重要数字用 **双星号加粗**（如 **¥128.50**、**餐饮**）；
- 并列的多条信息用「- 」开头分行列出；
- 段落要短（一两句一段），别一大坨文字；
- 只允许加粗和「- 」列表这两种 Markdown，不要表格、标题、引用等其它语法。

$transactionsText''';

    final body = jsonEncode({
      'model': _model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': question},
      ],
      'stream': false,
    });

    late http.Response resp;
    try {
      resp = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: _timeoutSeconds));
    } catch (e) {
      throw LlmQueryException('网络请求失败：$e');
    }

    if (resp.statusCode != 200) {
      throw LlmQueryException('DeepSeek 返回错误 ${resp.statusCode}');
    }

    try {
      final outer = jsonDecode(resp.body) as Map<String, dynamic>;
      final content =
          (outer['choices'] as List).first['message']['content'] as String;
      final text = content.trim();
      if (text.isEmpty) throw const LlmQueryException('空回答');
      return text;
    } catch (e) {
      throw LlmQueryException('响应解析失败：$e');
    }
  }
}

class LlmQueryException implements Exception {
  final String message;
  const LlmQueryException(this.message);
  @override
  String toString() => 'LlmQueryException: $message';
}
