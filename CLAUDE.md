# CLAUDE.md

> 交接文档。新会话/新环境（含 cowork / Claude Code）接手时先读这份，**别把已锁定的决策又问一遍或推翻**。
> 「§-1 最新交接」是 2026-07-02 的增量，**最优先看**；再往下依次是 2026-06-28 的 §0 和 2026-06-18 版底稿（仍有效，新章节覆盖旧的）。

---

## §-1 最新交接（2026-07-02 起：按用户优化文档做六批 UI/功能升级）

### -1.0 背景与两个重要变化
- **b0628-3 订单切单修复已真机验证通过**，京东订单列表解析告一段落（天花板结论见 §0.1，仍有效）。
- 用户写了**优化文档** `C:\Users\寻逆啊\Desktop\记账app\记账app优化文档-0701.docx`（21 张参考图：Telegram 分段胶囊 / 咔皮手动记账+键盘+预算流程 / Claude 抽屉+改名弹窗 / 团团账本封面等）。所有需求以它为准，我已完整读过并给了分析，用户认可全部结论。
- **⚠️ 决策解锁**：原「纯本地、无登录、无云同步、无多人共享（多次否决）」**已被用户 2026-07-02 亲口放开**：现在方向是「功能尽可能完善、满足用户需求」，**要做多人共享账本**。真·共享需要后端+账号体系，属六批之后的独立大项目；六批期间数据模型往「可同步」方向设计（如用 uuid、变更时间戳）。**别再拿旧决策否掉共享需求。**

### -1.1 六批实施计划（每批改完水印+1、推 CI、用户真机验一次）
1. **视觉快改批（进行中，b0702-1）**：空态猫放大3倍(216)；AI建议胶囊改输入框同款玻璃透明底；顶栏抽屉/搜索/账本按钮+抽屉头像统一 PressableScale 按压动效；主页底部 Telegram 式渐变过渡；全部/支出/收入改 Telegram 文件夹式胶囊；移除首页洞察小条(_InsightStrip已删)；手动卡移除今日可花横幅(_TodayAllowanceBanner已删)；聊天里只最后一条回复带猫(showMascot)。
2. **手动记账重构**：键盘对齐咔皮（减号/再记/完成）；金额显示区改输入框风格（左上金额+细横线备注+右下拍照/相册附图）；芯片排=日期/账本/账户/标签+更多(待报销/不计入收支)，**不做「优惠」「计入预算」**；二级分类改咔皮式「点一级原位展开二级面板+背景模糊」+记忆常用二级排前；收入页同款布局芯片少几个。附照片要加 DB 字段（attachment path）。
3. **抽屉重构**：Claude 式推开分层（主页右移露边）；字标/图标/字体对齐 Claude；头像挪左下角；账本菜单加「编辑/加星」（图标在前名称在后）；改名弹窗对齐 Claude（圆角/细边/灰底/左对齐）；抽屉项长按拖动排序（持久化）；新建账本半屏页=Claude 选图式横滑封面+自定义名称/封面+「计入总账本」开关（默认开）；总账本不可删；删账本二次确认。**封面图等用户拿 GPT 生成**（规格已给：蓝白英短猫主题、竖版3:4、PNG 900×1200、9张：默认/日常/餐饮/网购/旅游/宠物/母婴/家庭/生意/情侣）。
4. **统计重构**：时间维度加周/自定义（去掉"度"字），按钮同 Telegram 胶囊；右上角加账本切换；首图改环形图（环左+图例右，猫系低饱和多色板，>6类归其他）；趋势图按维度给粒度（周=7天柱/月=每日线/年=12月线）；页面卡片化，后续支持长按排序/删除/底部+添加（图表库：堆叠柱/热力图/横向条形/分组柱/雷达[本月vs上月]，桑基图缓）；AI洞察三件套（消费摘要/画像/超支预测）纯本地规则实现。
5. **预算期间模型**（动 DB，单独一批）：预算改「预算期间」表（账本id、起止或每月循环、总额、分类明细）；历史月显示当时生效预算；一页式设置（收入→固定支出→自动建议[收入-固定-20%储蓄，按历史消费结构分配]→微调→选账本+期间）。
6. **喵助手**：历史消息改记账明细卡（左上图标+名称、灰字时间+账本、右侧金额、底部改分类/删除芯片，替掉"喵+已记一笔"）；**保留改分类芯片**（学习闭环，用户已确认要）；AI 回复排版对齐 Claude（关键数字加粗，轻量 markdown 已有 _mdSpans 可加强）。

