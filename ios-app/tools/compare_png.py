#!/usr/bin/env python3
"""Create an auditable Android/iOS screenshot comparison report.

The script intentionally uses only the Python standard library so it can run on
GitHub-hosted macOS/Linux runners without installing Pillow. It treats native
platform styling as a visual difference, not a product failure: the gate is
missing files or invalid PNGs, while the report records dimensions and pixel
delta for human review.
"""

from __future__ import annotations

import argparse
import binascii
import json
import struct
import sys
import zlib
from pathlib import Path


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class PNGError(ValueError):
    pass


def _paeth(a: int, b: int, c: int) -> int:
    prediction = a + b - c
    pa = abs(prediction - a)
    pb = abs(prediction - b)
    pc = abs(prediction - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def read_png(path: Path) -> tuple[int, int, bytes]:
    data = path.read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        raise PNGError("not a PNG")

    offset = len(PNG_SIGNATURE)
    width = height = None
    bit_depth = color_type = interlace = None
    idat = bytearray()
    while offset < len(data):
        if offset + 12 > len(data):
            raise PNGError("truncated chunk")
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        kind = data[offset + 4 : offset + 8]
        start = offset + 8
        end = start + length
        if end + 4 > len(data):
            raise PNGError("truncated chunk data")
        payload = data[start:end]
        expected_crc = struct.unpack(">I", data[end : end + 4])[0]
        actual_crc = binascii.crc32(kind + payload) & 0xFFFFFFFF
        if expected_crc != actual_crc:
            raise PNGError(f"bad CRC in {kind.decode('ascii', errors='replace')}")
        offset = end + 4

        if kind == b"IHDR":
            if len(payload) != 13:
                raise PNGError("invalid IHDR")
            width, height, bit_depth, color_type, compression, filter_method, interlace = struct.unpack(
                ">IIBBBBB", payload
            )
            if compression != 0 or filter_method != 0:
                raise PNGError("unsupported PNG compression/filter method")
        elif kind == b"IDAT":
            idat.extend(payload)
        elif kind == b"IEND":
            break

    if width is None or height is None or bit_depth is None or color_type is None:
        raise PNGError("missing IHDR")
    if bit_depth != 8 or color_type not in (2, 6) or interlace != 0:
        raise PNGError("only non-interlaced 8-bit RGB/RGBA PNGs are supported")

    channels = 3 if color_type == 2 else 4
    row_bytes = width * channels
    raw = zlib.decompress(bytes(idat))
    expected = height * (row_bytes + 1)
    if len(raw) != expected:
        raise PNGError(f"unexpected decompressed size: {len(raw)} != {expected}")

    rows: list[bytes] = []
    cursor = 0
    previous = bytes(row_bytes)
    for _ in range(height):
        filter_type = raw[cursor]
        cursor += 1
        encoded = raw[cursor : cursor + row_bytes]
        cursor += row_bytes
        row = bytearray(row_bytes)
        for index, value in enumerate(encoded):
            left = row[index - channels] if index >= channels else 0
            up = previous[index]
            upper_left = previous[index - channels] if index >= channels else 0
            if filter_type == 0:
                decoded = value
            elif filter_type == 1:
                decoded = (value + left) & 0xFF
            elif filter_type == 2:
                decoded = (value + up) & 0xFF
            elif filter_type == 3:
                decoded = (value + ((left + up) // 2)) & 0xFF
            elif filter_type == 4:
                decoded = (value + _paeth(left, up, upper_left)) & 0xFF
            else:
                raise PNGError(f"unsupported PNG row filter: {filter_type}")
            row[index] = decoded
        rows.append(bytes(row))
        previous = bytes(row)

    if color_type == 6:
        return width, height, b"".join(rows)

    # Normalize RGB to RGBA for one comparison path.
    rgba = bytearray()
    for row in rows:
        for index in range(0, len(row), 3):
            rgba.extend(row[index : index + 3])
            rgba.append(255)
    return width, height, bytes(rgba)


def compare_images(android: Path, ios: Path) -> dict[str, object]:
    result: dict[str, object] = {
        "android": str(android),
        "ios": str(ios),
    }
    try:
        android_width, android_height, android_pixels = read_png(android)
        ios_width, ios_height, ios_pixels = read_png(ios)
    except (OSError, PNGError, zlib.error) as error:
        result.update(status="invalid_png", error=str(error))
        return result

    result["androidSize"] = [android_width, android_height]
    result["iosSize"] = [ios_width, ios_height]
    if (android_width, android_height) != (ios_width, ios_height):
        # Pixel 2 and iPhone Air intentionally have different physical pixel
        # sizes. Both valid captures still form a complete pair; keep the
        # mismatch explicit instead of pretending that native layouts are
        # pixel-identical or failing the evidence gate for an expected detail.
        result.update(status="dimension_mismatch", dimensionsMatch=False)
        return result

    changed = 0
    total_delta = 0
    for android_byte, ios_byte in zip(android_pixels, ios_pixels):
        delta = abs(android_byte - ios_byte)
        total_delta += delta
        if delta >= 8:
            changed += 1
    byte_count = max(len(android_pixels), 1)
    result.update(
        status="compared",
        changedChannelRatio=round(changed / byte_count, 6),
        meanAbsoluteChannelDelta=round(total_delta / byte_count, 3),
    )
    return result


def resolve(path: str, root: Path) -> Path:
    candidate = Path(path)
    return candidate if candidate.is_absolute() else root / candidate


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--require-complete",
        action="store_true",
        help="fail when any declared pair is missing or invalid; valid size mismatches remain reportable",
    )
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    pairs = manifest.get("pairs", [])
    if not pairs:
        print("manifest contains no screenshot pairs", file=sys.stderr)
        return 2

    reports = []
    failures = []
    for pair in pairs:
        pair_id = pair["id"]
        android = resolve(pair["android"], args.root)
        ios = resolve(pair["ios"], args.root)
        if not android.exists() and not ios.exists():
            report = {"id": pair_id, "status": "missing_both"}
        elif not android.exists():
            report = {"id": pair_id, "status": "missing_android", "ios": str(ios)}
        elif not ios.exists():
            report = {"id": pair_id, "status": "missing_ios", "android": str(android)}
        else:
            report = {"id": pair_id, **compare_images(android, ios)}
        report["feature"] = pair.get("feature", pair_id)
        report["route"] = pair.get("iosRoute", "")
        report["notes"] = pair.get("notes", "")
        reports.append(report)
        if report["status"] not in {"compared", "dimension_mismatch"}:
            failures.append(pair_id)

    compared = sum(report["status"] in {"compared", "dimension_mismatch"} for report in reports)
    output = {
        "schemaVersion": 1,
        "pairCount": len(reports),
        "comparedCount": compared,
        "incompleteCount": len(failures),
        "reports": reports,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    markdown = [
        "# Android / iOS 截图对比报告",
        "",
        f"已采集并比较：{compared}/{len(reports)}；缺失或无效：{len(failures)}。",
        "",
        "| 功能 | 状态 | Android 尺寸 | iOS 尺寸 | 像素变化比例 | 平均通道差 | 备注 |",
        "|---|---|---:|---:|---:|---:|---|",
    ]
    for report in reports:
        android_size = "x".join(map(str, report.get("androidSize", ["-", "-"])))
        ios_size = "x".join(map(str, report.get("iosSize", ["-", "-"])))
        markdown.append(
            "| {feature} | {status} | {android} | {ios} | {ratio} | {delta} | {notes} |".format(
                feature=report["feature"],
                status=report["status"],
                android=android_size,
                ios=ios_size,
                ratio=report.get("changedChannelRatio", "-"),
                delta=report.get("meanAbsoluteChannelDelta", "-"),
                notes=report.get("notes", "").replace("|", "/"),
            )
        )
    args.output.with_suffix(".md").write_text("\n".join(markdown) + "\n", encoding="utf-8")
    print(json.dumps({"compared": compared, "incomplete": len(failures)}, ensure_ascii=False))

    if args.require_complete and failures:
        print("未完成截图对：" + ", ".join(failures), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
