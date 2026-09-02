# 肥喵记账 iOS 同款重建：P0 基线决策与执行报告

> 状态：`P0_PARTIAL`
>
> 日期：2026-09-02
> 原则：Android 是唯一产品母版；iOS 是同一款肥喵记账的原生实现，不是另一个软件。

## 1. 本轮已经锁定的基线

| 项目 | 已锁定值 | 证据 |
|---|---|---|
| 干净远端锚点 | `72f14808b0fe32a6276558af16b775fa987f1c2f` | 已 fetch 并解析 |
| Android 母版快照 | `08f7a5e28ffcc65f50dd2661802111d0ef92446c` | 独立提交，48 个源码/测试/发布文件 |
| Android 版本 | `1.289.0+304` | `android-app/pubspec.yaml` |
| Android 水印 | `b0901-304` | `android-app/lib/build_info.dart` |
| Android DB | `49` | `android-app/lib/data/app_repository.dart` |
| Android APK | `feimiao-codex-v1.289.0-304.apk`，117,822,013 bytes | 本地构建产物 |
| Android APK SHA-256 | `EAB0DE7BD68D799786044BCA6DE2AED408179515F9FB987587B9A0529FEFDF3E` | 已重新计算 |
| iOS 生产主干 | `QingJi` + Widget + Share Extension + App Intents | `ios-app/project.yml` |
| iOS Bundle ID | `com.qingji.app` | `ios-app/project.yml` |
| iOS 当前版本 | `1.286.0+300` | `ios-app/project.yml` |
| iOS deployment target | `26.0` | `ios-app/project.yml` |
| P0 integration 分支 | `codex/ios-same-app` | 独立 worktree，不在脏主工作区开发 |
| 已纳入的 iOS 正确性修复 | `32beb69` | 导入与备份原子性修复 |

安卓版快照通过以下 Windows 验证：

- Flutter 3.44.2 / Dart 3.12.2；
- `flutter analyze --no-fatal-infos --no-fatal-warnings`：0 error，90 条 warning/info；
- `flutter test`：1210/1210 通过；
- 创建快照时主工作区 Git index 的 SHA-256 前后一致；没有执行 reset、clean、stash 或 `git add -A`；
- 缓存、失败截图、构建目录和旧 APK 删除没有进入母版提交。

这些证据说明 `1.289.0+304` 可以作为当前 Android 产品母版候选；它们不证明 iOS 已经对齐，也不代替 Android 真机观感复测。

## 2. 唯一产品和架构决策

1. Android 当前产品行为、信息架构、文案、数据口径、入口层级和可达功能是唯一规范。
2. iOS 继续使用成熟的 `QingJi`、SwiftData、Widget、Share Extension 和 App Intents；不另起 SQLite 壳，不重建第二套业务域。
3. `FeiMiao` target 冻结为供体和回退参考，不继续扩张，不整支 merge；P1 完成并确认所有采用项后再决定是否删除。
4. 每个功能只有一个 P0–P5 主责阶段。后续批次发现的问题必须回到该阶段关闭，不能用“以后优化”掩盖本批回归。
5. iOS 可以使用原生安全区、键盘、触觉、返回手势和权限弹窗；不得改变 Android 的入口位置、内容层级、字段、状态、动作和业务结果。
6. 当前 entitlements 只有 App Group，没有 iCloud entitlement。产品默认保持本地优先；在 entitlement、开关、冲突、删除、多设备和断网测试齐全前，界面不得宣称自动云同步。
7. 已有 `QingJi` 用户数据必须原地升级。视觉重构不得换库、清库或要求用户重新开始；schema 变化必须有升级、附件完整性和失败回滚测试。
8. P6 最低交付门是“签名后可安装到目标 iPhone 并完成升级测试”。TestFlight/App Store 发布取决于用户提供的签名和分发条件；unsigned IPA 不能计作最终交付。
9. 当前仓库没有 `PrivacyInfo.xcprivacy`。这是 P6 发布阻断项，不是可选美化项。

## 3. 机器合同和功能范围

机器合同：`ios-app/tools/p0_product_contract.json`。
截图 provenance 工具：`ios-app/tools/write_parity_metadata.py` + `ios-app/tools/check_capture_metadata.py`。

规范场景共 41 个，且每个场景有唯一 ID、唯一 iOS 目标入口、唯一主责阶段、两端源码锚点、必需页面锚点、必需业务字段和证据状态：

