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

{
  echo "PARITY_DRIVER_BEGIN"
  echo "PWD=$PWD"
  echo "ANDROID_DEVICE_ID=$device_id"
  echo "FLUTTER_BIN=$(command -v flutter || true)"
  echo "ADB_BIN=$(command -v adb || true)"
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
  scenes=(
    drawer-books
    home-overview
    quick-add-expense
    quick-add-income
    transactions-search
    reimburse
    reimburse-settlement
    books-management
    accounts-management
    categories
    tags
    category-memory
    stats-week
    stats-month
    stats-year
    stats-custom
    budget
    savings
    recurring
    import-review
    reports-library
    backup
    settings
    theme
    display
    assets-hub
    assets-funds
    reconcile
    liabilities
    net-worth
    physical-asset-detail
    account-detail
    ai-entry
    ai-settings
    ai-tasks
    ai-diagnostics
    ai-search
    ai-memory
    ai-extensions
    ai-schedules
    ai-local
  )
  for scene in "${scenes[@]}"; do
    echo "PARITY_SCENE_BEGIN scene=$scene"
    flutter drive \
      --driver=test_driver/integration_test.dart \
      --target=integration_test/parity_screenshots_test.dart \
      --device-id "$device_id" \
      --no-pub \
      --dart-define=QINGJI_PARITY_CAPTURE=true \
      --dart-define=QINGJI_PARITY_SCENE="$scene" \
      --dart-define=QINGJI_DEMO_NOW=2026-08-27T12:00:00+08:00 \
      --dart-define=QINGJI_P0_FIXTURE_HASH="$fixture_hash"
    scene_status=$?
    echo "PARITY_SCENE_END scene=$scene status=$scene_status"
    if [ "$scene_status" -ne 0 ]; then
      exit "$scene_status"
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
