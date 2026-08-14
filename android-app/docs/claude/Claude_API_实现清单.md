# Claude API 实现清单

## ✅ 已完成的文件

### 1. ai_provider_config.dart
- ✅ `isClaudeModel` getter（检测模型名和 baseUrl）
- ✅ `messagesUri` getter（统一的 `/v1/messages` 端点）
- ✅ 删除重复的 `isClaudeModel` 定义（行192）
- ✅ 删除 `claudeMessagesUri`（统一使用 `messagesUri`）

### 2. llm_query_v2.dart（主要记账和查账）
- ✅ `_postWithModelFallback`：在行377-378转换 Claude 格式
- ✅ `_postChat`：适配 Claude 请求头（`x-api-key`）和响应解析（`content[0].text`）
- ✅ `_streamChat`：直接构建 Claude 格式（行523-555），流式响应解析（行610-636）
- ✅ `_convertToClaudeFormat`：OpenAI → Claude 格式转换（行905+）
- ✅ `_stringContent` 辅助函数：提取文本内容

### 3. llm_entry_parser.dart（记账解析）
- ✅ `_postChatContent`：请求前转换格式（行267），响应解析支持 Claude（行306-318）
- ✅ 修复认证头：Claude 使用 `x-api-key` 而非 `Authorization: Bearer`（行276-287）
- ✅ `_convertToClaudeFormat` 和 `_stringContent` 辅助函数（文件末尾）

### 4. llm_query.dart（旧版）
- ✅ 统一使用 `messagesUri` 替代 `claudeMessagesUri`（行217）
- ℹ️ 已有完整的 `_postClaudeMessages` 实现（无需改动）

### 5. meow_assistant_view.dart
- ✅ 添加 `record_extras_sheet.dart` 导入（修复编译错误）

## 🔑 关键实现点

### 格式转换函数 `_convertToClaudeFormat`

**输入**：OpenAI 格式的请求体
```dart
{
  'model': 'claude-sonnet-3-5-20241022',
  'messages': [
    {'role': 'system', 'content': 'You are...'},
    {'role': 'user', 'content': 'Hello'},
  ]
}
```

**输出**：Claude 格式的请求体
```dart
{
  'model': 'claude-sonnet-3-5-20241022',
  'system': 'You are...',
  'messages': [
    {'role': 'user', 'content': 'Hello'},
  ],
  'max_tokens': 4096,
  'thinking': {  // 可选，根据 reasoningEffort
    'type': 'enabled',
    'budget_tokens': 8192,
  }
}
```

### 认证方式

**OpenAI**:
```dart
headers: {
  'Authorization': 'Bearer ${apiKey}',
  'Content-Type': 'application/json',
}
```

**Claude**:
```dart
headers: {
  'x-api-key': apiKey,
  'anthropic-version': '2023-06-01',
  'Content-Type': 'application/json',
}
```

### 响应解析

**OpenAI**:
```dart
final content = json['choices'][0]['message']['content'];
```

**Claude**:
```dart
final content = json['content'][0]['text'];
```

### 流式响应

**OpenAI**:
```dart
final delta = json['choices'][0]['delta'];
final content = delta['content'];
```

**Claude**:
```dart
if (json['type'] == 'content_block_delta') {
  final content = json['delta']['text'];
}
```

## 🧪 测试覆盖

✅ **75/75 测试通过**

- 异常处理和分类：8 个
- 数据脱敏：17 个
- 日志记录：25 个
- 重试逻辑：14 个
- 集成测试：6 个
- Provider 配置：3 个
- 数据裁剪：12 个

## 📋 使用方式

1. 在 AI 设置中添加自定义服务商
2. 基础地址：`https://api.anthropic.com`
3. 输入 Claude API Key
4. 刷新模型列表
5. 选择 Claude 模型（如 `claude-sonnet-3-5-20241022`）

应用会自动检测模型名或 baseUrl 包含 `claude` / `anthropic.com`，启用 Claude 格式。

## ⚠️ 注意事项

1. **不要重复转换**：`_postWithModelFallback` 已在上层转换，`_postChat` 不应再转换
2. **认证方式**：Claude 必须使用 `x-api-key` 头，不是 `Authorization: Bearer`
3. **流式响应**：`_streamChat` 直接构建 Claude 格式，不经过转换函数
4. **max_tokens**：Claude 必须提供，默认 4096
5. **thinking 参数**：只有 Claude 支持，根据 `reasoningEffort` 自动映射

## 📊 验证结果

```bash
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
```
✅ **0 error，25 issues（仅 warning 和 info）**

```bash
flutter test test/core/ai/
```
✅ **75/75 测试全部通过**
