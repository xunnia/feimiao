# 肥喵记账 Android 桌面小组件研究与实施方案

> 当前状态（2026-07-07 / b0707-103）：项目已经具备原生 Android 桌面小组件。  
> 已实现 `AppWidgetProvider + RemoteViews`、Flutter 快照服务、隐私开关、总览/快记/月度进度/分类活动 4 个 provider。  
> 但真机/模拟器截图验证仍未完成：本机 AVD 无法注册为 adb device，因此后续接手必须优先在小米 15 Pro 或可用模拟器上验证裁切、行距、文字层级和点击入口。

## 1. 当前状态

代码核查结果：

- `AndroidManifest.xml` 已声明 4 个 provider：
  - `FeimiaoWidgetProvider`：总览。
  - `FeimiaoQuickAddWidgetProvider`：快记入口。
  - `FeimiaoBudgetWidgetProvider`：本月进度对比。
  - `FeimiaoCategoriesWidgetProvider`：分类与支出活动。
- `android/app/src/main/res/xml` 已有各 provider 元数据。
- `android/app/src/main/res/layout` 已有：
  - `widget_feimiao.xml`
  - `widget_quick_add.xml`
  - `widget_budget.xml`
  - `widget_categories.xml`
- Flutter 侧已新增：
  - `lib/core/widgets/widget_snapshot.dart`
  - `lib/core/widgets/widget_snapshot_service.dart`
  - `lib/core/widgets/native_widget_bridge.dart`
- 设置页已有“小组件隐藏金额”开关。
- 当前 `1.101.0+103` 已把月度小组件从旧预算余量卡改为“本月进度对比”：截至今日、本月支出、过去 6 个月同期平均、深色/浅灰两条进度。
- `b0707-103` 追加小组件视觉减重：总览小组件三项辅助金额去掉 bold，分类小组件账本标题去掉 bold 并降到 14sp；月度进度小组件“本月/平均”标签 12sp、金额 13sp，平均进度条 5dp。

这意味着：系统桌面小组件列表理论上能看到肥喵小组件；但是否在小米桌面上裁切正常，仍需真机验证。

## 2. 官方实现要求

Android 桌面小组件不是 Flutter `Widget`，而是 Android Launcher 加载的原生 App Widget。

正式实现至少需要：

- 一个原生 receiver：
  - 传统方案：继承 `AppWidgetProvider`。
  - Glance 方案：使用 `GlanceAppWidgetReceiver`。
- 在 `AndroidManifest.xml` 里声明 receiver，并配置 `android.appwidget.action.APPWIDGET_UPDATE`。
- 在 `res/xml` 里提供 appwidget provider 元数据，声明尺寸、更新周期、预览、resize 能力等。
- 小组件点击只能通过 `PendingIntent` 跳回 App 或打开指定 Activity，不能直接调用 Flutter 页面里的回调。
- 小组件刷新不等于 Flutter 页面重绘，必须有独立的数据快照或原生数据读取方案。

官方参考：

- Android App widgets overview: https://developer.android.com/develop/ui/views/appwidgets/overview
- Jetpack Glance: https://developer.android.com/develop/ui/compose/glance
- Glance setup: https://developer.android.com/develop/ui/compose/glance/setup

## 3. 技术路线对比

### 方案 A：传统 `AppWidgetProvider + RemoteViews`

优点：

- 不需要引入 Compose / Glance 构建链。
- 对当前 Flutter 项目侵入最小。
- 适合一期只展示金额、预算、前三分类和快捷入口。
- 构建风险低，尤其适合当前已经被大量 UI 修改过、需要稳定交付的阶段。

缺点：

- UI 能力比 Flutter/Compose 弱，复杂圆角、渐变、动态图表受限。
- 需要写 Android XML 布局或在 Kotlin 中组装 `RemoteViews`。
- 视觉上很难做到 App 内玻璃质感，只能做简洁、系统风的小组件。

结论：一期推荐用这个方案。

### 方案 B：Jetpack Glance

优点：

