# Claude API 适配总结

更新时间：2026-08-14

## 一、适配范围

本次适配为肥喵记账 AI 后端添加了 Claude API 支持，使应用可以同时使用 OpenAI 兼容接口和 Claude 原生接口。

## 二、核心改动

### 2.1 请求格式转换

**OpenAI 格式 → Claude 格式的关键差异：**

1. **端点 URL**
   - OpenAI: `/v1/chat/completions`
   - Claude: `/v1/messages`

2. **认证方式**
   - OpenAI: `Authorization: Bearer {API_KEY}`
   - Claude: `x-api-key: {API_KEY}` + `anthropic-version: 2023-06-01`

3. **消息结构**
   - OpenAI: `messages` 数组包含 `role: system/user/assistant`
   - Claude: `system` 单独字段 + `messages` 数组只含 `user/assistant`

4. **响应格式**
   - OpenAI: `choices[0].message.content`
   - Claude: `content[0].text`

5. **流式响应**
   - OpenAI: `data: {"choices":[{"delta":{"content":"..."}}]}`
   - Claude: `data: {"type":"content_block_delta","delta":{"text":"..."}}`

### 2.2 涉及文件

✅ **已完成适配的文件：**

1. **`lib/core/ai/ai_provider_config.dart`**
   - 新增 `isClaudeModel` getter（检测模型名和 baseUrl）
   - 新增 `messagesUri` getter（统一的 Claude Messages API 端点）
   - 删除重复的 `isClaudeModel` 定义
   - 统一使用 `messagesUri` 替代 `claudeMessagesUri`

2. **`lib/core/ai/llm_query_v2.dart`**（主要记账和查账）
   - `_postWithModelFallback`: 在发送前转换 Claude 格式（行377-378）
   - `_postChat`: 适配 Claude 请求头和响应解析
   - `_streamChat`: 直接构建 Claude 格式请求体，流式响应解析（行610-636）
   - `_convertToClaudeFormat`: OpenAI → Claude 格式转换函数（行905+）
   - 支持 `thinking` 参数映射（根据 `reasoningEffort`）

3. **`lib/core/ai/llm_entry_parser.dart`**（记账解析）
   - `_postChatContent`: 请求前转换格式，响应解析支持 Claude
   - 修复认证头：Claude 使用 `x-api-key` 而非 `Authorization: Bearer`
   - `_convertToClaudeFormat` 和 `_stringContent` 辅助函数

4. **`lib/core/ai/llm_query.dart`**（旧版，已有 Claude 支持）
   - 统一使用 `messagesUri` 替代 `claudeMessagesUri`（行217）
   - 已有完整的 `_postClaudeMessages` 实现

5. **`lib/views/assistant/meow_assistant_view.dart`**
   - 添加 `record_extras_sheet.dart` 导入（修复编译错误）

### 2.3 关键函数

**`_convertToClaudeFormat(openaiBody, config)`**

- 分离 `system` 消息到独立字段
- 保留 `user/assistant` 消息到 `messages` 数组
- 添加 `max_tokens: 4096`
- 映射 `reasoningEffort` 到 `thinking` 参数

**`_stringContent(content)`**

- 处理 OpenAI 的复杂 content 结构
- 提取 `type: text` 的文本内容
- 支持字符串和数组格式

## 三、验证结果

### 3.1 编译检查

```bash
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
```

✅ **结果：0 error，25 issues（仅 warning 和 info）**

### 3.2 测试结果

```bash
flutter test test/core/ai/
```

✅ **结果：75/75 测试全部通过**

涵盖：
- 异常处理和分类（8 个测试）
- 数据脱敏（17 个测试）
- 日志记录（25 个测试）
- 重试逻辑（14 个测试）
- 集成测试（6 个测试）
- Provider 配置（3 个测试）
- 数据裁剪（12 个测试）

## 四、使用方式

### 4.1 配置 Claude 服务商

1. 在 AI 设置中添加自定义服务商
2. 基础地址填写：`https://api.anthropic.com`
3. 输入 Claude API Key
4. 刷新模型列表，选择 Claude 模型（如 `claude-sonnet-3-5-20241022`）

### 4.2 自动识别

应用会根据以下条件自动判断是否使用 Claude API：

1. 模型名包含 `claude`（不区分大小写）
2. 或 baseUrl 包含 `anthropic.com`

满足任一条件即启用 Claude 格式转换。

## 五、注意事项

1. **不要重复转换**：`_postWithModelFallback` 已在上层转换，`_postChat` 不应再转换
2. **认证方式**：Claude 必须使用 `x-api-key` 头，不是 `Authorization: Bearer`
3. **流式响应**：`_streamChat` 直接构建 Claude 格式，不经过转换函数
4. **thinking 参数**：只有 Claude 支持，根据 `reasoningEffort` 自动映射 token 预算
5. **max_tokens**：Claude 必须提供，默认 4096

## 六、后续优化建议

1. **统一转换逻辑**：考虑将 `_streamChat` 的 Claude 格式构建也改用 `_convertToClaudeFormat`
2. **错误处理增强**：针对 Claude 特有的错误码添加更友好的提示
3. **性能优化**：考虑缓存格式转换结果（如果请求体相同）
4. **测试覆盖**：添加 Claude API 的集成测试（需要真实 API Key）

## 七、相关文档

- [AI 后端架构优化](./AI后端架构优化-2026-08-13.md)
- [项目管理总纲](../PROJECT_MANAGEMENT.md)
- [当前交接文档](./CLAUDE_HANDOFF_CURRENT.md)
