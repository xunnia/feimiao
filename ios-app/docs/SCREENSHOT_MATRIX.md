# 双端截图验收矩阵

截图不是“看起来差不多”就算完成。每一个已迁移功能都要使用同一套演示数据，
分别采集 Android 与 iOS 首屏，再用 `ios-app/tools/compare_png.py` 生成机器可读和
Markdown 报告。

## 当前基线

- Android：`1.265.0+279` / `b0828-279` / DB v48。
- iOS：deployment target 26.0，CI 使用 GitHub macos-26，优先 Xcode 27、否则 Xcode 26.x/iOS 26 SDK。
- 演示数据：启动参数 `QINGJI_DEMO=1` 与 `QINGJI_DEMO_NOW=2026-08-27T12:00:00+08:00`，语言和币种固定为测试 fixture。
- iOS 路由：`QINGJI_SCREEN`，避免 `simctl openurl` 的系统确认弹窗。

## 采集方式

1. Android 端使用 `android-app/integration_test/parity_screenshots_test.dart` 在稳定设备或 CI 模拟器采集到 `android-app/outputs/parity/`。
2. iOS CI 用同一批路由采集到 ci-artifacts/ios-screenshots/；当前使用官方 macos-26 runner，脚本会优先选择镜像中已有的 Xcode 27，否则使用 Xcode 26.x。
3. 在仓库根目录执行：

   ```powershell
   python ios-app/tools/compare_png.py `
     --manifest ios-app/tools/screenshot_manifest.json `
     --root . `
     --output ci-artifacts/screenshot-report.json
   ```

4. `.github/workflows/parity-screenshots.yml` 会在两个模拟器任务都成功后生成成对报告，并使用 `--require-complete`。这个 gate 要求两边都有有效 PNG；Pixel 2 与 iPhone Air 的物理尺寸差异会标记为 `dimension_mismatch` 并保留在报告中，不会被伪装成像素一致，也不会把有效成对证据误判为缺图。

## 判定口径

截图用于确认入口、信息层级、数据显示、空态和交互后的状态。iOS 使用 SwiftUI、
Liquid Glass、SF Symbols、原生转场和触觉反馈，因此与 Flutter/Material 的像素差异
是预期的；像素差异会记录在报告中，业务一致性必须同时由 QingJiCore 测试证明：

- 收支、转账、账本和账户结果一致；
- 退款/报销按原账单日期挂接，列表展示净额；
- 不计入收支不进入统计和预算；
- 预算、统计、净资产使用同一币种和 Decimal 计算；
- iOS 专属动效和平台能力差异在 parity 表中单独标注；iOS 原生视觉不会被强行判为像素相同，但金额、类型、分类、账户、日期和交互后状态必须一致。

## 当前状态

| 场景 | iOS 路由 | Android 截图 | iOS 截图 | 状态 |
|---|---|---|---|---|
| 首页、记一笔、明细 | `home` / `quickadd` / `transactions` | 待设备采集 | CI 已配置 | 待成对对比 |
| 周/月/年/自定义统计 | `stats/week` / `stats/month` / `stats/year` / `stats/custom` | 待设备采集 | CI 已配置 | 待成对对比 |
| 预算、对账、待报销 | `settings/budget` / `settings/reconcile` / `settings/reimburse` | 待设备采集 | CI 已配置 | 待成对对比 |
| 存钱、定时记账 | `settings/savings` / `settings/recurring` | 待设备采集 | CI 已配置 | 待成对对比 |
| 资产、负债、净资产 | `settings/assets` / `settings/liabilities` / `settings/net-worth` | 待设备采集 | CI 已配置 | 待成对对比 |
| 账本、设置、AI 入口 | `settings/books` / `settings` / `ai` / `settings/ai` | 待设备采集 | CI 已配置；AI 路由为 Chats 列表和 AI 设置页 | 待成对对比 |
| 导入复核与商户批量分类 | `settings/import-review` | 待设备采集 | CI 已配置 | 待成对对比 |
| 报告库与月报阅读 | `settings/reports` | 待设备采集 | CI 已配置 | 待成对对比 |
| 喵学到的分类 | settings/memory | 待设备采集 | CI 已配置 | 待成对对比 |
| AI 任务/诊断/统一搜索 | settings/ai-tasks 等 | 待设备采集 | CI 已配置 | 待成对对比 |
| AI 可控记忆/技能/定时报表/本地伴侣 | settings/ai-memory 等 | 待设备采集 | CI 已配置 | 待成对对比 |
| 备份/主题/账单显示 | settings/backup 等 | 待设备采集 | CI 已配置 | 待成对对比 |

这份表只记录证据状态，不把“代码已写”冒充“真机已验收”。
