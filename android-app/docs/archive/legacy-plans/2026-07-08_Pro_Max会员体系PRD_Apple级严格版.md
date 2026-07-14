# 肥喵记账 Pro / Max 会员体系 PRD（Apple Review Grade 严格版）

版本：v1.0  
日期：2026-07-08  
状态：仅文档，不进入实现  
适用工程：`C:\src\xunni-codex\android-app`  
前置说明：本 PRD 是给产品评审、Claude/Codex 后续实现和人工复核使用的“严肃需求文档”。在用户明确说“开始做”之前，不应实现会员、登录、支付或优惠码。

---

## 0. 结论先行

### 0.1 推荐路线

肥喵记账应该采用：

| 阶段 | 策略 | 是否登录 | 是否真实收费 | 核心原因 |
|---|---|---:|---:|---|
| P0 | 本地 Free + 会员 UI 占位 + 权益埋点 | 否 | 否 | 不打断现有用户，先验证功能分层和付费点 |
| P1 | 服务端账号 + 权益系统 + 支付沙盒 | 可选 | 沙盒 | 先把账号、权益、额度、收据校验做对 |
| P2 | Pro / Max 正式订阅 | 会员需要 | 是 | AI、云同步、报告、自动记账都需要服务端保障 |
| P3 | 官方优惠码 + 朋友赠送 + 企业/家庭方案 | 需要 | 是 | 解决送朋友会员、活动推广和长期增长 |

### 0.2 最重要的产品原则

1. **记账本体不能被会员墙破坏。** 基础记账、账单查看、本地导入导出、基础统计必须继续可用。
2. **会员卖的是“省心、洞察、自动化、跨设备可靠性”，不是把原本好用的东西锁起来。**
3. **AI 成本必须可控。** 所有 AI 功能都要走服务端额度账本，不能只靠客户端开关。
4. **本地数据属于用户。** 会员到期不能删除用户数据，只降级未来能力。
5. **登录必须有理由。** Apple 指南要求非账号核心功能不应强制登录；肥喵的 Free 本地功能应免登录，云同步、会员、跨设备、优惠码才需要登录。
6. **iOS 数字订阅必须优先使用 App Store 内购和官方 offer code；Android 上架 Google Play 时使用 Play Billing 和 Google promo code；直装 APK 可另做服务端优惠码，但要和商店版本隔离。**

---

## 1. 背景与目标

### 1.1 背景

肥喵记账已经开始进入复杂功能阶段：

- AI 记账、AI 问账、AI 报告会产生模型成本。
- 小组件、自动记账、定时记账、资产管理会产生长期维护成本。
- 云同步、跨设备、备份恢复、报告文档库需要服务端能力。
- 用户明确希望有 Pro / Max 不同等级，并希望可通过优惠码给朋友开会员。

旧文档 `docs/2026-07-07_资产定时自动会员执行蓝图.md` 已有高层权益矩阵，但缺少：

- 登录必要性分析
- 支付渠道和平台审核约束
- 优惠码实现方案
- 服务端数据模型
- 成本测算
- 退款、降级、恢复购买、风控
- Apple 级验收标准

### 1.2 目标

本 PRD 要回答：

1. Free / Pro / Max 分别给什么功能？
2. 哪些功能可以本地做，哪些必须服务端？
3. 是否必须登录？什么时候登录？
4. 支付怎么做？iOS、Google Play、直装 Android 分别怎么处理？
5. 优惠码怎么做，能不能送朋友会员？
6. 成本分别是什么？
7. 怎么避免被破解、刷额度、滥用 AI？
8. 怎么设计 UI 才符合肥喵现有风格和 Apple 级标准？

### 1.3 非目标

本 PRD 不实现：

- 真实登录
- 真实支付
- 真实优惠码
- 服务端代码
- 会员页面代码

本 PRD 只定义未来实现标准。

---

## 2. 官方约束与事实依据

### 2.1 Apple

