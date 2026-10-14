"""Validate XCTest attachment files and build overviews, not before/after evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageStat

from make_ios_ui_comparisons import font


THEMES = ("warm", "white", "pink", "mint", "blue", "night")
EXPECTED = {
    *(f"form-{theme}" for theme in THEMES),
    *(f"confirmation-{theme}-{action}" for theme in THEMES for action in ("delete", "ordinary")),
    "form-warm-dark", "form-pink-320-large",
    "confirmation-warm-dark", "confirmation-pink-320-large",
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inspect_attachments(source: Path) -> list[dict]:
    manifest = json.loads((source / "manifest.json").read_text(encoding="utf-8"))
    if not isinstance(manifest, list):
        raise ValueError("Expected the xcresulttool attachment array")
    records = []
    names, filenames = set(), set()
    for test in manifest:
        for attachment in test["attachments"]:
            filename = attachment["exportedFileName"]
            if Path(filename).name != filename or "/" in filename or "\\" in filename:
                raise ValueError(f"Unsafe attachment filename: {filename}")
            name = attachment["suggestedHumanReadableName"].split("_", 1)[0]
            if name not in EXPECTED or name in names or filename in filenames:
                raise ValueError(f"Unexpected or duplicate attachment: {name}")
            if attachment["deviceName"] != "iPhone Air":
                raise ValueError(f"Unexpected device for {name}")
            names.add(name)
            filenames.add(filename)
            path = source / filename
            with Image.open(path) as original:
                original.verify()
            with Image.open(path) as original:
                expected_size = (960 if "320-large" in name else 1260, 2736)
                if original.format != "PNG" or original.size != expected_size:
                    raise ValueError(f"Unexpected PNG dimensions for {name}: {original.size}")
                deviation = ImageStat.Stat(original.convert("RGB")).stddev
                if max(deviation) <= 1:
                    raise ValueError(f"Blank capture: {name}")
                records.append({
                    "name": name, "file": filename, "test": test["testIdentifier"],
                    "size": list(original.size), "sha256": digest(path),
                    "alphaRange": list(original.convert("RGBA").getchannel("A").getextrema()),
                    "channelStdDev": deviation,
                })
    if names != EXPECTED:
        raise ValueError(f"Missing attachments: {sorted(EXPECTED - names)}")
    return sorted(records, key=lambda item: item["name"])


def overview(source: Path, output: Path, records: list[dict], kind: str) -> None:
    selected = [item for item in records if item["name"].startswith(kind + "-")]
    columns, tile_width, tile_height = 4, 360, 800
    rows = (len(selected) + columns - 1) // columns
    canvas = Image.new("RGB", (columns * tile_width, 90 + rows * tile_height), "#eeeeee")
    draw = ImageDraw.Draw(canvas)
    draw.text((16, 10), "iPhone Air XCTest - " + kind, font=font(23), fill="#222222")
    draw.text((16, 44), "组件原图缩略总览；不是完整页面或前后对比，语言/裁切需人工复核。",
              font=font(16), fill="#555555")
    for index, item in enumerate(selected):
        x, y = index % columns * tile_width, 90 + index // columns * tile_height
        draw.text((x + 12, y + 8), item["name"], font=font(16), fill="#222222")
        with Image.open(source / item["file"]) as original:
            thumbnail = original.convert("RGBA")
            thumbnail.thumbnail((tile_width - 24, tile_height - 60), Image.Resampling.LANCZOS)
            canvas.paste(thumbnail, (x + (tile_width - thumbnail.width) // 2, y + 42), thumbnail)
    canvas.save(output / f"overview-{kind}.png", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.resolve() == args.source.resolve():
        raise ValueError("Keep generated summaries separate from original attachments")
    records = inspect_attachments(args.source)
    args.output.mkdir(parents=True, exist_ok=True)
    for kind in ("form", "confirmation"):
        overview(args.source, args.output, records, kind)
    if any(digest(args.source / item["file"]) != item["sha256"] for item in records):
        raise ValueError("An original attachment changed during review")
    receipt = {
        "sourceFileChecksPassed": True, "captureCount": len(records), "captures": records,
        "scope": "XCTest component attachments only; not full-page, before/after or device acceptance",
    }
    (args.output / "attachment-review.json").write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Validated {len(records)} original attachments; wrote two component overviews to {args.output}")


if __name__ == "__main__":
    main()
