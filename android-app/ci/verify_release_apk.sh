#!/usr/bin/env bash
# Verify that an APK is the exact Feimiao release identity expected by users.
#
# Usage:
#   ./verify_release_apk.sh <apk-path> [versionName versionCode]
#
# With no version arguments, expected values come from ../pubspec.yaml.

set -euo pipefail

readonly EXPECTED_PACKAGE="com.qingji.qingji.codex"
readonly EXPECTED_CERT_DN="CN=Feimiao Codex Test, OU=Codex, O=Feimiao, L=Shanghai, ST=Shanghai, C=CN"
readonly EXPECTED_CERT_SHA256="4E99C399D4D246BD9C6B08B1D641248BD0846E7AE650C3A766E30FA67483D507"

fail() {
  echo "release verification failed: $*" >&2
  exit 1
}

to_posix_path() {
  local value="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$value" 2>/dev/null || printf '%s\n' "$value"
  else
    printf '%s\n' "$value"
  fi
}

discover_build_tool() {
  local command_name="$1"
  local windows_name="$2"
  local override="$3"

  if [ -n "$override" ]; then
    override="$(to_posix_path "$override")"
    [ -f "$override" ] || fail "$command_name override does not exist: $override"
    printf '%s\n' "$override"
    return
  fi

  if command -v "$command_name" >/dev/null 2>&1; then
    command -v "$command_name"
    return
  fi

  local roots=()
  [ -n "${ANDROID_SDK_ROOT:-}" ] && roots+=("$ANDROID_SDK_ROOT")
  [ -n "${ANDROID_HOME:-}" ] && roots+=("$ANDROID_HOME")
  [ -n "${LOCALAPPDATA:-}" ] && roots+=("$LOCALAPPDATA/Android/Sdk")
  roots+=("$HOME/AppData/Local/Android/Sdk")

  local candidates=()
  local root candidate
  shopt -s nullglob
  for root in "${roots[@]}"; do
    root="$(to_posix_path "$root")"
    for candidate in \
      "$root"/build-tools/*/"$command_name" \
      "$root"/build-tools/*/"$windows_name"; do
      [ -f "$candidate" ] && candidates+=("$candidate")
    done
  done
  shopt -u nullglob

  [ "${#candidates[@]}" -gt 0 ] || \
    fail "$command_name was not found; install Android SDK Build-Tools or set ${command_name^^}_BIN"
  printf '%s\n' "${candidates[@]}" | sort -V | tail -n 1
}

[ "$#" -eq 1 ] || [ "$#" -eq 3 ] || \
  fail "usage: $0 <apk-path> [versionName versionCode]"

APK="$1"
if [ ! -f "$APK" ]; then
  APK="$(to_posix_path "$APK")"
fi
[ -s "$APK" ] || fail "APK does not exist or is empty: $APK"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

if [ "$#" -eq 3 ]; then
  EXPECTED_VERSION_NAME="$2"
  EXPECTED_VERSION_CODE="$3"
else
  PUBSPEC_VERSION="$({ awk '/^version:[[:space:]]*/ { print $2; exit }' "$APP_DIR/pubspec.yaml"; } 2>/dev/null)"
  if [[ ! "$PUBSPEC_VERSION" =~ ^([^+[:space:]]+)\+([0-9]+)$ ]]; then
    fail "cannot parse version from $APP_DIR/pubspec.yaml"
  fi
  EXPECTED_VERSION_NAME="${BASH_REMATCH[1]}"
  EXPECTED_VERSION_CODE="${BASH_REMATCH[2]}"
fi

[[ "$EXPECTED_VERSION_CODE" =~ ^[0-9]+$ ]] || fail "versionCode must be an integer"

AAPT_BIN="$(discover_build_tool aapt aapt.exe "${AAPT_BIN:-}")"
APKSIGNER_BIN="$(discover_build_tool apksigner apksigner.bat "${APKSIGNER_BIN:-}")"
ZIPALIGN_BIN="$(discover_build_tool zipalign zipalign.exe "${ZIPALIGN_BIN:-}")"

