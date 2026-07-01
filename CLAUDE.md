# CLAUDE.md

> 交接文档。新会话/新环境（含 cowork / Claude Code）接手时先读这份，**别把已锁定的决策又问一遍或推翻**。
> 下面「§0 最新交接」是 2026-06-28 那次长 session 的增量，**优先看它**；再往下是更早的 2026-06-18 版底稿（仍有效，但 §0 覆盖更新的部分）。

---

## §0 最新交接（2026-06-28，一次超长 session）

### 0.1 首要在途：截图识别「京东/淘宝订单列表」解析（正在攻）
- 现象：用京东「我的订单」整页截图记账时，会**漏单、错位（金额配错商品）、把已取消订单也记了**。
- 已定位真因（用户贴了原始 OCR）：**ML Kit 对京东这种密集彩色页识别很糟——¥ 符号丢失（金额是裸的 `17.70`）、"999"认成"99"、行序打乱**。因为旧判定用 `[¥￥]\d` 认金额 → 认不到 → **`isOrderList` 判 false → 切单代码根本没触发**。
- 已推的修复（最新提交，构建号 **b0628-3**）：
  - `screenshot_entry.dart` 里 `isOrderList` 判定**不再依赖 ¥**，改用「共N件」锚点 + 裸两位小数金额。
  - `order_list_parser.dart`（新，纯逻辑+单测）：按每单一个的「共N件」**确定性切单**，切单时**整单丢弃「已取消/退款/未付款」**；无「共N件」回退到 `screenshot_layout.dart` 的纵向聚类。
  - `llm_entry_parser.dart` 的 `screenshotExtra` 提示词：多平台结构感知（店铺→商品→金额→共N件→状态）、跳过已取消、不漏单、金额只配同单商品。
- **待用户真机验 b0628-3**：看①是否触发切单（输入框会出现 `─────` 分块）②取消单丢没丢③漏单补没补。
- **诚实结论/天花板**：本地 OCR（ML Kit）对京东这类页就是不稳，切单能显著改善但**做不到分毫不差**；要 100% 只有**视觉大模型看图**（通义/智谱 VL，需云端 key）。用户**明确嫌云端麻烦、要纯本地**，所以别擅自上云；可以再优化本地启发式，但要如实告诉他上限。**单个订单详情页截图几乎不会错**，整页列表当"批量草稿"、确认页删改兜底。

### 0.2 本 session 已完成（都在分支上、有单测的已进 CI 硬闸门）
- **改名**：App 从「轻记」→ **「肥喵记账」**（`AndroidManifest label`）。
- **AI 记账准确率三连**：
  - P0-1 大模型统一判意图：`parseWithLLM` 返回 `{intent,entries}`，记账/查账交给 DeepSeek 判；关键词 `ChatIntent`（`chat_intent.dart`）仅离线兜底。**修了"花了"被误判查账的 bug。**
  - P0-2 商户词典 `merchant_category.dart`（真实 key、kind 感知、最长匹配）：瑞幸→饮料、滴滴→打车…；分类优先级 **用户记忆 > 词典 > 大模型 > 兜底**（`_matchCat` / quick-entry / auto-record 都接了）。
  - P1 记账卡**一键改分类芯片**（`ai_chat_panel.dart` `_CatChip`/`_pickCategory`/`_catCandidates`）：同大类兄弟子类，点一下=改+学习(`learnCategory`)+若已入库改库(`repo.setTransactionCategory`)。`addTransaction` 现返回 id。
  - P2 `entry_sanity.dart`（金额≤0/过大→null、未来日期→今天、置信度 clamp，接在 LLM 与本地两条路）；本地解析认**中文数字金额**（`_cnToInt`：一百二/两块五/一万二）。
