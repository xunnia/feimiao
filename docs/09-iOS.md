# 09 · iOS 版：现状、目标、执行规则、验收

> 整理日期：2026-09-27。合并自 `ios-app/docs/` 下 8 份旧文档，再加上 `ios-app/README.md`、`project.yml`、两个 iOS 工作流、`salvaged-2026-09-06/README.md`、git 分支/worktree 现场和 Obsidian 上架笔记。
> **新旧冲突时以最新复盘为准**：2026-08-31 复盘更正 → 2026-09-02 Luna 方案 → 2026-09-12/09-23 复盘（09-23 版目前只在 worktree 里、还没提交，见 §2.3）。被推翻的旧说法在 §2.4 列出。
> 标「待核实」的地方，是我没法用代码或 CI 结果确认的内容。

---

## 1. 目标（一句话）

**iOS 版就是 Android「肥喵记账」在 iPhone 上的原生实现，不是一个新产品。** Android 当前生产版是唯一母版；当前已发布 `1.313.0+328` / DB v50，精确源码、APK 身份和水印见 `tools/p0_product_contract.json`、`tools/screenshot_manifest.json` 与 `02` §7.34，不再沿用旧313/v49或327快照。

**必须和 Android 一模一样的部分：**主页 + 左侧推开式抽屉（没有底部 Tab）；每个入口的名称、位置、层级；页面首屏的信息顺序和字段；金额、净额、退款/报销归属、预算、统计、净资产的算法；肥喵 Logo、猫咪、分类图标、账本封面和猫系配色（收入铜金、支出深色、超支橙，不用系统红绿）；空态、错误、取消、删除/撤销之后看到的结果。

**优先用 iOS 原生方式做的部分（2026-10-02 用户再次明确）：**原生设计更好的地方就用原生，尤其 Liquid Glass、alert/confirmationDialog、Menu/contextMenu、sheet、Form/Picker、状态栏/灵动岛/安全区、系统键盘、日期/相册/文件选择器、触觉、侧滑返回、VoiceOver/动态字体/减弱动态或透明度/深色模式、系统权限弹窗。保持产品入口、信息层级和结果，不为 Android 逐像素同款去遮住系统材质或复刻自绘外壳；原生菜单的定位、圆角、排版由系统负责。

**双端品质目标（2026-10-03 用户确认）：**按 `06` §9 的奖项级完成度目标执行视觉、流程、动效、性能、可访问性和品牌自查，修正后反复复验。iOS 继续原生优先，不为网页式视觉效果重画系统外壳。Windows 源码检查、附件工具通过或 Android 离屏图不算 iOS 体验通过；实际 Mac 编译/XCTest、同场景前后图、原生操作及适用的真机门禁必须分别登记。

**Apple 做不到的地方，用同目标替代方案，并且老实写出差异：**
| Android 能力 | iOS 替代方案 |
|---|---|
| 读取微信/支付宝通知自动记账 | 分享扩展 + OCR + 快捷指令（iOS 没有这种系统权限） |
| WorkManager 定时后台生成 | 本地通知提醒 + 打开 App 时补算；BGTask 只是“系统有空才跑” |
| APK 应用内更新 | TestFlight / App Store / 侧载重签，不放假的“更新”按钮 |
| 任意明文 HTTP | 只允许本机回环/受控局域网，远程一律 HTTPS |

---

## 2. 当前真实状态

### 2026-10-07 按钮收口与最新截图（已获测试分支/CI授权）

- 067d592 Mac编译/Core146/App260/260与9交互通过，38附件取得；tint浅色仍泛黄，深色按钮像素保持。浅色subtle补clear的同形透明白承托（52%），使用原生材质/交互不变，新Mac视觉待验，未封板。

- 浅色校准续接：用户认可深色、确认优化浅色泛黄；基线37a9858的30真实图/前后图取得，App259中1项初始化等待失败，其余258通过。原生clear浅色opt-in中性tint/细边、详情更多中性图标，深色和默认不变；交互测试async等待真实appearance/关闭、保留9用例/5秒/断言，额外8主题采图及边界测试。新编译/截图仍待Mac，不凭代码宣称视觉达标。

- 用户明确授权本批精确推独立测试分支并采最新原生截图；`codex/ios-ui-chrome-20261007`基于`b0d8d8f`，10份相关View与1份测试，主目录其他候选保留，不合main、不正式发IPA、不改Android或VPS。
- 工具项隐藏系统共享背景但保留自有单层玻璃；本批按钮44pt，预算账本限宽/大字精简，资金五类筛选与排序分离，详情轻操作，无历史不留空图表。全局玻璃、预算主卡/日历和财务逻辑不改。
- 新增1项布局边界，原11测试保留；30场景采图包含浅深/窄屏大字和原生sheet、预算日→账单编辑双层sheet。本地工具45/45为准备结果；Windows不能执行Swift/Xcode，本批Mac编译、XCTest、真实图和按钮操作仍待验。10-06旧图仅作比较基线，不能称为优化后的最新图。
- 首轮`06ffbf7`编译/Core/未签名打包成功，App258项中3采图用例因窗口隐藏未产生host退出回调失败；仅补AssetsConcept/ThemePopup两个测试，UIKit根控制器真实呈现/关闭SwiftUI host，原生完成后再清理，保持场景/断言/5秒门限和生产UI不变。补修及30张附件待新Mac验证，不掩盖首次失败。
- `dea09fe` App XCTest/编译/Core job成功。用户新增Claude/GPT按钮参考，首张原生图确认暖主题regular仍偏实；新增subtle opt-in公共样式，只在本批相关顶栏/编辑层使用clear原生玻璃、细轮廓、轻阴影和中等粗图标。默认regular/48pt不变，保留系统返回与侧滑；账户管理顶栏补统一44pt/隐藏外框。增加默认保留测试，不扩为全App改色，新Mac截图待验。

### 2026-10-04 iOS候选集中收尾（独立测试分支，Mac结果待验）

- 用户已授权推独立测试分支触发MacCI，不合main、不正式发布IPA。在`.tmp/ios-sync-20261004`精确转移并逐份校验35个原候选，主目录原样保留；测试基线为Android328已发布记录`048abec`，分支`codex/ios-sync-20261004`、源码提交`6e0b685`，38路径仅iOS源码/测试/project.yml及必要ios-ci。其父链包含此前8个未推的已发布Android基线提交，不能说本批重新改/发了Android。iOS版本仍1.286.0+300，候选不是正式包。
- 补修趋势质量资格/非正当前百分比/带符号取整，及还款original_principal冻结/撤销越界/零本金信用卡兼容。补修SSE完整组帧/多行/BOM/CRLF/UTF-8、Claude截断与顶层error、取消不记服务商故障；请求级摘要缓冲/32ms显示合批，结束和中断刷新、摘要独有中断保留。详细范围与统计见02 §7.35。
- 新增106个XCTest函数仍仅源码（本轮追加22个，网络11项实际调用注入URLSession/URLProtocol）；本地Python截图工具45/45、工程/CI YAML、固定MarkdownUI2.4.1、分类图标两组各133、合同38场景/12旅程/6开放门、两工作流各38路由及空白差异检查通过。沙箱临时目录失败已用工作树TMP重新完整运行，不以失败那次报告通过。
- CI为本测试分支单独采改前048abec/候选两组完整38路由原图，分别上传Artifacts，未实际取到图前不称前后图通过。Mac编译/Core/App XCTest/原生图复看、真实操作、SwiftData保存失败补偿和跨context刷新均待验；不拿Android328、离屏组件或旧CI替代，不自动反复轮询。凭据读取被门禁阻止且未执行，使用正常Git和公开只读API，不提取本机Token。

