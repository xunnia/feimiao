# 肥喵记账 Android → iOS 功能对照矩阵

更新时间：2026-08-29

## 基线与验收原则

- Android 成对截图基线：1.269.0+283、b0829-283、DB v48。
- Android 自动证据：Flutter analyze 0 error、全量测试 1129/1129；Parity #51（旧远端提交 d95fe65）已完成 35 张 Android/iOS 成对截图与完整性对比，安卓 1.269.0+283 进入远端后需按新基线重跑；真实 OAuth、provider 网络、IME 和真机仍是用户设备验收项。
- iOS 工程：原生 SwiftUI + SwiftData + QingJiCore；部署目标 iOS 26.0，可运行于 iOS 27 beta。
- iOS 当前状态：原生 SwiftUI/SwiftData 工程已建立，核心逻辑、App XCTest、模拟器构建和截图由 macOS CI 验证；Windows 仍没有 Swift/Xcode，iPhone Air 真机和真实账号网络行为仍待设备验收。
- “一致”指同一输入得到相同的金额、类型、分类、日期、账本、账户、净额、预算和统计结果，且页面结构、主入口和导航层级一一对应；按钮触感、转场、材质、系统控件和动效可以用平台原生实现，但不能删掉或替换 Android 的功能入口。

## 功能矩阵

