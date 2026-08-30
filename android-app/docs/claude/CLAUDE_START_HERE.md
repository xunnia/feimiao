# Claude 新会话启动入口（先读这里）

更新时间：2026-08-30
适用工程：`C:\src\xunni-codex\android-app`  
严禁触碰：`C:\src\xunni`，除非用户明确要求并确认风险。

这份文件是 Claude 新会话第一入口。旧的 `TASKS_FOR_CODEX.md` 只在用户明确点名具体任务时读取执行，不是默认开工清单。

项目范围、优先级、交付门禁、路线图、风险与产物保留规则统一见 `../PROJECT_MANAGEMENT.md`。本文件负责“当前实现状态”，不再承担完整项目管理职责。

## 0.0.3 GPT OAuth/JSON 最终链路状态（v1.277.0+291）

- 官方 ChatGPT/Codex Responses 拒绝 `stream:false`；普通问答、主页记账、报告和连接测试现在在 OAuth Responses 传输层统一强制 `stream:true`，并保留官方请求元数据。
- 本机真实 Cockpit 完整备份解析 10 个 Codex 账号且无警告；指定测试账号的官方模型目录和 Responses 均真实返回 200，肥喵主页 `LlmQuery` 与喵助手 `LlmQueryV2` 都解析出 `OK`。
- 验证：OAuth/Responses/JSON/仓库定向 `113/113`、Flutter 全量 `1171/1171`、analyze 无 error、Gradle Kotlin 编译成功；APK `C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.277.0-291.apk`，SHA256 `43DAC969193535B39EBC08EE133546C0C63F3E78C64720829389CF635A754F28`，16 KiB/V2/固定证书 gate 通过。
- 当前无在线 Android ADB；手机 VPN、Chrome Custom Tab、设备码轮询和真机观感仍需安装后复测。未使用 Plus 账号。

## 0.0.2 GPT OAuth 与 Cockpit JSON 最终状态（v1.276.0+290，历史）

- Android GPT OAuth 现在优先官方设备授权码流程，不依赖 localhost 回调；设备码轮询、PKCE 与 Token 兑换按 Cockpit 当前协议实现，旧 localhost/手动粘贴路径仍可用。
- Token 邮箱回填；主页普通记账、报告、连接测试、喵助手遇到不支持模型会读取账号模型目录并自动换用可用模型；导入后的 refresh-only/PAT 账号按需刷新/补全工作区 ID。
- Cockpit 完整备份实际解析 10 个 Codex 账号（5 OAuth、5 API Key），重启持久化通过；定向 OAuth `19/19`、JSON/AI/模型目录 `44/44`、仓库 `3/3`、全量 Flutter `1168/1168`，analyze 无 error。
- 真实测试账号仅完成官方网页授权页、账号选择页和回调可达性验证，未使用 Plus 账号；无在线 ADB，手机出口、VPN 分流和设备码真实轮询待目标手机安装复测。

## 0.0.1 主页月份选择弹窗最新状态（v1.275.0+289）

- 主页月份选择弹窗已按用户提供的旧版参考图二回退：普通底部弹层、自然暗化背景、标题左对齐、统计起始日右对齐同一行。
- 已移除弹层内关闭圆圈和背景高斯模糊，年份箭头恢复无圆形视觉底；月份网格与数据逻辑保持不变。
- 前后截图与带编号的左右对比图：`outputs/ui_comparisons/2026-08-30/`；定向回归 `3/3`，全量 Flutter `1164/1164`，analyze 无 error。
- APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.275.0-289.apk`，SHA256 `196FED571B03372A4F89211034759E89061A8AF00B72163DD1542D27C4C4B56B`；本轮未发布线上。

## 0.0 GPT OAuth 与 Cockpit JSON 导入最新状态（v1.274.0+288）

- OAuth 已恢复官方直达授权入口，Token 成功后先保存，模型目录失败可稍后恢复；Android 系统代理动态接管后续请求，普通授权兜底明确走外部浏览器，不把 ChatGPT 当前个人空间当作授权结果。
- Cockpit/CPA 导入支持完整备份 `accounts.platforms.codex.exported_data`、单独 `exported_data` 传输段、共享 workspace 多账号、`token_data`、JSON Lines、嵌套 payload、BOM/UTF-16 和标准 API Key 默认地址/模型；`at-...` 令牌会先走官方 `whoami` 获取工作区 ID。
- 定向回归 **53/53**、串行全量 Flutter **1164/1164**、Dart analyze 无 error；最终 Release APK 已通过身份门禁。
- APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.274.0-288.apk`，SHA256 `9459F72F75845DF38D53385FA7B60E731B695BDC749673BAC6EA79A854D19035`。
- 本机 ADB 模拟器仍 offline，真实 Android 真机 OAuth、手机 VPN 出口、IME 和安装观感尚未验证；不要将本地测试写成真机验收。

## 0.1 全局 UI 收口最新状态（v1.264.0+278）

- 全局 UI 已按统一契约收口：`AppType`/`AppControl`/`AppHitTarget` 管理字号、视觉尺寸和触控热区；公共圆形按钮、胶囊按钮、设置行、弹层、菜单和勾选件已迁移，顶栏布局不被热区撑高。
- 旧 `AlertDialog`/随意底部弹层/设置页私有重复行已清理；AI 账号值尾部在 320dp/200% 字体下不溢出，危险操作统一使用肥喵警示橙，整行勾选不会重复切换。
- 截图证据已刷新：`outputs/global_ui/`、`outputs/ai_account/`、`outputs/ai_chat_input_alignment/`、`outputs/ai_chat_claude/`、`outputs/chats/`；全局 UI 与 Claude/Chats 视觉回归通过。
- 当前代码已通过 Dart analyze 无 error（64 条既有 warning/info）、串行全量 Flutter **1124/1124**；Release APK `C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.264.0-278.apk`，SHA256 `3BFC09913BB28C0CC783C30773C459570B7195BCE321DAF530FF2A9DCE6FF07C`，identity gate 通过。
- 本机无在线 ADB；真实 ChatGPT OAuth、provider 网络、IME、相册和真机字体观感仍需用户设备验收。本轮未修改 `ios-app/**` 及指定 Android 集成测试文件。

## 0.2 深度审计历史状态（v1.263.0+277）

