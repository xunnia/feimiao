---
title: 肥喵记账统计与账务口径标准
version: 1.1
calculation_version: 1
aliases: [肥喵记账统计口径标准]
created: 2026-07-12
updated: 2026-07-13
status: locked
tags: [肥喵记账, 统计口径, 账务规则, 开发标准]
sources: 3
---

# 肥喵记账统计与账务口径标准

> 关联：[[肥喵记账App开发笔记]]
> 工程方案：`android-app/docs/claude/BUDGET_ASSET_UX_PLAN_V2_1_2026-07-12.md`
> UI 标准：`android-app/docs/claude/UI_DESIGN_STANDARD.md`
> 规范源：仓库 `android-app/docs/claude/STATISTICS_CALCULATION_STANDARD.md`；Obsidian `记账app/肥喵记账统计口径标准.md` 是逐字同步镜像。修改必须先落规范源，再同步镜像并校验 SHA256 一致。

## 0. 文档地位

本文是肥喵记账关于**当前 App 全部财务指标、派生分析、运营计数，以及未来统一口径**的最高优先级统计合同。

- 主页、账单、预算、统计、Widget、月报/周报/年报、AI 查询和洞察都必须消费同一计算入口。
- 其他产品方案、页面文案或旧实现与本文冲突时，以本文为准；若产品决定确需改变口径，先修订本文、版本号和反例测试，再改 UI。
- 本文文档版本为 `1.1`，首个实现口径仍固定为 `calculationVersion=1`；本次只补齐当前 App 指标台账和差距，没有改变线上算法。两者分别表达文档修订和数据计算合同，不能混用。
- 新指标进入 UI 前必须登记：指标 ID、公式、事件范围、日期轴、窗口、账本范围、币种、空值、笔数单位、比较方式和至少一个反例。
- 本文是个人财务产品口径，不是企业会计准则、税务申报或证券收益核算规范。

标记约定：

- **FACT**：当前代码或已有数据可直接证明。
- **DECISION**：V2.1 锁定的产品规则。
- **CURRENT GAP**：当前实现尚不满足的规则。
- **UNKNOWN**：缺少汇率、估值、历史锚点等，产品必须诚实表达。

## 1. 统计域分类

当前 App 的指标先按经济含义归入四个业务域，再附带两个横切域。一个事件可以投影到多个业务域，但结果不能混名、混算：

| 域 | 回答的问题 | 主日期轴 / 时点 | 例子 |
|---|---|---|---|
| A. 收支与消费归属 | 这段时间赚了多少、实际消费了什么？ | `attribution_date` | 净支出、收入、退款后分类金额、笔数 |
| B. 预算执行与预测 | 计划额度用了多少、未来还能安排多少？ | 预算周期日历 + `attribution_date` | 已用、剩余、今日可用、月底预测 |
| C. 账户结算与现金流 | 钱什么时候真正进出哪个账户？ | `settled_at` | 扣款、退款到账、转账、出售收款、余额 |
| D. 资产负债存量 | 某个时点拥有和欠了多少？ | `as_of` / `valued_at` | 总资产、总负债、净资产、目标资金 |
| X. 审计、版本与质量 | 结果依据什么数据、当时知道什么、是否完整？ | `created_at` / `effective_at` / `knowledgeCutoff` | 补录、校准、冻结报告、缺汇率、待估值 |
| Y. 工作流与运营计数 | 某个操作队列有多少项、流程完成到哪一步？ | 操作发生时点或当前状态 | 搜索命中、导入跳过、候选数、备份份数 |

统计输出再按三类登记：

1. **财务真值指标 `F-*`**：金额、存量和具有财务含义的笔数，可进入收支、预算、账户或净资产核对。
2. **派生分析指标 `D-*`**：占比、排行、趋势、比较、均值、预测、画像和异常，必须能追溯到 `F-*`。
3. **运营与工作流计数 `O-*`**：行数、候选数、任务进度、文件数和配置使用数，只描述流程，**禁止参与财务合计**。

数据质量是所有三类指标的元数据，不另造一套金额。**DECISION：**任何单一 `TransactionRecord.date` 都不能继续同时服务收支归属、预算、账户结算和资产存量。普通交易的消费归属和结算时间通常相同，但模型必须允许不同。

## 2. 统一查询合同

统计核心应逐步收口为显式查询和显式状态：

```text
MetricQuery
  metricId
  window                 // [startInclusive, endExclusive)
  dateAxis               // attribution / settlement / valuation / asOf
  timezone
  bookScope              // explicit ids + scopeVersion
  currencyScope
  asOf
  knowledgeCutoff         // 查询允许看见的事件版本；live=now，冻结产物=生成时
  resultMode              // live / frozen
  classificationVersion
  calculationVersion

MetricResult<T>
  value
  status                 // available / partial / unavailable /
                         // notApplicable / stale / conflict
  reasons[]
  window
  scope
  currency
  asOf
  lineage                // resolver 与口径版本
```

规则：

1. UI 不得用 `null ?? 0` 把未知、无设置或冲突变成 0。
2. 同一屏主卡、分类和趋势必须来自同一个主 window/scope/version。同比另显式携带 `currentComparableWindow + previousWindow`；短月时可取主 window 的等长前 N 天子窗口，并在 UI 标“前 N 天”，不能假装同比 delta 直接来自截至今天的主卡总额。
3. 原始 Repository 列表不是统计合同；页面不得自行筛日期、净退款或换分类层级。
4. 结果为 `partial` 时必须携带缺失原因，例如“未含 2 项外币资产”或“1 件物品待估值”。
5. `window` 决定业务归属，`knowledgeCutoff` 决定当时已经知道哪些事件，两者不能混用。live 历史页以 now 为 cutoff，后来退款会动态修正旧月份；冻结报告/导出/checkpoint 使用生成时 cutoff 和不可变结果。

## 3. 当前 App 全量指标注册表

### 3.1 台账基线与状态

本节审计基线为 2026-07-13 当前 Flutter/SQLite 工作树（应用版本基线 `1.186.0+188`、DB v32）。它登记**当前 App 所有会汇总、比较、排行、计数、预测或生成结论的指标**；后文给出统一后的目标合同。

实现状态：

| 状态 | 含义 |
|---|---|
| `current_exact` | 当前受支持范围内，现行实现与本标准一致 |
| `current_partial` | 当前能计算，但缺日期轴、币种、质量状态或完整覆盖 |
| `current_inconsistent` | 同名指标在不同页面公式不同，或现行公式与本标准冲突 |
| `target_only` | V2.1 已锁定、当前 App 尚未实现 |
| `deferred` | 当前不支持且尚未进入实施范围 |

消费者简称：`HOME`=主页大卡；`LEDGER`=账单列表/分类下钻；`SEARCH`=搜索；`STAT`=统计页；`BUDGET`=预算管理；`WIDGET`=桌面小组件；`REPORT`=本地月报/AI 报告；`AI`=喵助手查账与洞察；`ASSET`=资产管理；`GOAL`=存钱目标；`OPS`=导入、自动/定时记账和设置流程。

当前交易统计的共同地基是 `LedgerPolicy.userAmountWith`：不计收支行和附着退款子行输出 0，原消费输出 `原额 + 负数退款合计`。`AppRepository.allRecords` 只包含当前账本视图中可计入收支的用户净额记录。凡下表写“净额记录流”，均指这一现状；它仍只有 `date_ms` 一个日期轴。

### 3.2 财务真值：收支、交易家族、退款与报销

| metric_id | 当前名称 / 消费者 | 当前公式与范围 | 单位、日期轴与笔数 | 状态与标准 |
|---|---|---|---|---|
| `F-TXN-001` | 支出 / `HOME STAT WIDGET REPORT AI` | 窗口内 expense 净额记录求和；transfer、excluded、退款子行不计 | 金额；当前 `date_ms`；账本视图 | `current_partial`；消费归属正确，仍缺独立结算日/币种质量 |
| `F-TXN-002` | 收入 / 同上 | 窗口内 income 用户金额求和；退款不算收入 | 金额；当前 `date_ms`；账本视图 | `current_partial` |
| `F-TXN-003` | 收支结余 / 同上 | `F-TXN-002 - F-TXN-001` | 金额；与主窗口同 scope | `current_exact`；禁止称余额、净资产变化或收益 |
| `F-TXN-004` | 每日支出、每日收入 / `HOME STAT REPORT WIDGET` | 按自然日对 `F-TXN-001/002` 分组，统计引擎为窗口内无记录日补 0 | 金额/日；当前设备本地日 | `current_partial`；待冻结业务时区 |
| `F-TXN-005` | 一级分类金额 / `HOME STAT REPORT WIDGET AI` | 支出按稳定一级 category key 聚合；空/未分类归“其他” | 金额；root family；消费归属窗口 | `current_partial`；实时分类已统一到一级，冻结版本尚不完整 |
| `F-TXN-006` | 支出笔数、收入笔数、购买订单数 | 当前各消费者有三种算法：原始行数、净额非零行数、正净额家族数 | `expenseCount` 应为正净额 family；`incomeCount` 为 distinct 收入事件；订单数另列 | `current_inconsistent`；全额退款、legacy 负支出和转账会让页面间笔数不一致 |
| `F-TXN-007` | 分类笔数 / `STAT WIDGET REPORT` | `StatisticsEngine` 当前每遇一条支出记录先 `count+1`，不在聚合后剔除净额 0 | distinct 正净额 family / 分类 | `current_inconsistent`；一单拆分类时分类笔数不可相加成总笔数 |
| `F-TXN-008` | 原额、已退、可退、净额 / `LEDGER AI退款卡` | `original`；`refunded=sum(attached refund abs)`；`available=max(original-refunded,0)`；`net=original-refunded` | 金额；root family；退款消费归属原单日 | `current_exact`（消费视角）；退款到账时间和到账账户仍缺失 |
| `F-TXN-009` | 退款事件数、已退款订单数 | 数据可由附着退款子行数与发生退款的 distinct root 得出，当前没有统一公共结果 | refund event / refunded family | `current_partial`；到账日 unknown 时现金流事件数必须 partial |
| `F-TXN-010` | 搜索结果支出/收入金额与笔数 / `SEARCH` | 先按关键词、类型、日期、账户、标签、金额过滤可见 root；金额用用户净额，非零即加一笔 | 金额 + 结果 family 数；搜索 scope | `current_inconsistent`；legacy 负支出会形成负“支出”且仍计 1 笔 |
| `F-TXN-011` | 分类下钻金额、“共 N 笔” / `STAT` | 明细按分类和日期取 root，金额按净额；当前 `N=rows.length` | 金额 + family 数；所选分类/window | `current_inconsistent`；全额退款 root 仍可能计入 N |
| `F-TXN-012` | 待报销金额、待报销笔数 / `LEDGER 报销页` | 当前筛 `reimbursable=true` 后直接求 `t.amount` 与行数，未排除 excluded | 应为 `sum(max(familyNet,0))` 与正净额 family 数 | `current_inconsistent`；部分退款后仍报原额，全退后仍可能计一笔 |
| `F-TXN-013` | 账单日小计 / `LEDGER` | 公共主页日卡使用用户净额；旧交易列表日标题直接加原额 | 金额/自然日 | `current_inconsistent`；必须统一到净额 family |
| `F-TXN-014` | AI 时间范围/关键词查账合计与笔数 / `AI` | 显式日期问题按 `QueryRange` 裁剪；关键词可查全库后补近期；多处自行合计 | 金额 + 明确事件单位；问题解析窗口 | `current_inconsistent`；部分“共 X 笔”混合收入、支出、转账与全退原单，必须拆名 |

