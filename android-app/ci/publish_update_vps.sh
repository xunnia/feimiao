#!/usr/bin/env bash
set -euo pipefail
[[ $# -ge 3 && $# -le 4 ]] || { echo 'Usage: publish_update.sh APK versionName versionCode [notes]' >&2; exit 1; }
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APK="$1"; VNAME="$2"; VCODE="$3"; NOTES="${4:-修复问题并改进体验。}"
[[ "$VCODE" =~ ^[1-9][0-9]*$ ]] || exit 1
bash "$SCRIPT_DIR/verify_release_apk.sh" "$APK" "$VNAME" "$VCODE"
if command -v cygpath >/dev/null 2>&1; then APK="$(cygpath -u "$APK")"; fi
HOST="${FEIMIAO_SSH_HOST:-root@104.168.2.245}"
if [[ -n "${FEIMIAO_SSH_KEY:-}" ]]; then KEY="$FEIMIAO_SSH_KEY";
elif command -v cygpath >/dev/null 2>&1; then KEY="$(cygpath -u "$USERPROFILE")/.ssh/dedirock_ed25519";
else echo 'Set FEIMIAO_SSH_KEY to a deployment SSH key' >&2; exit 1; fi
KNOWN_HOSTS="${FEIMIAO_KNOWN_HOSTS:-${KEY%/*}/known_hosts}"
OPTS=(-i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$KNOWN_HOSTS")
TMP="$(mktemp -d)"
trap 'rm -f "$TMP/version.json" "$TMP/current.json"; rmdir "$TMP"' EXIT
APK_NODE="$APK"
if command -v cygpath >/dev/null 2>&1; then APK_NODE="$(cygpath -m "$APK")"; fi
export APK_NODE VNAME VCODE NOTES
node --input-type=module - <<'JS' > "$TMP/version.json"
import fs from 'node:fs'; import crypto from 'node:crypto';
const apk=fs.readFileSync(process.env.APK_NODE), sha=crypto.createHash('sha256').update(apk).digest('hex');
const code=Number(process.env.VCODE), rid=`v${code}-${sha.slice(0,12)}`;
console.log(JSON.stringify({versionName:process.env.VNAME,versionCode:code,sha256:sha,releaseId:rid,sizeBytes:apk.length,notes:process.env.NOTES,url:`https://updates.xunni.dpdns.org/feimiao-latest.apk?release=${rid}`}));
JS
curl -fLsS --max-time 30 https://updates.xunni.dpdns.org/version.json -o "$TMP/current.json"
node "$SCRIPT_DIR/release_gate.mjs" --candidate "$TMP/version.json" --current "$TMP/current.json" --candidate-apk "$APK"
RID="$(node -p "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).releaseId" "$TMP/version.json")"
[[ "$RID" =~ ^v[0-9]+-[0-9a-f]{12}$ ]] || exit 1
ssh "${OPTS[@]}" "$HOST" "umask 077; mkdir -p /srv/feimiao-updates/incoming/$RID"
scp "${OPTS[@]}" "$APK" "$HOST:/srv/feimiao-updates/incoming/$RID/app.apk"
scp "${OPTS[@]}" "$TMP/version.json" "$HOST:/srv/feimiao-updates/incoming/$RID/version.json"
ssh "${OPTS[@]}" "$HOST" "python3 /srv/feimiao-updates/bin/finalize.py $RID"
curl -fLsS --max-time 30 https://updates.xunni.dpdns.org/version.json -o "$TMP/current.json"
node "$SCRIPT_DIR/release_gate.mjs" --candidate "$TMP/version.json" --current "$TMP/current.json" --candidate-apk "$APK"
