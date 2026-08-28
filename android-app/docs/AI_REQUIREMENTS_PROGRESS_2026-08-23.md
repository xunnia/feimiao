# AI 需求进度表（2026-08-28，v1.263.0+277）

> 本表只追踪本轮截图/会话中用户明确提出、且当前批次需要闭环的需求。`实现` 不等于 `验收`，`验收` 不等于 `交付`。

## 最新验收（2026-08-28，v1.263.0+277）

### 2026-08-28 深度审计补修（v1.263.0+277）

- **OAuth 首次请求**：Cockpit refresh-only 账号仅有 `refresh_token` 时，首次模型目录/请求前会强制交换 access token；报告、隐私确认、账单复核和快速记账统一用 `hasCredential`，不再只看 API Key。
- **报告思考时长**：`model_started_ms` 延后到真正调用模型前 CAS 写入；后台 Worker 使用同一时点，恢复未开始模型的队列不伪造创建时间；并发 CAS 输家回读并同步持久化赢家。
- **回复与字体**：`SelectableText.rich` 明确固定 Nunito + Noto Sans SC fallback；裸来源 URL 不再出现在正文，来源留在操作栏/可上拉面板；URL 后中文标点不会吞正文。
- **截图证据**：思考、来源、三图与 Claude 加号截图均带实际暖背景并人工查看；Claude/Chats 视觉回归 **16/16**。
- **验证**：analyze 无 error（60 条既有 warning/info）；最终源码全量 Flutter **1118/1118**；Claude/Chats 视觉 **16/16**；Release identity gate 通过。

- **三阶段方案与 8-27 需求**：第一批正确性/安全、第二批体验/效率、第三批受控扩展及 Obsidian 8-27 图文需求均已实现；插件、连接器和本地 companion 均为白名单/显式控制，账单写入必须结构化提案、确认、原子提交并可撤销。
- **隐私边界**：AI run/event 不保存原始 prompt、凭据或 reasoning 文本，只保存必要摘要/字符数；上下文按轮压缩并受预算限制。
- **本轮补修**：草稿附件累计添加统一限制每条消息最多 3 张图片/10 个文件（文件选择器中的图片也计入）；报告任务新增 DB v48 `model_started_ms`，首次模型处理时间以 compare-and-set 持久化，恢复 Chats 不重置思考计时。
- **验证**：Dart analyze 无 error（57 条既有 warning/info）；全量 Flutter **1114/1114**；定向 AI/UI/会话/图片/思考/来源/模型/菜单及 Claude/Chats 视觉回归通过。
- **Release gate**：`com.qingji.qingji.codex` / versionName `1.262.0` / versionCode `276`；16 KiB 对齐、APK V2、固定证书通过。
- **APK**：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.262.0-276.apk`，117,071,394 字节，SHA256 `A3839FFBBE94104866888EA73A0ECBD7A303C2E6A67AE4447FEFE41B18268A6B`。
- **外部边界**：本机无在线 ADB；真实 ChatGPT OAuth、Token 交换、provider 网络、系统相册/文件选择器、IME、安装冷启动和真机视觉仍需用户设备验收。

## 历史验收（v1.260.0+274）

- **版本**：`1.260.0+274`，build tag `b0827-274`，DB v46；本批源码、测试和文档保持在当前工作树，未提交、未推送、未发布线上。
- **请求可靠性**：`AiRequestManager` 已补齐请求 ownership；旧请求的 `finally`、延迟 Token、停止回调不会清理或消费新流程，同一 task 的取消与重试不会互相污染。
- **后台报告可靠性**：报告交给 WorkManager 后保留 flow ownership，发送 Future 返回不会终止思考计时器或完成轮询；任务完成/失败或 120 秒 UI 交接后才释放，失败 flow 不会残留。
- **图片流程验收**：离屏截图改用真实封面文件并等待 `Image.file` 解码；已发送三图真实可见，输入框草稿首屏展示三张，第四张可横向滑动查看。
- **本轮补修**：整条前台 AI 流程及解析/附件请求增加 120 秒超时，避免永不结束的传输永久停留在思考态；三图消息按参考图采用聊天内容区满宽的方形三等分卡片，保留两侧边距和卡片间细间距。
- **设置页字号**：模型列表和手动模型输入统一为 `15px`、`w300`；输入框底部模型名称/Effort 的既有字号和对齐标准保持不变，并新增 Widget 回归断言。
- **自动验证**：串行全量 Flutter **1094/1094**；AI 请求/重试/Responses **36/36**；AI/UI/会话/图片/思考/来源/模型/菜单 **104/104**；严格 Claude/Chats 视觉 **16/16**；静态分析 exit 0（45 条既有 info/warning）。生产历史区三图边界、恢复竞态和思考状态回归通过。
- **Release gate**：Gradle `:app:assembleRelease` 成功；包名 `com.qingji.qingji.codex`、versionName `1.260.0`、versionCode `274`、16 KiB 对齐、APK V2、固定证书均通过。
- **APK**：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.260.0-274.apk`，116,446,150 字节，SHA256 `2A603BF8B063F26D6FD393591D7440275FE652CE81EA6CA6935595A1E85F36EA`。
- **未替代的真机验收**：本机无在线 ADB，真实 ChatGPT OAuth/Token 交换、官方模型目录、provider Responses、IME、系统文件选择器、相册权限和 Android 字体观感仍需用户在可联网设备安装后确认。

## 历史批次对照

