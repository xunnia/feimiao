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
    ("01-home", "首页 / Liquid Glass 顶部与底部输入框"),
    ("03-transactions", "明细 / 玻璃背景与输入控件"),
    ("05-stats-month", "统计 / 原生玻璃翻页控件"),
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


def fit(image: Image.Image, max_height: int) -> Image.Image:
    image = image.convert("RGB")
    if image.height <= max_height:
        return image.copy()
    width = round(image.width * max_height / image.height)
    return image.resize((width, max_height), Image.Resampling.LANCZOS)


def ios_before_after(before: Image.Image, after: Image.Image, title: str) -> Image.Image:
    left = fit(before, 900)
    right = fit(after, 900)
    gap = 28
    header = 82
    footer = 58
    canvas = Image.new("RGB", (left.width + gap + right.width, header + max(left.height, right.height) + footer), "#f4f5f7")
    draw = ImageDraw.Draw(canvas)
    draw.text((20, 12), title, fill="#202124", font=font(23, bold=True))
    draw.text((20, 48), "改动前 · 原 iOS 页面", fill="#8a4f3d", font=font(16, bold=True))
    draw.text((left.width + gap + 20, 48), "改动后 · iOS 26 Liquid Glass", fill="#315f78", font=font(16, bold=True))
    canvas.paste(left, (0, header))
    canvas.paste(right, (left.width + gap, header))
    draw.line((left.width + gap // 2, header, left.width + gap // 2, header + max(left.height, right.height)), fill="#cfd2d6", width=2)
    draw.text((20, header + max(left.height, right.height) + 18), "变化：原生 .glass / .glassProminent、GlassEffectContainer、玻璃下方内容层与状态动画", fill="#62666d", font=font(14))
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
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    pairs = manifest.get("pairs", [])
    if not pairs:
        raise SystemExit("manifest contains no pairs")
    args.output_dir.mkdir(parents=True, exist_ok=True)

    parity_images: list[Image.Image] = []
    parity_paths: list[Path] = []
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
        for stem, title in UI_SCENES:
            before_path = args.before_dir / f"{stem}.png"
            after_path = args.after_dir / f"{stem}.png"
            if not before_path.exists() or not after_path.exists():
                missing = [str(path) for path in (before_path, after_path) if not path.exists()]
                raise SystemExit("missing UI screenshot(s): " + ", ".join(missing))
            with Image.open(before_path) as before, Image.open(after_path) as after:
                image = ios_before_after(before, after, title)
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