| 阶段 | 场景数 | 主责范围 |
|---|---:|---|
| P1 | 1 | 抽屉账本与产品壳层 |
| P2 | 11 | 首页、记账、明细、退款报销、账本账户、分类标签与分类记忆 |
| P3 | 13 | 四种统计、预算、存钱、定时、导入、报告、备份、设置、主题和显示 |
| P4 | 7 | 资产 hub、资金页、账户详情、对账、物品、负债和净资产 |
| P5 | 9 | 喵助手、服务商与模型、任务、诊断、搜索、记忆、扩展、计划和本地模型 |

此外还有：

- 12 条黄金操作旅程，覆盖首次启动、支出、收入、转账、退款、报销、预算、导入、备份、物品资产、负债和 AI；
- 6 类 iOS 系统能力合同：Widget、Share Extension、App Intents、OCR、语音、通知/后台；
- 静态截图不能代替这些操作合同，尤其不能证明事务原子性、跨重启恢复、OAuth、通知和扩展行为。

### 已修正的旧清单错误

旧 39 槽位存在一图多义，现已拆成正确合同：

- `books` → `drawer-books` + `books-management`；
- `accounts` → `accounts-management` + `assets-funds`；
- `reconcile` 明确为“资产管理 > 资金 > 账户详情 > 校准/对账”，不是独立根页面；
- `liabilities` 明确属于资产管理资金层；
- `net-worth` 明确属于资产管理总览层；
- `reports` 改为 `reports-library`，与 AI 生成报告动作分开；
- `quick-add`、`transactions` 等含混名称改为明确的操作态或页面态。

## 4. 固定 fixture

规范输入文件：`ios-app/tools/fixtures/p0-demo-ledger-2026-08-v1.json`。

- SHA-256：`E45AB0CEFF322CCAE8A54474AB523F954724A749D0561F698ED81F23850996A6`；
- now：`2026-08-27T12:00:00+08:00`；
- locale：`zh-Hans`；timezone：`Asia/Shanghai`；currency：`CNY`；book：`总账本`；
- 30 条交易输入，包含附着退款和转账；
- 8 月收入 `620.00`、毛支出 `1032.90`、退款 `15.00`、净支出 `1017.90`、结余 `-397.90`、预算 `3000.00`；
- 退款日期必须等于原账单日期，真实到账日保存在 `settledAt`；
- 固定预算、存钱目标、定时规则、报告和物品资产详情样本。

自动检查器会重算上述金额、检查引用、退款归属、41 场景、12 旅程、版本、水印、DB、Bundle ID、deployment target、源码锚点、fixture hash 和 APK hash。

当前两端 seeder 已接入这一份规范文件：Android 采集驱动从 Flutter asset 解码，QingJi 从 Bundle 解码；两端都各自写入演示容器并导出平台中立的业务 JSON。代码接线已完成，但 Android 模拟器/iOS Simulator 的真实运行、导出和逐字段差异报告仍待 macOS/CI 证据，所以 P0 仍不能关闭。

### 4.1 数据升级合同

机器合同中的 `dataUpgrade` 锁定了 `ios-app/tools/migration-fixtures/p0-ios-qingji-upgrade-2026-09-v1.json`（SHA-256 `AE08B995CCCD952CBB1CF965F09B7EC31703734FE660076A0D656AC036D685C6`）。本合同只允许 `QingJi` 的 SwiftData 原地升级，继续使用 `AppModelContainer.shared`；不得换成 `FeiMiaoKit`/GRDB、换 store URL、清库或要求用户重新开始。

- 源模型锚点：`08f7a5e28ffcc65f50dd2661802111d0ef92446c` 的 QingJi inferred model graph；
- 目标模型：当前 `AppModelContainer.swift` 登记的完整 QingJi 模型集合；下一次模型变化前必须引入显式 `VersionedSchema`/迁移计划；
- 必须保留：稳定 ID、账本/账户/流水字段、退款关联、结算字段、排除/报销状态和附件相对路径；
- 必须验证：当前 Android DB v49、v40、v48 备份样本可恢复到 QingJi，附件路径和字节在升级前后不变，注入失败时模型和附件均回滚；
- 当前状态：`SPEC_LOCKED_MACOS_EVIDENCE_PENDING`，不是已完成迁移。