### -1.15 环境重要变化：本机有 Flutter 工具链！
- 用户这台 Windows 机（Claude Code 环境）装了 **Flutter 3.44.2 / Dart 3.12.2**，`flutter analyze`、`flutter test` 都能本地跑（本批已跑：analyze 无 error、154 测试全过）。**推 CI 前先本地验，别再盲推**。CI 仍负责出 APK 到固定 Release 链接。

### -1.2 已完成批次速查
- **批6.5（b0702-12，待真机验）第四轮反馈**：①**右滑手势让位**：新 `widgets/slidable_tracker.dart`（全局登记左滑面板开合，`transaction_actions.dart` 内 _PaneWatcher 监听 actionPaneType），RootShell 裸指针右滑仅在 `!SlidableTracker.anyOpen` 时开抽屉——面板开着时右滑=关面板 ②新全局组件 `widgets/app_toast.dart`（顶部深色胶囊 toast，对齐Claude，轻提示统一用它），AI回复点复制→「已复制」③**字标logo**：用户 GPT 生成两版，选定第二版（藏青+金币爪印，贴主题色），**等用户把文件存到 `Desktop\记账app\图片\logo.png`**→PIL 白底转透明+裁边+压缩→assets/brand/→抽屉头部 Image.asset 替换文字（fallback 保留文字）。
- **批5.7+批6（b0702-11，待真机验）预算三层重构+喵助手**：①**预算页重构**（GPT复盘用户认可）：首页「看预算」=本月预算卡（总额/已用·剩余/还剩N天·日均可花/**分类进度前5条带预警色**：≥80%金、超支橙）+「预算计划」列表（⋯菜单=编辑/删除，不裸露垃圾桶）+底部新建按钮；「设预算」=**showBudgetSheet 底部模糊弹层**（每月/自定义+账本胶囊、本月可支配预算+**智能建议缩成小按钮**点开折叠区[收入/固定支出/生成]、分类预算、编辑模式预填）；repo 加 `updateBudgetPeriod`；新全局助手 `app_sheet.dart#showBlurSheet`（与手动卡同款模糊弹层，以后大弹层都用它）②**批6喵助手**：已保存记账改**每笔一张明细卡** `_SavedEntryCard`（CatIcon+备注/分类名、灰字日期时间·账本·分类、右侧金额收入金色、底部**改分类芯片**(showIosMenu候选,保留学习闭环)+**删除芯片**(确认后单笔删除,卡片淡化划线'已删除',_RecordMsg.deletedIdx运行时态)，替掉「喵+已记一笔」，msg级撤销删除）；确认卡去猫改纯文字头；`llm_query.dart` 提示词加排版规则（关键数字**加粗**/「- 」列表/短段落/禁其它markdown）。记账卡不跨重启恢复（chat_messages只存文本），deletedIdx不持久化无碍。
- **批5.6（b0702-10，待真机验）账本封面接入**：用户 GPT 图 8 张已到（默认/餐饮/网购/旅游/美妆/生意/情侣/多人，源图在 `C:\Users\寻逆啊\Desktop\记账app\图片\账本图片`，**还缺：记账(日常)/宠物/母婴/家庭，GPT 在做**）。处理：PIL 缩到 420 宽+256色量化（8张共427KB）进 `assets/book_covers/`（pubspec 已注册）；`book_sheet.dart` BookTemplate 加 cover、封面卡=图+底部渐变压名字+emoji兜底，新增「美妆/多人」模板，「日常生活」暂用 default.png 等专属图；**DB v14**：books 加 `cover` 列，addBook/updateBook 带 cover；抽屉账本列表有封面显示 24px 缩略图。补图时：同 PIL 流程压缩→丢进 assets/book_covers/→给模板补 cover 字段即可。
- **待办复盘（对照优化文档，2026-07-02 用户点名）**：❌批6喵助手（记账明细卡替"已记一笔"+DeepSeek排版提示词）→下一批；❌统计小组件卡片体系（长按排序/删除/+添加）；❌图表库（热力图/堆叠柱/分组柱/横向条形/雷达/面积/桑基）；❌手动卡「不计入收支」开关(要DB字段)；❌手动卡转账tab；❌二级页面按钮动效扫尾。顺序已和用户定：批6喵助手→批7统计图表+卡片化→批8杂项。
- **批5.5（b0702-9，待真机验）第三轮真机反馈修正（11条）**：①showManualAddSheet 弹卡前有键盘先 unfocus+等130ms（修AI切手动"先上再下"）②手动卡删拖动把手（下滑关卡手势移到顶栏空白区，顶部padding 14）③**二级面板改浮层**：LayerLink+CompositedTransformTarget挂在被点行，Follower浮层=白雾BackdropFilter盖网格区+被点行在雾上重画一遍保持清晰+面板锚行正下方——不占布局、卡片高度纹丝不动 ④AnimatedPadding/键盘收起AnimatedSize统一250ms easeOutCubic合成一次过渡；金额-备注间细灰线恢复（上轮理解偏了）⑤AI字重 wght330/430 ⑥**抽屉拖动改 Listener 裸指针**（不进手势竞技场：账单行上右滑也能开抽屉、行左滑编辑不冲突；引导阈值 dx>24 且 dx>1.6*dy，方向感知，_settlePointerDrag 按末段速度落定）⑦芯片全圆角胶囊+缩20%(高32/字11/图标12) ⑧抽屉开时主页盖**白色半透明模糊遮罩**(BackdropFilter 5σ+白35%，对齐Claude) ⑨主页卡阴影收敛(blur18/无偏移/黑10%)修左下角灰底 ⑩抽屉宽 0.75(240-320) ⑪新建账本右边距24左移。
- **批5（b0702-8，待真机验）预算期间模型**：**DB v13** 新表 `budget_periods`（book_id/start_ms/end_ms/recurring_monthly/total/category_budgets JSON/monthly_income/fixed_expenses JSON/created_ms），迁移时把旧 budget 表的单一预算自动搬成「2000年起每月循环」一条（行为不变，旧表保留）。新核心：`core/budget/budget_period.dart`（BudgetPeriod + **BudgetResolver**：effectiveOn 特异性排序=一次性区间>循环、账本专属>通用、start晚>早、created新>旧；monthlyTotalFor 一次性区间按天摊月）、`core/budget/budget_suggestion.dart`（suggestTotal=收入−固定−20%储蓄；historicalWeights 近3月不含本月按顶级归并；split 整元切分零头给最大头）。repo：`budgetPeriods/budgetTotalFor(y,m)/addBudgetPeriod/deleteBudgetPeriod`，**monthlyBudget/categoryBudgets getter 改从期间解析**（老调用方无感），删了 saveMonthlyBudget/saveCategoryBudget/_loadBudget。首页和统计的历史月都改用 budgetTotalFor（**历史月显示当时生效预算**），统计预算卡加 on: 历史月按月末算。`budget_setting_view.dart` 重写=一页式（收入→固定支出行→一键建议按消费结构分配→总额+分类明细折叠→每月循环/自定义期间 SlidingSegment+账本选择→保存；当前生效卡+期间列表可删带确认）。新测试 `budget_period_test.dart`（11个）。
- **批4（b0702-7，待真机验）统计重构**：`statistics_view.dart` 整体重写——①时间维度=周/月/年/自定义（SlidingSegment 胶囊，自定义走 showDateRangePicker）②右上角 _BookChip 账本切换（showIosMenu+switchBook，≥2本才显示）③首图 _RingCard 环形图（环左中心总额+图例右名称/占比/金额，>6类归「其他」，_kPieColors 猫系7色板）④趋势按维度：周=_WeekBars 7天柱/月和自定义=_DualLineChart 每日双线/年=12月双线（旧「近半年趋势」删除）⑤_ArrowSwitcher 周/月/年通用切换器。`statistics_engine.dart` 加 **RangeSummary/DateTotal + rangeSummary()**（任意区间、含两端、补零、起止颠倒自纠）。新文件 `core/statistics/spending_insights.dart`=**喵的洞察三件套**（纯本地规则）：summaryLines 消费摘要（vs上月总额/涨最多分类/大头占比）、profile 画像（<5笔null→大额冲动型≥35%单笔→月光<5%/稳健≥30%/平衡/无收入=认真记账型）、forecast 线性外推超支预测（月视图 _InsightsCard 展示，仅当月显示预测）。新测试 `spending_insights_test.dart`（13个，含 rangeSummary）。**长按排序/删除卡片/底部+添加图表 属后续增强未做**；桑基图/热力图/雷达图未做（进后续图表库）。
- **批3.7（b0702-6）第二轮真机反馈修正（11条）**：①AI字体改**可变字重**正文wght350/加粗450（FontVariation，回退w400/w500），用户气泡同350 ②抽屉恢复「更多」折叠（前5项+展开，折叠态也可拖排序，shown=前缀索引直通全局order）③头像改玻璃按钮风格(GlassSurface blur:0) ④右滑开抽屉范围恢复左半屏(screenW*0.5) ⑤**编辑账目统一进 ManualAddSheet 编辑模式**（showEditTransactionSheet 分流：转账走旧卡；edit预填+updateTransaction+learnCategory纠正学习+无再记+保存键+不显账本芯片）⑥手动卡 AnimatedSize 高度过渡 ⑦book_sheet 编辑时 autofocus ⑧主页卡片-分段间距减半(expandedHeight-8/卡片底4/分段顶0) ⑨芯片白底+发丝边+淡影(去灰底) ⑩**新统一入口 showManualAddSheet**：与AI面板同款背景模糊+上滑出场（替代showModalBottomSheet），键盘用AnimatedPadding顶起 ⑪备注聚焦时收起数字键盘让位系统键盘(_noteFocus)+textInputAction.done。
- **批3.6（b0702-5）发烫修复**：用户反馈"打开App手机很烫"。根因=①`MascotBreath` 永动画 `repeat()` 逼手机 60/120fps 持续渲染 ②首页常驻 6-7 层 `BackdropFilter` 实时模糊每帧重算。修复：`mascot.dart` 改**间歇呼吸**（呼吸2个来回→静止8秒零渲染→循环，+RepaintBoundary 隔离重绘）；`glass.dart` GlassSurface 加 `blur:0` 免模糊快速通道，**纯色/静态背景上的小按钮一律 blur:0**（顶栏3钮/账本胶囊/输入卡内按钮/手动卡按钮/AI面板小件/统计翻月钮已改），只有盖在滚动内容上的大浮层（底部输入卡、AI面板背板、iOS菜单）保留模糊。**性能铁律：不要写 `repeat()` 永动画；新加 GlassSurface 先想背景是不是纯色。**
- **批3.5（b0702-4）用户真机反馈修正**：①空状态只留猫(184,无文案) ②新建全局组件 `widgets/sliding_segment.dart`（Telegram式滑块平移+AnimatedDefaultTextStyle，主页 _FilterSegment 和手动卡支出/收入都用它，**分段切换以后一律用这个组件**）③AI回答字重 w300→w400（加粗仍 w600，反差一档=Claude 标准）④手动卡：支出/收入缩到 150 宽、模式胶囊对齐 AI 面板(31/12号)、卡片高度改内容自适应(ConstrainedBox+Flexible 消大片空白)、金额 24/w600(咔皮)、去掉备注分隔线和输入框边线、账本/账户芯片弹框从 PopupMenu 换成 showIosMenu（`ios_menu.dart` 加了**靠屏底自动向上弹**逻辑）。**用户设计铁律：同类功能必须同一种设计（弹框/分段/按钮都走全局组件），别再各写各的。**
- **批1（b0702-1，待真机验）**：`home_view.dart`（猫216/新_FilterSegment/删_InsightStrip）、`main.dart`（PressableScale+底部渐变）、`ai_chat_panel.dart`（_SuggestionGrid玻璃底/_AnswerBubble.showMascot）、`manual_add_sheet.dart`（删今日可花）。
- **批3（b0702-3，待真机验）抽屉重构**：`main.dart` RootShell 改 Claude 式推开抽屉（AnimationController+Transform，主页右移+圆角+阴影，左缘28px右滑开、点遮罩/左滑/返回键关）；`_DrawerPanel`（字标对齐Claude、功能项 ReorderableDelayedDragStartListener 长按拖动排序→repo.setDrawerOrder 持久化、去掉「更多」折叠、头像挪左下+新建账本胶囊）；账本菜单=加星/编辑/改名/删除（图标在前，`ios_menu.dart` 全局翻转）；`ios_form.dart` 弹窗对齐Claude（左对齐标题+subtitle+双灰胶囊）；**DB v12**：books 加 `starred`+`include_in_total`；**总账本改真聚合**（_loadTransactions 按 include_in_total 聚合，最早的账本=总账本=defaultBookId 不可删）；新文件 `views/books/book_sheet.dart`（新建/编辑账本半屏页，9个模板封面 emoji 占位等用户 GPT 图，规格见 -1.1 批3）。⚠️ 仓库根有已提交的垃圾目录 `qingji-receipt/`（旧拷贝），建议用户 `git rm -r` 清掉。
- **批2（b0702-2，待真机验）手动记账重构**：`manual_add_sheet.dart` 整体重写（_KindSegment Telegram胶囊 / 咔皮式二级面板 _SubcategoryPanel+_blurIf 模糊收起 / _ChipsRow 日期·账本·账户·标签·待报销 / _AmountCard 输入框风格金额+备注+相册拍照+再记flash提示）；`amount_keypad.dart` 重写成咔皮4×4（1-9/⌫长按清空/+/−/再记/0/./完成，onSaveAgain 可选，编辑页 saveLabel=保存）；`app_repository.dart` 加 `addTransaction(bookId:)` 和 `childrenOfRanked`；`receipt_picker.dart` 拆出 `pickAndSaveReceiptFrom(source)`；新测试 `amount_keypad_widget_test.dart`（4个）。旧 `SubcategoryRow` 仅编辑页还在用。

