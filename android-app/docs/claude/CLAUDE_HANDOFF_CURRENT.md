# 肥喵记账 Codex 当前交接文档

更新时间：2026-08-31（GPT OAuth、Cockpit JSON 与架构收口，v1.281.0+295；本轮无在线 Android 设备）
当前 Android 工程：`C:\src\xunni-codex\android-app`  
新会话第一入口：`docs/claude/CLAUDE_START_HERE.md`

> 本文只保留当前有效状态。历史流水看 `CHANGELOG_CODEX.md` 和 git 历史。

## -1.0.13. 2026-08-31 GPT OAuth、Cockpit JSON 与架构收口（v1.281.0+295）

- OAuth 普通入口固定为官方 PKCE + `auth.openai.com/oauth/authorize` + localhost:1455/1457；Android 原生监听支持 IPv4/IPv6、Activity 重建、重复回调和 flowId 隔离。固定系统代理被 `ProxySelector=DIRECT` 误判时现在回退 `ConnectivityManager.defaultProxy`；Token authorization-code 遇 `unsupported_country_region` 时由 Chrome 本地一次性页面通过浏览器 VPN 完成交换，code/verifier 只在 App 私有文件和本机响应体中传递，不进入 URL/云端。
- Token 成功后先持久化，再拉官方模型目录并以首个模型执行不带账本内容的最小 `ping`；恢复路径同样执行探测。模型目录失败不丢登录账号，健康记录按阶段保存“可用/需代理/凭据失效/模型不可用/网络失败”。
- Cockpit JSON 解析完整备份 `accounts.platforms.codex.exported_data`、standalone transfer、auth.json、Sub2API、嵌套 token、refresh-only、PAT、JSON/JSONL、BOM/UTF-16；显式 `auth_mode=apikey` 不会被 `type=codex` 或 stale token 误判。provider 地址、wire format、模型目录、关联 key 会合并；workspace/account_id 单独不去重。导入预览支持更新/副本/跳过，凭据只写安全存储，单账号可重新验证。
- 新增共享 `AiHttpTransport`，OAuth、模型、Responses、主页记账、Chats、联网搜索共享代理刷新、超时和重试边界；错误/AI run/报告摘要统一脱敏。SQLite 迁移列改为缺列才添加，真实迁移错误不再被空 catch 吞掉，数据库版本升至 v49。
- 验证：Flutter 全量 **1182/1182**；OAuth/JSON/代理/健康/仓库定向回归通过；Dart analyze 0 error（91 条既有 warning/info）；Android `:app:compileDebugKotlin` 成功；Release gate 通过。2026-08-31 本机完整 Cockpit 备份解析 **9 个 Codex 账号（6 OAuth、3 API Key），0 警告**。
- APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.281.0-295.apk`，117,707,189 字节，SHA256 `A3960191D17E8CB2E2EA4B4D0310C9A8579B39127F8A317E86E73E1BAC9C07BA`。
- 本轮无在线 Android ADB；Chrome Ephemeral/账号选择、手机 VPN 出口、localhost 回调、显式设备码、安装冷启动及输入法/字体观感仍需目标手机复测；未使用 Plus 账号。

## -1.0.10. 2026-08-30 GPT OAuth 旧设备授权状态迁移（v1.279.0+293）

- Android 普通“GPT OAuth 授权”只走 Cockpit 默认的浏览器 PKCE + localhost 回调，不调用 device-auth user-code 接口。
- 旧版本遗留的设备授权 pending 状态在读取时直接清理；设备授权状态不再持久化，避免升级后恢复旧轮询再次触发 `unsupported_country_region` 403。浏览器 PKCE pending 仍持久化，Activity 重建后可恢复。
- 当前无在线 Android ADB；真机 VPN、Chrome Custom Tab、账号选择、localhost 回调、模型目录与 Responses 仍需安装本包后在目标手机复测。

## -1.0.9. 2026-08-30 GPT OAuth Android 默认流程修复（v1.278.0+292）

- Android 普通“GPT OAuth 授权”恢复 Cockpit 默认的浏览器 PKCE 流程，不再先调用地区受限的 device-auth user-code 接口；设备码 API 保留但不作为默认入口。
- Android 继续使用原生 localhost 回调保活、Ephemeral/无痕 Chrome、`prompt=select_account`、Token 交换/刷新和模型目录获取；目标是避免手机直连出口在授权页前收到 `unsupported_country_region`。
- 验证：OAuth/JSON/Responses/设置定向 `113/113`、Flutter 全量 `1171/1171`、Dart analyze 无 error、Android Kotlin 编译和 Release 构建成功；APK `C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.278.0-292.apk`，SHA256 `0F893CD39C9386BA4C6D325A6B3C417BA1E3CB311B997BD38400BFA2A6C672FD`，16 KiB/V2/固定证书 gate 通过。
- 当前无在线 Android ADB，真机 VPN、Chrome Custom Tab、回调和实机观感仍需目标手机安装后复测。

## -1.0.8. 2026-08-30 GPT OAuth/JSON 最终链路修复（v1.277.0+291）

- 官方 ChatGPT/Codex Responses 端点要求 `stream=true`；普通问答、主页记账、报告和连接测试的缓冲 Responses 传输层现在统一强制流式标志，并保留官方会话/请求元数据。
- 聊天请求补齐按目标地址的 Android 系统代理/PAC 解析；设备授权码、PKCE/state、Token 刷新、模型目录重试和首包重试继续保留。
- 本机真实 Cockpit 完整备份解析出 10 个 Codex 账号（5 OAuth、5 API Key）且无警告；指定测试账号的模型目录 HTTP 200、真实 Responses HTTP 200 并解析 `OK`，肥喵 `LlmQueryV2` 与主页 `LlmQuery` 路径均通过。
- 验证：OAuth/Responses/JSON/仓库定向回归 `113/113`；Flutter 全量 `1171/1171`；Dart analyze 无 error；Gradle `:app:compileDebugKotlin` 成功。APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.277.0-291.apk`，SHA256 `43DAC969193535B39EBC08EE133546C0C63F3E78C64720829389CF635A754F28`，16 KiB/V2/固定证书 gate 通过。
- 当前无在线 Android ADB，真机 VPN、Chrome Custom Tab、设备码轮询、输入法和字体观感仍需在目标手机安装后复测；未使用 Plus 账号。

## -1.0.7. 2026-08-30 GPT OAuth 与 Cockpit JSON 最终修复（v1.276.0+290）

- Android GPT OAuth 默认改用官方设备授权码：`deviceauth/usercode` -> 官方 `codex/device` -> 403/404 轮询 `deviceauth/token` -> PKCE 校验 -> `deviceauth/callback` Token 兑换；不再依赖 Android 可能被回收的 localhost 回调。桌面/手动 localhost 回调路径保留。
- Token 响应邮箱回填账号身份；主页记账、报告、设置连接测试、喵助手遇到 Codex 不支持模型会重新读取官方模型目录并重试；附件解析和导入后请求动态刷新系统代理。
- Cockpit 完整备份/PAT/共享 workspace/API Key 目录导入规则保持并补齐；真实本机备份解析 10 个 Codex 账号，仓库重启后仍可用。
- 验证：OAuth `19/19`、JSON/AI/模型目录 `44/44`、仓库导入 `3/3`、Flutter `1168/1168`、Dart analyze 无 error（86 条既有 warning/info）。APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.276.0-290.apk`，SHA256 `F762CA8B5E5C478A55EEFB879F5549E66C81662CD1838CBD5347D1AD2CD9D8DF`。
- 本机无在线 ADB，手机真实出口、VPN 分流和设备码真实轮询仍待目标手机安装复测。

## -1.0.6. 2026-08-30 月份选择弹窗回退（v1.275.0+289）

- 主页月份选择弹窗恢复用户提供的旧版参考图二：使用普通底部弹层和自然暗化背景，移除关闭圆圈及高斯模糊。
- 弹层标题改为左侧“月份选择”，右侧同一行显示“月统计起始日：每月 1 号”；年份箭头恢复无圆形视觉底，保留原有可点击热区、年份切换、月份网格和数据计算。
- 可视化证据保存在 `outputs/ui_comparisons/2026-08-30/`：`before/month_picker_before.png`、`month_picker_after.png`、`month_picker_before_after.png`。原截图未覆盖，对比图带 1/2/3 编号标注。
- 定向月份/全局 UI 测试 `3/3`，Flutter 全量 `1164/1164`，Dart analyze exit 0（无 error，84 条既有 warning/info）。
- Release APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.275.0-289.apk`，117,445,045 字节，SHA256 `196FED571B03372A4F89211034759E89061A8AF00B72163DD1542D27C4C4B56B`；16 KiB 对齐、APK V2、固定证书 gate 通过。
- 本轮未发布线上；本机无在线 Android 设备，真实 OAuth/JSON 导入、手机 VPN 分流、Chrome Custom Tab、IME 和真机观感仍需用户设备验收。

## -1.0.5. 2026-08-30 OAuth 网络与 Cockpit JSON 导入修复（v1.274.0+288）

- Cockpit 完整备份现在识别 `accounts.platforms.codex.exported_data` 和单独 `exported_data` 传输段，只抽取 Codex 凭据；本机真实备份解析 9 个账号（5 个 OAuth），无解析警告。
- `at-...` 个人访问令牌按官方 Codex `whoami` 流程获取工作区 ID，并持久化到账号配置；模型目录、身份查询和 401 刷新复用同一 OAuth service/client。
- OAuth/JSON/模型目录定向回归 `53/53`，Flutter 全量 `1164/1164`，Dart analyze 无 error。
- APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.274.0-288.apk`，117,445,049 字节，SHA256 `9459F72F75845DF38D53385FA7B60E731B695BDC749673BAC6EA79A854D19035`；16 KiB/V2/固定证书 gate 通过。
- 本机无在线 ADB；手机 VPN 分流、Chrome Custom Tab、真实 OAuth/模型请求及 JSON 导入仍需目标手机验收。

## -1.0.4. 2026-08-29 GPT OAuth 与 Cockpit JSON 导入稳定性修复（v1.272.0+286）

- OAuth 授权入口恢复官方直达 `auth.openai.com/oauth/authorize` 的 PKCE 流程；`chatgpt.com/codex/desktop-auth` 仅保留为可选成功页封装，不再作为前置授权页，避免已登录浏览器直接复用个人空间。Android 仍优先 Ephemeral/无痕 Chrome，普通兜底明确使用外部浏览器。
- OAuth Token 交换成功先持久化凭据；模型目录是独立的可恢复步骤，临时网络/VPN/代理失败不会让成功登录被丢弃。Android 系统 HTTP 代理在请求前动态刷新，OAuth、模型目录、Responses 和普通 AI 请求共享该路由；localhost 回调始终直连。
- Cockpit/CPA JSON 导入修复 workspace `account_id` 共享导致的错误去重；支持 `token_data`、JSON Lines、嵌套 JSON 字符串、UTF-8 BOM/UTF-16，以及缺少地址/模型的标准 API Key 默认值。批量导入延迟索引写入并在末尾一次提交，避免大文件逐账号重写和逐账号拉模型目录。
- 验证：OAuth/JSON/代理/设置/模型目录定向 **78 项**，串行 Flutter 全量 **1157/1157**，Dart analyze 无 error；Release APK 身份门禁通过（16 KiB、V2、固定证书）。
- APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.272.0-286.apk`，117,363,129 字节，SHA256 `7FAEE2C959F784CC45A29F4BFB4F4DB2796B08F23FCBF28FEED7740135482D0D`。
- 本机 Android 模拟器在独立 ADB 端口下仍无法进入 `device`（持续 offline/无 guest 启动完成），因此没有把安装、Ephemeral Custom Tab、手机 VPN 出口、IME 或真实设备 OAuth 写成已验收；需用户在开启 VPN 的 Android 真机安装此包复测。

## -1.0.3. 2026-08-28 全局 UI 收口（v1.264.0+278）

- 公共 UI 令牌新增 `AppControl`/`AppHitTarget`/`AppType` 动作和菜单文字层级；圆形/胶囊控件把视觉尺寸与触控尺寸分离，独立操作热区至少 48dp，紧凑顶栏不再被热区撑高。
- 设置页、个人中心、自动记账候选、备份、导入导出、AI 快记、收据查看、月份/标签/来源/图表弹层和模型选择统一公共弹层、设置行、按钮和菜单；设置页私有 `_Group/_Tile/_SwitchTile` 已移除。
- 新增 `AppCheckmark` 的整行嵌入模式，避免外层行和内部勾选件一次手势切换两次；选项菜单危险色改用 `AppColors.warning`。
- 修复 AI 账号尾部值在 320dp/200% 字体下的布局溢出，统一 CJK/Latin 文本 Token；新增全局 UI 控件语义、窄屏/深色/大字号测试。
- 截图证据：`outputs/global_ui/settings.png`、`outputs/global_ui/gallery.png`，以及刷新后的 `outputs/ai_account/`、`outputs/ai_chat_input_alignment/`、`outputs/ai_chat_claude/`、`outputs/chats/`；截图回归通过。
- 当前源码验证：Dart analyze 无 error（64 条既有 warning/info）；串行全量 Flutter **1124/1124**；UI 定向和截图回归通过。
- APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.264.0-278.apk`，116,596,258 字节，SHA256 `3BFC09913BB28C0CC783C30773C459570B7195BCE321DAF530FF2A9DCE6FF07C`；Release identity gate 已通过。旧 v1.263.0+277 及更早包保留回退。
- 本机无在线 ADB；真实 OAuth、provider 网络、IME、系统相册/文件选择器和真机字体观感仍需用户设备验收；本轮未修改 iOS 和指定 Android 集成测试文件。

## -1.0.2. 2026-08-28 深度审计收口（v1.263.0+277）

- 修复 Cockpit refresh-only OAuth 首次请求：仅有 `refresh_token` 时会在第一次模型目录/请求前强制交换 access token，并沿用共享刷新与安全存储；报告、隐私确认、账单复核和快速记账入口统一认 `hasCredential`。
- 修复报告思考计时语义：`model_started_ms` 不再在排队、隐私确认或上下文收集阶段写入；前台在首次实际调用模型前 CAS 写入，WorkManager 在同一时点写入，CAS 输家读取并回写持久化赢家时间，恢复任务未开始模型时不伪造创建时间。
- 修复回答富文本的 CJK/Nunito 缺字方块：`SelectableText.rich` 明确使用 Nunito + Noto Sans SC fallback；裸来源 URL 从正文移除，来源统一放到操作栏和可上拉来源面板；URL 后的中文标点与正文不会被误吞。
- 视觉证据改为带真实暖背景的整屏截图，思考、来源、三图、消息和 Claude 加号截图人工复核；截图回归 **16/16**。
- 当前源码验证：Flutter analyze 无 error（60 条既有 warning/info）；串行全量 Flutter **1118/1118**；OAuth/账号、报告计时、AI 请求/重试/Responses、Claude/Chats 视觉回归通过。
- 最新 APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.263.0-277.apk`，117,071,394 字节，SHA256 `C31C24AF83AD5A4BC3BAD245D86536EB60CA124DCB1E54F3ED4C32F0AEAEE509`；Release identity gate 已通过。旧 v1.262.0+276 及更早包保留回退。本机无在线 ADB，真实 OAuth、Token 交换、官方模型目录/Responses、IME、相册和真机观感仍需用户设备验收。

## -1.0.1. 2026-08-27 交付前收口（v1.262.0+276）

- 草稿附件累计限制已补齐：相册重复选择和“添加文件”返回的图片共用每条消息最多 3 张图片；普通文件共用最多 10 个，超出项即时提示并不会进入草稿。
- 报告任务新增 DB v48 字段 `model_started_ms`，首次模型处理时间以 compare-and-set 持久化；前台、WorkManager 和恢复路径沿用同一时间点，重开 Chats 不会重置思考计时。
- `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` exit 0（57 条既有 warning/info）；全量 Flutter **1114/1114**。
- APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.262.0-276.apk`，117,071,394 字节，SHA256 `A3839FFBBE94104866888EA73A0ECBD7A303C2E6A67AE4447FEFE41B18268A6B`；`com.qingji.qingji.codex / 1.262.0 / 276`，16 KiB 对齐、APK V2、固定证书通过。
- 本机无在线 ADB，真实 ChatGPT OAuth/Token、官方模型目录与 Responses、IME、系统相册/文件选择器和真机视觉仍需用户设备验收；iOS 与指定 `integration_test`/`test_driver` 文件本轮未改。

## -1.0. 2026-08-27 三阶段 AI 能力与 8-27 需求收口（v1.261.0+275）

- 正确性/安全：AiRun/AiRunEvent、幂等、配置快照、结构化提案、原子提交与撤销、服务商健康、图片大小/数量校验和 flow ownership 已完成；reasoning 事件只保存字符数摘要，不落原始思考文本。
- 体验/效率：真实思考进度与摘要、上下文按轮压缩/预算、后台任务中心、可控记忆、诊断页、统一搜索、首条 ready barrier、120 秒收口、三图聊天满宽和表格横滑已完成。
- 受控扩展：内部技能、连接器白名单、定时报表配置和 loopback-only 本地 companion service 已提供显式入口；不开放任意 shell、远程 MCP 或自动财务写入。
- 8-27 UI：全局弹层/灰幕/模糊/圆角标准统一；Claude Add to Chat 支持近期图片多选、编号、文件入口和上传进度；输入框、消息操作、模型/Effort 选中态、来源和思考摘要按参考图收口。
- 验证：Dart analyze 无 error（56 条既有 warning/info）；全量 Flutter **1109/1109**；AI/UI/图片/思考/来源/模型/菜单与 Claude/Chats 视觉回归通过；release 构建和包身份校验通过。
- APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.261.0-275.apk`，117,038,626 字节，SHA256 `04692649468A63A11FC22E0DF4530A3DAFC36EFD2EA3BCB9FE41533B1F39C8C2`；`com.qingji.qingji.codex / 1.261.0 / 275`，16 KiB 对齐、APK V2、固定证书通过。旧 v1.260.0+274 保留回退；本机无在线 ADB，真实 provider/OAuth、IME、安装冷启动仍待用户设备验收。

## -1.0. 2026-08-27 后台思考 flow 与参考图三图布局修复（v1.260.0+274）

