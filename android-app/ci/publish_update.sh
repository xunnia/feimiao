#!/usr/bin/env bash
# Publish an in-app update to the Cloudflare KV backed update worker.
#
# Usage:
#   ./publish_update.sh <apk-path> <versionName> <versionCode> "<release notes>"
#
# The script verifies package/version/signing identity and evaluates the full
# online release identity before uploading a single byte. version.json switches last.

set -euo pipefail

fail() {
  echo "publish failed: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command is missing: $1"
}

[ "$#" -ge 3 ] && [ "$#" -le 4 ] || \
  fail "usage: $0 <apk-path> <versionName> <versionCode> [release notes]"

APK="$1"
VNAME="$2"
VCODE="$3"
NOTES="${4:-修复问题并改进体验。}"
[[ "$VCODE" =~ ^[0-9]+$ ]] || fail "versionCode must be an integer"

for command_name in awk curl mktemp node npx split stat; do
  require_command "$command_name"
done
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  fail "sha256sum or shasum is required"
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/verify_release_apk.sh" "$APK" "$VNAME" "$VCODE"

if [ ! -f "$APK" ] && command -v cygpath >/dev/null 2>&1; then
  APK="$(cygpath -u "$APK")"
fi
[ -s "$APK" ] || fail "APK does not exist or is empty: $APK"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SIZE=$(stat -c%s "$APK" 2>/dev/null || stat -f%z "$APK")
SHA256=$(
  sha256sum < "$APK" 2>/dev/null | awk '{print $1}' ||
  shasum -a 256 < "$APK" | awk '{print $1}'
)
[[ "$SHA256" =~ ^[0-9a-fA-F]{64}$ ]] || fail "could not calculate a clean APK SHA-256"
SHA256="$(printf '%s' "$SHA256" | tr '[:upper:]' '[:lower:]')"
RELEASE_ID="v${VCODE}-${SHA256:0:12}"

VNAME="$VNAME" VCODE="$VCODE" SHA256="$SHA256" RELEASE_ID="$RELEASE_ID" \
  node - <<'NODE' > "$TMP/candidate.json"
const candidate = {
  versionName: process.env.VNAME,
  versionCode: Number(process.env.VCODE),
  sha256: process.env.SHA256,
  releaseId: process.env.RELEASE_ID,
};
process.stdout.write(JSON.stringify(candidate, null, 2));
NODE

VERSION_URL="${FEIMIAO_VERSION_URL:-https://updates.xunni9481.dpdns.org/version.json}"
echo "checking online version: $VERSION_URL"
curl --fail --silent --show-error --location --max-time 30 \
  "$VERSION_URL" -o "$TMP/online-version.json"

NSID="34c07e0793ea4fb8a526dd28eb1aa1b0"
WRANGLER=(npx --yes --registry=https://registry.npmmirror.com wrangler)
kv_put() {
  local attempt
  for attempt in 1 2 3 4 5; do
    if NO_COLOR=1 "${WRANGLER[@]}" kv key put --namespace-id="$NSID" --remote "$@"; then
      return 0
    fi
    echo "KV upload failed (attempt $attempt/5); retrying..." >&2
    sleep 3
  done
  fail "KV upload failed after 5 attempts: $1"
}

kv_delete() {
  local key="$1"
  local attempt
  for attempt in 1 2 3 4 5; do
    if NO_COLOR=1 "${WRANGLER[@]}" kv key delete --namespace-id="$NSID" --remote "$key"; then
      return 0
    fi
    echo "KV delete failed for $key (attempt $attempt/5); retrying..." >&2
    sleep 3
  done
  fail "KV delete failed after 5 attempts: $key"
}

# Keep the active release and one complete previous release. This runs after
# the version pointer has been switched, and also on an idempotent rerun, so a
# transient cleanup failure can be repaired without re-uploading the APK.
retain_recent_releases() {
  echo "checking retention policy: keep current and previous release"
  # Read the pointer directly from KV rather than the public Worker URL. A
  # CDN edge may briefly serve an older no-cache response while another
  # publisher is advancing production; deleting against that stale view could
  # remove the concurrently published release.
  NO_COLOR=1 "${WRANGLER[@]}" kv key get \
    --namespace-id="$NSID" --remote version.json > "$TMP/online-version-retention.json"
  node "$SCRIPT_DIR/release_gate.mjs" \
    --candidate "$TMP/candidate.json" \
    --current "$TMP/online-version-retention.json" \
    --candidate-apk "$APK" >/dev/null

  NO_COLOR=1 "${WRANGLER[@]}" kv key list \
    --namespace-id="$NSID" --remote > "$TMP/retention-keys.json"
  node "$SCRIPT_DIR/retention_policy.mjs" \
    --keys "$TMP/retention-keys.json" \
    --current-release "$RELEASE_ID" \
    --keep 2 > "$TMP/retention-plan.json"

  RETENTION_PLAN_FILE="$TMP/retention-plan.json" node - <<'NODE'
const fs = require('node:fs');
const plan = JSON.parse(fs.readFileSync(process.env.RETENTION_PLAN_FILE, 'utf8'));
console.log(`retention keep releases=${plan.keepReleaseIds.join(',')} delete keys=${plan.deleteKeys.length}`);
NODE

  RETENTION_PLAN_FILE="$TMP/retention-plan.json" node - <<'NODE' > "$TMP/retention-delete.txt"
const fs = require('node:fs');
const plan = JSON.parse(fs.readFileSync(process.env.RETENTION_PLAN_FILE, 'utf8'));
for (const key of plan.deleteKeys) console.log(key);
NODE
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    kv_delete "$key"
  done < "$TMP/retention-delete.txt"

  NO_COLOR=1 "${WRANGLER[@]}" kv key list \
    --namespace-id="$NSID" --remote > "$TMP/retention-keys-final.json"
  node "$SCRIPT_DIR/retention_policy.mjs" \
    --keys "$TMP/retention-keys-final.json" \
    --current-release "$RELEASE_ID" \
    --keep 2 \
    --assert-clean > "$TMP/retention-final.json"
  RETENTION_FINAL_FILE="$TMP/retention-final.json" node - <<'NODE'
const fs = require('node:fs');
const plan = JSON.parse(fs.readFileSync(process.env.RETENTION_FINAL_FILE, 'utf8'));
console.log(`retention verified: ${plan.keepReleaseIds.length} release(s), ${plan.keepKeys.length} key(s)`);
NODE
}

GATE_DECISION="$(node "$SCRIPT_DIR/release_gate.mjs" \
  --candidate "$TMP/candidate.json" \
  --current "$TMP/online-version.json" \
  --candidate-apk "$APK")"
case "$GATE_DECISION" in
  advance)
    echo "release gate verified: candidate advances the online release"
    ;;
  idempotent)
    echo "release already published with the same identity; repairing retention without upload"
    retain_recent_releases
    exit 0
    ;;
  *)
    fail "unexpected release gate decision: $GATE_DECISION"
    ;;
