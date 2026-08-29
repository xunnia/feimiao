# iOS 26 Liquid Glass 研究与实现约束

## 结论

本项目的 iOS 版仍与 Android 保持同一信息架构和业务入口；平台差异只用于提高触控、转场、材质和系统整合。Liquid Glass 不等于给普通控件加一层半透明白色背景，必须让系统玻璃材质、底层内容和控件状态动画一起工作。

## Apple 官方依据

- [`glassEffect(_:in:)`](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:))：iOS 26.0 起可用；系统会在视图后渲染 Liquid Glass 材质并叠加前景效果，材质锚定在视图 bounds，默认使用 regular 变体和 Capsule 形状。
- [`GlassEffectContainer`](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)：把多个玻璃形状合成一个可交互、可变形的形状集合，同时改善相关玻璃控件的渲染性能；spacing 决定形状靠近时何时融合。
- [`glassEffectID(_:in:)`](https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:))：与 `glassEffect` 和 `GlassEffectContainer` 一起使用，在状态切换或转场时让玻璃形状从一个身份变形到另一个身份。
- [WWDC25 — Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)：Apple 将 Liquid Glass 定位为跨平台系统材质和控件层，内容层应保持清晰，控件层使用系统材质和一致的动效。

## 公开 iOS 产品样本

以下只使用 App Store 公开截图观察布局，不推断 Claude 或 ChatGPT 的私有实现细节：

- [ChatGPT on the App Store](https://apps.apple.com/us/app/chatgpt/id6448311069)：常见模式是内容卡片在上、底部大圆角输入卡在下，输入卡内把加号、文本输入、语音/发送动作组织成一个紧凑控件组。
- [Claude by Anthropic on the App Store](https://apps.apple.com/us/app/claude-by-anthropic/id6473753684)：常见模式是内容优先、顶部菜单控件成组、结果卡片分层叠放，玻璃或浅色控制面板与内容区域有清晰层级。

## 本项目实现规则

1. 可操作控件优先使用系统 `.buttonStyle(.glass)`；主提交、发送和确认动作使用 `.glassProminent`，不再使用普通 `.bordered` 作为 iOS 26 主控件。
2. 顶部工具组、底部记账输入组、键盘按键组使用 `GlassEffectContainer`；相关状态使用 `glassEffectID`，并让 `withAnimation(.snappy)` 驱动状态变化。
3. 页面底层提供轻量的内容色彩和柔光，列表使用 `.scrollContentBackground(.hidden)` 露出底层，玻璃因此能显示折射/透光层次；原始账单内容不加过多玻璃，保证可读性。
4. 视觉验收和性能验收分开：成对截图用于证明 Android/iOS 页面和入口对齐；性能前后必须使用同一数据集的真实耗时或 XCTest measure 结果，不能用两张相同截图宣称性能提升。
5. `project.yml` 的最低系统版本为 iOS 26.0，因此可覆盖 iOS 27 beta；最终仍需在用户的 iPhone Air 真机上验收动态效果、触感、字体和安全区域。