- Apple Developer Program 年费为 `99 USD / year`，官方页面写明该会员可分发 App 和数字服务。参考：https://developer.apple.com/programs/
- App Store Small Business Program 对符合条件的小开发者提供 `15%` 抽成，条件包括上一日历年收益不超过 `1,000,000 USD`。参考：https://developer.apple.com/app-store/small-business-program/
- Apple App Review Guidelines 要求：如果 App 没有显著账号型功能，应允许用户不登录使用；如果支持创建账号，也必须在 App 内提供账号删除。参考：https://developer.apple.com/app-store/review/guidelines/
- Apple 对使用第三方登录的 App 有等效登录要求；如果使用 Google/微信等第三方登录，需要评估是否也要提供 Sign in with Apple。参考：https://developer.apple.com/app-store/review/guidelines/
- Apple 订阅 offer code 支持一次性 code 和自定义 code，可用于免费或折扣订阅；每个 App 每季度最高 `1,000,000` 次兑换，one-time code 有创建批次和有效期限制，custom code 可设置兑换上限和有效期。参考：https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-subscription-offer-codes
- Apple promotional offers 可用于召回、升级或给已有/过期订阅用户提供优惠，但每个订阅 SKU 同时最多 `10` 个 active offers。参考：https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-promotional-offers-for-auto-renewable-subscriptions/

### 2.2 Google Play

- Google Play Console 注册费为 `25 USD` 一次性。参考：https://support.google.com/googleplay/android-developer/answer/6112435
- Google Play 订阅服务费一般为 `15%`，并且 2026-06-30 起 EEA/UK/US 有新的服务费结构；剩余市场在全球更新前仍按现行结构。参考：https://support.google.com/googleplay/android-developer/answer/112622
- Google Play promo code 支持一次性 code 和 custom code；订阅促销可提供 `3-90` 天免费试用，订阅一次性 code 每季度每个订阅产品最多 `10,000` 个，custom code 可设置 `2,000-99,999` 的兑换上限。参考：https://support.google.com/googleplay/android-developer/answer/6321495

### 2.3 服务端与 AI 成本

- Firebase Spark 计划有无成本额度；Authentication 非短信登录可在免费额度内使用，Phone Auth 按 SMS 计费；Firestore 有每日读写和存储免费额度；Cloud Functions 有调用免费额度；FCM 无成本。参考：https://firebase.google.com/pricing
- DeepSeek V4 Flash / Pro 按 token 计费，官方价格以每 1M token 为单位，且 DeepSeek 明确价格可能调整。参考：https://api-docs.deepseek.com/quick_start/pricing

### 2.4 竞品事实样本

- YNAB：订阅制，`109 USD/year` 或 `14.99 USD/month`，强调无广告、不卖数据、34 天试用、家庭/亲密关系分享。参考：https://www.ynab.com/pricing
- Monarch：订阅制，强调不卖财务数据、无广告、数据连接质量和家庭/协作管理；页面可见首年优惠 code。参考：https://www.monarch.com/pricing
- Copilot Money：订阅制，强调自动分类、订阅识别、资产/投资/net worth、漂亮图表和无广告；定价页面可见约 `95 USD/year`、`13 USD/month`。参考：https://www.copilot.money/#pricing-dark

---

## 3. 竞品模式拆解

### 3.1 订阅型个人财务 App 的共性

| 产品 | 付费逻辑 | 用户买单点 | 可借鉴 | 肥喵不能照搬 |
|---|---|---|---|---|
| YNAB | 单一订阅 | 方法论、预算纪律、银行导入、家庭共享 | “用户不是商品”、长期陪伴、清晰价值承诺 | 中国用户未必接受高价年费和强预算方法论 |
| Monarch | 单一/分层订阅 | 家庭协作、数据连接、长期计划 | 隐私承诺、家庭成员、资产视图 | 银行连接在国内落地难度高 |
| Copilot | 单一订阅 | 自动分类、精致 UI、资产/投资、订阅识别 | 高审美、自动化、AI-like 智能归类 | 价格体系偏美国市场 |
| 国内记账 App | Free + 会员 | 图表、账本、预算、导入、云同步、小组件 | 更适合国内用户习惯，可多档位 | 常见问题是会员墙太碎、广告感重 |

### 3.2 对肥喵的启发

1. 肥喵不应像传统工具只卖“更多按钮”，应卖“更少操作”。
2. Pro 应该像效率层：更多 AI、更多报告、更强小组件、自动化待确认。
3. Max 应该像管家层：深度报告、资产高级分析、云同步、AI 后台生成、优先模型、跨设备可靠性。
4. Free 必须足够能用，才能建立信任。
5. 定价页面必须说明“不卖数据、不塞广告、不把用户财务数据用于广告画像”。

---

## 4. 用户分层

