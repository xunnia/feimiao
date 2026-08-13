# AI 后端架构代码审查报告

## 1. 概览

### 模块结构
- **文件数量**: 27 个 Dart 文件
- **核心层次**: 配置层、请求层、业务层、工具层
- **测试覆盖**: 已有单测文件，覆盖核心逻辑

### 架构亮点
1. **清晰的分层**: 配置、请求管理、异常处理、业务逻辑分离
2. **可测试性**: 纯函数设计，依赖注入友好
3. **错误处理**: 统一的异常体系，分级重试策略
4. **数据裁剪**: 智能的 token 优化，避免浪费

---

## 2. 已发现并修复的问题

### ✅ TransactionRecord 构造器调用错误
**位置**: `test/core/ai/ai_data_trimmer_test.dart`

**问题**: 测试中使用了旧的构造器签名，传入了 `createdMs`、`updatedMs` 参数，但新模型已移除这些字段。

**修复**: 
```dart
// 修复前
final record = TransactionRecord(
  id: 99,
  createdMs: DateTime.now().millisecondsSinceEpoch,
  updatedMs: DateTime.now().millisecondsSinceEpoch,
);

// 修复后
final record = TransactionRecord(
  id: '99',  // 同时修正 id 类型为 String
  // 移除 createdMs/updatedMs
);
```

**状态**: ✅ 已修复并验证通过

---

## 3. 代码质量分析

### 3.1 配置层 (ai_provider_config.dart)

**优点**:
- 支持多提供商（DeepSeek、OpenAI）
- 模型降级策略（modelCandidates）
- Reasoning effort 配置灵活

**改进建议**:
```dart
// 当前设计依赖硬编码的工厂方法
class AiProviderConfig {
  factory AiProviderConfig.deepSeek({...}) { }
  factory AiProviderConfig.openAI({...}) { }
}

// 建议：支持运行时动态注册提供商
class AiProviderRegistry {
  static void register(String name, AiProviderConfig config) { }
  static AiProviderConfig? get(String name) { }
}
```

**优先级**: 中（当前方案足够，但扩展性受限）

---

### 3.2 请求层 (llm_query_v2.dart)

**优点**:
- 模型降级自动重试
- 流式/非流式统一接口
- Responses API 支持（支持推理模式）
- Token 使用统计

**潜在问题**:

#### 问题 A: 模型降级逻辑混淆业务意图
```dart
// 当前代码：356-403 行
for (int i = 0; i < models.length; i++) {
  try {
    return await _postChat(...);
  } catch (e) {
    if (i == models.length - 1) rethrow;
    if (lastError is! AiModelNotSupportedException) rethrow;
  }
}
```

**问题**: 
- 404/400 错误被广泛识别为 `AiModelNotSupportedException`
- 真正的请求错误（参数错误、格式错误）也会触发降级

**建议**: 
```dart
// 更精确的错误分类
static AiException _exceptionFromStatusCode(int code, String body) {
  if (code == 400) {
    if (_isModelNotFoundError(body)) {
      return AiModelNotSupportedException(...);
    }
    if (_isTokenLimitError(body)) {
      return AiTokenLimitException(...);
    }
    return AiBadRequestException(...); // 新增：参数错误不应降级
  }
}
```

**优先级**: 高（影响错误处理准确性）

---

#### 问题 B: 流式响应错误吞没
```dart
// 当前代码：529-531 行
try {
  final json = jsonDecode(data);
  // ...
} catch (e) {
  // 忽略单条解析错误，继续处理后续数据
}
```

**问题**: 
- 静默失败，调试困难
- 无法区分"正常的空 delta"和"格式错误"

**建议**:
```dart
} catch (e) {
  AiLogger.logWarning(
    taskType: 'stream_parse_error',
    message: 'Failed to parse SSE chunk: $data',
    error: e,
  );
  // 继续处理，但记录异常
}
```

**优先级**: 中（当前能工作，但可观测性差）

---

