"""Create the dated before/after evidence image for the home month picker."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "android-app" / "outputs" / "ui_comparisons" / "2026-08-30"
BEFORE = OUT / "before" / "month_picker_before.png"
AFTER = OUT / "month_picker_after.png"
TARGET = OUT / "month_picker_before_after.png"


def font(size: int, *, bold: bool = False):
    candidates = [
        Path(r"C:\Windows\Fonts\msyhbd.ttc" if bold else r"C:\Windows\Fonts\msyh.ttc"),
        Path(r"C:\Windows\Fonts\simhei.ttf"),
        Path(r"C:\Windows\Fonts\arial.ttf"),
    ]
    for candidate in candidates:
        if candidate.exists():
            try:
                return ImageFont.truetype(str(candidate), size)
            except OSError:
                pass
    return ImageFont.load_default()


def annotate(source: Image.Image, boxes: list[tuple[int, int, int, int]]) -> Image.Image:
    result = source.convert("RGBA")
    overlay = Image.new("RGBA", result.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    badge_font = font(15, bold=True)
    for index, box in enumerate(boxes, start=1):
        left, top, right, bottom = box
        draw.rounded_rectangle(
            box,
            radius=8,
            fill=(235, 127, 68, 28),
            outline=(210, 82, 43, 230),
            width=3,
        )
        cx = min(right - 13, left + 13)
        cy = min(bottom - 13, top + 13)
        draw.ellipse((cx - 13, cy - 13, cx + 13, cy + 13), fill=(210, 82, 43, 245))
        label = str(index)
        bounds = draw.textbbox((0, 0), label, font=badge_font)
        draw.text(
            (cx - (bounds[2] - bounds[0]) / 2, cy - (bounds[3] - bounds[1]) / 2 - 1),
            label,
            fill="white",
            font=badge_font,
        )
    return Image.alpha_composite(result, overlay).convert("RGB")


def wrap(draw: ImageDraw.ImageDraw, text: str, typeface, width: int) -> list[str]:
    lines: list[str] = []
    line = ""
    for char in text:
        candidate = line + char
        if line and draw.textlength(candidate, font=typeface) > width:
            lines.append(line)
            line = char
        else:
            line = candidate
    if line:
        lines.append(line)
    return lines or [""]


def main() -> None:
    before = Image.open(BEFORE).convert("RGB")
    after = Image.open(AFTER).convert("RGB")
    assert before.size == after.size, (before.size, after.size)

    boxes = [
        (28, 279, 113, 337),
        (150, 279, 239, 338),
        (242, 279, 366, 338),
    ]
    left = annotate(before, boxes)
    right = annotate(after, boxes)
    gutter = 24
    margin = 24
    header = 82
    body_width = margin * 2 + before.width * 2 + gutter
    footer_font = font(16)
    probe = Image.new("RGB", (body_width, 10), "white")
    probe_draw = ImageDraw.Draw(probe)
    notes = [
        "1. 去掉弹层内的关闭圆圈，恢复图二的轻量头部布局。",
        "2. 标题左对齐，统计起始日右对齐，位于同一行。",
        "3. 取消背景高斯模糊，仅保留自然的页面暗化过渡。",
    ]
    wrapped = []
    for note in notes:
        wrapped.extend(wrap(probe_draw, note, footer_font, body_width - margin * 2))
    footer = 78 + len(wrapped) * 25
    canvas = Image.new("RGB", (body_width, header + before.height + footer), "#f7f7f8")
    draw = ImageDraw.Draw(canvas)
    draw.text((margin, 14), "主页月份选择弹窗", fill="#202124", font=font(23, bold=True))
    draw.text((margin, 49), "改动前", fill="#7c4d3a", font=font(18, bold=True))
    draw.text((margin + before.width + gutter, 49), "改动后", fill="#315f78", font=font(18, bold=True))
    body_y = header
    canvas.paste(left, (margin, body_y))
    canvas.paste(right, (margin + before.width + gutter, body_y))
    divider_x = margin + before.width + gutter // 2
    draw.line((divider_x, body_y, divider_x, body_y + before.height), fill="#d4d5d8", width=2)
    footer_y = body_y + before.height + 14
    draw.text((margin, footer_y), "改动说明", fill="#202124", font=font(18, bold=True))
    line_y = footer_y + 28
    for line in wrapped:
        draw.text((margin, line_y), line, fill="#4e5156", font=footer_font)
        line_y += 25
    draw.text(
        (margin, canvas.height - 22),
        "左侧原始截图 · 右侧当前截图 · 原图未修改",
        fill="#8a8d91",
        font=font(14),
    )
    OUT.mkdir(parents=True, exist_ok=True)
    canvas.save(TARGET, format="PNG", optimize=True)
    print(TARGET)


if __name__ == "__main__":
    main()
