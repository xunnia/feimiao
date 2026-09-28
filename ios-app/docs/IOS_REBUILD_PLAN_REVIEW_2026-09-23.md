# iOS 同款重建方案复盘与修订记录

日期：2026-09-23。范围：用户要求审查并详细调整《肥喵记账 iOS 同款重建方案（Luna 执行版）》；不包含业务代码、构建脚本、门禁放宽、Git 提交推送或设备安装。

## 1. 结论

方向正确：Android 为母版、保留 QingJi/SwiftData、禁止第二产品栈、要求业务与 UI 一起验证。问题主要在执行合同：历史与当前混用，P0/后续阶段循环等待，旅程编号分叉，分发假设不符合用户环境，成功证据含义不清。应修执行规则，不推倒已有代码或降低最终同款目标。

修订后的主文：[唯一详细计划](IOS_ANDROID_SAME_APP_REBUILD_PLAN_FOR_LUNA.md)。简表：[同款执行合同](IOS_SAME_PRODUCT_EXECUTION_PLAN.md)。

## 2. 实质问题与本次处置

| 编号 | 问题与影响 | 已写入的修订 | 未因此完成的工作 |
|---|---|---|---|
| R01 高 | P0 声称只锁合同，却又等待 P3 恢复/P5 设备/P6 交付；同时禁止任何 UI，形成循环 | 当前入口 B 分出 P0-DEV/DATA/DEVICE，明确影响范围、并行和最终汇合 | 机器状态仍 P0_PARTIAL，迁移/签名未通过 |
| R02 高 | 9/12 快照、9/2 问题与当前指令混杂，容易反复重做或误报 | 顶部放当前快照，历史章节显式标注，重写接手指令 | 历史报告原件不改 |
| R03 高 | 308 固定基线已落后公开 312；又要求永远追最新，容易移动目标 | 分 APK/源码/截图三个身份，按批次冻结、增量队列和最终追平 | 发布包与干净源码映射仍待 N1 |
| R04 高 | “40/41 图”易被理解为功能进度；实际 40 对 dimension_mismatch | 分采集健康、归一化视觉、业务、真实交互，设置禁止外推结论 | 工具报告需 N2 修改并加正反测试 |
| R05 高 | demo 直达页面当作按钮/返回/保存验证 | 冷启动截图与真实点击操作分账，持久化/重启读回独立验收 | 分类图例到明细真实交互仍待验 |
| R06 高 | 正文 P6 的“12 旅程”与 JSON 12 ID 内容不相同 | P6 改为同一 canonical ID 表；其他能力扩展为附属合同 | 不生成虚假旅程通过记录 |
| R07 高 | 把 macOS 编译和用户必须 Mac 签名混为一谈，忽视 Windows/普通账号 | F 节拆编译、Windows 侧载候选、完整/noext、早期装机 spike | iOS 27 预览版兼容、签名与安装未验证 |
| R08 高 | 删扩展/空 entitlements 就称免费包可用；回退只说留 IPA | 加 App Group/Keychain/store 身份与数据迁移检查；区分代码、包、数据回退 | 完整/noext 的真实数据兼容仍待验 |
| R09 中 | 以技术控件名判不同款、强制新目录/新分支，制造无效重构 | 禁的是产品信息架构替换，不禁 List/Form/局部 NavigationStack；优先复用当前工作线 | 主路径同款仍须逐页验收 |
| R10 中 | 统计顺序写成洞察默认优先、卡片管理仅月视图，与参考代码不符 | P3.1 改为冻结源码实际默认序列、四维共用配置、分批退出条件 | 卡片库/年统计/预算等仍待实现或验证 |
| R11 中 | 色彩规则一刀切、退款类型混为一谈、AI 要求泛化 | 写明统计徽章色例外、外部未匹配退款与孤儿 offset 分开、AI 验结构不逐字 | 实际业务差异仍需测试 |
| R12 中 | “缺陷为零/流畅/有图”不可审计，过程只许完整/不完整两态 | 独立状态台账、分层里程碑、性能同机基线、测试/证据字段 | 不承诺不存在任何潜在 bug，不编造百分比 |
| R13 中 | 多批共享组件堆积、重复全量跑 CI、定时轮询浪费资源 | G 节限制未封板批次，明确风险相关回归，不建用户拒绝的轮询 | 现有 workflow 仍可能只支持全量，未假装已有快速参数 |
| R14 中 | 三种起点×所有旅程×多真机的要求既含逻辑矛盾又不匹配设备 | 核心账务覆盖三起点，其他风险适用性矩阵，模拟器尺寸与一台真机分开 | 真机缺口不能被 N/A 隐藏 |
| R15 中 | 外部网站/旧 README 容易把不确定平台能力说死 | 引用 Apple/AltStore 官方说明，标核查日期、适用边界和待真机结果 | 不承诺第三方工具支持当前手机 build |