### 4.1 Free 用户

画像：

- 日常手动记账
- 偶尔导入账单
- 只在一台手机使用
- 还没有建立强记账习惯

需求：

- 快速记一笔
- 查看本月支出/收入
- 账单搜索
- 本地备份/导入导出
- 基础统计

不能被会员墙阻断：

- 新增/编辑/删除账单
- 本地账本
- 基础分类
- 基础预算
- 基础统计
- 本地导入导出

### 4.2 Pro 用户

画像：

- 已经高频记账
- 希望少打字、少整理
- 关心报告和小组件
- 愿意为省时间付费

需求：

- AI 记账额度更高
- AI 问账更快更准
- 标准周报/月报/年报
- 多样式桌面小组件
- 自动记账待确认池
- 定时记账增强
- 导入复核效率提升

### 4.3 Max 用户

画像：

- 长期使用，资产较复杂
- 关心资产、负债、预算、趋势和复盘
- 希望像“财务管家”一样自动提醒和分析
- 可能有家庭/伴侣共同管理需求

需求：

- 深度报告
- 资产高级分析
- 云同步和跨设备
- 后台生成报告并通知
- 高置信自动入账
- 预算异常预警
- 更高级 AI 模型和更高额度
- 未来家庭共享/多成员

---

## 5. 权益矩阵

### 5.1 总体矩阵

| 能力 | Free | Pro | Max |
|---|---:|---:|---:|
| 手动记账 | 不限 | 不限 | 不限 |
| AI 记账 | 每月 30 次 | 每月 600 次 | 每月 3000 次 |
| AI 问账 | 每月 20 次 | 每月 300 次 | 每月 1500 次 |
| AI 聊天闲聊 | 轻量，本地/低成本模型 | 标准 | 标准 |
| 敏感问题限制 | 全等级一致 | 全等级一致 | 全等级一致 |
| 标准月报 | 每月 1 份 | 不限 | 不限 |
| 周报/年报 | 预览 | 不限 | 不限 |
| 深度报告 | 不支持 | 每月 3 份 | 每月 20 份 |
| 报告后台生成 | 不支持 | 支持 | 支持，优先队列 |
| 小组件 | 基础总览 1-2 个 | 多样式小组件 | 全量小组件 + 高级数据 |
| 当前统计第一个图小组件 | 预览 | 支持 | 支持 |
| 自动记账 | 不支持 | 待确认池不限 | 高置信自动入账可开 |
| 定时记账 | 基础规则 3 条 | 不限 | 不限 + 智能建议 |
| 资产管理 | 基础账户/实物资产 | 权益资产、负债增强 | 高级资产分析、估值历史 |
| 云同步 | 不支持 | 1 台主设备 + 手动云备份 | 多设备自动同步 |
| 本地备份 | 保留最新 3 个 | 保留最新 10 个 | 保留最新 30 个 + 云备份 |
| 导入导出 | 基础 CSV/肥喵 JSON | 高级导入复核 | 批量规则和自动归类 |
| 账本数量 | 3 个 | 20 个 | 不限 |
| 预算数量 | 基础 | 多预算周期 | 多预算 + 异常预警 |
| 客服/反馈 | 普通 | 优先 | 最高优先 |

### 5.2 推荐首版额度

额度不要一开始太激进，应能覆盖真实用户又防止滥用：

| 类型 | Free | Pro | Max | 说明 |
|---|---:|---:|---:|---|
| AI 记账 | 30/月 | 600/月 | 3000/月 | 1 天 20 笔已经很高频 |
| AI 问账 | 20/月 | 300/月 | 1500/月 | 问账比记账更耗上下文 |
| 标准报告 | 1/月 | 不限 | 不限 | 标准报告成本可控 |
| 深度报告 | 0 | 3/月 | 20/月 | 深度报告消耗更大 |
| OCR 导入识别 | 10/月 | 300/月 | 2000/月 | 可后续调参 |
| 自动记账规则 | 0 | 不限待确认 | 不限 + 高置信自动入账 | 自动入账需要风控 |

### 5.3 到期/降级规则

1. Pro/Max 到期后自动降级 Free。
2. 历史账单、资产、报告文档不删除。
3. 超出 Free 限额的数据只读保留，例如第 4 个账本仍可查看，但新增账本需要升级或删除至限制内。
4. 云同步到期后：
   - 继续保留云端数据 90 天；
   - 用户可导出；
   - 90 天后进入冷归档；
   - 删除前至少 App 内提示 + 邮件/通知提醒。