- `showIosMenu` 统一为 Claude/iOS 风格：中性灰遮罩、锚点镂空、磨砂圆角、阴影和缩放淡入；复制/星标/编辑/删除/选择文本统一使用细线图标，菜单项支持震动反馈。
- 长按自己消息原位放大并高亮，菜单显示发送时间，提供复制、编辑、选择文本；选择文本直接作用于原消息的只读 `EditableText`，不再复制出居中的白框。
- 思考状态使用“正在思考”动效；完成后显示耗时，展开后显示简短思考过程并以灰色分隔线隔开正文。来源 favicon 叠放和数量位于回答操作栏最右侧，正文不再追加来源段落。
- 发送图片保持真实缩略图：输入框先预览，消息内三图按参考图在聊天内容区内方形同排，更多图片可横向滚动；Claude Add to Chat、模型/Effort 浮层和 Chats 菜单继续使用统一设计标准。
- 整条前台 AI 流程及解析/附件请求增加 120 秒超时，避免永不结束的传输永久停留在思考态；三图消息采用参考图的一行方形三等分卡片，保留内容区边距。
- 修复后台报告交接竞态：WorkManager 接管后保留 flow ownership，发送 Future 返回不会终止思考 ticker/报告轮询；任务完成、失败或 120 秒 UI 交接时释放，旧 flow 的迟到回调不能污染新消息。
- 生产历史区三图填满聊天内容区，390dp 下首图左边界为 16、末图右边界为 374；草稿输入区仍首屏三格并支持横向查看更多。
- 本轮补齐 `AiRequestManager` 请求 ownership 竞态：旧请求的 finally/延迟回调不会清理或消费新请求；截图验收改用真实封面文件并等待异步解码，三张已发送图片真实可见、草稿首屏保留三格并可横滑查看更多。
- 设置页模型列表与手动模型输入统一为 15px/w300，并通过 Widget 回归断言；输入框底部模型名称/Effort 标准保持不变。
- 定向 Claude/Chats 视觉回归 **16/16**、AI 请求/重试/Responses **36/36**、AI/UI/会话/图片/思考/来源/模型/菜单 **104/104**；串行全量 Flutter **1094/1094**；analyze exit 0（45 条既有 info/warning）。golden 证据目录：`outputs/ai_chat_claude/`。
- 本轮 Release APK 已归档为 `C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.260.0-274.apk`，116,446,150 字节，SHA256 `2A603BF8B063F26D6FD393591D7440275FE652CE81EA6CA6935595A1E85F36EA`；release identity gate 已确认 `com.qingji.qingji.codex / 1.260.0 / 274`、16 KiB 对齐、APK V2 和固定证书。旧 v1.260.0+273 和 v1.259.0+272 包保留作回退。本机无在线 ADB，真实 provider/OAuth、IME、安装冷启动仍待用户设备验收。

## -1.0. 2026-08-25 本批十项 AI 体验收口（v1.255.0+268）

- 思考状态、处理摘要和来源面板；长按自己消息支持高亮、时间、复制/编辑/选择文本与震动反馈；回复排版、链接、表格横向滚动和 88dp 上拉回弹完成。
- 普通记账模型/Effort 选择、首条消息 ready barrier、主页强制记账路由、Claude 风格加号/图片流程和服务商卡片边界完成。
- Flutter analyze exit 0（34 条既有 info）；串行全量 Flutter **1065/1065**；Gradle release 和 release identity gate 通过。
- APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.255.0-268.apk`，116,069,242 字节；SHA256 `F70BB00313FFBB5EF487C5A3959AEC7284FB2EC62F395608E9390F7B8982E091`；包名/版本 `com.qingji.qingji.codex / 1.255.0 / 268`。
- 本机无在线 ADB 设备，真实 provider/OAuth、安装/冷启动和 IME 观感仍需用户设备验收；源码未提交、未推送、未发布线上。

## -1.1. 2026-08-25 Cockpit AI 账号 JSON 导入导出（v1.252.0+265）

- AI 账号设置新增 JSON 文件导入、剪贴板粘贴和 Cockpit 兼容导出；解析支持 Cockpit flat OAuth、多账号数组、OpenAI `auth.json`、Sub2API `accounts[].credentials` 及常见通用 API Key/OAuth 字段。
- 导入预览显示脱敏账号身份；重复账号可选择更新已有、新建副本或跳过；“同步加入 API 服务”直接映射到账号启用开关。API Key、access token、refresh token、id token 只写入平台安全存储，普通 provider 元数据不含凭据。
- OAuth 文件缺少模型目录时，导入流程会用 access token 尝试获取 GPT/Codex 官方模型；离线时保留默认模型并允许账号页后续刷新。真实网络和账号仍需用户验收。
- Flutter analyze exit 0（33 条既有 info）；全量 Flutter **1059/1059**；账号 JSON/仓库/账号页定向回归通过；Gradle release 成功。
- Release APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.252.0-265.apk`，115,511,398 字节；SHA256 `08E43A3816B6A8832CAC46DDF165A1B7D12F97BADE2AF124F710EE8C28528DD5`；包名/版本 `com.qingji.qingji.codex / 1.252.0 / 265`；16 KiB 对齐、APK V2、固定 Codex 证书和 release identity gate 通过。
- ADB 5037 默认端口仍被系统保留；改用 16037 后在线模拟器已安装并冷启动新包。未执行真实 ChatGPT OAuth、Token 交换、官方模型目录和 Responses 请求。

## -1.2. 2026-08-25 OAuth/主页 GPT/喵助手修复（v1.253.0+266）

- OAuth 请求遇到 401 会共享强制刷新 access token 后重试；GPT 模型目录遇到 401/网络瞬态失败会刷新或有限重试；授权回调响应后保留短暂监听窗口，Chrome 重复回调继续返回成功页。
- 主页记账的官方 Codex Responses 改用 `text.format.type=json_schema`；OAuth 登录后模型目录暂时失败仍保存 Token 和可用默认模型。
- AI 账号凭据、授权地址、基础地址、名称和模型输入框统一认证方式/上游格式的半透明样式；喵助手历史底部空白收紧并将回弹限制为 88dp。
- 全量 Flutter **1059/1059**、analyze exit 0（33 条既有 info）、Gradle release 和 release identity gate 通过。APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.253.0-266.apk`，SHA256 `DB37C1B2E668938B4FB527906EDD4FD704F49AD6E3AC93A58BDF3F20A36D420E`。
- 本轮无在线 ADB 设备，真实 ChatGPT OAuth、模型目录和 Responses 请求仍需用户联网 Android 设备验收。

## -1.0. 2026-08-25 GPT OAuth 原生回调竞态与流隔离最终收口（v1.250.0+263）

- 前台保活服务停止改为 `stopService()` + 有界等待，避免 STOP Intent 与 `startForegroundService()` 竞态；Activity 恢复时按当前 state 复用健康监听。
- ready/callback 文件携带 flow/state；原生服务只接受当前 state，错误 state 返回 400；监听只绑定 `127.0.0.1`，IPv6 作为附加监听。
- 设备级：在线模拟器安装/冷启动成功，Chrome Custom Tab 打开官方授权 URL，`:oauth` 前台服务 `startForegroundCount=1`；1455 错误 state=400、正确 state=200；无前台服务启动异常。
- 全量 Flutter **1051/1051**、analyze exit 0（33 条既有 info）、Gradle release 构建和 release gate 均通过。
- Release APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.250.0-263.apk`，115,970,438 字节；SHA256 `13d6d6a5f71fcd7cb374fbc188c2f644c6e98bfe5c3fb451ff5b0dbc77615342`；包名/版本 `com.qingji.qingji.codex / 1.250.0 / 263`。
- 真实 ChatGPT 账号登录、Token 交换、官方模型目录和 Responses 请求仍需用户在可联网设备上验收。

## -0.9. 2026-08-24 GPT OAuth Android 回调保活修复（v1.248.0+261）

- 根因是外部 Chrome 跳转期间 Flutter Activity 进入后台被 Android 回收，Dart localhost 监听消失，浏览器报 `ERR_CONNECTION_REFUSED`。
- 新增短时 `OAuthKeepAliveService` 前台服务；OAuth 开始时启动，Token 交换/取消/过期/恢复失败时停止；监听改为 IPv4 全接口（包含回环）并同时探测 IPv4/IPv6。
- OAuth/账号设置 **12/12**、全量 Flutter **1051/1051**、analyze exit 0（33 条既有 info）、Gradle release 和 release gate 均通过。
- Release APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.248.0-261.apk`，115,281,574 字节；SHA256 `d2b896e6e09a028192c4e96b875b56f163eb85eb127ce5c9a9c292fd919c77e2`；包名/版本 `com.qingji.qingji.codex / 1.248.0 / 261`。
- 无 Android 真机/AVD，真实账号登录和 Chrome 回调仍需用户安装本包验证。

## -0.8. 2026-08-24 GPT OAuth 官方模型链路与最终 APK（v1.247.0+260）

- OAuth 优先监听 IPv4 `127.0.0.1`，1455 失败自动切换 1457；恢复前台先健康检查，IPv6 作为补充回调地址。
- 授权后交换/刷新官方 ChatGPT/Codex Token，从官方 Codex 模型目录获取账号实际模型；请求走 `/codex/responses` 并携带 `ChatGPT-Account-Id`。
- Flutter analyze exit 0（33 条既有 info），串行全量 Flutter **1051/1051**；Gradle release 构建和 release gate 通过。
- Release APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.247.0-260.apk`，115,281,466 字节；SHA256 `9d7a95099f84bf76c61409e05c54ae8d3ffa92b6c95952f383ee4805ac8a53d1`；包名/版本 `com.qingji.qingji.codex / 1.247.0 / 260`。
- `adb devices` 当前无连接 Android 真机；真实 OAuth/provider 网络、安装/冷启动、IME 和中文字体观感待用户验收。

## -0.7. 2026-08-24 加号比例二次收口与 Tool access 全局化（当前源码）

- 加号面板相册首屏按参考图收敛为 **94dp 相机卡 + 94dp 近期图片横滑轨道**；权限/相册加载期间保留同样比例的占位，不再闪出夸张的双大卡；无近期图片时保留紧凑 Photos 兜底。
- 生产路由在 390dp 屏幕使用 374dp 面板宽度（左右 8dp、底部 8dp 小浮层边距），整屏截图证据为 `outputs/ai_chat_claude/ai_chat_add_sheet.png`，近期图片 rail 证据为 `outputs/ai_chat_claude/ai_chat_add_sheet_recent.png`。
- 联网搜索开关只属于喵助手当前 Chats，会话配置和普通供应商设置页均不再提供独立开关；旧供应商值只在首次迁移时继承到全局值。
- Tool access 现在是全局 Chats 权限（Auto/Off），持久化到 `ai_chat_tool_access`；关闭时普通查账/报告转为不带账本工具的聊天请求，且请求配置不会携带联网搜索工具。面板说明账本查询、记账分类、图片识别和联网搜索四类能力。
- 定向视觉/权限回归已通过：Claude 加号与近期图片 **8/8**、供应商/会话权限回归 **15/15**；最终全量 Flutter **1051/1051**、analyze exit 0（33 条既有 info）。
- 本轮交付 APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.246.0-259.apk`（115,281,466 字节），SHA256 `4eda522926fab151ea47cfd0d7113b66ffd1b5269159a237bf90566429f603dc`；包名/版本 `com.qingji.qingji.codex / 1.246.0 / 259`，16 KiB 对齐、APK V2 固定证书和 release identity gate 通过。
- `adb devices` 当前没有连接 Android 设备，未执行真机安装/冷启动；真实相册权限、IME、OAuth/provider 网络和字体观感待用户安装验收。

## -0.6. 2026-08-24 喵助手 Claude 风格加号菜单与功能归位（v1.244.0+257）

- 普通 Chats 不再显示「记一记」快捷提醒；主页 AI 记账仍保留智能建议。
- Chats 输入文字使用 `w350`；加号由旧 33px 图标改为 26.4px GPT 风格细圆角线条，触控区域仍为 36px，和模型/思考强度保持同一水平线。
- 新增独立 `lib/views/home/chat_add_sheet.dart`：底部圆角 `Add to Chat` 面板包含 Camera/Photos、Add files、Tool access、Web search；明确移除 Add to project、Connectors。
- 加号面板生产入口统一走 `showBlurSheet`，带底部上滑和背景模糊；照片入口改为紧凑小卡，左右留白、操作行和圆角按 iOS Claude 参考比例收敛。
- 选图会调用现有截图 OCR 记账入口，因而截图识别能力没有丢失；导入/导出继续由设置页提供；主页 `record_extras_sheet` 未改动。
- Windows 离屏截图已按实机注册应用 Nunito、Noto Sans SC CJK fallback、`MaterialIcons` 和 `packages/cupertino_icons/CupertinoIcons`；输入框、模型/Effort、聊天正文、问候语和操作图标不再显示中文/图标方框。截图前重新挂载 Widget，避免字体缓存造成半成品截图。已人工检查 `android-app/outputs/ai_chat_input_alignment/` 与 `android-app/outputs/ai_chat_claude/`。
- 定向回归 **10/10**（golden 零差异）、串行全量 Flutter **1049/1049**、静态分析 exit 0（33 条既有 info）；视觉证据：`android-app/outputs/ai_chat_claude/ai_chat_add_sheet.png`。
- 当前版本已同步为 `1.244.0+257` / `b0824-257`；Release APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.244.0-257.apk`（114,936,226 字节），SHA256 `7cc057a84437acd4d9947234feb2130491fae2ee97029bde0af92e687f50950e`；aapt、16 KiB zipalign、APK V2 固定证书和 release identity gate `validated`。
- 注意：以上 APK 是本次比例收口前的产物；当前源码的 Claude 面板比例/模糊弹层调整已通过截图回归，尚未递增版本或重建 APK，待用户确认后再出包。
- 真实 Android 相机/相册、IME、中文字体和 provider 网络仍需用户安装 APK 后验收；源码未提交、未推送、未发布线上。

## -0.5. 2026-08-24 喵助手输入框最终字号与底部控件对齐（v1.243.0+256）

- 输入框模型名称与 `High` 统一为 `15px`；模型列表保持 `15px`。
- 模型名称不再用横向 `Expanded` 撑开，`High` 紧跟其后，仅保留约一个空白符宽度（4dp）。
- 无圆底加号图标由 22px 增至 33px（线长 +50%），加号、模型名称和思考强度统一垂直中心线，触控区域仍为 36px。
- 已同步版本 `1.243.0+256` / `b0824-256`。
- 串行全量 Flutter **1048/1048**、analyze exit 0（28 条既有 info）、release gate **9/9** 通过；Release APK 身份等价门禁通过。
- Release APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.243.0-256.apk`，114,902,818 字节；SHA256 `4db579d9f5315f98e0f14acdb0fe7c86d56685551d11e81d62bd8594cd2d468a`；包名/版本 `com.qingji.qingji.codex / 1.243.0 / 256`。
- 真实 Android 真机、IME 和中文字体观感仍待用户安装验收；源码未提交、未推送、未发布线上。

## -0.4. 2026-08-24 OAuth 网络路径与输入框字号修复（v1.242.0+255）

- Android GPT OAuth 使用 Chrome Custom Tabs，沿用系统浏览器的网络/代理路径；IPv6/IPv4 localhost 回调、重绑和粘贴兜底保留。
- 全屏输入区移除多余 `Spacer`，模型区域获得真实剩余宽度，19px 模型名不再被缩放成约 4px；底部 `High` 调为 16px。
- 定向 OAuth/UI **21/21**、全量 Flutter **1048/1048**、analyze exit 0（28 条既有 info）通过。
- 本轮已递增到 `v1.242.0+255` 并重建 APK；真实 Android OAuth、provider 网络、IME 和中文字体观感仍待用户安装验收。
- Release APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.242.0-255.apk`，114,902,818 字节；SHA256 `2a7177a0e3cc26bd9cea048f79b01247983d2adedd5e14afaa9ea7be367c091e`；包名/版本 `com.qingji.qingji.codex / 1.242.0 / 255`，16 KiB 对齐、APK V2 固定证书和 release gate 已通过。

## -1. 2026-08-23 OAuth 回调、聊天字重与字号修复（v1.241.0+254，当前未提交，本地验收完成）

- 当前版本：`1.242.0+255`，build tag `b0824-255`，DB v45；分支 `feature/ai-model-selector`。
- OAuth 回调监听 IPv6 优先并补 IPv4，应用从浏览器恢复时按原注册端口重绑，端口释放增加短重试；PKCE/state 和 1455/1457 注册地址保持不变。
- Android 使用 Chrome Custom Tabs 打开 GPT 授权，Activity 重建后由应用级 watcher 接管待完成流程，自动换 Token、获取模型并保存到原服务商；localhost 回调允许最小范围明文流量；粘贴回调地址仍是兜底路径。
- 本地回调成功页改为 Cockpit 风格紫色页面，显示“✅ 授权成功 / 您可以关闭此窗口并返回应用”。
- 全局 Toast 关闭计时器改为可取消，销毁页面不再留下 pending timer。
- 喵助手输入框已对齐主页「记一记」的尺寸、透明度、内边距和提示文字；加号去掉圆底并与模型/Effort 同组左对齐。
- 输入框底部模型名称为 19px，`Low/High` 思考强度为 16px；模型列表名称为 15px；模型/Effort 默认态不加灰底，选中时才显示灰底；Effort 滑块保持原样。模型名称与思考强度之间固定 `4dp` 外部间距，配合标签内边距避免黏连又不拉开。
- 模型目录获取在 `/v1/models` 超时、连接异常或非认证错误时回退 `/models`；目录为空时保留当前配置模型，显式删除的模型不会复活。
- 用户发送内容与 AI 回复正文默认可变字重为 `w350`（比上一版减少 w50）；问候语、提示语及 Chats 辅助文字保持统一层级，关键强调仍保留独立加粗样式。
- Chats 会话标题、聊天正文和辅助文字缩小一档，正文约 14.5px / w200。
- 普通问答提示词去掉强制 Markdown 标题/列表/加粗、段落长度和短回复要求，性格由“口语化、简短亲切”改为“口语化、亲切”；账目准确性规则保留。月报/周报/年报仍使用独立文档模板。
- OAuth 主流程为 PKCE + state 校验 + localhost 回调（1455/1457），回调后自动换 Token、拉取 GPT 模型并支持 refresh token；浏览器连接失败时可粘贴回调地址兜底。
- 主页 AI 记账任何非空自然语言都会先进入 AI 记账请求，不再在请求前调用本地意图规则拦截；`forceRecord: true` 保证模型按记账结构解析。空文本、忙碌状态和隐私授权仍是必要发送门槛；无 key/请求失败时才使用离线单笔兜底。
- 验证：OAuth/UI 定向回归 **21/21**（OAuth 9/9、账号页 3/3、模型/输入框 9/9）；最终全量 Flutter 测试 **1048/1048**；`flutter analyze --no-fatal-infos --no-fatal-warnings` exit 0（28 条既有 info）。
- 最终 Release APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.241.0-254.apk`，114,902,818 字节；SHA256 `665951676d33a6012582e875715b050cb4e7518881d3dad770801328213bbf5f`；包名/版本 `com.qingji.qingji.codex / 1.241.0 / 254`，16 KiB 对齐、APK V2 固定证书和 release identity gate 已通过。
- 未提交、未推送、未发布线上；真实 provider、Android 真机交互和 IME 动画仍待用户安装验收。

## 0. 2026-08-20 Chats/喵助手 Claude 风格模型与 Effort 交付（v1.228 已构建，当前未提交，待用户安装验收）

- 当前版本：`1.228.0+241`，build tag `b0820-241`，DB v45；分支 `feature/ai-model-selector`。
- 喵助手入口先展示 Chats 会话选择页；「记一记」是唯一默认置顶、不可删除的账单会话，普通会话可新建、搜索、按全部/加星筛选、长按重命名/加星/删除。
- 每个普通会话独立持久化 provider、model、Effort；删除服务商或模型后，引用它的会话在事务中回退到可用主模型，同时保留标题、星标和 Effort。
- Models 浮层由生产组件直接渲染为 `195×224dp` Claude 风格白卡；Effort 浮层为 `222×102dp`，从 Low 起步，包含 Low/Medium/High/Extra/Max/Ultracode，并以紫色颗粒轨道表现 Ultracode。
- Models 行 hover/focus 浅灰圆角背景由显式状态控制，参考图中的悬停行已纳入 golden 截图验收。
- 本轮 Chats 几何收口：筛选浮层锚定右上角、勾选置左；会话卡使用主题半透明 `AppColors.card/selectedCard`、18dp 圆角、68dp 最小高度、34dp 灰色聊天图标；搜索栏为单层半透明表面；底部控件移除重复 SafeArea；模型列表不显示服务商前缀；Effort 当前值文字改灰。
- 主页的 `AiChatPanel` 现在显式传入 `recordOnly: true`；全屏喵助手显式传 `false`。`recordOnly` 不再有默认值，未来新增入口必须主动选择模式。
- （历史记录，已由当前 v1.238 取代）主页曾在写聊天历史和调用模型前拦截闲聊、知识问答与查账；当前主页任何非空输入先进入 `forceRecord` 记账模型，闲聊/查账仅在全屏喵助手处理。
- 本地收入解析覆盖“13号失业金到账2250”“社保补贴到账”等语句，保留指定日期并归入 `inc_subsidy`。
- 验证：同一 SDK 的 `dart analyze --format machine` exit 0（21 条既有 info/lint）；Chats 定向 Widget 测试 **4/4** 通过；全量 Flutter 测试本轮 **997/998**，唯一失败是与 Chats 无关的资产信用卡测试文案断言。
- Golden 截图：`C:\src\xunni-codex\android-app\outputs\chats\chats_current.png`，已核对暖色主题背景、半透明会话卡、单层搜索栏和底部安全区布局。
- Release APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.228.0-241.apk`，114,157,999 字节；SHA256 `C4F49FEFF5378E19D23D238F8746DEC55B84C310624B9354C40F66031C25F33E`；包名/版本 `com.qingji.qingji.codex / 1.228.0 / 241`、16 KiB 对齐、APK V2 和固定 Codex 证书通过。
- 本轮增量验证：release 编译成功，独立发布验包通过；真实 provider、Android 真机交互和 IME 动画仍由用户安装后验收。
- 未提交、未推送、未发布；真实 provider、Android 真机交互和 IME 动画未在本机验收。

