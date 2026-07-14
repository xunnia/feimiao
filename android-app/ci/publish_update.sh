#!/usr/bin/env bash
# Publish an in-app update to the Cloudflare KV backed update worker.
#
# Usage:
#   ./publish_update.sh <apk-path> <versionName> <versionCode> "<release notes>"
#
# Safety rules:
# - APK chunks are written under a versioned release id: apk:<releaseId>:<index>.
# - version.json is updated only after every chunk and manifest has uploaded.
# - version.json is generated with Node JSON.stringify so notes can contain quotes
#   and newlines safely.

set -euo pipefail

APK="${1:?apk path required}"
VNAME="${2:?versionName required}"
VCODE="${3:?versionCode required}"
NOTES="${4:-修复问题并改进体验。}"

SIZE=$(stat -c%s "$APK" 2>/dev/null || stat -f%z "$APK")
# 用 stdin 喂 sha256sum：直接传 Windows 路径时文件名含反斜杠，
# GNU coreutils 会在哈希前加 "\" 转义标志，污染 releaseId 和 sha256 字段。
SHA256=$(
  sha256sum < "$APK" 2>/dev/null | awk '{print $1}' ||
  shasum -a 256 < "$APK" | awk '{print $1}'
)
RELEASE_ID="v${VCODE}-${SHA256:0:12}"

NSID="34c07e0793ea4fb8a526dd28eb1aa1b0"
WRANGLER="npx --yes --registry=https://registry.npmmirror.com wrangler"
KV="$WRANGLER kv key put --namespace-id=$NSID --remote"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

split -b 24m -d -a 2 "$APK" "$TMP/chunk-"
CHUNKS=$(ls "$TMP"/chunk-* | wc -l)
echo "APK $((SIZE / 1024 / 1024)) MB -> $CHUNKS chunks, release=$RELEASE_ID"

i=0
for f in "$TMP"/chunk-*; do
  echo "  upload chunk $i/$CHUNKS"
  $KV "apk:$RELEASE_ID:$i" --path "$f"
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
$KV "apk:$RELEASE_ID:manifest" --path "$TMP/manifest.json"

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
$KV "version.json" --path "$TMP/version.json"

echo "published v$VNAME ($VCODE), sha256=$SHA256"
echo "https://updates.xunni9481.dpdns.org/version.json"