**当前收支共性差距：**`StatisticsEngine` 没有币种 scope，会直接相加传入的不同币种；自然月/年统计也没有统一把主窗口截到“今天”，未来日期交易可能提前进入“截至今日”金额并被画成已发生。统一 resolver 必须同时解决币种与 `knowledgeCutoff`，不能只在某张卡临时过滤。

**报销 inclusion 决策：**`reimbursable` 是独立工作流标志。不计收支但确实可向他人报销的原单仍可进入待报销队列；其未结金额按退款后 family net 算。报销到账沿用原单的收支/预算策略（excluded 原单不因到账突然变普通收入），但必须按真实到账账户与结算日进入账户现金流。

### 3.3 财务真值：预算执行

| metric_id | 当前名称 / 消费者 | 当前公式与范围 | 单位、日期轴 | 状态与标准 |
|---|---|---|---|---|
| `F-BUD-001` | 本月预算 / `HOME BUDGET STAT WIDGET` | `budgetTotalFor(year, month)`：取覆盖该月/当前账本的预算计划总额 | 金额；自然月展示窗口 | `current_partial`；历史 revision、重叠和计划 scope 需由新 resolver 固化 |
| `F-BUD-002` | 已用预算 / 同上 | 当前月可计预算支出净额求和，现行等同本月净支出 | 金额；消费归属日 | `current_partial`；未来需独立 `countsInBudget` 策略和固定承诺 |
| `F-BUD-003` | 剩余、超支额 / 同上 | `remaining=budget-spent`；`over=max(spent-budget,0)` | 金额 | `current_exact`（旧月预算范围内） |
| `F-BUD-004` | 预算使用率 / `BUDGET STAT WIDGET` | `spent/budget`；UI 进度条常 clamp 到 `[0,1]`，文字可显示真实超支 | 比率 | `current_partial`；无预算/预算 0 应 unavailable，不是 0% |
| `F-BUD-005` | 今日已花、剩余天数 / `HOME BUDGET STAT` | `spentToday` 为今日净支出；主页/预算页 `daysLeft=月末日-today+1`，统计预算环当前按未过天数显示 | 金额 + 自然日数 | `current_inconsistent`；同名剩余天数存在含今天/不含今天两套，未来按预算周期统一 |
| `F-BUD-006` | 今日可用 / `HOME` | `(budget-spentBeforeToday)/含今天剩余天数-spentToday` | 金额/今天 | `current_partial`；未预留固定承诺、还本、目标存款前不得写“安全可花” |
| `F-BUD-007` | 往后每天可花 / `BUDGET` | 未超支时 `remaining/daysLeft`，当前页面显示前转 0 位 Decimal | 金额/剩余自然日 | `current_inconsistent`；与逐分分配标准精度不同，且不能与今日可用混名 |
| `F-BUD-008` | 分类预算额度、已用、剩余、进度 / `BUDGET` | 生效计划的 category amount；一级分类月净支出；`spent/amount` | 金额 + 比率；分类/计划 scope | `current_partial`；继承、revision、分类合计超额和币种状态尚未完整建模 |
| `F-BUD-009` | 已分配分类预算、未分配额度 | 当前编辑表单可由 category amounts 求和并与总额比较 | 金额；预算计划 | `current_partial`；必须按分逐项校验，不能静默缩放 |
| `F-BUD-010` | 预算计划覆盖状态 | 当前按月/周/一次性 period 的 start/end 与 book 解析生效计划 | 计划状态；日历周期 | `current_partial`；重叠 primary、revision 和关闭周期冻结是 V2.1 目标 |

### 3.4 财务真值：账户、资产、负债与存钱目标

| metric_id | 当前名称 / 消费者 | 当前公式与范围 | 单位、时点与对象 | 状态与标准 |
|---|---|---|---|---|
| `F-ACC-001` | 单账户余额 / `ASSET` | `openingBalance + income - expenseNet + transferIn - transferOut`，按账户币种过滤交易；不计收支流水仍真实改变账户 | 原币金额；当前时点；账户 | `current_partial`；缺 settled_at、校准锚点和历史 as-of |
| `F-ACC-002` | 账户类型组余额 / `ASSET` | 当前对同一 AccountType 的活动账户余额直接相加 | 金额；账户组 | `current_inconsistent`；会跨币种直接相加，且组卡不等同净资产计入范围 |
| `F-ACC-003` | 本月收支净额 / `ASSET` | 当前账本视图 `本月收入-本月支出` | 金额；消费窗口；当前账本 | `current_exact` 但位置/命名有风险；它不是全局净资产变化，应移出资产主卡或显式标账本 |
| `F-NW-001` | 流动资产、投资资产 / `ASSET REPORT` | 只取计入净资产且币种为 CNY 的账户；正余额按类型进入流动/投资 | CNY 存量；当前时点；全局 scope | `current_partial`；外币单列但无折算 |
| `F-NW-002` | 实物资产、权益资产 / 同上 | CNY 且 `countsInNetWorth` 的实物 `currentValue`、权益 `remainingAmount` 求和 | CNY 存量；当前时点；全局 scope | `current_partial`；归档会错误改变 include，历史 as-of 未实现 |
| `F-NW-003` | 总资产 / 同上 | `流动+投资+实物+权益` | CNY 存量 | `current_partial`；只在明确排除外币并返回 partial 时可显示精确总数 |
| `F-NW-004` | 总负债 / 同上 | 负余额账户取绝对值；若同账户无负余额再取 liability profile `currentPrincipal` | CNY 存量；当前时点 | `current_inconsistent`；legacy hybrid 是临时单一真相源，profile 循环还可能把非 CNY 本金当 CNY |
| `F-NW-005` | 净资产 / 同上 | `totalAssets-totalLiabilities` | CNY 存量；当前时点；全局 scope | `current_partial`；与账户月结余、投资收益分开 |
| `F-NW-006` | 计入项数 / 全部项数 / `ASSET` | 当前分子使用全局计入账户+实物+权益，分母混用当前账本可见/归档对象 | object count | `current_inconsistent`；分子分母 scope 不同，甚至可能分子大于分母 |
| `F-NW-007` | 净资产快照 / `ASSET REPORT` | 保存调用时 `currentNetWorthBreakdown()`，再把传入日期写成 snapshot date | CNY 存量；标签日期 | `current_inconsistent`；传历史日期仍写今天状态，不能称历史 as-of |
| `F-NW-008` | 未支持币种集合 / `ASSET` | 声明计入净资产但 currency!=CNY 的账户、实物、权益币种去重集合 | currency code set；全局 scope | `current_exact`（质量提示）；该集合非空时 CNY 总数必须标 partial，未来还应覆盖负债 |
| `F-AST-001` | 物品购买价、当前价值 / `ASSET` | 当前实体字段与最新估值/折旧事件维护；终止状态可归零 | 原币金额；对象/估值时点 | `current_partial`；缺统一 cost quality、历史 as-of 与跨币种成本 |
| `F-AST-002` | 折旧基数、残值、寿命、折旧状态 / `ASSET` | 线性折旧配置字段；当前值可由自动折旧事件更新 | 原币金额 + 月数 + 状态 | `current_partial`；会计折旧不等于市场价值或真实损失 |
| `F-AST-003` | 权益原始额、剩余额、累计收回 / `ASSET` | `remaining` 为当前字段；`recovered=sum(recovery amount)`；应满足 `original=remaining+recovered+loss` | 原币金额；权益对象 | `current_partial`；归档/零余额 legacy 状态仍需迁移解释 |
| `F-AST-004` | 负债原始本金、当前本金、利率 / `ASSET` | liability profile 字段；当前本金与负账户余额并存 | 原币金额 + 年利率；负债对象 | `current_inconsistent`；必须迁到单一负债真相源 |
| `F-AST-005` | 还款日、距还款天数 / `ASSET` | profile repayment day 映射到下个合法日期，再与 today 做日差 | 日期 + 自然日数 | `current_partial`；需冻结业务时区并定义短月裁剪 |
| `F-AST-006` | 实物/权益分组金额 / `ASSET` | 当前账本视图中可计入实物的 currentValue、权益的 remainingAmount 分组求和 | 原币金额；当前视图 | `current_inconsistent`；分组卡未按币种拆分，和顶部仅 CNY 的总额 scope 不同 |
| `F-AST-007` | 权益收回金额与次数 / `ASSET` | 每次 recovery amount；累计额应为有效 recovery 求和，次数为 event count；详情当前只列最近 5 次 | 原币金额 + recovery event count | `current_partial`；累计收回与 `original-remaining-loss` 需守恒 |
| `F-GOAL-001` | 目标金额、已存金额 / `GOAL` | 目标字段 + 手工存入/取出台账累计 | 金额；目标对象；当前状态 | `current_exact`（手工模型） |
| `F-GOAL-002` | 剩余金额、超额金额 / `GOAL` | 标准为 `remaining=max(target-saved,0)`、`overfunded=max(saved-target,0)` | 金额；目标对象 | `current_partial`；当前部分 UI 直接 `target-saved`，超额需独立表达 |

**当前存钱目标边界：**“存入/取出”只改变目标台账进度，不自动改变账户余额、收支、现金流或净资产。绑定专用账户和资金分配台账属于 V2.1 后续能力；在接通前不得把 `saved` 当成真实账户存量。

### 3.5 派生分析：统计、比较、预测与资产比率

