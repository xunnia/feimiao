# 09 · iOS 版：现状、目标、执行规则、验收

> 整理日期：2026-09-27。合并自 `ios-app/docs/` 下 8 份旧文档，再加上 `ios-app/README.md`、`project.yml`、两个 iOS 工作流、`salvaged-2026-09-06/README.md`、git 分支/worktree 现场和 Obsidian 上架笔记。
> **新旧冲突时以最新复盘为准**：2026-08-31 复盘更正 → 2026-09-02 Luna 方案 → 2026-09-12/09-23 复盘（09-23 版目前只在 worktree 里、还没提交，见 §2.3）。被推翻的旧说法在 §2.4 列出。
> 标「待核实」的地方，是我没法用代码或 CI 结果确认的内容。

---

## 1. 目标（一句话）

**iOS 版就是 Android「肥喵记账」在 iPhone 上的原生实现，不是一个新产品。** Android 当前生产版是唯一母版（本机源码 `1.298.0+313` / DB v49；线上公告版本以更新服务为准）。

**必须和 Android 一模一样的部分：**主页 + 左侧推开式抽屉（没有底部 Tab）；每个入口的名称、位置、层级；页面首屏的信息顺序和字段；金额、净额、退款/报销归属、预算、统计、净资产的算法；肥喵 Logo、猫咪、分类图标、账本封面和猫系配色（收入铜金、支出深色、超支橙，不用系统红绿）；空态、错误、取消、删除/撤销之后看到的结果。

**允许用 iOS 原生方式做的部分：**状态栏/灵动岛/安全区、系统键盘、日期选择器、相册和文件选择器、触觉反馈、侧滑返回、sheet 转场、VoiceOver/动态字体/减弱动态效果/深色模式、系统权限弹窗，以及 Liquid Glass 材质。这些只能改“手感”，不能改“页面是什么、入口在哪、结果是多少”。

**Apple 做不到的地方，用同目标替代方案，并且老实写出差异：**
| Android 能力 | iOS 替代方案 |
|---|---|
| 读取微信/支付宝通知自动记账 | 分享扩展 + OCR + 快捷指令（iOS 没有这种系统权限） |
| WorkManager 定时后台生成 | 本地通知提醒 + 打开 App 时补算；BGTask 只是“系统有空才跑” |
| APK 应用内更新 | TestFlight / App Store / 侧载重签，不放假的“更新”按钮 |
| 任意明文 HTTP | 只允许本机回环/受控局域网，远程一律 HTTPS |

---

## 2. 当前真实状态

### 2.1 总体结论
- 状态是 **`P0_PARTIAL`，属于开发预览版**。P1–P6 都还没有完整的关闭证据。旧文档里的“70%–75% 完成度”已经被 09-12 复盘作废（没有可审计的分母），**不要再引用任何完成百分比**。
- 工程：`ios-app/project.yml` → XcodeGen，App 名“肥喵记账”，Bundle ID `com.qingji.app`（加 `.share` / `.widget` / `.tests`），**部署目标 iOS 26.0**，仅支持 iPhone，版本 **`1.286.0+300`**（落后 Android 很多）。
- 技术栈：SwiftUI + SwiftData（`QingJi`）+ 平台无关规则包 `QingJiCore`（SwiftPM）+ `QingJiWidget` + `QingJiShare` + App Intents。只有 App Group 权限，**没有 iCloud 权限**。
- 规模（main）：约 172 个 Swift 文件、37 个测试文件。根视图 `RootTabView` 实际是 NavigationStack + 抽屉，**没有 TabView**（名字是历史遗留）。

