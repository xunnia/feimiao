# 肥喵记账 Android -> iOS 原生迁移方案

> 版本：v1，2026-08-27
>
> 目标：在不破坏 Android 现有开发的前提下，把肥喵记账迁移为原生 SwiftUI iOS App。iOS 是同一软件的原生实现：页面结构、主入口、导航层级、业务结果与 Android 对齐；控件、材质、动效和系统集成在对应功能内部按 iOS 规范增强。

## 1. 先给结论

我可以直接完成以下工作：

- SwiftUI / SwiftData 的 iOS App 源码；
- Android 与 iOS 共用的账务规则、DTO、导入导出格式和测试样例；
- iOS 原生页面、Liquid Glass、原生按钮按压、转场、触觉反馈、WidgetKit、App Intents、Share Extension、Vision OCR 和 Speech；
- GitHub Actions 上的 Xcode 27 编译、核心测试、模拟器截图和未签名 IPA；
- Android/iOS 成对截图与同一演示数据下的金额、退款、预算、统计对账报告。

当前 Windows 环境不能替代 Xcode，因此我不能在本机直接完成：

- 本地 iOS 模拟器运行；
- 本地 Apple 证书签名；
- 没有 Apple Account 时生成可安装到用户 iPhone 的个人签名包；
- App Store / TestFlight 正式发布。

这不是代码能力的限制，而是 Apple 工具链和签名链的限制。最终安装仍需要一台可运行 Xcode 的 Mac、云 Mac，或用户自己完成重签。

## 2. Android 当前基线

以交接文档锁定的当前版本为准：

- Flutter / Dart，Provider，SQLite / sqflite；
- 应用版本 `1.265.0+279`，build tag `b0828-279`，数据库 v48；
- Android 当前批次已收口，本次 iOS 迁移只读取 Android 结构，不改 Android 实现；
- 最新本地验收记录 Flutter 全量测试 1127/1127、analyze 0 error；真实 OAuth、provider 网络和真机行为仍不替代为“已验证”。

### 2.1 用户可见功能域

| 功能域 | Android 已有能力 | iOS 迁移优先级 |
|---|---|---|
| 核心账务 | 支出、收入、转账、编辑、删除、按天明细、搜索 | R0 |
| 账本 | 总账本、多账本、封面、备注、排序、加星、删除保护 | R0 |
| 账户 | 现金、银行卡、信用卡、存款、投资、贷款等；余额、对账 | R0 |
| 分类与标签 | 层级分类、自定义分类、隐藏、分类学习、标签 | R0 |
| 退款与报销 | 附着原账单、部分退款、撤销、报销抵消到 0 | R0 |
| 记账入口 | 表达式金额键盘、手动、快捷、AI、定时、自动 | R0 基础入口；R1/R3 扩展 |
| 导入 | 微信/支付宝、咔皮/木木/肥喵、CSV/Excel/GBK、重复检测、导入复核 | R1 |
| 备份 | SQLite、收据、资产媒体、manifest、SHA-256、迁移前备份 | R1 |
| 预算 | 月/周/自定义周期、分类预算、今日可花、固定承诺、专项追踪 | R1 |
| 存钱目标 | 目标金额、已存金额、进度、与物品资产关联 | R1（iOS 基础版已接入） |
| 定时记账 | 日/周/月/年，转账规则，补记到期记录，重复保护 | R1（iOS 基础版已接入） |
| 统计与报告 | 环形图、趋势、排行、热力图、画像、异常、预测、月报、AI 报告 | R0 基础统计；R1/R3 完整 |
| 资产 | 物品、购置成本、追加成本、估值、折旧、照片、发票、生命周期 | R2（iOS 基础档案已接入） |
| 负债 | 信用卡、房贷、车贷、消费贷、个人借入、还款、利息 | R2（iOS 基础档案已接入） |
| 净资产 | 资金/投资、物品/权益/负债、快照、质量状态、可信核对、趋势 | R2（iOS 基础计算已接入） |
| AI | DeepSeek、OpenAI-compatible、OpenAI Responses、Claude、多账号、多模型、Effort、OAuth、Chats、附件、搜索 | R3 |
| 系统集成 | Android 通知监听、WorkManager、APK 更新、4 类 Widget、分享 Intent | R4；部分只能替代 |

### 2.2 Android 端不能直接照搬的能力

