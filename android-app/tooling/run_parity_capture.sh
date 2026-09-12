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
# Flutter's Android tooling has historically derived the package to clean up
# from the Gradle namespace (`com.qingji.qingji`) instead of the final
# applicationId. Keep both identities in the scene lifecycle so an older
# install cannot keep a process/VM service alive between captures.
legacy_app_id="com.qingji.qingji"
app_ids=("$app_id" "$legacy_app_id")
scene_timeout_seconds="${PARITY_SCENE_TIMEOUT_SECONDS:-600}"
scene_retry_limit="${PARITY_SCENE_RETRIES:-1}"
shard_index="${PARITY_SHARD_INDEX:-0}"
shard_count="${PARITY_SHARD_COUNT:-1}"
if ! [[ "$shard_index" =~ ^[0-9]+$ && "$shard_count" =~ ^[1-9][0-9]*$ ]] ||
   [ "$shard_index" -ge "$shard_count" ] || [ "$shard_count" -gt 41 ]; then
  echo "Invalid parity shard: $shard_index/$shard_count" >&2
  exit 2
fi
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
if ! [[ "$scene_retry_limit" =~ ^[0-9]+$ ]]; then
  echo "PARITY_SCENE_RETRIES must be a non-negative integer; got: $scene_retry_limit" >&2
  exit 2
fi
timeout_bin="$(command -v timeout || true)"
if [ -z "$timeout_bin" ]; then
  echo "GNU timeout is required to bound each parity scene" >&2
  exit 2
fi
python_bin="${PYTHON_BIN:-}"
if [ -z "$python_bin" ]; then
  python_bin="$(command -v python3 || true)"
fi
if [ -z "$python_bin" ]; then
  python_bin="$(command -v python || true)"
fi
if [ -z "$python_bin" ]; then
  python_bin="$(command -v py || true)"
fi
if [ -z "$python_bin" ]; then
  echo "Python 3 is required for parity artifact validation" >&2
  exit 2
fi

