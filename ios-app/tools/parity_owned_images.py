"""Resolve scene ownership from the same manifest used by metadata."""
import json
import sys
from pathlib import Path


SUPPLEMENTAL_IMAGES = {
    "stats-month-trend": "stats-month-trend-android.png",
}


def owned_images(manifest, scenes):
    pairs = manifest["pairs"]
    mapping = {pair["id"]: pair["android"] for pair in pairs}
    if len(mapping) != len(pairs) or len(set(scenes)) != len(scenes):
        raise ValueError("Duplicate scene identity")
    if set(mapping) & set(SUPPLEMENTAL_IMAGES):
        raise ValueError("Supplemental scene duplicates a canonical scene")
    mapping.update({scene: f"android-app/outputs/parity/{image}"
                    for scene, image in SUPPLEMENTAL_IMAGES.items()})
    result = []
    for scene in scenes:
        path = Path(mapping[scene])
        if path.parent.as_posix() != "android-app/outputs/parity" or path.suffix != ".png":
            raise ValueError("Unexpected Android screenshot path")
        result.append(path.name)
    if len(set(result)) != len(result):
        raise ValueError("Duplicate image ownership")
    return result


if __name__ == "__main__":
    manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    print("\n".join(owned_images(manifest, sys.argv[2:])))
