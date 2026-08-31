## 2026-09-01 v1.283.0+297 Cockpit JSON 边界与 AI 传输收口

- **JSON 解析补齐**：支持已解码的 `data`/`payload`/`content` 包装对象和列表，以及 `exported_data` 直接承载单个凭据对象；保持只导入 Codex 凭据并避免把普通元数据误当账号。
- **认证模式稳定**：账号顶层显式 `auth_mode` 优先于嵌套 token/credentials，API Key 不会因 stale OAuth 字段被误判为 OAuth，OAuth 也不会被 stale API Key 覆盖。
- **传输边界统一**：`LlmEntryParser` 与 `LlmQueryV2` 流式请求复用共享 `AiHttpTransport`，统一代理/PAC 刷新、超时和重试生命周期，保留 localhost-only companion 的隔离边界。
- **事务回归加强**：补充禁用账号跳过验证、单账号元数据失败无孤儿凭据、批量回滚恢复选择/健康状态/安全凭据等测试。
- **验证**：Flutter 全量 **1194/1194**；OAuth/JSON/传输定向 **48/48**；导入 Controller/仓库定向 **32/32**；Dart analyze 0 error（91 条既有 warning/info）；Android `:app:compileDebugKotlin` 成功；Release identity gate 通过（16 KiB、APK V2、固定证书）。
- **APK**：`C:\src\xunni-codex\android-app\build\app\outputs\flutter-apk\app-release.apk`，117,658,041 字节，SHA256 `8e02474d7bf81e60bc6201b0ffff60024d5fd16cef95057b78ea30944c8a9cd9`。
- **边界**：当前无在线 Android ADB；手机 Chrome 账号选择、VPN 出口、localhost 回调、安装冷启动和实机字体/输入法观感仍需目标设备复测；未使用 Plus 账号。

## 2026-08-31 v1.282.0+296 AI 账号导入事务与架构收口

- **导入职责收口**：新增 `AiAccountImportController` 与仓库适配边界，设置页只负责预览选择和结果展示；导入、逐账号验证、模型目录保存和批量提交由应用层统一编排。
- **失败隔离**：单个账号导入失败或验证器异常会记录脱敏问题并继续处理其他账号；停用账号保留导入状态且跳过网络验证；模型目录和健康状态按账号保存。
- **事务一致性**：批量导入提交失败时恢复账号目录、用途选择、健康状态及安全凭据；“新建副本”不会误覆盖已有账号，只有“更新已有”才使用原账号 ID。
- **验证**：Controller 定向测试 3/3，Flutter 全量测试 1189/1189，Dart analyze 0 error；未修改 iOS 或指定 integration_test 文件。

## 2026-08-31 v1.281.0+295 GPT OAuth、Cockpit JSON 与架构收口

- **OAuth 稳定链路**：普通按钮固定走官方 PKCE + `auth.openai.com/oauth/authorize` + localhost:1455/1457；Android 原生回调保活支持 IPv4/IPv6、Activity 重建、重复回调和 flowId 隔离。修正 `ProxySelector=DIRECT` 但系统存在固定代理时的路由错误；Token authorization-code 交换收到 `unsupported_country_region` 时，使用本机私有一次性页面让 Chrome 通过自身 VPN 完成交换，code/verifier 不进入 URL 或第三方服务。
- **成功判定完整**：授权 Token 先安全持久化，再获取官方模型目录；登录完成和恢复路径都会用首个模型执行不携带账本内容的最小 `ping`，并在账号健康记录中保存“可用/需代理/凭据失效/模型不可用/网络失败”等阶段状态。目录失败不会丢已登录账号。
- **Cockpit JSON**：完整备份 `accounts.platforms.codex.exported_data`、standalone transfer、auth.json、Sub2API、嵌套 token、refresh-only、PAT、JSON/JSONL、BOM/UTF-16 均可解析；显式 `auth_mode=apikey` 优先于 stale OAuth 字段；workspace/account_id 单独不再去重；provider 的地址、wire format、模型目录和 API Key 关联会合并。导入预览支持更新/副本/跳过，凭据仅写入安全存储，逐账号可验证并可重试。
- **架构与数据安全**：新增共享 `AiHttpTransport`；OAuth、模型、Responses、主页记账、Chats、联网搜索共用代理刷新与超时边界。健康状态增加显式验证字段；错误/AI run/报告错误统一脱敏；迁移列改为显式“缺列才添加”，真实 SQLite 错误不再被空 catch 吞掉，数据库版本升至 v49。
- **验证**：Flutter 全量 **1182/1182**；OAuth/JSON/代理/健康/仓库定向回归通过；Dart analyze 0 error（91 条既有 warning/info）；Android `:app:compileDebugKotlin` 成功；Release gate 通过（包名 `com.qingji.qingji.codex`、版本 `1.281.0+295`、16 KiB、APK V2、固定证书）。本机 2026-08-31 Cockpit 完整备份解析 **9 个 Codex 账号（6 OAuth、3 API Key），0 警告**。
- **APK**：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.281.0-295.apk`，117,707,189 字节，SHA256 `A3960191D17E8CB2E2EA4B4D0310C9A8579B39127F8A317E86E73E1BAC9C07BA`。
- **边界**：当前无在线 Android ADB，真实手机 Chrome Ephemeral/账号选择、VPN 出口、localhost 回调、设备码显式流程、安装冷启动和字体/输入法观感仍需目标手机复测；未使用 Plus 账号。

## 2026-08-30 v1.279.0+293 GPT OAuth 旧设备授权状态迁移

- **根因补齐**：Android 普通授权入口继续只走 Cockpit 默认的浏览器 PKCE 流程；升级后发现旧版本可能在安全存储里遗留 device-auth 状态，启动恢复器会继续轮询地区受限的设备授权接口，造成用户明明安装新包仍看到 `unsupported_country_region` 403。
- **迁移修复**：设备授权会话不再写入持久化安全存储；读取到旧设备授权状态时立即清理，不再恢复或轮询。浏览器 PKCE 的 state、verifier、回调地址仍会持久化，Android Activity 重建后可继续完成 localhost 回调。
- **Cockpit 对齐**：对照当前开源实现，默认 `start_oauth_login` 为 PKCE + localhost:1455，device-auth 是独立显式流程，并且 Cockpit 不持久化设备授权状态。
- **验证**：OAuth/JSON/Responses/设置定向 `126/126`；Flutter 全量 `1171/1171`；Dart analyze 无 error；Release 构建及包身份门禁通过（16 KiB、V2、固定证书）。APK `C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.279.0-293.apk`，117,543,353 字节，SHA256 `2B5B85A5636C1F6E8C2E2F345B93B1E35680AA2020DBD613CD33A83F61F4C307`。
- **边界**：本机无在线 Android ADB，真实手机 VPN、Chrome 账号选择、localhost 回调和网络出口仍需安装后复测；未使用 Plus 账号。

## 2026-08-30 v1.278.0+292 GPT OAuth Android 默认流程修复

- **修复截图中的 403**：Android“GPT OAuth 授权”不再先调用地区受限的设备授权码接口；恢复 Cockpit 默认的 `auth.openai.com/oauth/authorize` PKCE 浏览器流程。原生 localhost 回调保活、账号选择隔离、Token 交换/刷新和模型目录获取继续保留。
- **设备授权边界**：设备码 API 仍保留为显式服务能力，但不再作为普通授权按钮的默认入口，避免手机网络出口直接收到 `unsupported_country_region` 后在授权页前失败。
- **验证**：OAuth/JSON/Responses/设置定向回归 `113/113`；Flutter 全量 `1171/1171`；Dart analyze 无 error；Android `:app:compileDebugKotlin` 与 Release 构建成功；APK 包名、版本、16 KiB 对齐、APK V2 和固定证书 gate 通过。Cockpit 源码对照确认默认入口为 PKCE 浏览器授权；真实手机安装复测仍需目标设备。
- **APK**：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.278.0-292.apk`，117,543,349 字节，SHA256 `0F893CD39C9386BA4C6D325A6B3C417BA1E3CB311B997BD38400BFA2A6C672FD`。

## 2026-08-30 v1.277.0+291 GPT OAuth/JSON 导入最终链路修复

- **官方 Codex Responses**：修复 GPT OAuth 的缓冲请求仍发送 `stream: false` 的问题。官方 ChatGPT/Codex 端点要求 `stream: true`，现在普通问答、主页记账、报告和连接测试共用的 Responses 传输层会统一强制该标志，并保留官方会话/请求元数据。
- **OAuth 与网络**：保留设备授权码流程、PKCE/state、Token 刷新、模型目录重试、Android 系统代理/PAC 路由和首包重试；聊天请求也补齐按目标地址的代理解析。
- **Cockpit JSON**：保留完整备份 `accounts.platforms.codex.exported_data`、嵌套 token、refresh-only、PAT、API Key、多账号和 UTF-8/UTF-16 导入支持；本机真实 Cockpit 备份解析出 10 个 Codex 账号且无警告。
- **验证**：OAuth/Responses/JSON/仓库定向回归 `113/113`；Flutter 全量测试 `1171/1171`；Flutter analyze 无 error；Android `:app:compileDebugKotlin` 成功；指定测试账号真实模型目录 HTTP 200（6 个模型），真实流式 Responses HTTP 200 并解析 `OK`，肥喵 `LlmQueryV2` 与主页 `LlmQuery` 路径均真实返回 `OK`。
- **边界**：当前设备无在线 Android ADB，未把真机 VPN、Chrome Custom Tab、输入法和实机字体观感写成已验证；APK 构建后需在目标手机安装复测。

## 2026-08-30 v1.275.0+289 月份选择弹窗回退与交付验证

- **月份选择弹窗**：按用户提供的旧版参考图回退为轻量底部弹层；移除弹层内关闭圆圈和背景高斯模糊，标题左对齐、月统计起始日右对齐并保持同一行；年份箭头恢复无圆形视觉底，年份切换和月份网格数据逻辑不变。
- **回归与证据**：月份选择器/全局 UI 定向回归 `3/3`；Flutter 全量测试 `1164/1164`；Dart analyze exit 0、无 error（84 条既有 warning/info）。前后原图及带编号左右对比图位于 `outputs/ui_comparisons/2026-08-30/`。
- **APK**：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.275.0-289.apk`，117,445,045 字节，SHA256 `196FED571B03372A4F89211034759E89061A8AF00B72163DD1542D27C4C4B56B`；包名/版本 `com.qingji.qingji.codex / 1.275.0 / 289`，16 KiB 对齐、APK V2 和固定证书 gate 通过。
- **线上状态**：本轮 APK 只完成本地构建和验收，未发布线上；v1.270.0+284 仍为线上回退版本。
- **限制**：本机无在线 Android 设备，VPN 分流、Chrome Custom Tab、真实 OAuth/JSON 导入和真机观感仍需在目标手机安装后验证。

## 2026-08-30 v1.274.0+288 OAuth 网络与账号 JSON 导入修复

- **Cockpit 完整备份导入**：识别 `accounts.platforms.codex.exported_data` 和单独 `exported_data` 传输段，只导入 Codex 凭据，不把 Claude 等其它平台混入 GPT 账号。
- **个人访问令牌**：对 `at-...` 账号按官方 Codex 流程调用 `auth.openai.com/api/accounts/v1/user-auth-credential/whoami` 获取工作区 ID，再请求模型目录和 Responses；身份结果通过现有安全保存回调持久化。
- **模型目录链路**：模型获取、PAT 身份查询和 401 刷新复用同一个 OAuth service/client，避免注入测试/代理客户端与实际刷新客户端分裂。
- **验证**：OAuth/JSON/模型目录定向回归 `53/53`；Flutter 全量测试 `1164/1164`；Dart analyze 无 error；本机实际 Cockpit 完整备份解析 9 个 Codex 账号（5 个 OAuth）且 0 条警告。
- **APK**：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.274.0-288.apk`，117,445,049 字节，SHA256 `9459F72F75845DF38D53385FA7B60E731B695BDC749673BAC6EA79A854D19035`；包名 `com.qingji.qingji.codex`，16 KiB 对齐、APK V2 和固定证书 gate 通过。
- **限制**：本机无在线 Android 设备，手机 VPN 分流、Chrome Custom Tab 和真实账号闭环仍需在目标手机上验证。

## 2026-08-29 v1.270.0+284 UI 收口与 GPT OAuth 账号选择修复

- **Chats 进入态**：普通聊天不再显示主页“本月超预算”提醒；保留记账入口的预算提示。
- **主页预算卡**：月份标签统一 15px，数字使用 w500；超过预算显示实际整数百分比并四舍五入；“月预算已超”字重增加 w50；窄屏底部预算文字改为可收缩布局，避免横向溢出。
- **月份选择器**：恢复参考半屏布局；年份左右箭头取消圆形表面但保留 48dp 热区；修正左上角关闭按钮位置。
- **Chats/AI 账号**：Chats 标题字重增加 w100、相对时间字重增加 w50；AI 账号删除按钮移除圆圈并降低图标灰度。
- **OAuth 多账号**：授权 URL 增加 `prompt=select_account`，普通浏览器回退时也会进入账号选择页，不再静默复用个人空间；PKCE/state、Ephemeral/无痕优先、原生回调保活和失败恢复继续保留。
- **真实验收**：测试账号 OAuth 回调 HTTP 200、Token 交换 HTTP 200、官方 Codex 模型目录 HTTP 200（6 个模型）、Responses 实际请求 HTTP 200 且收到正文；Flutter 全量 `1134/1134`，Dart analyze 无 error。
- **UI 证据**：本轮 9 组 before/after/并排标注图和总览图位于 `outputs/ui_comparisons/2026-08-29/`，原始截图保留在 `before/`，改后截图保留在 `after/`。
- **线上发布**：已发布到 Cloudflare KV，releaseId=`v284-65be62b73c2b`；公网 `version.json`、Range 响应和完整 APK 下载哈希均与本地包一致。发布脚本现在自动保留当前版本与上一版本，清理更旧 release 键。

## 2026-08-29 v1.269.0+283 GPT OAuth 回调时序与多账号兼容修复

- **修复回调监听竞态**：Android 前台恢复不再因瞬时健康探测失败先停止当前 OAuth 服务；同一 flow 只做唤醒/修复，避免 Chrome 回调期间出现 `localhost:1455 ERR_CONNECTION_REFUSED`。
- **修复失败页误导**：Token 交换临时失败时保留已捕获的回调和原生监听 30 秒，允许应用直接重试并避免浏览器把成功回调刷新成拒绝页；成功、取消和过期仍会清理服务。
- **多账号登录**：Ephemeral Custom Tab 不可用时改用 Chrome Incognito 标签隔离 Cookie，避免直接复用当前个人空间；补充 Android 11+ Chrome 包可见性声明。
- **可靠性**：原生监听端口支持快速重认证复用；保留 PKCE/state、flowId 隔离、回调持久化和手动粘贴回调兜底。
- **验证**：OAuth/设置定向回归通过；Flutter 全量测试 `1129/1129`；Gradle `:app:compileDebugKotlin` 成功。真实账号/网络仍需在联网 Android 真机安装后验收。

## 2026-08-29 v1.268.0+282 GPT OAuth Android 回调与账号隔离修复

- **修复个人空间复用**：补充 Android 11+ Custom Tabs 服务可见性声明，让 Chrome Ephemeral Custom Tab 探测真正生效；支持的 Chrome 会使用隔离 Cookie 会话，不再直接带入当前个人空间。
- **修复 localhost 拒绝**：Android 原生 OAuth 保活监听未成功绑定时不再退回易失的 Dart 监听，也不再打开授权页；原生服务启动等待窗口延长到 10 秒，避免慢设备在授权过程中丢失 `localhost:1455` 回调。
- **保持恢复能力**：PKCE/state、回调持久化、flowId 隔离、Token 失败重试和手动粘贴回调继续保留。
- **验证**：OAuth/设置/账号定向回归 `39/39`；Gradle `:app:compileDebugKotlin` 成功。真实 Google/ChatGPT 账号切换和网络请求仍需联网 Android 真机验收。

## 2026-08-29 v1.267.0+281 GPT OAuth 多账号与回调恢复修复

- **隔离登录会话**：Android 优先使用 Chrome 137+/AndroidX Browser 1.9 的 Ephemeral Custom Tab，GPT 授权不再复用当前 Chrome 的个人空间，可在授权页选择其他 ChatGPT/Google 账号；旧浏览器自动回退外部浏览器和手动回调。
- **授权码交换对齐官方**：授权码交换恢复 Cockpit/官方 Codex 的原始表单请求，不附加运行时身份头；Token 刷新使用官方 JSON 请求和 Codex Desktop 身份头，减少授权端拒绝。
- **失败可恢复**：浏览器回调先持久化；原生回调文件按 flowId 读取与清理，Token 交换中途进程被回收或失败后可回到应用继续重试，旧授权流程不能删除新流程回调。
- **诊断**：Token 失败提示保留安全的状态码/错误摘要，便于区分授权码失效、网络故障和服务端错误，不暴露 Token。
- **验证**：Flutter analyze exit 0；OAuth/设置/账号定向回归 `39/39`；全量 Flutter `1129/1129`；Gradle `:app:compileDebugKotlin` 成功。真实 Google/ChatGPT 登录和官方模型请求仍需联网 Android 真机验收。

## 2026-08-28 v1.265.0+279 Android CI 编译修复与 iOS 首页入口对齐

- **Android CI**：升级 Workmanager 到 `0.10.9`（Android 实现 `0.10.8`），修复 AGP 9 + `android.builtInKotlin=false` 下 Kotlin 插件未编译、`GeneratedPluginRegistrant.java` 找不到 `WorkmanagerPlugin` 的 clean-runner 错误；上游修复对应 Workmanager #722。
- **iOS 首页**：移除首页与安卓主流程冲突的快捷操作卡，补齐顶部菜单/搜索/账本入口、收支筛选和底部「记一记」输入框；手动/AI 分流保留 iOS Liquid Glass 和原生按压反馈。
- **路由与截图门禁**：设置深链改为目标值绑定，iOS 截图脚本新增内容区非空检查；冷启动截图等待时间延长，避免保存白屏 PNG 冒充通过。
- **本地验证**：Android debug APK 构建成功；Flutter analyze 无 error；全量 Flutter **1127/1127**。iOS 需由 macOS CI 完成编译和截图复验。

## 2026-08-28 v1.264.0+278 全局 UI 收口（Codex，本地交付候选）

- **公共 UI 契约**：在 `AppType`、`AppControl`、`AppHitTarget` 中收口字号、视觉尺寸和触控尺寸；圆形按钮保留 34/38px 视觉大小，独立操作热区至少 48dp，顶栏按钮不再撑高布局。
- **弹窗与设置**：AI 记忆、本地伴侣地址、自动记账候选、收据来源、月份选择、标签、来源、图表库和个人中心等入口统一使用毛玻璃弹层、`SheetHeader`、`SettingsGroup/SettingsRow` 和胶囊动作；设置页移除私有重复行组件。
- **按钮、菜单和选择件**：统一圆形/胶囊按钮的禁用、加载、边框、图标和语义标签；新增 `AppCheckmark`，避免整行与勾选件重复响应；选项菜单危险色统一为肥喵警示橙。
- **响应式与字体**：修复 AI 账号尾部值在大字号下溢出；统一菜单/弹窗/操作文字 Token；覆盖 320dp、200% 字体、深色主题和 CJK/Latin 混排。
- **视觉证据**：新增 `outputs/global_ui/settings.png`、`outputs/global_ui/gallery.png`；刷新 AI 账号、输入框、Claude 加号/图片和 Chats golden，实际截图人工复核通过。
- **验证**：Dart analyze 无 error（64 条既有 warning/info）；串行全量 Flutter **1124/1124**；全局 UI、设置表单、资产滚动、AI 账号、输入框、Claude/Chats 视觉回归全部通过。
- **APK**：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.264.0-278.apk`，116,596,258 字节，SHA256 `3BFC09913BB28C0CC783C30773C459570B7195BCE321DAF530FF2A9DCE6FF07C`；包名 `com.qingji.qingji.codex`，versionName `1.264.0`，versionCode `278`；16KiB 对齐、APK v2 和固定证书 gate 通过。
- **边界**：本机无在线 ADB，真实 ChatGPT OAuth、provider 网络、IME、相册和真机字体观感仍需用户在可联网 Android 设备验收；未修改 `ios-app/**` 及指定 Android `integration_test`/`test_driver` 文件。

## 2026-08-28 v1.263.0+277 深度审计补修（Codex，本地交付候选）

- **OAuth 凭据完整性**：Cockpit refresh-only 账号在首次模型目录/请求前强制交换 access token；报告、隐私确认、账单复核和快速记账不再把 OAuth 误判为无 API Key。
- **报告思考计时**：`model_started_ms` 只在真正调用模型前 compare-and-set 写入；排队/上下文/WorkManager 交接不计入时长，恢复未开始模型的任务不伪造创建时间，CAS 赢家会回写 UI。
- **回复与字体**：富文本显式 Nunito + Noto Sans SC fallback，修复 CJK 方块；正文裸来源 URL 移入来源操作栏/上拉面板，中文标点不会吞掉后续正文。
- **截图证据**：思考、来源、三图和 Claude 加号 golden 改为真实暖背景整屏，人工复核通过；Claude/Chats 视觉回归 **16/16**。
- **验证**：Flutter analyze 无 error（60 条既有 warning/info）；全量 Flutter **1118/1118**；OAuth/账号与报告计时定向回归通过；Release identity gate 通过。
- **APK**：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.263.0-277.apk`，117,071,394 字节，SHA256 `C31C24AF83AD5A4BC3BAD245D86536EB60CA124DCB1E54F3ED4C32F0AEAEE509`；包名 `com.qingji.qingji.codex`，versionName `1.263.0`，versionCode `277`。
- **边界**：本机无在线 ADB，真实 ChatGPT OAuth/Token/官方模型请求、IME、相册和字体观感仍需用户在可联网 Android 设备验收；未修改 `ios-app/**` 及指定 Android 集成测试文件。

## 2026-08-27 v1.262.0+276 交付前收口：附件累计上限与报告思考起点

- **附件可靠性**：喵助手草稿现在在每次添加附件时统一执行每条消息最多 3 张图片、10 个文件的限制；重复打开相册或从“添加文件”选择图片也会计入同一上限，超出的附件即时提示并不进入草稿，不再等发送时整批失败。
- **报告思考计时**：报告任务新增 `model_started_ms`（DB v48），首次模型处理时间使用 compare-and-set 持久化；前台、WorkManager 和恢复路径共享同一个时间点，重新打开 Chats 不会把“思考了 Xs”重置为重新打开的时刻。
- **验证**：`flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` exit 0（57 条既有 warning/info）；全量 Flutter **1114/1114**；附件/报告迁移/会话恢复/思考与输入框定向回归通过。
- **交付**：Release APK [feimiao-codex-v1.262.0-276.apk](C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.262.0-276.apk)，117,071,394 字节，SHA256 `A3839FFBBE94104866888EA73A0ECBD7A303C2E6A67AE4447FEFE41B18268A6B`；包名 `com.qingji.qingji.codex`，versionName `1.262.0`，versionCode `276`，16 KiB 对齐、APK V2、固定证书 gate 通过。
- **运行态边界**：本机 `adb devices` 无在线设备，未执行新包安装/冷启动；真实 ChatGPT OAuth、Token 交换、官方模型目录/Responses、系统相册/文件选择器、IME 和视觉观感仍需用户在可联网 Android 设备验收。iOS 与指定的 Android `integration_test`/`test_driver` 文件本轮未修改。

## 2026-08-27 v1.261.0+275 AI 分层能力与 8-27 需求收口

- **正确性与安全**：AI run/event 持久化、幂等和 flow ownership 完成；结构化账单提案以数据库事务原子提交并支持撤销；reasoning 事件只保存字符数摘要，不保存原始思考文本；服务商健康、连接器协议/主机白名单、图片大小/数量与本地 companion 回环限制完成。
- **体验与效率**：上下文检查器接入按轮压缩与预算；后台任务中心、可控记忆、诊断页和统一搜索完成；前台/后台请求有 120 秒收口，首条消息等待 ready barrier，短回复、表格横滑、来源和操作栏按参考图收紧。
- **8-27 UI**：全局选项弹层和半屏表单统一白色轻模糊/灰幕/圆角；Claude 风格加号菜单支持近期图片多选、编号、相册/文件入口和上传进度；思考状态、摘要、消息操作、模型/Effort 选中态、透明输入框及三图满宽布局完成。
- **扩展能力**：受控内部技能/连接器、定时报表配置和本地模型 companion service 保留为显式可控入口，不开放任意 shell、远程 MCP 或自动财务写入。
- **验证**：Dart 分析无 error（56 条既有 warning/info）；全量 Flutter **1109/1109**；本轮 AI/UI/图片/思考/来源/模型/菜单定向回归及视觉回归通过。真实 OAuth、provider 网络、IME、系统相册/文件选择器和 Android 真机安装冷启动仍需用户设备验收。
- **交付**：Release APK `C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.261.0-275.apk`，117,038,626 字节，SHA256 `04692649468A63A11FC22E0DF4530A3DAFC36EFD2EA3BCB9FE41533B1F39C8C2`；包名 `com.qingji.qingji.codex`，versionName `1.261.0`，versionCode `275`，16 KiB 对齐、APK V2、固定证书通过。

## 2026-08-27 v1.260.0+274 参考图对齐修复

- 三图消息改为参考图的聊天内容区满宽方形三等分，保留左右内容边距和卡片间细间距；不再越过聊天视口边界，也不再使用 3:4 竖向卡片。
- 思考 flow ownership 修复、120 秒有限收口、真实附件解码和后台报告轮询保持不变。
- **验证与交付**：串行全量 Flutter **1094/1094**、严格 Claude/Chats 视觉 **16/16**、AI 请求/重试/Responses **36/36**、AI/UI/会话/图片/思考/来源/模型/菜单 **104/104**、静态分析 exit 0（45 条既有 info/warning）；Release APK `C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.260.0-274.apk` 已构建并通过 release identity gate，116,446,150 字节，SHA256 `2A603BF8B063F26D6FD393591D7440275FE652CE81EA6CA6935595A1E85F36EA`。

## 2026-08-27 v1.260.0+273 后台思考流程与三图布局最终修复（Codex，本地交付）

- **思考流程根因修复**：报告交给 WorkManager 后，发送 Future 不再提前释放 flow ownership；计时器和报告轮询会持续到任务完成、失败或 120 秒 UI 交接，避免消息永久停留在“正在思考”。失败状态也会释放旧 flow，迟到回调不会污染新消息。
- **图片边界**：生产历史区三张已发送图片突破聊天内容两侧内边距，真实图片一行 3:4 卡片贴合 390dp 聊天视口；输入框草稿仍首屏三格，第四张可横向查看。
- **版本与验证**：`flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` exit 0（45 条既有 info/warning）；串行全量 Flutter **1094/1094**；严格 Claude/Chats 视觉回归 **16/16**；生产历史区三图边界、恢复竞态和思考状态回归通过。
- **APK**：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.260.0-273.apk`，116,446,150 字节，SHA256 `4D5034CD5F6288C6E53EC8F78633288E89588BDB579B0A9D18C2044ACDAF15DE`；包名 `com.qingji.qingji.codex`，versionName `1.260.0`，versionCode `273`，16 KiB 对齐、APK V2、固定证书 gate 通过。
- **边界**：本机无在线 ADB；真实 ChatGPT OAuth/Token、官方模型目录、provider Responses、IME、系统文件选择器和真机字体观感仍需用户在可联网 Android 设备验收。源码未提交、未推送、未发布线上。

## 2026-08-27 v1.259.0+272 设置页模型列表字号、思考超时与三图布局收口（Codex，本地交付）

- **模型列表字号**：修复设置页模型列表仍使用 16px 的遗漏；列表模型名和手动模型输入统一为 `15px`、`w300`，输入框底部模型名称/Effort 标准保持不变。
- **本次补修**：整条前台 AI 流程及解析/附件请求增加 120 秒超时；请求 ownership 继续隔离旧流程；发送三图从正方形改为一行 3:4 竖向卡片，并补充对应回归断言。
- **回归验证**：新增设置页模型列表和思考超时/三图比例 Widget 断言；全量 Flutter **1093/1093**；AI 请求/重试/Responses **36/36**；AI/UI/会话/图片/思考/来源/模型/菜单 **104/104**；Claude/Chats 视觉 **16/16**；Flutter analyze exit 0（43 条既有 info/warning）。
- **APK**：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.259.0-272.apk`，116,446,150 字节，SHA256 `D28375B51E697B432714EA5B937C5AA0596A42863952BA0FB2F7A24A37A2EEDD`；包名 `com.qingji.qingji.codex`，versionName `1.259.0`，versionCode `272`，16 KiB 对齐、APK V2、固定证书 gate 通过。
- **边界**：本机无在线 ADB；真实 ChatGPT OAuth/Token、官方模型目录、provider Responses、IME、系统文件选择器和真机字体观感仍需用户在可联网 Android 设备验收。源码未提交、未推送、未发布线上。

## 2026-08-26 v1.258.0+271 请求竞态与图片验收收口（Codex，本地交付）

- **请求可靠性**：修复 `AiRequestManager` 的请求 ownership 竞态；旧请求的 `finally`、延迟 Token、停止回调不会清理或消费同一任务的新请求，取消等待改为类型安全并观察底层 Future，避免首条/重试/连续发送互相污染。
- **图片验收**：截图测试改用真实书本封面图片并等待 `Image.file` 异步解码；发送消息中的三张图片真实可见，输入框草稿首屏保留三张并支持横向查看更多。
- **版本与交付**：版本 `1.258.0+271`，build tag `b0826-271`；全量 Flutter **1090/1090**，AI 请求/重试/Responses **36/36**，AI/UI/会话/图片/思考/来源/模型/菜单 **104/104**，Claude/Chats 视觉 **16/16**；analyze exit 0（40 条既有 info/warning）。
- **APK**：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.258.0-271.apk`，116,993,515 字节，SHA256 `BAB34815FD6CEF36FA6CD2008BEB9BE95B59CD5E8CCB29194926E9C326C73EB3`；包名 `com.qingji.qingji.codex`，versionName `1.258.0`，versionCode `271`，16 KiB 对齐、APK V2、固定证书 gate 通过。
- **边界**：本机无在线 ADB；真实 ChatGPT OAuth/Token、官方模型目录、provider Responses、IME、系统文件选择器和真机字体观感仍需用户在可联网 Android 设备验收。源码未提交、未推送、未发布线上。

## 2026-08-25 v1.255.0+268 本批十项 AI 体验收口（Codex，本地交付）

- **思考与回复**：加入“思考中/思考了 Xs”、可展开处理摘要和来源面板；回复操作栏、链接处理、结构化表格和横向滚动完成，短回复底部留白收紧并保留上拉回弹。
- **消息操作**：长按自己的消息显示灰色高亮、发送时间，支持复制、编辑、选择文本和震动反馈，不再提供重复发送。
- **输入与路由**：普通记账可选模型/Effort；首条消息等待 AI 配置就绪；主页非空输入直接走 AI 记账；聊天/记账图片走各自多模态流程。
- **Claude 风格**：喵助手加号、Add files、图片入口和服务商卡片边界统一，原有导入/导出能力保留在设置入口。
- **验证**：Flutter analyze exit 0（34 条既有 info）；串行全量 Flutter 测试 **1065/1065**；Gradle `assembleRelease` 成功；APK 包名、版本、16 KiB 对齐、APK V2 和固定 Codex 证书 gate 通过。
- **交付**：APK [`feimiao-codex-v1.255.0-268.apk`](C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.255.0-268.apk)，116,069,242 字节，SHA256 `F70BB00313FFBB5EF487C5A3959AEC7284FB2EC62F395608E9390F7B8982E091`；版本 `1.255.0+268`，build tag `b0825-268`。
- **运行态边界**：本机无在线 ADB 设备，未执行真机安装/冷启动及真实 provider/OAuth 网络验收；以上仍需用户在可联网 Android 设备安装后确认。

## 2026-08-25 v1.254.0+267 AI 首条消息与回复版式修复（Codex，本地交付）

- **首条消息**：启动快路径提前加载 AI 配置，发送前等待 Repository ready barrier，避免刚打开应用时第一条消息误走“未连接 AI”而第二条才成功。
- **回复布局**：短回复在内容区底部锚定，收紧回复与输入框之间的异常留白；Markdown 表格改为结构化渲染，支持表头、分隔线、列对齐和数字右对齐，长回复更接近常见 AI 应用排版。
- **回复操作**：普通回复与报告回复补齐分享、更多操作入口和统一操作图标。
- **验证**：Flutter analyze exit 0（33 条既有 info）；串行全量 Flutter 测试 **1065/1065**；Gradle `assembleRelease` 成功；归档 APK 的包名、版本、16 KiB 对齐、APK V2 和固定 Codex 证书 gate 通过。
- **交付**：APK [`feimiao-codex-v1.254.0-267.apk`](C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.254.0-267.apk)，115,856,118 字节，SHA256 `519174271F8AD13E730A08B38B654959E546F8781448151AAC9E3F73D10575FF`；版本 `1.254.0+267`，build tag `b0825-267`。
- **运行态边界**：本机无在线 ADB 设备，未执行真机安装/冷启动及真实 provider/OAuth 网络验收；以上仍需用户在可联网 Android 设备安装后确认。

## 2026-08-25 v1.253.0+266 OAuth/主页 GPT 记账与喵助手滚动修复（Codex，本地交付）

- **OAuth 稳定性**：401 时对 GPT access token 做一次共享强制刷新并重试；模型目录 401 自动刷新，目录网络超时/连接失败有限重试；授权回调成功后保留原生 localhost 监听短暂窗口，Chrome 重复回调继续返回成功页。
- **GPT 记账链路**：主页 AI 记账改用官方 Codex Responses `text.format=json_schema` 结构，避免 Chat Completions 的 `json_object` 被官方 Responses 拒绝；OAuth 登录后模型目录短暂不可用时仍保存 Token 和可用官方默认模型。
- **设置与喵助手**：OAuth Token、授权地址、基础地址、服务商名称和模型输入框统一为认证方式/上游格式同款半透明样式；喵助手历史底部空白改为小间距，滚动回弹限制在 88dp 内。
- **验证**：Flutter analyze exit 0（33 条既有 info）；串行全量 Flutter 测试 **1059/1059**；Gradle `assembleRelease` 成功；APK 包名、版本、16 KiB 对齐、APK V2 和固定 Codex 证书 gate 通过；本机当前无在线 ADB 设备，未冒充完成真机安装/真实 OAuth 验收。
- **交付**：APK [`feimiao-codex-v1.253.0-266.apk`](C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.253.0-266.apk)，115,511,398 字节，SHA256 `DB37C1B2E668938B4FB527906EDD4FD704F49AD6E3AC93A58BDF3F20A36D420E`；版本 `1.253.0+266`，build tag `b0825-266`。

## 2026-08-25 v1.252.0+265 Cockpit AI 账号 JSON 导入/导出（Codex，本地交付）

- **账号文件**：AI 账号设置新增 JSON 文件导入、剪贴板粘贴和 Cockpit 兼容导出；解析支持 Cockpit flat OAuth、多账号数组、OpenAI `auth.json`、Sub2API `accounts[].credentials` 及常见通用 API Key/OAuth 字段。
- **安全与冲突**：API Key、access token、refresh token、id token 只写入平台安全存储，普通 `ai_providers_json` 元数据不包含凭据；导入预览支持更新已有账号、新建副本、跳过，并可控制“同步加入 API 服务”。
- **官方模型**：OAuth 导入后若文件没有模型目录，会用导入 Token 尝试获取 GPT/Codex 官方模型；离线时仍保留可用的默认模型，后续可在账号页重新获取。
- **验证**：Flutter analyze exit 0（33 条既有 info）；全量 Flutter 测试 **1059/1059**；Gradle `assembleRelease` 成功；APK 包名、版本、16 KiB 对齐、APK V2 和固定 Codex 证书均通过；16037 ADB 模拟器安装/冷启动成功，未执行真实账号 OAuth/Token 网络验收。
- **交付**：APK [`feimiao-codex-v1.252.0-265.apk`](C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.252.0-265.apk)，115,511,398 字节，SHA256 `08E43A3816B6A8832CAC46DDF165A1B7D12F97BADE2AF124F710EE8C28528DD5`；版本 `1.252.0+265`，build tag `b0825-265`。

## 2026-08-25 v1.251.0+264 GPT OAuth 流程竞态彻底收口与本地 APK（Codex，本地交付）

- **竞态修复**：OAuth 流程增加 flow generation/ownership；启动、恢复、取消及 native 保活调用串行化。旧流程的延迟 Token 返回、`finally` 清理、停止请求、ready marker 或 callback 消费，都不能关闭或清理新流程的 1455/1457 监听。
- **Android 保活**：`MainActivity` 与隔离进程 `OAuthKeepAliveService` 的 start/stop/takeCallback 均携带并校验 flowId；旧流程不会消费新流程回调，也不会误停新前台服务。此前已验证的 PKCE/state、IPv4/IPv6 回环、Token 交换/刷新、GPT 模型目录和粘贴回调兜底保持不变。
- **验证**：OAuth 定向回归 **11/11**；全量 Flutter 测试 **1052/1052**；Flutter analyze exit 0（33 条既有 info）；Gradle `:app:assembleRelease` 成功；APK 身份、16 KiB zipalign、APK V2 和固定 Codex 证书均通过。
- **交付**：APK `[feimiao-codex-v1.251.0-264.apk](C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.251.0-264.apk)`（116,052,358 字节），SHA256 `002e92221345770ff61bbbdf3b0fd174681dd0b7a1a90d3e9ed26ea927c5f8ee`；包名 `com.qingji.qingji.codex` / versionName `1.251.0` / versionCode `264`。
- **运行态边界**：本机默认 ADB 5037 落在 Windows 保留端口段，已用 16037 启动 ADB；专用模拟器 QEMU 可启动但设备持续 `offline`，因此本包尚未完成安装/冷启动和新包设备级 OAuth 冒烟。真实 ChatGPT 账号登录、Token 交换、官方模型目录及 Responses 请求仍需用户在可联网设备安装后验收；OpenAI `unsupported_country_region` 属外部网络限制，不等同于回调失败。

## 2026-08-24 v1.249.0+262 GPT OAuth 保活超时收口与最终 APK（Codex，本地交付）

- **最终收口**：OAuth 前台保活服务在授权完成、取消、过期或恢复失败时停止；若用户关闭浏览器不返回，6 分钟自动退出，不留下永久通知。
- **验证**：串行全量 Flutter 测试 **1051/1051**；OAuth/账号设置定向测试 **12/12**；Flutter analyze exit 0（33 条既有 info）；Gradle release 构建、归档 APK release gate 和 Manifest 服务权限检查通过。
- **交付**：APK `[feimiao-codex-v1.249.0-262.apk](C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.249.0-262.apk)`（115,281,574 字节），SHA256 `9a928363851bafbe8f1031d1cfcf2c92edc609cf87039ff35cff59cc1531dcde`；包名 `com.qingji.qingji.codex` / versionName `1.249.0` / versionCode `262`。
- **运行态边界**：当前无 Android 真机/AVD，真实账号登录、Chrome 回调和冷启动安装仍需用户安装本包验证；源码未提交、未推送、未发布线上。

## 2026-08-24 v1.248.0+261 GPT OAuth localhost 回调保活修复（Codex，本地交付）

- **根因修复**：Android 打开外部 Chrome/Custom Tab 后，Flutter Activity 进入后台可能被系统回收，Dart 的 `localhost:1455/1457` 监听随进程消失，授权完成后浏览器因此出现 `ERR_CONNECTION_REFUSED`。
- **Android 保活**：新增短时 `OAuthKeepAliveService` 前台服务；OAuth 启动前保活，Token 交换、取消、过期或恢复失败后停止，确保浏览器跳转期间监听进程不被回收。
- **回调监听**：IPv4 改为包含回环的全接口监听（仍受 PKCE/state 保护），恢复健康探测同时尝试 IPv4/IPv6；1455 失败仍回退 1457，粘贴回调继续保留。
- **版本同步**：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart`、`android/local.properties` 同步为 `1.248.0+261` / `b0824-261`。
- **验证**：OAuth/账号设置定向测试 **12/12**；串行全量 Flutter 测试 **1051/1051**；Flutter analyze exit 0（33 条既有 info）；Gradle release 构建和 release gate 通过。
- **交付**：APK `[feimiao-codex-v1.248.0-261.apk](C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.248.0-261.apk)`（115,281,574 字节），SHA256 `d2b896e6e09a028192c4e96b875b56f163eb85eb127ce5c9a9c292fd919c77e2`；包名 `com.qingji.qingji.codex` / versionName `1.248.0` / versionCode `261`。
- **运行态边界**：当前无 Android 真机/AVD，未执行真实账号登录、Chrome 回调和冷启动安装验证；请安装本包后重点验证 GPT OAuth，源码未提交、未推送、未发布线上。

## 2026-08-24 v1.247.0+260 OAuth 官方模型登录修复与最终 APK（Codex，本地交付）

- **OAuth 回调稳定性**：GPT OAuth 优先监听 IPv4 `127.0.0.1`，1455 端口失败时自动切换 1457；恢复前台时先做健康检查，不强制关闭仍可用的监听，IPv6 继续作为补充回调地址。
- **官方模型链路**：授权后交换并刷新官方 ChatGPT/Codex Token，从 `chatgpt.com/backend-api/codex/models` 获取账号实际模型；请求走官方 `/codex/responses` 并携带 `ChatGPT-Account-Id`。
- **版本同步**：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart` 同步为 `1.247.0+260` / `b0824-260`。
- **验证**：Flutter analyze exit 0（33 条既有 info）；串行全量 Flutter 测试 **1051/1051**；release gate 校验包名、版本、16 KiB 对齐、APK V2 和固定证书均通过；Gradle `assembleRelease` 成功。
- **交付**：APK `[feimiao-codex-v1.247.0-260.apk](C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.247.0-260.apk)`（115,281,466 字节），SHA256 `9d7a95099f84bf76c61409e05c54ae8d3ffa92b6c95952f383ee4805ac8a53d1`；包名 `com.qingji.qingji.codex` / versionName `1.247.0` / versionCode `260`。
- **运行态边界**：`adb devices` 当前无连接 Android 真机，真实 OAuth 出口、官方模型网络、安装/冷启动、IME 和中文字体观感仍需用户安装后验收；源码未提交、未推送、未发布线上。

## 2026-08-24 v1.246.0+259 喵助手 Claude 风格面板干净重建（Codex，本地 APK）

- 参考图比例收口：Camera/近期图片卡统一为 94dp 方卡；首屏默认从系统相册读取近期图片并横向滑动，权限或媒体列表加载时使用同尺寸占位，无图片时才显示紧凑 Photos 兜底。
- 联网搜索开关归位到喵助手加号面板，供应商设置页不再展示；新增全局 Chats `Tool access`（Auto/Off）持久化，Off 会关闭账本上下文、报告工具和联网搜索工具。
- Tool access 说明拆成账本查询与统计、记账与分类、图片识别、联网搜索四类；新增整屏视觉和权限回归。
- **版本同步**：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart`、`android/local.properties` 已同步为 `1.246.0+259` / `b0824-259`。
- **验证**：干净构建后静态分析 exit 0（33 条既有 info）；Claude 加号/输入框定向视觉回归 **8/8**；此前同一源码全量 Flutter 测试 **1051/1051**；`git diff --check` 通过。
- **交付**：APK `C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.246.0-259.apk`（115,281,466 字节），SHA256 `4eda522926fab151ea47cfd0d7113b66ffd1b5269159a237bf90566429f603dc`；aapt、16 KiB zipalign、APK V2 固定证书和 release identity gate 通过。
- **运行态边界**：`adb devices` 当前没有连接 Android 设备，未执行真机安装/冷启动；真实相册权限、IME、OAuth/provider 网络和字体观感仍需安装此 APK 后验收。源码未提交、未推送、未发布线上。

## 2026-08-24 v1.244.0+257 喵助手 Claude 风格加号菜单与功能归位（Codex，本地交付候选）

- **聊天快捷提醒**：普通喵助手 Chats 不再显示主页「记一记」快捷提醒；主页 AI 记账建议保持不变。
- **输入与加号**：聊天输入正文使用 `w350`；加号保留 36px 触控区，图形缩小 20% 为 26.4px，改为 GPT 风格细圆角线条，并与模型/思考强度保持同一水平线。
- **Claude 风格加号菜单**：新增 `Add to Chat` 底部圆角面板，提供 Camera/Photos、Add files、Tool access、Web search；不显示 Add to project、Connectors，也不重复显示截图识别、导入账单、导出账单。
- **比例与弹层**：加号菜单改走全局 `showBlurSheet`，从底部上滑并模糊后面的聊天内容；截图按 390×844 整屏验收。照片入口改为紧凑小卡，面板左右留白、操作行和圆角收敛到 Claude 参考图比例。
- **功能归位**：选图/添加图片继续进入现有截图 OCR 记账链路；导入账单、导出账单继续保留在设置页；主页原有记账加号入口不变。
- **截图字体修复**：Windows 离屏截图按实机注册应用 Nunito、Noto Sans SC CJK fallback、`MaterialIcons` 和 `packages/cupertino_icons/CupertinoIcons`；输入框、模型/Effort、聊天正文、问候语和所有操作图标不再显示中文/图标方框。截图前重新挂载 Widget，避免字体缓存造成半成品截图。已人工检查 `outputs/ai_chat_input_alignment/`、`outputs/ai_chat_claude/`。
- **验证**：定向输入框/Claude UI 回归 **10/10**（golden 零差异），串行全量 Flutter 测试 **1049/1049**，静态分析 exit 0（33 条既有 info）。已生成并检查 `outputs/ai_chat_claude/ai_chat_add_sheet.png`。
- **版本同步**：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart`、`android/local.properties` 同步为 `1.244.0+257` / `b0824-257`。
- **交付**：APK `C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.244.0-257.apk`（114,936,226 字节），SHA256 `7cc057a84437acd4d9947234feb2130491fae2ee97029bde0af92e687f50950e`；aapt、16 KiB zipalign、APK V2 固定证书和 release identity gate `validated`。源码仍未提交、未推送、未发布线上。
- **后续源码收口**：本条之后的面板比例/模糊弹层调整已通过截图回归，但尚未递增版本或重建 APK，待用户确认视觉后出下一包。

## 2026-08-24 v1.243.0+256 喵助手输入框最终字号与底部控件对齐（Codex，本地交付候选）

- **输入框字号**：模型名称与当前思考强度（包括 `High`）统一为 `15px`；模型列表字号保持 `15px`。
- **输入框布局**：模型名称改为自然宽度排列，`High` 不再被 `Expanded` 推到最右侧；两者之间仅保留约一个空白符宽度（4dp）。
- **加号与基线**：无圆底加号的两条线由 `22px` 增至 `33px`（长度增加 50%）；加号、模型名称和思考强度统一垂直中心线，触控区域仍为 36px。
- **版本同步**：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart`、`android/local.properties` 同步为 `1.243.0+256` / `b0824-256`。
- **验证**：串行全量 Flutter 测试 **1048/1048**；静态分析 exit 0（28 条既有 info）；release gate **9/9**；Release 构建成功；aapt、16 KiB zipalign、APK V2 与固定证书等价门禁通过。真实 Android 真机/IME 和中文字体观感仍需用户安装验收。
- **交付**：APK `C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.243.0-256.apk`（114,902,818 字节），SHA256 `4db579d9f5315f98e0f14acdb0fe7c86d56685551d11e81d62bd8594cd2d468a`；源码仍未提交、未推送、未发布线上。

## 2026-08-24 v1.242.0+255 OAuth 网络路径与输入框字号修复（Codex，本地交付候选）

- **OAuth 网络路径**：Android GPT OAuth 使用 Chrome Custom Tabs，沿用系统 Chrome 的 Cookie、代理和出口网络；PKCE/state、1455/1457 localhost 回调、恢复重绑、Token 刷新、GPT 模型目录和粘贴回调兜底保持不变。
- **输入框布局**：全屏输入区移除多余 `Spacer`，模型名称不再被压缩到约 4px；输入框模型名称为 `19px`，`High/Low` 思考强度为 `16px`，模型列表为 `15px`；选中时才显示灰底，Effort 滑块不变。
- **验证**：analyze exit 0（28 条既有 info）；串行全量 Flutter 测试 **1048/1048**；release gate **9/9**；APK 身份门禁通过（包名、版本、16 KiB 对齐、APK V2、固定证书）。真实 Android OAuth、provider 网络和 IME 仍需用户安装后验收。
- **交付**：APK `C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.242.0-255.apk`（114,902,818 字节），SHA256 `2a7177a0e3cc26bd9cea048f79b01247983d2adedd5e14afaa9ea7be367c091e`；源码仍未提交、未推送、未发布线上。

## 2026-08-23 v1.241.0+254 OAuth 回调与聊天字号修复（Codex，本地交付候选）

- **聊天字重**：用户发送文字与 AI 回复正文默认可变字重调整为 `w350`（比上一版减少 w50）；标题和关键强调保持层级差异。
- **字号收口**：输入框底部当前模型名称为 `19px`；思考强度 `High/Low` 为 `17px`；模型选择列表（含兼容列表）为 `15px`。滑块、输入框正文和布局不变。
- **OAuth 回调**：Android GPT OAuth 改用应用内 WebView 打开授权页，增加 localhost 明文回调的最小网络安全配置，避免外部 Chrome 切后台后 Dart 回调监听被回收；PKCE/state、Token 交换/刷新、模型目录和粘贴地址兜底保持不变。
- **版本同步**：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart`、`android/local.properties` 同步为 `1.241.0+254` / `b0823-254`。
- **验证**：Flutter analyze exit 0（28 条既有 info）；OAuth/UI 定向回归 **21/21**；全量 Flutter 测试 **1048/1048**；release gate **9/9**；APK 验包通过（包名、版本、16 KiB 对齐、APK V2、固定证书）。
- **交付**：APK `C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.241.0-254.apk`（114,902,818 字节），SHA256 `665951676d33a6012582e875715b050cb4e7518881d3dad770801328213bbf5f`；源码仍未提交、未推送、未发布线上。

## 2026-08-23 v1.240.0+253 输入框模型与思考强度字号微调（Codex，本地交付候选）

- **输入框字号**：输入框底部当前模型名称从 17px 调整为 18px；`Low`/思考强度同步为 18px，保持同字号。
- **模型列表字号**：模型选择列表名称从 17px 调整为 16px；不改变模型列表布局、滑块或模型前缀规则。
- **版本同步**：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart`、`android/local.properties` 同步为 `1.240.0+253` / `b0823-253`。
- **验证**：静态分析 exit 0（27 条既有 info）；全量 Flutter 测试 **1047/1047** 通过；Release 验包通过（包名、版本、16 KiB 对齐、APK V2、固定证书）。
- **交付**：APK `C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.240.0-253.apk`（114,902,382 字节），SHA256 `bdbcf4b809185089aa3b87408df90ddfde3f1cb8cb0ac8245e04cc61399668a6`；源码仍未提交、未推送、未发布线上。

## 2026-08-23 v1.239.0+252 OAuth 回调稳定性与 Cockpit 风格授权页（Codex，本地交付候选）

- **localhost 回调**：OAuth 回调监听改为 IPv6 优先并补 IPv4，兼容 Android/Chrome 将 `localhost` 解析为 `::1` 或 `127.0.0.1`；应用从浏览器恢复时会按原注册端口重绑，端口释放有短重试，不改变已签发的 PKCE/state。
- **授权流程恢复**：OAuth 状态继续安全持久化；Activity 重建或恢复后，应用级 watcher 会接管待完成流程，自动换 Token、获取 GPT/Codex 模型并保存到对应服务商，不再依赖设置页实例必须存活。
- **授权成功页**：本地回调返回 Cockpit 同款紫色成功页，显示“✅ 授权成功 / 您可以关闭此窗口并返回应用”；Android 优先使用 Custom Tab 保持回调监听，平台不支持时回退系统浏览器，粘贴回调仍保留兜底。
- **稳定性**：全局 Toast 的关闭计时器改为可取消，页面销毁不再遗留 1.2 秒 pending timer。
- **验证**：OAuth 定向测试 **9/9**（含强制重绑、成功页和 Token 交换）；Flutter analyze exit 0（27 条既有 info）；固定并发全量 Flutter 测试 **1047/1047**。
- **交付**：版本 `1.239.0+252` / `b0823-252`；真实 OpenAI 授权、Android 浏览器和模型目录仍需用户真机安装后验收。

## 2026-08-23 v1.238.0+251 主页 AI 记账直达模型与输入字号修复（Codex，本地交付验收）

- **主页 AI 记账路由**：主页输入不再在请求前调用本地 `ChatIntent`/退款意图拦截；任何非空自然语言都会进入记账模型请求，继续使用 `forceRecord: true` 保证按记账结构解析。空文本、忙碌状态和隐私授权仍保留为必要门槛；没有 key、拒绝授权或请求失败时才落到离线单笔解析。全屏喵助手的闲聊、查账和知识问答分流不变。
- **输入框字号**：模型名称字号调整为 17px，思考强度文字同步为 17px，生产模型列表也统一为 17px；模型/Effort 默认无灰底、选中才显示灰底，滑块不改。
- **回归证据**：定向 AI/模型/喵助手测试 **37/37**，AI 账号页 **2/2**；截图 golden **14/14**（输入框、模型/Effort、Chats、账号页）；Flutter analyze exit 0（27 条既有 info）；固定并发全量 Flutter 测试 **1047/1047**。当前源码截图已检查；测试环境缺完整中文字体，中文观感保留真机验收项。
- **交付**：版本已递增到 `1.238.0+251` / `b0823-251`；APK `C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.238.0-251.apk`（114,771,310 字节），SHA256 `7fb41172c6b231193e2dc788228c85a7c55cddd0920c68c02a165bc68acb4957`；包名/版本、16 KiB 对齐、APK V2 固定证书和 release identity gate 已通过。

## 2026-08-23 普通问答提示词放开排版（Codex，本地定向验收）

- **普通问答**：移除喵助手查账/聊天提示词中的强制 Markdown 标题、列表、加粗、段落长度和短回复限制，让回答按问题自然展开。
- **性格**：将“口语化、简短亲切”调整为“口语化、亲切”；保留金额引用、分类范围和数据不足如实回答等账目准确性约束。
- **报告边界**：月报/周报/年报仍保留独立的文档结构模板，不受普通聊天提示词调整影响。
- **验证**：AI/账号/模型/喵助手定向测试 **55/55**、普通问答提示词回归 **1/1** 通过；全量 Flutter 测试 **1032/1032** 通过；`flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` exit 0，仅有既有 27 条 info。

## 2026-08-22 v1.236.0+249 喵助手/Chats/多服务商需求最终验收（Codex，本地交付候选）

- **输入框统一**：喵助手输入区与主页「记一记」统一尺寸、透明度、内边距和提醒文字；左下角加号去掉圆底并与模型/Effort 同组左移；发送按钮保持同一右边界。
- **模型与思考强度**：模型名和 Effort 默认不显示灰底，选中时才显示；字号统一加大，模型长名称按可用宽度完整缩放；两者外部间距固定 `4dp`，Effort 滑块保持原样；模型列表不显示服务商前缀。
- **Chats 与聊天**：搜索栏/关闭按钮统一 `38dp`，首次点击搜索会唤起输入法；会话卡使用灰色半透明底和 Claude 风格图标；会话及聊天正文恢复正常 `w400`，Chats 字号和字重按最终规格收口；筛选与长按菜单文字为 `w400`。
- **AI 账号与上下文**：多服务商、多 Key、启停开关、OAuth Token/API Key、Chat Completions/Responses/Anthropic Messages 上游格式、模型获取兼容回退、会话级 provider/model/Effort、查账上下文裁剪和分类纠正记忆均已落地。该历史条目当时的 OAuth 仍是过渡实现；随后版本已补齐 PKCE、state、localhost 回调、Token 刷新和 GPT 模型目录。
- **截图证据**：重新生成并检查 `outputs/ai_chat_input_alignment/`、`outputs/chats/chats_current.png`、`outputs/ai_account/ai_account_current.png`、`outputs/ai_chat_claude/`；定向 golden/UI 回归 **14/14** 通过。
- **验证**：`flutter test --no-pub --concurrency=1` **1023/1023** 通过；`flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` exit 0（25 条既有 info）；release 验包通过（包名、版本、16 KiB 对齐、APK V2 固定证书）；release identity gate `validated`。
- **Release APK**：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.236.0-249.apk`，`114,607,518` 字节；SHA256 `198577F0DED835DCA0170D0D0D0D0D441C7245E8BFBF817369C69D121D16D1D751`；sidecar 同目录保存。
- **运行态边界**：未提交、未推送、未发布线上；真实 provider 网络、Android 真机安装、IME 动画和系统中文字体观感仍待用户安装验收。

## 2026-08-21 v1.235.0+248 模型获取回退与模型/Effort 间距收口（Codex，本地验收完成，待用户安装）

- **模型获取**：模型目录请求在 `/v1/models` 超时、连接异常或非认证 HTTP 错误时继续尝试兼容的 `/models` 路径；401/403 仍明确提示认证错误。官方 Anthropic 端点使用原生请求头，自定义 Claude 中转继续使用 Bearer。
- **模型保留**：目录暂时为空或获取失败时，仍保留当前配置模型；用户明确删除的模型不会被自动复活。
- **输入区间距**：模型名称与思考强度外部间距固定为 `4dp`，标签内边距保留少量视觉空隙，避免黏连或出现不合理大空隙。
- **验证**：模型获取/AI provider 定向回归 **41/41**，喵助手输入区与 Claude 视觉回归 **8/8**；`flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` exit 0（24 条既有 info）；全量 Flutter 测试 **1012/1012**；aapt、16 KiB zipalign、APK V2 固定证书验包全部通过。
- **截图证据**：已检查 `outputs/ai_chat_input_alignment/assistant_fullscreen.png`、`outputs/ai_chat_input_alignment/ai_chat_input_alignment.png`、`outputs/ai_chat_claude/ai_chat_claude_models.png`、`outputs/ai_chat_claude/ai_chat_messages.png` 和 `outputs/chats/chats_current.png`；模型/Effort 间距、输入框透明卡、Chats 和聊天字阶均符合定向断言。
- **Release APK**：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.235.0-248.apk`，`114,239,919` 字节；SHA256 `0C0B317724ED1C87C9B805C62CE0D1DE5DFCD28E4D70B9137B3A8319A3E918E6`；包名/版本 `com.qingji.qingji.codex / 1.235.0 / 248`，16 KiB 对齐、APK V2 和固定 Codex 证书通过。

## 2026-08-21 v1.234.0+247 模型/Effort 间距微调（Codex，本地已验收，待用户安装）

- **模型与思考强度间距**：外部控件间距由 `8dp` 收窄为 `4dp`；两侧标签仍保留自身内边距，视觉上保持少量空隙但不再显得松散，也不影响点击区域。
- **回归验证**：喵助手输入区与 Claude 风格模型/Effort 定向测试 **8/8 通过**；`flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` exit 0，仅有既有 info。
- **Release APK**：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.234.0-247.apk`，`114,239,919` 字节，SHA256 `EBA7E6FC5D7F8CECFCFB3E8177D95129BF724078CE41A11C39E174C19236F99C`；包名/版本 `com.qingji.qingji.codex / 1.234.0 / 247`，16 KiB 对齐、APK V2 和固定 Codex 证书通过。
- **运行态边界**：未提交、未推送、未发布线上；真实 provider、Android 真机安装和 IME 动画仍待用户验收。

## 2026-08-21 v1.233.0+246 喵助手模型/Effort 间距与聊天字重修正（Codex，本地已验收，待用户安装）

- **输入区统一**：喵助手与主页「记一记」共用输入卡尺寸、透明度、内边距和提示字阶；加号为无圆底图标，并和模型/思考强度一起靠左下；发送按钮保持与主页相同右边界。
- **模型与思考强度**：两者固定保持 `8dp` 的小间距；模型名按可用宽度完整缩放；默认态不显示灰底，选中态才显示；输入区字号 `16px`，模型列表字号 `15px`；模型列表不拼接服务商前缀，思考强度滑块保持原样。
- **聊天字重**：用户发送内容、AI 回复、问候语和提示语恢复正常 `w400`，移除会造成过细渲染的 `wght=330/350` 可变字重；关键强调仍保留独立加粗样式。
- **Chats**：会话卡标题最终为 `13px / w400`，正文、提示和搜索交互继续沿用统一轻量字阶；搜索首次点击会正常唤起输入法，关闭按钮与搜索栏均为 `38dp`。
- **模型获取**：自定义 OpenAI 兼容中转即使模型名包含 Claude 也使用 Bearer；仅官方 Anthropic 端点使用原生 Claude 请求头，并支持 `/v1/models` 不可用时的 `/models` 回退。
- **截图证据**：`outputs/ai_chat_input_alignment/`、`outputs/chats/chats_current.png`、`outputs/ai_chat_claude/` 已重新生成并通过 golden 回归。
- **本地验收**：Flutter analyze exit 0（24 条既有 info）；喵助手/Chats/模型定向回归与 golden 截图均通过；全量 Flutter 测试仍有 1 个既有资产页信用卡“已还款”文案断言失败（`test/asset_management_view_test.dart:1204`，与本批无关）。
- **Release APK**：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.233.0-246.apk`，`114,239,919` 字节，SHA256 `846779AEAEF8ECA27106E19019DBAF757F91B8B29992256CBE6E7F8D449A39FA`；包名/版本 `com.qingji.qingji.codex / 1.233.0 / 246`，16 KiB 对齐、APK V2 和固定 Codex 证书通过。
- **运行态边界**：未提交、未推送、未发布线上；真实 provider、Android 真机安装、IME 动画和实际交互仍待用户安装验收。

## 2026-08-21 v1.230.0+243 喵助手输入区间距收口与完整回归（Codex，本地待用户安装验收）

- **输入区统一**：喵助手输入框与主页「记一记」统一尺寸、透明度、内边距和提示文字；加号去掉圆底，并与模型/Effort 控件一起左移。模型名称与思考强度之间保持 6dp 的紧凑间距，既不黏连也不产生大空隙。
- **模型/Effort 状态**：默认态不显示灰底，选中态才显示；输入区文字为 16px、模型列表文字为 15px，Effort 滑块保持不变。
- **Chats 字阶**：会话标题、聊天正文和相关辅助文字缩小一档，正文降为约 14.5px / w200，避免喵助手聊天内容过重。
- **验证**：`flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` exit 0（24 条既有 info）；Flutter 全量测试 **1008/1008** 通过；喵助手/输入区 golden 截图已更新并复验。
- **Release APK**：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.230.0-243.apk`，114,239,919 字节，SHA256 `E2AD24C3787F980FECFDA1FC9221633E3071D766EFB7F55D2069D0ADC6078AF3`；包名/版本 `com.qingji.qingji.codex / 1.230.0 / 243`，16 KiB 对齐、APK V2 和固定 Codex 证书通过。
- **运行态边界**：未提交、未推送、未发布线上；真实 provider、Android 真机安装、IME 动画和实际交互仍待用户安装验收。

## 2026-08-20 v1.228.0+241 Chats 会话与喵助手模型切换交付（Codex，本地待用户安装验收）

- **Chats 会话入口**：喵助手先进入会话选择页；唯一置顶且不可删除的「记一记」会话承接主页账单，普通聊天会话支持新增、搜索、全部/加星筛选、长按重命名/加星/删除。
- **会话级 AI 配置**：每个普通会话独立保存服务商、模型和 Effort；删除服务商模型后，引用它的会话在事务中回写到可用主模型，保留标题、星标和 Effort。报告任务同时冻结发起会话的模型配置。
- **主页边界**：主页 AI 入口强制只记账，闲聊、知识问答和查账在本地拦截，不写入主页历史也不调用模型；这些操作只在喵助手会话中生效。
- **Claude 风格交互**：Models 浮层固定 `195×224dp`，Effort 浮层固定 `222×102dp`；Effort 从 Low 起步，包含 Low/Medium/High/Extra/Max/Ultracode，模型行 hover/focus、序号、选中勾和 Ultracode 紫色轨道均由生产组件渲染。
- **本轮视觉收口**：筛选浮层锚定在右上角并把当前勾选放到左侧；会话卡使用主题半透明 `AppColors.card/selectedCard`、18dp 圆角、68dp 最小高度和 34dp 灰色聊天图标；搜索栏改为单层半透明表面；底部控件移除重复 SafeArea；跨服务商同名模型显示服务商前缀；Effort 当前值使用灰色文字。
- **截图证据**：暖色主题 golden 截图位于 `android-app/outputs/chats/chats_current.png`，已核对背景、半透明卡片、单层搜索栏和底部安全区布局。
- **请求链稳定性**：自定义服务商默认使用流式 `/v1/responses`；Responses SSE 会正确处理完成、停止、`[DONE]`、失败和不完整事件，不因空行提前结束。
- **验证**：同一 SDK 的 `dart analyze --format machine` exit 0（21 条既有 info/lint）；Chats 定向 Widget 测试 **4/4** 通过；全量 Flutter 测试本轮 **997/998**，唯一失败是与 Chats 无关的资产信用卡测试文案断言；本轮改动已包含在 release 编译中。
- **Release APK**：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.228.0-241.apk`，114,157,999 字节，SHA256 `C4F49FEFF5378E19D23D238F8746DEC55B84C310624B9354C40F66031C25F33E`；包名/版本 `com.qingji.qingji.codex / 1.228.0 / 241`，16 KiB 对齐、APK V2 和固定 Codex 证书通过。
- **运行态边界**：未提交、未推送、未发布线上；真实 provider 网络、Android 真机安装、IME 动画和实际交互仍由用户安装验收。

## 2026-08-19 v1.225.0+238 喵助手 Claude 风格模型/Effort 浮层对齐（Codex，本地待用户安装验收）

- **Models 浮层**：模型列表改为 Claude 桌面端同款紧凑白卡，固定宽 `195dp`、行高 `24dp`、右侧序号和选中勾；支持跨服务商模型列表，点选后立即持久化并影响下一条消息。
- **交互态**：模型行的鼠标悬停/键盘聚焦使用显式浅灰圆角背景，参考图中的 hover 行在桌面指针和 golden 截图中稳定可见。
- **Effort 浮层**：固定宽 `222dp`、高 `102dp`，标题、帮助标记、Faster/Smarter 标签和滑条留白按参考图对齐；保留 `Off → Minimal → Low → Medium → High → Extra → Max → Ultracode`，Ultracode 使用紫色颗粒高光轨道。
- **视觉回归**：新增 `test/ai_chat_claude_visual_test.dart`，锁定 Models `195×224` 和 Effort `222×102` 的布局断言，并保留三张 PNG golden 证据。
- **验证**：Claude 视觉验收 **2/2**、AI/喵助手相关回归 **180/180**、`flutter analyze --no-fatal-infos --no-fatal-warnings` exit 0（24 条既有 info）；未重复此前已通过的 970 项全量测试。
- **Release APK**：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.225.0-238.apk`，113,698,691 字节，SHA256 `E9E7E22C72E0D2309623F2E3CD8237F907EB115402676FF836B2D91F824BCB97`；包名/版本 `com.qingji.qingji.codex / 1.225.0 / 238`，16 KiB 对齐、APK V2 和固定 Codex 证书通过。
- **运行态边界**：未提交、未推送、未发布线上；真实 provider、Android 真机安装、IME 动画和实际交互仍由用户安装验收。

## 2026-08-19 v1.224.0+237 主页仅记账入口收口（Codex，本地待用户安装验收）

- **主页不再承接闲聊或查账**：主页 AI 面板启用强制 `recordOnly` 契约，发送前就在写历史和网络调用之前拦截闲聊、知识问答和账本查询；提示用户到全屏「喵助手」完成这些操作。
- **记账路径保持可用且更稳**：主页仍接受普通收支和可确定的历史退款；即使模型错误回传 query/chat，也会按记账路径处理。建议缓存按主页/喵助手模式隔离，主页不恢复报告任务或展示历史问答卡。
- **收入解析补齐**：支持“13号失业金到账2250”“社保补贴到账”等收入语句，能保留日期并归入补贴收入。
- **验证**：`flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` exit 0（25 条既有 info）；全量 Flutter 测试 **970/970** 通过。
- **Release APK**：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.224.0-237.apk`，113,682,307 字节，SHA256 `F84EB42B67F595351AE375426AFA9E8DF7742BB33DCAFB6C51441C09ECD9E4A9`；包名/版本 `com.qingji.qingji.codex / 1.224.0 / 237`，16 KiB 对齐、APK V2 和固定 Codex 证书通过。
- **运行态边界**：未提交、未推送、未发布线上；真实 provider、Android 真机输入法与实际交互仍由用户安装验收。

## 2026-08-16 v1.223.0+236 AI 兼容性审查收尾与全量验收（Codex，本地待用户安装验收）

- **AI 兼容性问题全部收口**：保留用户删除模型、跨服务商模型列表滚动与标识、透明输入框、服务商/模型安全回退、隐私授权只在接收方变化时重置、Claude 原生端点与 Effort 参数映射，以及闲聊/查账/记账三态分流修复。
- **补修本批验收中发现的 5 项失败**：资产页测试改为精确匹配净资产值标题；月度进度测试按真实月份标签校验；10k 性能基准改用仓库批量导入入口，避免逐笔副作用刷新污染读取性能指标。
- **验证**：`flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` 0 error；全量 Flutter 测试 **967/967**；定向 AI 回归仍全通过。
- **Release APK**：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.223.0-236.apk`，113,682,307 字节，SHA256 `856A3875C1E8FE405D73C1869038F393092868649C25DA04C35861868F9B9465`；包名/版本 `com.qingji.qingji.codex / 1.223.0 / 236`，16 KiB 对齐、APK V2 签名和固定 Codex 证书通过。
- **清理**：删除 build、`.dart_tool`、Flutter 依赖临时清单、Wrangler 本地账号缓存、旧 v1.221 APK 和旧 Playwright 页面快照；保留 v1.222 回退包、当前 v1.223 包、CI iOS 产物与 `android-app/outputs` 已登记视觉证据。
- **运行态边界**：真实服务商网络、Android 真机安装、IME 动画和截图仍待用户安装验收；本批未提交、未推送、未发布线上。

## 2026-08-14 项目治理与本地存储清理（Codex，仅文档/维护）

- 新增 `docs/PROJECT_MANAGEMENT.md` 项目管理总纲，统一当前看板、产品范围、文档权威层级、架构边界、需求状态流、DoR/DoD、验证矩阵、版本/分支/发布/回退、路线图、风险登记和磁盘保留规则；重写工程 README 与 docs 索引，并从 `CLAUDE_START_HERE.md` 建立入口。
- 清理可再生的 Flutter/Gradle 缓存、重复 APK 和运行日志；本地 APK 改为只保留 v1.214 当前候选与 v1.213 上一候选。标准 `git gc --prune=now` 后对象库为 1 pack、0 loose、0 garbage，`git fsck` 通过。
- 仓库由约 5.73 GiB 降至约 0.85 GiB，释放约 4.88 GiB；`.git` 从约 3.15 GiB 降至约 615 MiB。根 `.gitignore` 新增 APK/AAB、本地 release、浏览器证据和构建归档规则，防止再次膨胀。
- 本批未改业务行为，因此没有重跑 Flutter 测试或重建 APK；v1.214 原定向 42/42、静态分析 0 error 和验包证据保持不变。

## 2026-08-14 v1.214.0+227 AI 多服务商与喵助手模型切换（Codex，本地待安装验收）

- **多服务商账号**：AI 账号页改为可折叠服务商卡片，可新增/删除任意 OpenAI 兼容服务商；DeepSeek 固定为唯一不可删除的内置项。API Key 按服务商隔离安全保存，地址、名称和模型列表独立持久化，旧 DeepSeek/自定义配置自动兼容迁移。
- **模型获取与管理**：普通模型旁提供“获取模型”，按 `{baseUrl}/v1/models` 请求并携带 Bearer Key；管理弹层显示数量、支持删除、从上游刷新和保存。同名模型用服务商 ID 区分，密钥不会进入 provider JSON 或完整备份。
- **用途与请求链简化**：用途分配只保留普通记账；喵助手、报告和独立助手都使用输入框当前选择的服务商、模型与 Effort。模型点选立即生效并跨重启保持，删除当前服务商自动回退；切换服务商会重新确认隐私授权。
- **闲聊恢复**：输入先由本地 record/query/chat 三态分流，闲聊与知识问答直接使用聊天模型且不带账本上下文；明确记账才进入普通记账解析，避免双请求和误记账。
- **验证与产物**：本批定向测试 42/42、`flutter analyze` 0 error；遵照用户要求未重复既有 581 项全量测试。Release APK 113,928,115 字节，SHA256 `E81925A62DA5C0EC2E3BFB9D8E1A4C759713BA7DF3A829076C024CC3413B9B1A`；aapt=`com.qingji.qingji.codex / 227 / 1.214.0`，16 KiB ZIP 对齐、唯一 Codex V2 签名和固定证书均通过。归档 `ci-artifacts/releases/feimiao-codex-v1.214.0-227.apk`；不做模拟器/截图，由用户真机验收。

## 2026-07-18 v1.202.0+204 冷启动本月快照优先与后台收敛（Codex，本地已验包）

- **纠正 v203 的空首帧方案**：不再先画一个没有数据的主页再突然补入账单。启动第一阶段只读取首页必需的账本、当前账本、账户、分类、预算、显示偏好和**当月已持久化账单**；这些真实数据就绪后立即进入主页。
- **首帧后再完整收敛**：全历史账单、资产、报告、定时记账物化、折旧、净资产快照、周期备份和旧退款全库归并都移到第二阶段。完整 hydration 失败时，Widget、自动记账和后台报告不会误读半快照。
- **首帧降负与入口保护**：主题 JSON 改为首帧后异步读取并自动刷新；抽屉封面和可排序列表到首次打开才构建；初始化期不显示误导性的“首次使用”空态。手动/AI 记账、Widget deep link 和冷启动分享在完整数据就绪前排队，不用空账户或空分类打开。
- **回归与门禁**：启动/SQLite 专项 **5/5**，最终全量 Flutter 测试 **752/752**；`flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` 0 issue，格式检查通过；发布身份逻辑 9/9，发布 Bash 脚本语法通过。
- **产物**：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.202.0-204.apk`，120,826,320 字节，SHA256 `3C178D9A6EE37DE806B281BD031058AD60A355E690844099534BAC421C566CC3`。项目验包脚本确认 `com.qingji.qingji.codex / 204 / 1.202.0`、16 KiB ZIP 对齐、APK Signature Scheme v2 和固定 Codex 证书全部通过，源 APK、归档件与 sidecar 哈希一致。
- **运行态边界**：本轮未连接可用 Android 设备，未将编译/模拟测试误报为真机冷启动观感通过；由用户安装后复验“本月数据首屏即在、无空首页闪现”。未 commit、未 push、未发布线上。当前构建另有 `charset_converter/share_plus/workmanager_android` 的 Flutter 未来 KGP 兼容性警告，不影响本包，但升级 Flutter 前需更新这三个插件。

## 2026-07-18 v1.201.0+203 预算默认本周期与 AI 分类查账修复（Codex，本地已验包）

- **预算默认值**：新建预算表单默认选中「本周期生效」；「下周期生效」仍保留为用户主动选择，避免第一次设置后预算看起来没有生效。
- **AI 查账根因修复**：原逻辑只识别时间范围，未把问题中的分类词应用到本地合计；“这个月购物我花了多少”因此错误使用了全月总支出。新增本地分类范围解析，一级分类自动包含所有子分类，先筛选再计算净额并喂给模型；上下文明确锁定分类，其他分类不会混入金额或明细。
- **启动优先级修复（本轮）**：Android 12 启动主题显式使用透明 splash drawable，阻止系统把桌面图标放大叠在主页中央；数据库迁移/读取与 Widget 卡片渲染移到首帧之后，首页先绘制再由 Provider 补齐真实数据；未初始化时预算查询安全返回无预算状态。
- **回归**：新增购物含子类、子分类精确匹配、通用总支出不误筛选、首设预算默认值、Android 启动资源和“仓库未初始化也能绘制主页”测试；全量 Flutter 测试 **750/750**，`flutter analyze` 0 issue。
- **产物**：`C:\src\xunni-codex\android-app\build\app\outputs\flutter-apk\app-release.apk`，120,760,784 字节，SHA256 `ED30BF8EE989911ECAD194361E53FF184093ACDC55C988CE8E64BCC2A508E916`；aapt 确认 `com.qingji.qingji.codex / 203 / 1.201.0`，16 KiB zipalign、APK V2 签名和固定证书均通过。
- **运行态边界**：本机 `emulator-5554` 当前仍为 adb offline，未虚报模拟器/真机观感验证；请安装上述新 APK 后重点复测冷启动是否直接进入主页、中央是否不再出现大图标，以及“这个月购物我花了多少”和首次新建预算。

## 2026-07-18 v1.200.0+202 Android 冷启动白屏修复（Codex，本地已验包）

- **根因**：后台报告功能把 WorkManager、通知通道初始化与待处理报告恢复串行放在 `runApp()` 之前；这些非首帧任务延后了主页绘制，而 Android 启动窗口仍是 Flutter 模板纯白，因此原先短到不明显的白色窗口被明显暴露。
- **修复启动顺序**：数据库与主题偏好并行读取；后台报告调度严格延后到 Flutter 第一帧之后，失败也不再阻塞首页。首页所需数据库数据仍在首帧前完整加载，不以空数据或假主页换速度。
- **修复原生底色**：Android 12+ 与旧系统、浅色与深色模式的 LaunchTheme/NormalTheme 全部改为主页同系暖色或深色，移除模板 `@android:color/white`，即使极短冷启动窗口也不再闪纯白。
- **验证**：启动专项 2/2、全量 Flutter 测试 745/745、`flutter analyze` 0 issue；Release APK 资源编译通过，`aapt` 确认 `com.qingji.qingji.codex / 202 / 1.200.0`，16 KiB zipalign、APK Signature Scheme v2、唯一固定签名证书均通过。
- **产物**：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.200.0-202.apk`，120,743,924 字节，SHA256 `31D3E61766D21E599075718325E09CC662317B07B3A7744A12F7E89B4F91DFFC`。
- **运行态边界**：本机 `emulator-5554` 当前为 adb offline，未把模拟器启动观感误报为真机通过；需安装 202 包确认具体手机的冷启动过渡。

## 2026-07-18 v1.199.0+201 预算当前周期与下周期计划冲突修复（Codex，本地已验包）

- **修复预算死锁**：新建“本周期生效”预算时，如果账本已有尚未开始的下周期主计划，不再把未来计划误判为当前冲突；新计划自动截断到未来计划开始前一天，历史与下周期计划保持不变。
- **修复归档边界**：归档尚未生效的计划写入 `end_day = NULL`，不再生成早于 `anchor_start` 的非法区间；已归档周期仍保留历史覆盖，禁止同周期重复主计划，避免解析器产生双计划冲突。
- **验证**：预算定向 9/9、预算页面 11/11、全量 Flutter 测试 743/743、`flutter analyze` 0 issue；Release APK 通过 `aapt`、16 KiB `zipalign`、APK Signature Scheme v2 和固定证书指纹校验。
- **产物**：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.199.0-201.apk`，120,740,224 字节，SHA256 `BDAD7C125515C35BA493E8384EBCB58D7A0BDEDABC79A25CD91FF54755A3692D`。
- **未验证项**：本机 AVD 进程启动后 30 秒未注册 adb，未把模拟器 UI 冒烟误报为通过；请安装 APK 后重点验证预算“本周期生效”和下周期接续。

## 2026-07-14 v1.196.0+198 旧账时间降噪与时间精度地基（Codex，已提交、推送并上线，待安装验收）

- **不再成片显示 `00:00`（DB v40）**：`transactions` 新增 `time_precision`，区分来源明确时分、应用记账时钟、仅日期和旧数据未知。旧账统一迁移为 `legacy_unknown`，不改写任何 `date_ms`，不拿创建/更新时间伪造消费时间；日期分组卡隐藏不可靠午夜，独立卡只保留日期，真实明确午夜仍显示 `00:00`。
- **全入口与兼容链收口**：主页、搜索、账单、报销、喵助手普通卡与退款卡统一使用时间精度；手动/快捷/AI/通知、定时、普通导入、肥喵 CSV、退款报销和资产流水分别写入来源对应精度。旧聊天 JSON 与旧 CSV 缺字段时安全回退未知；CSV 为兼容旧格式继续输出固定 `yyyy-MM-dd HH:mm` 日期字段，并通过时间精度列避免把未知 `00:00` 解释成明确时分。
- **智能建议读取真实证据**：建议引擎不再只靠“值是不是午夜”猜时段。`exact` 可使用真实午夜，`entryClock` 降权，`dateOnly/legacyUnknown` 不作为时段证据；星期和周期证据仍可独立工作，缓存指纹同步纳入精度。
- **验证 / 产物与发布**：定向回归 192/192、最终全量测试 707/707；`flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` 0 issue，格式与 `git diff --check` 通过。Release build 成功；aapt=`com.qingji.qingji.codex` / 198 / 1.196.0，16K ZIP 对齐、唯一 Codex V2 签名和固定证书通过。APK 120,641,920 字节，SHA256 `69AE3CCDA9ADE11D470E444E519CEC01483F701B495199A11EE0C744C1EC9A7E`，源 APK、归档件和 sidecar 一致。未连接 Android 设备，按用户既定要求不做模拟器/真机安装或截图。本地功能提交 `1301e44`；为避开 31 个历史超限 APK，远端使用不含 `ci-artifacts` 与 Wrangler 缓存的单提交源码快照 `6703f8e`，已推到 `origin/codex/feimiao-p0-fixes`。Cloudflare 已发布 releaseId `v198-69ae3ccda9ad`；公网 `version.json`、KV manifest、5 分片逐片内容、拼接后 120,641,920 字节与 SHA256、以及公网 Range 206/长度/哈希响应头均通过验证。运行态仍待用户安装确认。

## 2026-07-14 v1.195.0+197 真机反馈修复（Codex，本地待安装验收）

- **账单时分不再写成午夜**：AI 只返回日期时合入本次提交的真实时分，明确时间（含真实 `00:00`）保持原样；本地自然语言解析支持“昨天下午 6:30 / 昨晚 8 点”。手动与快捷新建在保存时写真实时刻，两个编辑入口改日期时保留原时分；导入、自动记账和定时记账继续尊重各自来源，不套用提交时钟。
- **旧午夜数据边界**：已经落库的 `00:00` 缺少足够证据，未用更新时间、导入时间或今天批量伪造。新写入已修复；旧记录仍保持原值，后续若做数据修复必须基于可审计来源单独设计。
- **AI 建议重做**：删除“一级分类全历史中位数 + 随机抽两条 + 随机查账补满四条”的旧逻辑。新引擎只学习近 180 天的叶子分类与规范化备注/商户重复事件，按跨日频次、近期、真实时段、星期和周期确定性排序；旧 `00:00` 不作为时段证据。金额只有在至少 3 个跨日样本且落在 `max(0.5 元, 中位数 8%)` 稳定带内时才显示，否则只推荐事项。查询建议仅在真实预算或足量账单数据存在时出现，证据不足允许 0 条，不再随机制造噪音。
- **主页猫贴边**：实测两张探头猫素材在 96dp 高度下各有约 1.8dp 右透明边，定位补偿由 2dp 调到 4dp，使可见轮廓稳定跨过卡片描边约 2.2dp；未裁图或拉伸。新增 320px 明暗主题几何测试，锁定贴边且不越屏。
- **验证 / 产物**：版本 `1.195.0+197`、build tag `b0714-197`、DB v39。增量定向 49/49，AI 焦点与建议复验 27/27，版本同步后最终全量测试 691/691；`flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` 0 issue，本批文件格式与 `git diff --check` 通过。Release build 成功；aapt=`com.qingji.qingji.codex` / 197 / 1.195.0，16K ZIP 对齐、唯一 Codex V2 签名和固定证书通过。APK 120,641,920 字节，SHA256 `836E22D684F77CD8E4446227F0E8CEE54CD5DFD75D1BD07901CAEB58A65B3AB6`，源 APK、归档件和 sidecar 一致。未连接 Android 设备，按用户既定要求不做模拟器/真机安装或截图；未 commit、未 push、未发布，线上仍为 v195。

## 2026-07-14 v1.194.0+196 预算进度、账单显示与分类交互统一（Codex，本地待安装验收）

- **预算视觉恢复并统一**：确认灰色回归来自 `bf50e97` 将旧健康绿机械替换为 `scheme.primary`；恢复浅色健康绿 `#7FB069`（深色 `#9AC584`），新增共享 `BudgetProgressBar/BudgetProgressRing`，统一健康绿→临界铜金→超支橙。未完成轨道跟随当前进度末端色并带同色略深边缘；主页汇总卡改按真实内容高度布局，筛选条上下间距均为 8dp。
- **账单与喵助手显示统一**：新增全局“内容优先（默认）/分类优先”偏好和真实卡片预览；日期分组卡显示 `HH:mm · 次信息`，独立卡显示完整日期时分、账本和次信息。用户消息气泡默认跟随卡片透明度，可切固定灰底；偏好持久化到 `app_settings`，旧值或未知值安全回退默认。
- **喵助手进入稳定性**：历史区先完成最终滚动定位再显示，消除进入时上下闪动；补上恢复负责人被快速关闭时的接管逻辑，新面板会重新读取持久化历史，不再需要第三次打开才恢复。
- **手动记账与分类层级**：备注字段请求系统 `done` 动作并复用原“完成”保存链；无效金额保持焦点，成功保存时锁住自定义数字键盘，避免退出前先上再下。共享 `HierarchicalCategoryPicker` 已用于手动记账、定时记账、喵助手改分类和导入复核，一级原位展开二级，选中、箭头、背景柔化与恢复/主动收起行为一致。Android 键帽文字由具体输入法决定，App 保证 `done` 行为。
- **规范与版本**：UI 设计标准升至 v1.2，明确预算健康态是绿色唯一例外并登记共享预算进度组件。版本 `1.194.0+196`，build tag `b0714-196`，DB 保持 v39。
- **验证与产物**：`flutter analyze --no-pub` 0 issue；最终全量测试 664/664；Release build 成功。aapt=`com.qingji.qingji.codex` / 196 / 1.194.0 / 肥喵记账；16K ZIP 对齐、V2 签名、唯一签名者和固定 Codex 证书均通过。APK 120,609,152 字节，SHA256 `BFA815FB8A04CE89BE560B8D29B940DCD457100C7378B60ED324468B84AB0BCD`，源 APK、归档件和 sidecar 一致。
- **边界 / 回退**：按用户要求不做模拟器、真机安装或截图验收，由用户自行安装确认。v196 仅本地构建，未 commit、未 push、未发布；当前线上仍为 v195（releaseId `v195-3c502eb61f4e`）。v195、v194 与 v193 APK/sidecar 保留为回退基线，但不代表 DB v39 运行后可直接无损降级。

## 2026-07-14 v1.193.0+195 资产日期仓储不变量封板（Codex，本地待安装验收）

- **新购买日期成为硬约束**：仓储拒绝没有购买日期的“新购买，同时记账”，且在同一事务内让物品、购买支出、结算、创建事件和初始估值统一使用该日；失败不会留下半套资产或流水。
- **账单日期不可漂移**：账单来源物品始终回写原交易 canonical date，普通编辑不能改写或清空；启用自动折旧必须显式提供开始日期，不再把今天当默认值。
- **保修边界补齐**：账单加入、手工创建和普通编辑都拒绝早于购买日的保修日期；比较口径统一为自然日，原账单带时分时，同一天仍合法。账单加入表单的日期选择下限同步锁到原购买日。
- **回归与交付**：修正一条跨午夜失效的终态撤销测试时间基准；`flutter analyze --no-pub` 0 issue，资产专项 38/38、最终全量测试 645/645。`b0714-195` Release APK 120,592,516 字节，SHA256 `3C502EB61F4E372A1EB1787CC0E418AB19AAFD9EAAA7A4963CEB57E694F3BF4E`；aapt、16K ZIP 对齐、唯一 Codex V2 签名和源/发布副本哈希均通过。
- **边界 / 回退**：本包完整包含 v194 的资产 UI 重做；按用户要求不做模拟器、真机安装或截图验收，由用户自行安装确认。v195 已由 Claude 提交（`bf50e97`）并于 2026-07-14 发布上线（releaseId `v195-3c502eb61f4e`）；v194 与 v193 APK/sidecar 原样保留。

## 2026-07-13 v1.192.0+194 资产物品 UI 与购买日期纠错（Codex，本地待安装验收）

- **购买日期不再伪造**：手工补录和编辑都提供全局日期选择器，可录入历史购买日、补充或清空未知日期；“新购买，同时记账”使用同一购买日写物品、支出、创建事件和初始估值；从已有账单加入的日期由仓储强制继承原账单，调用方传入的冲突日期会被忽略。DB 继续为 v39，不做无法证明的自动日期迁移。
- **成本与状态语义修正**：新增可持久化 `manual_unknown`，购买价留空时日均花费和保值率诚实显示待补充，不再用当前估值冒充精确购置成本；手工补录和账单加入均可选择在用/闲置，unknown 不再误显示成闲置；毛额已分配完的订单不再出现在新增物品候选中，手工物品也不再显示无法完成的账单退货入口。
- **物品详情和列表重做**：详情从 90% 高半屏改为普通二级页，首屏按照片、日均持有花费、持有天数和估值组织；编辑、闲置、出售、退货、报废、丢失、赠送和归档收进右上菜单。网格把日均花费升为主指标，当前估值降为辅助，统一 `AppRadius`、`PressableScale` 和读屏摘要。
- **表单与凭证统一**：新增入口拆成“从最近账单加入 / 新购买同时记账 / 手工补录”三条明确路径；物品表单全量使用 `SheetHeader`、`AppLabeledField`、`SettingsGroup/Row`、`AppSwitch`、`SlidingSegment` 和 `showBlurSheet`，补齐照片、保修日期与净资产开关。估值和折旧可选择真实生效日期；发票/保修单改为文件选择并复制到受管 `asset_media/`，不再要求手输本机路径，照片支持移除和替换。
- **回归与交付**：`flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` 0 issue；资产定向 65/65、最终全量测试 641/641。Release APK 120,592,516 字节，SHA256 `C0208E5270788EE1A60F278354D29E6ACFE90D39425231535BCE79F34D36E845`；aapt、16K ZIP 对齐、唯一 Codex V2 签名和源/发布副本哈希均通过。
- **边界 / 回退**：按用户要求不做模拟器、真机安装或截图验收，由用户自行安装确认视觉与触控；v194 未上传、未提交。v193 APK 与 sidecar 原样保留为本批升级前回退基线，当前线上仍为 v185。

## 2026-07-13 v1.191.0+193 预算资产 V2.1 第五个双批：B3 专项追踪 + A4 物品增强（Codex，本地待安装验收）

- **B3 专项追踪（DB v39）**：专项按分类/标签范围做 OR 匹配，消费统一读取原单退款家族净额；多个重叠专项各自观察同一笔消费，不相加、不进入主预算或“今日可用”。新增创建、编辑、管理和归档；编辑通过“归档旧计划 + 新建活动计划”保留历史，knowledge cutoff 仍能解析当时有效的范围和额度。
- **B3 引用安全**：删除仍被专项历史引用的分类或标签会被阻止；分类合并会同步重写 `expense_scope_json` 并重载专项数据。归档只停止未来执行，历史 revision 和执行结果保持可审计。
- **A4 物品增强**：补齐保修/到期提醒、维护/配件/保险等追加持有成本、可选使用次数和快捷 `+1`、存钱目标关联，以及报废/丢失/赠送撤销。持有成本候选、展示和导出都使用当前退款家族净额；使用撤销事务化且每个目标最多一条，终态撤销只接受完整前态证据并绑定尚未撤销的最新创建事件。
- **JSON 与同版本兼容**：资产 JSON 升到 v6；存钱目标使用稳定 UUID/`updated_ms`，导入按 UUID→合法旧 ID→唯一名称解析，歧义保持 unresolved。交易关联严格校验并报告 unresolved/rejected；重复、跨物品、非零或时间倒置的 usage 撤销直接跳过，不回滚整批且重启前后一致。早期 `user_version=39` 中间态会在启动、恢复候选和恢复重开路径事务化自修复；修复前原子保留不覆盖的 `pre-v39-compat` 备份，partial usage 表可补列/重建，非法和重复 reversal 确定性清理后建立正确唯一索引。
- **版本与验证**：版本 `1.191.0+193`，build tag `b0713-193`，DB v39。`flutter analyze --no-pub` 0 issue；B3/A4 扩展回归 79/79、共享仓储 111/111、最终全量测试 635/635。Release APK 120,428,384 字节，SHA256 `3A2345620F91524CC83A644F8BCFF76B8BBC186DA981B1DAE6CEA41FFF1D6F16`；aapt、16K ZIP 对齐、唯一 Codex V2 签名及源/发布副本哈希全部通过。
- **运行态与后续边界**：按用户要求不做模拟器、真机安装或截图验收，由用户自行安装确认。当前线上仍为 v185，v193 尚未上传；v192 APK/sidecar 原样保留为升级前回退基线，但不代表运行 DB v39 后可直接无损降级。A3b verified-checkpoint 纠错流程（superseding/revoked）与 A5 负债单一真相源仍未完成，继续作为独立后续批次。

## 2026-07-13 v1.190.0+192 预算资产 V2.1 第四个双批：A3 余额校准 + B2 预算计划与固定承诺（Codex，本地待安装验收）

- **A3 绝对余额校准（DB v37）**：账户补齐 UUID、期初日期/质量和归档状态；余额校准写绝对 `target_balance` 锚点，不造普通收支、预算或现金流。锚点前补录会被吸收，锚点后流水继续累计；撤销通过审计反转回到前一有效锚点。同日事件按 sequence/id 稳定排序，unknown-date 转账按来源/目标账户双腿覆盖，避免校准后重复加减。
- **A3 可信核对与趋势**：账户归档只改变可见性，非零余额仍计入净资产；账户趋势只从可信起点开始。完整净资产核对冻结 header/items，覆盖不足时只能生成 partial，过期物品估值必须显式接受；后续记账、估值或范围修正不会静默改写旧证据。
- **B2 预算计划模型（DB v38）**：新增 `budget_plans`、revision、cycle override、fixed occurrence 和 change event。支持月度锚点与自然周计划；修改默认下一个完整周期生效，本周期调整保存绝对周期总额。V2 生效后旧预算仅保留历史证据，归档 V2 不会让开放式 legacy 预算在未来复活。
- **B2 固定承诺闭环**：固定模板按周期物化独立 occurrence，可匹配账单家族、跳过、重置和处理退款复核；实际支出与预留互斥，部分退款后差额继续预留，全额退款不会错误释放整笔额度。revision 重复保存会同步未处理 occurrence，恢复备份后立即物化当前/下一周期；未来周期浏览不混入今天的固定额度。
- **独立审查收口**：补齐 latest partial 核对与旧比较串线、过期估值确认、revision 二次编辑、override knowledge cutoff、退款撤销复核、unknown 转账双腿、真实 `v36→v38` 迁移，以及 320dp/大字号布局边界。统计 `calculationVersion` 保持 1，本批没有改变既定统计合同。
- **版本与验证**：版本 `1.190.0+192`，build tag `b0713-192`，DB v38。`flutter analyze --no-pub` 0 issue；最终全量测试 587/587。Release APK 119,756,044 字节，SHA256 `363A58B13DBAA732495D9C8BE7A247597ED3F6B84EFD08D361BC821499362B45`；aapt、16K zipalign、唯一 Codex V2 签名及源/发布副本哈希全部通过。
- **运行态边界**：按用户要求不做模拟器或截图验收，由用户自行安装验证。当前线上仍为 v185，v192 尚未上传；v191 已被本包完整取代。

## 2026-07-13 v1.189.0+191 预算资产 V2.1 第三个双批：A1 物品闭环 + A2 账户活动与可信净资产趋势（Codex，本地待安装验收）

- **A1 账单到物品的完整链路（DB v35）**：可从已有支出账单创建物品，不重复生成支出；一笔账单可按整数分拆给多件物品，混合订单只跟踪耐用品部分。物品页新增双列照片网格、搜索、分类/状态筛选，320dp 或 130% 字号自动降为单列；相机/相册媒体进入 App 受管目录并生成缩略图。
- **A1 退款、退货与出售守恒**：单物订单退款高置信自动分配，多物订单进入待确认并可从物品详情人工分配；已退货物品会阻止删除或重分关键退款，须先撤销退货。解除账单关联会反转退款审计并把当时净购置成本固化为手工成本。出售拆分成交价、费用和净到账，只有净到账进入账户流水，不重复生成普通收入/支出。
- **完整备份 package v2**：备份同时包含 SQLite、`receipts/` 和 `asset_media/`，逐文件 SHA256、文件集合全等和路径穿越校验；兼容 v1。恢复会重映射收据、照片、缩略图和发票路径，并以 DB/收据/资产媒体三个组件原子切换、独立回滚；失败 staging 和临时目录会清理，成功后的旧文件清理为 best-effort，不会反向破坏已恢复数据。
- **A2 账户活动与净资产估算趋势（DB v36）**：账户详情新增近期活动，退款、报销、转账双腿、出售和权益收回按真实到账账户投影并与账户币种口径一致。资产总览新增可信净资产估算趋势；旧快照迁移为 `legacy_unverified`，历史日期禁止用当前值伪造，`scopeVersion` 持久化并在净资产计入政策变化时断开趋势，`snapshot_date` 作为 civil day 真相。
- **发布审查收口**：定时记账即时生成、肥喵交易导入、删除账本及其数据后都会顺序刷新当天快照；legacy 外币账户保留查看但不再出现在记账选择器，写入边界拒绝 CNY 流水落入外币账户。账单分配来源物品的购买价锁定为 resolver 净购置成本；近期活动长金额在 320dp、130% 字体下稳定缩放且保留完整读屏语义。
- **版本与验证**：版本 `1.189.0+191`，build tag `b0713-191`，DB v36。`flutter analyze --no-pub` 0 issue；定向回归 112/112；最终全量测试 540/540。Release APK 118,920,116 字节，SHA256 `BB320F5F6FA725E41853F0D07722A4FA5498FEEC9C75FF25416482EAF3BE2556`；aapt、16K zipalign、唯一 Codex V2 签名及源/发布副本哈希全部通过。
- **运行态边界**：按用户要求不做模拟器或截图验收，由用户自行安装验证。当前线上仍为 v185，v191 尚未上传；v190 为上一份本地测试包。

## 2026-07-13 v1.188.0+190 预算资产 V2.1 第二个双批：A0 资产信任地基 + D0 真实结算时间（Codex，本地待安装验收）

- **A0 资产状态地基（DB v33）**：实物与权益拆分经济状态、使用状态、可见性和计入口径质量；归档/恢复只改变列表可见性，不再篡改持有状态、余额或净资产计入开关。旧归档权益按经济事件、收回台账和金额矩阵等价迁移，无法证明的条目进入待确认，迁移前后净资产逐分守恒。
- **A0 三视图与可信指标**：资产管理改为“总览 / 资金 / 物品”页内分段并使用全局跨账本数据，移除“本月收支净额”伪指标；新增持有天数、日均持有花费、保值率、估值记录，以及报废、丢失、赠送和归档/恢复闭环。一账多物或退款分配不确定时返回 partial/conflict，不重复套用整单金额。
- **D0 双日期与事件类型（DB v34）**：交易新增 `created_ms / settled_ms / settlement_quality / settlement_account_id / settlement_account_quality / event_type`。`date_ms` 继续代表消费与预算归属；真实到账日/账户用于现金流和余额。旧普通账单按 `legacy_assumed` 迁移；旧商家退款到账日保持 unknown、原账户仅作历史假定；旧报销日期和账户都保持 unknown，绝不使用更新时间、迁移日或今天补造证据。
- **逐结算事件账户投影**：账户余额从“原单 family 净额”切换为逐事件投影，退款、报销、转账双腿、资产出售和权益收回按真实到账账户移动；unknown 账户不回退原账户。账户列表、详情和净资产对 partial 明确显示“待确认/历史推定/按已知金额”，不再把不完整余额伪装成精确值。
- **退款/报销确认闭环**：手工账单、喵助手、AI 快捷记账和待报销四个入口统一要求真实到账日期与账户；旧 unknown 退款/报销可在退款记录中补确认并升级为 `user_confirmed`。普通编辑只改归属字段，不再覆盖或伪升级结算证据；周期记账的计划到账标为历史推定而非 exact。
- **导入导出与自动记账护栏**：肥喵 CSV 新增到账日期、日期质量、到账账户、账户质量和事件类型，旧格式继续兼容；旧“报销到账”恢复为 reimbursement 且账户保持 unknown。无法匹配或超额退款不再生成普通收入，复核页明确提示未导入；通知退款禁止按普通收入自动保存，混合批保存普通账单时不会顺带清除退款通知。
- **版本与验证**：版本 `1.188.0+190`，build tag `b0713-190`，DB v34。`flutter analyze` 0 issue；最终全量测试 491/491。Release APK 115,069,684 字节，SHA256 `EEA6A350085C9499996D4A43C6B9FC4DEF431ED56172D42FCCB5E1CB09544998`；aapt、16K zipalign、唯一 Codex V2 签名及源/发布副本哈希全部通过。
- **运行态边界**：按用户要求不做模拟器或截图验收，由用户自行安装验证。当前线上仍为 v185，v190 尚未上传；v189 为上一份本地测试包。

## 2026-07-13 v1.187.0+189 预算 V2.1 首个双批：统一统计合同与预算浏览（Codex，本地待安装验收）

- **C0 统计口径地基**：新增统一 `MetricQuery / MetricResult` 合同，查询显式携带半开日期窗口、账本范围、币种、业务日历时区、知识截止时间和计算版本；结果统一区分 `available / partial / unavailable / conflict`，不再用 `0` 或空值掩盖未知、冲突和部分可用。
- **消费与同期口径**：消费投影统一使用整数分计算，退款归回原消费期，普通收支分类与预算分类独立聚合；外币被排除时返回 partial。月、周、年、自定义及预算周期的同期比较改为等长窗口，并覆盖周起始日、跨月、月底和闰日边界。
- **B0 预算单一 resolver**：新增 `BudgetWindowResolver`，所有预算读取统一解析旧 `budget_periods`。旧循环预算继续按自然月生效，一次性期间按唯一 winner 覆盖而不与循环预算叠加；金额按日稳定分配到整数分，明确区分无预算、0 元预算、部分可用、计划冲突和非法旧数据。
- **历史真实性与兼容**：预算计划的创建时间参与 `knowledgeCutoff`，冻结回放不会看到截止时间之后才创建的计划；正常页面查看历史月份时，业务日期与当前知识截止时间保持分离。相邻周期通过真实计划查找，不凭空外推；开放式旧期间只能逐月回退并标记 partial。DB 保持 v32，没有改写用户现有预算记录。
- **B1 预算浏览页**：预算页统一为“本周期 / 月 / 周 / 自定义”四段浏览，支持日期前后导航并明确显示当前账本；一次性旧期间与自定义浏览分开表达。主卡和分类卡统一展示预算、已用、剩余、周期进度与按预算平均的日均参考，并为无预算、0 元预算、partial、conflict 提供独立状态。
- **全 App 预算读路径统一**：主页、快速记账、喵洞察、统计、月度报告、Widget、AI 查账和 AI 报告全部转接同一预算 resolver。发布审查额外修复历史预算窗口混入当前周期“今日可用”的错期问题，并新增回归测试。
- **首版边界**：本版的“今日可用/日均参考”只是预算均摊，不是扣除固定支出后的“安全可花”；固定支出预留仍明确为 unavailable，待后续 B2 实现。`businessCalendarTimezone` 已进入查询身份，严格跨时区迁移仍按 V2.1 分期渐进实施。
- 版本 `1.187.0+189`，build tag `b0713-189`，DB v32。APK：`ci-artifacts/releases/feimiao-codex-v1.187.0-189.apk`，114,904,780 字节，SHA256 `02FD3E3AD0942EC2024F3A987890E557B3675AA44F0AF5B2F58C6B62FB249A34`。
- 验证：`flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` 0 issue；C0/B0/B1 定向 70/70，AI 错期与预算页复验 18/18，最终全量测试 445/445；release build 成功；aapt 确认 `com.qingji.qingji.codex` / 189 / 1.187.0 / 肥喵记账；16K zipalign、单一 Codex V2 签名及源/发布副本哈希全部通过。
- **运行态边界**：按用户要求不做模拟器或截图验收，由用户自行安装验证。当前线上仍为 v185，v189 尚未上传；v188 已被本包完整取代，不再单独发布。

## 2026-07-13 统计口径标准 v1.1：当前 App 全量指标分类（仅文档，未改代码 / DB）

- `docs/claude/STATISTICS_CALCULATION_STANDARD.md` 从预算/资产为主的规则合同升级为全 App 指标注册表：四个业务域（收支、预算、账户、资产）+ 审计质量/工作流两个横切域，并按财务真值 `F-*`、派生分析 `D-*`、运营计数 `O-*` 分类。
- 全量登记主页、账单/搜索/分类下钻/待报销、预算、统计图表、Widget、月报/AI 报告与查账、账户/实物/权益/负债、存钱目标，以及导入导出、自动/定时记账、分类/标签/记忆/备份等当前消费者；每项写明现行公式、日期/时点、scope、计数单位和 `current_exact/partial/inconsistent/target_only`。
- 将同名不同算的现状写成明确 GAP：待报销原额、全退 family 笔数、当前月对完整上月、历史零月样本、未来交易提前入账、跨币种直加、资产全局/当前账本 scope 混用、负债 hybrid、假历史快照、AI 混合“笔”、Widget 双口径及运营“处理数≠新增数”。
- 反例矩阵从 59 项扩到 77 项；文档版本升为 1.1，因本轮未改变 App 算法，`calculation_version` 保持 1。Obsidian `记账app/肥喵记账统计口径标准.md` 继续作为逐字同步镜像。
- 本轮只维护统计规范、交接和笔记镜像，不修改 Flutter、数据库、应用版本号或 APK，因此不运行 Flutter analyze/test/build。

## 2026-07-12 预算 / 资产 V2.1 与统计口径标准（仅文档，未改代码 / DB）

- V2 竞品研究稿保留并标记为历史稿；新增锁定方案 `docs/claude/BUDGET_ASSET_UX_PLAN_V2_1_2026-07-12.md`，修正退款双日期与到账账户质量、绝对余额锚点、固定支出互斥预留、整周期预算修订、物品成本基数、归档与经济状态分离、权益归档迁移、computed snapshot / verified checkpoint、净资产互斥集合、存钱目标资金分配和共享隐私。
- 新增最高优先级合同 `docs/claude/STATISTICS_CALCULATION_STANDARD.md`：统一消费统计、账户现金流、预算和资产存量四条日期轴，覆盖金额精度、退款家族、笔数、同期窗口、多币种、未知值、历史重算、单一 resolver 和 59 项反例矩阵。
- Obsidian 新增 `记账app/肥喵记账统计口径标准.md`，并在 `肥喵记账App开发笔记.md` 建立双链；工程副本与笔记副本逐字节一致。
- 本轮仅维护方案和交接文档，未修改 Flutter 代码、数据库、版本号或 APK，因此不运行 Flutter analyze/test/build。

## 2026-07-12 v1.186.0+188 剩余六项收口：AI 退款、设置页与预算/资产方案（Codex，本地待安装验收）

- **AI 历史订单退款改为附着式退款**：喵助手与快速 AI 入口都会先用本地确定性规则匹配原支出；只有唯一强匹配且金额不超过剩余可退额时才调用 `refundTransaction`。缺金额、无匹配、歧义和超额全部停止写入并追问，不再生成独立退款收入；“本月退款多少”等查询不会误触发写入。退款金额解析会先剔除日期，避免把“7 月 3 日”里的 3 当成退款金额。成功后的聊天退款卡以 `role=refund` 持久化，重启后仍能恢复原订单、退款行和累计退款信息。
- **自动记账页**：接入当前六色主题背景，状态区改用标准 `SettingsGroup/SettingsRow`；删掉三段编号式说明，正文和底注统一为 `AppType.secondary/caption`，保留通知使用权、后台运行建议和“逐笔确认后入账”的清晰边界。
- **AI 设置页**：删除顶部重复“AI”分组名和四条入口下的冗余说明，标题统一标准 w500；账号与高级参数的 6 个输入框改为 `AppLabeledField + iosInputDecoration`，字段名常驻、说明左对齐，底注与非重点选项降为标准灰阶。
- **预算与资产只完成方案，不提前改结构**：新增 `docs/claude/BUDGET_ASSET_UX_PLAN_2026-07-12.md`。预算拆开“浏览维度（月/周/自定义）”和“计划周期（月/周/一次性专项）”，给出版本化计划、迁移、分期和验收；资产固定全局口径，规划总览/清单/四类详情/余额校准/生命周期及负债单一真相源。等待用户确认推荐决策后再进入结构代码与 DB 改造，当前 DB 仍为 v32。
- **抽屉真实前后对比图**：`outputs/drawer_before_after_v188.png` 使用用户原始真机截图与当前生产 `RootShell/AppTheme` 的真实右滑抽屉渲染并排合成，加载真实 logo、默认账本封面、中文和 Material 图标，没有制作理想化概念稿。尺寸 1664x1848，SHA256 `B34E7DF815EE7D4287B5FE5934232806B09BC84C63D7619B87567908DAA44555`。
- 版本 `1.186.0+188`，build tag `b0712-188`，DB v32。APK：`ci-artifacts/releases/feimiao-codex-v1.186.0-188.apk`，114,626,156 字节，SHA256 `0A0282847451BE7650E4C3C89CE56ED4D306FF3AC0B6C13613462814E93C1FF7`。
- 验证：`flutter analyze --no-pub` 0 issue；退款/UI 定向回归 111/111；最终全量测试 374/374；release build 成功；aapt 确认 `com.qingji.qingji.codex` / 188 / 1.186.0 / 肥喵记账；`zipalign -c -P 16 -v 4` 通过；`apksigner verify --print-certs` 确认 Codex V2 签名，证书 SHA256 `4e99c399d4d246bd9c6b08b1d641248bd0846e7ae650c3a766e30fa67483d507`；源 APK 与发布副本 SHA256 一致。
- **运行态边界**：按用户决定不做模拟器/真机截图验收，应用内视觉、通知设置跳转和真实 AI 退款措辞由用户安装后确认；抽屉对比图只作为用户明确要求的真实 UI 对比产物。当前线上仍为 v185，v188 尚未上传；v187 已被本包完整取代，不再单独发布。

## 2026-07-12 v1.185.0+187 UI 规范收口、主题可见度与 AI 输入性能（Codex，本地待安装验收）

- **主页与抽屉**：探头猫改为右边缘锚定的轻纵向呼吸，取消会造成离边的旋转/横摆；“今日可用”下移 8px 与收支金额对齐。抽屉导航统一 Lucide 风格线性图标，设置与新建账本分别改为 gear / square-pen，“更多”移除右侧箭头；主页打开时增加朝抽屉侧的定向阴影与发丝边界。
- **主题与备份**：简约白主题下预算横条和“今日可用”圆环底轨改为可见的中性灰，彩色主题仍保留透白轨道；6 张主题色卡在 320dp 窄屏保持单行；双滑杆收口为 iOS `CupertinoSlider`，轨道按色卡使用可见控制色，简约白回退主色蓝灰。删除“极简模式”入口和新配置写入，旧 `minimal=true` 偏好继续兼容为既有白色外观。本机备份页面只展示最新 3 份，迁移/升级保护文件不做破坏性删除。
- **表单规范**：新增 `AppLabeledField`，字段名常驻、hint 只承担示例；`SheetHeader` 统一 12px 等距边界、居中标题和右上操作胶囊，`SettingsGroup` 自定义行默认横向撑满。分类图标样式、公共分类选择器、定时记账分类入口统一标准头部；新建存钱目标改半屏表单并补齐目标名称/金额/日期常驻标签；导入导出按钮、说明文字、文案与导出范围滚动布局统一，修复自定义日期显示不全。预算页仅将“新建预算”移到右上角，预算模型没有在本版改造。
- **喵助手**：全屏背景接入 6 种主题；记账卡“改分类/删除”和卡外说明统一次要灰阶；回答操作栏改为 Claude 风格细线图标、固定 36px 热区和 tooltip。AI 输入法启动期间保持组件树稳定，仅关闭大范围及输入框 `BackdropFilter`，位置直接跟随系统 inset，避免重复补间；焦点保活与系统返回逻辑原样保留。
- **明确顺延到下一版**：AI 退款附着原单、自动记账页主题/文字、AI 设置页重排、预算展示方案、资产管理全流程方案、抽屉优化前后对比图。本版不包含未接通的 AI 退款草稿。
- 版本 `1.185.0+187`，build tag `b0712-187`，DB 仍为 v32。APK：`ci-artifacts/releases/feimiao-codex-v1.185.0-187.apk`，114,462,292 字节，SHA256：`8041C21299EFC1CA618ADC005D6272794BE90C6CEE77D74C0E54DCFC9699AE8E`。
- 验证：`flutter analyze --no-pub` 0 issue；AI 输入焦点回归 10/10；全量测试 364/364；release 构建成功；`aapt` 确认 `com.qingji.qingji.codex` / 187 / 1.185.0 / 肥喵记账；`zipalign` 通过；`apksigner` 确认唯一 Codex V2 签名，证书 SHA256 `4e99c399d4d246bd9c6b08b1d641248bd0846e7ae650c3a766e30fa67483d507`；源 APK 与发布副本 SHA256 一致。
- **运行态边界**：用户明确取消本轮模拟器截图验收，将自行安装 APK 验收；因此真机视觉、触控和输入法流畅度仍标记为“待用户安装验证”。当前线上仍为 v185，v186 被本包取代且不再单独发布，v187 尚未上传。

## 2026-07-11 v1.184.0+186 主页卡片小米合成修复（Codex，本地待 Claude 发布）

- **主页卡片合成除根**：真机截图取样确认暖色背景约 `#F4E2BA`，旧主页大卡片和账单日卡中心却约 `#CBC0AC`；40% 白色覆盖不可能主动压暗背景，根因是小米 GPU 对“半透明 Material Card + physical elevation/阴影层”的异常合成。主页 `HomeSummaryCard` 与 `TxDayCard` 已改用 `GlassSurface(blur: 0)`，保留主题动态白色卡底、透明度滑杆、渐变发丝边和账单交互，同时移除物理 elevation，且不新增常驻 `BackdropFilter`。
- **预算轨道透明化**：预算横向进度条和“今日可用”圆环底轨统一为半透明白，浅色 56%、深色 14%；主页卡片默认仍为白色 40% 不透明度，并继续跟随主题设置。
- **回归保护**：新增像素断言，要求玻璃卡片按白色 alpha 正确合成且 RGB 三通道均比暖色背景更亮；新增结构断言，禁止主页重新使用 elevated Material Card。
- 版本 `1.184.0+186`，build tag `b0711-186`，功能基线 commit `008998b`，出包 commit `6dde87c`。APK：`ci-artifacts/releases/feimiao-codex-v1.184.0-186.apk`，114,446,116 字节，SHA256：`C91C69ECE23E5E02CAE482B50D837286621785143B289C0F18C475172331D535`。
- 验证：`flutter analyze --no-pub` 0 issue；`flutter test --no-pub` 352/352；release 构建成功；`aapt` 确认 `com.qingji.qingji.codex` / 186 / 1.184.0 / 肥喵记账；`apksigner` 确认唯一 Codex V2 签名，证书 SHA256 `4e99c399d4d246bd9c6b08b1d641248bd0846e7ae650c3a766e30fa67483d507`。
- **运行态限制**：本机 Emulator 36.6.11 仍无法进入可安装 App 的 Android guest，本轮没有虚拟机安装截图，不能宣称运行态已验收；需用户在小米真机复测暖橙/简约白主题下的主页大卡片、账单日卡和预算轨道。
- **线上状态**：尚未上传，当前线上仍为 `1.183.0+185` / releaseId `v185-a42a2d3875b8`；由 Claude 使用发布脚本上传 v186 后，必须复核 `version.json` 的 64 位干净 SHA256、响应头和分片拼接哈希。

## 2026-07-11 v1.183.0+185 账单增量同步、导入/Widget 性能与后台报告（Codex，已由 Claude 发布）

- **常规账单写入不再全表重载**：交易 JOIN 查询收口为统一入口，新增 `_refreshTransactionRows` 按受影响 ID/退款家族回读；新增、编辑、改分类、退款和删除只更新相关内存行。账本切换与“计入总账本”改为复用全局缓存；批量导入在整批提交后仍只做一次有意的全量刷新。新增测试确认这些常规操作不会增加 full reload 计数。
- **大文件导入移出 UI isolate**：CSV/XLSX 表格解析、肥喵格式识别、日期金额转换及第三方账单标准化改用 `Isolate.run`；XLSX 字节通过 `TransferableTypedData` 传递，FilePicker 改为路径/流读取，避免平台结果额外持有整文件副本。
- **Widget 渲染减负**：Flutter 布局/绘制因引擎限制继续在根 isolate，图片读取改 raw RGBA，PNG 压缩由 `image` 库在后台 isolate 完成；总览卡与进度卡之间拆帧；快照指纹与最终渲染复用同一份 snapshot，不再重复聚合。
- **报告进程级后台生成**：引入 Android WorkManager、Flutter Secure Storage 和本地通知。报告使用唯一 job、联网约束、指数退避与 24 小时失败边界；旧原生安全存储 API Key 首次读取后迁移到可供 headless FlutterEngine 使用的加密存储，密钥不进入 SQLite 或 WorkManager input。报告正文、聊天卡和 job 完成状态在单一 SQLite 事务内提交，可安全重试且不重复生成。
- **恢复与失败边界**：喵助手每 1.6 秒同步持久 job 阶段，切回能继续看到思考状态和最终报告；调度失败回退现有前台生成。Worker 初始化失败不阻断 App 首屏，数据库未打开时返回 retry；任务已原子完成后即使内存刷新异常也不会被改回排队。完成后发“报告生成完成”通知。
- 版本 `1.183.0+185`，build tag `b0711-185`，功能与出包 commit `10c59e1`。APK：`ci-artifacts/releases/feimiao-codex-v1.183.0-185.apk`，114,446,116 字节，SHA256：`A42A2D3875B8619FDF362294B76AA40130D0C91C2A847A0291B322EB4E7DAE77`。
- 验证：`flutter analyze --no-pub` 0 issue；`flutter test --no-pub` 349/349；release 构建成功；`aapt` 确认 `com.qingji.qingji.codex` / 185 / 1.183.0 / 肥喵记账；`apksigner` 确认唯一 Codex V2 签名，证书 SHA256 `4e99c399d4d246bd9c6b08b1d641248bd0846e7ae650c3a766e30fa67483d507`。
- **运行态限制**：实际尝试 3 个 API 35 AVD、WHPX 无快照冷启动及纯软件模式；Emulator 36.6.11 均未进入可安装 App 的 Android guest（ADB offline/未注册，软件模式退出码 1）。因此本轮没有虚拟机安装截图，真机需复测 AI 键盘三查、报告杀进程续跑和通知、大文件导入响应及 Widget 连续刷新。
- **线上状态**：Claude 已于 2026-07-11 发布并逐分片验证，releaseId `v185-a42a2d3875b8`；`version.json` 返回 185、SHA256 干净，5 分片拼接哈希与源 APK 完全一致。v184 不再单独发布。

## 2026-07-11 v1.182.0+184 数据可靠性、报告恢复与主题修复（Codex，本地待发布）

- **主题视觉按用户图二定稿**：图二的半透明暖白卡片保持不变并作为基准；全局 `CardTheme.surfaceTintColor` 设为透明，消除主页 Material Card 在 elevation 下的二次染色；“简约白”页面底色恢复历史 `#F7F8FA`，卡片仍为白色 40% alpha。新增离屏像素测试，确认 Material Card 与普通半透明卡片中心色一致。
- **DB v32 与自动记账不漏单**：新增 `auto_record_occurrences`，通知用系统 notification key + postTime/队列 UUID 做精确幂等，删除会误吞真实同文同价消费的“60 秒文本去重”；队列改 peek + 精确 ack，只有用户保存或明确忽略才清除，失败/下滑关闭可重试。
- **报告任务可跨页面、跨重启恢复**：新增 `report_jobs` 持久表和进程内 `ReportJobRuntime`；切走再回来继续显示原始思考时长与阶段，完成/失败会清掉思考态；重新生成锁定报告原账本，更新原报告和聊天摘要，不创建重复报告；保存异常必释放任务锁。
- **统计口径统一**：统计页、Widget、AI 报告统一按一级分类稳定 ID 聚合，并共同复用退款索引；二级分类仍保留在明细，下钻会展开实际二级账单，环比不再只按同名文本碰运气。
- **查账与聊天竞态**：无日期 AI 查账改为全库关键词检索后再补最近账目，旧备注（如 `k12`）、账户和转入账户不再因最近 80 条截断而漏掉；聊天恢复按数据库行 ID + 写入中签名去重，清空操作带代次，避免恢复异步把旧消息插回或把刚发消息重复显示。
- **Widget 快照与更新器**：Widget 刷新改为单通道、数据代次失效、每代独立 PNG、原生保存成功后清理旧图，避免并发 `.tmp` 互抢和旧图覆盖；前台更新兜底支持 HTTP Range 续传、30 分钟总超时、响应头 SHA256，且会清理已安装/不同版本的陈旧 DownloadManager 任务。
- **CSV 与隐私**：肥喵 CSV 增加独立“转入账户”和“可报销”列，标签可往返；恢复时按名称找回或创建缺失账户/标签，不再把未知转入账户错误指向第一个账户。Android 明确 `allowBackup=false`，并用 `dataExtractionRules` 排除云备份和设备迁移中的数据库/偏好文件。
- **旧 SQLite 备份兜底**：优先 `VACUUM INTO`；旧设备语法不支持时使用 `wal_checkpoint(TRUNCATE)` + 独占锁复制 + WAL 竞态重试，最终仍执行 `quick_check`。
- 版本 `1.182.0+184`，build tag `b0711-184`。APK：`ci-artifacts/releases/feimiao-codex-v1.182.0-184.apk`，112,033,911 字节，SHA256：`4A10710413F2256E38C86DD33C2E58DBF9F1EEC19E14C24CC67C1223CD08EA8E`。
- 验证：`flutter analyze --no-pub` 0 issue；`flutter test --no-pub` 347/347；release 构建成功（Kotlin/Manifest/data extraction rules 均实际编译）；`aapt` 确认 `com.qingji.qingji.codex` / 184 / 1.182.0 / 肥喵记账；`apksigner` 确认唯一 Codex V2 签名。
- **运行态限制如实记录**：本机 Emulator 36.6.11 在 WHPX 与 `-accel off` 两种模式都冻结在 guest 启动前，ADB 始终 offline，故本轮没有虚拟机安装截图；不能写成已完成运行态截图验证，需用户真机或修复 AVD 环境后复测图二主题、AI 键盘和报告切页。
- **线上状态**：尚未上传。Codex 当前环境不直接改 Cloudflare 元数据，交 Claude 按发布脚本上传后复核 `version.json`、64 位 SHA256、分片拼接哈希。

## 2026-07-11 v1.181.0+183 大合批出包+发布（Claude）

- **主题外观系统**（用户拍板）：设置→显示→主题外观。6 张猫系色卡（暖橙默认/简约白/樱粉/薄荷/雾蓝/暮夜强制深色）+背景浓度/卡片透明度双滑杆+极简模式一键开关+实时预览。偏好存 JSON（theme_prefs.json），AppColors 动态化（applyTheme 唯一写入口），语义色永不开放。
- **UI 设计标准 v1**：`docs/claude/UI_DESIGN_STANDARD.md` 成文+AppType 字阶令牌落地；SettingsRow/SectionLabel 收口令牌（全 App 设置页自动获得 iOS 式层次）；AI 设置四子页整改；全库 8 处违规红→超支橙清零。
- **视觉调整**：卡片透明度 40%（用户二调）；设置弹窗补暖渐变背景；SlidingSegment 滑块半透明白；设置✕/抽屉齿轮全部收口 AppCircleButton 标准件。
- **GPT5.6 数据一致性批**（Claude 验收 330/330）：DB v31——定时记账单事务+recurring_occurrences 台账幂等；net_worth_snapshots 重建表 UNIQUE(scope_key,snapshot_date)；8+ 多表操作事务化；表单防重入。
- 版本 `1.181.0+183`，build tag `b0711-183`。APK：`ci-artifacts/releases/feimiao-codex-v1.181.0-183.apk`，111,902,175 字节，SHA256：`606EBA7269A6B3CB62C60F96E35E27C36A825F3A8202B99316B826BEFB600A09`。
- 验证：analyze 0 issue；330/330 全过（exit 0，含 GPT 新增 13 测试）；aapt versionCode=183；apksigner codex 签名；线上发布 releaseId `v183-606eba7269a6`，5 分片拼接哈希与源一致。
- 真机重点：升级时 DB v30→v31 迁移（有迁移前自动备份兜底）；主题页调色卡/滑杆；定时记账不再重复。

## 2026-07-11 Worker 分片边缘缓存（Claude，下载提速）

- 用户反馈修复后能下但比旧版慢。分析：迅雷把 106MB 切成几十段 Range 请求，每段都触发 Worker 从 KV 读整个 24MB 分片再切（KV 自带边缘缓存 TTL 仅 ~60s，靠不住）。
- 增加 Cache API 分片边缘缓存：首读回源 KV 后 `ctx.waitUntil(cache.put(...))` 写入边缘（按 releaseId 隔离、immutable、1 年 TTL），后续分段请求同节点直接命中；新增诊断端点 `/__chunkstat?release=..&i=..`（返回 colo+是否已缓存）和响应头 `x-feimiao-colo`。
- 部署版本 df29084e。验证：3 个 1MB 分段与源字节级一致；`__chunkstat` 确认 `cached:true`（LAX）。本机代理延迟大测不出吞吐差，等用户真机实测。
- 若真机仍明显慢于旧版：剩余瓶颈是 CF 节点到运营商的线路，下一步选项是迁 R2（原生 Range+更好吞吐）。

## 2026-07-11 Worker「总大小未知」除根：FixedLengthStream（Claude）

- 用户重试后速度 227KB/s→3.11MB/s（Range 修复生效），但仍显示「未知」。真根因：**Workers 对普通流式响应会忽略手写 content-length 一律 chunked**，与 gzip/no-transform/encodeBody 都无关；官方正解 = `new FixedLengthStream(length)` 声明定长流。
- 整包与 Range 两条路径都换 FixedLengthStream（版本 06945e4d）。验证：gzip 头整包 `Content-Length: 111524835` 正常返回（不再 chunked）；Range 206 带 content-length+content-range 且跨分片内容与源字节级一致。
- 教训：Workers 流式响应要带 content-length，必须 FixedLengthStream，手写 header 没用。

## 2026-07-11 Worker Range 分段修复部署（Claude，用户批准）

- 用户真机反馈：182 更新下载「46.22MB/未知」且龟速疑似卡死。诊断（curl 复现）：①客户端带 Accept-Encoding: gzip 时 CF 把流式响应转 chunked 吞掉 content-length →「总大小未知」；②MIUI 迅雷加速发多线程 Range 分段请求，旧 Worker 不认 Range 一律回 200 整包 → 加速器越加速越乱。
- 修复并部署（版本 ae374bfa）：①单段 Range（bytes=a-b/a-/-n）回 206+content-range，按 CHUNK_SIZE=24MiB 只取重叠 KV 分片切片流出；②accept-ranges: bytes + cache-control: no-transform + encodeBody: manual。
- 验证：头 100B/跨分片边界 200B/尾 100B 三种 Range 全部 206 且与源 APK 字节级一致；gzip 头下 Range 内容一致（无压缩污染）；整包 identity 请求 content-length 正常。已知残留：gzip 头的整包 GET 仍 chunked 无 CL（CF 出口行为，encodeBody manual 压不住）——但 DownloadManager 用 identity、迅雷走 Range，实际链路都有总大小。
- 用户端操作：取消卡住的旧下载重新点更新即可，无需发新 APK。

## 2026-07-10 设置页 ChatGPT 化九连改出包+发布（Claude，用户对照图二/图三逐条点名）/ 1.180.0+182

- ①设置从 push 全屏页改 **ChatGPT 式全屏弹窗**（showSettingsSheet：底部滑出 96% 高、圆顶角 28、右上角白圆 ✕、无「设置」标题）。②分组标题（管理/显示/小组件/关于）13.5/w500/onSurface 50% 中灰（原 12/w400 变体灰）。③行图标全换 Cupertino 系并改深色：AI=sparkles、备份=cloud_upload、金额=money_yen_circle、隐藏金额=eye_slash、更新=arrow_down_circle、关于=info_circle。④卡片透明度全局 cardAlpha 0.78/0.86→**0.52/0.62**（用户点名 52%，主页卡自动跟随），选中态 0.36/0.46。⑤版本号只留「检查更新」行。⑥AppSwitch 关闭态从"透明槽裸灰点"改回 iOS 经典**灰槽+白点**（两态同尺寸 40 宽），配套改 app_buttons_widget_test 断言。⑦删设置页底部"本地优先存储"宣传语。⑧分组卡圆角改**连续曲率**（ContinuousRectangleBorder 34≈视觉 22 超椭圆），settings_ui.SettingsGroup 同步。⑨抽屉齿轮对齐图三：白圆+深色齿轮+柔影（深色模式 #3A3633 底）。
- 本包同时带上未单独发布的 1.179.0+181 弹窗二轮精修（磨砂卡/发丝边/16w500 标题/中灰正文/灰底按钮）。
- **教训（写进流程）**：`flutter test | tail -1 && build` 的管道会吞测试退出码（tail 恒 0），本轮 AppSwitch 旧断言实际挂了但 build 照跑——以后测试一律落文件后查 `$?`，别接管道再 &&。
- 版本三处+local.properties 同步 `1.180.0+182`，build tag `b0710-182`。
- APK：`ci-artifacts/releases/feimiao-codex-v1.180.0-182.apk`，大小 111,524,835 字节，SHA256：`569B5149EFCC0863668BB5E375B3C4DB665F537825ECCAE2EC80BBFA733AA00D`。
- 验证：analyze 0 issue；317/317 全过（exit 0 亲验）；aapt versionCode=182；apksigner codex 签名。
- 线上发布：✅（用户拍板"推上线吧"）releaseId `v182-569b5149efcc`；version.json/sha256 干净；5 分片大小全对、拼接哈希与源 APK 完全一致。

## 2026-07-10 弹窗二轮精修出包（Claude，用户对照参考图逐条点名）/ 1.179.0+181

- 用户对照 Cloudflare 参考图指出 5 处不符，全部修正：①卡片半透明会透出底下文字→改**磨砂**（BackdropFilter σ26 + 白 82%/暖灰 84% tint，透色不透字）②补发丝细描边 ③标题 17/w600→16/w500 ④正文弃 M3 onSurfaceVariant（深灰紫看着像黑）→新 dialogBodyColor=onSurface 55% 中灰 ⑤按钮白底→明确灰底（浅色黑 7%/深色白 12%）+文字 w600→w500。
- 新全局零件（widgets/ios_dialogs.dart）：`FrostedDialogCard`（磨砂弹窗卡）+ `DialogPillButton`（灰底胶囊）+ `dialogBodyColor`。确认弹窗/表单弹窗(ios_form)/下载进度/截图识别中 四处全部换装；ios_form 的 _FormButton 删除。弹窗是瞬态浮层，此处 BackdropFilter 不违反常驻模糊性能铁律。
- 版本三处+local.properties 同步 `1.179.0+181`，build tag `b0710-181`。
- APK：`ci-artifacts/releases/feimiao-codex-v1.179.0-181.apk`，SHA256：`8FFFC9FCB9E2CB8E160C17972953EA0E9AB6752E53F6C555CD35417B52C04CA8`。
- 验证：analyze 0 issue；317/317 全过；aapt 确认 versionCode=181；apksigner 确认 codex 签名。
- 线上发布：未单独发布，内容并入 1.180.0+182 一起上线（见顶部）。

## 2026-07-10 应用内更新支持后台下载出包+发布（Claude）/ 1.178.0+180

- 用户反馈：更新中切后台就下载失败。根因=下载活在 App 进程里（Dart http 流式），国产 ROM 冻结后台进程掐网络，60s 空闲超时判失败并删半包。
- 下载改交系统 DownloadManager：切后台/锁屏/杀进程都继续，通知栏自带系统进度，断网自动续传。Kotlin 侧 `feimiao/update` 通道新增 startDownload/queryDownload/cancelDownload/pendingDownload/clearPendingDownload；挂起记录存 SharedPreferences（feimiao_update），落盘 getExternalFilesDir 的 Downloads；`update_file_paths.xml` 补 external-files-path 供 FileProvider 安装。
- Dart 侧 `app_update_flow` 重写：弹窗只是进度镜子（600ms 轮询系统状态），新增「后台下载」按钮关弹窗不停下载；下载完成时 App 在前台→自动校验+安装，在后台→不硬拉安装器（Android 拦后台起 Activity），下次打开走「新版本已下载好，现在安装？」分支，不重下。SHA256 校验链路原样（verifyFileSha256 流式哈希）。
- 兜底：DownloadManager 不可用（个别 ROM 禁用）时回退老的进程内下载。
- 版本三处+local.properties 同步 `1.178.0+180`，build tag `b0710-180`。
- APK：`ci-artifacts/releases/feimiao-codex-v1.178.0-180.apk`，大小 111,507,891 字节，SHA256：`66B213368D4484BB8E5F2ED56F3B142779991EF42B1F7D56B85136AB548A8235`。
- 验证：analyze 0 issue；317/317 全过；release 构建成功（含 Kotlin 新代码编译）；aapt 确认 versionCode=180；apksigner 确认 codex 签名。
- 线上发布：✅ releaseId `v180-66b213368d44`。version.json 返回 180 且 sha256 干净；因本机代理拉不动 106MB 长连接（curl 56 非线上问题），改用**逐分片校验**——5 个分片从 KV 拉回大小全对、拼接 SHA256 与源 APK 完全一致（比整包下载更严格）。
- 注意：装上 180 后的「下次更新」才开始享受后台下载；179→180 这次仍走老下载，请保持前台。

## 2026-07-10 全局弹窗统一图二风格出包（Claude）/ 1.177.0+179

- 用户对照 iOS Cloudflare 客户端截图（图二）点名：更新弹窗不是那个风格。排查发现 1.161.0 视觉升级把参考图做成了「标题居中+实心色确认键」，与原图不符；本轮全局对齐。
- `widgets/ios_dialogs.dart` 确认弹窗重写：标题/正文**左对齐**；两颗**同浅底**（inputFill）等宽胶囊，强调靠文字颜色——普通=主色蓝灰 w600、危险=超支橙 w600（守不用红铁律）。全 App showConfirmDialog 调用点（各类删除确认、更新提示、AI 隐私弹窗）自动升级。
- `widgets/ios_form.dart` 表单弹窗按钮：文字从深灰改主色，与确认弹窗同观感（结构原本已是左对齐+双浅胶囊，不动）。
- `views/settings/app_update_flow.dart` 下载进度弹窗：标题/说明/百分比改左对齐。
- 消灭全部残留裸 Material AlertDialog（3 处）：`tag_selector` 新建标签→showIosFormDialog+iosInputDecoration；`edit_transaction_sheet` 删除确认→showConfirmDialog(destructive)（顺手消灭一处违反配色铁律的红字）；`screenshot_entry` 识别中弹窗→统一圆角卡+主色 spinner。全库 grep AlertDialog 仅剩注释。
- 不动范围：收据全屏查看器（黑底图片查看）、iOS 菜单、底部弹层（另一套规范）。
- 本包同时带上 178 之后补的「小组件快照指纹跳渲」。
- 版本三处+local.properties 同步 `1.177.0+179`，build tag `b0710-179`。
- APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.177.0-179.apk`，大小 111,425,943 字节，SHA256：`23CF92A491B252F2B787A4E3E3DC0029BEEAA6EC2819B8653FC96226F11D86A4`。
- 验证：analyze 0 issue；317/317 测试全过；release 构建成功；aapt 确认 `versionCode=179/versionName=1.177.0`；apksigner 确认 codex 签名。
- 线上发布：✅ 已由 Claude 发布并全量验证（releaseId `v179-23cf92a491b2`，下载哈希与源一致；用户 WSL 自跑失败后确认由 Claude 执行）。

## 2026-07-10 v1.176.0+178 线上发布（Claude，用户拍板）

- `bash ci/publish_update.sh` 发布 178 到 Cloudflare KV，releaseId `v178-61752a7c6383`（干净无反斜杠，脚本 stdin 修复后首次发布验证通过）。
- 验证四连：version.json 返回 178；`sha256` 干净 64 位 hex；响应头 `x-feimiao-sha256` 一致；全量下载 111,442,327 字节，sha256 与源 APK 完全相同。
- v177 时代的污染元数据至此整体翻篇；真机待验：从 v176/v177 应用内更新到 v178 不再「安装包校验失败」。

## 2026-07-10 小组件快照指纹跳渲（Claude 验收补漏，未出包）

- Claude 逐项验收 1.176.0+178 的修复清单，7/8 确认到位；唯一漏项是「小组件快照数据未变时跳过重渲」——`widget_snapshot_service.dart` 此前零改动，本轮补上。
- `WidgetSnapshotService.refreshNow()` 先把快照 JSON（剔除每次必变的 `generatedAtMs`）做指纹，与上次一致就整体跳过：不再每次 repo notifyListeners 后都离屏渲两张 PNG + 写盘。渲染+落盘成功才记指纹，失败下次重试。
- 另：v177 线上元数据污染其实已由 Claude 在 GPT 动工前直接改写 KV 修复（curl 验证 sha256/响应头干净），178 一节里"需重发元数据"的说法过时，START_HERE §4 已更正。
- 验证：`flutter analyze --no-pub` 通过；`flutter test --no-pub` 317/317 通过。**此改动不在 178 APK 里**，随下次出包生效。

## 2026-07-10 Claude 发现问题复核修复出包（Codex）/ 1.176.0+178

- 修复应用内更新 v177 元数据污染导致的校验失败：`AppUpdateInfo.sanitizeSha256()` 会清理 sha256 前缀反斜杠并严格校验 64 位 hex；下载时如果 `version.json.sha256` 缺失或格式脏，会回退读取 Worker 响应头 `x-feimiao-sha256`，避免用户下满整包后必定“安装包校验失败”。
- 复核发布脚本：`ci/publish_update.sh` 已使用 `sha256sum < "$APK"`，避免 Windows 路径触发 coreutils 的反斜杠转义前缀；说明：线上 v177 的 `releaseId/url` 仍带旧反斜杠污染，需要 Claude/token 环境重发干净元数据或直接发布 v178。
- 修复深色模式主页状态栏不可见：主页 `AppBar.systemOverlayStyle` 按主题亮暗切换，深色主题使用浅色状态栏/导航栏图标；全局深色 `AppBarTheme` 同步显式设置浅色系统图标。
- 优化账本核心净额计算：新增 `LedgerPolicy.refundTotals()`、`netAmountWith()`、`userAmountWith()`、`toUserRecordWith()`，Repository 缓存退款索引、可见账单和 `allRecords`，把附着式退款相关统计从循环内全表扫描降为一次建索引后 O(1) 查询。
- 增加 transactions 查询索引：`book_id/date_ms`、`refund_of`、`book_id/refund_of`、`book_id/category_id/date_ms`、`book_id/account_id/date_ms`，不升级数据库版本，使用 `CREATE INDEX IF NOT EXISTS` 在打开、创建和升级后幂等确保。
- 同步替换搜索页、月报、喵洞察、导出、账单日列表等旧净额调用，避免重新引入逐笔 O(n²) 计算；移除主页 body 顶部重复实时模糊层，保留 AppBar 虚化，减少滚动时双层 BackdropFilter。
- 新增 `test/app_update_test.dart` 覆盖 clean sha、反斜杠污染 sha、非法 sha 和 `fromJson` 清洗。
- 版本同步递增到 `1.176.0+178`，build tag `b0710-178`；同步文件：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart`、`android/local.properties`。
- APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.176.0-178.apk`，大小 111,442,327 字节，SHA256：`61752A7C638379D6FD39F52BBBF059C459B7CE77B956A655A90FA39629BB7630`。
- 验证：`flutter analyze --no-pub` 通过；`flutter test --no-pub` 317/317 通过；`flutter build apk --release --no-pub` 成功；`aapt dump badging` 确认包名 `com.qingji.qingji.codex`、`versionCode=178`、`versionName=1.176.0`、应用名 `肥喵记账`；`apksigner verify --print-certs` 确认证书 `CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`。
- 线上上传：本节完成时 Codex 环境无 token 未上传；后续已由 Claude 发布（见顶部「v1.176.0+178 线上发布」一节）。
## 2026-07-10 Claude 接手文档整理（Codex）

- 新增 `docs/claude/CLAUDE_START_HERE.md`，作为 Claude 新会话第一入口，写清最新 APK、SHA256、commit、线上上传状态和阅读顺序。
- 重写 `docs/claude/CLAUDE_HANDOFF_CURRENT.md` 为当前状态版，移除旧的 `1.155.0+157` 当前状态、过期任务和占位符混杂问题。
- `docs/claude/TASKS_FOR_CODEX.md` 顶部增加历史任务书提醒：只有用户明确点名时才执行，不再作为默认开工清单。
- 修复 `CHANGELOG_CODEX.md` 顶部 APK/SHA 占位符和由转义导致的控制字符，补入 `1.175.0+177` 与 `1.174.0+176` 的真实 APK 路径和 SHA256。
- 本轮只整理文档，不改业务代码、不构建 APK。整理时发现 git status 中存在旧 release APK 产物删除状态；这些不是本轮文档整理内容，后续不要和功能提交混在一起。
## 2026-07-10 全局卡片透明度 + 首页顶部暖色修复出包（Codex） / 1.175.0+177

- 按用户参考图三，将全局卡片从纯白改为半透明白，覆盖 AppColors.card() 调用的主页大卡片、账单卡、统计卡、设置卡、资产卡等。
- 当前透明度参数：浅色普通卡片 cardAlphaLight = 0.78；深色普通卡片 cardAlphaDark = 0.86；浅色选中态 selectedCardAlphaLight = 0.52；深色选中态 selectedCardAlphaDark = 0.62。
- 新增 AppColors.selectedCard()，抽屉账本选中行和无封面账本占位底色改走该参数，避免账本选中块继续是实心灰。
- 修复主页顶部状态栏/顶栏被洗成白色的问题：_TopFrostedFade 不再使用灰白 AppColors.appBg() 做 tint，改用 AppColors.topFrostTint()，浅色为暖背景顶部色 #FAE0B0，保持图二那种暖色顶部。
- 版本同步递增到 1.175.0+177，build tag b0710-177；同步文件：pubspec.yaml、lib/core/app_version.dart、lib/build_info.dart、android/local.properties。
- APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.175.0-177.apk`，大小 111,425,943 字节，SHA256：`27664317590107FF6BBF538F6189612D951B5B899BE264D1539D238A0CEF6D0F`。
- 验证：flutter analyze --no-pub 通过；flutter test --no-pub 通过，313/313；flutter build apk --release --no-pub 成功；aapt dump badging 确认包名 com.qingji.qingji.codex、versionCode=177、versionName=1.175.0、应用名 肥喵记账；apksigner verify --print-certs 确认证书仍为 CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN。
## 2026-07-10 在线更新安全链路修复出包（Codex） / 1.174.0+176

- 基于上一节“在线更新安全链路 + 报告库一致性修复”出正式 release APK，版本同步递增到 1.174.0+176，build tag b0710-176；同步文件：pubspec.yaml、lib/core/app_version.dart、lib/build_info.dart、android/local.properties。
- APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.174.0-176.apk`，大小 111,425,943 字节，SHA256：`F68930BC23F17A3D47597907C81D0CA186CB61CEC38F36EB0A545D41FFB9E57F`。
- 验证：flutter analyze --no-pub 通过；flutter test --no-pub 通过，313/313；flutter build apk --release --no-pub 成功；aapt dump badging 确认包名 com.qingji.qingji.codex、versionCode=176、versionName=1.174.0、应用名 肥喵记账；apksigner verify --print-certs 确认证书仍为 CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN。
- 在线更新上传：已按标准调用 ci/publish_update.sh，但当前非交互环境没有 CLOUDFLARE_API_TOKEN，Wrangler 拒绝写 Cloudflare KV；因此本轮 APK 已本地出包并校验，在线上传待补 token 后重跑。
- 补 token 后重跑命令：bash ci/publish_update.sh "C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.174.0-176.apk" "1.174.0" "176" "修复在线更新安全链路与报告库一致性：更新包增加 SHA256 校验和下载超时保护；发布过程改为原子切换；报告重新生成使用报告 AI 配置；删除报告会同步清理喵助手报告卡片引用。"。
## 2026-07-10 在线更新安全链路 + 报告库一致性修复（Codex）

- 修复在线更新发布链路非原子问题：`ci/publish_update.sh` 现在先按 `releaseId` 上传 `apk:<releaseId>:chunk` 和 `apk:<releaseId>:manifest`，最后才切换 `version.json`；下载地址带 `?release=`，避免用户在发布中途拿到半新半旧 APK。
- 修复 `version.json` 更新说明 JSON 转义问题：发布脚本改用 Node `JSON.stringify` 生成清单，更新说明包含引号、换行、中文都不会写坏 JSON。
- 修复 App 下载更新包缺少完整性校验：`AppUpdateInfo` 新增 `sha256/releaseId`，下载时边写文件边计算 SHA256，优先校验 `version.json.sha256`，旧元数据缺失时可回退 Worker 响应头 `x-feimiao-sha256`。
- 修复下载弹窗可能永久卡住：下载请求增加 30s 首包超时、60s 流空闲超时、10min 总体超时；失败或校验失败会删除半包 APK，不再留下坏安装包。
- 修复报告库重新生成走错 AI 配置：报告重新生成现在使用 `aiProviderConfigFor(AiTaskType.report)`，不再误用普通记账/默认 AI 配置。
- 修复删除报告后喵助手残留报告卡片引用：`deleteReport` 改成事务删除 reports，并清理 `chat_messages.role='report'` 中指向该 `reportId` 的卡片；新增回归测试，确保不误删普通助手消息。
- 验证：`dart format` 已执行；`flutter analyze --no-pub` 通过；`flutter test --no-pub` 通过，313/313；`bash -n ci/publish_update.sh` 通过；`node --check ci/update-worker/src/index.js` 通过。
- 说明：本轮是修复与验证，没有单独递增版本出 APK；当前工作树里已有 Claude/前序改动把版本标到 `1.173.0+175 / b0710-175`，后续正式出包时继续按三处版本同步规则处理。

## 2026-07-10 分类图标顶部高光统一（Codex） / 1.167.0+169
- 根据用户反馈“前面生成的 20 个图标上部分有高光，后来的图标没有”，统一补齐三套分类图标资源的顶部半透明白色高光。
- 本轮只补背景高光层，不改图标主体语义、不改分类颜色、不改图标风格切换逻辑；`other_invest`、`investment`、`inc_gain` 的向上趋势语义保持不变。
- 处理范围：`assets/cat_icons/`、`assets/cat_icons_filled/`、`assets/cat_icons_line/`。新增高光 357 个 SVG，原本已有高光的 42 个 SVG 保持原样不重复添加；最终 399 个 SVG 全部覆盖同一条顶部高光。
- 已重新生成视觉对比图：`outputs/feimiao_category_icons_detail_1_highlight_unified.png` 至 `outputs/feimiao_category_icons_detail_4_highlight_unified.png`，以及 `outputs/feimiao_category_icons_all_compare_highlight_unified.png`。
- 版本已同步递增到 `1.167.0+169`：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart`、`android/local.properties` 均已更新，build tag 为 `b0710-169`。
- 验证：`flutter analyze --no-pub` 通过；`flutter build apk --release --no-pub` 成功；APK 内部资源复查 `svg_total=399 missing_highlight=0`。
- APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.167.0-169.apk`，大小 `111,130,031` 字节，SHA256：`C074CB803559A49BD650FD4AAD7260CFACEC52430CEF8E0F7D6E69BFD37D90B7`；`aapt dump badging` 确认 `com.qingji.qingji.codex` / `versionCode=169` / `versionName=1.167.0` / 应用名 `肥喵记账`；`apksigner verify --print-certs` 确认证书仍为 `CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`。

## 2026-07-10 分类图标语义精修与出包（Codex） / 1.166.0+168
- 按用户反馈“投资应该向上”重新全量复查分类图标语义，本轮重点精修 17 个容易误认或方向错误的 SVG：`other_invest`、`investment`、`inc_gain`、`inc_dividend`、`house_phone`、`transport`、`trans_public`、`trans_repair`、`car_wash`、`groceries`、`shop_deco`、`dining_treat`、`edu_course`、`edu_tuition`、`dining`、`dining_lunch`、`dining_drink`。
- `other_invest`（投资费用）从向下趋势改成向上趋势图，`inc_gain`（投资收益）从百分号改成向上趋势图，保证投资相关图标不再传达“下跌/亏损”语义；默认、面性、线性三套目录同步更新。
- 修正其它语义弱项：电话宽带改为手机+信号，保养修车改为扳手，洗车改为车+水滴，生鲜改为菜篮+叶子，装修维修改为滚刷，请客吃饭改为多人同桌，课程/学费分别改为课程屏幕/学校建筑，交通大类与公共交通区分。
- 已重新生成图标对比图：`outputs/feimiao_category_icons_detail_1_semantic_refined.png` 至 `outputs/feimiao_category_icons_detail_4_semantic_refined.png`，以及 `outputs/feimiao_category_icons_all_compare_semantic_refined.png`。
- 版本已同步递增到 `1.166.0+168`：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart`、`android/local.properties` 均已更新，build tag 为 `b0710-168`。
- 验证：`flutter analyze --no-pub` 通过；`flutter test --no-pub test\app_repository_test.dart` 52 项通过；`flutter build apk --release --no-pub` 成功。
- APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.166.0-168.apk`，大小 `111,117,095` 字节，SHA256：`CDB6843E81B5EE9D7F3BE08131A0F1458BBE8CE6ED2F0BDE0322A4E37EC9AF5D`；`aapt dump badging` 确认 `com.qingji.qingji.codex` / `versionCode=168` / `versionName=1.166.0` / 应用名 `肥喵记账`；`apksigner verify --print-certs` 确认证书仍为 `CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`。

## 2026-07-10 分类图标双风格全量补齐（Codex）
- 已将 `assets/cat_icons_filled/` 和 `assets/cat_icons_line/` 补齐到与默认目录一致的 `133` 个 SVG 资源，覆盖分类、目标/储蓄、转账等现有图标资源。
- 保留首批手工优化过的 20 个高频双风格图标；其余缺失项按默认图标批量补齐面性版本，并从默认 SVG 派生线性版本，先解决“可切换但未覆盖”的问题。
- `CatIcon` 的 `kDualStyleCategoryKeys` 已扩展到全量资源；分类管理里切换「面性 / 线性」后，所有已有分类 SVG 都能走对应目录，不再只影响 20 个高频分类。
- 重新生成全量对比图：`outputs/feimiao_category_icons_all_compare_full.png`，图中显示 `133 个默认资源 · 133 个双风格资源`。
- 额外生成 4 张放大分段图：`outputs/feimiao_category_icons_detail_1_clean.png` 至 `outputs/feimiao_category_icons_detail_4_clean.png`，用于人工圈选后续要重画或微调的图标。
- 验证：`flutter analyze --no-pub` 通过，No issues found。

## 2026-07-10 早餐分类图标语义修正（Codex）
- `dining_breakfast` 不再使用咖啡/热饮杯，避免和饮料、咖啡语义混淆。
- 默认目录 `assets/cat_icons/` 与面性目录 `assets/cat_icons_filled/` 的早餐图标改为白色蛋白 + 金黄色蛋黄的煎蛋图形。
- 线性目录 `assets/cat_icons_line/` 的早餐图标改为煎蛋轮廓 + 蛋黄，保持线性风格但优先保证“早餐/鸡蛋”的辨识度。
- 本次仅替换 SVG 资产，不改分类 key、统计、导入匹配、设置项或数据库。

## 2026-07-10 分类管理图标风格切换（Codex）
- 分类管理页右上角新增「图标样式」入口，按钮使用统一 `AppCircleButton` 浅底圆形样式；点击后打开 `showBlurSheet` 半屏弹层。
- 新增 `CategoryIconStyle`：当前支持 `filled`（面性）和 `line`（线性），默认 `filled`；用户选择后写入 `app_settings.category_icon_style`，不升级数据库版本。
- `CatIcon` 改为读取 `AppRepository.categoryIconStyle`，全局分类图标会跟随设置切换；若当前分类未覆盖双风格资产，则回退 `assets/cat_icons/`，避免切换线性后出现空白、emoji 或资源报错。
- 图标样式弹层采用统一 `SheetHeader`：左上关闭、中间标题、右上保存；内容为两张预览卡，展示面性/线性两套高频分类图标样式，选中态使用猫眼金描边和 check 标识。
- 验证：`flutter analyze --no-pub` 通过；`flutter test --no-pub test\app_repository_test.dart` 52 项通过。

## 2026-07-10 分类图标双风格样板（Codex）

- 资产结构调整：assets/cat_icons/ 保持当前 App 默认并使用面性增强版；新增 assets/cat_icons_filled/ 保存面性增强版；新增 assets/cat_icons_line/ 保存线性版，为后续“图标类型选择”做资产准备。
- 面性增强版方向：接近原来的高识别度实心风格，但统一圆角、渐变底、透明负形细节和视觉重心，减少粗糙拼贴感。
- 线性版方向：保留更轻、更克制的线条风格，适合后续给用户作为第二套风格选择。
- 首批覆盖高频图标：dining, dining_breakfast, dining_lunch, dining_dinner, dining_drink, groceries, shopping, shop_digital, transport, trans_public, car, housing, house_rent, utilities, medical, education, salary, bonus, otherIncome, other。
- 本次不改分类 key、数据库、统计、导入匹配和渲染逻辑；后续做设置项时再接入目录切换。
# 肥喵记账 Codex 交接文档（给 Claude 执行版）

> 这份文档不是完整流水账，而是给 Claude 或人工接手时使用的当前状态说明。  
> 如果同一个功能经历过多次调整，只保留最新有效结论；旧的反复试错记录不再展开。

## 2026-07-09 任务 5 视觉升级批（Claude 直做）/ 1.161.0+163

参考 iOS Cloudflare 客户端截图，全部规格见 TASKS_FOR_CODEX.md 任务 5（已闭合）。

- **全局确认弹窗重写**（`widgets/ios_dialogs.dart`）：CupertinoAlertDialog → 大圆角(26)卡 +
  标题加粗居中 + 灰正文居中 + 两颗等宽胶囊（取消=浅灰底、确认=主色蓝灰底白字、
  危险=超支橙底白字）。全 App showConfirmDialog 调用点自动升级；
  AI 隐私弹窗（ai_privacy_consent.dart）也改走它。
- **统计头大数字卡**：支出/收入/结余三张 1/3 小卡 → 支出通栏主卡（「总支出 · X月」+
  右上涨跌徽章 + 38号 Nunito w700 金额）+ 收入/结余两张半宽小卡带紧凑徽章。
  徽章三指标限定；配色支出↑橙/↓铜金、收入结余反转；基准=同期（当月比上月截至同日、
  周比上周同星期几、年比去年同月日，历史期全对全）；自定义无同期不显示；
  上期 0/无数据隐藏，不出 ∞%。
- **趋势图曲线+渐变**：isCurved + preventCurveOverShooting（防过冲，b0703-36 的直线可以退役）+
  线下渐变填充（支出蓝灰→透明、收入铜金→透明）；同期虚线也曲线化；Y 轴网格改淡虚线。
- **统计页背景暖渐变试点**：浅色主题顶部极淡铜金(#FCF3E2)→奶白(#FFFDF7)，
  AppBar/Scaffold 透明化透出渐变；深色主题不动；只统计页，用户认可再铺开。
- **新卡「消费来源」**（key `sources`，月视图）：账单备注经 normalizeMerchant 归一化聚合，
  净额 TOP6 横向条形（猫系色板），退款负数自然相抵。进图表库+默认序；
  **老配置用户需从图表库手动开一次**（区分不了"没见过新卡"和"手动关掉"，不强塞）。
- 验证：analyze 0 error；310/310 全过；出包 `feimiao-codex-v1.161.0-163.apk`（codex 签名）。
- 真机复测：各类删除确认弹窗和 AI 隐私弹窗观感；统计月/周/年头卡与徽章数字是否合理；
  趋势曲线是否平滑无过冲；统计页顶部暖渐变是否够淡；图表库打开「消费来源」看聚合质量。

## 2026-07-09 任务 4：抽屉底栏调换 + 个人中心并入设置 + 头像/昵称编辑 / 1.158.0+160

### 本次改动

- `lib/main.dart`
  - 抽屉底栏改为左侧「+ 新建账本」白底黑字胶囊，右侧设置齿轮 `AppCircleButton`。
  - 原左下头像入口移除，不再从抽屉进入 `PersonalCenterView`。
  - 设置齿轮成为抽屉里的唯一设置入口，打开 `SettingsView`。
  - 历史 `drawer_order` 里的未知 key 仍由现有 `_orderedFns()` 忽略，不会崩。
- `lib/views/settings/settings_view.dart`
  - 设置页顶部新增资料区：圆头像、昵称、编辑角标，空头像回退昵称首字占位，不放猫。
  - 新增「编辑资料」半屏弹层：`SheetHeader` 左上 ✕、居中标题、右上「保存」pill。
  - 编辑资料支持昵称（最多 12 字）和头像选择：拍照、相册、选择文件。
  - 头像保存前限制 512px 以内，文件目标控制在约 200KB 内；选择文件会重采样，非图片会 toast。
  - 「关于」迁入设置页：使用条款、隐私政策、版本号三项在弹窗内展示。
- `lib/data/app_repository.dart`
  - 新增个人资料本地状态：
    - `profile_nickname` 存入 `app_settings`。
    - 头像保存到 App 文档目录 `profile/avatar.png`，路径存入 `profile_avatar_path` 方便重启后读取。
  - 不新增数据库表，不升级数据库版本，不碰 `_onUpgrade`。
- `test/app_repository_test.dart`
  - 新增测试：昵称与头像路径在 repository 重启后仍能读回，头像文件写入固定 `avatar.png`。

### 验证

- 已执行：`dart format lib\data\app_repository.dart lib\views\settings\settings_view.dart lib\main.dart test\app_repository_test.dart`。
- 已执行：`flutter analyze --no-pub`，No issues found。
- 已执行：`flutter test --no-pub test\app_repository_test.dart`，51/51 通过。
- 已执行：`flutter test --no-pub`，310/310 通过。
- 已执行：`flutter build apk --release --no-pub`，成功生成 release APK。
- 已执行：`aapt dump badging`，确认：
  - package：`com.qingji.qingji.codex`
  - versionCode：`160`
  - versionName：`1.158.0`
  - application-label：`肥喵记账`
- 已执行：`apksigner verify --print-certs`，确认仍为 codex 正式签名证书：
  - `CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`
- APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.158.0-160.apk`
- 大小：`111,026,761` 字节。
- SHA256：`12109425C8BDB0F599EBFB696EB433F524CCCE845E9AB780704483EB576CDF4C`

## 2026-07-09 任务 3 Claude 接手完成：小组件离屏渲染跑通 + 出包 / 1.157.0+159

### 卡壳根因（给 Codex 长经验，下次别再猜错方向）

- 测试卡死不在 `Future.delayed`：`toImage()`/图片解码/sqflite 都是**真实异步**，`testWidgets`
  跑在假异步时钟里永远等不到它们完成。解法是把这些调用包进 `tester.runAsync()`，不是改渲染器。
- Codex 第二轮把"等图片解码的延时"删掉换微任务，方向反了：测试照样卡（卡在 toImage），
  真机上反而会把猫/封面渲成空白。已改回真实延时重刷（8×25ms），测试侧用 runAsync 兜。
- 另有两处隐性错误已修：`BuildOwner` 缺 `onBuildScheduled` 回调（图片解码完成触发重建会断言崩）；
  离屏树需要 `TickerMode(enabled:false)`（动画停初始帧，不空转）。

### 顺手逮到一个真机级 bug

- `AnimatedMoney` 金额从 0 滚动到目标值——离屏渲染 Ticker 被禁用时动画停在第 0 帧，
  **小组件上所有金额都会渲成 ¥0.00**。已修：TickerMode 禁用时直接静态显示最终值
  （`TickerMode.valuesOf(context).enabled`）。

### 其他收尾（Claude 完成）

- 删掉 home_view/statistics_view 里被共享组件替代的死代码（`_ExpandedSummaryCard`/`_MonthlyPaceCard`
  及其孤儿子组件，共约 900 行），home_view 1275→633 行、statistics_view 3204→2891 行。
- 预览图从真渲染生成（`UPDATE_WIDGET_PREVIEWS=1` 跑 widget_card_renderer_test）：
  测试引擎只有 Ahem 占位字体，`_tryLoadRealFonts` 把自带 Nunito、本机等线（注册为 PreviewCJK，
  经 `renderWidgetToPng(fontFamily:)` 从主题层应用+fallback）、MaterialIcons/CupertinoIcons
  图标字体都喂进去，预览图文字/图标/猫全真。**该机制只影响本机预览生成，设备端渲染不传 fontFamily。**
- `widget_preview_overview.png` / `widget_preview_budget.png` 已换成真渲染结果。

### 验证与交付

- `flutter analyze --no-pub`：No issues found（含清理掉 codex 留的 7 个半成品告警）。
- `flutter test --no-pub`：**309/309 全过**（307 旧 + 2 个渲染新用例，卡死问题根除）。
- 版本三处同步 `1.157.0+159`，build tag `b0709-159`，codex 签名出包（详见 commit）。
- 真机复测重点：桌面添加两个小组件是否和主页大卡片/统计进度卡一比一（含探头猫）；
  金额是否正常（不是 ¥0.00）；记一笔账后小组件是否跟着刷新；点总览→主页、点进度→统计；
  隐私模式金额变 ¥****；添加列表预览图是否为真卡片样式。

## 2026-07-09 第二批任务 3：小组件真组件离屏渲染改造卡壳记录（Claude 已接手解决，见上节）

### 当前状态

- 已按 `docs/claude/TASKS_FOR_CODEX.md` 第二批任务 3 开始实施“小组件推倒重做”。
- 本批目标是：总览小组件使用主页真实大卡片离屏渲染 PNG，本月进度小组件使用统计页“截至今日”真实卡片离屏渲染 PNG，原生 RemoteViews 只负责展示 PNG 和兜底。
- 按任务书“卡壳规则”，离屏渲染器两轮跑不通后已停止继续盲试，未构建 APK，未提交 commit。

### 已做改动

- 新增共享卡片组件：
  - `lib/widgets/home_summary_card.dart`
  - `lib/widgets/monthly_pace_card.dart`
- 主页/统计页已改为调用共享组件：
  - `lib/views/home/home_view.dart`
  - `lib/views/statistics/statistics_view.dart`
- 新增离屏渲染器雏形：
  - `lib/core/widgets/widget_card_renderer.dart`
- 快照服务已接入渲染路径雏形：
  - `lib/core/widgets/widget_snapshot_service.dart`
  - `refreshNow()` 构建快照后尝试渲染 `overview.png` / `pace.png` 到 `widget_render/`，并把路径写入 JSON。
- 原生小组件已改为 PNG 优先、文字布局兜底的雏形：
  - `android/app/src/main/res/layout/widget_feimiao.xml`
  - `android/app/src/main/res/layout/widget_budget.xml`
  - `android/app/src/main/kotlin/com/qingji/qingji/FeimiaoWidgetProvider.kt`
- 新增渲染器测试雏形：
  - `test/widget_card_renderer_test.dart`

### 卡壳症状

- 第 1 次运行：
  - 命令：`flutter test --no-pub test\widget_card_renderer_test.dart`
  - 现象：卡在第一个用例 `真实总览卡和本月进度卡可离屏渲染为 4x2 PNG`，长时间无输出，手动终止。
  - 初步怀疑：渲染器内部使用 `Future.delayed(16ms)`，在 `testWidgets` fake async 环境里可能不会自然推进。
- 第 2 次运行：
  - 已把渲染等待改为 `Future.value()` 微任务刷新。
  - 再次执行同一命令后仍卡在同一个用例，长时间无输出，手动终止。
- 目前疑点：
  - `RenderRepaintBoundary.toImage()` 前的离屏 `RenderView` / `PipelineOwner` / `BuildOwner` 挂载或 paint-ready 状态可能不正确。
  - 也可能需要先用最小 `ColoredBox` 隔离验证离屏管线，再逐步加入 `HomeSummaryCard`、资源图片和完整主题。

### 当前验证结果

- 已执行：`dart format`，格式化本批新增/修改 Dart 文件成功。
- 已执行：`flutter test --no-pub test\widget_card_renderer_test.dart` 两次，均卡死在第一个渲染测试，已停止。
- 已执行：`flutter analyze --no-pub`，当前有 7 个问题，主要是半成品导致的未使用代码/导入：
  - `lib/core/widgets/widget_card_renderer.dart`：`dart:typed_data`、`package:flutter/widgets.dart` 为 unnecessary import。
  - `lib/views/home/home_view.dart`：旧私有 `_ExpandedSummaryCard` 已不再使用。
  - `lib/views/statistics/statistics_view.dart`：旧私有 `_MonthlyPaceCard` 已不再使用。
  - `lib/widgets/home_summary_card.dart`：`dart:ui` 为 unnecessary import。
  - `lib/widgets/monthly_pace_card.dart`：`trailing` 可选参数未被传入。
  - `test/widget_card_renderer_test.dart`：`package:sqflite/sqflite.dart` 为 unnecessary import。

### 给 Claude 的接手建议

- 先不要继续在完整卡片上盲试；建议新增最小离屏渲染验证：
  - 先渲染纯 `ColoredBox` / `Container`。
  - 再渲染不含 `Image.asset` 的简化卡片。
  - 最后渲染完整 `HomeSummaryCard` / `MonthlyPaceCard`。
- 对照 Flutter 当前版本的 `RenderView` / `PipelineOwner` API，确认独立离屏树是否正确 attach、flush layout、flush paint。
- 渲染器跑通后再清理旧私有组件和 analyze 问题，并补齐预览图生成。

## 2026-07-09 AI 键盘/备份安全验收出包 / 1.156.0+158

### 本次交付

- 用户确认 2026-07-09 Codex 任务 1/2 已验收通过，本次只做正式出包：
  - 版本三处同步升级到 `1.156.0+158`：
    - `pubspec.yaml`
    - `lib/core/app_version.dart`
    - `lib/build_info.dart`
  - build tag：`b0709-158`
- 本 APK 包含上一节记录的两项已验收修复：
  - AI 记账键盘：系统/返回键收起键盘后释放焦点，不再被恢复计时器拉回。
  - 本机备份清理：`pre-v*.bak` 迁移前备份不参与日常轮换，manual/auto 各自保留 3 份，备份列表纯读取。

### 出包验证

- 已执行：`dart format lib\core\app_version.dart lib\build_info.dart`。
- 已执行：`flutter analyze --no-pub`，No issues found。
- 已执行：`flutter test --no-pub`，307/307 通过。
- 已执行：`flutter build apk --release --no-pub`，成功生成 release APK。
- 已执行：`aapt dump badging`，确认：
  - package：`com.qingji.qingji.codex`
  - versionCode：`158`
  - versionName：`1.156.0`
  - application-label：`肥喵记账`
- 已执行：`apksigner verify --print-certs`，确认仍为 codex 正式签名证书：
  - `CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`
- APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.156.0-158.apk`
- 大小：`110,809,949` 字节。
- SHA256：`65A6C96C4BB431850B56BCA36651F1C2C0152CD25B5B842637A2D1DAB02FE024`

### 真机复测三查

- 点 AI 记账输入框后，键盘几秒内是否仍保持打开、不自动收回。
- 手机返回键是否能收起键盘，并且不会被重新拉起。
- 点击上方空白区域是否退出半屏并回到初始主页界面。

## 2026-07-09 Codex 任务 1/2 收口：AI 键盘回收 + 备份清理安全（无 APK 构建）

### 任务 1：AI 记账键盘回收回归修复

- `lib/views/home/ai_chat_panel.dart`
  - 修复系统收起键盘后输入框仍保持焦点的问题：当 `viewInsets` 从已打开状态回到 0 时，明确视为用户/系统关闭键盘意图。
  - 新增内部处理 `_acceptSystemKeyboardDismissal()`：先停止输入会话和恢复计时器，再在下一帧确认会话未恢复时释放 `_focus`。
  - 保留启动阶段的键盘修复逻辑：键盘尚未真实打开前，仍允许原有 startup repair 避免首次点击失败。
  - 未删除 AI 半屏、虚化、猫猫和四条建议；本次只收敛焦点/键盘会话状态。

### 任务 2：本机备份清理安全修复

- `lib/data/app_repository.dart`
  - `localBackupFiles()` 改为纯读取，不再因为打开备份页触发删除副作用。
  - `_pruneLocalBackups()` 改为只清理日常备份桶：
    - `qingji.db.manual-*`：独立保留最新 3 份。
    - `qingji.db.auto-*`：独立保留最新 3 份。
  - `qingji.db.pre-v*.bak` 迁移前救命备份不再参与日常轮换，避免被自动/手动备份挤掉。
  - `qingji.db.bak` 等非 manual/auto 的临时或未知备份名也不参与自动清理。
  - `_autoPeriodicBackup()` 如果因为最近已经自动备份而跳过创建，不再顺手清理，保证清理只发生在新建备份之后。
- `test/app_repository_test.dart`
  - 更新“本机备份列表只读取不清理旧备份”用例，覆盖打开备份页不删除旧备份。
  - 新增迁移前备份保护用例：目录里有 `pre-v20.bak` + 多份 manual 时，新建备份后 `pre-v20.bak` 仍存在，manual 只留 3 份。
  - 新增 manual/auto 独立限额用例：手动备份和自动备份各自保留 3 份，互不挤占。

### 验证

- 已执行：`dart format lib\views\home\ai_chat_panel.dart lib\data\app_repository.dart test\app_repository_test.dart`。
- 已执行：`flutter test --no-pub test\ai_chat_panel_focus_test.dart`，10/10 通过。
- 已执行：`flutter test --no-pub test\app_repository_test.dart`，50/50 通过。
- 已执行：`flutter analyze --no-pub`，No issues found。
- 已执行：`flutter test --no-pub`，307/307 通过。
- 本批次按任务书要求未构建 APK、未递增版本号、未提交 commit；等待 Claude/用户验收后再进入下一批。

### 后续真机复测三查

- 点 AI 记账输入框后，键盘几秒内不应自动收回。
- 手机返回键应能收起键盘，且不会被重新拉起。
- 点击上方空白区域应退出半屏并回到初始主页界面。

## 2026-07-09 Claude 全量审查 + 数据安全修复（无 APK 构建）

### 审查结论（Claude 执行，工具：flutter analyze + 全量 flutter test + 人工 diff 审查）

- `flutter analyze`：0 error。全量测试：审查时 301 个用例 299 过、**2 个挂**（见下）。
- 之前"测试跑不了"的根因（sqlite3.x64.windows.dll 从 GitHub 下载超时）已修复：DLL 从
  `C:\src\xunni\android-app` 的缓存复制到本仓 `.dart_tool`。**以后没有理由跳过测试出包。**
- 工作区 2.2 万行未提交改动已打 git 快照 commit（`快照:codex工作区截至v1.155.0+157`）。

### Claude 直接修掉的（任务 0）

- `lib/data/app_repository.dart` 的 `_normalizeStandaloneRefunds` 重写：原版用打分启发式在**每次启动**时
  猜测归并"疑似退款"，会把备注含"退款/退回"的**收入行**静默转成支出冲减（收入凭空消失）、
  空备注负数行被改写日期/分类/备注，且全程无测试。现改为高置信确定性匹配：
  只处理负数支出行、收入行一律不碰；仅"分类一致或金额精确相等且候选唯一"才挂回原单，有歧义不动；
  非空备注保留。调用点不变（init / 恢复备份 / 导入后）。
- `test/app_repository_test.dart` 新增『游离退款归并』group 4 个用例（行为契约，勿删改）。
- 验证：analyze 0 error；`test/app_repository_test.dart` 48/48 全过。未构建 APK、未动版本号（源码级修复，
  随下一次出包一起带出去）。

### 遗留给 Codex 的（详见 docs/claude/TASKS_FOR_CODEX.md，按序做）

- 任务 1：`test/ai_chat_panel_focus_test.dart` 两个键盘回归用例挂着——1.155.0+157 宣称的
  "系统收起键盘不再拉回"未生效，需真修（不许改断言迁就实现）。
- 任务 2：`_pruneLocalBackups` 会把 `pre-v` 迁移前备份混进 3 份限额里删掉，且打开备份页就触发清理；
  需要 pre-v 永不自动删、auto/manual 各自限额、`localBackupFiles()` 改纯读取，并补测试。

### 流程新规（用户拍板）

- 每交付一个 APK 必须 `git add -A && git commit`（不 push）。
- 出包前 analyze + 全量 test 必须绿。
- 数据层（迁移/退款报销/统计口径）没有任务书授权不许改。

## 2026-07-09 AI 设置分组重构 / 1.155.0+157

### 用户要求

- 当前 AI 设置页信息太乱，需要按功能分类拆分：AI 账号设置、用途分配、高级参数设置、隐私与数据。
- 自定义 AI 不应只有固定“自定义”两个字，名称也要能自己设置。
- 用途分配需要支持智能/自动模式：在满足需求的前提下，普通一句话记账优先速度，报告类任务优先深度。

### 本轮修改

- `lib/views/settings/ai_setting_view.dart`
  - 从单页大表单重构为入口页 + 4 个子页：
    - `AI 账号设置`：DeepSeek / 自定义服务切换、API Key、服务名称、基础地址、普通模型、连接测试、清除当前密钥。
    - `用途分配`：普通记账、喵助手、报告生成分别支持 `自动 / 固定`；固定模式可指定 DeepSeek 或自定义服务。
    - `高级参数设置`：普通模型、报告模型、喵助手接口、报告接口、喵助手思考深度、报告思考深度。
    - `隐私与数据`：说明 API Key 本机安全存储、不进入备份；显示 AI 隐私确认状态，并支持下次重新确认。
  - 入口页只展示四个分类和当前摘要，不再把密钥、用途、接口、思考深度全部堆在同一个页面。
  - 复用现有 `SettingsGroup / SettingsRow / AppBackButton` 风格，避免新增陌生设置页样式。
  - 自动分配 UI 文案明确当前策略：普通记账/喵助手优先快，报告生成优先深度；没有对应 key 时回退可用服务。
- `lib/core/ai/ai_provider_config.dart`、`lib/data/app_repository.dart`
  - 上轮已加入的 `AiRouteMode`、自定义服务显示名、用途路由 getter/setter 继续作为本轮 UI 的数据来源。
  - API Key 仍通过 `SecureKeyStore` 保存，自定义服务名/模型/地址走普通设置项；密钥不进入导出备份。
- 版本同步升级到 `1.155.0+157`：
  - `pubspec.yaml`
  - `lib/core/app_version.dart`
  - `lib/build_info.dart`
  - build tag：`b0709-157`

### 验证

- 已执行：`dart format lib\views\settings\ai_setting_view.dart lib\core\ai\ai_provider_config.dart lib\data\app_repository.dart`。
- 已执行：`flutter analyze --no-pub lib\views\settings\ai_setting_view.dart lib\core\ai\ai_provider_config.dart lib\data\app_repository.dart`，无问题。
- 已执行：`flutter analyze --no-pub lib\views\settings\ai_setting_view.dart lib\core\ai\ai_provider_config.dart lib\data\app_repository.dart lib\core\app_version.dart lib\build_info.dart`，无问题。
- 已执行：`flutter build apk --release --no-pub`。
- 已执行：`aapt dump badging`，确认包名 `com.qingji.qingji.codex`，`versionCode=157`，`versionName=1.155.0`，应用名 `肥喵记账`。
- 已执行：`apksigner verify --print-certs`，签名证书仍为 `CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`。
- APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.155.0-157.apk`
- 大小：`110,744,413` 字节。
- SHA256：`8EAD90E4D83EF9D1A94F9CE2B7B03727608E6AA028192434853DC6CB0F6CE1BA`

### 工作区整理

- 清理可再生成构建缓存：
  - `C:\src\xunni-codex\android-app\build`
  - `C:\src\xunni-codex\android-app\.dart_tool`
- `build` 目录普通删除时遇到 Gradle 深层临时目录幽灵残留，已用空目录镜像方式清理干净。
- 清理旧 release 产物，只保留本次最新 APK：
  - 保留：`feimiao-codex-v1.155.0-157.apk`
  - 保留：`feimiao-codex-v1.155.0-157.apk.sha256.txt`
  - 删除：`feimiao-codex-v1.154.0-156.apk`
  - 删除：`feimiao-codex-v1.154.0-156.apk.sha256.txt`
- 整理后体积：
  - `C:\src\xunni-codex`：约 `172.14MB`
  - `C:\src\xunni-codex\android-app`：约 `26.77MB`
  - `C:\src\xunni-codex\ci-artifacts`：约 `109.40MB`
  - `C:\src\xunni-codex\ci-artifacts\releases`：约 `105.61MB`

### 后续建议

- 当前仍是 `DeepSeek + 一个自定义服务槽` 的 P1 实现。后续如果用户继续要求“多个自定义账号池”，应新增 AI 账号列表模型，而不是继续往单个自定义槽里塞字段。
- 真机复测重点：AI 设置入口是否清爽；各子页保存后返回入口页摘要是否更新；报告使用自定义服务时是否仍走 Responses/XHigh；普通记账是否仍走快速路径。

## 2026-07-08 AI 回复前多阶段状态展示（无 APK 构建）

### 用户要求

- Claude 在回复前会展示多个处理状态；肥喵当前只有“喵在想”，需要根据 AI 正在执行的任务展示更直观的状态。

### 本轮修改

- `lib/views/home/ai_chat_panel.dart`
  - `_ThinkingMsg` 保持为轻量状态消息，按 `_ThinkingKind` 轮播短状态文案。
  - 新增并接入完整状态流：`intent`、`recordParse`、`recordMatch`、`queryCollect`、`queryAnswer`、`reportCollect`、`reportGenerate`、`reportFallback`、`reportSave`。
  - 普通记账：识别意图 -> 拆分账单/提取金额 -> 匹配分类/校对账本。
  - 普通问账：整理账本/筛选记录 -> 计算金额/组织回答。
  - 报告生成：汇总周期/整理明细 -> 分析结构/生成报告 -> 必要时换用简版生成 -> 保存文档/生成报告卡片。
  - 重新生成普通回答从 `queryCollect` 开始，重新生成报告从 `reportCollect` 开始，不再统一显示“识别意图”。
  - 思考状态每 1.6 秒轮播一次，超过 8 秒显示耗时，减少长报告生成时“是不是卡住了”的不确定感。
  - `dispose()` 已取消 `_thinkingStatusTimer`，避免离开页面后计时器残留。

### 验证

- 已执行：`dart format lib\views\home\ai_chat_panel.dart`。
- 已执行：`flutter analyze --no-pub lib\views\home\ai_chat_panel.dart`，无问题。
- 本轮未构建 APK；如后续出包需按规则递增版本号。
## 2026-07-08 项目文件整理 / 无 APK 构建

### 用户要求

- `C:\src\xunni-codex` 项目又变大，需要整理文件和清理冗余产物。

### 本轮整理

- 清理可再生成构建产物：
  - `C:\src\xunni-codex\android-app\build`
  - `C:\src\xunni-codex\android-app\.dart_tool`
- 清理旧 release APK，只保留最新正式交付包：
  - 保留：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.154.0-156.apk`
  - 保留：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.154.0-156.apk.sha256.txt`
  - 删除旧包：`1.153.0+155`、`1.152.0+154` 及对应 sha 文本。
- `android-app\build` 初次删除时遇到 Gradle 深层临时目录长路径/目录空壳残留，最终用空目录 `robocopy /MIR` 镜像后删除干净。

### 整理后体积

- `C:\src\xunni-codex`：约 `171MB`。
- `android-app`：约 `26.62MB`。
- `ci-artifacts`：约 `109.39MB`，主要为最新 APK。
- `android-app\assets`：约 `12.61MB`。
- `android-app\android`：约 `12.01MB`。

### 注意

- 本轮没有改业务代码，没有构建新 APK。
- `.dart_tool` 和 `build` 被删除后，下次运行 analyze/test/build 会自动重新生成，属于正常现象。
## 2026-07-08 AI 用途分配 / GPT Responses / 键盘回收修复 / 1.154.0+156

### 用户要求

- GPT 官方接入改用 `/v1/responses`，报告生成可调思考深度，并将报告思考深度默认提升到 `XHigh`。
- DeepSeek 仍然保留，普通记账可以继续使用 DeepSeek；AI 需要按用途分配，例如普通记账、喵助手、报告生成分别选择服务。
- 修复 AI 记账键盘弹出后一段时间自动收回、手机返回键收不掉键盘的问题。
- 每次涉及调整必须更新给 Claude/Fable 的交接文档并构建 APK。

### 本轮修改

- `lib/core/ai/ai_provider_config.dart`
  - 新增 `AiTaskType`：`recordParse`、`chatQuery`、`report`。
  - 新增 `AiEndpointType`：`auto`、`chatCompletions`、`responses`。
  - 新增 `AiReasoningEffort`：`none`、`minimal`、`low`、`medium`、`high`、`xhigh`。
  - `AiProviderConfig` 增加 `endpointType`、`reasoningEffort`、`responsesUri`、`shouldUseResponses`。
  - DeepSeek 固定走 Chat Completions；自定义 OpenAI 官方地址在 `auto` 下默认可走 Responses。
- `lib/core/ai/llm_query.dart`
  - 保留原 Chat Completions 调用路径。
  - 新增 Responses 调用路径：system/developer prompt 转为 `instructions`，用户内容转为 `input`，`max_tokens` 转为 `max_output_tokens`，并在配置允许时加入 `reasoning.effort`。
  - Responses 返回解析优先读 `output_text`，否则递归读取 `output[].content[].text`。
- `lib/data/app_repository.dart`
  - 新增用途级 AI 路由设置，存储在 `app_settings`，不升级数据库表结构。
  - 旧 `aiProviderConfig` 保留为普通记账兼容入口；新增 `aiProviderConfigFor(AiTaskType)`。
  - 默认策略：普通记账用 DeepSeek/Chat/关闭思考；喵助手沿用旧选择并支持高级设置；报告默认自定义 GPT/Responses/XHigh，若没有自定义 key 则回退旧选择。
  - 切换服务、地址、用途分配或接口类型后重置 AI 隐私确认。
- `lib/views/settings/ai_setting_view.dart`
  - 设置页重构为三段：服务密钥、用途分配、报告高级参数。
  - 用途分配支持普通记账、喵助手、报告生成分别选择 DeepSeek 或自定义。
  - 报告高级参数支持报告模型、报告接口、报告思考深度；喵助手也可调接口和思考深度。
- `lib/views/home/ai_chat_panel.dart`
  - 普通记账解析改用 `AiTaskType.recordParse`。
  - 普通查账改用 `AiTaskType.chatQuery`。
  - 报告生成/重新生成改用 `AiTaskType.report`。
  - 键盘修复：删除旧的 keyboard reconnect 逻辑；键盘真实打开后，后续关闭视为用户/系统意图，不再被定时器强行拉回；点击空白仍会退出输入态并回到主页初始界面。
- `lib/views/quick_add/ai_quick_entry_view.dart`、`lib/views/settings/bill_review_view.dart`
  - AI 解析/批量分类统一使用普通记账路由，避免误用报告的 XHigh 慢路径。
- 版本同步升级到 `1.154.0+156`：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart` 已更新，build tag 为 `b0708-156`。

### 验证与交付

- 已通过：`flutter analyze --no-pub lib\core\ai\ai_provider_config.dart lib\core\ai\llm_query.dart lib\data\app_repository.dart lib\views\settings\ai_setting_view.dart lib\views\home\ai_chat_panel.dart lib\views\quick_add\ai_quick_entry_view.dart lib\views\settings\bill_review_view.dart`。
- 已通过：`flutter build apk --release --no-pub`。
- 已通过：`aapt dump badging`，确认包名 `com.qingji.qingji.codex`，`versionCode=156`，`versionName=1.154.0`，应用名 `肥喵记账`。
- 已通过：`apksigner verify --print-certs`。
- 测试未跑通：`flutter test --no-pub test\ai_chat_panel_focus_test.dart test\ai_chat_record_serialization_test.dart` 因本机需要从 GitHub 下载 `sqlite3.x64.windows.dll`，当前网络超时。
- APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.154.0-156.apk`
- 大小：`110,728,029` 字节
- SHA256：`056355A460DF6C064ABF7E528A57C1D4FB26F40A99261A9D89DAD62F138C7396`

### 真机复测重点

- AI 设置页：DeepSeek key、自定义 key、用途分配、报告 Responses/XHigh 保存后是否保持。
- 普通记账：DeepSeek 路径是否仍能快速解析，不应走报告 XHigh。
- 报告生成：选择自定义 GPT 后是否走 `/v1/responses`，报告是否能生成文档卡片。
- AI 记账键盘：点击输入框后键盘是否稳定；几秒后是否还会自动收回；手机返回键是否可以收回键盘；点击上方空白是否回到主页初始态。
## 2026-07-08 AI 记账透明模糊参数调整 / 1.153.0+155

### 用户要求

- AI 记账键盘弹出态，输入框外应该是透明模糊；当前输入框和背景白遮罩透明度不够。
- 用户确认参数：输入框玻璃不透明度从 `0.78` 调到 `0.55`；空态背景遮罩从 `0.42` 调到 `0.20`。

### 本轮修改

- `lib/views/home/ai_chat_panel.dart`
  - AI 空态整页背景遮罩：`alpha: _started ? 0.18 : 0.42` -> `alpha: _started ? 0.18 : 0.20`。
  - 底部输入框 `GlassSurface`：`opacity: blurEnabled ? 0.78 : 0.9` -> `opacity: blurEnabled ? 0.55 : 0.9`。
  - 背景模糊半径保持不变：空态 `sigmaX/Y=22`，对话态 `sigmaX/Y=16`。
  - 输入框自身模糊保持不变：`blur=10`。
- 版本同步升级到 `1.153.0+155`：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart` 已更新，build tag 为 `b0708-155`。

### 验证与交付

- 已通过：`flutter analyze --no-pub lib\views\home\ai_chat_panel.dart lib\build_info.dart lib\core\app_version.dart`。
- 已通过：`flutter build apk --release --no-pub`。
- 已通过：`aapt dump badging`，确认包名 `com.qingji.qingji.codex`，`versionCode=155`，`versionName=1.153.0`，应用名 `肥喵记账`。
- 已通过：`apksigner verify --print-certs`。
- APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.153.0-155.apk`
- 大小：`110,678,877` 字节
- SHA256：`53280CA56D4BE79AF3100574D001D9AC7ADF5EFC786D68377B6FF3305F66E793`

### 真机复测

- 小米 15 Pro 上进入 AI 记账，弹出键盘后检查：背景是否比上一版更透，底部输入框是否更接近透明模糊而不是实白卡。
- 同时复测上一轮修复：发送消息后是否自动停在最新用户消息位置，历史消息是否不再默认挤入视野。

## 2026-07-08 AI 记账发送后定位与半屏顶部压缩

### 用户现象

- 首页 AI 记账发送消息后，视口不会自动定位到用户刚发出的消息，需要手动下滑才看得到。
- 用户期望：发送后默认只聚焦最新用户消息，历史消息应由用户主动滑动查看，避免对话区显得杂乱。
- 半屏对话态顶部白色区域过高，猫猫位置偏低，导致可读内容区域被压缩。

### 本轮修改

- `lib/views/home/ai_chat_panel.dart` 新增最新用户消息锚点维护：发送时立即设置 `_latestUserMsg`，并在写入数据库前先触发滚动定位，避免等待持久化或 AI 响应后才移动。
- `_scrollToLatestUserMessage()` 改为强制 `alignment: 0.0`，并在 260ms 后做二次定位，用来覆盖键盘收起、半屏高度变化、异步回复插入后的布局变化。
- 对话列表在存在最新用户消息时动态增加底部留白，解决“最新消息后内容不够高，Flutter 最大滚动距离不够，导致历史消息被迫露出”的问题。
- 历史对话恢复时，如果当前已经有最新用户消息锚点，不再滚到底部，而是继续保持最新用户消息位置。
- 半屏对话态顶部进一步压缩：拖拽条垂直 padding 从 `7` 降到 `5`，对话态 header 高度从 `44` 降到 `36`，猫猫从 `52` 调为 `50` 并上移 `5px`，减少顶部白块占用。

### 验证

- 已通过：`flutter analyze --no-pub lib\views\home\ai_chat_panel.dart`。
- `flutter test --no-pub test\ai_chat_panel_focus_test.dart` 未跑通，原因是本机需要从 GitHub 下载 `sqlite3.x64.windows.dll`，当前网络超时；这不是本次 Dart 代码编译错误。
- 已随 `1.153.0+155` 一起构建 APK，仍需用户真机复测：发送后是否自动停在最新用户消息、历史是否不再默认挤入视野、半屏顶部猫猫和白块高度是否合适。

## 2026-07-08 Claude 交接文档与文件夹整理（无 APK 构建）

### 本轮整理

- 新增当前接手入口：`docs/claude/CLAUDE_HANDOFF_CURRENT.md`。这份文档压缩了当前 APK、用户最新方向、重点模块、构建命令、真机复测项和严禁事项，给 Claude / Fable 5 优先阅读。
- 新增 docs 目录说明：`docs/README.md`。
- 旧方案文档非破坏性归档到：`docs/archive/legacy-plans/`。
- 小组件计划从工程根目录移到：`docs/widget/WIDGETS_FEIMIAO_PLAN.md`。
- 保留 `CHANGELOG_CODEX.md` 作为完整历史流水，但不建议接手者第一眼从头读；优先看 `docs/claude/CLAUDE_HANDOFF_CURRENT.md` 和本文顶部最近记录。
- 清理可再生成缓存：`.dart_tool`、`android/.gradle` 已移除；`build` 从约 1.56GB 级别降到约 160KB 残留空壳。最新 APK 已保留在 `C:\src\xunni-codex\ci-artifacts\releases\`。

### 文件结构约定

- `docs/claude/`：当前接手文档。
- `docs/widget/`：小组件 PRD / 计划。
- `docs/archive/legacy-plans/`：旧方案、旧 PRD、阶段性分析，仅作追溯。
- `ci-artifacts/releases/`：正式交付 APK 和 SHA256。
## 2026-07-08 小米桌面小组件产品方向修正 / 1.152.0+154

### 用户现象

- `1.151.0+153` 已经补上小组件预览图并修复 RemoteViews 加载风险，但用户真机截图反馈：总览和本月进度两个小组件视觉上像“两张大白统计卡”，桌面占比过大、信息堆叠，不符合此前“小组件家族”的要求。
- 用户重新明确方向：现在 App 里的“主页大卡片”和“统计页本月进度图”已经是最合适的视觉基础；小组件应直接迁移这两个成熟模块，比例不合适时只做桌面比例适配，不要重新发明一套白卡样式。

### 产品结论

- 小组件不是缩小版统计页，也不是把多个分析模块塞进一张桌面卡。
- 总览小组件对齐主页大卡片：月份胶囊、统计胶囊、快捷记账入口、支出/收入双栏、底部结余/今日提示；有预算时切到“预算剩余 + 本月支出 + 预算进度”的同一张卡片结构。
- 本月进度小组件对齐统计页 `_MonthlyPaceCard` 的核心图：截至今日、平均、本月、历史同进度柱图、平均线；分类与支出活动不再混入该卡。
- 分类与支出活动继续由独立分类小组件承载，避免预算/进度小组件再次变成半屏统计报表。

### 本轮改动

- `android/app/src/main/res/layout/widget_feimiao.xml`：总览小组件重做为主页大卡片缩放版。顶部改为月份胶囊 + `统计 ›` 胶囊 + 账本名 + `+`；主体恢复支出/收入双栏；底部展示结余和今日支出；预算模式复用同一布局展示预算剩余、支出和预算进度。
- `android/app/src/main/kotlin/com/qingji/qingji/FeimiaoWidgetProvider.kt`：总览绑定改为读取 `modules.overview` 后按 `mode=budget/normal` 分流；新增 `monthText()` 读取年月；`统计 ›` 点击进入统计页；预算底部说明读取已有 `budgetHint`。
- `android/app/src/main/res/layout/widget_budget.xml`：本月进度小组件改回只承载统计页进度图核心，删除分类行、查看所有和额外列表空间。
- `android/app/src/main/res/xml/feimiao_widget_budget_info.xml`：本月进度从 `4x3 / 220dp` 调回 `4x2 / 150dp`，避免桌面继续出现半屏大卡。
- `FeimiaoWidgetProvider.renderPaceChart()`：图表 bitmap 高度同步到 56dp，匹配新的 4x2 进度卡。
- `android/app/src/main/res/drawable-nodpi/widget_preview_overview.png`、`widget_preview_budget.png`：重新生成预览图，避免系统添加小组件列表继续展示旧的大白统计卡预览。
- 版本同步升级到 `1.152.0+154`：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart` 已更新，build tag 为 `b0708-154`。

### 验证证据

- `flutter build apk --release --no-pub` 成功，产物大小 `110,678,877` 字节。
- `aapt dump badging` 确认：包名 `com.qingji.qingji.codex`，`versionCode=154`，`versionName=1.152.0`，应用名 `肥喵记账`，入口 `com.qingji.qingji.MainActivity`。
- `aapt dump resources` 确认 APK 内包含 `widget_preview_overview`、`widget_preview_budget`、`widget_preview_categories`、`widget_preview_quick_add`，并包含 `feimiao_widget_info` 和 `feimiao_widget_budget_info`。
- Provider XML 扫描确认：总览 `4x2 / minHeight=150dp`，本月进度 `4x2 / minHeight=150dp`，分类活动 `3x2`，快捷记账 `2x1`，四个小组件均保留 `previewImage`。
- `apksigner verify --print-certs` 通过，证书仍为 `CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`。

### 交付物

- APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.152.0-154.apk`
- SHA256：`033AFCEA163907BE1DB5FF4AF0810981E934A04F127B0F95B0F55A2E09663DD6`
- 校验文件：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.152.0-154.apk.sha256.txt`

### 重点复测

- 小米桌面添加小组件列表中，总览预览应像主页大卡片，不应再是单个巨大主指标卡。
- 本月进度预览应像统计页柱状图，不应再带“分类与支出活动”列表。
- 桌面实际添加后，总览、本月进度、分类活动应分别承担各自任务，不能出现两个半屏白卡同时堆统计信息。
- 本机未连接用户真机，仍需用户安装 APK 后用小米 15 Pro 桌面实际验证预览、添加、缩放和点击跳转。
## 2026-07-08 小米桌面小组件预览与加载失败修复 / 1.151.0+153

### 用户现象

- 小米 15 Pro 桌面“添加小部件”列表中，肥喵记账的 4 个小组件只显示应用图标，没有真实预览图。
- 用户添加小组件到桌面后，桌面提示“加载窗口小部件时出现问题”，小组件本体不渲染。

### 根因判断

- 预览缺失：4 个 `appwidget-provider` XML 只有 `android:previewLayout`，没有 `android:previewImage`。MIUI 添加页优先展示静态预览图，缺失时会退回应用图标。
- 加载失败高概率原因：小组件布局里用了普通 `<View>` 做细分割线。Android 桌面小组件通过 `RemoteViews` 由 Launcher 进程 inflate，支持的 View 类是白名单；部分 Launcher/MIUI 对普通 `android.view.View` 兼容不稳定，可能直接导致“加载窗口小部件时出现问题”。
- 本轮没有证据显示是 Flutter 页面、账本快照、数据库或 App 图标问题，因此修复范围限定在 Android 原生小组件资源和 RemoteViews 兼容性。

### 本轮改动

- `android/app/src/main/res/xml/feimiao_widget_info.xml`、`feimiao_widget_quick_add_info.xml`、`feimiao_widget_budget_info.xml`、`feimiao_widget_categories_info.xml`：全部补充 `android:previewImage`。
- 新增 4 张真实预览图：
  - `android/app/src/main/res/drawable-nodpi/widget_preview_overview.png`
  - `android/app/src/main/res/drawable-nodpi/widget_preview_quick_add.png`
  - `android/app/src/main/res/drawable-nodpi/widget_preview_budget.png`
  - `android/app/src/main/res/drawable-nodpi/widget_preview_categories.png`
- `widget_feimiao.xml`、`widget_budget.xml`、`widget_categories.xml`、`widget_quick_add.xml`：将小组件布局中的普通 `<View>` 分割线替换为 RemoteViews 白名单支持的 `<FrameLayout>`。
- 没有改动小组件数据口径、账本快照结构、点击路由、App 图标资源和 Flutter 页面。

### 验证证据

- `flutter build apk --release --no-pub` 成功。
- `aapt dump badging` 确认：包名 `com.qingji.qingji.codex`，`versionCode=153`，`versionName=1.151.0`，应用名 `肥喵记账`。
- `aapt dump resources` 确认 APK 资源表包含：`widget_preview_budget`、`widget_preview_categories`、`widget_preview_overview`、`widget_preview_quick_add`。
- 打包后 appwidget XML 扫描确认：4 个 `appwidget-provider` 均含 `previewImage`，并保持正确的 `initialLayout`、`previewLayout`、`targetCellWidth`、`targetCellHeight`。
- `apksigner verify --print-certs` 通过，签名证书仍为 `CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`。

### 交付物

- APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.151.0-153.apk`
- 大小：`110,675,017` 字节
- SHA256：`007FF9ED1A52AA7E262154A14B0875F491DB636CEB2A89E3AD8D09F1BCA8EE99`
- 版本：`1.151.0+153`，build tag：`b0708-153`。

### 仍需真机复核

- 本机当前未连接到用户的小米 15 Pro，无法读取 MIUI Launcher logcat 或直接截图验证。
- 用户安装 `1.151.0+153` 后需要优先检查：添加小组件列表是否展示真实预览图；4 个小组件分别添加到桌面后是否仍提示“加载窗口小部件时出现问题”；打开 App 后小组件数据是否能刷新；点击 `+`、主体和分类行是否进入对应页面。
- 如果仍失败，下一步必须抓取 `adb logcat` 中 `AppWidgetHostView`、`RemoteViews`、`Launcher`、`InflateException` 相关日志，再按具体异常定位，不再继续盲改样式。

## 2026-07-08 AI 设置移除重复对话记录 / 1.150.0+152

- AI 设置页移除“对话记录”分组，不再在设置里重复展示“保存一个月 / 保存半年 / 清空对话”；对话记录入口保留在喵助手内部，避免两个入口语义重复。
- 删除 AI 设置页中已经无用的 `_ChatRetentionCard`、`clearChatHistoryMemory` 引用和死 import，并清理 `_SettingsCard` 已不再使用的 `clip` 参数。
- 保留上一节小组件改动：本月进度小组件升级为 4x3 分析卡，补齐分类前三、点击下钻、同进度柱状图和退款净额测试。
- 已通过：`dart format lib\views\settings\ai_setting_view.dart`；`dart analyze lib\views\settings\ai_setting_view.dart`。
- 版本已递增到 `1.150.0+152`：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart` 已更新，build tag 为 `b0708-152`。`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.150.0-152.apk` 已构建，大小 `110,653,045` 字节，SHA256：`D91017E71AD2F90CAF9D921112B368EEE4C7AA1581B847A2148D6CABA3700C6B`。已通过 `aapt dump badging`（`com.qingji.qingji.codex` / `versionCode=152` / `versionName=1.150.0` / `肥喵记账`）和 `apksigner verify --print-certs`。

## 2026-07-08 小组件继续优化：进度分析卡 + 点击下钻 / 1.149.0+151

- 本月进度小组件从 `4x2` 调整为 `4x3` 分析卡，避免“进度图 + 分类活动”挤在 2 行高度里裁切；布局改为顶部账本/日期/+、截至今日、平均/本月双指标、同进度柱状图、分类与支出活动前三。
- `widget_budget.xml` 新增前三分类行，复用分类小组件的颜色圆点、金额、百分比和 3dp 圆角进度条；无分类数据时默认隐藏，避免空白占位。
- 原生 `FeimiaoWidgetProvider` 的本月进度小组件现在读取 `modules.categories.items`，和独立“支出活动”小组件共享同一份 Snapshot，不再只展示“分类与支出活动”几个字。
- 小组件点击意图补齐：原生侧 `MainActivity` 透传 `feimiao_category_id`；Flutter `ShareIntake` 现在支持 `statistics`、`statistics_categories`、`statistics_category`，点击分类行会进入当月该分类明细，点击“查看所有”进入统计页。
- 图表 bitmap 调整：浅灰完整月柱更浅，历史同进度柱略提亮，当前月继续蓝色；生成高度改为 62dp，对齐新布局，平均线颜色改为更柔的灰并略加粗。
- 补充回归测试：`桌面小组件快照：附着式退款按净额输出`，确保小组件本月支出、今日支出、分类占比和进度模块都按退款后净额输出。
- 已通过：`dart analyze lib\share_intake.dart lib\core\widgets\widget_snapshot_service.dart test\app_repository_test.dart`；`flutter_tools.dart test test\app_repository_test.dart --no-pub`，44 项全通过。
- 版本已递增到 `1.149.0+151`：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart` 已更新，build tag 为 `b0708-151`。APK 构建与验签结果待本节后续补齐。

## 2026-07-08 月报精简 Prompt + AI 记账返回键修复 / 1.148.0+150

- 月报/周报/年报生成 Prompt 收敛：`LlmQuery.askReport()` 从“完整长文档、至少 900 字”调整为“手机可读的精简分析报告”，全文目标 `900-1300` 中文字符，固定输出 `本月一句话 / 核心指标 / 支出结构 / 值得确认的账单 / 下阶段建议`。其中 `本月一句话` 要求 `120-180` 字，先给总支出与对比、主要变化来源、最值得确认或优化的一点。
- 报告分析口径加强：强制区分 `固定/周期支出`、`一次性大额支出`、`日常可控支出`，避免把房租、保险、还款、校园支付等周期性或一次性事件误写成日常消费失控；如果分类可能影响判断，必须写“建议确认分类”。
- 报告语气降焦虑：禁止无证据使用“恶化、暴跌、暴涨、紧张、风险很大、严重”等高压词；建议必须包含金额、阈值、触发条件或分类动作，不允许“理性消费/合理规划”空话。`temperature` 从 `0.35` 降到 `0.25`，`max_tokens` 从 `4096` 收到 `2400`，减少长文漂移。
- 报告卡片摘要提取优化：`_reportSummary()` 和报告库重新生成时的 `_reportSummaryFromMarkdown()` 优先读取 `## 本月一句话` 或 `## 摘要` 段落，最多展示 `160` 字；如果没有该段落才回退到旧的全文清洗截断。
- AI 记账 Android 返回键修复：此前为了防止键盘异常掉线，`didChangeMetrics()` 和 keyboard reconnect 会把“用户按系统返回键收起输入法”误判成异常关闭并重新 `TextInput.show()`，导致用户手机返回键无法退出键盘。本次改为：键盘正常打开过后，系统收起键盘即视为用户意图，清理输入会话、取消保活、不再自动拉起；重新点输入框仍会再次弹出键盘。
- AI 记账路由增加 `PopScope`：系统返回键进入 `_handleSystemBack()`，键盘/输入会话存在时只收键盘；键盘已关闭时再退出半屏。点击空白仍保持原行为：非全屏 AI 记账直接回主页，全屏喵助手只收键盘。
- 回归测试更新：`AI input respects system keyboard dismissal after startup` 和 `AI input keeps keyboard dismissed after a delayed system close` 覆盖系统/返回键收起后不得重连；保留“启动不丢焦点”“视觉层 settle 不重建输入框”“重新点击可再弹键盘”等测试。
- 已通过：`dart analyze lib\views\home\ai_chat_panel.dart lib\core\ai\llm_query.dart lib\views\reports\report_views.dart test\ai_chat_panel_focus_test.dart test\ai_chat_record_serialization_test.dart`；`flutter_tools.dart test test\ai_chat_panel_focus_test.dart test\ai_chat_record_serialization_test.dart --no-pub`，16 项全通过。
- 版本同步升级到 `1.148.0+150`：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart` 已更新，build tag 为 `b0708-150`。`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.148.0-150.apk` 已构建，大小 `110,669,185` 字节，SHA256：`188AFEF009B56569CD02A255BF83B6FCC6F2D6EDFD9AB440320F33F092BE0F8E`。已通过 `aapt dump badging` 和 `apksigner verify --print-certs`。
## 2026-07-08 AI 记账键盘自动收回根因修复 / 1.147.0+149

- 用户反馈 `1.146.0+148` 中 AI 记账点击输入框后键盘仍会在几秒后自动收回。本次重新定位链路：主页输入框现在进入 `showRecordEntrySheet()`，半屏 host 内嵌 `AiChatPanel`；真正风险点不是单纯重连窗口太短，而是 `_inputFocusGuardUntil` 约 3.6 秒后结束时，`_settleVisualsReady()` 会把 `_visualsReady` 切为 true，进而通过 `ValueListenableBuilder` 重建包着 `TextField` 的 `_inputBox`/`GlassSurface`/`BackdropFilter`。Android/Xiaomi 上焦点可能还在，但 IME input connection 会被这个延迟视觉层切换打断，表现为“键盘过几秒自己收回”。
- 修复策略：输入框不再监听 `_visualsReady` 来切换自身 `blurEnabled`，`TextField` 外层玻璃容器保持稳定；`_settleVisualsReady()` 新增 `_inputConnectionCritical` 判断，只要输入会话仍 active 且焦点/键盘/保护期仍存在，就不切换会影响输入连接的视觉层；对话态高度判断也纳入 `_inputSessionActive`，避免保护期结束后面板从键盘态缩回半屏态。
- 键盘保活同步加强：`didChangeMetrics()` 在输入会话仍有效时，如果检测到 inset 已经回到 0，会走 `_scheduleKeyboardReconnect()`；如果键盘仍开，则主动 `TextInput.show` 保持输入法连接。空白点击仍按既定语义关闭半屏/回到主页，发送、切换手动、关闭面板会清理输入会话。
- 新增回归测试 `AI entry sheet does not swap input blur after focus settles`：打开 AI 半屏后等待超过 4.2 秒，校验输入框 `GlassSurface.blur` 没有延迟切换、`FocusNode` 未被替换、测试输入法仍可见。并保留原有 IME 掉线重连、Android 抢焦点、半屏自动聚焦等测试。
- 已通过：`dart analyze lib\views\home\ai_chat_panel.dart test\ai_chat_panel_focus_test.dart`；`flutter_tools.dart test test\ai_chat_panel_focus_test.dart --no-pub`，10 项全通过。
- 版本同步升级到 `1.147.0+149`：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart` 已更新，build tag 为 `b0708-149`。
- 已构建 APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.147.0-149.apk`，大小 `110,652,801` 字节，SHA256：`D5786AC9A9B2AC0FEAC2DAE84A66965AFAFE207DC99541070C1E15460BD3EF04`。同目录已写入 `.sha256.txt`。
- 已通过 `aapt dump badging`：包名 `com.qingji.qingji.codex`，`versionCode=149`，`versionName=1.147.0`，应用名 `肥喵记账`。已通过 `apksigner verify --print-certs`，证书仍为 `CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`。

## 2026-07-08 AI Provider / API Key 切换（DeepSeek + 自定义中转站）

- 新增 `lib/core/ai/ai_provider_config.dart`：统一描述当前 AI 服务配置，支持 `DeepSeek` 官方和 `自定义` OpenAI 兼容接口。DeepSeek 仍是默认 provider，默认 base URL 为 `https://api.deepseek.com`，主模型 `deepseek-v4-flash`，问账/报告保留 `deepseek-chat` 兼容降级；自定义 provider 默认 `https://api.openai.com/v1` + `gpt-4o-mini`，用户可改为 GPT 中转站、OpenRouter、硅基流动等兼容地址。
- `AppRepository` AI 设置升级：保留旧 `deepseek_api_key` 兼容读取和 `deepSeekApiKey` getter；新增 `aiProviderType`、`customAiApiKey`、`customAiBaseUrl`、`customAiModel`、`aiProviderConfig`、`hasAiApiKey`。DeepSeek key 与自定义 key 分开存储，正式 Android 仍通过 `SecureKeyStore`/Keystore 保存；桌面测试 fallback 写入 `app_settings` 时，备份净化会同时排除 `deepseek_api_key` 和 `custom_ai_api_key`。
- AI 设置页重写为“模型供应商”切换：DeepSeek / 自定义两个选项；自定义模式展示 Base URL 和模型名；新增“测试连接”，只发 `ping` 类短请求，不带账本数据。保存 provider 或自定义 Base URL 变化后会重置 AI 隐私确认，下次联网 AI 调用需重新确认。
- 所有 AI 调用入口已统一走 `repo.aiProviderConfig`：首页 AI 记账解析、喵助手问账、报告生成/重新生成、快捷 AI 记账、导入复核 AI 归类。不再有页面只认 DeepSeek key。
- AI 隐私弹窗文案改为读取当前 provider 名称；用户能明确知道账本上下文会发给 DeepSeek 还是自定义服务。关于页/备份页原有“备份不含 API Key”说明继续有效。
- 验证：已通过 `C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe analyze` 检查本次相关 11 个文件，结果 `No issues found!`。
- 版本同步升到 `1.146.0+148`：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart` 已更新，build tag 为 `b0708-148`。
- 已构建 APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.146.0-148.apk`，大小 `110,669,185` 字节，SHA256：`2B9EAF70026FBDC65F6EC7E4AEF145047436E9217067C3F9D917C1974D9D8EB7`。同目录已写入 `.sha256.txt`。
- 已通过 `aapt dump badging`：包名 `com.qingji.qingji.codex`，`versionCode=148`，`versionName=1.146.0`，应用名 `肥喵记账`。已通过 `apksigner verify --print-certs`，证书仍为 `CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`。

## 2026-07-08 AI 记账输入法延迟收起修复

- 定位原因：AI 记账输入框此前为了解决“小米/Android 键盘弹不出或闪退”叠加了 `focus guard`、`keyboard reconnect`、`visualsReady` 延迟模糊层和 `TextField.onTapOutside` 多套保护。旧逻辑只把输入保护维持约 `1600ms`，保护窗口结束后，如果模糊/动画层收尾重建或 Flutter 误触发 `onTapOutside`，键盘可能在几秒后自动收回。
- 修复策略：新增显式 `_inputSessionActive` 输入会话状态。用户点击输入框后，输入会话一直保持到明确动作发生：发送、切换手动记账、关闭/点空白退出；不再依赖固定 1.6 秒窗口判断用户是否还在输入。
- 键盘恢复策略：如果输入会话仍然有效、焦点仍属于 AI 输入框，而系统/布局在打开后数秒内把 IME 收掉，会继续通过 `_observeKeyboardInset()` 触发重连；重连窗口已从短窗口继续放宽到 `60s`，重连/焦点修复次数提高到 12 次，并在键盘打开时重新武装窗口，避免“几秒后自动收起”。
- 移除 `TextField.onTapOutside` 对输入意图的隐式清理；空白处关闭只走 `_handleBackdropTap()`，避免 Stack/透明层/AnimatedPositioned 重建造成外部点击误判。
- 明确空白点击语义：非全屏首页 AI 面板点击空白会清理输入会话、收键盘并关闭面板；全屏喵助手点击空白只清理输入会话并收键盘。
- 新增回归测试 `AI input restores keyboard after a delayed IME drop`，覆盖键盘打开约 3 秒后被系统/布局隐藏时必须恢复；历史测试曾通过 `flutter test --no-pub test\ai_chat_panel_focus_test.dart`，本次改动后已通过相关文件 `dart analyze`，仍建议 APK 后用小米 15 Pro 真机复测输入法是否稳定停留。

## 2026-07-08 项目体积整理 / 缓存清理

- 本次只整理 `C:\src\xunni-codex`，未触碰 `C:\src\xunni` 或 Claude 分支。整理前 `android-app` 约 `4.15GB`，主要膨胀来自 Flutter/Gradle 可再生成产物：`android-app/build` 约 `3.66GB`、`android-app/.dart_tool` 约 `442MB`。
- 清理前已保留最新 release APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.145.0-147.apk`，SHA256 为 `84096B8B3ABC105284BAC6845D0082B8227BF5D19D9AE1090C1EE378F98F8078`，同目录有 `.sha256.txt` 校验文件。
- 已删除可再生成缓存：`android-app/.dart_tool`、`android-app/android/.gradle`、大部分 `android-app/build`，并清理临时日志/测试残留：qemu 日志、`flutter_01.log`、`assets/mascot/_writetest.tmp`、根目录空日志 `analyze_verbose.log`。
- 整理后 `C:\src\xunni-codex` 约 `160.5MB`；其中 `ci-artifacts` 约 `109.2MB` 主要是保留的最新 APK，`android-app` 约 `15.3MB`，源码/资源本体很小。`android-app/build` 仍有约 `0.153MB` 的 Windows/Flutter transform 残留空壳，体积可忽略，下次构建会重新生成。
- 忽略规则补充：新增根目录 `.gitignore` 忽略 `*.log`；`android-app/.gitignore` 新增 `.gradle/`，避免未来 app 目录下 Gradle 缓存进入 Git 状态。已有规则继续忽略 `build/`、`.dart_tool/`、`android/.gradle/`。

## 2026-07-08 小组件 P0 重构出包 / 1.145.0+147

- 按 `outputs/feimiao_widget_optimization_prd_v1_1_apple_review_grade.md` 推进小组件 P0 第一版：Dart 侧新增 `schemaVersion=2` 的小组件 snapshot，输出 `modules.overview / modules.quickAdd / modules.pace / modules.categories`，同时保留 V1 fallback 顶层字段，避免旧 Provider 或旧小组件升级后空白。
- 小组件数据口径加固：总览模块按“无预算=本月支出；有预算=预算剩余”输出一级信息；本月进度模块输出最近 6 个历史月 + 当前月的 `fullValue / sameProgressValue`，支持后续柱状图；分类模块按一级分类聚合，缺失分类统一为一个“其他”，颜色改为按一级分类 key 稳定映射，不再按排行临时轮换。
- Android Provider 改为优先读取 V2 `modules`，未知/缺失时回退 V1 字段；四个小组件都补充基础 contentDescription。`肥喵本月进度` 改为 Kotlin Canvas 生成柱状图 bitmap：历史完整月浅灰、历史同进度深灰、当前月蓝色、平均线在图表内绘制，并避免 `fitXY` 非等比拉伸。Provider 继续保留空数据/无 snapshot 的兜底状态。
- 小组件 XML 同步调整：快捷记账去掉重 bold，补 `widget_quick_title`；本月进度卡新增 `widget_budget_chart`，删除旧两条 progress bar 的渲染依赖；分类活动卡补标题 id、底部细线和“查看所有”入口；小组件名称从“肥喵记账总览”改为“肥喵总览”。
- 版本同步升到 `1.145.0+147`：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart` 已更新，build tag 为 `b0708-147`。
- 已通过：`flutter analyze --no-pub`；`flutter_tools.dart test --no-pub test\app_repository_test.dart`，43 项全绿；`flutter build apk --release --no-pub`。
- 已构建 APK：`build/app/outputs/flutter-apk/feimiao-codex-v1.145.0-147.apk`，大小 `110,571,189` 字节，SHA256：`84096B8B3ABC105284BAC6845D0082B8227BF5D19D9AE1090C1EE378F98F8078`。
- 已通过 `aapt dump badging`：包名 `com.qingji.qingji.codex`，`versionCode=147`，`versionName=1.145.0`，应用名 `肥喵记账`。
- 已通过 `apksigner verify --print-certs`：签名证书仍为 `CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`。
- 尚未完成小米 15 Pro 真机桌面截图验证；用户安装后需重点检查：小组件添加页预览、桌面实际尺寸、柱状图是否清楚、平均线位置、分类卡“查看所有”是否裁切、点击加号是否进入记账。

## 2026-07-08 定时记账优化出包 / 1.144.0+146

- 本次出包包含 2026-07-08 未出包的 P0/P1/P2 数据修复、统计页“截至今日进度 / 分类与支出活动”UI 调整，以及定时记账完整优化：结束日期、记录次数、已记录情况、规则到账本选择、自动账单 `recurring_rule_id` 关联。
- 版本同步升到 `1.144.0+146`：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart` 已更新，build tag 为 `b0708-146`。
- 已通过：`flutter analyze --no-pub`、`flutter_tools.dart test --no-pub test\app_repository_test.dart`，43 项全绿。
- 已构建 APK：`build/app/outputs/flutter-apk/feimiao-codex-v1.144.0-146.apk`，大小 `110,554,593` 字节，SHA256：`988B7C82894AFE94BA220430686269BB3FEEE9ABF2D94357B8DCB18C08FF76E5`。
- 已通过 `aapt dump badging`：包名 `com.qingji.qingji.codex`，`versionCode=146`，`versionName=1.144.0`，应用名 `肥喵记账`。
- 已通过 `apksigner verify --print-certs`：签名证书仍为 `CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`。
- 构建时 Flutter 提示 `charset_converter`、`share_plus` 插件仍使用旧 Kotlin Gradle Plugin 应用方式；这是未来 Flutter 版本兼容性 warning，本次 release 构建未失败。

## 2026-07-08 P0/P1/P2 复查修复（已并入 1.144.0+146）

> 状态更新：本节内容已并入 `1.144.0+146` 出包；保留本节是为了让 Claude 看到具体修复范围。

- 按用户要求复核 P0/P1/P2 数据正确性问题，确认并修复：仓库层 `refundTransaction()` 现在拒绝超额退款、非正数退款、对退款行再次退款、找不到原始支出等非法调用，避免 UI 之外的路径写坏净额。
- 账单导入继续加固退款归属：第三方账单导入如果按订单号/启发式匹配到原单，但退款金额超过原单剩余可退金额，会作为独立退款收入保留，不再强行挂回原单；肥喵 CSV 恢复遇到历史 `refunded` 或显式退款行超过原单剩余金额时会跳过异常退款，避免导入后出现“退款大于原支出”的错误净额。
- 备份恢复加固完整性校验：备份包内 `manifest.json` 已有 SHA256 checksums 时，恢复前逐项校验 DB 和收据文件；校验失败会中止恢复，避免损坏/被篡改包覆盖本地数据。
- 资产 JSON 导入导出修复跨库账户引用：权益收回的到账账户、负债档案账户/还款账户导出时同时写账户名，导入时优先按账户名映射，只有旧 JSON 没有名称时才回退本地数字 ID，避免不同数据库 ID 不一致导致资产流水挂错账户。
- 定时记账补齐用户要求的终止逻辑：数据库版本从 `29` 升到 `30`，`recurring_rules` 新增 `start_date_ms`、`end_date_ms`、`total_count`、`generated_count`；`transactions` 新增 `recurring_rule_id`，新生成的定时账单可追溯到具体规则。自动补记现在支持“结束日期（包含当天）”和“记录次数”，达到终点后不再无限生成。
- 定时记账支持明确选择“记录到账本”：Repository 的新增/编辑规则接口支持显式 `bookId`，不传时仍保持旧逻辑写入当前账本；表单新增“账本”选择项，规则卡片副标题也展示账本名，生成账单会稳定落到目标账本。
- 定时记账编辑页去掉容易误解的“未来 3 次”卡片，新增“结束方式：不限 / 结束日期 / 记录次数”。已有规则展示“已记录情况”，包含开始日期、已记录/总次数、状态，以及最近几笔由该规则生成的账单行；账单行复用主页 `TxRow` 标准，避免新增一套列表样式。
- 保留此前月末锚点修复：编辑已有规则时 `anchor_day` 优先使用开始日期日号，不会因为下次执行日曾被 2 月夹到 28 号而丢失 31 号锚点。
- 复核结论：同文件两笔完全相同公共交通 2.5 元只导入一笔的问题，当前已有回归测试覆盖并通过；本机备份仅保留最新 3 份已存在且测试通过；资产账单关联仍以 `transaction_uuid`/唯一 ID 为真实来源，没有回退到名称金额去重。
- 已通过：`dart format lib/core/models/recurring_rule.dart lib/data/app_repository.dart lib/views/settings/recurring_view.dart test/app_repository_test.dart`；`dart analyze lib/data/app_repository.dart lib/views/settings/recurring_view.dart test/app_repository_test.dart`；`flutter_tools.dart test --no-pub test\app_repository_test.dart`，43 项全绿。已随 `1.144.0+146` 构建 APK；尚未做真机/模拟器 UI 截图验证。

## 2026-07-08 143 后 UI 修复（已并入 1.144.0+146）

- 统计页“截至今日进度 / 分类与支出活动”卡继续对齐用户给的 iOS 电池参考：顶部标题字号从 15 降到 14；“平均/本月”下方金额字号从 22 降到 18；本月标签与金额、当前月份柱状图统一使用 iOS 蓝 `0xFF0A84FF`；当前柱底部不再写“本月”，改为实际月份如 `7月`。平均线改为贯穿图表的 2.25px 线，粗度比原 1.5px 增加 50%，平均文字移到线右端上方。柱状图浅灰背景再浅一些，柱体圆角从胶囊改为小半径矩形四角圆弧。分类前三下面增加细分割线，并新增“查看所有支出活动 >”入口，点击进入全部支出活动明细。已通过：`dart format lib/views/statistics/statistics_view.dart` 和 `dart analyze lib/views/statistics/statistics_view.dart`；已随 `1.144.0+146` 构建出包，尚未做真机截图验证。

## 2026-07-07 143 后 UI 修复（已并入 1.144.0+146，仍需真机复测）

- 资产管理内表单选择弹窗统一为现有 iOS 浮层菜单标准：新增/编辑实物资产、权益资产、出售/收回资产、账户负债详情中复用的枚举、账户、分类、历史账单选择器，不再使用 Flutter 默认 `DropdownButtonFormField` 大白列表。
- `showIosMenu()` 保持默认调用不变，新增可选 `width`、`alignToAnchorLeft` 和浮层内部滚动能力；资产表单选择器按输入框宽度左对齐弹出，列表过长时只在菜单内部滚动，保留圆角、玻璃底、细分割线和紧凑行高。
- `IosMenuItem` 新增可选 `selected` 状态，资产选择菜单打开后在当前选中项右侧显示对勾；其它未传 `selected` 的旧菜单视觉不变。
- 选择框入口新增 `_IosPickerField`，外观继续对齐现有 `iosInputDecoration`：浅灰圆角底、14sp/w400 文本、浅灰 hint、右侧小下箭头，避免入口样式和表单 TextField 割裂。
- 已执行：`dart format lib/widgets/ios_menu.dart lib/views/settings/accounts_view.dart`；已通过：`C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe analyze lib/widgets/ios_menu.dart lib/views/settings/accounts_view.dart`，结果 `No issues found!`。本节改动已随 `1.144.0+146` 构建出包；资产弹窗仍需模拟器/真机截图验证。
- AI 记账点击输入框后输入法弹出又瞬间收回的问题再次收敛：删除 `_scheduleKeyboardReconnect()` 里的“先 `_focus.unfocus()` 再 32ms 后重连”策略，改成不破坏当前输入连接的软恢复；焦点仍在时只补 `TextInput.show`，焦点真的丢失时才 `requestFocus`。同时将 `_visualsReady` 的模糊/动画层恢复延后到输入保护期结束，避免键盘打开 100-200ms 内重建输入框导致 `TextInput.clearClient` / `TextInput.hide`。键盘 inset 从 0 变为打开时也改为 post-frame 软恢复，等本帧 TextField 稳定后再补键盘显示。已通过：`dart analyze lib/views/home/ai_chat_panel.dart test/ai_chat_panel_focus_test.dart` 和 `flutter_tools.dart test --no-pub test/ai_chat_panel_focus_test.dart`，8 项全绿；已随 `1.144.0+146` 构建出包，仍需小米 15 Pro 真机复测输入法是否稳定停留。

## 2026-07-07 UI 修复 / 1.143.0+145

- 半屏弹窗全局头部 `SheetHeader` 修正视觉平衡：关闭按钮和右侧保存/确认按钮统一按 `12dp` 边距落位，按钮尺寸保持 `34dp`，标题栏高度改为 `58dp`，使按钮到顶部的距离等于到左右边界的距离。影响范围包括新增定时记账、账本、预算、资产、日期确认等所有复用 `SheetHeader` 的弹窗。
- 本机备份统一改为默认只保留最新 3 份：自动备份、手动“立即备份”、升级前备份、恢复前兜底备份都会进入同一套清理规则；打开备份页时也会顺手清理旧备份。备份列表标题不再展示“数据库 vXX”，升级前备份只显示“升级前备份”；“立即备份”按钮删除前置图标，改为纯文字按钮。
- 喵助手报告卡片底部操作区改为复用普通 AI 回复的同一套 `_ClaudeActionButton` 样式和 Lucide 图标：复制、点赞、点踩、重新生成四个按钮保持一致，不再只有单独一个报告复制按钮。报告消息现在会保存并恢复原始问题，历史报告也能拿到重新生成回调；重新生成时显示“喵在想”，并原地刷新同一份 `report.id` 的标题、摘要和 Markdown 内容，不会在报告库里额外生成重复报告。
- 主页 AI 记账点击输入框后的键盘启动链路做性能优化：移除原先 `fastSwitch` 下约 `260ms + 50ms` 的人为焦点延迟，改为路由首帧立即 `requestFocus` 并显式调用 `TextInput.show`；输入框玻璃模糊、猫猫动画、历史聊天恢复、个性化建议扫描延后到键盘启动后执行，避免导入大量账单后首帧抢主线程。视觉效果保留，只是从键盘首帧解耦。
- 主页 AI 记账半屏状态下，点击上方空白区域现在会清除输入焦点并直接关闭 AI 面板，回到初始主页输入框；不再只收起键盘后停留在猫猫/建议/输入框半屏界面。全屏喵助手仍保留原来的空白处先收键盘逻辑。
- 资产管理页所有 `showModalBottomSheet` 弹窗统一启用 `useSafeArea: true`，修复“添加实物资产”等键盘弹起后头部关闭/保存按钮顶到状态栏的问题；同时覆盖新增账户、权益资产、资产详情、更新价值、出售资产、凭证、折旧设置等同类弹窗。
- 版本同步为 `1.143.0+145`：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart` 已更新，build tag 为 `b0707-145`。
- 已通过：`flutter analyze --no-pub`、`flutter build apk --release --no-pub`、`aapt dump badging`、`apksigner verify --print-certs`；备份裁剪测试已通过 `test/app_repository_test.dart --plain-name "本机备份列表默认只保留最新 3 份"`。
- 已构建 APK：`build/app/outputs/flutter-apk/feimiao-codex-v1.143.0-145.apk`，大小 `110,669,069` 字节，SHA256：`E604E9ECE36D04B8E8F7D07E78D54E0494C28AD05DC98EC313C4759BA769BB2A`。已通过 `aapt dump badging`：包名 `com.qingji.qingji.codex`，`versionCode=145`，`versionName=1.143.0`，应用名 `肥喵记账`；已通过 `apksigner verify --print-certs`，签名证书仍为 `CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`。

## 2026-07-07 资产管理 P3 / 1.142.0+144

- 按 PRD 推进 P3：数据库版本从 `27` 升到 `28`，新增 `liability_profiles` 负债扩展表，负债详情挂在现有账户上，不迁移账户本体。
- 负债档案字段包含：账户 ID、负债类型、原始金额、剩余本金/当前欠款、年化利率、每月还款日、默认还款账户、起止日期、状态、备注。
- 支持负债类型：信用卡、房贷、车贷、消费贷、其他负债；状态支持还款中、已结清、暂停、已归档。
- 净资产口径补充 P3 负债档案，但避免重复计算：如果账户自身已经是负余额，则以账户负余额计负债；如果账户余额非负但挂了还款中的负债档案，则用档案 `current_principal` 补进总负债。
- 账户编辑页在账户类型为信用卡/贷款时显示“负债详情”区域，可维护原始金额、剩余本金、利率、还款日、默认还款账户、状态和备注；账户列表会展示负债类型和每月还款日摘要。
- 肥喵资产 JSON 导入导出纳入 `liability_profiles`，导入完成提示会显示负债档案数量。
- 版本同步升到 `1.142.0+144`：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart` 已更新。
- 已通过：`flutter analyze --no-pub`、全量 `flutter test --no-pub` 285 项。新增 P3 测试覆盖负债档案保存/还款日计算、正余额账户用剩余本金补充负债、账户负余额已计负债时不重复计入。
- 已构建 APK：`build/app/outputs/flutter-apk/feimiao-codex-v1.142.0-144.apk`，大小 `110,554,381` 字节，SHA256：`16EA46C4BFC589DE185E9A4FEB6B0A4F0884A4454A5DC7D9738BE3008893BF56`。已通过 `aapt dump badging`：包名 `com.qingji.qingji.codex`，`versionCode=144`，`versionName=1.142.0`，应用名 `肥喵记账`；已通过 `apksigner verify --print-certs`，签名证书仍为 `CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`。

## 2026-07-07 资产管理 P2 / 1.141.0+143

- 按 `feimiao_asset_management_prd_v1_1_1_strict.md` 推进 P2：数据库版本从 `26` 升到 `27`，新增 `receivable_assets`、`receivable_recoveries`、`net_worth_snapshots` 三张表，并给 `asset_events` 补充 `asset_type`，避免实物资产和权益资产 ID 相同时事件混淆。
- 权益资产支持类型：租房押金、借出款、应收款、预付卡余额、会员卡余额、保证金、其他权益；状态支持未收回、部分收回、已收回、已损失、已归档。
- 权益资产只按 `remaining_amount` 计入净资产；全部收回、损失、归档后不计入净资产。部分/全部收回会写 `receivable_recoveries` 和 `asset_events(asset_type=receivable)`。
- 权益收回会生成 `excluded=1` 的账户收入流水，用于增加到账账户余额，但不会进入普通收入统计或 `allRecords`；净资产本身不因收回动作变化，只是从“权益资产”转换成“现金/账户余额”。
- 仓库新增统一净资产口径 `currentNetWorthBreakdown()` 和账户余额计算 `accountBalanceOf()`：总资产 = 流动账户正余额 + 投资账户正余额 + 实物资产当前价值 + 权益资产剩余金额；总负债 = 计入净资产账户负余额绝对值。
- 资产管理页新增“资产结构”卡，展示流动资产、投资账户、实物资产、权益资产构成和负债率；支持记录净资产快照到 `net_worth_snapshots`，并可生成本地资产分析报告文档（`reports.type=asset`），后续可接入喵助手/DeepSeek 生成更深的报告正文。
- 资产管理页新增“权益资产”分组，支持添加/编辑、详情、收回、归档/恢复、标记损失；新增资产入口从“账户/实物资产”扩展为“账户/实物资产/权益资产”。
- 肥喵资产 JSON 导入导出扩展到权益资产、收回历史和净资产快照；导入按唯一 `uuid` 更新，不按名称金额去重，因此同名同金额押金/借出款不会被合并。
- 导入导出页文案从“实物资产”扩展为“实物资产 + 权益资产”，导入完成提示会显示权益资产和收回历史数量。
- 版本同步升到 `1.141.0+143`：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart` 已更新。
- 已通过：`flutter analyze --no-pub`、全量 `flutter test --no-pub` 283 项。新增 P2 测试覆盖权益资产按剩余金额计净资产、部分收回不进普通收入且净资产不变、全部收回后不计权益净资产、同名同金额权益资产导入不合并。
- 已构建 APK：`build/app/outputs/flutter-apk/feimiao-codex-v1.141.0-143.apk`，大小 `110,456,073` 字节，SHA256：`A4ACFD7A63B6E4A5F88C04D10B2A81F0EAF1A07C7023F85A69227F8F14A4A29D`。已通过 `aapt dump badging`：包名 `com.qingji.qingji.codex`，`versionCode=143`，`versionName=1.141.0`，应用名 `肥喵记账`；已通过 `apksigner verify --print-certs`，签名证书仍为 `CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`。

## 2026-07-07 资产管理 P1 / 1.140.0+142

- 按 `feimiao_asset_management_prd_v1_1_1_strict.md` 落地实物资产 P1：数据库版本从 `25` 升到 `26`，新增 `physical_assets`、`asset_events`、`asset_valuations`、`asset_transaction_links` 四张表。
- `asset_transaction_links` 是资产和账单关系的唯一真实来源；`asset_events` 只记录资产生命周期事件，不保存交易 ID。
- 新增实物资产来源：历史已有补录、从已有账单加入、新购买同时记账、别人赠送、继承/转入、其他来源；“其他来源”在高价值/有购买价时会二次确认，避免误把新消费当补录。
- 新增资产状态：使用中、闲置、已出售、已报废、已丢失、已赠送、已归档。归档不归零，但不计入净资产；出售/报废/丢失/赠送会把当前价值归零并移出净资产。
- 资产出售会生成 `excluded=1` 的账户收入流水并写 `sale_account_movement` 关联，用于账户余额变化，但不会进入普通收入统计或 `allRecords`。
- 资产管理页在原账户总览基础上增加“实物资产”分组，支持添加/编辑、详情、更新当前价值、出售、归档/恢复。顶部净资产、总资产已纳入计入净资产的实物资产当前价值。
- 肥喵自有导出现在同次分享账单 CSV 和资产 JSON；资产 JSON 包含四张资产表，导入时按唯一 `uuid` 更新，不按名称/金额去重，因此同名同金额资产不会被合并。
- 版本同步升到 `1.140.0+142`：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart` 已更新。
- 已通过：`flutter analyze --no-pub`、全量 `flutter test --no-pub` 279 项。新增资产 P1 测试覆盖历史补录不生成收支、新购买生成支出、从已有账单加入不重复流水、出售不进普通收入、归档不归零但不计净资产、同名同金额资产导入不合并。
- 已构建 APK：`build/app/outputs/flutter-apk/feimiao-codex-v1.140.0-142.apk`，大小 `109,882,109` 字节，SHA256：`93F7F471F0F34500115A10118626A33FC9890E01D4BBE7906B32694DE5E0E085`。已通过 `aapt dump badging`：包名 `com.qingji.qingji.codex`，`versionCode=142`，`versionName=1.140.0`，应用名 `肥喵记账`；已通过 `apksigner verify --print-certs`，签名证书仍为 `CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`。


## 1. 硬性边界

- 只在 `C:\src\xunni-codex\android-app` 工作。
- 不要修改 `C:\src\xunni`，这是 Claude 原本的本地项目。
- 不要影响 Claude 在 GitHub 上已有的分支和提交。
- 当前 Codex 分支：`codex/feimiao-p0-fixes`。
- Codex 版本必须保持可与 Claude 版本同时安装：
  - Android 包名：`com.qingji.qingji.codex`
  - 签名证书：`CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`
  - 应用显示名：`肥喵记账`

## 2. 当前交付状态

- 当前源码版本：`1.151.0+153`
- 当前 APK 版本：`1.151.0+153`
- build tag：`b0708-153`
- APK 路径：待构建
- APK SHA256：待构建
- 版本文件：
  - `pubspec.yaml`：`1.151.0+153`
  - `lib/core/app_version.dart`：`1.151.0 (153)`
  - `lib/build_info.dart`：`b0708-153`
- 当前验证状态：`dart analyze lib\views\home\ai_chat_panel.dart test\ai_chat_panel_focus_test.dart` 通过；`flutter_tools.dart test --no-pub test\ai_chat_panel_focus_test.dart` 10 项全绿；`flutter build apk --release --no-pub`、`aapt dump badging`、`apksigner verify --print-certs` 均通过。

### 2.1 历史交付摘录（旧记录，非当前状态）

> 以下是旧交付流水，可能保留当时“未出包/尚未验证”的原始描述；不代表当前 `1.148.0+150` 状态。

- 1.138.0+140：按用户要求构建交付版，版本号从 `1.137.0+139` 递增到 `1.138.0+140`，同步更新 `pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart`。本轮 APK 包含此前 139 后未出包的自动记账去重、定时记账持久化测试补充、主页统计胶囊、统计页“截至今日进度”文字层级、统计图表库开关灰色放大和回弹修复、金额显示弹窗过渡/裁切修复、喵助手底部操作按钮调整、搜索页顶部浮层虚化修复等改动。常规 `flutter analyze --no-pub` 和 `flutter build apk --release --no-pub` 通过 `flutter.bat` 入口启动时卡在 bat 包装层，本轮已终止卡住进程并改用 `dart.exe flutter_tools.snapshot build apk --release --no-pub` 成功构建。已通过 `aapt dump badging` 校验包名 `com.qingji.qingji.codex`、versionCode `140`、versionName `1.138.0`、应用名 `肥喵记账`；已通过 `apksigner verify --print-certs` 校验签名证书 `CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`。APK：`build/app/outputs/flutter-apk/feimiao-codex-v1.138.0-140.apk`；SHA256：`0750E7CA437172776A8741E76BE7E174456EEEFB1A78F086DE6779649D151387`。本轮未完成 `flutter analyze`/测试套件，未做模拟器/真机截图验证。
- 2026-07-07 140 后未出包 UI 小改：主页预算大卡片内“支出 / 收入”指标按用户截图调整为“收入 / 支出”顺序，并让两列内部左对齐，不再居中散开；实现上只给 `_SummaryMetric` 新增可选对齐参数，默认仍保持居中，避免影响其他调用场景。已通过 `dart format lib\views\home\home_view.dart` 和 `dart analyze lib\views\home\home_view.dart`；本条尚未构建 APK，尚未做模拟器/真机截图验证。
- 1.137.0+139：按用户要求构建交付，并在构建前修复一处定时记账月末日期锚点迁移的编译问题。`recurring_rules` 数据库版本升级到 v25，新增 `anchor_day` 字段，月度/年度定时记账按原始起始日作为锚点推进，避免 1 月 31 日到 2 月 28 日后继续漂移成 3 月 28 日；迁移测试同步校验 `anchor_day`。本轮还包含此前未出包的导出范围半开区间修复、金额显示设置持久化测试、统计页“支出构成/分类排行”字重和进度条背景微调。已通过 `flutter test --no-pub test\export_range_test.dart test\app_repository_test.dart test\recurring_rule_test.dart test\statistics_engine_test.dart test\money_format_test.dart`、`flutter analyze --no-pub`、`flutter build apk --release --no-pub`、`aapt dump badging`、`apksigner verify --print-certs`。APK：`build/app/outputs/flutter-apk/feimiao-codex-v1.137.0-139.apk`；SHA256：`7AF21C1861387BCB9F743D96C74F1FFBF928B198FCA22D35A52D36EF2074652D`；包名 `com.qingji.qingji.codex`，应用名 `肥喵记账`，签名证书 `CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`。本轮未做模拟器/真机截图验证。
- 2026-07-07 139 后未出包源码改动：继续推进长期目标中的“自动记账完善”和“定时记账可靠性”。`AutoRecord.drain()` 现在会在 Dart 层对同批通知候选做保守二次去重：只有同 app、同方向、同金额、规范化文本相同且时间相差 15 秒以内的候选才合并，避免微信/支付宝重复 post 的通知进入确认弹窗；同金额同文本但相隔更久的真实连续消费仍会保留。新增 `test/auto_record_test.dart` 覆盖短窗合并、长时间隔保留、不同收支方向保留。`test/app_repository_test.dart` 新增定时记账持久化测试，确认月末起始日写入 `anchorDay`，重启后仍能按原始 31 日锚点预览 1/31、2/28、3/31、4/30。已通过 `flutter test --no-pub test\app_repository_test.dart test\recurring_rule_test.dart test\auto_record_test.dart test\notification_parse_test.dart`；本条尚未构建 APK，尚未做模拟器/真机截图验证。
- 2026-07-07 139 后未出包 UI 小改：主页大卡片内“统计 >”从透明文字入口改为紧凑白底胶囊，仅包裹“统计”和向右箭头；尺寸为 26dp 高、左右轻 padding、0.5dp 浅边线和极轻阴影，文字/箭头改为柔和灰色，避免在预算卡片里过于跳色。已通过 `dart format lib\views\home\home_view.dart` 和 `flutter analyze --no-pub`；本条尚未构建 APK，尚未做模拟器/真机截图验证。
- 2026-07-07 139 后未出包 UI 小改：统计页“截至今日进度”卡继续按用户截图降低文字层级。“截至 X月X日...”主句字号减一号、字重降一档；“平均 / 本月”标签和金额字号减一号；“分类与支出活动”标题字号减一号；分类行里的名称、金额、百分比均减一号，分类名称字重降一档。`dart format lib\views\statistics\statistics_view.dart` 已执行；本机 Dart/Flutter analyze 命令本轮启动异常卡住，已终止卡住进程，尚未构建 APK，尚未做模拟器/真机截图验证。
- 2026-07-07 139 后未出包 UI/功能修复：统计页“自定义图表”弹窗列表标题（截至今日进度、支出构成、分类排行等）字号从 12 调到 13，字重从 w300 调到 w400；图表库开关不再复用全局深黑 `AppSwitch`，改为弹窗专用灰色开关，视觉尺寸约放大 20%，动画从 180ms 收到 120ms。修复图表开关状态回弹：弹窗内使用即时本地 `localVisible` 更新，不再每次点击从仓库旧值重算；仓库新增 `hasStatCardOrderConfig` 区分“从未设置过”和“用户明确全关”，避免全关或连续关闭多个图表后恢复默认。新增 `test/app_repository_test.dart` 回归测试覆盖显式全关重启后仍为空。`dart format`、`flutter test --no-pub test\app_repository_test.dart` 本轮均在本机 Dart/Flutter 命令入口异常卡住，已终止卡住进程；本条尚未构建 APK，尚未做模拟器/真机截图验证。
- 2026-07-07 139 后未出包 UI 修复：设置页“金额显示”弹窗改为本地即时状态驱动，点击“两位 / 一位 / 整数”后先更新 UI 再异步保存，恢复 `SlidingSegment` 的滑动过渡；示例金额用 `AnimatedSwitcher` 跟随选择淡入切换；整数取整方式区域用 `AnimatedSize` 展开/收起。底部 sheet 改为 `isScrollControlled`，内容最大高度约 86% 屏高并包进 `SingleChildScrollView`，避免选择“整数”后“直接取整”被底部裁切。`dart format lib\views\settings\settings_view.dart` 本轮仍在本机 Dart 命令入口异常卡住，已终止卡住进程；本条尚未构建 APK，尚未做模拟器/真机截图验证。
- 2026-07-07 139 后未出包 UI 小改：喵助手普通 AI 回复底部操作栏删除“播放”按钮，只保留复制、点赞、点踩、重新生成；Claude 风格线性图标从 19dp 放大到 22.8dp（约 +20%），按钮横向 padding 从 7dp 收到 6dp（约 -15%），让图标更清楚但整体行宽不明显变长。本条尚未构建 APK，尚未做模拟器/真机截图验证。
- 2026-07-07 139 后未出包 UI 修复：搜索页顶部筛选条和支出/收入统计卡从内容流改为浮层，账单列表铺满底层并通过顶部 padding 预留初始位置；上滑时账单会像底部输入框处一样从浮层下方经过，不再被白底区域硬切断。新增 `_SearchTopFrostedFade`，顶部使用和底部输入框一致的渐隐模糊遮罩，控件边缘之外只保留透明/模糊过渡，不再整块遮挡列表。底部 `_SearchBottomFrostedFade` 保留原逻辑。本条尚未构建 APK，尚未做模拟器/真机截图验证。
- 1.136.0+138：按用户要求只做构建交付版，未新增功能改动。版本号从 `1.135.0+137` 递增到 `1.136.0+138`，同步更新 `pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart`。已通过 `flutter analyze --no-pub`、`flutter test --no-pub test\app_repository_test.dart test\app_buttons_widget_test.dart test\export_range_test.dart`、`flutter build apk --release --no-pub`、`aapt dump badging`、`apksigner verify --print-certs`。APK：`build/app/outputs/flutter-apk/feimiao-codex-v1.136.0-138.apk`；SHA256：`4F63F43A47A29F5FFDFA48C82B45BD504AA295EE6746B59D9CBF9B68FF614DAE`；包名 `com.qingji.qingji.codex`，应用名 `肥喵记账`，签名证书 `CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`。本轮未做模拟器/真机截图验证。
- 2026-07-07 未出包源码改动：继续按长期目标做证据式复查和低风险修复。`ExportRange.isAll` 从“任一边界为空即全部”修正为“起止都为空才是全部”，并为半开区间补安全文件名后缀，避免未来扩展导出范围时误判为全量导出或生成文件名崩溃；`test/export_range_test.dart` 新增半开区间回归测试。补充 `test/app_repository_test.dart` 的金额显示设置持久化测试，确认“设置 → 显示 → 金额显示”里的小数位和整数取整方式重启后仍保留，并同步恢复 `MoneyFormat`。统计页继续按用户要求降低“支出构成 / 分类排行”视觉重量：`_SectionCard` 标题、支出构成图例金额、分类排行名称/金额/百分比字重均降一档，分类排行进度条背景从偏深灰改为更浅。已通过 `flutter test --no-pub test\export_range_test.dart test\app_repository_test.dart` 和 `flutter analyze --no-pub`。本条尚未构建 APK。
- 1.135.0+137：继续做 UI 一致性代码审查并出包。运行态截图再次尝试：新建纯英文路径 AVD `C:\tmp\codex-avd\codex_feimiao_ascii.avd`，并复用已有 `codex_ascii_api35`，两次均能启动到 emulator userspace boot，日志显示 WHPX 可用、端口 `5582/5583` 监听，但 adb 始终停在 `offline`，无法进入 `device`，所以仍不能安装 APK 或截图；已清理 emulator/qemu/adb 进程。同步修正 `test/app_repository_test.dart` 的测试名称，明确旧配置迁移是“移除废弃余量图，保留本月进度卡”。自动记账候选弹窗降低过重字重：标题 `w700 -> w600`、候选标题 `w600 -> w500`、金额 `w700 -> w600`，底部“忽略 / 记下这 N 笔”按钮统一为 40dp 胶囊形。资产管理新增/编辑账户弹窗不再使用底部“取消/保存”大按钮，改为全局 `SheetHeader`：左上关闭、中间标题、右上保存；表单内容进入可滚动区域，最大高度约 88% 屏高；期初余额校验修正为“空值默认 0、输入 0 可保存、非法数字禁用保存”。备份页“导出/恢复”卡片底部按钮从 52dp 系统大按钮收成 42dp 胶囊按钮，危险按钮边框和字重也降一档。已通过 `flutter analyze --no-pub`、`flutter test --no-pub test\app_repository_test.dart test\app_buttons_widget_test.dart test\export_range_test.dart`、`flutter build apk --release`、`aapt dump badging`、`apksigner verify --print-certs`。APK：`build/app/outputs/flutter-apk/feimiao-codex-v1.135.0-137.apk`；SHA256：`9F1489509BF2E142AADEA6B2BE1114E06AC44DEAD021EABB74755920C0753D80`；包名 `com.qingji.qingji.codex`，应用名 `肥喵记账`，签名证书 `CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`。
- 1.134.0+136：按长期目标继续复核统计和小组件。统计页彻底移除用户明确不要的“预算余量”卡：删除 `budget` 的注册项、默认显示项、强制插回逻辑和 `_BudgetProgressCard` 死代码；旧配置迁移仍过滤 `pace/budget/budget_cat`，但保留“截至今日进度 / battery”，避免把本月同期进度对比误删。主页月份选择 sheet 中年份字号从 22 降到 18，月份格标题从 17 降到 16，对齐用户“年份减两号、月份减一号”的反馈。本月进度小组件中“平均/本月”标签从 13sp 提到 14sp，金额从 17sp 收到 16sp，平均进度条从 5dp 收到 4dp；分类小组件标题“分类与支出活动”从 12sp 提到 13sp、颜色改为更灰的 `#74777D`，并补一条 0.5dp 细分割线。`docs/2026-07-07_全面复查与执行方案.md` 同步修正当前复核矩阵，明确“删预算余量、保留本月同期进度”。已通过 `flutter analyze --no-pub`、`flutter test --no-pub test\app_repository_test.dart test\app_buttons_widget_test.dart test\export_range_test.dart`、`flutter build apk --release`、`aapt dump badging`、`apksigner verify --print-certs`。APK：`build/app/outputs/flutter-apk/feimiao-codex-v1.134.0-136.apk`；SHA256：`CBB10E634F0B502008E88561DA8DACFF15A4D36A0A2E79FBB41F3354D10C48CE`；包名 `com.qingji.qingji.codex`，应用名 `肥喵记账`，签名证书 `CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`。未做模拟器/真机截图验证。
- 1.128.0+130：修复用户反馈的主页大卡片回归：日期 `2026年7月` 固定为 15sp，小两号；主页大卡片不再渲染左右月份箭头，只保留年月文字和下拉小箭头，左右滑动仍可切月；“统计”按钮从猫图附近的绝对定位恢复到日期右侧同一行，避免被猫挤压或位置下沉。清理上一轮补丁遗留的重复 `_MonthStepButton` 和类外旧代码片段，避免结构不稳定。AI 记账半屏/空态恢复更明显的透明磨砂：根层 blur 调整为 22/16，空态遮罩透明度从 0.62 降到 0.42，输入框玻璃透明度从 0.88 降到 0.78，让主页背景重新以虚化方式透出，同时保留 `RecordInputBar` 在记账弹层打开时隐藏的逻辑，避免两个输入框。已通过 `dart format`、`flutter analyze --no-pub`、`flutter test test\ai_chat_panel_focus_test.dart` 8 项、`flutter test test\app_repository_test.dart` 15 项、`flutter build apk --release`、`aapt dump badging`、`apksigner verify --print-certs`。APK：`build/app/outputs/flutter-apk/feimiao-codex-v1.128.0-130.apk`；SHA256：`8B1C25572C1DA7FF698D70D83B1A3488654C34441175379E7510D1C917EBF3F8`；包名 `com.qingji.qingji.codex`，应用名 `肥喵记账`，签名证书 `CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`。未做真机/模拟器截图验证，需用户安装后重点看主页日期/统计位置和 AI 记账展开后的磨砂透明感。
- 2026-07-07 未出包：修复 AI 记账空态点击后视觉错层问题。`RecordInputBar` 在记账弹层打开期间会临时隐藏自身，避免主页底部假输入框透过半透明磨砂层露出，造成“两个输入框/两个键盘”的错觉；`AiChatPanel` 空态根部磨砂从 12px 提升到 18px，空态遮罩从 0.38 提升到 0.62，输入框玻璃卡和四条建议胶囊的白底透明度同步提高，保证建议、猫和输入框在键盘弹出后仍然清楚。视觉层稳定逻辑改为“输入法仍未完成打开时继续等待；键盘 inset 已出现后允许视觉层进入 ready”，减少模糊层重绘与 Android/MIUI 输入法启动互相打架。新增回归测试 `home record input is hidden while entry sheet is open`。已通过 `dart format`、`flutter test test/ai_chat_panel_focus_test.dart` 8 项、`flutter analyze --no-pub`；本条未构建 APK，未做真机/模拟器截图验证。
- 1.127.0+129：基于上面的 AI 记账浮层/双输入框修复、资产管理 P0 仪表盘增强继续出包。资产管理页从平铺账户列表推进为基础资产仪表盘：顶部新增资产、负债、本月变化，账户按类型分组展示，仍保留账户编辑/删除和期初余额、净资产口径。已通过 `flutter analyze --no-pub`、`flutter test test/ai_chat_panel_focus_test.dart` 8 项、`flutter test test/app_repository_test.dart` 15 项、`flutter build apk --release`、`aapt dump badging`、`apksigner verify --print-certs`。APK 路径：`build/app/outputs/flutter-apk/feimiao-codex-v1.127.0-129.apk`；包名 `com.qingji.qingji.codex`，应用名 `肥喵记账`，签名证书 `CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`。仍未做真机/模拟器截图验证，需用户在小米 15 Pro 上验证 AI 键盘、磨砂、建议显示和资产页视觉比例。


- 1.125.0+127：再次修复“AI 记账点击输入框后输入法弹出瞬间又消失”。本轮复盘认为旧方案仍保留了过多 `TextInput.show` 强制唤起和键盘可见性轮询；在小米/MIUI 的 IME 启动动画期间，应用多次补发 show / 焦点修复可能反而重置输入连接。最新实现移除 `SystemChannels.textInput.invokeMethod('TextInput.show')` 及相关键盘可见性 timer，只保留有限次数的 FocusNode 修复；`didChangeMetrics()` 只在保护期内补回焦点，不再硬拉输入法。空态 AI 记账布局也调整为不再用 `MediaQuery.viewInsets.bottom` padding 挤压整棵面板，而是只让建议区和输入框随键盘高度局部上移，降低 TextField 输入连接被整树重排打断的概率。相关文件：`lib/views/home/ai_chat_panel.dart`、`test/ai_chat_panel_focus_test.dart`。已通过 `flutter analyze --no-pub`、`flutter test test/ai_chat_panel_focus_test.dart` 6 项、全量 `flutter test` 261 项、`flutter build apk --release`、`aapt dump badging`、`apksigner verify --print-certs`；APK 为 `1.125.0+127` / `b0707-127`。仍需用户在小米 15 Pro 真机连续测试 AI 记账输入框，确认输入法稳定停留。
- 1.122.0+124：再次修复“AI 记账点击输入框后输入法弹出又瞬间收起”。本轮把 `_focusKeepAliveTimer` 从持续循环式保活改成有限次数焦点修复；同一个输入会话内只允许最多 3 次受控 `TextInput.show`，并增加 420ms 节流，避免 MIUI/Android 在 IME 启动动画期间被应用反复重建输入连接。用户点击输入框时会取消尚未执行的自动聚焦 timer，并开启新的焦点会话，避免“自动聚焦”和“手动点击”两路同时抢控制权。`_onFocusChanged()` 不再在丢焦回调里立即 post-frame 强拉键盘，而是交给有限修复和键盘可见性检测处理；`didChangeMetrics()` 也只触发检测，不再立即硬拉。已通过 `flutter analyze --no-pub`、`flutter test test/ai_chat_panel_focus_test.dart`、全量 `flutter test` 260 项、release 构建、`aapt`、`apksigner`；版本同步升到 `1.122.0+124` / `b0707-124`。仍需小米 15 Pro 真机安装后连续点击 AI 记账输入框验证键盘是否稳定停留。
- 1.121.0+123：推进目标 4“资产管理学习有数模式”的 P0 数据地基。`accounts` 表升到 v24，新增账户类型、期初余额、是否计入净资产、机构/银行、排序字段；旧账户默认迁移为“现金 / 期初 0 / 计入净资产”，不改变老余额。`AccountEntity` 新增 `AccountType` 枚举和字段映射，`addAccount()` / `updateAccount()` 支持完整账户资料。资产管理页从“账户余额合计”升级为“净资产合计”，余额口径改为“期初余额 + 当前可见账单流水净额”，顶部合计只统计 `includeInNetWorth=true` 的账户；新增/编辑账户表单加入类型胶囊、期初余额、机构、计入净资产开关，并复用全局 `AppSwitch`。新增 repository 测试覆盖账户资产字段持久化，v15→当前迁移测试同步检查新列并确认当前 DB 版本为 24。已通过 `flutter analyze --no-pub`、`test/app_repository_test.dart`、全量 `flutter test` 260 项、release 构建、`aapt`、`apksigner`；版本同步升到 `1.121.0+123` / `b0707-123`。后续仍需真机进入资产管理页截图检查表单比例和列表视觉，并继续做负债中心、资产快照曲线、按账户类型分组与对账功能。
- 1.120.0+122：再次处理“AI 记账点击输入框后输入法弹出又瞬间收起”。复盘后确认 `1.118.0+120` 的“连续检测不到键盘后短暂 `unfocus -> requestFocus` 重建输入连接”在 MIUI 上可能反而把刚弹出的输入法关掉。本次已撤回该策略：`_scheduleKeyboardVisibilityCheck()` 在保护期内如果同一个 AI 输入框仍持有焦点但 `viewInsets.bottom` 暂未更新，只继续对当前输入连接补 `TextInput.show` 并做 `_stabilizeInputFocus()`，不再主动 `_focus.unfocus()`。新增 `AI input does not drop focus during prolonged IME startup` 回归测试，验证 900ms IME 启动窗口内同一个 `FocusNode` 不丢焦点、测试输入法保持可见。已通过 `flutter analyze --no-pub`、`flutter test test/ai_chat_panel_focus_test.dart`、全量 `flutter test` 259 项、release 构建、`aapt`、`apksigner`；版本同步升到 `1.120.0+122` / `b0707-122`。仍需小米/MIUI 真机连续点击 AI 记账输入框验证。
- 1.119.0+121：推进目标 5“导入导出选择导出时必须可选择时间段，不能默认全量导出”的可验证性。新增 `lib/core/export/export_range.dart`，把导出范围的默认选项、日期边界归一化、包含判断、文件名后缀从 UI 私有逻辑抽到核心层；导入导出页改为使用 `ExportRange.presets()`、`range.contains()` 和 `range.fileSuffix`。新增 `test/export_range_test.dart`，覆盖默认第一项为“本月”而不是“全部”、上月整月边界、近 3 个月起点、自定义范围归一到整天和文件名后缀。已通过 `flutter analyze --no-pub`、`test/export_range_test.dart`、全量 `flutter test` 258 项、release 构建、`aapt`、`apksigner`；版本同步升到 `1.119.0+121` / `b0707-121`。后续仍需真机点开导入导出页确认 sheet 视觉和分享流程。
- 1.118.0+120：继续修复 AI 记账点击输入框后输入法弹出又瞬间收起的问题。本轮在既有 1.76s 键盘可见性保护窗口内新增“输入连接重建”兜底：如果连续两次检测到同一个 AI 输入框仍持有焦点、但 Android/MIUI 仍报告键盘不可见，则判断当前输入连接可能已被系统断开；此时只对同一个 `FocusNode` 执行一次短暂 `unfocus -> requestFocus -> TextInput.show`，重建输入连接，后续检查继续走轻量 `TextInput.show`，避免反复重建造成抖动。已通过 `flutter analyze --no-pub`、`test/ai_chat_panel_focus_test.dart`、全量 `flutter test` 254 项、release 构建、`aapt`、`apksigner`；版本同步升到 `1.118.0+120` / `b0707-120`。仍需小米/MIUI 真机连续点击 AI 记账输入框验证键盘是否稳定停留。
- 1.117.0+119：继续推进目标 1“小组件样式对齐主页大卡片”。总览小组件在有预算时新增 `widget_budget_progress` 细进度线，使用现有深灰圆角进度条样式，显示 `budgetProgress`；无预算时该进度线 `GONE`，不占空间，仍保持“支出 / 收入 / 结余 / 今日”的主页无预算双指标结构。`FeimiaoWidgetProvider` 同步设置该进度线的可见性和进度，避免无快照或无预算状态出现空进度条。本轮只改小组件原生布局和 Provider 映射，不改主 App 页面、不改数据库、不碰图标资源。已通过 `flutter analyze --no-pub`、`test/app_repository_test.dart`、全量 `flutter test` 254 项、release 构建、`aapt`、`apksigner`；版本同步升到 `1.117.0+119` / `b0707-119`。仍需真机桌面添加小组件截图确认进度线比例和整体裁切。
- 1.116.0+118：继续修复 AI 记账点击输入框后输入法弹出又瞬间收起的问题，并补齐上一轮未出包的小组件预算态映射。AI 输入面板现在实现 `WidgetsBindingObserver.didChangeMetrics()`：只在用户刚刚点击/自动聚焦输入框后的输入保护期内，监听 Android/MIUI 键盘导致的窗口尺寸变化；如果系统把 IME 刚弹出又收起，但当前仍是 AI 输入框的有效输入意图，则在下一帧补回同一个 `FocusNode` 并再次 `TextInput.show`。键盘可见性检查从 2 次延长到 8 次，每 220ms 覆盖约 1.76s，与现有 1800ms 输入保护期对齐，降低小米/MIUI 首帧动画期间输入连接被收走的概率。本轮同时保留小组件总览预算态的修正：有预算时总览输出“预算剩余 / 支出 / 收入 / 今日”，避免小组件预算态仍用旧的收入/支出顺序。已通过 `flutter analyze --no-pub`、`test/ai_chat_panel_focus_test.dart`、全量 `flutter test` 254 项、release 构建、`aapt`、`apksigner`；版本同步升到 `1.116.0+118` / `b0707-118`。仍需用户真机验证 MIUI 输入法是否稳定停留。
- 1.115.0+117：继续推进目标 3“主页日期/概览对齐咔皮”。本轮对照用户给的咔皮月份选择参考图复核：当前 12 宫格月份 sheet 已基本接近参考；继续修正主页预算态大卡片内的信息一致性。预算态的收支小指标顺序从“收入 / 支出”改为“支出 / 收入”，与无预算态和小组件总览保持一致；`_SummaryMetric` 改为居中展示，避免预算态内部一套左对齐、无预算态一套居中的割裂。预算剩余金额、百分比胶囊、预算总额、圆环金额字重均降低一档，符合用户“减少 w100”的长期标准；右侧预算圆环去掉 `Transform.translate(-8, 8)` 的手动偏移，回到自然居中布局；当月圆环文案从“今日可花”改为“今日可用”，更贴近参考图和预算语义。`flutter analyze --no-pub`、全量 `flutter test` 253 项、release 构建、`aapt`、`apksigner` 均通过；版本同步升到 `1.115.0+117` / `b0707-117`。仍需真机截图确认主页卡片、猫图、筛选条和预算圆环实际比例。
- 1.114.0+116：继续修复 AI 记账点击输入框后输入法弹出又瞬间收起的问题。本次收敛到“打开面板自动聚焦”和“用户点击输入框聚焦”两条路径与视觉模糊层同帧竞争：面板打开后先标记 `_autoFocusPending`，把外层 `BackdropFilter` 和输入卡玻璃模糊延后到自动聚焦已执行或确认跳过之后；`_settleVisualsReady()` 在 pending、已聚焦或输入保护期内都不启用重视觉层，避免 Android/MIUI IME 启动时输入连接被重建打断。输入框点击不再同步硬抢焦点，而是先让 `TextField` 自己建立输入连接，再在下一帧补焦点和 `TextInput.show` 保活。新增 `AI entry sheet keeps keyboard visible after auto focus` 测试，覆盖从首页 AI 模式打开记账面板后的自动聚焦链路。`flutter analyze --no-pub`、`test/ai_chat_panel_focus_test.dart`、全量 `flutter test` 253 项、release 构建、`aapt`、`apksigner` 均通过；版本同步升到 `1.114.0+116` / `b0707-116`。仍需用户真机验证 MIUI 输入法是否稳定停留。
- 1.113.0+115：推进目标 2 的 UI 复核。当前源码统计页图表库已不再注册旧的“预算余量/本月预算”卡片；可确认的剩余问题集中在图表库开关与行标题视觉。`AppSwitch` 改成更明确的状态逻辑：关闭态轨道 `Colors.transparent`，只保留灰色圆点；开启态固定深黑胶囊轨道 + 白色圆点，并用 `AnimatedAlign` 让圆点移动更自然，避免“开/关都是灰底”的误读。统计页“自定义图表”弹层行高从 34 收到 32，标题字号从 12 降到 11，开关区域宽度从 40 调到 44，保证视觉更轻且命中区稳定。`flutter analyze --no-pub` 与 `test/app_buttons_widget_test.dart` 通过；版本同步升到 `1.113.0+115` / `b0707-115`。仍需真机截图确认视觉是否符合用户给的参考图。
- 1.112.0+114：继续修复 AI 记账输入框点击后输入法弹出又瞬间收起的问题。最新定位不是单纯 `viewInsets` 误判，而是焦点保护期内仍可能被 Android/MIUI 输入连接短暂抢走；现在统一在 `_requestInputFocus()`、焦点保活 tick、焦点恢复 post-frame、键盘可见性检查中补 `TextInput.show`，但不再主动 `unfocus`。聊天态面板在输入保护期内把 `_inputFocusGuardActive` 视为 focused，避免瞬时失焦导致半屏高度收缩、进一步触发键盘关闭。`_handleInputPointerDown()` 改为走同一个 `_requestInputFocus(bypassThrottle: true)` 入口，减少分叉。新增/更新 `test/ai_chat_panel_focus_test.dart`，覆盖点击后同一输入框保持焦点、IME 被隐藏后恢复、外部焦点请求后仍保持/恢复 AI 输入框可输入。`flutter analyze --no-pub`、全量 `flutter test` 252 项、release 构建、`aapt`、`apksigner` 均通过；版本同步升到 `1.112.0+114` / `b0707-114`。仍需用户真机验证 MIUI 输入法是否稳定停留。
- 1.111.0+113：继续推进小组件样式目标。总览小组件 `widget_feimiao.xml` 从“单个 31sp 主数字 + 收入/结余/今日三项”的旧结构，改为更接近主页无预算大卡片的双主指标结构：顶部仍是账本/日期/+，中间两列主指标，默认显示“支出 / 收入”，金额 23sp 居中；底部只保留“结余 / 今日”两个辅助指标，字号降到 13sp，降低信息密度。预算态由 `FeimiaoWidgetProvider` 写入“预算概览 / 预算剩余 / 收入”，底部辅助变为“支出 / 今日”，保持有预算时主看预算剩余。新增 `widget_primary_label`、`widget_secondary_label` 并同步 Provider，无快照态也有正确占位。`flutter analyze --no-pub`、全量 `flutter test` 251 项、release 构建、`aapt`、`apksigner` 均通过；版本同步升到 `1.111.0+113` / `b0707-113`。仍未完成真机桌面截图验证，需用户在手机桌面添加小组件检查裁切和字号。
- 1.110.0+112：继续按 12 条目标做当前状态复核，并修复一个代码可确认的主页 UI 不一致点：无预算大卡片的支出/收入两栏不再一左一右，而是统一居中展示，金额字号收为 23，避免小屏两栏数字视觉失衡；这一点更贴近用户反复要求的“支出、收入、结余及金额居中”和咔皮式双指标信息架构。本轮复核再次确认：导出时间范围、统计旧余量卡删除、AppSwitch 关闭态透明、小组件拆分已有代码证据；主页日期完整咔皮化、资产管理代码实现、定时/自动记账代码实现、会员系统代码实现、全仓逐行安全审计、模拟器截图仍不能宣称完成。版本同步升到 `1.110.0+112` / `b0707-112`。
- 1.109.0+111：修复 AI 记账点击输入框后输入法弹出又瞬间收起的问题。本次把根因收敛到 `_scheduleKeyboardVisibilityCheck()`：Android/小米输入法启动时 `MediaQuery.viewInsets.bottom` 可能短暂仍为 0，旧逻辑误判“键盘没打开”后主动 `_focus.unfocus()`，等于在输入法刚出现时自己关掉。现在保护期内如果焦点仍在但 `viewInsets` 未更新，只补发 `TextInput.show`，不再先失焦；如果焦点真的丢失，仍由原来的 FocusNode 保活逻辑补回。同步保留 1.108 后未出包的主页无预算大卡片调整：无预算时卡片主体改为并列展示支出/收入，结余作为弱信息显示，更贴近“默认直接看支出和收入；有预算再看预算圆环”的方向。`flutter analyze --no-pub` 与全量 `flutter test` 251 项通过；版本同步升到 `1.109.0+111` / `b0707-111`。
- 1.108.0+110：继续按 12 条目标做证据复核和小组件清理。总览小组件 `widget_feimiao.xml` 不再保留隐藏的预算进度块和隐藏的分类排行块，初始布局、桌面预览和运行态都只承载主页大卡片核心信息：主数字 + 收入/结余或支出/今日三项；`FeimiaoWidgetProvider` 总览分支同步删除旧隐藏节点赋值和 `setCategoryRows(null)` 调用，预算进度和分类活动只由独立 `widget_budget.xml`、`widget_categories.xml` 承载。`test/app_buttons_widget_test.dart` 加严 AppSwitch 回归：关闭态不仅必须透明，还必须无边框；开启态非透明且无边框，避免后续把“灰底开关”改回去。`docs/2026-07-07_全面复查与执行方案.md` 更新为严格状态矩阵：明确主页日期只是入口/月网格部分落地，用户提出的日期区块 + 支出/收入 + 预算圆环完整方案尚未实现；小组件、UI 全盘审查、模拟器截图仍需运行态验证。版本同步升到 `1.108.0+110` / `b0707-110`。
- 1.107.0+109：再次修复 AI 记账点击输入框后输入法弹出又瞬间收起的问题。本次定位到两层竞争：一是 `_inputBox` 外层 `Listener.onPointerDown` 会让整张输入卡、加号、模式切换、发送按钮都参与输入焦点保护，容易和 TextField 自己的点击序列抢同一轮 IME 动画；二是面板打开后 270ms 的自动聚焦定时器会在输入框已经有焦点时重新排 IME 可见性检查，把用户点击时的恢复检查从 320ms 推迟到约 590ms。现在输入卡外层不再抢 pointer down，只由 TextField 点击触发输入保护；焦点已在时使用 `_ensureKeyboardVisibilityCheck()`，不会覆盖已有检查。若保护期内焦点仍在但键盘被 Android/小米 IME 收掉，会跨帧释放并重新请求同一个 FocusNode，再补一次 `TextInput.show`，让 Flutter 重建输入连接。同步修复 `_stabilizeInputFocus()` 多个 post-frame 回调覆盖 timer 引用导致 dispose 漏取消的问题。新增测试覆盖“焦点仍在但 IME 被隐藏后恢复”，`flutter analyze --no-pub` 与全量 `flutter test` 251 项通过；版本同步升到 `1.107.0+109` / `b0707-109` 并重新构建 APK。
- 1.106.0+108：补齐上一轮小组件与统计页清理。统计页“本月进度对比/余量图”从构建分支、死代码和旧配置迁移中完整移除，`pace`、`battery`、`budget`、`budget_cat` 旧卡片会在迁移时被过滤；桌面总览小组件重新收敛为主页核心信息，不再在一个 4x2 总览里混塞预算块和分类排行，预算与分类活动保留为独立小组件方向。版本同步升到 `1.106.0+108` / `b0707-108`。
- 1.105.0+107：继续推进全盘 UI/功能复核中的确定性修复。统计页“本月进度对比/余量图”从卡片注册表、默认可见卡片和自定义图表入口中移除；如果用户旧配置里仍保存 `pace`，`visibleKeys` 会因注册表过滤而不再显示。自定义图表弹层继续收紧：列表外边距从 22/10/22/12 收到 18/6/18/10，行高 34，标题字号 12、字重约 w300；全局 `AppSwitch` 关闭态改为透明底 + 单灰点，不再有灰色胶囊底或描边，开启态仍是深色胶囊 + 白点。小组件总览 `FeimiaoWidgetProvider` 补齐 XML 已预留但此前未显示的区域：无快照时明确隐藏预算块和分类块；有预算时显示预算进度块；有分类数据时显示“分类与支出活动”和前三分类，使总览小组件更接近主页大卡片的信息密度。已复核导出入口：当前导出会先弹时间范围选择，默认第一项是本月，CSV 已包含 `交易UUID` 与 `退款归属UUID`，导入恢复会保留退款关系。版本同步升到 `1.105.0+107` / `b0707-107`。
- 1.104.0+106：修复 AI 记账点击输入框后输入法弹出又瞬间收起的问题。新增 `test/ai_chat_panel_focus_test.dart` 复现到 Flutter 层：点击输入框后 `FocusNode` 仍在，但 220ms 左右打开毛玻璃/动画视觉层会让测试输入法可见性掉下去，对应真机上的“键盘闪一下消失”。本版移除最后一处直接调用 `SystemChannels.textInput.show` 的硬拉输入法逻辑，避免继续扰动小米/Android IME；同时把 `_visualsReady` 的毛玻璃/动画层切换延后到输入框没有焦点、输入保护窗口结束之后，输入法启动期间只保持同一个 `FocusNode` 和同一个 `TextField` 稳定。新增焦点回归测试验证点击后 240ms 仍是同一个输入框、焦点仍在、测试输入法仍可见。版本同步升到 `1.104.0+106` / `b0707-106`。
- 1.103.0+105：继续推进小组件 UI 审查。分类与支出活动小组件不再只是“圆点 + 名称 + 金额 + 百分比”的纯文字排行，`FeimiaoWidgetCategorySnapshot` 新增 `progress` 字段，按一级分类占本月支出比例输出 0-100；Android 原生 `FeimiaoWidgetProvider` 读取该字段并设置 `widget_category_progress_1/2/3`；`widget_categories.xml` 每一行改为上方文字、下方 4dp 圆角进度条的结构，视觉上更接近“分类排行 + 百分比 + 进度条”的数据卡片。新增测试“桌面小组件快照：分类排行输出百分比进度条数值”，验证 30/10 两个一级分类输出 75%/25% 且 progress 为 75/25。版本同步升到 `1.103.0+105` / `b0707-105` 并重新构建 APK。
- 1.102.0+104：继续推进长期目标复核。主页无预算大卡片主数字从“本月结余”改为“本月支出”，下方辅助栏从“收入/支出”改为“收入/结余”，避免主数字和辅助项重复，并更贴近“默认直接看支出和收入；有预算时看预算剩余”的方向。`docs/2026-07-07_全面复查与执行方案.md` 新增“当前 12 条目标复核矩阵”，逐项标注当前证据、状态和下一步，明确小组件/主页日期/自动记账/会员/代码审计/模拟器截图等哪些已代码落地、哪些仍需运行态验证。同版追加修复 AI 记账输入框点击后输入法弹出又瞬间收起的问题：输入框外层 pointer down 只标记输入意图，不再同步强抢焦点；真正的 TextField 继续接管点击序列；焦点保护期内如果 Android/小米输入法在首帧动画中误收键盘，会通过 `_showKeyboardSoon()` 在短延迟后只对当前焦点补一次 `TextInput.show`，同时保留 `_focus.requestFocus()` 的丢焦兜底，避免外层背景关闭层、面板重排和 IME 动画互相打架。
- 1.101.0+103：继续推进长期目标的 UI 与方案复核。统计页“自定义图表”弹层行高从 42 收到 38、标题字号从 14 收到 13、卡片圆角从 20 收到 18，关闭态开关继续保持透明底并放在白色卡片上，减少“开关开关都是灰底”的视觉误读。桌面小组件继续减重：总览小组件三项辅助金额去掉 bold，分类小组件账本标题去掉 bold 并降到 14sp；月度进度小组件把“本月/平均”标签从 11sp 提到 12sp，金额从 14sp 降到 13sp，平均进度条从 6dp 降到 5dp。`docs/2026-07-07_资产定时自动会员执行蓝图.md` 已补充可执行任务单：资产管理、定时记账、自动记账候选池、Free/Pro/Max 会员分别给出迁移字段、入口文件、执行顺序和验收测试。
- 1.100.0+102：继续修复 AI 记账点击输入框后输入法弹出又瞬间收起的问题。输入框点击统一收敛到 `_handleInputPointerDown()`，避免外层 `Listener`、TextField、背景关闭层在同一轮触摸里各自抢焦点；TextField 增加稳定 key `ai-chat-input-field`，降低空态建议区、键盘 inset、面板动画重排时 EditableText 被替换的概率；输入焦点保护从一次性检查改为 120ms 启动、每 180ms 循环检查，持续到 1800ms 保护期结束，期间如果 Android/输入法动画导致 FocusNode 短暂丢失，会自动补回同一个输入焦点。版本同步升到 `1.100.0+102` / `b0707-102`。
- 1.99.0+101：推进桌面小组件重做。总览小组件继续向主页大卡片靠拢：主标题改为可由数据驱动的“本月支出/预算剩余”，有预算时主数字显示预算剩余，第二列从“结余”切为“支出”；无预算时仍显示本月支出、收入、结余、今日。新增小组件快照字段 `paceCaption`、`paceAverageText`、`paceThisProgress`、`paceAverageProgress`，月度小组件从旧预算余量卡改为“本月进度对比”：展示截至今日、本月支出、过去 6 个月同期平均，并用深色/浅灰两条进度条表达本月 vs 平均。新增 repo 层测试覆盖同期平均口径：本月 30、历史同期 10/20 时，平均为 15，本月进度 100、平均进度 50。
- 1.98.0+100：继续修复 AI 记账点击输入框后输入法弹出又瞬间收起的问题。移除最后一处直接调用 Android `TextInput.show` 的键盘硬拉逻辑，避免和小米/Android 输入法自身动画、`viewInsets` 首帧变化互相打架；输入框仍保留 1800ms 输入意图保护，但保护期内如果 FocusNode 被面板重排误丢，会在下一帧立即补回同一个输入焦点，再用一次 80ms 稳定检查兜底。输入卡外层只标记输入意图，真正 requestFocus 收窄到 TextField 文本区域，避免加号、模式切换、发送按钮被误触发键盘。
- 1.97.0+99：再次修复 AI 记账点击输入框后输入法弹出又瞬间收起的问题。上一版的 IME 可见性守护使用周期性 `TextInput.show` 轮询，容易在 Android 键盘打开动画与 `viewInsets` 尚未稳定时反复扰动输入法状态；本版移除周期性轮询，改为一次性延迟唤起键盘，并在输入框区域增加 `Listener.onPointerDown` 级别的输入意图标记，让外层背景点击关闭逻辑在同一轮点击内不会介入。输入焦点保护期从 1300ms 延长到 1800ms；如果焦点短暂丢失，只补一次 `requestFocus`，避免键盘被长期粘住或反复闪烁。
- 1.96.0+98：继续推进全盘目标中的确定性 UI 修复。新增独立 `widget_budget.xml`，`FeimiaoBudgetWidgetProvider` 不再复用总览小组件，月度概览/预算小组件改为白底大卡片：预算/本月概览主数字、预算进度条、本月支出、今日支出；`feimiao_widget_budget_info.xml` 的 initial/preview layout 均指向独立布局。小组件进度条由 `clip` 改为 `scale`，减少进度末端一刀切。全局 `AppSwitch` 关闭态从透明改为白底/卡片底 + 更浅发丝边，避免灰色父容器透出后看起来“开关开关都是灰底”。主页大卡片左上日期入口进一步对齐咔皮：去掉长灰胶囊和可见左右箭头，改为直接的“年月 + 下箭头”；“统计”改为浅蓝小胶囊；日期区域保留左右滑快切月份，点按打开 3 列月份选择。

- 1.95.0+97：修复 AI 记账点击输入框后输入法弹出又瞬间收起的问题。上一版只守住 FocusNode，这次新增 IME 可见性守护：输入框点击或自动聚焦后进入 1300ms 输入保护期，期间每 180ms 检查 `viewInsets`；如果焦点仍在但键盘被 Android/布局变化收掉，会通过 `TextInput.show` 主动恢复键盘；如果焦点也丢失，则绕过节流重新 requestFocus。发送、切换手动、面板 inactive、主动背景收键盘都会取消保护，避免键盘被长期粘住。

- 1.94.0+96：继续推进全盘复核里的确定性修复。全局 `AppSwitch` 改为自绘胶囊：开启为黑底白圆，关闭为透明底 + 发丝描边 + 灰点；设置页残留 `Switch.adaptive` 替换为 `AppSwitch`，统计自定义图表库开关复用同一标准。自定义图表库行高从 44 收到 42，标题字号从 15 收到 14。导出 CSV 入口文案改为“先选择时间段再导出”，与实际弹出的范围选择一致。总览小组件隐藏预算进度块，先收敛为主页大卡片式核心信息：本月支出主数字 + 收入/结余/今日辅助指标，预算/同期对比后续单独做小组件。

- 1.93.0+95：继续修复 AI 记账点击输入框后输入法弹出又瞬间收起的问题。输入框点击/自动聚焦后进入 1100ms 焦点保护期；保护期内背景遮罩点击只忽略，不再二次抢焦或触发收起；新增 260ms 焦点保活计时器，若 Android IME 打开期间因面板重布局误丢焦点，会绕过 160ms 节流补一次 requestFocus；发送、切换到手动、点背景主动收键盘、面板变为 inactive 时都会清掉保护期，避免键盘被“粘住”。

- 1.92.0+94：继续推进全盘 UI 复查第一批可落地项。统计页“自定义图表”弹层行高从 50 收到 44、标题字号从 16 收到 15，开关关闭态改为透明胶囊轮廓 + 小圆点，不再显示灰色填充底；主页月份选择 sheet 降低标题/年份/月份格子的厚重感，默认白底、选中浅蓝，行距和格子高度更接近轻量选择器；Android 总览小组件收敛为主页大卡片式概览，不再混塞分类排行，分类排行留给独立“分类与支出活动”小组件。


- 1.91.0+93：继续修复 AI 记账点击输入框后输入法弹出又瞬间收起的问题。新增输入框聚焦保护窗口，点击输入框或自动聚焦后的 700ms 内，空态/对话态背景关闭层不会 pop 面板或抢焦点；背景点击在键盘已打开时只先收起键盘，不直接关闭面板；空态背景关闭层不再铺到输入框区域背后；TextField 点击只标记输入意图，不再重复 requestFocus，减少 Android IME 首帧抖动。


- 1.90.0+92：修复 AI 记账空态点击输入框后输入法弹出又瞬间收起的问题。输入框外层不再用 `GestureDetector` 抢占 TextField 点击，改为 `TextFieldTapRegion`；禁用 TextField 默认 tap outside 失焦；AI 空态获得焦点时不再触发整块无意义 rebuild，降低 Android IME 打开期间焦点被布局重建抖掉的概率。


- 1.89.0+91：修复 AI 记账点击输入框后键盘弹出又瞬间收起的问题。输入框不再依赖 TextField autofocus，统一由带防抖的焦点请求方法控制，避免键盘 inset 触发布局重建时焦点抖动。


- 1.89.0+91：继续完成全盘复查第一批落地项：主页日期改为咔皮式月份网格；导出 CSV 增加时间段选择；统计页移除旧预算余量/本月预算卡；自定义图表库开关关闭态去灰底；预算小组件改为复用主页月度概览；新增全面复查与执行方案文档。


- 1.89.0+91：补齐统计余量图彻底移除：删除统计页旧 budget 构建分支、注册项、默认项和 _BudgetProgressCard 死代码；删除未使用的 Android 旧 widget_budget.xml，避免后续误用。

旧版本验证结果（历史摘录，非当前状态）：

> 本段保留的是 `1.125.0+127` 附近的运行态验证记录，只用于说明当时模拟器无法截图的背景；不要把本段当成当前 `1.145.0+147` 的验证结论。当前交付状态以本文顶部和第 2 节为准。

| 检查项 | 结果 |
| --- | --- |
| `analyze --no-pub` | 通过，`No issues found` |
| `flutter test` | 通过，`All tests passed!`，共 261 项 |
| `flutter build apk --release` | 通过 |
| `aapt dump badging` | 通过，`com.qingji.qingji.codex` / `versionCode=127` / `versionName=1.125.0` / label=`肥喵记账` |
| `apksigner verify --print-certs` | 通过，签名为 Codex 测试证书 |

运行态验证说明：

- 已尝试启动本机 AVD `codex_feimiao_api35_small`、`codex_feimiao_fresh_api35`、`codex_feimiao_api35`。
- 多次都未能在限定时间内注册为 adb `device`，因此没有完成模拟器安装、启动和截图验证。
- 本轮再次尝试启动 `codex_feimiao_api35_small -no-window`，失败原因是 AVD 目录写入 `qemu-version.txt` 失败，并提示存在另一个 emulator 实例；但 `adb devices` 无设备，`adb emu kill` 提示 no emulator detected，进程检查仅见 adb，无 emulator/qemu 进程。
- 本次 `1.125.0+127` 构建后仍需执行真机/模拟器截图；AI 输入法稳定性、图表库开关视觉、全局开关、导出范围入口、小组件总览/预算/分类排行、主页预算态咔皮化后的实际视觉仍需复核。
- 2026-07-07 07:58 再次启动 `codex_feimiao_api35_small -no-window -gpu swiftshader_indirect -no-snapshot -no-boot-anim -no-audio`。`emulator` 与 `qemu-system-x86_64-headless` 进程成功启动，但 `adb devices` 2 分钟轮询始终没有 device；日志仍显示 `avdInfo_setLastRunQemuVersion: Could not write file ... qemu-version.txt`，且 AVD 路径中的用户名出现乱码，因此未能安装 APK、启动 App 或截图。结束后已停止本次 emulator/qemu 进程。
- 2026-07-07 06:08 再次启动 `codex_feimiao_api35_small -no-window -gpu swiftshader_indirect -no-snapshot -no-boot-anim`。`emulator` 与 `qemu-system-x86_64-headless` 进程能启动，但 2 分钟 adb 轮询始终只有 `List of devices attached`、没有任何 device，因此未能安装 APK 或截图。随后已停止本次 emulator/qemu 进程，未留下运行中的模拟器。
- 2026-07-07 04:16 曾清理两个 adb 不可见的 `qemu-system-x86_64-headless` 残留进程后重新启动 `codex_feimiao_api35_small`。模拟器进程成功启动，但 2 分钟内没有注册为 adb `device`，无法安装 APK 和截图验证；随后已结束本次 `emulator` / `qemu` 进程，未留下运行中的模拟器。
- 已确认结束后无 `emulator` / `qemu` / `adb` 残留进程。
- 当时 APK 已完成代码静态分析、全量测试、构建、包名、版本、签名验证；真机 UI 仍需用户安装后复核。
- 2026-07-07 04:40 再次尝试启动 `codex_feimiao_api35_small -no-window` 做 AI 输入框运行态验证。模拟器进程启动后自行退出，日志仍显示无法写入 `codex_feimiao_api35_small.avd\qemu-version.txt`；adb 轮询 2 分钟没有发现 `device`，因此本次未完成安装、点击输入框和截图验证。结束后检查无 `emulator` / `qemu` 残留进程，仅 adb 服务进程仍在。
- 2026-07-07 04:55 使用提升权限再次启动 `codex_feimiao_api35_small -no-window` 以验证小组件/主页 UI。模拟器仍记录同一个 `qemu-version.txt` 写入错误，adb 轮询 3 分钟仍无 `device`；未完成安装和截图。随后只结束本次启动的 `emulator` / `qemu-system-x86_64-headless` 进程，保留 adb 服务。
- 2026-07-07 05:30 再次启动 `codex_feimiao_api35_small -no-window` 以验证 `1.101.0+103`。模拟器进程能启动，但日志仍出现 `avdInfo_setLastRunQemuVersion: Could not write file ... qemu-version.txt`；随后 adb 轮询约 2 分钟始终只有 `List of devices attached`、无任何 device，因此无法安装 APK、无法截图验证小组件/统计图表库/AI 输入框运行态。结束后已停止本次 `emulator` / `qemu-system-x86_64-headless` 进程，仅保留 adb 服务。

当时重新构建的旧 APK 路径为 `C:\src\xunni-codex\android-app\build\app\outputs\flutter-apk\app-release.apk`，文件时间 `2026-07-07 11:20:20`，大小 `109,061,725` 字节。当前交付 APK 不是这个文件，而是第 2 节记录的 `feimiao-codex-v1.144.0-146.apk`。

截至当时，金额显示设置、金额搜索兼容修复、金额展示漏接修复、统计页“本月进度对比/余量图”移除、小组件市场分析文档、喵助手报告文档产物底座、喵助手顶部虚化、统计图表库入口、退款弹窗字重、AI 回复底部按钮再收敛、报告生成漏判修复、AI 输入框聚焦动画优化、预算进度条末端圆角、AI 空态聚焦后保留猫和建议、报告卡片长按菜单、报告专用 DeepSeek prompt、统计自定义图表白底大卡片开关样式、多样式 Android 桌面小组件、本轮思考行位置再左移、报告请求模型兼容重试、报告 AI 失败本地基础版兜底、AI 输入法弹出后瞬间收起的视觉层延迟修复与 `1.107.0+109` 的 IME 连接重建修复、`1.108.0+110` 的总览小组件 XML 结构清理和 AppSwitch 测试加强、`1.110.0+112` 的主页无预算支出/收入双指标居中、`1.111.0+113` 的总览小组件双主指标重排、`1.112.0+114` 的 AI 输入框焦点/输入法保活增强、`1.113.0+115` 的图表库开关/字号收敛、`1.114.0+116` 的 AI 入口自动聚焦与模糊层延后修复、`1.115.0+117` 的主页预算态收支顺序/字重/圆环位置修复、`1.116.0+118` 的 AI 输入法 metrics 兜底和小组件预算态映射修正、`1.117.0+119` 的总览小组件预算态进度线、`1.121.0+123` 的资产管理 P0 数据地基、`1.122.0+124` 的 AI 输入法有限焦点会话修复、`1.125.0+127` 的 AI 输入法去强制 show 与局部键盘位移修复，以及 `1.92.0+94` 的图表库开关/主页月份选择/小组件总览收敛，已进入当时 APK。当前 APK 是否包含某项，以顶部 `1.145.0+147` 出包摘要和第 2 节交付状态为准。

## 3. 构建命令说明

普通 `flutter.bat` 曾因 stale lock / Flutter 早期初始化卡住。当前可用的稳定方式是直接调用 Flutter 缓存里的 Dart 和 `flutter_tools.snapshot`：

```powershell
$env:FLUTTER_ROOT='C:\src\flutter'
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' --packages='C:\src\flutter\packages\flutter_tools\.dart_tool\package_config.json' 'C:\src\flutter\bin\cache\flutter_tools.snapshot' analyze --no-pub
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' --packages='C:\src\flutter\packages\flutter_tools\.dart_tool\package_config.json' 'C:\src\flutter\bin\cache\flutter_tools.snapshot' test
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' --packages='C:\src\flutter\packages\flutter_tools\.dart_tool\package_config.json' 'C:\src\flutter\bin\cache\flutter_tools.snapshot' build apk --release
```

每次交付新 APK 前必须递增版本号，并同步更新：

- `pubspec.yaml`
- `lib/core/app_version.dart`
- `lib/build_info.dart`

## 4. 统一设计标准

这些是用户已经明确确认过的偏好和规范，后续不要随意改回去。

### 字重

- 用户说“字重减少 w100”是相对减少一档：
  - `w700 -> w600`
  - `w600 -> w500`
  - `w500 -> w400`
- 不是把字重改成 `w100`。

### 数字字体

- 金额、百分比、键盘数字、AI 回复里的数字统一使用 `Nunito`。
- 中文正文仍使用原中文字体，不要整段切到 `Nunito`。
- 已处理范围包括：
  - 首页金额数字
  - 手动记账金额
  - 数字键盘
  - AI 回复、用户气泡、系统提示中的数字

### 半屏弹窗头部

统一使用全局按钮组件，不要在单个页面手写一套新样式。

- `SheetHeader` 高度：`48`
- 左上角关闭按钮：`AppCircleButton(size: 34, iconSize: 18)`
- 右上角动作按钮：`AppPillButton`
  - 高度：`34`
  - 圆角：`17`
  - 文本：`15 / w500`
  - 使用 `IntrinsicWidth` 控制宽度，避免按钮被撑成一整条
- 相关文件：
  - `lib/widgets/app_buttons.dart`
  - `lib/widgets/settings_ui.dart`
  - `test/app_buttons_widget_test.dart`

### 玻璃与虚化

- 首页顶部虚化要接近 iOS / GPT 顶部材质，不要硬灰底或“一刀切”遮罩。
- 首页底部输入框、搜索底部输入框都要有自然的渐隐/虚化过渡。
- 不要为了性能直接删除虚化、玻璃输入框、猫动效；性能问题要通过构建压力降低、局部刷新、路由合并等方式解决。

### 同功能同 UI

- 主页“总账本”和预算页“全部账本”共用 `BookSwitchChip`。
- 搜索输入框应沿用主页输入框语言。
- 导入复核、手动记账、统计列表等同类型账单展示应尽量复用同一视觉标准。

## 5. 已完成改动总览

### 5.1 数据、导入导出与退款

- 交易读取增加 `uuid`，用于稳定恢复退款关系。
- 肥喵 CSV 导出包含：
  - `分类Key`
  - `记录类型`
  - `交易UUID`
  - `退款归属UUID`
- 导出从“只导出可见交易”改为“导出完整交易”，隐藏退款行也会写入。
- 导入肥喵 CSV 时优先走专用恢复逻辑，不进入普通账单复核页。
- 新格式按 `uuid / refund_of` 恢复退款归属。
- 旧 CSV 如果没有退款行但有 `原始金额 / 已退款`，会自动补隐藏退款行。
- 肥喵自己导出的 CSV 以 `交易UUID` 作为稳定唯一 ID；重复导入时按 UUID 跳过，避免重复统计。
- 外部账单没有唯一 ID 时，导入去重改为“按已有次数消耗”：
  - 同一个文件里两笔完全相同的真实消费（如两笔 `公共交通 / 地铁 / 2.5`）都会入库。
  - 第二次导入同一个文件时，才会按已有笔数跳过，避免重复统计。
- 已补测试：
  - 肥喵导出恢复时保留原始金额和已退款关系。
  - 相同 `交易UUID` 再导入会跳过。
  - 同文件内完全相同账单按真实笔数导入，重复导入才跳过。

重点复测：

- 从 Codex App 导出后，重装再导入，退款必须仍挂在原支出下。
- 原支出 `150.17`、退款 `9.16` 的场景，应显示为原支出剩余约 `140.62`，不能把退款变成独立负数“其他”。
- 用用户反馈的 `公共交通 / 地铁 / 2.5` 两笔重复行导入，账单里必须能看到两笔；再次导入同文件才应跳过。

### 5.2 AI、模型与隐私

- DeepSeek 模型统一为 `deepseek-v4-flash`。
- 涉及文件：
  - `lib/core/ai/llm_entry_parser.dart`
  - `lib/core/ai/llm_query.dart`
- AI 记账、查账问答使用 AI 前增加隐私确认说明。
- AI 隐私说明弹窗：
  - 标题字号减小
  - 正文字重降低一档
- AI 回复排版减轻字重和颜色层级，避免标题过粗。
- AI 查账上下文会携带账本数据，避免问“上个月订单”时回答不知道。
- AI 回复里的数字、金额、百分比已统一走 `Nunito`。

### 5.3 首页、顶部虚化与抽屉

- 首页下滑时去掉折叠后的“结余 / 今日”等迷你栏，避免占空间。
- 顶部虚化从 body 内硬遮罩移到 AppBar 材质层，并让内容延伸到 AppBar 背后。
- 顶部增加渐隐层，减少 AppBar 底部“一刀切”。
- 底部输入栏保留渐变过渡，避免列表被输入框硬切。
- 抽屉拖动时不再实时全屏模糊，以降低右滑卡顿。
- 抽屉“新建账本”按钮改为白底黑字、轻描边。
- “资产管理”入口进入后标题统一为“资产管理”，不再显示“账户管理”。
- 首页 `全部 / 支出 / 收入` 筛选条做过多轮间距调整，当前按用户要求取消额外上方 padding。

重点复测：

- 用户多次反馈顶部虚化仍不像 GPT，要在真机截图上重点看。
- 首页大卡片位置、筛选条位置、筛选条到下方账单卡片距离要一起检查，不能修一个挤坏另一个。

### 5.4 账本选择器

- 新增公共组件：`lib/widgets/book_switch_chip.dart`。
- 首页右上角“总账本”和预算弹层“全部账本”共用同一 UI：
  - 高度一致
  - 圆角一致
  - 边框一致
  - 字重一致
  - 右侧下箭头一致

### 5.5 手动记账与 AI 记账切换

- 手动记账金额卡保留金额和备注之间的细横线。
- 金额数字、`¥`、数字键盘数字使用 `Nunito`。
- AI 记账和手动记账切换做过三轮性能优化：
  - 早期从 `showGeneralDialog` 改到 `PageRouteBuilder`。
  - 后续减少键盘 settle 等待，避免“先上再下”。
  - 最终新增 `lib/views/home/record_entry_sheet.dart`，在同一个路由内切换 `AiChatPanel / ManualAddSheet`，减少透明路由叠加造成的卡顿。
- AI -> 手动时隔离旧 keyboard inset，避免手动面板首帧变矮。
- 手动分类区改为固定高度 `ListView.builder` 懒加载，减少首帧 SVG 构建压力。

性能记录：

- v1.51 模拟器实测相较旧路径有明显改善。
- 键盘参与时 P95 从约 `53ms` 降到 `28-34ms`。
- 连续多次切换仍可能有约 `7.5%-10%` jank，主要来自系统键盘、透明弹层和首帧构建。

### 5.6 AI 记账面板

- 半屏 AI 空态中猫猫放大约 60%，并放到输入框上沿附近。
- 四个快捷建议整体下移。
- 全屏喵助手保留返回按钮和菜单按钮。
- 底部半屏 AI 记账不显示返回按钮和三个点菜单。
- 输入框继续沿用主页玻璃输入框标准。
- 主页 `Scaffold` 设置 `resizeToAvoidBottomInset: false`，避免出现两层输入框。

### 5.7 搜索页

- 搜索页左上返回按钮改为全局 `AppBackButton` 圆形样式。
- 搜索输入框沿用主页输入框外观。
- 去掉输入框左下角额外搜索图标。
- 去掉右下角关闭按钮。
- 右下角改成和主页一致的圆形上箭头发送按钮。
- 输入提示字重降低一档。
- 搜索页底部输入框改为浮在内容上方，并增加底部虚化渐隐层。
- 搜索页顶部 `支出 / 收入` 汇总卡改为玻璃化卡片，金额字重从 `w700` 降到 `w600`。
- 搜索关键词统一做归一化匹配：
  - 英文字母不再区分大小写，`k12` 可以命中备注里的 `K12`。
  - 全角英数字会转半角，`Ｋ１２` 也可以命中 `k12`。
  - 备注、分类名、账户名、转入账户名、分类 Key、原始金额、净额都参与搜索。
- 搜索页点击“时间”时，默认开始/结束时间为今天，不再默认跳到近 30 天前。
- 搜索页打开日期弹窗前会先等待输入法收起，减少日历“先上再下”的突兀动画。

重点复测：

- 输入框是否真的与主页一致。
- 有内容时发送按钮是否按主页标准变黄色。
- 底部输入框后方是否自然虚化，而不是白色硬切。

### 5.8 导入复核页

- 底部 `AI 归类` 和 `导入 xxxx 笔` 去掉图标。
- 去掉底部大白底块。
- `AI 归类` 与 `导入 xxxx 笔` 字号统一。
- `导入 xxxx 笔` 改为白底黑字。
- “识别为「账单」”标题字重降低一档。
- 导入复核页账单标题字重对齐主页账单标题。
- 退款导入时优先挂回原单，不再作为独立负数“其他”显示。

重点复测：

- 点击“待分类”后的分类选择界面，应尽量与手动记账的一二级分类选择保持一致。
- 单笔账单展示应向主页单笔占比 UI 靠齐，避免继续出现独立的一套设计。

### 5.9 退款弹层

- 去掉“虚拟充值 / 原支出 / 已退 / 剩余”等副标题说明。
- 去掉“默认剩余可退...”提示文案。
- 金额输入默认填最大可退金额。
- 默认不改金额点“全部退回”就是退全款。
- 用户点击数字后从全选状态直接替换输入，不需要先删除旧数字。
- 金额输入颜色改为灰色。
- 左上关闭按钮和右上动作按钮统一 `SheetHeader` 位置。
- 修复第二次打开退款弹层键盘不弹的问题。
- 弹层标题和输入区之间的硬分割线已移除。
- “全部退回”和其他弹窗右上角动作按钮字重统一降低一档。

### 5.10 统计、月报与日历

- 统计页自定义日期区间居中，字重对齐周/月/年日期。
- 三个统计小卡片的“支出 / 收入 / 结余”和金额居中显示。
- 每日趋势右侧“支出 / 收入”字号减小，选中不再加粗。
- 支出构成标题字重降低一档。
- 支出构成做过“重复其他”归并和明细箭头修复。
- 统计自定义日历滚轮补齐“日”。
- 自定义日历标题、关闭按钮、“回今日”、顶部小灰条和按钮样式做过统一。
- “回今天”按钮统一为灰底小胶囊 + 蓝色文字。
- 日历周标题和日期第一行间距收紧。
- 月度报告日期选择改为和统计页月维度一致：日期文字右侧下箭头，点击弹出月选择器。
- 统计页月维度新增“本月进度对比”卡片：
  - 只在当前月显示。
  - 按“今天在本月的时间进度”换算历史月份同进度支出，避免 28/30/31 天月份直接按日期比较造成误判。
  - 浅灰柱表示历史整月支出，深灰柱表示历史同进度支出，蓝色柱表示本月截至今日支出。
  - 浅灰柱颜色继续降低存在感；深灰同进度柱改为前景柱叠在浅灰整月背景柱上，顶部也保留圆角。
  - 卡片不再显示外层“本月进度对比”标题，首行直接展示“截至 X月X日，本月支出与往常……”结论，并在下方加细分割线。
  - 结论标题字重降低一档；指标区只保留“平均 / 本月”，去掉“少花 / 高出”；金额字号降低一号，标签字重提高一档。
  - 横线表示历史同进度平均，颜色更浅、线宽加倍；底部不再展示“整月 / 同进度 / 本月”图例。
  - 底部标题改为“分类与支出活动”，标题下方增加细分割线；内容展示本月截至今日支出前三的一级分类，二级分类会自动汇总到所属一级分类。
  - 数据不足 3 个月时显示“历史数据较少，仅供参考”。
  - 已兼容旧的统计卡片排序配置：如果用户之前保存过卡片顺序，新卡会做一次性迁移补进默认列表；用户之后手动关闭，不会再次自动复活。
  - 已补测试覆盖旧配置迁移边界，防止“默认卡片关掉后又被加回来”的回归。
- “预算余量”不再把剩余、已用、预计月底、图例和折线全部堆成报表：
  - 主层级改为“剩余可用 / 已超预算”大金额 + “节奏正常 / 节奏偏快 / 节奏宽松 / 预算已超”状态胶囊。
  - 增加预算进度条，实际已用为填充条，理想时间进度为竖向刻度。
  - 辅助信息只保留“今日建议”“理想剩余”和一句小号预计提示，避免月初固定支出导致“预计月底超很多”的大字误导。
  - 折线图降为轻量趋势图，隐藏左侧大额坐标，减少卡片拥挤感。

重点复测：

- 用户多次反馈“支出构成出现两个其他”，虽然代码侧做过归并，但必须用真实导入数据再次验证。
- 分类排行用户希望对齐咔皮：前五条展示、超出隐藏、百分比、进度条和右侧进入明细箭头都要复核。

### 5.11 我的、设置、备份与关于

- “我的”页按 iOS / GPT 设置页重组。
- 顶部头像用空白圆形占位，不放猫图。
- 只保留真实可用入口：
  - `AI 记账设置`
  - `备份与恢复`
  - `关于`
- 不展示未上线功能，不重复展示抽屉里已有功能。
- App 名称：`17 / w400`
- 版本号：`13 / w300`
- 设置分组标题：`12.5 / w400`
- 设置行标题：`15.5 / w400`
- 通用半屏弹层标题：`17 / w400`
- 备份页卡片标题：`w400`
- “备份与恢复”在“我的”页直接可见，也保留旧设置页入口。
- “关于肥喵记账”改为“关于”。
- “关于”弹窗内包含：
  - 使用条款
  - 隐私政策
  - 版本号
- 设置页版本不再硬编码 `0.1.0` 或 `v0.2`，统一显示 `AppVersion.display`。
- 备份页空状态下也显示 `立即备份`。

### 5.12 分类图标颜色

- 收入一级分类颜色已改为同一收支组内不重复。
- 二级分类图标主色与所属一级分类保持一致。
- 同步检查支出分类，修正过 `车辆支出`、`居家住房` 等父子颜色不一致问题。
- 已用脚本审计过：
  - `parent-child mismatches: none`
  - `top-level duplicate gradients: none`

重点复测：

- 用户指出部分二级图标仍保留旧黄色，要重点检查所有二级分类是否真正继承父级颜色。
- 一级分类图标在同一分类组内不要重复颜色。

### 5.13 图标、包名、签名与应用名

- 应用显示名已改为 `肥喵记账`。
- 通知监听服务 label 保持 `肥喵自动记账`。
- 当前 `assets/icon/app_icon.png` 使用用户最后提供的图标源图。
- Android `mipmap-*dpi/ic_launcher.png` 已重新生成。
- Android 8+ adaptive icon XML 已恢复，且对齐 Claude 当前可用方案：
  - `background` 指向完整成品图 `@drawable/ic_launcher_foreground`
  - `foreground` 使用透明色
  - 目的：让小米等桌面按完整背景层做圆角遮罩，避免 foreground 安全区被二次放大裁切。

重点复测：

- 用户多次反馈安装后图标被裁切、白边或显示不完整。
- 不同 Launcher 会套不同 mask，必须以真机安装后截图为准。
- 用户最后要求“安装后要跟给的图一样一样”，这里仍是最高风险点之一。

### 5.14 Android 桌面小组件

当前已完成一期 Android 原生桌面小组件实现。小组件不走 Flutter 页面渲染，而是由 Flutter 侧生成轻量账本快照，Android 原生 `AppWidgetProvider + RemoteViews` 读取快照展示。详细设计与后续二期方案见：

- `WIDGETS_FEIMIAO_PLAN.md`

- 当前抽屉不恢复旧的“小组件”占位入口；真实入口在系统桌面“添加小组件”列表中。
- Android 侧已新增：
  - `android/app/src/main/kotlin/com/qingji/qingji/FeimiaoWidgetProvider.kt`
  - `android/app/src/main/res/xml/feimiao_widget_info.xml`
  - `android/app/src/main/res/layout/widget_feimiao.xml`
  - `android/app/src/main/res/drawable/widget_feimiao_bg.xml`
  - `android/app/src/main/res/drawable/widget_add_bg.xml`
  - `android/app/src/main/res/drawable/widget_progress.xml`
  - `android/app/src/main/res/values/strings.xml`
- `AndroidManifest.xml` 已注册 `.FeimiaoWidgetProvider` receiver。
- `MainActivity.kt` 已新增 `MethodChannel("feimiao/widget")`：
  - `saveSnapshot`：保存 Flutter 快照到 `SharedPreferences("feimiao_widget_snapshot")` 并刷新所有桌面小组件。
  - `requestUpdate`：主动请求刷新桌面小组件。
- Flutter 侧已新增：
  - `lib/core/widgets/widget_snapshot.dart`
  - `lib/core/widgets/native_widget_bridge.dart`
  - `lib/core/widgets/widget_snapshot_service.dart`
- `main.dart` 在 `repo.init()` 后挂载 `WidgetSnapshotService`，App 启动、回到前台、仓库数据变化后会节流刷新小组件快照。
- `AppRepository` 新增 `widgetPrivacyMode`，持久化在 `app_settings.widget_privacy_mode`。
- 设置页新增“小组件 / 隐藏金额”开关。开启后，小组件快照写入的是 `••••`，不写入具体金额文本。
- 一期小组件展示：
  - 当前账本名和日期。
  - 今日支出。
  - 本月支出 / 收入 / 结余。
  - 预算剩余、预算进度条和预算提示。
  - 本月支出前三个一级分类；二级分类会汇总到所属一级分类。
  - 点击主体打开 App；点击 `+` 打开 App，并携带 `feimiao_open=quick_add` extra（当前至少能回到 App，后续可继续接入自动弹出记账面板）。

复核后的技术结论：

- 小组件不是 Flutter `Widget`，必须走 Android 原生 App Widget。
- 一期推荐 `AppWidgetProvider + RemoteViews`，不要一开始就引入 Glance/Compose 构建链。
- 不建议小组件直接读 Flutter SQLite；应由 Flutter 侧根据现有账本、预算、退款、分类口径生成快照，再通过 MethodChannel 写入原生 `SharedPreferences`。
- 当前项目已有 MethodChannel 经验：分享入口、自动记账、安全存储，所以新增 `feimiao/widget` 通道是可控路线。
- 必须先实现“小组件隐藏金额”隐私开关，再恢复入口。

推荐一期只做“桌面看数 + 快速入口”，不要把复杂记账输入塞进小组件：

- `2x2` 小组件：
  - 今日支出
  - 本月支出
  - 预算剩余
  - 快速记账按钮
- `4x2` 小组件：
  - 本月支出 / 收入 / 结余
  - 预算剩余与进度条
  - 本月前三一级分类
  - 快速记账按钮
- 点击交互：
  - 点击金额区域打开首页或统计页。
  - 点击快速记账打开 App 内 AI/手动记账入口。

推荐技术路线：

- 一期：传统 `AppWidgetProvider + RemoteViews`，构建风险最低。
- 二期：等一期稳定后，再评估 Jetpack Glance。
- 数据同步：Flutter 生成轻量快照，原生小组件只读快照渲染。
- 快照建议字段：
  - `bookId`
  - `bookName`
  - `todayExpense`
  - `monthExpense`
  - `monthIncome`
  - `monthBalance`
  - `budgetTotal`
  - `budgetLeft`
  - `budgetProgress`
  - `topCategories: [{name, amount, percent, color}]`
  - `updatedAt`
  - `privacyMode`
- 写快照的触发点：
  - 新增 / 编辑 / 删除账单
  - 退款
  - 导入账单
  - 切换账本
  - 修改预算
  - App 启动或回到前台

隐私与可靠性标准：

- 设置页需要提供“小组件隐藏金额”开关。
- 隐藏金额时显示 `••••`，但仍可显示预算进度和趋势。
- 小组件必须显示“更新时间”，避免用户误以为数据实时。
- 离线、本地无数据、预算未设置时都要有明确空态，不要显示 `0` 造成误解。
- 小米桌面必须真机验证：
  - `2x2`、`4x2` 两种尺寸。
  - 深色 / 浅色模式。
  - 字体缩放。
  - 点击跳转是否稳定。
  - 刷新后是否被系统延迟或省电策略限制。

## 6. 历史重点修复索引（旧摘录，非当前 APK 状态）

> 本节是早期交接文档留下的功能索引，不再代表“最新 APK”。当前最新 APK 状态以本文顶部 `1.145.0+147` 和“当前交付状态”为准。

`v1.82.0+84` 当时已包含：

- 喵助手报告类回答升级为“聊天摘要 + Markdown 文档产物”：用户询问周报、月报、年报等报告类问题时，AI 完整回答会写入独立 `reports` 表，聊天里只保留摘要和可点击的 `Document · MD` 文档卡片。
- 报告失败态补强：未配置 AI key 或 DeepSeek 调用失败时，不会把错误提示保存成报告文档，只保留普通聊天提示。
- 报告聊天摘要补强：摘要会跳过 `# 标题`、`## 摘要` 等 Markdown 标题，只展示正文判断，避免卡片摘要变成“2026年6月消费月报 摘要...”。
- 报告纯函数测试补齐：覆盖报告类型识别、月份周期解析、摘要提取、失败态不入库。
- 喵助手全屏右上角新增“文档 / 菜单”组合胶囊：左侧打开报告库，右侧打开原聊天菜单，视觉合并但点击区域分离。
- 新增报告库与报告阅读页：支持查看历史周报、月报、年报，并用轻量 Markdown 渲染标题、列表、加粗和数字字体。
- 报告文档与聊天记录解耦：清空聊天只删除 `chat_messages`，不会删除已生成的 `reports` 文档。
- 数据库版本升至 `23`，新增 `reports` 表并为报告增加 `pinned_ms` 置顶字段；补充仓库层持久化测试和聊天报告引用 JSON 测试。
- Android 桌面小组件一期已实现：原生 `AppWidgetProvider + RemoteViews` 展示当前账本、今日支出、本月支出/收入/结余、预算进度和本月支出前三一级分类；Flutter 侧通过 `WidgetSnapshotService` 生成快照并写入原生 `SharedPreferences`。
- 设置页新增“小组件 / 隐藏金额”开关；开启后快照中的金额文本写入 `••••`，避免桌面小组件显示具体金额。
- 抽屉里的“小组件”占位入口仍隐藏，避免用户测试时点到 App 内尚未实现的 ComingSoon 页；真实小组件入口在系统桌面添加组件列表。
- 历史记录：统计页月维度“本月进度对比”曾按用户参考图改版：去掉卡片标题和底部图例，首行结论上移并加分割线，只保留“平均 / 本月”两项指标，底部改为“分类与支出活动”并加分割线。
- 统计图表旧配置迁移改为一次性数据层迁移；旧用户会看到新卡，用户后续在图表库关闭该卡后不会被自动恢复。
- 统计页“支出构成”的“更多”聚合项现在与其他分类一样显示小箭头，并可进入被折叠分类的账单明细；下钻页支持多分类集合过滤。
- 统计页“本月电量”已改名为“预算余量”，改为“实际剩余 vs 理想节奏”双线图，并优化每日趋势选中态的本期/同期对比展示。
- 历史记录：统计页“本月进度对比”曾按用户反馈微调：金额字号降低、结论标题字重降低，浅灰整月柱更淡，深灰同进度柱顶部也保留圆角。
- 历史记录：统计页“本月进度对比”曾再次细调：`平均 / 本月` 标签字号加一号、对应金额字号再降一号、平均横线粗度从 `4` 降到 `3`、`分类与支出活动` 字号加一号且颜色更灰。
- 统计页“预算余量”重排为预算健康摘要：主视觉展示剩余可用和节奏状态，预算进度条内加入理想时间进度刻度，预计月底提示降级为小号辅助信息。
- 设置页新增“显示 / 金额显示”：支持金额显示保留整数、一位小数、两位小数；选择整数时可选“四舍五入、向上取整、向下取整、直接取整”。该设置只影响显示，不修改账单真实金额和计算精度。
- 金额显示设置已接入全局 `MoneyFormat.string`，首页、账单、统计、AI 回复、小组件快照等走统一格式化入口的金额会随设置变化。
- 金额搜索已补兼容 token：即使用户把金额显示改为整数，搜索仍会同时匹配当前展示金额、固定两位金额、原始 Decimal 文本和两位小数字符串，避免 `12.50` 因显示成 `¥13` 后搜不到。
- 金额显示自审补齐 3 个展示漏接点：定时记账列表摘要金额、月度报告“日均支出”、搜索页金额区间筛选 chip 均改为跟随全局金额显示设置。
- 新增小组件市场分析与产品方案文档：`docs/widget_market_analysis.md`。结论是不要继续微调单一万能小组件，后续应做 `1x1 快记入口 + 2x2 今日可花 + 4x2 月预算卡 + 4x2 分类洞察` 的小组件家族。
- 预算管理、喵助手、快记、AI 快记、明细、自动记账、占位页等二级页面显式使用统一 `AppBackButton`，避免出现系统裸返回箭头。
- 外部账单导入去重改为按已有次数消耗，修复两笔完全相同真实消费只导入一笔的问题。
- 肥喵 CSV 导出/导入继续以 `交易UUID` 和 `退款归属UUID` 作为稳定唯一 ID，避免重复统计和漏统计。
- Launcher 图标改为使用用户最新提供的图标源图重新生成；manifest 明确指向纯 PNG `@mipmap/ic_launcher_legacy`，并同步 `roundIcon`，避免小米桌面优先使用 Android 8+ adaptive XML 后把 foreground 二次放大裁切。
- Launcher 图标在用户反馈仍有细白边后，按 `1.14x` 做轻微外扩重采样，把源图外圈白底推出桌面显示区域。
- 定时记账编辑页选中分类后，分类字段不再显示 emoji 文本图标，改为复用与分类选择页一致的 `CatIcon` / SVG 图标。
- 导入复核页清理未调用的旧分类选择弹窗，待分类入口只走公共分类选择器。
- 半屏弹窗右上角 `创建 / 保存 / 全部退回 / 确认` 不再被撑成超宽大按钮。
- 新增 `test/app_buttons_widget_test.dart` 防止动作按钮回归。
- 搜索页底部输入框改为浮层，并补底部虚化过渡。
- 搜索页 `支出 / 收入` 汇总卡玻璃化，金额字重降低。
- 搜索关键词改为大小写不敏感，并兼容全角英数字；用户输入 `k12` 可以搜到备注里的 `K12`。
- 搜索页日期筛选默认今天，“回今天”改为灰底蓝字小胶囊，并在弹出日历前等待键盘收起，减少“先上再下”动画。
- AI 聊天里“已记 1 笔”的单笔账单标题字重对齐主页单笔账单标题：`bodyMedium / w400`。
- AI 聊天回复、用户气泡、系统提示中的数字统一使用 `Nunito`。
- AI 记账确认卡和已保存明细卡的“改分类”统一改为 `showCategoryPickerSheet`，与定时记账里的“选择分类”完全同一套一级/二级分类选择标准；旧的最多 6 个候选分类菜单和横向候选芯片已移除。
- 定时记账编辑页分类来源改为包含未隐藏的一二级分类，已选择子分类不会再被顶级分类列表误清空。
- AI 保存后的“今天第 N 次「某分类」”反馈按实际入账日期统计，并在入库后计算，避免第三次仍显示第二次。
- 喵助手全屏顶部改为与主页一致的渐隐虚化层，降低顶部栏与内容之间的硬切感。
- 退款弹窗里“本次退款金额”输入字重提高一档，“全部退回”等半屏弹窗右上角动作按钮字重降低一档。
- 统计页右上角报告按钮改为 `+` 图表库入口；报告查看入口归到喵助手文档库，底部“+ 自定义图表”按钮移除。
- 统计图表库弹窗改为紧凑设置行：行高降低、开关缩小、分割线更细更浅，靠近用户给的 iOS 设置参考图。
- AI 回复底部操作按钮对齐 Claude 风格：复制、播放、点赞、点踩、重试使用同一组浅灰线性图标，重试箭头改为顺时针方向，图标尺寸和间距统一。
- 年报识别补强：`年度消费报告`、`2025年消费报告` 会识别为年度报告，不会被误判成月报。
- AI 输入框空态聚焦动画二次修复：空输入时不再自动抢焦点弹键盘；用户点击输入框后键盘弹起，但猫猫和四条建议继续保留，只有开始输入文字才收起，避免“键盘有了、建议猫没了”的严重断层。
- “喵在想…”左侧猫猫尺寸从 `28` 调整为 `56`。
- 报告识别补强：`帮我生成6月的报告`、`做一份上个月的总结` 会识别为月度报告文档，不再只生成普通聊天回复。
- 首页预算进度条填充层末端改为圆角，右端与左端保持一致，同时保留整条轨道的绿→黄橙→红渐变取色。
- 统计图表库弹窗再次按参考图压缩：行高从 `58` 降到 `48`，开关缩放从 `0.82` 降到 `0.72`，分割线更浅更细。
- AI 回复底部操作按钮再次收敛：图标从 `28` 降到 `21`，描边从 `2.2` 降到 `2.0`，左右和上下留白同步缩小，避免真实聊天页里显得过大。
- Android 桌面小组件从单一总览布局扩展为多样式小组件家族：总览、快速记一笔、预算余量、分类与支出活动分别注册独立 `AppWidgetProvider` 和 provider XML；仍需小米 15 Pro 桌面实际添加截图验证。

### 5.18 本轮 `1.83.0+85` 重点变更

- AI 记账空态：点击底部输入框后键盘可以弹出，猫猫和四条建议不再因为 focus/keyboard 状态被隐藏；输入卡片空白区域也会主动聚焦，降低“第一下点不到输入框”的概率。
- 喵助手报告：报告类请求改走 `LlmQuery.askReport()` 专用 Prompt，不再复用“口语化、简短亲切”的普通查账 Prompt；要求输出完整 Markdown 文档，包含摘要、核心指标、分类分析、行为模式、异常关注和行动建议。
- 报告库卡片：改为更接近 Claude Artifacts 的白底文档卡片，文档纸张视觉更大，标题/副标题字号和间距调整；报告库内卡片支持长按菜单。
- 报告菜单：报告库长按菜单包含 `置顶/取消置顶`、`重新生成`、`删除`；置顶落库到 `reports.pinned_ms`，删除落库，重新生成会重新构造报告上下文并调用 DeepSeek。
- 统计自定义图表弹窗：从透明列表改为白底大卡片，行高、字体、分割线和右侧胶囊开关按参考图重新调整；图表名称字重减少一档。
- AI 回复底部操作按钮：复制、播放、点赞、点踩、重试再次缩小到 16dp 视觉图标，线条从 1.8 降到 1.65，颜色更浅，按钮横向留白继续收窄。
- Android 桌面小组件：新增快速记一笔、预算余量、分类与支出活动三个原生布局和 receiver，连同原总览形成多样式小组件入口。
- 当前 APK 元数据、包名、签名、label 均已验证。

### 5.19 本轮 `1.84.0+86` 重点变更

- AI 记账空态二次修复：把“点击空白关闭面板”的手势放到底层，把猫猫、四条建议和输入框放到同一个 `Stack` 上层；键盘弹出后输入框上移时，猫猫和建议仍按固定距离保留在输入框上方，只有用户真正输入内容后才隐藏。
- AI 输入框点击命中修复：输入卡片仍保留自身 `GestureDetector` 主动聚焦；上层输入框和建议按钮优先接收点击，避免第一下点到背景关闭层。
- 报告上下文闭环：补齐 `ai_chat_panel.dart` 内报告生成使用的 `_buildReportContext(...)`，报告类请求不再引用缺失 helper；上下文包含本期合计、上一等长周期、分类支出、分段支出、最大支出和最多 240 笔净额明细。
- 本轮已构建 APK，并验证 package、versionCode/versionName、label、widget component 和 Codex 测试签名。

### 5.20 本轮 `1.85.0+87` 重点变更

- AI 记账入口聚焦修复：去掉“空输入且未开始聊天时不请求焦点”的保护逻辑；AI 模式从首页输入框进入后会主动聚焦并弹出键盘，同时保留猫猫和四条建议。
- AI 回复底部 Claude 风格操作按钮回调：图标从 `16dp` 调整到 `19dp`，padding 从 `5.5/2.5` 调整到 `7/4`，避免真机上过小。
- “喵在想…”思考行微调：左侧猫猫向左贴近，文字与猫猫间距收紧。
- 报告生成稳定性：`LlmQuery.askReport()` 使用 `deepseek-v4-flash`，报告专用超时从 `30s` 提高到 `90s`，并设置 `max_tokens: 4096`；报告专用请求失败时会自动降级到普通 AI 问答接口生成完整 Markdown 报告，不再直接显示“喵没连上 AI”。
- 测试闭环：同步 DB 迁移测试到版本 `23`，并断言 `reports.pinned_ms`；本轮 `flutter test` 已全绿。

### 5.21 本轮 `1.89.0+91` 重点变更

- “喵在想…”思考行再次按真机截图微调：猫猫容器宽度从 `50` 收到 `38`，图片向左偏移从 `-8` 调到 `-18`，文字不再被推得过远。
- DeepSeek 查询请求保留主模型 `deepseek-v4-flash`，但在模型/参数类错误时自动降级到 `deepseek-chat` 兼容模型重试，降低“模型不可用”导致整条报告失败的概率。
- DeepSeek 非 200 响应会保留短错误摘要和状态码；普通查账失败时按 401/403、402/429、超时等情况给更明确的提示，方便排查 key、余额、频率或网络问题。
- 报告生成链路补第三层兜底：`askReport()` 失败后仍会尝试普通问答生成 Markdown；如果两次 AI 都失败，会基于本地账本生成一份基础版 Markdown 报告卡片，并提示可长按重新生成，不再只显示“喵没连上 AI”。
- 本轮已完成 `flutter analyze --no-pub`、`flutter test`、`flutter build apk --release`、`aapt dump badging` 和 `apksigner verify`；测试总数 246 项全绿，APK 元数据为 `1.89.0+91`。

## 7. 仍需重点人工/真机复核

这些不是说一定没修，而是用户多次反馈过，必须在接手后优先验证：

- 安装后 Launcher 图标是否与用户最新图标完全一致，无白边、无异常裁切。
- 当前机器 AVD 未能注册 adb device，启动与截图验证未完成；需要用户真机安装复核。
- 首页顶部虚化是否真正像 GPT/iOS 顶部材质，而不是灰底或硬切。
- 首页 `全部 / 支出 / 收入` 横条与大卡片、账单卡片之间的距离是否一致自然。
- 搜索输入框是否与主页输入框完全同标准，发送按钮有内容时是否变黄色。
- 搜索页底部输入框和顶部支出/收入卡片是否有自然虚化过渡。
- AI 回复中的数字字体是否全部为 `Nunito`。
- 手动记账与 AI 记账切换是否仍有明显卡顿。
- 导入后抽屉右滑是否仍明显卡顿，尤其是 2200 条账单导入后。
- 支出构成是否还会出现两个“其他”。
- 分类排行是否真正对齐咔皮标准。
- Android 桌面小组件已完成一期实现；仍需在小米 15 Pro 桌面验证能否添加、刷新、缩放，以及隐私模式是否不显示具体金额。
- 小组件多样式重设计尚未完成；如果继续处理，不能只微调 `widget_feimiao.xml`，需要按产品方案拆成多个布局和多个 provider/preview。
- 退款导出再导入后是否仍保留退款关系。
- 所有半屏弹窗右上角动作按钮是否都是紧凑小胶囊，没有再次炸宽。
- 分类选择、定时记账、新建账本等弹窗是否符合统一 `SheetHeader` 标准。

## 8. 接手后的推荐流程

1. 先执行 `git status`，确认当前工作区有哪些未提交改动。
2. 只改 `C:\src\xunni-codex\android-app`，不要碰 `C:\src\xunni`。
3. UI 改动优先复用现有全局组件：
   - `AppCircleButton`
   - `AppPillButton`
   - `SheetHeader`
   - `BookSwitchChip`
   - 主页输入框相关组件
4. 如果用户要求“减少 w100”，按相对字重下降一档处理。
5. 涉及数字、金额、百分比时，确认 `Nunito` 是否覆盖。
6. 新增 APK 前递增版本号，并同步三处版本文件。
7. 构建前至少跑：
   - `analyze --no-pub`
   - `flutter test`
   - `build apk --release`
8. 构建后验证：
   - package 仍为 `com.qingji.qingji.codex`
   - label 仍为 `肥喵记账`
   - 签名仍为 `CN=Feimiao Codex Test`
9. 用户强烈关注视觉细节，凡是 UI 改动都要尽量真机或模拟器截图验证。

## 9. 历史关键里程碑

| 版本 | 重点 |
| --- | --- |
| `1.37.0+39` | AI/手动切换第一轮性能优化，减少路由切换闪回和键盘 inset 跳动 |
| `1.46.0+48` | 保留虚化和猫动效的前提下继续优化切换性能，分类区改懒加载 |
| `1.51.0+53` | 新增 `record_entry_sheet.dart`，同一路由内切换 AI/手动，明显降低 jank |
| `1.55.0+57` | 首页筛选条间距修正，分类排行固定前 5 条 |
| `1.57.0+59` | 应用名、图标和首页间距调整，安装与签名验证 |
| `1.61.0+63` | 半屏弹窗按钮规格回退为紧凑标准，备份入口补齐 |
| `1.62.0+64` | 修复右上角动作按钮炸宽、搜索页虚化、AI 数字字体 |
| `1.77.0+79` | 金额显示设置收尾，补金额搜索兼容 token，确保整数显示后仍可搜原始两位金额 |
| `1.78.0+80` | 补齐金额显示设置的展示漏接点：定时记账、月度报告日均、搜索金额区间 chip |
| `1.79.0+81` | 喵助手报告类回答升级为 Markdown 文档产物底座，新增报告库、报告阅读页和 reports 持久化表 |
| `1.80.0+82` | 修复报告生成失败态误入库风险，优化报告卡片摘要提取并补齐报告纯函数测试 |
| `1.81.0+83` | 喵助手顶部虚化、统计图表库入口、退款弹窗字重、图表库紧凑 UI、AI 回复底部 Claude 风格操作按钮 |
| `1.82.0+84` | 修复报告生成漏判、AI 输入框聚焦动画、喵在想猫尺寸、预算进度条末端圆角、图表库行距、AI 操作按钮过大 |
| `1.83.0+85` | 修复 AI 空态聚焦后建议猫消失；报告卡片/菜单/专用 Prompt；统计图表库白底大卡片开关；多样式 Android 小组件；AI 操作按钮再缩小 |
| `1.84.0+86` | 二次修复 AI 记账键盘弹出后猫/建议消失；补齐报告上下文 helper；完成 release APK 构建与包签名校验 |
| `1.85.0+87` | 修复 AI 入口不弹键盘、操作按钮过小、喵在想布局；报告生成增加 90 秒超时、max_tokens 和兜底调用；全量测试绿 |
| `1.89.0+91` | 思考行猫猫再左移、文字更贴近；DeepSeek 模型兼容重试；报告 AI 失败时生成本地基础版报告卡 |

## 10. 文档维护规则

- 以后不要再把每次尝试按时间线无限追加到文件顶部。
- 同一功能如果改过多次，只保留最新结论。
- 每次交付 APK 时更新：
  - “当前交付状态”
  - “历史重点修复索引（旧摘录，非当前 APK 状态）”
  - 必要时更新“仍需重点人工/真机复核”
- 如果某个问题被用户再次截图指出，不要只写“已修复”，要在对应章节补充“重点复测”。
## 2026-07-10 分类图标最终语义微调（Codex）/ 1.169.0+171
- 根据用户人工复核 133 个分类图标后的反馈，本轮只改两个仍有误读风险的图标，不再动已验收的交通大类图标。
- `car_wash`（洗车）：三套资源目录同步从“大水滴压车身”的旧造型，改为更明确的低矮车头 + 水流线 + 小水滴，避免小尺寸下误读成餐盘盖/餐饮类。
- `car_toll`（过路过桥）：三套资源目录同步保留道闸杆，同时补充小收费岗亭、窗口和底部线条，让“收费站/过路费”语义比单根斜杆更明确。
- 影响范围仅限 SVG 资源：`assets/cat_icons/`、`assets/cat_icons_filled/`、`assets/cat_icons_line/` 下的 `car_wash.svg`、`car_toll.svg`。未改分类 key、数据库、统计、导入导出或图标风格切换逻辑。
- 顺手修复已有更新模块 analyze 阻断：`lib/core/update/app_update.dart` 中外部缓存目录选择从三元表达式改为显式 `if/else`，避免 `externals.first` 被推断为 `Object` 后 `dir.path` 报错；更新下载逻辑不变。
- 版本同步递增到 `1.169.0+171`：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart`、`android/local.properties` 均已更新，build tag 为 `b0710-171`。
- 验证：`flutter analyze --no-pub` 通过；`flutter build apk --release --no-pub` 成功；APK 内部资源抽查确认 6 个目标 SVG 均已打包，且保留顶部高光。
- APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.169.0-171.apk`，大小 `111,409,563` 字节，SHA256：`50AD0848FE416288B434A8ABFE93FE30B75113B0C9C8E9EFDCFFC09755A04722`。`aapt dump badging` 确认 `com.qingji.qingji.codex` / `versionCode=171` / `versionName=1.169.0` / 应用名 `肥喵记账`；`apksigner verify --print-certs` 确认证书仍为 `CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`。
- 本地对比预览：`C:\Users\寻逆啊\Documents\Codex\2026-07-04\xian\outputs\icon_refine_car_wash_toll_compare.svg`。
## 2026-08-16 v1.222.0+235（AI 兼容性审查修复，待用户安装验收）

- 修复模型管理刷新会复活用户已删除模型；跨服务商模型列表可滚动并显示服务商；AI 输入字段统一回到主题透明填充。
- 修复清空/新增/删除服务商后的即时回退与模型校正；仅改元数据不再误重置隐私授权。
- Claude 原生请求尊重显式 endpoint，统一 thinking budget、`max_tokens` 和 `temperature`；Effort 保留关闭、Minimal、Low、Medium、Extra、Max、Ultra 全档位。
- 闲聊分流补齐今日/昨日/近 N 天，购买建议不再误走普通记账，无问号账本摘要可以查账。
- 清理本轮可再生 Flutter/Gradle/Dart 缓存、日志和旧重复 APK；移除被误跟踪的 `.wrangler` 账号缓存并加入忽略规则，保留当前包与上一包作为回退。
- 定向测试：AI provider 56/56、意图/日期/模型接口 47/47、AI 核心 77/77、AI Chat Widget 31/31；静态分析 0 error。
- 全工程 959 项实际执行，954 通过；5 项既有资产页/月份轴/性能基线失败未混入本批修复。Release APK 已归档：113,682,307 字节，SHA256 `889D493B04232C2B6B807E74CC39A1764786B8B9555815287559E0685F622ED9`，包名/版本 `com.qingji.qingji.codex / 1.222.0 / 235`，16 KiB 对齐、V2 签名和固定证书通过。真机、真实 provider API 和截图未验证。
## 2026-08-21 v1.231.0+244 喵助手模型布局与模型获取修复（Codex，本地待验包）

- **输入区布局**：模型名与思考强度保持 6dp 紧凑间距，模型名使用可用宽度完整缩放；模型/思考强度组不再与 Spacer 平分宽度，发送按钮继续固定右边界。
- **Chats 字阶**：标题调整为 19px / w400；设置页模型列表同步放大一号。
- **模型获取**：自定义 OpenAI 兼容中转即使使用 Claude 模型名也继续使用 Bearer；仅官方 Anthropic 端点发送原生 Claude 请求头。
- **验证**：待本轮 analyze、全量测试和 release APK 验包完成后补齐证据。
## 2026-08-24 v1.242.0+255 OAuth 网络路径与输入框字号修复（Codex，待用户真机验收）

- **OAuth 网络路径**：Android GPT OAuth 使用 Chrome Custom Tabs，沿用系统 Chrome 的 Cookie、代理和出口网络；PKCE/state、1455/1457 localhost 回调、恢复重绑、Token 刷新、GPT 模型目录和粘贴回调兜底保持不变。
- **输入框布局**：全屏输入区移除多余 `Spacer`，模型名称不再被压缩到约 4px；输入框模型名称为 `19px`，`High/Low` 思考强度为 `16px`，模型列表为 `15px`；选中时才显示灰底，Effort 滑块不变。
- **验证**：构建前重新执行 analyze、全量 Flutter 测试和 release APK 门禁；真实 Android OAuth、provider 网络和 IME 仍需用户安装后验收。
- **版本同步**：`pubspec.yaml`、`lib/core/app_version.dart`、`lib/build_info.dart`、`android/local.properties` 同步为 `1.242.0+255` / `b0824-255`。
## 2026-08-24 v1.242.0+255 OAuth 网络路径与输入框字号修复（Codex，本地交付候选）

- **OAuth 网络路径**：Android GPT OAuth 使用 Chrome Custom Tabs，沿用系统 Chrome 的 Cookie、代理和出口网络；PKCE/state、1455/1457 localhost 回调、恢复重绑、Token 刷新、GPT 模型目录和粘贴回调兜底保持不变。
- **输入框布局**：全屏输入区移除多余 `Spacer`，模型名称不再被压缩到约 4px；输入框模型名称为 `19px`，`High/Low` 思考强度为 `16px`，模型列表为 `15px`；选中时才显示灰底，Effort 滑块不变。
- **验证**：analyze exit 0（28 条既有 info）；串行全量 Flutter 测试 **1048/1048**；release gate **9/9**；APK 身份门禁通过（包名、版本、16 KiB 对齐、APK V2、固定证书）。真实 Android OAuth、provider 网络和 IME 仍需用户安装后验收。
- **交付**：APK `C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.242.0-255.apk`（114,902,818 字节），SHA256 `2a7177a0e3cc26bd9cea048f79b01247983d2adedd5e14afaa9ea7be367c091e`；源码仍未提交、未推送、未发布线上。
## 2026-08-25 v1.250.0+263 GPT OAuth 原生回调竞态与流隔离最终收口（Codex，本地交付）

- **停止竞态修复**：OAuth 保活停止改为 `stopService()` + 有界等待，不再发送会与 `startForegroundService()` 竞争的 STOP Intent；MainActivity 的停止等待放到后台线程。
- **恢复稳定性**：启动时先按当前 OAuth state 检查 ready 标记并做真实 `127.0.0.1` TCP 探测，健康监听直接复用，Activity 重建不会制造新的拒绝窗口。
- **回调隔离**：ready 标记携带 flow/state；原生服务仅接受当前 state，错误 state 返回 400，不覆盖已有 callback；新授权会清理废弃回调；监听只绑定回环 IPv4，IPv6 仅作附加监听。
- **设备级证据**：在线模拟器安装/冷启动成功；真实 Chrome Custom Tab 打开官方授权 URL，`:oauth` 前台服务 `startForegroundCount=1`；端口转发访问 1455 的错误 state=400、正确 state=200；无 `ForegroundServiceDidNotStartInTimeException`。
- **验证**：全量 Flutter 测试 **1051/1051**；`flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` exit 0（33 条既有 info）；Gradle `:app:assembleRelease` 成功；APK 包名 `com.qingji.qingji.codex` / versionName `1.250.0` / versionCode `263`，16 KiB 对齐与 V2 签名通过。
- **交付**：APK `[feimiao-codex-v1.250.0-263.apk](C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.250.0-263.apk)`（115,970,438 字节），SHA256 `B2FDF2AF9BCADD5AAAD82529655905CAAD5B640F16E4BEC8010CB5B8B8F70568`；证书 SHA-256 `4e99c399d4d246bd9c6b08b1d641248bd0846e7ae650c3a766e30fa67483d507`。
- **边界**：模拟器未执行真实 ChatGPT 账号交互，因此 Token 交换、官方模型列表非空和 Responses 实际回复待用户在可联网设备登录后确认；源码未提交、未推送、未发布线上。
## 2026-08-26 v1.257.0+270 Claude/iOS 弹窗与 AI 回复体验收口（Codex，本地交付候选）

- **统一弹窗**：全局 `showIosMenu` 改为 Claude/iOS 风格中性灰遮罩、锚点镂空、磨砂圆角、缩放淡入和统一细线图标；长按菜单、Chats 菜单、模型/Effort 选择共享同一视觉壳，点击带震动反馈。
- **消息操作**：长按自己发送的消息原位放大约 1.18 倍并高亮，显示发送时间，支持复制、编辑、选择文本；选择文本直接在原消息气泡内调用系统选区，不再出现居中白框，也不提供重复发送。
- **思考与来源**：思考中显示动效，完成后显示思考耗时并可展开简短过程，过程与正文用灰线分隔；来源 favicon 和数量放在回答操作栏最右侧，正文不再追加来源段落。
- **图片与排版**：发送图片保留真实缩略图，三张图片同排，超出数量可横向滑动；Markdown 表格按列对齐并支持横向滚动，短回复底部留白保持收紧。
- **验证**：Claude/Chats 定向 **18/18**；串行全量 Flutter **1084/1084**；`flutter analyze --no-fatal-infos --no-fatal-warnings` exit 0（40 条既有 info/warning）。
- **交付**：Release APK `C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.257.0-270.apk`，116,937,094 字节，SHA256 `C168DBC4E3A93784B4320736AD4A232D9290B97E7D7E6B9DDEC320E9B333120B`；release identity gate 已确认 `com.qingji.qingji.codex / 1.257.0 / 270`、16 KiB 对齐、APK V2 和固定 Codex 证书均正确。
- **运行态边界**：本机无在线 Android 设备，真实 provider/OAuth、IME、相册权限和安装冷启动仍需用户设备验收；源码未提交、未推送、未发布线上。
## 2026-08-28 v1.265.0+279 OAuth 稳定性与性能专项

- GPT OAuth 按 Cockpit 当前流程补齐 `chatgpt.com/codex/desktop-auth` hosted 登录封装、客户端版本/稳定 ID 参数和官方桌面身份头。
- 浏览器已成功回调但 Token 交换失败时，保留回调状态并对瞬时网络/网关错误做有界重试；Android keep-alive 会清理旧流程残留 callback 文件，避免新授权被旧状态吞掉。
- 账号刷新增加并发写入保护，旧 refresh 结果不能覆盖用户刚完成的新授权。
- 指定账本记录流按数据版本缓存，喵助手建议不再每次打开都排序全量账单；10k 流水重复 `recordsForBookView` 从约 3.8–5.0s 降至约 0.10–0.16s。
- Gemini 授权调研记录见 `docs/oauth-gemini-research-2026-08-28.md`；本版本不内置 Cockpit/Antigravity 私有 Google OAuth client secret。

## 2026-08-28 v1.265.0+279 Android CI 编译修复与 iOS 首页入口对齐

- **Android CI**：升级 Workmanager 到 `0.10.9`（Android 实现 `0.10.8`），修复 AGP 9 + `android.builtInKotlin=false` 下 Kotlin 插件未编译、`GeneratedPluginRegistrant.java` 找不到 `WorkmanagerPlugin` 的 clean-runner 错误；上游修复对应 Workmanager #722。
- **iOS 首页**：移除首页与安卓主流程冲突的快捷操作卡，补齐顶部菜单/搜索/账本入口、收支筛选和底部「记一记」输入框；手动/AI 分流保留 iOS Liquid Glass 和原生按压反馈。
- **路由与截图门禁**：设置深链改为目标值绑定，iOS 截图脚本新增内容区非空检查；冷启动截图等待时间延长，避免保存白屏 PNG 冒充通过。
- **本地验证**：Android debug APK 构建成功；Flutter analyze 无 error；全量 Flutter **1127/1127**。iOS 需由 macOS CI 完成编译和截图复验。
## 2026-08-28 v1.266.0+280 OAuth 等待窗口与性能收口

- GPT OAuth 浏览器 pending 有效期与 Cockpit 对齐为 10 分钟，Android 原生回调监听保留 1 分钟收尾余量；回调持久化、临时失败重试和旧 state 清理继续保留。
- 喵助手建议缓存使用仓库对象身份比较，避免极低概率的 identity hash 复用导致跨仓库显示旧建议。
- 性能专项最终验证见 `docs/performance-review-2026-08-28.md`；本包包含账本视图缓存、稳定顺序上下文和重复排序削减。
## 2026-08-29 v1.271.0+285 OAuth/账号 JSON 网络与兼容修复

- **OAuth 浏览器路由**：Android 继续优先 Ephemeral Custom Tab/Chrome 无痕；普通兜底改为指定 Chrome，再最后才交给系统通用浏览器，避免已安装 ChatGPT/OpenAI 应用抢占 `auth.openai.com` 后直接复用个人空间。
- **网络路径**：启动时读取 Android 系统 HTTP 代理并接入 Dart `HttpClient`；OAuth Token、模型目录、Responses 和其它 AI 请求跟随系统代理；`localhost`/`127.0.0.1` 回调始终直连，VPN TUN 全局模式不受影响。
- **Cockpit JSON**：兼容嵌套 `tokens`/`credentials`、`personal_access_token`、Bearer 请求头、`session_json`/`session`、嵌套账号身份、UTF-8 BOM/UTF-16 和键控账号对象；Agent Identity 会明确提示当前 Android 不支持，避免导入后伪装成可用账号。
- **模型目录**：没有 `account_id` 时不再本地提前失败，允许官方接口根据 Token 判断；access-token-only 账号可继续尝试模型目录。
- **验证**：真实 Cockpit 文件解析/落库通过；有效账号官方模型目录 HTTP 200（6 个模型）；官方 Responses HTTP 200，收到输出增量和完成事件；OAuth/JSON/系统代理/设置页定向回归通过。完整套件保留 1 个既有资产测试的定时器清理失败，单独复现通过。
## 2026-08-29 v1.272.0+286 GPT OAuth 与 Cockpit JSON 导入稳定性修复

- **授权入口**：恢复官方直达 `auth.openai.com/oauth/authorize` 的 PKCE 流程；`chatgpt.com/codex/desktop-auth` 不再作为前置授权页，避免已登录浏览器直接复用个人空间；Android 仍优先使用 Ephemeral/无痕 Chrome，并保留账号选择参数。
- **授权恢复**：Token 交换成功先保存凭据，模型目录获取失败不会回滚登录；系统代理在请求前动态刷新，VPN/代理晚于应用启动时也能被后续 OAuth、模型和 Responses 请求接管。
- **JSON 导入**：修复共享 workspace `account_id` 导致多账号被合并；兼容 Cockpit/CPA `token_data`、JSON Lines、嵌套字符串 payload、UTF-8 BOM/UTF-16；API Key 导入缺少地址/模型时使用官方默认值。
- **批量导入**：多账号导入不再对每个账号逐次重写整份索引或拉取模型目录，完成后一次提交，避免大文件长时间卡住。
- **验证**：OAuth/JSON/代理/设置/模型目录定向回归 78 项通过；串行全量 Flutter 测试和 Release 包门禁随后执行。
## 2026-08-30 v1.276.0+290 GPT OAuth 与 Cockpit JSON 最终修复

- **Android OAuth 改用官方设备授权码流程**：使用 `auth.openai.com/api/accounts/deviceauth/usercode` 获取一次性授权码，授权页为官方 `codex/device`，完成后轮询官方设备 Token 接口；不再依赖 Android 后台期间可能被回收的 localhost:1455 回调。设备码轮询的 403/404 等待语义、PKCE 字段校验、`deviceauth/callback` Token 兑换与 Cockpit 当前实现一致；原有桌面/手动 localhost 回调继续保留。
- **账号身份与模型恢复**：Token 响应邮箱回填到账号身份；主页普通记账、报告、设置连接测试和喵助手请求遇到 Codex `400/404` 不支持模型时，会重新获取该账号官方模型目录并自动重试可用模型。附件记账、JSON 导入后的首次请求也会走动态系统代理刷新。
- **Cockpit/CPA 导入**：完整备份只导入 Codex `exported_data`，PAT 先按官方 `whoami` 获取工作区 ID；共享 workspace 的不同邮箱分别保留，API Key 目录过滤内部 `codex-auto-review`，refresh-only 账号首次请求前自动换取 access token。
- **验证**：OAuth `19/19`、Cockpit JSON/AI/模型目录 `44/44`、仓库导入 `3/3`、Flutter 全量 `1168/1168`；Dart analyze 无 error（86 条既有 warning/info）。本机真实 Cockpit 备份解析 10 个 Codex 账号（5 OAuth、5 API Key）并完成仓库重启持久化验证。
- **APK**：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.276.0-290.apk`，117,526,965 字节，SHA256 `F762CA8B5E5C478A55EEFB879F5549E66C81662CD1838CBD5347D1AD2CD9D8DF`；16 KiB 对齐、APK V2 和固定证书 gate 通过。
- **真实账号边界**：使用用户授权的测试 Google 账号完成官方授权页、账号选择和 localhost 回调可达性验证，未使用 Plus 账号；当前终端无官方 HTTPS 出口、无在线 ADB，真实 Android 手机的 Token/模型/Responses 出口和 VPN 分流仍需安装后复测。
