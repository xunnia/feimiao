# 仓库维护规则与整理状态

## 规则

1. 主仓库仅为 `xunnia/feimiao`；Android/iOS 共用仓库，不夹带其他项目。
2. `main` 为集成主线。新工作使用 `codex/<任务>`，验证后合入；不要 merge 旧历史分叉来解决 ahead/behind 数量。
3. 正式保留源码、锁文件、必要资源、测试、构建脚本和当前规格。包名、数据库名及源码 namespace 中的 `qingji` 可能是升级兼容标识，不因品牌整理改名。
4. APK/IPA、日志、截图输出、SDK、构建缓存不进 Git。黄金图与手工产品参考图属于测试/规格资源，不按后缀一刀切删除。
5. Actions 只上传构建产物，不自动提交生成结果回分支。临时附件会过期，长期证据应归档到独立存储。
6. 精确暂存，禁止以 `git add -A` 混入其他端或临时改动。密钥、账号 JSON、测试账本和个人路径不应新增进入仓库。

## 2026-09-12 整理记录

- 整理基线：新仓库 main `b40316f`。在独立工作树操作，不覆盖原工作目录。
- 原始引用已用本地 `all-refs.bundle` 备份并通过 `git bundle verify`；未提交源码另有逐文件哈希核验备份。备份仅本地保存，不上传 GitHub。
- 移除主线已追踪的 `android-app/outputs/` 生成截图；原文件仍在原工作目录及 Git 备份中。
- 关闭 iOS/parity 工作流自动回写源码；保留其上传 Artifact 步骤。
- `youxuan_subscribe_update` 是其他项目，归档后移出本仓库。
- 历史 `archive/*` 标签只做本地归档，不当作当前开发入口。`android-latest` 暂留，避免破坏既有 Release 引用；它不是 VPS 当前版本。

## 尚待集成，不可删除的工作

| 内容 | 处理 |
|---|---|
| Android 308 启动/抽屉/备份/请求修复及 VPS 脚本 | 已从实际源码三方整合，保留新主线时钟约定；全量 1222/1222、固定历史日期 3/3，analyze 无 error（88 条提示） |
| `rescue/ios-p1-2026-08-31` | 有预算、资产、备份等独有功能，但也缺少新主线测试；保留并逐项移植，不整支合并 |
| `wip/2026-09-06-startup-optimization` | 含 48 个抢救文件；与本地已发布源码并不等同，保留至有效差异核对完成 |
| `codex/fix-parity-gates` | 截图稳定性候选；需 CI 最终证据后集成，不能仅凭运行时间认为通过 |

后续只有在有效改动全部进入主线或有独立可恢复归档后，才删除相应开发/抢救分支。本轮不重新改写所有提交历史。

## 功能差异的处理依据

## 2026-09-12 续验进度

- Android 整合已推送：`b46043d`；本地全量 1222/1222，但 Linux CI 暴露资产页 SQLite 异步交互的 fake_async 定时器残留。`2bcc135` 将相关点击放到真实异步区域，不删除断言；资产页 16/16 通过，Linux 全量重跑中。
- 截图契约已与 308 源码版本、水印对齐；41 场景/12 旅程契约及 40 路由检查通过。契约状态仍是 `P0_PARTIAL`，6 项开放门禁未宣称完成。
- iOS P1 候选 `94b93ea` 已通过 App 编译、核心测试和未签名 IPA 构建；App XCTest、截图仍待最终结果，未合入 main。
- 上轮 Android 截图在 reconcile 场景遇到模拟器 offline/VM service 丢失；尚未取得完整截图通过证据。
- 远端 `codex/ios-same-app` 已确认是 main 祖先，并核对 bundle 内原引用后删除；其余未验收分支保留。
- 本轮未重新发布 VPS，也未宣称已发布 APK 与整合源码完全一致。

## 本地工作目录

- 原始 `C:\src\xunni-codex` 的在途改动保留，不能为追求干净而 reset/clean。
- 本轮集成工作树：`.tmp/repository-cleanup`；iOS 候选工作树：`.tmp/ios-p1-integration`。在验证与移交完成前不要删除这些临时目录。
- 恢复资料：`.tmp/repo-cleanup-20260912/all-refs.bundle`、`worktree.patch` 和 `working-files/`，仅存本地。

## 保留与不采用的差异

- Android 三方基线使用原在途改动前的版本，保留 main 中已存在的 AppClock、现金账户单一时间戳和指定 integration_test；不是把本地目录整体覆盖主线。
- iOS P1 按共同祖先提取增量，保留主线独立 P0 fixture、路由冷启动修复、备份 ZIP 回滚和新增测试。旧硬编码演示数据、旧截图清单不覆盖主线；两侧备份测试均保留。
- 旧 WIP 的导入复核真实文件流程已包含于 iOS P1 候选；QuickAdd 高度放宽改动不覆盖主线明确的两行分类约定。
- 48 个 salvaged 文件是不参与正式构建的旧草稿/抢救副本，完整保留于本地 Git bundle，不能作为一份新的 App 实现混入仓库。与 iOS P1 对应的正式功能以候选源码和 XCTest 为准。
- 独立 parity 分支的换行规范、fixture hash 和 runner 增量已合入 Android 整合提交；截图最终成功仍以 Actions 运行结果为准。
- 两个 `.wrangler/cache/wrangler-account.json` 本地旧账号缓存明确排除；私钥、APK、截图输出、SDK 均不在暂存范围。
