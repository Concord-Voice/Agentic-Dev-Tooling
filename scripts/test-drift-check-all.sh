#!/usr/bin/env bash
# Test harness for drift-check-all.sh — temp org layout; asserts OK when all consumers are in
# sync, and non-zero (naming the culprit) when one drifts.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/drift-check-all.sh"
SYNCALL="$HERE/sync-all.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/org/master"/{skills/ci-status,agents}
git -C "$TMP/org/master" init -q
echo "M" > "$TMP/org/master/skills/ci-status/SKILL.md"
echo "A" > "$TMP/org/master/agents/code-reviewer.md"
printf '{"shared_skills":["ci-status"],"shared_agents":["code-reviewer"]}\n' > "$TMP/org/master/shared-manifest.json"
for c in c1 c2; do mkdir -p "$TMP/org/$c/.claude"; git -C "$TMP/org/$c" init -q; done

# Bring both consumers into sync, then drift-check-all should be OK (exit 0).
SHARED_MASTER="$TMP/org/master" "$SYNCALL" >/dev/null
if ! SHARED_MASTER="$TMP/org/master" "$SCRIPT" >/dev/null 2>&1; then fail "in-sync org should exit 0"; fi

# Drift one consumer's copy → non-zero exit, and the output names that consumer.
echo "DRIFTED" > "$TMP/org/c2/.claude/skills/ci-status/SKILL.md"
out="$(SHARED_MASTER="$TMP/org/master" "$SCRIPT" 2>&1 || true)"
echo "$out" | grep -q "c2" || fail "drift output should name the drifted consumer (c2)"
if SHARED_MASTER="$TMP/org/master" "$SCRIPT" >/dev/null 2>&1; then fail "drifted org should exit non-zero"; fi

# Resync fixes it.
SHARED_MASTER="$TMP/org/master" "$SYNCALL" >/dev/null
if ! SHARED_MASTER="$TMP/org/master" "$SCRIPT" >/dev/null 2>&1; then fail "after resync should be OK again"; fi

echo "ALL PASS"
