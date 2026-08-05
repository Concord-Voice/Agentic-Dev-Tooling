#!/usr/bin/env bash
# Test harness for sync-all.sh — temp org layout (master + 2 consumers + a non-consumer);
# asserts auto-discovery syncs the consumers, skips the non-consumer, and excludes the Master.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/sync-all.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Master (a git repo WITH a .claude/ dir — to prove the Master-exclusion, not just "no .claude").
mkdir -p "$TMP/org/master"/{skills/ci-status,agents,.claude}
git -C "$TMP/org/master" init -q
echo "M" > "$TMP/org/master/skills/ci-status/SKILL.md"
echo "A" > "$TMP/org/master/agents/code-reviewer.md"
printf '{"shared_skills":["ci-status"],"shared_agents":["code-reviewer"]}\n' > "$TMP/org/master/shared-manifest.json"

# Two wired consumers (git repo + .claude/) and one non-consumer (git repo, no .claude/).
for c in c1 c2; do mkdir -p "$TMP/org/$c/.claude"; git -C "$TMP/org/$c" init -q; done
mkdir -p "$TMP/org/plain"; git -C "$TMP/org/plain" init -q

SHARED_MASTER="$TMP/org/master" "$SCRIPT" >/dev/null

# Both consumers got the shared skill + agent as REAL copies.
for c in c1 c2; do
  [ -d "$TMP/org/$c/.claude/skills/ci-status" ] && [ ! -L "$TMP/org/$c/.claude/skills/ci-status" ] || fail "$c: skill not synced as real dir"
  [ "$(cat "$TMP/org/$c/.claude/skills/ci-status/SKILL.md")" = "M" ] || fail "$c: skill content wrong"
  [ -f "$TMP/org/$c/.claude/agents/code-reviewer.md" ] || fail "$c: agent not synced"
done
# Non-consumer (no .claude/) skipped entirely.
[ ! -d "$TMP/org/plain/.claude" ] || fail "non-consumer 'plain' should be skipped"
# Master excluded even though it is a git repo with a .claude/ dir.
[ ! -d "$TMP/org/master/.claude/skills" ] || fail "Master should be excluded from consumers"

# Explicit-args form syncs just the named repo.
rm -rf "$TMP/org/c1/.claude/skills"
SHARED_MASTER="$TMP/org/master" "$SCRIPT" "$TMP/org/c1" >/dev/null
[ -d "$TMP/org/c1/.claude/skills/ci-status" ] || fail "explicit-arg form did not sync c1"

echo "ALL PASS"
