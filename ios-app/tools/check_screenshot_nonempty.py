#!/usr/bin/env python3
"""Fail when an iOS route screenshot contains only system chrome/background.

The simulator can successfully save a PNG even after the app crashed or while a
deep-link destination is still blank.  This guard samples the content area and
requires visible pixels beyond the status-bar/background colors.  It uses the
same standard-library PNG decoder as compare_png.py.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from compare_png import PNGError, read_png


def content_sample_count(path: Path) -> tuple[int, int, float]:
    width, height, pixels = read_png(path)
    channels = 4
    # Exclude the status bar and the bottom home-indicator/tab-bar area.  A
    # valid page must still draw something in the central content region.
    first_row = int(height * 0.08)
    last_row = int(height * 0.84)
    stride = 4
    sampled = 0
    interesting = 0
    for y in range(first_row, last_row, stride):
        row_start = y * width * channels
        for x in range(0, width, stride):
            offset = row_start + x * channels
            red, green, blue, alpha = pixels[offset : offset + channels]
            if alpha < 16:
                continue
            sampled += 1
            maximum = max(red, green, blue)
            minimum = min(red, green, blue)
            luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            # The iOS grouped background is close to #f2f2f7; text, cards,
            # separators, and accent controls are materially different.
            if luminance < 225 or maximum - minimum >= 18:
                interesting += 1
    ratio = interesting / sampled if sampled else 0.0
    return width, height, ratio


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--min-ratio", type=float, default=0.001)
    args = parser.parse_args()

    failed = False
    for path in args.paths:
        try:
            width, height, ratio = content_sample_count(path)
        except (OSError, PNGError, ValueError, IndexError) as error:
            print(f"{path}: invalid PNG ({error})", file=sys.stderr)
            failed = True
            continue
        print(f"{path}: {width}x{height}, contentSampleRatio={ratio:.5f}")
        if ratio < args.min_ratio:
            print(
                f"{path}: screenshot is blank in the content region "
                f"(ratio {ratio:.5f} < {args.min_ratio:.5f})",
                file=sys.stderr,
            )
            failed = True

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
