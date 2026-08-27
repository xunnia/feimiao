# iOS 27 / Xcode 27 核验结论

更新时间：2026-08-28

## 结论

可以做 iOS 27 版，而且当前工程的最低部署目标 `iOS 26.0` 可以作为
iOS 27 的兼容构建目标。当前代码使用的 Liquid Glass 和 Tab Bar 收起 API
最低都是 iOS 26，因此不必为了“能在 iOS 27 跑”把全部工程锁死到 iOS 27。
真正使用 iOS 27 专属 API 时，才需要用 Xcode 27 / iOS 27 SDK 编译，并在用户的
iPhone Air 上做真机回归。

这意味着当前方案分成两种证据：

- **已确认的工具链事实**：Apple 的 Xcode 27 Beta 6 发布说明明确写明包含
  iOS 27 SDK，并支持在 iOS 17 及以上设备调试；
- **兼容性推断**：部署目标为 iOS 26 的普通 App 运行在 iOS 27 上属于向后兼容
  场景，但 Liquid Glass、Widget、相册、通知、输入法和 iOS 27 beta 的具体行为
  仍必须在真实系统验证，不能用模拟器或“能编译”替代。

## 视觉 API 核验

- `View.glassEffect(_:in:)`：Apple 标注为 iOS 26.0+；当前首页、键盘、统计卡和
  AI 入口使用它。
- `View.tabBarMinimizeBehavior(_:)`：Apple 标注为 iOS 26.0+；当前 TabView 使用
  `.onScrollDown`，让系统根据滚动收起底部 Tab Bar。
- Apple 的 Liquid Glass 迁移建议是优先使用系统 `NavigationStack`、toolbar、sheet、
  Button、Toggle、Picker 等标准控件；自定义玻璃效果应限于重要交互，避免把所有卡片
  叠成玻璃。当前 iOS 版保留业务卡片层级，并把玻璃集中在导航/输入/关键操作区。
- iOS 26 还提供 `.glass` / `.glassProminent` 按钮样式；首页主次操作已切换到
  这些系统样式，保留原生按压、形变和可访问性适配。

## 没有 Mac、没有开发者账号时的边界

Apple 官方说明：只用 Apple Account 也能在 Xcode 中做个人真机测试，但
Personal Team 有明确的 7 天限制：同时最多 10 个 App ID、3 台测试设备，App ID、
设备注册和 provisioning profile 都会过期，需要重新配置、构建和安装。

因此：

1. Windows 可以继续完成 SwiftUI/QingJiCore 源码、测试和 CI 配置，但不能在本机
   运行 Xcode、iOS Simulator 或创建 Apple 签名；
2. CI 可以生成模拟器 App 和未签名设备产物，但未签名 IPA 不能直接装入 iPhone；
3. 最终安装需要一台 Mac/云 Mac 登录用户自己的 Apple Account，或使用用户自己
   控制的 AltStore/Sideloadly 等工具重签；长期使用应选 TestFlight/App Store 或
   Apple Developer Program；
4. Apple Developer Program 目前是每年 99 美元（地区货币可能不同），它解决长期
   签名和分发，不等同于免费 7 天 Personal Team。

仓库的 iOS CI 会同时产出两个设备包：完整版保留 Widget/Share Extension；另一个
使用空 entitlements 并移除 `PlugIns`，只保留主 App，作为免费团队遇到 App Group
或扩展签名限制时的兜底。兜底包不包含小组件和系统分享扩展，但不会削弱主 App 的
记账、统计、备份和 AI 前台功能。

## 本项目的验证顺序

1. 在 macOS runner 上用 Xcode 27 Beta 6（若 runner 没有则明确记录 Xcode 26 fallback）
   生成工程、跑 QingJiCore 和 App XCTest；
2. 在 iOS 27 模拟器采集 35 个路由，与 Android `1.262.0+276 / b0827-276`
   做成对截图；
3. 重点在 iPhone Air 真机验收 Liquid Glass、动态字体、Reduce Motion、键盘、
   通知、Widget、照片、麦克风、Speech、Share Extension、OAuth 回调和免费签名；
4. 真机验证通过后，再生成给用户重签的 Release 产物。

## 官方资料

- [Xcode 27 Beta 6 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes)
- [Xcode 26 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [`glassEffect(_:in:)`](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:))
- [`tabBarMinimizeBehavior(_:)`](https://developer.apple.com/documentation/swiftui/view/tabbarminimizebehavior(_:))
- [Choosing a Membership](https://developer.apple.com/support/compare-memberships/)
