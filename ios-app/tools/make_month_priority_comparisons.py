#!/usr/bin/env python3
"""Pair the supplemental monthly statistics captures without altering originals."""

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

from make_ios_ui_comparisons import contact_sheet, fit, font


PAIRS = (
    ("pace", "月度进度", "stats-month-pace-android.png", "14i-stats-month-pace.png",
     ((0.20, "金额与标题"), (0.55, "七个月柱图"), (0.85, "分类与活动入口"))),
    ("activity", "活动入口", "stats-month-pace-activity-android.png", "14j-stats-month-pace-activity.png",
     ((0.18, "查看所有支出活动"), (0.43, "预算环"))),
    ("budget", "预算使用", "stats-month-budget-ring-android.png", "14k-stats-month-budget-ring.png",
     ((0.20, "34% 与同色轨道"), (0.56, "分类构成"))),
    ("detail", "全部支出活动", "stats-month-pace-detail-android.png", "14l-stats-month-pace-detail.png",
     ((0.18, "14 笔与净额"), (0.32, "首笔标题与退款"))),
    ("cards", "自定义图表", "stats-month-cards-android.png", "14m-stats-month-cards.png",
     ((0.23, "卡片开关"), (0.55, "跨维度顺序"))),
)


def pair(android_path: Path, ios_path: Path, title: str,
         markers: tuple[tuple[float, str], ...], height: int) -> Image.Image:
    with Image.open(android_path) as android, Image.open(ios_path) as ios:
        left, right = fit(android, height), fit(ios, height)
    gap, header, footer = 24, 78, 36 + 28 * len(markers)
    width = left.width + gap + right.width
    canvas = Image.new("RGB", (width, header + height + footer), "#eef0f3")
    draw = ImageDraw.Draw(canvas)
    draw.text((18, 10), title, fill="#24262a", font=font(24, bold=True))
    draw.text((18, 47), "Android", fill="#6d503b", font=font(17, bold=True))
    draw.text((left.width + gap + 18, 47), "iOS", fill="#315f78", font=font(17, bold=True))
    canvas.paste(left, (0, header))
    canvas.paste(right, (left.width + gap, header))
    draw.line((left.width + gap // 2, header, left.width + gap // 2, header + height),
              fill="#c7cbd0", width=2)
    for number, (vertical, description) in enumerate(markers, start=1):
        x = left.width + gap + right.width - 27
        y = header + round(height * vertical)
        draw.ellipse((x - 17, y - 17, x + 17, y + 17), fill="#dc6a42", outline="white", width=2)
        draw.text((x - 6, y - 12), str(number), fill="white", font=font(18, bold=True))
        draw.text((18, header + height + 12 + (number - 1) * 28),
                  f"{number}. {description}", fill="#4f535a", font=font(17))
    return canvas


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--android", type=Path, required=True)
    parser.add_argument("--ios", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    overview = []
    for key, title, android_name, ios_name, markers in PAIRS:
        full = pair(args.android / android_name, args.ios / ios_name, title, markers, 1180)
        full.save(args.output / f"{key}-android-ios.png", optimize=True)
        overview.append(full.resize((round(full.width * 0.52), round(full.height * 0.52))))
    contact_sheet(overview, columns=2).save(args.output / "00-month-priority-overview.png", optimize=True)


if __name__ == "__main__":
    main()
