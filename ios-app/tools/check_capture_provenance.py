#!/usr/bin/env python3
"""Refuse to compare screenshots that cannot say where they came from.

`write_parity_metadata.py` already records a capture's provenance, but nothing
consumed it: the comparison and the P0 report happily read whatever PNGs were
on disk. That is how a set of 39 pairs reached "39/39 compared" while every
single pair was unprovenanced, and how an Android capture taken at one revision
could be compared against an iOS capture taken at another.

This guard runs before any comparison and fails when:

  * either side has no capture-metadata.json;
  * a capture's baseline or fixture does not match the manifest it is being
    compared under;
  * the two sides were not captured from the same source revision;
  * a capture's recorded app version disagrees with the manifest baseline.

A screenshot without provenance is not weak evidence, it is not evidence, so
this fails the build rather than emitting a warning.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from write_parity_metadata import fixture_hash


class ProvenanceError(Exception):
    """A capture cannot be trusted as evidence."""


def load_metadata(path: Path, platform: str) -> dict:
    if not path.is_file():
        raise ProvenanceError(
            f"{platform}: {path} is missing — this capture has no provenance and "
            f"cannot be used as parity evidence. Re-run the capture job so "
            f"write_parity_metadata.py records it."
        )
    try:
        metadata = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise ProvenanceError(f"{platform}: {path} is unreadable ({error})") from error
    if metadata.get("platform") != platform:
        raise ProvenanceError(
            f"{platform}: {path} is labelled platform="
            f"{metadata.get('platform')!r}; the wrong artifact was downloaded"
        )
    return metadata


def check_against_manifest(
    metadata: dict,
    baseline: dict,
    platform: str,
    allow_baseline_drift: bool,
    warnings: list[str],
) -> list[str]:
    problems: list[str] = []
    if metadata.get("baselineId") != baseline.get("id"):
        problems.append(
            f"{platform}: captured under baseline {metadata.get('baselineId')!r} "
            f"but compared under {baseline.get('id')!r}"
        )
    expected_fixture = fixture_hash(baseline)
    if metadata.get("fixtureHash") != expected_fixture:
        problems.append(
            f"{platform}: fixtureHash {metadata.get('fixtureHash')!r} does not "
            f"match the manifest fixture ({expected_fixture})"
        )
    if not metadata.get("sourceRevision"):
        problems.append(f"{platform}: no sourceRevision recorded")

    versions = metadata.get("sourceVersions") or {}
    version_key = "androidVersion" if platform == "android" else "iosVersion"
    recorded = versions.get(version_key)
    declared = baseline.get(version_key)
    if recorded != declared:
        message = (
            f"{platform}: captured from {version_key}={recorded!r} but the "
            f"manifest baseline declares {declared!r}. The baseline has drifted "
            f"from the source it is meant to describe: either re-lock it "
            f"(update baseline.{version_key} and baseline.id in the manifest, "
            f"then recapture both sides) or capture from the declared version. "
            f"Comparing across versions is what makes a report unfalsifiable."
        )
        if allow_baseline_drift:
            warnings.append(message)
        else:
            problems.append(message)
    return problems


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--android-metadata", type=Path, required=True)
    parser.add_argument("--ios-metadata", type=Path, required=True)
    parser.add_argument(
        "--expect-revision",
        help="fail unless both captures came from this commit (e.g. the workflow SHA)",
    )
    parser.add_argument(
        "--allow-baseline-drift",
        action="store_true",
        help=(
            "downgrade 'captured version differs from the declared baseline' to a "
            "warning. The two sides must still share one revision. Use this only "
            "while deliberately capturing ahead of a baseline that is about to be "
            "re-locked, and never as the default in CI."
        ),
    )
    args = parser.parse_args()

    root = args.root.resolve()
    manifest = json.loads((root / args.manifest).read_text(encoding="utf-8"))
    baseline = manifest["baseline"]

    problems: list[str] = []
    warnings: list[str] = []
    captures: dict[str, dict] = {}
    for platform, path in (
        ("android", args.android_metadata),
        ("ios", args.ios_metadata),
    ):
        try:
            captures[platform] = load_metadata(root / path, platform)
        except ProvenanceError as error:
            problems.append(str(error))

    for platform, metadata in captures.items():
        problems.extend(
            check_against_manifest(
                metadata, baseline, platform, args.allow_baseline_drift, warnings
            )
        )

    if len(captures) == 2:
        revisions = {p: m.get("sourceRevision") for p, m in captures.items()}
        if len(set(revisions.values())) > 1:
            problems.append(
                "the two sides were captured from different revisions "
                f"(android={revisions['android']}, ios={revisions['ios']}); "
                "a pair built from two different commits proves nothing"
            )
        elif args.expect_revision and revisions["android"] != args.expect_revision:
            problems.append(
                f"captures came from {revisions['android']} but this run is "
                f"comparing {args.expect_revision}"
            )

    for warning in warnings:
        print(f"warning: {warning}")

    if problems:
        print("capture provenance check failed:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    shared = next(iter(captures.values()))
    print(
        f"provenance ok: baseline={shared.get('baselineId')} "
        f"revision={shared.get('sourceRevision')} "
        f"android={captures['android'].get('device')} "
        f"ios={captures['ios'].get('device')}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
