#!/usr/bin/env python3
"""Check that declared iOS screenshot routes are all captured by CI."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


TOKEN = r'(?:(?:"([^"]+)")|(\S+))'
SHOOT_CALL = re.compile(
    rf"^\s*shoot\s+{TOKEN}\s+{TOKEN}\s*$", re.MULTILINE
)


def manifest_routes(path: Path) -> list[str]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    pairs = payload.get("pairs")
    if not isinstance(pairs, list) or not pairs:
        raise ValueError("manifest contains no pairs")

    ids: list[str] = []
    routes: list[str] = []
    for index, pair in enumerate(pairs, start=1):
        if not isinstance(pair, dict):
            raise ValueError(f"pair {index} is not an object")
        pair_id = pair.get("id")
        route = pair.get("iosRoute")
        if not isinstance(pair_id, str) or not pair_id:
            raise ValueError(f"pair {index} has no non-empty id")
        if not isinstance(route, str) or not route:
            raise ValueError(f"pair {pair_id} has no non-empty iosRoute")
        ids.append(pair_id)
        routes.append(route)

    duplicate_ids = sorted({value for value in ids if ids.count(value) > 1})
    duplicate_routes = sorted({value for value in routes if routes.count(value) > 1})
    if duplicate_ids:
        raise ValueError("duplicate manifest ids: " + ", ".join(duplicate_ids))
    if duplicate_routes:
        raise ValueError("duplicate manifest routes: " + ", ".join(duplicate_routes))
    return routes


def workflow_routes(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    routes: list[str] = []
    for match in SHOOT_CALL.finditer(text):
        # The first TOKEN is groups 1-2; its quoted/unquoted value is in 1/2.
        route = match.group(1) or match.group(2)
        routes.append(route)
    if not routes:
        raise ValueError(f"{path}: no shoot calls found")
    return routes


def check(manifest: Path, workflows: list[Path]) -> int:
    try:
        expected = manifest_routes(manifest)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"{manifest}: invalid manifest ({error})", file=sys.stderr)
        return 1

    expected_set = set(expected)
    failed = False
    for workflow in workflows:
        try:
            actual = workflow_routes(workflow)
        except (OSError, ValueError) as error:
            print(str(error), file=sys.stderr)
            failed = True
            continue

        duplicates = sorted({value for value in actual if actual.count(value) > 1})
        missing = sorted(expected_set - set(actual))
        extra = sorted(set(actual) - expected_set)
        if duplicates:
            print(
                f"{workflow}: duplicate shoot routes: {', '.join(duplicates)}",
                file=sys.stderr,
            )
            failed = True
        if missing:
            print(
                f"{workflow}: missing manifest routes: {', '.join(missing)}",
                file=sys.stderr,
            )
            failed = True
        if extra:
            print(
                f"{workflow}: unlisted shoot routes: {', '.join(extra)}",
                file=sys.stderr,
            )
            failed = True
        if not duplicates and not missing and not extra and len(actual) == len(expected):
            print(f"{workflow}: {len(actual)} routes match manifest")
        elif len(actual) != len(expected):
            print(
                f"{workflow}: capture count {len(actual)} != manifest count {len(expected)}",
                file=sys.stderr,
            )
            failed = True

    return 1 if failed else 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--workflow", type=Path, action="append", required=True)
    args = parser.parse_args()
    return check(args.manifest, args.workflow)


if __name__ == "__main__":
    raise SystemExit(main())