| 功能域 | Android 事实入口 | iOS 计划/当前落点 | 当前状态 | 必须验证 |
|---|---|---|---|---|
| 首页月度总览 | lib/views/home/home_view.dart | QingJi/Views/Home/HomeView.swift | 已有原生首页、账本筛选、月度汇总、喵助手入口 | 同一 fixture 的收入/支出/结余、最近流水和空态截图 |
| 手动支出/收入 | lib/views/quick_add/quick_add_view.dart、home/manual_add_sheet.dart | Views/QuickAdd/QuickAddView.swift、AmountKeypad.swift、CategoryGrid.swift | 已有表达式键盘、两级分类、账户/账本/标签/备注/附件/报销/不计入 | 三种类型保存、金额边界、键盘/IME 真机截图 |
| 转账 | quick_add_view.dart、record_entry_sheet.dart | QuickAddView + LedgerStore | 已有双账户校验，转账不进收支统计 | 余额两端变化、统计排除、不同币种/同账户拒绝 |
| 明细与搜索 | widgets/transaction_day_list.dart、views/search/search_view.dart | Views/Transactions/TransactionListView.swift | 已有按天列表、搜索、类型/账户/标签/日期/金额筛选、编辑/删除 | 净额、筛选结果、按天小计、原生 swipe actions |
| 退款 | widgets/transaction_actions.dart、AppRepository.refundTransaction | LedgerStore.createOffset、EditTransactionSheet | 已有附着式退款、部分退款、余额上限、原账单日期/结算日期分离、撤销 | 原账单净额、退款 badge、跨月归属、删除级联 |
| 报销 | views/transactions/reimburse_view.dart、markReimbursed | ReimburseView + LedgerStore.createOffset | 已有报销抵消到 0；余额校准链路不再伪造收入/支出 | 部分/全部报销、待报销列表、到账账户和日期 |
| 账本 | 抽屉、views/books/book_sheet.dart | Views/Settings/BooksView.swift | 已有总账本保护、封面/备注、排序、加星、归档/删除确认基础 | 总账本保护、切换 scope、恢复/删除行为 |
| 账户与余额 | views/assets 资金页、account_detail_page.dart | AccountsView.swift、LedgerStore | 已有账户类型、期初余额、信用卡字段、归档、余额计算 | 重名账户 stable UUID、负债账户、账户流水和余额 |
| 余额核对 | account_detail_page.dart、checkpoint API | AccountCheckpointStore.swift、CheckpointModels.swift、ReconcileView.swift | 已接入可撤销校准记录，不生成普通收支 | 校准后余额、撤销恢复、净资产同步、历史记录 |
| 分类 | views/settings/categories_view.dart | CategoriesView.swift、CategorySeed.swift | 已有稳定 key、两级树、自定义/隐藏/合并基础 | 120 个分类 key、历史交易不失联、分类筛选 |
| 标签 | views/settings/tags_view.dart | TagsView.swift、交易标签快照 | 已有标签管理和交易引用 | 新增/编辑/删除、历史账目不丢标签 |
| 喵分类记忆 | views/settings/memory_view.dart | MemoryView.swift、CategoryMemoryStore.swift | 已有决定性商户学习、展示和忘记 | 平台商户不误学、自定义分类、重启保持 |
| 预算基础 | budget_setting_view.dart、BudgetEngine | BudgetSettingView.swift、BudgetStore、BudgetEngine.swift | 已有月/周/自定义、总预算、分类预算、今日可花 | 同一预算窗口、退款/报销净额、历史月份 |
| 预算高级 | budget_plan_v2.dart、固定承诺/专项追踪 | BudgetV2Models.swift、BudgetPlanV2.swift、编辑页 | 预算计划、分类额度、专项追踪、固定承诺模板和当前/下一周期 occurrence 物化已接入 | 生效版本编辑、固定承诺账单匹配/跳过/退款复核 |
| 存钱目标 | savings_goals_view.dart | SavingsGoalsView.swift、SavingsGoal | 已有目标、进度、归档/恢复和资产关联字段 | 进度、归档、备份恢复 |
| 定时记账 | recurring_view.dart、occurrence 表 | RecurringRulesView.swift、RecurringStore.swift | 已有日/周/月/年、转账、到期幂等物化 | 重复打开不重复落账、结束日期/次数、账户失效 |
| 微信/支付宝导入 | bill_import.dart、bill_review_view.dart | PaymentBillImporter.swift、ImportReviewView.swift、BillRecordSaver | 已有列名定位、中文/英文金额、GBK 入口、商品优先分类、商户分组、退款订单号匹配 | 真实导出文件、重复导入、退款/不计收支/0 元行 |
| 完整备份 | backup_package_codec.dart、SQLite/ZIP | BackupStore.swift、AndroidBackupImporter.swift、BackupView.swift | 已有 canonical JSON/ZIP、manifest/SHA-256、Android SQLite 只读转换、媒体安装、本机恢复点；恢复默认完整替换，另保留显式合并模式 | 旧 Android v48 ZIP、附件、失败回滚、真机恢复 |
| 报告库/月报 | report_views.dart、monthly_report_view.dart | ReportsView.swift、ReportStore.swift | 已有本地月报、阅读、置顶、删除、后台择机刷新基础 | 同一统计结果、Markdown/表格、后台限制说明 |
| 资产物品 | views/assets/physical_asset_* | AssetsView.swift、AssetStore.swift、ExtendedModels.swift、QingJiCore AssetMetrics/Allocation | 已有档案、估值、照片路径、生命周期、使用次数、持有天数/日均成本/每次成本/保值率和分摊校验基础 | 购置/估值/出售/退货/报废/丢失/赠送的详情操作、资产成本自动关联和退款分摊 UI |
| 权益/应收 | receivable_*、lending_view.dart | AssetsView.swift、AssetStore.swift | 已有应收、部分收回、损失、归档和恢复基础 | 回收流水、剩余金额、净资产 |
| 负债/还款 | liability_*、loan_wizard_sheet.dart、repayment_sheet.dart | LiabilitiesView.swift、LiabilityStore | 已有信用卡/房贷/车贷/个人借入档案、还款基础和利息拆分 | 本金/利息、账户余额、信用卡字段、还款向导 |
| 还款提醒 | repayment_reminder.dart + Android 通知 | RepaymentReminderScheduler.swift + UserNotifications | 已有前一天/当天本地通知排程和设置开关 | 权限拒绝、日期边界、系统通知实际到达 |
| 净资产 | asset_overview_cards.dart、verified checkpoints | NetWorthView.swift、NetWorthStore.swift | 已有资金/投资/物品/权益/负债拆分、外币待核对、快照；账户校准已接入 | 负债重复计算、外币、快照历史、校准后结果 |
| AI 账号/模型 | ai_setting_view.dart、provider/model catalog | AIProviderStore.swift、AIProviderSettingsView.swift | 已有 Keychain、多服务商、多模型、端点选择、Effort、JSON 配置迁移 | Keychain、同名模型隔离、重启、真实 provider 网络 |
| AI 记一笔 | ai_quick_entry_view.dart、结构化提案 | AIQuickEntryView.swift、AIRecordProposal.swift | 已有本地解析 + 云端 JSON 提案、多笔、改分类、批量原子保存 | 不确认不落账、金额精度、账户/账本、真实模型 JSON |
| 喵助手/Chats | ai_chat_panel.dart、meow_assistant_view.dart、Chats | MeowAssistantView.swift、AIChatsView.swift、AIChatModels.swift | 已有会话持久化、附件、来源、思考摘要、结构化记账卡、撤销 | 流式、停止/超时、消息恢复、图片/文件、Markdown/表格 |
| OAuth | Android Chrome Custom Tabs + PKCE/state | OpenAIOAuth.swift、ASWebAuthenticationSession | 已有 PKCE/state、loopback、Token 刷新和 Keychain 接线 | iOS 27 真机回调、登录地区、真实账号模型目录 |
| AI 记忆/工具/报告任务 | ai_memories、ai_runs、tool registry、report jobs | AIMemory、AIRequestRun/Event、AIReportSchedule 已持久化并纳入 canonical v9 备份；技能/连接器有白名单 | 工具访问和 AI 后台报告仍受 iOS 后台限制，定时报表以本地通知提醒打开 App | 隐私边界、取消/重试/恢复、后台限制 |
| OCR/语音 | Android 截图/通知/语音入口 | Vision + Speech in AIQuickEntryView | 已有 Vision OCR、中文语音听写和支付截图回填 | 相册/麦克风权限、中文识别、真机输入体验 |
| 分享入口 | Android Share Intent | QingJiShare Share Extension + App Group | 已有文本/单图 hand-off，主 App 进入 AI 记一笔 | 微信/支付宝分享菜单、扩展冷启动、图片读取 |
| 快捷指令 | Android 相关入口 | AddTransactionIntent.swift | 已有 App Intent、Siri/快捷指令直接记账 | 不打开 App 入账、账户/分类兜底、权限 |
| Widget | Android 4 类 Widget | QingJiWidget + App Group 快照 | 已实现快记、概览、消费节奏、分类支出四类骨架 | iOS 真机添加、刷新频率、隐私隐藏金额 |
| 通知自动记账 | NotificationListenerService 读取微信/支付宝 | iOS 无公开等价权限 | 不承诺照搬；用分享扩展、OCR、快捷指令替代 | 明确提示用户平台能力差异 |
| 应用内更新 | APK 下载/安装器 | iOS 无法自替换 App 二进制 | 用 TestFlight/App Store/侧载重签；不做假更新入口 | 发布与安装链路单独验收 |

