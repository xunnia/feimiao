# CLAUDE.md

> 交接文档（2026-06-18 刷新）。新会话/新环境（含 cowork）接手时先读这份，**别把已锁定的决策又问一遍或推翻**。

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