### 3.3 请求管理 (ai_request_manager.dart)

**优点**:
- 并发控制（自动取消旧请求）
- 指数退避重试
- 统一的异常转换

**潜在问题**:

#### 问题 C: 重试逻辑缺少上下文
```dart
// 当前代码：61-86 行
static Future<T> retryWithBackoff<T>({...}) async {
  while (true) {
    try {
      return await request();
    } catch (e) {
      // 没有日志记录重试行为
      await Future.delayed(delay);
    }
  }
}
```

**问题**: 
- 用户看不到重试进度
- 无法调试重试失败原因

**建议**:
```dart
static Future<T> retryWithBackoff<T>({
  required Future<T> Function() request,
  String? taskType, // 新增：用于日志
  // ...
}) async {
  while (true) {
    try {
      return await request();
    } catch (e) {
      if (retryCount >= maxRetries) rethrow;
      
      AiLogger.logRetry(
        taskType: taskType ?? 'unknown',
        attempt: retryCount + 1,
        maxRetries: maxRetries,
        delay: delay.inSeconds,
        reason: e.toString(),
      );
      
      await Future.delayed(delay);
      retryCount++;
      delay *= 2;
    }
  }
}
```

**优先级**: 中（用户体验改进）

---

### 3.4 数据裁剪 (ai_data_trimmer.dart)

**优点**:
- 任务导向的裁剪策略
- 备注脱敏（手机号、身份证）
- Token 估算工具

**潜在问题**:

#### 问题 D: 脱敏逻辑可能误伤
```dart
// 当前代码：131-134 行
sanitized = sanitized.replaceAllMapped(
  RegExp(r'1[3-9]\d{9}'),
  (m) => '${m.group(0)!.substring(0, 3)}****${m.group(0)!.substring(7)}',
);
```

**问题**: 
- 正则可能匹配到流水号、订单号中的 11 位数字
- 示例: "202501381234567890" → "202****7890"（误伤）

**建议**:
```dart
// 更精确的上下文检测
sanitized = sanitized.replaceAllMapped(
  RegExp(r'(?<!\d)1[3-9]\d{9}(?!\d)'),  // 前后不能有数字
  (m) => '${m.group(0)!.substring(0, 3)}****${m.group(0)!.substring(7)}',
);
```

**优先级**: 中（当前可用，但边界情况需注意）

---

#### 问题 E: Token 估算过于粗糙
```dart
// 当前代码：146-150 行
static int estimateTokens(String text) {
  final chineseCount = RegExp(r'[一-龥]').allMatches(text).length;
  final englishWords = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  return (chineseCount * 2 + englishWords * 1.3).round();
}
```

**问题**: 
- JSON 结构开销未计算（`{`, `}`, `"`, `,`）
- 数字、标点符号处理不准确

**建议**:
```dart
static int estimateTokens(String text) {
  // 方案 A: 使用官方 tokenizer（需引入依赖）
  // 方案 B: 改进启发式规则
  final chineseCount = RegExp(r'[一-龥]').allMatches(text).length;
  final symbolCount = RegExp(r'[{}[\]:,"]').allMatches(text).length;
  final numberCount = RegExp(r'\d+').allMatches(text).length;
  
  return (chineseCount * 2 + 
          symbolCount * 0.5 + 
          numberCount * 0.8).round();
}
```

**优先级**: 低（估算值仅用于预警，不影响功能）

---

### 3.5 异常体系 (ai_exception.dart)

**优点**:
- 分层清晰（网络、认证、限流、模型、服务器）
- 支持 `shouldRetry` 标识
- 携带 `statusCode`、`retryAfterSeconds` 元数据

**改进建议**:

