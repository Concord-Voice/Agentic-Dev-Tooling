#!/usr/bin/env bash
# Measure the real sync CLI under its existing integration harness.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${1:?usage: measure-sync-coverage.sh OUTPUT_XML}"
cd "$ROOT"
SYNC_REAL_PYTHON="${SYNC_COVERAGE_PYTHON:-$(command -v python3)}"
"$SYNC_REAL_PYTHON" -m coverage --version >/dev/null
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/python3" <<'WRAPPER'
#!/usr/bin/env bash
case "${1:-}" in
  */sync-shared-safe.py) exec "$SYNC_REAL_PYTHON" -m coverage run --parallel-mode "$@" ;;
  *) exec "$SYNC_REAL_PYTHON" "$@" ;;
esac
WRAPPER
chmod +x "$TMP/bin/python3"
cat > "$TMP/.coveragerc" <<'COVERAGE'
[run]
relative_files = true
source = scripts
timid = true
COVERAGE
export SYNC_REAL_PYTHON COVERAGE_FILE="$TMP/coverage" COVERAGE_RCFILE="$TMP/.coveragerc"
PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/test-sync-shared.sh"
"$SYNC_REAL_PYTHON" -m coverage combine --quiet "$TMP"
"$SYNC_REAL_PYTHON" -m coverage report --include='*/sync-shared-safe.py' --fail-under=80
"$SYNC_REAL_PYTHON" -m coverage xml --quiet --include='*/sync-shared-safe.py' -o "$OUTPUT"