{
  echo "PARITY_DRIVER_BEGIN"
  echo "PWD=$PWD"
  echo "ANDROID_DEVICE_ID=$device_id"
  echo "ANDROID_APP_ID=$app_id"
  echo "PARITY_SCENE_TIMEOUT_SECONDS=$scene_timeout_seconds"
  echo "PARITY_SCENE_RETRIES=$scene_retry_limit"
  echo "FLUTTER_BIN=$(command -v flutter || true)"
  echo "ADB_BIN=$(command -v adb || true)"
  echo "TIMEOUT_BIN=$timeout_bin"
  echo "PYTHON_BIN=$python_bin"
  flutter --version
  adb -s "$device_id" get-state
  # The canonical fixture lives under ios-app so there is only one source of
  # truth. Stage the same file into Flutter's package asset tree for the
  # integration test; it is generated in CI and never becomes production data.
  mkdir -p assets/parity
  # Normalize the fixture at the staging boundary as well as in the Python
  # contract checker. This keeps the Dart asset hash deterministic even when a
  # local checkout was created with core.autocrlf=true.
  fixture_asset="assets/parity/p0-demo-ledger-2026-08-v1.json"
  if ! fixture_hash="$("$python_bin" "$repo_root/ios-app/tools/canonical_fixture_hash.py" \
    "$fixture_path" --copy-to "$fixture_asset")"; then
    echo "Unable to canonicalize the P0 fixture" >&2
    exit 2
  fi
  if ! [[ "$fixture_hash" =~ ^[0-9A-F]{64}$ ]]; then
    echo "Canonical fixture helper returned an invalid SHA-256: $fixture_hash" >&2
    exit 2
  fi
  echo "P0_FIXTURE_HASH=$fixture_hash"
  # A parity artifact must contain only files produced by this invocation.
  # A previous partial run must never make a later run look complete.
  rm -rf "$parity_output"
  mkdir -p "$parity_output"
  # Keep Calendar/DateTime local-day calculations aligned with the iOS
  # simulator. The logical capture date itself is injected at compile time.
  adb -s "$device_id" shell settings put global auto_time_zone 0 || true
  adb -s "$device_id" shell settings put global time_zone Asia/Shanghai || true
  # Keep every scene in its own Flutter/VM-service session. A page that leaves
  # a route, animation, or platform channel pending must not hold the other
  # captures hostage; the driver response still writes the same business JSON
  # on every invocation and the final metadata check covers all 41 images.
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
  selected_scenes=()
  for index in "${!scenes[@]}"; do
    if [ "$((index % shard_count))" -eq "$shard_index" ]; then
      selected_scenes+=("${scenes[$index]}")
    fi
  done
  scenes=("${selected_scenes[@]}")
  echo "PARITY_SHARD index=$shard_index count=$shard_count scenes=${scenes[*]}"
  cleanup_scene_state() {
    local package
    # Stop both the current applicationId and the historical namespace-derived
    # id. `flutter drive` may have attempted to clean the latter even though it
    # installs the former, leaving an old process alive on a reused emulator.
    for package in "${app_ids[@]}"; do
      adb -s "$device_id" shell am force-stop "$package" >/dev/null 2>&1 || true
      adb -s "$device_id" shell am kill "$package" >/dev/null 2>&1 || true
    done
    # A stale Flutter VM-service forward makes the next driver connect to a
    # dead isolate. The parity job owns the only device, so remove all forwards
    # between independent scenes.
    adb -s "$device_id" forward --remove-all >/dev/null 2>&1 || true
  }

  # Remove packages left by a previous local/emulator run before the first
  # Flutter install. pm clear cannot repair a signing mismatch, while
  # uninstalling both ids also prevents the namespace-derived stale process.
  cleanup_scene_state
  for package in "${app_ids[@]}"; do
    adb -s "$device_id" uninstall "$package" >/dev/null 2>&1 || true
  done
  # A long sequence of independent flutter drive processes can leave the
  # emulator transport in the `offline` state even after the Dart test and
  # screenshot have completed. Recover the ADB server before giving up, then
  # rerun only the affected scene. This keeps a transient emulator transport
  # failure from invalidating an otherwise valid screenshot batch.
  recover_device() {
    local attempt
    for attempt in 1 2 3; do
      if adb -s "$device_id" get-state >/dev/null 2>&1; then
        echo "PARITY_DEVICE_READY attempt=$attempt"
        return 0
      fi
      echo "PARITY_DEVICE_RECOVER attempt=$attempt"
      adb reconnect offline >/dev/null 2>&1 || true
      sleep 2
      if adb -s "$device_id" get-state >/dev/null 2>&1; then
        echo "PARITY_DEVICE_READY attempt=$attempt method=reconnect"
        return 0
      fi
      adb kill-server >/dev/null 2>&1 || true
      adb start-server >/dev/null 2>&1 || true
      sleep 3
    done
    return 1
  }

  run_scene() {
    local scene="$1"
    echo "PARITY_SCENE_BEGIN scene=$scene"
    # Each scene gets a fresh application database. The package is deliberately
    # left installed so flutter drive can reuse the build, but stale process and
    # data state are cleared before the next invocation.
    cleanup_scene_state
    adb -s "$device_id" shell pm clear "$app_id" >/dev/null 2>&1 || true
    echo "PARITY_SCENE_RESET scene=$scene"
    "$timeout_bin" --foreground --kill-after=30s "${scene_timeout_seconds}s" flutter drive \
      --driver=test_driver/integration_test.dart \
      --target=integration_test/parity_screenshots_test.dart \
      --device-id "$device_id" \
      --no-pub \
      --dart-define=QINGJI_PARITY_CAPTURE=true \
      --dart-define=QINGJI_PARITY_SCENE="$scene" \
      --dart-define=QINGJI_DEMO_NOW=2026-08-27T12:00:00+08:00 \
      --dart-define=QINGJI_P0_FIXTURE_HASH="$fixture_hash"
    local status=$?
    # Always tear down the app and VM forward, including timeout/driver-error
    # paths. This is what makes a retry or the next scene independent.
    cleanup_scene_state
    echo "PARITY_SCENE_CLEANUP scene=$scene"
    echo "PARITY_SCENE_END scene=$scene status=$status"
    return "$status"
  }

  for scene in "${scenes[@]}"; do
    attempt=0
    while true; do
      if ! recover_device; then
        echo "::error::Android emulator is not online before parity scene: $scene"
        adb devices -l 2>&1 || true
        exit 2
      fi
      run_scene "$scene"
      scene_status=$?
      if [ "$scene_status" -eq 0 ]; then
        # Give the emulator a short idle window to flush PixelCopy/ADB work
        # before the next Flutter process starts.
        sleep 2
        break
      fi

      if [ "$scene_status" -eq 124 ] || [ "$scene_status" -eq 137 ]; then
        echo "::error::Parity scene timed out or was killed: $scene"
        adb -s "$device_id" shell dumpsys activity activities 2>&1 | tail -n 120 || true
        adb -s "$device_id" logcat -d -t 300 2>&1 | tail -n 300 || true
      fi

      # Retry only transport/process-loss failures. Assertion and application
      # failures remain fail-fast so a real regression is never hidden.
      transient_failure=0
      if ! adb -s "$device_id" get-state >/dev/null 2>&1; then
        transient_failure=1
      elif tail -n 160 "$log_path" 2>/dev/null | grep -Eq \
          'Service has disappeared|device offline|bad color buffer handle'; then
        transient_failure=1
      fi
      if [ "$transient_failure" -eq 1 ] && [ "$attempt" -lt "$scene_retry_limit" ]; then
        attempt=$((attempt + 1))
        echo "::warning title=Android parity transient transport failure::retrying scene=$scene attempt=$attempt/$scene_retry_limit"
        if recover_device; then
          sleep 2
          continue
        fi
      fi

      last_capture="$(grep -E 'PARITY_CAPTURE_(BEGIN|DONE)|PARITY_PAGE_(BEGIN|READY)|PARITY_SCENE_(BEGIN|END)' "$log_path" 2>/dev/null | tail -n 1 || true)"
      echo "::error title=Android parity scene failed::scene=$scene status=$scene_status"
      echo "PARITY_FAILURE scene=$scene status=$scene_status"
      if [ -n "$last_capture" ]; then
        echo "::error title=Android parity last capture::$last_capture"
        echo "PARITY_FAILURE_LAST_CAPTURE $last_capture"
      fi
      adb -s "$device_id" get-state 2>&1 || true
      adb devices -l 2>&1 || true
      exit "$scene_status"
    done
    if ! recover_device; then
      echo "::error::Android emulator went offline after parity scene: $scene"
      adb devices >&2 || true
      exit 2
    fi
  done
} 2>&1 | tee "$log_path"