5. AI 报告到期后历史报告可查看，不能新生成深度报告。

---

## 6. 价格策略

### 6.1 建议价格

首版建议按中国个人工具心理价位，不直接照搬 YNAB/Copilot：

| 档位 | 月付 | 年付 | 定位 |
|---|---:|---:|---|
| Free | 0 | 0 | 本地记账基础体验 |
| Pro | ¥12/月 | ¥98/年 | 高频记账效率层 |
| Max | ¥28/月 | ¥228/年 | AI 财务管家层 |

### 6.2 为什么不是更高价

1. 肥喵还在早期，用户信任尚未完全建立。
2. 国内用户对记账 App 的付费心理价位低于美国订阅制财务 App。
3. Pro 的核心是省时间，价格应低到用户少喝一杯奶茶即可接受。
4. Max 是长期价值和 AI 成本覆盖，不能太低，否则深度报告和云同步会亏。

### 6.3 可选一次性买断

不建议首版提供买断。

原因：

- AI、云同步、服务端、报告生成都有持续成本。
- 买断容易制造长期负债。
- 后续如果成本上涨，会伤害老用户和产品可持续性。

可替代：

- 早鸟终身折扣：如首年 ¥68 Pro，续费保持 ¥68。
- 创始用户 Max 年费固定价：如前 500 名 ¥168/年。

---

## 7. 登录体系

### 7.1 是否需要登录

| 场景 | 是否需要登录 | 理由 |
|---|---:|---|
| 本地记账 | 否 | 不应强制账号 |
| 本地导入导出 | 否 | 数据在设备内 |
| 本地基础统计 | 否 | 没有账号价值 |
| 购买会员 | 是 | 需要绑定权益 |
| 恢复购买 | 是/平台账号 | 需要匹配订单和用户 |
| 云同步 | 是 | 必须有用户身份 |
| 跨设备 | 是 | 必须合并/同步 |
| 优惠码 | 是 | 防止重复兑换和转卖 |
| AI 高额度 | 是 | 防止刷接口 |
| 报告后台生成 | 是 | 服务端任务需要归属 |

### 7.2 登录方式建议

P1：

- Apple：Sign in with Apple
- Android：Google 登录 + 邮箱验证码
- 国内直装 APK：邮箱验证码优先，暂不做手机号验证码

暂不推荐：

- 手机号验证码：成本高，容易被刷，隐私负担大。
- 微信登录：需要开放平台资质，审核和维护复杂；若上 iOS 还要处理 Apple 等效登录要求。

### 7.3 账号删除

只要支持账号创建，就必须在 App 内提供：

- 删除账号入口
- 删除前风险说明
- 会员和退款说明
- 云端数据删除/导出说明
- 7 天冷静期可选

删除范围：

- 用户 profile
- 云同步数据
- AI usage ledger
- 优惠码兑换记录
- 设备绑定
- 报告云副本

不应删除：

- 法务要求保留的支付流水摘要
- App Store / Google Play 原始交易记录的最小审计字段

---

## 8. 支付体系

### 8.1 iOS

必须优先：

- StoreKit 2
- Auto-renewable subscriptions
- App Store Server Notifications
- App Store receipt / transaction 校验
- 官方 subscription offer codes

不建议：

- App 内引导用户去微信/支付宝购买数字会员。
- 私下收款后在 iOS App 内解锁数字功能。

### 8.2 Google Play

必须优先：

- Google Play Billing
- Play Developer API 校验订阅状态
- Real-time developer notifications
- Google Play promo code

### 8.3 国内 Android 直装 APK

可选路线：

1. 微信/支付宝网页支付或小程序支付。
2. 服务端订单系统。
3. 服务端权益发放。
4. 与 Google Play 包名/渠道隔离。

风险：

- 退款、发票、对账成本上升。
- 被破解和盗刷风险更高。
- 如果未来上架应用商店，需要按商店规则切换支付。

### 8.4 恢复购买

必须有：

- 设置页“恢复购买”
- 会员页“恢复购买”
- 启动时静默刷新权益
- 购买成功后立即刷新 entitlement
- 网络失败时保留最近一次有效 entitlement cache

### 8.5 退款

规则：

