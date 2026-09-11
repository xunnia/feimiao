#!/usr/bin/env bash
# Production distribution moved to VPS. Cloudflare legacy publisher is archived.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/publish_update_vps.sh" "$@"