---

## §0 最新交接（2026-06-28，一次超长 session）

### 0.1 首要在途：截图识别「京东/淘宝订单列表」解析（正在攻）
- 现象：用京东「我的订单」整页截图记账时，会**漏单、错位（金额配错商品）、把已取消订单也记了**。
- 已定位真因（用户贴了原始 OCR）：**ML Kit 对京东这种密集彩色页识别很糟——¥ 符号丢失（金额是裸的 `17.70`）、"999"认成"99"、行序打乱**。因为旧判定用 `[¥￥]\d` 认金额 → 认不到 → **`isOrderList` 判 false → 切单代码根本没触发**。
- 已推的修复（最新提交，构建号 **b0628-3**）：
  - `screenshot_entry.dart` 里 `isOrderList` 判定**不再依赖 ¥**，改用「共N件」锚点 + 裸两位小数金额。
  - `order_list_parser.dart`（新，纯逻辑+单测）：按每单一个的「共N件」**确定性切单**，切单时**整单丢弃「已取消/退款/未付款」**；无「共N件」回退到 `screenshot_layout.dart` 的纵向聚类。
  - `llm_entry_parser.dart` 的 `screenshotExtra` 提示词：多平台结构感知（店铺→商品→金额→共N件→状态）、跳过已取消、不漏单、金额只配同单商品。
