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

- SHA-256：`AC6BA74FE1C9C43C29CF9915FB9632E5496338E838394DEF72FBD7DDFA7D498C`；
- now：`2026-08-27T12:00:00+08:00`；
- locale：`zh-Hans`；timezone：`Asia/Shanghai`；currency：`CNY`；book：`总账本`；
- 30 条交易输入，包含附着退款和转账；
- 8 月收入 `620.00`、毛支出 `1032.90`、退款 `15.00`、净支出 `1017.90`、结余 `-397.90`、预算 `3000.00`；
- 退款日期必须等于原账单日期，真实到账日保存在 `settledAt`；
- 固定预算、存钱目标、定时规则、报告和物品资产详情样本。

自动检查器会重算上述金额、检查引用、退款归属、41 场景、12 旅程、版本、水印、DB、Bundle ID、deployment target、源码锚点、fixture hash 和 APK hash。

当前两端 seeder 的可见数据与该 fixture 基本一致，但尚未真正从这一份规范文件加载，也未导出同构业务 JSON，所以 P0 仍不能关闭。

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
- `0600683` 和 `FeiMiao` 供体已完成采用/重写/拒绝审计；
- iOS 当前项目配置为 QingJi、`com.qingji.app`、iOS 26.0、本地 SwiftData + App Group。
- 旧 39 路由与两个 CI workflow 的 `shoot` 调用数量一致；旧 39 张 iOS PNG 均为 `1260×2736` 且未判为空白；
- 旧图最近似的一对是“存钱目标/定时记账”，`meanDelta=2.101`，高于旧门禁阈值 `1.0`。这只排除了近乎相同的占位图，不证明页面同款。
- metadata 工具已用旧图抽样验证：每张图有独立 sidecar，旧的 books/accounts 槽位会明确标成 `legacy_ambiguous`；完整 41 场景采集才允许 `--require-complete`。

### 未验证

- 41 张 Android 规范截图的重新采集和 metadata sidecar；
- 现有 iOS 页面在 macOS Simulator 上的改前截图与 metadata；
- 两端从同一 fixture 文件加载并导出同构业务 JSON；
- 页面逐项视觉、信息架构和字段结果的同款程度；
- 旧 iOS 数据原地升级、Android v49 完整备份恢复和附件恢复；
- OAuth、真实 AI 网络、Widget、Share Extension、App Intents、权限、通知和后台任务；
- 真机安装、签名、升级、回退、Dynamic Type、VoiceOver、深色模式和 Reduce Motion。

旧 `25-memory.png` 的中央内容采样比例只有 `0.01454`。文件并非纯空白，但接近空态，只能保留为“当前页面存在”的弱证据，不能作为分类记忆功能已完成的证据。

### 平台限制

- 当前 Windows 环境不能运行 Xcode、Swift 编译、XCTest、iOS Simulator、签名或归档；
- 当前没有在线 Android ADB 或 iPhone；
- 因此不能把现有 iOS CI 绿灯、39 张 PNG 可解码或 unsigned IPA 写成产品完成。

## 8. P0 剩余关闭门

1. 让 Android 和 iOS 都从固定 fixture 规范加载，输出同构字段 JSON 并生成差异报告；
2. 重采 41 个 Android 场景，每张带 revision、版本、fixture hash、route、设备、OS、locale、timezone；
3. 在 macOS 捕获所有已存在 iOS 页；缺失目标页写 `missing`，不得拿近似页补数；
4. 锁定本轮最终分发模式和签名条件；
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
