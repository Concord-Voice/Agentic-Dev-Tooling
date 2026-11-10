#!/usr/bin/env bash
# Exercise actual hooks on review findings, without executing the supplied commands.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_DIR="${HOOKS_DIR:-$ROOT/plugins/guardrails/hooks}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.claude" "$TMP/desktop/src/preload" "$TMP/migrations"
printf '%s\n' '{"hooks":{"protected_patterns":["desktop/src/preload/"]}}' > "$TMP/.claude/repo-config.json"
run_hook() {
  local hook="$1" json="$2" cwd="$3" rc=0
  (cd "$cwd" && printf '%s' "$json" | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOKS_DIR/$hook" >/dev/null 2>&1) || rc=$?
  printf '%s\n' "$rc"
}
case "${1:-all}" in
  cwd|all)
    j="$(jq -cn '{tool_name:"Bash",tool_input:{command:"touch src/preload/test.ts"}}')"
    [ "$(run_hook protect-sensitive.sh "$j" "$TMP/desktop")" = 2 ] || { echo 'FAIL: relative protected path from subdirectory allowed' >&2; exit 1; }
    ;;&
  large|all)
    python3 -c 'import json; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"python3 - <<\047PY\047\nopen(\"desktop/src/preload/test.ts\",\"w\").write(\"x\")\nPY\n#" + "x" * 1000000}}))' > "$TMP/large.json"
    rc=0
    (cd "$TMP" && CLAUDE_PROJECT_DIR="$TMP" bash "$HOOKS_DIR/protect-sensitive.sh" < "$TMP/large.json" >/dev/null 2>&1) || rc=$?
    [ "$rc" = 2 ] || { echo 'FAIL: large interpreter command bypassed protection' >&2; exit 1; }
    ;;&
  migration|all)
    j="$(jq -cn --arg p "$TMP/new-review-probe-directory/file.txt" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"}}')"
    [ "$(run_hook protect-applied-migrations.sh "$j" "$TMP")" = 0 ] || { echo 'FAIL: new non-migration path blocked' >&2; exit 1; }
    : > "$TMP/migrations/000001_init.up.sql"
    ln -s "$TMP/migrations" "$TMP/migration-link"
    j="$(jq -cn --arg p "$TMP/migration-link/000001_init.up.sql" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"}}')"
    [ "$(run_hook protect-applied-migrations.sh "$j" "$TMP")" = 2 ] || { echo 'FAIL: existing migration through symlink allowed' >&2; exit 1; }
    j="$(jq -cn --arg p "$TMP/missing/../migrations/000001_init.up.sql" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"}}')"
    [ "$(run_hook protect-applied-migrations.sh "$j" "$TMP")" = 2 ] || { echo 'FAIL: ambiguous traversal to existing migration allowed' >&2; exit 1; }
    ;;&
  *) ;;
esac
printf '%s\n' 'ALL PASS'
