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
- **走 A：极简工具路线**（对标钱迹），不走可爱风。主色深蓝 `#2E5090`，中性收支配色（收入蓝/支出中性/超支橙，见 `lib/theme/app_colors.dart`）。
- **AI 一句话记账接 DeepSeek**（不用 Claude——国产便宜、国内直连、中文好）。OpenAI 兼容 HTTP，`lib/core/ai/llm_entry_parser.dart`；用户的 key 存本地 `app_settings` 表（设置→AI记账设置）；没 key/失败时降级本地规则解析。一笔约 0.001 元。
- **输入框对标 Claude（已按用户逐张图对齐，标准已定）**：底部悬浮白框启动器（`record_input_bar.dart`，白底+轻阴影）。相关文件都在 `android-app/lib/views/home/`：
  - `record_input_bar.dart`：首页底部启动器。点模式胶囊 → 弹「手动/AI」选择面板；点输入区按模式分流；点话筒 → 按住说话面板。
  - `manual_add_sheet.dart`：手动模式键盘大卡（分类网格+金额+数字键盘），右上角关闭 X + 「AI 助手」胶囊切换。
  - `ai_focused_input_sheet.dart`：AI 模式贴键盘聚焦输入，**布局对标 Claude 输入框**：占位"记一记" + 底部一行 `[+] [⇄模式胶囊] …Spacer… [话筒] [发送]`，发送键有字才亮、触发解析。
  - `voice_input_sheet.dart`：「按住说话」面板（长按录音 `speech_to_text` zh_CN → 松手转文字 → `AiQuickEntryView(initialText)` 走 DeepSeek 解析）。
  - **按钮统一标准**：工具按钮（`+`/话筒/关闭/胶囊）= 透明感 `scheme.surface` + `Border black.06` + 淡阴影 `BoxShadow black.06 blur6`；唯发送键例外，实心 `scheme.primary` 圆。胶囊 `_ModePill`：前置 `Icons.swap_horiz`、文字**不加粗**。
  - **极简无卡通吉祥物**（用户明确不要可爱风）。

### 安卓待办（按优先级）
- 手动大卡「备注」TextField 可能与数字键盘抢系统键盘 → 需 `resizeToAvoidBottomInset:false`
- 输入框/按钮视觉细节以用户对照截图反馈为准，可能仍要微调
- 截图 OCR、CSV 导入导出（`+` 菜单里现是「即将到来」占位）
- 深色模式打磨、明细搜索/编辑、固定/周期账

## 模型分工策略（重要）

> 注：Fable 5 官方暂时停用，编排者暂由 **Opus 4.8** 接任，待 Fable 5 恢复后切回。

主对话由编排者（当前 Opus 4.8）担任：负责理解需求、做方案决策、写关键/精巧代码、审查子代理产出、向用户汇报。**凡是会产生大量 token 消耗的跑腿与重活，必须派给对应档位的子代理**，保持主对话上下文干净：

| 任务类型 | 派给 | 模型 |
|---|---|---|
| 代码库检索、找文件/符号、翻日志、简单事实核查 | `haiku-scout` | haiku |
| 按明确规格写代码、批量重构、写测试、修 lint/CI 小错、写文档 | `sonnet-builder` | sonnet |
| 疑难 bug 根因分析、架构权衡、安全/性能审计、反复失败的 CI 诊断 | `opus-reasoner` | opus（独立上下文，隔离重推理） |
| 需求决策、最终审查、对用户的总结汇报、一次性小修改 | 主对话编排者 | opus（Fable 恢复后切回 fable） |

执行要点：

- 多个互不依赖的子任务**并行派发**（同一条消息里多个 Agent 调用）
- 子代理只回传结论摘要，不要让原始文件内容灌进主对话
- haiku-scout 结果不可靠时升级到 sonnet 重查，而不是自己下场翻
- 升级路径：scout 查不清 → builder 试不动 → reasoner 分析 → Fable 拍板
