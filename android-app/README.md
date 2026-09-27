# 肥喵记账 Android

肥喵记账是一款以“可爱、简单、可信”为核心的 Flutter 个人记账应用。

项目文档统一在仓库根目录 [`docs/`](../docs/README.md)：先读 `02-项目进度.md`，再读 `01-项目总览.md` 和 `04-开发规范.md`。发布流程见 `05-构建与发布.md`。

## 本地启动

```powershell
cd C:\src\xunni-codex\android-app
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --concurrency=1
flutter run
```

Windows 上多个 Repository 测试共用 SQLite 测试路径，必须用 `--concurrency=1`。
