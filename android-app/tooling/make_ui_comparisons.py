"""Build annotated before/after UI comparison images from screenshot fixtures.

The script intentionally only reads existing screenshots and writes comparison
artifacts under ``android-app/outputs/ui_comparisons``.  It does not modify the
source screenshots, application code, or test fixtures.
"""

from __future__ import annotations

import textwrap
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "android-app" / "outputs" / "ui_comparisons" / "2026-08-28"


PAIRS = [
    {
        "file": "01_global_settings_before_after.png",
        "title": "全局设置页",
        "before": ROOT / "android-app/test/failures/settings_masterImage.png",
        "after": ROOT / "android-app/outputs/global_ui/settings.png",
        "boxes": [(16, 376, 374, 523), (16, 575, 374, 799)],
        "notes": ["设置分组、发丝分隔、副标题与开关热区统一为全局设置行标准"],
    },
    {
        "file": "02_global_gallery_before_after.png",
        "title": "全局设置控件画廊",
        "before": ROOT / "android-app/test/failures/gallery_masterImage.png",
        "after": ROOT / "android-app/outputs/global_ui/gallery.png",
        "boxes": [(16, 20, 374, 96), (16, 100, 374, 230), (16, 240, 374, 310)],
        "notes": ["弹层头部统一为左侧关闭、居中标题、右侧操作胶囊；控件行复用同一标准"],
    },
    {
        "file": "03_ai_account_before_after.png",
        "title": "AI 账号设置",
        "before": ROOT / "android-app/test/failures/ai_account_current_masterImage.png",
        "after": ROOT / "android-app/outputs/ai_account/ai_account_current.png",
        "boxes": [(16, 8, 374, 56), (260, 382, 365, 452), (25, 486, 365, 716)],
        "notes": ["返回、新增、删除和密码查看操作统一独立热区；凭据输入项改为透明输入框并防止长值溢出"],
    },
    {
        "file": "04_home_input_before_after.png",
        "title": "主页/喵助手输入框",
        "before": ROOT / "android-app/test/failures/ai_chat_input_alignment_masterImage.png",
        "after": ROOT / "android-app/outputs/ai_chat_input_alignment/ai_chat_input_alignment.png",
        "boxes": [(12, 224, 378, 326), (12, 738, 378, 840)],
        "notes": ["加号、模型名称与思考强度保持同一水平线，间距和字号契约在两种输入框中一致"],
    },
    {
        "file": "05_assistant_fullscreen_before_after.png",
        "title": "喵助手全屏会话",
        "before": ROOT / "android-app/test/failures/assistant_fullscreen_masterImage.png",
        "after": ROOT / "android-app/outputs/ai_chat_input_alignment/assistant_fullscreen.png",
        "boxes": [(12, 8, 378, 58), (12, 726, 378, 840)],
        "notes": ["全屏顶栏按钮、底部输入卡和键盘上移后的定位统一，历史底部留白收紧并支持回弹"],
    },
    {
        "file": "06_claude_add_sheet_before_after.png",
        "title": "Claude 风格加号菜单",
        "before": ROOT / "android-app/test/failures/ai_chat_add_sheet_masterImage.png",
        "after": ROOT / "android-app/outputs/ai_chat_claude/ai_chat_add_sheet.png",
        "boxes": [(8, 430, 382, 844), (16, 462, 374, 512), (16, 515, 374, 615), (16, 623, 374, 824)],
        "notes": ["统一模糊底部弹层、照片入口比例、文件/工具/联网操作行和触控热区"],
    },
    {
        "file": "07_recent_photos_before_after.png",
        "title": "加号菜单·最近照片",
        "before": ROOT / "android-app/test/failures/ai_chat_add_sheet_recent_masterImage.png",
        "after": ROOT / "android-app/outputs/ai_chat_claude/ai_chat_add_sheet_recent.png",
        "boxes": [(16, 22, 374, 72)],
        "notes": ["最近照片页的关闭按钮与“全部照片”操作统一为全局圆形/胶囊按钮"],
    },
    {
        "file": "08_four_images_before_after.png",
        "title": "多图草稿输入",
        "before": ROOT / "android-app/test/failures/ai_chat_draft_four_images_masterImage.png",
        "after": ROOT / "android-app/outputs/ai_chat_claude/ai_chat_draft_four_images.png",
        "boxes": [(12, 8, 378, 56), (12, 622, 378, 840)],
        "notes": ["三图并排卡片、文字补充区与发送栏保持一致；本场景用于确认图片流程没有回归"],
    },
    {
        "file": "09_chats_before_after.png",
        "title": "Chats 会话列表",
        "before": ROOT / "android-app/test/failures/chats_current_masterImage.png",
        "after": ROOT / "android-app/outputs/chats/chats_current.png",
        "boxes": [(18, 62, 372, 286), (270, 718, 372, 780), (20, 786, 370, 833)],
        "notes": ["会话卡片字号/字重、右下角新聊天胶囊和底部搜索条统一到全局控件标准"],
    },
]


