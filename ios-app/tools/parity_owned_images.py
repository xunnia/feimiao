"""Resolve scene ownership from the same manifest used by metadata."""
import json
import sys
from pathlib import Path


SUPPLEMENTAL_IMAGES = {
    "stats-month-trend": "stats-month-trend-android.png",
    "stats-month-bottom": "stats-month-top5-android.png",
    "stats-month-controls": "stats-month-picker-android.png",
    "stats-month-priority": (
        "stats-month-pace-android.png",
        "stats-month-pace-activity-android.png",
        "stats-month-budget-ring-android.png",
        "stats-month-pace-detail-android.png",
        "stats-month-cards-android.png",
    ),
    "stats-month-extras": (
        "stats-month-optional-cards-android.png",
        "stats-month-insights-android.png",
        "stats-month-heatmap-android.png",
        "stats-month-radar-android.png",
        "stats-month-stacked-android.png",
    ),
}


def owned_images(manifest, scenes):
    pairs = manifest["pairs"]
    mapping = {pair["id"]: pair["android"] for pair in pairs}
    if len(mapping) != len(pairs) or len(set(scenes)) != len(scenes):
        raise ValueError("Duplicate scene identity")
    if set(mapping) & set(SUPPLEMENTAL_IMAGES):
        raise ValueError("Supplemental scene duplicates a canonical scene")
    mapping.update({scene: [f"android-app/outputs/parity/{image}" for image in
                           (images if isinstance(images, tuple) else (images,))]
                    for scene, images in SUPPLEMENTAL_IMAGES.items()})
    result = []
    for scene in scenes:
        paths = mapping[scene] if isinstance(mapping[scene], list) else [mapping[scene]]
        for item in paths:
            path = Path(item)
            if path.parent.as_posix() != "android-app/outputs/parity" or path.suffix != ".png":
                raise ValueError("Unexpected Android screenshot path")
            result.append(path.name)
    if len(set(result)) != len(result):
        raise ValueError("Duplicate image ownership")
    return result


if __name__ == "__main__":
    manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    print("\n".join(owned_images(manifest, sys.argv[2:])))
