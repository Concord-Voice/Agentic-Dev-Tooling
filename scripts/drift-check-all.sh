#!/usr/bin/env bash
# drift-check-all.sh — run drift-check-shared.sh across every wired consumer repo under the org
# folder. Same auto-discovery as sync-all.sh (override with explicit repo-path args). Exits
# non-zero if ANY consumer has drifted, and names them.
# Usage: drift-check-all.sh [consumer-path ...]
# Test seam: SHARED_MASTER overrides the Master root (default = the repo this script lives in).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MASTER="${SHARED_MASTER:-$(cd "$HERE/.." && pwd)}"
CHECK="$HERE/drift-check-shared.sh"
die() { echo "drift-check-all: $*" >&2; exit 2; }
[ -x "$CHECK" ] || die "drift-check-shared.sh not found or not executable at $CHECK"

# Explicit args if given, else auto-discover sibling git repos (of the Master) with a .claude/ dir.
list_consumers() {
  if [ "$#" -gt 0 ]; then printf '%s\n' "$@"; return; fi
  local org d base abs; org="$(dirname "$MASTER")"
  for d in "$org"/* "$org"/.*; do
    [ -d "$d" ] || continue
    base="$(basename "$d")"; case "$base" in .|..) continue ;; esac
    { [ -d "$d/.git" ] || [ -f "$d/.git" ]; } || continue
    [ -d "$d/.claude" ] || continue
    abs="$(cd "$d" && pwd)"; [ "$abs" = "$MASTER" ] && continue
    printf '%s\n' "$abs"
  done
}

rc=0; count=0; drifted=""
echo "drift-check-all: Master=$MASTER"
while IFS= read -r repo; do
  [ -n "$repo" ] || continue
  count=$((count + 1))
  echo "=== $repo ==="
  if SHARED_MASTER="$MASTER" "$CHECK" "$repo"; then :; else rc=1; drifted="$drifted $(basename "$repo")"; fi
done < <(list_consumers "$@")
[ "$count" -gt 0 ] || die "no wired consumers found under $(dirname "$MASTER")"
if [ "$rc" -eq 0 ]; then
  echo "drift-check-all: OK — all $count consumer(s) in sync with the Master"
else
  echo "drift-check-all: DRIFT in:$drifted  — run scripts/sync-all.sh to resync"
fi
exit "$rc"
