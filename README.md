# 肥喵 · Feimiao

Android 与原生 iOS 的个人记账应用。两端共用产品口径，分别维护实现与测试。

## 目录

| 目录 | 用途 |
|---|---|
| `android-app/` | Flutter Android 源码、资源、测试和发布工具 |
| `ios-app/` | SwiftUI iOS 源码、资源、测试和构建工具 |
| `docs/` | 全部项目管理文档（进度、功能、规范、发布、iOS、更新日志） |
| `.github/workflows/` | 构建、测试及双端截图验证 |

## 从这里开始

- [项目文档总目录](docs/README.md)：先读 `02-项目进度`
- [iOS 开发说明](ios-app/README.md)
- [开发规范与 Git 规则](docs/04-开发规范.md)
- [协作约束](AGENTS.md)

## 源码与发布包

源码仓库不存 APK、IPA、SDK、缓存和自动截图产物。测试截图及 iOS 构建包在对应 GitHub Actions 运行的 Artifacts 中下载；需要长期保存的产物另行归档。

Android 更新入口：[VPS version.json](https://updates.xunni.dpdns.org/version.json)。**线上版本以该接口为准，不以旧标签 `android-latest` 或某个文档中的历史版本推断。**

主线源码与线上 Android 版本一致（当前版本见 `android-app/pubspec.yaml`），集成记录和待办见 [`docs/02-项目进度.md`](docs/02-项目进度.md)。iOS 候选功能在各自分支接受 Xcode 验证，通过之前不覆盖主线，详见 [`docs/09-iOS.md`](docs/09-iOS.md)。