1. **通知自动记账**：Android 使用 `NotificationListenerService` 读取微信/支付宝通知。iOS 没有面向第三方 App 的等价全局通知读取权限，不能承诺完全相同的自动化。
2. **后台执行**：Android WorkManager 可以重试任务；iOS `BGTaskScheduler` 由系统择机执行，不能保证固定时刻或固定时长完成报告生成。
3. **应用内更新**：Android 可下载 APK 更新；iOS 需要 App Store、TestFlight 或侧载重装，应用不能自行替换 App 二进制。
4. **OAuth 回调**：Android 当前使用浏览器 + localhost 保活服务；iOS 应使用 `ASWebAuthenticationSession` 配合 URL Scheme 或 Universal Link，不能照搬 Android Service。
5. **分享入口**：Android 是分享 Intent；iOS 对应 Share Extension，运行在独立扩展进程，必须使用 App Group 传递数据。

替代设计：分享扩展、截图/票据 OCR、快捷指令、App Intents、Widget、前台打开时补算、本地通知。它们能覆盖“快速入账”和“主动提醒”，但不会伪装成系统通知监听。

## 3. 跨平台架构

```text
Android SQLite / Flutter                 iOS SwiftData / SwiftUI
          |                                      |
          +-- 稳定 UUID / 分类 key --------------+
          +-- TransactionRecord / DTO ------------+
          +-- 退款、结算、预算、统计契约 ----------+
          +-- 导入/备份 canonical package --------+
          +-- 同一组核心测试夹具 ------------------+
```

### 3.1 QingJiCore

平台无关层放进 `ios-app/QingJiCore`，不依赖 SwiftUI、SwiftData 或 UIKit：

- 金额表达式与 Decimal 金额运算；
- `TransactionKind`、`TransactionEventType`、时间精度、结算质量；
- 交易、账户、预算、分类、备份的跨平台 DTO；
- 退款家族和报销净额策略；
- 账户余额投影；
- 预算周期、今日可花、分类预算；
- 统计口径；
- CSV/微信/支付宝导入解析；
- canonical JSON / ZIP 备份编解码；
- 周期日期推进、资产指标、净资产质量状态；
- 每个关键规则的 XCTest。

SwiftData 只负责持久化和查询，页面不直接散落修改账务字段。所有新增、编辑、退款、报销、删除、导入都经过 Store / Service，避免 Android 与 iOS 各自产生一套隐含规则。

### 3.2 关键数据契约

- 每个业务实体有稳定 UUID；不能用 Android 自增 ID 作为跨平台身份；
- 分类使用稳定 `key`，改名不换 key，历史账单不因升级失联；
- 金额使用 Decimal 或最小货币单位，禁止用 Double 作为账务真值；
- 交易保存 `date` 与 `timePrecision`，不能把没有时分证据的午夜时间显示成明确时间；
- 退款/报销是原交易的子记录，带 `refundOfID`，按原交易日期进入统计；
- 退款结算账户、结算日期、来源质量单独保存；
- 转账不进入收支统计，但要投影到转出和转入账户余额；
- `isExcluded` 同时排除预算、统计和相关 AI 上下文；
- 币种不支持时标记为待核对，不能静默换算为 0；
- 删除原账单时级联处理附着退款，孤儿退款不应出现在用户明细中；
- 附件、订单号、周期规则、资产事件都必须有稳定关联 ID，便于备份恢复和后续同步。

### 3.3 Android ZIP 与 iOS 备份

Android 完整备份包含 SQLite、`receipts/`、`asset_media/`、manifest 和 SHA-256。iOS 不能直接把 Android SQLite 文件当作 SwiftData 数据库打开，因为两端模型和迁移机制不同。

因此采用两层策略：

1. Android 仍保留原始 SQLite 完整备份能力；
2. Android/iOS 共用一个 canonical JSON 数据层和媒体目录，ZIP 只作为容器；
3. iOS 导入 ZIP 时读取 manifest、实体 JSON 和媒体，不直接恢复 Android SQLite；
4. 每个实体按 UUID upsert，报告新增、更新、跳过、冲突和未识别字段；
5. API Key、OAuth refresh token 等凭据永不进入备份；
6. 导入前先做可回滚的本地快照，失败时保留原数据。

这比“直接复制数据库”多一层适配，但能保证 SwiftData、Android SQLite 和未来多人同步都使用同一业务身份。

## 4. iOS 产品实现原则

### 4.1 同一产品结构，原生实现

Android 和 iOS 不要求逐像素复制，但以下内容必须一致：

- 同一输入得到相同金额、类型、分类、账户、日期和账本；
- 退款、报销、转账、不计收支的统计和余额结果一致；
- 预算周期、可花金额、分类统计结果一致；
- 同一导入文件得到相同的商户、订单号、退款配对和重复决策；
- 备份恢复后实体 UUID、金额和关联关系不变。
- 页面结构、主入口、信息层级和导航层级一一对应；主页底部记账输入框、抽屉、搜索、账本切换等 Android 主流程不能被另一套 TabBar 或快捷卡替代。

iOS 页面采用：