- 写法更接近 Compose，声明式，比 XML 更容易维护。
- 适合后续做更丰富的响应式尺寸、主题和样式。
- 官方长期方向更现代。

缺点：

- 当前项目没有启用 Compose / Glance 依赖，需要新增 AndroidX 依赖并验证 Kotlin/AGP 兼容。
- 可能引入额外构建风险。
- Glance 最终仍会转换为 RemoteViews，复杂交互和复杂动画仍受系统限制。

结论：二期可考虑，等一期 RemoteViews 小组件稳定后再评估迁移。

### 方案 C：小组件直接读取 Flutter SQLite

优点：

- 理论上不用 Flutter 主动写快照。

缺点：

- 原生侧必须复制一套账单、账本、预算、退款、隐藏行、分类归并口径。
- 数据库路径、迁移、锁、并发读取都更容易出错。
- 一旦 Flutter schema 变更，小组件可能显示错数。
- 用户最在意的“退款挂回原单”“重复导入不漏”都依赖现有 Dart 逻辑，原生重写风险很高。

结论：不推荐。

## 4. 推荐一期范围

一期只做“桌面看数 + 快速入口”，不要把完整记账流程放进桌面小组件。

### 2x2 小组件

展示：

- 标题：`肥喵记账` 或当前账本名。
- 今日支出。
- 本月支出。
- 预算剩余：如果未设置预算，显示“未设置预算”。
- 更新时间。

交互：

- 点击主体：打开 App 首页。
- 点击 `+`：打开 App 内记账入口。第一版可先打开首页并自动弹出记账面板；如果路由改造成本高，先打开首页。

### 4x2 小组件

展示：

- 当前账本名。
- 本月支出 / 收入 / 结余。
- 预算剩余与预算进度条。
- 本月支出前三一级分类。
- 更新时间。

交互：

- 点击主体：打开统计页或首页。
- 点击 `+`：打开记账入口。

## 5. 数据快照设计

推荐由 Flutter 侧生成快照，原生侧只负责存储和渲染。

快照字段：

```json
{
  "schema": 1,
  "bookId": 1,
  "bookName": "总账本",
  "todayExpense": "36.50",
  "monthExpense": "1692.84",
  "monthIncome": "0.01",
  "monthBalance": "-1692.83",
  "budgetTotal": "4000",
  "budgetLeft": "2307.16",
  "budgetProgress": 0.42,
  "topCategories": [
    {"name": "居家住房", "amount": "1300.00", "percent": 0.77, "color": "#6BC2AA"}
  ],
  "updatedAtMs": 1783339200000,
  "privacyMode": false
}
```

隐私模式下：

- 金额统一显示 `••••`。
- 仍可显示“预算已用 42%”这类不暴露具体金额的信息。
- 小组件必须保留“更新时间”，避免用户误以为数据实时。

## 6. 数据刷新触发点

Flutter 侧新增 `WidgetSnapshotService`，在这些事件后刷新快照：

- App 启动且仓库加载完成。
- 新增 / 编辑 / 删除账单。
- 退款。
- 导入账单。
- 切换账本。
- 修改预算。
- 修改账本是否计入总账本。
- 修改小组件隐私开关。
- App 回到前台。

刷新需要节流，例如 300-800ms 内多次数据变化只写一次，避免导入几千笔账单时频繁刷新桌面。

## 7. 推荐文件改动清单

### Android 原生

- `android/app/src/main/AndroidManifest.xml`
  - 新增小组件 receiver。
- `android/app/src/main/kotlin/com/qingji/qingji/FeimiaoWidgetProvider.kt`
  - 继承 `AppWidgetProvider`。
  - 读取快照并渲染 `RemoteViews`。
  - 处理点击打开 App。
- `android/app/src/main/kotlin/com/qingji/qingji/WidgetSnapshotStore.kt`
  - 读写 `SharedPreferences("feimiao_widget_snapshot")`。
- `android/app/src/main/res/xml/feimiao_widget_info.xml`
  - provider 元数据。