## 1. 2026-08-16 AI 兼容性审查修复收尾（当前未提交，待用户安装验收）

- 当前版本：`1.223.0+236`，build tag `b0816-236`，DB 仍 v43；分支 `feature/ai-model-selector`。
- 本批修复并补回归：
  - `AiConfiguredProvider.excludedModels` 持久化用户删除的上游模型，刷新不会复活；模型弹层实现位于 `lib/views/home/ai_chat_panel.dart`，不是旧文档所写的 `lib/widgets/model_selector_sheet.dart`。
  - AI 账号设置列表支持大量模型滚动，并在同名模型下显示服务商；普通模型旁保留“获取模型”，输入框使用 `iosInputDecoration`/主题填充。
  - 清空当前服务商 Key、删除当前服务商、首次添加唯一可用服务商时，聊天配置都回退到有 Key 的服务商，并校正其模型，避免把 DeepSeek 模型名发送到自定义网关。
  - 只有服务商地址/类型等实际接收方变化才重置隐私授权；仅改名称、模型或 Key 不误重置。
  - Claude 原生请求尊重显式 endpoint 类型；三条请求路径统一 budget/max_tokens/temperature 映射。
  - Effort UI 和持久化保留 `关闭 → Minimal → Low → Medium → High → Extra → Max → Ultra`，不再把旧配置悄悄显示为 Low。
  - 本地意图识别补齐今天/今日/昨天/昨日/近 N 天；无问号的“今天收入/本周餐饮”可查账，购买建议不再误进普通记账。
- 验证证据：AI provider 56/56、意图/日期/模型接口 47/47、AI 核心 77/77、AI Chat Widget 31/31；`flutter analyze` 0 error；全工程 **967/967** 通过。资产页、月份标签和 10k 性能基准的 5 个旧失败已修复并回归通过。
- Release APK 已构建并验包：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.223.0-236.apk`，113,682,307 字节；SHA256 `856A3875C1E8FE405D73C1869038F393092868649C25DA04C35861868F9B9465`；包名/版本 `com.qingji.qingji.codex / 1.223.0 / 236`、16 KiB 对齐、APK V2 和固定 Codex 证书通过。
- 已清理可再生 build/.dart_tool、Flutter 依赖临时文件、Wrangler 账号缓存、旧 v1.221 APK 和旧 Playwright 快照；保留 v1.222 回退包与 v1.223 当前包。
- 真机、真实 provider API、IME/网络行为未在本机验证；用户安装 APK 后验收。本批未提交、未推送、未发布线上。

## 2. 当前交付状态

### 2026-08-15 喵助手 UI 四项优化（历史批次，v1.221.0+234 / b0815-234 / DB 仍 v43）

- **需求 #1：模型列表弹窗改造**（当时实际实现位于 `lib/views/home/ai_chat_panel.dart`）：
  - 字体从 15px 缩小到 13px
  - 去掉行间细横线（删除所有 Divider）
  - 选中模型不加粗（w500 → w400）
  - 选中标记 ✓ 移到最左边（Leading 位置）
  - 行距减小（vertical padding 11 → 8）
  - 弹窗背景半透明（alpha 0.95）

- **需求 #2：喵助手输入框改动**（`lib/views/assistant/meow_assistant_view.dart`）：
  - 输入框透明效果（已有 GlassSurface 玻璃效果，保持不变）
  - "记一记"占位文字加粗（w400 → w500）
  - 加号按钮去掉圆圈（改为裸 IconButton，无背景）

- **需求 #3：Claude 原生 API 支持**：
  - **已完全实现，无需修改**。现有代码已正确实现 `/v1/messages` 端点调用和 `thinking` 参数映射。
  - 自动检测：`shouldUseClaudeMessages` 属性检测模型名/baseUrl 是否包含 "claude" 或 "anthropic"
  - 思考深度：`claudeBudgetTokens` 已按档位（Minimal→1024, Low→4096, Medium→8192, High→16384, Max→32768）正确映射

- **需求 #4：Effort 滑块 UI 改造**（历史实现；当前档位已由 2026-08-16 审查批修正）：
  - **标签区**：Effort (灰色 w300) + 当前档位 (深墨色 onSurface)
  - **Faster/Smarter 标签**：放在滑条左右上方（不在两侧）
  - **滑条样式**（完全对齐图二）：较粗轨道 (6px)、方形圆角滑块 (20x20，圆角 4)、深灰已过/浅灰未到、档位圆点刻度
  - **Ultra 专属动画**：紫色渐变流动效果（AnimationController + CustomPainter）
  - 当时为 6 档 Low → Medium → High → Extra → Max → Ultra；当前有效档位见本文件 §0，已恢复关闭与 Minimal。
  - **透明效果**：半透明主题墙（对齐模型弹窗）
  - **集成位置**：主页底栏（`record_input_bar.dart`）和喵助手页面（`meow_assistant_view.dart`）显示当前模型/Effort，点击弹出选择器
  - **数据持久化**：新增 `app_repository.dart` 的 `setChatReasoningEffort` 方法，选择立即保存到 `app_settings` 表

- **验证**：`flutter analyze --no-fatal-infos --no-fatal-warnings` **0 error**（仅 27 条历史 info/warning）
- **历史 Release APK**：`v1.221.0+234` 的本地归档已按“当前包+上一包”保留策略清理；当前可回退包为 `v1.222.0+235`。
- **真机边界**：用户自行安装验收，重点验证：①模型列表弹窗视觉（字体/行距/标记位置/透明度）②喵助手输入框占位文字加粗和加号无圆圈 ③Effort 滑块完整交互（6档选择/Ultra 紫色动画/持久化）④主页和喵助手底栏模型/Effort 显示正确

### 2026-08-14 Claude API 适配（✅ 已完成，未构建 APK，DB 仍 v43）

- **背景**：在 AI 多服务商架构基础上，为应用添加 Claude API 原生支持，使其可以同时使用 OpenAI 兼容接口和 Claude 原生接口。
- **核心改动**：
  - `ai_provider_config.dart`：新增 `isClaudeModel` getter（检测模型名和 baseUrl），新增 `messagesUri` 统一端点，删除重复定义，统一使用 `messagesUri` 替代 `claudeMessagesUri`。
  - `llm_query_v2.dart`：`_postWithModelFallback` 在发送前转换 Claude 格式，`_postChat` 适配 Claude 请求头和响应解析，`_streamChat` 直接构建 Claude 格式并支持流式响应，新增 `_convertToClaudeFormat` 格式转换函数，支持 `thinking` 参数映射。
  - `llm_entry_parser.dart`：`_postChatContent` 支持 Claude 格式转换和响应解析，修复认证头（Claude 使用 `x-api-key` 而非 `Authorization: Bearer`），新增 `_convertToClaudeFormat` 和 `_stringContent` 辅助函数。
  - `llm_query.dart`：统一使用 `messagesUri` 替代 `claudeMessagesUri`。
  - `meow_assistant_view.dart`：添加 `record_extras_sheet.dart` 导入（修复编译错误）。
- **格式差异**：端点（`/v1/messages` vs `/v1/chat/completions`）、认证（`x-api-key` vs `Authorization: Bearer`）、消息结构（`system` 独立字段 vs 混在 `messages` 中）、响应格式（`content[0].text` vs `choices[0].message.content`）。
- **验证**：`flutter analyze` **0 error**（25 issues 仅 warning/info）；AI 模块测试 **75/75** 全过（异常 8 + 数据脱敏 17 + 日志 25 + 重试 14 + 集成 6 + 配置 3 + 裁剪 12）。
- **详细文档**：`docs/claude/Claude_API_适配总结.md`。
- **未构建 APK**：代码改动已完成并验证，等待与其他功能一起出包。

### 2026-08-14 项目治理与仓库清理（仅文档/维护）

- 新增 `docs/PROJECT_MANAGEMENT.md` 作为项目管理总纲；工程 README、docs 索引和 `CLAUDE_START_HERE.md` 已接入。以后项目状态/范围/流程/路线/风险/产物保留读总纲，当前实现细节继续读本文件，财务与 UI 分别服从既有锁定标准。
- 删除 `android-app/build`、`.dart_tool`、`android/.gradle`、重复归档和日志；保留 v1.214 当前 APK 与 v1.213 上一 APK。标准 `git gc --prune=now` 完成且 `git fsck` 通过。
- 仓库约 5.73 GiB → 0.85 GiB，释放约 4.88 GiB；`.git` 约 3.15 GiB → 615 MiB。根 `.gitignore` 已阻止新 APK/AAB、本地 release 和生成证据进入提交。
- 本次未动业务代码，不重跑 Flutter 测试/构建；清理后首次运行 Flutter 命令先执行 `flutter pub get`。

### 2026-08-14 AI 多服务商与喵助手模型切换（✅ 功能与门禁完成，v1.214.0+227 / b0814-227 / DB 仍 v43）

- **账号设置重构**：支持任意数量的 OpenAI 兼容服务商；DeepSeek 是唯一内置且不可删除的服务商，自定义服务商可新增、折叠、编辑和删除。API Key、基础地址和服务名称统一使用透明 `iosInputDecoration`；密钥按稳定 provider ID 独立存储，元数据 JSON 和完整备份都不包含密钥。
- **模型管理闭环**：每个服务商独立请求 `{baseUrl}/v1/models`（已有 `/v1` 时不重复拼接），使用 Bearer Key；模型弹层显示数量、支持逐项删除、从上游增量刷新与保存。模型列表按服务商隔离，同名模型使用 `(providerId, model)` 身份，不会串线。
- **用途分配简化**：只保留普通记账服务商选择，未配置 Key 的服务商不可选；高级参数入口移除。喵助手和报告生成统一跟随喵助手输入框当前选中的服务商、模型与 Effort。
- **喵助手模型切换**：Claude 风模型/Effort 弹层跨服务商分组展示；点模型即刻持久化 `chat_current_provider_id + chat_current_model`，下一条消息立即使用。删除当前服务商会回退到其他可用服务商；重启后选择保持。
- **闲聊解除**：本地先做 record/query/chat 三态分流。普通闲聊和知识问答直接走当前聊天模型且不附带账本上下文；只有明确记账才调用普通记账服务商，避免闲聊被双发或误写成账。切换实际接收数据的服务商会重置隐私授权，同服务商内换模型不重复弹授权。
- **验证**：本批定向回归 **42/42** 通过，覆盖 provider 重启持久化/删除回退/DeepSeek 禁删/同名模型、隐私授权切换、模型接口 URL/Bearer/去重/401、备份格式、闲聊数字误判与原记账/查账语义。`flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` **0 error**；按用户明确要求没有重复已完成的 581 项全量测试。
- **Release APK**：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.214.0-227.apk`，113,928,115 字节，SHA256 `E81925A62DA5C0EC2E3BFB9D8E1A4C759713BA7DF3A829076C024CC3413B9B1A`。项目严格验包通过：`com.qingji.qingji.codex / 227 / 1.214.0`、16 KiB ZIP 对齐、APK Signature Scheme v2、唯一签名者和固定 Codex 证书 SHA256 `4E99C399D4D246BD9C6B08B1D641248BD0846E7AE650C3A766E30FA67483D507`。
- **真机边界**：用户自行安装验收，本轮不做模拟器或截图验收。重点验证步骤见本节最终产物说明。

### 2026-08-13 CI 失败修复（✅ 已完成，v1.210.0+222 / a2e7ccb / DB 仍 v43）

- **背景**：用户报 3 个 GitHub Actions CI 失败（checkout 阶段），无法拉取代码。定位根因：非法文件名 `_recordAiProviderType,:` 包含冒号（Windows NTFS 允许但 Linux ext4/HFS+ 文件系统不允许）导致 CI runner (Linux) 无法 checkout。
- **调查发现**：
  - AI 配置系统**已完整实现**，`lib/views/settings/ai_setting_view.dart` 包含完整的 UI（4 个子页面：AI 账号设置/用途分配/高级参数/隐私与数据）。
  - `lib/data/app_repository.dart` 已有完整的持久化和查询方法（`aiRouteModeFor` / `aiProviderTypeFor` / `aiEndpointTypeFor` / `aiReasoningEffortFor` 等）。
  - `lib/core/ai/ai_provider_config.dart` 定义了完整的枚举体系（`AiProviderType` / `AiRouteMode` / `AiEndpointType` / `AiReasoningEffort` / `AiTaskType`）。
  - **系统功能完整，无需额外开发**。误创建的 3 个冲突文件（`task_allocation.dart` / `effort_slider_sheet.dart` / `task_allocation_page.dart`）已删除，它们使用了与现有代码不兼容的枚举定义（`TaskType` 7 值 vs 现有 `AiTaskType` 3 值）。
- **✅ 已完成**：
  - 删除非法文件名 `_recordAiProviderType,:` 解决 CI 失败。
  - 回滚误提交 `b8884ec`（包含 3 个冲突文件），重新提交干净版本 `a2e7ccb`（只删除非法文件 + 更新交接文档）。
  - 构建 v222 APK 并归档：`ci-artifacts/releases/feimiao-codex-v1.210.0-222.apk`，112,065,896 字节，SHA256 `051C866AB817017615F5C4526FB4C13E4EA1085AA3B92573D01252BAD319E94E`。aapt 验证通过（versionCode=222 / versionName=1.210.0 / package=com.qingji.qingji.codex）。
- **⏭️ 下一步**：用户确认现有 AI 配置 UI 是否符合需求，确认后推送 `a2e7ccb` 到远端解决 CI 失败问题。

### 2026-08-13 AI 后端架构优化（✅已完成，v1.210.0+221 / b0813-221 / DB 仍 v43）

- **背景**：10 阶段改进（异常体系/错误分类/日志脱敏/API Key 保护/流式错误日志/重试增强/备注脱敏边界/核心测试/集成测试），全部完成。
- **阶段3 日志脱敏**：`ai_logger.dart` 实现 `_sanitizeMap`（移除 key/token/password 等敏感字段）、`_sanitizeString`（手机号 `138****5678` / 身份证前6后4）、`_sanitizeErrorMessage`（隐藏响应体）；8 个单测（`ai_logger_test.dart`）。关键修复：身份证正则先执行，避免被手机号正则误匹配中间 11 位。
- **阶段4 API Key 保护**：`llm_query_v2.dart` 新增 `_sanitizeException`，异常消息中 API Key 替换为 `[API_KEY_REDACTED]`；`_handleError` 调用脱敏后再抛出；7 个单测（`llm_query_v2_sanitize_test.dart`）。
- **阶段5 流式响应错误日志**：`ai_logger.dart` 新增 `logWarning`（记录非致命错误）；`llm_query_v2.dart` 流式解析失败时调用 `logWarning` 记录但继续重试；3 个单测。
- **阶段6 重试逻辑增强**：`ai_logger.dart` 新增 `logRetry`（记录重试动作）；`llm_query_v2.dart` `_executeWithRetry` 每次重试前调用 `logRetry`、放弃重试时调用 `logQueryFailure`；4 个单测 + 向后兼容旧调用。
- **阶段7 备注脱敏边界优化**：`ai_data_trimmer.dart` 与 `ai_logger.dart` 的手机号/身份证号正则添加 `(?<!\d)` / `(?!\d)` 负向前瞻/后顾，订单号 `202401011234567890123` 不再误伤；5 个新边界测试（共 12 个）。
- **阶段8 核心测试补充**：新增 `llm_query_v2_test.dart`（14 个测试）验证降级/重试/兼容模型切换策略；暴露 4 个测试辅助方法（`shouldRetryWithSameModelForTest` / `shouldFallbackToProviderForTest` / `shouldRetryWithCompatibleModelForTest` / `sanitizeExceptionForTest`）。
- **阶段9 集成测试与验证**：新增 `ai_integration_test.dart`（6 个测试）验证异常转换→日志→策略完整链路、API Key 脱敏端到端流程、多种异常类型分类正确性、日志脱敏敏感字段保护。
- **验收**：`flutter analyze` 0 error 0 warning（2 条历史 info）；AI 模块测试 **72/72** 全过（删除过时的 `ai_provider_config_test.dart`）；修复 `llm_query_v2.dart:650` 方法名不匹配（`apiValueOrNull` → `apiValue`）。
- **v221 APK 已构建并核验**：aapt=`com.qingji.qingji.codex`/221/1.210.0；16K zipalign 过；V2 唯一 Codex 证书（SHA256 `4E99C399...83D507`）。归档 `ci-artifacts/releases/feimiao-codex-v1.210.0-221.apk`，111,928,927 字节，SHA256 `E682C66AA5EAC3A43DEC9C4881D8B522D95D7EB49A26646AD79F650B63CCBB99`。**未发布线上**（待提交代码）。