### 2026-10-04 Android母版328已上线（仅工具元数据同步，iOS未发布）

- Android聊天主题补修、图片网络副本与真实公开摘要流式体验已随1.313.0+328/b1004-328/DB50发布VPS，源码`8c609988b8b0c54b22a3bd21bbfe8fca3852c9a1`；APK118,903,579字节，SHA256 `8CE3988E4E72A66A2B1F5B132EBBAA256ABCD86A2246D5B3033469B37B742120`。正式发布前重新全量1680/1680、0 error、签名/16 KiB/字体门禁及新旧域各一次整包复验通过，安装/冷启动/真实AI未验，见02 §7.34。
- 只更新两份工具JSON的Android版本/水印/来源提交/APK身份和实际测试数，`--require-apk`合同有效，两工作流各38路由匹配，仍PARTIAL/6开放门。iOS生产/测试/project.yml共463份冻结文件原样，6项新增图片/摘要XCTest仍仅源码、未Mac编译/运行/采原生前后图；无iOS出包、推送或CI触发，不以Android成绩代替。下方保留本地候选与旧母版的过程记录。

### 2026-10-04 图片网络副本与流式摘要（本地源码，Mac验收未完成）

- 用户「那开始吧」实施02 §7.31已批准方向；新增`AIImagePreparation` actor/后台ImageIO、同附件串行/合并/长度及SHA256缓存，原图/预览/历史引用不变。小图不重复编码，PNG无损最长4096边、照片JPEG94/最长3072边、HEIC转JPEG、不放大/不裁切，20MiB及24Mi像素前置检查；真实内容修正MIME。照片选择不先统一JPEG0.88，附件最多4张、一屏3张/第四张横滑，文件入口同样检查数量；准备后才生成请求，失败/取消不发送假附件。
- `AIStreamSummaryBuffer`保留公开摘要段落与前文并设65536上限；只接Responses公开summary与原生Claude thinking_delta，不把兼容reasoning_content当摘要。生成时可展开并持续更新，次级灰Markdown/280pt滚动/Divider，正文到达与完成折叠；活跃等待文字有克制动效，减弱动态停用。历史恢复、停止/断流正文保留与既有重新生成继续沿用，不加「继续生成」；本地首正文前等待标「处理了Ns」，不假称隐藏思考秒数。
- Responses有reasoning参数时加summary=auto；必须收到终止事件，不完整流抛interrupted并保留正文、健康分类为networkError；最终正文优先，错误响应最多读取2048字节。不修改托管后端或自动切AI通道，现有BYOK/OAuth/搜索保留；托管Claude可信摘要/工具事件、record流式及附件/搜索能力仍待后端适配。
- 图片/摘要4、公开事件白名单1、断流健康分类1共6项新增XCTest函数为源码候选；Windows无Mac/Xcode，未编译运行/触发CI/出IPA，无本批iOS原生前后图。Android专项/全量与6组离屏消息组件图不算iOS验收；原生动态字体/滚动/减弱动态/键盘/读屏、真实相机HEIC/大照片清晰度与耗时仍须Mac/iPhone测试。现有其他iOS在途保留，本轮未提交推送/递增版本或发布。

### 2026-10-04 下一版双端肥喵AI规划（图片/流式方向获准，接入未实施）

- 完整范围、顺序和待确认项统一见02 §7.31：先补当前在途代码的Mac编译/XCTest/原生前后图，再账号与自动配置、操作恢复、记一记/归类、文本助手及双端联调；共享业务契约与测试向量，不共享Flutter UI。iOS继续优先原生菜单/sheet/Liquid Glass，不另造普通用户的服务商/模型选择。
- 下一候选建议先内部联调，保留当前自用BYOK/OAuth和完整附件/搜索路径，不提前隐藏或覆盖凭据。托管通道当前record非流式、助手不支持图片文件/搜索，不能作为现有完整能力的无损替换；正式用途/路由/提示词、模型评测和纠错等后端第4批余项仍阻塞正式开放。
- 用户已同意质量优先图片副本与Claude iOS式完整流式方向，计时次要；首次副本不改原图，一屏三张/第四张横滑，具体编码和清晰度阈值待样本验证。record最终JSON与既定流式要求的冲突仍是后端前置门，不默认为可撤回流式；官方资料/源码与原参考图研究见02 §7.31，UI原生sheet/增量/滚动与后端可信摘要/工具事件分别验收。本轮先修Android聊天主题（§7.32），没有实施iOS接入或改后端契约。27份iOS在途文件未修改/提交/编译，不把Android327发布、离屏主题图或后端275验收算成iOS通过；未触发CI/真实AI/出IPA或上线。

### 2026-10-04 Android母版327已上线（仅工具元数据同步，iOS未发布）

- 资产资金、聊天可靠性及阅读交互的Android批次已随1.312.0+327/b1004-327/DB50发布VPS，源码`c6917cec0557ed1a5d172d0e4cc0c7655d15f877`；APK118,690,591字节，SHA256 `621309182D5DA648F6E6F6CC0F8041CD21518DEFF8FC761ABF484216D5547287`。本轮重新全量1646/1646、0 error、签名/16 KiB/字体门禁及新旧域整包复验通过，安装/冷启动未验，见02 §7.30。
- 只更新两份工具JSON的Android版本/水印/来源提交/包哈希及实际测试数，iOS生产源码/版本和27份在途文件原样保留。`--require-apk`合同有效、两工作流各38路由匹配，仍PARTIAL/6开放门；没有本批Mac编译/XCTest/原生前后图或iOS发布，不以Android成绩替代。未推GitHub/触发MacCI，不切新后端；BYOK/OAuth、重新生成与Claude iOS主要参考方向保持。

### 2026-10-04 第5批图片成本保护依赖（275后端已接入，App未接入）

- 只读核对后端三份文档：报告唯一18200为275/1fab2dc2、下一迁移276；无新增App字段/凭据/协议。record JPEG/PNG/WebP、最多4张/每张1536KiB/每边2048限制不变，实际路线另查采购张数/总字节/总像素及完整费用风险；未配置或超容量路线不能发送。正式文本助手仍拒绝附件/图片/搜索，不把采购保护当助手能力开放。
- 采购问题用AI_UNAVAILABLE/retry_later，业务图片用既有DTO错误；图片准备只在首次提交前，未知操作保留原DTO/X-Request-Id，先查状态/结果，不能自动压缩/删图/拆批或换编号重发；仅服务端can_start_replacement=true许可替代。稳定Key/会话、原费用风险/防重和ready＋billing_pending规则保持。
- 149专项单元/75专项DB/772相关单元/370完整隔离DB、8前端专项、构建/真实恢复/12候选HTTP/桌面及390深浅主题/保存刷新重启与回退、135账号/31原生入口为后端记录，不是本会话重跑或iOS/App/手机成绩；第4批余项、第5–6批未完成。这里只登记02/09/10及镜像，保留Claude iOS阅读UI、BYOK/OAuth、重新生成与内部自用，不改Swift、不触发iOS CI/出IPA或切AI通道；327 Android构建发布另按用户授权，Mac/原生前后图仍待验。

### 2026-10-04 第5批完整FeatureState与数值权限依赖（274已后端接入，App未接入）

