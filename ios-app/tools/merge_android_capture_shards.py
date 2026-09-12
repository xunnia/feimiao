#!/usr/bin/env python3
"""Merge successful independent captures without rewriting their provenance."""
import argparse
import copy
import json
import shutil
import subprocess
from pathlib import Path


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def collect(shards, count, revision):
    directories = sorted(shards.glob("android-parity-shard-*"))
    if len(directories) != count:
        raise ValueError("Missing or extra capture shards")
    seen, images, entries, sources = set(), set(), [], []
    baseline = business = None
    for directory in directories:
        receipt = load(directory / "shard.json")
        index = receipt["index"]
        if receipt["count"] != count or index not in range(count) or index in seen:
            raise ValueError("Invalid or duplicate shard receipt")
        seen.add(index)
        metadata = load(directory / "capture-metadata.json")
        if metadata["sourceRevision"] != revision or metadata["platform"] != "android":
            raise ValueError("Capture revision/platform differs from checked-out source")
        current_business = load(directory / "p0-business-android.json")
        if baseline is None:
            baseline, business = metadata, current_business
        elif any(metadata[key] != baseline[key] for key in ("fixture", "sourceVersions", "schemaVersion")):
            raise ValueError("Shard fixture/version mismatch")
        elif current_business != business:
            raise ValueError("Shard business data mismatch")
        if not metadata["screenshots"]:
            raise ValueError("Empty shard")
        owned_list = (directory / "shard-images.txt").read_text(encoding="utf-8").splitlines()
        owned = set(owned_list)
        if not owned or len(owned) != len(owned_list) or any(Path(name).name != name for name in owned):
            raise ValueError("Invalid shard image ownership")
        captured = set()
        for entry in metadata["screenshots"]:
            entry_sources = []
            for key, suffix in (("imagePath", ".png"), ("sidecarPath", ".metadata.json")):
                relative = Path(entry[key])
                if relative.parent.as_posix() != "android-app/outputs/parity" or not relative.name.endswith(suffix):
                    raise ValueError("Unexpected artifact path")
                source = directory / relative.name
                if source.is_symlink() or not source.is_file():
                    raise ValueError("Missing/unsafe artifact")
                entry_sources.append(source)
            # Navigation helpers can also capture prerequisite pages. Only the
            # assigned scene's batch owns its final image; never choose a copy
            # based on artifact download order or overwrite another capture.
            name = Path(entry["imagePath"]).name
            if name not in owned:
                continue
            captured.add(name)
            sources.extend(entry_sources)
            if entry["imagePath"] in images:
                raise ValueError("Duplicate image across shards")
            images.add(entry["imagePath"])
            entries.append(entry)
        if captured != owned:
            raise ValueError("Shard did not capture all assigned images")
    merged = copy.deepcopy(baseline)
    merged["screenshots"] = entries
    merged["counts"] = {
        "total": len(entries),
        "captured": sum(e["captureStatus"] == "captured" for e in entries),
        "legacyAmbiguous": sum(e["captureStatus"] == "legacy_ambiguous" for e in entries),
        "unmapped": sum(e["captureStatus"] == "unmapped" for e in entries),
    }
    merged["captureShards"] = count
    return merged, business, sources


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--shards", type=Path, required=True)
    parser.add_argument("--count", type=int, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    merged, business, sources = collect(root / args.shards, args.count, revision)
    output = root / "android-app/outputs/parity"
    if output.exists() and any(output.iterdir()):
        raise ValueError("Refusing to merge into nonempty capture directory")
    output.mkdir(parents=True, exist_ok=True)
    for source in sources:
        shutil.copyfile(source, output / source.name)
    for name, payload in (("capture-metadata.json", merged), ("p0-business-android.json", business)):
        (output / name).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Merged {args.count} shards; full metadata/business gates must run next")


if __name__ == "__main__":
    main()