- `NavigationStack`、原生 `sheet`、`swipeActions`、`DatePicker` / 自定义原生选择器；
- SwiftUI 标准 Button 的 pressed 状态、`sensoryFeedback` 触觉和系统转场；
- Liquid Glass 只用于导航栏、操作栏、输入栏、分类/筛选胶囊等高价值交互，不给所有卡片无限叠加玻璃；
- `GlassEffectContainer` 管理同一组玻璃控件，控制性能和形变；
- SF Symbols 代替手绘 Android 图标；
- Dynamic Type、VoiceOver、Reduce Motion、深色模式和中文排版作为验收项。

“iOS 有更好的原生效果”可以使用，但只能增强对应功能内部的表现，不能改变页面结构、账务结果或操作反馈。低性能设备或开启减少动态效果时要有降级路径。

## 5. 分阶段施工

### R0：核心账务 parity

目标是先让 iOS 成为可靠的日常记账 App：

- 稳定 UUID、完整交易字段和 SwiftData 模型；
- 支出、收入、转账；
- 多账本、总账本、账本编辑和保护；
- 账户、余额、账户对账；
- 分类层级、自定义分类、标签；
- 快速记账金额键盘、日期/备注/账户/账本/更多选项；
- 明细按天、搜索、编辑、删除；
- 附着式退款、部分退款、退款撤销；
- 待报销抵消到 0；
- 月度/年度统计和基础月/周/自定义预算；
- Android/iOS 同数据测试夹具与第一组配对截图。

当前 iOS 工作树已经有 R0 的部分模型、核心策略、快速记账、明细、退款/报销和周期预算基础，并已开始接入 R1/R2 的目标、周期规则、资产、负债和净资产模型；这批代码尚未经过 Xcode 27 CI 编译和真机验收，不能把它称为完成版。

### R1：导入、备份、预算高级能力

- iOS canonical JSON/ZIP 备份、收据复制、manifest 和 SHA-256 校验已接入；Android v1/v2 原始 SQLite ZIP 已接入 manifest/checksum 校验、只读转换、媒体安装和失败回滚；恢复默认完整替换并保留显式合并模式；AI 运行记录、事件和定时报表计划已纳入 canonical v9；
- 收据/媒体复制、哈希和失败保护；
- 微信/支付宝解析、订单号优先、退款配对、重复检测；
- 导入复核、商品优先分类、按商户分组、一次 AI 归类兜底、退款订单匹配；
- 预算基础周期、总预算、分类预算；预算计划、分类额度、专项追踪和固定承诺模板已接入；
- 当前/下一周期固定承诺 occurrence 物化、账单匹配、跳过/重置和退款复核已接入基础流程，完整历史修订编辑仍待补齐；
- 专项追踪；
- 存钱目标（iOS 基础页面和模型已接入）；
- 定时记账和到期物化（iOS 基础页面、规则和幂等执行已接入）；
- 本地通知提醒。

### R2：资产、负债、净资产

- 资金/物品分栏和账户详情；
- 物品新增、历史补录、从账单加入、新购买（iOS 已完成档案、估值、生命周期和持有指标基础，详情操作/成本关联继续收口）；
- 照片、缩略图、发票、保修、位置、品牌型号；
- 当前估值、购置成本、追加持有成本、持有天数/日均成本/每次使用成本/保值率和折旧；
- 使用次数、出售、退货、报废、丢失、赠送及撤销；
- 权益/应收款和回收记录；
- 信用卡账期、房贷/车贷/消费贷、个人借入和还款（iOS 当前完成本金档案和还款基础）；
- 净资产快照、趋势、可信核对、质量和币种覆盖状态（iOS 当前完成组件计算、快照和外币提示）；
- 外币和历史未知数据的显式待核对状态。

### R3：AI

- API Key Keychain 安全存储；
- DeepSeek、OpenAI-compatible、OpenAI Responses、Anthropic Messages（iOS 已接入首版配置与流式 wire format）；
- 多服务商、多账号、多模型、模型目录和 Effort（iOS 基础版已接入）；
- ChatGPT/Codex OAuth（iOS `ASWebAuthenticationSession` + localhost 1455/1457 loopback + PKCE/state + Keychain refresh token 已接入，真实登录需在 Xcode/真机验证回调注册）；
- 喵助手闲聊/查账/记账边界；
- Chats 新建、搜索、加星、删除和会话级模型（iOS 基础会话列表与持久化已接入）；
- 图片/文件附件（图片/文件内容已映射到三类原生请求格式并持久化附件引用）、来源、思考状态、Markdown/表格；
- AI 分类、退款匹配和月报；
- 网络失败、超时、重试、取消、隐私提示和数据发送范围。

### R4：系统集成与交付