| metric_id | 当前名称 / 消费者 | 当前算法 | 输入与单位 | 状态与标准 |
|---|---|---|---|---|
| `D-STAT-001` | 分类占比 / `STAT WIDGET REPORT` | `categoryNet/totalNetExpense` | `F-TXN-005/F-TXN-001`；比率 | `current_inconsistent`；分母 0 时部分消费者写 0%，标准为 notApplicable |
| `D-STAT-002` | 分类排行、Top 3/5/6 / `HOME STAT WIDGET REPORT` | 按精确金额降序，同额当前部分位置按名称 | 分类金额；rank | `current_partial`；统一稳定 key 兜底 |
| `D-STAT-003` | 单笔支出排行 / `STAT REPORT` | 应按正净额 root 降序；AI 报告已剔除非正净额，统计页部分 Top 5 路径未显式过滤 | family net；rank | `current_inconsistent`；legacy 负支出不得进入榜单 |
| `D-STAT-004` | 每日/每月趋势 / `STAT` | 周/月/自定义按日，年按 12 月；未来日通常补 0 或不画 | 日/月金额序列 | `current_partial`；未来日期必须 null，主/对比序列必须同窗 |
| `D-STAT-005` | 消费热力图、最高支出日 / `STAT REPORT` | 日支出相对窗口最大值映射颜色；最高日取最大日金额 | `F-TXN-004`；强度/rank | `current_partial`；热力强度不是金额等级，必须有数值摘要 |
| `D-STAT-006` | 消费来源 Top 6 / `STAT` | 月内支出按商户/备注归一化后聚合正净额，取前 6 | family net；normalized source | `current_partial`；归一化规则需版本化，未知来源不能伪装商户 |
| `D-STAT-007` | 本期 vs 上期金额差、涨跌率 / `STAT REPORT AI` | 多处自行构造上月或上一等长周期；`delta=current-previous`，率为 `delta/previous` | 同 scope 两窗口；金额/比率 | `current_inconsistent`；当前月多处拿截至今天直接比完整上月，上期 0 还会隐藏 |
| `D-STAT-008` | 本月 vs 上月分类条/雷达 | 取两个月一级分类金额并归一化到图表尺度；当前候选主要来自本月正额 Top 分类 | 分类金额；比较 | `current_inconsistent`；当前月应比上月同期，上月存在但本月归零的分类也必须进入并集 |
| `D-STAT-009` | 近 12 月收支堆叠 | 每月支出与收入；`income>=expense` 显示支出+结余，否则支出与差额 | 月金额序列 | `current_inconsistent`；支出超收入的差额应叫“负结余/超出收入”，不能叫预算“超支” |
| `D-STAT-010` | 历史 6 个月同期平均 / `STAT WIDGET` | 截至相同日序的过去 6 月支出平均；当前只纳入 `>0` 月，页面 1 样本可显示、Widget 至少 2 样本 | 同期月金额；均值 | `current_inconsistent`；真实 0 月与缺数据月必须区分，样本门槛统一 |
| `D-STAT-011` | 偏高/持平/偏低 / `STAT WIDGET` | 当前月截至今日与 `D-STAT-010` 比；当前页面以历史均值上下约 8% 为“基本持平”边界 | 比率/枚举 | `current_partial`；8% 阈值、样本数与版本必须跨消费者一致 |
| `D-STAT-012` | 笔均支出、笔均收入 / `REPORT AI` | `net amount / 对应 count` | 金额/事件 | `current_inconsistent`；零笔时当前部分路径写 0，标准为 notApplicable |
| `D-STAT-013` | 日均支出 / `REPORT` | 当前月用今天日序，历史月用完整月天数；`expense/days` | 金额/自然日 | `current_partial`；自定义/部分窗口应使用窗口已覆盖日数 |
| `D-STAT-014` | 7 天分段支出 / `AI REPORT` | `floor((date-start)/7)+1` 聚合正净额支出 | 金额/分段 | `current_exact`；文案不得把最后不足 7 天段写成完整周 |
| `D-STAT-015` | 累计收支结余曲线 / `STAT` | 按日或月累加 `income-expense` | 金额序列 | `current_partial`；它是窗口内累计结余，不是账户余额或净资产曲线 |
| `D-STAT-016` | 结余率 / `STAT AI画像` | 有收入时 `(income-expense)/income` | 比率 | `current_partial`；income<=0 时 notApplicable，不得显示 0% |
| `D-STAT-017` | 最大单笔集中度 / `STAT AI画像` | `maxPositiveFamilyNet/totalNetExpense` | 比率 | `current_partial`；总支出<=0 时 notApplicable |
| `D-BUD-001` | 预算状态 / `HOME BUDGET WIDGET` | `spent>budget` 为超支；Widget 另以 85% 为“临近” | 枚举；预算率 | `current_partial`；阈值必须有单一配置 |
| `D-BUD-002` | 月底支出预测 / `STAT AI` | 月日序 >=3 且有预算/支出时：`spent/todayDay*monthDays` | 金额 forecast | `current_partial`；纯线性外推，必须标预测，不得当实际或承诺感知预测 |
| `D-BUD-003` | 智能预算建议 | 有收入时参考收入 80%，否则参考近 3 月消费均值，并按历史结构分配 | 建议金额 | `current_partial`；是可编辑建议，不是财务事实 |
| `D-BUD-004` | 今日可用圆环比例 / `HOME` | 当前视觉比例约为 `todayAllowance/(spentToday+todayAllowance)`，负可用时归 0 | 比率/视觉编码 | `current_partial`；分母无效时不可计算，圆环比例不能反推精确预算执行率 |
| `D-INS-001` | 总支出变化洞察 | 上月和本月均 >0 且绝对变化 >=10% 才提示 | `D-STAT-007` | `current_inconsistent`；当前月比较窗仍不等长 |
| `D-INS-002` | 分类增量与集中度 | 分类多花 >=50 元提示；Top 分类占比 >=45% 且总支出 >=200 提示 | 金额/比率 | `current_partial`；阈值须版本化 |
| `D-INS-003` | 消费画像 | 至少 5 笔；最大单笔占比 >=35% 为大额集中；有收入时按结余率 <5%、>=30% 分型 | 枚举 + 文案 | `current_inconsistent`；样本笔数当前按原始正支出行，不完全等同 family count |
| `D-INS-004` | 大额异常提醒 | 有足够历史样本时，以中位金额和本次金额倍数/差额阈值判断 | 金额 + 布尔 | `current_partial`；常用分类、excluded 与退款过滤需要统一 |
| `D-PERS-001` | 常用分类排序、AI 分类建议权重 | 当前按历史分类频次、时段等启发式排序 | score/rank | `current_inconsistent`；部分入口仍可能读原始行，退款/不计收支不应增加偏好频次 |
| `D-PERS-002` | 常用金额/中位金额建议 | 对历史同类金额排序取中位或常用值 | 金额建议 | `current_partial`；必须只用正净额 family 并标样本窗口 |
| `D-NW-001` | 资产结构占比 / `ASSET REPORT` | `各资产类/totalAssets` | 比率 | `current_partial`；缺汇率或 totalAssets=0 时不可计算 |
| `D-NW-002` | 负债率 / `ASSET REPORT` | `totalLiabilities/totalAssets`；当前页面视觉值封顶 999%，资产报告不封顶 | 比率 | `current_inconsistent`；分母 <=0 为 notApplicable，原始比率与视觉上限必须分字段 |
| `D-NW-003` | 较上次净资产变化 | 当前快照可做差，但历史快照质量不足 | 金额差/比率 | `target_only`；仅两次可比 verified checkpoint 才能称可信变化 |
| `D-AST-001` | 保值率、日均持有花费、最终成本 | 当前数据模型已保存购置、估值、维护/处置事件；完整公式见第 12 节 | 比率/金额/日 | `target_only` 为统一 resolver；当前零散字段不得包装成精确收益 |
| `D-AST-002` | 资产报告实物 Top 5 / 权益 Top 5 | 计入净资产的 CNY 实物按 currentValue、权益按 remainingAmount 降序取 5 | object rank | `current_exact`；同额使用稳定 UUID/id 兜底 |
| `D-GOAL-001` | 存钱进度、完成状态 | `raw=saved/target`；显示 `clamp(raw,0,1)`；`saved>=target` 为完成 | 比率 + 枚举 | `current_partial`；target<=0 不可计算，超额另用 `F-GOAL-002` |
| `D-WIDGET-001` | 历史 full / same-progress 与本月进度序列 | 过去 6 月分别保存完整月支出和截至同日序支出；本月只具备截至今天值 | 月金额序列 | `current_inconsistent`；JSON 与 Flutter 图片卡对本月 `fullValue` 定义不同，必须统一为 unknown 或明确 partial |
| `D-WIDGET-002` | Widget 预算状态 | 无预算 normal；进度 >=85% 为 nearLimit，>=100% 为 over | 枚举 | `current_exact`（当前阈值）；阈值后续纳入单一配置并版本化 |

AI 生成的自然语言不是新的财务指标。报告和喵助手只能引用已登记的结构化指标；模型给出的原因、建议和预测结论必须标为分析，不得覆盖金额真值。

### 3.6 运营与工作流计数

下表所有 `O-*` 都是产品流程状态。即使 UI 使用“笔”，也不得与 `expenseCount`、`incomeCount` 或资产对象数相加。

| metric_id | 当前名称 / 消费者 | 当前定义与单位 | 状态与约束 |
|---|---|---|---|
| `O-SEARCH-001` | 搜索命中数 | 通过当前关键词和筛选器的可见 root 行数 | `current_exact`；只是结果行数，财务笔数另见 `F-TXN-010` |
| `O-LEDGER-001` | 当前账本可见账单行数 | `visibleTransactions` 的 root 行数 | `current_exact`；含转账、全退订单和不计收支行，不等于支出笔数 |
| `O-ACC-001` | 账户类型组账户数 | 同一 AccountType 下活动账户行数 | `current_exact`；对象数，不随 `includeInNetWorth` 自动过滤 |
| `O-AST-001` | 实物/权益对象数 | 当前账本视图非删除对象数，按 visible/archived/status 分开 | `current_partial`；“件/项”不能与净资产计入数或导出行数混用 |
| `O-GOAL-001` | 存钱目标数 | 当前全局 savings goal 对象行数 | `current_exact`；不分账本，不进入收支或资产合计 |
| `O-IMPORT-001` | 原文件总行、解析成功、跳过中性/无效 | parser 的 `totalRows / rows.length / skipped` | `current_exact`；三个分母不得互换 |
| `O-IMPORT-002` | 自动归类笔数、商户组、退款行数 | 复核页 `_autoRows.length / _groups.length / _refunds.length`；另拆 pending group、group row 和每组原始金额 | `current_partial`；商户组数、组内行数和账单笔数不得混用 |
| `O-IMPORT-003` | 实际插入、跳过重复、挂回退款 | import result 的 `inserted / skippedDuplicates / refundsAttached` | `current_exact`；退款挂回数不得重复算成新增普通账单 |
| `O-IMPORT-004` | AI 成功归类组数 | 本次 AI 返回有效分类并写入 pending 商户组的数量 | `current_exact`；计的是 group，不是 row |
| `O-IMPORT-005` | 资产导入处理数 | 实物、权益、事件、估值、关联、收回、快照、负债档案各自处理计数 | `current_inconsistent`；部分“处理”包含更新/冲突忽略，不等于新增，必须拆 inserted/updated/skipped |
| `O-EXPORT-001` | 导出交易行数 | 选定日期范围内序列化的物理 transaction 行数，包含附着退款子行 | `current_partial`；不能称交易家族/用户“账单笔数”，冻结 scope/version 待补 |
| `O-EXPORT-002` | 导出实物/权益数 | 当前选定对象集合的序列化行数 | `current_inconsistent`；现行范围可能含归档或软删除对象，需显式 visible/archived/deleted |
| `O-AUTO-001` | 自动记账候选数、已选数、保存调用数 | 当前队列长度、勾选布尔数、成功返回的保存调用数 | `current_inconsistent`；幂等命中旧流水也可能被 toast 算“记下”，中途失败缺成功/失败明细 |
| `O-REC-001` | 定时记账已生成/总次数 | `generatedCount / totalCount`；无总次数时只显示 generated | `current_exact`；由 occurrence 幂等台账推进，删除账单不回退历史生成次数 |
| `O-REC-002` | 定时记账剩余次数/完成状态 | `max(total-generated,0)`；`generated>=total` 为按次数完成 | `current_exact`；无限规则为 notApplicable，不显示 0 次剩余 |
| `O-REC-003` | 规则数、实际流水数 | recurring rule 行数；`recurringRuleId` 对应的当前可见交易 root 数 | `current_inconsistent`；规则是全账本，流水列表受当前账本 scope，且 generated 不等于现存流水数 |
| `O-CAT-001` | 子分类数 | 某一级分类直接 children 行数 | `current_exact`；分类结构计数，不是账单数 |
| `O-CAT-002` | 分类关联/受影响账单数 | 操作前按 category id/key 命中的交易 root 行数 | `current_partial`；合并/删除提示应说明是否含隐藏、历史和退款 family |
| `O-CAT-003` | 分类依赖数 | 关联定时规则数、引用该分类的预算计划数 | `current_partial`；属于删除保护，不是分类使用笔数 |
| `O-TAG-001` | 标签使用账单数 | tag id 出现在 root 账单 tags 中的 distinct 行数 | `current_partial`；当前 scope 与分类全库计数不同，且不得把附着退款子行重复计入 |
| `O-TAG-002` | 标签总数 | 当前 tag 实体行数 | `current_exact`；对象数，不是使用次数 |
| `O-MEM-001` | 分类记忆数 | `categoryMemories.length` | `current_exact`；一条是短语×收支类型映射，不是交易样本数 |
| `O-BACKUP-001` | 原始/展示备份份数 | raw 为目录内所有匹配 `.bak` 文件数；displayed=`min(按时间排序后数量,3)` | `current_exact`；UI 的 3 份不等于磁盘保护文件总数，手动/自动清理桶也各自独立 |
| `O-BACKUP-002` | 备份大小、自动备份年龄 | size=`bytes/1024/1024` MiB（当前文案写 MB）；age 为距最新自动备份修改时间的整日差 | `current_inconsistent`；单位应改 MiB 或按十进制 MB，7 天门槛需基于明确时区 |
| `O-REPORT-001` | 报告数、任务状态数 | report 实体数；job 按 queued/running/completed/failed 计数 | `current_partial`；重生成更新原报告，不应制造重复完成数 |
| `O-OBJ-001` | 账本、账户、报告等其余对象数 | 对应当前可见/归档对象集合长度 | `current_partial`；每个卡片必须写清 global/book、visible/archived、included/all，已单列的资产/目标数复用其 ID |
| `O-OBJ-002` | 账本物理流水数 | 删除保护或管理页按 book_id 命中的 transaction 物理行数 | `current_partial`；含退款子行时不等于用户账单 family 数 |
| `O-AI-001` | AI 记账识别条数、待保存/已保存/已删除条数 | 解析卡 entries 按状态计数 | `current_partial`；它们是草稿工作流，不是最终交易笔数 |
| `O-AI-002` | AI 关键词命中数 | 全库检索命中的可见 root 行数 | `current_exact`；与关键词命中金额并列，但不得冒充 expenseCount |
| `O-AI-003` | AI 上下文截断数 | `总命中/候选数 - 实际送入模型行数` | `current_partial`；被截断时结论必须披露范围，不得声称全库完整 |