- Cockpit refresh-only OAuth 账号现在会在首次模型目录/请求前交换 access token；所有 AI 入口统一以 API Key 或 OAuth refresh token 作为凭据，避免账号页显示可用但发送时误走本地 fallback。
- 报告 `model_started_ms` 只在真正准备调用模型时 CAS 写入；排队、隐私确认、上下文收集和 WorkManager 交接不再计入模型思考时长，恢复任务未开始模型时不伪造创建时间，并同步 CAS 赢家到 UI。
- 富文本显式使用 Nunito + Noto Sans SC fallback，修复离屏/实机可能出现的中文方块；回答正文移除裸来源 URL，来源统一显示在操作栏和可上拉面板，URL 后中文标点不会吞掉后续正文。
- 当前代码已通过 analyze 无 error、全量 Flutter **1118/1118**、Claude/Chats 视觉 **16/16**；Release APK `C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.263.0-277.apk` 已通过 identity gate，SHA256 `C31C24AF83AD5A4BC3BAD245D86536EB60CA124DCB1E54F3ED4C32F0AEAEE509`。

## 1. 当前真实状态

### 2026-08-27 交付前收口（v1.262.0+276，历史基线）

- 草稿附件累计添加现在按每条消息统一限制 3 张图片/10 个文件；相册重复选择和“添加文件”选择的图片都会计入上限，超出项即时提示且不会等到发送时才整批失败。
- 报告任务新增 DB v48 的 `model_started_ms`，首次模型处理时间以 compare-and-set 持久化；前台、WorkManager 和恢复路径共享同一时间点，重新打开 Chats 不会重置“思考了 Xs”。
- 验证：Dart analyze 无 error（57 条既有 warning/info）；全量 Flutter **1114/1114**；附件/报告迁移、AI/UI/会话/图片/思考、Claude/Chats 视觉回归通过；Release APK 身份 gate 通过。
- APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.262.0-276.apk`，117,071,394 字节，SHA256 `A3839FFBBE94104866888EA73A0ECBD7A303C2E6A67AE4447FEFE41B18268A6B`；包名/版本 `com.qingji.qingji.codex / 1.262.0 / 276`。
- 本机无在线 ADB；真实 ChatGPT OAuth、provider 网络、IME、系统相册/文件选择器、安装冷启动和真机字体观感仍需用户设备验收。iOS 与指定 Android 集成测试文件本轮未修改。

### 2026-08-27 三阶段 AI 能力与 8-27 需求收口（v1.261.0+275，历史）

- 三阶段 AI 能力已收口：安全的运行记录/幂等/结构化提案/撤销/健康诊断/图片可靠性；上下文压缩、任务中心、可控记忆、统一搜索；白名单技能/连接器、定时报表配置和 loopback-only 本地 companion service。
- reasoning 持久化只保留字符数摘要；禁止任意 shell、远程 MCP 和自动财务写入。全局弹层、Claude 加号图片流程、思考/来源/消息操作、模型/Effort、输入框和三图布局按 8-27 参考图完成。
- 验证：Dart analyze 无 error（56 条既有 warning/info）；全量 Flutter **1109/1109**；定向 AI/UI/图片/视觉回归通过；release 构建和身份 gate 通过。
- APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.261.0-275.apk`，117,038,626 字节，SHA256 `04692649468A63A11FC22E0DF4530A3DAFC36EFD2EA3BCB9FE41533B1F39C8C2`；包名/版本 `com.qingji.qingji.codex / 1.261.0 / 275`。
- 本机无在线 ADB；真实 ChatGPT OAuth、provider 网络、IME、系统相册/文件选择器和安装冷启动仍需用户设备验收。

### 2026-08-27 后台思考 flow 与参考图三图布局修复（v1.260.0+274，历史）

- 统一小弹窗改为 Claude/iOS 风格中性灰遮罩、锚点镂空、磨砂圆角、缩放淡入和统一细线图标；长按自己消息提供时间、复制、编辑、选择文本与震动反馈。
- 思考中显示动效，完成后显示“思考了 Xs”，可展开摘要/过程并用灰线与正文分隔；来源以 favicon 叠放和数量放在回答操作栏最右侧，正文不再铺开裸链接；Markdown 表格按列对齐并支持横向滚动。
- 聊天图片在发送前留在输入框，发送后显示真实图片；三图同排，Add to Chat/模型/Effort/Chats 视觉与间距继续沿用既有锁定标准。
- 整条前台 AI 流程及解析/附件请求增加 120 秒超时，避免永不结束的传输永久停留在思考态；三图消息采用参考图的一行方形三等分卡片，保留内容区边距。
- 修复报告交给 WorkManager 后 flow ownership 被发送 Future 提前释放的问题；思考 ticker 和报告轮询持续到完成、失败或 120 秒交接，避免永久“正在思考”。
- 生产历史区三张图片填满聊天内容区（390dp 下首图 x=16、末图 right=374），草稿首屏保留三格并可横滑查看更多。
- 本轮补齐请求 ownership 竞态：旧请求的 finally/延迟回调不会清理或消费新请求；图片截图验收改用真实封面文件并等待异步解码，三张已发送图片真实可见、草稿首屏保留三格并可横滑查看更多。
- 设置页模型列表和手动模型输入字号统一收口为 15px/w300，补充 Widget 断言，避免列表仍沿用 16px。
- Claude/Chats 定向视觉回归 **16/16**，AI 请求/重试/Responses **36/36**，AI/UI/会话/图片/思考/来源/模型/菜单 **104/104**；golden 已按本轮源码刷新；串行全量 Flutter **1094/1094**；analyze exit 0（45 条既有 info/warning）。
- Release APK 已归档为 `C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.260.0-274.apk`，116,446,150 字节，SHA256 `2A603BF8B063F26D6FD393591D7440275FE652CE81EA6CA6935595A1E85F36EA`；release identity gate 已确认包名/版本、16 KiB 对齐、APK V2 和固定证书。旧 v1.260.0+273 和 v1.259.0+272 包保留作回退。本轮无在线 ADB，真实 provider/OAuth、IME 和安装冷启动仍待用户设备验收。

### 2026-08-25 本批十项 AI 体验收口与 APK（v1.255.0+268，待用户真实设备验收）

- 思考状态、处理摘要和来源面板；长按自己消息的高亮、时间、复制/编辑/选择文本与震动；回复排版、链接和表格横向滚动均已收口。
- 普通记账模型/Effort 选择、首条消息 ready barrier、主页强制记账路由、Claude 风格加号/图片流程和服务商卡片边界均已通过定向回归。
- Flutter 全量 **1065/1065**，analyze exit 0（34 条既有 info），Gradle release 与 release identity gate 通过。
- Release APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.255.0-268.apk`，116,069,242 字节，SHA256 `F70BB00313FFBB5EF487C5A3959AEC7284FB2EC62F395608E9390F7B8982E091`；包名/版本 `com.qingji.qingji.codex / 1.255.0 / 268`。
- 本机无在线 ADB 设备，未执行真机安装/冷启动及真实 provider/OAuth 网络验收；需用户在可联网 Android 设备安装后确认。

### 2026-08-25 OAuth/主页 GPT/喵助手修复与 APK（v1.253.0+266，待用户真实账号验收）

- 本轮修复 OAuth 401 强刷/模型目录重试和 Chrome 回调成功页连接窗口；主页 GPT 记账使用官方 Responses JSON Schema；AI 账号输入框统一半透明样式；喵助手历史底部空白收紧并限制 88dp 回弹。
- Flutter 全量 **1059/1059**，analyze exit 0（33 条既有 info），release gate 通过。APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.253.0-266.apk`，SHA256 `DB37C1B2E668938B4FB527906EDD4FD704F49AD6E3AC93A58BDF3F20A36D420E`。
- 本轮无在线 ADB 设备；真实 ChatGPT OAuth、Token 交换、官方模型目录和 Responses 请求仍需用户在可联网 Android 设备验收。