- **待用户真机验 b0628-3**：看①是否触发切单（输入框会出现 `─────` 分块）②取消单丢没丢③漏单补没补。
- **诚实结论/天花板**：本地 OCR（ML Kit）对京东这类页就是不稳，切单能显著改善但**做不到分毫不差**；要 100% 只有**视觉大模型看图**（通义/智谱 VL，需云端 key）。用户**明确嫌云端麻烦、要纯本地**，所以别擅自上云；可以再优化本地启发式，但要如实告诉他上限。**单个订单详情页截图几乎不会错**，整页列表当"批量草稿"、确认页删改兜底。

### 0.2 本 session 已完成（都在分支上、有单测的已进 CI 硬闸门）
- **改名**：App 从「轻记」→ **「肥喵记账」**（`AndroidManifest label`）。
- **AI 记账准确率三连**：
  - P0-1 大模型统一判意图：`parseWithLLM` 返回 `{intent,entries}`，记账/查账交给 DeepSeek 判；关键词 `ChatIntent`（`chat_intent.dart`）仅离线兜底。**修了"花了"被误判查账的 bug。**
  - P0-2 商户词典 `merchant_category.dart`（真实 key、kind 感知、最长匹配）：瑞幸→饮料、滴滴→打车…；分类优先级 **用户记忆 > 词典 > 大模型 > 兜底**（`_matchCat` / quick-entry / auto-record 都接了）。
  - P1 记账卡**一键改分类芯片**（`ai_chat_panel.dart` `_CatChip`/`_pickCategory`/`_catCandidates`）：同大类兄弟子类，点一下=改+学习(`learnCategory`)+若已入库改库(`repo.setTransactionCategory`)。`addTransaction` 现返回 id。
  - P2 `entry_sanity.dart`（金额≤0/过大→null、未来日期→今天、置信度 clamp，接在 LLM 与本地两条路）；本地解析认**中文数字金额**（`_cnToInt`：一百二/两块五/一万二）。