### 3.7 消费者覆盖矩阵

| 消费者 | 当前必须登记的指标族 | 当前主要计算入口 | 已知风险 |
|---|---|---|---|
| 主页大卡与月份选择 | `F-TXN-*`、`F-BUD-*` | `StatisticsEngine`、`BudgetEngine` | 单日期轴、旧月预算 |
| 账单列表、搜索、分类下钻、待报销 | `F-TXN-008~013`、`O-SEARCH/LEDGER` | `LedgerPolicy` + 页面局部循环 | 日小计/报销/笔数口径分裂 |
| 统计周/月/年/自定义 | `F-TXN-*`、`D-STAT/BUD/INS` | `StatisticsEngine` + 页面卡片 | 对比窗口、0 月样本、图表文案 |
| 预算管理 | `F-BUD-*`、`D-BUD-*` | `BudgetResolver`、`BudgetEngine` | revision、固定承诺、逐分精度 |
| Widget | `F-TXN/BUD`、`D-STAT-001/002/010/011` | `widget_snapshot_service.dart` | 与页面样本门槛不一致 |
| 月报、AI 报告、喵助手查账 | `F-TXN-*`、`D-STAT/INS` | 多个局部 summarize + LLM context | 0 当不可用、混合“笔”、冻结口径 |
| 资产管理与资产报告 | `F-ACC/NW/AST`、`D-NW/AST` | `AppRepository.currentNetWorthBreakdown` | scope、外币、负债 hybrid、假历史快照 |
| 存钱目标 | `F-GOAL-*`、`D-GOAL-*` | 手工目标台账 | 尚未连接真实账户资金 |
| 导入/导出、自动/定时记账、分类/标签/备份 | `O-*` | 各流程结果对象/集合长度 | “笔/行/组/项/份”容易混名 |

### 3.8 注册门禁

1. 新增或改名任何用户可见数字前，先在本节登记唯一 `metric_id`；同义 UI 文案只能作为 aliases。
2. 每个财务指标必须能下钻到稳定 root family/event/object；每个运营计数必须说明计的是行、组、对象、文件还是任务。
3. `current_inconsistent` 项未迁移前，页面不得宣称“全 App 已统一”。修复时先补反例，再迁消费者，最后把状态改为 `current_exact`。
4. `target_only` 不得在交接或 UI 写成已实现；`current_partial` 必须把缺失范围或质量原因传到展示层。
5. 本节是全量人工注册表；第 23 节差距清单只列高风险实现问题，两者交叉审计但不互相替代。

## 4. 日期与时间轴

### 4.1 字段定义

| 字段 | 用途 | 禁止用途 |
|---|---|---|
| `attribution_date` | 收入、消费、分类、预算归属 | 退款实际到账现金流 |
| `settled_at` | 可空；账户扣款/到账、现金流、余额变化 | 把退款算成到账月普通收入 |
| `settlement_account_id` | 可空；事件真实扣款/到账账户，退款/报销可不同于原单付款账户 | 强制继承原单账户 |
| `settlement_account_quality` | exact / user_confirmed / legacy_assumed / unknown；与日期质量独立 | 用日期质量代替账户可信度 |
| `valued_at` | 某资产估值在何时有效 | 用普通编辑时间判断估值新鲜度 |
| `effective_at` | 校准锚点、状态事件何时生效 | 当普通收支日期 |
| `created_at/updated_at` | 同步和审计 | 任何业务统计窗口 |

现有迁移建议：

- `transactions.date_ms` 暂时保留并明确为 `attribution_date`。
- 新增 `settled_ms` 和 `settlement_quality`（exact / user_confirmed / legacy_assumed / unknown）。
- 新增 `settlement_account_id` 和独立的 `settlement_account_quality`；普通历史交易的现有账户可迁为 `legacy_assumed`。
- 普通历史交易可先令 `settled_ms=date_ms / quality=legacy_assumed`。
- 现有附着退款只保留了原订单日，真实到账日已丢失；迁移为 `settled_ms=null / quality=unknown`，不能拿 `updated_ms` 或迁移日伪造。新退款才写用户确认或本次记录的真实到账日。
- 旧商家退款沿用原付款账户只能标 `settlement_account_quality=legacy_assumed`；旧报销可能进入工资卡等其他账户，必须迁为 account unknown 并进入待确认，不能假定原付款账户。

### 4.2 窗口边界

- 核心统一使用半开区间 `[startInclusive, endExclusive)`；UI 可显示含首尾日期。
- 自然日、自然月、自然周和 attribution 使用持久化 `businessCalendarTimezone`（默认创建时用户时区），不随设备旅行自动漂移。计划另保存 timezone；修改业务时区属于口径变化。
- `settled_at` 保存 UTC instant，按查询冻结的 reporting/business timezone 分组展示；冻结报告保存当时 timezone/version。不能用“当前设备时区”重写旧月份日期。
- 当前周期按本地日历日计算；不能用固定 24 小时毫秒数代替跨时区自然日。
- 同一毫秒的多事件使用业务 sequence，再用 id 兜底，结果必须稳定。
- 已发生交易、退款、估值和状态事件只有在 `created_at <= knowledgeCutoff` 且其业务生效时点不晚于 cutoff 时才进入该版本查询；撤销同样按 cutoff 判断。计划配置和固定 commitment 是预测数据：只要 `created_at <= cutoff` 即可看见未来 due date，并参与 forecast/unresolved reserve，但不能冒充已发生 spent。冻结结果不能看到生成后才录入或生效的真实事件。

### 4.3 跨月退款示例

```text
6/20 原消费 100 元
7/05 实际退款到账 30 元

6 月净支出             70
6 月预算占用           70
7 月普通收入            0
7 月账户现金流入       30
7/05 结算后账户余额    +30
```

这不是两套互相矛盾的账，而是同一退款事件的消费归属投影和账户结算投影。

## 5. 金额、精度和舍入

- CNY 核心计算统一使用整数分；现有 Decimal 存储可兼容，但进入 resolver 前转最小货币单位。
- 预算、合计、账户余额和净资产禁止使用 `double`。`double` 只用于精确结果生成后的图表坐标。
- 输入超出币种精度时在输入边界按 `ROUND_HALF_UP` 明确舍入；中间步骤不反复舍入。
- 百分比从精确分子/分母计算，展示层统一小数位。分类展示和为 99.9% 或 100.1% 时不篡改某一分类凑 100%。
- 金额为负、为零、未知和不适用是不同状态。
- 预算周期/专项/分类/固定模板/存钱目标金额必须是非负整数最小单位；周期 `start < end` 且 `cycleDays > 0`。调整 delta 可负，但换算后的绝对 target 不得小于 0。

预算周期拆日统一为：

```text
q = totalMinor ~/ cycleDays
r = totalMinor % cycleDays
周期按日期升序，前 r 天各 q+1 分，其余 q 分
```

先对完整周期固定分配，再裁剪自然月、自然周、自定义窗口和 Widget。任何消费者不得重新分余数。

## 6. 事件真值表

| 事件 | 普通支出 | 普通收入 | 预算 | 账户现金流 | 净资产 |
|---|---:|---:|---:|---:|---:|
| 普通消费 | 增加 | 0 | 增加 | 结算日流出 | 账户减少 |
| 普通收入 | 0 | 增加 | 0 | 结算日流入 | 账户增加 |
| 部分/全部退款 | 冲减原消费期 | 0 | 冲减原消费期 | 到账日流入 | 到账后增加 |
| 报销到账 | 按附着原单退款处理 | 0 | 冲减原消费期 | 到账日流入 | 到账后增加 |
| 同币种账户间转账 | 0 | 0 | 0 | 一端流出、一端流入 | 两端都在同一净资产 scope 时为 0 |
| 不计收支账户变动 | 0 | 0 | 0 | 仍按结算日进出 | 随账户改变 |
| 物品购买 | 增加 | 0 | 增加 | 结算日流出 | 账户减、物品估值增 |
| 未含在订单内的购置费/维护/配件 | 增加 | 0 | 增加 | 结算日流出 | 账户减少；不自动抬估值 |
| 物品出售 | 0 | 0 | 0 | 结算日流入 | 账户增、物品价值归零 |
| 物品出售费 | 0 | 0 | 0 | 净额扣除或单独流出 | 作为处置成本减少净收益 |
| 权益收回 | 0 | 0 | 0 | 结算日流入 | 账户增、权益减 |
| 借款到账 | 0 | 0 | 0 | 结算日流入 | 账户增、负债增 |
| 偿还贷款本金 | 0 | 0 | 0 | 结算日流出 | 账户和负债同时减 |
| 利息/手续费 | 增加 | 0 | 增加 | 结算日流出 | 账户减少 |
| 储蓄账户间调拨 | 0 | 0 | 0 | 两端移动 | 全局为 0 |
| 估值变化 | 0 | 0 | 0 | 0 | 改变存量价值 |
| 余额校准 | 0 | 0 | 0 | 不算真实现金流 | 单列数据修正 |
| 归档/取消归档 | 0 | 0 | 0 | 0 | 不改变 |