### 2026-08-25 Cockpit AI 账号 JSON 导入导出与 APK（v1.252.0+265，历史基线）

- AI 账号设置新增 JSON 文件导入、剪贴板粘贴和 Cockpit 兼容导出；支持 Cockpit flat OAuth、多账号数组、OpenAI `auth.json`、Sub2API credentials 和常见 API Key/OAuth JSON。
- 导入先显示脱敏预览；重复账号可更新/新建副本/跳过；“同步加入 API 服务”映射账号启用开关。所有 API Key/access/refresh/id token 只写平台安全存储，不写普通 provider 元数据。
- OAuth JSON 没有模型目录时，导入会尝试用 Token 拉取官方 GPT/Codex 模型；离线仍保留默认模型，后续可在账号页刷新。
- Flutter analyze exit 0（33 条既有 info）；全量 Flutter **1059/1059**；Gradle release 与 APK release gate 通过。16037 ADB 模拟器已安装并冷启动。
- Release APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.252.0-265.apk`，SHA256 `08E43A3816B6A8832CAC46DDF165A1B7D12F97BADE2AF124F710EE8C28528DD5`。
- 真实 ChatGPT OAuth、Token 交换、官方模型目录和 Responses 请求仍需用户在可联网设备验收。

### 2026-08-25 GPT OAuth Android 回调竞态与流隔离最终收口与 APK（v1.250.0+263，历史基线）

- GPT OAuth 启动短时 Android 前台保活服务，停止改用 `stopService()` + 有界等待，避免 `ForegroundServiceDidNotStartInTimeException`；恢复时按当前 state 复用健康监听，避免制造拒绝窗口。
- ready/callback 文件携带 flow/state；错误 state 由原生服务直接返回 400；IPv4 只绑定 `127.0.0.1`，IPv6 作为附加监听；1455 失败自动切换 1457。
- 授权成功后从官方 Codex 模型目录获取账号实际模型，请求走官方 `/codex/responses` 并携带 `ChatGPT-Account-Id`。
- 全量 Flutter **1051/1051**、analyze exit 0（33 条既有 info）、Gradle release 构建和 release gate 均通过；在线模拟器已安装/冷启动并完成 1455 回调冒烟（错误 state=400、正确 state=200）。
- Release APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.250.0-263.apk`，SHA256 `13d6d6a5f71fcd7cb374fbc188c2f644c6e98bfe5c3fb451ff5b0dbc77615342`；包名/版本 `com.qingji.qingji.codex / 1.250.0 / 263`。
- 真实 OAuth/provider 网络、Token 交换、官方模型目录和 Responses 实际回复仍待用户在可联网设备登录验收。

### 2026-08-24 喵助手输入框最终字号与底部控件对齐（v1.243.0+256，待用户真机验收）

- GPT OAuth Android 使用 Chrome Custom Tabs，沿用系统浏览器的网络/代理路径；localhost 回调重绑和粘贴兜底保留。
- 输入框模型名称与 `High` 统一为 `15px`；模型名称自然宽度排列，仅与 `High` 保留约一个空白符宽度（4dp）。
- 无圆底加号由 22px 增至 33px（线长 +50%），加号、模型名称和思考强度统一垂直中心线，触控区域仍为 36px。
- 全量 Flutter **1048/1048**、analyze exit 0、release gate **9/9**；本轮已递增版本并重建 APK。
- Release APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.243.0-256.apk`，114,902,818 字节；SHA256 `4db579d9f5315f98e0f14acdb0fe7c86d56685551d11e81d62bd8594cd2d468a`；包名/版本 `com.qingji.qingji.codex / 1.243.0 / 256`，16 KiB 对齐、APK V2 固定证书等价门禁通过。

### 当前工作区 OAuth 回调、聊天字重与字号修复（2026-08-23，v1.241 源码已验收）

- 当前版本：`1.242.0+255`；build tag：`b0824-255`；DB v45；分支：`feature/ai-model-selector`。
- GPT OAuth 回调监听改为 IPv6 优先并补 IPv4；Android 使用 Chrome Custom Tabs 沿用系统浏览器网络路径，并允许 localhost 回调所需的最小明文流量；Activity 重建后 watcher 自动完成 Token 交换和模型保存。
- 本地回调页为 Cockpit 风格紫色成功页：“✅ 授权成功 / 您可以关闭此窗口并返回应用”；仍保留完整回调地址粘贴兜底。
- 喵助手进入 Chats 会话选择页：唯一置顶且不可删除的「记一记」会话承接主页账单；普通聊天会话支持新建、搜索、筛选全部/加星、长按重命名/加星/删除，并为每个会话独立保存服务商、模型和 Effort。
- 喵助手 Models 浮层按参考图锁定为 `195×224dp`，Effort 浮层锁定为 `222×102dp`；模型序号/选中勾、Faster/Smarter、帮助标记和 Ultracode 紫色颗粒轨道均由生产组件渲染，不是测试替身。
- Models 行的 hover/focus 浅灰圆角背景由生产状态显式控制，参考图中的悬停行已纳入 golden 验收。
- 本轮 Chats 几何收口：筛选浮层移到右上角按钮附近并将勾选置左；会话卡使用主题半透明 `AppColors.card/selectedCard`、18dp 圆角、68dp 最小高度、34dp 灰色聊天图标；搜索栏为单层半透明表面；底部控件移除重复 SafeArea；模型列表不显示服务商前缀；Effort 当前值为灰色。喵助手输入区的模型名称为 19px、思考强度为 16px，模型列表为 15px；两者之间固定 `4dp` 外部间距，滑块不改。
- 聊天用户消息与 AI 回复正文默认可变字重为 `w350`（减少 w50）；关键强调仍独立加粗。
- 模型目录在 `/v1/models` 超时、连接异常或非认证错误时回退 `/models`；目录为空时保留当前配置模型，用户明确删除的模型不会复活。
- 普通问答提示词不再强制 Markdown 排版、短回复或固定字数，性格改为“口语化、亲切”；账目准确性规则保留，报告仍使用独立文档模板。
- GPT OAuth 使用 PKCE、state 校验和 localhost 1455/1457 回调，授权后自动交换/刷新 Token 并获取模型；浏览器连接失败时可粘贴回调地址兜底。
- 主页 AI 记账入口保持 `recordOnly: true`，但任何非空自然语言都会先进入 AI 记账请求，不再在请求前调用本地意图规则拦截；`forceRecord: true` 保证模型按记账结构解析。空文本、忙碌状态和隐私授权仍是必要发送门槛；无 key/请求失败时才使用离线单笔兜底。全屏「喵助手」继续负责闲聊、知识问答和查账。
- 主页不恢复报告/问答历史，建议缓存按主页/喵助手模式隔离。`recordOnly` 已改成构造器必传，避免未来入口遗漏模式边界；收入解析补齐“13号失业金到账2250”“社保补贴到账”等指定日期的补贴收入。
- Flutter analyze exit 0（28 条既有 info）；OAuth/UI 定向回归 **21/21**；全量 Flutter 测试 **1048/1048**；release gate **9/9**；golden 结构断言通过。
- 最终 Release APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.241.0-254.apk`，114,902,818 字节；SHA256 `665951676d33a6012582e875715b050cb4e7518881d3dad770801328213bbf5f`；包名/版本 `com.qingji.qingji.codex / 1.241.0 / 254`，16 KiB 对齐、APK V2 固定证书和 release identity gate 已通过。
- 真实服务商网络、Android 真机 UI、IME 动画和安装观感仍待用户安装验收；本包未提交、未推送、未发布线上。