if ! BADGING="$("$AAPT_BIN" dump badging "$APK" 2>&1)"; then
  fail "aapt could not inspect APK: $BADGING"
fi
BADGING="$(printf '%s' "$BADGING" | tr -d '\r')"
PACKAGE_LINE="$(printf '%s\n' "$BADGING" | sed -n '/^package:/p')"
[ -n "$PACKAGE_LINE" ] || fail "aapt output has no package record"

ACTUAL_PACKAGE="$(printf '%s\n' "$PACKAGE_LINE" | sed -nE "s/^package: name='([^']+)'.*/\1/p")"
ACTUAL_VERSION_CODE="$(printf '%s\n' "$PACKAGE_LINE" | sed -nE "s/.* versionCode='([^']+)'.*/\1/p")"
ACTUAL_VERSION_NAME="$(printf '%s\n' "$PACKAGE_LINE" | sed -nE "s/.* versionName='([^']+)'.*/\1/p")"

[ "$ACTUAL_PACKAGE" = "$EXPECTED_PACKAGE" ] || \
  fail "package is $ACTUAL_PACKAGE, expected $EXPECTED_PACKAGE"
[ "$ACTUAL_VERSION_NAME" = "$EXPECTED_VERSION_NAME" ] || \
  fail "versionName is $ACTUAL_VERSION_NAME, expected $EXPECTED_VERSION_NAME"
[ "$ACTUAL_VERSION_CODE" = "$EXPECTED_VERSION_CODE" ] || \
  fail "versionCode is $ACTUAL_VERSION_CODE, expected $EXPECTED_VERSION_CODE"

if ! ALIGN_OUTPUT="$("$ZIPALIGN_BIN" -c -P 16 -v 4 "$APK" 2>&1)"; then
  fail "APK is not 16 KiB page-aligned: $ALIGN_OUTPUT"
fi

if ! CERT_OUTPUT="$("$APKSIGNER_BIN" verify --verbose --print-certs "$APK" 2>&1)"; then
  fail "apksigner rejected APK: $CERT_OUTPUT"
fi
CERT_OUTPUT="$(printf '%s' "$CERT_OUTPUT" | tr -d '\r')"
mapfile -t CERT_DNS < <(printf '%s\n' "$CERT_OUTPUT" | sed -nE 's/^.*certificate DN:[[:space:]]*//p')
mapfile -t CERT_DIGESTS < <(printf '%s\n' "$CERT_OUTPUT" | sed -nE 's/^.*certificate SHA-256 digest:[[:space:]]*//p')
V2_STATUS="$(printf '%s\n' "$CERT_OUTPUT" | sed -nE 's/^Verified using v2 scheme.*:[[:space:]]*(true|false)$/\1/p' | tail -n 1)"

[ "${#CERT_DNS[@]}" -eq 1 ] || fail "expected exactly one signing certificate DN"
[ "${#CERT_DIGESTS[@]}" -eq 1 ] || fail "expected exactly one signing certificate SHA-256 digest"
[ "$V2_STATUS" = "true" ] || fail "APK Signature Scheme v2 is not verified"

ACTUAL_CERT_SHA256="$(printf '%s' "${CERT_DIGESTS[0]}" | tr -d '[:space:]:' | tr '[:lower:]' '[:upper:]')"
[ "${CERT_DNS[0]}" = "$EXPECTED_CERT_DN" ] || \
  fail "certificate DN is ${CERT_DNS[0]}, expected $EXPECTED_CERT_DN"
[ "$ACTUAL_CERT_SHA256" = "$EXPECTED_CERT_SHA256" ] || \
  fail "certificate SHA-256 is $ACTUAL_CERT_SHA256, expected $EXPECTED_CERT_SHA256"

printf 'verified package=%s versionName=%s versionCode=%s alignment=16KiB signature=v2 certSHA256=%s\n' \
  "$ACTUAL_PACKAGE" "$ACTUAL_VERSION_NAME" "$ACTUAL_VERSION_CODE" "$ACTUAL_CERT_SHA256"
