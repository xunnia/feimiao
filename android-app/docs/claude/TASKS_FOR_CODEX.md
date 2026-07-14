> **当前状态提醒（2026-07-10）**：本文件是历史任务书，不再是 Claude/Codex 新会话的默认开工清单。新会话必须先读 `docs/claude/CLAUDE_START_HERE.md`。只有用户明确点名“按 TASKS_FOR_CODEX.md 的某个任务做”时，才读取并执行本文对应任务。

---
# Claude → Codex 任务书

> 维护者：Claude（架构/验收）。Codex 每一批开工前先读这份，按顺序做，做完一批停下等验收。
> 分工已由用户拍板（2026-07-09）：**Codex 负责实施；Claude 负责需求拆解、方案设计、数据层改动和交付验收。**

---

## 一、流程规矩（每一批都适用，长期有效）

1. **出包前必须全量验证**：`flutter analyze --no-pub` 0 error + `flutter test --no-pub` 全绿。
   之前"sqlite3.x64.windows.dll 下载超时跑不了测试"的问题已由 Claude 修复（DLL 已放进
   `.dart_tool/hooks_runner/shared/sqlite3/build/download-563a01a5/`；若 `.dart_tool` 被清理导致 DLL 丢失，
   从 `C:\src\xunni\android-app\.dart_tool\hooks_runner\shared\sqlite3\build\download-563a01a5\sqlite3.dll` 再复制一份）。
   **测试跑不了 ≠ 可以跳过测试**。
2. **每交付一个 APK 就 `git add -A && git commit`**（本仓已有 git，2026-07-09 之前 2.2 万行一直悬在工作区，太危险）。
   commit message 用中文描述式，带版本号和 build tag。**不要 push**，推送由用户决定。
3. **数据层红线**：`app_repository.dart` 的迁移（`_onUpgrade`）、退款/报销逻辑、统计口径（LedgerPolicy）
   ——没有任务书明确授权**不许改**。任何"扫全库改写历史数据"的想法先停下来写进 CHANGELOG 提问，等 Claude 评审。
   教训：`_normalizeStandaloneRefunds` 第一版用打分启发式猜测归并，会把用户的收入行静默吃掉，已被推翻重写。
