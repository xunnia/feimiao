# CLAUDE.md

## 项目概况

这个仓库的活跃项目是 `ios-app/` 下的「轻记 QingJi」—— 一款 iOS 26+ 极简记账 App（SwiftUI + SwiftData + Liquid Glass 设计），核心逻辑在纯 Swift 包 `ios-app/QingJiCore/`（带完整单元测试）。

- 开发分支：`claude/new-session-4kh1ll`
- 本环境没有 Xcode/Swift 工具链，**一切编译与测试验证依赖 GitHub Actions**（`.github/workflows/ios-ci.yml`），macOS runner 上跑 swift test + Xcode 26 编译 + 模拟器截图 + 未签名 IPA 打包
- CI 会把截图和 IPA 提交回分支的 `ci-artifacts/`，截图可直接 Read 查看 UI 效果
- 用户没有 Mac，通过 Sideloadly + 免费 Apple ID 侧载 IPA 到 iPhone（iOS 27）
- 与用户沟通一律使用中文；用户是开发小白，解释要通俗

## 模型分工策略（重要）

> 注：Fable 5 官方暂时停用，编排者暂由 **Opus 4.8** 接任，待 Fable 5 恢复后切回。

主对话由编排者（当前 Opus 4.8）担任：负责理解需求、做方案决策、写关键/精巧代码、审查子代理产出、向用户汇报。**凡是会产生大量 token 消耗的跑腿与重活，必须派给对应档位的子代理**，保持主对话上下文干净：

| 任务类型 | 派给 | 模型 |
|---|---|---|
| 代码库检索、找文件/符号、翻日志、简单事实核查 | `haiku-scout` | haiku |
| 按明确规格写代码、批量重构、写测试、修 lint/CI 小错、写文档 | `sonnet-builder` | sonnet |
| 疑难 bug 根因分析、架构权衡、安全/性能审计、反复失败的 CI 诊断 | `opus-reasoner` | opus（独立上下文，隔离重推理） |
| 需求决策、最终审查、对用户的总结汇报、一次性小修改 | 主对话编排者 | opus（Fable 恢复后切回 fable） |

执行要点：

- 多个互不依赖的子任务**并行派发**（同一条消息里多个 Agent 调用）
- 子代理只回传结论摘要，不要让原始文件内容灌进主对话
- haiku-scout 结果不可靠时升级到 sonnet 重查，而不是自己下场翻
- 升级路径：scout 查不清 → builder 试不动 → reasoner 分析 → Fable 拍板
