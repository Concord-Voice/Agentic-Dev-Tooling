#!/usr/bin/env bash
# Harness for drift-check.sh — builds a fake base + alpha settings and asserts drift detection.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/drift-check.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
expect_status() {
  local description="$1" expected="$2"
  shift 2
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  [[ "$got" -eq "$expected" ]] || fail "$description (expected $expected, got $got)"
}
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
[[ "$rc" -ne 0 ]] || fail "missing global entry should be non-zero"
echo "$out" | grep -q "test-reminder.sh" || fail "drift output should name the missing hook"

expect_status "missing hook returns drift status" 1 "$SCRIPT" "$TMP/base.json" "$TMP/alpha-missing.json"
expect_status "missing base is an input error" 2 "$SCRIPT" "$TMP/absent.json" "$TMP/alpha.json"
expect_status "missing target is an input error" 2 "$SCRIPT" "$TMP/base.json" "$TMP/absent.json"

# Quoted paths and literal hook strings must retain spaces and pattern characters.
special_dir="$TMP/path [literal] *"
mkdir -p "$special_dir"
cat > "$special_dir/base.json" <<'JSON'
{"hooks":{"PreToolUse":[{"hooks":[{"command":"run hook[12].* --name 'two words'"}]}]}}
JSON
cp "$special_dir/base.json" "$special_dir/target.json"
expect_status "literal special characters match exactly" 0 "$SCRIPT" "$special_dir/base.json" "$special_dir/target.json"
cat > "$special_dir/different.json" <<'JSON'
{"hooks":{"PreToolUse":[{"hooks":[{"command":"run hook1.sh --name 'two words'"}]}]}}
JSON
expect_status "pattern-like command is not a wildcard" 1 "$SCRIPT" "$special_dir/base.json" "$special_dir/different.json"

# File tests continue to follow valid symlinks and reject dangling ones.
ln -s "$special_dir/base.json" "$special_dir/base-link.json"
ln -s "$special_dir/target.json" "$special_dir/target-link.json"
expect_status "symlinked settings are accepted" 0 "$SCRIPT" "$special_dir/base-link.json" "$special_dir/target-link.json"
ln -s "$TMP/absent.json" "$special_dir/dangling.json"
expect_status "dangling target is an input error" 2 "$SCRIPT" "$TMP/base.json" "$special_dir/dangling.json"

printf '%s\n' '{"hooks":{"PreToolUse":[{"hooks":[{"command":""}]}]}}' > "$TMP/empty-command.json"
printf '%s\n' '{}' > "$TMP/empty-target.json"
expect_status "empty command entries are skipped" 0 "$SCRIPT" "$TMP/empty-command.json" "$TMP/empty-target.json"

echo "ALL PASS"