- **解析更聪明**：`meal_time.dart`（笼统 `dining` 按时段→早/午/晚餐）；`smart_tags.dart`（报销识别→存账标"待报销"、AA 分摊按人数）；`spending_anomaly.dart`（记完比同类历史贵一大截→温和提醒，仅聊天记账路弹）；`notification_parse.dart`（通知挑支付金额避余额+方向）。
- **顶级·捕获入口（原生）**：
  - **分享到肥喵**：`MainActivity.kt`（MethodChannel `feimiao/share`）+ manifest SEND/SEND_MULTIPLE + `share_intake.dart`（全局 navigatorKey，文字→AiQuickEntryView、图片→`recognizeImagePathAndEntry`，与相册选图共用 OCR 管线）。**待真机验。**
  - **自动记账**：`PaymentNotificationListener.kt`（`NotificationListenerService` 抓微信/支付宝支付通知→粗筛→排队 SharedPreferences）+ channel `feimiao/autorecord`（取队列/查授权/跳设置）+ `auto_record.dart` + `auto_record_sheet.dart`（回前台一键批量确认，不静默乱记）+ 设置页 `auto_record_setting_view.dart`（抽屉入口，含保活引导）。**待真机验（通知文案解析 + 国产 ROM 保活是最大变数）。**
- **趋势图**：统计页「近半年趋势」支出+收入双线（`statistics_view.dart` `_TrendChart`）。
- **月度报告**：`monthly_report_view.dart`（本地算的月报 + 猫锐评，统计页入口）。修了双 ¥ bug。
- **退款=冲账方案1**：`repo.refundTransaction` 记负支出；左滑「编辑/退款/删除」`transaction_actions.dart`（flutter_slidable）。
- **周期记账**：`recurring_rule.dart` + DB v11 + `recurring_view.dart`（抽屉「定时记账」）。
- **崩溃修复（重要）**：release 版截图识别崩（NPE `getClass() on null`）根因是 **R8 裁掉了 ML Kit 反射加载的中文模型类** → 已在 `android/app/build.gradle.kts` 的 release 关掉 R8：`isMinifyEnabled=false` + `isShrinkResources=false`。**别再打开**，否则 ML Kit 会被裁崩。
- **图标**：`app_icon.png` 是完整成品图（内容贴边），CI 里 `rm` 掉自适应 XML 强制传统图标。真正无裁切要用户给「透明背景 logo 前景」做标准自适应——用户没给，**暂搁置**。