### 4.2 分发决策

本轮 P0–P5 锁定分发模式为 `development-sideload`：最终设备验收必须使用 macOS 签名的 IPA 安装到目标 iPhone。Simulator 的 unsigned build 只用于截图和自动化证据，不能当作真机安装包。

- 签名平台：macOS；团队条件：Personal Team 或 Apple Developer Program；
- 当前凭据状态：`PENDING_MACOS_USER_INPUT`，团队 ID、证书和 provisioning profile 不能在 Windows 猜测或伪造；
- TestFlight/App Store 明确不在本轮范围；切换渠道必须得到用户明确决定并更新机器合同；
- P6 必须补齐签名安装、升级保留数据、真机冒烟和可回退安装包四项证据。

## 5. `0600683` 导入/备份修复审计

结论：**采用**，已 cherry-pick 为 `32beb69`，保持独立提交。

采用内容：

- 报销完成判断使用四舍五入后的 `normalizedAmount`，修复 `59.999 → 60.00` 仍残留待报销的问题；
- `BillRecordSaver` 保存失败时只删除本批新增对象，不破坏已有交易；
- 重复导入不新增；订单号退款挂回原单并保留原账单日期；无法匹配的退款转为可见收入；
- JSON 恢复保存失败回滚 SwiftData；
- ZIP 附件安装失败回滚模型和已覆盖附件；
- 校验和损坏时不修改当前数据；
- 增加 Ledger、BillRecordSaver、BackupStore 回归测试。

边界：Windows 没有 Swift/Xcode，当前只完成代码审计与 `git diff --check`；Swift 编译和 XCTest 必须由 macOS CI 证明。

## 6. `FeiMiao` 供体文件级审计

供体提交：`495c3f6`。结论：**禁止整支 merge**。

### 采用

- 品牌 logo；供体与 Android `assets/brand/logo.png` 的 Git blob 完全相同；
- 11 张账本封面；供体与 Android 对应文件的 Git blob 全部完全相同；
- 资产最终从 Android 母版复制并进入 QingJi 资源目录，Android 始终是来源，不把供体当新规范。

### 重写到 QingJi

- `FeiMiaoTheme` 中的颜色、圆角、间距、字体和动效 token；
- `PressableButtonStyle`、`ParityGlassSurface`；
- `SideDrawerView` 的推开式抽屉和账本操作结构；
- `HomeSummaryCard`、`HomeTransactionFilterControl`、`HomeRecordInputBar`、`TransactionDayCard` 的布局思路；
- mascot 展示逻辑。供体 mascot 是格式转换产物，最终以 Android 原始视觉和 P1 截图验收为准。

“重写”意味着接入 QingJi 现有 Store、Router、主题、无障碍和数据模型；不得直接复制供体的假数据、简化仓库或第二套导航。

### 拒绝

- `FeiMiaoApp`、`AppStore`、`RootTabView` 作为生产根；
- `FeiMiaoKit` 的 SQLite/Repository/Domain 第二套业务栈；
- `AccountsOverviewView` 等空壳或占位管理页；
- 供体对 `project.yml` 的 target/deployment 修改；
- 任何删除 QingJi AI、资产、预算、备份、扩展、entitlements、测试和资源的差异；
- 供体里的自造文案、字段或与 Android 不一致的 iOS 风信息架构。

## 7. 当前证据边界

### 已验证

- Android 母版版本、源码快照、APK 大小和 SHA-256；
- Android 静态分析 0 error、1210/1210 测试；
- 41 个场景合同无重复，源码锚点存在，阶段计数正确；
- 12 条黄金旅程和 6 类系统能力已登记；
- fixture 文件可解析、SHA-256 固定、核心金额可重算；
- Android 采集驱动会把 canonical fixture 暂存到 Flutter asset tree，
  `parity_screenshots_test.dart` 从该 asset 解码；QingJi 通过
  `P0ParityFixtureLoader` 从同一 JSON 资源解码、由 `P0ParityDemoSeeder`
  写入演示容器，并由 `P0ParityBusinessExporter` 输出字段 JSON；这是代码
  接线证据，不等于两端已经在设备上运行成功；
- `run_parity_capture.sh` 的 Android 业务 JSON 校验路径已按其
  `android-app` 工作目录修正；`compare_p0_business_json.py` 默认记录差异，
  只有 `--require-match` 才把业务差异作为失败；
