# 双端截图链路

## 2026-09-12 修复与验收边界

- 旧 Android 任务连续执行 41 次 Flutter drive，失败日志包含 `Service has disappeared`、`device offline` 和 `bad color buffer handle`，曾在 reconcile 页面完成后失联。不能把收到页面就绪日志当作截图成功。
- 当前拆成 5 个独立 runner/新 AVD 批次，每批最多 9 个场景，同时最多 2 批。每场景仍清理两个历史包名及 ADB forward，原测试和 driver 不改。
- 每批成功后才写完成凭据；汇总拒绝缺批次、重复图片、跨提交、fixture/版本/业务数据差异。汇总保留原截图与 sidecar，仍执行全部 41 场景的 `--require-complete`、哈希、尺寸和业务字段验收。
- iOS 两条工作流的 simctl 启停/截图命令增加 45 秒超时，防止命令永不返回使原有三次重试失效。超时失败保持非零退出，不把空白截图当成功。
- 同分支旧 parity 工作流由新运行取代；对比任务 checkout 固定触发 SHA，避免分支前进后用新源码解释旧截图。
- 此次只修改截图编排，不改生产 UI、数据库或 APK，不修改指定 integration_test/driver。

本地验证包含编排单元测试、Shell 语法与工作流 YAML 解析。真实验收必须检查 GitHub 各批次、两端完整截图、业务对比和最终报告；连续两次完整通过以前，不声明稳定性已解决。
