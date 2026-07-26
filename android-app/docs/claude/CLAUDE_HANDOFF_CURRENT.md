# 肥喵记账 Codex 当前交接文档

更新时间：2026-07-27（P2 施工中断点，见下方 P2 段）
当前 Android 工程：`C:\src\xunni-codex\android-app`  
新会话第一入口：`docs/claude/CLAUDE_START_HERE.md`

> 本文只保留当前有效状态。历史流水看 `CHANGELOG_CODEX.md` 和 git 历史。

## 1. 当前交付状态

### 2026-07-26 审计修复批（v1.204.0+206 / b0726-206 / DB v41）

- **背景**：同日先做了两轮多智能体审查（`docs/代码审查报告-2026-07-26.md` 36 条 + `docs/代码审计报告-2026-07-26.md` 43 条，后者含前者去重后的最终清单）。修复分两段：前一会话修 38 条后中断（留下 2 个失败测试），本会话核查盘点后补齐剩余 5 条并修复失败测试。**43 条全部修复**，明细与逐条状态见审计报告顶部状态块。
- **DB v41**：transactions 新增 `order_no` 列（导入订单号落库，退款支持跨批/跨月挂回历史原单）。v38→v41 迁移等价性测试已同步。
- **本会话补修的 5 条**：①M3 明确标「收入」的导入行只认平台侧退款强信号（分类/类型列或非「转账备注」的商品列），朋友转账「房租退款」不再被错当退款，复核页完成提示文案同步修正；②M7 退款分摊新增「不属于已跟踪物品」出口（审计行哨兵 link_id=0，免迁移），未跟踪部分的退款不再污染物品成本也不再永卡待分配；③M13 支付宝通知加官方交易模板锚点（聊天/生活号消息不再入队）；④M15 从最近任务恢复时跳过 SEND intent 重放（不重复 OCR）；⑤L4 备份导出改流式（逐文件流式校验和 + ZipFileEncoder 流式写盘，`BackupPackageCodec.encodeToFile`，包格式与 decode 兼容不变）。
- **验证**：`flutter analyze` 0 error / 0 warning（仅 2 条既有测试 info）；全量 `flutter test` **802/802** 通过（新增 5 个测试：收入行退款判定、未跟踪分摊 repo/弹层×2、流式备份往返）。
- **✅ 已全部交付（2026-07-26 晚）**：
  - 本地功能提交 `b2dc7a9`（59 文件，含两份审查/审计报告和上会话遗留的 money_normalization_test.dart；ci-artifacts 的 33 个旧 APK 删除状态**刻意未提交**，按规矩别混功能提交）。
  - GitHub 源码快照 `ae5fdb5` 已推到 `origin/codex/feimiao-p0-fixes`（快照=HEAD 树剔除 ci-artifacts/releases 大 APK，parent=远端上一个快照 482aed4；**直推本地分支必失败**，历史里有 31 个 >100MiB 的 APK）。
  - Release APK 已构建并全套核验：aapt=`com.qingji.qingji.codex`/206/1.204.0/肥喵记账；16K zipalign 过；apksigner V2 唯一 Codex 证书（SHA256 `4E99C399...83D507`）。归档 `ci-artifacts/releases/feimiao-codex-v1.204.0-206.apk`，110,666,547 字节，SHA256 `CF261263D66B835F3617D921E5438B189646B5CEEE31C94DC9ED09DF1A561C4F`（比 v198 小 10MB=mascot WebP 压缩的收益）。apksigner 需要 `JAVA_HOME="C:\Program Files\Android\Android Studio\jbr"`。
  - **线上已发布**：`ci/publish_update.sh` 发布成功，releaseId `v206-cf261263d66b`；发布后验证过 version.json（返回 206/哈希一致）+ 全量下载拼接哈希与源 APK 完全一致。
- **⚠️ 用户报应用内更新下载只有 30KB/s——已诊断，待用户拍板方案**：直连探针显示大陆流量被调度到 Cloudflare 阿姆斯特丹节点（CF-RAY AMS），免费版对大陆就这样，晚高峰 30KB/s 正常、波动 10 倍。包本身完好。已告知用户可直接从电脑传 APK 到手机安装。**根治方案候选**：A=发布脚本双写腾讯云 COS/阿里 OSS 国内源+version.json 指向它（推荐，需用户开账号给 key）；B=App 进程内下载器改多线程分段（治标，零外部依赖）；C=优选 IP（custom domain 模式下不可行，已排除）。
- Kotlin 两处小改（MainActivity 分享重放守卫 / PaymentNotificationListener 支付宝模板锚点 ALIPAY_TXN）已随 v206 APK 编译通过；**运行态锚点覆盖面待真机验**：如果用户反馈支付宝某种官方通知没被自动记账抓到，把通知文案要来、往 ALIPAY_TXN 正则加一个模板词即可（宁漏抓不错抓是既定取舍）。

### 2026-07-26/27 资产管理 UI P0 快赢批（✅已完成验收，v1.205.0+207 / b0726-207 / DB 仍 v41）

- 复盘方案：`docs/claude/资产UI优化方案-2026-07-26.md`（P0 快赢 / P1 结构 / P2 重构）。P0 全部落地：术语人话化全扫（口径/证据/锚点/推定等内部词清零、·CNY 全删）、净资产卡重排（34px Nunito 主数字+铜金 ¥）、卡片规格统一（appCardDecoration/appCardDivider/iconCircleFill 三个新全局零件）、物品网格裁切 bug 修复、scheme.error 红清零、_SwitchRow 删除换 SettingsRow+AppSwitch、三表单铺 AppLabeledField、_TypeChip 主色化、空态换猫。明细与验收状态见方案文档 §五点五。
- **验收**：analyze 0 error 0 warning；全量测试 **802/802**；before/after 对比图 7 张 `outputs/asset_ui_review/compare/`。
- **v207 APK 已构建并核验**：aapt=`com.qingji.qingji.codex`/207/1.205.0；16K zipalign 过；V2 唯一 Codex 证书。归档 `ci-artifacts/releases/feimiao-codex-v1.205.0-207.apk`，110,666,579 字节，SHA256 `3528D5DFA9D069B84EBE86111681890A938402E5CEC3249096341C7D3F51EADA`。**未发布线上**（线上仍 v206；用户从电脑直接传包安装，绕开 30KB/s 直连）。本地功能提交 `992ff8c`，远端源码快照 `a63456c`。
### 2026-07-27 P1 结构批（✅已完成验收，v1.206.0+208 / b0727-208 / DB 仍 v41）

