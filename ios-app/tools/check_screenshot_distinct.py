#!/usr/bin/env python3
"""Reject perceptually near-duplicate route screenshots on one platform."""

from __future__ import annotations

import argparse
import itertools
import sys
from pathlib import Path

from compare_png import PNGError, read_png


def sample(path: Path, target_columns: int = 126) -> tuple[int, int, bytes]:
    width, height, pixels = read_png(path)
    stride = max(1, width // target_columns)
    values = bytearray()
    for y in range(0, height, stride):
        for x in range(0, width, stride):
            offset = (y * width + x) * 4
            values.extend(pixels[offset : offset + 3])
    return width, height, bytes(values)


def mean_delta(left: bytes, right: bytes) -> float:
    if len(left) != len(right):
        return float("inf")
    return sum(abs(a - b) for a, b in zip(left, right)) / max(len(left), 1)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--min-mean-delta", type=float, default=1.0)
    args = parser.parse_args()

    sampled: dict[Path, tuple[int, int, bytes]] = {}
    failed = False
    for path in args.paths:
        try:
            sampled[path] = sample(path)
        except (OSError, PNGError, ValueError, IndexError) as error:
            print(f"{path}: invalid screenshot ({error})", file=sys.stderr)
            failed = True

    closest: tuple[float, Path, Path] | None = None
    for left_path, right_path in itertools.combinations(sampled, 2):
        left_width, left_height, left = sampled[left_path]
        right_width, right_height, right = sampled[right_path]
        if (left_width, left_height) != (right_width, right_height):
            continue
        delta = mean_delta(left, right)
        if closest is None or delta < closest[0]:
            closest = (delta, left_path, right_path)
        if delta < args.min_mean_delta:
            print(
                f"near-duplicate routes: {left_path.name} and {right_path.name} "
                f"meanDelta={delta:.3f} < {args.min_mean_delta:.3f}",
                file=sys.stderr,
            )
            failed = True

    if closest:
        print(
            f"closestPair={closest[1].name},{closest[2].name} "
            f"meanDelta={closest[0]:.3f}"
        )
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
