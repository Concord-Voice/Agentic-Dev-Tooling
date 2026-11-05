#!/usr/bin/env bash
# Checks the review-pr merge-base floor block (.review_agents.mandatory).
# Extracts the block from SKILL.md and runs it against a stubbed `gh`.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BLOCK="$(mktemp)"; trap 'rm -f "$BLOCK"' EXIT
awk '/^MB_CFG_SHA=/{f=1} f{print} f&&/^fi$/{exit}' \
  "$ROOT/plugins/core-lifecycle/skills/review-pr/SKILL.md" > "$BLOCK"
[[ -s "$BLOCK" ]] || { echo "FAIL: floor block not found in review-pr SKILL.md"; exit 1; }

gh() { [[ -n "${GH_FAIL:-}" ]] && return 1; printf '%s' "$CFGTXT" | base64 | fold -w 20; }
DEFAULT='security-reviewer code-reviewer docs-reviewer'
T='{"tree":[{"path":".claude/repo-config.json","type":"blob","sha":"abc"}]}'
PASS=0; FAIL=0
check() {  # name want-floor|STOP cfg tree
  local name="$1" want="$2" cfg="$3" tree="$4" got
  got="$(CFGTXT="$cfg" MERGE_BASE_TREE="$tree" MANDATORY_BASE="$DEFAULT" bash -c '
    '"$(declare -f gh)"'; source "$1" >/dev/null 2>&1; echo "$MANDATORY_BASE"' _ "$BLOCK" 2>/dev/null)" || got=STOP
  if [[ "$got" == "$want" ]]; then PASS=$((PASS+1)); echo "  ok   $name"; else FAIL=$((FAIL+1)); echo "  FAIL $name: got [$got] want [$want]"; fi
}
check "key set replaces the floor" "red-team code-reviewer docs-reviewer" \
  '{"review_agents":{"mandatory":["red-team","code-reviewer","docs-reviewer"]}}' "$T"
check "key absent keeps the default" "$DEFAULT" '{"review_agents":{"base":["x"]}}' "$T"
check "no config at merge base keeps the default" "$DEFAULT" '{"review_agents":{"mandatory":["x"]}}' '{"tree":[]}'
check "empty array stops" STOP '{"review_agents":{"mandatory":[]}}' "$T"
check "bad agent name stops" STOP '{"review_agents":{"mandatory":["Bad Name"]}}' "$T"
check "non-string entry stops" STOP '{"review_agents":{"mandatory":[1]}}' "$T"
check "unparseable config stops" STOP 'notjson' "$T"
GH_FAIL=1 check "failed blob fetch stops" STOP '{}' "$T"
echo "passed: $PASS   failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
