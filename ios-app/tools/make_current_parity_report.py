#!/usr/bin/env python3
"""Build current Android/iOS parity images and a per-screen review report.

The Android and iOS apps are one product. This report separates acceptable
native-platform rendering differences from evidence that still needs a
business-field or build-baseline check.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image

TOOLS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR))

from make_ios_ui_comparisons import contact_sheet, parity_pair  # noqa: E402


ASSESSMENTS = {
    "home-overview": (
        "有（需修复：数据/证据）",
        "Android 显示月结余 -¥1,217.90、支出 ¥4,217.90 和 8月30日房租；iOS 显示月结余 ¥1,982.10、支出 ¥1,017.90，最近账目也不是同一批。顶部安全区和控件尺寸另有正常平台差异。",
        "两端没有使用同一份 fixture/执行状态，Android 多出 ¥3,200 房租；不能把金额差异归因于 iOS 原生渲染。",
        "先锁定同一源码提交、数据库 fixture、日期和账本，重新生成两端首页；金额、交易列表和预算口径一致后，再保留安全区/控件的原生差异。",
    ),
    "quick-add": (
        "有（平台外观）",
        "数字键盘、返回/AI 入口、输入卡圆角和底部安全区不同；支出记账的金额、分类、账户、日期和备注入口应保持同款。",
        "系统键盘和 SwiftUI/Flutter sheet 的布局由平台提供，不能用像素复制替代。",
        "统一字段顺序、默认支出状态和保存结果；分别按平台检查键盘遮挡、取消和保存。",
    ),
    "transactions": (
        "有（需修复：数据）",
        "Android 明细从 8月30日房租 ¥3,200 开始，iOS 从 8月27日的兼职收入/午餐开始；同一截图窗口里的交易集合和按天合计不同。列表卡宽度、字体和分隔线也有平台差异。",
        "Android 截图包含额外房租或使用了不同运行状态，iOS 截图不是同一账本快照。",
        "用同一数据库快照逐笔对账日期、商户、分类、金额、退款/报销净额和日合计；确认数据相同后才评估列表视觉。",
    ),
    "stats-week": (
        "有（需修复：数据）",
        "Android 周支出为 ¥3,246.00，iOS 为 ¥46.00；收入同为 ¥620，但净额、趋势和分类构成随之不同。图表比例和标签排布还有正常平台差异。",
        "两端周统计没有基于同一交易集合，Android 的 ¥3,200 房租被计入。",
        "固定同一周窗口和数据库快照，逐字段核对支出、收入、净额、分类和 7 天序列；数据一致后再收口图表布局。",
    ),
    "stats-month": (
        "有（需修复：数据）",
        "Android 月支出 ¥4,217.90、结余 -¥3,597.90，iOS 月支出 ¥1,017.90、结余 -¥397.90；分类环图和每日趋势也不是同一数据。月份控件尺寸另有平台差异。",
        "Android 多计入 ¥3,200 房租，且两端截图基线没有锁定到同一数据库状态。",
        "统一 fixture 后逐字段对账月支出、收入、结余、分类和每日序列；不要先改图表样式掩盖数据问题。",
    ),
    "stats-year": (
        "有（需修复：数据）",
        "Android 年支出 ¥6,058.90，iOS 年支出 ¥2,858.90，差额正好为 ¥3,200；年度趋势和分类排行因此不一致。刻度与图表比例另有平台差异。",
        "Android 和 iOS 年度统计读取了不同交易快照，Android 多了房租记录。",
        "用相同年度窗口和 fixture 对账 12 个月序列及分类金额；修正数据后保留图表渲染差异。",
    ),
    "stats-custom": (
        "有（需修复：数据）",
        "Android 自定义区间支出 ¥4,217.90，iOS 为 ¥1,017.90；两端起止日期显示同为 8月1日到8月30日，但结果不同。日期控件和图表排版另有平台差异。",
        "相同日期窗口下交易集合不一致，Android 多了 ¥3,200 房租。",
        "先固定同一数据库和区间，逐项对账总额、分类和趋势；确认日期包含规则一致后再处理控件视觉。",
    ),
    "budget": (
        "有（需修复：数据）",
        "Android 显示本月已超 ¥1,217.90、支出 ¥4,217.90；iOS 当前期间显示支出 ¥1,017.90，未超预算。预算卡结构和 sheet 排布也不同。",
        "两端预算计算使用了不同交易快照，Android 多计入 ¥3,200 房租；预算是同一产品的业务口径，不能接受这个差异。",
        "统一账本、预算期间和交易 fixture，逐字段对账总额、今日可花、分类预算和 occurrence，再保留原生 sheet 布局。",
    ),
    "reconcile": (
        "有（需修复：页面身份）",
        "iOS 是真正的“对账”页面；Android 截图标题为“资产管理”，实际展示资产管理的资金 tab，根本不是同一页面。",
        "Android parity 测试明确用资产管理 hub 的 tab 代替对账路由，属于测试取证错误，不是允许的平台差异。",
        "先让 Android 截图真实进入对账页，再与 iOS 同一 fixture 对账账面余额、实际余额和校准结果；禁止用资产页替代。",
    ),
    "reimburse": (
        "有（平台外观）",
        "待报销列表卡、金额对齐、按钮和安全区不同；待报销笔数、金额、原账单日期和净额口径必须一致。",
        "两端列表和金额排版不同。",
        "核对原支出与待报销金额、状态和日期；保持平台原生列表，不把按钮位置差异当成业务缺陷。",
    ),
    "savings": (
        "有（需修复：计算显示）",
        "两端目标名称、已存 ¥6,800 和目标 ¥12,000 相同，但 Android 显示 57%，iOS 显示 56%；卡片、进度条和按钮尺寸也不同。",
        "56.666...% 的舍入规则不一致：一端四舍五入，另一端疑似截断。",
        "统一进度百分比的舍入规则和测试断言，再保留卡片与原生按钮的布局差异。",
    ),
    "recurring": (
        "有（需业务核对）",
        "规则卡、日期/频率文本和操作入口不同；规则、下次执行日、金额、分类和归档状态必须一致。",
        "原生列表排版不同，后台调度也存在平台能力差异。",
        "先对账规则数据和幂等物化结果，再分别验证 Android 后台调度与 iOS 前台/本地提醒替代。",
    ),
    "assets": (
        "有（需修复：信息层级/状态）",
        "两端都在“物品”tab 且显示没有物品，但 iOS 额外显示当前净资产 ¥25,561.10 的摘要卡，Android 没有；筛选和空态布局也不同。",
        "iOS 资产页加入了 Android 截图中不存在的摘要层，说明两端信息架构没有完全按 Android 母版对齐。",
        "按 Android 母版统一资产页层级；如果保留摘要，先在 Android 同步实现并纳入同一字段验收，不能只在 iOS 增加。",
    ),
    "liabilities": (
        "有（需修复：页面身份）",
        "iOS 是真正的“负债管理”空态页；Android 截图标题为“资产管理”，实际展示资金 tab 和账户余额，不是负债页。",
        "Android parity 测试用资产 hub 代替负债路由，导致两端没有在比较同一页面。",
        "先捕获 Android 真正的负债页，再核对负债本金、余额、还款入口及净资产影响；禁止用资产资金页顶替。",
    ),
    "net-worth": (
        "有（需修复：数据/信息层级）",
        "Android 净资产为 ¥22,361.10，iOS 为 ¥25,561.10，差额为 ¥3,200；两端摘要结构也不同。",
        "两端交易快照不一致，Android 多计入房租；同时 iOS 使用了更完整的摘要卡，未完全遵守 Android 母版层级。",
        "统一 fixture 后对账现金、投资、物品、权益、负债和净资产；按 Android 母版决定摘要层级，再保留平台卡片样式。",
    ),
    "books": (
        "有（需修复：页面身份）",
        "两端截图都显示打开的抽屉和首页背景，不是独立的“账本管理”列表；Android 还显示抽屉中的“我的账本”入口。",
        "截图路由/场景命名把抽屉账本入口当成账本管理页，属于证据不对齐。",
        "明确该场景是“抽屉账本入口”还是“账本管理页”；若验收账本管理，双方都进入真实列表并核对总账本、封面、备注、星标和删除保护。",
    ),
    "accounts": (
        "有（需修复：页面身份）",
        "iOS 是“账户管理”页面；Android 截图标题为“资产管理”，展示资金 tab。虽然能看到相同账户余额，但不是同一入口/页面。",
        "Android parity 测试把账户管理映射为资产 hub 的资金 tab，无法证明 Android 的真实账户管理页与 iOS 同款。",
        "分别捕获 Android 真实账户管理页和 iOS 对应页，再核对账户类型、余额、排序、归属账本和对账入口。",
    ),
    "categories": (
        "有（需业务核对）",
        "收支切换、分类行高、emoji/图标和新增入口不同；稳定 key、层级、名称、隐藏状态和排序必须一致。",
        "图标字体与列表组件不同；分类 key 是历史账单依赖，不能只看名称像不像。",
        "用分类 key/parent key 对账，再分别检查新增、隐藏和恢复；不要改动历史 key 来追求视觉一致。",
    ),
    "tags": (
        "有（平台外观）",
        "标签行、删除/编辑操作和新增入口的留白不同；标签名称、排序和关联账单效果必须一致。",
        "不同端的列表与操作热区布局不同。",
        "对账标签列表和排序持久化结果；保持统一交互语义，允许原生热区大小差异。",
    ),
    "settings": (
        "有（功能外观）",
        "设置分组、导航行、开关和版本/数据管理入口不同；所有功能入口和危险操作语义必须覆盖一致。",
        "iOS 使用 SwiftUI 设置行，Android 使用 Flutter 设置组；备份格式和系统能力存在平台边界。",
        "逐入口核对功能覆盖，再测试备份/恢复真实副作用；平台限制明确标注为替代方案。",
    ),
    "ai": (
        "有（平台外观）",
        "Chats 列表卡、顶栏按钮、搜索/新聊天入口和输入区比例不同；会话列表与进入记账聊天的入口必须一致。",
        "原生导航、字体和底部输入栏安全区不同。",
        "统一会话数据、入口名称和操作结果；保留原生导航与键盘差异。",
    ),
    "ai-settings": (
        "有（需修复：信息架构）",
        "Android 是包含 AI 账号、用途分配、隐私数据、任务中心、诊断、搜索、记忆、技能、定时报表和本地模型等入口的总设置页；iOS 只展示 AI 与喵助手账号/迁移页。",
        "iOS 当前把多个 Android AI 设置入口收进了不同层级或尚未暴露，不能仅用原生设置行差异解释。",
        "按 Android 母版逐项补齐或明确映射全部入口，再逐账号核对非敏感字段、模型目录和连接测试；不要暴露密钥。",
    ),
    "import-review": (
        "有（需修复：页面身份）",
        "Android 是真实的“导入复核”页，显示支付宝来源、自动归类/待确认/退款统计、入账账户和待分类商户；iOS 截图实际是首页。",
        "iOS 截图路由没有进入 `settings/import-review`，文件名不能证明页面身份。",
        "先修 iOS 冷启动路由并重新截图，确认出现真实复核页后，再逐行核对商户、金额、分类、账户和退款匹配。",
    ),
    "reports": (
        "有（需核对：内容/平台外观）",
        "Android 使用玻璃半屏报告库，iOS 使用原生报告列表；两端都显示 2026年8月月报，但 Android 卡片未显示 iOS 图中的支出/收入摘要。",
        "报告库呈现方式可以是平台差异，但报告摘要字段是否缺失属于同款信息内容问题。",
        "统一报告标题、期间、支出、收入、结余和生成状态；保留 Android sheet 与 iOS NavigationStack 的原生呈现。",
    ),
    "memory": (
        "有（平台外观）",
        "学习映射列表、删除入口和空态排布不同；商户到分类的映射内容、删除结果和历史账单影响必须一致。",
        "设置列表和操作热区的原生布局不同。",
        "逐条对账映射并验证删除不改历史；只统一信息层级。",
    ),
    "ai-tasks": (
        "有（平台外观）",
        "任务卡、状态徽章、时间信息和详情入口不同；任务阶段、状态、配置摘要和失败脱敏信息必须一致。",
        "卡片与状态标签在两端使用不同组件。",
        "对账任务状态机和错误摘要；不要为了视觉一致显示密钥、完整提示词或原始思考。",
    ),
    "ai-diagnostics": (
        "有（需核对：状态）",
        "Android 显示 DeepSeek 诊断项 `0/0`；iOS 显示“还没有 AI 运行记录”，两端空状态表达和诊断范围不同。",
        "可能是同一空数据的不同呈现，也可能是服务商/运行记录 fixture 不一致；截图不能直接证明两端状态相同。",
        "固定同一 AI 运行记录 fixture，统一服务商、运行次数、失败状态和脱敏摘要；空数据文案可按平台排版适配。",
    ),
    "ai-search": (
        "有（平台外观）",
        "搜索框、结果分组、筛选入口和空态不同；账单、对话和 AI 任务的搜索范围、排序和结果必须一致。",
        "搜索控件和结果列表使用不同端的输入/导航组件。",
        "统一搜索语义和结果字段；分别处理键盘、返回和结果点击。",
    ),
    "ai-memory": (
        "有（功能外观）",
        "记忆开关、授权说明、记忆列表和删除入口不同；授权范围、上下文是否使用、删除结果必须一致。",
        "系统设置行与 Flutter 设置组件不同，隐私提示在两端可能有原生排版差异。",
        "逐项核对授权和删除副作用；平台文案可适配，但不能扩大记忆范围。",
    ),
    "ai-extensions": (
        "有（需修复：状态）",
        "Android 的记账助手、账本分析、账单导入、报告生成和联网搜索开关均为关闭；iOS 对应开关全部为开启，不能视为单纯控件颜色差异。",
        "两端使用了不同的设置初始状态或 fixture，导致 AI 行为开关不一致。",
        "统一默认值和 demo fixture，逐项验证开关对真实行为的影响；只有系统权限没有对应能力时才做明确平台替代。",
    ),
    "ai-schedules": (
        "有（平台功能外观）",
        "定时报表规则、时间选择和状态卡不同；计划、时区、启用状态和报告内容必须一致。",
        "Android 可交给 WorkManager，iOS 后台执行受系统限制，使用本地提醒/前台补算替代。",
        "对账计划数据和生成内容；把后台时机差异标为平台边界，不伪装成完全相同。",
    ),
    "ai-local": (
        "有（功能外观）",
        "本地模型地址、健康状态和操作按钮不同；回环地址、健康检查结果和明文 HTTP 安全策略必须一致。",
        "系统网络设置与输入控件不同。",
        "统一地址校验和健康状态；分别验证 Android/iOS 本机回环网络限制。",
    ),
    "backup": (
        "有（功能外观）",
        "备份选项、最近恢复点、文件选择器和危险操作提示不同；完整备份、附件、校验失败和回滚语义必须一致。",
        "文件选择器和沙盒路径是平台原生能力，不能像素统一。",
        "先用同一备份包验证导出/导入/失败回滚，再统一入口层级；文件路径差异按平台处理。",
    ),
    "theme": (
        "有（需修复：功能范围）",
        "Android 提供暖橙/简约白/樱粉/薄荷/雾蓝/暮夜背景色卡、背景浓度和卡片透明度；iOS 当前只显示跟随系统、浅色、深色和 Liquid Glass 预览。",
        "iOS 当前主题设置没有完整映射 Android 的主题枚举和调节项，不能全部归因于系统 Liquid Glass。",
        "以 Android 主题枚举、语义色和持久化结果为母版；iOS 可使用原生材质，但缺失的主题控制需要补齐或明确产品决策。",
    ),
    "display": (
        "有（平台外观）",
        "显示选项行、开关和示例区域不同；内容优先/分类优先、聊天气泡和字体策略必须一致。",
        "设置行、开关和字体度量不同。",
        "对账设置持久化后的首页/聊天效果；分别做 Dynamic Type/大字体和安全区检查。",
    ),
    "quick-add-income": (
        "有（平台外观）",
        "收入分段、键盘、金额色和分类/账户入口不同；收入类型、金额、分类、账户、日期和保存结果必须一致。",
        "系统键盘和收入语义色在原生实现中的排版不同。",
        "先对账保存后的交易和统计，再优化各端输入可用性；收入仍统一使用铜金语义。",
    ),
    "asset-detail": (
        "有（需修复：数据/信息层级）",
        "两端都是 iPhone Air 详情，但 Android 显示持有 96 天、¥72.91/天，iOS 显示持有 93 天、¥75.26/天；iOS 还展示了更完整的操作按钮和持有指标卡。",
        "截图日期/fixture 不同造成持有天数与日均成本不同，同时两端详情页信息层级未完全对齐。",
        "固定同一 as-of 日期和资产快照，逐字段对账估值、成本、持有天数、日均成本和关联账单；再按 Android 母版决定缺失操作是否补齐。",
    ),
    "account-detail": (
        "有（需业务核对）",
        "余额摘要、趋势、校准入口和流水活动的卡片比例不同；同一现金账户的余额、趋势和流水必须一致。",
        "iOS 使用原生 sheet/列表，Android 使用 Flutter 详情页。",
        "对账账户余额、趋势序列和活动流水；验证校准后两端状态一致。",
    ),
    "reimburse-settlement": (
        "有（需修复：数据/平台外观）",
        "两端到账金额都是 ¥68、账户都是现金，但 Android 到账日期为 2026/08/30，iOS 为 2026年8月27日 04:00；sheet、遮罩和输入控件也有正常平台差异。",
        "默认到账日期和时间 fixture 不一致，不能用原生日期控件差异解释。",
        "统一原订单、到账日期的 fixture 和日期语义，验证结算后原支出净额归零；再保留两端原生 sheet 外观。",
    ),
}


def _path_for(root: Path, directory: Path, pair: dict, side: str) -> Path:
    directory = directory if directory.is_absolute() else root / directory
    if side == "android":
        return directory / Path(pair["android"]).name
    return directory / Path(pair["ios"]).name


def _write_report(
    output_dir: Path,
    manifest_path: Path,
    android_dir: Path,
    ios_dir: Path,
    pairs: list[dict],
    artifact_names: list[str],
) -> None:
    rows = []
    for pair, artifact_name in zip(pairs, artifact_names):
        status, difference, reason, action = ASSESSMENTS.get(
            pair["id"],
            (
                "有（需人工核对）",
                "当前截图存在平台视觉差异。",
                "Android 与 iOS 使用不同原生渲染与安全区。",
                "先逐字段核对业务数据，再决定是否需要视觉收口。",
            ),
        )
        rows.append(
            {
                "id": pair["id"],
                "feature": pair.get("feature", ""),
                "status": status,
                "difference": difference,
                "reason": reason,
                "action": action,
                "android": str(_path_for(Path.cwd(), android_dir, pair, "android")),
                "ios": str(_path_for(Path.cwd(), ios_dir, pair, "ios")),
                "comparison": str(output_dir / artifact_name),
                "manifestNotes": pair.get("notes", ""),
            }
        )

    payload = {
        "productRule": "iOS is the native implementation of the same Android product; it is not a separate app.",
        "manifest": str(manifest_path),
        "androidDir": str(android_dir),
        "iosDir": str(ios_dir),
        "pairCount": len(rows),
        "screenshotsAreCurrentSourceEvidence": False,
        "baselineWarning": "Android source is 1.289.0+304 while the checked-in manifest still says 1.275.0+289; iOS screenshot build metadata is not embedded in the current image set.",
        "pairs": rows,
    }
    (output_dir / "parity-review.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    lines = [
        "# 肥喵记账 Android / iOS 当前截图对比",
        "",
        "结论口径：iOS 是 Android 产品的原生实现，不是另一款软件。以下“有差异”先区分视觉平台差异与业务证据差异；截图不能替代金额、字段和操作副作用对账。",
        "",
        f"- 对比数量：{len(rows)} 组",
        f"- Android 截图目录：`{android_dir}`",
        f"- iOS 截图目录：`{ios_dir}`",
        "- 基线警告：Android 当前源码为 `1.289.0+304`，manifest 仍是 `1.275.0+289`；iOS 截图未内嵌可核对的构建版本。因此本报告是当前可用截图证据，不是最终同提交验收。",
        "",
    ]
    for index, row in enumerate(rows, start=1):
        relative = Path(row["comparison"]).name
        lines.extend(
            [
                f"## {index:02d}. {row['feature']} (`{row['id']}`)",
                "",
                f"![{row['feature']}]({relative})",
                "",
                f"- 是否有差异：**{row['status']}**",
                f"- 差异：{row['difference']}",
                f"- 原因：{row['reason']}",
                f"- 应该怎么做：{row['action']}",
                f"- manifest 约束：{row['manifestNotes']}",
                "",
            ]
        )
    (output_dir / "parity-review.md").write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--android-dir", type=Path, required=True)
    parser.add_argument("--ios-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    pairs = manifest.get("pairs", [])
    if not pairs:
        raise SystemExit("manifest contains no pairs")
    args.output_dir.mkdir(parents=True, exist_ok=True)

    images = []
    artifact_names = []
    for pair in pairs:
        android_path = _path_for(args.root, args.android_dir, pair, "android")
        ios_path = _path_for(args.root, args.ios_dir, pair, "ios")
        if not android_path.exists() or not ios_path.exists():
            missing = [str(path) for path in (android_path, ios_path) if not path.exists()]
            raise SystemExit("missing parity screenshot(s): " + ", ".join(missing))
        with Image.open(android_path) as android, Image.open(ios_path) as ios:
            images.append(parity_pair(android, ios, f"{pair['id']} · {pair.get('feature', '')}"))
        artifact_name = f"parity-{pair['id']}.png"
        images[-1].save(args.output_dir / artifact_name, format="PNG", optimize=True)
        artifact_names.append(artifact_name)

    for sheet_index in range(0, len(images), 9):
        sheet = contact_sheet(images[sheet_index : sheet_index + 9], columns=3)
        sheet.save(
            args.output_dir / f"00-android-ios-parity-{sheet_index // 9 + 1:02d}.png",
            format="PNG",
            optimize=True,
        )

    _write_report(
        args.output_dir,
        args.manifest,
        args.android_dir,
        args.ios_dir,
        pairs,
        artifact_names,
    )
    print(f"generated {len(images)} parity images into {args.output_dir}")
    print(args.output_dir / "parity-review.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