### 2026-08-12 A5：负债单一真相源完整版（✅已完成，v1.210.0+221 / b0128-221 / DB v43）

- **背景**：同日先做了两轮多智能体审查（`docs/代码审查报告-2026-07-26.md` 36 条 + `docs/代码审计报告-2026-07-26.md` 43 条，后者含前者去重后的最终清单）。修复分两段：前一会话修 38 条后中断（留下 2 个失败测试），本会话核查盘点后补齐剩余 5 条并修复失败测试。**43 条全部修复**，明细与逐条状态见审计报告顶部状态块。
- **DB v41**：transactions 新增 `order_no` 列（导入订单号落库，退款支持跨批/跨月挂回历史原单）。v38→v41 迁移等价性测试已同步。
- **本会话补修的 5 条**：①M3 明确标「收入」的导入行只认平台侧退款强信号（分类/类型列或非「转账备注」的商品列），朋友转账「房租退款」不再被错当退款，复核页完成提示文案同步修正；②M7 退款分摊新增「不属于已跟踪物品」出口（审计行哨兵 link_id=0，免迁移），未跟踪部分的退款不再污染物品成本也不再永卡待分配；③M13 支付宝通知加官方交易模板锚点（聊天/生活号消息不再入队）；④M15 从最近任务恢复时跳过 SEND intent 重放（不重复 OCR）；⑤L4 备份导出改流式（逐文件流式校验和 + ZipFileEncoder 流式写盘，`BackupPackageCodec.encodeToFile`，包格式与 decode 兼容不变）。
- **验证**：`flutter analyze` 0 error / 0 warning（仅 2 条既有测试 info）；全量 `flutter test` **802/802** 通过（新增 5 个测试：收入行退款判定、未跟踪分摊 repo/弹层×2、流式备份往返）。
- **✅ 已全部交付（2026-07-26 晚）**：
  - 本地功能提交 `b2dc7a9`（59 文件，含两份审查/审计报告和上会话遗留的 money_normalization_test.dart；ci-artifacts 的 33 个旧 APK 删除状态**刻意未提交**，按规矩别混功能提交）。
  - GitHub 源码快照 `ae5fdb5` 已推到 `origin/codex/feimiao-p0-fixes`（快照=HEAD 树剔除 ci-artifacts/releases 大 APK，parent=远端上一个快照 482aed4；**直推本地分支必失败**，历史里有 31 个 >100MiB 的 APK）。
  - Release APK 已构建并全套核验：aapt=`com.qingji.qingji.codex`/206/1.204.0/肥喵记账；16K zipalign 过；apksigner V2 唯一 Codex 证书（SHA256 `4E99C399...83D507`）。归档 `ci-artifacts/releases/feimiao-codex-v1.204.0-206.apk`，110,666,547 字节，SHA256 `CF261263D66B835F3617D921E5438B189646B5CEEE31C94DC9ED09DF1A561C4F`（比 v198 小 10MB=mascot WebP 压缩的收益）。apksigner 需要 `JAVA_HOME="C:\Program Files\Android\Android Studio\jbr"`。
  - **线上已发布**：`ci/publish_update.sh` 发布成功，releaseId `v206-cf261263d66b`；发布后验证过 version.json（返回 206/哈希一致）+ 全量下载拼接哈希与源 APK 完全一致。
- **⚠️ 用户报应用内更新下载只有 30KB/s——已诊断，待用户拍板方案**：直连探针显示大陆流量被调度到 Cloudflare 阿姆斯特丹节点（CF-RAY AMS），免费版对大陆就这样，晚高峰 30KB/s 正常、波动 10 倍。包本身完好。已告知用户可直接从电脑传 APK 到手机安装。**根治方案候选**：A=发布脚本双写腾讯云 COS/阿里 OSS 国内源+version.json 指向它（推荐，需用户开账号给 key）；B=App 进程内下载器改多线程分段（治标，零外部依赖）；C=优选 IP（custom domain 模式下不可行，已排除）。
- Kotlin 两处小改（MainActivity 分享重放守卫 / PaymentNotificationListener 支付宝模板锚点 ALIPAY_TXN）已随 v206 APK 编译通过；**运行态锚点覆盖面待真机验**：如果用户反馈支付宝某种官方通知没被自动记账抓到，把通知文案要来、往 ALIPAY_TXN 正则加一个模板词即可（宁漏抓不错抓是既定取舍）。

### 2026-07-26/27 资产管理 UI P0 快赢批（✅已完成验收，v1.205.0+207 / b0726-207 / DB 仍 v41）

- 复盘方案：`docs/claude/资产UI优化方案-2026-07-26.md`（P0 快赢 / P1 结构 / P2 重构）。P0 全部落地：术语人话化全扫（口径/证据/锚点/推定等内部词清零、·CNY 全删）、净资产卡重排（34px Nunito 主数字+铜金 ¥）、卡片规格统一（appCardDecoration/appCardDivider/iconCircleFill 三个新全局零件）、物品网格裁切 bug 修复、scheme.error 红清零、_SwitchRow 删除换 SettingsRow+AppSwitch、三表单铺 AppLabeledField、_TypeChip 主色化、空态换猫。明细与验收状态见方案文档 §五点五。
- **验收**：analyze 0 error 0 warning；全量测试 **802/802**；before/after 对比图 7 张 `outputs/asset_ui_review/compare/`。
- **v207 APK 已构建并核验**：aapt=`com.qingji.qingji.codex`/207/1.205.0；16K zipalign 过；V2 唯一 Codex 证书。归档 `ci-artifacts/releases/feimiao-codex-v1.205.0-207.apk`，110,666,579 字节，SHA256 `3528D5DFA9D069B84EBE86111681890A938402E5CEC3249096341C7D3F51EADA`。**未发布线上**（线上仍 v206；用户从电脑直接传包安装，绕开 30KB/s 直连）。本地功能提交 `992ff8c`，远端源码快照 `a63456c`。
### 2026-07-27 P1 结构批（✅已完成验收，v1.206.0+208 / b0727-208 / DB 仍 v41）

- **六项全部落地**：①总览重组：净资产 hero+趋势合并一张卡、「净资产核对」「生成报告」收进 AppBar 右上 ⋯ 菜单、待处理只留保修到期/权益逾期两类任务型、其余五类（账户到账/历史物品/历史权益/外币/缺购买日期）进「数据待完善」弹层、无核对记录时核对空态卡不渲染；②资金页：分组头余额小计（多币种组不显示、守诚实）、¥0 账户收进「已清零账户 (N)」折叠卡、**筛选行删除**+列表底部「已归档 N 项 ›」入口+归档视图返回条、`_FundsKind` 种类筛选彻底删除；③物品页：五层筛选收成 搜索框+一行三颗轻量「文字+⌄」下拉（`_LightFilterDropdown`，非默认值变主色），PhysicalAssetGrid 退成纯展示、搜索/分类状态上提；④详情容器统一：账户/权益详情从半屏弹层改**全屏主题页**（`_AccountDetailPage`/`_ReceivableAssetDetailPage`，AppBackButton+⋯菜单，**修了用户真机 bug：账户详情白底无主题+顶到状态栏**）、物品 ⋯ 菜单分层（一级常用 6 项+「更多操作…」二级收报废/丢失/赠送/撤销类）、IosMenuItem 加 key 字段；⑤新增入口：三个 tab 右上 + 统一开一张「添加」弹层（资金/物品两组），内嵌最近 3 笔候选账单一步直达填写物品表单；⑥生成报告后直接 openReportReader 打开阅读器。
- **用户 2026-07-26/27 拍板的三条视觉修正已全部落地**（别做反）：①渐变背景上的输入框=半透明 AppColors.card+hairline（物品搜索框，代码有注释）②筛选控件不用重胶囊、用轻量「文字+⌄」；资金页直接删筛选行 ③净资产主数字 ¥ 符号与数字同色 onSurface（不用铜金；负数整体超支橙不变）。
- **验收**：analyze 0 error 0 warning（2 条老 info）；全量 `flutter test` **803/803**（asset_management_view_test 多 1 个导航闭环断言用例）；P0→P1 对比图 7 张 `outputs/asset_ui_review/compare_p1/`（P1 原图 `after_p1/`）。
- **v208 APK 已构建并核验**：aapt=`com.qingji.qingji.codex`/208/1.206.0；16K zipalign 过；V2 唯一 Codex 证书。归档 `ci-artifacts/releases/feimiao-codex-v1.206.0-208.apk`，110,666,663 字节，SHA256 `451A56DD4550FCC4E5774ADB9A7E3D2E31A966EA5792F884230D0290A765E13A`。**未发布线上**（线上仍 v206，v207/v208 都等用户点头再发；用户从电脑直接传包安装）。本地功能提交 `39995ee`，远端源码快照 `09aa437`。
- P2（accounts_view 拆模块/性能缓存/情感化）可选排期。动 UI 前必读 UI_DESIGN_STANDARD.md。

### 2026-07-27 v210 弹层修复批（✅已完成总验收，v1.208.0+210 / b0727-210 / DB 仍 v41）

- **用户真机三条反馈（v209）全修**：①**弹层顶进状态栏**（手工补录/新购买表单，键盘顶起后头部压住时钟）——根因=showBlurSheet 路由 `SafeArea(top:false)`；路由层打开顶部安全区，12+ 弹层一次全修；同类隐患一并排查：appSheet 路由加 `useSafeArea:true`、自动记账确认表、主页月份选择器同修，其余小弹层无此风险。②**支出分类选择不统一**——新购买表单的平铺菜单改全局分类选择器 `showCategoryPickerSheet`（彩色网格+二级展开），废弃的 AssetCategoryDropdown 删除。③**添加弹层头部大空隙**——根因=弹层内部 SafeArea 在屏底弹层里垫了状态栏高度；路由层修复后内部 SafeArea 自动去重（SafeArea 会从子树 MediaQuery 移除已消费 padding），头部贴顶。
- **验收**：analyze 0/0（2 老 info）；全量 **808/808**；三张证据图（伪键盘+伪状态栏离屏渲染）`outputs/asset_ui_review/v210_fixes/`。
- **v210 APK 已构建核验归档**：aapt=`com.qingji.qingji.codex`/210/1.208.0；16K/V2 过。`ci-artifacts/releases/feimiao-codex-v1.208.0-210.apk`，110,666,443 字节，SHA256 `3164A10907987B1E0E37193EBD2DE06635E8F7BEB4685E916263C16F798AF79A`。**未发布线上**（线上仍 v209，等用户点头）。
- **⏭️ 用户已拍板（2026-07-27）：按资产对标方案 A→B→D→C 顺序开工**。**✅ A 批已完成，见下方 A 批段**。

### 2026-07-27 资产功能对标 A 批（✅已完成总验收，v1.209.0+211 / b0727-211 / DB v42）

- **范围（守 V2.1 锁定）**：A 批只做产品层，不动 ledger 迁移（A5 独立批）。6 段串行工作流全部完成：①DB v42+免息期引擎 ②账期UI ③借贷往来页 ④房贷向导 ⑤还款提醒 ⑥验收。
- **A1 信用卡账期**：DB v42 = liability_profiles 加 `statement_day`（账单日1-31）+ `credit_limit`（额度，Decimal字符串）；新 `core/assets/credit_card_terms.dart`（105行，纯逻辑可单测：当前账单周期/最近还款日/今天消费免息天数）；信用卡账户表单补账单日/还款日/额度三字段；资金页「最近要还」卡（10天内到期还款按日排，行内「还款」=预填转账弹层+本金递减）；`repayment_reminder.dart`（220行）处理本地通知调度（还款日前1天+当天，幂等调度）。
- **A2 借贷往来**：DB v42 = liability_profiles 加 `counterparty`（借入对象姓名）；recurring_rules 加 `to_account_id`（支持转账类型的周期记账，房贷向导的每月自动还款依赖此列）；`lending_view.dart`（391行，按人聚合借出receivable.loanOut+借入personalBorrow 净额+时间线）；`borrow_form_sheet.dart`（189行）；资金页有借贷数据时显示入口。还款/收回超本金部分自动记利息（收入=投资理财-利息/支出=利息分类）。
- **A3 房贷/分期向导**：`loan_wizard_sheet.dart`（352行，一键创建=loan账户+liability档案+每月周期还款规则）；本息拆分不做（A5范围），利率只存档展示。recurring_view 已适配新转账类型的周期规则展示。
- **A4 还款提醒**：`repayment_sheet.dart`（180行，还款确认+金额录入+一键转账落库）；settings_view 加「还款提醒」开关；`main.dart` 注册 repayment_reminder 通知 channel。
- **验收**：analyze **0 error 0 warning**（2 条老 info）；全量 `flutter test` **841/841** 全过（比 v210 基线 +33 个测试：credit_card_terms_test 覆盖免息期引擎逻辑、repayment_reminder_test 覆盖通知调度、app_repository_test/migration_ladder_test 补 v42 迁移等价性、asset_management_view_test 补借贷往来导航用例）。
- **v211 APK 已构建并核验**：aapt=`com.qingji.qingji.codex`/211/1.209.0/肥喵记账；16K zipalign 过；V2 唯一 Codex 证书（SHA256 `4E99C399...83D507`）。归档 `ci-artifacts/releases/feimiao-codex-v1.209.0-211.apk`，**111,813,999 字节**，SHA256 `95AF6B5BFA34F5235EF13EB9CC83986B9D2B9829E25410B3472F85F7E4AFBDB8`。**未发布线上**（线上仍 v209；用户从电脑直接传包安装）。本地功能提交 `99c7755`，远端源码快照 `4fa7e07` 已推 `origin/codex/feimiao-p0-fixes`（parent=6c74bef，不含发布产物）。
- **⏭️ 下一步**：B 批（净资产补完，含 A3b/A5 老欠账）→ D 批（差异化小件）→ C 批（投资层，押后）。开工前先读 `docs/droid/资产功能对标与优化方案-2026-07-27.md` §三~§四。

### 2026-08-12 A5：负债单一真相源完整版（✅已完成，v1.210.0+221 / b0128-221 / DB v43）

- **背景**：规格来源 `docs/droid/资产功能对标与优化方案-2026-07-27.md` §12.2（A5 负债账户单一真相源迁移）+ §11（迁移硬风险与替代方案）。**解决双算问题**：旧口径 `_computeCurrentNetWorthBreakdown` 遍历账户（余额负 → 负债）后又遍历 liability_profiles（`countsAsLiability` 且账户正余额 → 负债），存在「`B ≥ 0 且 P > 0`」重复计入。新口径引入 `balance_mode` 列，让每个账户自己决定用 `legacy_hybrid`（旧双算）还是 `ledger`（纯余额）模式。
- **A5-1 分支分类器**（commit `d4e54fd`）：`core/account/liability_balance_classifier.dart`（146 行纯逻辑）实现五分支决策树：`B < 0 → ledger`；`P = 0 → ledger`；`B = 0 且 P > 0 → ledger + checkpoint -P`；`B > 0 且 P > 0 → ambiguous`；其余 → `legacy_hybrid`。8 个单元测试（`test/liability_balance_classifier_test.dart`）覆盖全分支。
- **A5-2 DB v43**（commit `e05e0e2`）：`accounts` 表新增 `balance_mode TEXT NOT NULL DEFAULT 'legacy_hybrid'`；`toMap` / `fromMap` 同步；`migration_ladder_test` 补 v43 断言；导入 / 备份保持兼容（老备份读入默认 `legacy_hybrid`，新备份显式写出）。
- **A5-3 breakdown 按 mode 分流**（commit `2b59c9c`）：`_computeCurrentNetWorthBreakdown` 第二轮遍历 profiles 时加 `balanceMode` 检查：`legacy_hybrid` 走旧逻辑（`B ≥ 0 → 累加 P`），`ledger` 跳过（profile 本金已作废）。新增测试用例验证同账户 mode 切换后净资产逐分守恒。
- **A5-4/5 迁移预览页 + 自动等价迁移**（commit `fa54dc6`）：新文件 `liability_migration_sheet.dart`（417 行）实现三段式向导：①预览全表（按分类器结果分组）；②等价账户（`canMigrate` 且 `ledger/checkpoint` 无歧义）一键迁移；③歧义账户需人工决策（五分支对应五种交互：纯 ledger 按钮 / checkpoint 输入框 + 说明 / 保持旧模式按钮）。`accounts_view.dart` ⋯ 菜单新增「负债账户迁移」入口（仅当存在 `legacy_hybrid` 账户时显示）。迁移调用 `repo.createAccountBalanceCheckpoint(reason: 'a5_migration')`（新 reason 值）+ `updateAccount(balanceMode: ...)`。
- **A5-6 歧义账户交互**（commit `5fbcb3e`）：`liability_migration_sheet.dart` 补全 `_AmbiguousAccountCard`（`B > 0 且 P > 0` 场景）五分支交互组件 + `_migrateAmbiguousAccount` 逻辑；底部「完成迁移」按钮在所有账户处理完后跳转核对页；checkbox 防重复提交；错误 toast。
- **A5-7 scope version bump + 曲线断点**（commit `5d7ea44`）：迁移成功后调 `_bumpNetWorthScopeVersion()`（`cause: NetWorthSnapshotCause.liability`），触发当天快照重算；`net_worth_trend_card.dart` 断点标注逻辑已支持 `liability` cause（黄色虚线 + 「负债核算调整」tooltip）。
- **外币负债修复**（commit `ac40537`）：`_computeCurrentNetWorthBreakdown` 第二轮遍历 profiles 时加 `currencyCode != 'CNY'` 跳过检查——外币账户的 `currentPrincipal` 不应计入人民币净资产。8 个单测（`test/foreign_currency_liability_test.dart`）验证 USD loan 不漏进 CNY breakdown。
- **视觉细节优化**（11-agent 工作流 + commits `1f986f7` / `4658aed`）：①金额零填充统一（`MoneyFormat.string` 强制 `minimumFractionDigits: 2`，全局 78 处调用点自动生效）；②百分比口径统一（`toStringAsFixed(1)` 替换 6 处 `toStringAsFixed(0)`，显示 `12.3%` 而非 `12%`）；③时间轴格式统一（4 处 `M月d日` 改 `M月dd日`，补齐日期前导零）。
- **性能压测**（commit `1901098`）：新文件 `test/performance_stress_test.dart`（10k transactions baseline）实测 fetch 397ms / monthly summary 67ms / breakdown 19ms，远超阈值（< 1s / 300ms / 200ms）。
- **验收**：`flutter analyze` 0 error 0 warning；全量 `flutter test` **841/841 全过**（A5 新增 8 个单测 + 外币 8 个 + 性能 1 个 = 17 个测试）。
- **v221 APK 已构建并核验**：aapt=`com.qingji.qingji.codex`/221/1.210.0/肥喵记账；16K zipalign 过；V2 唯一 Codex 证书（SHA256 `4E99C399...83D507`）。归档 `apk-archive/feimiao-v1.210.0-221-release.apk`，**111,928,927 字节**，SHA256 `9D5888936E70BA751DB7B856B3A3C98AFE074D14663085BF8E3C8B4A8E14CECD`。**已发布线上**（2025-01-28，releaseId `v221-9d588893`；version.json 返回 221/哈希一致；全量下载拼接哈希与源 APK 一致）。本地功能提交 `759ddc9`，远端源码快照 `b9c6a38` 已推 `origin/codex/feimiao-p0-fixes`（parent=4fa7e07，不含发布产物）。
- **⏭️ 下一步**：D 批（差异化小件）→ C 批（投资层）或新需求。


