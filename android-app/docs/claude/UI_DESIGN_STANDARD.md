# 肥喵记账 UI 设计标准（v1.2，2026-07-14 更新）

> **任何新功能、新页面、新按钮，先对照这份标准，再写代码。**
> 标准来源：用户历次点名的参考（ChatGPT iOS 设置页、Cloudflare iOS 弹窗、iOS App Store、Claude 抽屉/改名弹窗、Telegram 分段胶囊、咔皮记账键盘）+ 已锁定的产品决策。
> 修改本标准需用户拍板；执行不需要——不符合就是 bug。

---

## 0. 三条总原则

1. **同类同设计**：同一种交互（弹窗/分段/按钮/开关/日期选择）全 App 只允许一种长相，一律用 §3 的标准件。发现第二种写法就是违规。
2. **非重点降号 + 变灰**（iOS 式层次）：说明、副标题、脚注必须比正文小一号且用灰阶——这是"有视觉重心"和"大杂烩"的分水岭。
3. **语义色是铁律不是主题**：收入=铜金 `kCatGold`、支出=中性 onSurface、危险/超支=橙 `AppColors.warning`、强调=主色蓝灰。**永远不用红；绿色唯一例外是预算健康态** `AppColors.budgetHealthy(scheme)`（浅色 `#7FB069`、深色 `#9AC584`），不得用于按钮、选中、成功、收入或其他状态；主题系统只开放背景与卡片质感。

## 1. 文字层级（代码：`theme/app_tokens.dart` 的 `AppType`）

| 层级 | 规格 | 用途 | 代码 |
|---|---|---|---|
| 页面标题 | 17 / w600 | AppBar（全局主题已管，**别手写**） | `AppBar(title: Text(..))` |
| 弹窗标题 | 16 / w500 左对齐 | 确认/表单弹窗 | ios_dialogs / ios_form 内置 |
| 行标题 | 15.5 / w500 onSurface | 设置行、编辑块标题 | `AppType.rowTitle` |
| 正文 | 15 / w400 onSurface | 一般内容 | `AppType.body` |
| 说明/副标题 | **13 / w400 / onSurface 55%** | 行副标题、选项说明、弹窗正文 | `AppType.secondary` |
| 分组标签 | 13.5 / w500 / 50% | 「管理」「显示」「接口」 | `SettingsSectionLabel` |
| 行尾值 | 14 / w400 / 55% | 「两位小数」「已配置」 | `AppType.trailingValue` |
| 脚注 | 12.5 / w400 / 45% | 页面底部整段说明 | `AppType.caption` |
| 金额/数字 | Nunito 字族，大小按场景 | 所有数字 | `fontFamily: 'Nunito'` |

**禁止**：裸 `Text('...')` 不带样式（默认 16px 深色=层次杀手）；`onSurfaceVariant`（深灰紫，没有灰的层次感，一律换 onSurface 灰阶）。

## 2. 颜色

- 灰阶：主文字 onSurface → 次要 55% → 最弱 45%（`AppTextColor.primary/secondary/hint`）。
- 语义：收入 `kCatGold` / 危险&超支 `AppColors.warning`（橙）/ 强调&选中 `scheme.primary`（蓝灰）/ 预算健康 `AppColors.budgetHealthy(scheme)`（唯一绿色例外）。
- 预算进度：健康绿 → 临界铜金 → 超支橙；未完成轨道必须取当前进度末端的同色低透明度，外缘同色略深，禁止退回灰色或白色底轨。
- 背景与卡片：一律 `AppColors.pageBackground(brightness)` / `AppColors.card(scheme)` / `selectedCard`——它们跟主题系统走，**别写死颜色**。
- 描边：`AppColors.hairline(scheme)`（别手写 black 6%，深色模式看不见）。
- 输入底：`AppColors.inputFill(scheme)`。

## 3. 标准件清单（有件必用，无件先造件再用）

