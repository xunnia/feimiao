# GPT OAuth 稳定性与 Gemini 授权调研（2026-08-28）

## 参考来源

- Cockpit Tools（公开仓库）：<https://github.com/jlcodes99/cockpit-tools>
- Cockpit 当前 `1.3.34` 的变更记录明确提到：Codex 浏览器 OAuth 使用
  `chatgpt.com/codex/desktop-auth` hosted 登录页、桌面客户端身份参数、
  `localhost:1455` 回调、持久化 pending 状态、Token 刷新和失败后的重试/重新授权。
- Google Gemini API 官方 OAuth 快速入门：<https://ai.google.dev/gemini-api/docs/oauth>
- Google Gemini API Key 官方说明：<https://ai.google.dev/gemini-api/docs/api-key>

## 本次 GPT OAuth 修复

1. 授权地址按 Cockpit 的 hosted envelope 生成：内层仍是
   `auth.openai.com/oauth/authorize`，外层使用
   `chatgpt.com/codex/desktop-auth`，补齐 `codex_streamlined_login`、
   `codex_app_version`、`source_surface_stable_id`、`codex_origin_stable_id`。
   stable id 保存在安全存储中，不写普通数据库。
2. 浏览器已回调但 Token 交换失败时，将完整回调 URL 写回安全 pending 状态；
   Activity 被回收或页面回到前台后可直接重试，不必重新打开授权页面。
3. Token endpoint 对超时、连接异常、408/425/429/5xx 做最多 3 次有界重试；
   400 等授权码/凭据错误保持快速失败，不掩盖真实错误。
4. 失败 completion 会释放内存等待器但保留 pending 状态，避免恢复流程继续拿到
   已失败的 Future。
5. Android 原生 keep-alive 服务启动时校验回调文件里的 state；旧流程残留文件会被
   清理，不再阻塞新流程或让浏览器显示假成功页。
6. 授权码交换保持 Cockpit/官方 Codex 的原始 OAuth 表单请求，不附加运行时身份头；
   refresh token 请求使用 Cockpit 对齐的 JSON body 和 Codex Desktop 身份头；业务 API
   请求仍保留现有 Responses/Codex 请求头，避免改变已验证的模型请求协议。
7. Android 优先通过 AndroidX Browser 1.9 的 Chrome Ephemeral Custom Tab 打开授权，
   将当前 Chrome/Google Cookie 与本次登录隔离；不支持时才走外部浏览器并保留手动回调。
   原生回调文件读取不再立即删除，成功交换后按 flowId 清理，避免进程回收时丢失回调。
8. 浏览器 pending 有效期调整为 10 分钟，Android 原生监听保留 1 分钟收尾余量，
   与 Cockpit 的浏览器登录窗口一致，覆盖 MFA/慢网络场景。

## Gemini 授权可行性边界

- **Gemini API OAuth：可做。** Google 官方文档提供桌面应用 OAuth 2.0 流程，
  需要 Google Cloud 项目、启用 Generative Language API、自有 OAuth Desktop
  Client ID/Secret、同意屏幕与测试用户；首次授权拿 refresh token，后续刷新后用
  Bearer token 调 Gemini API。官方文档同时说明 API Key 是最简单入口。
- **Gemini Pro 网页订阅直接登录：不能把它等同于 Gemini API OAuth。** 用户的
  `gemini.google.com`/Google One Pro 订阅并不会自动变成公开 Gemini API 配额。
  API 调用仍受 Cloud 项目、API 启用、区域、配额和计费约束。
- **Cockpit 的 Google OAuth 主要是 Antigravity/Gemini Code Assist 路线。** 其源码
  使用 Google OAuth、Cloud Code 相关 scope 和私有客户端配置，并读取/写入
  Antigravity 的本地凭据格式。这不是一个应直接复制到肥喵、也不应把其 client
  secret 硬编码进 APK 的通用 Gemini Pro 登录方案。
- **建议的安全落地顺序：** 先支持用户自有 Google OAuth Desktop Client 的
  Gemini API（或继续使用 API Key）；若要兼容 Cockpit/Antigravity，再做“导入
  refresh token/JSON + 安全存储 + 账号开关”，不要抓取 Google 网页 cookie，也不
  要内置 Cockpit 私有 secret。真正的 Gemini Pro 订阅配额需要单独验证官方授权
  资格后再接入，不能先承诺可用。