### 0.3 构建 / 验证 的变化（覆盖 §二）
- **提交信息不再用 `M{n}` 流水号**，改**中文描述式**（如「AI记账P2:…」）。
- **用户在本地 `master` 分支**，推送用 **`git push origin HEAD:claude/hopeful-wozniak-pr2ne3`**（把 HEAD 推到那个固定分支；直接 `git push -u origin claude/…` 会 `src refspec … does not match`，因为本地分支名叫 master）。
- **cowork 环境里没有 `mcp__github__*` 工具**，我读不到 CI 日志；靠用户截图/告知 CI 颜色。Claude Code 环境若有 `gh` CLI 或 github 工具可自查。
- **构建水印**：`lib/build_info.dart` 的 `kBuildTag` 显示在 AI 记账页副标题（现 **b0628-3**）。**每次有意义改动就 +1**，让用户一眼确认装的是不是最新包（本 session 反复踩"用户在测旧包"的坑，务必让他先认水印再报问题）。
- 沙箱/cowork 的 bash **不能 commit/push**（`.git/objects` 无写权限 + 无 git 身份）；**代码编辑靠文件工具落盘到用户磁盘，git 提交推送让用户在自己终端跑**。Claude Code 在用户机器上则可直接 git。
- CI 仍是唯一编译闸门：**没有本地 Dart/Flutter，我编译不了；纯逻辑都写了单测让 CI 真验；原生(Kotlin)只能 CI 验编译 + 用户真机验行为。**

