#!/usr/bin/env python3
"""Validate and report the Android/iOS P0 product baseline.

This is deliberately a contract check, not a pixel-equality check. Android
owns the product entry points and accounting semantics; iOS may render the
same surface with native controls. Existing PNGs are useful evidence only
when their source metadata, fixture, route identity and image surface are
known.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

try:
    from PIL import Image
except ImportError:  # pragma: no cover - CI installs Pillow before this tool.
    Image = None  # type: ignore[assignment]


ANDROID_SIZE = (1080, 1920)
IOS_SIZE = (1260, 2736)
WORKFLOW_SHOOT = re.compile(r"^\s*shoot\s+(\S+)\s+(\S+)\s*$", re.MULTILINE)


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def first_match(source: str, pattern: str) -> str | None:
    match = re.search(pattern, source, re.MULTILINE)
    return match.group(1) if match else None


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


def source_metadata(root: Path) -> dict[str, Any]:
    pubspec = text(root / "android-app/pubspec.yaml")
    build_info = text(root / "android-app/lib/build_info.dart")
    repository = text(root / "android-app/lib/data/app_repository.dart")
    project = text(root / "ios-app/project.yml")
    deployment = first_match(project, r"^    iOS:\s*\"([^\"]+)\"$")
    return {
        "androidVersion": first_match(pubspec, r"^version:\s*([^\s]+)$"),
        "androidWatermark": first_match(build_info, r"kBuildTag\s*=\s*'([^']+)'"),
        "androidDatabaseVersion": int(
            first_match(repository, r"static const _dbVersion = (\d+);") or 0
        ),
        "iosVersion": (
            first_match(project, r'MARKETING_VERSION:\s*"([^\"]+)"')
            + "+"
            + (first_match(project, r'CURRENT_PROJECT_VERSION:\s*"([^\"]+)"') or "")
            if first_match(project, r'MARKETING_VERSION:\s*"([^\"]+)"')
            else None
        ),
        "iosDeploymentTarget": deployment,
    }


def git_metadata(root: Path) -> dict[str, Any]:
    def run(*args: str) -> str:
        try:
            return subprocess.run(
                args,
                cwd=root,
                check=False,
                capture_output=True,
                text=True,
                encoding="utf-8",
            ).stdout.strip()
        except OSError:
            return ""

    status = run("git", "status", "--porcelain")
    return {
        "revision": run("git", "rev-parse", "HEAD"),
        "branch": run("git", "branch", "--show-current"),
        "dirty": bool(status),
        "dirtyEntryCount": len(status.splitlines()) if status else 0,
    }


def route_calls(path: Path) -> list[tuple[str, str]]:
    return [(match.group(1), match.group(2)) for match in WORKFLOW_SHOOT.finditer(text(path))]


def check_source_contract(
    root: Path,
    manifest: dict[str, Any],
    contract: dict[str, Any],
) -> list[dict[str, Any]]:
    expected = manifest["baseline"]
    actual = source_metadata(root)
    checks: list[dict[str, Any]] = []

    def add(name: str, want: Any, got: Any, required: bool = True) -> None:
        checks.append(
            {
                "name": name,
                "expected": want,
                "actual": got,
                "status": "pass" if want == got else ("fail" if required else "review"),
                "required": required,
            }
        )

    add("Android version", expected.get("androidVersion"), actual["androidVersion"])
    add("Android build watermark", expected.get("androidWatermark"), actual["androidWatermark"])
    add(
        "Android database version",
        expected.get("androidDatabaseVersion"),
        actual["androidDatabaseVersion"],
    )
    add("iOS version", expected.get("iosVersion"), actual["iosVersion"])
    add(
        "iOS deployment target",
        expected.get("iosDeploymentTarget"),
        actual["iosDeploymentTarget"],
    )
    add(
        "Fixture hash is self-consistent",
        expected.get("fixtureHash"),
        fixture_hash(expected),
    )

    fixture = expected.get("fixture", "")
    now = contract["baseline"]["fixture"]["now"]
    android_capture = text(root / "android-app/tooling/run_parity_capture.sh")
    android_test = text(root / "android-app/integration_test/parity_screenshots_test.dart")
    ios_workflow = text(root / ".github/workflows/parity-screenshots.yml")
    ios_clock = text(root / "ios-app/QingJi/Models/AppClock.swift")
    ios_root = text(root / "ios-app/QingJi/Views/RootTabView.swift")
    ios_router_tests = text(root / "ios-app/QingJiTests/AppRouterTests.swift")
    add("Manifest fixture date", now in fixture, True)
    add("Android compile-time fixture date", now in android_capture, True)
    add("Android fixture uses AppClock", "AppClock.now" in android_test, True)
    add("iOS fixture date injection", now in ios_workflow, True)
    add(
        "iOS timezone injection",
        True,
        "SIMCTL_CHILD_TZ" in ios_workflow and "Asia/Shanghai" in ios_workflow,
    )
    add("iOS demo clock reads fixture environment", "QINGJI_DEMO_NOW" in ios_clock, True)
    add(
        "iOS import review uses dedicated demo root",
        True,
        "shouldRenderDemoImportReviewAsRoot" in ios_root
        and "importReviewDestination" in ios_root,
    )
    add(
        "iOS import review route has XCTest coverage",
        True,
        "testImportReviewColdLaunchUsesDedicatedRootRoute" in ios_router_tests
        and "testImportReviewDemoLaunchUsesStableRootOnlyForThatRoute" in ios_router_tests,
    )
    add("Fixture id declared", True, bool(expected.get("fixtureId")))
    add("Android expected income", "Decimal.parse('620')" in android_test, True)
    add("Android expected expense", "Decimal.parse('1017.9')" in android_test, True)
    add("Android expected budget", "Decimal.parse('3000')" in android_test, True)

    manifest_ids = {pair["id"] for pair in manifest.get("pairs", [])}
    for scenario in contract["baseline"].get("goldenScenarios", []):
        add(f"Golden scenario declared: {scenario}", scenario in manifest_ids, True)
    for review in contract.get("routeReview", []):
        add(f"Route review declared: {review['id']}", review["id"] in manifest_ids, True)

    workflow = root / ".github/workflows/parity-screenshots.yml"
    expected_routes = [pair["iosRoute"] for pair in manifest.get("pairs", [])]
    actual_routes = [route for route, _ in route_calls(workflow)]
    add(
        "iOS workflow routes match manifest",
        sorted(expected_routes),
        sorted(actual_routes),
    )
    return checks


def image_info(path: Path, expected_size: tuple[int, int]) -> dict[str, Any]:
    if not path.exists():
        return {"status": "missing", "path": str(path)}
    if Image is None:
        return {"status": "unverified", "path": str(path), "reason": "Pillow unavailable"}

    try:
        with Image.open(path) as image:
            rgba = image.convert("RGBA")
            width, height = rgba.size
            alpha = rgba.getchannel("A")
            alpha_min, alpha_max = alpha.getextrema()
            reduced = rgba.resize((64, 64), Image.Resampling.BILINEAR)
            if hasattr(reduced, "get_flattened_data"):
                pixels = list(reduced.get_flattened_data())
            else:
                pixels = list(reduced.getdata())
            near_black_ratio = sum(
                1 for red, green, blue, opacity in pixels
                if opacity < 16 or max(red, green, blue) < 16
            ) / len(pixels)
            valid = (width, height) == expected_size and alpha_min >= 250
            return {
                "status": "pass" if valid else "fail",
                "path": str(path),
                "size": [width, height],
                "expectedSize": list(expected_size),
                "alphaMin": alpha_min,
                "alphaMax": alpha_max,
                "nearBlackRatio": round(near_black_ratio, 6),
                "reason": None if valid else "size or alpha contract failed",
            }
    except Exception as error:  # Pillow raises several format-specific errors.
        return {"status": "fail", "path": str(path), "reason": str(error)}


def metadata_info(
    path: Path,
    platform_name: str,
    baseline: dict[str, Any],
) -> dict[str, Any]:
    if not path.exists():
        return {"status": "unprovenanced", "path": str(path), "reason": "metadata missing"}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return {"status": "fail", "path": str(path), "reason": str(error)}

    fixture_text = baseline.get("fixture", "")
    logical_now = fixture_text.split("QINGJI_DEMO_NOW=", 1)[-1].split(";", 1)[0].strip()
    expected_version = (
        baseline.get("androidVersion") if platform_name == "android" else baseline.get("iosVersion")
    )
    source_versions = payload.get("sourceVersions", {})
    fixture = payload.get("fixture", {})
    checks = {
        "baselineId": payload.get("baselineId") == baseline.get("id"),
        "fixtureId": payload.get("fixtureId") == baseline.get("fixtureId"),
        "fixtureHash": payload.get("fixtureHash") == baseline.get("fixtureHash"),
        "platform": payload.get("platform") == platform_name,
        "sourceRevision": bool(payload.get("sourceRevision")),
        "appVersion": source_versions.get(
            "androidVersion" if platform_name == "android" else "iosVersion"
        )
        == expected_version,
        "logicalNow": fixture.get("logicalNow") == logical_now,
        "locale": fixture.get("locale") == baseline.get("locale"),
        "timezone": fixture.get("timezone") == baseline.get("timezone"),
        "currency": fixture.get("currency") == baseline.get("currency"),
        "book": fixture.get("book") == baseline.get("book"),
    }
    if platform_name == "android":
        checks["databaseVersion"] = (
            source_versions.get("androidDatabaseVersion")
            == baseline.get("androidDatabaseVersion")
        )
        checks["watermark"] = (
            source_versions.get("androidWatermark") == baseline.get("androidWatermark")
        )
    valid = all(checks.values())
    return {
        "status": "pass" if valid else "fail",
        "path": str(path),
        "checks": checks,
        "reason": None if valid else "metadata does not match baseline",
    }


def artifact_path(root: Path, override: Path | None, declared: str) -> Path:
    return (root / override / Path(declared).name) if override else root / declared


def capture_checks(
    root: Path,
    manifest: dict[str, Any],
    android_dir: Path | None,
    ios_dir: Path | None,
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for pair in manifest.get("pairs", []):
        android = artifact_path(root, android_dir, pair["android"])
        ios = artifact_path(root, ios_dir, pair["ios"])
        android_metadata = (
            root / android_dir / "capture-metadata.json"
            if android_dir
            else root / Path(pair["android"]).parent / "capture-metadata.json"
        )
        ios_metadata = (
            root / ios_dir / "capture-metadata.json"
            if ios_dir
            else root / Path(pair["ios"]).parent / "capture-metadata.json"
        )
        android_info = image_info(android, ANDROID_SIZE)
        ios_info = image_info(ios, IOS_SIZE)
        android_provenance = metadata_info(
            android_metadata, "android", manifest["baseline"]
        )
        ios_provenance = metadata_info(ios_metadata, "ios", manifest["baseline"])
        rows.append(
            {
                "id": pair["id"],
                "feature": pair.get("feature", ""),
                "android": android_info,
                "ios": ios_info,
                "metadata": {
                    "android": android_provenance,
                    "ios": ios_provenance,
                },
                "status": (
                    "pass"
                    if (
                        android_info["status"] == "pass"
                        and ios_info["status"] == "pass"
                        and android_provenance["status"] == "pass"
                        and ios_provenance["status"] == "pass"
                    )
                    else "incomplete"
                ),
            }
        )
    return rows


def route_review(contract: dict[str, Any]) -> list[dict[str, Any]]:
    return list(contract.get("routeReview", []))


def render_report(payload: dict[str, Any]) -> str:
    source = payload["sourceChecks"]
    captures = payload["captureChecks"]
    review = payload["routeReview"]
    passed_source = sum(item["status"] == "pass" for item in source)
    passed_pairs = sum(item["status"] == "pass" for item in captures)
    pending_routes = sum(item["status"] == "decision-required" for item in review)

    lines = [
        "# 肥喵记账 P0 同款基线报告",
        "",
        f"- 结论：**{payload['overall']}**",
        f"- 基线：`{payload['baselineId']}`",
        f"- 产品规则：Android 是产品和信息架构母版，iOS 是原生实现，不是第二款软件。",
        f"- 当前源码：`{payload['git']['revision'] or 'unknown'}` / `{payload['git']['branch'] or 'unknown'}`；工作区 dirty=`{payload['git']['dirty']}`",
        "",
        "## 已检查",
        "",
        f"- 源码与 fixture 检查：`{passed_source}/{len(source)}` 项通过",
        f"- PNG + provenance 检查：`{passed_pairs}/{len(captures)}` 对完整有效",
        f"- 待确认路由：`{pending_routes}` 项",
        "",
        "## 源码合同",
        "",
        "| 检查 | 结果 | 期望 | 实际 |",
        "|---|---|---|---|",
    ]
    for item in source:
        lines.append(
            f"| {item['name']} | {item['status']} | `{item['expected']}` | `{item['actual']}` |"
        )

    lines.extend(["", "## 路由未决项", "", "| 场景 | 当前事实 | iOS 路由 | 处理 |", "|---|---|---|---|"])
    for item in review:
        lines.append(
            f"| `{item['id']}` | {item['androidCurrentCapture']} | `{item['iosDeclaredRoute']}` | {item['action']} |"
        )

    lines.extend(
        [
            "",
            "## PNG 与 provenance 证据",
            "",
            "| 场景 | Android PNG/元数据 | iOS PNG/元数据 | 结论 |",
            "|---|---|---|---|",
        ]
    )
    for item in captures:
        android = item["android"]
        ios = item["ios"]
        android_meta = item["metadata"]["android"]["status"]
        ios_meta = item["metadata"]["ios"]["status"]
        lines.append(
            f"| `{item['id']}` | {android['status']}/{android_meta} `{android.get('size', '')}` | {ios['status']}/{ios_meta} `{ios.get('size', '')}` | {item['status']} |"
        )

    lines.extend(
        [
            "",
            "## 当前不能宣称的内容",
            "",
            "1. PNG 文件存在不等于页面身份正确；本次检查的旧 PNG 旁缺少采集提交号和 fixture hash sidecar。",
            "2. 本机没有 Swift/Xcode，无法在 Windows 重新运行 iOS 冷启动截图；当前 iOS PNG 只能算已有证据，不能算本轮重采集通过。",
            "3. `accounts`、`reconcile`、`liabilities`、`net-worth`、`books` 的 Android 入口仍需按真实用户路径确认，不能依据文件名强行判定。",
            "",
            "## 下一步关闭条件",
            "",
            "- 在 macOS CI 重新运行 Android/iOS 双端截图，使用本报告中的版本、fixture、时区和逻辑时间。",
            "- 为每次截图上传 `source revision / app version / DB version / fixture hash / device / OS` 元数据。",
            "- 先确认未决路由，再生成新的成对截图；旧 PNG 不覆盖。",
            "- P0 关闭后才把差异交给 P1 主记账链路处理。",
        ]
    )
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument(
        "--contract", type=Path, default=Path("ios-app/tools/p0_baseline.json")
    )
    parser.add_argument("--android-dir", type=Path)
    parser.add_argument("--ios-dir", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--strict-source", action="store_true")
    args = parser.parse_args()

    root = args.root.resolve()
    manifest = json.loads((root / args.manifest).read_text(encoding="utf-8"))
    contract = json.loads((root / args.contract).read_text(encoding="utf-8"))
    source_checks = check_source_contract(root, manifest, contract)
    captures = capture_checks(root, manifest, args.android_dir, args.ios_dir)
    payload = {
        "schemaVersion": 1,
        "baselineId": manifest["baseline"].get("id", "unknown"),
        "git": git_metadata(root),
        "sourceChecks": source_checks,
        "captureChecks": captures,
        "routeReview": route_review(contract),
        "overall": "P0_PARTIAL",
    }
    if all(item["status"] == "pass" for item in source_checks):
        payload["sourceStatus"] = "PASS"
    else:
        payload["sourceStatus"] = "FAIL"
    if captures and all(item["status"] == "pass" for item in captures):
        payload["captureStatus"] = "PASS"
    else:
        payload["captureStatus"] = "INCOMPLETE"
    if (
        payload["sourceStatus"] == "PASS"
        and payload["captureStatus"] == "PASS"
        and not any(item["status"] == "decision-required" for item in payload["routeReview"])
    ):
        payload["overall"] = "P0_PASS"

    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "p0-baseline-report.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (args.output_dir / "p0-baseline-report.md").write_text(
        render_report(payload), encoding="utf-8"
    )
    print(render_report(payload))
    if args.strict_source and payload["sourceStatus"] != "PASS":
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
