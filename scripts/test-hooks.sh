#!/usr/bin/env bash
# Harness for the generalized hooks. Drives each via stdin JSON, asserts exit
# code + stderr, with and without a .claude/repo-config.json.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="${HOOKS_DIR:-$HERE/../plugins/guardrails/hooks}"   # override for repos where hooks don't live at plugins/guardrails/hooks
HOOKS="$(cd "$HOOKS_DIR" 2>/dev/null && pwd)"
[ -n "$HOOKS" ] && [ -d "$HOOKS" ] || { echo "FAIL: cannot resolve hooks dir ($HOOKS_DIR)" >&2; exit 1; }
fail() { echo "FAIL: $*" >&2; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.claude"
run() { # run <hook> <file_path> ; echoes "rc|stderr", uses CLAUDE_PROJECT_DIR=$TMP
  local hook="$1" fp="$2" err rc
  err="$(printf '{"tool_input":{"file_path":"%s"}}' "$fp" | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOKS/$hook" 2>&1 >/dev/null)"; rc=$?
  printf '%s|%s' "$rc" "$err"
}

# ---- No config present: protect-sensitive allows everything; test-reminder silent ----
rm -f "$TMP/.claude/repo-config.json"
[ "$(run protect-sensitive.sh services/auth/login.go)" = "0|" ] || fail "protect: no-config should allow (rc0, no stderr)"
[ "$(run test-reminder.sh src/foo.go)" = "0|" ] || fail "test-reminder: no-config should be silent"

# ---- With config: protect-sensitive blocks a matching pattern, allows a non-match ----
cat > "$TMP/.claude/repo-config.json" <<'JSON'
{ "hooks": {
  "protected_patterns": ["/auth/","tokenManager"],
  "test_reminders": [ {"regex":"migrations/.*\\.sql$","message":"MIGRATION-REMINDER","stop":true} ],
  "test_paths": { "source_ext":["go"], "skip_ext":["md"], "test_skip_re":"_test\\.go$", "remaps":[], "docs_reminder":"DOCS-REMINDER" }
} }
JSON
out="$(run protect-sensitive.sh "$TMP/services/auth/login.go")"; [ "${out%%|*}" = "2" ] || fail "protect: should BLOCK /auth/ (got $out)"
echo "$out" | grep -q "BLOCKED" || fail "protect: missing BLOCKED message"
[ "$(run protect-sensitive.sh "$TMP/src/util.go")" = "0|" ] || fail "protect: non-match should allow"

# ---- test-reminder: domain reminder + stop; docs reminder + coverage nag ----
out="$(run test-reminder.sh "$TMP/db/migrations/001_x.sql")"; echo "$out" | grep -q "MIGRATION-REMINDER" || fail "reminder: migration rule didn't fire"
out="$(run test-reminder.sh "$TMP/src/widget.go")"; echo "$out" | grep -q "DOCS-REMINDER" || fail "reminder: docs reminder didn't fire"; echo "$out" | grep -q "_test.go" || fail "reminder: coverage nag missing"
[ "$(run test-reminder.sh "$TMP/README.md")" = "0|" ] || fail "reminder: skip_ext md should be silent"

# ---- auto-format: empty/absent file path is a clean no-op ----
[ "$(run auto-format.sh "")" = "0|" ] || fail "auto-format: empty path should no-op"

# ---- auto-format: never fetch prettier through npx; only the installed binary runs ----
mkdir -p "$TMP/fmt/bin"; printf '{}\n' > "$TMP/fmt/.prettierrc"; printf 'x\n' > "$TMP/fmt/a.md"
printf '#!/bin/sh\ntouch "%s/npx-ran"\n' "$TMP/fmt" > "$TMP/fmt/bin/npx"; chmod +x "$TMP/fmt/bin/npx"
PATH="$TMP/fmt/bin:$PATH" run auto-format.sh "$TMP/fmt/a.md" >/dev/null
[ ! -e "$TMP/fmt/npx-ran" ] || fail "auto-format: ran npx with no installed prettier"
mkdir -p "$TMP/fmt/node_modules/.bin"
printf '#!/bin/sh\ntouch "%s/prettier-ran"\n' "$TMP/fmt" > "$TMP/fmt/node_modules/.bin/prettier"; chmod +x "$TMP/fmt/node_modules/.bin/prettier"
run auto-format.sh "$TMP/fmt/a.md" >/dev/null
[ -e "$TMP/fmt/prettier-ran" ] || fail "auto-format: installed prettier did not run"

