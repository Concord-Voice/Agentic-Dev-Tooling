#!/usr/bin/env bash
# Harness for drift-check.sh — builds a fake base + alpha settings and asserts drift detection.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/drift-check.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/base.json" <<'JSON'
{ "hooks": { "PreToolUse": [ {"matcher":"Bash","hooks":[{"type":"command","command":".claude/hooks/destructive-commands.sh"}]} ],
             "PostToolUse": [ {"matcher":"Edit|Write","hooks":[{"type":"command","command":".claude/hooks/test-reminder.sh"}]} ] } }
JSON

# Alpha has all global entries (superset) → no drift (exit 0).
cat > "$TMP/alpha.json" <<'JSON'
{ "hooks": { "PreToolUse": [ {"matcher":"Bash","hooks":[{"type":"command","command":".claude/hooks/destructive-commands.sh"}]},
                             {"matcher":"Edit|Write","hooks":[{"type":"command","command":".claude/hooks/protect-applied-migrations.sh"}]} ],
             "PostToolUse": [ {"matcher":"Edit|Write","hooks":[{"type":"command","command":".claude/hooks/test-reminder.sh"}]} ] } }
JSON
"$SCRIPT" "$TMP/base.json" "$TMP/alpha.json" || fail "superset should report no drift (exit 0)"

# Alpha missing a global entry (test-reminder) → drift (non-zero) + names it.
cat > "$TMP/alpha-missing.json" <<'JSON'
{ "hooks": { "PreToolUse": [ {"matcher":"Bash","hooks":[{"type":"command","command":".claude/hooks/destructive-commands.sh"}]} ] } }
JSON
out="$("$SCRIPT" "$TMP/base.json" "$TMP/alpha-missing.json" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || fail "missing global entry should be non-zero"
echo "$out" | grep -q "test-reminder.sh" || fail "drift output should name the missing hook"

echo "ALL PASS"