### 当前工作区新增启动修复（2026-07-18，尚未提交/发布）

- 本地验证 APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.202.0-204.apk`
- 版本：`1.202.0+204`；build tag：`b0718-204`；DB v40；SHA256：`3C178D9A6EE37DE806B281BD031058AD60A355E690844099534BAC421C566CC3`
- 当前启动合同：不再用“空主页先画、数据后掉入”换速度。启动首阶段读取账本/当前账本、账户、分类、预算、显示偏好和当月已持久化账单，真实本月数据就绪后立即进主页；全历史、资产、报告、定时物化、净资产、备份和旧退款归并在首帧后完成。
- 完整 hydration 前记账、Widget deep link 和冷启动分享会排队；后台服务不会读半快照。主题 JSON 异步读取，抽屉首次打开才构建。
- Android 12+ 的 `LaunchTheme` 必须包含 `windowSplashScreenAnimatedIcon=@drawable/splash_transparent` 和透明 icon background，不能让系统回退到 launcher icon。
- 验证已完成：启动/SQLite 专项 5/5、全量测试 752/752、analyze 0 issue、发布逻辑 9/9、aapt/16 KiB zipalign/固定证书 V2 签名通过。本轮无可用 Android 设备，未宣称真机冷启动观感通过；未 commit、未 push、未发布线上。

- 历史已发布基线 APK（非本轮）：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.196.0-198.apk`
- 历史基线版本：`1.196.0+198`
- build tag：`b0714-198`
- DB：v40
- 当前开发工作区分支：`codex/feimiao-p0-fixes`；本地功能提交 `1301e44`。因本地历史含 31 个超过 GitHub 100 MiB 限制的 APK，未改写原分支历史，改用无发布产物的源码快照 `6703f8e`（父提交 `61c0c06`）推到 `origin/codex/feimiao-p0-fixes`；当前线上为 v198（releaseId `v198-69ae3ccda9ad`）
- SHA256：`69AE3CCDA9ADE11D470E444E519CEC01483F701B495199A11EE0C744C1EC9A7E`
- 包名：`com.qingji.qingji.codex`
- 应用名：`肥喵记账`
- 签名：`CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`
- 注意：git status 里如果看到旧 release APK `1.167.0+169` 到 `1.181.0+183` 的删除状态，不要自动混入提交；那不是本次业务改动。
- v197、v195、v194 与 v193 APK/sidecar 必须保留为回退基线；不要用 `git clean` 删除。它们不代表 DB v40 运行后可以直接无损降级。
- v198 已把旧账无可靠时分时的 `00:00` 从所有账单卡隐藏，并用 DB v40 持久化时间精度；真实午夜仍显示。全量 707/707、analyze 0 issue，Release APK 的 aapt/16K/V2 签名/哈希均通过；已 commit、push 并发布，运行态仍待用户安装验收。

## 2. 历史已完成改动（当前启动修复见上方）

`1.196.0+198` 已完成旧账时间降噪并本地出包，等待用户安装验收：

- DB v40 给交易新增四态时间精度。旧数据只标记为未知，不改 `date_ms`，也不使用创建/更新时间补造；日期分组卡隐藏不可靠午夜，独立卡只显示日期，明确真实午夜保留 `00:00`。
- 主页、搜索、账单、报销、喵助手普通卡/退款卡、普通导入、肥喵 CSV、定时记账、退款报销和资产流水统一携带或继承精度；旧聊天 JSON/CSV 缺字段安全回退。CSV 为兼容旧格式继续输出固定 `yyyy-MM-dd HH:mm` 日期字段，并通过新增的时间精度列明确 `00:00` 是否可信。
- 智能建议改读真实精度：明确时分是完整时段证据，应用提交时钟降权，仅日期和旧未知不参与时段评分。定向 192/192、最终全量 707/707，full analyze 0 issue；APK 120,641,920 字节，SHA256 `69AE3CCDA9ADE11D470E444E519CEC01483F701B495199A11EE0C744C1EC9A7E`，aapt/16K/V2 签名和源/归档/sidecar 哈希通过。无连接设备，未做安装/冷启动。

`1.195.0+197` 已完成真机反馈修复并本地出包，等待用户安装验收：

- AI 纯日期合入提交时分，明确时间保持原样；手动/快捷新建写实际保存时刻，编辑改日期保留原时分。导入、自动与定时记账继续尊重来源；旧库 `00:00` 无可靠证据时不伪造。
- 建议从旧的“一级分类全历史中位数 + 随机建议/查账补满四条”改为 `SmartSuggestionEngine`：只学习近 180 天叶子分类与规范化备注/商户的跨日重复，旧午夜不算时段证据；金额不稳定时不带金额，证据不足允许 0 条，查询建议只由真实预算/账本数据触发。
- 探头猫按 PNG 约 1.8dp 右透明边把 bleed 调为 4dp，320px 明暗主题几何测试锁定贴边且不越屏。最终全量测试 691/691，full analyze 0 issue；APK 120,641,920 字节，SHA256 `836E22D684F77CD8E4446227F0E8CEE54CD5DFD75D1BD07901CAEB58A65B3AB6`，aapt/16K/V2 签名和源/归档/sidecar 哈希通过。无连接设备，未做安装/冷启动。

`1.194.0+196` 已完成预算、账单显示、喵助手与分类交互统一并本地出包，等待用户安装验收：

