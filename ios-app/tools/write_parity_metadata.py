#!/usr/bin/env python3
"""Write provenance metadata next to a parity screenshot capture."""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def first_match(source: str, pattern: str) -> str | None:
    match = re.search(pattern, source, re.MULTILINE)
    return match.group(1) if match else None


def git(root: Path, *args: str) -> str:
    try:
        return subprocess.run(
            ("git", *args),
            cwd=root,
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
        ).stdout.strip()
    except OSError:
        return ""


def source_versions(root: Path) -> dict[str, Any]:
    pubspec = read(root / "android-app/pubspec.yaml")
    build_info = read(root / "android-app/lib/build_info.dart")
    repository = read(root / "android-app/lib/data/app_repository.dart")
    project = read(root / "ios-app/project.yml")
    ios_marketing = first_match(project, r'MARKETING_VERSION:\s*"([^\"]+)"')
    ios_build = first_match(project, r'CURRENT_PROJECT_VERSION:\s*"([^\"]+)"')
    return {
        "androidVersion": first_match(pubspec, r"^version:\s*([^\s]+)$"),
        "androidWatermark": first_match(build_info, r"kBuildTag\s*=\s*'([^']+)'"),
        "androidDatabaseVersion": int(
            first_match(repository, r"static const _dbVersion = (\d+);") or 0
        ),
        "iosVersion": f"{ios_marketing}+{ios_build}" if ios_marketing and ios_build else None,
    }


def fixture_hash(baseline: dict[str, Any]) -> str:
    descriptor = {
        "fixture": baseline.get("fixture"),
        "locale": baseline.get("locale"),
        "timezone": baseline.get("timezone"),
        "currency": baseline.get("currency"),
        "book": baseline.get("book"),
        "expected": baseline.get("expected", {}),
    }
    encoded = json.dumps(
        descriptor, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return "sha256:" + hashlib.sha256(encoded).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--platform", choices=("android", "ios"), required=True)
    parser.add_argument("--device", required=True)
    parser.add_argument("--os", dest="os_name", default=platform.platform())
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    root = args.root.resolve()
    manifest = json.loads((root / args.manifest).read_text(encoding="utf-8"))
    baseline = manifest["baseline"]
    computed_fixture_hash = fixture_hash(baseline)
    if baseline.get("fixtureHash") != computed_fixture_hash:
        raise ValueError(
            "manifest fixtureHash does not match its fixture descriptor: "
            f"expected {computed_fixture_hash}"
        )
    fixture_text = baseline.get("fixture", "")
    logical_now = fixture_text.split("QINGJI_DEMO_NOW=", 1)[-1].split(";", 1)[0].strip()
    metadata = {
        "schemaVersion": 1,
        "baselineId": baseline.get("id"),
        "fixtureId": baseline.get("fixtureId"),
        "fixtureHash": computed_fixture_hash,
        "platform": args.platform,
        "device": args.device,
        "os": args.os_name,
        "sourceRevision": git(root, "rev-parse", "HEAD"),
        "sourceBranch": git(root, "branch", "--show-current"),
        "fixture": {
            "demo": True,
            "logicalNow": logical_now,
            "locale": baseline.get("locale"),
            "timezone": baseline.get("timezone"),
            "currency": baseline.get("currency"),
            "book": baseline.get("book"),
            "expected": baseline.get("expected", {}),
        },
        "sourceVersions": source_versions(root),
        "generatedAt": datetime.now(timezone.utc).isoformat(),
    }
    output = root / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
