# 肥喵 · Feimiao

Android 与原生 iOS 的个人记账应用。两端共用产品口径，分别维护实现与测试。

## 目录

| 目录 | 用途 |
|---|---|
| `android-app/` | Flutter Android 源码、资源、测试和发布工具 |
| `ios-app/` | SwiftUI iOS 源码、资源、测试和构建工具 |
| `docs/` | 项目导航与仓库维护规则 |
| `.github/workflows/` | 构建、测试及双端截图验证 |
| `.codex/`、`.claude/` | 项目共用的代理角色配置；不是个人账号凭据 |

## 从这里开始

- [Android 项目管理](android-app/docs/PROJECT_MANAGEMENT.md)
- [iOS 开发说明](ios-app/README.md)
- [仓库维护与迁移状态](docs/REPOSITORY.md)
- [协作约束](AGENTS.md)

## 源码与发布包

源码仓库不存 APK、IPA、SDK、缓存和自动截图产物。测试截图及 iOS 构建包在对应 GitHub Actions 运行的 Artifacts 中下载；需要长期保存的产物另行归档。

Android 更新入口：[VPS version.json](https://updates.xunni.dpdns.org/version.json)。**线上版本以该接口为准，不以旧标签 `android-latest` 或某个文档中的历史版本推断。**

Android 308 的启动、抽屉、备份、AI 请求修复及 VPS 发布工具已整合到本主线，同时保留主线较新的固定日期测试与截图约定。整合树全量 1222 项测试、固定历史日期 3 项测试通过；这不是重新发布 APK，线上包的哈希见版本接口。

iOS P1 功能整合在 `codex/ios-p1-integration` 接受 Xcode 验证，通过之前不覆盖主线。详细状态见仓库维护文档。