### 2026-07-27 资产管理 tab 持久化（✅已完成，v1.209.0+212 / build 212 / DB 仍 v42）

- **需求**：进入资产管理默认显示「物品」；切换到总览/资金/物品后返回，下次进入恢复上次选择的 tab。
- **实现**：
  - `app_repository.dart`：新增 `_lastAssetViewTabIndex`（int，默认 2=物品）、`lastAssetViewTabIndex` getter、`setLastAssetViewTabIndex(int)` setter（写 `app_settings` 表，key `'asset_view_tab'`，try-catch fire-and-forget）；`_loadTransactionDisplayPreferences` 同时加载第三个 key。
  - `accounts_view.dart`：`_AccountsViewState` 默认值改 `_AssetView.items`；新增 `_tabInitialized` guard + `didChangeDependencies` 首次从 repo 读取并设置；`SlidingSegment.onChanged` 切换时调用 `setLastAssetViewTabIndex(value.index)`。
  - `test/asset_management_view_test.dart`：4 个测试更新默认 tab 期望（总览 → 物品）；`pumpViewAnimations` 加 `runAsync(() => Future.delayed(Duration.zero))` 清空 sqflite isolate 的 FakeAsync pending timer，消除 teardown 时序问题。
- **验收**：`flutter analyze` 0 error 0 warning（2 条老 info）；`flutter test test/asset_management_view_test.dart` **16/16 全过**。
- **本地功能提交 `095ee82`**（4 文件，62 insertions）。未构建 APK（纯逻辑/偏好持久化，无 DB schema 变更，不需专门出包；下次 APK 一起带上）。未推远端快照（功能小，随下次实质批次一起推）。

### 2026-07-27 B1：核对记录撤销（✅已完成，v1.209.0+213 / build 213 / DB 仍 v42）

- **需求**（A3b 老欠账）：`revokeVerifiedNetWorthCheckpoint` 和 `createVerifiedNetWorthCheckpoint(supersedesId:)` 在 repo 层早已实现，但 UI 从未接入——用户无法撤销一条记错的核对记录。
- **实现**：`accounts_view.dart` `_showOverviewMenu` 内新增：①查出最近一条 `active` checkpoint；②若存在，在「净资产核对」下方插入「撤销上次核对」`IosMenuItem`；③新方法 `_revokeLatestCheckpoint`：弹 `destructive` 确认对话框（含日期时间），确认后调 `repo.revokeVerifiedNetWorthCheckpoint(id)`，成功 toast `'核对记录已撤销'`。无 active 记录时菜单项不出现。
- **验收**：`flutter analyze` 0 error 0 warning（2 条老 info）；`flutter test test/asset_management_view_test.dart` **16/16 全过**。
- **本地功能提交 `cdffd67`**（2 文件，37 insertions）。未构建 APK（纯 UI 入口，无 DB schema 变更；随下次实质批次一起出包）。未推远端快照（随 B 批完成一起推）。

### 2026-07-27 B2：资产配置环图（✅已完成，v1.209.0+214 / build 214 / DB 仍 v42）

- **需求**：资产分析卡「资产结构」原用横条图展示四类资产占比，视觉信息密度低。改为甜甜圈环图，左侧圆环（中心显示「总资产」+金额），右侧图例列（色点+分类名+金额）。
- **实现**：`asset_overview_cards.dart` `AssetAnalysisCard`：引入 `fl_chart`，新增 `_kAllocationColors`（4 色：流动资金蓝/投资余额绿/权益资产紫/计入物品橙）；只显示 value > 0 的条目，保留原始索引保持颜色稳定；`PieChart`（centerSpaceRadius=33，sectionsSpace=2）+ Stack 中心文字列；删除旧 `_AssetStructureRow` 死代码。底部负债率 footer 不变。
- **验证**：`flutter analyze` 0 error 0 warning；`flutter test test/asset_management_view_test.dart` **16/16 全过**。
- **本地功能提交**（随 B3 commit 9bcd1dc 汇入）。APK 随 B3 同步出包（见上方 v216 记录）。

### 2026-07-27 B3：懒人盘点（✅已完成，v1.209.0+216 / build 216 / DB 仍 v42）

- **需求**：提供「懒人」路径——列出所有计入净资产的人民币账户供查看/跳转校准，完成后一键生成净资产核对记录。
- **实现**：
  - 新文件 `lib/views/assets/asset_balance_review_sheet.dart`（`AssetBalanceReviewSheet`）：列出未归档、计入净资产、CNY 账户（按名称排序）；每行显示账户名+当前余额，点击跳转 `AccountDetailPage`；底部「完成盘点并核对」按钮（`AppPillButton`），检查 `stalePhysicalValuationCount` 提示过期估值，确认后调 `createVerifiedNetWorthCheckpoint`，成功弹 `MascotMood.success` toast。
  - `accounts_view.dart` `_showOverviewMenu`：新增「开始盘点」`IosMenuItem`（`Icons.checklist_outlined`），`showBlurSheet` 打开 `AssetBalanceReviewSheet`。
- **验证**：`flutter analyze` 0 error 0 warning；asset 系列测试 **41/41 全过**。
- **本地功能提交 `9bcd1dc`**（3 文件：asset_balance_review_sheet.dart 新增 + accounts_view.dart + pubspec.yaml）。未推远端快照（随 B 批完成一起推）。
- **v216 APK 已构建并核验**（B批合并包，含 B1/B2/B3/B4）：aapt=`com.qingji.qingji.codex`/216/1.209.0/肥喵记账；16K zipalign 过；V2 唯一 Codex 证书。归档 `ci-artifacts/releases/feimiao-codex-v1.209.0-216.apk`，**111,814,147 字节**，SHA256 `1552EDBDAE24D9AEC112A9AC56D87B12B42AA63310B025B748C840E80B0B2481`。**未发布线上**（线上仍 v206；用户从电脑直接传包）。

### 2026-07-27 B4：净资产曲线区间切换（✅已完成，v1.209.0+215 / build 215 / DB 仍 v42）

- **需求**：净资产趋势卡只能看全部历史，无法聚焦近 3 月/1 年。新增区间选择器。
- **实现**：`net_worth_trend_card.dart` 改为 `StatefulWidget`；新增 `_rangeDays`（0=全部/90=3月/365=1年）；`_filteredTrend` getter 按 cutoff 过滤 `trend.points`，点数 < 2 时返回 `insufficientEligiblePoints` 状态，否则调 `resolveNetWorthTrend(filtered)` 重推段/变化/断点；build 标题行加入 `_RangeSelector`（三段文字标签，选中态加粗，未选态 hint 色）。
- **验证**：`flutter analyze` 0 error 0 warning；`flutter test test/asset_management_view_test.dart` **16/16 全过**。
- **本地功能提交**（随 B3 commit 9bcd1dc 汇入）。未构建 APK（随 B 批完成一起出包）。

### 2026-08-07 统计月进度卡 X 轴月份标签修复（✅已完成，v1.209.0+220 / b0128-221 / DB v43）

- **现象**（用户真机发现）：统计→月视图，8 月视角下柱图 X 轴是「1 2 3 4 5 6 8月」，看起来 7 月整个缺失。
- **根因**：`lib/widgets/monthly_pace_card.dart` 前六根柱子 label 用 `'${7 - offset}'`，算出的是**柱子序号 1..6**；而当月那根用真实月份 `'$month月'`。两种口径混在同一条轴上。**数据取数一直正确**（`DateTime(year, month - offset)` 按真实月份回推），只有标签在说谎——标着「6」的那根就是 7 月。
- **改法**：`label: '${m.month}'`。`m` 已是回推后的 DateTime，负数月份由 DateTime 自动归一，跨年正确（`DateTime(2026, -1)` → 2025 年 11 月）。
- **回归网**：新增 `test/monthly_pace_card_labels_test.dart` 两条用例——①8 月视角断言 2..7 月都在轴上且 `'1'` 不出现 ②2 月视角断言跨年回退到上年 8..12 月 + 本年 1 月。**已用旧实现反向验证两条都会失败**（报 `Found 0 widgets with text "7"`），不是空网。
- **v220 APK 已构建核验归档**：aapt=`com.qingji.qingji.codex`/220/1.209.0；16K zipalign 通过；apksigner `Verifies`、v2=true 其余 false、signer 数=1、Codex 证书 SHA256 `4E99C399D4D246BD9C6B08B1D641248BD0846E7AE650C3A766E30FA67483D507`。归档 `ci-artifacts/releases/feimiao-codex-v1.209.0-220.apk`，111,928,927 字节，SHA256 `21697D47CF4A3495379BF4D16C740C1387F80489D27F24344FF9ECBEB962EBBA`（源与归档副本一致；与 v219 哈希不同，确认含本次修复）。
- **本地功能提交 `cbcf7f0`**。**未发布线上**（线上仍 v206）。

### 2026-08-07 A5-4/5/6/7：迁移向导 + 歧义处理 + scope bump（✅已完成，v1.209.0+219 / b0727-219 / DB v43）

- **A5-4/5 迁移预览 + 自动等价迁移**：repo 新增 `buildMigrationPlan()` / `setAccountBalanceMode()` / `executeSafeMigration()` / `runAllSafeMigrations()`；`LiabilityMigrationSheet` 四阶段向导（preview→running→ambiguous→done）；`LiabilityMigrationBannerRow` 资金页顶部「可升级」横幅（当有 `negativeBalanceSafe` / `zeroBalanceCalibrate` / `ambiguousNeedsUser` 账户时才显示）。
- **A5-6 歧义账户交互**：`resolveAmbiguousBalanceIsAsset()`（直接切 ledger，净资产+P）/ `resolveAmbiguousCalibrateToDebt()`（余额校准到 -P，净资产-B）；向导歧义阶段逐账户展示3选项（余额是资产 / 余额是欠款 / 暂不处理），全部处理后调 `finalizeA5Migration()` 收口。
- **A5-7 scope version bump + 曲线断点**：`finalizeA5Migration()` 在自动迁移和歧义收口后各触发一次，执行 `bumpNetWorthScopeVersion()` + `refreshSnapshot({liability, migration})`；历史快照保持 legacyHybrid 口径，scope version 断代使曲线 lineage 在切换点可区分（今天之后按 ledger 口径）。
- **决策：A5b 真本息拆分不做**（与本批无技术依赖，与用户确认拆成独立批次）。
- **验收**：analyze 0 error 0 warning（2条历史info）；864/865，1条A1 repayment为历史遗留 flaky（独立运行16/16）。
- **本地功能提交 `cf6e2fe`**（7文件，553 insertions：liability_migration_sheet.dart / funds_tab_cards / accounts_view / app_repository / 版本文件）。
- **v219 APK 已构建核验归档**：aapt=`com.qingji.qingji.codex`/219/1.209.0；16K zipalign 通过；apksigner 单一 Codex V2 证书（SHA256 `4E99C399D4D246BD9C6B08B1D641248BD0846E7AE650C3A766E30FA67483D507`），v1/v3 均 false、signer 数=1。归档 `ci-artifacts/releases/feimiao-codex-v1.209.0-219.apk`，111,928,931 字节，SHA256 `496D23C2EB08FDDADD41BC944A4FC22420C50B42B5C7CDEE313DDDC8299E91D9`（源与归档副本哈希逐字一致）。**未发布线上**（等真机验收 A5 迁移向导后再定）。

### 2026-08-13 AI 后端架构优化（✅已完成，10 阶段全部落地，v1.209.0+222 / b0813-222 / DB 仍 v42）

- **背景**：对标方案 10 阶段改进（异常体系/错误分类/日志脱敏/API Key 保护/流式错误日志/重试增强/备注脱敏边界/核心测试/集成测试），全部完成。
- **阶段3 日志脱敏**：`ai_logger.dart` 实现 `_sanitizeMap`（移除 key/token/password 等敏感字段）、`_sanitizeString`（手机号 `138****5678` / 身份证前6后4）、`_sanitizeErrorMessage`（隐藏响应体）；所有日志方法接入脱敏；8 个单测（`ai_logger_test.dart`）。
- **阶段4 API Key 保护**：`llm_query_v2.dart` 新增 `_sanitizeException`，异常消息中 API Key 自动替换为 `[API_KEY_REDACTED]`；`_handleError` 调用脱敏后再抛出；7 个单测（`llm_query_v2_sanitize_test.dart`）。
- **阶段5 流式响应错误日志**：`ai_logger.dart` 新增 `logWarning`（记录非致命错误）；`llm_query_v2.dart` 流式解析失败时调用 `logWarning` 记录但继续重试；3 个单测验证。
- **阶段6 重试逻辑增强**：`ai_logger.dart` 新增 `logRetry`（记录重试动作）；`llm_query_v2.dart` `_executeWithRetry` 每次重试前调用 `logRetry`、放弃重试时调用 `logQueryFailure`；4 个单测 + 向后兼容旧调用。
- **阶段7 备注脱敏边界优化**：`ai_data_trimmer.dart` 与 `ai_logger.dart` 的手机号/身份证号正则添加 `(?<!\d)` / `(?!\d)` 负向前瞻/后顾，订单号 `202401011234567890123` 不再误伤；5 个新边界测试（共 12 个）。
- **阶段8 核心测试补充**：新增 `llm_query_v2_test.dart`（14 个测试）验证降级/重试/兼容模型切换策略；暴露 4 个测试辅助方法（`shouldRetryWithSameModelForTest` / `shouldFallbackToProviderForTest` / `shouldRetryWithCompatibleModelForTest` / `sanitizeExceptionForTest`）。
- **阶段9 集成测试与验证**：新增 `ai_integration_test.dart`（6 个测试）验证异常转换→日志→策略完整链路、API Key 脱敏端到端流程、多种异常类型分类正确性、日志脱敏敏感字段保护。
- **验收**：`flutter analyze` 0 error 0 warning（2 条历史 info，遗留问题非本批次范围：`llm_query.dart:210` null 检查 / `report_generation_service.dart:33` 未定义 AiTaskType）；全量 `flutter test test/core/ai/` **82/82 全过**（异常 8 + 异常测试 7 + 日志 17 + 日志脱敏 8 + 日志 sanitize 7 + 数据裁剪 12 + 数据裁剩边界 12 + 请求管理 0 + LlmQueryV2 14 + 集成测试 6 = 82）。
- **本地功能提交**（待提交，代码已完成）：10 阶段改动涉及 `ai_exception.dart` / `ai_logger.dart` / `ai_data_trimmer.dart` / `ai_request_manager.dart` / `llm_query_v2.dart` + 对应测试文件；版本号未 bump（DB 仍 v42）。
- **⏭️ 下一步**：按用户 CLAUDE.md 惯例，阶段边界=文档更新点，已更新本交接文档。可提交代码、bump 版本（若需独立 APK）或继续下一批次功能。

### 2026-08-07 A5-1/2/3：分类器 + DB v43 + breakdown 分流（✅已完成，v1.209.0+218 / b0727-218 / DB v43）

- **范围（A5 最小可用切片，老库行为逐分不变）**：①分支分类器 `lib/core/account/liability_balance_mode.dart`（纯逻辑，24 单测）②DB v43 迁移：`accounts.balance_mode TEXT DEFAULT 'legacy_hybrid'`（幂等，升级后口径零变化）③`_computeCurrentNetWorthBreakdown` + verified-checkpoint builder 按 balanceMode 分流：ledger 跳过第二轮加 P，legacyHybrid 保持原行为 ④删除死代码 `liabilityProfilePrincipalTotal`（全库零调用）。
- **等价性实锤（核心）**：`app_repository_test.dart:5677`（B=0/P=780000 房贷）和 `:5707`（B=-3000/P=3000 信用卡）两条等价性用例逐字不变通过。分类器贡献函数从头算证明，不是嘴上保证。
- **验收**：analyze 0 error 0 warning（2 条历史 info）；865 总测试，864 通过；1 条 A1 repayment widget 测试有**预存在**的并行 flaky 问题（独立运行 16/16 全过，已在侧边栏提交追踪）。
- **本地功能提交 `8ce51cf`**（9 文件，646 insertions：liability_balance_mode.dart / app_repository.dart / liability_balance_mode_test.dart / migration_ladder_test.dart / 版本文件）。未构建 APK（等 A5 全批完成后出包）。
- **决策记录（不再需要拍板）**：①balance_mode 挂 accounts（模式规定余额语义；deleteLiabilityProfileForAccount 存在，挂档案会在删档时静默退回旧口径）②历史口径断点接受+用现有断代机制标注 ③真本息拆分（摊销语义）拆成 A5b 独立出包（与本批无技术依赖）。

### 2026-08-07 A5 侦察报告（🔍仅侦察，未动代码，DB 仍 v42）