- App Store / Google Play 退款以平台通知为准。
- 服务端收到退款/撤销后，权益到期时间回滚或立即失效，按平台状态处理。
- 用户本地数据不删除。
- AI 已消耗额度不追扣到负数，但退款后未来额度停止。

---

## 9. 优惠码与送朋友会员

### 9.1 推荐方案

| 分发渠道 | 推荐优惠码方式 | 是否支持送朋友 | 说明 |
|---|---|---:|---|
| iOS App Store | Apple subscription offer codes | 是 | 官方合规，适合送朋友 |
| Google Play | Google Play promo codes | 是 | 官方合规，支持订阅免费试用 |
| Android 直装 APK | 肥喵服务端优惠码 | 是 | 仅直装渠道，不能混淆 App Store 权益 |
| 内测/朋友 | 服务端 invite code + 平台 offer code | 是 | invite code 记录关系，真正解锁仍走平台 |

### 9.2 Apple 方案

适用：

- 送朋友 1 个月 Pro
- 送朋友 3 个月 Max
- 首年折扣
- 过期用户召回

限制：

- 官方 offer code 有创建和有效期规则。
- one-time code 适合小规模赠送。
- custom code 适合活动，但要设置上限。
- 不应把自建 coupon 当作 iOS 数字订阅的直接解锁来源。

### 9.3 Google Play 方案

适用：

- 订阅免费试用 3-90 天。
- 一次性 code 或 custom code。

限制：

- custom code 仅适用于订阅，且只能在 App 内兑换。
- 必须清楚展示活动条款。

### 9.4 肥喵自建优惠码

仅用于：

- 直装 APK
- 内测用户
- 客服补偿
- 非商店数字商品场景

字段：

```text
coupon_codes
- id
- code_hash
- campaign_id
- tier: pro|max
- duration_days
- max_redemptions
- redeemed_count
- starts_at
- expires_at
- channel: ios|google_play|direct_android|internal
- created_by
- status: active|paused|expired|revoked
- notes

coupon_redemptions
- id
- coupon_id
- user_id
- device_id
- redeemed_at
- entitlement_id
- ip_hash
- user_agent_hash
- status
```

风控：

- code 只存 hash，不存明文。
- 每账号每天最多尝试 10 次。
- 每设备每天最多尝试 10 次。
- 同一活动每账号只可兑换一次。
- 黑名单 code 立即失效。
- 客服后台可以撤销未使用 code，已使用 code 不影响已发放权益，除非判定作弊。

---

## 10. 服务端架构

### 10.1 为什么必须有服务端

会员不能只写在本地 SQLite：

- 容易被改。
- 无法跨设备恢复。
- 无法校验支付状态。
- 无法限制 AI 额度。
- 无法管理优惠码。
- 无法处理退款。

### 10.2 推荐 P1 技术路线

优先选 Firebase：

- Auth：邮箱/Apple/Google 登录。
- Firestore：用户、权益、额度账本。
- Cloud Functions：支付 webhook、AI 代理、优惠码兑换。
- FCM：报告完成通知、会员到期提醒。
- Remote Config：灰度功能和价格展示开关。
- Crashlytics/Analytics：稳定性和转化漏斗。

原因：

- 与 Android/Flutter 集成成熟。
- FCM 无成本。
- 初期免费额度足够。
- 避免一开始自建全套后端。

### 10.3 数据模型

```text
users
- id
- created_at
- deleted_at
- primary_email_hash
- display_name
- auth_providers
- locale
- timezone
- status

devices
- id
- user_id
- platform
- app_version
- push_token
- last_seen_at
- status

subscriptions
- id
- user_id
- platform: apple|google|direct_android|internal
- product_id
- tier: free|pro|max
- status: active|grace|billing_retry|expired|refunded|revoked
- starts_at
- expires_at
- auto_renew
- original_transaction_id
- latest_transaction_id
- purchase_token_hash
- environment: sandbox|production
- updated_at

entitlements
- id
- user_id
- tier
- source_subscription_id
- source_coupon_id
- valid_from
- valid_until
- status
- feature_flags_json

usage_ledger
- id
- user_id
- feature_key
- amount
- unit: call|token|report|ocr
- period_key: 2026-07
- source: ai_record|ai_query|report|ocr|auto_record
- request_id
- created_at

ai_requests
- id
- user_id
- feature_key
- model
- input_tokens
- output_tokens
- cache_hit_tokens
- cost_usd_estimate
- status
- created_at

payment_events
- id
- platform
- event_type
- raw_event_hash
- parsed_json
- processed_at
- status

coupon_codes
- id
- code_hash
- campaign_id
- tier
- duration_days
- max_redemptions
- redeemed_count
- channel
- starts_at
- expires_at
- status

coupon_redemptions
- id
- coupon_id
- user_id
- redeemed_at
- entitlement_id
- status
```