# ---- protect-applied-migrations: no migrations dir in the repo => nothing to
# protect, allow (rc0, no stderr) — regression test for the fail-open fix:
# realpath used to fail closed and block EVERY Edit when the dir was absent.
rm -rf "$TMP/migrations"
[ "$(run protect-applied-migrations.sh "$TMP/migrations/000001_init.up.sql")" = "0|" ] \
  || fail "protect-applied-migrations: missing migrations dir should allow (rc0, no stderr)"

# ---- protect-applied-migrations: dir present, existing migration file => BLOCKED ----
mkdir -p "$TMP/migrations"
: > "$TMP/migrations/000001_init.up.sql"
out="$(run protect-applied-migrations.sh "$TMP/migrations/000001_init.up.sql")"
[ "${out%%|*}" = "2" ] || fail "protect-applied-migrations: should BLOCK an existing migration file (got $out)"
echo "$out" | grep -q "BLOCKED" || fail "protect-applied-migrations: missing BLOCKED message"
rm -rf "$TMP/migrations"

# ---- I1: invalid regex in protected_patterns fails CLOSED ----
cat > "$TMP/.claude/repo-config.json" <<'JSON'
{ "hooks": { "protected_patterns": ["[unbalanced"] } }
JSON
out="$(run protect-sensitive.sh "$TMP/src/whatever.go")"; [ "${out%%|*}" = "2" ] || fail "protect: invalid regex must fail closed (got $out)"
echo "$out" | grep -q "invalid regex" || fail "protect: invalid-regex message missing"

# ---- Marker-bypass engine (requires a git repo + branch) ----
GTMP="$(mktemp -d)"
( cd "$GTMP" || exit 1
  git init -q
  git checkout -q -b feature/test 2>/dev/null || git switch -q -c feature/test 2>/dev/null || true
  mkdir -p .claude/state/hook-bypass
  cat > .claude/repo-config.json <<'JSON'
{ "hooks": { "protected_patterns": ["/auth/"] } }
JSON
  # (a) Without a marker, a protected file is BLOCKED.
  rc=0; printf '{"tool_input":{"file_path":"%s"}}' "$GTMP/services/auth/login.go" | CLAUDE_PROJECT_DIR="$GTMP" bash "$HOOKS/protect-sensitive.sh" >/dev/null 2>&1 || rc=$?
  [ "$rc" = "2" ] || exit 31
  # (b) With a valid marker entry (repo-relative path), the same file is ALLOWED,
  #     and the bypass log names the marker FILE (auditability — Alpha's test asserts this).
  echo "services/auth/login.go" > ".claude/state/hook-bypass/feature__test.txt"
  err="$(printf '{"tool_input":{"file_path":"%s"}}' "$GTMP/services/auth/login.go" | CLAUDE_PROJECT_DIR="$GTMP" bash "$HOOKS/protect-sensitive.sh" 2>&1 >/dev/null)"; rc=$?
  [ "$rc" = "0" ] || exit 32
  echo "$err" | grep -q "feature__test.txt" || exit 35
  # (c) A symlinked marker is IGNORED → file BLOCKED again.
  rm ".claude/state/hook-bypass/feature__test.txt"
  echo "services/auth/login.go" > ".claude/state/hook-bypass/real.txt"
  ln -s real.txt ".claude/state/hook-bypass/feature__test.txt"
  rc=0; printf '{"tool_input":{"file_path":"%s"}}' "$GTMP/services/auth/login.go" | CLAUDE_PROJECT_DIR="$GTMP" bash "$HOOKS/protect-sensitive.sh" >/dev/null 2>&1 || rc=$?
  [ "$rc" = "2" ] || exit 33
  # (d) A '..' traversal entry is rejected → file BLOCKED.
  rm -f ".claude/state/hook-bypass/feature__test.txt"
  echo "../../../etc/passwd" > ".claude/state/hook-bypass/feature__test.txt"
  rc=0; printf '{"tool_input":{"file_path":"%s"}}' "$GTMP/services/auth/login.go" | CLAUDE_PROJECT_DIR="$GTMP" bash "$HOOKS/protect-sensitive.sh" >/dev/null 2>&1 || rc=$?
  [ "$rc" = "2" ] || exit 34
)
mrc=$?; rm -rf "$GTMP"
case "$mrc" in
  0) ;;
  31) fail "marker: protected file should be BLOCKED without a marker" ;;
  32) fail "marker: valid marker entry should ALLOW the file" ;;
  33) fail "marker: symlinked marker must be ignored (file BLOCKED)" ;;
  34) fail "marker: '..' traversal entry must be rejected (file BLOCKED)" ;;
  35) fail "marker: ALLOWED bypass log must name the marker file (feature__test.txt), not just the branch" ;;
  *) fail "marker: unexpected failure ($mrc)" ;;
esac

echo "ALL PASS"