#### 问题 F: 缺少用户友好的错误描述
```dart
// 当前实现
class AiRateLimitException extends AiException {
  final int? retryAfterSeconds;
  AiRateLimitException(super.message, {this.retryAfterSeconds, super.statusCode});
}

// 建议：增加 UI 展示用的友好描述
abstract class AiException implements Exception {
  String get message;
  String get userFacingMessage;  // 新增
  
  // 默认实现
  String get userFacingMessage => message;
}

class AiRateLimitException extends AiException {
  @override
  String get userFacingMessage {
    if (retryAfterSeconds != null) {
      return '请求过于频繁，请 $retryAfterSeconds 秒后重试';
    }
    return '请求过于频繁，请稍后重试';
  }
}
```

**优先级**: 中（用户体验改进）

---

## 4. 性能 & 可观测性

### 4.1 日志系统 (ai_logger.dart)

**当前状态**: 
- 结构化日志（JSON）
- 性能指标（duration、token 使用）
- 重试/降级事件

**改进空间**:

#### 建议 A: 支持日志级别过滤
```dart
enum LogLevel { debug, info, warn, error }

class AiLogger {
  static LogLevel minLevel = LogLevel.info;
  
  static void logDebug(String message, Map<String, dynamic> data) {
    if (minLevel.index > LogLevel.debug.index) return;
    _emit('DEBUG', message, data);
  }
}
```

#### 建议 B: 结构化错误追踪
```dart
// 增加 traceId 跟踪完整请求链路
class AiLogger {
  static String _currentTraceId = '';
  
  static void beginTrace(String taskId) {
    _currentTraceId = '${DateTime.now().millisecondsSinceEpoch}_$taskId';
  }
  
  static void logQueryStart({...}) {
    _emit('QUERY_START', {
      'trace_id': _currentTraceId,
      // ...
    });
  }
}
```

**优先级**: 低（当前日志已足够）

---

### 4.2 性能监控

**缺失项**:
- ❌ 慢查询告警（> 10s）
- ❌ Token 使用趋势统计
- ❌ 错误率监控

**建议**:
```dart
class AiMetrics {
  static final _slowQueries = <String, int>{};
  static final _tokenUsage = <String, int>{};
  
  static void recordSlowQuery(String taskType, int durationMs) {
    if (durationMs > 10000) {
      _slowQueries[taskType] = (_slowQueries[taskType] ?? 0) + 1;
    }
  }
  
  static Map<String, dynamic> getMetricsSummary() {
    return {
      'slow_queries': _slowQueries,
      'total_tokens': _tokenUsage.values.fold(0, (a, b) => a + b),
    };
  }
}
```

**优先级**: 低（锦上添花）

---

## 5. 测试覆盖度

### 已有测试
- ✅ `ai_data_trimmer_test.dart` - 数据裁剪逻辑
- ✅ `ai_provider_config_test.dart` - 配置校验
- ✅ `entry_sanity_test.dart` - 输入校验

### 缺失测试
- ❌ `llm_query_v2` - 模型降级、流式响应
- ❌ `ai_request_manager` - 并发控制、重试逻辑
- ❌ `ai_exception` - 异常分类准确性

**建议优先补充**:
1. 模型降级场景（404 → 切换模型）
2. 流式响应异常处理
3. 并发请求取消机制

**优先级**: 高（核心逻辑需要测试保护）

---

## 6. 安全性

### 已做防护
- ✅ API Key 安全存储（`ai_secure_config.dart`）
- ✅ 备注脱敏（手机号、身份证）
- ✅ 输入校验（`entry_sanity.dart`）

### 潜在风险

#### 风险 A: 敏感数据可能泄露到日志
```dart
// ai_logger.dart 当前实现
static void logQueryFailure({
  required String errorMessage,  // 可能包含用户数据
}) {
  print(jsonEncode({
    'error_message': errorMessage,  // 直接打印
  }));
}
```

**建议**: 
```dart
static void logQueryFailure({
  required String errorMessage,
}) {
  final sanitizedMessage = _sanitizeForLogging(errorMessage);
  print(jsonEncode({
    'error_message': sanitizedMessage,
  }));
}

static String _sanitizeForLogging(String message) {
  // 移除可能的敏感数据
  return message
      .replaceAll(RegExp(r'1[3-9]\d{9}'), '***PHONE***')
      .replaceAll(RegExp(r'\d{17}[\dXx]'), '***ID***');
}
```

