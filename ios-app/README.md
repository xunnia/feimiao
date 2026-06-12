# 轻记 QingJi — iOS 极简记账

「3 秒记一笔、漏了能补平、超支提前说」的本地优先 iOS 记账 App。

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
└── QingJiWidget/        # 锁屏/桌面「记一笔」小组件
```

## 本地运行

需要 macOS + Xcode 15 以上。

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

## 路线图

- **Phase 1（当前）**：极简快记、分类智能排序、账户与转账、明细、月统计、小组件、快捷指令、CSV 导入导出、中英双语
- **Phase 2**：AI 录入（自然语言/语音/截图票据识别）、自动分类学习
- **Phase 3**：预算与「今日可花」、每周对账（账平机制）、消费年报、家庭共享账本
