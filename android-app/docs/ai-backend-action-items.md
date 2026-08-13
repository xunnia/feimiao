# AI 后端优化行动清单

## 🔴 高优先级（本周完成）

### 1. 模型降级逻辑精确化
**文件**: `lib/core/ai/llm_query_v2.dart` (356-403 行)

**当前问题**:
```dart
// 当前：所有 400/404 都被当作"模型不支持"
if (code == 400 || code == 404) {
  if (message.toLowerCase().contains('token') && ...) {
    return AiTokenLimitException(...);
  }
  return AiModelNotSupportedException(...);  // 太宽泛
}
```

**修复方案**:
```dart
static AiException _exceptionFromStatusCode(int code, String body) {
  if (code == 400) {
    // 精确分类
    if (_isModelNotFoundError(body)) {
      return AiModelNotSupportedException(body, statusCode: code);
    }
    if (_isTokenLimitError(body)) {
      return AiTokenLimitException(body, statusCode: code);
    }
    if (_isInvalidParameterError(body)) {
      return AiBadRequestException(body, statusCode: code);
    }
    return AiUnknownException(body, statusCode: code);
  }
  
  if (code == 404) {
    if (_isModelNotFoundError(body)) {
      return AiModelNotSupportedException(body, statusCode: code);
    }
    return AiUnknownException('Resource not found', statusCode: code);
  }
  // ...
}

static bool _isModelNotFoundError(String body) {
  final lower = body.toLowerCase();
  return lower.contains('model') && 
         (lower.contains('not found') || 
          lower.contains('not supported') ||
          lower.contains('does not exist'));
}

static bool _isInvalidParameterError(String body) {
  final lower = body.toLowerCase();
  return lower.contains('invalid') || 
         lower.contains('required') ||
         lower.contains('missing');
}
```

**新增异常类** (`lib/core/ai/ai_exception.dart`):
```dart
/// 请求参数错误（不应降级重试）
class AiBadRequestException extends AiException {
  const AiBadRequestException(
    super.message, {
    super.statusCode,
    super.originalError,
  });

  @override
  bool get shouldRetry => false;
  
  @override
  String get userFacingMessage => '请求参数错误，请联系开发者';
}
```

---

### 2. 日志脱敏
**文件**: `lib/core/ai/ai_logger.dart`

**当前问题**: 错误消息可能包含用户数据直接打印

**修复方案**:
```dart
class AiLogger {
  // 在所有 log 方法中增加脱敏
  static void logQueryFailure({
    required String errorMessage,
    // ...
  }) {
    print(jsonEncode({
      'event': 'query_failure',
      'error_message': _sanitize(errorMessage),  // 脱敏
      // ...
    }));
  }
  
  static void logQuerySuccess({
    String? responsePreview,
    // ...
  }) {
    print(jsonEncode({
      'event': 'query_success',
      if (responsePreview != null) 
        'response_preview': _sanitize(responsePreview),
      // ...
    }));
  }
  
  /// 日志脱敏：移除手机号、身份证号、API Key
  static String _sanitize(String text) {
    return text
        // 手机号
        .replaceAllMapped(
          RegExp(r'(?<!\d)1[3-9]\d{9}(?!\d)'),
          (m) => '***PHONE***',
        )
        // 身份证号
        .replaceAllMapped(
          RegExp(r'\d{17}[\dXx]'),
          (m) => '***ID***',
        )
        // API Key 特征（Bearer token）
        .replaceAllMapped(
          RegExp(r'Bearer\s+[A-Za-z0-9_\-]{20,}'),
          (m) => 'Bearer ***',
        )
        // 通用长密钥（超过 16 位的连续字母数字）
        .replaceAllMapped(
          RegExp(r'[A-Za-z0-9_\-]{32,}'),
          (m) => '***KEY***',
        );
  }
}
```

---

### 3. API Key 保护
**文件**: `lib/core/ai/llm_query_v2.dart` (405-468 行)

**当前问题**: HTTP 异常可能泄露 headers 中的 API Key