| 场景 | 标准件 | 位置 |
|---|---|---|
| 圆形图标按钮（返回/✕/＋/齿轮） | `AppCircleButton` / `AppBackButton` | widgets/app_buttons.dart |
| 文字胶囊按钮（保存/创建） | `AppPillButton`（弹层右上角），禁底部大长条 | 同上 |
| 确认弹窗 | `showConfirmDialog`（磨砂+左对齐+双灰底胶囊） | widgets/ios_dialogs.dart |
| 表单弹窗（改名/新建） | `showIosFormDialog` | widgets/ios_form.dart |
| 弹窗卡片壳 | `FrostedDialogCard`（磨砂+发丝边）/ `DialogPillButton` | widgets/ios_dialogs.dart |
| 半屏/全屏弹层 | `showBlurSheet` + `SheetHeader`（✕左上、标题居中、操作右上） | views/common/app_sheet.dart, widgets/settings_ui.dart |
| 设置列表 | `SettingsGroup`+`SettingsRow`+`SettingsSectionLabel` | widgets/settings_ui.dart |
| 开关 | `AppSwitch`（ON=主色蓝灰；关=可见灰槽白点） | 同上 |
| 分段切换 | `SlidingSegment`（滑块=半透明白 65%） | widgets/sliding_segment.dart |
| 单选菜单 | `showIosMenu` | widgets/ios_menu.dart |
| 日期选择 | `showAppDatePicker` / `showAppDateRangePicker` | widgets/app_date_picker.dart |
| 轻提示 | `showAppToast`（禁 SnackBar） | widgets/app_toast.dart |
| 账单列表 | `TxDayCard`/`TxRow`/`groupTxnsByDay` | widgets/transaction_day_list.dart |
| 预算横条/圆环 | `BudgetProgressBar` / `BudgetProgressRing`（禁页面自行拼进度条） | widgets/budget_progress.dart |
| 分类图标 | `CatIcon` | — |
| 按压反馈 | `PressableScale` | widgets/pressable_scale.dart |
| 页面路由 | `AppPageRoute`（自带主题背景+右滑返回） | widgets/app_page_route.dart |
| 常驻标签表单字段 | `AppLabeledField`（字段名常驻，hint 只放示例） | widgets/ios_form.dart |
| 抽屉/工具线性图标 | `AppLineIcon` / `AppLineIcons`（Lucide 风格） | widgets/app_line_icon.dart |

## 4. 页面模板

- **普通二级页**：`Scaffold(backgroundColor: transparent)` + `AppBar(leading: AppBackButton(), title: ...)`，经 `AppPageRoute` push（自带主题渐变底）。
- **设置类页**：ListView + `SettingsSectionLabel` 分组 + `SettingsGroup` 白卡 + 底部 `AppType.caption` 脚注（脚注左右 padding 24）。
- **全屏弹窗**（设置这种）：底部滑出 96% 高、圆顶角 28、右上 `AppCircleButton` ✕、无标题文字、主题渐变背景。
- **表单弹层**：`SheetHeader`（✕ 左上 + 居中标题 + 右上 `AppPillButton` 确认），**禁底部大长条确认按钮**。
- **多字段表单**：优先半屏弹层；每个输入框外套 `AppLabeledField`，字段名不能只靠会在输入后消失的 hint 表达。

## 5. 质感与动效

- 卡片：`AppColors.card()`（透明度跟主题，默认浅色 40%）；圆角走 `AppRadius`（卡 20 / 大卡 28 / 胶囊 999）；分组卡用连续曲率。
- 磨砂（BackdropFilter）只允许：瞬态弹窗（FrostedDialogCard）、iOS 菜单、底部输入卡、主页顶部渐隐（仅一层）。**禁常驻多层 blur、禁 `repeat()` 永动画**（发烫铁律）。
- 动效走 `AppMotion`（120/250/400ms），按压一律 `PressableScale`。
- 纯色/静态背景上的 GlassSurface 必须 `blur: 0`。
- 输入法/系统 inset 正在动画时，常驻大面积 `BackdropFilter` 必须用 `enabled: false` 暂停；不得通过替换祖先组件类型关闭模糊，以免重建 TextField、丢失焦点。
- 主题色卡固定单行展示；主题滑杆用 `CupertinoSlider`。普通进度条在浅色近白主题中的白色底轨必须回退为可见中性灰；预算进度不适用此规则，必须使用 §2 的动态同色轨道。
- 抽屉打开时主页必须有朝抽屉侧的定向阴影或发丝边界；导航图标统一使用 `AppLineIcon`，同组不得混用厚重 Material 图标。

## 6. 明令禁止（历史踩坑清单）

1. 裸 `AlertDialog` / `showDialog`＋Material 默认样式
2. 红色；预算健康态以外的任何绿色；`scheme.error` 当强调色
3. 底部大长条确认按钮（挪 SheetHeader 右上）
4. 手搓白圆按钮/开关/分段条（用标准件）
5. `IconButton`/`FilledButton` 裸用在导航位
6. `withOpacity`（用 `withValues`）；写死背景色（用 pageBackground/card）
7. `SnackBar`；系统 `showDatePicker`
8. 弹窗文字居中、实心色确认键（图二规范之前的旧样式）
9. `onSurfaceVariant` 当灰色用
10. 空状态放文案堆砌（只放猫）

## 7. 新功能上线前自查（5 问）

1. 用的都是 §3 标准件吗？有没有自己手搓的轮子？
2. 说明文字是不是 `AppType.secondary`/`caption`（降号+灰）？
3. 有没有出现红色、预算健康态之外的绿色、实心色按钮或居中弹窗文本？
4. 背景和卡片是不是走 `pageBackground`/`card()`（主题能跟上）？
5. 深色模式下看过一遍吗（描边/状态栏/文字可读）？