- **解析更聪明**：`meal_time.dart`（笼统 `dining` 按时段→早/午/晚餐）；`smart_tags.dart`（报销识别→存账标"待报销"、AA 分摊按人数）；`spending_anomaly.dart`（记完比同类历史贵一大截→温和提醒，仅聊天记账路弹）；`notification_parse.dart`（通知挑支付金额避余额+方向）。
- **顶级·捕获入口（原生）**：
  - **分享到肥喵**：`MainActivity.kt`（MethodChannel `feimiao/share`）+ manifest SEND/SEND_MULTIPLE + `share_intake.dart`（全局 navigatorKey，文字→AiQuickEntryView、图片→`recognizeImagePathAndEntry`，与相册选图共用 OCR 管线）。**待真机验。**
  - **自动记账**：`PaymentNotificationListener.kt`（`NotificationListenerService` 抓微信/支付宝支付通知→粗筛→排队 SharedPreferences）+ channel `feimiao/autorecord`（取队列/查授权/跳设置）+ `auto_record.dart` + `auto_record_sheet.dart`（回前台一键批量确认，不静默乱记）+ 设置页 `auto_record_setting_view.dart`（抽屉入口，含保活引导）。**待真机验（通知文案解析 + 国产 ROM 保活是最大变数）。**
- **趋势图**：统计页「近半年趋势」支出+收入双线（`statistics_view.dart` `_TrendChart`）。
- **月度报告**：`monthly_report_view.dart`（本地算的月报 + 猫锐评，统计页入口）。修了双 ¥ bug。
- **退款=冲账方案1**：`repo.refundTransaction` 记负支出；左滑「编辑/退款/删除」`transaction_actions.dart`（flutter_slidable）。
- **周期记账**：`recurring_rule.dart` + DB v11 + `recurring_view.dart`（抽屉「定时记账」）。
- **崩溃修复（重要）**：release 版截图识别崩（NPE `getClass() on null`）根因是 **R8 裁掉了 ML Kit 反射加载的中文模型类** → 已在 `android/app/build.gradle.kts` 的 release 关掉 R8：`isMinifyEnabled=false` + `isShrinkResources=false`。**别再打开**，否则 ML Kit 会被裁崩。
- **图标**：`app_icon.png` 是完整成品图（内容贴边），CI 里 `rm` 掉自适应 XML 强制传统图标。真正无裁切要用户给「透明背景 logo 前景」做标准自适应——用户没给，**暂搁置**。

### 0.3 构建 / 验证 的变化（覆盖 §二）
- **提交信息不再用 `M{n}` 流水号**，改**中文描述式**（如「AI记账P2:…」）。
- **用户在本地 `master` 分支**，推送用 **`git push origin HEAD:claude/hopeful-wozniak-pr2ne3`**（把 HEAD 推到那个固定分支；直接 `git push -u origin claude/…` 会 `src refspec … does not match`，因为本地分支名叫 master）。
- **cowork 环境里没有 `mcp__github__*` 工具**，我读不到 CI 日志；靠用户截图/告知 CI 颜色。Claude Code 环境若有 `gh` CLI 或 github 工具可自查。
- **构建水印**：`lib/build_info.dart` 的 `kBuildTag` 显示在 AI 记账页副标题（现 **b0628-3**）。**每次有意义改动就 +1**，让用户一眼确认装的是不是最新包（本 session 反复踩"用户在测旧包"的坑，务必让他先认水印再报问题）。
- 沙箱/cowork 的 bash **不能 commit/push**（`.git/objects` 无写权限 + 无 git 身份）；**代码编辑靠文件工具落盘到用户磁盘，git 提交推送让用户在自己终端跑**。Claude Code 在用户机器上则可直接 git。
- CI 仍是唯一编译闸门：**没有本地 Dart/Flutter，我编译不了；纯逻辑都写了单测让 CI 真验；原生(Kotlin)只能 CI 验编译 + 用户真机验行为。**

