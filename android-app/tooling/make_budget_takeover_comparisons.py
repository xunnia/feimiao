"""Compare real budget Widget captures without modifying their originals."""

from pathlib import Path

from PIL import Image, ImageDraw

import make_ui_comparisons as ui


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "android-app/outputs/ui_comparisons/2026-10-02-budget-takeover"
PAIRS = [
    (
        "budget_main",
        "预算主页",
        [(28, 100, 356, 150), (28, 211, 359, 239), (27, 389, 360, 551)],
        [
            "1. 主金额取消负字距；过长金额缩放到可见宽度，完整金额保留。",
            "2. 已花 / 月预算继续左右对齐，窄屏或大字可换行，不互相挤压。",
            "3. 常规日历结构保持一致；大字增行高，花费列留间距，短安排可查看完整名称。",
        ],
    ),
    (
        "budget_rule_sheet",
        "新增规则弹层",
        [(13, 475, 377, 538), (18, 548, 373, 759), (18, 1083, 373, 1232)],
        [
            "1. 关闭 / 标题 / 保存位置保持一致，中文及图标字体完整显示。",
            "2. 已有名称、预算、单位与时间的字段层级保持一致。",
            "3. 本新建场景的预览保持一致；历史修改的影响月份、原值到新值另由流程测试验收。",
        ],
    ),
    (
        "budget_day_sheet",
        "某一天详情",
        [(15, 835, 375, 922), (15, 924, 375, 997), (15, 1008, 375, 1223)],
        [
            "1. 日期和规则归属保持一致；日期格新增读屏说明。",
            "2. 常规金额三格保持一致；格子装不下大金额 / 200% 大字时，改纵向同款格子。",
            "3. 提示与统一账单行保持一致，深色 / 樱粉底色见补充场景。",
        ],
    ),
]
SUPPLEMENTAL_TITLES = {
    "budget_calendar_short_rule": "单日长安排 / 320dp",
    "budget_day_narrow_large_text": "详情大金额 / 200% 大字",
    "budget_day_sheet": "某一天详情 / 常规",
    "budget_day_sheet_dark": "某一天详情 / 深色",
    "budget_day_sheet_pink": "某一天详情 / 樱粉主题",
    "budget_main": "预算主页 / 常规",
    "budget_main_dark": "预算主页 / 深色",
    "budget_narrow_large_text": "主页大金额 / 320dp / 200%",
    "budget_rule_sheet": "新增规则 / 常规",
    "budget_rule_sheet_dark": "新增规则 / 深色",
}


def build_pair(name, title, boxes, notes):
    before = Image.open(OUT / f"{name}_before.png").convert("RGB")
    after = Image.open(OUT / f"{name}_after.png").convert("RGB")
    if before.size != after.size:
        raise ValueError(f"capture dimensions differ: {before.size}, {after.size}")
    width = before.width * 2 + 96
    font = ui._font(16)
    probe = ImageDraw.Draw(Image.new("RGB", (width, 1)))
    lines = [line for note in notes for line in ui._wrap(probe, note, font, width - 48)]
    footer_height = 84 + 25 * len(lines)
    canvas = Image.new("RGB", (width, 104 + before.height + footer_height), "#f7f7f8")
    draw = ImageDraw.Draw(canvas)
    draw.text((24, 12), title, font=ui._font(23, bold=True), fill="#202124")
    draw.text((24, 45), "接手前（Claude 在途 UI）", font=ui._font(17), fill="#7c4d3a")
    draw.text((before.width + 72, 45), "本批优化后", font=ui._font(17), fill="#315f78")
    draw.text(
        (24, 74),
        "同数据 / 同尺寸 / 同字体；Flutter Widget 离屏渲染，非模拟器或真机截图",
        font=ui._font(13),
        fill="#70757a",
    )
    canvas.paste(ui._annotate(before, boxes), (24, 104))
    canvas.paste(ui._annotate(after, boxes), (before.width + 72, 104))
    y = 120 + before.height
    for line in lines:
        draw.text((24, y), line, font=font, fill="#4e5156")
        y += 25
    draw.text(
        (24, canvas.height - 27),
        "原图未修改；基线不是线上 v323；当前日常场景和补充边界场景分别记录",
        font=ui._font(13),
        fill="#70757a",
    )
    target = OUT / f"{name}_before_after.png"
    canvas.save(target, optimize=True)
    return target


def main():
    generated = [build_pair(*pair) for pair in PAIRS]
    ui.OUT = OUT
    contact = ui.build_contact_sheet(generated)
    supplemental = sorted(OUT.glob("*_after.png"))
    supplemental = [path for path in supplemental if not path.name.endswith("before_after.png")]
    cards = []
    for path in supplemental:
        original = Image.open(path).convert("RGB")
        thumb = original.resize((260, round(original.height * 260 / original.width)))
        card = Image.new("RGB", (280, thumb.height + 62), "#f7f7f8")
        title = SUPPLEMENTAL_TITLES[path.stem.removesuffix("_after")]
        ImageDraw.Draw(card).text((10, 10), title, font=ui._font(13), fill="#202124")
        card.paste(thumb, (10, 42))
        cards.append(card)
    row_heights = [max(card.height for card in cards[i:i + 3]) for i in range(0, len(cards), 3)]
    canvas = Image.new("RGB", (880, sum(row_heights) + 20 * (len(row_heights) + 1)), "#ececef")
    y = 20
    for row, row_height in zip(range(0, len(cards), 3), row_heights):
        for col, card in enumerate(cards[row:row + 3]):
            canvas.paste(card, (20 + col * 290, y))
        y += row_height + 20
    supplemental_target = OUT / "01_supplemental_contact.png"
    canvas.save(supplemental_target, optimize=True)
    for path in [*generated, contact, supplemental_target]:
        print(path)


if __name__ == "__main__":
    main()
