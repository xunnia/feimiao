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
  flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/parity_screenshots_test.dart \
    --device-id emulator-5554 \
    --no-pub \
    --dart-define=QINGJI_PARITY_CAPTURE=true
} 2>&1 | tee "$log_path"

status=${PIPESTATUS[0]}
echo "PARITY_DRIVER_END status=$status" | tee -a "$log_path"
exit "$status"
