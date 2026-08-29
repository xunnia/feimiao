#!/usr/bin/env python3
"""Build before/after evidence for the iOS performance pass.

The optimization is intentionally visual-neutral. This tool keeps the raw
captures untouched and creates separate, labeled comparison artifacts so the
same iOS route can be checked before and after the data-projection changes.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageStat


SCENES = (
    ("01-home", "首页：账本投影 + 月度汇总"),
    ("03-transactions", "明细：搜索 / 净额 / 按天分组"),
    ("05-stats-month", "统计：月度图表投影"),
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
                continue
    return ImageFont.load_default()


def resized(image: Image.Image, max_height: int) -> Image.Image:
    if image.height <= max_height:
        return image.copy()
    width = round(image.width * max_height / image.height)
    return image.resize((width, max_height), Image.Resampling.LANCZOS)


def comparison(before: Image.Image, after: Image.Image, title: str) -> tuple[Image.Image, dict[str, object]]:
    before_view = resized(before.convert("RGB"), 900)
    after_view = resized(after.convert("RGB"), 900)
    view_height = max(before_view.height, after_view.height)
    gap = 28
    header = 82
    footer = 60
    canvas = Image.new(
        "RGB",
        (before_view.width + after_view.width + gap, header + view_height + footer),
        "#f5f6f8",
    )
    draw = ImageDraw.Draw(canvas)
    draw.text((20, 14), title, fill="#202124", font=font(24, bold=True))
    draw.text((20, 49), "优化前", fill="#8a4f3d", font=font(17, bold=True))
    draw.text(
        (before_view.width + gap + 20, 49),
        "优化后",
        fill="#315f78",
        font=font(17, bold=True),
    )

    body_y = header
    canvas.paste(before_view, (0, body_y))
    canvas.paste(after_view, (before_view.width + gap, body_y))
    divider_x = before_view.width + gap // 2
    draw.line((divider_x, body_y, divider_x, body_y + view_height), fill="#d0d2d6", width=2)
    draw.text(
        (20, header + view_height + 18),
        "视觉基线保持不变；优化内容：iOS 数据投影缓存与单次聚合",
        fill="#62666d",
        font=font(15),
    )

    if before.size == after.size:
        diff = ImageChops.difference(before.convert("RGB"), after.convert("RGB"))
        stat = ImageStat.Stat(diff)
        mean_delta = sum(stat.mean) / len(stat.mean)
        changed_ratio = sum(1 for value in diff.resize((160, 160)).getdata() if max(value) >= 8) / (160 * 160)
    else:
        mean_delta = None
        changed_ratio = None

    metrics = {
        "beforeSize": list(before.size),
        "afterSize": list(after.size),
        "sameDimensions": before.size == after.size,
        "meanAbsoluteRGBDelta": round(mean_delta, 3) if mean_delta is not None else None,
        "changedPixelRatioAt8On160pxProbe": round(changed_ratio, 6) if changed_ratio is not None else None,
    }
    return canvas, metrics


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--before-dir", type=Path, required=True)
    parser.add_argument("--after-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    generated: list[Path] = []
    metrics: dict[str, object] = {}
    for stem, title in SCENES:
        before_path = args.before_dir / f"{stem}.png"
        after_path = args.after_dir / f"{stem}.png"
        if not before_path.exists() or not after_path.exists():
            missing = [str(path) for path in (before_path, after_path) if not path.exists()]
            raise SystemExit("missing screenshot(s): " + ", ".join(missing))
        with Image.open(before_path) as before, Image.open(after_path) as after:
            image, scene_metrics = comparison(before, after, title)
        output = args.output_dir / f"{stem}-before-after.png"
        image.save(output, format="PNG", optimize=True)
        generated.append(output)
        metrics[stem] = scene_metrics

    thumb_width = 420
    thumbs: list[Image.Image] = []
    for path in generated:
        with Image.open(path) as image:
            thumb = image.convert("RGB")
            thumb.thumbnail((thumb_width, 760), Image.Resampling.LANCZOS)
            thumbs.append(thumb.copy())
    gutter = 18
    contact = Image.new(
        "RGB",
        (sum(image.width for image in thumbs) + gutter * (len(thumbs) - 1), max(image.height for image in thumbs)),
        "#eef0f3",
    )
    x = 0
    for image in thumbs:
        contact.paste(image, (x, 0))
        x += image.width + gutter
    contact_path = args.output_dir / "00-ios-performance-before-after-contact.png"
    contact.save(contact_path, format="PNG", optimize=True)

    report = {
        "scenes": metrics,
        "artifacts": [str(path) for path in generated] + [str(contact_path)],
    }
    (args.output_dir / "comparison-metrics.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(contact_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