### 10.4 本地缓存

App 本地只缓存：

```text
membership_cache
- tier
- valid_until
- last_verified_at
- grace_until
- feature_flags_json
- signature
```

规则：

- 本地 cache 可离线使用最多 72 小时。
- 超过 72 小时仍不能联网时，高成本功能停用，低成本功能保留。
- cache 必须带服务端签名，防止直接改本地数据库。

---

## 11. 成本测算

### 11.1 固定成本

| 项目 | 成本 | 备注 |
|---|---:|---|
| Apple Developer Program | 99 USD/年 | 上 iOS 必需 |
| Google Play Console | 25 USD 一次性 | 上 Google Play 必需 |
| 域名 | 约 ¥50-100/年 | 视域名而定 |
| 服务端 P0 | 可接近 0 | Firebase 免费额度可支撑早期 |
| 支付平台抽成 | 约 15%-30% | 取决于平台、地区、资格 |

### 11.2 AI 成本估算

以 DeepSeek V4 官方价格粗估：

| 场景 | 模型 | 估算 token | 单次成本粗估 | 备注 |
|---|---|---:|---:|---|
| AI 记账解析 | V4 Flash | 输入 1.5k / 输出 0.3k | 约 $0.0003 | 可缓存 prompt |
| AI 问账 | V4 Flash | 输入 6k / 输出 1k | 约 $0.0011 | 取决于账单上下文 |
| 标准月报 | V4 Flash/Pro | 输入 20k / 输出 4k | $0.004-$0.012 | 可异步生成 |
| 深度月报 | V4 Pro | 输入 60k / 输出 10k | 约 $0.035 | 成本明显更高 |

粗估换算：

- Pro 用户如果每月 600 次 AI 记账 + 100 次问账 + 3 份深度报告，AI 成本可能在 `¥1-5/月` 区间，取决于上下文长度和 cache hit。
- Max 用户如果大量深度报告和问账，必须有额度，否则极端用户可能超过月费成本。

控制策略：

1. AI 记账走短 prompt。
2. 问账上下文只传聚合数据和命中账单，不传全量账单。
3. 报告生成走后台队列，限制并发。
4. 深度思考只给 Max 或 Pro 少量额度。
5. 自带 API Key 用户可绕过模型费用，但不能绕过会员权益。

### 11.3 服务端成本估算

P1 早期：

- Auth 邮箱/Apple/Google：预计免费额度内。
- Firestore：用户量 < 10k、同步低频时预计免费或极低成本。
- FCM：无成本。
- Cloud Functions：预计免费额度内或低成本。
- SMS：不建议首版做，避免短信计费和刷量。

P2 增长后：

| MAU | 预估服务端成本 | 关键变量 |
|---:|---:|---|
| 1,000 | 接近 0-¥100/月 | AI 才是主要成本 |
| 10,000 | ¥100-1000/月 | Firestore 读写、函数、存储 |
| 100,000 | 需要专项优化 | 同步策略、报告队列、冷热数据 |

---

## 12. 功能使用链路

### 12.1 首次遇到会员墙

原则：

- 不突然打断。
- 先解释“为什么值得”。
- 给用户继续 Free 的出口。

示例：

用户点击“生成深度月报”：

1. 检查 entitlement。
2. Free 用户看到 Pro/Max 说明弹窗。
3. 弹窗展示：
   - 当前功能：深度月报
   - 用户能得到什么：更完整的分类解释、异常分析、预算建议
   - Pro：每月 3 份
   - Max：每月 20 份 + 后台生成
4. 按钮：
   - 升级 Pro
   - 查看 Max
   - 稍后

### 12.2 会员页

入口：

- 我的/设置页
- AI 额度用完
- 报告功能
- 小组件高级样式
- 云同步入口

页面结构：