长期不能只依赖一个 `excluded` 布尔值。领域策略至少要区分：

```text
countsInIncomeExpense
countsInBudget
countsInAccountMovement
countsInNetWorth
eventType
```

转账若从计入净资产账户流向不计入/范围外账户，已报告净资产会下降；反向则上升。变化解释为“范围内外资金移动”，不是消费、收入或投资收益。只有两端同在同一净资产 scope 才守恒为 0。

## 7. 交易家族与退款

每笔原始消费形成一个交易家族：

```text
familyNetExpense(cutoff) =
  originalAmount - sum(validAttachedRefunds known and effective by cutoff)
0 <= sum(validAttachedRefunds) <= originalAmount
periodNetExpense = sum(familyNetExpense where root.attribution_date in window)
```

规则：

1. 退款继承原单账本、币种和消费分类，但不强制继承付款账户。退款事件保存真实 `settlementAccountId` 与账户质量，默认原账户可改并在保存时确认；报销到账必须确认收款账户。
2. 原单不计收支时，退款也不进入收支和预算，但仍在到账日影响账户。
3. 部分退款不新增支出家族；多次退款分别保留到账事件。
4. 全额退款后净支出为 0，普通收入仍为 0。
5. legacy 独立负支出不能自动猜成退款；保留“历史冲账”或经过明确迁移。
6. AI 退款只有唯一强匹配且金额合法时才写入原交易家族；查询、歧义和超额不落账。
7. live 回看使用当前 cutoff，因此后来的退款会修正原消费期；已经生成的冻结报告保存生成时 cutoff/结果，不被未来退款静默改写，用户选择“重新生成”时创建新版本。

### 7.1 笔数

- `expenseCount`：窗口内 `familyNetExpense > 0` 的原始消费家族数。
- `purchaseOrderCount`：窗口内发生过的原始消费订单数；全额退款订单仍为 1。
- `incomeCount`：`attribution_date` 落在收入窗口、计入普通收入的 distinct 原始收入事件数。
- `refundEventCount`：`settled_at` 落在现金流窗口的真实退款事件数；一单三次退款为 3。存在 unknown settlement 时结果为 partial，并单列待确认数。
- `refundedPurchaseCount`：消费窗口内、截至 knowledgeCutoff 曾发生有效退款的 distinct 原始消费家族数，按 root `attribution_date` 归属。
- `averageExpense = netExpense / expenseCount`；分母为 0 时为不可计算，不显示 0。
- `averageIncome = income / incomeCount`；分母为 0 时同样不可计算。
- 分类笔数是该分类下具有正净分配额的 distinct 原单数。一单拆到多个分类时，各分类笔数不能相加冒充总笔数。

## 8. 收入、支出和收支结余

```text
income = sum(included ordinary income by attribution_date)
expense = sum(positive transaction-family net expense by attribution_date)
balanceOfIncomeExpense = income - expense
```

- 退款和报销冲减原支出，不进入普通收入。
- 转账、贷款本金、资产出售、权益收回、校准、估值变化和不计收支事件不进入普通收支。
- “收支结余”只是期间流量差，不是账户余额、可支配现金或净资产变化。
- 全额退款后的家族对支出金额贡献 0，不生成负消费。
- 分类占比的分母是正的期间净支出；期间净支出为 0 时占比不可计算。

## 9. 账户现金流与余额

### 9.1 现金流

- 账户现金流逐结算事件读取 `settled_at`，不能读取退款家族的原订单日。
- 转账保留两端 movement；单账户视图可见流出/流入，全局同币种净现金流为 0。
- 校准是余额修正，不是真实流入流出；现金流图单列或排除。
- 跨币种转账在没有两端金额、汇率和手续费前不得伪装为已完整支持。
- settlement 日期未知的 legacy 退款仍计入当前余额，但不被硬塞进某个历史现金流日；历史现金流和跨该事件的余额结果标 partial，并单列“到账日期待确认”。
- settlement 账户 unknown 时，分账户现金流和余额均为 partial，并单列“到账账户待确认”；不能把原付款账户显示成精确真相。单账户 checkpoint 只能锚定该账户自生效时点起的 target，不能把账户未知事件写进 covered 表或替其他候选账户消除 partial。必须先确认目标账户；checkpoint 仍不能补造历史分账户现金流。

### 9.2 余额和绝对校准锚点

```text
balance(asOf) =
  latestActiveCheckpoint.targetBalance
  + sum(account movements after checkpoint through asOf)
```

若此前无有效锚点：

```text
balance(asOf) = openingBalance
  + sum(account movements after openingEffectiveAt/sequence through asOf)
```

规则：

1. `calculated_before` 和 `delta_at_creation` 只作审计展示，不参与以后计算。
2. 后补锚点之前的历史流水不得改变锚点之后余额。
3. 撤销校准使原锚点失效并回退上一有效锚点重算，不写固定反向 delta。
4. 默认“现在核对”使用保存时精确时间；之后发生的同日流水继续累计。只有用户主动选择并看到“历史日终”时，才把所选日期解释为当地日终。
5. 同一时点用 `effective_at + sequence/id` 固定顺序。
6. 期初必须是精确 effective instant + sequence。新建账户默认保存时；历史日期输入明确“该日日初”或“前一日日终”。legacy 期初时点未知时，该点以前及依赖它的趋势不可用，不能向前补水平线。
7. 归档非零账户只隐藏列表，余额和净资产不变。
8. “现在核对”只能覆盖 settlement account 已确认且等于 checkpoint.account_id、但 settlement date unknown 的 legacy 事件，并保存 covered UUID。账户仍 unknown 的事件禁止进入任何单账户 covered 表；先确认目标账户。历史日终锚点不能自动吸收所有 unknown-date：逐项确认在锚点前/后，只覆盖确认在前者；未确认则该锚点及跨越查询为 partial。锚点后新录入的 unknown event 同样不能无条件相加或排除，直到确认日期/账户或再次做合法的现在核对。

## 10. 预算周期、执行和今日可用

### 10.1 周期与浏览窗口

- `本周期`：真实计划周期，如 7/15-8/14 或周一至周日。
- `自然月`：永远是 1 日至月末。
- `自然周`：按用户设置的周起始日至连续 7 天。
- `自定义`：只改变浏览窗口，不创建计划。
- 同一账本同一天最多一个 active primary 计划；重叠是 conflict，不静默求和。
- 一个自然月/周/自定义窗口可以先后覆盖多个不重叠 primary；结果必须返回 planSlices/cycleSlices，单一 current plan 只用于今天所在完整周期的日指标。
- 专项产品文案为“专项追踪”，不增加可花额度，不与 primary 相加。
- 首版预算计划固定 `currency_code=CNY`，只与 CNY 支出比较；非 CNY 支出被排除并使页面显示排除数量，不静默换汇或当作 0。
- 计划归档只停止未来生成并移出管理列表；已经发生的历史周期仍按 anchor/end/revision/override 解析。

月锚点若未来开放 29/30/31，短月落到月末，下个足月恢复原锚点。V2.1 首版仍建议限制 1 至 28 日。

### 10.2 Revision 与本周期调整

- 默认修改从下一完整周期生效，已结束周期不可静默改写。
- `replaceCycleTotal(X)`：把本周期完整总额改为 X。
- `adjustRemainingBy(delta)`：交互上追加/减少剩余额度，落库前转换为新的绝对周期总额。
- `setRemaining(X)`：换算为 `截至保存时已花 + X`，保存前展示结果。
- 禁止把修改日前旧日额与修改日后新日额拼接成用户没有输入的第三个总额。
- revision 管未来完整周期；当前周期例外写 cycle override。
- 保存 cycle override 时必须在事务中解析继承后的最终分类额度；若降低总额导致分类合计超额，阻止保存，直到用户调整或明确清空本周期分类额度，不能把 null 继承当安全或自动缩放。

### 10.3 核心金额

```text
planned = sum(stable daily allocations in view window)
spent = sum(in-budget family net expenses by attribution_date in window)
remaining = planned - spent
```

以上三个金额属于任意 view window。日指标另取“今天所在 active primary 的完整周期”，不得把自然月/周/自定义窗口的 `remaining` 与周期天数混算。

固定支出包含在总预算内，不得重复扣除。对当前完整周期，设单个 occurrence 的计划额为 `P`；只有 link 在 query cutoff 时仍满足账本 scope、币种、周期、未撤销和唯一性约束，才是 `exclusiveLinked`，其当前净额 `A=max(familyNet, 0)`；`H` 表示 root attribution_date 截至 query as-of 已发生：

```text
fixedActualSpentThroughNow(o) =
  !skipped && exclusiveLinked && H ? A : 0

fixedReserveNotYetInSpent(o) =
  skipped                                      -> 0
  no exclusive link                            -> P
  exclusive link && !H && no refund review     -> A
  exclusive link && !H && refund review        -> max(P, A)
  exclusive link &&  H && no refund review     -> 0
  exclusive link &&  H && refund review        -> max(P - A, 0)

fixedActualSpentThroughNow = sum(fixedActualSpentThroughNow(o))
fixedReserveNotYetInSpent = sum(fixedReserveNotYetInSpent(o))
effectiveFixedCost = fixedActualSpentThroughNow + fixedReserveNotYetInSpent

cycleRemaining = cycleTotal - totalSpentThroughNow
discretionaryRemaining = cycleRemaining - fixedReserveNotYetInSpent
                       = cycleTotal - variableSpentThroughNow - effectiveFixedCost
```

`variableSpentThroughNow = totalSpentThroughNow - fixedActualSpentThroughNow`，且 beforeToday/today 两个 variable 字段也必须排除对应 fixed family。`effectiveFixedCost` 只能与 variable spent 配套；从已经减过 total spent 的 `cycleRemaining` 再减整个 effective 值会把 fixed actual 扣两次。

同一 occurrence 的 actual 与 reserve 必须按上表互斥。已逾期但未匹配的承诺没有 exclusive link，继续预留 `P`；对外 MetricResult 为 `status=partial, reasons=[overdueCommitment(...)]`。只有用户确认 skipped 后才释放额度。

固定支出模板属于 revision；每个周期生成独立 occurrence，保存 `planned_cents / due_date / resolution_status / review_reason`。七月的 matched/skipped 不污染八月。首版同一 plan 下一个交易家族只能完整匹配一个 occurrence，且 root attribution_date、账本范围和币种必须落在该 occurrence 周期；结算日可以更晚。实际金额始终从交易家族净额派生，退款后同步重算，不能复制漂移的 actual 值。skipped 必须清空 exclusive link，状态、link 和审计事件同事务更新。

`matched_future` 与 `overdue` 是 resolver 按 query as-of 派生的时间状态，不依赖 App 跨午夜改写 DB。提前匹配且 root attribution_date 仍在未来时，family 尚未进入 `totalSpentThroughNow`，其净额 `A` 继续进入 fixed reserve；到归属日才由 fixed actual spent 接管。不能因提前匹配释放未来房租。

已匹配家族部分退款后 occurrence 转 `requires_review(reason=refund_after_match)`，MetricResult 为 `partial + refundedMatchedCommitment`；归属已发生时 actual 为 A、差额 `max(P-A,0)` 继续预留，归属未发生时预留 `max(P,A)`，因此切换归属日前后 `totalSpent + reserve` 连续。全额退款/扣款撤销恢复整笔 P。用户确认折扣、改匹配替代账单或跳过剩余后才能解除，不允许 `matched + familyNet=0` 仍释放额度。

