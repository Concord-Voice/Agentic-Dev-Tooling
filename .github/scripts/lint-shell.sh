#!/usr/bin/env bash
# ShellCheck gate for every tracked shell script.
# Blocks on warnings and errors, plus SC2251 (a bare `!` that skips errexit and
# so turns a test assertion into a no-op). Other info/style notes are advisory.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
list_shell() {
  local f
  while IFS= read -r -d '' f; do
    case $f in
      *.sh) ;;
      *) head -n1 -- "$f" | grep -Eq '^#!.*[/ ](ba)?sh$' || continue ;;
    esac
    printf '%s\0' "$f"
  done < <(git ls-files -z)
}
# One pass at info severity; only blocking findings are printed. ShellCheck
# exits 1 for any finding (notes included), so only exit >1 is a tool failure.
list_shell | xargs -0 -P "$(nproc)" -n 4 sh -c 'shellcheck --severity=info --format=gcc "$@"; [ $? -le 1 ]' sh \
  | awk '/: (error|warning): / || /\[SC2251\]$/ { print; bad = 1 } END { exit bad }'
