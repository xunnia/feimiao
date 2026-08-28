# 肥喵记账 Android / iOS 对齐验收表

这份表是 iOS 原生迁移的验收入口。目标是业务行为、数据口径、页面结构和入口能力一致；
iOS 的控件、动效和玻璃材质按 Apple 原生规范实现，但不能用另一套导航或快捷入口替代 Android。

当前 Android 基线：`1.269.0+283` / `b0829-283` / 数据库 v48；该批次已由用户确认收口，
可作为当前成对截图和逻辑对账基线。真实 OAuth、provider 网络和真机体验仍单独标记为待验收。

首页的结构性入口与 Android 保持一致：顶部账本/搜索/菜单和底部「记一记」输入框必须存在；
iOS 只在按钮反馈、系统菜单、键盘、转场和 Liquid Glass 材质上做原生增强，不能用通用快捷操作卡替代主入口。

## 截图规则

- 每个已迁移功能至少保存一组 Android 与 iOS 截图。
- 截图场景使用同一演示数据、同一时间、同一语言和同一屏幕逻辑尺寸。
- 截图只证明画面；金额、退款、预算等还必须有跨平台核心逻辑测试证明。
- 文件命名：`<功能>/<场景>-android.png` 与 `<功能>/<场景>-ios.png`。
- iOS CI 产物目录：`ci-artifacts/ios-screenshots/`；Android 现有 golden 仍保留在 `android-app/outputs/`。
- 成对场景和报告由 `ios-app/tools/screenshot_manifest.json` 与 `ios-app/tools/compare_png.py` 管理，报告会区分“缺失截图”“尺寸不一致”和“已比较”。
- Android 端已加入真实页面的 integration_test/parity_screenshots_test.dart，由 .github/workflows/parity-screenshots.yml 在 Android 模拟器和 iOS 模拟器分别采集 35 个场景，再生成同一份报告；iOS 另有内容区非空门禁，白屏截图会直接让 job 失败。
- 当前工作树没有在线 Android 设备，也没有本机 Xcode；因此“CI 已配置”不等于“截图已通过”。Pixel 2 与 iPhone 模拟器物理尺寸不同，报告会如实记录尺寸差异，不把原生 UI 的像素差异伪装成业务一致。

## 当前批次

| 功能 | Android 基线 | iOS 状态 | 截图状态 |
|---|---|---|---|
| 首页月度总览 | `home_view.dart` | 已实现 Android 同结构首页、月选择、预算与底部记账输入框 | 待最新 CI 成对截图 |
| 手动支出/收入/转账 | `quick_add_view.dart` | 已接入账本、账户、分类和原生键盘 | 待最新 CI 成对截图 |
| 账本切换与新建 | 抽屉账本 | 已实现账本模型与管理页 | 待 CI 运行 |
| 交易明细与搜索 | `transaction_day_list.dart` | 已实现基础列表、搜索、编辑 | 待 CI 运行 |
| 退款/报销冲减 | `transaction_actions.dart` | 已实现挂原交易、原日期冲减 | 待逻辑回归与截图 |
| 待报销 | `reimburse_view.dart` | 已接入报销抵消到 0 | 待 CI 编译与截图 |
| 周/月/年度/自定义统计 | `statistics_view.dart` | 已接入 QingJiCore 净额统计与原生 Charts | 待 CI 编译与成对截图 |
| 月度预算 | `budget_setting_view.dart` | 已有总预算、周期窗口、今日可花、分类预算、预算计划、专项追踪、固定承诺 occurrence 物化及匹配/跳过/重置/退款复核基础流程 | 完整历史修订编辑仍待 CI 后续收口 |
| 账户/分类/对账 | 设置页相关页面 | 已有基础版 | 待 CI 运行 |
| 导入复核与完整备份 | `bill_review_view.dart`、`backup_package_codec.dart` | 已有商品优先分类、商户分组、AI 兜底、退款匹配；iOS 已接入 Android v1/v2 原始 SQLite ZIP 校验、只读转换、收据/资产媒体安装、失败回滚和完整替换恢复；AI 运行记录/定时报表随 canonical v9 保存 | 待 Xcode 27 CI 与真机用真实备份验收 |
| AI Chats/多服务商 | `ai_chat_panel.dart` | 已接入 iOS 原生 AI 账号、Keychain、模型目录、三类流式端点、ChatGPT/Codex PKCE OAuth、401 刷新、Chats 会话列表、图片/文件附件和基础喵助手；来源/结构化账单动作仍待后续批次 | 待 CI 编译与网络回归 |
| 存钱目标 | `savings_goals_view.dart` | 已实现目标、进度、归档/恢复 | 待 CI 编译与截图 |
| 定时记账 | `recurring_view.dart` | 已实现日/周/月/年规则、转账、幂等补记 | 待 CI 编译与核心回归 |
| 资产/负债/净资产 | `views/assets` | 已实现 iOS 基础档案、生命周期、持有指标计算、还款、组件净资产与快照 | 待 CI 编译、资产详情操作/分摊 UI 与截图 |
| 报告/后台任务/提醒 | `reports`、Worker | 已有本地月报库、阅读/置顶/删除和 `BGTaskScheduler` 择机刷新；AI 定时报表保存计划并用本地通知提醒前台生成，不能承诺 iOS 后台固定联网 | 待 Xcode 27 编译、后台触发和真机验收 |
| Widget/快捷指令/分享 | Android 原生通道 | Widget、App Intent、Share Extension 已有基础版；分享文本/截图会进入 AI 记一笔 | 待 CI 编译与截图 |
| 通知自动记账 | `PaymentNotificationListener` | iOS 无等价系统权限 | 用分享/OCR/快捷指令替代 |

## “一致”的判定

1. 同一输入得到相同的金额、类型、分类、账户、日期和统计结果。
2. 退款与报销仍属于原交易家族，按原交易日期进入统计。
3. 转账不计入收支，但正确改变两个账户的余额。
4. 不计收支记录不进入预算和统计。
5. 所有平台差异都在功能矩阵中明确记录，不能用截图相似掩盖能力缺失。