**修复方案**:
```dart
static Future<String> _postChat({
  required AiProviderConfig config,
  required Map<String, dynamic> body,
  required int timeoutSeconds,
}) async {
  late http.Response resp;

  try {
    resp = await http.post(
      config.chatCompletionsUri,
      headers: {
        'Authorization': 'Bearer ${config.apiKey}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    ).timeout(Duration(seconds: timeoutSeconds));
  } on TimeoutException catch (e) {
    throw const AiNetworkException('请求超时');
  } catch (e) {
    // 清理异常消息中的 API Key
    final sanitized = _sanitizeException(e, config.apiKey);
    throw AiNetworkException('网络请求失败: $sanitized');
  }
  
  // ...
}

/// 清理异常消息中的敏感信息
static String _sanitizeException(Object error, String apiKey) {
  final message = error.toString();
  
  // 移除完整 API Key
  var sanitized = message.replaceAll(apiKey, '***');
  
  // 移除 Bearer 格式
  sanitized = sanitized.replaceAll(
    RegExp(r'Bearer\s+[A-Za-z0-9_\-]{20,}'),
    'Bearer ***',
  );
  
  return sanitized;
}

// 同样应用到 _postResponses 和 _streamChat
```

---

### 4. 补充核心测试
**新建文件**: `test/core/ai/llm_query_v2_test.dart`

**测试场景**:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xunni_codex/core/ai/llm_query_v2.dart';
import 'package:xunni_codex/core/ai/ai_exception.dart';

void main() {
  group('LlmQueryV2 - 模型降级', () {
    test('模型不支持时应该降级到下一个模型', () async {
      // 模拟 404 返回 model not found
      // 验证：尝试第二个模型
    });
    
    test('参数错误时不应该降级', () async {
      // 模拟 400 返回 invalid parameter
      // 验证：抛出 AiBadRequestException，不尝试第二个模型
    });
    
    test('所有模型失败后应该抛出最后的错误', () async {
      // 验证：不会无限重试
    });
  });
  
  group('LlmQueryV2 - 错误分类', () {
    test('应该正确识别 token 超限', () {
      final exception = AiRequestManager.wrapException(
        Exception('token limit exceeded'),
        statusCode: 400,
      );
      expect(exception, isA<AiTokenLimitException>());
    });
    
    test('应该正确识别模型不支持', () {
      final exception = AiRequestManager.wrapException(
        Exception('model not found'),
        statusCode: 404,
      );
      expect(exception, isA<AiModelNotSupportedException>());
    });
    
    test('应该正确识别参数错误', () {
      final exception = AiRequestManager.wrapException(
        Exception('invalid parameter: temperature'),
        statusCode: 400,
      );
      expect(exception, isA<AiBadRequestException>());
    });
  });
}
```

**新建文件**: `test/core/ai/ai_request_manager_test.dart`

**测试场景**:
```dart
void main() {
  group('AiRequestManager - 并发控制', () {
    test('同一 taskId 的新请求应该取消旧请求', () async {
      // 验证：旧请求被取消，新请求执行
    });
    
    test('allowConcurrent=true 时不应该取消旧请求', () async {
      // 验证：两个请求都执行
    });
  });
  
  group('AiRequestManager - 重试', () {
    test('shouldRetry=true 时应该重试', () async {
      var attempts = 0;
      await AiRequestManager.retryWithBackoff(
        request: () async {
          attempts++;
          if (attempts < 3) throw AiNetworkException('timeout');
          return 'success';
        },
        maxRetries: 3,
      );
      expect(attempts, 3);
    });
    
    test('shouldRetry=false 时不应该重试', () async {
      var attempts = 0;
      expect(
        () => AiRequestManager.retryWithBackoff(
          request: () async {
            attempts++;
            throw AiBadRequestException('invalid');
          },
          maxRetries: 3,
        ),
        throwsA(isA<AiBadRequestException>()),
      );
      expect(attempts, 1);
    });
  });
}
```

---

## 🟡 中优先级（本月完成）

### 5. 流式响应错误日志
**文件**: `lib/core/ai/llm_query_v2.dart` (529-531 行)

**当前问题**: 解析错误静默失败

**修复方案**:
```dart
try {
  final json = jsonDecode(data) as Map<String, dynamic>;
  final delta = json['choices']?[0]?['delta'];
  final content = delta?['content'] as String?;

  if (content != null && content.isNotEmpty) {
    fullAnswer.write(content);
    onChunk(content);
  }
} catch (e) {
  // 记录异常，但继续处理
  AiLogger.logWarning(
    taskType: 'stream_parse_error',
    provider: config.providerLabel,
    model: body['model'] as String,
    errorMessage: 'Failed to parse SSE chunk: $data',
    errorDetail: e.toString(),
  );
}
```

**同时增加日志方法** (`lib/core/ai/ai_logger.dart`):
```dart
static void logWarning({
  required String taskType,
  required String provider,
  required String model,
  required String errorMessage,
  String? errorDetail,
}) {
  print(jsonEncode({
    'timestamp': DateTime.now().toIso8601String(),
    'level': 'WARN',
    'event': 'ai_warning',
    'task_type': taskType,
    'provider': provider,
    'model': model,
    'error_message': _sanitize(errorMessage),
    if (errorDetail != null) 'error_detail': _sanitize(errorDetail),
  }));
}
```

---

### 6. 重试逻辑增强
**文件**: `lib/core/ai/ai_request_manager.dart` (61-86 行)

**修复方案**:
```dart
static Future<T> retryWithBackoff<T>({
  required Future<T> Function() request,
  int maxRetries = 3,
  Duration initialDelay = const Duration(seconds: 1),
  bool Function(Object error)? shouldRetry,
  String? taskType,  // 新增：用于日志
  String? provider,  // 新增
}) async {
  var retryCount = 0;
  var delay = initialDelay;

  while (true) {
    try {
      return await request();
    } catch (e) {
      if (retryCount >= maxRetries) {
        // 最后一次失败，记录放弃
        if (taskType != null) {
          AiLogger.logWarning(
            taskType: taskType,
            provider: provider ?? 'unknown',
            model: '',
            errorMessage: 'Max retries reached, giving up',
            errorDetail: e.toString(),
          );
        }
        rethrow;
      }

      final canRetry = shouldRetry?.call(e) ??
          (e is AiException && e.shouldRetry);

      if (!canRetry) rethrow;

      retryCount++;
      
      // 记录重试
      if (taskType != null) {
        AiLogger.logRetry(
          taskType: taskType,
          provider: provider ?? 'unknown',
          fromModel: '',
          toModel: '',
          reason: 'Attempt $retryCount/$maxRetries after ${delay.inSeconds}s delay',
        );
      }
      
      await Future.delayed(delay);
      delay *= 2;
    }
  }
}
```

---

### 7. 异常友好化
**文件**: `lib/core/ai/ai_exception.dart`

**修复方案**:
```dart
abstract class AiException implements Exception {
  const AiException(
    this.message, {
    this.statusCode,
    this.originalError,
  });