- 预算进度恢复低饱和健康绿 `#7FB069`，统一健康绿→临界铜金→超支橙；未完成轨道跟随当前进度末端色并带略深同色边缘。主页汇总卡改为真实内容高度，筛选条上下均为 8dp。
- 账单卡新增全局“内容优先（默认）/分类优先”偏好与预览；分组卡显示时分，独立卡显示完整日期时分、账本和次信息。用户消息气泡默认跟随卡片透明度，可选固定灰底，偏好持久化且未知旧值安全回退。
- 喵助手历史在同步定位后才显示，并补上恢复负责人被关闭时的新面板接管，进入不再先上下闪动或偶发空历史。手动备注 `done` 复用完成保存链并锁住退出前数字键盘。
- 手动记账、定时记账、喵助手改分类和导入复核统一使用 `HierarchicalCategoryPicker`，一级原位展开二级，选中、箭头、背景柔化和恢复/主动收起一致。
- analyze 0 issue；最终全量测试 664/664。APK 120,609,152 字节，SHA256 `BFA815FB8A04CE89BE560B8D29B940DCD457100C7378B60ED324468B84AB0BCD`；aapt、16K ZIP 对齐、唯一 Codex V2 签名和源/归档哈希均通过。
- 用户明确不做模拟器、真机安装或截图验收；应用运行态由用户自行安装确认。v196 未 commit、未 push、未发布，当前线上仍为 v195。

`1.193.0+195` 已完成资产日期仓储不变量封板，现为当前线上基线：

- 新购买物品在仓储层必须显式提供购买日期；物品、购买支出、结算日期、创建事件和初始估值统一使用同一天，缺日期时整笔拒绝且不产生半套数据。
- 账单来源物品始终继承原交易日期，普通编辑不能漂移或清空；启用折旧必须显式选择开始日期，不再回退今天。保修日期按自然日校验，创建和编辑都不能早于购买日，同一天不会因账单时分被误判。
- 本包完整包含 v194 的资产 UI 重做、照片优先详情页、三条新增路径、历史购买日补录、受管照片/凭证和标准控件铺开；v194 现作为本轮升级前回退包。
- analyze 0 issue；资产专项 38/38、最终全量测试 645/645。APK 120,592,516 字节，SHA256 `3C502EB61F4E372A1EB1787CC0E418AB19AAFD9EAAA7A4963CEB57E694F3BF4E`；aapt、16K ZIP 对齐、唯一 Codex V2 签名和源/副本哈希均通过。
- 用户明确不做模拟器、真机安装或截图验收；应用运行态由用户自行安装确认。**v195 已由 Claude 于 2026-07-14 提交(`bf50e97`)并发布上线**（releaseId `v195-3c502eb61f4e`，逐分片哈希与源一致）；v194 与 v193 保留为回退基线。
- A3b verified-checkpoint 纠错（superseding/revoked）与 A5 负债单一真相源仍未完成，继续作为独立后续批次。

`1.192.0+194` 已完成资产物品 UI 与购买日期纠错并本地出包，现为本轮升级前回退包：

- 手工新增/编辑可填写、补充或清空购买日期；新购买让物品、支出、事件和估值共用同一日期；账单来源日期由仓储强制继承。未知购买价持久化为 `manual_unknown`，不再用当前估值伪造日均与保值率。DB 保持 v39。
- 物品详情改成照片优先的普通二级页，日均和持有天数进入第一屏；生命周期动作收到右上菜单。物品网格以日均为主指标，unknown 显示待确认，并统一圆角、按压和读屏语义。
- 新增入口拆成账单加入、新购买记账、手工补录；表单全量使用标准件，补齐在用/闲置、照片、购买日、保修和净资产开关。估值/折旧支持历史日期；发票/保修单改受管文件选择，照片支持替换和移除。
- analyze 0 issue；资产定向 65/65、最终全量测试 641/641。APK 120,592,516 字节，SHA256 `C0208E5270788EE1A60F278354D29E6ACFE90D39425231535BCE79F34D36E845`；aapt、16K ZIP 对齐、唯一 Codex V2 签名和源/副本哈希均通过。
- 用户明确不做模拟器、真机安装或截图验收；应用运行态由用户自行安装确认。当前线上仍为 v185，v194 未上传；v193 保留为升级前回退基线。
- A3b verified-checkpoint 纠错（superseding/revoked）与 A5 负债单一真相源仍未完成，继续作为独立后续批次。

`1.191.0+193` 已完成 B3+A4 第五个双批并本地出包，现为上一份本地回退包：

- B3（DB v39）新增专项追踪：分类/标签范围按 OR 匹配，消费按退款家族净额计算；重叠专项彼此独立，不进入主预算。创建、编辑、管理和归档均已落地，编辑以归档旧计划+新建 successor 保留历史 cutoff。
- 删除专项历史引用的分类/标签会被阻止，分类合并会同步重写 scope。A4 补齐到期提醒、追加持有成本、使用次数与撤销、存钱目标关联，以及报废/丢失/赠送撤销；关联金额统一使用当前退款家族净额。
- 资产 JSON v6 按存钱目标 UUID 解析并报告 unresolved/rejected；非法/重复 usage reversal 会跳过且不回滚整批。早期 v39 中间态会在启动和恢复路径事务化自修复，先保留 `pre-v39-compat` 备份，partial usage 表可补列/重建并清理非法/重复 reversal。
- analyze 0 issue；B3/A4 扩展回归 79/79、共享仓储 111/111、最终全量测试 635/635。APK 120,428,384 字节，SHA256 `3A2345620F91524CC83A644F8BCFF76B8BBC186DA981B1DAE6CEA41FFF1D6F16`；aapt、16K ZIP 对齐、唯一 Codex V2 签名和源/副本哈希均已核验。
- 用户明确不做模拟器、真机安装或截图验收；应用运行态由用户自行安装确认。当前线上仍为 v185，v193 未上传；v192 保留为升级前回退基线。
- A3b verified-checkpoint 纠错（superseding/revoked）与 A5 负债单一真相源仍未完成，继续作为独立后续批次。

`1.190.0+192` 已完成 A3+B2 第四个双批并本地出包，现为上一份本地回退包：

