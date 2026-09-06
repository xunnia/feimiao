#!/usr/bin/env python3
"""Reject near-duplicate route screenshots within one platform.

File count and MD5 uniqueness are too weak: a failed cold route can fall back
to Home while the status-bar clock changes a few pixels, producing a distinct
hash. This guard samples the full frame and fails when two declared routes are
perceptually almost identical.

A few scenario pairs are identical by construction rather than by accident:
Android has no dedicated liabilities or reconciliation page, so both scenarios
render the asset hub's funds tab. Failing on those would only train people to
ignore a permanently red gate, so the manifest declares them under
`sharedSurfaces` and this guard skips exactly those combinations. Declaring an
overlap does not make the pair valid evidence: the manifest entry carries an
`unproven` list naming the scenarios that still have no comparable Android
page. Exempting them here only keeps the duplicate check honest about what it
is actually testing.
"""

from __future__ import annotations

import argparse
import hashlib
import itertools
import json
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


def digest(path: Path) -> str:
    return hashlib.md5(path.read_bytes()).hexdigest()


def shared_surface_names(manifest_path: Path, platform: str) -> list[set[str]]:
    """File names the manifest declares as one surface on this platform."""
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    by_id = {pair["id"]: pair for pair in manifest.get("pairs", [])}
    groups: list[set[str]] = []
    for group in manifest.get("sharedSurfaces", []):
        if platform not in group.get("platforms", []):
            continue
        names = {
            Path(by_id[scenario][platform]).name
            for scenario in group.get("ids", [])
            if scenario in by_id and platform in by_id[scenario]
        }
        if len(names) > 1:
            groups.append(names)
    return groups


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--min-mean-delta", type=float, default=1.0)
    parser.add_argument(
        "--manifest",
        type=Path,
        help="screenshot_manifest.json, read only for its sharedSurfaces exemptions",
    )
    parser.add_argument(
        "--platform",
        choices=("android", "ios"),
        help="which side of the manifest the given paths belong to",
    )
    args = parser.parse_args()

    exempt: list[set[str]] = []
    if args.manifest and args.platform:
        exempt = shared_surface_names(args.manifest, args.platform)
    elif args.manifest or args.platform:
        parser.error("--manifest and --platform must be given together")

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
        pair = {left_path.name, right_path.name}
        if any(pair <= group for group in exempt):
            print(
                f"declared shared surface, not compared: "
                f"{left_path.name} and {right_path.name}"
            )
            continue
        delta = mean_delta(left, right)
        if closest is None or delta < closest[0]:
            closest = (delta, left_path, right_path)
        if delta >= args.min_mean_delta:
            continue
        if digest(left_path) == digest(right_path):
            # One capture filed under two scenario names. Report it separately:
            # the fix is in the capture driver's routing, not in a threshold.
            print(
                f"identical capture reused: {left_path.name} and "
                f"{right_path.name} are byte-for-byte the same file",
                file=sys.stderr,
            )
        else:
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