  final String message;
  final int? statusCode;
  final Object? originalError;

  bool get shouldRetry => false;

  /// 开发者看的详细错误
  String get message;

  /// 用户看的友好描述
  String get userFacingMessage => message;
  
  /// 可选的操作建议
  String? get actionHint => null;
}

class AiNetworkException extends AiException {
  const AiNetworkException(super.message, {super.originalError});

  @override
  bool get shouldRetry => true;

  @override
  String get userFacingMessage => '网络连接失败';
  
  @override
  String get actionHint => '请检查网络设置后重试';
}

class AiRateLimitException extends AiException {
  const AiRateLimitException(
    super.message, {
    super.statusCode,
    this.retryAfterSeconds,
  });

  final int? retryAfterSeconds;

  @override
  bool get shouldRetry => true;

  @override
  String get userFacingMessage {
    if (retryAfterSeconds != null && retryAfterSeconds! > 0) {
      return '请求过于频繁，请 $retryAfterSeconds 秒后重试';
    }
    return '请求过于频繁，请稍后重试';
  }
  
  @override
  String get actionHint => '系统会自动重试';
}

class AiAuthException extends AiException {
  const AiAuthException(super.message, {super.statusCode});

  @override
  String get userFacingMessage => 'API 密钥无效';
  
  @override
  String get actionHint => '请在设置中检查 AI 配置';
}

class AiTokenLimitException extends AiException {
  const AiTokenLimitException(super.message, {super.statusCode});

  @override
  String get userFacingMessage => '数据量过大，超出 AI 处理限制';
  
  @override
  String get actionHint => '请尝试缩小查询范围或时间段';
}

class AiBadRequestException extends AiException {
  const AiBadRequestException(super.message, {super.statusCode, super.originalError});

  @override
  bool get shouldRetry => false;

  @override
  String get userFacingMessage => '请求参数错误';
  