1. 顶部：当前状态
2. 核心价值：省时间 / 更懂消费 / 更安全
3. 三档卡片：Free / Pro / Max
4. 权益对比
5. 隐私承诺
6. 恢复购买
7. 使用条款 / 隐私政策

UI 标准：

- 不使用夸张营销英雄页。
- 采用 iOS 设置风格分组列表 + 清晰卡片。
- 价格和权益必须可扫读。
- 默认突出 Pro，Max 作为高级选择。
- 所有按钮命名必须明确，不用“立即解锁全部”这种不清楚表达。

### 12.3 优惠码兑换页

入口：

- 我的/设置页：兑换会员码
- 会员页底部：已有优惠码？
- 好友分享链接打开 App 后落地到兑换页

流程：

1. 输入 code。
2. 本地做格式校验。
3. 服务端验证。
4. 展示兑换结果：
   - Pro 1 个月
   - Max 3 个月
   - 已兑换/已过期/不适用渠道
5. 用户确认后写 entitlement。
6. 展示会员到期时间。

错误文案：

| 错误 | 文案 |
|---|---|
| 不存在 | 这个码好像不对 |
| 已过期 | 这个码已经过期 |
| 已用完 | 这个码已经被领完 |
| 已兑换过 | 你已经使用过这个活动 |
| 渠道不匹配 | 这个码不能在当前版本使用 |
| 网络失败 | 没连上服务，稍后再试 |

---

## 13. 权益检查规则

### 13.1 统一入口

所有会员判断必须走：

```text
EntitlementService.canUse(featureKey)
EntitlementService.consume(featureKey, amount)
EntitlementService.currentTier()
```

禁止：

- UI 直接读本地 bool。
- 某个页面自己写 Pro/Max 判断。
- AI 请求绕过 usage ledger。

### 13.2 功能 key

```text
ai.record.parse
ai.query.standard
ai.query.deep
report.weekly.standard
report.monthly.standard
report.monthly.deep
report.yearly.standard
report.yearly.deep
widget.home_card
widget.pace_chart
widget.category_activity
auto_record.pending_pool
auto_record.high_confidence_commit
cloud_sync.manual_backup
cloud_sync.multi_device
asset.equity
asset.advanced_analysis
recurring.unlimited_rules
```

### 13.3 额度周期

- 月度额度按用户本地时区自然月重置。
- 服务端以 UTC 存储，展示按用户 timezone。
- 订阅中途升级：立即获得新档位额度，已消耗不清零。
- 降级：当前订阅周期结束后降级。
- 退款：按平台状态立即调整。

---

## 14. 安全与风控

### 14.1 防破解

1. 高成本功能必须服务端校验。
2. 本地 entitlement cache 只做离线兜底。
3. AI 请求必须由服务端代理，不在客户端暴露主 API Key。
4. 会员权益 cache 必须签名。
5. 关键服务端接口需要 App Check / 设备校验。

### 14.2 防刷

1. 登录态限流。
2. 设备限流。
3. IP hash 限流。
4. AI 请求长度限制。
5. 报告生成队列限制。
6. 优惠码尝试次数限制。
7. 高风险账号进入人工复核。

### 14.3 隐私

1. 不将用户账单用于广告。
2. 不出售财务数据。
3. AI 上下文最小化。
4. 报告生成只传必要统计和命中明细。
5. 用户可删除云端数据。
6. 隐私政策要说明 AI 处理、服务端存储、支付验证、通知。

---

## 15. Apple 级体验标准

### 15.1 可理解

用户在 3 秒内要知道：

- 当前自己是什么会员
- 会员到期时间
- 当前功能为什么需要升级
- 升级后得到什么

### 15.2 不制造焦虑

禁止文案：

- 你的财务很危险
- 不升级就无法管理资产
- 现在不买就亏了

推荐文案：

- 让肥喵帮你少整理一点
- 深度报告会把这个月的变化讲清楚
- Max 更适合多资产和长期复盘

### 15.3 不误导

必须展示：

- 价格
- 计费周期
- 是否自动续费
- 试用结束后是否收费
- 取消方式
- 会员到期后的数据保留规则

### 15.4 可访问性

- 会员权益不能只靠颜色区分。
- 支持大字体。
- VoiceOver/TalkBack 能读出价格、周期、权益。
- 支付按钮必须有明确语义。

---

## 16. 实施计划

### P0：文档和本地门面

目标：

