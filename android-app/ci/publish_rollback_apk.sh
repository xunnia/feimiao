#!/usr/bin/env bash
# Publish one rollback-compatible APK without changing version.json.
#
# Usage:
#   ./publish_rollback_apk.sh <apk-path> <source-version-code> \
#     <install-version-code> <version-name> [release notes]
#
# The APK must already be signed with the Feimiao release certificate and its
# Android manifest must contain install-version-code.  The script uploads the
# immutable chunks first, then publishes a one-entry rollback catalog.  It is
# intentionally separate from publish_update.sh so a historical package can
# never become the active update by accident.

set -euo pipefail

fail() {
  echo "rollback APK publish failed: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command is missing: $1"
}

[ "$#" -ge 4 ] && [ "$#" -le 5 ] || \
  fail "usage: $0 <apk-path> <source-version-code> <install-version-code> <version-name> [release notes]"

APK="$1"
SOURCE_CODE="$2"
INSTALL_CODE="$3"
VNAME="$4"
NOTES="${5:-可回退的上一版本。账本数据会保留，请先导出备份。}"
[[ "$SOURCE_CODE" =~ ^[0-9]+$ ]] || fail "source versionCode must be an integer"
[[ "$INSTALL_CODE" =~ ^[0-9]+$ ]] || fail "install versionCode must be an integer"
(( INSTALL_CODE > SOURCE_CODE )) || \
  fail "install versionCode must be greater than source versionCode"

for command_name in awk curl mktemp node npx split stat sleep; do
  require_command "$command_name"
done
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  fail "sha256sum or shasum is required"
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/verify_release_apk.sh" "$APK" "$VNAME" "$INSTALL_CODE"

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
RELEASE_ID="v${INSTALL_CODE}-${SHA256:0:12}"

VERSION_URL="${FEIMIAO_VERSION_URL:-https://updates.xunni9481.dpdns.org/version.json}"
curl --fail --silent --show-error --location --max-time 30 \
  "$VERSION_URL" -o "$TMP/current-version.json"
CURRENT_CODE="$(CURRENT_VERSION_FILE="$TMP/current-version.json" node - <<'NODE'
const fs = require('node:fs');
const value = JSON.parse(fs.readFileSync(process.env.CURRENT_VERSION_FILE, 'utf8'));
const code = Number(value?.versionCode);
if (!Number.isSafeInteger(code) || code <= 0) {
  throw new Error('version.json has no positive versionCode');
}
process.stdout.write(String(code));
NODE
)"
(( INSTALL_CODE > CURRENT_CODE )) || \
  fail "install versionCode $INSTALL_CODE must be greater than current $CURRENT_CODE"

NSID="${FEIMIAO_KV_NAMESPACE_ID:-34c07e0793ea4fb8a526dd28eb1aa1b0}"
WRANGLER=(npx --yes --registry=https://registry.npmmirror.com wrangler)

# A catalog replacement must never reuse an install sequence that is still
# present in the old catalog.  Otherwise both packages can be uploaded before
# the fail-closed retention check notices the unreferenced higher release.
ROLLBACK_URL="${FEIMIAO_ROLLBACK_URL:-https://updates.xunni9481.dpdns.org/rollback.json}"
ROLLBACK_STATUS="$(curl --silent --show-error --location --max-time 30 \
  -o "$TMP/current-rollback.json" -w '%{http_code}' "$ROLLBACK_URL" || true)"
case "$ROLLBACK_STATUS" in
  200)
    CANDIDATE_INSTALL_CODE="$INSTALL_CODE" CANDIDATE_RELEASE_ID="$RELEASE_ID" \
      ROLLBACK_CATALOG_FILE="$TMP/current-rollback.json" node - <<'NODE'
const fs = require('node:fs');
const parsed = JSON.parse(fs.readFileSync(process.env.ROLLBACK_CATALOG_FILE, 'utf8'));
const entries = Array.isArray(parsed)
  ? parsed
  : (parsed.versions ?? parsed.rollbacks ?? parsed.items ?? null);
if (!Array.isArray(entries)) throw new Error('rollback catalog entries must be an array');
for (const [index, entry] of entries.entries()) {
  const installCode = Number(entry?.installVersionCode ?? entry?.install_version_code);
  const releaseId = String(entry?.releaseId ?? entry?.release_id ?? '').trim();
  if (installCode === Number(process.env.CANDIDATE_INSTALL_CODE)) {
    throw new Error(
      `installVersionCode ${installCode} already exists in rollback catalog at entry ${index}; ` +
        'allocate a new sequence before publishing',
    );
  }
  if (releaseId === process.env.CANDIDATE_RELEASE_ID) {
    throw new Error(`releaseId ${releaseId} already exists in rollback catalog`);
  }
}
NODE
    ;;
  404)
    echo "no rollback catalog published yet"
    ;;
  *)
    fail "could not read rollback catalog before upload (HTTP $ROLLBACK_STATUS)"
    ;;
esac

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

split -b 24m -d -a 2 "$APK" "$TMP/chunk-"
CHUNK_FILES=("$TMP"/chunk-*)
CHUNKS="${#CHUNK_FILES[@]}"
[ "$CHUNKS" -gt 0 ] || fail "APK split produced no chunks"
echo "APK $((SIZE / 1024 / 1024)) MB -> $CHUNKS chunks, release=$RELEASE_ID"

i=0
for file in "${CHUNK_FILES[@]}"; do
  echo "upload rollback chunk $((i + 1))/$CHUNKS"
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

# A rollback APK is the hot previous release.  Replacing the catalog keeps
# the KV namespace bounded to the active release plus this one compatibility
# package.  Older builds can still be listed separately when hosted outside KV.
VNAME="$VNAME" SOURCE_CODE="$SOURCE_CODE" INSTALL_CODE="$INSTALL_CODE" \
  NOTES="$NOTES" SIZE="$SIZE" SHA256="$SHA256" RELEASE_ID="$RELEASE_ID" \
  node - <<'NODE' > "$TMP/rollback.json"
const entry = {
  versionName: process.env.VNAME,
  sourceVersionCode: Number(process.env.SOURCE_CODE),
  installVersionCode: Number(process.env.INSTALL_CODE),
  url: `https://updates.xunni9481.dpdns.org/feimiao-latest.apk?release=${encodeURIComponent(process.env.RELEASE_ID)}`,
  notes: process.env.NOTES || '可回退的上一版本。',
  sizeBytes: Number(process.env.SIZE),
  sha256: process.env.SHA256,
  releaseId: process.env.RELEASE_ID,
};
process.stdout.write(JSON.stringify({ versions: [entry] }, null, 2));
NODE

NO_COLOR=1 "${WRANGLER[@]}" kv key put \
  --namespace-id="$NSID" --remote rollback.json --path "$TMP/rollback.json"

echo "published rollback source v$VNAME (source=$SOURCE_CODE, install=$INSTALL_CODE)"
echo "release=$RELEASE_ID sha256=$SHA256"
echo "rollback catalog: ${VERSION_URL%/version.json}/rollback.json"