  @override
  String get actionHint => '这是应用程序错误，请联系开发者';
}
```

**UI 使用示例**:
```dart
try {
  await LlmQueryV2.queryText(...);
} on AiException catch (e) {
  // 显示友好错误
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('操作失败'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(e.userFacingMessage),
          if (e.actionHint != null) ...[
            SizedBox(height: 8),
            Text(
              e.actionHint!,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('确定'),
        ),
      ],
    ),
  );
  
  // 后台记录详细错误
  AiLogger.logQueryFailure(
    taskType: 'user_query',
    provider: 'deepseek',
    model: 'deepseek-chat',
    errorType: e.runtimeType.toString(),
    errorMessage: e.message,  // 详细的开发者信息
    durationMs: 0,
    statusCode: e.statusCode,
  );
}
```

---

### 8. 备注脱敏边界优化
**文件**: `lib/core/ai/ai_data_trimmer.dart` (127-143 行)

**当前问题**: 可能误伤订单号中的 11 位数字

**修复方案**:
```dart
/// 备注脱敏：去掉手机号、身份证号
static String _sanitizeNote(String note) {
  var sanitized = note;

  // 手机号脱敏：前后不能有数字（避免误伤订单号）
  sanitized = sanitized.replaceAllMapped(
    RegExp(r'(?<!\d)1[3-9]\d{9}(?!\d)'),
    (m) => '${m.group(0)!.substring(0, 3)}****${m.group(0)!.substring(7)}',
  );

  // 身份证号脱敏：前6后4
  sanitized = sanitized.replaceAllMapped(
    RegExp(r'(?<!\d)\d{17}[\dXx](?!\d)'),  // 同样增加边界
    (m) => '${m.group(0)!.substring(0, 6)}********${m.group(0)!.substring(14)}',
  );

  // 截断长度（保留原逻辑）
  return sanitized.length > 50 
      ? '${sanitized.substring(0, 50)}...' 
      : sanitized;
}
```

**增加单测** (`test/core/ai/ai_data_trimmer_test.dart`):
```dart
test('_sanitizeNote 不应该误伤订单号', () {
  // 订单号中包含 11 位数字
  final note = '订单号202501381234567890';
  final record = TransactionRecord(
    id: '99',
    date: DateTime.now(),
    kind: TransactionKind.expense,
    amount: Decimal.fromInt(10000),
    currencyCode: 'CNY',
    categoryName: '食品餐饮',
    note: note,
    accountId: 1,
  );

  final trimmed = AiDataTrimmer.trimForMonthlyAnalysis(
    allRecords: [record],
    year: record.date.year,
    month: record.date.month,
  );

  // 验证：订单号中的数字不应该被脱敏
  expect(trimmed.first['note'], '订单号202501381234567890');
});

test('_sanitizeNote 应该脱敏独立的手机号', () {
  final note = '联系方式：13812345678';
  final record = TransactionRecord(
    id: '99',
    date: DateTime.now(),
    kind: TransactionKind.expense,
    amount: Decimal.fromInt(10000),
    currencyCode: 'CNY',
    categoryName: '食品餐饮',
    note: note,
    accountId: 1,
  );

  final trimmed = AiDataTrimmer.trimForMonthlyAnalysis(
    allRecords: [record],
    year: record.date.year,
    month: record.date.month,
  );

  expect(trimmed.first['note'], '联系方式：138****5678');
});
```

---

## ⚪ 低优先级（长期优化）

### 9. 性能监控
**新建文件**: `lib/core/ai/ai_metrics.dart`

```dart
/// AI 性能指标收集器
class AiMetrics {
  static final _slowQueries = <String, List<int>>{};
  static final _tokenUsage = <String, int>{};
  static final _errorCounts = <String, int>{};
  
  /// 记录慢查询（> 10s）
  static void recordSlowQuery({
    required String taskType,
    required int durationMs,
  }) {
    if (durationMs > 10000) {
      _slowQueries.putIfAbsent(taskType, () => []).add(durationMs);
    }
  }
  
  /// 记录 token 使用
  static void recordTokenUsage({
    required String taskType,
    required int tokens,
  }) {
    _tokenUsage[taskType] = (_tokenUsage[taskType] ?? 0) + tokens;
  }
  
  /// 记录错误
  static void recordError({
    required String errorType,
  }) {
    _errorCounts[errorType] = (_errorCounts[errorType] ?? 0) + 1;
  }
  