- 已只读核对后端三份文档及主规划§16.2：后端报告唯一18200为274/e8b88472，功能目录/布尔用途权限/完整数值权限与后台UI已本地验收；此状态优先于下方候选记录。252–274已冻结，下一迁移275；正式iOS/Android适配仍在第5批，当前不切AI通道。
- entitlements.features解析完整17内置项及自定义项，非AI pool=system；整数可选value保留合法0，关闭/无权限/不可用省略，布尔项无value，未知项可忽略。不能把缺值当无限制。设备/用户并发/归类读实时目录默认或最高角色覆盖，设备默认2、跨两池/Key/设备并发默认5，不写死pro/max设备数；DEVICE_LIMIT.details.max_devices为实际值。AI分组未就绪不降会员角色/数值，cloud/adv.*权限不是能力已接入。
- limits.categorize_batch_max为实际归类上限，默认100/范围1–2000/关闭或无角色为0，DTO/结果硬上限2000及2MiB入站约束保持；两端首次发送前分批，已发送DTO/编号不变。超时/断线/配置变化/413不自动换编号或拆批重发未知操作，先查原编号与可替代状态。缺默认角色仅目录有界登录、AI关闭；目录故障/缺定义/暂停不能回落无限制。
- 63专项单元/32专项DB/695相关单元/355完整隔离DB、build/vet/嵌入构建、真实恢复/31候选HTTP/浏览器/重启/回退及135账号/31原生入口为后端报告，不算iOS编译/正式App或手机验收，本会话未重跑。第4批业务配置/通用入口收口、纠错、图片成本、模型评测与第5–6批仍未完成。
- 本轮仅更新文档与镜像，不改Swift/Android/后端代码、不访问实例或真实模型、不运行测试/触发CI/出包/上线。稳定Key/双凭据/结果恢复/ready＋billing_pending、Claude iOS阅读候选、BYOK/OAuth与重新生成保持，不加「继续生成」。后续联调边界见02 §7.17；现有Mac/原生前后图待验不关闭。

### 2026-10-04 第5批用途功能权限依赖（273/274候选，仅登记）

- 只读核对后端API-CONTRACT/APP-CHANGES顶部及实施记录：运行实例仍272/d17eecd2，273/274尚未接入。候选quota用途项、私有ai/config.credentials新增feature_key/locked_reason；助手、归类、记账、图片、截图、报告及绑定自定义功能逐项判断，同池其他用途可用不能开启该功能。available不等于额度/钱包/采购准入通过。
- 角色关闭locked/tier，全站暂停unavailable/unavailable，保留有效本人Key且不返回route；403 FEATURE_LOCKED/open_paywall与503 AI_UNAVAILABLE/retry_later用details.feature区分，暂停不能提示购买会员解决。不得清Key/会话、借其他用途/入口或换编号重发未知操作；旧费用和本人结果查询继续按原操作处理，锁定功能不被钱包或低档解锁。
- 后端报告reset nil私有配置崩溃及同功能多用途锁定原因汇总已修，最终32专项单元/13权限DB/679相关单元/345完整隔离DB及build/vet、274迁移保护通过；这里只登记记录，不重跑、不算iOS编译/双端App或设备通过。完整非AI FeatureState/数值value、设备/并发/归类数值执行、后台UI与候选HTTP/浏览器/恢复仍未交付。
- 本轮仅更新文档及镜像，不改Swift/Android/后端代码、不切AI通道、不触发CI/出包/上线；Claude iOS阅读候选、BYOK/OAuth与重新生成保持，不增加「继续生成」。后续按02 §7.17验权限边界与原编号恢复，已有Mac/原生前后图待验状态不变。

### 2026-10-04 第5批文本助手接入依赖（修订4，仅登记，未接入）

- 已只读核对后端修订4、API-CONTRACT/APP-CHANGES及实施证据：后端报告正式助手已接入唯一18200、271已执行、镜像45731f2f healthy；847相关回归（含166助手专项）/316隔离数据库/81候选HTTP/135账号/31原生入口是后端记录，不计为iOS编译、App联调、手机或真实供应商通过。本会话未访问后端实例或重跑测试。
- 未来使用严格助手DTO、本人JWT/设备会话＋assistant用途Key＋稳定请求编号，固定主池；两端账本/预算/家族净额/Unicode映射服从02 §7.17，不使用MoneyFormat显示字符串组装业务金额。SSE完整result先持久保存再替换delta，尾部缺usage/done或断线保持成功；此前中断保留部分正文并按原编号24小时取结果，本地防重应用、不自动新编号重发。
- `ready`与`billing_pending`独立，费用待核对不把完整回答改失败；原始thinking只有累计chars，仅原生OpenAI公开summary可展开，pre_answer_ms是等待正文时间而非实际思考。当前/历史非空附件、图片及搜索开启均明确拒绝，不能丢内容或自动换收费入口。
- 主库assistant用途、角色路由、chat/text提示词发布及各业务入口验收尚未完成，第5批正式双端适配待后续；当前Claude iOS阅读候选、BYOK/OAuth、重新生成保持，不加「继续生成」。本轮只更新文档，不改Swift/Android源码、不接新通道、不触发CI/出包/上线；Mac及原生前后图待验状态不变。

### 2026-10-04 喵助手阅读与原生交互（本地源码，Mac验收未完成）

- 以Claude iOS为主要参考，不增加「继续生成」；助手正文去重复头像/大气泡，MarkdownUI2.4.1固定依赖仅App：正文、列表/引用、自然列宽横滑表格/代码复制、网页协议限制、模型远程图片不自动加载。库固定FontSize不自动随系统缩放，已补`@ScaledMetric`，真实动态字体效果仍需Mac/iPhone核对。
- 草稿/发送图一排三等宽，后台ImageIO缩略图、移除、系统QuickLook图片/文件和缺失反馈；用户消息原生contextMenu显示真实发送时间、复制、编辑、选择文本，编辑回填附件。来源移至操作栏右侧，用系统medium/large sheet/拖条，头像当前为host首字母本机占位。思考真实摘要/时间、展开后Divider，生成时原生ProgressView；safeAreaInset/系统soft滚动边缘、用户读历史不抢滚动。记账卡及此前独立context业务保留。
- 新增4项XCTest函数仅源码，未编译/运行；公开固定版本API只读核实、project.yml真实YAML解析、两工作流各38路由与P0结构检查通过，仍PARTIAL/6开放门。不把Android1646/12组离屏图当作iOS验证，没有本批原生前后图。需Mac依赖解析/编译/XCTest/全页截图与原生菜单/来源/QuickLook实测；iPhone键盘/动态字体/VoiceOver/减弱动态另验。
- 不递增版本/DB、不提交推送/触发CI/出IPA/上线，资产在途与指定Androidintegration文件保留。后端271/修订4最新仅登记第5批依赖，当前BYOK/OAuth不改；最新范围和日志见02 §7.17/7.29及上节。

### 2026-10-04 喵助手可靠性（本地源码，Mac验收未完成）

- `AIChatOperationFence`固定发起账本并隔离清空/备份恢复后旧请求；附件单独发送不再被空文字拦截，停止/断流保留已有正文。按会话predicate读取历史，保存真实可展示摘要及首正文前思考耗时/中断；沿既有DisclosureGroup显示时间，中断只用轻说明、不加续写按钮。前端后续主要参考Claude iOS，Pi补充；不是本批已经复刻Claude全套页面。
- `AIRecordCardStore`独立ModelContext读取已保存卡：确认、分类修正、单条删除、整批撤销的账单与卡状态同一次提交，重复确认不重复入账，全批预检后才删除。失败回滚局部context、不动其他页面未保存修改；旧已保存卡仍能核对，旧未确认卡缺bookID不猜当前账本。LedgerStore原调用保留默认接口/提交行为，媒体仍在数据库保存成功后清理；实际SwiftData context通知/清理与失败保存需Mac验。
- 新Store 8、运行隔离3、卡片bookID兼容1项XCTest源码，当前未编译/运行；Windows无Swift/Xcode，未触发MacCI/采本批iOS前后图。Android86专项和6组离屏图不算iOS验收。仍需Mac编译、全相关XCTest、完整原生前后图、停止/清空/重开及跨context刷新；iPhone键盘/回弹/动态字体/VoiceOver另验。
- 不改版本/DB，不隐藏当前AI配置、不接尚未正式适配的后台SSE/恢复接口；后端270已自报结果恢复本地验收、这里只登记依赖，非iOS接入或验收。保留资产在途，不提交推送/出IPA或上线。详细日志、源码边界见02 §7.17/7.28。