## 3. 本轮证据清单与边界

- 工作树：`C:/src/xunni-codex/.tmp/repository-cleanup`，分支 `codex/screenshot-stability`，业务 HEAD `32876ece43430a9afcaf4d757bf13d4d574f1071`。
- 修改前主计划和简表已存在未提交编辑，均先备份后增量修订。备份目录：`C:/src/xunni-codex/.tmp/ios-plan-review-before-20260923/`；主计划 before SHA256 `D4E79E91D16237A9B65224612026B571C80E04DFA2B839C189CC410C9D190D5C`，简表 before SHA256 `2C7B3A9C9FEAC8613232384DD87DA8A4E8C94DCC52F9424E949F050DF775E094`。
- 主目录 Android 312 APK 实算 SHA256 `1522EE4623454176682E8F3CA837C4698D0BC5E9A77D4277F557DFDA0ABD1ED3`，与本轮读取的 [version.json](https://updates.xunni.dpdns.org/version.json) 公告一致。未完整下载公网 APK，未验证脏源码就是该包的构建输入。
- [周统计 run 35832306421](https://github.com/xunnia/feimiao/actions/runs/35832306421)：API 已 completed/success，SHA `436c94d`；本次文档审查未下载其原图作视觉验收。
- [月统计 run 35834126243](https://github.com/xunnia/feimiao/actions/runs/35834126243)：本轮约 16:06 查询仍 in_progress，SHA `32876ec`；以后以最终 run 结果更新，本文不自动随 CI 改变。
- 本地历史报告 `.tmp/parity-35508046549/report/`：41 项中 40 个 dimension_mismatch、1 个 missing_ios_target（assets-funds）；业务 diff 只报 platform 1 项。范围来自合成导出，不代表全部账本数据与操作。
- 源码依据：`android-app/lib/views/statistics/statistics_view.dart` 的 `_ManagedCards.defaultOrder`/monthOnly/四维使用点和 `_DeltaBadge`；`ios-app/QingJi/Models/AppModelContainer.swift` 的 inferred Schema；`ios-app/project.yml` 的 iOS 26.0、主/扩展 target；`.github/workflows/ios-ci.yml` 的 noext 构建与移除 PlugIns 流程。
- 外部规则只依赖官方来源：[Apple Personal Team](https://developer.apple.com/help/account/basics/about-your-developer-account)、[AltStore Windows 安装](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)。前者说明 Xcode 个人测试与期限，后者说明存在 Windows 工具路径；二者都不是当前肥喵已安装成功的证据。

## 4. 文档与机器合同的过渡规则

本次更新主计划、配套简表并新增本复盘记录；没有修改机器 JSON/自动检查器、旧运行产物或业务源码。

`p0OpenGates` 仍列旧 6 项，部分 scene evidence 仍是历史待采状态。新增 P0-DEV/DATA/DEVICE 是责任和准入定义，不可由文档推导 CI 新枚举已实现。N2 需要逐项建立旧 gate→证据→缺口→主责→验收条件的映射，并同步 JSON/schema/检查器/README/基线说明；旧证据不覆写，未证实的门不删除。

## 5. 本轮验证范围

本轮已执行并通过：

1. `git diff --check`：无空白错误。
2. 三份本轮文档的 Markdown 代码围栏成对，本地相对链接目标存在。
3. 主文 P6 的 12 个 `journey-*` ID 与 `p0_product_contract.json.interactionContracts` 精确匹配，无缺项或多项。
4. 与修改前备份比较，原有 2026-09-12 未提交交接段落除历史标题外逐字保留。
5. `check_p0_product_contract.py`：结构有效、仍报告 `P0_PARTIAL`、41 场景/12 旅程/6 开放门；本工作树缺合同引用的 308 APK，工具明确跳过该包哈希，故本次不声称 APK gate 通过。
6. `check_route_manifest.py`：工作流中的 40 个 iOS `shoot` 路由与 manifest 对齐。

Swift/Xcode/Flutter 构建不属于本次纯文档修改的必要验证；没有新增 CI 运行，以上检查不代表 App 产品验收。原有未跟踪的 `p0/P0_CAPTURE_ACCEPTANCE_2026-09-20.md` 保留且未纳入本次修改或暂存。