def _font(size: int, *, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    """Load a Windows font with CJK coverage for readable annotations."""

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
                continue
    return ImageFont.load_default()


def _wrap(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.ImageFont, max_width: int) -> list[str]:
    lines: list[str] = []
    current = ""
    for char in text:
        candidate = current + char
        if current and draw.textlength(candidate, font=font) > max_width:
            lines.append(current)
            current = char
        else:
            current = candidate
    if current:
        lines.append(current)
    return lines or [""]


def _annotate(image: Image.Image, boxes: list[tuple[int, int, int, int]]) -> Image.Image:
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    for index, (left, top, right, bottom) in enumerate(boxes, start=1):
        draw.rounded_rectangle(
            (left, top, right, bottom),
            radius=9,
            fill=(244, 132, 72, 28),
            outline=(221, 91, 48, 235),
            width=3,
        )
        radius = 14
        cx = min(right - radius, left + radius + 2)
        cy = min(bottom - radius, top + radius + 2)
        draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=(221, 91, 48, 245))
        badge_font = _font(16, bold=True)
        label = str(index)
        bbox = draw.textbbox((0, 0), label, font=badge_font)
        draw.text((cx - (bbox[2] - bbox[0]) / 2, cy - (bbox[3] - bbox[1]) / 2 - 1), label, fill="white", font=badge_font)
    return Image.alpha_composite(image.convert("RGBA"), overlay).convert("RGB")


def build_pair(pair: dict) -> Path:
    before = Image.open(pair["before"]).convert("RGB")
    after = Image.open(pair["after"]).convert("RGB")
    # 24px outer margin on both sides plus a 48px gutter between screenshots.
    body_width = before.width + 96 + after.width
    header_h = 82
    footer_font = _font(16)
    probe = Image.new("RGB", (body_width, 10), "white")
    probe_draw = ImageDraw.Draw(probe)
    wrapped_notes: list[str] = []
    for note_index, note in enumerate(pair["notes"], start=1):
        wrapped_notes.extend(_wrap(probe_draw, f"{note_index}. {note}", footer_font, body_width - 44))
    footer_h = 52 + max(1, len(wrapped_notes)) * 25
    canvas = Image.new("RGB", (body_width, header_h + max(before.height, after.height) + footer_h), "#f7f7f8")
    draw = ImageDraw.Draw(canvas)
    title_font = _font(23, bold=True)
    label_font = _font(18, bold=True)
    hint_font = _font(14)
    draw.text((24, 13), pair["title"], fill="#202124", font=title_font)
    draw.text((24, 48), "改动前", fill="#7c4d3a", font=label_font)
    draw.text((24 + before.width + 48, 48), "改动后", fill="#315f78", font=label_font)
    draw.text((body_width - 270, 17), "橙框 = 改动位置", fill="#70757a", font=hint_font)
    before_annotated = _annotate(before, pair["boxes"])
    after_annotated = _annotate(after, pair["boxes"])
    body_y = header_h
    canvas.paste(before_annotated, (24, body_y))
    canvas.paste(after_annotated, (24 + before.width + 48, body_y))
    divider_x = 24 + before.width + 24
    draw.line((divider_x, body_y, divider_x, body_y + max(before.height, after.height)), fill="#d4d5d8", width=2)
    footer_y = body_y + max(before.height, after.height) + 13
    draw.text((24, footer_y), "改动说明", fill="#202124", font=label_font)
    line_y = footer_y + 28
    for line in wrapped_notes:
        draw.text((24, line_y), line, fill="#4e5156", font=footer_font)
        line_y += 25
    draw.text((24, canvas.height - 23), "左侧原始截图 · 右侧当前截图 · 原图未修改", fill="#8a8d91", font=hint_font)
    OUT.mkdir(parents=True, exist_ok=True)
    target = OUT / pair["file"]
    canvas.save(target, format="PNG", optimize=True)
    return target


def build_contact_sheet(paths: list[Path]) -> Path:
    thumb_width = 410
    margin = 16
    gap = 16
    cards: list[Image.Image] = []
    for path in paths:
        source = Image.open(path).convert("RGB")
        scale = thumb_width / source.width
        cards.append(source.resize((thumb_width, round(source.height * scale)), Image.Resampling.LANCZOS))
    rows: list[list[Image.Image]] = [cards[i : i + 2] for i in range(0, len(cards), 2)]
    row_heights = [max(card.height for card in row) for row in rows]
    total_h = margin + sum(row_heights) + gap * (len(rows) - 1) + margin
    sheet = Image.new("RGB", (margin * 2 + thumb_width * 2 + gap, total_h), "#ececef")
    y = margin
    for row, row_h in zip(rows, row_heights):
        for col, card in enumerate(row):
            x = margin + col * (thumb_width + gap)
            sheet.paste(card, (x, y))
        y += row_h + gap
    target = OUT / "00_all_ui_comparisons_contact.png"
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
