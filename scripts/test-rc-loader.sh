#!/usr/bin/env bash
# Runs the trusted config loader from dev-lifecycle/SKILL.md against throwaway repos.
# The loader must tell "the default branch ships no config" (absent) apart from every
# case where a config exists but cannot be trusted or read (FATAL). Phase 7.5 and the
# quality gate treat absent as "nothing configured", so a wrong absent is a skipped gate.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$ROOT/plugins/core-lifecycle/skills/dev-lifecycle/SKILL.md"
PASS=0; FAIL=0
ok()  { echo "  ✓ $1"; PASS=$((PASS+1)); }
bad() { echo "  ✗ $1 — $2"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
# The first `> ```bash` fence after the "Load the helper once" note is the loader.
awk '/^> Load the helper once/{f=1} f&&/^> ```bash$/{g=1; next} g&&/^> ```$/{exit} g{sub(/^> ?/,""); print}' \
  "$SKILL" > "$WORK/loader.sh"
[ -s "$WORK/loader.sh" ] || { echo "could not extract the loader"; exit 1; }
mkdir -p "$WORK/bin"; printf '#!/bin/sh\nexit 1\n' > "$WORK/bin/gh"; chmod +x "$WORK/bin/gh"   # no API: use origin/HEAD

# <name> <config-kind: none|file|symlink>
mkrepo() {
  local r="$WORK/$1"; git init -q "$r"; git -C "$r" config user.email t@t; git -C "$r" config user.name t
  mkdir -p "$r/scripts" "$r/.claude"
  printf 'rc_get() { printf %%s "$2"; }\n' > "$r/scripts/repo-config.sh"
  case "$2" in
    file) printf '{"bots":[]}\n' > "$r/.claude/repo-config.json" ;;
    symlink) ln -s /etc/hostname "$r/.claude/repo-config.json" ;;
  esac
  git -C "$r" add -A; git -C "$r" commit -qm init
  git -C "$r" update-ref refs/remotes/origin/main HEAD
  git -C "$r" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  echo "$r"
}
# Prints STATE=<state> LEN=<n> and the exit code; stderr to $WORK/err.
run() {
  (cd "$1" && PATH="$WORK/bin:$PATH" RC_TRUSTED_STATE="${2:-}" bash -c \
    'source "$0" || exit 1; echo "STATE=${RC_TRUSTED_STATE:-unset} LEN=${#RC_TRUSTED_CFG}"' "$WORK/loader.sh") 2>"$WORK/err"
}

r="$(mkrepo present file)"; out="$(run "$r")"; rc=$?
[ $rc -eq 0 ] && grep -q 'STATE=present LEN=1[0-9]' <<<"$out" && ok "regular config → present, read" || bad "present" "rc=$rc out=[$out]"

r="$(mkrepo absent none)"; out="$(run "$r")"; rc=$?
[ $rc -eq 0 ] && grep -q 'STATE=absent LEN=0' <<<"$out" && ok "no config on the default branch → absent" || bad "absent" "rc=$rc out=[$out]"

r="$(mkrepo symlink symlink)"; out="$(run "$r")"; rc=$?
[ $rc -ne 0 ] && grep -q 'not a regular file' "$WORK/err" && ok "symlinked config → FATAL" || bad "symlink" "rc=$rc out=[$out]"

# Listed in the tree but the blob is gone (a partial clone that never fetched it).
r="$(mkrepo unreadable file)"
blob="$(git -C "$r" rev-parse HEAD:.claude/repo-config.json)"
rm -f "$r/.git/objects/${blob:0:2}/${blob:2}"
out="$(run "$r")"; rc=$?
[ $rc -ne 0 ] && grep -q 'could not read the default-branch' "$WORK/err" && ok "listed but unreadable → FATAL, not absent" || bad "unreadable" "rc=$rc out=[$out]"

# A state left in the environment by an earlier run must not survive a FATAL.
out="$(run "$r" absent)"; rc=$?
[ $rc -ne 0 ] && ! grep -q 'STATE=absent' <<<"$out" && ok "stale RC_TRUSTED_STATE is cleared before the read" || bad "stale state" "rc=$rc out=[$out]"

echo "─────────────"; echo "Passed: $PASS   Failed: $FAIL"
[ "$FAIL" -eq 0 ]
