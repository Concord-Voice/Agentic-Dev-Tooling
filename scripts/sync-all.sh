#!/usr/bin/env bash
# sync-all.sh — run sync-shared.sh across every wired consumer repo under the org folder.
# Consumers are auto-discovered: sibling git repos of the Master that carry a .claude/ directory
# (pass explicit repo paths as arguments to override). Aggregates exit status across all.
# Usage: sync-all.sh [consumer-path ...]
# Test seam: SHARED_MASTER overrides the Master root (default = the repo this script lives in).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MASTER="${SHARED_MASTER:-$(cd "$HERE/.." && pwd)}"
SYNC="$HERE/sync-shared.sh"
die() { echo "sync-all: $*" >&2; exit 2; }
[ -x "$SYNC" ] || die "sync-shared.sh not found or not executable at $SYNC"

# Explicit args if given, else auto-discover sibling git repos (of the Master) with a .claude/ dir.
list_consumers() {
  if [ "$#" -gt 0 ]; then printf '%s\n' "$@"; return; fi
  local org d base abs; org="$(dirname "$MASTER")"
  for d in "$org"/* "$org"/.*; do
    [ -d "$d" ] || continue
    base="$(basename "$d")"; case "$base" in .|..) continue ;; esac
    { [ -d "$d/.git" ] || [ -f "$d/.git" ]; } || continue   # is a git repo
    [ -d "$d/.claude" ] || continue                         # is a wired consumer
    abs="$(cd "$d" && pwd)"; [ "$abs" = "$MASTER" ] && continue
    printf '%s\n' "$abs"
  done
}

rc=0; count=0
echo "sync-all: Master=$MASTER"
while IFS= read -r repo; do
  [ -n "$repo" ] || continue
  count=$((count + 1))
  echo "=== sync $repo ==="
  SHARED_MASTER="$MASTER" "$SYNC" "$repo" || { rc=1; echo "  (sync-shared FAILED for $repo)"; }
done < <(list_consumers "$@")
[ "$count" -gt 0 ] || die "no wired consumers found under $(dirname "$MASTER")"
echo "sync-all: done ($count consumer(s)); exit $rc"
exit "$rc"
