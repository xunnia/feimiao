# CLAUDE.md

## 项目概况

这个仓库的活跃项目是 `ios-app/` 下的「轻记 QingJi」—— 一款 iOS 26+ 极简记账 App（SwiftUI + SwiftData + Liquid Glass 设计），核心逻辑在纯 Swift 包 `ios-app/QingJiCore/`（带完整单元测试）。

- 开发分支：`claude/new-session-4kh1ll`
- 本环境没有 Xcode/Swift 工具链，**一切编译与测试验证依赖 GitHub Actions**（`.github/workflows/ios-ci.yml`），macOS runner 上跑 swift test + Xcode 26 编译 + 模拟器截图 + 未签名 IPA 打包
- CI 会把截图和 IPA 提交回分支的 `ci-artifacts/`，截图可直接 Read 查看 UI 效果
- 用户没有 Mac，通过 Sideloadly + 免费 Apple ID 侧载 IPA 到 iPhone（iOS 27）
- 与用户沟通一律使用中文；用户是开发小白，解释要通俗

## 当前主战场：安卓版（`android-app/`，Flutter）

> 用户没有 Mac，iOS 27 测试版侧载又失败（Sideloadly Guru Meditation）。已转向 **Flutter 安卓版**作为主力迭代对象——安卓装 APK 简单，用户能真机用。iOS 版（`ios-app/`）保留不动。

- **技术栈**：Flutter + sqflite + provider + `decimal`（金额精度）。核心逻辑已从 Swift 移植到 `android-app/lib/core/`（金额/表达式/分类/统计/预算/账户/NL解析，带 Dart 测试）。
- **构建与分发**：无本地 Flutter 工具链，**一切验证靠 GitHub Actions**（`.github/workflows/android-ci.yml`，ubuntu runner）。每次推送 → 编译 release APK → 发布到固定 tag `android-latest` 的 GitHub Release。固定下载链接：`https://github.com/178517877qq-sketch/xunni/releases/download/android-latest/qingji.apk`
- **查构建结果**：用 `mcp__github__get_release_by_tag`（看 qingji.apk 资源的 `updated_at` 是否晚于本次推送；发布步骤只在构建成功后跑，所以更新了=成功）。**不要**用 `list_workflow_runs`（返回上百KB，烧 token）。失败再用 `get_job_logs`。
- **CI 注意**：android/ 脚手架每次 `flutter create` 重新生成，所以 manifest 权限要在 CI 里注入（已注入 `INTERNET` + `RECORD_AUDIO`）；图标用 `flutter_launcher_icons`（`android-app/assets/icon/app_icon.png`）。

### 产品方向与关键决策（定了别反复）

> **⚠️ 方向已转向可爱风**（推翻原「极简工具路线」，完整方案见 `android-app/docs/可爱风改造方案.md`）

- **走可爱风路线**（对标咔皮记账），吉祥物为**用户自家蓝白英短猫**（比竞品卡皮巴拉更有故事、不撞形象）。
- **新配色（从猫身上取色）**：主色蓝灰毛 `#7D8B9B`、铜金眼 `#F2B23C`（收入/高亮）、粉鼻爪 `#F4A9B8`（萌点）、超支橙 `#FF9F68`、背景奶白 `#FFFDF7`；节日点缀钱袋金 `#F3C44B` / 红绳 `#D94B3D`。见 `lib/theme/app_colors.dart`。
- **架构**：无底部 Tab 栏，单主页 + 左上角抽屉（学咔皮）；抽屉与输入框对齐 Claude 气质。
- **AI 一句话记账接 DeepSeek**（不用 Claude——国产便宜、国内直连、中文好）。OpenAI 兼容 HTTP，`lib/core/ai/llm_entry_parser.dart`；用户的 key 存本地 `app_settings` 表（设置→AI记账设置）；没 key/失败时降级本地规则解析。一笔约 0.001 元。
- **输入框对标 Claude（已按用户逐张图对齐，标准已定）**：底部悬浮白框启动器（`record_input_bar.dart`，白底+轻阴影）。相关文件都在 `android-app/lib/views/home/`：
  - `record_input_bar.dart`：首页底部启动器。点模式胶囊 → 弹「手动/AI」选择面板；点输入区按模式分流；点话筒 → 按住说话面板。
  - `manual_add_sheet.dart`：手动模式键盘大卡（分类网格+金额+数字键盘），右上角关闭 X + 「AI 助手」胶囊切换。
  - `ai_focused_input_sheet.dart`：AI 模式贴键盘聚焦输入，**布局对标 Claude 输入框**：占位"记一记" + 底部一行 `[+] [⇄模式胶囊] …Spacer… [话筒] [发送]`，发送键有字才亮、触发解析。
  - `voice_input_sheet.dart`：「按住说话」面板（长按录音 `speech_to_text` zh_CN → 松手转文字 → `AiQuickEntryView(initialText)` 走 DeepSeek 解析）。
  - **按钮统一标准**：工具按钮（`+`/话筒/关闭/胶囊）= 透明感 `scheme.surface` + `Border black.06` + 淡阴影 `BoxShadow black.06 blur6`；唯发送键例外，实心 `scheme.primary` 圆。胶囊 `_ModePill`：前置 `Icons.swap_horiz`、文字**不加粗**。
  - **吉祥物组件**：`lib/widgets/mascot.dart`，7 个表情（idle/success/overspend/celebrate/empty/thinking/report），M0 用 emoji 占位，M8 换真猫 PNG。

### 安卓待办（按优先级）
- 手动大卡「备注」TextField 可能与数字键盘抢系统键盘 → 需 `resizeToAvoidBottomInset:false`
- 输入框/按钮视觉细节以用户对照截图反馈为准，可能仍要微调
- 截图 OCR、CSV 导入导出（`+` 菜单里现是「即将到来」占位）
- 深色模式打磨、明细搜索/编辑、固定/周期账

## 工作方式（重要）

> **分工已关闭**（用户决定，2026-06-14）。不再派子代理（haiku-scout / sonnet-builder / opus-reasoner）。

- 用户当前对话选的是哪个模型，就由**这个模型本人**直接干全部活：找代码、读文件、写代码、改 bug、验证、汇报，一条龙自己来。
- **不要调用 `Agent` 工具派子代理**做检索/写代码/推理等任务。需要查代码就自己用 Grep/Glob/Read，需要写代码就自己写。
- 例外：仅当用户明确要求时才用子代理。
- 其余原则不变：中文沟通、用户是小白要讲通俗、改动推 GitHub Actions 验证、方案定了别反复。
