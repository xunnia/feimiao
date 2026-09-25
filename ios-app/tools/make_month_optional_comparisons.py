#!/usr/bin/env python3
"""Pair the Android and iOS optional statistics captures."""

import argparse
from pathlib import Path

from PIL import Image

from make_ios_ui_comparisons import contact_sheet
from make_month_priority_comparisons import pair


PAIRS = (
    ("insights", "喵的洞察", "stats-month-insights-android.png", "14-optional-stats-month-insights.png",
     ((0.28, "消费画像"), (0.65, "消费摘要与预算预测"))),
    ("heatmap", "消费热力图", "stats-month-heatmap-android.png", "14-optional-stats-month-heatmap.png",
     ((0.30, "日期与消费强度"), (0.67, "图例与单日金额"))),
    ("radar", "本月 vs 上月", "stats-month-radar-android.png", "14-optional-stats-month-radar.png",
     ((0.28, "分类与两期金额"), (0.67, "双条占比"))),
    ("stacked", "近 12 月收支", "stats-month-stacked-android.png", "14-optional-stats-month-stacked.png",
     ((0.28, "月份与图例"), (0.67, "花掉、结余和超支"))),
    ("library", "可选卡开关", "stats-month-optional-cards-android.png", "14m2-stats-month-optional-cards.png",
     ((0.40, "四张月专属可选卡"),)),
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--android", type=Path, required=True)
    parser.add_argument("--ios", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    overview: list[Image.Image] = []
    for key, title, android_name, ios_name, markers in PAIRS:
        image = pair(args.android / android_name, args.ios / ios_name, title, markers, 1180)
        image.save(args.output / f"{key}-android-ios.png", optimize=True)
        overview.append(image.resize((round(image.width * 0.52), round(image.height * 0.52))))
    contact_sheet(overview, columns=2).save(args.output / "00-month-optional-overview.png", optimize=True)


if __name__ == "__main__":
    main()
