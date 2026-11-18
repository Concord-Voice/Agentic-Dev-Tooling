#!/usr/bin/env bash
# Harness for the generalized hooks. Drives each via stdin JSON, asserts exit
# code + stderr, with and without a .claude/repo-config.json.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="${HOOKS_DIR:-$HERE/../plugins/guardrails/hooks}"   # override for repos where hooks don't live at plugins/guardrails/hooks
HOOKS="$(cd "$HOOKS_DIR" 2>/dev/null && pwd)"
[ -n "$HOOKS" ] && [ -d "$HOOKS" ] || { echo "FAIL: cannot resolve hooks dir ($HOOKS_DIR)" >&2; exit 1; }
fail() { echo "FAIL: $*" >&2; exit 1; }
# Run hooks with the interpreter their shebang names (bash 3.2 on macOS), not the PATH bash.
HOOK_BASH=/bin/bash; [[ -x "$HOOK_BASH" ]] || HOOK_BASH=bash
fp_json() { local p=$1; jq -nc --arg p "$p" '{tool_input:{file_path:$p}}'; }   # file_path-only hook input
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.claude"
run() { # run <hook> <file_path> ; echoes "rc|stderr", uses CLAUDE_PROJECT_DIR=$TMP
  local hook="$1" fp="$2" err rc
  err="$(CLAUDE_PROJECT_DIR="$TMP" "$HOOK_BASH" "$HOOKS/$hook" <<<"$(fp_json "$fp")" 2>&1 >/dev/null)"; rc=$?
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

# ---- destructive-commands: enforced in the hook, not only by a settings deny list ----
dc() { local cmd=$1; printf '{"tool_input":{"command":"%s"}}' "$cmd" | "$HOOK_BASH" "$HOOKS/destructive-commands.sh" >/dev/null 2>&1; echo $?; }
for c in "git push --force origin main" "git push -f" "git reset --hard HEAD~1" "git clean -fd" "rm -rf build" "cd x && rm -r y" "git checkout -- ." \
         "git push origin +main" "git push origin b -fu" "git restore --staged --worktree ." "rm --recursive x" \
         "rm -f -r x" "git checkout -- ./" "git checkout HEAD -- ." "git restore ." "git clean --force" "find . | xargs rm -rf" "bash -c \\\"rm -rf build\\\"" "sh -c 'git reset --hard'" \
         "git diff --staged && git restore ." "git restore --staged . && git restore ." "git restore \\\".\\\"" "git restore '.'" \
         "git commit -m \\\"don't\\\" && git reset --hard && git commit -m \\\"it's\\\"" "echo \\\"\$(rm -rf x)\\\"" \
         "git restore --staged --worktree=true ." "git restore -SW ." \
         "git -C /tmp/x reset --hard HEAD" "git -c advice.detachedHead=false reset --hard" "git --no-pager push -f" \
         "env git reset --hard" "sudo git reset --hard" "time git push -f" "/usr/bin/git reset --hard" "GIT_DIR=.git git reset --hard" \
         "{ git reset --hard; }" "if true; then git reset --hard; fi" "! git reset --hard" "ls | xargs git push -f" \
         "git -C \\\"/tmp/a b\\\" reset --hard" "git --work-tree . reset --hard" "bash -lc \\\"rm -rf x\\\"" "find . -name x -exec rm -rf {} +" "/bin/rm -rf x" 'bash -c \"echo \\\"a\\\" && rm -rf x\"' \
         "git -c user.name=\\\"A B\\\" push --force" "git -c alias.x='a b' reset --hard" \
         "timeout 60 rm -rf build" "nice rm -rf build" "sudo -u root rm -rf build" "doas rm -rf build" \
         "xargs -I{} rm -rf {} < list" "if rm -rf build; then :; fi" "while rm -rf build; do :; done" \
         "eval rm -rf build" "echo rm -rf build | sh" "find . -ok rm -rf {} \\;" "parallel rm -rf ::: a b" \
         "timeout 5 bash -c 'rm -rf build'" "sudo -u root bash -c 'rm -rf build'" "bash -e -c 'rm -rf build'" \
         "find . -exec sh -c 'rm -rf x' _ {} \\;" "git commit -m 'Document bash -c \\\"rm -rf build\\\"'"; do
  [ "$(dc "$c")" = 2 ] || fail "destructive: should block: $c"
done
for c in "git push --force-with-lease origin b" "git push -u origin b" "git reset --soft HEAD~1" "rm file.txt" "git checkout -- src/a.ts" "npm run format" \
         "git commit -m 'fix git reset --hard docs'" "git commit -m 'document git push --force handling'" \
         "git push --force-with-lease --force-if-includes origin topic" "git restore --staged ." \
         "git commit -m 'Prevent rm -rf from running'" "git -C \\\"/tmp/a b\\\" status" "time make test" "git -c user.name=\\\"A B\\\" status" \
         "git rm -r --cached node_modules" "git -C sub rm -r old"; do
  [ "$(dc "$c")" = 0 ] || fail "destructive: should allow: $c"
done

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
# A hoisted install in an ancestor between the config dir and REPO_ROOT is found.
mkdir -p "$TMP/ws/pkg" "$TMP/ws/node_modules/.bin"; printf '{}\n' > "$TMP/ws/pkg/.prettierrc"; printf 'x\n' > "$TMP/ws/pkg/a.md"
printf '#!/bin/sh\ntouch "%s/hoisted-ran"\n' "$TMP/ws" > "$TMP/ws/node_modules/.bin/prettier"; chmod +x "$TMP/ws/node_modules/.bin/prettier"
run auto-format.sh "$TMP/ws/pkg/a.md" >/dev/null
[ -e "$TMP/ws/hoisted-ran" ] || fail "auto-format: hoisted prettier in an intermediate dir did not run"

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
# A `..` or `.` segment inside the missing part of a path fails closed: a later mkdir
# could make the path reach an existing migration.
for seg in .. .; do
  out="$(run protect-applied-migrations.sh "$TMP/migrations/not-yet/$seg/000001_init.up.sql")"
  [[ "${out%%|*}" = "2" ]] || fail "protect-applied-migrations: '$seg' in a missing suffix must fail closed (got $out)"
  echo "$out" | grep -q "Failed to resolve" || fail "protect-applied-migrations: '$seg' refusal message missing (got $out)"
  out="$(run protect-applied-migrations.sh "$TMP/migrations/not-yet/$seg")"
  [[ "${out%%|*}" = "2" ]] || fail "protect-applied-migrations: final '$seg' of a missing path must fail closed (got $out)"
done
# Spellings the editing tool resolves differently from the hook must not reach an
# existing migration: ~, surrounding blanks, a path relative to the session cwd, a
# newline that splits one path, and apply_patch markers the tool accepts.
pam() { # pam <json> ; echoes the hook's exit code
  local input=$1
  CLAUDE_PROJECT_DIR="$TMP" HOME="$(dirname "$TMP")" "$HOOK_BASH" "$HOOKS/protect-applied-migrations.sh" <<<"$input" >/dev/null 2>&1
  echo $?
}
# Write reaches the missing-suffix walk (an Edit with a missing parent already fails closed),
# so only Write runs guard the `.`/`..` checks there.
for seg in .. .; do
  for p in "$TMP/migrations/not-yet/$seg/000001_init.up.sql" "$TMP/migrations/not-yet/$seg"; do
    [[ "$(pam "$(jq -nc --arg p "$p" '{tool_name:"Write",tool_input:{file_path:$p}}')")" = "2" ]] \
      || fail "protect-applied-migrations: Write with '$seg' in a missing path must fail closed ($p)"
  done
done
mkdir -p "$TMP/sub"; : > "$TMP/sub/a.md"
MIG="$TMP/migrations/000001_init.up.sql"
# The Write runs are the real guard below; most Edit runs also fail closed on a missing parent.
for tool in Edit Write; do
  # shellcheck disable=SC2088 # the literal ~ is the input under test
  for p in "~/$(basename "$TMP")/migrations/000001_init.up.sql" " $MIG" "$MIG " "$TMP/migrations/"$'\n'"/../000001_init.up.sql" \
           $'\xc2\xa0'"$MIG" "$MIG"$'\xef\xbb\xbf' $'\xe3\x80\x80'"$MIG"; do
    [[ "$(pam "$(jq -nc --arg t "$tool" --arg p "$p" '{tool_name:$t,tool_input:{file_path:$p}}')")" = "2" ]] \
      || fail "protect-applied-migrations: $tool of a respelled migration path must fail closed ($(printf %q "$p"))"
  done
  [[ "$(pam "$(jq -nc --arg t "$tool" --arg c "$TMP/sub" '{tool_name:$t,cwd:$c,tool_input:{file_path:"../migrations/000001_init.up.sql"}}')")" = "2" ]] \
    || fail "protect-applied-migrations: $tool of a cwd-relative migration path must be blocked"
done
for hdr in $'\v'"*** Update File: $MIG" "*** Add File: $MIG" " *** Update File: $MIG" "*** update file: $MIG" "*** Update File: $MIG"$'\r'; do
  [[ "$(pam "$(jq -nc --arg c "*** Begin Patch"$'\n'"$hdr"$'\n'"+x"$'\n'"*** End Patch" '{tool_name:"apply_patch",tool_input:{command:$c}}')")" = "2" ]] \
    || fail "protect-applied-migrations: apply_patch header must be caught ($(printf %q "$hdr"))"
done
# Legitimate creates still pass: a new migration, a new file in new nested dirs, an
# absolute path while the session cwd is gone, and apply_patch Move to into a new dir.
[[ "$(pam "$(jq -nc --arg p "$TMP/docs/abs.md" --arg c "$TMP/gone" '{tool_name:"Write",cwd:$c,tool_input:{file_path:$p}}')")" = "0" ]] \
  || fail "protect-applied-migrations: absolute Write must not need the session cwd"
[[ "$(pam "$(jq -nc --arg c "*** Begin Patch"$'\n'"*** Update File: $TMP/sub/a.md"$'\n'"*** Move to: $TMP/newdir/b.md"$'\n'"*** End Patch" '{tool_name:"apply_patch",tool_input:{command:$c}}')")" = "0" ]] \
  || fail "protect-applied-migrations: apply_patch Move to into a new directory must be allowed"
[[ "$(pam "$(jq -nc --arg p "$TMP/migrations/000002_next.up.sql" '{tool_name:"Write",tool_input:{file_path:$p}}')")" = "0" ]] \
  || fail "protect-applied-migrations: Write of a new migration must be allowed"
[[ "$(pam "$(jq -nc --arg p "$TMP/docs/new/a.md" '{tool_name:"Write",tool_input:{file_path:$p}}')")" = "0" ]] \
  || fail "protect-applied-migrations: Write into new nested directories must be allowed"
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
  rc=0; CLAUDE_PROJECT_DIR="$GTMP" "$HOOK_BASH" "$HOOKS/protect-sensitive.sh" <<<"$(fp_json "$GTMP/services/auth/login.go")" >/dev/null 2>&1 || rc=$?
  [ "$rc" = "2" ] || exit 31
  # (b) With a valid marker entry (repo-relative path), the same file is ALLOWED,
  #     and the bypass log names the marker FILE (auditability — Alpha's test asserts this).
  echo "services/auth/login.go" > ".claude/state/hook-bypass/feature__test.txt"
  err="$(CLAUDE_PROJECT_DIR="$GTMP" "$HOOK_BASH" "$HOOKS/protect-sensitive.sh" <<<"$(fp_json "$GTMP/services/auth/login.go")" 2>&1 >/dev/null)"; rc=$?
  [ "$rc" = "0" ] || exit 32
  echo "$err" | grep -q "feature__test.txt" || exit 35
  # (c) A symlinked marker is IGNORED → file BLOCKED again.
  rm ".claude/state/hook-bypass/feature__test.txt"
  echo "services/auth/login.go" > ".claude/state/hook-bypass/real.txt"
  ln -s real.txt ".claude/state/hook-bypass/feature__test.txt"
  rc=0; CLAUDE_PROJECT_DIR="$GTMP" "$HOOK_BASH" "$HOOKS/protect-sensitive.sh" <<<"$(fp_json "$GTMP/services/auth/login.go")" >/dev/null 2>&1 || rc=$?
  [ "$rc" = "2" ] || exit 33
  # (d) A '..' traversal entry is rejected → file BLOCKED.
  rm -f ".claude/state/hook-bypass/feature__test.txt"
  echo "../../../etc/passwd" > ".claude/state/hook-bypass/feature__test.txt"
  rc=0; CLAUDE_PROJECT_DIR="$GTMP" "$HOOK_BASH" "$HOOKS/protect-sensitive.sh" <<<"$(fp_json "$GTMP/services/auth/login.go")" >/dev/null 2>&1 || rc=$?
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

# ---- protect-sensitive: Bash writes are guarded too (follow-up 27) ----
cmdrun() { # cmdrun <hook> <command> ; echoes rc
  local hook="$1" cmd="$2" rc=0
  jq -cn --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$TMP" "$HOOK_BASH" "$HOOKS/$hook" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}
cat > "$TMP/.claude/repo-config.json" <<'JSON'
{ "hooks": { "protected_patterns": ["/auth/"] } }
JSON
[[ "$(cmdrun protect-sensitive.sh "sed -i s/a/b/ services/auth/login.go")" = "2" ]] || fail "protect: Bash sed -i on a protected file must BLOCK"
[[ "$(cmdrun protect-sensitive.sh "echo x > services/auth/login.go")" = "2" ]] || fail "protect: Bash redirect onto a protected file must BLOCK"
[[ "$(cmdrun protect-sensitive.sh "cat services/auth/login.go")" = "0" ]] || fail "protect: Bash read of a protected file should allow"

# ---- protect-env-files: only .env.example is exempt; Bash is covered (follow-ups 10, 29) ----
for f in .env .env.e2e .env.eu-production .env.local app/prod.env; do
  [[ "$(run protect-env-files.sh "$TMP/$f")" != "0|" ]] || fail "env: $f must BLOCK"
done
[[ "$(run protect-env-files.sh "$TMP/.env.example")" = "0|" ]] || fail "env: .env.example should allow"
[[ "$(cmdrun protect-env-files.sh "cat desktop/.env")" = "2" ]] || fail "env: Bash cat of .env must BLOCK"
[[ "$(cmdrun protect-env-files.sh "cat .env.example")" = "0" ]] || fail "env: Bash cat of .env.example should allow"
[[ "$(cmdrun protect-env-files.sh "git status")" = "0" ]] || fail "env: unrelated Bash should allow"
for c in "cat .env*" "cat .en?" "cat .en''v" "cat {.env,x}" "cat .ENV" 'cat ".env"*' "cat '.en'?"; do
  [[ "$(cmdrun protect-env-files.sh "$c")" = "2" ]] || fail "env: Bash $c must BLOCK"
done
[[ "$(cmdrun protect-env-files.sh "cat .*")" = "2" ]] || fail "env: Bash cat .* must BLOCK"
for c in 'grep -rn "process.env" src' "rg import.meta.env" "ls config.env" \
         "jq -r '.[] | .name' f.json" "sed 's/.*foo//' x" "gh api x --jq '.[0].id'" "echo '.env*'"; do
  [[ "$(cmdrun protect-env-files.sh "$c")" = "0" ]] || fail "env: Bash $c should allow"
done

# ---- protect-applied-migrations: Write may create, never overwrite (follow-up 8) ----
wrun() { local path="$1" rc=0; jq -cn --arg p "$path" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"}}' | CLAUDE_PROJECT_DIR="$TMP" "$HOOK_BASH" "$HOOKS/protect-applied-migrations.sh" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
mkdir -p "$TMP/migrations"; : > "$TMP/migrations/000001_init.up.sql"
[[ "$(wrun "$TMP/migrations/000001_init.up.sql")" = "2" ]] || fail "migrations: Write over an existing migration must BLOCK"
[[ "$(wrun "$TMP/migrations/000002_next.up.sql")" = "0" ]] || fail "migrations: Write of a new migration should allow"

# Bot-PR review coverage: a review on an older SHA must never count.
bash "$HERE/../plugins/core-lifecycle/skills/enhanced-pr-review/test-review-coverage.sh" \
  || fail "review-coverage regression failed"

echo "ALL PASS"
