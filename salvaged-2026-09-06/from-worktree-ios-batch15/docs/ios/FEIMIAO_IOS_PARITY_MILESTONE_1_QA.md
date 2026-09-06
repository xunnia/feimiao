# 肥喵记账 iOS 同款里程碑 1 验收记录

日期：2026-07-19

## 范围

- 回退基线：`5392cf0`。
- 版本：`0.2.0 (2)`。
- 只修改 `ios-app`、`docs/ios`；Android 工作树和 APK 未修改。
- 本里程碑覆盖设计 token/品牌素材、推开式抽屉、首页月份快照、首页汇总/筛选/日卡/底部入口和启动顺序。
- 预算、统计、AI、自动记账仍属后续里程碑，不用假数据占位。

## 本地证据

- `git diff --check`：通过，仅有 Windows LF/CRLF 提示。
- Asset Catalog `Contents.json`：3 个均可解析。
- iOS Resources：11 张账本封面、1 张 Logo、3 张首页猫图存在；猫图和 Logo 均有有效 alpha。
- 当前 SwiftUI target 已移除五栏 `TabView` 和 `cat.fill` 品牌占位。
- 三轮只读静态审查已检查首页 API、根导航、SQL、退款净额、月份边界、资源路径和启动竞态；发现的问题已在提交前修正。

## 未在 Windows 验证

- Windows 本机没有 Swift、Xcode、XcodeGen 和 iOS Simulator，不能把静态审查当作编译通过。
- Android 专用 AVD 的 ADB transport 持续 offline，未能从现有 APK 重新抓图；已改用当前 Android 源码和用户已有真实截图作为基准，失败复现另有记录。
- macOS CI 必须继续执行 SwiftPM 测试、XcodeGen、Simulator build、两次冷启动、截图和未签名 IPA 构建。CI 全绿且截图人工对比前，本里程碑不标记完成。

## macOS CI 结果

- GitHub Actions `iOS CI #20`，run `29690767988`，提交 `495c3f6`：成功。
- `FeiMiaoKit tests`：成功。
- `Build for iOS Simulator`：成功。
- Simulator 首次启动 5 秒存活、首页截图、终止、第二次启动 2 秒存活：成功。
- `Unsigned device IPA`：成功，artifact 6.02 MB，digest `3c003ee776e3486d66fe231fd17c52d50b6dd13ed93fd3c25b326b88e4d8880b`。
- `FeiMiao-Appetize`：成功，artifact 11.7 MB，digest `47b54e2ef9f75604c367a9033d42f1252ff1fe5d58046fe86056d25104cdd318`。
- 首页截图已人工检查：暖色背景、工具栏、账本胶囊、汇总卡、贴边猫、筛选、真实肥喵空态和底部记账入口均渲染；无大标题和底部 Tab，未见元素重叠。

本里程碑只证明新首页方向与基础启动链路成立，不代表预算、统计、AI 或完整记账闭环已经完成。

## 人工视觉反馈（2026-07-20，待修）

- 首页汇总大卡片右侧的猫与卡片右边缘仍有明显空隙，应继续右移并贴住卡片边缘，同时保持不裁切主体。
- 首页空状态猫与下方引导文案距离偏大，应缩短垂直间距，让图文形成同一组空状态内容。
