# 双端截图验收矩阵

> 2026-08-31 复盘更正：旧报告的 39/39 是“文件存在/PNG 可解析”，不是页面身份、内容完整或数据一致。已确认 `23-import-review` 实际为首页，Android 多张图含大面积透明像素并显示为黑底，部分同名场景不是同一业务页面。以下旧状态仅作历史索引；P0 重采、路由去重门禁、Android alpha 门禁和逐字段对账全部通过前，统一视为“待重新验收”。

截图不是“看起来差不多”就算完成。每一个已迁移功能都要使用同一套演示数据，
分别采集 Android 与 iOS 首屏，再用 `ios-app/tools/compare_png.py` 生成机器可读和
Markdown 报告。

## 当前基线

- Android：`1.270.0+284` / `b0829-284` / DB v48。
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

4. `.github/workflows/parity-screenshots.yml` 会在两个模拟器任务都成功后生成成对报告，并使用 `--require-complete`。Parity #61 已对 39 个场景通过这个 gate；Pixel 2 与 iPhone Air 的物理尺寸差异会标记为 `dimension_mismatch` 并保留在报告中，不会被伪装成像素一致，也不会把有效成对证据误判为缺图。

## 判定口径

截图用于确认入口、信息层级、数据显示、空态和交互后的状态。iOS 使用 SwiftUI、
Liquid Glass、SF Symbols、原生转场和触觉反馈，因此与 Flutter/Material 的像素差异
是预期的；像素差异会记录在报告中，业务一致性必须同时由 QingJiCore 测试证明：

- 收支、转账、账本和账户结果一致；
- 退款/报销按原账单日期挂接，列表展示净额；
- 不计入收支不进入统计和预算；
- 预算、统计、净资产使用同一币种和 Decimal 计算；
- iOS 专属动效和平台能力差异在 parity 表中单独标注；iOS 原生视觉不会被强行判为像素相同，但金额、类型、分类、账户、日期和交互后状态必须一致。

## 历史状态（全部待重新验收）

| 场景 | iOS 路由 | Android 截图 | iOS 截图 | 状态 |
|---|---|---|---|---|
| 首页、记一笔、明细 | `home` / `quickadd` / `transactions` | Parity #61 已采集 | Parity #61 已采集 | 已完成成对对比 |
| 周/月/年/自定义统计 | `stats/week` / `stats/month` / `stats/year` / `stats/custom` | Parity #61 已采集 | Parity #61 已采集 | 已完成成对对比 |
| 预算、对账、待报销 | `settings/budget` / `settings/reconcile` / `settings/reimburse` | Parity #61 已采集 | Parity #61 已采集 | 已完成成对对比 |
| 存钱、定时记账 | `settings/savings` / `settings/recurring` | Parity #61 已采集 | Parity #61 已采集 | 已完成成对对比 |
| 资产、负债、净资产 | `settings/assets` / `settings/liabilities` / `settings/net-worth` | Parity #61 已采集 | Parity #61 已采集 | 已完成成对对比 |
| 账本、设置、AI 入口 | `books` / `settings` / `ai` / `settings/ai` | Parity #61 已采集 | Parity #61 已采集 | 已完成成对对比 |
| 导入复核与商户批量分类 | `settings/import-review` | Parity #61 已采集 | Parity #61 已采集 | 已完成成对对比 |
| 报告库与月报阅读 | `settings/reports` | Parity #61 已采集 | Parity #61 已采集 | 已完成成对对比 |
| 喵学到的分类 | settings/memory | Parity #61 已采集 | Parity #61 已采集 | 已完成成对对比 |
| AI 任务/诊断/统一搜索 | settings/ai-tasks 等 | Parity #61 已采集 | Parity #61 已采集 | 已完成成对对比 |
| AI 可控记忆/技能/定时报表/本地伴侣 | settings/ai-memory 等 | Parity #61 已采集 | Parity #61 已采集 | 已完成成对对比 |
| 备份/主题/账单显示 | settings/backup 等 | Parity #61 已采集 | Parity #61 已采集 | 已完成成对对比 |
| 收入记账与物品资产详情操作态 | `quickadd/income` / `settings/assets/detail` | Parity #61 已采集 | Parity #61 已采集 | 已完成成对对比 |
| 账户详情操作态 | `settings/accounts/detail` | Parity #61 已采集 | Parity #61 已采集 | 已完成成对对比 |
| 报销到账操作态 | `settings/reimburse/settlement` | Parity #61 已采集 | Parity #61 已采集 | 已完成成对对比 |
| 借贷往来按对象聚合 | `lending` | 待本轮重采 | 待本轮重采 | 待重新验收 |

这份表只记录证据状态，不把“代码已写”冒充“真机已验收”。
