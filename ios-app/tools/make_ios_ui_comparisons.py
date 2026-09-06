#!/usr/bin/env python3
"""Create auditable iOS UI and Android/iOS parity comparison images.

Raw screenshots are never overwritten. The output contains individual paired
images plus small overview sheets so a reviewer can inspect the whole route
matrix without confusing native iOS rendering with a missing capture.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


UI_SCENES = (
    (
        "01-home",
        "首页 / 顶栏与底部记账输入框",
        (
            (0.11, 0.08, "顶栏菜单改为显式圆形单层玻璃"),
            (0.72, 0.08, "搜索圆形 + 账本胶囊各自只有一层材质"),
            (0.50, 0.88, "底部输入框、模式胶囊与圆形发送键统一"),
        ),
    ),
    (
        "02-quickadd",
        "手动记账 / 顶栏、详情胶囊与数字键盘",
        (
            (0.09, 0.08, "返回键固定为圆形玻璃"),
            (0.90, 0.08, "AI 入口固定为圆形玻璃"),
            (0.50, 0.77, "数字键改为圆角矩形，不再使用默认椭圆"),
        ),
    ),
    (
        "05-stats-month",
        "统计 / 月份翻页控件",
        (
            (0.09, 0.15, "上一月按钮固定为圆形交互玻璃"),
            (0.91, 0.15, "下一月按钮固定为圆形交互玻璃"),
        ),
    ),
    (
        "17-accounts",
        "账户管理 / 编辑与新增",
        (
            (0.18, 0.08, "编辑使用文字胶囊"),
            (0.90, 0.08, "新增使用圆形玻璃"),
        ),
    ),
    (
        "18-categories",
        "分类管理 / 收支、图标样式与新增",
        (
            (0.12, 0.08, "收支切换入口固定为圆形玻璃"),
            (0.82, 0.08, "新增与图标样式采用独立圆形热区"),
        ),
    ),
    (
        "38-assets-detail",
        "资产详情 / 导航与高频操作",
        (
            (0.10, 0.08, "返回键固定为圆形玻璃"),
            (0.90, 0.08, "更多操作固定为圆形玻璃"),
            (0.50, 0.28, "高频操作统一为单层文字胶囊"),
        ),
    ),
)


def font(size: int, bold: bool = False) -> ImageFont.ImageFont:
    candidates = (
        r"C:\Windows\Fonts\msyhbd.ttc" if bold else r"C:\Windows\Fonts\msyh.ttc",
        r"C:\Windows\Fonts\simhei.ttf",
        "/System/Library/Fonts/PingFang.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    )
    for candidate in candidates:
        path = Path(candidate)
        if path.exists():
            try:
                return ImageFont.truetype(str(path), size)
            except OSError:
                pass
    return ImageFont.load_default()


def flatten_alpha(image: Image.Image) -> Image.Image:
    """Composite transparent captures onto the app's warm page gradient.

    PixelCopy can preserve alpha when a Flutter route is transparent. Pillow's
    direct RGBA-to-RGB conversion turns those pixels black, which makes a
    healthy light page look truncated in the review sheet. The raw PNG stays
    untouched; this only affects the derived visual artifact.
    """
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A")
    if alpha.getextrema() == (255, 255):
        return rgba.convert("RGB")

    width, height = rgba.size
    background = Image.new("RGB", (width, height))
    draw = ImageDraw.Draw(background)
    top = (250, 224, 176)  # AppColors.warmBackgroundTop
    bottom = (255, 253, 247)  # AppColors.warmBackgroundBottom
    denominator = max(height - 1, 1)
    for y in range(height):
        progress = y / denominator
        color = tuple(
            round(top[channel] + (bottom[channel] - top[channel]) * progress)
            for channel in range(3)
        )
        draw.line((0, y, width, y), fill=color)
    background.paste(rgba, mask=alpha)
    return background


def fit(image: Image.Image, max_height: int) -> Image.Image:
    image = flatten_alpha(image)
    if image.height <= max_height:
        return image.copy()
    width = round(image.width * max_height / image.height)
    return image.resize((width, max_height), Image.Resampling.LANCZOS)


def ios_before_after(
    before: Image.Image,
    after: Image.Image,
    title: str,
    callouts: tuple[tuple[float, float, str], ...],
) -> Image.Image:
    left = fit(before, 900)
    right = fit(after, 900)
    gap = 28
    header = 82
    footer = 38 + len(callouts) * 27
    canvas = Image.new("RGB", (left.width + gap + right.width, header + max(left.height, right.height) + footer), "#f4f5f7")
    draw = ImageDraw.Draw(canvas)
    draw.text((20, 12), title, fill="#202124", font=font(23, bold=True))
    draw.text((20, 48), "改动前 · 原 iOS 页面", fill="#8a4f3d", font=font(16, bold=True))
    draw.text((left.width + gap + 20, 48), "改动后 · iOS 26 Liquid Glass", fill="#315f78", font=font(16, bold=True))
    canvas.paste(left, (0, header))
    canvas.paste(right, (left.width + gap, header))
    draw.line((left.width + gap // 2, header, left.width + gap // 2, header + max(left.height, right.height)), fill="#cfd2d6", width=2)
    after_x = left.width + gap
    for index, (x_ratio, y_ratio, description) in enumerate(callouts, start=1):
        x = after_x + round(right.width * x_ratio)
        y = header + round(right.height * y_ratio)
        radius = 15
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill="#ff7a45", outline="white", width=2)
        number = str(index)
        box = draw.textbbox((0, 0), number, font=font(15, bold=True))
        draw.text(
            (x - (box[2] - box[0]) / 2, y - (box[3] - box[1]) / 2 - 1),
            number,
            fill="white",
            font=font(15, bold=True),
        )
        footer_y = header + max(left.height, right.height) + 12 + (index - 1) * 27
        draw.text((20, footer_y), f"{index}. {description}", fill="#62666d", font=font(14))
    return canvas


def parity_pair(android: Image.Image, ios: Image.Image, title: str) -> Image.Image:
    left = fit(android, 520)
    right = fit(ios, 520)
    gap = 18
    header = 58
    canvas = Image.new("RGB", (left.width + gap + right.width, header + max(left.height, right.height) + 18), "#eef0f3")
    draw = ImageDraw.Draw(canvas)
    draw.text((12, 10), title, fill="#202124", font=font(15, bold=True))
    draw.text((12, 34), "Android", fill="#7c4d3a", font=font(12, bold=True))
    draw.text((left.width + gap + 12, 34), "iOS", fill="#315f78", font=font(12, bold=True))
    canvas.paste(left, (0, header))
    canvas.paste(right, (left.width + gap, header))
    draw.line((left.width + gap // 2, header, left.width + gap // 2, header + max(left.height, right.height)), fill="#d0d2d6", width=2)
    return canvas


def contact_sheet(images: list[Image.Image], columns: int, gutter: int = 14) -> Image.Image:
    if not images:
        return Image.new("RGB", (1, 1), "white")
    rows = (len(images) + columns - 1) // columns
    cell_width = max(image.width for image in images)
    cell_height = max(image.height for image in images)
    canvas = Image.new("RGB", (columns * cell_width + (columns - 1) * gutter, rows * cell_height + (rows - 1) * gutter), "#eef0f3")
    for index, image in enumerate(images):
        x = (index % columns) * (cell_width + gutter)
        y = (index // columns) * (cell_height + gutter)
        canvas.paste(image, (x, y))
    return canvas


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--before-dir", type=Path)
    parser.add_argument("--after-dir", type=Path)
    parser.add_argument("--skip-parity", action="store_true")
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    pairs = manifest.get("pairs", [])
    if not pairs:
        raise SystemExit("manifest contains no pairs")
    args.output_dir.mkdir(parents=True, exist_ok=True)

    parity_images: list[Image.Image] = []
    parity_paths: list[Path] = []
    if not args.skip_parity:
        for pair in pairs:
            android_path = args.root / pair["android"]
            ios_path = args.root / pair["ios"]
            if not android_path.exists() or not ios_path.exists():
                missing = [str(path) for path in (android_path, ios_path) if not path.exists()]
                raise SystemExit("missing parity screenshot(s): " + ", ".join(missing))
            with Image.open(android_path) as android, Image.open(ios_path) as ios:
                image = parity_pair(android, ios, f"{pair.get('id', '')} · {pair.get('feature', '')}")
            output = args.output_dir / f"parity-{pair['id']}.png"
            image.save(output, format="PNG", optimize=True)
            parity_paths.append(output)
            parity_images.append(image)

        for sheet_index in range(0, len(parity_images), 9):
            sheet = contact_sheet(parity_images[sheet_index : sheet_index + 9], columns=3)
            sheet.save(args.output_dir / f"00-android-ios-parity-{sheet_index // 9 + 1:02d}.png", format="PNG", optimize=True)

    ui_paths: list[Path] = []
    if args.before_dir and args.after_dir:
        ui_images: list[Image.Image] = []
        for stem, title, callouts in UI_SCENES:
            before_path = args.before_dir / f"{stem}.png"
            after_path = args.after_dir / f"{stem}.png"
            if not before_path.exists() or not after_path.exists():
                missing = [str(path) for path in (before_path, after_path) if not path.exists()]
                raise SystemExit("missing UI screenshot(s): " + ", ".join(missing))
            with Image.open(before_path) as before, Image.open(after_path) as after:
                image = ios_before_after(before, after, title, callouts)
            output = args.output_dir / f"ui-{stem}-before-after.png"
            image.save(output, format="PNG", optimize=True)
            ui_paths.append(output)
            ui_images.append(image)
        contact_sheet(ui_images, columns=1).save(args.output_dir / "00-ios-liquid-glass-before-after.png", format="PNG", optimize=True)

    report = {
        "pairCount": len(parity_paths),
        "parityArtifacts": [str(path) for path in parity_paths],
        "uiArtifacts": [str(path) for path in ui_paths],
    }
    (args.output_dir / "comparison-index.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(args.output_dir / "00-android-ios-parity-01.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