4. **验收流**：每批做完 → 更新 `CHANGELOG_CODEX.md`（沿用现有格式）→ 用户会让 Claude 审 diff + 跑测试 → 过了才算完成。
5. 版本规则沿用现状：出包时 `pubspec.yaml` / `lib/core/app_version.dart` / `lib/build_info.dart` 三处同步，minor+1、versionCode+1。
6. **签名铁律（2026-07-09 用户拍板：codex 签名即正式签名）**：用户日常主用的就是本仓出的包
   （`com.qingji.qingji.codex`），所以**所有后续 APK 必须继续用
   `android/app/codex-upload-keystore.jks`（alias `codexupload`，`android/key.properties` 指向它）签名**。
   不许换证书、不许改 applicationId、versionCode 只增不减——任何一条破了都会导致用户无法覆盖安装、
   卸载重装=账本数据丢失。该 keystore 被 gitignore（git 里没有副本），备份在
   `C:\Users\寻逆啊\Desktop\记账app\签名备份\`；如果发现 keystore 丢失，先从备份恢复，**绝不许新生成一个顶上**。

---

## 二、当前批次任务（2026-07-09 第二批）

### 任务 3【本批唯一任务】：小组件推倒重做——不再仿制，改「真组件离屏渲染成图」

**背景与架构决定（Claude 拍板，不要再走老路）**：之前 4 轮（1.149→1.152）用原生 RemoteViews XML
手工仿制主页卡片，用户始终不满意——因为主页大卡片是带探头猫、圆角阴影、Nunito 数字字体、
预算态切换的完整 Flutter 组件，RemoteViews 的白名单控件永远仿不到一比一。
**新路线：Flutter 侧把「真实组件」离屏渲染成 PNG，原生小组件只负责显示这张图 + 接点击。**
同一份代码画主页也画小组件，一比一是构造出来的，不是调出来的。

**用户明确要求（2026-07-09）**：至少两个小组件按此重做——
① 总览小组件 = 主页大卡片（`home_view.dart` 的 `_ExpandedSummaryCard`）尽量一比一；
② 本月进度小组件 = 统计页「截至今日」进度卡（`statistics_view.dart` 的 `_MonthlyPaceCard`）。
分类活动 / 快捷记账两个小组件本批不动。

**实施步骤**：

1. **抽共享组件（纯重构，不许改观感）**：
   - 把 `_ExpandedSummaryCard` 的卡片本体（Card+月份胶囊+统计胶囊+收支双栏/预算体+探头猫）抽成可复用的
     公开组件（如 `HomeSummaryCard`），参数保持现有字段（monthDate/summary/budgetStatus/budget/isCurrentMonth），
     回调改为可空（小组件渲染时传 null）。主页继续用它，diff 必须是纯搬家。
   - 同样把 `_MonthlyPaceCard` 抽成公开组件（records/summary/year/month/isCurrentMonth 参数不变）。
2. **离屏渲染器** `lib/core/widgets/widget_card_renderer.dart`：
   - 实现 `Future<Uint8List> renderWidgetToPng(Widget w, {required Size logicalSize, double pixelRatio = 2.0})`，
     用 RenderRepaintBoundary + 独立 BuildOwner/PipelineOwner 离屏渲染（不依赖第三方包；
     参考 screenshot 包 `captureFromWidget` 的公开实现思路）。
   - 渲染时包 MaterialApp/Theme（用 App 当前主题）+ MediaQuery(设备 pixelRatio)；探头猫要完整入画：
     渲染画布顶部预留猫的出头高度，不许裁头。
   - 总览渲染逻辑尺寸按 4x2 比例（建议 340×170 逻辑像素 @2x），进度卡同理；单张 PNG ≤ 1.5MB。
3. **快照服务接入** `widget_snapshot_service.dart`：
   - 每次 refreshNow 构建数据后，用真实数据渲染两张 PNG 写到
     `<app files>/widget_render/overview.png` / `pace.png`（先写临时文件再原子改名，防半张图）；
     路径和渲染时间戳写进快照 JSON。
   - 隐私模式：沿用 `widgetPrivacyMode`，渲染前把金额文本替换成 `¥****`（在共享组件加 masked 参数
     或传入已脱敏的 summary），不许渲染真实金额再打码。
4. **原生侧改造**：
   - `widget_feimiao.xml` / `widget_budget.xml` 改为：圆角背景 FrameLayout + ImageView（fitCenter）。
   - `FeimiaoWidgetProvider`：从快照 JSON 读 PNG 路径，`BitmapFactory.decodeFile`（带 inSampleSize 防超限）
     → `setImageViewBitmap`。**PNG 缺失/解码失败必须回退到现有文字版布局**，不许白屏或报"加载出现问题"。
   - 点击：总览整卡 → 打开 App 主页；进度卡整卡 → 统计页。区域级点击（统计胶囊/+）本批不做，别自作主张加。
   - 预览图 `widget_preview_overview.png` / `widget_preview_budget.png` 用新渲染结果重新生成。
5. **测试**：
   - 渲染器 widget test：两张卡都能渲出非空 PNG、尺寸符合预期比例。
   - 快照服务测试：refresh 后 JSON 含 PNG 路径且文件存在；隐私模式下渲染输入已脱敏。
   - 既有 307 个测试全绿。

**验收标准（Claude 执行）**：
- 主页大卡片截图 vs 总览小组件渲染图肉眼几乎无差（字体/颜色/圆角/猫都在）；
- 统计「截至今日」卡 vs 进度小组件同理；
- 小米桌面添加不报错、点击路由正确、隐私模式生效；
- 抽组件的 diff 是纯重构（主页/统计页观感零变化）；analyze 0 error + 全量测试绿；
- 出包走第 5/6 条规矩（版本三处同步、codex 签名、commit）。

**卡壳规则**：离屏渲染器如果两轮内跑不通（黑图/尺寸错/asset 加载不到），停下来把症状写进
CHANGELOG 等 Claude 接手，不要连续盲试。

---

## 二·A、已完成批次（留档）

### 任务 1【已完成，2026-07-09 Claude 验收通过 + 用户真机三查通过】：键盘修复没有通过你自己写的回归测试

`flutter test test/ai_chat_panel_focus_test.dart` 有 2 个用例挂着（你出 1.155.0+157 时因 DLL 问题没跑过它们）：

- `AI input respects system keyboard dismissal after startup`（`ai_chat_panel_focus_test.dart:196`）
- `AI input keeps keyboard dismissed after a delayed system close`（`ai_chat_panel_focus_test.dart:298`）

两个都断言：**系统收起键盘（viewInsets 回到 0）后，输入框 FocusNode 必须释放焦点、不得再拉回键盘**。
实际结果 `hasFocus` 仍为 true——也就是 CHANGELOG 里宣称的"键盘真实打开后，后续关闭视为用户意图，不再被定时器强行拉回"**并没有生效**，用户真机上"键盘自动弹回/返回键收不掉"的投诉可能依旧存在。

要求：
- 修 `lib/views/home/ai_chat_panel.dart` 的焦点/输入会话逻辑，让这 2 个测试真实通过（**不许改测试断言来迁就实现**；
  如果你认为测试本身写错了，把理由写进 CHANGELOG 等 Claude 评审，不要直接删）。
- 修完全量测试必须绿，出包后在 CHANGELOG 列出真机复测三查：①点输入框后键盘几秒内是否自动收回；
  ②手机返回键能否收起键盘；③点击上方空白是否退出半屏回主页。

### 任务 2【已完成，2026-07-09 Claude 验收通过】：备份清理不得删掉迁移前备份（数据安全回退）

现状：`_pruneLocalBackups(dir, keep: 3)` 把 `auto-` / `manual-` / `pre-v` 三种 `.bak` 混在一起按时间只留 3 份，
而且 `localBackupFiles()`（用户打开备份页）也会触发清理。后果：`pre-v20.bak` 这类**迁移前救命备份**会被
后来的自动/手动备份挤掉——它存在的意义就是迁移出 bug 后能回滚，绝不能被日常备份轮换掉。

要求：
- `pre-v*.bak` **永不自动删除**（或至少每个版本各保留一份，只在出现更高版本的 pre-v 时才考虑收敛）。
- `auto-` 和 `manual-` 各自独立限额（各留 3 份），互不挤占。
- `localBackupFiles()` 改成**纯读取**，不做删除副作用；清理只发生在"新建了一份备份之后"。
- 更新现有测试 `本机备份列表默认只保留最新 3 份`，并新增用例：目录里有 1 份 `pre-v20.bak` + 4 份 manual 时，
  清理后 pre-v 仍然存在、manual 剩 3 份。

### 任务 0（已由 Claude 完成，2026-07-09，勿重做勿放宽）

`_normalizeStandaloneRefunds` 已重写为高置信确定性匹配：
- 只处理负数支出行，**收入行一律不碰**；
- 只在"分类一致或金额精确相等、且候选唯一"时才挂回原单，有歧义原样保留；
- 非空备注保留不覆盖；带正经备注（不像退款）的负数行不动。
- 新增 4 个测试在 `test/app_repository_test.dart` 的『游离退款归并』group，**这些测试是行为契约，不许删改**。

---

## 三、排队中（还没到，别提前动工）

### 任务 4【任务 3 验收通过后才开工】：抽屉底栏调换 + 个人中心并入设置 + 头像/昵称编辑（对齐 ChatGPT 移动端）

**用户拍板（2026-07-09，参考 ChatGPT App 截图）**：

1. **抽屉底栏调换并合并入口**：
   - 左下 = 「+ 新建账本」胶囊（最高频动作占左下，对齐 GPT 的「聊天」）。
   - 右下 = 设置齿轮，用现成 `AppCircleButton` 灰圆（守全局按钮标准）。
   - 原左下头像按钮（进 PersonalCenterView 的）移除。
   - **去重**：抽屉功能列表里如有单独「设置」项一并删掉——合并后全 App 只留齿轮这一个设置入口。
     注意 drawer order registry 老用户持久化顺序里的 settings key 要兼容处理（忽略即可，别崩）。
2. **个人中心并入设置页**（用户原话：个人中心其实也是设置）：
   - `settings_view.dart` 顶部加：圆头像 + 昵称 + 编辑铅笔角标（GPT 同款布局）。
   - `PersonalCenterView` 的现有内容评估后搬进设置页合适分组，该页退役（保留文件留档，路由删除）。
3. **编辑资料半屏弹层**：
   - **样式铁律：不许照抄 GPT 的底部黑色大按钮**。走我们的 SheetHeader 标准：✕ 左上、
     「编辑资料」居中、右上「保存」pill（AppPillButton）；输入框用 iosInputDecoration。
   - 字段：头像（点相机角标 → showIosMenu 三选：拍照 / 相册 / 选择文件）+ 昵称（maxLength 12）。
   - 依赖零新增：拍照/相册用现有 `image_picker`，选文件用现有 `file_picker`。
4. **存储（纯本地）**：
   - 昵称存 app_settings（key `profile_nickname`）。
   - 头像图片压缩后（≤512px、≤200KB）复制到 App 文件目录 `profile/avatar.png`，
     先写临时文件再原子改名；设置页读固定路径，无文件回退现有占位（👤/昵称首字）。
   - 不动数据库表结构（app_settings 足够，**不许加 DB 迁移**）。
5. **测试**：昵称与头像路径持久化的 repo 测试（重开 repo 仍在）；analyze 0 error + 全量测试绿。
6. 出包走流程规矩第 1/2/5/6 条。

**验收标准（Claude 执行）**：抽屉底栏观感对齐 GPT（左胶囊右灰圆齿轮）；设置页顶部头像区完整；
编辑弹层符合 SheetHeader 标准；换头像三条路都通；重启后昵称头像仍在；全 App 设置入口唯一。

**背景说明**：昵称+头像也是将来多人共享账本的成员身份地基，字段命名取通用点（profile_*）。

### 任务 4.1【返工，优先于任务 5】：设置页资料区与重复入口修正（2026-07-09 用户真机反馈）

1. **资料区显示的是 App 名+版本号，错了**：
   - 昵称位显示**用户昵称**（`profile_nickname`），未设置时显示灰字「点击设置昵称」；
     头像无图占位 = 昵称首字（未设昵称用 👤），**不许再显示"肥喵记账"和它的首字**。
   - **删掉版本号那行**——版本号在「关于」里已有，个人资料区不放 App 信息。
2. **「管理」组去重**：删掉 月度预算 / 资产管理 / 分类管理 三项（抽屉功能列表里都有，
   核实于 main.dart `_kDrawerFns`）。**保留** AI 记账设置、备份与恢复（抽屉里没有这两个）。
   原则记住：**抽屉有的入口，设置页不重复**。
3. 完成后 analyze+全量 test 绿、出包（版本 minor+1/versionCode+1/水印+1）、commit。

### 任务 5【任务 4.1 之后开工】：视觉升级批（参考 iOS Cloudflare 客户端截图，2026-07-09 用户拍板）

> 参考基调：暖色渐变背景、简洁但可读性极强的数据图、大数字+涨跌徽章、圆角大弹窗。
> **配色铁律不破**：主色蓝灰 #7D8B9B、铜金 #F2B23C（收入/好事）、超支橙（警示）、不用红绿。
> 参考图只学布局和质感，颜色一律换成我们自己的。

1. **全局弹窗升级**（性价比最高，先做）：
   - 改全局组件 `ios_form.dart` 的确认弹窗：大圆角（约 26）、标题加粗居中、正文 onSurfaceVariant
     居中多行、底部两个**等宽胶囊**（次要=inputFill 浅灰底深字；主要=主色蓝灰底白字）。
   - 所有 showConfirmDialog 调用点自动升级；AI 隐私确认弹窗也对齐这套（用户点名它丑）。
2. **统计大数字卡**（月视图主卡）——**布局定案（2026-07-09，用户确认现有三小卡塞不下徽章）**：
   - 现有「支出/收入/结余」三张 1/3 宽小卡改为：**支出升级成通栏主卡** +
     **收入/结余两张半宽小卡**（一行两张，金额+小徽章半宽装得下，对齐参考图的半宽指标卡）。
   - 主卡：顶部小灰标签「总支出 · X月」+ 右上角涨跌徽章，下面超大金额（Nunito、约 40/w700）。
   - 半宽小卡：小灰标签 + 金额 + 紧凑小徽章；三张卡金额颜色语义保持现状（支出深色/收入铜金/结余负数橙）。
   - 右上角**涨跌徽章**：小箭头+环比百分比，支出↑=超支橙、支出↓=铜金；收入卡语义反转。
     ⚠️ 历史：用户删过「本月支出较上月+X%」那行文字（嫌丑）——删的是文字形式，
     徽章形式已获用户 2026-07-09 批准，**做成参考图那种紧凑小徽章，不许再回退成一行字**。
   - **徽章只上三个指标**（用户拍板，别加满屏）：总支出（↑橙/↓铜金）、总收入（↑铜金/↓橙）、
     结余（↑铜金/↓橙）。分类排行等其余地方一律不加。
   - **对比基准=同期不是全月**：当月看「截至同日 vs 上月截至同日」（口径复用 b0703-37 同期虚线），
     历史月才全月对全月；周视图比上周同期、年视图比去年同期、自定义无天然同期不显示。
   - 上期无数据或为 0 → 徽章整个隐藏，不许出现 ∞%/NaN。
3. **趋势图改曲线+渐变填充**（数据=现有「每日趋势」卡原样，只换皮肤；月=当月逐日、
   周=7天、年=12个月、自定义=区间逐日；支出/收入切换、同期虚线、今天标记全保留。
   **不并进大数字主卡**——保持卡片拼装系统的独立卡身份，用户真机看完想合再说）：
   - `isCurved: true` + `preventCurveOverShooting: true`（b0703-36 改直线是因为过冲，防过冲开了就能回曲线）。
   - 支出线=主色蓝灰、下方蓝灰→透明渐变填充；收入线=铜金、铜金→透明渐变。
   - 保留现有同期对比虚线和今天标记；Y 轴网格改淡虚线（对齐参考图质感）。
4. **统计页背景暖渐变（试点，只改统计页）**：
   - 浅色主题：顶部极淡铜金暖调 → 奶白 #FFFDF7 的纵向渐变（要非常淡，奶油感不是橙色海报）；
     深色主题背景不动。**只统计页试点**，用户真机认可后另开批次铺开，别自作主张全 App 铺。
5. **新统计卡「消费来源」**（地图分布的替代，用户点名要）：
   - TOP 商户/平台横向条形图（京东/美团/淘宝/线下扫码…），商户名用 `BillCategorizer.normalizeMerchant`
     归一化后聚合，取净额 TOP 6，条形用现有猫系色板。
   - 进统计卡注册表（key `sources`，月视图，默认开）；点条目可下钻该来源明细（复用 category_txns_view
     思路按备注/商户过滤，做不到干净下钻就先不做点击，别硬凑）。
6. 出包走流程规矩；改动全是 UI 层，**不许碰数据层**。
7. 远期备忘（本批不做）：用户对「消费位置分布（地图）」仍有兴趣，等以后评估记账加位置的方案。

### 更远的排队

- AI 设置多账号池（等用户确认是否要做）
- 资产 P2（权益资产与资产分析，先看 PRD）
- 消费位置分布（地图）——需要先解决账单没有位置数据的问题，远期
