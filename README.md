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

`main` 是唯一集成主线，但目前仍是 Android323，不能当作最新工作版本。2026-10-15 双端云端接手统一使用 [`codex/android-handoff-20261006`](https://github.com/xunnia/feimiao/tree/codex/android-handoff-20261006)：Android `1.315.0+330 / b1006-330 / DB50`，iOS 源码及测试对齐候选 `dd692b7`，包含最新资产/预算与透明按钮。已有 [Draft PR #1](https://github.com/xunnia/feimiao/pull/1) 只看进度、不合并；先读本分支 [`docs/02-项目进度.md`](docs/02-项目进度.md) 顶部的已做/未做与验收边界，不能拿旧 iOS 分支的 Android328 覆盖330。SDK、签名、真实账本、发布包及本机 ignored 截图不随 Git 上传；源码同步不是本次正式发布或设备验收，iOS 细节见 [`docs/09-iOS.md`](docs/09-iOS.md)。
