#!/usr/bin/env python3
"""Write provenance metadata for every Android/iOS parity PNG.

The old parity pipeline wrote only one capture-level JSON file. This tool keeps
that summary for CI and also writes one sidecar next to every image, so a copied
PNG cannot lose its source revision, fixture, route, device, or hash context.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import re
import struct
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def png_dimensions(path: Path) -> tuple[int, int]:
    header = path.read_bytes()[:24]
    if len(header) != 24 or not header.startswith(PNG_SIGNATURE):
        raise ValueError(f"{path} is not a PNG")
    width, height = struct.unpack(">II", header[16:24])
    if width <= 0 or height <= 0:
        raise ValueError(f"{path} has invalid dimensions")
    return width, height


def git(root: Path, *args: str) -> str:
    try:
        result = subprocess.run(
            ("git", *args),
            cwd=root,
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
    except OSError:
        return ""
    return result.stdout.strip()


def first_match(source: str, pattern: str) -> str | None:
    match = re.search(pattern, source, re.MULTILINE)
    return match.group(1) if match else None


def current_source_versions(root: Path) -> dict[str, Any]:
    pubspec = (root / "android-app/pubspec.yaml").read_text(encoding="utf-8")
    build_info = (root / "android-app/lib/build_info.dart").read_text(encoding="utf-8")
    repository = (root / "android-app/lib/data/app_repository.dart").read_text(encoding="utf-8")
    project = (root / "ios-app/project.yml").read_text(encoding="utf-8")
    ios_marketing = first_match(project, r'MARKETING_VERSION:\s*"([^\"]+)"')
    ios_build = first_match(project, r'CURRENT_PROJECT_VERSION:\s*"([^\"]+)"')
    return {
        "androidVersion": first_match(pubspec, r"^version:\s*([^\s]+)$"),
        "androidWatermark": first_match(build_info, r"kBuildTag\s*=\s*'([^']+)'"),
        "androidDatabaseVersion": int(
            first_match(repository, r"static const _dbVersion\s*=\s*(\d+);") or 0
        ),
        "iosVersion": f"{ios_marketing}+{ios_build}" if ios_marketing and ios_build else None,
    }


def legacy_slots(root: Path, contract: dict[str, Any]) -> dict[str, dict[str, Any]]:
    manifest_path = root / "ios-app/tools/screenshot_manifest.json"
    manifest = load_json(manifest_path)
    mapping = {
        item["legacyId"]: item
        for item in contract.get("legacyScreenshotMapping", [])
        if isinstance(item, dict) and isinstance(item.get("legacyId"), str)
    }
    slots: dict[str, dict[str, Any]] = {}
    for pair in manifest.get("pairs", []):
        if not isinstance(pair, dict) or not isinstance(pair.get("id"), str):
            continue
        legacy_id = pair["id"]
        canonical = mapping.get(legacy_id, {"canonicalIds": [legacy_id]})
        canonical_ids = canonical.get("canonicalIds", [])
        for key in ("android", "ios"):
            value = pair.get(key)
            if not isinstance(value, str):
                continue
            slots[Path(value).name] = {
                "legacyId": legacy_id,
                "canonicalRouteIds": canonical_ids,
                "sourcePath": value,
            }
    return slots


def fixture_descriptor(contract: dict[str, Any]) -> dict[str, Any]:
    fixture = contract["fixture"]
    return {
        "fixtureId": fixture["id"],
        "inputHash": fixture["inputHash"],
        "logicalNow": fixture["now"],
        "locale": fixture["locale"],
        "timezone": fixture["timezone"],
        "currency": fixture["currency"],
        "book": fixture["book"],
        "expected": fixture["expected"],
    }


def make_entry(
    root: Path,
    image: Path,
    screenshot_dir: Path,
    contract: dict[str, Any],
    slots: dict[str, dict[str, Any]],
    platform_name: str,
    device: str,
    os_name: str,
    source_revision: str,
    source_branch: str,
    generated_at: str,
) -> dict[str, Any]:
    width, height = png_dimensions(image)
    slot = slots.get(image.name)
    canonical_ids = list(slot.get("canonicalRouteIds", [])) if slot else []
    route_id = canonical_ids[0] if len(canonical_ids) == 1 else None
    if not slot:
        capture_status = "unmapped"
    elif len(canonical_ids) != 1:
        capture_status = "legacy_ambiguous"
    else:
        capture_status = "captured"
    image_relative = image.resolve().relative_to(root.resolve()).as_posix()
    sidecar_relative = image.with_suffix(".metadata.json").resolve().relative_to(root.resolve()).as_posix()
    return {
        "schemaVersion": 2,
        "captureStatus": capture_status,
        "imagePath": image_relative,
        "sidecarPath": sidecar_relative,
        "imageSha256": sha256(image),
        "width": width,
        "height": height,
        "platform": platform_name,
        "device": device,
        "os": os_name,
        "sourceRevision": source_revision,
        "sourceBranch": source_branch,
        "fixture": fixture_descriptor(contract),
        "sourceVersions": current_source_versions(root),
        "legacySlot": slot,
        "routeId": route_id,
        "canonicalRouteIds": canonical_ids,
        "generatedAt": generated_at,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument(
        "--contract",
        type=Path,
        default=Path("ios-app/tools/p0_product_contract.json"),
    )
    parser.add_argument("--platform", choices=("android", "ios"), required=True)
    parser.add_argument("--device", required=True)
    parser.add_argument("--os", dest="os_name", default=platform.platform())
    parser.add_argument("--screenshot-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    root = args.root.resolve()
    contract = load_json((root / args.contract).resolve())
    screenshot_dir = (root / args.screenshot_dir).resolve()
    output = (root / args.output).resolve()
    if not screenshot_dir.is_dir():
        raise ValueError(f"screenshot directory is missing: {screenshot_dir}")
    images = sorted(screenshot_dir.glob("*.png"), key=lambda path: path.name)
    if not images:
        raise ValueError(f"no PNG captures found in {screenshot_dir}")

    source_revision = git(root, "rev-parse", "HEAD")
    source_branch = git(root, "branch", "--show-current")
    generated_at = datetime.now(timezone.utc).isoformat()
    slots = legacy_slots(root, contract)
    entries = [
        make_entry(
            root,
            image,
            screenshot_dir,
            contract,
            slots,
            args.platform,
            args.device,
            args.os_name,
            source_revision,
            source_branch,
            generated_at,
        )
        for image in images
    ]
    aggregate = {
        "schemaVersion": 2,
        "captureType": "parity-screenshots",
        "platform": args.platform,
        "device": args.device,
        "os": args.os_name,
        "sourceRevision": source_revision,
        "sourceBranch": source_branch,
        "fixture": fixture_descriptor(contract),
        "sourceVersions": current_source_versions(root),
        "generatedAt": generated_at,
        "screenshots": entries,
        "counts": {
            "total": len(entries),
            "captured": sum(item["captureStatus"] == "captured" for item in entries),
            "legacyAmbiguous": sum(item["captureStatus"] == "legacy_ambiguous" for item in entries),
            "unmapped": sum(item["captureStatus"] == "unmapped" for item in entries),
        },
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(aggregate, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for entry in entries:
        sidecar = root / entry["sidecarPath"]
        sidecar.write_text(json.dumps(entry, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(output)
    print(json.dumps(aggregate["counts"], ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