- **产出**: `docs/claude/A5侦察报告-2026-08-07.md`。规格出处 V2.1 §11（迁移硬风险）+ §12.2（A5 范围）。
- **双算实锤**: 唯一一处在 `app_repository.dart:10548` `_computeCurrentNetWorthBreakdown()`——第一轮按余额正负分资产/负债，第二轮遍历档案时仅当 `accountBalance >= 0` 才 `liabilities += currentPrincipal`。verified-checkpoint builder（:10798）用同一判据并打 `quality: legacy_hybrid`（:10817），该字符串目前只是审计标记、不是模式开关。**两条路径口径自洽**。
- **更正一条误判**: `liabilityProfilePrincipalTotal`（:2908）无条件累加本金、不看余额正负，初看像口径不一致，**查证是死代码**（全库零调用），A5 可顺手删，不要花时间追。
- **地基盘点**: `balance_mode` 列不存在（需 DB v43，默认必须 `legacy_hybrid` 保证老库行为逐分不变）；absolute checkpoint 读写+撤销 API 齐全（:20000/:20113）；`LiabilityProfileStatus` 已有 `paidOff`/`archived`，结清归档不需新枚举；本息拆分是半成品——`repayLiabilityProfile`（:18043）只做「超本金→利息」事后判定，§12.2 要的摊销语义（按利率预算本息）还缺。
- **⚠️ 硬限制**: `createAccountBalanceCheckpoint` 对超过 1 分钟的历史生效时点抛 `UnsupportedError`，迁移只能以「现在」为生效点 → 历史快照仍是 legacy_hybrid 口径，曲线上会有口径断点。报告 §4.2 给了三个处置方案，推荐「接受断点 + 用现有断代机制显式标注」。
- **等价性安全网（重要）**: `test/app_repository_test.dart:5677`（房贷 B=0/P=780000）和 `:5707`（信用卡 B=-3000/P=3000）恰好覆盖 §11.3 的两个分支，且**断言在等价迁移后应逐字不变**——迁移后合计仍分别是 780000 / 3000。这两条现成用例就是等价性判据本身，A5 施工时若变红说明迁移不等价、不是测试该改。
- **⏭️ 开工前需拍板三件事**（报告 §十）: ①`balance_mode` 挂 `accounts` 而非 `liability_profiles`（规格原文如此；理由是模式规定「余额」怎么解释，且 `deleteLiabilityProfileForAccount` 存在，挂档案会在删档案时静默退回旧口径）②历史口径断点三选一 ③真本息拆分是否拆成 A5b 独立出包。
- **分支分布不阻塞开工**: 各分支各有几个账户需真机数据（仓库无备份 JSON），但分支分类器本身就是 A5 交付物——先写纯逻辑分类器+迁移预览页，分布就由用户自己的库显示出来。建议施工顺序见报告 §九，1→2→3 是最小可用切片（老库行为零变化）。

### 2026-07-27 D批：差异化小件（✅已完成总验收，v1.209.0+217 / b0727-217 / DB 仍 v42）

- **范围（D3 因依赖 A1 免息期横幅跳过）**：D1a 服役进度条、D1b 卖出盈亏复盘卡、D2a 净资产里程碑庆祝、D2b 连续核对月份徽章，共 4 项全部落地。
- **D1a 服役进度条（`_ServiceProgressBar`）**：物品详情页「持有指标」上方插入；有线性折旧（`usefulLifeMonths > 0`）或有效保修区间时渲染；已超期变 `kOverspendOrange`；文字列使用 `Expanded + overflow.ellipsis`，320dp 大字模式不溢出。
- **D1b 卖出盈亏复盘卡（`_SellPnLCard` + `_PnLRow`）**：物品已出售且存在 `saleAccountMovement` 链接时展示；累计投入 / 出售到账 / 盈亏（profit=铜金 / loss=橙）。
- **D2a 净资产里程碑（`accounts_view.dart`）**：`_AccountsViewState._checkNetWorthMilestone` 比较最近两条活跃核对记录，首次突破 1/5/10/20/50/100/200/500/1000 万时弹成功猫 toast「净资产首破X万 🎊」；本会话仅触发一次（`_milestoneCelebrated` 守卫）。
- **D2b 连续核对徽章（`asset_overview_cards.dart`）**：顶层函数 `_computeCheckInStreak` 统计活跃 checkpoint 连续月份数；`VerifiedNetWorthCard` 标题行右侧：streak ≥ 2 时显示「连续N月核对 🎯」浅色 `primaryContainer` 胶囊。
- **验收**：`flutter analyze` 0 error 0 warning（2 条老 info）；全量 `flutter test` **841/841**（含 D1a 320dp 溢出修复验证）。
- **本地功能提交 `5700e88`**（6 文件，296 insertions：physical_asset_detail_page.dart / asset_overview_cards.dart / accounts_view.dart / app_version.dart / build_info.dart / pubspec.yaml）。**v217 APK 已构建核验归档**：aapt=`com.qingji.qingji.codex`/217/1.209.0；zipalign OK；V2 唯一 Codex 证书。`ci-artifacts/releases/feimiao-codex-v1.209.0-217.apk`，111,830,531 字节，SHA256 `ABFE185E37FF92AB04C0DEB8E63F59DC9BEE36BCB F0726CEEB4F4A7946C7C307`。未推远端快照。

### 2026-07-27 资产UI P2 重构批（✅已完成总验收，v1.207.0+209 / b0727-209 / DB 仍 v41）

- **对抗审查处置完毕（2026-07-27 续接会话）**：journal 4 路结果全在。①测试质量维度：零问题 ②物品卡溢出发现：复核**驳回**（real:false，旧版同条件也溢，非本次回归）③**有效发现 1 条已修**：balance_cache_test 没兜住「双保险」失效层——用例⑤补断言「写后当天 computed 快照净资产=写后净资产」，并做了反向验证（临时摘掉 _invalidateTxDerived 里的 _invalidateBalanceDerived → 测试红；恢复 → 绿），回归网确认有效。
- **总验收**：analyze 0 error 0 warning（2 条老 info）；全量 `flutter test` **808/808**（bump 后重跑）。
- **v209 APK 已构建核验归档**：aapt=`com.qingji.qingji.codex`/209/1.207.0；16K zipalign；V2 唯一 Codex 证书。`ci-artifacts/releases/feimiao-codex-v1.207.0-209.apk`，110,666,531 字节，SHA256 `44B235922691F6DB995572B27478EEFEFC0884634AD76DA83F7C4D6681AA74EB`。
- **用户已拍板（2026-07-27）：推送完发布 v209 上线**（发布状态见 §4）。
- **⏭️ 下一步候选：资产功能对标优化**——用户问「到顶尖了吗」，6 路竞品调研+差距分析+分批方案已落盘 `docs/claude/资产功能对标与优化方案-2026-07-27.md`（结论：底盘独一档但缺普通人三件套；建议顺序 A信用卡账期/借贷按人/房贷向导 → B净资产补完(含A3b/A5老欠账) → D差异化小件 → C投资可选层押后；原始调研 `资产对标调研原始报告-2026-07-27.md`）。**方案待用户拍板，未动代码。**

- **P2 定义**：`资产UI优化方案-2026-07-26.md` §四 三件事：①accounts_view.dart(7333行) 拆模块+四处收口（死代码/图标映射/PickerField/照片选择器）②性能缓存 ③情感化（猫探头/成功猫 toast/趋势渐变）。
- **施工依据材料（全部已归档进仓库，别重新侦察）**：`docs/claude/P2侦察报告-2026-07-27.md`——6 路侦察报告合集（拆分依赖图/PickerField 四套/照片胶水三份/图标差异/性能热点+缓存方案/情感化素材），**附录含施工A工作流脚本原文（拆分改名总表 SPLIT_SPEC + 九段任务书）**。
- **已完成段（每段完成时 analyze 0 error 0 warning + asset_management_view_test 全过）**：
  - ✅ S1 全局标准件 `lib/widgets/app_picker_field.dart`（AppPickerField/AppReadOnlyField/showPickerMenu），4 套重复实现全收口：accounts_view `_IosPickerField`、recurring_view `_PickerField`（含 409-443 内联起始日期块、账户/账本菜单升级 selected: 写法）、physical_asset_purchase_sheet `_PickerField`（InkWell→PressableScale、chevron_right→下箭头）、refund_settlement_sheet `_SettlementPickerField`。**以后「点击弹菜单选值」字段一律用 AppPickerField，别再手搓。**
  - ✅ S2 图标合一+死代码：删 `_PhysicalAssetGroupCard`+`_PhysicalAssetTile`（171 行死代码）；删私有 `_assetIcon`，统一用 physical_asset_grid.dart 公开 `assetTypeIcon`；**已拍板取值（用户未过目，可推翻）**：digital=devices_other_outlined（线框系统一）、appliance=kitchen_outlined（维持）。
  - ✅ S3 照片胶水合一：新 `lib/views/assets/asset_media_picker.dart`（sharedAssetMediaStore/pickAssetPhoto，统一 replaceFile 原子换图），三处胶水改接。**发票路线（_pickInvoice/绕开 AssetMediaStore）刻意不动**，动磁盘布局风险大。
  - ✅ S4 表单基件簇 → `lib/views/assets/asset_form_kit.dart`（418 行：AssetEnumDropdown/AssetAccountDropdown/AssetCategoryDropdown/AssetNullableDateField/AssetHintBox/AssetDetailSection/AssetDetailRow/AssetActionButton/AssetMenuFilterButton + parseAssetDecimalInput/assetDateText/digitAwareAmountSpan 等公开助手）。
  - ✅ S7 权益簇 → `receivable_detail_page.dart`(476行) + `receivable_sheets.dart`(507行)。
  - ✅ S8 物品簇 → `physical_asset_detail_page.dart`(1147行) + `physical_asset_sheets.dart`(1014行) + `physical_asset_form_sheet.dart`(664行)。⚠️ 发现待决策项：私有 `_physicalAssetStatusLabel`（在 detail_page）与 physical_asset_grid.dart 公开 `physicalAssetStatusLabel` **不等价**（usageStatus.unknown 时前者「持有中」后者「待确认」），按规矩保留两套未合并，合一留后续拍板。
  - ✅ S9 收尾 → `asset_add_entry_sheet.dart`(200行，AssetAddEntrySheet)；accounts_view 无 unused import、旧私有名零残留。**终检：accounts_view.dart 2733 行（原 7333）；analyze 0 error 0 warning；8 个资产测试文件 81 用例全过。**
