# 肥喵记账 Android

肥喵记账是一款以“可爱、简单、可信”为核心的 Flutter 个人记账应用，覆盖日常记账、AI 辅助、预算、统计、账户、资产、负债、存钱目标、导入导出和本地备份。

## 项目入口

- 项目管理总纲：[`docs/PROJECT_MANAGEMENT.md`](docs/PROJECT_MANAGEMENT.md)
- 当前状态交接：[`docs/claude/CLAUDE_START_HERE.md`](docs/claude/CLAUDE_START_HERE.md)
- 最新详细交接：[`docs/claude/CLAUDE_HANDOFF_CURRENT.md`](docs/claude/CLAUDE_HANDOFF_CURRENT.md)
- 统计与账务口径：[`docs/claude/STATISTICS_CALCULATION_STANDARD.md`](docs/claude/STATISTICS_CALCULATION_STANDARD.md)
- UI 设计标准：[`docs/claude/UI_DESIGN_STANDARD.md`](docs/claude/UI_DESIGN_STANDARD.md)
- 提交与发布手册：[`docs/claude/COMMIT_AND_PUBLISH_RUNBOOK.md`](docs/claude/COMMIT_AND_PUBLISH_RUNBOOK.md)

## 本地启动

```powershell
cd C:\src\xunni-codex\android-app
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --concurrency=1
flutter run
```

Windows 上多个 Repository 测试会共用 SQLite 测试路径，稳定执行时使用 `--concurrency=1`。发版前必须按提交与发布手册完成版本同步、完整测试、Release 构建、16 KiB 对齐、签名和哈希验证。