### 0.4 又锁定的决策（补充 §三）
- **AI 记账要做到"顶级"**：方向是①解析准（已大量做）②捕获无摩擦（分享+自动记账）③更聪明（餐次/报销/AA/异常）。**纯本地优先，用户嫌云端 OCR 麻烦——不上云。**
- **不派子代理**依旧（用户 6-14 决定），一条龙干。

## 一、当前活跃项目

**「轻记 QingJi」安卓版**：`android-app/`，Flutter + sqflite + provider + `decimal`（金额精度）。
- 开发分支：**`claude/hopeful-wozniak-pr2ne3`**（所有进度都在这；环境是临时的，代码只认 git）。
- iOS 版（`ios-app/`，Swift）已**休眠保留不动**（用户没 Mac、侧载失败，转安卓）。
- 与用户**一律中文**沟通；用户是开发小白，解释要通俗。

## 二、构建 / 验证（没有本地工具链，全靠 CI）

- `.github/workflows/android-ci.yml`（ubuntu runner）：每次推分支 → `flutter pub get` → 生成图标 → `flutter analyze`(非阻断) → **`flutter test`(硬闸门)** → 编译 release APK → 发布到固定 tag `android-latest` 的 Release。
- **固定下载链接（永不变）**：`https://github.com/178517877qq-sketch/xunni/releases/download/android-latest/qingji.apk`
- **查构建结果**：优先 `mcp__github__get_release_by_tag`（看 qingji.apk 的 `updated_at` 晚于本次推送即成功——发布步骤只在成功后跑）。`list_workflow_runs` 返回上百KB会爆 token；若必须用，结果会落到本地文件，用 `python3` 读该文件解析 `head_sha/conclusion`。失败再 `get_job_logs`。
- **提交规范**：commit message 用 `M{n}: 简述` 流水号（当前已到 **M37**）。推送用 `git push -u origin claude/hopeful-wozniak-pr2ne3`；推前先 `git fetch + rebase`（远端偶有删文件类提交）。
- **CI 注意**：`android/` 脚手架每次 `flutter create` 重生成，所以 manifest 权限在 CI 里注入（现仅 **INTERNET**；RECORD_AUDIO 已移除）；图标用 `flutter_launcher_icons`（`assets/icon/app_icon.png`）。`assets/`、`pubspec.yaml` 是我们维护的、不会被重生成。

## 三、锁定的产品决策（定了别反复）

- **可爱风路线**（对标咔皮记账），吉祥物=用户自家蓝白英短猫。`lib/widgets/mascot.dart`（7 表情，现 emoji 占位，将来换真猫 PNG）。
- **猫系配色**（`lib/theme/app_colors.dart`）：主色蓝灰毛 `#7D8B9B`、铜金眼 `#F2B23C`（**收入/高亮**）、粉鼻爪 `#F4A9B8`、超支橙 `#FF9F68`、奶白底 `#FFFDF7`。
  - **收支语义**：收入=铜金，支出=中性深色(onSurface)，超支/预算超标=橙。**不要用通用红/绿**（多次否决）。
- **架构**：**无底部 Tab 栏**，单主页 + 左上角抽屉（学咔皮）。抽屉/输入框对齐 Claude 气质。**多次否决底部导航栏改造。**
- **纯本地 App**：sqflite，**无后端/无登录/无云同步/无多人共享**（多次否决）。
- **AI 记账接 DeepSeek**（不用 Claude——国产便宜、直连、中文好）。OpenAI 兼容 HTTP，`lib/core/ai/llm_entry_parser.dart`；用户 key 存 `app_settings` 表（设置→AI记账设置）；无 key/失败降级本地规则 `natural_language_entry_parser.dart`。
- **设计令牌**：`lib/theme/app_tokens.dart`（圆角偏大=萌、间距、动效、字重、文字三级灰度），新 UI 都走它，别再手写魔法数字。
- **GPT/Gemini 的 review 只挑增量、别照单全收**：它们反复想塞底部Tab、通用蓝/红绿配色、云同步、跟同类用户对比的AI——这些都与上面冲突，**不做**。