`requires_review` 必须带原因。歧义候选在用户确认前不得建立 exclusive link：候选交易仍是 variable spent，occurrence 同时保留 P 并返回 partial；这是“是否已经履约未知”的保守结果，不得伪装成精确可用额。确认时在同一事务中建立唯一匹配，避免短暂双预留。

`invalid_scope / amount_conflict` 不能沿用旧 link。检测到 scope、币种、周期、撤销、唯一性或金额约束失效时，事务内清空 link 并写 requires_review；该 occurrence 按未匹配计算 `fixedActual=0 / reserve=P`，原交易只在其真实 scope 保持 variable spent，MetricResult 为 partial。只有 `refund_after_match` 可以在复核期间保留当前有效 link 并使用 refund gap 公式。

### 10.4 两个日指标不能混名

两个日指标只对**今天所在的 active primary 完整周期**计算，`cycleTotal`、variable spent、fixed cost、remaining days 必须属于同一个 cycle。历史周期、未来周期、无 active primary 或纯自然月/周结果本身均为 `notApplicable`；页面可以另挂当前周期状态，但不能混入 view 主卡公式。

```text
todayRemainingAllowance =
  (cycleTotal - effectiveFixedCost - variableSpentBeforeToday)
  / remainingDaysIncludingToday
  - variableSpentToday

remainingDailyReference =
  discretionaryRemaining / remainingDaysIncludingToday
```

- 上述除法在 resolver 内按最小货币单位对剩余日期做稳定余数分配，今天读取对应日期的整数分；不得先转 `double` 再四舍五入。
- `todayRemainingAllowance` 回答“按当前均匀预算方法，今天还可以安排多少”。
- `remainingDailyReference` 回答“从现在起把剩余可自由安排额平均到余下日期，每天约多少”。
- 没有结构化未来固定支出时，只能写“按预算平均今日可用/日均参考”，不能写“安全可花”。
- 贷款本金和计划储蓄不是消费预算支出，但会占用现金；未来“安全可花现金”必须在单独流动性层预留，不能塞回消费预算重复扣除。
- 时间进度只与可变支出或具有到期曲线的计划比较。没有曲线时只并列显示，不输出“花得过快”的价值判断。

```text
timeProgress = elapsedCalendarDays / cycleCalendarDays
```

历史周期为 100%，未来周期为 0%，当前日计入 elapsed。若未来实现非均匀计划曲线，另给 `expectedSpendProgress`，不能偷换 `timeProgress` 的含义。

### 10.5 Legacy 预算迁移

- 迁移前 adapter 必须复现旧 `book_id=null`、重叠区间、一次性覆盖和同级优先规则，并生成逐日 golden。
- null 只映射到代码证据能证明的真实默认/总账本 ID；歧义 scope 保留 legacy 待确认。
- 旧循环计划转 plan/revision，一次性或周期内胜出片段转 cycle override/legacy slice，不生成重叠 primary。
- 迁移前后每日期、账本、分类 planned minor units 必须一致；无法等价者继续只读 legacy，不静默改历史。

## 11. 资产、负债和净资产

互斥集合：

```text
资金资产 = 账户正余额 + 投资余额 + 权益资产
总资产 = 资金资产 + 明确计入的物品可变现净估值
资金净值 = 资金资产 - 总负债
净资产 = 总资产 - 总负债
```

锁定示例：

```text
流动资金 42,000 + 投资 96,000 + 权益 52,000 = 资金资产 190,000
总资产 = 190,000 + 物品 78,400 = 268,400
资金净值 = 190,000 - 负债 51,600 = 138,400
净资产 = 268,400 - 51,600 = 216,800
```

规则：

1. 投资账户只能进入一个桶，不能同时算账户正余额和投资余额。
2. 负债账户余额和 profile 本金只能有一个真相源；legacy_hybrid 在迁移完成前明确标记。
3. 非零资产/负债不会因为归档而从合计消失。
4. `include_in_net_worth` 的改变是口径变化，不是收益或损失。
5. 正余额负债可能是溢缴款、可用额度、符号错误或独立资产，不能自动推荐拆资产。
6. 资产总览是用户私有全局域，不随当前抽屉账本变化；共享成员只能看到明确共享对象。

## 12. 物品成本、估值和处置

### 12.1 成本基数

```text
acquisitionGross = source == transactionAllocations
  ? sum(allocatedGross)
  : manualGross
acquisitionRefund = source == transactionAllocations
  ? sum(allocatedRefund)
  : manualRefund
netAcquisitionCost = acquisitionGross - acquisitionRefund + nonDuplicatedAcquisitionFees
cumulativeHoldingInvestment =
  netAcquisitionCost + maintenance + insurance + accessories

netLiquidationEstimate = max(0, estimatedSalePrice - estimatedSaleFees)
actualNetSaleProceeds = actualSalePrice - actualSaleFees
finalNetCost = cumulativeHoldingInvestment - actualNetSaleProceeds
```

`acquisitionCostSource` 必须在 `transactionAllocations` 与 `manual` 中二选一。手动补录成本直接替代公式中的 allocated gross/refund 来源；后来关联真实账单时由用户确认用分配额替换手动成本，不能两边相加。`purchase_price` 若保留只作当前来源缓存。

手动来源满足 `manualGross >= 0`、`0 <= manualRefund <= manualGross`，购置费/维护/保险/配件金额非负；违反约束为 conflict，不参与累计成本。

```text
dailyHoldingInvestment = cumulativeHoldingInvestment / heldDays
retentionRate = netLiquidationEstimate / netAcquisitionCost
dailyValueChange =
  (netLiquidationEstimate - netAcquisitionCost) / heldDays
```

- `heldDays = max(1, localDate(end) - localDate(purchase) + 1)`；持有中 end=today，终止后 end=terminal event date。购买当天出售/退货为 1 天；不以毫秒/24h 计算。购买日未知或 end 早于 purchase 时，日均指标 unavailable。
- 退款只在净购置成本扣一次。
- 维护支出进入消费和累计持有投入，但不自动抬高估值。
- 购置费已含在原订单毛额时不得另加；未包含时作为普通支出/预算和购置成本各投影一次。出售费从净到账扣除或作为 `asset_sale_fee` 单独账户移动，不进入普通消费/预算，最终净成本只扣净出售收入一次。
- `netAcquisitionCost <= 0`、估值未知或币种不可折算时，保值率不可计算。
- 最终净成本小于 0 时展示实现收益，不展示负成本。
- 预计处置费高于预计售价时，资产估值下限为 0；潜在处置费不作为负资产，形成真实义务后才写账户流出或负债。实际净出售收入可以为负（付费处置），并相应提高最终净成本。
- 日均持有投入随时间自然下降，不等于利用率、收益或“买值了”；不能仅因时间过去触发奖励。
- 一件物品的多笔购置、维护、退款和出售首版限制同币种。出现异币且无带来源汇率时按原币分项，累计投入、保值率和最终成本为 unavailable，禁止直接相加。

### 12.2 估值

- 某日价值取 `valued_at <= asOf` 的最新未撤销有效估值。
- 补录旧估值不能覆盖日期更晚的估值。
- 估值新鲜度按 `valued_at` 和 source 判断，不取资产普通 `updated_at`。
- 未知估值不等于 0；出售、退货或报废后的有效归零才是真 0。
- 过期估值可保留金额，但必须显示日期和 stale 状态。
- as-of 时点存在未撤销经济终止事件时，终止状态优先于估值查询；生效日晚于终止的普通估值标 inactive/conflict，不能复活资产。撤销终止后才重新解析保留的估值记录。

### 12.3 账单分配和生命周期

- 一账多物保存每件物品的 allocated gross/refund；所有有效分配净额不得超过订单净额。
- 每条分配及订单合计同时满足 `0 <= allocatedRefund <= allocatedGross`、`sum gross <= order gross`、`sum refund <= valid refunds`；未分配余额允许存在但降低 costQuality。
- 存在待分配退款时，相关物品 `costQuality=pendingRefundAllocation`：日均只显示“按已知成本”与待分配提示，保值率和最终成本为 unavailable；确认分配后再恢复精确值。
- 多账一物只累计各账单分配额；分期还款本金不重复形成成本。
- 重复关联被唯一约束拦截；部分退款不能唯一分配时由用户确认。
- 物品终止条件按物品分配额判断：该物品有效净购置分配被全额退回且用户确认已退货即可终止，不要求一张多物订单整体全退。
- `economic_status` 表示 owned/sold/returned/scrapped/lost/gifted。
- `visibility_status` 表示 active/archived，只影响列表。
- 出售后再收到原购买退款：重算净购置成本和最终净成本，但不自动把 sold 改回 owned。
- 旧 archived 物品只能按现有代码可达前态恢复为 owned + usage unknown；旧 archived 权益不能套同一规则。权益先按最后未撤销经济事件和 recovery 台账恢复 lost/recovered，`0 < remaining < original` 恢复 partial_recovered，`remaining=original` 且无冲突恢复 active；`remaining=0` 无法区分收回/损失或证据冲突时为 economic unknown + needsReview。两类迁移均保持 visibility archived 和迁移前 include/合计，取消归档只改 visibility。

## 13. 计算快照与可信检查点

### 13.1 computed snapshot

- 是可重算缓存，不是用户确认事实。
- 保存 `as_of`、`cause_set`、`scope_version`、`calculation_version`、币种覆盖、缺失估值数和质量状态。
- 普通记账、退款、转账、估值、范围调整等都可触发重算。
- 补录历史事件时，从最早受影响时点失效/重算，不能只在今天制造跳变。
- 传入历史日期必须真正计算历史状态，禁止把今天的 current breakdown 写到过去。

### 13.2 verified checkpoint

- 只有用户明确核对并保存覆盖范围时成立。
- 单账户校准只验证该账户，全局状态只能标“部分核对”。
- 全局完整核对保存账户、负债、权益、物品估值、币种和口径版本覆盖。
- 只有两次覆盖范围、币种和计算版本一致，才显示“较上次完整核对”。
- 当前日未结束的自动结果标 provisional。

全局 verified checkpoint 必须是不可变 header + items：header 冻结 `as_of / knowledgeCutoff / scopeVersion / calculationVersion / currency coverage / total assets / liabilities / net worth / status`；items 冻结每个对象 UUID、确认金额、币种、估值时点/来源和质量。后补、删除或修改估值不重写旧行；纠错新建 superseding checkpoint 或标 revoked。任何“较上次完整核对”都读取两份冻结证据，不能用当前数据回算旧 checkpoint。

完整资格要求 items 覆盖 as-of 时所有应计对象，且每个存量余额/估值可确认。计入范围 needsReview、必需币种无法折算或锚点后新 unknown movement 使当前存量不确定时才 partial；已被当前余额锚点吸收的 legacy unknown settlement、待分配成本等流量/成本缺口只作 lineage warning，只要当前余额/估值已独立确认就不阻止完整核对。过期估值需明确接受其日期。比较要求相同 scope 政策、币种覆盖和 calculationVersion；正常对象新增/处置允许 UUID 集合变化并作为变化来源解释，漏项或口径变化则取消直接涨跌率。