  /// 获取汇总指标
  static Map<String, dynamic> getSummary() {
    return {
      'slow_queries': _slowQueries.map((k, v) => MapEntry(k, {
        'count': v.length,
        'avg_duration_ms': v.reduce((a, b) => a + b) ~/ v.length,
        'max_duration_ms': v.reduce((a, b) => a > b ? a : b),
      })),
      'token_usage': _tokenUsage,
      'error_counts': _errorCounts,
      'total_tokens': _tokenUsage.values.fold(0, (a, b) => a + b),
    };
  }
  
  /// 清空指标（用于测试或定期重置）
  static void reset() {
    _slowQueries.clear();
    _tokenUsage.clear();
    _errorCounts.clear();
  }
}
```

**集成到日志系统**:
```dart
// lib/core/ai/ai_logger.dart
static void logQuerySuccess({
  required int durationMs,
  int? totalTokens,
  // ...
}) {
  // 原有日志逻辑
  print(jsonEncode({...}));
  
  // 收集指标
  AiMetrics.recordSlowQuery(
    taskType: taskType,
    durationMs: durationMs,
  );
  
  if (totalTokens != null) {
    AiMetrics.recordTokenUsage(
      taskType: taskType,
      tokens: totalTokens,
    );
  }
}

static void logQueryFailure({
  required String errorType,
  // ...
}) {
  // 原有日志逻辑
  print(jsonEncode({...}));
  
  // 收集指标
  AiMetrics.recordError(errorType: errorType);
}
```

---

### 10. Token 估算改进
**文件**: `lib/core/ai/ai_data_trimmer.dart` (146-157 行)

**当前问题**: JSON 结构开销未计算

**改进方案**:
```dart
/// 估算 token 数（改进版）
static int estimateTokens(String text) {
  // 中文字符
  final chineseCount = RegExp(r'[一-龥]').allMatches(text).length;
  
  // 英文单词（按空格分割）
  final englishWords = text
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && RegExp(r'[a-zA-Z]').hasMatch(w))
      .length;
  
  // JSON 结构符号
  final jsonSymbols = RegExp(r'[{}[\]:,"]').allMatches(text).length;
  
  // 数字（连续数字视为一个 token）
  final numbers = RegExp(r'\d+').allMatches(text).length;
  
  // 标点符号
  final punctuation = RegExp(r'[。，、；：！？（）《》【】]').allMatches(text).length;
  
  return (
    chineseCount * 2.0 +      // 中文 1 字 ≈ 2 token
    englishWords * 1.3 +      // 英文 1 词 ≈ 1.3 token
    jsonSymbols * 0.5 +       // JSON 符号 ≈ 0.5 token
    numbers * 0.8 +           // 数字 ≈ 0.8 token
    punctuation * 0.5         // 标点 ≈ 0.5 token
  ).round();
}

/// 更精确的数据 token 估算（直接序列化再估算）
static int estimateDataTokens(List<Map<String, dynamic>> data) {
  final json = const JsonEncoder().convert(data);
  return estimateTokens(json);
}
```

---

## 📊 进度追踪

| 任务 | 优先级 | 预计工时 | 状态 | 负责人 |
|------|--------|----------|------|--------|
| 1. 模型降级逻辑精确化 | 🔴 高 | 3h | ⬜ 待开始 | - |
| 2. 日志脱敏 | 🔴 高 | 2h | ⬜ 待开始 | - |
| 3. API Key 保护 | 🔴 高 | 1h | ⬜ 待开始 | - |
| 4. 补充核心测试 | 🔴 高 | 4h | ⬜ 待开始 | - |
| 5. 流式响应错误日志 | 🟡 中 | 1h | ⬜ 待开始 | - |
| 6. 重试逻辑增强 | 🟡 中 | 2h | ⬜ 待开始 | - |
| 7. 异常友好化 | 🟡 中 | 3h | ⬜ 待开始 | - |
| 8. 备注脱敏边界优化 | 🟡 中 | 1h | ⬜ 待开始 | - |
| 9. 性能监控 | ⚪ 低 | 3h | ⬜ 待开始 | - |
| 10. Token 估算改进 | ⚪ 低 | 1h | ⬜ 待开始 | - |

**总计**: 21 小时（约 3 个工作日）

---

## 🎯 本周目标

1. ✅ 完成所有 🔴 高优先级任务（10h）
2. ✅ 单测覆盖率达到 80%+
3. ✅ 无安全风险残留

---

_更新时间: 2025-01-XX_
_下次评审: 1 周后_
