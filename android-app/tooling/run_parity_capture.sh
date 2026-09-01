#!/usr/bin/env bash

set -u

log_path="${GITHUB_WORKSPACE:-$PWD}/android-parity-drive.log"

{
  echo "PARITY_DRIVER_BEGIN"
  echo "PWD=$PWD"
  echo "FLUTTER_BIN=$(command -v flutter || true)"
  echo "ADB_BIN=$(command -v adb || true)"
  flutter --version
  adb devices
  # Keep Calendar/DateTime local-day calculations aligned with the iOS
  # simulator. The logical capture date itself is injected at compile time.
  adb shell settings put global auto_time_zone 0 || true
  adb shell settings put global time_zone Asia/Shanghai || true
  flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/parity_screenshots_test.dart \
    --device-id emulator-5554 \
    --no-pub \
    --dart-define=QINGJI_PARITY_CAPTURE=true \
    --dart-define=QINGJI_DEMO_NOW=2026-08-27T12:00:00+08:00
} 2>&1 | tee "$log_path"

status=${PIPESTATUS[0]}
if [ "$status" -eq 0 ]; then
  if ! python3 ../ios-app/tools/write_parity_metadata.py \
      --root .. \
      --contract ios-app/tools/p0_product_contract.json \
      --platform android \
      --device emulator-5554 \
      --os "Android emulator emulator-5554" \
      --screenshot-dir android-app/outputs/parity \
      --output android-app/outputs/parity/capture-metadata.json; then
    status=1
  elif ! python3 ../ios-app/tools/check_capture_metadata.py \
      --root .. \
      --metadata android-app/outputs/parity/capture-metadata.json \
      --platform android; then
    status=1
  fi
fi
echo "PARITY_DRIVER_END status=$status" | tee -a "$log_path"
exit "$status"