status=${PIPESTATUS[0]}
completeness_args=()
if [ "$shard_count" -eq 1 ]; then
  completeness_args+=(--require-complete)
fi
if [ "$status" -eq 0 ]; then
  if ! "$python_bin" "$repo_root/ios-app/tools/check_p0_business_json.py" \
      --input outputs/parity/p0-business-android.json \
      --contract "$contract_path" \
      --platform android; then
    status=1
  elif ! "$python_bin" "$repo_root/ios-app/tools/write_parity_metadata.py" \
      --root "$repo_root" \
      --contract "$contract_path" \
      --platform android \
      --device "$device_id" \
      --os "Android emulator $device_id" \
      --screenshot-dir "$parity_output" \
      --output "$parity_output/capture-metadata.json"; then
    status=1
  elif ! "$python_bin" "$repo_root/ios-app/tools/check_capture_metadata.py" \
      --root "$repo_root" \
      --metadata "$parity_output/capture-metadata.json" \
      --platform android \
      "${completeness_args[@]}"; then
    status=1
  fi
fi

if [ "$status" -eq 0 ]; then
  # This receipt is written only after the entire shard and its business and
  # provenance checks succeed. The aggregate job rejects absent shards.
  printf '{"index":%s,"count":%s}\n' "$shard_index" "$shard_count" > "$parity_output/shard.json"
fi
echo "PARITY_DRIVER_END status=$status" | tee -a "$log_path"
exit "$status"