## 四、已完成（截至 M37，CI 全绿）

- **输入栏**（`lib/views/home/record_input_bar.dart`）：底部 Claude 式白卡启动器；工具行 `[+] [模式胶囊] … [发送↑]`。模式胶囊=**直接切换**手动/AI 且**显示当前模式**（不是弹选择面板、不显示目标模式）；记住上次选择。`[+]`→`record_extras_sheet.dart`（截图识别/导入/导出）。
- **AI 面板**（`ai_chat_panel.dart`，`showAiChatPanel`）：一句话→DeepSeek 解析→记账卡（保存/撤销）。**置信度自动入库**：每笔 confidence≥0.9 直接记+撤销提示，否则弹确认卡，缺金额则追问。查账问答走 `llm_query.dart`。
- **手动卡**（`manual_add_sheet.dart`）：分类网格(大类，按频次排序)+**子类下钻**(`SubcategoryRow`)+金额表达式键盘(`amount_keypad.dart`，含 +/− 连加)+账户/日期/备注/标签。
- **首页**（`home_view.dart`）：顶部三层卡（结余→收入/支出→预算细条/引导）+ 洞察小条（本月最大支出）+ 按天分组账单流（金额主角·收支分色·emoji 图标）。月份点击进统计页。
- **二级分类**（核心数据特性）：`category_seed.dart` 两级树（9 大类 + ~50 子类 + emoji + parentKey）；DB `categories` 加 `parent_id`，版本 6；`_applyCategoryTree` 幂等 upsert（建库+迁移共用，**纯增量、绝不动 transactions**）；`repo.categoriesForKindRanked`=顶级大类、`repo.childrenOf(id)`=子类。手动卡 & 编辑页都支持大类→子类下钻。
- **分类图标=彩色 emoji**（`CategorySeed.emoji` / `emojiOf(key)`，代码侧映射、不入库）。
- **统计页**（`statistics_view.dart`）：占比饼图/趋势柱/分类排行/预算进度/**环比(vs上月)**，fl_chart。
- **其它**：多账本（抽屉切换）、资产/账户、预算、存钱目标、分类/标签管理、CSV/Excel 导入（微信/支付宝GBK原生解码+自动归类）、CSV 导出、深浅色主题。全项目已用 `withValues` 替换弃用的 `withOpacity`。

## 五、在途 / 待办

- **⚠️ 二级分类迁移待用户真机验证**：用户升级安装后需确认「旧账目全在、金额对、旧分类(买菜超市/水电网/旅行/宠物/订阅)已并入对应大类」。若用户反馈异常优先修。
- **Fluent 3D 光泽图标（用户想要）卡点**：微软 fluentui-emoji 多词图标的真实文件夹名无法靠猜，GitHub API 又限流没法枚举 → 现保留彩色 emoji。要做需先拿到「分类 emoji → Fluent 资源路径」的准确全表（换有授权的途径，或人工对照），再在 CI 下载 ~60 个 PNG 到 `assets/cat_icons/`，渲染处用 `Image.asset` + emoji 兜底。
- **可选打磨**（价值不高）：弹窗统一抽 `appSheet()`；分类管理页按大类分组；导入自动归类映射到子类；语音（已砍，国产ROM无谷歌语音；要做得接云端ASR，需用户给key+成本）。
- 旧待办：手动卡备注 TextField 可能与键盘抢焦点（`resizeToAvoidBottomInset:false`）。

## 六、工作方式

- **不派子代理**（用户 2026-06-14 决定）：当前模型本人一条龙干完（找码/读/写/验/汇报）。需查码自己用 Grep/Glob/Read。
- 改动一律推 CI 验证，**绿了再说"完成"**；推送后用后台 sleep 等约 9 分钟再查结果（前台 sleep 被拦，用 `run_in_background`）。
- 中文沟通、对小白讲通俗、**方案定了别反复**。
