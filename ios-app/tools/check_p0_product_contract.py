#!/usr/bin/env python3
"""Validate the P0 same-product contract and its source anchors.

The checker intentionally distinguishes a structurally valid P0 contract from a
closed P0 gate. A partial contract may pass this checker while still listing
open evidence gates; `P0_COMPLETE` may not.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from collections import Counter
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any


EXPECTED_SCENE_COUNT = 41
EXPECTED_JOURNEY_COUNT = 12
REQUIRED_SPLIT_IDS = {
    "drawer-books",
    "books-management",
    "accounts-management",
    "assets-funds",
    "reconcile",
    "liabilities",
    "net-worth",
}
AMBIGUOUS_LEGACY_IDS = {"books", "accounts", "assets", "reports", "quick-add", "transactions"}
REQUIRED_SCENE_KEYS = {
    "id",
    "phase",
    "board",
    "feature",
    "androidEntry",
    "androidState",
    "androidSource",
    "iosTargetEntry",
    "iosCurrentEntry",
    "iosSource",
    "requiredAnchors",
    "requiredFields",
    "evidence",
}


class ContractError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def load_json(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ContractError(f"cannot read {path}: {error}") from error
    require(isinstance(payload, dict), "contract root must be an object")
    return payload


def text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as error:
        raise ContractError(f"cannot read {path}: {error}") from error


def regex_value(pattern: str, content: str, label: str, flags: int = 0) -> str:
    match = re.search(pattern, content, flags)
    if not match:
        raise ContractError(f"cannot find {label}")
    return match.group(1)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def git_object_exists(repo: Path, revision: str) -> bool:
    result = subprocess.run(
        ["git", "cat-file", "-e", f"{revision}^{{commit}}"],
        cwd=repo,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0


def decimal_value(value: Any, label: str) -> Decimal:
    try:
        return Decimal(str(value))
    except (InvalidOperation, ValueError) as error:
        raise ContractError(f"{label} is not a decimal: {value}") from error


def validate_fixture_semantics(path: Path, contract_fixture: dict[str, Any]) -> None:
    fixture = load_json(path)
    require(fixture.get("fixtureId") == contract_fixture.get("id"), "fixture id differs from contract")
    require(fixture.get("clock") == contract_fixture.get("now"), "fixture clock differs from contract")
    require(fixture.get("locale") == contract_fixture.get("locale"), "fixture locale differs from contract")
    require(fixture.get("timezone") == contract_fixture.get("timezone"), "fixture timezone differs from contract")
    require(fixture.get("currency") == contract_fixture.get("currency"), "fixture currency differs from contract")

    books = fixture.get("books")
    accounts = fixture.get("accounts")
    transactions = fixture.get("transactions")
    require(isinstance(books, list) and books, "fixture books must be non-empty")
    require(isinstance(accounts, list) and accounts, "fixture accounts must be non-empty")
    require(isinstance(transactions, list) and transactions, "fixture transactions must be non-empty")
    book_keys = {item.get("key") for item in books if isinstance(item, dict)}
    account_keys = {item.get("key") for item in accounts if isinstance(item, dict)}
    canonical_account_kinds = {"cash", "debit", "credit", "savings", "investment", "loan", "other"}
    for account in accounts:
        require(account.get("kind") in canonical_account_kinds,
                f"{account.get('key')}: account kind is not an Android canonical storage key")
    transaction_keys = [item.get("key") for item in transactions if isinstance(item, dict)]
    require(len(transaction_keys) == len(transactions), "every fixture transaction needs a key")
    require(len(set(transaction_keys)) == len(transaction_keys), "fixture transaction keys must be unique")
    by_key = {item["key"]: item for item in transactions}

    august_income = Decimal("0")
    august_gross_expense = Decimal("0")
    august_refund = Decimal("0")
    for transaction in transactions:
        transaction_id = transaction["key"]
        require(transaction.get("book") in book_keys, f"{transaction_id}: unknown book")
        require(transaction.get("account") in account_keys, f"{transaction_id}: unknown account")
        if transaction.get("toAccount") is not None:
            require(transaction["toAccount"] in account_keys, f"{transaction_id}: unknown destination account")
        amount = decimal_value(transaction.get("amount"), f"{transaction_id}.amount")
        if transaction.get("refundOf") is not None:
            original = by_key.get(transaction["refundOf"])
            require(original is not None, f"{transaction_id}: refund original is missing")
            require(transaction.get("date") == original.get("date"),
                    f"{transaction_id}: refund must belong to the original bill date")
            require(amount < 0 and transaction.get("eventType") == "refund",
                    f"{transaction_id}: invalid refund representation")
        if not str(transaction.get("date", "")).startswith("2026-08-"):
            continue
        if transaction.get("kind") == "income":
            august_income += amount
        elif transaction.get("kind") == "expense":
            if amount >= 0:
                august_gross_expense += amount
            else:
                august_refund += -amount

    expected = fixture.get("expected")
    require(isinstance(expected, dict), "fixture expected values are missing")
    august_net_expense = august_gross_expense - august_refund
    august_balance = august_income - august_net_expense
    require(august_income == decimal_value(expected.get("augustIncome"), "expected.augustIncome"),
            "fixture August income does not match expected")
    require(august_gross_expense == decimal_value(expected.get("augustGrossExpense"), "expected.augustGrossExpense"),
            "fixture August gross expense does not match expected")
    require(august_refund == decimal_value(expected.get("augustRefund"), "expected.augustRefund"),
            "fixture August refund does not match expected")
    require(august_net_expense == decimal_value(expected.get("augustNetExpense"), "expected.augustNetExpense"),
            "fixture August net expense does not match expected")
    require(august_balance == decimal_value(expected.get("augustBalance"), "expected.augustBalance"),
            "fixture August balance does not match expected")


def validate_baseline(
    payload: dict[str, Any],
    repo: Path,
    require_apk: bool,
    apk_override: Path | None,
) -> list[str]:
    warnings: list[str] = []
    baseline = payload.get("baseline")
    require(isinstance(baseline, dict), "baseline must be an object")
    android = baseline.get("android")
    ios = baseline.get("ios")
    require(isinstance(android, dict), "baseline.android must be an object")
    require(isinstance(ios, dict), "baseline.ios must be an object")

    pubspec_version = regex_value(
        r"^version:\s*([^\s]+)\s*$",
        text(repo / "android-app/pubspec.yaml"),
        "Android pubspec version",
        re.MULTILINE,
    )
    watermark = regex_value(
        r"kBuildTag\s*=\s*'([^']+)'",
        text(repo / "android-app/lib/build_info.dart"),
        "Android watermark",
    )
    database_version = int(
        regex_value(
            r"static const _dbVersion\s*=\s*(\d+)",
            text(repo / "android-app/lib/data/app_repository.dart"),
            "Android database version",
        )
    )
    require(android.get("version") == pubspec_version, "Android version drifted from pubspec.yaml")
    require(android.get("watermark") == watermark, "Android watermark drifted from build_info.dart")
    require(android.get("databaseVersion") == database_version, "Android DB version drifted")

    source_commit = android.get("sourceCommit")
    require(isinstance(source_commit, str) and re.fullmatch(r"[0-9a-f]{40}", source_commit) is not None,
            "baseline.android.sourceCommit must be a full lowercase SHA")
    require(git_object_exists(repo, source_commit), f"Android source commit is unavailable: {source_commit}")

    project = text(repo / "ios-app/project.yml")
    ios_target = regex_value(r"iOS:\s*\"([^\"]+)\"", project, "iOS deployment target")
    ios_version = regex_value(r"MARKETING_VERSION:\s*\"([^\"]+)\"", project, "iOS marketing version")
    ios_build = regex_value(r"CURRENT_PROJECT_VERSION:\s*\"([^\"]+)\"", project, "iOS build version")
    bundle = regex_value(r"PRODUCT_BUNDLE_IDENTIFIER:\s*([^\s]+)", project, "iOS bundle identifier")
    require(ios.get("deploymentTarget") == ios_target, "iOS deployment target drifted from project.yml")
    require(ios.get("version") == f"{ios_version}+{ios_build}", "iOS version drifted from project.yml")
    require(ios.get("bundleIdentifier") == bundle, "iOS bundle identifier drifted from project.yml")
    require(ios.get("productionTarget") == "QingJi", "QingJi must remain the only production app target")

    fixture = payload["fixture"]
    fixture_path = repo / str(fixture.get("file", ""))
    require(fixture_path.is_file(), f"canonical fixture is missing: {fixture_path}")
    fixture_hash = fixture.get("inputHash")
    require(isinstance(fixture_hash, str) and re.fullmatch(r"[0-9A-F]{64}", fixture_hash) is not None,
            "fixture.inputHash must be an uppercase SHA-256")
    require(sha256(fixture_path) == fixture_hash, "canonical fixture SHA-256 differs from the contract")
    validate_fixture_semantics(fixture_path, fixture)

    apk_path = apk_override.resolve() if apk_override is not None else repo / str(android.get("apk", ""))
    if apk_path.is_file():
        require(apk_path.stat().st_size == android.get("apkBytes"), "APK size differs from baseline")
        require(sha256(apk_path) == android.get("apkSha256"), "APK SHA-256 differs from baseline")
    elif require_apk:
        raise ContractError(f"baseline APK is required but missing: {apk_path}")
    else:
        warnings.append(f"APK not present in this worktree; hash check skipped: {apk_path}")
    return warnings


def validate_data_upgrade(payload: dict[str, Any], repo: Path) -> None:
    upgrade = payload.get("dataUpgrade")
    require(isinstance(upgrade, dict), "dataUpgrade must be an object")
    require(upgrade.get("id") == "p0-ios-qingji-upgrade-2026-09-v1",
            "dataUpgrade id is not locked")
    require(upgrade.get("status") in {
        "SPEC_LOCKED_MACOS_EVIDENCE_PENDING",
        "VERIFIED_ON_MACOS",
    }, "invalid dataUpgrade status")

    source = upgrade.get("source")
    require(isinstance(source, dict), "dataUpgrade.source must be an object")
    require(source.get("product") == "QingJi", "dataUpgrade source product must be QingJi")
    require(source.get("store") == "SwiftData", "dataUpgrade source store must be SwiftData")
    require(source.get("container") == "AppModelContainer.shared",
            "dataUpgrade source container drifted")
    source_revision = source.get("sourceRevision")
    require(isinstance(source_revision, str) and re.fullmatch(r"[0-9a-f]{40}", source_revision),
            "dataUpgrade sourceRevision must be a full lowercase SHA")
    require(git_object_exists(repo, source_revision),
            f"dataUpgrade source revision is unavailable: {source_revision}")

    target = upgrade.get("target")
    require(isinstance(target, dict), "dataUpgrade.target must be an object")
    require(target.get("product") == "QingJi", "dataUpgrade target product must be QingJi")
    require(target.get("store") == "SwiftData", "dataUpgrade target store must be SwiftData")
    require(target.get("policy") == "in-place", "dataUpgrade policy must be in-place")
    require(target.get("container") == "AppModelContainer.shared",
            "dataUpgrade target container drifted")
    model_types = target.get("modelTypes")
    require(isinstance(model_types, list) and model_types,
            "dataUpgrade target modelTypes must be non-empty")
    require(len(model_types) == len(set(model_types)) and
            all(isinstance(value, str) and value for value in model_types),
            "dataUpgrade target modelTypes must be unique strings")
    model_source = text(repo / "ios-app/QingJi/Models/AppModelContainer.swift")
    actual_model_types = re.findall(
        r"^\s+([A-Za-z][A-Za-z0-9]+)\.self,",
        model_source,
        re.MULTILINE,
    )
    require(model_types == actual_model_types,
            "dataUpgrade target modelTypes differ from AppModelContainer")

    fixture = upgrade.get("fixture")
    require(isinstance(fixture, dict), "dataUpgrade.fixture must be an object")
    fixture_path = (repo / str(fixture.get("file", ""))).resolve()
    repo_path = repo.resolve()
    require(repo_path == fixture_path or repo_path in fixture_path.parents,
            "dataUpgrade fixture path escapes the repository")
    require(fixture_path.is_file(), f"dataUpgrade fixture is missing: {fixture_path}")
    fixture_hash = fixture.get("inputHash")
    require(isinstance(fixture_hash, str) and re.fullmatch(r"[0-9A-F]{64}", fixture_hash),
            "dataUpgrade fixture inputHash must be an uppercase SHA-256")
    require(sha256(fixture_path) == fixture_hash,
            "dataUpgrade fixture SHA-256 differs from the contract")
    upgrade_fixture = load_json(fixture_path)
    require(upgrade_fixture.get("schemaVersion") == 1,
            "dataUpgrade fixture schemaVersion must be 1")
    require(upgrade_fixture.get("fixtureId") == upgrade["id"],
            "dataUpgrade fixture id differs from contract")
    require(upgrade_fixture.get("source") == source,
            "dataUpgrade fixture source differs from contract")
    require(upgrade_fixture.get("target") == target,
            "dataUpgrade fixture target differs from contract")

    attachment = upgrade_fixture.get("attachment")
    require(isinstance(attachment, dict), "dataUpgrade attachment must be an object")
    relative_path = attachment.get("relativePath")
    require(isinstance(relative_path, str) and relative_path and
            not Path(relative_path).is_absolute() and
            all(part not in {"", ".", ".."} for part in relative_path.split("/")) and
            "\\" not in relative_path,
            "dataUpgrade attachment path is unsafe")
    content = attachment.get("contentUtf8")
    require(isinstance(content, str), "dataUpgrade attachment contentUtf8 is missing")
    content_bytes = content.encode("utf-8")
    require(attachment.get("byteLength") == len(content_bytes),
            "dataUpgrade attachment byteLength differs")
    require(attachment.get("sha256") == hashlib.sha256(content_bytes).hexdigest().upper(),
            "dataUpgrade attachment SHA-256 differs")
    sentinel_rows = upgrade_fixture.get("sentinels")
    require(isinstance(sentinel_rows, list) and sentinel_rows,
            "dataUpgrade sentinels must be non-empty")
    sentinel_ids = [row.get("stableID") for row in sentinel_rows if isinstance(row, dict)]
    require(len(sentinel_ids) == len(sentinel_rows) and
            len(set(sentinel_ids)) == len(sentinel_ids),
            "dataUpgrade sentinel stableIDs must be unique")

    preserve_fields = upgrade.get("preserveFields")
    require(isinstance(preserve_fields, list) and preserve_fields and
            all(isinstance(value, str) and value for value in preserve_fields),
            "dataUpgrade preserveFields must be non-empty")
    require(upgrade_fixture.get("preserveFields") == preserve_fields,
            "dataUpgrade preserveFields differ from fixture")

    android_backup = upgrade.get("androidBackup")
    require(isinstance(android_backup, dict), "dataUpgrade.androidBackup must be an object")
    require(android_backup.get("requiredDatabaseVersion") ==
            payload["baseline"]["android"]["databaseVersion"],
            "dataUpgrade Android DB version differs from baseline")
    samples = android_backup.get("requiredSamples")
    require(samples == ["current-v49", "v40", "v48"],
            "dataUpgrade Android backup sample set is not locked")
    require(android_backup.get("restoreTarget") == "QingJi SwiftData",
            "dataUpgrade Android restore target drifted")
    require(android_backup.get("status") in {"MACOS_EVIDENCE_PENDING", "VERIFIED_ON_MACOS"},
            "invalid dataUpgrade Android backup status")
    require(upgrade_fixture.get("androidBackup") == android_backup,
            "dataUpgrade Android backup contract differs from fixture")

    expected = upgrade.get("expected")
    require(isinstance(expected, dict) and expected and
            all(value is True for value in expected.values()),
            "dataUpgrade expected assertions must all be true")
    require(upgrade_fixture.get("expected") == expected,
            "dataUpgrade expected assertions differ from fixture")
    checks = upgrade.get("requiredChecks")
    require(isinstance(checks, list) and checks and
            all(isinstance(value, str) and value for value in checks),
            "dataUpgrade requiredChecks must be non-empty")
    require(upgrade_fixture.get("requiredChecks") == checks,
            "dataUpgrade requiredChecks differ from fixture")

    if payload["status"] == "P0_COMPLETE":
        require(upgrade["status"] == "VERIFIED_ON_MACOS",
                "P0_COMPLETE requires macOS data upgrade evidence")
        require(android_backup["status"] == "VERIFIED_ON_MACOS",
                "P0_COMPLETE requires macOS Android backup evidence")


def validate_distribution(payload: dict[str, Any]) -> None:
    distribution = payload.get("distribution")
    require(isinstance(distribution, dict), "distribution must be an object")
    require(distribution.get("mode") == "development-sideload",
            "P0 distribution mode must be development-sideload")
    require(distribution.get("status") in {"DECISION_LOCKED", "VERIFIED_ON_MACOS"},
            "invalid distribution status")
    require(distribution.get("deviceInstall") == "signed-ipa-required",
            "device install must require a signed IPA")
    require(distribution.get("simulatorArtifact") ==
            "unsigned-simulator-build-for-evidence-only",
            "simulator artifact policy drifted")
    signing = distribution.get("signing")
    require(isinstance(signing, dict), "distribution.signing must be an object")
    require(signing.get("platform") == "macOS", "distribution signing platform must be macOS")
    require(signing.get("teamType") == "Personal Team or Apple Developer Program",
            "distribution signing team policy drifted")
    require(signing.get("credentialsStatus") in {
        "PENDING_MACOS_USER_INPUT",
        "AVAILABLE_ON_MACOS",
    }, "invalid distribution credentials status")
    excluded = distribution.get("excludedChannels")
    require(excluded == ["TestFlight", "App Store"],
            "P0 distribution excluded channels are not locked")
    required_at_p6 = distribution.get("requiredAtP6")
    require(isinstance(required_at_p6, list) and required_at_p6 and
            all(isinstance(value, str) and value for value in required_at_p6),
            "distribution requiredAtP6 must be non-empty")
    require(distribution.get("changePolicy") ==
            "changing-the-channel-requires-an-explicit-user-decision-and-a-contract-update",
            "distribution change policy drifted")
    if distribution["status"] == "DECISION_LOCKED":
        require(signing["credentialsStatus"] == "PENDING_MACOS_USER_INPUT",
                "locked distribution must record pending macOS credentials")
        require(signing.get("teamId") is None and signing.get("certificate") is None and
                signing.get("provisioningProfile") is None,
                "pending distribution credentials must not contain stale values")
    if payload["status"] == "P0_COMPLETE":
        require(distribution["status"] == "VERIFIED_ON_MACOS",
                "P0_COMPLETE requires macOS distribution evidence")
        require(signing["credentialsStatus"] == "AVAILABLE_ON_MACOS",
                "P0_COMPLETE requires available macOS signing credentials")


def validate_scenes(payload: dict[str, Any], repo: Path) -> Counter[str]:
    scenes = payload.get("scenes")
    require(isinstance(scenes, list), "scenes must be an array")
    require(len(scenes) == EXPECTED_SCENE_COUNT, f"scene count must be {EXPECTED_SCENE_COUNT}")

    ids: list[str] = []
    target_routes: list[str] = []
    phase_counts: Counter[str] = Counter()
    for index, scene in enumerate(scenes, start=1):
        require(isinstance(scene, dict), f"scene {index} must be an object")
        missing = REQUIRED_SCENE_KEYS - set(scene)
        require(not missing, f"scene {index} is missing keys: {', '.join(sorted(missing))}")
        scene_id = scene["id"]
        require(isinstance(scene_id, str) and scene_id, f"scene {index} has an invalid id")
        require(scene_id not in AMBIGUOUS_LEGACY_IDS, f"ambiguous legacy scene id is forbidden: {scene_id}")
        ids.append(scene_id)

        phase = scene["phase"]
        require(phase in {"P1", "P2", "P3", "P4", "P5"}, f"{scene_id}: invalid phase {phase}")
        phase_counts[phase] += 1

        target = scene["iosTargetEntry"]
        require(isinstance(target, str) and target, f"{scene_id}: missing iOS target entry")
        target_routes.append(target)
        current = scene["iosCurrentEntry"]
        require(current is None or (isinstance(current, str) and current),
                f"{scene_id}: iosCurrentEntry must be a string or null")

        for key in ("requiredAnchors", "requiredFields", "androidSource", "iosSource"):
            values = scene[key]
            require(isinstance(values, list) and values, f"{scene_id}: {key} must be a non-empty array")
            require(all(isinstance(value, str) and value for value in values),
                    f"{scene_id}: {key} contains an invalid value")
        for source_key in ("androidSource", "iosSource"):
            for relative in scene[source_key]:
                require((repo / relative).is_file(), f"{scene_id}: missing source anchor {relative}")

        evidence = scene["evidence"]
        require(isinstance(evidence, dict), f"{scene_id}: evidence must be an object")
        require(isinstance(evidence.get("android"), str) and evidence["android"],
                f"{scene_id}: Android evidence status is missing")
        require(isinstance(evidence.get("ios"), str) and evidence["ios"],
                f"{scene_id}: iOS evidence status is missing")

    duplicates = sorted(scene_id for scene_id, count in Counter(ids).items() if count > 1)
    require(not duplicates, "duplicate scene ids: " + ", ".join(duplicates))
    duplicate_routes = sorted(route for route, count in Counter(target_routes).items() if count > 1)
    require(not duplicate_routes, "duplicate iOS target entries: " + ", ".join(duplicate_routes))
    require(REQUIRED_SPLIT_IDS <= set(ids), "required split scene ids are missing")

    expected_phase_counts = payload.get("expectedPhaseCounts")
    require(isinstance(expected_phase_counts, dict), "expectedPhaseCounts must be an object")
    require(dict(phase_counts) == expected_phase_counts,
            f"phase counts differ: actual={dict(phase_counts)} expected={expected_phase_counts}")
    return phase_counts


def validate_screenshot_manifest(payload: dict[str, Any], repo: Path) -> None:
    manifest_path = repo / "ios-app/tools/screenshot_manifest.json"
    manifest = load_json(manifest_path)
    require(manifest.get("schemaVersion") == 1, "screenshot manifest schemaVersion must be 1")
    baseline = manifest.get("baseline")
    require(isinstance(baseline, dict), "screenshot manifest baseline is missing")
    android = payload["baseline"]["android"]
    require(baseline.get("androidVersion") == android["version"], "screenshot manifest Android version drifted")
    require(baseline.get("androidWatermark") == android["watermark"], "screenshot manifest Android watermark drifted")
    require(baseline.get("androidDatabaseVersion") == android["databaseVersion"], "screenshot manifest Android DB version drifted")
    require(baseline.get("iosDeploymentTarget") == payload["baseline"]["ios"]["deploymentTarget"],
            "screenshot manifest iOS deployment target drifted")

    scenes = {scene["id"]: scene for scene in payload["scenes"]}
    pairs = manifest.get("pairs")
    require(isinstance(pairs, list), "screenshot manifest pairs must be an array")
    pair_ids = []
    ios_routes = []
    for index, pair in enumerate(pairs, start=1):
        require(isinstance(pair, dict), f"screenshot manifest pair {index} must be an object")
        pair_id = pair.get("id")
        require(isinstance(pair_id, str) and pair_id, f"screenshot manifest pair {index} has invalid id")
        require(pair_id in scenes, f"screenshot manifest pair {pair_id} is not a canonical scene")
        pair_ids.append(pair_id)
        require(isinstance(pair.get("android"), str) and pair["android"],
                f"screenshot manifest pair {pair_id} has no Android path")
        ios_route = pair.get("iosRoute")
        ios_path = pair.get("ios")
        if ios_route is None:
            require(ios_path is None and pair.get("iosStatus") == "missing",
                    f"screenshot manifest pair {pair_id} has an invalid missing iOS target")
            require(scenes[pair_id].get("iosCurrentEntry") is None,
                    f"screenshot manifest pair {pair_id} hides an existing iOS target")
        else:
            require(isinstance(ios_route, str) and ios_route,
                    f"screenshot manifest pair {pair_id} has an invalid iOS route")
            require(isinstance(ios_path, str) and ios_path,
                    f"screenshot manifest pair {pair_id} has no iOS path")
            ios_routes.append(ios_route)

    require(len(pair_ids) == len(set(pair_ids)), "screenshot manifest ids must be unique")
    require(set(pair_ids) == set(scenes), "screenshot manifest must cover all 41 canonical scenes")
    require(len(ios_routes) == len(set(ios_routes)), "screenshot manifest iOS routes must be unique")


def validate_supporting_contracts(payload: dict[str, Any]) -> None:
    scenes = payload["scenes"]
    scene_ids = {scene["id"] for scene in scenes}
    mappings = payload.get("legacyScreenshotMapping")
    require(isinstance(mappings, list) and len(mappings) == 39,
            "legacyScreenshotMapping must contain the 39 old screenshot slots")
    legacy_ids = [item.get("legacyId") for item in mappings if isinstance(item, dict)]
    require(len(legacy_ids) == 39 and len(set(legacy_ids)) == 39,
            "legacy screenshot ids must be unique")
    mapped_scene_ids: set[str] = set()
    for mapping in mappings:
        canonical_ids = mapping.get("canonicalIds")
        require(isinstance(canonical_ids, list) and canonical_ids,
                f"{mapping.get('legacyId')}: canonicalIds must be non-empty")
        require(set(canonical_ids) <= scene_ids,
                f"{mapping.get('legacyId')}: maps to an unknown canonical scene")
        mapped_scene_ids.update(canonical_ids)
    require(mapped_scene_ids == scene_ids,
            "legacy screenshot mapping must cover all 41 canonical scenes")

    journeys = payload.get("interactionContracts")
    require(isinstance(journeys, list) and len(journeys) == EXPECTED_JOURNEY_COUNT,
            f"interactionContracts must contain {EXPECTED_JOURNEY_COUNT} journeys")
    journey_ids = [item.get("id") for item in journeys if isinstance(item, dict)]
    require(len(journey_ids) == EXPECTED_JOURNEY_COUNT and len(set(journey_ids)) == EXPECTED_JOURNEY_COUNT,
            "interaction journey ids must be unique")
    for journey in journeys:
        require(isinstance(journey.get("assertions"), list) and journey["assertions"],
                f"{journey.get('id')}: assertions must be non-empty")

    capabilities = payload.get("systemCapabilityContracts")
    require(isinstance(capabilities, list) and capabilities, "systemCapabilityContracts must be non-empty")
    capability_ids = [item.get("id") for item in capabilities if isinstance(item, dict)]
    require(len(capability_ids) == len(set(capability_ids)), "system capability ids must be unique")


def validate_policy(payload: dict[str, Any]) -> None:
    require(payload.get("schemaVersion") == 1, "schemaVersion must be 1")
    require(payload.get("status") in {"P0_PARTIAL", "P0_COMPLETE"}, "invalid P0 status")
    product = payload.get("canonicalProduct")
    require(isinstance(product, dict), "canonicalProduct must be an object")
    require(product.get("canonicalPlatform") == "android", "Android must remain canonical")
    require(product.get("iosImplementation") == "QingJi", "QingJi must remain the iOS implementation")
    require(payload.get("globalAllowedPlatformDifferences"), "allowed platform differences are missing")
    require(payload.get("globalForbiddenSubstitutions"), "forbidden substitutions are missing")

    fixture = payload.get("fixture")
    require(isinstance(fixture, dict), "fixture must be an object")
    require(fixture.get("timezone") == "Asia/Shanghai", "fixture timezone must be Asia/Shanghai")
    require(fixture.get("currency") == "CNY", "fixture currency must be CNY")

    open_gates = payload.get("p0OpenGates")
    require(isinstance(open_gates, list), "p0OpenGates must be an array")
    if payload["status"] == "P0_COMPLETE":
        require(not open_gates, "P0_COMPLETE cannot contain open gates")
        require(isinstance(fixture.get("inputHash"), str) and re.fullmatch(r"[0-9A-F]{64}", fixture["inputHash"]),
                "P0_COMPLETE requires an uppercase SHA-256 fixture hash")
    else:
        require(open_gates, "P0_PARTIAL must list its open gates")


def check(contract: Path, require_apk: bool, apk_path: Path | None) -> int:
    try:
        payload = load_json(contract)
        repo = contract.resolve().parents[2]
        validate_policy(payload)
        warnings = validate_baseline(payload, repo, require_apk, apk_path)
        validate_data_upgrade(payload, repo)
        validate_distribution(payload)
        phase_counts = validate_scenes(payload, repo)
        validate_screenshot_manifest(payload, repo)
        validate_supporting_contracts(payload)
    except (ContractError, OSError) as error:
        print(f"P0 contract invalid: {error}", file=sys.stderr)
        return 1

    for warning in warnings:
        print(f"warning: {warning}", file=sys.stderr)
    print(
        f"{payload['status']} contract valid: {EXPECTED_SCENE_COUNT} scenes "
        f"({', '.join(f'{phase}={phase_counts[phase]}' for phase in sorted(phase_counts))}), "
        f"{EXPECTED_JOURNEY_COUNT} journeys, {len(payload['p0OpenGates'])} open gates"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--contract",
        type=Path,
        default=Path(__file__).with_name("p0_product_contract.json"),
    )
    parser.add_argument("--require-apk", action="store_true")
    parser.add_argument(
        "--apk-path",
        type=Path,
        help="validate an external/local artifact without copying it into the worktree",
    )
    args = parser.parse_args()
    return check(args.contract, args.require_apk, args.apk_path)


if __name__ == "__main__":
    raise SystemExit(main())
