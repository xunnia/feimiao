#!/usr/bin/env python3
"""Validate and compare the Android/iOS P0 business projections."""

from __future__ import annotations

import argparse
import difflib
import json
import sys
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any

from check_p0_business_json import BusinessJSONError, check, load_json, validate


AMOUNT_KEYS = {
    "amount",
    "balance",
    "initialBalance",
    "target",
    "saved",
    "augustIncome",
    "augustGrossExpense",
    "augustRefund",
    "augustNetExpense",
    "augustBalance",
    "budget",
    "fixtureExpectedBalance",
}
DATE_KEYS = {
    "date",
    "settledAt",
    "periodStart",
    "periodEnd",
    "startDate",
    "endDate",
    "logicalNow",
}


def normalized_decimal(value: Any) -> str:
    try:
        return str(Decimal(str(value)))
    except (InvalidOperation, ValueError) as error:
        raise BusinessJSONError(f"not a decimal during comparison: {value}") from error


def normalized_date(value: Any) -> str:
    if value is None:
        return "<null>"
    if not isinstance(value, str):
        raise BusinessJSONError(f"not an ISO date during comparison: {value}")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise BusinessJSONError(f"not an ISO date during comparison: {value}") from error
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def canonical(value: Any, key: str = "") -> Any:
    if isinstance(value, dict):
        return {name: canonical(value[name], name) for name in sorted(value)}
    if isinstance(value, list):
        values = [canonical(item, key) for item in value]
        if all(isinstance(item, dict) and isinstance(item.get("key"), str) for item in values):
            return sorted(values, key=lambda item: item["key"])
        return values
    if key in AMOUNT_KEYS:
        return normalized_decimal(value)
    if key in DATE_KEYS and value is not None:
        return normalized_date(value)
    return value


def diff_paths(left: Any, right: Any, path: str = "$") -> list[str]:
    if type(left) is not type(right):
        return [f"{path}: {left!r} != {right!r}"]
    if isinstance(left, dict):
        differences: list[str] = []
        for key in sorted(set(left) | set(right)):
            if key not in left or key not in right:
                differences.append(f"{path}.{key}: missing on one platform")
            else:
                differences.extend(diff_paths(left[key], right[key], f"{path}.{key}"))
        return differences
    if isinstance(left, list):
        differences = []
        if len(left) != len(right):
            differences.append(f"{path}: list length {len(left)} != {len(right)}")
        for index, (left_item, right_item) in enumerate(zip(left, right)):
            differences.extend(diff_paths(left_item, right_item, f"{path}[{index}]"))
        return differences
    return [] if left == right else [f"{path}: {left!r} != {right!r}"]


def compare(
    android_path: Path,
    ios_path: Path,
    contract_path: Path,
    output: Path,
    require_match: bool,
) -> int:
    try:
        contract = load_json(contract_path)
        fixture_path = (contract_path.parent.parent.parent / contract["fixture"]["file"]).resolve()
        contract["_fixturePath"] = str(fixture_path)
        android = load_json(android_path)
        ios = load_json(ios_path)
        validate(android, contract, "android")
        validate(ios, contract, "ios")
        left = canonical(android)
        right = canonical(ios)
        differences = diff_paths(left, right)
        diff_text = list(
            difflib.unified_diff(
                json.dumps(left, ensure_ascii=False, indent=2).splitlines(),
                json.dumps(right, ensure_ascii=False, indent=2).splitlines(),
                fromfile="android",
                tofile="ios",
                lineterm="",
            )
        )
        report = {
            "schemaVersion": 1,
            "status": "match" if not differences else "different",
            "android": str(android_path),
            "ios": str(ios_path),
            "differenceCount": len(differences),
            "differences": differences,
            "unifiedDiff": diff_text,
        }
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        output.with_suffix(".md").write_text(
            "# P0 Android / iOS 业务字段对比\n\n"
            f"状态：`{report['status']}`；差异数：{len(differences)}。\n\n"
            + ("无业务字段差异。\n" if not differences else "```diff\n" + "\n".join(diff_text) + "\n```\n"),
            encoding="utf-8",
        )
        print(json.dumps({"status": report["status"], "differences": len(differences)}, ensure_ascii=False))
        return 0 if not differences or not require_match else 1
    except (BusinessJSONError, KeyError, OSError, json.JSONDecodeError) as error:
        print(f"business JSON comparison failed: {error}", file=sys.stderr)
        return 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--android", type=Path, required=True)
    parser.add_argument("--ios", type=Path, required=True)
    parser.add_argument("--contract", type=Path, default=Path("ios-app/tools/p0_product_contract.json"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--require-match",
        action="store_true",
        help="fail when the validated business projections differ",
    )
    args = parser.parse_args()
    return compare(
        args.android.resolve(),
        args.ios.resolve(),
        args.contract.resolve(),
        args.output.resolve(),
        args.require_match,
    )


if __name__ == "__main__":
    raise SystemExit(main())
