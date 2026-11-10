#!/usr/bin/env bash
# Copy shared skills and agents without replacing consumer customizations.
# The provenance ledger records each installed tree; unknown or edited copies
# require review before synchronization can proceed.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MASTER="${SHARED_MASTER:-$(cd "$HERE/.." && pwd)}"
command -v python3 >/dev/null 2>&1 || { echo 'sync-shared: python3 required' >&2; exit 2; }
exec python3 "$HERE/sync-shared-safe.py" "$MASTER" "${1:?usage: sync-shared.sh <consumer-repo-path>}"