- A3（DB v37）新增账户绝对余额 checkpoint、撤销、归档/恢复和可信余额趋势；锚点前补录被吸收，锚点后流水继续累计，unknown-date 转账按双腿覆盖，不造普通收支或预算。
- 完整净资产核对冻结 header/items；覆盖不足时只标 partial，过期物品估值必须显式接受，后续记账或估值不会静默改写旧核对证据。
- B2（DB v38）新增预算 plan/revision、绝对 cycle override、月/周周期和固定承诺 occurrence；默认下周期生效，本周期调整保存绝对总额，V2 归档后不会让 legacy 预算复活。
- 固定支出可按周期回显、匹配、跳过、重置和退款复核；actual/reserve 不重复扣，部分退款继续预留差额，恢复备份后会立即物化当前与下一周期 occurrence。
- analyze 0 issue；最终全量测试 587/587。APK 119,756,044 字节，SHA256 `363A58B13DBAA732495D9C8BE7A247597ED3F6B84EFD08D361BC821499362B45`；aapt、16K zipalign、唯一 Codex V2 签名和源/副本哈希均已核验。
- 用户明确不做模拟器/截图验收；应用运行态由用户自行安装确认。当前线上仍为 v185；B3/A4 已在 v193 完成，v192 保留为升级前回退基线。

`1.189.0+191` 已完成 A1+A2 第三个双批并本地出包，等待用户安装验收：

- A1（DB v35）已打通“已有账单→一账多物整数分配→退款分配→退货/出售/解除关联”闭环，不重复生成普通收支；物品页提供双列照片网格、搜索和分类/状态筛选，窄屏/大字号降为单列，相机/相册媒体进入受管目录并生成缩略图。
- 完整备份 package v2 同时包含 SQLite、收据和资产媒体，逐文件 SHA256、文件集合与路径安全校验；DB/收据/媒体分组件切换和独立回滚，恢复失败会清理 staging，v1 继续兼容。
- A2（DB v36）给账户详情增加逐结算事件近期活动，资产总览增加可信净资产估算趋势；旧快照降级为 `legacy_unverified`，历史日期不伪造，scopeVersion 持久化，civil day 和时区身份明确。
- 发布审查补齐定时记账、肥喵导入、删账本三条快照刷新；CNY 流水拒绝 legacy 外币账户；账单来源物品购买价锁定为净购置成本；近期活动长金额覆盖 320dp/130% 字号。
- analyze 0 issue；定向 112/112；最终全量测试 540/540。APK 118,920,116 字节，SHA256 `BB320F5F6FA725E41853F0D07722A4FA5498FEEC9C75FF25416482EAF3BE2556`；aapt、16K zipalign、唯一 Codex V2 签名和源/副本哈希均已核验。
- 用户明确不做模拟器/截图验收；应用运行态由用户自行安装确认。当前线上仍为 v185，v191 未上传；开发可继续下一组阶段。

`1.188.0+190` 已完成 A0+D0 第二个双批并本地出包，现为上一份本地测试包：

- A0（DB v33）拆分物品/权益的经济、使用、可见性和计入口径质量；旧归档数据按事件与金额矩阵等价迁移，归档/恢复不再改变金额或净资产计入；资产页改“总览 / 资金 / 物品”全局三视图，新增持有天数、日均持有花费、保值率、估值记录和报废/丢失/赠送闭环。
- D0（DB v34）给交易加入真实到账日期、到账账户、两项证据质量和事件类型；消费/预算继续按归属日，账户余额改按退款、报销、转账、出售和权益收回逐结算事件投影。旧退款/报销未知证据不伪造，可在退款记录补确认；账户与净资产会把 partial 明确显示为待确认、历史推定或按已知金额。
- 手工退款、喵助手、AI 快捷记账和待报销统一确认到账日/账户；肥喵 CSV 可往返双日期与质量。无法匹配/超额的导入退款不再造普通收入；通知退款不按普通收入自动保存，也不会在混合批保存时被顺带清除。
- 发布审查修复普通编辑伪升级结算证据、旧 CSV 报销误当商家退款、周期记账误标 exact 等问题。analyze 0 issue；最终全量测试 491/491；APK 115,069,684 字节，SHA256 `EEA6A350085C9499996D4A43C6B9FC4DEF431ED56172D42FCCB5E1CB09544998`；aapt、16K zipalign、单一 Codex V2 签名和源/副本哈希均已核验。
- 用户明确不做模拟器/真机截图验收；应用运行态由用户自行安装确认。当前线上仍为 v185，v190 未上传；A1/A2 已在 v191 完成。

`1.187.0+189` 已完成 C0+B0+B1 首个双批并本地出包，等待用户安装验收：

- C0 已落地统一指标查询/结果合同、整数分消费投影、退款归原消费期和等长同期窗口；未知、部分可用、不可用与冲突不再伪装成 0。
- B0 已建立预算唯一 resolver，兼容旧自然月循环预算和一次性期间 winner；支持历史 knowledge cutoff、逐日稳定分配及无预算/0 元/partial/conflict 独立状态，DB 保持 v32。
- B1 预算页改为“本周期 / 月 / 周 / 自定义”四段浏览和日期导航；主页、快速记账、喵洞察、统计、月报、Widget 与 AI 预算上下文均读取同一 resolver。发布审查修复了历史预算窗口误带当前“今日可用”的错期问题。
- 本版仍不提供固定支出预留后的“安全可花”；当前只显示按预算平均的今日可用/日均参考。analyze 0 issue；最终全量测试 445/445；APK 114,904,780 字节，SHA256 `02FD3E3AD0942EC2024F3A987890E557B3675AA44F0AF5B2F58C6B62FB249A34`；aapt、16K zipalign、单一 Codex V2 签名和源/副本哈希均已核验。
- 用户明确不做模拟器/真机截图验收；应用运行态由用户自行安装确认。当前线上仍为 v185，v189 未上传；v188 被本包取代。

`1.186.0+188` 已完成本地出包，现已被 v189 取代：

- AI 历史订单退款已在喵助手与快速 AI 入口统一为附着原单：只在唯一强匹配、金额合法时写入；缺金额/无匹配/歧义/超额均追问，退款查询不误写，日期数字不会冒充退款金额；成功退款卡可跨重启恢复。
- 自动记账页接入主题背景并精简文字层级；AI 设置删除重复分组与入口说明，6 个输入框改常驻标签、左对齐和标准灰阶。
- 预算与资产结构代码/DB 尚未修改；初稿与 V2 竞品研究稿保留，**当前锁定方案**为 `docs/claude/BUDGET_ASSET_UX_PLAN_V2_1_2026-07-12.md`。V2.1 修正双日期与到账账户质量、固定支出互斥预留、绝对校准锚点、整周期预算修订、物品成本、权益归档迁移、快照可信度和净资产算式。所有页面统计必须服从 `docs/claude/STATISTICS_CALCULATION_STANDARD.md`；该规范已升到文档 v1.1，按财务真值 `F-*`、派生分析 `D-*`、运营计数 `O-*` 登记当前 App 全部消费者，并明确 `current_exact/partial/inconsistent/target_only`。先做 C0 口径门禁，再进入 B0/A0。
- 抽屉真实对比图：`outputs/drawer_before_after_v188.png`，用户旧真机截图 vs 当前生产 UI 右滑渲染，1664x1848，SHA256 `B34E7DF815EE7D4287B5FE5934232806B09BC84C63D7619B87567908DAA44555`。
- analyze 0 issue；定向 111/111；最终全量测试 374/374；release APK、aapt、16K zipalign、Codex V2 签名和源/发布副本哈希均已核验。APK 114,626,156 字节，SHA256 `0A0282847451BE7650E4C3C89CE56ED4D306FF3AC0B6C13613462814E93C1FF7`。
- 用户明确不做模拟器/真机截图验收；应用运行态由用户自行安装确认。当前线上仍为 v185，v188 未上传；v187 被本包取代。

