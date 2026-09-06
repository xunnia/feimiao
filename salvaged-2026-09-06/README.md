# 抢救出的孤本代码（2026-09-06）

> 目录结构：
> - `ios-app/` —— 来自 `.tmp/ios-development/`，24 个**从未进入任何 git 分支**的文件（见下文）
> - `from-old-branches/` —— 来自即将删除的老线分支，5 个主线没有的文件（见文末）
> - `from-worktree-elegant-panini/` —— 安卓 AI 多账号／多模型／任务分配功能，11 个文件、约 85 KB，**从未提交**
> - `from-worktree-ios-batch15/` —— FeiMiao 那套 iOS 实现的收尾改动，6 个文件 + 1 份参考文档，**从未提交**
>
> ⚠️ **另有一条完整的提交历史被救回，不在本目录，而在分支 `rescue/ios-p1-2026-08-31`。**
> 它有 14 个主线没有的提交（iOS 预算 V2、资产退款分摊、借贷往来、房贷分期向导、
> 权益详情、备份恢复加固……），原本只被 `.tmp/ios-development` 这个 worktree 的
> detached HEAD 吊着，任何分支都不指向它。删掉那个 worktree 后 git 会把它当垃圾回收。
> 本目录 `ios-app/` 下那 24 个文件只是它的工作区快照，**真正完整的东西在那条分支上**。


这 24 个文件在清理 `.tmp/` 之前只存在于 `.tmp/ios-development/` 一份纯文件拷贝里，
**从未进入任何 git 分支**（`origin/main`、`origin/feature/ai-model-selector`、
`origin/codex/ios-same-app` 都没有）。清理 20 GB 临时副本前先复制到这里保命。

## 它们是什么

修改时间集中在 **2026-08-31 ~ 09-01**，也就是新历史（根提交 `ddd4ed2e`，08-30）
开始之后。主线对其中所有类型的引用都是 **0 处**，`ios-app/project.yml` 也没有声明它们——
说明这批工作是整块没进主线的，不是"引用了但文件丢失"那种损坏。

| 文件 | 大小 | 对应 Android 侧 |
|---|---|---|
| `AssetRefundAllocationStore.swift` | 30 KB | `physical_asset_refund_allocation_sheet.dart` |
| `BudgetStoreV2Tests.swift` | 25 KB | 预算 V2 测试 |
| `LendingView.swift` | 17 KB | `lending_view.dart`（借出／应收） |
| `AssetRefundAllocationStoreTests.swift` | 16 KB | — |
| `BudgetSpecialTracking.swift` | 14 KB | `budget_special_tracking_ui.dart`（预算专项追踪） |
| `AssetRefundAllocationSheet.swift` | 9 KB | 资产退款分摊 UI |
| `LoanWizardView.swift` | 8 KB | `loan_wizard_sheet.dart`（贷款向导） |
| `LiabilityStoreTests.swift` | 6 KB | — |
| `ReceivableStoreTests.swift` | 5 KB | — |
| `BudgetBusinessCalendar.swift` | 3 KB | — |
| `AIChatAttachmentTests.swift` | 3 KB | — |
| `LedgerScopeTests.swift` | 2 KB | — |
| `BooksViewTests.swift` | 1 KB | — |
| `Assets.xcassets/BookCovers/*` | 11 个 json | 账本封面图集（主线无此图集） |

## 为什么值得留

这批代码正好落在 iOS 版最大的几个缺口上——审计测得 **资产/负债/权益域 iOS 只有 Android 的 23%**，
而借出应收、贷款向导、资产退款分摊、预算专项追踪恰好都是该域里 Android 有、iOS 没有的功能。
7 个测试文件也是现成的。

## 未决

不确定这批工作是「做完没提交」还是「被有意回滚」——`.tmp/` 下另有一个
`rollback-index-302` 目录暗示当时做过回滚操作。并入主线前需要：

1. 确认它们能在当前主线（`codex/ios-same-app`）上编译；
2. 确认 `BookCovers` 图集所需的图片资源存在（这里只有 `Contents.json`，PNG 未一并留存）；
3. 走 macOS CI 跑一遍 `QingJiTests`。

在这三点确认之前，**不要直接拷回 `ios-app/`**。

---

## `from-old-branches/` —— 删分支前捞出的 5 个文件

这些文件存在于老线分支上，但当前主线 `codex/ios-same-app` 没有。分支删除后就只剩这里一份。

| 文件 | 大小 | 来源分支 | 说明 |
|---|---|---|---|
| `docs/待做方案-b0703-19后.md` | 7 KB | `master` | **项目 CLAUDE.md 里点名"下次直接照做"的实施方案**：统计卡真懒加载 + 喵助手记账卡跨重启恢复，含具体行号和改法 |
| `docs/可爱风改造方案.md` | 12 KB | `master` | 可爱风路线的设计方案 |
| `lib/voice_input_sheet.dart` | 11 KB | `claude/new-session-4kh1ll` | 语音输入弹层。CLAUDE.md 记载语音"已砍"，但代码写完了 |
| `lib/ai_focused_input_sheet.dart` | 11 KB | `claude/new-session-4kh1ll` | AI 聚焦输入弹层 |
| `lib/coming_soon_view.dart` | 1 KB | `master` | 占位页 |

未捞的老线独有文件：`android-app/assets/mascot/_writetest.tmp`（写入测试残留）、
`qingji-cat-budget/` 下 2 个文件（CLAUDE.md 2026-07 就标注为应删的旧拷贝）——均为垃圾。

## 相关归档 tag

删掉的分支内容并未消失，三个 tag 永久保留：

- `archive/pre-2026-08-30-main` → 老线 main（105 提交，止于 2026-06-20）
- `archive/android-master-2026-07-04` → 老线安卓主线（领先老 main 239 提交）
- `archive/ios-feimiao-rewrite-2026-07` → **iOS 第一次重写**（`ios-app/FeiMiao/` + `FeiMiaoKit/`，
  与当前 `QingJi/QingJiCore` 完全独立的另一套实现，49 个源文件，带 Data/Domain 分层和 4 个单测）