### 2.2 各领域已有什么（“有代码”≠“验收通过”）
| 领域 | 代码状态 | 还缺什么 |
|---|---|---|
| 壳层/抽屉/品牌组件 (P1) | 有抽屉、暖色背景、玻璃按钮 | 更像覆盖式 iOS 面板；系统蓝/纯白卡/SF Symbol 混用，要统一 token 和组件 |
| 首页/记账/明细/退款报销/账本账户分类标签 (P2) | 基本都有；退款挂在原单上、按原单日期归属 | 同 fixture 逐字段对账、真实操作链、重启读回 |
| 统计/预算/存钱/定时/导入/备份/报告/设置/主题 (P3) | 大部分有；`codex/screenshot-stability` 上正在对齐统计卡片 | 预算管理页骨架不对；六套主题、显示设置不全；旧库升级和 Android 备份恢复还没实测 |
| 资产/负债/对账/净资产 (P4) | 基础档案、还款、快照都有 | **资产-资金 tab 缺失**（parity 报 missing）；借贷往来/房贷向导/退款分摊只在候选分支上 |
| AI/OAuth/系统能力 (P5) | Keychain、多服务商、Chats、PKCE OAuth、Widget、Share、Intent、OCR、Speech 都有基础版 | AI 设置 10 个入口层级不全；真实网络/OAuth/扩展**都没在真机跑过** |
| 交付 (P6) | CI 能出**未签名** IPA（完整版 + 无扩展兜底版） | 没签名、没装过真机、**没有 `PrivacyInfo.xcprivacy`**（发布阻断项） |

### 2.3 代码分散在哪里（重要）
> ⚠️ 仓库在 GitHub 迁移时改写过历史，各分支和 main 的“领先/落后 N 个提交”数字没有意义（都显示两三百）。下面是按**文件内容**比对出来的结果。旧文档里的提交号（如 `72f14808`、`0600683`、`32beb69`）在新仓库里可能已经找不到了——**待核实**。

| 位置 | 分支/状态 | 里面有什么 | 合入主线了吗 |
|---|---|---|---|
| `main`（远端默认分支） | 最新 iOS 提交 `96edaec`（09-03） | 09-03 的 P0 取证门禁；41 场景清单；`p0/P0_BASELINE_DECISIONS.md` | —（就是主线本身） |
| 主工作区 `C:\src\xunni-codex` | 已切到 `main`（2026-09-27） | `ios-app/` 就是 main 的版本 | —（开发 iOS 仍建议从 main 开独立 worktree） |
| worktree `.tmp/repository-cleanup` | **`codex/screenshot-stability`**（`60963fa`，09-27，已推送） | **最新的 UI 工作线**：统计卡片对齐、月热力图、资产资金分组等；和 main 差 46 个文件 | ❌ 未合入。另有 **未提交**：09-23 修订版 Luna 方案 + 执行合同、`IOS_REBUILD_PLAN_REVIEW_2026-09-23.md`、`p0/P0_CAPTURE_ACCEPTANCE_2026-09-20.md` |
| worktree `.tmp/ios-p1-integration` | **`codex/ios-p1-integration`**（`2cb4b97`，09-19） | 把抢救回来的 P1 功能（借贷 `LendingView`、房贷向导 `LoanWizardView`、资产退款分摊 `AssetRefundAllocationStore`、预算 V2 等）接入；软删除修复 `820e6d3`；和 main 差 93 个文件 | ❌ 未合入，只是**候选**。本地比远端多 **4 个未推送提交**；另有未提交：两个工作流、`RootTabView.swift`、`AppRouterTests.swift`、`p0/SOFT_DELETE_REPAIR_2026-09-12.md` |
| worktree `.tmp/fix-parity` | `codex/fix-parity-gates`（`c118ce4`，09-08，已推送） | 截图门禁的小修（7 个 iOS 文件） | ❌ 未合入；和上面两条线都不是祖先关系，是否已被吸收**待核实** |
| 分支 `codex/ios-same-app` | 09-05 | 09-02 方案指定的 P0 集成分支 | ✅ 内容已等同于 main 的 iOS 部分（无差异） |
| 分支 `rescue/ios-p1-2026-08-31` | 08-31 | 14 个 P1 提交（预算 V2、资产退款分摊、借贷、房贷向导、权益详情、备份加固…） | ❌ 未合入；已被 `ios-p1-integration` 吸收了多少**待核实**。⚠️ 本地和远端同名分支**已分叉**（本地 `2673c4c` / 远端 `ac364e8`），哪个才是真的**待核实** |
| 目录 `salvaged-2026-09-06/ios-app/` | 09-12 整理时已移出 main；原文件仍在本机旧工作目录和 `.tmp/repo-cleanup-20260912/all-refs.bundle` | 24 个文件，其中 **`BudgetSpecialTracking.swift`（预算专项追踪）在所有分支都不存在**；`BookCovers` 图集只有 json 没有图 | ❌ README 要求：确认能编译、补齐图片、跑过 CI 之前不要拷回去 |
| 目录 `salvaged-2026-09-06/from-worktree-ios-batch15/` | 同上，不在 main | FeiMiao 那套实现的收尾改动 | ❌ 只能当参考 |
| tag `archive/ios-feimiao-rewrite-2026-07` | 已归档 | 第一次重写 `FeiMiao/` + `FeiMiaoKit/`（GRDB、`com.feimiao.app`、0.2.0） | 🚫 **禁止**整体采用 |
| `ios-app/安装包/FeiMiao-unsigned.ipa` | main 里还跟踪着 | FeiMiao 那套的旧安装包 | 容易被误认成当前产品，建议后续清理（本次不动） |