### 0.4 又锁定的决策（补充 §三）
- **AI 记账要做到"顶级"**：方向是①解析准（已大量做）②捕获无摩擦（分享+自动记账）③更聪明（餐次/报销/AA/异常）。**纯本地优先，用户嫌云端 OCR 麻烦——不上云。**
- **不派子代理**依旧（用户 6-14 决定），一条龙干。

## 一、当前活跃项目

**「轻记 QingJi」安卓版**：`android-app/`，Flutter + sqflite + provider + `decimal`（金额精度）。
- 开发分支：**`claude/hopeful-wozniak-pr2ne3`**（所有进度都在这；环境是临时的，代码只认 git）。
- iOS 版（`ios-app/`，Swift）已**休眠保留不动**（用户没 Mac、侧载失败，转安卓）。
- 与用户**一律中文**沟通；用户是开发小白，解释要通俗。

## 二、构建 / 验证（没有本地工具链，全靠 CI）

- `.github/workflows/android-ci.yml`（ubuntu runner）：每次推分支 → `flutter pub get` → 生成图标 → `flutter analyze`(非阻断) → **`flutter test`(硬闸门)** → 编译 release APK → 发布到固定 tag `android-latest` 的 Release。
- **固定下载链接（永不变）**：`https://github.com/178517877qq-sketch/xunni/releases/download/android-latest/qingji.apk`
- **查构建结果**：优先 `mcp__github__get_release_by_tag`（看 qingji.apk 的 `updated_at` 晚于本次推送即成功——发布步骤只在成功后跑）。`list_workflow_runs` 返回上百KB会爆 token；若必须用，结果会落到本地文件，用 `python3` 读该文件解析 `head_sha/conclusion`。失败再 `get_job_logs`。
- **提交规范**：commit message 用 `M{n}: 简述` 流水号（当前已到 **M37**）。推送用 `git push -u origin claude/hopeful-wozniak-pr2ne3`；推前先 `git fetch + rebase`（远端偶有删文件类提交）。
- **CI 注意**：`android/` 脚手架每次 `flutter create` 重生成，所以 manifest 权限在 CI 里注入（现仅 **INTERNET**；RECORD_AUDIO 已移除）；图标用 `flutter_launcher_icons`（`assets/icon/app_icon.png`）。`assets/`、`pubspec.yaml` 是我们维护的、不会被重生成。

## 三、锁定的产品决策（定了别反复）

- **可爱风路线**（对标咔皮记账），吉祥物=用户自家蓝白英短猫。`lib/widgets/mascot.dart`（7 表情，现 emoji 占位，将来换真猫 PNG）。
- **猫系配色**（`lib/theme/app_colors.dart`）：主色蓝灰毛 `#7D8B9B`、铜金眼 `#F2B23C`（**收入/高亮**）、粉鼻爪 `#F4A9B8`、超支橙 `#FF9F68`、奶白底 `#FFFDF7`。
  - **收支语义**：收入=铜金，支出=中性深色(onSurface)，超支/预算超标=橙。**不要用通用红/绿**（多次否决）。
- **架构**：**无底部 Tab 栏**，单主页 + 左上角抽屉（学咔皮）。抽屉/输入框对齐 Claude 气质。**多次否决底部导航栏改造。**
- **纯本地 App**：sqflite，**无后端/无登录/无云同步/无多人共享**（多次否决）。
- **AI 记账接 DeepSeek**（不用 Claude——国产便宜、直连、中文好）。OpenAI 兼容 HTTP，`lib/core/ai/llm_entry_parser.dart`；用户 key 存 `app_settings` 表（设置→AI记账设置）；无 key/失败降级本地规则 `natural_language_entry_parser.dart`。
- **设计令牌**：`lib/theme/app_tokens.dart`（圆角偏大=萌、间距、动效、字重、文字三级灰度），新 UI 都走它，别再手写魔法数字。
- **GPT/Gemini 的 review 只挑增量、别照单全收**：它们反复想塞底部Tab、通用蓝/红绿配色、云同步、跟同类用户对比的AI——这些都与上面冲突，**不做**。

