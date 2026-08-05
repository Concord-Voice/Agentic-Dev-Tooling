#!/usr/bin/env bash
# drift-check.sh — verify every GLOBAL hook command in base.settings.json is also
# present in a target settings.json (a downstream repo's superset). Reports missing entries.
# Usage: drift-check.sh [base.settings.json] [target-settings.json]
# Defaults: base = <this repo>/config/base.settings.json
#           target = ~/Dev/example-org/example-repo/.claude/settings.json
#                    (adjust the fallback paths below for your own layout)
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo "drift-check: jq required" >&2; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="${1:-$HERE/../config/base.settings.json}"
TARGET="${2:-}"
if [ -z "$TARGET" ]; then
  for c in "$HOME/Dev/example-org/example-repo/.claude/settings.json" "$HOME/Dev/example-repo/.claude/settings.json"; do
    [ -f "$c" ] && { TARGET="$c"; break; }
  done
fi
[ -f "$BASE" ] || { echo "drift-check: base not found: $BASE" >&2; exit 2; }
[ -f "$TARGET" ] || { echo "drift-check: target settings.json not found" >&2; exit 2; }

# All hook command strings, regardless of event/matcher nesting.
cmds() { jq -r '[.hooks[]?[]?.hooks[]?.command] | sort | unique[]' "$1" 2>/dev/null; }
missing=0
while IFS= read -r cmd; do
  [ -z "$cmd" ] && continue
  if ! cmds "$TARGET" | grep -qxF "$cmd"; then
    echo "DRIFT: global hook missing from target: $cmd"
    missing=1
  fi
done < <(cmds "$BASE")

if [ "$missing" -eq 0 ]; then echo "OK: all global hook entries present in target ($TARGET)"; fi
exit "$missing"
