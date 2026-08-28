# 肥喵记账 Feimiao — iOS 原生版

「3 秒记一笔、漏了能补平、超支提前说」的本地优先 iOS 记账 App。

Android 与 iOS 共享产品口径，但 iOS 使用原生 SwiftUI、WidgetKit、Vision、Speech 和 Liquid Glass 控件。
对齐验收记录见 [docs/ANDROID_IOS_PARITY.md](docs/ANDROID_IOS_PARITY.md)。

面向 **iOS 26+**，可安装到你的 iOS 27 beta。界面采用 **Liquid Glass（液态玻璃）** 设计语言：主页保留 Android 同款单页结构、顶部抽屉和底部「记一记」输入框，快记键盘、分类网格、统计卡片使用 `glassEffect` 交互玻璃；二级页面沿用 Android 的 push 信息架构，再用 iOS 原生导航、系统转场和触觉反馈增强。云端 CI 使用 GitHub 官方 `macos-26` runner；若镜像提供 Xcode 27 就优先选择，否则用镜像内 Xcode 26.x/iOS 26 SDK 编译，运行目标仍覆盖 iOS 27。

产品定位与市场调研见 [docs/product-analysis.md](../docs/product-analysis.md)。

## 项目结构

```
ios-app/
├── project.yml          # XcodeGen 工程定义（生成 QingJi.xcodeproj）
├── QingJiCore/          # 平台无关核心逻辑（SwiftPM 包，可独立测试）
│   ├── Sources/         #   金额输入、分类排序、统计引擎、账单导入导出
│   └── Tests/           #   单元测试，macOS/Linux 均可运行
├── QingJi/              # iOS App（SwiftUI + SwiftData）
│   ├── Models/          #   SwiftData 模型、容器、种子数据
│   ├── Views/           #   快记 / 明细 / 统计 / 设置
│   └── Intents/         #   App Intents（Siri、快捷指令）
├── QingJiShare/         # 系统分享扩展（文本/支付截图 → AI 记一笔）
└── QingJiWidget/        # 锁屏/桌面「记一笔」小组件
```

## 本地运行

本地运行需要 Apple silicon Mac、macOS Tahoe 26.4+ 和 Xcode 26.x/27。没有 Mac 时由 GitHub Actions（`.github/workflows/ios-ci.yml`）在云端 macOS 上自动编译、跑核心测试并生成模拟器截图；Windows 不能替代 Xcode 完成 iOS 设备签名。CI 会同时提供完整版和移除 Widget/Share Extension、使用空 entitlements 的免费团队无扩展兜底包；两种 IPA 都仍需用户自己的 Apple Account 重签。

```bash
brew install xcodegen
cd ios-app
xcodegen generate        # 生成 QingJi.xcodeproj
open QingJi.xcodeproj
```

在 Xcode 中把 `QingJi` 与 `QingJiWidget` 两个 target 的 Bundle Identifier 改成你自己的（默认 `com.qingji.app`），选好签名 Team 后即可在真机/模拟器运行。

## 跑核心逻辑测试

```bash
cd ios-app/QingJiCore
swift test
```

## 开启 iCloud 同步（可选）

数据默认只存本地。在 Xcode 中为 `QingJi` target 添加 **iCloud → CloudKit** 能力并勾选一个容器后，SwiftData 会自动开始同步（数据模型已按 CloudKit 要求设计：全部默认值、可选关系、无唯一约束）。

## 快捷指令「双击背面记账」玩法

1. App 安装后，「快速记一笔」会自动出现在快捷指令 App 中；
2. 新建快捷指令：截屏 → 从屏幕截图提取文本（OCR）→ 匹配金额 → 调用「快速记一笔」；
3. 设置 → 辅助功能 → 触控 → 轻点背面 → 双击，绑定该快捷指令；
4. 在微信/支付宝支付完成页双击手机背面即可自动入账。

## 迁移路线

完整的 Android 功能盘点、iOS 平台差异、分阶段施工和 7 天签名交付说明见 [`docs/IOS_MIGRATION_PLAN.md`](docs/IOS_MIGRATION_PLAN.md)。逐项对账和 Android/iOS 成对截图规则见 [`docs/ANDROID_IOS_PARITY.md`](docs/ANDROID_IOS_PARITY.md)。