### 2026-10-04 资产资金可靠性第一批（本地源码，Mac验收未完成）

- 权益收回生成真实、不计普通收入的到账流水，关联收回记录，撤销一并恢复权益/到账和原计入选择。负债还款按实际余额和既有余额模式拆本息，凭UUID关联整次撤销；账单和账本删除前保护真实资产操作，购买解绑/撤销退货后不因历史标签永久锁住普通账单。
- 新`AssetFinancialCommand`通过单次保存和仅本次对象/字段清理处理失败，退货不再先单独提交退款；不对共享ModelContext做整体rollback。已保存对象删除后重新插入的失败恢复、重复操作/日期/资料/锚点边界，均须实际Mac运行确认，不能只看源码宣布可靠。
- 当前Windows没有Swift/Xcode，本批没有编译、XCTest、原生操作或iOS前后图。Android离屏证据不能替代iOS验收；既有8份资产总览/结构区在途源码保留，未提交推送或触发Mac CI。最新测试源码数量和验证结果统一见02 §7.26。

### 2026-10-03 Android母版326已上线（仅工具元数据同步，iOS未发布）

- Android字体校准、AR01–AR04可靠性及主卡/上次核对/结构区收口已随1.311.0+326/b1003-326/DB50发布VPS，来源`fc1e797682d8a71a1b4d59619386b02b5e531498`；APK117,527,847字节，SHA256 `AE86D7EA71662491DDD817173AB201FF2BD46788F9828ACEBF2A3925580F55CC`。全量1515/1515、0 error、签名/16 KiB/字体门禁及新旧域整包复验通过，安装/冷启动未验，见02 §7.25。
- 只同步两份工具中的Android来源、包身份、测试数和截图水印；实际APK合同与两工作流各38路由通过，仍PARTIAL/6开放门。8份iOS资产在途源码/测试保留、未混入提交，未触发Mac CI/编译/采图/出IPA；Android离屏图和发布成功不等于iOS同款验收。

### 2026-10-03 资产卡片字体与结构区补充（本地源码，未编译/未采图）

- 用户确认参考为橙云，核对公开源码固定提交的系统字体声明；在已有总览在途代码上把局部主小标题设为系统13常规secondary、主40/小22 rounded bold，保留动态字号/原生Menu/Swift Charts，内距16。不是打包Apple字体或复制橙云受限业务代码，也不以声明相同承诺截图100%一致。
- 新增`AssetStructureProjection`与`AssetsStructureSection`：同一份breakdown的分类金额列表/细构成条；partial、零分母、负组件/负债及合计不符不造比例，单类别不画重复图，负债率不封顶。品牌色、动态字体分行与人民币读屏保留，总览避免重复调用breakdown。新增6项`AssetStructureProjectionTests`尚未运行，原6项总览XCTest也未验。
- 10-04复核更正：`CheckpointModels.swift`已存在`NetWorthVerifiedCheckpointRecord`实体，不能说没有全局checkpoint实体。该实体不等于Android完整header/items冻结覆盖与当前总览消费者已对齐；完整可信核对/比较/页面接入仍需逐项验收，不拿普通快照伪造「上次核对」。NetWorthStore既有归档/估值/历史语义及趋势可靠性差距不在本批关闭。
- 本机无Swift/Xcode，没有编译、原生交互或本批iOS前后图；两工作流各38路由和P0合同检查通过仍PARTIAL/6开放门，Android离屏图不算iOS通过。此源码批次当时未提交/推送/触发Mac CI/出IPA或更新Android母版，详见02 §7.24；随后Android326正式发布基线见上节与02 §7.25。

### 2026-10-03 Android母版325已上线（仅工具元数据同步，iOS未发布）

- Android资产总览与主题补修已发布VPS，版本1.310.0+325/b1003-325/DB v50，来源`4199708901e5de13e4c33913baaeab1fa653f9df`；APK117,445,927字节，SHA256 `DEB25A455E540B024E416BE94AD3201563E14E4F7617C7ACD351FA0DB94F6424`。正式门禁、1431全量及新旧域完整下载通过；装机仍未验，详情见02 §7.19。
- 本次只同步`p0_product_contract.json`的Android来源/版本/包身份/测试数字及`screenshot_manifest.json`的版本水印，不改iOS资产在途源码。带实际APK的P0契约与两工作流38路由通过，仍PARTIAL/6开放门；无新Mac/原生截图/触摸结果，不把Android发布算iOS通过。GitHub本轮未推送、不合main。

### 2026-10-03 资产总览获准实施（本地源码，Mac与前后图待验）

- 用户批准总览第八轮布局并要求主/小卡标题15px、灰色、相同字重和左边缘；仅替换资产总览汇总区。原生Menu/Picker与Swift Charts，大金额＋四张独立小卡，真实snapshot趋势、缺失/断点状态、人民币读屏、动态字号单列；没有新增DB写入或历史反造，资金/物品及其他入口保留。
- 新只读`AssetOverviewProjection`按真实快照的global/CNY、日期、scope/calculation/币种覆盖/质量断段，最新同日knowledge保留；区间变化只在单段完整历史且末点等于当前时显示，零/负起点不假造0%。iOS当前只有手动快照，文案为「快照估算」，不冒称Android自动重建能力。
- `MoneyFormat.string`新增默认true的`withSymbol`兼容参数，资产主/小卡false，原调用与小数/舍入设置不变。金额用原生rounded，不为了Android同款引入网页装饰、多层常驻blur或仿制系统菜单。
- 新6项XCTest已写但**未运行**；Windows无Swift/Xcode，未Swift编译、未原生点击、未采集本批iOS前后图。38路由与P0结构检查通过仍PARTIAL/6开放门，不代替运行；Android146回归/Widget图也不算iOS通过。
- 源码未提交推送，不擅自触发MacCI或混入既有主题验收；版本与P0截图母版不变。平台验收、完整前后图和发布另行安排，详见02 §7.18。

### 2026-10-03 主题验收：Mac编译通过，交互与截图未封板