### 2.4 被复盘推翻的旧说法（以后别再引用）
| 旧说法（出处） | 现在的结论 |
|---|---|
| “Parity #61 的 39/39 已成对截图 = 已完成”（PARITY、MATRIX、SCREENSHOT_MATRIX） | 只能证明 PNG 存在、能打开。当时 iOS 导入复核页其实显示的是首页、Android 截图有透明黑底、两端 fixture 金额不一致、有的场景拿相近页面顶替 |
| 完成度 70–75% / 50–55% / 35–40%（08-31 执行合同） | 09-12 作废，不报百分比 |
| 用 SF Symbols 替代 Android 的手绘图标（迁移方案 §4.1） | 禁止。Logo、猫、分类图标、账本封面必须用肥喵自己的素材 |
| TabView + `tabBarMinimizeBehavior`（iOS 27 核验） | 违反“没有底部 Tab”；当前代码已不用 TabView |
| 用 `Form`/`List`/大标题做设置类页面 | 禁的是**换掉信息架构**，不是禁用 List/Form 控件本身（09-23 修正） |
| iOS 不直接读 Android SQLite，只走 canonical JSON（迁移方案 §3.3） | 后来已实现 Android v1/v2 原始 SQLite ZIP 的只读转换；但真实备份恢复**还没实测** |
| README 写“加上 CloudKit 就自动同步” | P0 决定：本地优先，没有 iCloud 权限；在权限、冲突/删除、断网测试都齐之前，不许宣称会同步 |
| “没有 Mac 就装不了” | 09-23：Windows 也可能通过 AltStore 这类工具用自己的 Apple 账号重签，但**还没有真机成功过** |
| 以 Android 1.270/1.281/1.289/1.293 为基线 | 都是历史快照；每批重新锁定母版（见 §3.4） |
| 31 个 / 35 个 / 39 个场景 | 现在的合同是 **41 个静态场景 + 12 条用户旅程**（`ios-app/tools/p0_product_contract.json`，在 main 和两条候选分支上都有；主工作区那份 `ios-app/` 是 09-06 旧快照，看不到这个文件）。这是**范围**，不是已通过的数量 |

---

## 3. 执行规则（同款合同）

### 3.1 禁止
- 删除、合并、改名或挪动 Android 已有的入口；增加底部 Tab；另做第二套首页。
- 用系统默认风格（系统蓝、纯白卡、默认 Section）把 Android 的工作台页面改成通用设置页。
- 用静态页面、mock 数据、demo 直接跳转来冒充功能已经打通。
- 维护两套生产数据层 / 两个 Bundle ID（`FeiMiao`、GRDB、`com.feimiao.app` 一律不进生产）。FeiMiao 只能**逐个文件**移植纯 UI 和素材，而且要先和当前 Android 对一遍。
- 把 CI 绿灯、PNG 数量、生成了 IPA 当成“产品完成”。
- 为了让 UI 好做，去改分类 key、UUID、退款关系、备份格式或 OAuth 安全边界。