资产变化解释至少区分：真实账户事件、估值变化、校准/补录、范围/迁移。最后两类不能包装成经济收益。

## 14. 比较窗口

所有卡片消费同一个 `ComparisonWindowResult`：

| 当前窗口 | 默认比较窗口 |
|---|---|
| 未结束自然月 | 当前月与上月相同可比较天数 |
| 已结束自然月 | 完整上月 |
| 未结束自然周 | 上周相同已过日序 |
| 已结束自然周 | 完整上周 |
| 未结束预算周期 | 当前与上周期相同可比较日序 |
| 已结束预算周期 | 完整上周期 |
| 未结束自然年 | 去年截至同月同日；2/29 合法裁剪 |
| 自定义 N 天 | 紧邻此前 N 天 |

规则：

- 两边必须使用相同账本范围、币种范围、分类版本和计算版本。
- “同期”必须等长：`N = min(当前已过日数, 上期总日数)`，两边都取各自前 N 个自然日。当前为 31 日而上月只有 30 天时，比较当前前 30 天与上月 30 天，并明确标“前30天”；主卡截至今天的总额与可比增幅是两个字段，不能拿 31 天直接除 30 天。
- 范围或口径不同显示“口径已变化”，不计算误导性涨跌率。
- 上期为 0、本期大于 0 时显示“新增 ¥X”，不显示无穷百分比。
- 净资产为负或跨零时默认显示金额差，不显示失真增长率。
- 未来日期是 `null`，不是 0。

## 15. 分类、排行、占比和历史变化

- 实时统计按稳定 category key 聚合，不按可变中文名聚合。
- 重命名只改变标签；合并/重挂会改变实时历史分组并提升 `classificationVersion`。
- 已生成月报、导出和 verified checkpoint 冻结当时的分类 key、名称、层级和版本。
- 分类删除/合并不能让金额消失；无法映射时进入“历史分类/其他”。
- 排行按精确金额排序，同额使用稳定 key 排序，避免每次刷新跳位。
- 分类占比只使用正净支出；占比为 0 和不可计算分开。

## 16. 账本范围与共享权限

- 普通统计必须携带明确 `scopeBookIds`；“总账本”不能长期用 `null` 同时表示全部、当前或兜底。
- 实时总账本统计可按当前 `includeInTotal` 动态回看，但 UI 标“按当前总账本范围”。
- 已生成报告和 verified checkpoint 冻结当时账本集合与 scopeVersion。
- 已关闭预算周期必须冻结其账本范围，不能因后来退出总账本静默改写历史执行率。
- 私有全局资产不随账本切换。共享账本成员不能看到未明确共享的个人账户、房贷、权益和物品。
- 净资产 `scopeVersion` 表示计入政策和用户 include 设置版本；正常新建、买入、出售、结清对象不提升 scopeVersion，而由 checkpoint items 增减解释。只有范围政策、include 开关或权限口径变化才提升。

## 17. 币种与不可折算数据

- 无汇率时只允许单币种精确统计，禁止静默相加。
- CNY 卡只汇总 CNY，并写明排除的币种和对象数。
- 只有外币时展示原币结果，不能显示 `¥0`。
- 不允许在无统一币种时画分类占比或净资产总计。
- 未来汇率必须保存 rate、base/quote、effective_at、source 和状态；历史报告使用当时锁定口径，不拿今天汇率静默重写。

## 18. 零值、未知值和数据质量

只有输入完整且数学结果确实为零才能显示 0：

| 状态 | UI 展示 |
|---|---|
| 可计算且为零 | `¥0.00` |
| 无预算 | `未设置` |
| 分母为零 | `--`，并说明暂无可比较数据 |
| 缺估值 | 已知金额 + “N 项待估值”，status=partial |
| 无汇率 | 分币种列出，不给人民币总数 |
| 无历史锚点 | “从开始记录后”，不补伪历史 |
| 估值过期 | 保留金额并显示估值日期/已过期 |
| 结算日期未知 | 当前余额包含金额；历史现金流标 partial，并提示待确认到账日 |
| 范围或算法变化 | “口径已变化”，不直接比较 |
| resolver 冲突 | 阻止误导结果并给修复入口 |

## 19. UI 文案约束

- `收支结余` 不得写成 `账户余额` 或 `净资产变化`。
- 未预留固定支出、还本和储蓄时，不得使用“安全可花”。
- 自动快照不得写“已核对”或“可信”；单账户核对不得升级成全局完整核对。
- 日均持有花费不得写“利用率”“真实折旧”或自动判断“买值了”。
- 退款到账不得出现在普通收入排行榜。
- 未知估值、缺汇率和范围不完整不得使用看似精确的总数。
- 图表必须有文字摘要；读屏至少读出窗口、范围、金额、趋势状态和数据不完整原因。

## 20. 单一计算入口与消费者

建议最终形成四个领域投影：

```text
ConsumptionProjection       // 收支、分类、退款家族、笔数
AccountMovementProjection   // 结算现金流与账户余额
BudgetWindowResolver        // 计划、周期切片、执行与日指标
NetWorthAsOfResolver        // 某时点资产、负债、估值和核对质量
```

消费者迁移门禁：

| 消费者 | 禁止直接读取 |
|---|---|
| 主页大卡 | 旧 monthlyBudget、裸 records 自算退款 |
| 统计页 | 各卡分别构造上期窗口 |
| Widget | 旧月预算和页面专属快照 |
| 月/周/年报 | 当前配置冒充历史配置 |
| AI 查询/洞察 | 毛额原单 + 散退款行、未知状态当 0 |
| 快速记账 | 独立复制预算和分类统计公式 |

迁移期间允许旧入口适配新 resolver，不允许新 UI 再依赖旧公式。

## 21. 最低反例验收矩阵

1. 普通收入、普通支出和不计收支账户变动分别符合真值表。
2. 同币种转账两端都在同一净资产 scope 时收支和净资产变化均为 0；included 与 excluded 账户互转只改变已报告 scope，并标范围内外移动。
3. 六月订单七月部分退款：六月消费/预算冲回，七月现金流入，七月普通收入为 0。
4. 全额退款：净支出 0、支出笔数 0、消费订单数 1、退款事件数正确。
5. 一笔原单分三次退款，合计不得超过原额。
6. 不计收支原单退款仍到账，但不进入收支和预算。
7. 购买计入净资产的物品，账户、预算、估值和净资产符合守恒示例。
8. 出售物品：现金增加、普通收入不变、物品价值归零。
9. 借款到账、还本金、利息/手续费分别符合真值表。
10. 校准后补录锚点前旧流水，锚点后余额不变。
11. 连续两个校准，撤销第二个后回退第一个；撤销中间锚点也可重算。
12. 同日流水、校准和撤销有稳定顺序。
13. 15 日锚定月周期在自然月视图由两个周期切片组成。
14. 周预算跨月切片后，两月逐分相加仍等于完整周额度。
15. 3,000 元不能整除周期天数时，所有消费者逐分一致。
16. 月中 replace total、adjust remaining 和 set remaining 得到不同且可解释的绝对周期总额。
17. 同账本 primary 重叠阻止保存；专项重叠不生成重复合计。
18. 月初固定房租不触发错误“消费过快”；预留与实际匹配只扣一次。
19. 当前月比较上月同期，历史完整月比较完整上月。
20. 只有外币、CNY+外币和缺汇率分别展示正确质量状态。
21. 分类重命名、重挂、合并后实时统计重算，冻结报告保持原版本。
22. 缺估值和真实零估值分开；补录旧估值不覆盖新估值。
23. 归档非零账户/物品/权益后净资产逐分不变。
24. 一张订单创建两个物品时分配不超净额；多笔分期不重复成本。
25. 首版同一专用账户绑定第二个 active 目标时阻止保存；未来分配台账在账户消费后可能 overallocated，必须报警但不拦记账或静默改目标。
26. 补录旧流水只重算受影响区间，不在今天制造虚假收益。
27. computed snapshot、部分核对和完整 checkpoint 文案与比较资格不同。
28. 共享账本成员看不到未明确共享的个人资产和负债。
29. 320dp、200% 字体、读屏和减少动画下仍能读懂核心指标与错误状态。
30. 同一 MetricQuery 在主页、统计、预算、Widget、报告和 AI 中金额、笔数、状态完全一致。
31. 迁移前附着退款没有真实到账日时，不伪造日期；当前余额正确，消费归属正确，历史现金流明确 partial。
32. 一张多物订单只全退其中一件时，仅终止该物品，其他物品成本和状态不变。
33. 上午 10:00 现在核对余额 100，下午 15:00 支出 20 后余额为 80；显式历史日终才采用日终锚点。
34. unknown-date 旧退款存在后做现在核对，锚点覆盖它且余额不重复；历史日终锚点未确认前后关系时保持 partial。
35. 逾期未匹配固定承诺在 today allowance 和 daily reference 中都继续预留，跳过后同步释放。
36. 提前匹配未来归属房租时，在归属日前仍作为 unresolved；到期后才由 spent 接管。
37. 已匹配固定支出部分退款后差额待确认，全额退款恢复整笔预留，不保持零净额 matched。
38. 同一固定模板七月/八月 occurrence 独立；同一交易家族不能释放两个承诺，跨周期匹配被拒绝。
39. 降低本周期 target 导致继承分类合计超额时阻止保存，不自动缩放或把 null 继承当安全。
40. 预算计划归档后历史周期不变，未来不再生成；首版 CNY 预算明确排除非 CNY 支出。
41. legacy null book、重叠循环和一次性覆盖迁移前后逐日/逐分一致，歧义留 legacy 待确认。
42. 7/31 对 6 月比较时，两边均取前 30 天并标“前30天”；主卡仍可展示 7/31 截至今天总额。
43. 六月消费页 refundedPurchaseCount 按原单归属；七月 cash-flow refundEventCount 按到账日；unknown settlement 使后者 partial。incomeCount 按收入归属日。
44. 6/30 冻结报告显示当时支出 100；7/5 退款后 live 回看六月为 70，旧报告仍为 100，重新生成产生新版本。
45. 信用卡消费、工资卡收到报销：消费仍冲减原分类，现金流进入工资卡，不能强制回原付款账户。
46. verified checkpoint 创建后修改估值/补录不改旧 header/items；新对象允许参与下一次比较，漏项或 scope 口径变化取消直接涨跌率。
47. 手动成本 1,000 后补链同一笔 1,000 账单，净购置成本仍为 1,000；manual 与 allocations 互斥。
48. 购买当天出售/退货 heldDays=1；后补早于新估值的终止事件优先，资产不被后续估值复活。
49. 多物分配分别校验 gross/refund/net；未分配退款使 costQuality 降级，保值率和最终成本不显示伪精确值。
50. 一件物品异币购置/维护/出售且无汇率时分项展示，综合成本 unavailable。
51. 新账户期初使用精确时点；历史“日日初/前一日日终”边界下同日第一笔流水不漏算或重复。
52. 设备旅行切换时区不会改变已记 attribution/预算周期；修改 business timezone 被标为口径变化。
53. 出售价 6,100、出售费 100、净到账 6,000 时账户/估值/净资产守恒；费用不重复进入普通支出和最终成本。
54. 预计处置费高于售价时资产估值为 0 而非负数；实际付费处置可产生账户流出并提高最终净成本。
55. 旧商家退款的原账户迁为 legacy_assumed，旧报销账户迁为 unknown；确认前分账户余额/现金流为 partial，不能显示精确原账户。
56. 旧 archived 权益有完整收回/损失事件时恢复 recovered/lost，有部分收回时恢复 partial_recovered；remaining=0 且无事件证据时为 unknown，迁移前后净资产逐分不变。
57. `P=1000/A=900` 的 matched future 在归属日前 reserve=900、actual=0，归属后 reserve=0、actual=900；部分退款使 `totalSpent+reserve` 在用户确认义务减少前保持连续，任何路径都不重复扣 fixed actual。
58. linked family 后来变为 scope/币种/撤销/金额冲突时，link 原子清除，fixed actual=0、reserve=P，交易只在真实 scope 作 variable spent，结果为 partial。
59. 旧报销到账账户 unknown 时，原付款账户 checkpoint 不得覆盖该事件；先确认进入工资卡后，才允许工资卡的“现在核对”覆盖其 unknown date。
60. `[TXN]` 100 元待报销支出已退款 30 元时，待报销金额=70、笔数=1；全额退款后金额=0、笔数=0。
61. `[TXN]` 搜索和分类下钻同时遇到全退 family 与 legacy 独立负支出时，净支出、支出笔数、订单数和结果行数分别可解释，不能互相冒充。
62. `[STAT]` 本月只过 10 天、上月 31 天时，主卡仍展示本月截至今天总额；涨跌只比较两边前 10 天。上期为 0、本期为正时显示“新增 ¥X”。
63. `[STAT]` 过去 6 月含 2 个真实零支出月、1 个追踪前缺数据月和 3 个正支出月时，同期平均只排除缺数据月，真实零进入分母；页面与 Widget 使用相同最小样本数。
64. `[STAT/BUD]` 支出 120、收入 100、预算 200 时，结果是收支负结余 20、预算尚余 80；任何卡不得把前者写成“预算超支”。
65. `[FX]` 同时存在 CNY 与 USD 账户、实物、权益和负债时，任何 `¥总资产/组余额/总负债` 都不得直接跨币种相加；无汇率时返回分币种或 partial。
66. `[NW]` 切换当前账本时，全局净资产不变；若同屏保留“本月收支净额”，必须明确标出它的当前账本 scope，且不得解释为净资产变化。
67. `[NW]` 传入三个月前日期创建快照时，必须计算三个月前 as-of；若做不到则拒绝或明确保存“今天的当前快照”，不能给当前值贴历史日期。
68. `[GOAL]` 手工向存钱目标存入 100 元只改变 saved/remaining/progress；当前未绑定账户模型下，账户余额、收支、现金流和净资产均不改变。
69. `[REPORT]` 零笔支出时，笔均支出和分类占比为 notApplicable；报告、AI 上下文和 UI 均不得写成 `¥0` 或 `0%`。
70. `[AI]` 查询结果同时含收入、支出、转账、全退订单和退款事件时，分别输出 income event、positive expense family、transfer、purchase order、refund event 数，不使用含义不明的“共 X 笔”。
71. `[OPS]` 导入 100 原始行、跳过 10 无效、自动归类 50、剩 8 个商户组、插入 70、挂回 5 个退款、跳过 15 个重复时，各计数独立守恒，不能把组数或退款挂回数加入普通账单笔数。
72. `[OPS]` 备份页显示 3 份、本地磁盘另有迁移保护文件时，UI 的“3 份”只表示展示备份；分类子类数、标签使用数、记忆数、定时生成次数同样不得进入任何财务合计。
73. `[TIME]` 今天为 7/13、存在归属日 7/20 的未来交易时，“截至今天”支出、预算已用、趋势、Widget 和报告都不得提前计入；完整未来计划只能进入 forecast/reserve。
74. `[WIDGET]` 同一份快照的 Flutter 图片卡与原生 JSON 对历史样本门槛、当前月 full/same-progress、分类笔数和预算状态给出完全相同的结构化值。
75. `[OPS]` 自动记账候选已由幂等 occurrence 命中旧流水时，显示“已存在/已处理”而不是“新增 1 笔”；批量第 3 项失败时分别报告新增、已存在、失败数。
76. `[OPS]` 定时规则 generated=5、用户删除 2 条流水后，生成次数仍为 5、现存流水数为 3；两者必须使用不同名称，切换账本也不得把 scope 偷换。
77. `[ASSET]` 资产导入处理同一 UUID 时，inserted、updated、skipped/conflict 分开；总处理数不得包装成“新增资产数”。