esac

split -b 24m -d -a 2 "$APK" "$TMP/chunk-"
CHUNK_FILES=("$TMP"/chunk-*)
CHUNKS="${#CHUNK_FILES[@]}"
[ "$CHUNKS" -gt 0 ] || fail "APK split produced no chunks"
echo "APK $((SIZE / 1024 / 1024)) MB -> $CHUNKS chunks, release=$RELEASE_ID"

i=0
for file in "${CHUNK_FILES[@]}"; do
  echo "upload chunk $((i + 1))/$CHUNKS"
  kv_put "apk:$RELEASE_ID:$i" --path "$file"
  i=$((i + 1))
done

RELEASE_ID="$RELEASE_ID" CHUNKS="$CHUNKS" SIZE="$SIZE" SHA256="$SHA256" node - <<'NODE' > "$TMP/manifest.json"
const manifest = {
  releaseId: process.env.RELEASE_ID,
  chunks: Number(process.env.CHUNKS),
  size: Number(process.env.SIZE),
  sha256: process.env.SHA256,
};
process.stdout.write(JSON.stringify(manifest, null, 2));
NODE
kv_put "apk:$RELEASE_ID:manifest" --path "$TMP/manifest.json"

VNAME="$VNAME" VCODE="$VCODE" NOTES="$NOTES" SIZE="$SIZE" SHA256="$SHA256" RELEASE_ID="$RELEASE_ID" node - <<'NODE' > "$TMP/version.json"
const releaseId = process.env.RELEASE_ID;
const version = {
  versionName: process.env.VNAME,
  versionCode: Number(process.env.VCODE),
  url: `https://updates.xunni9481.dpdns.org/feimiao-latest.apk?release=${encodeURIComponent(releaseId)}`,
  notes: process.env.NOTES || '修复问题并改进体验。',
  sizeBytes: Number(process.env.SIZE),
  sha256: process.env.SHA256,
  releaseId,
};
process.stdout.write(JSON.stringify(version, null, 2));
NODE

# Re-check immediately before the pointer switch. Another publisher may have
# advanced production while this process was uploading chunks; never overwrite
# that newer identity with an older candidate.
curl --fail --silent --show-error --location --max-time 30 \
  "$VERSION_URL" -o "$TMP/online-version-final.json"
FINAL_GATE_DECISION="$(node "$SCRIPT_DIR/release_gate.mjs" \
  --candidate "$TMP/candidate.json" \
  --current "$TMP/online-version-final.json" \
  --candidate-apk "$APK")"
case "$FINAL_GATE_DECISION" in
  advance)
    echo "final release gate verified: production still allows this candidate"
    ;;
  idempotent)
    echo "the same release identity became current during upload; pointer is already correct"
    retain_recent_releases
    exit 0
    ;;
  *)
    fail "unexpected final release gate decision: $FINAL_GATE_DECISION"
    ;;
esac

# Atomic pointer switch: this is the first operation that makes the new build
# visible to clients.
kv_put "version.json" --path "$TMP/version.json"

retain_recent_releases

echo "published v$VNAME ($VCODE), sha256=$SHA256"
echo "$VERSION_URL"
