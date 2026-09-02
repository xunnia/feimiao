#!/usr/bin/env python3
"""Validate a platform's P0 business projection against the canonical fixture."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any


class BusinessJSONError(ValueError):
    pass


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise BusinessJSONError(f"cannot read {path}: {error}") from error
    if not isinstance(value, dict):
        raise BusinessJSONError(f"{path} must contain an object")
    return value


def decimal(value: Any, label: str) -> Decimal:
    try:
        return Decimal(str(value))
    except (InvalidOperation, ValueError) as error:
        raise BusinessJSONError(f"{label} is not a decimal: {value}") from error


def date_value(value: Any, label: str) -> datetime:
    if not isinstance(value, str) or not value:
        raise BusinessJSONError(f"{label} is not an ISO date")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise BusinessJSONError(f"{label} is not an ISO date: {value}") from error
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def same_amount(actual: Any, expected: Any, label: str) -> None:
    if decimal(actual, label) != decimal(expected, label):
        raise BusinessJSONError(f"{label} differs: actual={actual} expected={expected}")


def same_date(actual: Any, expected: Any, label: str) -> None:
    if date_value(actual, label) != date_value(expected, label):
        raise BusinessJSONError(f"{label} differs: actual={actual} expected={expected}")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise BusinessJSONError(message)


def rows_by_key(value: Any, label: str) -> dict[str, dict[str, Any]]:
    require(isinstance(value, list), f"{label} must be an array")
    result: dict[str, dict[str, Any]] = {}
    for row in value:
        require(isinstance(row, dict), f"{label} contains a non-object row")
        key = row.get("key")
        require(isinstance(key, str) and key, f"{label} row has no key")
        require(key not in result, f"{label} contains duplicate key {key}")
        result[key] = row
    return result


def expected_event_type(kind: str, row: dict[str, Any]) -> str:
    explicit = row.get("eventType")
    if isinstance(explicit, str) and explicit:
        return explicit
    return {"expense": "expense", "income": "income", "transfer": "transfer"}.get(
        kind, "legacy_adjustment"
    )


def expected_account_balances(fixture: dict[str, Any]) -> dict[str, Decimal]:
    accounts = rows_by_key(fixture.get("accounts"), "fixture.accounts")
    balances = {key: decimal(row["initialBalance"], f"account {key}") for key, row in accounts.items()}
    for row in fixture.get("transactions", []):
        kind = row["kind"]
        amount = decimal(row["amount"], f"transaction {row['key']}")
        absolute = abs(amount)
        event = expected_event_type(kind, row)
        if event == "transfer":
            balances[row["account"]] -= absolute
            if row.get("toAccount"):
                balances[row["toAccount"]] += absolute
        elif event in {"income", "refund", "reimbursement", "asset_sale", "receivable_recovery"}:
            balances[row["settlementAccount"] if row.get("settlementAccount") else row["account"]] += absolute
        else:
            balances[row["settlementAccount"] if row.get("settlementAccount") else row["account"]] -= absolute
    return balances


def validate(payload: dict[str, Any], contract: dict[str, Any], platform: str) -> None:
    require(payload.get("schemaVersion") == 1, "business JSON schemaVersion must be 1")
    require(payload.get("platform") == platform, f"business JSON platform must be {platform}")

    fixture_contract = contract["fixture"]
    metadata = payload.get("fixture")
    require(isinstance(metadata, dict), "business JSON fixture metadata is missing")
    for output_key, contract_key in (
        ("fixtureId", "id"),
        ("logicalNow", "now"),
        ("locale", "locale"),
        ("timezone", "timezone"),
        ("currency", "currency"),
    ):
        require(
            metadata.get(output_key) == fixture_contract[contract_key],
            f"fixture metadata {output_key} differs",
        )
    require(metadata.get("inputHash") == fixture_contract["inputHash"], "fixture inputHash differs")

    fixture = contract_fixture(contract)
    fixture_books = rows_by_key(fixture["books"], "fixture.books")
    fixture_accounts = rows_by_key(fixture["accounts"], "fixture.accounts")
    fixture_transactions = rows_by_key(fixture["transactions"], "fixture.transactions")
    fixture_budgets = rows_by_key(fixture["budgets"], "fixture.budgets")
    fixture_savings = rows_by_key(fixture["savingsGoals"], "fixture.savingsGoals")
    fixture_recurring = rows_by_key(fixture["recurringRules"], "fixture.recurringRules")
    fixture_reports = rows_by_key(fixture["reports"], "fixture.reports")

    actual_books = rows_by_key(payload.get("books"), "books")
    actual_accounts = rows_by_key(payload.get("accounts"), "accounts")
    actual_transactions = rows_by_key(payload.get("transactions"), "transactions")
    actual_budgets = rows_by_key(payload.get("budgets"), "budgets")
    actual_savings = rows_by_key(payload.get("savingsGoals"), "savingsGoals")
    actual_recurring = rows_by_key(payload.get("recurringRules"), "recurringRules")
    actual_reports = rows_by_key(payload.get("reports"), "reports")

    for label, actual, expected in (
        ("books", actual_books, fixture_books),
        ("accounts", actual_accounts, fixture_accounts),
        ("transactions", actual_transactions, fixture_transactions),
        ("budgets", actual_budgets, fixture_budgets),
        ("savingsGoals", actual_savings, fixture_savings),
        ("recurringRules", actual_recurring, fixture_recurring),
        ("reports", actual_reports, fixture_reports),
    ):
        require(set(actual) == set(expected), f"{label} keys differ")

    for key, expected in fixture_books.items():
        actual = actual_books[key]
        require(actual.get("name") == expected["name"], f"book {key} name differs")
        require(actual.get("includeInTotal") == expected["includeInTotal"], f"book {key} includeInTotal differs")
        require(actual.get("isDefault") == expected["isDefault"], f"book {key} isDefault differs")
        require(actual.get("sortOrder") == expected["sortOrder"], f"book {key} sortOrder differs")

    balances = expected_account_balances(fixture)
    for key, expected in fixture_accounts.items():
        actual = actual_accounts[key]
        require(actual.get("name") == expected["name"], f"account {key} name differs")
        require(actual.get("kind") == expected["kind"], f"account {key} kind differs")
        same_amount(actual.get("initialBalance"), expected["initialBalance"], f"account {key} initialBalance")
        same_amount(actual.get("balance"), balances[key], f"account {key} balance")
        require(actual.get("sortOrder") == expected["sortOrder"], f"account {key} sortOrder differs")

    for key, expected in fixture_transactions.items():
        actual = actual_transactions[key]
        for field in ("kind", "category", "account", "toAccount", "book", "note", "reimbursable", "excluded"):
            expected_value = expected.get(field)
            if field in {"reimbursable", "excluded"}:
                expected_value = expected_value if expected_value is not None else False
            require(actual.get(field) == expected_value, f"transaction {key} {field} differs")
        same_amount(actual.get("amount"), expected["amount"], f"transaction {key} amount")
        same_date(actual.get("date"), expected["date"], f"transaction {key} date")
        expected_settled = expected.get("settledAt") or expected["date"]
        same_date(actual.get("settledAt"), expected_settled, f"transaction {key} settledAt")
        expected_settlement_account = expected.get("settlementAccount") or expected["account"]
        require(actual.get("settlementAccount") == expected_settlement_account, f"transaction {key} settlementAccount differs")
        require(actual.get("eventType") == expected_event_type(expected["kind"], expected), f"transaction {key} eventType differs")
        require(actual.get("isReimbursed") is False, f"transaction {key} isReimbursed must be false")
        require(actual.get("refundOf") == expected.get("refundOf"), f"transaction {key} refundOf differs")

    for key, expected in fixture_budgets.items():
        actual = actual_budgets[key]
        for field in ("book", "category", "cycle"):
            require(actual.get(field) == expected.get(field), f"budget {key} {field} differs")
        same_amount(actual.get("amount"), expected["amount"], f"budget {key} amount")
        same_date(actual.get("periodStart"), expected["periodStart"], f"budget {key} periodStart")

    for key, expected in fixture_savings.items():
        actual = actual_savings[key]
        for field in ("name", "emoji"):
            expected_value = expected.get(field) or "🐷"
            require(actual.get(field) == expected_value, f"savings goal {key} {field} differs")
        same_amount(actual.get("target"), expected["target"], f"savings goal {key} target")
        same_amount(actual.get("saved"), expected["saved"], f"savings goal {key} saved")

    for key, expected in fixture_recurring.items():
        actual = actual_recurring[key]
        for field in ("kind", "category", "account", "toAccount", "book", "note", "period", "totalCount"):
            require(actual.get(field) == expected.get(field), f"recurring rule {key} {field} differs")
        same_amount(actual.get("amount"), expected["amount"], f"recurring rule {key} amount")
        same_date(actual.get("startDate"), expected["startDate"], f"recurring rule {key} startDate")
        if expected.get("endDate") is not None:
            same_date(actual.get("endDate"), expected["endDate"], f"recurring rule {key} endDate")
        else:
            require(actual.get("endDate") is None, f"recurring rule {key} endDate differs")

    for key, expected in fixture_reports.items():
        actual = actual_reports[key]
        for field in ("type", "book", "title", "summary"):
            require(actual.get(field) == expected[field], f"report {key} {field} differs")
        same_date(actual.get("periodStart"), expected["periodStart"], f"report {key} periodStart")
        same_date(actual.get("periodEnd"), expected["periodEnd"], f"report {key} periodEnd")

    expected_values = fixture["expected"]
    summary = payload.get("summary")
    require(isinstance(summary, dict), "business JSON summary is missing")
    for key in ("augustIncome", "augustGrossExpense", "augustRefund", "augustNetExpense", "augustBalance", "budget"):
        same_amount(summary.get(key), expected_values[key], f"summary {key}")
    for key in ("augustTransactionRowsIncludingOffsetAndTransfer", "augustVisibleOrdinaryRows"):
        require(summary.get(key) == expected_values[key], f"summary {key} differs")
    require(summary.get("fixtureExpectedBalance") == expected_values["augustBalance"], "summary fixtureExpectedBalance differs")
    require(payload.get("physicalAssets") == [], "base P0 business export must not include operation-only assets")


def contract_fixture(contract: dict[str, Any]) -> dict[str, Any]:
    fixture_path = Path(contract["_fixturePath"])
    return load_json(fixture_path)


def check(path: Path, contract_path: Path, platform: str) -> int:
    try:
        contract = load_json(contract_path)
        contract["_fixturePath"] = str((contract_path.parent.parent.parent / contract["fixture"]["file"]).resolve())
        payload = load_json(path)
        validate(payload, contract, platform)
    except BusinessJSONError as error:
        print(f"business JSON invalid: {error}", file=sys.stderr)
        return 1
    print(f"business JSON valid: {platform} {path}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--contract", type=Path, default=Path("ios-app/tools/p0_product_contract.json"))
    parser.add_argument("--platform", choices=("android", "ios"), required=True)
    args = parser.parse_args()
    return check(args.input.resolve(), args.contract.resolve(), args.platform)


if __name__ == "__main__":
    raise SystemExit(main())
