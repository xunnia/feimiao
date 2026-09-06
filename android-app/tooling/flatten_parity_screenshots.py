#!/usr/bin/env python3
"""Make Android parity screenshots opaque without changing the source images."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw


TOP = (250, 224, 176)
BOTTOM = (255, 253, 247)


def _background(size: tuple[int, int]) -> Image.Image:
    width, height = size
    background = Image.new("RGB", size)
    draw = ImageDraw.Draw(background)
    denominator = max(height - 1, 1)
    for y in range(height):
        progress = min(y / denominator / 0.85, 1.0)
        color = tuple(
            round(TOP[channel] + (BOTTOM[channel] - TOP[channel]) * progress)
            for channel in range(3)
        )
        draw.line((0, y, width, y), fill=color)
    return background


def flatten(source: Path, target: Path) -> None:
    with Image.open(source) as opened:
        image = opened.convert("RGBA")
        if image.getchannel("A").getextrema() == (255, 255):
            result = image.convert("RGB")
        else:
            result = Image.alpha_composite(_background(image.size).convert("RGBA"), image)
            result = result.convert("RGB")
    target.parent.mkdir(parents=True, exist_ok=True)
    result.save(target, format="PNG", optimize=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_dir", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()

    sources = sorted(args.input_dir.glob("*.png"))
    if not sources:
        raise SystemExit(f"no PNG screenshots found in {args.input_dir}")
    for source in sources:
        flatten(source, args.output_dir / source.name)
    print(f"flattened {len(sources)} screenshot(s) into {args.output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