- `android/app/src/main/res/layout/widget_feimiao_2x2.xml`
  - 2x2 布局。
- `android/app/src/main/res/layout/widget_feimiao_4x2.xml`
  - 4x2 布局，或先用同一布局根据尺寸简化。
- `MainActivity.kt`
  - 新增 `MethodChannel("feimiao/widget")`：
    - `saveSnapshot`
    - `setPrivacyMode`
    - `requestUpdate`
  - 处理小组件点击传入的 intent extra，例如 `feimiao_open=quick_add`。

### Flutter

- `lib/core/widgets/widget_snapshot.dart`
  - 快照模型和 JSON 序列化。
- `lib/core/widgets/native_widget_bridge.dart`
  - MethodChannel 封装。
- `lib/core/widgets/widget_snapshot_service.dart`
  - 从 `AppRepository` 生成快照并节流写入。
- `lib/data/app_repository.dart`
  - 在数据变更后触发快照刷新。
- `lib/share_intake.dart` 或新增入口协调器
  - 处理小组件点击带来的 `quick_add` 打开请求。
- `lib/views/settings/settings_view.dart` 或“我的/设置”
  - 增加“小组件隐藏金额”开关。

## 8. UI 标准

小组件不追求 App 内玻璃拟态，因为系统桌面材质、不同 Launcher mask 和 RemoteViews 能力都有限。

建议标准：

- 背景：白色或跟随系统浅灰卡片，圆角由系统/布局控制。
- 字体：
  - 标题：14-15 / w500。
  - 标签：11-12 / w400，浅灰。
  - 金额：18-22 / w500，数字使用系统等宽感或原生默认；原生小组件无法直接复用 Flutter 的 Nunito，除非额外打包字体并自定义渲染，不建议一期做。
- 颜色：
  - 支出：接近 App 内文本黑色，不用大红。
  - 收入：低饱和金色。
  - 预算剩余：蓝色或绿色，但避免过亮。
  - 分类色：沿用 App 一级分类色。
- 信息密度：
  - 2x2 不超过 3 个核心数字。
  - 4x2 可展示 3 个指标 + 3 个分类。

## 9. 验收标准

功能验收：

- 系统桌面小组件列表能看到“肥喵记账”。
- 能添加 2x2 小组件。
- 能添加 4x2 小组件，或 4x2 尺寸下布局不挤压。
- 新增账单后，小组件在 2 秒内更新。
- 编辑/删除账单后，小组件更新。
- 导入账单后，小组件只刷新一次或少量次数，不明显卡顿。
- 切换账本后，小组件口径与 App 首页一致。
- 修改预算后，预算剩余同步更新。
- 隐藏金额开关打开后，小组件不显示任何具体金额。
- 点击小组件主体能打开 App。
- 点击 `+` 能打开记账入口或至少打开首页。

视觉验收：

- 小米 15 Pro 桌面添加后不卡顿、不裁切、不文字重叠。
- 浅色/深色模式可读。
- 系统字体放大后不溢出。
- 没有“0 元”误导空态；无数据时显示“暂无记录”。
- 更新时间清楚，例如“19:30 更新”。

工程验收：

- `flutter analyze --no-pub` 通过。
- `flutter test` 通过。
- `flutter build apk --release` 通过。
- `aapt dump badging` 包名仍为 `com.qingji.qingji.codex`。
- `apksigner verify --print-certs` 仍为 Codex 测试证书。
- 真机安装后不影响 Claude 版本共同存在。

## 10. 风险与注意事项

- 不要在小组件里展示 API Key、AI 内容、完整备注、商户敏感信息。
- 不要让小组件直接读 SQLite。
- 不要在导入 2000+ 笔账单时每插入一笔就刷新小组件。
- 不要恢复“小组件”入口，除非系统桌面小组件已经能正常添加和更新。
- 不要承诺小组件完全实时；Android Launcher 可能因省电策略延迟刷新。
- 真机验证必须包含小米桌面，因为用户主力机是小米 15 Pro。