`1.185.0+187` 已完成本地出包，现已被 v188 取代：

- 主页探头猫改右边缘锚定轻呼吸，“今日可用”下移 8px；抽屉统一 Lucide 线性图标，删除“更多”箭头并补主页侧边界/定向阴影。
- 简约白预算轨道改可见中性灰；6 色卡单行；双滑杆改 iOS 风格并跟随色卡；删除极简模式但兼容旧偏好；备份页只展示最新 3 份且不删除升级保护文件；新建预算移到右上角。
- 新增 `AppLabeledField` 常驻字段标签；分类/定时分类弹层头部、新建存钱目标半屏表单、导入导出按钮/文案/日期范围统一标准 UI。
- 喵助手接入主题背景，次要操作和说明降为灰阶，回答操作栏收口 Claude 风格；IME 动画期间只禁用模糊、不替换 TextField 祖先结构，保留焦点稳定性。
- analyze 0 issue；AI 焦点回归 10/10；全量测试 364/364；release APK、aapt、zipalign、Codex V2 签名和源/发布副本哈希均已核验。APK 114,462,292 字节，SHA256 `8041C21299EFC1CA618ADC005D6272794BE90C6CEE77D74C0E54DCFC9699AE8E`。
- 用户明确取消模拟器截图，本轮运行态由用户自行安装验收。顺延六项：AI 退款附着原单、自动记账页、AI 设置页、预算展示方案、资产管理方案、抽屉前后对比图。

`1.184.0+186` 已完成本地出包，现已被 v187 取代：

- 真机主页灰卡并非透明度数值本身：截图背景约 `#F4E2BA`，Card 中心却为 `#CBC0AC`，确认是半透明 Material Card 与 elevation/阴影物理层在小米 GPU 上的深色合成。
- 主页大卡片、账单日卡改为 `GlassSurface(blur: 0)`，继续使用主题动态白色卡底和渐变发丝边；预算横条/圆环底轨改为半透明白。当前参数：卡片白 40% 不透明度（随用户滑杆变化），预算底轨浅色 56%、深色 14%。
- analyze 0；相关回归 10/10；全量测试 352/352；release APK、aapt、Codex V2 签名和发布目录哈希均已核验。APK 114,446,116 字节，SHA256 `C91C69ECE23E5E02CAE482B50D837286621785143B289C0F18C475172331D535`。
- v186 未上传且不再单独发布；对应修复已完整包含在 v187。

`1.183.0+185` 完成（**已上线**）：

- 常规账单新增、编辑、改分类、退款和删除改为受影响 ID/退款家族增量回读，不再全表 JOIN；新增回归测试锁定该行为。
- CSV/XLSX 解析和第三方账单标准化移到 `Isolate.run`；Widget 的 RGBA→PNG 压缩移到后台 isolate，两张卡拆帧且同一轮快照只构建一次。
- 报告改由 Android WorkManager 持久调度：联网重试、API Key 安全迁移、报告/聊天卡/job 原子幂等提交、完成通知、面板轮询恢复。Worker 初始化失败不挡首屏，数据库未就绪会重试，调度失败保留前台兜底。
- 运行态限制：本机 Emulator 36.6.11 的 3 个 AVD、WHPX 无快照冷启动和 `-accel off` 均未进入可用 guest，故没有伪造安装截图；真机重点复测 AI 键盘、报告杀进程续跑/通知、大导入响应和 Widget 连续刷新。

`1.182.0+184` 完成（本地包已被 v185 取代，不再单独上线）：

- 图二半透明暖白卡作为视觉基准保持不变；主页 Material Card 禁止 surface tint 二次染色；简约白页面底恢复 `#F7F8FA`。
- DB v32：自动记账精确事件幂等 + peek/ack 队列；报告任务持久化，跨页面/重启恢复，原账本锁定；统计/Widget/报告统一一级分类与退款净额口径。
- 无日期 AI 查账先全库关键词检索；聊天恢复解决重复/清空竞态；Widget PNG 单通道+代次+独立文件；更新兜底支持 Range；CSV 保留转入账户/标签/可报销；Android 禁止数据云备份。
- 运行态注意：本机 Emulator 36.6.11 在 WHPX 和纯软件 CPU 两种模式都冻结在 guest 启动前，未取得截图。真机必须复测图二主题、AI 键盘三查、报告切页持续生成。

`1.181.0+183` 完成（已上线）：主题外观系统（6色卡/双滑杆/极简模式）+UI设计标准v1(UI_DESIGN_STANDARD.md+AppType令牌)+GPT数据一致性批(DB v31:定时幂等/快照重建/事务化)+违规红清零。

`1.180.0+182`（已上线）：设置页 ChatGPT 化九连改（设置改全屏弹窗+右上✕/分组标题规格/Cupertino 图标/卡片透明度 52%/版本号只留检查更新/开关恢复灰槽白点/删宣传语/连续曲率圆角/抽屉齿轮图三化）+ 并入 181 的弹窗磨砂精修。
- 坑：`flutter test | tail && build` 管道吞测试退出码，测试一律落文件查 $?。

`1.178.0+180` 完成（应用内更新后台下载，已上线）：

- 下载改系统 DownloadManager：切后台/锁屏/杀进程不中断，通知栏系统进度，断点续传；弹窗加「后台下载」按钮；冷启动接续「已下载没装」的包不重下；SHA256 校验保留；DM 不可用回退进程内下载。
- Kotlin `feimiao/update` 通道 +5 方法；FileProvider 补 external-files-path。

`1.177.0+179`（已上线，全局弹窗统一图二 Cloudflare 风格）：

- 确认弹窗（ios_dialogs）：标题/正文左对齐；两颗同浅底等宽胶囊，文字主色蓝灰、危险=超支橙字（不再实心色底）。全 App showConfirmDialog 自动升级。
- 表单弹窗按钮（ios_form）文字改主色；下载进度弹窗左对齐。
- 消灭最后 3 处裸 Material AlertDialog：新建标签、编辑转账删除确认（顺手除掉违规红字）、截图识别中弹窗。
- 带上 178 后补的小组件快照指纹跳渲（数据没变不重渲 PNG）。
- 弹窗规范落地后：新弹窗一律走 showConfirmDialog / showIosFormDialog，别再手写 AlertDialog。