- 已读取一次 `2389bae` 的Mac CI `37028494081`：App编译、Core测试和两份未签名IPA生成成功；App XCTest 140项有2失败，均在主题交互（sheet关闭后仍有alert、关闭重开仍是旧host）。主题展示8/8通过，但不代表交互或视觉通过；全页面截图及双端run `37028493722` 当时仍运行，未再轮询。
- `mac-diagnostics-2389bae/` 已保留xcresult、日志、manifest和22张真实组件原图。尺寸/PNG完整/非空/全不透明及原图SHA256核对通过；人工查看发现英文标题/Picker与窄屏大字确认框裁切、背景残影，不能作为合格的全页面改后图。`review/` 内两张总览仅帮助查看原附件，不是前后对比；61张旧全页图不与这些不同场景硬配。
- 本次仅修改两份XCTest：固定等待改等UIKit状态、测试窗口key/恢复、中文locale和完整主题底。生产协调器未改，**候选修正无新Swift/Xcode运行证据，不能说失败或截图缺陷已解决**。新增附件核对工具8项本地测试通过；两工作流38路由及P0结构通过，仍6开放门。
- 用户10-03确认授权后，精确提交7路径为 `80ff8f0433e8d2b196309ec27508c284aae96702` 并推 `origin/codex/budget-takeover`，远端SHA一致。iOS CI [37037590763](https://github.com/xunnia/feimiao/actions/runs/37037590763) 与双端截图 [37037590756](https://github.com/xunnia/feimiao/actions/runs/37037590756) 读取一次时均排队，未自动轮询/验最终结果。真实原生按钮、多段删除、Menu/VoiceOver和29处Form全页面前后图仍待验。保持原生Liquid Glass方向，不改用户系统语言、不把Android离屏图当iOS完成；本轮无正式包、VPS或main集成。

### 2026-10-02 主题弹窗补修与原生优先收口（源码已推送，Mac 验收待结果）

- 内容层取色对齐品牌主题：彩色顶底插值 35%，跟随浓度；白主题仍白，深色提亮 6%；输入同主题。原生弹窗不再绘制 Android 双灰胶囊、遮罩或高不透明度磨砂卡，不强制系统玻璃背景取相同实色。
- `AppConfirmationDialog` 已按最新要求改为原生 `UIAlertController`，保留预算历史影响、降额转换、删除和账本三段确认；系统布局/材质/动态字体/模态无障碍不覆盖。多段动作在真实关闭完成后接续，防重、旧回调和拆除保护保留；危险上下文以公开 tint 取橙，取消为安全默认动作。不使用私有 KVC，不添加系统未提供的背景点击关闭行为。
- `AppSelectionMenu` 改用原生 Menu/Toggle，系统显示单选标记和图标，保留月底结余副标题；取消固定宽高的自绘 popover。预算编辑/日详情移除不透明 presentationBackground 和覆盖安全区的内容底，保留主题内容与原生 sheet 外壳。
- 新 `AppThemedForm` 内部仍为系统 Form，统一内容底/行填充/品牌 tint。29 处 Form 接入，覆盖账户/账本/分类/标签/资料/显示设置/AI 配置与记忆/存钱/资产负债/定时/对账/账单编辑/快记表单；仅换容器名称，未改字段、保存、数据或凭据逻辑。旧布局不重排，原生 Picker/Toggle/输入保留。
- `ThemePopupPresentationTests` 8 项、`ThemePopupInteractionTests` 9 项，共 **17 项 XCTest，均未运行**。两个截图测试拟产出 22 个 UIKit 原生层级附件（14 确认、8 表单，六主题、浅深、320pt 大字），不是完整页面交互/真机证据。CI 增加 app-tests.xcresult 保留，避免附件随 runner 丢失。尚无本批 iOS 实际前后图，不能拿 Android Widget 图或未运行的截图代码代替。
- 本机重新执行 38 路由匹配及 P0 契约源码检查，退出 0；P0 仍 PARTIAL / 6 开放门。这只验证清单结构，没有运行新 presenter，不算 Mac 编译/XCTest 通过。
- 同日源码复核未发现可直接确认的 Swift 编译错误，不等于类型检查通过。交互测试直接调用 Coordinator，尚未覆盖真正点击 UIAlertAction 时系统自动关闭的 transitionCoordinator 分支；Mac 必须实际点击验证三段删除接续。Menu 勾选/副标题/VoiceOver 与 Form 多 Section 行背景也须运行检查，现有 17 项测试不能替代这些验收。
- 撤回上一轮将 60 处 alert、7 处 confirmationDialog 与 Menu/contextMenu 一律列为「待替换」的计划：原生本身不是缺陷。后续只针对实际主题不适配、不可读、流程错误或多套 App 自绘设计改动，不机械全替换。Mac 上需先编译/XCTest，再真实点击预算确认和账本三段删除、获取同数据前后图；此后再做全 App 视觉判断。
- P0 机器合同的允许平台差异同步纳入原生材质/弹窗菜单/sheet/Form/Picker 和无障碍；财务数据、入口、字段与信息层级禁替代要求不变，没有关闭任何开放门。
- 用户授权后，36个精确路径提交为 `2389bae835e0a8b69b360964bb7579d6fee4aefd`，已推 `origin/codex/budget-takeover` 并复验远端一致；未混入 Android 源码、产物、图片及后端规划，未合入 main、改版本或发布 VPS。
- Mac [iOS CI 37028494081](https://github.com/xunnia/feimiao/actions/runs/37028494081) 和[双端截图 37028493722](https://github.com/xunnia/feimiao/actions/runs/37028493722) 已触发；读取一次时排队，最终编译/XCTest/截图结果未验，不自动轮询。工作流增加 `xcresulttool export attachments`，可下载原始附件与 xcresult；不是只有测试代码就能称截图通过。
- 改前基线 CI `37008733173` 已实际查询为成功（`04a92a1`），iOS 源码/工作流与修改前 `8a4ac23` 无差异。38规定场景+23额外原图已下载到 `ios-app/outputs/ui_comparisons/2026-10-02-native-theme/before/`；metadata记录 iPhone Air和固定fixture。61 PNG合计49,511,777字节，图片不入 Git。当前只有改前原图，尚无本批改后/编号前后图及真实按钮操作证据；Android 96组组件前后图不替代 iOS 验收。

### 2026-10-02 预算接手批次（优先于下文旧快照）

- 后续用户已授权本批提交/推送及 Android v1.309.0+324 正式发布；两端源码一并提交并推至 `codex/budget-takeover`，Android VPS 公网复验通过。iOS CI `37008733173` 已触发，Mac 编译/XCTest/截图最终结果仍未验收，不把当前改动直接合入 main。Android 发布不能解除这些门禁，最新发布证据见 `02` §7.11。
- 本地分支 `codex/budget-takeover`，Android 基线 `1f455c5` / v1.308.0+323 / DB v50。承接 Claude 在途预算 UI，未恢复分类预算、固定预留或专项追踪；未升版本、推送或发布。
- iOS 源码已同步：六套主题、浓度/透明度、新用户 80% 且保留已存 40%、主题静态卡片/输入、胶囊分段、选择菜单、常驻字段名；预算三屏与历史影响范围/原→新预览、日常规则名称、跨日及前台刷新。日常 AI 服务商配置不隐藏、不覆盖。
- 预算建议复用净额投影和账本范围，退款冲原单、排除不计入预算和外币，先整元再整百；首日没有可比计划不做节奏评价。迁移只选实际生效 V2 来源，已有 v50 不自动重迁，见 `08` §6.12。
- 本机只能检查源码、路由和契约：38 路由匹配；P0 合同结构有效，仍是 `P0_PARTIAL` / 6 个开放门。新增 XCTest 未运行；Windows 无 Swift/Xcode，尚无本批 iOS 编译、模拟器截图或真机证据。不得以 Android 测试通过替代 iOS 验收。
- 未封板差异：iOS 金额仍用系统 rounded 字体，没有 Nunito 资源；Mac 编译/XCTest、三屏同数据前后图与真实交互未验，本批不代表全 App 公共 UI 已收口。原生确认框按同日最新要求保留，不再作为必须替换成 Android 自绘卡的缺口。
- 后端主池/记一记池、稳定 Key 及设备会话方案只作依赖与契约评估；当前未接入。最新规划、建议与已定边界见 `02` §7.9。

### 2.1 总体结论
- 状态是 **`P0_PARTIAL`，属于开发预览版**。P1–P6 都还没有完整的关闭证据。旧文档里的“70%–75% 完成度”已经被 09-12 复盘作废（没有可审计的分母），**不要再引用任何完成百分比**。
- 工程：`ios-app/project.yml` → XcodeGen，App 名“肥喵记账”，Bundle ID `com.qingji.app`（加 `.share` / `.widget` / `.tests`），**部署目标 iOS 26.0**，仅支持 iPhone，版本 **`1.286.0+300`**（落后 Android 很多）。
- 技术栈：SwiftUI + SwiftData（`QingJi`）+ 平台无关规则包 `QingJiCore`（SwiftPM）+ `QingJiWidget` + `QingJiShare` + App Intents。只有 App Group 权限，**没有 iCloud 权限**。
- 规模（main）：约 172 个 Swift 文件、37 个测试文件。根视图 `RootTabView` 实际是 NavigationStack + 抽屉，**没有 TabView**（名字是历史遗留）。

### 2.2 各领域已有什么（“有代码”≠“验收通过”）
| 领域 | 代码状态 | 还缺什么 |
|---|---|---|
| 壳层/抽屉/品牌组件 (P1) | 有抽屉、暖色背景、玻璃按钮 | 更像覆盖式 iOS 面板；系统蓝/纯白卡/SF Symbol 混用，要统一 token 和组件 |
| 首页/记账/明细/退款报销/账本账户分类标签 (P2) | 基本都有；退款挂在原单上、按原单日期归属 | 同 fixture 逐字段对账、真实操作链、重启读回 |
| 统计/预算/存钱/定时/导入/备份/报告/设置/主题 (P3) | 大部分有；09-25~26 补了可选月度统计卡片、月热力图（已进 main） | 统计卡片顺序、图表形式、语义色和分类标签仍与 Android 有差异；预算管理页骨架不对；六套主题、显示设置不全；旧库升级和 Android 备份恢复还没实测 |
| 资产/负债/对账/净资产 (P4) | 基础档案、还款、快照都有；09-27~28 补了资产-资金分组页、添加入口、新购物品与支出原子写入、账单分配、估值默认值（已进 main） | 需要新一轮截图验证资金页；借贷往来/房贷向导/退款分摊只在 `codex/ios-p1-integration` 候选分支上 |
| AI/OAuth/系统能力 (P5) | Keychain、多服务商、Chats、PKCE OAuth、Widget、Share、Intent、OCR、Speech 都有基础版 | AI 设置 10 个入口层级不全；真实网络/OAuth/扩展**都没在真机跑过** |
| 交付 (P6) | CI 能出**未签名** IPA（完整版 + 无扩展兜底版） | 没签名、没装过真机、**没有 `PrivacyInfo.xcprivacy`**（发布阻断项） |

### 2.3 代码分散在哪里（重要）
> ⚠️ 仓库在 GitHub 迁移时改写过历史，各分支和 main 的“领先/落后 N 个提交”数字没有意义（都显示两三百）。下面是按**文件内容**比对出来的结果。旧文档里的提交号（如 `72f14808`、`0600683`、`32beb69`）在新仓库里可能已经找不到了——**待核实**。

| 位置 | 分支/状态 | 里面有什么 | 合入主线了吗 |
|---|---|---|---|
| `main`（远端默认分支） | 最新 iOS 提交 `96edaec`（09-03） | 09-03 的 P0 取证门禁；41 场景清单；`p0/P0_BASELINE_DECISIONS.md` | —（就是主线本身） |
| 主工作区 `C:\src\xunni-codex` | 已切到 `main`（2026-09-27） | `ios-app/` 就是 main 的版本 | —（开发 iOS 仍建议从 main 开独立 worktree） |
| 分支 `codex/screenshot-stability` | `df55463`（09-28，已推送） | UI 工作线：统计卡片、月热力图、资产资金分组页、物品添加与账单分配、截图链路加固 | ✅ 09-28 已合入 main；09-23 方案修订与截图验收记录的要点已并入本文 |
| worktree `.tmp/ios-p1-integration` | **`codex/ios-p1-integration`**（`2cb4b97`，09-19） | 把抢救回来的 P1 功能（借贷 `LendingView`、房贷向导 `LoanWizardView`、资产退款分摊 `AssetRefundAllocationStore`、预算 V2 等）接入；软删除修复 `820e6d3`；和 main 差 93 个文件 | ❌ 未合入，只是**候选**。09-28 已全部提交并推送（含 `stats/custom` 路由别名修复和软删除修复记录） |
| worktree `.tmp/fix-parity` | `codex/fix-parity-gates`（`c118ce4`，09-08，已推送） | 截图门禁的小修（7 个 iOS 文件） | ❌ 未合入；和上面两条线都不是祖先关系，是否已被吸收**待核实** |
| 分支 `codex/ios-same-app` | 09-05 | 09-02 方案指定的 P0 集成分支 | ✅ 内容已等同于 main 的 iOS 部分（无差异） |
| 分支 `rescue/ios-p1-2026-08-31` | 08-31 | 14 个 P1 提交（预算 V2、资产退款分摊、借贷、房贷向导、权益详情、备份加固…） | ❌ 未合入；已被 `ios-p1-integration` 吸收了多少**待核实**。⚠️ 本地和远端同名分支**已分叉**（本地 `2673c4c` / 远端 `ac364e8`），哪个才是真的**待核实** |
| 目录 `salvaged-2026-09-06/ios-app/` | 09-12 整理时已移出 main；原文件仍在本机旧工作目录和 `.tmp/repo-cleanup-20260912/all-refs.bundle` | 24 个文件，其中 **`BudgetSpecialTracking.swift`（预算专项追踪）在所有分支都不存在**；`BookCovers` 图集只有 json 没有图 | ❌ README 要求：确认能编译、补齐图片、跑过 CI 之前不要拷回去 |
| 目录 `salvaged-2026-09-06/from-worktree-ios-batch15/` | 同上，不在 main | FeiMiao 那套实现的收尾改动 | ❌ 只能当参考 |
| tag `archive/ios-feimiao-rewrite-2026-07` | 已归档 | 第一次重写 `FeiMiao/` + `FeiMiaoKit/`（GRDB、`com.feimiao.app`、0.2.0） | 🚫 **禁止**整体采用 |
| `ios-app/安装包/FeiMiao-unsigned.ipa` | main 里还跟踪着 | FeiMiao 那套的旧安装包 | 容易被误认成当前产品，建议后续清理（本次不动） |

### 2.4 被复盘推翻的旧说法（以后别再引用）
| 旧说法（出处） | 现在的结论 |
|---|---|
| “Parity #61 的 39/39 已成对截图 = 已完成”（PARITY、MATRIX、SCREENSHOT_MATRIX） | 只能证明 PNG 存在、能打开。当时 iOS 导入复核页其实显示的是首页、Android 截图有透明黑底、两端 fixture 金额不一致、有的场景拿相近页面顶替 |
| 完成度 70–75% / 50–55% / 35–40%（08-31 执行合同） | 09-12 作废，不报百分比 |
| 用 SF Symbols 替代 Android 的手绘图标（迁移方案 §4.1） | 禁止。Logo、猫、分类图标、账本封面必须用肥喵自己的素材 |
| TabView + `tabBarMinimizeBehavior`（iOS 27 核验） | 违反“没有底部 Tab”；当前代码已不用 TabView |
| 用 `Form`/`List`/大标题做设置类页面 | 禁的是**换掉信息架构**，不是禁用 List/Form 控件本身（09-23 修正） |
| iOS 不直接读 Android SQLite，只走 canonical JSON（迁移方案 §3.3） | 后来已实现 Android v1/v2 原始 SQLite ZIP 的只读转换；但真实备份恢复**还没实测** |
| README 写“加上 CloudKit 就自动同步” | P0 决定：本地优先，没有 iCloud 权限；在权限、冲突/删除、断网测试都齐之前，不许宣称会同步 |
| “没有 Mac 就装不了” | 09-23：Windows 也可能通过 AltStore 这类工具用自己的 Apple 账号重签，但**还没有真机成功过** |
| 以 Android 1.270/1.281/1.289/1.293 为基线 | 都是历史快照；每批重新锁定母版（见 §3.4） |
| 31 个 / 35 个 / 39 个场景 | 现在的合同是 **38 个静态场景 + 12 条用户旅程**（09-29 两端删掉统一搜索、技能与连接、本地模型伴侣，从 41 减到 38）（`ios-app/tools/p0_product_contract.json`，在 main 和两条候选分支上都有；主工作区那份 `ios-app/` 是 09-06 旧快照，看不到这个文件）。这是**范围**，不是已通过的数量 |

---

## 3. 执行规则（同款合同）

### 3.1 禁止
- 删除、合并、改名或挪动 Android 已有的入口；增加底部 Tab；另做第二套首页。
- 用系统默认风格把肥喵工作台页面改成另一套信息架构。原生控件、菜单、弹层及 Liquid Glass 可以优先使用；App 内容底/品牌色应跟主题，不以改默认 Section 为由重排入口。
- 用静态页面、mock 数据、demo 直接跳转来冒充功能已经打通。
- 维护两套生产数据层 / 两个 Bundle ID（`FeiMiao`、GRDB、`com.feimiao.app` 一律不进生产）。FeiMiao 只能**逐个文件**移植纯 UI 和素材，而且要先和当前 Android 对一遍。
- 把 CI 绿灯、PNG 数量、生成了 IPA 当成“产品完成”。
- 为了让 UI 好做，去改分类 key、UUID、退款关系、备份格式或 OAuth 安全边界。

### 3.2 数据安全
- 老用户的 `QingJi` 数据必须**原地升级**，不许换库、清库。每次 schema 变更都要有：用旧提交生成的真实旧库去打开的升级测试、附件完整性测试、失败回滚测试。“新建库再重新打开”不算升级测试。
- 所有冲减类记录（退款/报销）的日期都算在**原订单那天**；金额用 Decimal，不用 Double。

### 3.3 Git 与协作
- 主工作区里有别人正在改的 Android 代码：**禁止** `git add -A`、整体 stash、reset、clean、整分支 merge。iOS 改动只在各自的 worktree 里做，精确地 stage `ios-app/**` 和 iOS 工作流。
- 每批只做一条完整用户链路，或 2–4 个关系紧密的页面；每批都要能单独回退。同一时间最多只能有一个“视觉还没封板”的 UI 批次。
- Windows 上没有 Swift/Xcode，本机只能做 diff 和 Python 门禁脚本；**必须等 macOS CI 跑完才能写“编译/测试通过”**。不许自动轮询 CI（用户已经拒绝过）。

### 3.4 母版冻结
分清三个身份：**线上 APK**（版本 + 哈希）、**源码快照**（干净的 SHA）、**截图构建**（实际构建时的 SHA + fixture）。版本号一样不代表这三者一致。每批冻结一个 Android 参考版本；Android 的新变化进入“增量差异队列”，只在批次边界上升级母版。Android 本身的 bug 不照抄，要登记并确认正确规则。

### 3.5 阶段（09-23 修订后）
- **P0** 拆成三部分：**P0-DEV**（开发准入：基线、入口、fixture、改前截图、回退点）、**P0-DATA**（升级/恢复样本和回滚合同）、**P0-DEVICE**（装机可行性）。它们阻止的只是各自影响的结论，不会把整个项目锁死。
- **P1** 壳层/品牌/组件 → **P2** 核心记账 → **P3** 统计预算导入备份设置 → **P4** 资产 → **P5** AI/系统能力 → **P6** 集成交付。
- 立即执行队列：**N0** 收尾周/月统计 → **N1** 锁定母版身份 → **N2** 证据与机器合同同步（N2-D 数据安全、N2-I 真机试装**并行**）→ N3–N8 对应 P1–P6。
- **09-23 方案复盘的结论**：方向正确，不推倒已有代码，也不降低同款目标。改的是执行规则，共 15 条：拆开 P0 的循环等待；当前状态和历史分开写；母版按批冻结；「有图」不等于「功能完成」；冷启动截图和真实点击分开验收；旅程 ID 统一用机器合同里的 12 个；「Mac 编译」和「用户装机」分开；完整包和无扩展包都要检查数据身份；禁的是换掉信息架构，不是禁用 List/Form；统计默认卡片顺序照 Android 源码；不报完成百分比；不建自动轮询。机器合同（`p0_product_contract.json`）里的 6 个开放门还没按新的 P0-DEV/DATA/DEVICE 改写，这是 N2 的工作。

---

## 4. 验收方式

### 4.1 三类证据分开算
1. **截图**：同 routeId、同 fixture、同逻辑时间的 Android 原图 + iOS 改前图 + iOS 改后图 + 并排对比图，每张都带 metadata（源码 SHA、版本、fixture 哈希、设备、系统、语言、时区）。两端分辨率不同（1080×1920 对比 1260×2736），报告里的 `dimension_mismatch` 表示“**还没做视觉判断**”，不是通过。**有 UI 的交付必须把图直接给用户看。**
2. **交互**：冷启动直接跳到目标页只能证明“页面画得出来”。点击、返回、保存必须是真实操作（XCUITest / 模拟器交互 / 用户真机录屏），并且重启后查库确认。
3. **业务**：两端导出字段 JSON 逐字段对比。只有 `platform` 这类来源字段可以列入白名单；金额、日期、主键、关联字段不许被忽略。

固定 fixture：`p0-demo-ledger-2026-08-v1`，时间 `2026-08-27T12:00:00+08:00`，zh-Hans / 上海时区 / CNY / 总账本；期望 收入 620.00、支出 1017.90、结余 −397.90、预算 3000.00。启动参数 `QINGJI_DEMO=1`、`QINGJI_DEMO_NOW`，路由用 `QINGJI_SCREEN`。

### 4.2 CI 怎么跑
- **`.github/workflows/ios-ci.yml`**：推送 `claude/** codex/** feature/** main` 且改动了 `ios-app/**` 时触发，也可以手动触发。在 `macos-26` 上跑（优先用 Xcode 27，没有就用 26.x）：QingJiCore `swift test` → 模拟器编译 → App XCTest → 模拟器截图 → 未签名 IPA（`QingJi-unsigned.ipa` 完整版 + `QingJi-noext.ipa` 去掉扩展和 entitlements 的兜底版）→ 上传为 Actions Artifacts。09-12 起不再自动提交回分支；Artifacts 会过期，长期证据要另行归档。
- **`.github/workflows/parity-screenshots.yml`**：Android 模拟器（分片）+ iOS 模拟器各自采集 → 核对来源 → `ios-app/tools/compare_png.py --require-complete` → 生成可视化对比图和 P0 基线报告 → 上传为 Artifacts（不回写分支）。两个工作流共用同一个并发组，不会互相抢着写。
- 相关工具：`ios-app/tools/screenshot_manifest.json`、`check_route_manifest.py`、`check_p0_product_contract.py`、`write_parity_metadata.py`、`check_capture_metadata.py`。
- 最近一次完整的双端采集：run `35508046549`（`76e093f`，在 screenshot-stability 线上）：41 个场景里 40 对有图，全部是 `dimension_mismatch`，`assets-funds` 缺失；业务 diff 只有 `platform` 一项。**这次运行没有验证 P1 候选分支。** 那次的原始 PNG 还没归档到本机，Actions 保留期过后会丢。
- **截图链路的防假成功机制**（09-12 起）：
  - Android 41 个场景拆成 5 批、各用新 AVD，每批最多 9 个、同时最多 2 批。每批成功后才写完成凭据；汇总时缺批次、图片重复、跨提交、fixture/版本/业务数据不一致都会拒绝。
  - simctl 启停和截图加 45 秒超时，超时按失败处理，不把空白截图当成功。启动前先结束旧进程（`--terminate-running-process`）。
  - 对比任务 checkout 固定触发 SHA，不用新源码解释旧截图。
  - 截图模式下 Android 不弹更新对话框（`main.dart` 的 `_parityCapture`）。
  - 收到「页面就绪」日志不等于截图成功；连续两次完整通过之前，不宣称截图稳定。

### 4.3 真机验收
用户的环境：Windows、没有自己的 Mac、没有付费开发者账号、iPhone Air、iOS 27 预览版（具体 build 号**待核实**，测试前记录下来）。
最小试装链：用户自己输入凭据 → 核对 IPA → 重签，检查 Bundle ID / Team / App Group → 安装、冷启动 → 记几笔合成账目 → 重启后数据还在 → 导出恢复点 → 续签/更新后再查一遍。**不要让用户先卸载唯一有数据的那个 App**；改了 Bundle ID 或签名 Team 就等于换了一个安装身份，不能承诺能覆盖升级。免费 Personal Team 签名 **7 天过期**。
交付分四级：①工程能跑 ②指定功能在模拟器验收通过 ③用户设备上可安装的预览版（写明限制）④最终同款交付。③不等于④。

---

## 5. 上架路线要点（摘自 Obsidian《Fable5 给我的 iOS 上架路线》，09-26）
> ⚠️ 这份笔记是**按 Flutter 写的**（`flutter run` / `ios/Runner`），但我们的 iOS 是原生 SwiftUI，那些 Flutter 步骤不适用；笔记里“纯本地、不联网、不收集数据”的前提，也和肥喵的 AI 联网功能冲突。下面只保留仍然适用的部分。
- **账号**：Apple ID 开双重认证 → Apple Developer 个人账号（每年约 ¥688）→ 在 App Store Connect 签付费协议、填税务和银行 → 申请小型企业计划（抽成 30%→15%）。
- **Mac**：打包归档、上传需要 Xcode。GitHub macOS CI 能编译；CI 签名归档上传要把证书放进 Secrets，可行性**待核实**；也可以借用或租用 Mac。
- **Bundle ID 上架后永远不能改**，备案也要填它。现在是 `com.qingji.app`，要不要换成肥喵自己的 ID 必须**在备案和首次上架前定死**（**待用户决定**）。
- **只支持 iPhone**（工程已经是 `TARGETED_DEVICE_FAMILY=1`）。
- **提审必备**：`PrivacyInfo.xcprivacy`（现在**缺**）；权限说明文案（相机/相册/麦克风/语音已经写好）；`ITSAppUsesNonExemptEncryption=false` 已经设置（有 HTTPS 联网时这样填是否合规**待核实**）。
- **隐私标签**：因为有 AI 联网（会把用户选择的内容发给第三方模型），**不能简单选“不收集数据”**，要按实际情况申报（**待核实**）。
- **中国大陆上架**：需要 ICP 备案（域名要用 .com/.cn + 轻量服务器放官网和 https 隐私政策页）→ App 备案（填 App 名 + Bundle ID）→ 把备案号填进 ASC。备案要等 2–4 周，建议**尽早并行启动**。
- **内购**（如果要做“Pro 买断”）：非消耗型 + 必须有“恢复购买”按钮；原生用 StoreKit 2。收费范围和价格是**产品决策、待定**。
- **先走 TestFlight 内部测试**，再提审。记账类 App 常见的拒审原因：功能没做完/显示“敬请期待”、没有恢复购买、隐私说明敷衍、**明显的 Android 风格控件**、截图和实际不符。
- 年成本大约 ¥850–1100（账号 + 域名 + 服务器，不含 Mac）。

---

## 6. 待办与风险

**近期待办（按顺序）**
1. ~~保全各 worktree 的未提交/未推送内容~~：09-28 已完成，`ios-p1-integration` 的改动已提交并推送（`092cfa1`、`c3ba50c`），`screenshot-stability` 的文档已提交（`df55463`）。
2. N0：收尾周/月统计（最终 CI 结果、原图、核对数字、真实点击下钻）。
3. N1：锁定 Android 母版（线上 APK 哈希 ↔ 干净源码 ↔ DB 版本），整理 308→当前版本的增量队列。
4. 把 `codex/ios-p1-integration`（功能候选：借贷、房贷向导、资产退款分摊、预算 V2 等）逐项移植进 main。UI 线已先合入；候选分支不整支 merge，防止冲掉 main 已有的改动。
5. 处理 `BudgetSpecialTracking.swift` 这类只存在于 salvaged 目录的孤本；核实 rescue 分支本地/远端分叉的问题。
6. N2：同步机器合同（`p0_product_contract.json` 的 6 个开放门禁）、检查器、README/BASELINE 里过期的 304/308 数值；把原始截图归档到 `.tmp` 以外的地方（Actions 的产物会过期）。
7. 并行：旧库升级 + Android v40/v48/当前版本备份的恢复实测；第一次真机试装。
8. 补 `PrivacyInfo.xcprivacy`；iOS 版本号追上 Android。

**风险**
- 代码分散在 3 个 worktree + 2 个分支 + 1 个抢救目录，而且 GitHub 迁移改写了历史，**最容易出现的事故是功能丢失或整支覆盖造成回退**。
- 09-12 那次，`84ae9f1` 的 App XCTest 失败过，原因是 SwiftData 的 `isDeleted` 冲突，已由 `820e6d3` 改名为 `isSoftDeleted`；但**旧库升级还没被证明**。
- Android 一直在往前走（313），iOS 在追一个移动的目标 → 必须按批冻结母版。
- iOS 27 预览版 + 免费签名 + 扩展（App Group）能不能装得上，完全未知。无扩展兜底包是否会改变 App Group / Keychain / 数据库路径，**待核实**。
- 后台能力（定时报表、定时记账）在 iOS 上不保证准时，文案不能夸大。

---

## 7. Liquid Glass / iOS 27 技术约束（要点）
- `glassEffect(_:in:)`、`GlassEffectContainer`、`glassEffectID`、`.buttonStyle(.glass/.glassProminent)` 都需要 **iOS 26.0+**，所以部署目标定在 26.0 就能覆盖 iOS 27，不用锁死 27。真正用到 iOS 27 专属 API 时，才需要 Xcode 27 SDK。
- 玻璃只用在**导航/输入栏/关键操作/分类筛选胶囊**这类控件层；账单内容卡不要层层叠玻璃，要保证可读性。成组的控件放进 `GlassEffectContainer`（性能更好、还能互相融合变形）。
- Liquid Glass 主要服务于控件/导航层。原生效果更好时优先使用，允许系统确定菜单/弹层的排版、圆角与材质；功能、信息层级、品牌素材、账务语义与入口不变。内容层跟主题，原生材质可保留中性色，不叠实色背景遮挡玻璃，也不向系统内部子视图写私有样式。
- 官方依据：[Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)、[SwiftUI Menu](https://developer.apple.com/documentation/swiftui/menu)。10-02 实际读取：标准组件自动采用新系统外观，减少自定义外壳背景，支持菜单副标题，并验证减弱动态/透明度设置；没有据此宣称每一种弹层都一定透明或已完成真机验收。
- 性能验收和视觉验收分开：性能要用同一份数据集的真实耗时或 XCTest measure 来比，不能拿截图当性能证据。
- 公开的 GitHub runner 只有 `macos-26` 标签，没有 `xcode-27` 标签；工作流会自动挑 Xcode 27，没有就回退到 26.x。模拟器通过不代表 iOS 27 真机没问题；动态效果、触觉、字体、安全区最终要在 iPhone Air 真机上验收。