## 截图与对账关闭条件

每个功能域关闭前必须同时有：

1. Android 和 iOS 同一演示数据、同一日期、同一语言的截图；
2. 同一输入的核心结果 JSON 或逐字段断言；
3. 正常、空态、错误/取消和关键操作后状态至少覆盖一组；
4. iOS 原生按钮按压、触觉、动态字体、深色模式和减少动态效果不破坏功能；
5. 截图报告明确记录像素差异，不把原生材质差异判成业务失败。

截图基线由 tools/screenshot_manifest.json 管理；Android 采集入口是
android-app/integration_test/parity_screenshots_test.dart，iOS 采集入口是
.github/workflows/parity-screenshots.yml。当前报告尚未完成，因为 Windows 没有
Xcode、工作树也还没有云端构建结果。

## iOS 27 与交付边界

- iOS 工程最低目标是 iOS 26.0；iOS 27 beta 是向后兼容的运行环境，最终仍要在
  用户的 iPhone Air 真机检查系统 API、Liquid Glass、Widget、照片、麦克风、通知和输入法。
- GitHub Actions 使用官方 macos-26 runner；当前公开镜像主要提供 Xcode 26.x/iOS
  26 SDK，脚本若发现 Xcode 27 会优先选择。工作流不能使用不存在的 xcode-27 runner 标签。
- 免费 Apple Account 的 Personal Team 侧载/真机开发签名通常只有 7 天，且需要
  用户自己在 Xcode/侧载工具中登录账号；未签名 IPA 不能直接安装到 iPhone。
- 最终交付物不是“CI 绿”本身，而是：Xcode 构建产物、成对截图报告、核心测试、
  用户设备安装包、7 天续签说明和明确列出的 iOS 平台差异。