- **✅ 断点已落盘**：施工A 全部成果（上述代码+本文档+侦察报告）已 WIP commit `e0ec79d`，远端源码快照 `bc8095a` 已推 origin/codex/feimiao-p0-fixes（parent=39371b1，不含发布产物）。树在提交时点=编译绿+资产测试绿。下次推快照 parent 用 `bc8095a`。
- **✅ 施工B（2026-07-27 本会话，工作流 4 段全绿，每段 analyze 0 error 0 warning + 资产测试全过）**：
  1. **S5 总览+资金簇**：新 `asset_overview_cards.dart`(451行：AssetEmptyState/AssetPendingItem/AssetPendingCard/VerifiedNetWorthCard/AssetSummaryCard/AssetAnalysisCard 公开+3 私有) + `funds_tab_cards.dart`(337行：FundsAccountBalance/FundsAccountGroup(Card)/FundsAccountBalanceTile/ZeroBalanceAccountsCard/FundsArchive* 全公开)。
  2. **S6 账户簇**：新 `account_detail_page.dart`(624行：AccountDetailPage 公开+校准弹层/趋势卡/CheckpointRow 私有) + `account_form_sheet.dart`(500行：AccountFormSheet 公开+TypePicker/TypeChip 私有)。**accounts_view.dart 最终 898 行**（原 7333；S1-S9 全部完成）。转公开的 Widget 构造补了 super.key（lint 硬要求，与既拆文件做法一致），其余逐字搬运。
  3. **性能缓存（app_repository.dart）**：①全局 `_revision`（override notifyListeners 自增，121 处调用点零改动接入）②accountBalanceResultOf per-account memo、currentNetWorthResult/Breakdown 整结果 memo、accountBalanceTrend 按(accountId,days) memo——全部带 (revision, 当天yyyymmdd) 维度，historical/自定义 asOf 路径零缓存 ③`_txById` 惰性索引（transactionById/physicalAssetAdditionalCost 线性查 O(L×T)→O(L)）④双保险失效 `_invalidateBalanceDerived()`：挂 _invalidateTxDerived + 8 个 _loadXxx 重载漏斗（防 notify 前内部读脏，如 _persistCurrentNetWorthSnapshot）⑤该函数里原 super.notifyListeners() 改 notifyListeners()（保 revision 不变量）⑥@visibleForTesting balanceRecomputeCount/netWorthRecomputeCount/trendRecomputeCount ⑦physical_asset_grid 物品卡 watch→read（外层 Consumer 已重建，卡内 watch 冗余）⑧新 `test/balance_cache_test.dart` 5 用例（命中/交易失效/校准失效/账户编辑失效/净资产+趋势）。效果：资产页 build 从 3×账户数次全量重放降到同数据版本只算一次；账户详情趋势 ~91 次/帧→1 次。
  4. **情感化三件**：①净资产合并卡探头猫（accounts_view _buildOverview：Stack Clip.none+Positioned top-8/right-4+MascotBreath(bob:2,sway:0,centerRight)+idle.webp 高80、overview ListView 顶 padding 4→12 防裁）②showAppToast 加可选 `MascotMood? mascot`（Mascot size22 自带回退，胶囊 vertical padding 8→6），三处接成功猫：净资产核对完成/余额已核对/**权益收回 _save 补 toast「权益已收回」**（原来无任何提示，pop 前调用走 rootOverlay 存活）③两个趋势 painter（net_worth_trend_card + account_detail_page）per-segment 渐变填充 ui.Gradient.linear lineColor withValues 0.18→0，断点不连片，网格后描线前。
- **✅ 用户真机反馈两条已修（2026-07-27，等 v209 一起交付）**：
  1. **编辑物品键盘 bug（用户截图：键盘弹起后大片空白+表头顶进状态栏）**：根因=「双重键盘垫层」——showBlurSheet 路由层已有 AnimatedPadding 避让键盘，弹层内部又垫了一层 `Padding(bottom: viewInsetsOf)`，两层叠加把可视区压没。**12 处 showBlurSheet 弹层统一删内层垫层**（物品表单/权益表单/收回/物品估值·出售·凭证·折旧·复核·结束持有/退款分摊/成本关联/账户表单/余额校准）。⚠️ book_sheet 走 appSheet(showModalBottomSheet) 路由**不会**自动避让，其内层垫层是正确的，刻意保留——以后判断这类问题先看弹层走哪条路由。
  2. **物品卡空隙（用户截图红框：副标题和日均之间大空白）**：根因=竖卡文字区固定 6/11 高度+Spacer，名称一行时富余全成空白。改「照片 Expanded 吃掉富余高度+文字块贴底自适应」（physical_asset_grid.dart），照片更大、空隙消失、名称两行时照片自动让位天生防溢出。测试适配：asset_management_view_test 一处 tap 卡片前补 scrollLastGridTo（文字贴底后在 800×600 测试视口落到折叠线下，非弱化）。
- **✅ 已验收部分（2026-07-27 施工B会话）**：
  - **全量 flutter test：808/808 全过**（803 基线 + 5 新缓存用例），exit 0。
  - **渲染图已出**：after `outputs/asset_ui_review/after_p2/`（7 张，含 p2_07=编辑物品+FakeViewPadding 伪键盘的修复证据图）；对比图 `outputs/asset_ui_review/compare_p2/`（5 张，P1 vs P2），已发用户过目（尚未回复拍板）。渲染脚本临时拷进 test/ 跑完已删，原件在施工B会话 scratchpad `tmp_asset_ui_p2_render_test.dart`（丢了就照 after_p1 那版改：输出目录/p2_07 那段 FakeViewPadding(bottom:600)）。
  - 对抗审查工作流（拆分等价/缓存正确性/UI铁律/测试质量 4 维+逐条复核）**发起但用户额度耗尽时未跑完**：4 路中 1 路（test 维度）已回报**零问题**。journal：`~/.claude/projects/C--src-xunni-codex/a86b7f00-6c65-4beb-8553-07d51f8bce67/subagents/workflows/wf_d4379b23-5d5/journal.jsonl`（每路一条 result）。接手时若 journal 已有 4 条 result 就直接看结论；没有就重发一轮审查（或人工抽查缓存失效点+拆分引用即可，全量测试已绿兜底）。
- ~~剩余清单~~ **已全部完成（2026-07-27 续接会话）**：审查处置✅ bump 1.207.0+209✅ APK 构建核验归档✅ 文档终稿✅；commit+快照+发布状态见本节顶部和 §4。
- **⚠️ 历史断点记录（已过时）**：施工B 的 WIP commit、源码快照和旧 APK 删除状态只保留作追溯；其中 `android-app/outputs/` 的旧 v1.203 APK/孤立校验文件已在后续清理中移除。当前真实版本、分支、产物和验证以本文 §0 及项目管理总纲为准。

### 2026-07-18 当前启动体验修复（工作区未提交）

- 最新本地验证 APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.202.0-204.apk`
- 版本：`1.202.0+204`；build tag：`b0718-204`；DB：v40。
- 启动第一原则：**主页第一屏必须带真实当月数据，不允许先画空主页再掉入账单**。首屏前只读账本/当前账本、账户、分类、预算、显示偏好和当月已持久化账单；全历史、资产、报告、定时物化、净资产、备份和旧退款归并在首帧后收敛。
- 完整 hydration 前，记账、Widget deep link 和冷启动分享会排队；失败时 Widget/自动记账/报告不会读半快照。主题异步读取，抽屉首次打开才构建。
- Android 12+ 启动主题显式使用 `@drawable/splash_transparent`，并将 splash icon background 设为透明，避免系统回退使用桌面图标。
- 验证：启动/SQLite 专项 5/5、最终全量 Flutter 测试 **752/752**、`flutter analyze` 0 issue；发布逻辑 9/9，aapt、16 KiB zipalign、固定证书 APK V2 签名通过。APK 120,826,320 字节，SHA256：`3C178D9A6EE37DE806B281BD031058AD60A355E690844099534BAC421C566CC3`。
- 运行态边界：本轮无可用 Android 设备，未做安装/真机冷启动截图；需用户安装后复验本月数据是否首屏即在。未 commit、未 push、未发布线上。

- 历史已发布基线 APK（非本轮）：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.196.0-198.apk`
- 历史基线版本：`1.196.0+198`
- build tag：`b0714-198`
- 当前开发工作区分支：`codex/feimiao-p0-fixes`；本地功能提交 `1301e44`。因历史含 31 个超过 GitHub 100 MiB 限制的 APK，未改写本地历史，改用无发布产物的源码快照 `6703f8e`（父提交 `61c0c06`）推到 `origin/codex/feimiao-p0-fixes`；当前线上为 v198（releaseId `v198-69ae3ccda9ad`）
- SHA256：`69AE3CCDA9ADE11D470E444E519CEC01483F701B495199A11EE0C744C1EC9A7E`
- 包名：`com.qingji.qingji.codex`
- 应用名：`肥喵记账`
- 签名：`CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`
- v198 已包含旧账时间降噪与 DB v40 时间精度地基；707/707、analyze 0 issue、aapt/16K/V2 签名/哈希均通过，已 commit、push 并发布，运行态待用户安装验收。

## 2. 历史修复摘要（1.196.0+198，本轮启动修复见上方）

### 1.196.0+198 本轮

- **旧账时间降噪（DB v40）**：交易新增 `time_precision` 四态。存量账只标记 `legacy_unknown`，不改写 `date_ms`，不拿创建或更新时间伪造消费时分；日期分组卡隐藏不可靠午夜，独立卡只保留日期，来源明确的真实午夜仍显示 `00:00`。
- **入口与兼容链**：主页、搜索、账单、报销、喵助手普通卡/退款卡、手动/快捷/AI/通知、定时、普通导入、肥喵 CSV、退款报销和资产流水统一携带或继承精度。旧聊天 JSON/CSV 缺字段回退未知；CSV 为兼容旧格式继续输出固定 `yyyy-MM-dd HH:mm` 日期字段，并通过时间精度列避免把未知 `00:00` 解释成明确时分。
- **建议证据**：`TransactionRecord` 与智能建议引擎消费真实精度；`exact` 使用完整时段证据，`entryClock` 降权，`dateOnly/legacyUnknown` 不参与时段评分，但星期和周期证据仍可独立生效。
- **验证 / 产物**：定向 192/192、最终全量 707/707；full analyze 0 issue，格式与 diff check 通过。`1.196.0+198` / `b0714-198` / DB v40；Release APK 120,641,920 字节，SHA256 `69AE3CCDA9ADE11D470E444E519CEC01483F701B495199A11EE0C744C1EC9A7E`。aapt、16K ZIP 对齐、唯一 Codex V2 签名和源/归档/sidecar 哈希一致。无连接设备，未做安装/冷启动；本地提交 `1301e44`、远端源码快照 `6703f8e`、Cloudflare releaseId `v198-69ae3ccda9ad`，公网与 KV 逐分片验证通过。

### 1.195.0+197 本轮

- **时间语义**：AI 纯日期继承提交时分，明确时分原样保留；本地解析、手动、快捷和两个编辑入口不再把时分归零。导入/自动/定时入口保持来源语义。旧库 `00:00` 无可靠证据时不批量伪造，所以下次不能把“改显示文案”误当成历史时间修复。
- **建议语义**：旧逻辑按一级分类聚合全历史、取分类金额中位数、随机选最多两条后再随机查账补满四条，且旧午夜时间会破坏时段权重，现已全部删除。新 `SmartSuggestionEngine` 使用近 180 天“叶子分类 + 规范化备注/商户”签名，按跨日频次、近期、真实时段、星期与周期评分；金额不稳定时不带金额，证据不足允许不显示。查账建议只由真实预算和当前账本数据触发，缓存按内容指纹失效。
- **主页猫**：按 PNG alpha 边界把右侧盒子 bleed 调为 4dp，可见轮廓与卡片边线约重叠 2.2dp；320px 明暗主题测试保证不越屏。
- **验证 / 产物**：增量 49/49、失败边界复验 27/27、版本同步后最终全量 691/691；full analyze 0 issue，本批格式与 diff check 通过。`1.195.0+197` / `b0714-197` / DB v39；Release APK 120,641,920 字节，SHA256 `836E22D684F77CD8E4446227F0E8CEE54CD5DFD75D1BD07901CAEB58A65B3AB6`。aapt、16K ZIP 对齐、唯一 Codex V2 签名和源/归档/sidecar 哈希一致。无连接设备，未做安装/冷启动；未 commit、push 或发布。

### 1.194.0+196 本轮

- **预算进度与主页间距**：恢复低饱和预算健康绿 `#7FB069`，共享横条/圆环统一健康绿→临界铜金→超支橙；未完成轨道跟随进度末端色并带略深边缘。主页汇总卡按真实内容高度布局，筛选条上下均为 8dp。
- **账单与聊天显示**：新增全局内容优先（默认）/分类优先偏好及真实卡片预览；日期分组卡只显示时分，独立卡显示完整日期时分、账本和次信息。用户消息气泡默认跟随卡片透明度，可切固定灰底，偏好持久化且旧值安全回退。
- **喵助手稳定性**：历史区同步定位完成后才显示，消除进入闪动；恢复负责人被快速关闭时，新面板会接管重试，不再偶发空历史。
- **手动记账与分类**：备注请求系统 `done` 并复用正常完成保存链，无效金额保持焦点，成功保存锁住退出前数字键盘。共享分级分类器统一手动、定时、喵助手和导入复核的一级原位展开二级行为。
- **验证 / 产物**：analyze 0 issue；全量测试 664/664；release build 成功。aapt=`com.qingji.qingji.codex` / 196 / 1.194.0 / 肥喵记账；16K ZIP 对齐、唯一 Codex V2 签名和源/归档哈希通过。APK 120,609,152 字节，SHA256 `BFA815FB8A04CE89BE560B8D29B940DCD457100C7378B60ED324468B84AB0BCD`。
- **边界 / 下一步**：用户自行安装验收，不做模拟器、真机安装或截图。v196 未 commit、未 push、未发布，当前线上仍为 v195；DB 保持 v39。

### 1.193.0+195 上一版（当前线上基线）

- **日期仓储不变量**：新购买必须显式传入购买日期；物品、购买支出、结算、创建事件和初始估值统一该日，缺日期时原子拒绝。账单来源物品始终以原交易日为 canonical date，普通编辑不能漂移或清空。
- **折旧与保修边界**：启用折旧必须显式传 `startAt`，不再静默回退今天。保修日期按自然日比较，创建与编辑均不得早于购买日；原账单含具体时分时，同一天仍合法。
- **UI 继承**：完整包含 v194 的资产 UI 重构、三条新增路径、照片优先详情页、历史日期补录、受管照片/凭证及标准控件铺开；v194 保留为升级前回退包。
- **验证 / 产物**：analyze 0 issue；资产专项 38/38、全量测试 645/645；release build 成功。aapt=`com.qingji.qingji.codex` / 195 / 1.193.0 / 肥喵记账；16K ZIP 对齐、唯一 Codex V2 签名和源/发布副本哈希通过。APK 120,592,516 字节，SHA256 `3C502EB61F4E372A1EB1787CC0E418AB19AAFD9EAAA7A4963CEB57E694F3BF4E`。
- **边界 / 下一步**：不做模拟器、真机安装或截图，由用户自行安装验收。**v195 已由 Claude 提交(`bf50e97`)并发布上线**（releaseId `v195-3c502eb61f4e`）；v194 与 v193 APK/sidecar 保留为回退基线。A3b verified-checkpoint 纠错与 A5 负债单一真相源仍按原队列，未在本批混入。

### 1.192.0+194 上一轮（本地回退包）

- **日期与成本纠错**：手工物品可填写、补充或清空历史购买日；新购买让物品、支出、事件和估值共用同一日期；账单来源强制继承原账单日期。新增 `manual_unknown`，未知购置成本不再用当前估值伪装，日均和保值率降级为待补充。DB 保持 v39。
- **资产 UI 重构**：物品详情改普通二级页，首屏展示照片、日均、持有天数和估值；生命周期操作收进右上菜单。新增/编辑表单使用全套标准件，补齐在用/闲置、照片、购买日、保修和净资产选项；新增入口拆成账单加入、新购买记账、历史补录三条路径。
- **列表与凭证**：物品网格以日均为主指标、估值为辅助，unknown 显示待确认并统一圆角/按压/读屏；估值与折旧可选真实日期。发票/保修单改文件选择并复制到 `asset_media/`，照片可替换或移除，不再手输路径。
- **验证 / 产物**：analyze 0 issue；资产定向 65/65、全量测试 641/641；release build 成功。aapt=`com.qingji.qingji.codex` / 194 / 1.192.0 / 肥喵记账；16K ZIP 对齐、唯一 Codex V2 签名和源/发布副本哈希通过。APK 120,592,516 字节，SHA256 `C0208E5270788EE1A60F278354D29E6ACFE90D39425231535BCE79F34D36E845`。
- **边界 / 下一步**：不做模拟器、真机安装或截图，由用户自行安装验收；v194 未上传、未提交，当前线上仍为 v185。v193 APK/sidecar 保留为升级前回退基线。A3b verified-checkpoint 纠错与 A5 负债单一真相源仍按原队列，未在本批混入。

### 1.191.0+193 上一轮（本地回退包）

- **B3 专项追踪（DB v39）**：分类/标签范围按 OR 匹配，消费按原单退款家族净额计算；重叠专项彼此独立，不进入主预算或今日可用。新增创建、编辑、管理和归档；编辑归档旧计划并创建活动 successor，knowledge cutoff 仍可恢复历史范围和额度。
- **B3 引用安全**：专项历史引用的分类/标签禁止删除；分类合并同步重写 `expense_scope_json` 并重载。归档不改写历史 revision 或执行结果。
- **A4 物品增强**：补齐到期提醒、追加持有成本、使用次数与快捷 `+1`、存钱目标关联、报废/丢失/赠送撤销。关联金额统一使用退款家族当前净额；使用撤销事务化且唯一，终态撤销要求完整前态证据并绑定当前尚未撤销的事件。
- **JSON / v39 兼容**：资产 JSON v6 用存钱目标 UUID 解析并报告 unresolved/rejected；非法或重复 usage reversal 跳过且不回滚整批。早期 v39 中间态在启动/恢复路径事务化自修复，修复前保留不覆盖的 `pre-v39-compat` 备份；partial usage 表可补列/重建，非法/重复 reversal 清理后建立正确唯一索引。
- **验证 / 产物**：analyze 0 issue；B3/A4 扩展回归 79/79、共享仓储 111/111、最终全量测试 635/635；release build 成功。aapt=`com.qingji.qingji.codex` / 193 / 1.191.0 / 肥喵记账；16K ZIP 对齐、唯一 Codex V2 签名和源/发布副本哈希全部通过。APK 120,428,384 字节，SHA256 `3A2345620F91524CC83A644F8BCFF76B8BBC186DA981B1DAE6CEA41FFF1D6F16`。
- **边界 / 下一步**：用户不做模拟器、真机安装或截图验收，自行安装确认。当前线上仍为 v185，v193 尚未上传；v192 APK/sidecar 保留为升级前回退基线。A3b verified-checkpoint 纠错（superseding/revoked）与 A5 负债单一真相源仍未完成，继续独立排期。

### 1.190.0+192 上一轮（本地回退包）

- **A3 余额校准（DB v37）**：账户新增 UUID、期初日期/质量和归档状态；绝对 checkpoint 支持创建、撤销和同日稳定顺序。锚点前补录被吸收，锚点后流水继续累计；unknown-date 转账按账户双腿覆盖，账户归档只影响可见性。
- **A3 可信核对**：账户趋势只从可信起点开始；完整净资产 checkpoint 冻结 header/items，覆盖不足标 partial，过期物品估值需显式接受，后续数据变化不静默改写旧核对证据。
- **B2 预算计划（DB v38）**：新增 plan/revision、cycle override、月度锚点、周计划、固定模板/occurrence 和 change event。修改默认下周期生效，本周期 override 保存绝对总额；V2 切换后 legacy 预算仅作历史证据。
- **B2 固定承诺**：每周期 occurrence 可匹配、跳过、重置和退款复核；actual/reserve 互斥，部分退款继续预留差额，全额退款不错误释放额度。revision 重复保存与备份恢复会同步/物化 occurrence，未来浏览不混入今日指标。
- **审查补丁**：修复 latest partial 核对比较、过期估值确认、unknown 转账双腿、revision 二次编辑、override knowledge cutoff、退款撤销复核、恢复后物化和真实 `v36→v38` 迁移；320dp/大字号布局边界已纳入回归。
- **验证 / 产物**：analyze 0 issue；最终全量测试 587/587；release build 成功。aapt=`com.qingji.qingji.codex` / 192 / 1.190.0 / 肥喵记账；16K zipalign、唯一 Codex V2 签名和源/发布副本哈希全部通过。APK 119,756,044 字节，SHA256 `363A58B13DBAA732495D9C8BE7A247597ED3F6B84EFD08D361BC821499362B45`。
- **边界 / 下一步**：用户不做模拟器/截图验收，自行安装确认。当前线上仍为 v185；B3/A4 已在 v193 完成，v192 保留为升级前回退基线。

### 1.189.0+191 本轮

- **A1 物品闭环（DB v35）**：从已有账单创建物品不重复生成支出；支持一账多物整数分配、单物退款自动分配、多物退款待确认/人工分配、退货保护、解除关联审计反转与手工成本固化。物品页新增受管照片/缩略图、双列网格、搜索和筛选；窄屏/大字号降单列。出售只把扣除费用后的净到账投影到账户。
- **完整备份 v2**：SQLite、`receipts/`、`asset_media/` 同包；逐文件 SHA256、集合全等和路径穿越校验，v1 兼容。DB/收据/媒体独立切换回滚；失败 staging/临时目录清理，成功后的旧文件清理不再触发破坏性回滚。
- **A2 账户活动/趋势（DB v36）**：账户详情显示真实结算事件近期活动；资产总览显示可信净资产估算趋势。旧快照为 legacy_unverified，历史日期不伪造；scopeVersion 持久化并在计入政策变化时断代，snapshot_date 为 civil day 真相。
- **审查补丁**：定时记账即时生成、肥喵导入、删账本后刷新当天快照；记账账户只接受 CNY，legacy 外币仅保留查看；账单分配来源购买价统一为 resolver 净购置成本；320dp/130% 字号长金额无溢出且读屏完整。
- **验证 / 产物**：analyze 0 issue；定向 112/112；最终全量测试 540/540；release build 成功。aapt=`com.qingji.qingji.codex` / 191 / 1.189.0 / 肥喵记账；16K zipalign、唯一 Codex V2 签名和源/发布副本哈希全部通过。APK 118,920,116 字节，SHA256 `BB320F5F6FA725E41853F0D07722A4FA5498FEEC9C75FF25416482EAF3BE2556`。
- **边界 / 下一步**：用户不做模拟器/截图验收，自行安装确认。当前线上仍为 v185，v191 尚未上传。下一组按 V2.1 分期继续，仍保持每两阶段一包。

### 1.188.0+190 本轮

- **A0 资产信任地基（DB v33）**：物品/权益拆分经济状态、使用状态、可见性和计入口径质量；旧归档数据按事件、收回台账和金额矩阵等价迁移，归档/恢复只改变列表可见性。资产页改“总览 / 资金 / 物品”全局三视图，移除本月收支伪指标，新增持有天数、日均持有花费、保值率、估值记录和报废/丢失/赠送闭环。
- **D0 真实结算地基（DB v34）**：交易新增 `created_ms / settled_ms / settlement_quality / settlement_account_id / settlement_account_quality / event_type`；归属日继续服务消费/预算，真实到账服务现金流/余额。旧普通账单为 legacy_assumed，旧退款/报销未知证据不伪造。
- **账户逐事件投影**：退款、报销、转账双腿、资产出售和权益收回按真实结算账户投影；unknown 账户不回退原账户。账户列表/详情与净资产明确标示待确认、历史推定和“按已知金额”，旧退款/报销可补确认到账信息。
- **四入口退款/报销**：手工账单、喵助手、AI 快捷记账、待报销统一使用结算确认弹层；普通编辑不覆盖结算证据，周期记账不再误标 exact。肥喵 CSV 往返双日期与质量；旧报销兼容恢复为 reimbursement。无法匹配/超额退款不造普通收入，通知退款不按收入保存且不会在混合批被误清。
- **验证 / 产物**：analyze 0 issue；最终全量测试 491/491；release build 成功。aapt=`com.qingji.qingji.codex` / 190 / 1.188.0 / 肥喵记账；16K zipalign、唯一 Codex V2 签名和源/发布副本哈希全部通过。APK 115,069,684 字节，SHA256 `EEA6A350085C9499996D4A43C6B9FC4DEF431ED56172D42FCCB5E1CB09544998`。
- **边界**：用户不做模拟器/截图验收，自行安装确认。当前线上仍为 v185，v190 尚未上传；A1/A2 已在 v191 完成。

### 1.187.0+189 上一轮

- **C0 统计口径地基**：新增统一 `MetricQuery / MetricResult` 合同、整数分消费投影和等长同期窗口；退款归原消费期，普通收支与预算分类独立，外币排除返回 partial，未知/冲突不再伪装为 0。
- **B0 预算单一 resolver**：`BudgetWindowResolver` 继续读取旧 `budget_periods`，兼容自然月循环预算、一次性 winner、逐日整数分分配、历史 knowledge cutoff 和无预算/0 元/partial/conflict 独立状态。正常历史浏览使用当前知识截点，冻结回放才显式传旧 cutoff。DB 仍为 v32。
- **B1 预算执行页**：预算页改为“本周期 / 月 / 周 / 自定义”页内分段浏览，支持日期导航和独立账本范围；主卡、分类执行和“按预算平均”日均参考全部读取 resolver。一次性旧期间与自定义浏览明确分开。
- **消费者统一**：主页、快速记账、喵洞察、统计、月报、Widget、AI 查账和 AI 报告都转接同一预算结果。发布审查修复历史预算窗口混入当前周期“今日可用”的错期问题，并新增回归测试。
- **产品边界**：B1 不显示固定支出预留、“安全可花”或“可自由安排”；这些能力等 B2 的 revision/fixed occurrence 数据地基完成后再开启。
- **验证 / 产物**：analyze 0 issue；C0/B0/B1 定向 70/70，AI 错期与预算页复验 18/18，最终全量测试 445/445；release build、aapt、16K zipalign、单一 Codex V2 签名、源与发布副本哈希全部通过。APK 114,904,780 字节，SHA256 `02FD3E3AD0942EC2024F3A987890E557B3675AA44F0AF5B2F58C6B62FB249A34`。
- **边界**：用户明确不做模拟器/真机截图验收，由用户自行安装确认。当前线上仍为 v185，v189 尚未上传；v188 被本包取代。下一步继续 A0 资产状态地基与 D0 双日期/账户移动。

### 1.186.0+188 上一轮（已被 v189 取代）

- **AI 退款闭环**：新增本地 `RefundMatcher`，喵助手和快速 AI 入口只有在历史原支出唯一强匹配且金额合法时才写附着式退款；缺金额、无匹配、歧义、超额全部追问，查询不误判。退款金额先去掉日期再解析，避免“7月3日”被当成 3 元。仓库边界事务内再次校验剩余金额并返回退款行 ID；聊天退款卡用 `role=refund` 持久化、重启可恢复。
- **自动记账 / AI 设置**：自动记账接入主题背景，状态改标准设置行，编号长文精简为 secondary/caption；AI 设置去掉重复“AI”和四条冗余入口说明，标题降为标准 w500，账号/高级参数 6 个输入框统一 `AppLabeledField + iosInputDecoration`，说明左对齐并降灰。
- **预算 / 资产方案 V2.1 与全 App 统计合同（仅文档，未改结构代码/DB）**：V2 竞品研究稿保留；当前锁定方案为 `docs/claude/BUDGET_ASSET_UX_PLAN_V2_1_2026-07-12.md`。跨页面最高口径合同 `docs/claude/STATISTICS_CALCULATION_STANDARD.md` 已升到文档 v1.1、`calculationVersion` 仍为 1：按财务真值 `F-*`、派生分析 `D-*`、运营计数 `O-*` 全量登记主页、账单/搜索/报销、预算、统计、Widget、月报/AI、账户资产、存钱目标、导入导出、自动/定时记账、分类/标签/记忆/备份，并用 `current_exact/partial/inconsistent/target_only` 区分线上现状与 V2.1 目标。新增 60-77 号反例，点名跨币种、未来交易、笔数、同期、Widget、资产 scope 和运营计数冲突。实施顺序先 C0 口径门禁，再 B0/A0；Obsidian 镜像必须与仓库规范逐字一致。
- **抽屉对比图**：`outputs/drawer_before_after_v188.png` 由用户原始真机图和当前生产 RootShell/AppTheme 的真实右滑渲染合成，真实加载 logo、封面、中文和 Material 图标；尺寸 1664x1848，SHA256 `B34E7DF815EE7D4287B5FE5934232806B09BC84C63D7619B87567908DAA44555`。
- **验证 / 产物**：analyze 0 issue；定向 111/111；最终全量测试 374/374；release build、aapt、16K zipalign、Codex V2 签名、源与发布副本哈希全部通过。APK 114,626,156 字节，SHA256 `0A0282847451BE7650E4C3C89CE56ED4D306FF3AC0B6C13613462814E93C1FF7`。
- **边界**：DB 仍为 v32；用户明确不做模拟器/真机截图验收，App 内运行态由用户安装确认。当前线上仍为 v185，v188 尚未上传；v187 被本包取代。

### 1.185.0+187 本轮

- **主页/抽屉**：探头猫右边缘锚定、取消横摆旋转，只保留轻纵向呼吸；“今日可用”下移 8px。抽屉导航统一 `AppLineIcon` 的 Lucide 线性风格，设置/新建账本换 gear/square-pen，“更多”移除右箭头，主页增加朝抽屉侧的定向阴影和发丝边界。
- **主题/备份**：简约白预算横条与圆环底轨改中性灰；6 色卡在 320dp 单行；滑杆改 `CupertinoSlider` 并按色卡给可见控制色；删除极简模式的新 UI/写入，旧配置继续兼容白色外观。备份主列表只展示最新 3 份，迁移/升级保护备份不删除。预算页仅把新增按钮移到右上角。
- **表单/导入导出**：新增 `AppLabeledField`；`SheetHeader` 统一等距边界，`SettingsGroup` 自定义行撑满。分类图标样式、公共分类选择器、定时记账分类弹层统一标准头部；存钱目标改半屏多字段表单；导入导出按钮、说明层级和文案收口，导出范围可滚动且自定义日期不再裁切。
- **喵助手**：全屏背景跟随主题；改分类/删除及卡外说明降为标准灰阶；回答操作栏收口 Claude 细线样式和稳定热区。IME 期间保持组件树不变，通过 `BackdropFilter.enabled=false` 暂停大面积/输入框模糊，位置直接跟随系统 inset；AI 焦点 10/10 回归全过。
- **明确不进本版的六项**：AI 退款附着原单、自动记账页面、AI 设置页面、预算展示深度方案、资产管理全流程方案、抽屉前后对比图。未接通的退款底层草稿已从本版剔除。
- **验证/产物**：analyze 0 issue；全量测试 364/364；release build 成功；aapt/zipalign/Codex V2 签名/源与发布副本哈希均通过。APK 114,462,292 字节，SHA256 `8041C21299EFC1CA618ADC005D6272794BE90C6CEE77D74C0E54DCFC9699AE8E`。
- **运行态边界**：用户明确取消模拟器截图，将自行安装验收；真机视觉、触控和输入法流畅度仍待用户确认。当前线上为 v185，v186 被本包取代，不再单独发布；v187 未上传。

### 1.184.0+186 本轮

- **主页卡片真根因**：真机截图中背景约 `#F4E2BA`、Material Card 中心约 `#CBC0AC`；40% 白色不可能把背景压暗，且无 elevation 的玻璃控件显示正常，确认是半透明 Card 与 physical elevation/阴影在小米 GPU 上的合成污染，不是 `surfaceTint` 或主题色值本身。
- **修复**：主页大卡片和账单日卡改为 `GlassSurface(blur: 0)`，保留动态白色卡底、渐变发丝边和账单交互；预算横条/圆环底轨改半透明白。参数：浅色卡片默认 40% 不透明度且跟随滑杆，预算底轨浅色 56%、深色 14%。
- **验证与产物**：像素断言要求卡片 RGB 必须比暖色背景更亮，且结构断言禁止主页退回 elevated Material Card；analyze 0、相关测试 10/10、全量测试 352/352。release APK 已构建并通过 aapt、Codex V2 签名与复制件哈希核验；114,446,116 字节，SHA256 `C91C69ECE23E5E02CAE482B50D837286621785143B289C0F18C475172331D535`。
- **交付边界**：v186 未上传且已被 v187 取代，对应修复完整包含在 v187；当时没有虚拟机安装截图。

### 上一版 1.183.0+185（已上线）

- **常规账单写入去全表重载**：新增受影响 ID/退款家族的增量回读；新增、编辑、改分类、退款和删除不再执行全表 JOIN。切换账本和总账本开关直接复用全局内存行；批量导入仍只在整批提交后做一次有意的全量刷新。
- **大文件导入降主线程压力**：CSV/XLSX 表格解析、肥喵格式识别、日期金额转换和第三方账单标准化移入 `Isolate.run`；XLSX 通过 `TransferableTypedData` 跨 isolate，FilePicker 不再先把整份文件复制进平台结果。
- **Widget PNG 压缩移入后台 isolate**：Flutter 布局/绘制因引擎限制保留在根 isolate，RGBA→PNG 编码改用 `image` 在后台完成；两张卡拆帧、同一轮快照只构建一次，减少记账后的连续 UI 占用。
- **报告支持进程被杀后继续**：Android WorkManager 以唯一 job 调度，联网约束+指数重试；API Key 从旧原生安全通道迁移到可供 headless engine 使用的 Flutter Secure Storage；报告正文、聊天卡和 job 完成状态原子提交且可幂等重试，完成后发本地通知。面板轮询持久 job，切回仍显示阶段和最终报告；调度不可用时保留前台兜底。Worker 初始化失败不会阻断 App 首屏，数据库未就绪会重试，已完成任务不会被误改回排队。

### 上一版 1.182.0+184（本地包已被 v185 取代，不再单独发布）

- **主题**：图二半透明暖白卡作为视觉基准保持不变；主页 Material Card 关闭 surface tint 二次染色；简约白页面底恢复 `#F7F8FA`，像素测试锁定效果。
- **DB v32 / 自动记账**：新增 `auto_record_occurrences` 精确事件幂等；原生通知队列改 key+postTime/UUID，删除 60 秒同文本误去重；Flutter 改 peek + 保存/明确忽略后 ack。
- **报告**：新增 `report_jobs`，切页/重开继续显示思考阶段和原始耗时；重新生成锁定原账本并更新原报告及聊天摘要；所有完成/失败路径释放运行时锁。
- **统计与查询**：统计、Widget、报告统一按一级分类身份和退款净额聚合；无日期 AI 查账先全库关键词检索；聊天恢复解决重复与清空回插竞态。
- **Widget / 更新 / CSV**：Widget 快照单通道+代次+每代独立 PNG；前台更新兜底支持 Range 和陈旧任务清理；CSV 保留转入账户、标签、可报销，并恢复缺失账户/标签。
- **数据安全**：旧 SQLite checkpoint+独占锁复制兜底；Android 禁止云备份和设备迁移应用数据。

### 上一版 1.181.0+183（已上线）

- **主题外观系统**：设置→显示→主题外观；6 色卡（暖橙/简约白/樱粉/薄荷/雾蓝/暮夜强制深色）+背景浓度/卡片透明度滑杆+极简模式+实时预览；AppThemeController 存 JSON；AppColors.applyTheme 唯一写入口；语义色永不开放。
- **UI 设计标准 v1**：`docs/claude/UI_DESIGN_STANDARD.md`（动 UI 前必读）+ AppType 字阶令牌；SettingsRow/SectionLabel 收口；AI 设置四子页整改；全库违规红清零（8 处→超支橙）。
- **GPT5.6 数据一致性批（Claude 验收）**：DB v31——定时记账单事务+recurring_occurrences 台账幂等；net_worth_snapshots 重建表 UNIQUE(scope_key,snapshot_date)；多表操作事务化；表单防重入。330/330（新增 13 测试）。
- 视觉：卡片透明度 40%、设置弹窗暖渐变、SlidingSegment 半透明滑块、✕/齿轮收口 AppCircleButton。

## 2z. 更早（1.180.0+182：设置页 ChatGPT 化 + 弹窗磨砂，已上线）

- 设置页九连改：全屏弹窗+右上✕、分组标题 13.5/w500 中灰、Cupertino 深色图标、卡片透明度 52%/62%（全局 AppColors.card）、版本号只留检查更新行、AppSwitch 恢复灰槽白点（测试已同步）、删宣传语、分组卡连续曲率圆角、抽屉齿轮白圆图三化。
- 并入 181 弹窗磨砂精修（FrostedDialogCard/DialogPillButton/dialogBodyColor）。
- 坑：flutter test 接管道会吞退出码，以后落文件查 $?。

## 2c. 更早（1.178.0+180：更新后台下载）

- 更新下载改系统 DownloadManager（切后台/锁屏/杀进程不中断+通知栏进度+续传）；弹窗「后台下载」按钮；前台完成自动装、后台完成下次打开接续装不重下；DM 禁用回退进程内下载；SHA256 链路不变。
- Kotlin feimiao/update +5 方法（挂起记录存 SharedPreferences）；update_file_paths.xml 补 external-files-path。

## 2b. 上一轮（1.177.0+179：全局弹窗统一图二风格）

- **确认弹窗**（ios_dialogs）：对齐 iOS Cloudflare 客户端原图——标题/正文左对齐、两颗同浅底等宽胶囊、文字主色蓝灰 w600、危险=超支橙字。1.161.0 那版「居中+实心色确认键」与参考图不符，本轮纠正。
- **表单弹窗**（ios_form）按钮文字改主色，与确认弹窗同观感；下载进度弹窗左对齐。
- **裸 AlertDialog 清零**：新建标签→showIosFormDialog；编辑转账删除→showConfirmDialog(destructive)（消灭违规红字）；截图识别中→统一圆角卡。
- **弹窗规范**：以后新弹窗一律 showConfirmDialog / showIosFormDialog，别再手写 AlertDialog / 居中文本 / 实心色按钮。
- 另带上 178 后补的小组件快照指纹跳渲。
- 上一轮（1.176.0+178，已上线）：更新校验加固、深色状态栏、退款净额索引化、transactions 索引、去重复模糊层。

## 3. 验证记录（最新 = v211，2026-07-27）

已完成：

- `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`：0 issue（仅 2 条既有测试 info）。
- `flutter test --no-pub --concurrency=1`：**841/841** 通过（注意：管道会吞退出码，结果落文件再查 `$?`）。
- `flutter build apk --release --no-pub --build-name 1.209.0 --build-number 211`：成功。
- `verify_release_apk.sh`（含 aapt/16K zipalign/apksigner）：`com.qingji.qingji.codex` / 211 / 1.209.0 / V2 唯一 Codex 签名，证书 SHA256 `4e99c399d4d246bd9c6b08b1d641248bd0846e7ae650c3a766e30fa67483d507`。跑它前先 `export JAVA_HOME="C:\Program Files\Android\Android Studio\jbr"`。
- APK：111,813,999 字节；SHA256 `95AF6B5BFA34F5235EF13EB9CC83986B9D2B9829E25410B3472F85F7E4AFBDB8`，归档与 sidecar 一致。v210/v209（线上）保留为回退包。
- 离屏渲染截图：A 批为逻辑/数据层功能，无新 UI 对比图（A批截图可在真机安装后验收）；模拟器/真机安装按惯例跳过；运行态由用户自行安装验收。

## 4. 线上上传状态
- ✅ **v209 已由 Claude 于 2026-07-27 发布上线（用户拍板）**：`1.207.0+209` / `b0727-209` / DB v41；releaseId `v209-44b235922691`。发布后验证：公网 version.json 返回 209、sha256 `44b23592...aa74eb` 与源 APK 一致、sizeBytes 110,666,531 一致（全量下载哈希核验另记）。本地功能提交与快照见 P2 段。v207/v208 APK 归档保留为回退包（未单独发布）。
- ↩️ **v206 历史基线**：已由 Claude 于 2026-07-26 提交、推送并发布上线：`1.204.0+206` / `b0726-206` / DB v41；本地功能提交 `b2dc7a9`，远端源码快照 `ae5fdb5` 位于 `origin/codex/feimiao-p0-fixes`，Cloudflare releaseId `v206-cf261263d66b`。发布后验证：公网 `version.json` 返回 206、全量下载 110,666,547 字节拼接 SHA256 与源 APK 完全一致。运行态由用户自行安装确认（用户已知可从电脑直接传包安装，绕开 30KB/s 的直连下载）。
- ↩️ **v198 历史基线**：`1.196.0+198` / `b0714-198`；本地提交 `1301e44`，快照 `6703f8e`，Cloudflare releaseId `v198-69ae3ccda9ad`（已被 v206 覆盖）。
- ↩️ **v197 APK/sidecar 原样保留**：作为本轮升级前本地回退基线，不代表 DB v40 运行后的无损降级方案。
- ↩️ **v196 APK/sidecar 原样保留**：作为前一轮回退基线，不代表 DB v40 运行后的无损降级方案。
- ✅ **v195 已由 Claude 于 2026-07-14 发布并逐分片验证**：releaseId `v195-3c502eb61f4e`，version.json 返回 195、sha256 干净、5 分片拼接哈希与源 APK 完全一致。发布时 Cloudflare 连接抖动，改用逐分片带重试上传（version.json 最后原子切换，过程中线上保持 185 不受影响）。

↩️ **v195、v194 与 v193 APK/sidecar 保留为回退基线**：它们不是 DB v39 运行后的无损降级方案，不删除、不覆盖。

↩️ **v192 APK/sidecar 保留为升级前回退基线**：它不是 DB v39 运行后的无损降级方案，不删除、不覆盖。

⏭️ **v191 已被 v192 完整取代，不再单独发布**。

⏭️ **v190 已被 v191 完整取代，不再单独发布**。

⏭️ **v189 已被 v190 完整取代，不再单独发布**。

⏭️ **v188 已被 v189 完整取代，不再单独发布**。

⏭️ **v187 已被 v188 完整取代，不再单独发布**。

⏭️ **v186 已被 v187 完整取代，不再单独发布**。

✅ **v185 已由 Claude 于 2026-07-11 发布并逐分片验证**（历史版本，现已被 v195 覆盖）：releaseId `v185-a42a2d3875b8`，version.json 返回 185、sha256 干净、5 分片拼接哈希与源 APK 完全一致。v184 已被本包完整取代，不单独发布。

✅ **v183 已由 Claude 于 2026-07-11 发布并逐分片验证**（历史版本，现已被 v195 覆盖）：releaseId `v183-606eba7269a6`，5 分片拼接哈希与源一致。

✅ **v182 已由 Claude 于 2026-07-10 发布并逐分片全量验证**。

✅ **v180 已由 Claude 于 2026-07-10 发布**：releaseId `v180-66b213368d44`；本机代理拉不动整包，改逐分片校验通过（5 分片拼接哈希与源一致）。

✅ **v179 已由 Claude 于 2026-07-10 发布并全量验证**：releaseId `v179-23cf92a491b2`，下载哈希与源一致。发布脚本务必在 Git Bash 跑（WSL 的 bash 处理不了 Windows 路径）。

✅ **v178 已由 Claude 于 2026-07-10 发布并全量验证**（用户拍板）：releaseId `v178-61752a7c6383`（干净无反斜杠）。验证：version.json 返回 178、`sha256` 干净 64 位 hex、响应头 `x-feimiao-sha256` 一致、**全量下载 111,442,327 字节哈希与源 APK 完全相同**。

历史备注：v177 污染元数据曾由 Claude 在 v178 发布前直接改写 KV 修复（保证 v176 用户能升 177），现已被 v178 整体覆盖。发布脚本已改 stdin 计算 sha，不会再产生 `\` 前缀。

## 5. 版本文件同步状态

- `pubspec.yaml`：`version: 1.209.0+217`
- `lib/core/app_version.dart`：`version = '1.209.0'`，`buildNumber = 217`
- `lib/build_info.dart`：`kBuildTag = 'b0727-217'`
- `android/local.properties`：Flutter release 构建已读取 `1.209.0+211`；该文件通常不入 git
- DB：**v42**（v41 订单号之上，liability_profiles 加 statement_day/credit_limit/counterparty；recurring_rules 加 to_account_id）
- 版本规矩：每次推送 minor+1、versionCode+1、kBuildTag 同步（b月日-versionCode）

## 6. 接手规则

- 开工前先跑：`git status --short`。
- 不要触碰 `C:\src\xunni`。
- 不要自动执行 `TASKS_FOR_CODEX.md` 的旧任务，除非用户明确点名。
- 不要把旧 release APK 删除状态混进功能提交。
- 不要为了性能删除用户明确要保留的模糊、猫、建议等体验；要从计算、缓存、渲染层优化。
- 出 APK 必须全量 analyze + test，并核验 aapt + apksigner。

## 7. 仍需关注的风险池

这些不是当前自动任务，只是后续排查优先级：

- v178 上传后，真机从 v176/v177 应用内更新到 v178 是否不再校验失败。
- 大数据量账单下主页、统计和小组件刷新是否明显改善；Widget 布局/绘制仍受 Flutter 引擎约束留在 UI isolate，但 PNG 压缩已经移出。
- 深色模式主页状态栏在真机不同系统主题下是否始终清晰。
- AI 记账键盘焦点、返回键、空白点击回主页等历史高频问题需继续真机回归。
- v196 用户安装后重点确认：预算健康绿和动态同色轨道、主页筛选条 8dp 间距、进入喵助手不闪、两种账单标题层级及时间格式、用户气泡透明度、备注完成键保存不跳动、定时记账二级分类原位展开；同时回归 v195 的资产购买日期、日均、持有天数和照片优先详情页。
- **A5 负债单一真相源**仍未完成（`balance_mode` ledger/legacy_hybrid 双模式、等价迁移、本息拆分、结清归档）；不要把底层枚举/比较器误写成完整产品闭环。侦察报告已落盘 `docs/claude/A5侦察报告-2026-08-07.md`（含双算实锤位置、等价性安全网、待拍板三项）。**A3b verified-checkpoint 纠错（superseding/revoked）已在 B1 段接完 UI，不再是欠账。**
- 本机 AVD guest 启动前冻结；升级/回退 Emulator 或修复 WHPX 后再做截图，不要宣称本轮已有运行态截图。
