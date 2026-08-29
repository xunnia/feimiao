"""Create the before/after evidence set for the 2026-08-29 UI batch.

The source screenshots are copied into a dated evidence folder, resized for a
common phone canvas, and never overwritten. The comparison images are simple
PIL compositions with numbered orange annotations; no generated artwork is
used.
"""

from __future__ import annotations

import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "android-app" / "outputs" / "ui_comparisons" / "2026-08-29"
BEFORE_OUT = OUT / "before"
AFTER_OUT = OUT / "after"

USER_PICTURES = Path(
    r"C:\Users\寻逆啊\Documents\Tencent Files\948095682\nt_qq\nt_data\Pic\2026-08\Ori"
)

PHONE_SIZE = (390, 844)

PAIRS = [
    {
        "id": "01_chat_greeting_before_after",
        "title": "普通 Chats 进入态",
        "before": USER_PICTURES / "1c189f2d459019c085cc498fbc4c08b5.jpg",
        "after": OUT / "chat_empty_after.png",
        "before_boxes": [(12, 56, 378, 144)],
        "after_boxes": [(12, 56, 378, 144)],
        "notes": ["普通聊天不再显示主页‘本月超预算’提醒，只保留聊天输入区"],
    },
    {
        "id": "02_home_month_typography_before_after",
        "title": "主页大卡片·月份文字",
        "before": USER_PICTURES / "d89e1f2485d259410847b74b7f3cef26.jpg",
        "after": OUT / "home_summary_after.png",
        "before_boxes": [(24, 58, 142, 91)],
        "after_boxes": [(28, 17, 119, 43)],
        "notes": ["月份标签统一为 15px；数字 w500，年月文字保持常规字重"],
    },
    {
        "id": "03_home_budget_percent_before_after",
        "title": "主页大卡片·预算百分比",
        "before": USER_PICTURES / "d89e1f2485d259410847b74b7f3cef26.jpg",
        "after": OUT / "home_summary_after.png",
        "before_boxes": [(28, 265, 92, 292)],
        "after_boxes": [(31, 181, 76, 202)],
        "notes": ["超过 100% 时显示实际百分比，不再显示 100%+；按整数四舍五入"],
    },
    {
        "id": "04_month_picker_layout_before_after",
        "title": "月份选择器·布局",
        "before": USER_PICTURES / "e27e7723728349e088481d294d192cd2.jpg",
        "after": OUT / "month_picker_after.png",
        "before_boxes": [(0, 560, 390, 844)],
        "after_boxes": [(0, 258, 390, 844)],
        "notes": ["恢复之前的半屏月份选择布局，关闭按钮、标题、年份和月份网格层次清晰"],
    },
    {
        "id": "05_month_picker_arrows_before_after",
        "title": "月份选择器·年份箭头",
        "before": USER_PICTURES / "e27e7723728349e088481d294d192cd2.jpg",
        "after": OUT / "month_picker_after.png",
        "before_boxes": [(22, 636, 80, 696), (310, 636, 368, 696)],
        "after_boxes": [(24, 359, 65, 414), (325, 359, 366, 414)],
        "notes": ["左右年份箭头移除圆圈表面，仅保留 48dp 独立触控热区"],
    },
    {
        "id": "06_month_picker_close_before_after",
        "title": "月份选择器·关闭按钮",
        "before": USER_PICTURES / "e27e7723728349e088481d294d192cd2.jpg",
        "after": OUT / "month_picker_after.png",
        "before_boxes": [(24, 574, 78, 628)],
        "after_boxes": [(38, 288, 71, 322)],
        "notes": ["左上角关闭按钮按弹层头部内边距重新定位，与标题垂直关系统一"],
    },
    {
        "id": "07_chats_typography_before_after",
        "title": "Chats 会话列表",
        "before": USER_PICTURES / "e38f15290ae69ed46daae6225bd8306a.jpg",
        "after": ROOT / "android-app" / "outputs" / "chats" / "chats_current.png",
        "before_boxes": [(72, 70, 370, 126), (72, 133, 260, 162)],
        "after_boxes": [(80, 72, 300, 112), (80, 110, 230, 134)],
        "notes": ["Chats 标题字重加一档；会话标题保持 14px；相对时间字重仅加 50"],
    },
    {
        "id": "08_budget_overage_label_before_after",
        "title": "主页大卡片·超预算提示",
        "before": USER_PICTURES / "d89e1f2485d259410847b74b7f3cef26.jpg",
        "after": OUT / "home_summary_after.png",
        "before_boxes": [(28, 93, 145, 119)],
        "after_boxes": [(30, 52, 90, 70)],
        "notes": ["‘月预算已超’仍是灰色提示，但字重在原标准上增加 w50"],
    },
    {
        "id": "09_ai_account_delete_before_after",
        "title": "AI 账号设置·删除操作",
        "before": USER_PICTURES / "f120a301f02c6cf9eb0cc57022bd7649.jpg",
        "after": ROOT
        / "android-app"
        / "outputs"
        / "ai_account"
        / "ai_account_current.png",
        "before_boxes": [(249, 330, 330, 402)],
        "after_boxes": [(265, 382, 317, 445)],
        "notes": ["删除图标移除圆圈背景，保留独立触控热区并使用更柔和的灰色"],
    },
]


def _font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        Path(r"C:\Windows\Fonts\msyhbd.ttc" if bold else r"C:\Windows\Fonts\msyh.ttc"),
        Path(r"C:\Windows\Fonts\simhei.ttf"),
        Path(r"C:\Windows\Fonts\arial.ttf"),
    ]
    for candidate in candidates:
        if candidate.exists():
            try:
                return ImageFont.truetype(str(candidate), size=size)
            except OSError:
                pass
    return ImageFont.load_default()