## 22. 口径版本与变更流程

每次口径变化必须：

1. 提升 `calculationVersion`；分类结构变化另提升 `classificationVersion`。
2. 写明影响的指标、历史窗口、快照、报告和迁移策略。
3. 决定历史是动态重算、冻结旧版本，还是显示“口径已变化”；禁止无说明混用。
4. 增加至少一个会让旧公式出错的反例测试。
5. 逐个迁移主页、预算、统计、Widget、报告和 AI 消费者。
6. 更新 V2.1、交接文档和 [[肥喵记账App开发笔记]]。

## 23. 当前实现差距

**CURRENT GAP：**以下是实施时必须处理的已知差距，不代表本轮已经改代码。

- `lib/core/models/transaction_record.dart`：领域记录只有一个业务日期。
- `lib/data/app_repository.dart`：附着退款把日期写成原订单日，消费净额正确但历史现金流无法正确表达；存量退款真实到账日不可恢复，迁移必须允许 unknown。
- `lib/core/ledger/ledger_policy.dart`：退款净额投影适合消费统计，缺少逐结算事件账户投影。
- `lib/core/budget/budget_period.dart`：旧自然月与 double 分摊需要由新 resolver 取代。
- `lib/core/budget/budget_engine.dart`：仍是自然月专用，今日可用缺少未来承诺与数据质量状态。
- `lib/core/statistics/statistics_engine.dart`：单日期、直接记录 count 和 double 占比不能覆盖本标准。
- `lib/core/statistics/statistics_engine.dart` 与 `BudgetEngine`：没有统一 currency scope 或截至今天 cutoff；不同币种可被直接相加，未来日期交易也可能提前进入“本月截至今日”。
- `lib/views/transactions/transaction_list_view.dart` 与 `lib/views/transactions/reimburse_view.dart`：待报销金额和部分日小计仍直接累加原额；公共主页日卡却使用退款后用户净额。同一账单 family 在不同列表会得到不同小计。
- `lib/views/search/search_view.dart` 与 `lib/views/statistics/category_txns_view.dart`：搜索、分类下钻的金额已部分净额化，但笔数仍可能把全额退款 root 或 legacy 负支出当作正支出笔数；搜索金额筛选在用户净额为 0 时回退原额，使全退订单仍可按原价命中，必须明确这是查原订单还是查净消费。
- `lib/views/statistics/statistics_view.dart`、`monthly_report_view.dart` 与 `core/statistics/spending_insights.dart`：当前月多处仍用截至今天金额对比完整上月；上期为 0 时部分徽章直接隐藏，未按“新增金额”表达。
- `lib/views/statistics/monthly_report_view.dart`：历史月仍可能读取“当前月才有预算”的旧路径；最大单笔与主合计对 legacy 负支出的过滤也不一致。
- `lib/widgets/monthly_pace_card.dart` 与 `lib/core/widgets/widget_snapshot_service.dart`：历史 6 月同期平均只纳入正支出月份，真实 0 月与缺数据混在一起；页面 1 个样本可显示，Widget 至少 2 个样本，门槛不一致。
- `lib/views/statistics/statistics_view.dart` 的近 12 月卡：支出大于收入的部分标为“超支”，把负结余与预算超支混成同一个词。
- `lib/core/ai/report_generation_service.dart`、`lib/views/reports/report_views.dart` 和部分 AI summary：无支出时仍把笔均/占比格式化为 0；部分“X 笔”混合可见账单、收入、转账和全退订单。
- AI 报告只冻结 book id，未冻结总账本成员集合、分类版本、币种范围和计算版本；LLM 输出也尚无结构化数字回验，因此模型文字不能被当成新的真值源。
- `lib/views/home/ai_chat_panel.dart` 与 `lib/data/app_repository.dart` 的常用分类/金额启发式：部分路径按原始行频次或金额取样，尚未全部统一为正净额 family 并排除退款子行与不计收支行。
- `lib/core/widgets/widget_snapshot_service.dart`：仍有旧月预算读取路径，页面与 Widget 尚未共同消费版本化预算 resolver。
- `lib/core/widgets/widget_snapshot_service.dart` 与 `widgets/monthly_pace_card.dart`：除样本门槛外，当前月 full/same-progress 值也不一致；分类 Top 3 笔数继承会计入全退 family 的旧 count。
- `lib/views/settings/accounts_view.dart`：全局净资产与当前账本“本月收支净额”并排；计入项分子和全部项分母 scope 不同；账户类型组、实物组和权益组存在原币直接相加后用人民币展示的路径。
- `lib/data/app_repository.dart` 的负债汇总仍是“负账户余额优先、否则 profile 本金”的 legacy hybrid，且 profile 路径需阻止非 CNY 本金进入 CNY 总负债。
- `lib/data/app_repository.dart` 的净资产快照：传历史日期仍计算当前 breakdown，且缺少类型、原因、质量、口径版本和历史 as-of 重算合同。
- 当前物品/权益归档会关闭 `include_in_net_worth`，与“归档只隐藏”的标准冲突；资产列表的组数、组额和净资产计入数也尚未共享同一 scope 结果。
- `lib/views/savings/savings_goals_view.dart`：目标进度是手工 ledger，尚未连接真实账户、调拨和净资产；超额存入需要独立 `overfunded`，不能只显示负剩余。
- 导入、自动/定时记账、分类/标签/记忆/备份等 `O-*` 尚无统一类型；多个页面都使用“笔/条/个/份”，但没有机器可校验的单位与守恒关系。
- 自动记账保存 toast 可能把幂等命中旧 occurrence 计作“记下”；中途失败缺新增/已存在/失败拆分。定时记账的 generated count 与现存流水数、全账本规则与当前账本明细也容易混名。
- 资产导入的“处理数”混合新增、更新与冲突忽略；普通导出 transaction row count 包含退款子行，均不能冒充用户可见 family 数。

## 24. 来源台账

统一核对日期：2026-07-13。

| source_id | 来源 | 类型 | 支持范围 | 状态 |
|---|---|---|---|---|
| S001 | `BUDGET_ASSET_UX_PLAN_V2_1_2026-07-12.md` | local / product decision | 预算、资产、成本、校准、快照、归档和权限决策 | verified |
| S002 | 当前 Flutter/SQLite 代码及测试 | local / primary | 主页、账单、搜索、预算、统计、Widget、报告/AI、账户资产、目标及全部主要工作流计数现状 | verified；2026-07-13 全量消费者审计，实现会继续变化 |
| S003 | `BUDGET_ASSET_UX_PLAN_V2_2026-07-12.md` 第 15 节来源台账 | official + local synthesis | 有数、MoneyWiz、Monarch、YNAB、Actual 等竞品证据与边界 | inherited；具体链接状态见原台账 |

本文的公式和真值表属于肥喵 V2.1 的 **DECISION**，不冒充竞品原始公式。证券持仓收益、自动汇率、税务、套装部分出售和复杂复式记账仍为 **UNKNOWN / DEFERRED**，不得从本标准外推为已支持。