### 3.2 数据安全
- 老用户的 `QingJi` 数据必须**原地升级**，不许换库、清库。每次 schema 变更都要有：用旧提交生成的真实旧库去打开的升级测试、附件完整性测试、失败回滚测试。“新建库再重新打开”不算升级测试。
- 所有冲减类记录（退款/报销）的日期都算在**原订单那天**；金额用 Decimal，不用 Double。

### 3.3 Git 与协作
- 主工作区里有别人正在改的 Android 代码：**禁止** `git add -A`、整体 stash、reset、clean、整分支 merge。iOS 改动只在各自的 worktree 里做，精确地 stage `ios-app/**` 和 iOS 工作流。
- 每批只做一条完整用户链路，或 2–4 个关系紧密的页面；每批都要能单独回退。同一时间最多只能有一个“视觉还没封板”的 UI 批次。
- Windows 上没有 Swift/Xcode，本机只能做 diff 和 Python 门禁脚本；**必须等 macOS CI 跑完才能写“编译/测试通过”**。不许自动轮询 CI（用户已经拒绝过）。

### 3.4 母版冻结
分清三个身份：**线上 APK**（版本 + 哈希）、**源码快照**（干净的 SHA）、**截图构建**（实际构建时的 SHA + fixture）。版本号一样不代表这三者一致。每批冻结一个 Android 参考版本；Android 的新变化进入“增量差异队列”，只在批次边界上升级母版。Android 本身的 bug 不照抄，要登记并确认正确规则。

### 3.5 阶段（09-23 修订后）
- **P0** 拆成三部分：**P0-DEV**（开发准入：基线、入口、fixture、改前截图、回退点）、**P0-DATA**（升级/恢复样本和回滚合同）、**P0-DEVICE**（装机可行性）。它们阻止的只是各自影响的结论，不会把整个项目锁死。
- **P1** 壳层/品牌/组件 → **P2** 核心记账 → **P3** 统计预算导入备份设置 → **P4** 资产 → **P5** AI/系统能力 → **P6** 集成交付。
- 立即执行队列：**N0** 收尾周/月统计 → **N1** 锁定母版身份 → **N2** 证据与机器合同同步（N2-D 数据安全、N2-I 真机试装**并行**）→ N3–N8 对应 P1–P6。

---

## 4. 验收方式

### 4.1 三类证据分开算
1. **截图**：同 routeId、同 fixture、同逻辑时间的 Android 原图 + iOS 改前图 + iOS 改后图 + 并排对比图，每张都带 metadata（源码 SHA、版本、fixture 哈希、设备、系统、语言、时区）。两端分辨率不同（1080×1920 对比 1260×2736），报告里的 `dimension_mismatch` 表示“**还没做视觉判断**”，不是通过。**有 UI 的交付必须把图直接给用户看。**
2. **交互**：冷启动直接跳到目标页只能证明“页面画得出来”。点击、返回、保存必须是真实操作（XCUITest / 模拟器交互 / 用户真机录屏），并且重启后查库确认。
3. **业务**：两端导出字段 JSON 逐字段对比。只有 `platform` 这类来源字段可以列入白名单；金额、日期、主键、关联字段不许被忽略。

固定 fixture：`p0-demo-ledger-2026-08-v1`，时间 `2026-08-27T12:00:00+08:00`，zh-Hans / 上海时区 / CNY / 总账本；期望 收入 620.00、支出 1017.90、结余 −397.90、预算 3000.00。启动参数 `QINGJI_DEMO=1`、`QINGJI_DEMO_NOW`，路由用 `QINGJI_SCREEN`。