def _fit_phone(path: Path) -> Image.Image:
    source = Image.open(path).convert("RGBA")
    # Flutter golden captures may leave the part outside the painted widget
    # transparent. Composite it onto the app's warm page background instead
    # of letting PIL turn those pixels black.
    page = Image.new("RGBA", source.size, "#fffaf2")
    image = Image.alpha_composite(page, source).convert("RGB")
    return ImageOps.fit(image, PHONE_SIZE, method=Image.Resampling.LANCZOS, centering=(0.5, 0.5))


def _annotate(image: Image.Image, boxes: list[tuple[int, int, int, int]]) -> Image.Image:
    annotated = image.convert("RGBA")
    overlay = Image.new("RGBA", annotated.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    badge_font = _font(15, bold=True)
    for index, (left, top, right, bottom) in enumerate(boxes, start=1):
        draw.rounded_rectangle(
            (left, top, right, bottom),
            radius=7,
            fill=(244, 132, 72, 28),
            outline=(221, 91, 48, 235),
            width=2,
        )
        radius = 11
        cx = min(right - radius, left + radius + 1)
        cy = min(bottom - radius, top + radius + 1)
        draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=(221, 91, 48, 245))
        bbox = draw.textbbox((0, 0), str(index), font=badge_font)
        draw.text(
            (cx - (bbox[2] - bbox[0]) / 2, cy - (bbox[3] - bbox[1]) / 2 - 1),
            str(index),
            fill="white",
            font=badge_font,
        )
    return Image.alpha_composite(annotated, overlay).convert("RGB")


def _copy_sources(pair: dict) -> tuple[Image.Image, Image.Image]:
    before = _fit_phone(pair["before"])
    after = _fit_phone(pair["after"])
    before_dir = BEFORE_OUT
    after_dir = AFTER_OUT
    before_dir.mkdir(parents=True, exist_ok=True)
    after_dir.mkdir(parents=True, exist_ok=True)
    before.save(before_dir / f"{pair['id']}.png", format="PNG", optimize=True)
    after.save(after_dir / f"{pair['id']}.png", format="PNG", optimize=True)
    return before, after


def _wrap(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.ImageFont, width: int) -> list[str]:
    lines: list[str] = []
    current = ""
    for char in text:
        candidate = current + char
        if current and draw.textlength(candidate, font=font) > width:
            lines.append(current)
            current = char
        else:
            current = candidate
    if current:
        lines.append(current)
    return lines or [""]


def build_pair(pair: dict) -> Path:
    before, after = _copy_sources(pair)
    before = _annotate(before, pair["before_boxes"])
    after = _annotate(after, pair["after_boxes"])
    gutter = 22
    header_h = 56
    footer_h = 88
    canvas = Image.new("RGB", (PHONE_SIZE[0] * 2 + gutter, header_h + PHONE_SIZE[1] + footer_h), "#f7f7f8")
    draw = ImageDraw.Draw(canvas)
    draw.text((12, 10), pair["title"], fill="#202124", font=_font(18, bold=True))
    draw.text((12, 34), "改动前", fill="#7c4d3a", font=_font(14, bold=True))
    draw.text((PHONE_SIZE[0] + gutter + 12, 34), "改动后", fill="#315f78", font=_font(14, bold=True))
    body_y = header_h
    canvas.paste(before, (0, body_y))
    canvas.paste(after, (PHONE_SIZE[0] + gutter, body_y))
    divider_x = PHONE_SIZE[0] + gutter // 2
    draw.line((divider_x, body_y, divider_x, body_y + PHONE_SIZE[1]), fill="#d4d5d8", width=2)
    footer_y = body_y + PHONE_SIZE[1] + 8
    draw.text((12, footer_y), "改动说明", fill="#202124", font=_font(13, bold=True))
    note_font = _font(12)
    line_y = footer_y + 20
    for index, note in enumerate(pair["notes"], start=1):
        for line in _wrap(draw, f"{index}. {note}", note_font, canvas.width - 24):
            draw.text((12, line_y), line, fill="#4e5156", font=note_font)
            line_y += 17
    target = OUT / f"{pair['id']}.png"
    OUT.mkdir(parents=True, exist_ok=True)
    canvas.save(target, format="PNG", optimize=True)
    return target


def build_contact_sheet(paths: list[Path]) -> Path:
    thumb_width = 410
    margin = 14
    gap = 14
    cards: list[Image.Image] = []
    for path in paths:
        image = Image.open(path).convert("RGB")
        scale = thumb_width / image.width
        cards.append(image.resize((thumb_width, round(image.height * scale)), Image.Resampling.LANCZOS))
    rows = [cards[index : index + 2] for index in range(0, len(cards), 2)]
    row_heights = [max(card.height for card in row) for row in rows]
    total_h = margin * 2 + sum(row_heights) + gap * max(0, len(rows) - 1)
    sheet = Image.new("RGB", (margin * 2 + thumb_width * 2 + gap, total_h), "#ececef")
    y = margin
    for row, row_h in zip(rows, row_heights):
        for column, card in enumerate(row):
            sheet.paste(card, (margin + column * (thumb_width + gap), y))
        y += row_h + gap
    target = OUT / "00_all_nine_ui_comparisons_contact.png"
    sheet.save(target, format="PNG", optimize=True)
    return target


def main() -> None:
    generated = [build_pair(pair) for pair in PAIRS]
    contact = build_contact_sheet(generated)
    print(f"generated {len(generated)} pair images")
    for path in generated:
        print(path)
    print(contact)


if __name__ == "__main__":
    main()
