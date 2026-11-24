#!/usr/bin/env bash
# Measure the sync and profile CLIs while their integration tests exercise them.
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
  "$COVERAGE_SCRIPTS/sync-shared-safe.py"|"$COVERAGE_SCRIPTS/render-agent-profiles.py") exec "$SYNC_REAL_PYTHON" -m coverage run --parallel-mode "$@" ;;
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
export PYTHONDONTWRITEBYTECODE=1
export SYNC_REAL_PYTHON COVERAGE_SCRIPTS="$ROOT/scripts" COVERAGE_FILE="$TMP/coverage" COVERAGE_RCFILE="$TMP/.coveragerc"
export PATH="$TMP/bin:$PATH"
bash "$ROOT/scripts/test-sync-shared.sh"
bash "$ROOT/scripts/test-native-agents.sh"
"$SYNC_REAL_PYTHON" -m coverage run --parallel-mode "$ROOT/scripts/test-codex-isolated-review.py"
"$SYNC_REAL_PYTHON" -m coverage run --parallel-mode "$ROOT/scripts/test-fleet-workflows.py"
"$SYNC_REAL_PYTHON" -m coverage run --parallel-mode "$ROOT/scripts/test-architect-git-evidence.py"
"$SYNC_REAL_PYTHON" -m coverage run --parallel-mode "$ROOT/scripts/test-claude-architect.py"
"$SYNC_REAL_PYTHON" -m coverage run --parallel-mode "$ROOT/scripts/test-protected-sonar.py"
"$SYNC_REAL_PYTHON" -m coverage combine --quiet "$TMP"
"$SYNC_REAL_PYTHON" -m coverage report --include='*/sync-shared-safe.py' --fail-under=80
"$SYNC_REAL_PYTHON" -m coverage report --include='*/render-agent-profiles.py' --fail-under=80
"$SYNC_REAL_PYTHON" -m coverage report --include='*/codex-isolated-review.py,*/codex_review_session.py' --fail-under=80
"$SYNC_REAL_PYTHON" -m coverage report --include='*/resolve-fleet-workflow.py' --fail-under=80
architect_sources="*/architect_git_evidence.py,*/architect_git_mcp.py,*/claude-architect.py"
"$SYNC_REAL_PYTHON" -m coverage report --include="$architect_sources" --fail-under=80
"$SYNC_REAL_PYTHON" -m coverage report --include='*/protected_sonar.py' --fail-under=80
"$SYNC_REAL_PYTHON" -m coverage xml --quiet --include='*/sync-shared-safe.py,*/render-agent-profiles.py,*/codex-isolated-review.py,*/codex_review_session.py,*/test-codex-isolated-review.py,*/resolve-fleet-workflow.py,*/native-issue-index.py,*/test-fleet-workflows.py,*/protected_sonar.py,'"$architect_sources" -o "$OUTPUT"
