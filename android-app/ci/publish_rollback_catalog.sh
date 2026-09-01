#!/usr/bin/env bash
# Publish the historical-build catalog without uploading APK bytes.
#
# Each entry points at an immutable HTTPS archive and contains an
# installVersionCode that is higher than the package currently installed when
# the entry is selected.  Worker-hosted entries are retained by
# publish_update.sh; external R2/GitHub URLs do not consume KV space.
#
# Usage:
#   ./publish_rollback_catalog.sh <rollback.json>

set -euo pipefail

fail() {
  echo "rollback catalog publish failed: $*" >&2
  exit 1
}

[ "$#" -eq 1 ] || fail "usage: $0 <rollback.json>"
CATALOG="$1"
[ -s "$CATALOG" ] || fail "catalog does not exist or is empty: $CATALOG"
command -v node >/dev/null 2>&1 || fail "node is required"
command -v npx >/dev/null 2>&1 || fail "npx is required"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Validate and canonicalize before touching KV.  This deliberately rejects
# HTTP and malformed release IDs: a rollback catalog is a supply-chain input.
CATALOG="$CATALOG" node - <<'NODE' > "$TMP/rollback.json"
const fs = require('node:fs');
const path = process.env.CATALOG;
let parsed;
try {
  parsed = JSON.parse(fs.readFileSync(path, 'utf8').replace(/^\uFEFF/, ''));
} catch (error) {
  throw new Error(`catalog is not valid JSON: ${error.message}`);
}
const entries = Array.isArray(parsed)
  ? parsed
  : (parsed.versions ?? parsed.rollbacks ?? parsed.items ?? null);
if (!Array.isArray(entries)) throw new Error('catalog entries must be an array');
const seenIds = new Set();
const seenInstallCodes = new Set();
const output = [];
for (const [index, raw] of entries.entries()) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new Error(`entry ${index} must be an object`);
  }
  const sourceVersionCode = Number(raw.sourceVersionCode ?? raw.source_version_code ?? raw.versionCode);
  const installVersionCode = Number(raw.installVersionCode ?? raw.install_version_code);
  const versionName = String(raw.versionName ?? raw.version_name ?? '').trim();
  const url = String(raw.url ?? '').trim();
  const releaseId = String(raw.releaseId ?? raw.release_id ?? '').trim();
  if (!Number.isSafeInteger(sourceVersionCode) || sourceVersionCode <= 0) {
    throw new Error(`entry ${index} has invalid sourceVersionCode`);
  }
  if (!Number.isSafeInteger(installVersionCode) || installVersionCode <= 0) {
    throw new Error(`entry ${index} has invalid installVersionCode`);
  }
  if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(versionName)) {
    throw new Error(`entry ${index} has invalid versionName`);
  }
  let parsedUrl;
  try { parsedUrl = new URL(url); } catch (_) {}
  if (
    !parsedUrl ||
    parsedUrl.protocol !== 'https:' ||
    !parsedUrl.hostname ||
    parsedUrl.username ||
    parsedUrl.password
  ) {
    throw new Error(`entry ${index} URL must be HTTPS`);
  }
  if (!/^v\d+-[0-9a-f]{12}$/.test(releaseId)) {
    throw new Error(`entry ${index} has invalid releaseId`);
  }
  if (seenIds.has(releaseId)) throw new Error(`duplicate releaseId: ${releaseId}`);
  if (seenInstallCodes.has(installVersionCode)) {
    throw new Error(`duplicate installVersionCode: ${installVersionCode}`);
  }
  if (installVersionCode <= sourceVersionCode) {
    throw new Error(
      `entry ${index} installVersionCode must be greater than sourceVersionCode`,
    );
  }
  const sha256 = String(raw.sha256 ?? '').trim().toLowerCase();
  if (sha256 && !/^[0-9a-f]{64}$/.test(sha256)) {
    throw new Error(`entry ${index} has invalid sha256`);
  }
  seenIds.add(releaseId);
  seenInstallCodes.add(installVersionCode);
  output.push({
    versionName,
    sourceVersionCode,
    installVersionCode,
    url,
    notes: String(raw.notes ?? ''),
    sizeBytes:
      Number.isSafeInteger(Number(raw.sizeBytes)) && Number(raw.sizeBytes) >= 0
        ? Number(raw.sizeBytes)
        : 0,
    ...(sha256 ? { sha256 } : {}),
    releaseId,
    ...(raw.databaseVersion != null ? { databaseVersion: Number(raw.databaseVersion) } : {}),
  });
}
process.stdout.write(JSON.stringify({ versions: output }, null, 2));
NODE

NSID="${FEIMIAO_KV_NAMESPACE_ID:-34c07e0793ea4fb8a526dd28eb1aa1b0}"
WRANGLER=(npx --yes --registry=https://registry.npmmirror.com wrangler)
# An entry is useful only when its package can replace the currently installed
# release.  Reject stale catalogs before writing rollback.json.
NO_COLOR=1 "${WRANGLER[@]}" kv key get \
  --namespace-id="$NSID" --remote version.json > "$TMP/current-version.json" 2>/dev/null \
  || fail "version.json is unavailable; publish the normal release first"
CURRENT_VERSION_FILE="$TMP/current-version.json" CATALOG_FILE="$TMP/rollback.json" node - <<'NODE'
const fs = require('node:fs');
const current = JSON.parse(fs.readFileSync(process.env.CURRENT_VERSION_FILE, 'utf8'));
const currentCode = Number(current?.versionCode);
if (!Number.isSafeInteger(currentCode) || currentCode <= 0) {
  throw new Error('version.json has no positive versionCode');
}
const catalog = JSON.parse(fs.readFileSync(process.env.CATALOG_FILE, 'utf8'));
const entries = catalog.versions ?? [];
for (const [index, entry] of entries.entries()) {
  const installCode = Number(entry.installVersionCode);
  if (installCode <= currentCode) {
    throw new Error(
      `entry ${index} installVersionCode ${installCode} must be greater than current ${currentCode}`,
    );
  }
}
NODE
NO_COLOR=1 "${WRANGLER[@]}" kv key put \
  --namespace-id="$NSID" --remote rollback.json --path "$TMP/rollback.json"
echo "published rollback catalog: ${CATALOG}"
echo "catalog is metadata only; APK bytes remain at each immutable HTTPS URL"