### 4.2 CI 怎么跑
- **`.github/workflows/ios-ci.yml`**：推送 `claude/** codex/** feature/** main` 且改动了 `ios-app/**` 时触发，也可以手动触发。在 `macos-26` 上跑（优先用 Xcode 27，没有就用 26.x）：QingJiCore `swift test` → 模拟器编译 → App XCTest → 模拟器截图 → 未签名 IPA（`QingJi-unsigned.ipa` 完整版 + `QingJi-noext.ipa` 去掉扩展和 entitlements 的兜底版）→ 上传为 Actions Artifacts。09-12 起不再自动提交回分支；Artifacts 会过期，长期证据要另行归档。
- **`.github/workflows/parity-screenshots.yml`**：Android 模拟器（分片）+ iOS 模拟器各自采集 → 核对来源 → `ios-app/tools/compare_png.py --require-complete` → 生成可视化对比图和 P0 基线报告 → 上传为 Artifacts（不回写分支）。两个工作流共用同一个并发组，不会互相抢着写。
- 相关工具：`ios-app/tools/screenshot_manifest.json`、`check_route_manifest.py`、`check_p0_product_contract.py`、`write_parity_metadata.py`、`check_capture_metadata.py`。
- 最近一次完整的双端采集：run `35508046549`（`76e093f`，在 screenshot-stability 线上）：41 个场景里 40 对有图，全部是 `dimension_mismatch`，`assets-funds` 缺失；业务 diff 只有 `platform` 一项。**这次运行没有验证 P1 候选分支。**

### 4.3 真机验收
用户的环境：Windows、没有自己的 Mac、没有付费开发者账号、iPhone Air、iOS 27 预览版（具体 build 号**待核实**，测试前记录下来）。
最小试装链：用户自己输入凭据 → 核对 IPA → 重签，检查 Bundle ID / Team / App Group → 安装、冷启动 → 记几笔合成账目 → 重启后数据还在 → 导出恢复点 → 续签/更新后再查一遍。**不要让用户先卸载唯一有数据的那个 App**；改了 Bundle ID 或签名 Team 就等于换了一个安装身份，不能承诺能覆盖升级。免费 Personal Team 签名 **7 天过期**。
交付分四级：①工程能跑 ②指定功能在模拟器验收通过 ③用户设备上可安装的预览版（写明限制）④最终同款交付。③不等于④。

---

## 5. 上架路线要点（摘自 Obsidian《Fable5 给我的 iOS 上架路线》，09-26）
> ⚠️ 这份笔记是**按 Flutter 写的**（`flutter run` / `ios/Runner`），但我们的 iOS 是原生 SwiftUI，那些 Flutter 步骤不适用；笔记里“纯本地、不联网、不收集数据”的前提，也和肥喵的 AI 联网功能冲突。下面只保留仍然适用的部分。
- **账号**：Apple ID 开双重认证 → Apple Developer 个人账号（每年约 ¥688）→ 在 App Store Connect 签付费协议、填税务和银行 → 申请小型企业计划（抽成 30%→15%）。
- **Mac**：打包归档、上传需要 Xcode。GitHub macOS CI 能编译；CI 签名归档上传要把证书放进 Secrets，可行性**待核实**；也可以借用或租用 Mac。
- **Bundle ID 上架后永远不能改**，备案也要填它。现在是 `com.qingji.app`，要不要换成肥喵自己的 ID 必须**在备案和首次上架前定死**（**待用户决定**）。
- **只支持 iPhone**（工程已经是 `TARGETED_DEVICE_FAMILY=1`）。
- **提审必备**：`PrivacyInfo.xcprivacy`（现在**缺**）；权限说明文案（相机/相册/麦克风/语音已经写好）；`ITSAppUsesNonExemptEncryption=false` 已经设置（有 HTTPS 联网时这样填是否合规**待核实**）。
- **隐私标签**：因为有 AI 联网（会把用户选择的内容发给第三方模型），**不能简单选“不收集数据”**，要按实际情况申报（**待核实**）。
- **中国大陆上架**：需要 ICP 备案（域名要用 .com/.cn + 轻量服务器放官网和 https 隐私政策页）→ App 备案（填 App 名 + Bundle ID）→ 把备案号填进 ASC。备案要等 2–4 周，建议**尽早并行启动**。
- **内购**（如果要做“Pro 买断”）：非消耗型 + 必须有“恢复购买”按钮；原生用 StoreKit 2。收费范围和价格是**产品决策、待定**。
- **先走 TestFlight 内部测试**，再提审。记账类 App 常见的拒审原因：功能没做完/显示“敬请期待”、没有恢复购买、隐私说明敷衍、**明显的 Android 风格控件**、截图和实际不符。
- 年成本大约 ¥850–1100（账号 + 域名 + 服务器，不含 Mac）。