`1.176.0+178`（已上线）：更新校验加固、深色状态栏修复、退款净额 O(n²)→索引化、transactions 补索引、主页去重复模糊层。

## 3. 已验证

- `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`：0 issue
- `flutter test --no-pub --concurrency=1`：707/707 通过
- `flutter build apk --release --no-pub --build-name 1.196.0 --build-number 198`：成功
- `aapt dump badging`：`com.qingji.qingji.codex` / `versionCode=198` / `versionName=1.196.0` / label `肥喵记账`
- `zipalign -c -P 16 4`：通过
- `apksigner verify --print-certs`：唯一 Codex V2 签名通过，证书 SHA256 `4e99c399d4d246bd9c6b08b1d641248bd0846e7ae650c3a766e30fa67483d507`
- APK：120,641,920 字节；归档目录复制件 SHA256 `69AE3CCDA9ADE11D470E444E519CEC01483F701B495199A11EE0C744C1EC9A7E` 与源及 sidecar 一致
- 模拟器、真机安装和截图：按用户要求跳过；运行态待用户自行安装验收

## 4. 线上上传状态

- ✅ **v198 已由 Codex 于 2026-07-14 提交、推送并发布上线**：`1.196.0+198` / `b0714-198`；本地功能提交 `1301e44`，远端无产物源码快照 `6703f8e` 位于 `origin/codex/feimiao-p0-fixes`，Cloudflare releaseId `v198-69ae3ccda9ad`。公网 `version.json`、KV manifest、5 分片逐片内容、拼接 SHA256 与 Range 响应均已验证；用户自行安装验收。
- ↩️ **v197 APK/sidecar 原样保留**：作为本轮升级前本地回退基线，不是 DB v40 运行后的无损降级方案。
- ↩️ **v196 APK/sidecar 原样保留**：作为本轮升级前本地回退基线，不是 DB v39 运行后的无损降级方案。
- ↩️ **v194 APK/sidecar 原样保留**：作为本轮升级前回退基线，不是 DB v39 运行后的无损降级方案。
- ↩️ **v193 APK/sidecar 原样保留**：作为上一阶段回退基线，不是 DB v39 运行后的无损降级方案。
- ⏭️ **v192 已被 v193 完整取代，不再单独发布**。
- ⏭️ **v191 已被 v192 完整取代，不再单独发布**。
- ⏭️ **v190 已被 v191 完整取代，不再单独发布**。
- ⏭️ **v189 已被 v190 完整取代，不再单独发布**。
- ⏭️ **v188 已被 v189 完整取代，不再单独发布**。
- ⏭️ **v187 已被 v188 完整取代，不再单独发布**。
- ⏭️ **v186 已被 v187 完整取代，不再单独发布**。
- ✅ **v195 已由 Claude 于 2026-07-14 发布并逐分片验证**：releaseId `v195-3c502eb61f4e`，version.json 返回 195、sha256 干净、5 分片拼接哈希与源 APK 完全一致。发布时 Cloudflare 连接抖动，改用逐分片带重试上传（version.json 最后原子切换，过程中线上保持 185 不受影响）。
- ✅ **v185 已由 Claude 于 2026-07-11 发布并逐分片验证**：releaseId `v185-a42a2d3875b8`，现已被 v195 覆盖；v184 已被 v185 完整取代，不单独发布。
- ✅ **v183 已由 Claude 于 2026-07-11 发布并验证**：releaseId `v183-606eba7269a6`，5 分片拼接哈希与源一致。
- ✅ **v182 已由 Claude 于 2026-07-10 发布并验证**（用户拍板）：releaseId `v182-569b5149efcc`，version.json 干净，5 分片拼接哈希与源一致。
- ✅ **v180 已由 Claude 于 2026-07-10 发布并验证**：releaseId `v180-66b213368d44`。version.json/sha256 干净；本机代理拉不动整包长连接（curl 56 非线上问题），改逐分片校验：5 分片大小全对、拼接哈希与源一致。真机 DownloadManager 有断点续传不受此影响。
- ✅ **v179 已由 Claude 于 2026-07-10 发布并验证**：releaseId `v179-23cf92a491b2`（干净）。验证四连：version.json 返回 179、sha256 干净、响应头一致、全量下载 111,425,943 字节哈希与源相同。注意：发布脚本必须在 **Git Bash** 跑，用户 PowerShell 里的 `bash` 是 WSL，Windows 路径会挂在 stat 第一步。
- ✅ **v178 已由 Claude 于 2026-07-10 发布并验证**（用户拍板）：releaseId `v178-61752a7c6383`（干净无反斜杠）。验证四连：version.json 返回 178；`sha256` 为干净 64 位 hex；响应头 `x-feimiao-sha256` 一致；**全量下载 111,442,327 字节，sha256 与源 APK 完全相同**。
- 历史备注：v177 元数据曾被 `\` 前缀污染（sha256sum 传 Windows 路径触发 coreutils 转义），Claude 曾直接改写 KV 的 `version.json`/manifest `sha256` 字段修复过一轮，现已被 v178 整体覆盖。发布脚本已改 stdin 计算 sha，后续不会再产生。**发布后的固定动作：重新拉 `version.json`，确认 `sha256` 是 64 位干净 hex。**

## 5. 新 Claude 会话阅读顺序

1. `android-app/docs/claude/CLAUDE_START_HERE.md`
2. `android-app/docs/claude/CLAUDE_HANDOFF_CURRENT.md`
   （动任何 UI 前必读：`docs/claude/UI_DESIGN_STANDARD.md`——全套设计标准，不符合=bug）
   （**提交或发布上线前必读**：`docs/claude/COMMIT_AND_PUBLISH_RUNBOOK.md`——commit/出包/发布逐步 SOP + 所有踩过的坑）
3. `android-app/CHANGELOG_CODEX.md` 顶部最近 3-5 节
4. `C:\Users\寻逆啊\iCloud\iCloudDrive\iCloud~md~obsidian\寻逆笔记\记账app\肥喵记账App开发笔记.md`
5. 用户明确点名时，才读并执行 `android-app/docs/claude/TASKS_FOR_CODEX.md`

## 6. 文档维护铁律

每次做功能、修 UI、构建 APK、上传线上更新，都必须同步维护：

- `android-app/docs/claude/CLAUDE_START_HERE.md`
- `android-app/docs/claude/CLAUDE_HANDOFF_CURRENT.md`
- `android-app/CHANGELOG_CODEX.md`
- `C:\Users\寻逆啊\iCloud\iCloudDrive\iCloud~md~obsidian\寻逆笔记\记账app\肥喵记账App开发笔记.md`

当前入口必须短、准，让新 Claude 30 秒内知道真实最新状态。