- WidgetKit 迁移四类 Android Widget 的主要信息结构；
- App Intents / Shortcuts 快速记账；
- Share Extension 接收账单文本、截图和图片（iOS 已接入文本/单图 hand-off）；
- Vision OCR、Speech、Local Notifications；
- BGTaskScheduler 已接入本地月报的择机刷新，不能承诺固定时刻；AI 报告后台任务仍需在 R3 端点与会话模型稳定后接入；
- iOS 26/27 模拟器截图、iPhone iOS 27 beta 真机回归；
- 云端签名或用户设备重签；
- TestFlight/App Store 或个人 7 天侧载交付。

## 6. 每批验收门

每一个功能批次必须同时通过：

1. **核心规则测试**：金额、净额、余额、预算、分类和日期规则；
2. **SwiftData 迁移测试**：旧数据打开、升级、备份恢复和关联不丢失；
3. **页面流程测试**：空态、正常态、错误态、取消、重复提交和删除保护；
4. **Android/iOS 同数据对账**：同一 fixture 的结果 JSON 逐字段比较；
5. **成对截图**：同一演示数据、同一时间和相同逻辑尺寸，保存 Android/iOS 两张图；
6. **iOS 无障碍/动效降级**：Dynamic Type、深色模式、VoiceOver、Reduce Motion；
7. **云端构建证据**：Xcode 27 编译、测试、模拟器启动和产物哈希；
8. **真机验收**：在用户的 iPhone iOS 27 beta 上检查输入法、触觉、照片权限、分享、网络和后台行为。

截图只证明画面，不能代替账务测试。对齐表见 `docs/ANDROID_IOS_PARITY.md`。

## 7. Windows、7 天签名和最终交付

Apple 官方的 Personal Team 流程允许免费 Apple Account 在 Xcode 中进行个人真机测试，但 App ID、设备和 provisioning profile 都有 7 天限制；到期要重新构建和安装。它不是永久分发，也不能替代 App Store/TestFlight。

本项目可在 GitHub Actions 的 macOS/Xcode 27 环境生成：

- 核心测试结果；
- iOS 模拟器 App；
- 模拟器截图；
- 未签名设备 IPA；
- 无 Widget 扩展的备用 IPA。

但未签名 IPA 不能直接装进你的 iPhone。安装路线按可靠性排序：

1. 借用或租用 Apple silicon Mac，用 Xcode 登录你的 Apple Account、连接 iPhone、选择 Personal Team、编译并安装；
2. 使用可控的云 Mac 完成同样流程，Apple 密码和双重认证只在你自己的环境输入；
3. 使用 AltStore/SideStore/Sideloadly 等侧载工具重签，仍需要 Apple Account、设备配对和定期续签；
4. 加入 Apple Developer Program 后用 TestFlight 或 App Store，适合长期使用和正式发布。

当前 iOS 工程 deployment target 为 iOS 26.0。GitHub 官方 `macos-26` 镜像目前提供 Xcode 26.x/iOS 26 SDK，Xcode 27 属公开预览，CI 脚本会在镜像已有时优先选择；使用 iOS 26 SDK 构建的 App 可安装到 iOS 27 beta。最终仍要在真实 beta 系统上验证 Liquid Glass、Widget、权限和系统行为。

## 8. 并行 Android 会话的协作规则

同一文件夹不会自动造成代码级冲突，因为 Android 和 iOS 主要是不同目录；但它们共享同一个 Git 工作树，会有以下风险：

- Android 会话的 `git add -A` 可能把 iOS 未完成文件一起提交；
- Flutter/CI 生成物可能改变状态，掩盖真正的 iOS diff；
- Android 的分类/字段/数据库迁移继续变化时，iOS 可能只同步到旧快照；
- reset、checkout、clean 或大范围格式化会误伤另一会话。

执行约束：

- Android 继续只改 `android-app/**`；iOS 迁移只改 `ios-app/**` 和必要的 iOS CI；
- 每次从 Android 稳定提交或版本文档提取契约，不从半成品工作树猜字段；
- 提交时精确 stage iOS 文件，禁止 `git add -A`；
- 每个 R 阶段完成后再生成截图、更新 parity 表和提交；
- 不做 destructive Git 操作，不覆盖用户已有的 iOS 迁移改动。

## 9. 推荐的下一步

以 Android v48 的字段和测试 fixture 为基线，按“先编译、再对账、再扩面”收口：

1. 让 iOS 核心包在 Xcode 27 CI 通过；
2. 补齐 R0 还缺的页面状态和跨平台 fixture；
3. 跑第一轮 Android/iOS 成对截图；
4. 在用户确认金额、退款、预算和输入体验后，继续收口 R1 导入/完整备份/固定承诺，再扩展 R2 资产细节和 R3 AI。

这样可以直接把 App 做出来，同时每一步都能回退、验收和继续扩展，不需要先等待完整 Android 功能全部冻结。