## 四、已完成（截至 M37，CI 全绿）

- **输入栏**（`lib/views/home/record_input_bar.dart`）：底部 Claude 式白卡启动器；工具行 `[+] [模式胶囊] … [发送↑]`。模式胶囊=**直接切换**手动/AI 且**显示当前模式**（不是弹选择面板、不显示目标模式）；记住上次选择。`[+]`→`record_extras_sheet.dart`（截图识别/导入/导出）。
- **AI 面板**（`ai_chat_panel.dart`，`showAiChatPanel`）：一句话→DeepSeek 解析→记账卡（保存/撤销）。**置信度自动入库**：每笔 confidence≥0.9 直接记+撤销提示，否则弹确认卡，缺金额则追问。查账问答走 `llm_query.dart`。
- **手动卡**（`manual_add_sheet.dart`）：分类网格(大类，按频次排序)+**子类下钻**(`SubcategoryRow`)+金额表达式键盘(`amount_keypad.dart`，含 +/− 连加)+账户/日期/备注/标签。
- **首页**（`home_view.dart`）：顶部三层卡（结余→收入/支出→预算细条/引导）+ 洞察小条（本月最大支出）+ 按天分组账单流（金额主角·收支分色·emoji 图标）。月份点击进统计页。
- **二级分类**（核心数据特性）：`category_seed.dart` 两级树（9 大类 + ~50 子类 + emoji + parentKey）；DB `categories` 加 `parent_id`，版本 6；`_applyCategoryTree` 幂等 upsert（建库+迁移共用，**纯增量、绝不动 transactions**）；`repo.categoriesForKindRanked`=顶级大类、`repo.childrenOf(id)`=子类。手动卡 & 编辑页都支持大类→子类下钻。
- **分类图标=彩色 emoji**（`CategorySeed.emoji` / `emojiOf(key)`，代码侧映射、不入库）。
- **统计页**（`statistics_view.dart`）：占比饼图/趋势柱/分类排行/预算进度/**环比(vs上月)**，fl_chart。
- **其它**：多账本（抽屉切换）、资产/账户、预算、存钱目标、分类/标签管理、CSV/Excel 导入（微信/支付宝GBK原生解码+自动归类）、CSV 导出、深浅色主题。全项目已用 `withValues` 替换弃用的 `withOpacity`。

## 五、在途 / 待办

- **⚠️ 二级分类迁移待用户真机验证**：用户升级安装后需确认「旧账目全在、金额对、旧分类(买菜超市/水电网/旅行/宠物/订阅)已并入对应大类」。若用户反馈异常优先修。
- **Fluent 3D 光泽图标（用户想要）卡点**：微软 fluentui-emoji 多词图标的真实文件夹名无法靠猜，GitHub API 又限流没法枚举 → 现保留彩色 emoji。要做需先拿到「分类 emoji → Fluent 资源路径」的准确全表（换有授权的途径，或人工对照），再在 CI 下载 ~60 个 PNG 到 `assets/cat_icons/`，渲染处用 `Image.asset` + emoji 兜底。
- **可选打磨**（价值不高）：弹窗统一抽 `appSheet()`；分类管理页按大类分组；导入自动归类映射到子类；语音（已砍，国产ROM无谷歌语音；要做得接云端ASR，需用户给key+成本）。
- 旧待办：手动卡备注 TextField 可能与键盘抢焦点（`resizeToAvoidBottomInset:false`）。

## 六、工作方式

- **不派子代理**（用户 2026-06-14 决定）：当前模型本人一条龙干完（找码/读/写/验/汇报）。需查码自己用 Grep/Glob/Read。
- 改动一律推 CI 验证，**绿了再说"完成"**；推送后用后台 sleep 等约 9 分钟再查结果（前台 sleep 被拦，用 `run_in_background`）。
- 中文沟通、对小白讲通俗、**方案定了别反复**。
