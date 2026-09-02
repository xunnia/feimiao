#!/usr/bin/env python3
"""Validate per-image parity provenance metadata."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


EXPECTED_SIZE = {"android": (1080, 1920), "ios": (1260, 2736)}


class MetadataError(ValueError):
    pass


def load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise MetadataError(f"cannot read {path}: {error}") from error
    if not isinstance(value, dict):
        raise MetadataError(f"{path} must contain an object")
    return value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def safe_rooted_path(root: Path, relative: str) -> Path:
    candidate = Path(relative)
    if candidate.is_absolute():
        raise MetadataError(f"metadata path must be relative: {relative}")
    resolved = (root / candidate).resolve()
    root_resolved = root.resolve()
    if resolved != root_resolved and root_resolved not in resolved.parents:
        raise MetadataError(f"metadata path escapes repository root: {relative}")
    return resolved


def expected_route_ids(root: Path, platform_name: str) -> set[str]:
    contract_path = safe_rooted_path(root, "ios-app/tools/p0_product_contract.json")
    contract = load(contract_path)
    scenes = contract.get("scenes")
    if not isinstance(scenes, list):
        raise MetadataError("P0 contract scenes are missing")
    scene_ids = {
        scene.get("id")
        for scene in scenes
        if isinstance(scene, dict) and isinstance(scene.get("id"), str)
    }
    scene_by_id = {
        scene["id"]: scene
        for scene in scenes
        if isinstance(scene, dict) and isinstance(scene.get("id"), str)
    }
    if len(scene_ids) != 41:
        raise MetadataError("P0 contract must contain 41 canonical scenes")
    if platform_name == "android":
        return scene_ids

    # An iOS gap is valid only when the manifest explicitly declares it and
    # the scene has no existing iOS entry. Every other canonical scene must
    # have a concrete route and screenshot path.
    manifest_path = safe_rooted_path(root, "ios-app/tools/screenshot_manifest.json")
    manifest = load(manifest_path)
    pairs = manifest.get("pairs")
    if not isinstance(pairs, list):
        raise MetadataError("screenshot manifest pairs are missing")
    routes: set[str] = set()
    missing_ids: set[str] = set()
    pair_ids: set[str] = set()
    for pair in pairs:
        if not isinstance(pair, dict) or not isinstance(pair.get("id"), str):
            raise MetadataError("screenshot manifest contains an invalid pair")
        pair_id = pair["id"]
        if pair_id in pair_ids:
            raise MetadataError(f"screenshot manifest contains duplicate pair {pair_id}")
        pair_ids.add(pair_id)
        if pair_id not in scene_ids:
            raise MetadataError(f"screenshot manifest contains unknown scene {pair_id}")
        ios_path = pair.get("ios")
        ios_route = pair.get("iosRoute")
        if ios_path is None:
            if pair.get("iosStatus") != "missing" or ios_route is not None:
                raise MetadataError(f"{pair_id}: invalid declared iOS gap")
            if scene_by_id[pair_id].get("iosCurrentEntry") is not None:
                raise MetadataError(f"{pair_id}: manifest hides an existing iOS entry")
            missing_ids.add(pair_id)
            continue
        if not isinstance(ios_path, str) or not ios_path:
            raise MetadataError(f"{pair_id}: iOS screenshot path is missing")
        if not isinstance(ios_route, str) or not ios_route:
            raise MetadataError(f"{pair_id}: iOS route is missing")
        routes.add(pair_id)
    if pair_ids != scene_ids or routes != scene_ids - missing_ids:
        raise MetadataError("iOS manifest does not cover the canonical scenes consistently")
    return routes


def check(root: Path, metadata_path: Path, platform_name: str, require_complete: bool) -> int:
    try:
        aggregate = load(metadata_path)
        if aggregate.get("schemaVersion") != 2:
            raise MetadataError("schemaVersion must be 2")
        if aggregate.get("platform") != platform_name:
            raise MetadataError(
                f"platform mismatch: metadata={aggregate.get('platform')} expected={platform_name}"
            )
        fixture = aggregate.get("fixture")
        if not isinstance(fixture, dict):
            raise MetadataError("fixture metadata is missing")
        if not isinstance(fixture.get("fixtureId"), str) or not fixture["fixtureId"]:
            raise MetadataError("fixtureId is missing")
        if not re.fullmatch(r"[0-9A-F]{64}", str(fixture.get("inputHash", ""))):
            raise MetadataError("fixture inputHash is not an uppercase SHA-256")
        source_revision = aggregate.get("sourceRevision")
        if not isinstance(source_revision, str) or not re.fullmatch(r"[0-9a-f]{40}", source_revision):
            raise MetadataError("sourceRevision must be a full commit SHA")
        entries = aggregate.get("screenshots")
        if not isinstance(entries, list) or not entries:
            raise MetadataError("screenshots must be a non-empty array")

        seen_images: set[str] = set()
        route_ids: list[str] = []
        expected_width, expected_height = EXPECTED_SIZE[platform_name]
        for entry in entries:
            if not isinstance(entry, dict):
                raise MetadataError("screenshot entry is not an object")
            image_path = entry.get("imagePath")
            sidecar_path = entry.get("sidecarPath")
            if not isinstance(image_path, str) or not isinstance(sidecar_path, str):
                raise MetadataError("imagePath/sidecarPath are required")
            if image_path in seen_images:
                raise MetadataError(f"duplicate image entry: {image_path}")
            seen_images.add(image_path)
            image = safe_rooted_path(root, image_path)
            sidecar = safe_rooted_path(root, sidecar_path)
            if not image.is_file():
                raise MetadataError(f"image is missing: {image}")
            if not sidecar.is_file():
                raise MetadataError(f"sidecar is missing: {sidecar}")
            if entry.get("platform") != platform_name:
                raise MetadataError(f"{image_path}: platform mismatch")
            if entry.get("fixture") != fixture:
                raise MetadataError(f"{image_path}: fixture differs from aggregate")
            if entry.get("sourceRevision") != source_revision:
                raise MetadataError(f"{image_path}: source revision differs from aggregate")
            if entry.get("imageSha256") != sha256(image):
                raise MetadataError(f"{image_path}: image SHA-256 differs")
            if (entry.get("width"), entry.get("height")) != (expected_width, expected_height):
                raise MetadataError(
                    f"{image_path}: expected {expected_width}x{expected_height}, "
                    f"got {entry.get('width')}x{entry.get('height')}"
                )
            sidecar_payload = load(sidecar)
            if sidecar_payload != entry:
                raise MetadataError(f"{image_path}: sidecar does not match aggregate entry")
            status = entry.get("captureStatus")
            if status == "captured":
                route_id = entry.get("routeId")
                if not isinstance(route_id, str) or not route_id:
                    raise MetadataError(f"{image_path}: captured image has no routeId")
                route_ids.append(route_id)
            elif status not in {"legacy_ambiguous", "unmapped"}:
                raise MetadataError(f"{image_path}: unknown captureStatus {status}")

        if require_complete:
            expected_routes = expected_route_ids(root, platform_name)
            if set(route_ids) != expected_routes or len(route_ids) != len(expected_routes):
                missing = sorted(expected_routes - set(route_ids))
                extra = sorted(set(route_ids) - expected_routes)
                raise MetadataError(f"complete capture route mismatch: missing={missing} extra={extra}")
            if any(entry.get("captureStatus") != "captured" for entry in entries):
                raise MetadataError("complete capture cannot contain ambiguous or unmapped images")

        print(
            f"capture metadata valid: {len(entries)} images, "
            f"captured={sum(entry.get('captureStatus') == 'captured' for entry in entries)}, "
            f"ambiguous={sum(entry.get('captureStatus') == 'legacy_ambiguous' for entry in entries)}, "
            f"unmapped={sum(entry.get('captureStatus') == 'unmapped' for entry in entries)}"
        )
        return 0
    except MetadataError as error:
        print(f"capture metadata invalid: {error}", file=sys.stderr)
        return 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--platform", choices=("android", "ios"), required=True)
    parser.add_argument("--require-complete", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    metadata = args.metadata if args.metadata.is_absolute() else root / args.metadata
    return check(root, metadata.resolve(), args.platform, args.require_complete)


if __name__ == "__main__":
    raise SystemExit(main())