- **六项全部落地**：①总览重组：净资产 hero+趋势合并一张卡、「净资产核对」「生成报告」收进 AppBar 右上 ⋯ 菜单、待处理只留保修到期/权益逾期两类任务型、其余五类（账户到账/历史物品/历史权益/外币/缺购买日期）进「数据待完善」弹层、无核对记录时核对空态卡不渲染；②资金页：分组头余额小计（多币种组不显示、守诚实）、¥0 账户收进「已清零账户 (N)」折叠卡、**筛选行删除**+列表底部「已归档 N 项 ›」入口+归档视图返回条、`_FundsKind` 种类筛选彻底删除；③物品页：五层筛选收成 搜索框+一行三颗轻量「文字+⌄」下拉（`_LightFilterDropdown`，非默认值变主色），PhysicalAssetGrid 退成纯展示、搜索/分类状态上提；④详情容器统一：账户/权益详情从半屏弹层改**全屏主题页**（`_AccountDetailPage`/`_ReceivableAssetDetailPage`，AppBackButton+⋯菜单，**修了用户真机 bug：账户详情白底无主题+顶到状态栏**）、物品 ⋯ 菜单分层（一级常用 6 项+「更多操作…」二级收报废/丢失/赠送/撤销类）、IosMenuItem 加 key 字段；⑤新增入口：三个 tab 右上 + 统一开一张「添加」弹层（资金/物品两组），内嵌最近 3 笔候选账单一步直达填写物品表单；⑥生成报告后直接 openReportReader 打开阅读器。
- **用户 2026-07-26/27 拍板的三条视觉修正已全部落地**（别做反）：①渐变背景上的输入框=半透明 AppColors.card+hairline（物品搜索框，代码有注释）②筛选控件不用重胶囊、用轻量「文字+⌄」；资金页直接删筛选行 ③净资产主数字 ¥ 符号与数字同色 onSurface（不用铜金；负数整体超支橙不变）。
- **验收**：analyze 0 error 0 warning（2 条老 info）；全量 `flutter test` **803/803**（asset_management_view_test 多 1 个导航闭环断言用例）；P0→P1 对比图 7 张 `outputs/asset_ui_review/compare_p1/`（P1 原图 `after_p1/`）。
- **v208 APK 已构建并核验**：aapt=`com.qingji.qingji.codex`/208/1.206.0；16K zipalign 过；V2 唯一 Codex 证书。归档 `ci-artifacts/releases/feimiao-codex-v1.206.0-208.apk`，110,666,663 字节，SHA256 `451A56DD4550FCC4E5774ADB9A7E3D2E31A966EA5792F884230D0290A765E13A`。**未发布线上**（线上仍 v206，v207/v208 都等用户点头再发；用户从电脑直接传包安装）。本地功能提交 `39995ee`，远端源码快照 `09aa437`。
- P2（accounts_view 拆模块/性能缓存/情感化）可选排期。动 UI 前必读 UI_DESIGN_STANDARD.md。

### 2026-07-27 资产UI P2 重构批（✅已完成总验收，v1.207.0+209 / b0727-209 / DB 仍 v41）

- **对抗审查处置完毕（2026-07-27 续接会话）**：journal 4 路结果全在。①测试质量维度：零问题 ②物品卡溢出发现：复核**驳回**（real:false，旧版同条件也溢，非本次回归）③**有效发现 1 条已修**：balance_cache_test 没兜住「双保险」失效层——用例⑤补断言「写后当天 computed 快照净资产=写后净资产」，并做了反向验证（临时摘掉 _invalidateTxDerived 里的 _invalidateBalanceDerived → 测试红；恢复 → 绿），回归网确认有效。
- **总验收**：analyze 0 error 0 warning（2 条老 info）；全量 `flutter test` **808/808**（bump 后重跑）。
- **v209 APK 已构建核验归档**：aapt=`com.qingji.qingji.codex`/209/1.207.0；16K zipalign；V2 唯一 Codex 证书。`ci-artifacts/releases/feimiao-codex-v1.207.0-209.apk`，110,666,531 字节，SHA256 `44B235922691F6DB995572B27478EEFEFC0884634AD76DA83F7C4D6681AA74EB`。
- **用户已拍板（2026-07-27）：推送完发布 v209 上线**（发布状态见 §4）。

- **P2 定义**：`资产UI优化方案-2026-07-26.md` §四 三件事：①accounts_view.dart(7333行) 拆模块+四处收口（死代码/图标映射/PickerField/照片选择器）②性能缓存 ③情感化（猫探头/成功猫 toast/趋势渐变）。
- **施工依据材料（全部已归档进仓库，别重新侦察）**：`docs/claude/P2侦察报告-2026-07-27.md`——6 路侦察报告合集（拆分依赖图/PickerField 四套/照片胶水三份/图标差异/性能热点+缓存方案/情感化素材），**附录含施工A工作流脚本原文（拆分改名总表 SPLIT_SPEC + 九段任务书）**。
- **已完成段（每段完成时 analyze 0 error 0 warning + asset_management_view_test 全过）**：
  - ✅ S1 全局标准件 `lib/widgets/app_picker_field.dart`（AppPickerField/AppReadOnlyField/showPickerMenu），4 套重复实现全收口：accounts_view `_IosPickerField`、recurring_view `_PickerField`（含 409-443 内联起始日期块、账户/账本菜单升级 selected: 写法）、physical_asset_purchase_sheet `_PickerField`（InkWell→PressableScale、chevron_right→下箭头）、refund_settlement_sheet `_SettlementPickerField`。**以后「点击弹菜单选值」字段一律用 AppPickerField，别再手搓。**
  - ✅ S2 图标合一+死代码：删 `_PhysicalAssetGroupCard`+`_PhysicalAssetTile`（171 行死代码）；删私有 `_assetIcon`，统一用 physical_asset_grid.dart 公开 `assetTypeIcon`；**已拍板取值（用户未过目，可推翻）**：digital=devices_other_outlined（线框系统一）、appliance=kitchen_outlined（维持）。
  - ✅ S3 照片胶水合一：新 `lib/views/assets/asset_media_picker.dart`（sharedAssetMediaStore/pickAssetPhoto，统一 replaceFile 原子换图），三处胶水改接。**发票路线（_pickInvoice/绕开 AssetMediaStore）刻意不动**，动磁盘布局风险大。
  - ✅ S4 表单基件簇 → `lib/views/assets/asset_form_kit.dart`（418 行：AssetEnumDropdown/AssetAccountDropdown/AssetCategoryDropdown/AssetNullableDateField/AssetHintBox/AssetDetailSection/AssetDetailRow/AssetActionButton/AssetMenuFilterButton + parseAssetDecimalInput/assetDateText/digitAwareAmountSpan 等公开助手）。
  - ✅ S7 权益簇 → `receivable_detail_page.dart`(476行) + `receivable_sheets.dart`(507行)。
  - ✅ S8 物品簇 → `physical_asset_detail_page.dart`(1147行) + `physical_asset_sheets.dart`(1014行) + `physical_asset_form_sheet.dart`(664行)。⚠️ 发现待决策项：私有 `_physicalAssetStatusLabel`（在 detail_page）与 physical_asset_grid.dart 公开 `physicalAssetStatusLabel` **不等价**（usageStatus.unknown 时前者「持有中」后者「待确认」），按规矩保留两套未合并，合一留后续拍板。
  - ✅ S9 收尾 → `asset_add_entry_sheet.dart`(200行，AssetAddEntrySheet)；accounts_view 无 unused import、旧私有名零残留。**终检：accounts_view.dart 2733 行（原 7333）；analyze 0 error 0 warning；8 个资产测试文件 81 用例全过。**