---

## 6. 待办与风险

**近期待办（按顺序）**
1. 把各 worktree 里**未提交/未推送**的东西先保全：`ios-p1-integration` 的 4 个未推送提交 + 未提交改动，`repository-cleanup` 的 09-23 方案文档（得到用户同意后再提交）。
2. N0：收尾周/月统计（最终 CI 结果、原图、核对数字、真实点击下钻）。
3. N1：锁定 Android 母版（线上 APK 哈希 ↔ 干净源码 ↔ DB 版本），整理 308→当前版本的增量队列。
4. 决定集成顺序：screenshot-stability（UI 线）和 ios-p1-integration（功能候选）怎么合流进 main，谁先谁后（**待决定**）。两条线都不包含对方，直接 merge 可能冲突或造成回退。
5. 处理 `BudgetSpecialTracking.swift` 这类只存在于 salvaged 目录的孤本；核实 rescue 分支本地/远端分叉的问题。
6. N2：同步机器合同（`p0_product_contract.json` 的 6 个开放门禁）、检查器、README/BASELINE 里过期的 304/308 数值；把原始截图归档到 `.tmp` 以外的地方（Actions 的产物会过期）。
7. 并行：旧库升级 + Android v40/v48/当前版本备份的恢复实测；第一次真机试装。
8. 补 `PrivacyInfo.xcprivacy`；iOS 版本号追上 Android。

**风险**
- 代码分散在 3 个 worktree + 2 个分支 + 1 个抢救目录，而且 GitHub 迁移改写了历史，**最容易出现的事故是功能丢失或整支覆盖造成回退**。
- 09-12 那次，`84ae9f1` 的 App XCTest 失败过，原因是 SwiftData 的 `isDeleted` 冲突，已由 `820e6d3` 改名为 `isSoftDeleted`；但**旧库升级还没被证明**。
- Android 一直在往前走（313），iOS 在追一个移动的目标 → 必须按批冻结母版。
- iOS 27 预览版 + 免费签名 + 扩展（App Group）能不能装得上，完全未知。无扩展兜底包是否会改变 App Group / Keychain / 数据库路径，**待核实**。
- 后台能力（定时报表、定时记账）在 iOS 上不保证准时，文案不能夸大。

---

## 7. Liquid Glass / iOS 27 技术约束（要点）
- `glassEffect(_:in:)`、`GlassEffectContainer`、`glassEffectID`、`.buttonStyle(.glass/.glassProminent)` 都需要 **iOS 26.0+**，所以部署目标定在 26.0 就能覆盖 iOS 27，不用锁死 27。真正用到 iOS 27 专属 API 时，才需要 Xcode 27 SDK。
- 玻璃只用在**导航/输入栏/关键操作/分类筛选胶囊**这类控件层；账单内容卡不要层层叠玻璃，要保证可读性。成组的控件放进 `GlassEffectContainer`（性能更好、还能互相融合变形）。
- Liquid Glass 只是**材质**，颜色语义、布局、入口还是以 Android 为准；不能把“系统默认样式”当成理由去换掉品牌 token。
- 性能验收和视觉验收分开：性能要用同一份数据集的真实耗时或 XCTest measure 来比，不能拿截图当性能证据。
- 公开的 GitHub runner 只有 `macos-26` 标签，没有 `xcode-27` 标签；工作流会自动挑 Xcode 27，没有就回退到 26.x。模拟器通过不代表 iOS 27 真机没问题；动态效果、触觉、字体、安全区最终要在 iPhone Air 真机上验收。
