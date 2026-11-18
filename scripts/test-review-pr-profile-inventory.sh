#!/usr/bin/env bash
# Exercise the actual profile inventory loop from the skill against Git trees.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$TMP"' EXIT
BLOCK="$TMP/inventory.sh"
awk '/^for profile_dir in / {copy=1} /^# Nothing moved while we looked/ {copy=0} copy {print}' \
  "$ROOT/plugins/core-lifecycle/skills/review-pr/SKILL.md" > "$BLOCK"
[[ -s "$BLOCK" ]] || { echo 'FAIL: inventory loop missing' >&2; exit 1; }
REPO_ROOT="$TMP/repo"; mkdir -p "$REPO_ROOT/.claude/agents"
git -C "$REPO_ROOT" init -q
printf '%s\n' 'trusted profile' > "$REPO_ROOT/.claude/agents/reviewer.md"
git -C "$REPO_ROOT" add .claude/agents/reviewer.md
git -C "$REPO_ROOT" -c user.name=test -c user.email=test@example.invalid commit -qm fixture
TAB="$(printf '\t')"
HEAD_PROFILE_ROWS="$(git -C "$REPO_ROOT" ls-tree -r HEAD -- .claude/agents .github/agents .codex/agents | awk -F '[ \t]' '{printf "%s\t%s\n", $4, $3}')"
export REPO_ROOT HEAD_PROFILE_ROWS TAB
if ! bash "$BLOCK" >/dev/null 2>&1; then
  echo 'FAIL: missing unused harness directories should be allowed' >&2
  exit 1
fi
mv "$REPO_ROOT/.claude/agents" "$TMP/expected-agents"
if bash "$BLOCK" >/dev/null 2>&1; then
  echo 'FAIL: missing directory with tracked profiles was accepted' >&2
  exit 1
fi
mv "$TMP/expected-agents" "$REPO_ROOT/.claude/agents"
printf '%s\n' injected > "$REPO_ROOT/.claude/agents/untracked.md"
if bash "$BLOCK" >/dev/null 2>&1; then
  echo 'FAIL: unexpected local reviewer was accepted' >&2
  exit 1
fi
rm "$REPO_ROOT/.claude/agents/untracked.md"
mkdir -p "$REPO_ROOT/.github"
ln -s "$REPO_ROOT/.claude/agents" "$REPO_ROOT/.github/agents"
if bash "$BLOCK" >/dev/null 2>&1; then
  echo 'FAIL: symlinked reviewer directory was accepted' >&2
  exit 1
fi
printf '%s\n' 'ALL PASS'