| 需求 | 实现 | 自动验证 | 运行/截图验证 | 交付 |
|---|---|---|---|---|
| 主页「AI 记账」按钮恢复自适应宽度 | 已完成 | Widget/布局断言 | 输入框截图已复核 | v1.242.0+255 |
| 主页 AI 记账任何非空输入直接进入 AI 记账请求，不做本地意图拦截 | 已完成 | `_send` 路由 + `forceRecord` 代码审计、全量回归 | 离屏输入区已复核；真实 provider 待真机 | v1.242.0+255 |
| 主页/喵助手输入框尺寸、透明度、模糊和发送按钮对齐 | 已完成 | 输入框 golden/几何断言 | 当前源码截图已复核 | v1.242.0+255 |
| AI 账号卡去箭头、删除按钮左置变灰、开关右置、字体变细 | 已完成 | 账号页 Widget 断言 | 账号截图产物已复核 | v1.242.0+255 |
| 加号、模型名称、思考强度同水平/间距/左下位置 | 已完成 | 输入框 alignment 测试 | 当前源码截图已复核 | v1.242.0+255 |
| 输入框模型名称 19px、思考强度 16px；模型列表 15px | 已完成 | 全量测试中的字号断言 | 模型/Effort golden 已复核 | v1.242.0+255 |
| 普通问答取消强制排版与“简短”性格 | 已完成 | Prompt 回归 | 待真实模型抽查 | v1.242.0+255 |
| 喵助手加号面板全局联网搜索开关（供应商页移除） | 已完成 | 全局持久化、请求体和会话配置测试 | 待真实网络端到端 | 本轮源码 |
| Claude 风格 Add to Chat 比例、背景模糊和功能归位 | 已完成 | 390×844 整屏 golden、结构回归 | 已查看整屏截图 | 本轮源码 |
| 近期图片默认横向展示并支持滑动 | 已完成 | 近期图片 rail/尺寸/滑动回归 | 已查看近期图片整屏截图；真机相册权限待验 | 本轮源码 |
| Tool access（Auto/Off）及账本、记账、图片、联网工具说明 | 已完成 | UI 选择、全局权限和持久化测试 | 待真实模型端到端 | 本轮源码 |
| GPT OAuth 授权、回调、Token 刷新 | 已完成 | PKCE/state、Mock/协议单测 + flow generation/ownership 竞态回归 **11/11** + Chrome Custom Tabs/localhost 回调配置 | 新包真实账号 Android 回调待用户设备；本机 AVD 持续 offline | v1.251.0+264 |
| OAuth 后真实获取 GPT 模型目录 | 已完成 | Mock 目录/Token/模型保留测试 | 待真实账号接口 | v1.251.0+264 |
| Cockpit/OpenAI/Sub2API AI 账号 JSON 导入导出 | 已完成 | 解析、重复账号冲突、OAuth/API Key 安全存储、仓库往返测试；账号页定向回归 | AVD 安装后冷启动通过；真实账号导入与模型网络待用户设备 | v1.252.0+265 |
| 最终全量门禁（分析、测试、golden、构建） | 已完成 | analyze exit 0（33 条既有 info）；全量 **1059/1059**；Claude/输入框/账号页定向回归；Gradle release 成功 | APK 已在 16037 ADB 模拟器安装并冷启动 | v1.252.0+265 |
| 最终版本、APK、签名/哈希和交接记录 | 已完成 | release identity gate 通过：包名/版本、16 KiB 对齐、APK V2 固定证书；115,511,398 字节，SHA256 `08E43A3816B6A8832CAC46DDF165A1B7D12F97BADE2AF124F710EE8C28528DD5` | 真实 ChatGPT OAuth、Token 交换、官方模型目录和 Responses 请求仍需用户联网设备验收 | v1.252.0+265 |
| 本轮 OAuth/主页 GPT/喵助手修复与出包 | 已完成 | OAuth 401 强刷与模型目录重试、Responses JSON Schema、透明设置输入框、88dp 回弹限制；analyze exit 0；全量 **1059/1059**；release gate 通过 | 本轮无在线 ADB 设备；真实 ChatGPT OAuth、官方模型目录和 Responses 请求仍需用户联网设备验收 | v1.253.0+266 |

| 本批十项 AI 体验需求与最终出包 | 已完成 | 思考摘要/来源、长按消息、回复排版/表格、模型/Effort、首条 ready barrier、Claude 加号/图片流程和服务商卡片边界；analyze exit 0；全量 **1065/1065**；release gate 通过 | 本机无在线 ADB；真实 provider、OAuth、IME、相册权限和字体观感仍需用户设备验收 | v1.255.0+268 |

## 当前阻塞与边界

- 普通聊天排版已取消；月报/周报/年报继续使用独立报告模板，除非用户另行要求取消。
- 真实 GPT OAuth 需要用户自己的账号和 Android 浏览器/设备；本地 Mock 不能替代这一步。
- 离屏截图已注册 Nunito、Noto Sans SC CJK fallback、Material/Cupertino 图标字体；中文和图标方框问题已修复，字体最终观感仍需真机验收。
- 真实 provider 网络、Android IME 和 OAuth 浏览器回调不能由本地单测替代，交付后需用户设备验收；OpenAI `unsupported_country_region` 属外部网络限制，不等于 localhost 回调失败。
- 本轮只生成本地 APK，不推送远端、不发布线上版本；本轮新包完成后作为当前本地交付候选，v1.260.0+273、v1.259.0+272 和 v1.254.0+267 均保留作回退。真实 ChatGPT OAuth、provider 网络、账号文件导入和真机 UI 仍需用户在可联网设备完成最终验收。
