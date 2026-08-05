#!/usr/bin/env bash
# migrate-claude-memory.sh — re-key Claude Code per-project state when a repo moves.
# Renames <projects>/<old-slug> → <new-slug>. Slug = abs path with '/' and '.' → '-'.
# Usage: migrate-claude-memory.sh <old-abs-path> <new-abs-path> [--apply]
#   default: dry-run. --apply backs up then renames.
# Test seam: CLAUDE_PROJECTS_DIR overrides the default ~/.claude/projects.
set -euo pipefail

PROJECTS="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
die() { echo "ERROR: $*" >&2; exit 1; }
slug() { printf '%s' "$1" | sed 's#[/.]#-#g'; }

OLD=""; NEW=""; APPLY=0
for a in "$@"; do
  case "$a" in
    --apply) APPLY=1 ;;
    -*) die "unknown flag: $a" ;;
    *) if [ -z "$OLD" ]; then OLD="$a"; elif [ -z "$NEW" ]; then NEW="$a"; else die "too many args"; fi ;;
  esac
done
[ -n "$OLD" ] && [ -n "$NEW" ] || die "usage: migrate-claude-memory.sh <old-abs-path> <new-abs-path> [--apply]"

OLD_SLUG="$(slug "$OLD")"; NEW_SLUG="$(slug "$NEW")"
SRC="$PROJECTS/$OLD_SLUG"; DST="$PROJECTS/$NEW_SLUG"
echo "old slug : $OLD_SLUG"
echo "new slug : $NEW_SLUG"

[ -d "$SRC" ] || { echo "no state dir at $SRC — nothing to migrate (ok)"; exit 0; }
[ -e "$DST" ] && die "destination already exists: $DST (refusing to clobber)"

if [ "$APPLY" -eq 0 ]; then
  echo "DRY-RUN: would back up then rename $SRC → $DST"
  echo "         ($(find "$SRC" -type f | wc -l | tr -d ' ') files)"
  echo "re-run with --apply to perform."
  exit 0
fi

BACKUP="${SRC}.bak.$$"
cp -a "$SRC" "$BACKUP"
mv "$SRC" "$DST"
echo "migrated: $SRC → $DST  (backup: $BACKUP)"
echo "verify Claude reads memory at the new path, then remove the backup manually."