- `0600683` 和 `FeiMiao` 供体已完成采用/重写/拒绝审计；
- iOS 当前项目配置为 QingJi、`com.qingji.app`、iOS 26.0、本地 SwiftData + App Group。
- 数据升级和分发合同已进入机器合同并通过结构校验；运行证据仍按下方未验证项处理。
- 2026-09-03 在独立 P0 worktree 重跑了 Android 生产构建：Gradle
  `:app:assembleRelease` 成功，`versionName=1.289.0`、`versionCode=304`，
  本地产物 SHA-256 为
  `7ED7F15C4265A9CF44C7AF4244E23E14CC6D0B48794D7217B9202E40480A8710`；
  这只是编译证据，不替代设备运行和截图证据。
- 2026-09-03 Android 确定性时钟与仓库定向测试 `144/144` 通过（`app_clock_test.dart`
  2 项、`app_repository_test.dart` 142 项），包含迁移、备份恢复、退款归属、预算和资产回归。
- 2026-09-03 P0 合同校验仍为 `P0_PARTIAL`，两条 CI 路由均为 40/40；Android
  ADB 设备列表为空，未生成新的 41 张 Android PNG 或业务 JSON。
- 旧 39 路由与两个 CI workflow 的 `shoot` 调用数量一致；旧 39 张 iOS PNG 均为 `1260×2736` 且未判为空白；
- 旧图最近似的一对是“存钱目标/定时记账”，`meanDelta=2.101`，高于旧门禁阈值 `1.0`。这只排除了近乎相同的占位图，不证明页面同款。
- metadata 工具已用旧图抽样验证：每张图有独立 sidecar，旧的 books/accounts 槽位会明确标成 `legacy_ambiguous`；完整 41 场景采集才允许 `--require-complete`。

### 未验证

- 41 张 Android 规范截图的重新采集和 metadata sidecar；
- 现有 iOS 页面在 macOS Simulator 上的改前截图与 metadata；
- Android 模拟器和 iOS Simulator 实际从同一 fixture 文件加载、导出业务 JSON，
  并完成一次真实逐字段差异报告；当前 Windows 没有 Android ADB，且不能运行
  Swift/Xcode，因此代码接线尚未升级为运行证据；
- 页面逐项视觉、信息架构和字段结果的同款程度；
- 旧 iOS 数据原地升级、Android v49/v40/v48 完整备份恢复和附件恢复；
- OAuth、真实 AI 网络、Widget、Share Extension、App Intents、权限、通知和后台任务；
- 真机安装、签名、升级、回退、Dynamic Type、VoiceOver、深色模式和 Reduce Motion。

旧 `25-memory.png` 的中央内容采样比例只有 `0.01454`。文件并非纯空白，但接近空态，只能保留为“当前页面存在”的弱证据，不能作为分类记忆功能已完成的证据。

### 平台限制

- 当前 Windows 环境不能运行 Xcode、Swift 编译、XCTest、iOS Simulator、签名或归档；
- 当前没有在线 Android ADB 或 iPhone；
- 因此不能把现有 iOS CI 绿灯、39 张 PNG 可解码或 unsigned IPA 写成产品完成。

## 8. P0 剩余关闭门

1. 在 Android 模拟器和 macOS iOS Simulator 运行固定 fixture，输出同构字段 JSON 并生成差异报告；
2. 重采 41 个 Android 场景，每张带 revision、版本、fixture hash、route、设备、OS、locale、timezone；
3. 在 macOS 捕获所有已存在 iOS 页；缺失目标页写 `missing`，不得拿近似页补数；
4. 在已锁定开发侧载模式的前提下，由 macOS 提供并验证实际签名条件；
5. 用旧 QingJi store 与 Android v49 备份样本验证升级、恢复、附件和失败回滚；
6. 上述证据全部通过后才能把机器合同从 `P0_PARTIAL` 改为 `P0_COMPLETE`，再进入 P1。

## 9. 复现命令

```powershell
& 'C:\Users\寻逆啊\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' `
  'ios-app/tools/check_p0_product_contract.py' `
  --require-apk `
  --apk-path 'C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.289.0-304.apk'
```

预期输出：

```text
P0_PARTIAL contract valid: 41 scenes (P1=1, P2=11, P3=13, P4=7, P5=9), 12 journeys, 6 open gates
```