**优先级**: 高（合规风险）

---

#### 风险 B: API Key 可能通过错误消息泄露
```dart
// llm_query_v2.dart:416-420
headers: {
  'Authorization': 'Bearer ${config.apiKey}',
  'Content-Type': 'application/json',
}
```

如果请求失败，HTTP 库可能在异常消息中包含 headers。

**建议**: 
```dart
try {
  resp = await http.post(...);
} catch (e) {
  // 清理异常消息中的敏感信息
  final sanitizedError = e.toString()
      .replaceAll(config.apiKey, '***API_KEY***');
  throw AiNetworkException(sanitizedError);
}
```

**优先级**: 高（安全基线）

---

## 7. 可扩展性

### 当前架构的扩展点
1. ✅ 新增 AI 提供商：工厂方法
2. ✅ 新增任务类型：裁剪策略
3. ⚠️ 新增推理模式：需修改多处代码

### 建议：插件化架构
```dart
abstract class AiTaskPlugin {
  String get taskType;
  Map<String, dynamic> trimData(List<TransactionRecord> records);
  String buildPrompt(Map<String, dynamic> data);
}

class MonthlyAnalysisPlugin extends AiTaskPlugin {
  @override
  String get taskType => 'monthly_analysis';
  
  @override
  Map<String, dynamic> trimData(List<TransactionRecord> records) {
    return AiDataTrimmer.trimForMonthlyAnalysis(
      allRecords: records,
      // ...
    );
  }
}

// 注册机制
class AiTaskRegistry {
  static final _plugins = <String, AiTaskPlugin>{};
  
  static void register(AiTaskPlugin plugin) {
    _plugins[plugin.taskType] = plugin;
  }
  
  static AiTaskPlugin? get(String taskType) => _plugins[taskType];
}
```

**优先级**: 低（当前规模不需要）

---

## 8. 总结 & 行动项

### 立即修复（高优先级）
1. ✅ **TransactionRecord 构造器错误** - 已修复
2. 🔴 **模型降级逻辑精确化** - 避免误降级
3. 🔴 **日志脱敏** - 防止敏感数据泄露
4. 🔴 **API Key 保护** - 错误消息中移除

### 近期改进（中优先级）
1. 🟡 **流式响应错误日志** - 提升可调试性
2. 🟡 **重试逻辑日志** - 增强用户感知
3. 🟡 **异常友好化** - 改善用户体验
4. 🟡 **备注脱敏边界** - 避免误伤

### 长期优化（低优先级）
1. ⚪ **性能监控** - 慢查询告警
2. ⚪ **插件化架构** - 提升扩展性
3. ⚪ **Token 估算改进** - 更精确的成本预测

---

## 9. 架构评分

| 维度 | 评分 | 说明 |
|------|------|------|
| **代码结构** | ⭐⭐⭐⭐⭐ | 分层清晰，职责分明 |
| **可测试性** | ⭐⭐⭐⭐ | 纯函数设计好，但测试覆盖不足 |
| **错误处理** | ⭐⭐⭐⭐ | 体系完善，但分类精度待提升 |
| **可观测性** | ⭐⭐⭐ | 有日志，但缺少结构化追踪 |
| **安全性** | ⭐⭐⭐ | 基础防护到位，但日志脱敏缺失 |
| **性能** | ⭐⭐⭐⭐ | Token 优化好，但缺少监控 |
| **可扩展性** | ⭐⭐⭐⭐ | 当前设计足够，未来可插件化 |

**总体评分**: ⭐⭐⭐⭐ (4.1/5)

**总结**: 架构设计扎实，工程实践良好，主要改进空间在错误处理精度和安全性加固。

---

_生成时间: 2025-01-XX_
_审查范围: lib/core/ai/* (27 files)_