- 不真实收费。
- 不强制登录。
- 做清楚会员入口和 entitlement facade。

任务：

1. 新增 `membership_prd` 文档。
2. 新增 `EntitlementService` 本地假实现。
3. UI 只展示“会员能力即将开放”，不显示真实价格按钮。
4. 所有未来付费功能调用 `canUse(featureKey)`。
5. 测试覆盖 Free 默认权限。

### P1：账号和权益后端

目标：

- 支持登录。
- 支持服务端 entitlement。
- 支持 usage ledger。

任务：

1. Firebase Auth。
2. Firestore 用户表。
3. Cloud Functions 权益接口。
4. AI 代理接口。
5. 本地 signed cache。
6. 设置页登录/退出/删除账号。

### P2：支付沙盒

目标：

- iOS StoreKit 沙盒。
若 Android 上 Google Play：
- Google Play Billing 测试。

任务：

1. 商品 SKU。
2. 购买页。
3. 恢复购买。
4. Server Notifications。
5. 退款/续费/过期状态同步。
6. 审核 demo account。

### P3：正式会员

目标：

- Pro / Max 正式可购买。
- AI 额度正式扣减。
- 报告后台生成。

任务：

1. 正式环境开关。
2. 价格页。
3. 会员到期提醒。
4. 发票/客服说明。
5. 监控转化和退款。

### P4：优惠码

目标：

- 朋友赠送会员。
- 活动 code。

任务：

1. iOS official offer codes。
2. Google Play promo codes。
3. 直装 APK server coupon。
4. 兑换页。
5. 风控和后台。

---

## 17. 验收标准

### 17.1 产品验收

- Free 用户不登录也能完成完整本地记账闭环。
- 会员页不影响当前记账主流程。
- 用户能明确区分 Pro 和 Max。
- 会员到期不删除历史数据。
- 优惠码能说明来源、权益、有效期。

### 17.2 技术验收

- 所有权益判断走统一服务。
- AI 请求有 usage ledger。
- 服务端校验支付收据。
- 恢复购买可用。
- 退款后权益能更新。
- 本地 cache 有签名和过期时间。
- 断网时低成本能力可继续，高成本能力降级。

### 17.3 合规验收

- iOS 数字订阅走 IAP。
- Android Google Play 版本走 Play Billing。
- App 内有删除账号。
- 有隐私政策和使用条款。
- App Review notes 写清楚会员和 AI。
- 试用/优惠/订阅条款清晰。

### 17.4 成本验收

- 每个 AI 功能都有单次成本估算。
- 每个 tier 都有月度成本上限。
- Max 极端用户不会明显亏损。
- 服务端有成本告警。

---

## 18. 开放问题

1. 肥喵是否确定上 iOS？如果上 iOS，必须提前按 IAP 设计，不能后补。
2. Android 是否只做直装 APK，还是未来上 Google Play？
3. 是否需要家庭共享？如果需要，应作为 Max P2，不要首版做。
4. 是否允许用户自带 DeepSeek API Key？建议允许，但只绕过 AI 成本，不解锁会员权益。
5. 是否需要学生/朋友长期优惠？建议先用官方 offer code，不做复杂身份认证。
6. 是否做人民币定价为主？如果上国际商店，需要多区域价格表。

---

## 19. 关键决策记录

| 决策 | 结论 |
|---|---|
| 是否强制登录 | 不强制，Free 本地免登录 |
| 是否先做真实支付 | 否，用户确认后再做 |
| 是否做买断 | 不建议 |
| 是否允许优惠码送朋友 | 允许，但 iOS/Google Play 优先使用官方 code |
| 是否做自建优惠码 | 仅直装 APK、内测、客服补偿 |
| 是否本地判断会员 | 不允许，服务端为准，本地只缓存 |
| 是否自带 API Key 等于会员 | 不等于 |
| 是否会员到期删除数据 | 不删除 |

---

## 20. 下一步建议

最合理的下一步不是写支付代码，而是：

1. 先实现 `EntitlementService` 本地假门面，让未来功能都接同一权限入口。
2. 设计会员页静态 UI，但不放真实购买按钮。
3. 写 `AI 功能额度与敏感问题限制 PRD`，和会员权益打通。
4. 写 `通知管理 PRD`，会员到期、报告完成、记账提醒都进入统一通知设置。
5. 等用户确认“可以做会员”，再进入 P1 登录和服务端。