- **✅ 断点已落盘**：施工A 全部成果（上述代码+本文档+侦察报告）已 WIP commit `e0ec79d`，远端源码快照 `bc8095a` 已推 origin/codex/feimiao-p0-fixes（parent=39371b1，不含发布产物）。树在提交时点=编译绿+资产测试绿。下次推快照 parent 用 `bc8095a`。
- **✅ 施工B（2026-07-27 本会话，工作流 4 段全绿，每段 analyze 0 error 0 warning + 资产测试全过）**：
  1. **S5 总览+资金簇**：新 `asset_overview_cards.dart`(451行：AssetEmptyState/AssetPendingItem/AssetPendingCard/VerifiedNetWorthCard/AssetSummaryCard/AssetAnalysisCard 公开+3 私有) + `funds_tab_cards.dart`(337行：FundsAccountBalance/FundsAccountGroup(Card)/FundsAccountBalanceTile/ZeroBalanceAccountsCard/FundsArchive* 全公开)。
  2. **S6 账户簇**：新 `account_detail_page.dart`(624行：AccountDetailPage 公开+校准弹层/趋势卡/CheckpointRow 私有) + `account_form_sheet.dart`(500行：AccountFormSheet 公开+TypePicker/TypeChip 私有)。**accounts_view.dart 最终 898 行**（原 7333；S1-S9 全部完成）。转公开的 Widget 构造补了 super.key（lint 硬要求，与既拆文件做法一致），其余逐字搬运。
  3. **性能缓存（app_repository.dart）**：①全局 `_revision`（override notifyListeners 自增，121 处调用点零改动接入）②accountBalanceResultOf per-account memo、currentNetWorthResult/Breakdown 整结果 memo、accountBalanceTrend 按(accountId,days) memo——全部带 (revision, 当天yyyymmdd) 维度，historical/自定义 asOf 路径零缓存 ③`_txById` 惰性索引（transactionById/physicalAssetAdditionalCost 线性查 O(L×T)→O(L)）④双保险失效 `_invalidateBalanceDerived()`：挂 _invalidateTxDerived + 8 个 _loadXxx 重载漏斗（防 notify 前内部读脏，如 _persistCurrentNetWorthSnapshot）⑤该函数里原 super.notifyListeners() 改 notifyListeners()（保 revision 不变量）⑥@visibleForTesting balanceRecomputeCount/netWorthRecomputeCount/trendRecomputeCount ⑦physical_asset_grid 物品卡 watch→read（外层 Consumer 已重建，卡内 watch 冗余）⑧新 `test/balance_cache_test.dart` 5 用例（命中/交易失效/校准失效/账户编辑失效/净资产+趋势）。效果：资产页 build 从 3×账户数次全量重放降到同数据版本只算一次；账户详情趋势 ~91 次/帧→1 次。
  4. **情感化三件**：①净资产合并卡探头猫（accounts_view _buildOverview：Stack Clip.none+Positioned top-8/right-4+MascotBreath(bob:2,sway:0,centerRight)+idle.webp 高80、overview ListView 顶 padding 4→12 防裁）②showAppToast 加可选 `MascotMood? mascot`（Mascot size22 自带回退，胶囊 vertical padding 8→6），三处接成功猫：净资产核对完成/余额已核对/**权益收回 _save 补 toast「权益已收回」**（原来无任何提示，pop 前调用走 rootOverlay 存活）③两个趋势 painter（net_worth_trend_card + account_detail_page）per-segment 渐变填充 ui.Gradient.linear lineColor withValues 0.18→0，断点不连片，网格后描线前。
- **✅ 用户真机反馈两条已修（2026-07-27，等 v209 一起交付）**：
  1. **编辑物品键盘 bug（用户截图：键盘弹起后大片空白+表头顶进状态栏）**：根因=「双重键盘垫层」——showBlurSheet 路由层已有 AnimatedPadding 避让键盘，弹层内部又垫了一层 `Padding(bottom: viewInsetsOf)`，两层叠加把可视区压没。**12 处 showBlurSheet 弹层统一删内层垫层**（物品表单/权益表单/收回/物品估值·出售·凭证·折旧·复核·结束持有/退款分摊/成本关联/账户表单/余额校准）。⚠️ book_sheet 走 appSheet(showModalBottomSheet) 路由**不会**自动避让，其内层垫层是正确的，刻意保留——以后判断这类问题先看弹层走哪条路由。
  2. **物品卡空隙（用户截图红框：副标题和日均之间大空白）**：根因=竖卡文字区固定 6/11 高度+Spacer，名称一行时富余全成空白。改「照片 Expanded 吃掉富余高度+文字块贴底自适应」（physical_asset_grid.dart），照片更大、空隙消失、名称两行时照片自动让位天生防溢出。测试适配：asset_management_view_test 一处 tap 卡片前补 scrollLastGridTo（文字贴底后在 800×600 测试视口落到折叠线下，非弱化）。
- **✅ 已验收部分（2026-07-27 施工B会话）**：
  - **全量 flutter test：808/808 全过**（803 基线 + 5 新缓存用例），exit 0。
  - **渲染图已出**：after `outputs/asset_ui_review/after_p2/`（7 张，含 p2_07=编辑物品+FakeViewPadding 伪键盘的修复证据图）；对比图 `outputs/asset_ui_review/compare_p2/`（5 张，P1 vs P2），已发用户过目（尚未回复拍板）。渲染脚本临时拷进 test/ 跑完已删，原件在施工B会话 scratchpad `tmp_asset_ui_p2_render_test.dart`（丢了就照 after_p1 那版改：输出目录/p2_07 那段 FakeViewPadding(bottom:600)）。
  - 对抗审查工作流（拆分等价/缓存正确性/UI铁律/测试质量 4 维+逐条复核）**发起但用户额度耗尽时未跑完**：4 路中 1 路（test 维度）已回报**零问题**。journal：`~/.claude/projects/C--src-xunni-codex/a86b7f00-6c65-4beb-8553-07d51f8bce67/subagents/workflows/wf_d4379b23-5d5/journal.jsonl`（每路一条 result）。接手时若 journal 已有 4 条 result 就直接看结论；没有就重发一轮审查（或人工抽查缓存失效点+拆分引用即可，全量测试已绿兜底）。
- ~~剩余清单~~ **已全部完成（2026-07-27 续接会话）**：审查处置✅ bump 1.207.0+209✅ APK 构建核验归档✅ 文档终稿✅；commit+快照+发布状态见本节顶部和 §4。
- **⚠️ 断点落盘（额度告急时做的保底）**：施工B 全部成果（S5/S6/性能/情感化/两条bug修复/本文档/渲染对比图）本地 WIP commit **749df31**；源码快照 **5c97564** 已推 origin/codex/feimiao-p0-fixes（parent=40ebb59，不含发布产物）。**下次推快照前先 `git ls-remote origin codex/feimiao-p0-fixes` 拿远端 tip 当 parent**（这次就是拿手册里的旧 parent bc8095a 被拒了一回）。**33 个旧 APK 删除状态（D）刻意未提交**；⚠️ `android-app/outputs/` 里躺着一个未跟踪的 110MB 旧 APK（feimiao-codex-v1.203.0-205.apk），`git add android-app` 会把它扫进来，提交前记得排除。版本号未 bump（仍 1.206.0+208 / b0727-208），DB 仍 v41，线上仍 v206。

### 2026-07-18 当前启动体验修复（工作区未提交）

- 最新本地验证 APK：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.202.0-204.apk`
- 版本：`1.202.0+204`；build tag：`b0718-204`；DB：v40。
- 启动第一原则：**主页第一屏必须带真实当月数据，不允许先画空主页再掉入账单**。首屏前只读账本/当前账本、账户、分类、预算、显示偏好和当月已持久化账单；全历史、资产、报告、定时物化、净资产、备份和旧退款归并在首帧后收敛。
- 完整 hydration 前，记账、Widget deep link 和冷启动分享会排队；失败时 Widget/自动记账/报告不会读半快照。主题异步读取，抽屉首次打开才构建。
- Android 12+ 启动主题显式使用 `@drawable/splash_transparent`，并将 splash icon background 设为透明，避免系统回退使用桌面图标。
- 验证：启动/SQLite 专项 5/5、最终全量 Flutter 测试 **752/752**、`flutter analyze` 0 issue；发布逻辑 9/9，aapt、16 KiB zipalign、固定证书 APK V2 签名通过。APK 120,826,320 字节，SHA256：`3C178D9A6EE37DE806B281BD031058AD60A355E690844099534BAC421C566CC3`。
- 运行态边界：本轮无可用 Android 设备，未做安装/真机冷启动截图；需用户安装后复验本月数据是否首屏即在。未 commit、未 push、未发布线上。

- 历史已发布基线 APK（非本轮）：`C:\src\xunni-codex\ci-artifacts\releases\feimiao-codex-v1.196.0-198.apk`
- 历史基线版本：`1.196.0+198`
- build tag：`b0714-198`
- 当前开发工作区分支：`codex/feimiao-p0-fixes`；本地功能提交 `1301e44`。因历史含 31 个超过 GitHub 100 MiB 限制的 APK，未改写本地历史，改用无发布产物的源码快照 `6703f8e`（父提交 `61c0c06`）推到 `origin/codex/feimiao-p0-fixes`；当前线上为 v198（releaseId `v198-69ae3ccda9ad`）
- SHA256：`69AE3CCDA9ADE11D470E444E519CEC01483F701B495199A11EE0C744C1EC9A7E`
- 包名：`com.qingji.qingji.codex`
- 应用名：`肥喵记账`
- 签名：`CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN`
- v198 已包含旧账时间降噪与 DB v40 时间精度地基；707/707、analyze 0 issue、aapt/16K/V2 签名/哈希均通过，已 commit、push 并发布，运行态待用户安装验收。

## 2. 历史修复摘要（1.196.0+198，本轮启动修复见上方）

### 1.196.0+198 本轮

- **旧账时间降噪（DB v40）**：交易新增 `time_precision` 四态。存量账只标记 `legacy_unknown`，不改写 `date_ms`，不拿创建或更新时间伪造消费时分；日期分组卡隐藏不可靠午夜，独立卡只保留日期，来源明确的真实午夜仍显示 `00:00`。
- **入口与兼容链**：主页、搜索、账单、报销、喵助手普通卡/退款卡、手动/快捷/AI/通知、定时、普通导入、肥喵 CSV、退款报销和资产流水统一携带或继承精度。旧聊天 JSON/CSV 缺字段回退未知；CSV 为兼容旧格式继续输出固定 `yyyy-MM-dd HH:mm` 日期字段，并通过时间精度列避免把未知 `00:00` 解释成明确时分。
- **建议证据**：`TransactionRecord` 与智能建议引擎消费真实精度；`exact` 使用完整时段证据，`entryClock` 降权，`dateOnly/legacyUnknown` 不参与时段评分，但星期和周期证据仍可独立生效。
- **验证 / 产物**：定向 192/192、最终全量 707/707；full analyze 0 issue，格式与 diff check 通过。`1.196.0+198` / `b0714-198` / DB v40；Release APK 120,641,920 字节，SHA256 `69AE3CCDA9ADE11D470E444E519CEC01483F701B495199A11EE0C744C1EC9A7E`。aapt、16K ZIP 对齐、唯一 Codex V2 签名和源/归档/sidecar 哈希一致。无连接设备，未做安装/冷启动；本地提交 `1301e44`、远端源码快照 `6703f8e`、Cloudflare releaseId `v198-69ae3ccda9ad`，公网与 KV 逐分片验证通过。

### 1.195.0+197 本轮

- **时间语义**：AI 纯日期继承提交时分，明确时分原样保留；本地解析、手动、快捷和两个编辑入口不再把时分归零。导入/自动/定时入口保持来源语义。旧库 `00:00` 无可靠证据时不批量伪造，所以下次不能把“改显示文案”误当成历史时间修复。
- **建议语义**：旧逻辑按一级分类聚合全历史、取分类金额中位数、随机选最多两条后再随机查账补满四条，且旧午夜时间会破坏时段权重，现已全部删除。新 `SmartSuggestionEngine` 使用近 180 天“叶子分类 + 规范化备注/商户”签名，按跨日频次、近期、真实时段、星期与周期评分；金额不稳定时不带金额，证据不足允许不显示。查账建议只由真实预算和当前账本数据触发，缓存按内容指纹失效。
- **主页猫**：按 PNG alpha 边界把右侧盒子 bleed 调为 4dp，可见轮廓与卡片边线约重叠 2.2dp；320px 明暗主题测试保证不越屏。
- **验证 / 产物**：增量 49/49、失败边界复验 27/27、版本同步后最终全量 691/691；full analyze 0 issue，本批格式与 diff check 通过。`1.195.0+197` / `b0714-197` / DB v39；Release APK 120,641,920 字节，SHA256 `836E22D684F77CD8E4446227F0E8CEE54CD5DFD75D1BD07901CAEB58A65B3AB6`。aapt、16K ZIP 对齐、唯一 Codex V2 签名和源/归档/sidecar 哈希一致。无连接设备，未做安装/冷启动；未 commit、push 或发布。

### 1.194.0+196 本轮

- **预算进度与主页间距**：恢复低饱和预算健康绿 `#7FB069`，共享横条/圆环统一健康绿→临界铜金→超支橙；未完成轨道跟随进度末端色并带略深边缘。主页汇总卡按真实内容高度布局，筛选条上下均为 8dp。
- **账单与聊天显示**：新增全局内容优先（默认）/分类优先偏好及真实卡片预览；日期分组卡只显示时分，独立卡显示完整日期时分、账本和次信息。用户消息气泡默认跟随卡片透明度，可切固定灰底，偏好持久化且旧值安全回退。
- **喵助手稳定性**：历史区同步定位完成后才显示，消除进入闪动；恢复负责人被快速关闭时，新面板会接管重试，不再偶发空历史。
- **手动记账与分类**：备注请求系统 `done` 并复用正常完成保存链，无效金额保持焦点，成功保存锁住退出前数字键盘。共享分级分类器统一手动、定时、喵助手和导入复核的一级原位展开二级行为。
- **验证 / 产物**：analyze 0 issue；全量测试 664/664；release build 成功。aapt=`com.qingji.qingji.codex` / 196 / 1.194.0 / 肥喵记账；16K ZIP 对齐、唯一 Codex V2 签名和源/归档哈希通过。APK 120,609,152 字节，SHA256 `BFA815FB8A04CE89BE560B8D29B940DCD457100C7378B60ED324468B84AB0BCD`。
- **边界 / 下一步**：用户自行安装验收，不做模拟器、真机安装或截图。v196 未 commit、未 push、未发布，当前线上仍为 v195；DB 保持 v39。

### 1.193.0+195 上一版（当前线上基线）

- **日期仓储不变量**：新购买必须显式传入购买日期；物品、购买支出、结算、创建事件和初始估值统一该日，缺日期时原子拒绝。账单来源物品始终以原交易日为 canonical date，普通编辑不能漂移或清空。
- **折旧与保修边界**：启用折旧必须显式传 `startAt`，不再静默回退今天。保修日期按自然日比较，创建与编辑均不得早于购买日；原账单含具体时分时，同一天仍合法。
- **UI 继承**：完整包含 v194 的资产 UI 重构、三条新增路径、照片优先详情页、历史日期补录、受管照片/凭证及标准控件铺开；v194 保留为升级前回退包。
- **验证 / 产物**：analyze 0 issue；资产专项 38/38、全量测试 645/645；release build 成功。aapt=`com.qingji.qingji.codex` / 195 / 1.193.0 / 肥喵记账；16K ZIP 对齐、唯一 Codex V2 签名和源/发布副本哈希通过。APK 120,592,516 字节，SHA256 `3C502EB61F4E372A1EB1787CC0E418AB19AAFD9EAAA7A4963CEB57E694F3BF4E`。
- **边界 / 下一步**：不做模拟器、真机安装或截图，由用户自行安装验收。**v195 已由 Claude 提交(`bf50e97`)并发布上线**（releaseId `v195-3c502eb61f4e`）；v194 与 v193 APK/sidecar 保留为回退基线。A3b verified-checkpoint 纠错与 A5 负债单一真相源仍按原队列，未在本批混入。

### 1.192.0+194 上一轮（本地回退包）

- **日期与成本纠错**：手工物品可填写、补充或清空历史购买日；新购买让物品、支出、事件和估值共用同一日期；账单来源强制继承原账单日期。新增 `manual_unknown`，未知购置成本不再用当前估值伪装，日均和保值率降级为待补充。DB 保持 v39。
- **资产 UI 重构**：物品详情改普通二级页，首屏展示照片、日均、持有天数和估值；生命周期操作收进右上菜单。新增/编辑表单使用全套标准件，补齐在用/闲置、照片、购买日、保修和净资产选项；新增入口拆成账单加入、新购买记账、历史补录三条路径。
- **列表与凭证**：物品网格以日均为主指标、估值为辅助，unknown 显示待确认并统一圆角/按压/读屏；估值与折旧可选真实日期。发票/保修单改文件选择并复制到 `asset_media/`，照片可替换或移除，不再手输路径。
- **验证 / 产物**：analyze 0 issue；资产定向 65/65、全量测试 641/641；release build 成功。aapt=`com.qingji.qingji.codex` / 194 / 1.192.0 / 肥喵记账；16K ZIP 对齐、唯一 Codex V2 签名和源/发布副本哈希通过。APK 120,592,516 字节，SHA256 `C0208E5270788EE1A60F278354D29E6ACFE90D39425231535BCE79F34D36E845`。
- **边界 / 下一步**：不做模拟器、真机安装或截图，由用户自行安装验收；v194 未上传、未提交，当前线上仍为 v185。v193 APK/sidecar 保留为升级前回退基线。A3b verified-checkpoint 纠错与 A5 负债单一真相源仍按原队列，未在本批混入。

### 1.191.0+193 上一轮（本地回退包）

- **B3 专项追踪（DB v39）**：分类/标签范围按 OR 匹配，消费按原单退款家族净额计算；重叠专项彼此独立，不进入主预算或今日可用。新增创建、编辑、管理和归档；编辑归档旧计划并创建活动 successor，knowledge cutoff 仍可恢复历史范围和额度。
- **B3 引用安全**：专项历史引用的分类/标签禁止删除；分类合并同步重写 `expense_scope_json` 并重载。归档不改写历史 revision 或执行结果。
- **A4 物品增强**：补齐到期提醒、追加持有成本、使用次数与快捷 `+1`、存钱目标关联、报废/丢失/赠送撤销。关联金额统一使用退款家族当前净额；使用撤销事务化且唯一，终态撤销要求完整前态证据并绑定当前尚未撤销的事件。
- **JSON / v39 兼容**：资产 JSON v6 用存钱目标 UUID 解析并报告 unresolved/rejected；非法或重复 usage reversal 跳过且不回滚整批。早期 v39 中间态在启动/恢复路径事务化自修复，修复前保留不覆盖的 `pre-v39-compat` 备份；partial usage 表可补列/重建，非法/重复 reversal 清理后建立正确唯一索引。
- **验证 / 产物**：analyze 0 issue；B3/A4 扩展回归 79/79、共享仓储 111/111、最终全量测试 635/635；release build 成功。aapt=`com.qingji.qingji.codex` / 193 / 1.191.0 / 肥喵记账；16K ZIP 对齐、唯一 Codex V2 签名和源/发布副本哈希全部通过。APK 120,428,384 字节，SHA256 `3A2345620F91524CC83A644F8BCFF76B8BBC186DA981B1DAE6CEA41FFF1D6F16`。
- **边界 / 下一步**：用户不做模拟器、真机安装或截图验收，自行安装确认。当前线上仍为 v185，v193 尚未上传；v192 APK/sidecar 保留为升级前回退基线。A3b verified-checkpoint 纠错（superseding/revoked）与 A5 负债单一真相源仍未完成，继续独立排期。

### 1.190.0+192 上一轮（本地回退包）

- **A3 余额校准（DB v37）**：账户新增 UUID、期初日期/质量和归档状态；绝对 checkpoint 支持创建、撤销和同日稳定顺序。锚点前补录被吸收，锚点后流水继续累计；unknown-date 转账按账户双腿覆盖，账户归档只影响可见性。
- **A3 可信核对**：账户趋势只从可信起点开始；完整净资产 checkpoint 冻结 header/items，覆盖不足标 partial，过期物品估值需显式接受，后续数据变化不静默改写旧核对证据。
- **B2 预算计划（DB v38）**：新增 plan/revision、cycle override、月度锚点、周计划、固定模板/occurrence 和 change event。修改默认下周期生效，本周期 override 保存绝对总额；V2 切换后 legacy 预算仅作历史证据。
- **B2 固定承诺**：每周期 occurrence 可匹配、跳过、重置和退款复核；actual/reserve 互斥，部分退款继续预留差额，全额退款不错误释放额度。revision 重复保存与备份恢复会同步/物化 occurrence，未来浏览不混入今日指标。
- **审查补丁**：修复 latest partial 核对比较、过期估值确认、unknown 转账双腿、revision 二次编辑、override knowledge cutoff、退款撤销复核、恢复后物化和真实 `v36→v38` 迁移；320dp/大字号布局边界已纳入回归。
- **验证 / 产物**：analyze 0 issue；最终全量测试 587/587；release build 成功。aapt=`com.qingji.qingji.codex` / 192 / 1.190.0 / 肥喵记账；16K zipalign、唯一 Codex V2 签名和源/发布副本哈希全部通过。APK 119,756,044 字节，SHA256 `363A58B13DBAA732495D9C8BE7A247597ED3F6B84EFD08D361BC821499362B45`。
- **边界 / 下一步**：用户不做模拟器/截图验收，自行安装确认。当前线上仍为 v185；B3/A4 已在 v193 完成，v192 保留为升级前回退基线。

### 1.189.0+191 本轮

- **A1 物品闭环（DB v35）**：从已有账单创建物品不重复生成支出；支持一账多物整数分配、单物退款自动分配、多物退款待确认/人工分配、退货保护、解除关联审计反转与手工成本固化。物品页新增受管照片/缩略图、双列网格、搜索和筛选；窄屏/大字号降单列。出售只把扣除费用后的净到账投影到账户。
- **完整备份 v2**：SQLite、`receipts/`、`asset_media/` 同包；逐文件 SHA256、集合全等和路径穿越校验，v1 兼容。DB/收据/媒体独立切换回滚；失败 staging/临时目录清理，成功后的旧文件清理不再触发破坏性回滚。
- **A2 账户活动/趋势（DB v36）**：账户详情显示真实结算事件近期活动；资产总览显示可信净资产估算趋势。旧快照为 legacy_unverified，历史日期不伪造；scopeVersion 持久化并在计入政策变化时断代，snapshot_date 为 civil day 真相。
- **审查补丁**：定时记账即时生成、肥喵导入、删账本后刷新当天快照；记账账户只接受 CNY，legacy 外币仅保留查看；账单分配来源购买价统一为 resolver 净购置成本；320dp/130% 字号长金额无溢出且读屏完整。
- **验证 / 产物**：analyze 0 issue；定向 112/112；最终全量测试 540/540；release build 成功。aapt=`com.qingji.qingji.codex` / 191 / 1.189.0 / 肥喵记账；16K zipalign、唯一 Codex V2 签名和源/发布副本哈希全部通过。APK 118,920,116 字节，SHA256 `BB320F5F6FA725E41853F0D07722A4FA5498FEEC9C75FF25416482EAF3BE2556`。
- **边界 / 下一步**：用户不做模拟器/截图验收，自行安装确认。当前线上仍为 v185，v191 尚未上传。下一组按 V2.1 分期继续，仍保持每两阶段一包。

### 1.188.0+190 本轮

- **A0 资产信任地基（DB v33）**：物品/权益拆分经济状态、使用状态、可见性和计入口径质量；旧归档数据按事件、收回台账和金额矩阵等价迁移，归档/恢复只改变列表可见性。资产页改“总览 / 资金 / 物品”全局三视图，移除本月收支伪指标，新增持有天数、日均持有花费、保值率、估值记录和报废/丢失/赠送闭环。
- **D0 真实结算地基（DB v34）**：交易新增 `created_ms / settled_ms / settlement_quality / settlement_account_id / settlement_account_quality / event_type`；归属日继续服务消费/预算，真实到账服务现金流/余额。旧普通账单为 legacy_assumed，旧退款/报销未知证据不伪造。
- **账户逐事件投影**：退款、报销、转账双腿、资产出售和权益收回按真实结算账户投影；unknown 账户不回退原账户。账户列表/详情与净资产明确标示待确认、历史推定和“按已知金额”，旧退款/报销可补确认到账信息。
- **四入口退款/报销**：手工账单、喵助手、AI 快捷记账、待报销统一使用结算确认弹层；普通编辑不覆盖结算证据，周期记账不再误标 exact。肥喵 CSV 往返双日期与质量；旧报销兼容恢复为 reimbursement。无法匹配/超额退款不造普通收入，通知退款不按收入保存且不会在混合批被误清。
- **验证 / 产物**：analyze 0 issue；最终全量测试 491/491；release build 成功。aapt=`com.qingji.qingji.codex` / 190 / 1.188.0 / 肥喵记账；16K zipalign、唯一 Codex V2 签名和源/发布副本哈希全部通过。APK 115,069,684 字节，SHA256 `EEA6A350085C9499996D4A43C6B9FC4DEF431ED56172D42FCCB5E1CB09544998`。
- **边界**：用户不做模拟器/截图验收，自行安装确认。当前线上仍为 v185，v190 尚未上传；A1/A2 已在 v191 完成。

### 1.187.0+189 上一轮

- **C0 统计口径地基**：新增统一 `MetricQuery / MetricResult` 合同、整数分消费投影和等长同期窗口；退款归原消费期，普通收支与预算分类独立，外币排除返回 partial，未知/冲突不再伪装为 0。
- **B0 预算单一 resolver**：`BudgetWindowResolver` 继续读取旧 `budget_periods`，兼容自然月循环预算、一次性 winner、逐日整数分分配、历史 knowledge cutoff 和无预算/0 元/partial/conflict 独立状态。正常历史浏览使用当前知识截点，冻结回放才显式传旧 cutoff。DB 仍为 v32。
- **B1 预算执行页**：预算页改为“本周期 / 月 / 周 / 自定义”页内分段浏览，支持日期导航和独立账本范围；主卡、分类执行和“按预算平均”日均参考全部读取 resolver。一次性旧期间与自定义浏览明确分开。
- **消费者统一**：主页、快速记账、喵洞察、统计、月报、Widget、AI 查账和 AI 报告都转接同一预算结果。发布审查修复历史预算窗口混入当前周期“今日可用”的错期问题，并新增回归测试。
- **产品边界**：B1 不显示固定支出预留、“安全可花”或“可自由安排”；这些能力等 B2 的 revision/fixed occurrence 数据地基完成后再开启。
- **验证 / 产物**：analyze 0 issue；C0/B0/B1 定向 70/70，AI 错期与预算页复验 18/18，最终全量测试 445/445；release build、aapt、16K zipalign、单一 Codex V2 签名、源与发布副本哈希全部通过。APK 114,904,780 字节，SHA256 `02FD3E3AD0942EC2024F3A987890E557B3675AA44F0AF5B2F58C6B62FB249A34`。
- **边界**：用户明确不做模拟器/真机截图验收，由用户自行安装确认。当前线上仍为 v185，v189 尚未上传；v188 被本包取代。下一步继续 A0 资产状态地基与 D0 双日期/账户移动。

### 1.186.0+188 上一轮（已被 v189 取代）

- **AI 退款闭环**：新增本地 `RefundMatcher`，喵助手和快速 AI 入口只有在历史原支出唯一强匹配且金额合法时才写附着式退款；缺金额、无匹配、歧义、超额全部追问，查询不误判。退款金额先去掉日期再解析，避免“7月3日”被当成 3 元。仓库边界事务内再次校验剩余金额并返回退款行 ID；聊天退款卡用 `role=refund` 持久化、重启可恢复。
- **自动记账 / AI 设置**：自动记账接入主题背景，状态改标准设置行，编号长文精简为 secondary/caption；AI 设置去掉重复“AI”和四条冗余入口说明，标题降为标准 w500，账号/高级参数 6 个输入框统一 `AppLabeledField + iosInputDecoration`，说明左对齐并降灰。
- **预算 / 资产方案 V2.1 与全 App 统计合同（仅文档，未改结构代码/DB）**：V2 竞品研究稿保留；当前锁定方案为 `docs/claude/BUDGET_ASSET_UX_PLAN_V2_1_2026-07-12.md`。跨页面最高口径合同 `docs/claude/STATISTICS_CALCULATION_STANDARD.md` 已升到文档 v1.1、`calculationVersion` 仍为 1：按财务真值 `F-*`、派生分析 `D-*`、运营计数 `O-*` 全量登记主页、账单/搜索/报销、预算、统计、Widget、月报/AI、账户资产、存钱目标、导入导出、自动/定时记账、分类/标签/记忆/备份，并用 `current_exact/partial/inconsistent/target_only` 区分线上现状与 V2.1 目标。新增 60-77 号反例，点名跨币种、未来交易、笔数、同期、Widget、资产 scope 和运营计数冲突。实施顺序先 C0 口径门禁，再 B0/A0；Obsidian 镜像必须与仓库规范逐字一致。
- **抽屉对比图**：`outputs/drawer_before_after_v188.png` 由用户原始真机图和当前生产 RootShell/AppTheme 的真实右滑渲染合成，真实加载 logo、封面、中文和 Material 图标；尺寸 1664x1848，SHA256 `B34E7DF815EE7D4287B5FE5934232806B09BC84C63D7619B87567908DAA44555`。
- **验证 / 产物**：analyze 0 issue；定向 111/111；最终全量测试 374/374；release build、aapt、16K zipalign、Codex V2 签名、源与发布副本哈希全部通过。APK 114,626,156 字节，SHA256 `0A0282847451BE7650E4C3C89CE56ED4D306FF3AC0B6C13613462814E93C1FF7`。
- **边界**：DB 仍为 v32；用户明确不做模拟器/真机截图验收，App 内运行态由用户安装确认。当前线上仍为 v185，v188 尚未上传；v187 被本包取代。

### 1.185.0+187 本轮

- **主页/抽屉**：探头猫右边缘锚定、取消横摆旋转，只保留轻纵向呼吸；“今日可用”下移 8px。抽屉导航统一 `AppLineIcon` 的 Lucide 线性风格，设置/新建账本换 gear/square-pen，“更多”移除右箭头，主页增加朝抽屉侧的定向阴影和发丝边界。
- **主题/备份**：简约白预算横条与圆环底轨改中性灰；6 色卡在 320dp 单行；滑杆改 `CupertinoSlider` 并按色卡给可见控制色；删除极简模式的新 UI/写入，旧配置继续兼容白色外观。备份主列表只展示最新 3 份，迁移/升级保护备份不删除。预算页仅把新增按钮移到右上角。
- **表单/导入导出**：新增 `AppLabeledField`；`SheetHeader` 统一等距边界，`SettingsGroup` 自定义行撑满。分类图标样式、公共分类选择器、定时记账分类弹层统一标准头部；存钱目标改半屏多字段表单；导入导出按钮、说明层级和文案收口，导出范围可滚动且自定义日期不再裁切。
- **喵助手**：全屏背景跟随主题；改分类/删除及卡外说明降为标准灰阶；回答操作栏收口 Claude 细线样式和稳定热区。IME 期间保持组件树不变，通过 `BackdropFilter.enabled=false` 暂停大面积/输入框模糊，位置直接跟随系统 inset；AI 焦点 10/10 回归全过。
- **明确不进本版的六项**：AI 退款附着原单、自动记账页面、AI 设置页面、预算展示深度方案、资产管理全流程方案、抽屉前后对比图。未接通的退款底层草稿已从本版剔除。
- **验证/产物**：analyze 0 issue；全量测试 364/364；release build 成功；aapt/zipalign/Codex V2 签名/源与发布副本哈希均通过。APK 114,462,292 字节，SHA256 `8041C21299EFC1CA618ADC005D6272794BE90C6CEE77D74C0E54DCFC9699AE8E`。
- **运行态边界**：用户明确取消模拟器截图，将自行安装验收；真机视觉、触控和输入法流畅度仍待用户确认。当前线上为 v185，v186 被本包取代，不再单独发布；v187 未上传。

### 1.184.0+186 本轮

- **主页卡片真根因**：真机截图中背景约 `#F4E2BA`、Material Card 中心约 `#CBC0AC`；40% 白色不可能把背景压暗，且无 elevation 的玻璃控件显示正常，确认是半透明 Card 与 physical elevation/阴影在小米 GPU 上的合成污染，不是 `surfaceTint` 或主题色值本身。
- **修复**：主页大卡片和账单日卡改为 `GlassSurface(blur: 0)`，保留动态白色卡底、渐变发丝边和账单交互；预算横条/圆环底轨改半透明白。参数：浅色卡片默认 40% 不透明度且跟随滑杆，预算底轨浅色 56%、深色 14%。
- **验证与产物**：像素断言要求卡片 RGB 必须比暖色背景更亮，且结构断言禁止主页退回 elevated Material Card；analyze 0、相关测试 10/10、全量测试 352/352。release APK 已构建并通过 aapt、Codex V2 签名与复制件哈希核验；114,446,116 字节，SHA256 `C91C69ECE23E5E02CAE482B50D837286621785143B289C0F18C475172331D535`。
- **交付边界**：v186 未上传且已被 v187 取代，对应修复完整包含在 v187；当时没有虚拟机安装截图。

### 上一版 1.183.0+185（已上线）

- **常规账单写入去全表重载**：新增受影响 ID/退款家族的增量回读；新增、编辑、改分类、退款和删除不再执行全表 JOIN。切换账本和总账本开关直接复用全局内存行；批量导入仍只在整批提交后做一次有意的全量刷新。
- **大文件导入降主线程压力**：CSV/XLSX 表格解析、肥喵格式识别、日期金额转换和第三方账单标准化移入 `Isolate.run`；XLSX 通过 `TransferableTypedData` 跨 isolate，FilePicker 不再先把整份文件复制进平台结果。
- **Widget PNG 压缩移入后台 isolate**：Flutter 布局/绘制因引擎限制保留在根 isolate，RGBA→PNG 编码改用 `image` 在后台完成；两张卡拆帧、同一轮快照只构建一次，减少记账后的连续 UI 占用。
- **报告支持进程被杀后继续**：Android WorkManager 以唯一 job 调度，联网约束+指数重试；API Key 从旧原生安全通道迁移到可供 headless engine 使用的 Flutter Secure Storage；报告正文、聊天卡和 job 完成状态原子提交且可幂等重试，完成后发本地通知。面板轮询持久 job，切回仍显示阶段和最终报告；调度不可用时保留前台兜底。Worker 初始化失败不会阻断 App 首屏，数据库未就绪会重试，已完成任务不会被误改回排队。

### 上一版 1.182.0+184（本地包已被 v185 取代，不再单独发布）

- **主题**：图二半透明暖白卡作为视觉基准保持不变；主页 Material Card 关闭 surface tint 二次染色；简约白页面底恢复 `#F7F8FA`，像素测试锁定效果。
- **DB v32 / 自动记账**：新增 `auto_record_occurrences` 精确事件幂等；原生通知队列改 key+postTime/UUID，删除 60 秒同文本误去重；Flutter 改 peek + 保存/明确忽略后 ack。
- **报告**：新增 `report_jobs`，切页/重开继续显示思考阶段和原始耗时；重新生成锁定原账本并更新原报告及聊天摘要；所有完成/失败路径释放运行时锁。
- **统计与查询**：统计、Widget、报告统一按一级分类身份和退款净额聚合；无日期 AI 查账先全库关键词检索；聊天恢复解决重复与清空回插竞态。
- **Widget / 更新 / CSV**：Widget 快照单通道+代次+每代独立 PNG；前台更新兜底支持 Range 和陈旧任务清理；CSV 保留转入账户、标签、可报销，并恢复缺失账户/标签。
- **数据安全**：旧 SQLite checkpoint+独占锁复制兜底；Android 禁止云备份和设备迁移应用数据。

### 上一版 1.181.0+183（已上线）

- **主题外观系统**：设置→显示→主题外观；6 色卡（暖橙/简约白/樱粉/薄荷/雾蓝/暮夜强制深色）+背景浓度/卡片透明度滑杆+极简模式+实时预览；AppThemeController 存 JSON；AppColors.applyTheme 唯一写入口；语义色永不开放。
- **UI 设计标准 v1**：`docs/claude/UI_DESIGN_STANDARD.md`（动 UI 前必读）+ AppType 字阶令牌；SettingsRow/SectionLabel 收口；AI 设置四子页整改；全库违规红清零（8 处→超支橙）。
- **GPT5.6 数据一致性批（Claude 验收）**：DB v31——定时记账单事务+recurring_occurrences 台账幂等；net_worth_snapshots 重建表 UNIQUE(scope_key,snapshot_date)；多表操作事务化；表单防重入。330/330（新增 13 测试）。
- 视觉：卡片透明度 40%、设置弹窗暖渐变、SlidingSegment 半透明滑块、✕/齿轮收口 AppCircleButton。

## 2z. 更早（1.180.0+182：设置页 ChatGPT 化 + 弹窗磨砂，已上线）

- 设置页九连改：全屏弹窗+右上✕、分组标题 13.5/w500 中灰、Cupertino 深色图标、卡片透明度 52%/62%（全局 AppColors.card）、版本号只留检查更新行、AppSwitch 恢复灰槽白点（测试已同步）、删宣传语、分组卡连续曲率圆角、抽屉齿轮白圆图三化。
- 并入 181 弹窗磨砂精修（FrostedDialogCard/DialogPillButton/dialogBodyColor）。
- 坑：flutter test 接管道会吞退出码，以后落文件查 $?。

## 2c. 更早（1.178.0+180：更新后台下载）

- 更新下载改系统 DownloadManager（切后台/锁屏/杀进程不中断+通知栏进度+续传）；弹窗「后台下载」按钮；前台完成自动装、后台完成下次打开接续装不重下；DM 禁用回退进程内下载；SHA256 链路不变。
- Kotlin feimiao/update +5 方法（挂起记录存 SharedPreferences）；update_file_paths.xml 补 external-files-path。

## 2b. 上一轮（1.177.0+179：全局弹窗统一图二风格）

- **确认弹窗**（ios_dialogs）：对齐 iOS Cloudflare 客户端原图——标题/正文左对齐、两颗同浅底等宽胶囊、文字主色蓝灰 w600、危险=超支橙字。1.161.0 那版「居中+实心色确认键」与参考图不符，本轮纠正。
- **表单弹窗**（ios_form）按钮文字改主色，与确认弹窗同观感；下载进度弹窗左对齐。
- **裸 AlertDialog 清零**：新建标签→showIosFormDialog；编辑转账删除→showConfirmDialog(destructive)（消灭违规红字）；截图识别中→统一圆角卡。
- **弹窗规范**：以后新弹窗一律 showConfirmDialog / showIosFormDialog，别再手写 AlertDialog / 居中文本 / 实心色按钮。
- 另带上 178 后补的小组件快照指纹跳渲。
- 上一轮（1.176.0+178，已上线）：更新校验加固、深色状态栏、退款净额索引化、transactions 索引、去重复模糊层。

## 3. 验证记录（最新 = v209，2026-07-27）

已完成：

- `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`：0 issue（仅 2 条既有测试 info）。
- `flutter test --no-pub --concurrency=1`：**808/808** 通过（803 基线+5 缓存用例；注意：管道会吞退出码，结果落文件再查 `$?`）。
- `flutter build apk --release --no-pub --build-name 1.207.0 --build-number 209`：成功。
- `verify_release_apk.sh`（含 aapt/16K zipalign/apksigner）：`com.qingji.qingji.codex` / 209 / 1.207.0 / V2 唯一 Codex 签名，证书 SHA256 `4e99c399d4d246bd9c6b08b1d641248bd0846e7ae650c3a766e30fa67483d507`。跑它前先 `export JAVA_HOME="C:\Program Files\Android\Android Studio\jbr"`。
- APK：110,666,531 字节；SHA256 `44B235922691F6DB995572B27478EEFEFC0884634AD76DA83F7C4D6681AA74EB`，归档与 sidecar 一致。v208（P1 批）/v207（P0 批）保留为回退包。
- 离屏渲染截图已做（对比图见 outputs/asset_ui_review/），模拟器/真机安装按惯例跳过；运行态由用户自行安装验收，不能宣称已通过真机验证。

## 4. 线上上传状态
- ✅ **v209 已由 Claude 于 2026-07-27 发布上线（用户拍板）**：`1.207.0+209` / `b0727-209` / DB v41；releaseId `v209-44b235922691`。发布后验证：公网 version.json 返回 209、sha256 `44b23592...aa74eb` 与源 APK 一致、sizeBytes 110,666,531 一致（全量下载哈希核验另记）。本地功能提交与快照见 P2 段。v207/v208 APK 归档保留为回退包（未单独发布）。
- ↩️ **v206 历史基线**：已由 Claude 于 2026-07-26 提交、推送并发布上线：`1.204.0+206` / `b0726-206` / DB v41；本地功能提交 `b2dc7a9`，远端源码快照 `ae5fdb5` 位于 `origin/codex/feimiao-p0-fixes`，Cloudflare releaseId `v206-cf261263d66b`。发布后验证：公网 `version.json` 返回 206、全量下载 110,666,547 字节拼接 SHA256 与源 APK 完全一致。运行态由用户自行安装确认（用户已知可从电脑直接传包安装，绕开 30KB/s 的直连下载）。
- ↩️ **v198 历史基线**：`1.196.0+198` / `b0714-198`；本地提交 `1301e44`，快照 `6703f8e`，Cloudflare releaseId `v198-69ae3ccda9ad`（已被 v206 覆盖）。
- ↩️ **v197 APK/sidecar 原样保留**：作为本轮升级前本地回退基线，不代表 DB v40 运行后的无损降级方案。
- ↩️ **v196 APK/sidecar 原样保留**：作为前一轮回退基线，不代表 DB v40 运行后的无损降级方案。
- ✅ **v195 已由 Claude 于 2026-07-14 发布并逐分片验证**：releaseId `v195-3c502eb61f4e`，version.json 返回 195、sha256 干净、5 分片拼接哈希与源 APK 完全一致。发布时 Cloudflare 连接抖动，改用逐分片带重试上传（version.json 最后原子切换，过程中线上保持 185 不受影响）。

↩️ **v195、v194 与 v193 APK/sidecar 保留为回退基线**：它们不是 DB v39 运行后的无损降级方案，不删除、不覆盖。

↩️ **v192 APK/sidecar 保留为升级前回退基线**：它不是 DB v39 运行后的无损降级方案，不删除、不覆盖。

⏭️ **v191 已被 v192 完整取代，不再单独发布**。

⏭️ **v190 已被 v191 完整取代，不再单独发布**。

⏭️ **v189 已被 v190 完整取代，不再单独发布**。

⏭️ **v188 已被 v189 完整取代，不再单独发布**。

⏭️ **v187 已被 v188 完整取代，不再单独发布**。

⏭️ **v186 已被 v187 完整取代，不再单独发布**。

✅ **v185 已由 Claude 于 2026-07-11 发布并逐分片验证**（历史版本，现已被 v195 覆盖）：releaseId `v185-a42a2d3875b8`，version.json 返回 185、sha256 干净、5 分片拼接哈希与源 APK 完全一致。v184 已被本包完整取代，不单独发布。

✅ **v183 已由 Claude 于 2026-07-11 发布并逐分片验证**（历史版本，现已被 v195 覆盖）：releaseId `v183-606eba7269a6`，5 分片拼接哈希与源一致。

✅ **v182 已由 Claude 于 2026-07-10 发布并逐分片全量验证**。

✅ **v180 已由 Claude 于 2026-07-10 发布**：releaseId `v180-66b213368d44`；本机代理拉不动整包，改逐分片校验通过（5 分片拼接哈希与源一致）。

✅ **v179 已由 Claude 于 2026-07-10 发布并全量验证**：releaseId `v179-23cf92a491b2`，下载哈希与源一致。发布脚本务必在 Git Bash 跑（WSL 的 bash 处理不了 Windows 路径）。

✅ **v178 已由 Claude 于 2026-07-10 发布并全量验证**（用户拍板）：releaseId `v178-61752a7c6383`（干净无反斜杠）。验证：version.json 返回 178、`sha256` 干净 64 位 hex、响应头 `x-feimiao-sha256` 一致、**全量下载 111,442,327 字节哈希与源 APK 完全相同**。

历史备注：v177 污染元数据曾由 Claude 在 v178 发布前直接改写 KV 修复（保证 v176 用户能升 177），现已被 v178 整体覆盖。发布脚本已改 stdin 计算 sha，不会再产生 `\` 前缀。

## 5. 版本文件同步状态

- `pubspec.yaml`：`version: 1.207.0+209`
- `lib/core/app_version.dart`：`version = '1.207.0'`，`buildNumber = 209`
- `lib/build_info.dart`：`kBuildTag = 'b0727-209'`
- `android/local.properties`：Flutter release 构建已读取 `1.204.0+206`；该文件通常不入 git
- DB：**v41**（v40 交易时间精度之上，transactions 新增 `order_no`；导入退款支持跨批/跨月挂回历史原单）
- 版本规矩：每次推送 minor+1、versionCode+1、kBuildTag 同步（b月日-versionCode）

## 6. 接手规则

- 开工前先跑：`git status --short`。
- 不要触碰 `C:\src\xunni`。
- 不要自动执行 `TASKS_FOR_CODEX.md` 的旧任务，除非用户明确点名。
- 不要把旧 release APK 删除状态混进功能提交。
- 不要为了性能删除用户明确要保留的模糊、猫、建议等体验；要从计算、缓存、渲染层优化。
- 出 APK 必须全量 analyze + test，并核验 aapt + apksigner。

## 7. 仍需关注的风险池

这些不是当前自动任务，只是后续排查优先级：

- v178 上传后，真机从 v176/v177 应用内更新到 v178 是否不再校验失败。
- 大数据量账单下主页、统计和小组件刷新是否明显改善；Widget 布局/绘制仍受 Flutter 引擎约束留在 UI isolate，但 PNG 压缩已经移出。
- 深色模式主页状态栏在真机不同系统主题下是否始终清晰。
- AI 记账键盘焦点、返回键、空白点击回主页等历史高频问题需继续真机回归。
- v196 用户安装后重点确认：预算健康绿和动态同色轨道、主页筛选条 8dp 间距、进入喵助手不闪、两种账单标题层级及时间格式、用户气泡透明度、备注完成键保存不跳动、定时记账二级分类原位展开；同时回归 v195 的资产购买日期、日均、持有天数和照片优先详情页。
- A3b verified-checkpoint 纠错流程（superseding/revoked）与 A5 负债单一真相源仍未完成；不要把底层枚举/比较器误写成完整产品闭环。
- 本机 AVD guest 启动前冻结；升级/回退 Emulator 或修复 WHPX 后再做截图，不要宣称本轮已有运行态截图。
