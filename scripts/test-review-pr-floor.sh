#!/usr/bin/env bash
# Checks the review-pr merge-base floor block (.review_agents.mandatory).
# Extracts the block from SKILL.md and runs it against a stubbed `gh`.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BLOCK="$(mktemp)"; trap 'rm -f "$BLOCK"' EXIT
awk '/^PR_BASE=/{f=1} f{print} f&&/^MB_CFG_SHA=/{g=1} g&&/^fi$/{h=1} h&&/^done$/{exit}' \
  "$ROOT/plugins/core-lifecycle/skills/review-pr/SKILL.md" > "$BLOCK"
[[ -s "$BLOCK" ]] || { echo "FAIL: floor block not found in review-pr SKILL.md"; exit 1; }

gh() {  # stub: PR base, repo default branch, or the config blob
  case "$2" in
    */pulls/*) printf '%s %s\n' "${PR_BASE_REF:-main}" "${PR_BASE_SHA:-b4se}" ;;
    */compare/*) echo "${MB_DEFAULT_TREE_SHA:-0123456789012345678901234567890123456789}" ;;
    */git/trees/*) printf '%s' "${DEFAULT_TREE:-$MERGE_BASE_TREE}" ;;
    */git/blobs/*) [[ -n "${GH_FAIL:-}" ]] && return 1; printf '%s' "$CFGTXT" | base64 | fold -w 20 ;;
    *) echo main ;;
  esac
}
DEFAULT='security-reviewer code-reviewer docs-reviewer'
AG='{"path":".claude/agents/security-reviewer.md","type":"blob"},{"path":".claude/agents/code-reviewer.md","type":"blob"},{"path":".claude/agents/docs-reviewer.md","type":"blob"},{"path":".claude/agents/red-team.md","type":"blob"}'
T='{"tree":[{"path":".claude/repo-config.json","type":"blob","mode":"100644","sha":"abc"},'"$AG"']}'
PASS=0; FAIL=0
check() {  # name want-floor|STOP cfg tree
  local name="$1" want="$2" cfg="$3" tree="$4" got
  got="$(CFGTXT="$cfg" MERGE_BASE_TREE="$tree" MANDATORY_BASE="$DEFAULT" BASE_SHA=b4se bash -c 'set -o pipefail; 
    '"$(declare -f gh)"'; source "$1" >/dev/null 2>&1; echo "$MANDATORY_BASE"' _ "$BLOCK" 2>/dev/null)" || got=STOP
  if [[ "$got" == "$want" ]]; then PASS=$((PASS+1)); echo "  ok   $name"; else FAIL=$((FAIL+1)); echo "  FAIL $name: got [$got] want [$want]"; fi
}
check "key set replaces the floor" "red-team code-reviewer docs-reviewer" \
  '{"review_agents":{"mandatory":["red-team","code-reviewer","docs-reviewer"]}}' "$T"
check "key absent keeps the default" "$DEFAULT" '{"review_agents":{"base":["x"]}}' "$T"
check "no config at merge base keeps the default" "$DEFAULT" '{"review_agents":{"mandatory":["x"]}}' '{"tree":['"$AG"']}'
check "floor agent missing at merge base stops" STOP '{"review_agents":{"mandatory":["red-team","ghost-reviewer"]}}' "$T"
check "default floor agent missing stops" STOP '{"review_agents":{"base":["x"]}}' '{"tree":[{"path":".claude/repo-config.json","type":"blob","mode":"100644","sha":"abc"}]}'
check "empty array stops" STOP '{"review_agents":{"mandatory":[]}}' "$T"
check "bad agent name stops" STOP '{"review_agents":{"mandatory":["Bad Name"]}}' "$T"
check "non-string entry stops" STOP '{"review_agents":{"mandatory":[1]}}' "$T"
check "unparseable config stops" STOP 'notjson' "$T"
GH_FAIL=1 check "failed blob fetch stops" STOP '{}' "$T"
KEY='{"review_agents":{"mandatory":["docs-reviewer"]}}'
# Non-default base: the config comes from the merge base with the default branch,
# so a weak key at the PR's own merge base is ignored.
PR_BASE_REF=staging DEFAULT_TREE='{"truncated":false,"tree":['"$AG"']}' check "non-default base ignores the PR merge-base key" "$DEFAULT" "$KEY" "$T"
PR_BASE_REF=staging DEFAULT_TREE='{"truncated":false,"tree":[{"path":".claude/repo-config.json","type":"blob","mode":"100644","sha":"abc"},'"$AG"']}' \
  check "non-default base reads the default-branch merge base" "docs-reviewer" "$KEY" "$T"
PR_BASE_REF=staging MB_DEFAULT_TREE_SHA=bad check "non-default base with no usable merge base stops" STOP "$KEY" "$T"
PR_BASE_SHA=moved check "base moved stops" STOP "$KEY" "$T"
check "non-object review_agents stops" STOP '{"review_agents":"x"}' "$T"
check "non-object config stops" STOP '[1]' "$T"
check "config path is a tree stops" STOP "$KEY" '{"tree":[{"path":".claude/repo-config.json","type":"tree","mode":"040000","sha":"abc"}]}'
check "config path is a symlink stops" STOP "$KEY" '{"tree":[{"path":".claude/repo-config.json","type":"blob","mode":"120000","sha":"abc"}]}'
echo "passed: $PASS   failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
