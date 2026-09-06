#!/usr/bin/env python3
"""Reject Android parity captures with a missing/black page surface.

The parity driver intentionally forces the light app theme. A transparent
capture route can therefore produce a valid PNG with the expected dimensions
but a black outer surface, hiding dark text and making the Android/iOS review
misleading. This guard checks both the full emulator frame and background
pixels outside the page content.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from compare_png import PNGError, read_png


EXPECTED_SIZE = (1080, 1920)


def _rgba_at(pixels: bytes, width: int, x: int, y: int) -> tuple[int, int, int, int]:
    offset = (y * width + x) * 4
    return tuple(pixels[offset : offset + 4])  # type: ignore[return-value]


def inspect(path: Path) -> tuple[int, int, float, float]:
    width, height, pixels = read_png(path)
    if (width, height) != EXPECTED_SIZE:
        raise ValueError(
            f"expected {EXPECTED_SIZE[0]}x{EXPECTED_SIZE[1]}, got {width}x{height}"
        )

    # The outer 1% is page background in every parity route. Sample both sides
    # at multiple heights so a black route surface cannot hide behind a card.
    xs = (max(0, round(width * 0.01)), min(width - 1, round(width * 0.99)))
    ys = (round(height * ratio) for ratio in (0.02, 0.08, 0.18, 0.35, 0.55, 0.75, 0.92, 0.98))
    background = [_rgba_at(pixels, width, x, y) for x in xs for y in ys]
    dark_background_ratio = sum(
        1
        for red, green, blue, alpha in background
        if alpha < 16 or max(red, green, blue) < 32
    ) / max(len(background), 1)

    # Use a sparse full-frame sample as a second signal. Text and icons may be
    # dark, but a light parity page must not be dominated by near-black pixels.
    stride = 8
    sampled = 0
    near_black = 0
    for y in range(0, height, stride):
        for x in range(0, width, stride):
            red, green, blue, alpha = _rgba_at(pixels, width, x, y)
            sampled += 1
            # Transparent pixels render as black in the comparison-sheet
            # tooling, so they count as a missing surface just like opaque
            # near-black pixels.
            if alpha < 16 or max(red, green, blue) < 16:
                near_black += 1
    near_black_ratio = near_black / max(sampled, 1)
    return width, height, dark_background_ratio, near_black_ratio


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--max-dark-background-ratio", type=float, default=0.20)
    parser.add_argument("--max-near-black-ratio", type=float, default=0.20)
    args = parser.parse_args()

    failed = False
    for path in args.paths:
        try:
            width, height, dark_background_ratio, near_black_ratio = inspect(path)
        except (OSError, PNGError, ValueError, IndexError) as error:
            print(f"{path}: invalid Android parity screenshot ({error})", file=sys.stderr)
            failed = True
            continue
        print(
            f"{path}: {width}x{height}, "
            f"darkBackgroundRatio={dark_background_ratio:.3f}, "
            f"nearBlackRatio={near_black_ratio:.3f}"
        )
        if dark_background_ratio > args.max_dark_background_ratio:
            print(
                f"{path}: outer page surface is too dark "
                f"({dark_background_ratio:.3f} > {args.max_dark_background_ratio:.3f})",
                file=sys.stderr,
            )
            failed = True
        if near_black_ratio > args.max_near_black_ratio:
            print(
                f"{path}: frame is dominated by near-black pixels "
                f"({near_black_ratio:.3f} > {args.max_near_black_ratio:.3f})",
                file=sys.stderr,
            )
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
