#!/usr/bin/env bash

set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
android_root="$(cd "$script_dir/.." && pwd)"
repo_root="$(cd "$android_root/.." && pwd)"
fixture_path="$repo_root/ios-app/tools/fixtures/p0-demo-ledger-2026-08-v1.json"
contract_path="$repo_root/ios-app/tools/p0_product_contract.json"
parity_output="$android_root/outputs/parity"
log_path="${GITHUB_WORKSPACE:-$repo_root}/android-parity-drive.log"

# The emulator runner currently supplies android-app as the working directory,
# but resolving paths from this script keeps the capture reproducible when it
# is invoked from the repository root or another shell.
cd "$android_root"

device_id="${ANDROID_SERIAL:-${ANDROID_DEVICE_ID:-}}"
app_id="com.qingji.qingji.codex"
scene_timeout_seconds="${PARITY_SCENE_TIMEOUT_SECONDS:-900}"
if [ -z "$device_id" ]; then
  mapfile -t online_devices < <(adb devices | awk '$2 == "device" { print $1 }')
  if [ "${#online_devices[@]}" -ne 1 ]; then
    echo "Expected exactly one online Android device; found ${#online_devices[@]}" >&2
    adb devices >&2
    exit 2
  fi
  device_id="${online_devices[0]}"
fi
if ! adb -s "$device_id" get-state >/dev/null 2>&1; then
  echo "Android device is not online: $device_id" >&2
  adb devices >&2
  exit 2
fi
if ! [[ "$scene_timeout_seconds" =~ ^[0-9]+$ ]] || [ "$scene_timeout_seconds" -le 0 ]; then
  echo "PARITY_SCENE_TIMEOUT_SECONDS must be a positive integer; got: $scene_timeout_seconds" >&2
  exit 2
fi
timeout_bin="$(command -v timeout || true)"
if [ -z "$timeout_bin" ]; then
  echo "GNU timeout is required to bound each parity scene" >&2
  exit 2
fi

{
  echo "PARITY_DRIVER_BEGIN"
  echo "PWD=$PWD"
  echo "ANDROID_DEVICE_ID=$device_id"
  echo "ANDROID_APP_ID=$app_id"
  echo "PARITY_SCENE_TIMEOUT_SECONDS=$scene_timeout_seconds"
  echo "FLUTTER_BIN=$(command -v flutter || true)"
  echo "ADB_BIN=$(command -v adb || true)"
  echo "TIMEOUT_BIN=$timeout_bin"
  flutter --version
  adb -s "$device_id" get-state
  # The canonical fixture lives under ios-app so there is only one source of
  # truth. Stage the same file into Flutter's package asset tree for the
  # integration test; it is generated in CI and never becomes production data.
  mkdir -p assets/parity
  cp "$fixture_path" \
    assets/parity/p0-demo-ledger-2026-08-v1.json
  fixture_hash="$(sha256sum "$fixture_path" | awk '{print toupper($1)}')"
  echo "P0_FIXTURE_HASH=$fixture_hash"
  # Keep Calendar/DateTime local-day calculations aligned with the iOS
  # simulator. The logical capture date itself is injected at compile time.
  adb -s "$device_id" shell settings put global auto_time_zone 0 || true
  adb -s "$device_id" shell settings put global time_zone Asia/Shanghai || true
  # The integration test already groups all 41 canonical scenes into five
  # complete batches. Keeping one driver session per batch avoids repeatedly
  # installing and tearing down the Flutter VM, which makes long emulator
  # runs prone to adb/device-offline failures while preserving clean data
  # between batches.
  groups=(
    core
    planning
    management
    ai
    system
  )
  # Remove a package left by a previous local/emulator run before the first
  # Flutter install. pm clear cannot repair a signing mismatch.
  adb -s "$device_id" uninstall "$app_id" >/dev/null 2>&1 || true
  for group in "${groups[@]}"; do
    echo "PARITY_GROUP_BEGIN group=$group"
    # Each batch gets a fresh application database, while the driver keeps all
    # screenshots in the same host output directory.
    adb -s "$device_id" shell am force-stop "$app_id" >/dev/null 2>&1 || true
    adb -s "$device_id" shell pm clear "$app_id" >/dev/null 2>&1 || true
    echo "PARITY_GROUP_RESET group=$group"
    "$timeout_bin" --foreground --kill-after=30s "${scene_timeout_seconds}s" flutter drive \
      --driver=test_driver/integration_test.dart \
      --target=integration_test/parity_screenshots_test.dart \
      --device-id "$device_id" \
      --no-pub \
      --dart-define=QINGJI_PARITY_CAPTURE=true \
      --dart-define=QINGJI_PARITY_GROUP="$group" \
      --dart-define=QINGJI_DEMO_NOW=2026-08-27T12:00:00+08:00 \
      --dart-define=QINGJI_P0_FIXTURE_HASH="$fixture_hash"
    group_status=$?
    echo "PARITY_GROUP_END group=$group status=$group_status"
    if [ "$group_status" -eq 124 ] || [ "$group_status" -eq 137 ]; then
      echo "::error::Parity group timed out or was killed: $group"
      adb -s "$device_id" shell dumpsys activity activities 2>&1 | tail -n 120 || true
      adb -s "$device_id" logcat -d -t 300 2>&1 | tail -n 300 || true
    fi
    if [ "$group_status" -ne 0 ]; then
      echo "::error title=Android parity group failed::group=$group status=$group_status"
      echo "PARITY_FAILURE group=$group status=$group_status"
      adb -s "$device_id" get-state 2>&1 || true
      adb devices -l 2>&1 || true
      exit "$group_status"
    fi
    if ! adb -s "$device_id" get-state >/dev/null 2>&1; then
      echo "::error::Android emulator went offline after parity group: $group"
      adb devices >&2 || true
      exit 2
    fi
  done
} 2>&1 | tee "$log_path"

status=${PIPESTATUS[0]}
if [ "$status" -eq 0 ]; then
  if ! python3 "$repo_root/ios-app/tools/check_p0_business_json.py" \
      --input outputs/parity/p0-business-android.json \
      --contract "$contract_path" \
      --platform android; then
    status=1
  elif ! python3 "$repo_root/ios-app/tools/write_parity_metadata.py" \
      --root "$repo_root" \
      --contract "$contract_path" \
      --platform android \
      --device "$device_id" \
      --os "Android emulator $device_id" \
      --screenshot-dir "$parity_output" \
      --output "$parity_output/capture-metadata.json"; then
    status=1
  elif ! python3 "$repo_root/ios-app/tools/check_capture_metadata.py" \
      --root "$repo_root" \
      --metadata "$parity_output/capture-metadata.json" \
      --platform android \
      --require-complete; then
    status=1
  fi
fi
echo "PARITY_DRIVER_END status=$status" | tee -a "$log_path"
exit "$status"
