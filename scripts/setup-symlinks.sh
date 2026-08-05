#!/usr/bin/env bash
# setup-symlinks.sh — wire a repo to the dev-tooling Master (global layer).
# Usage: setup-symlinks.sh <repo-path> [--mode=exclude|commit]
#   --mode=exclude (default): register symlinks in <repo>/.git/info/exclude (thin repos; pristine tree)
#   --mode=commit          : leave symlinks tracked (Alpha — committed relative symlinks)
# Assumes <repo> and dev-tooling are siblings under the org folder.
# Precedence: a repo's existing real item of a given name is kept (local overrides global).
#
# NOTE: skills/ and agents/ are intentionally NOT symlinked. Claude Code's skill/agent
# discovery walks REAL directories and does not follow symlinks, so symlinked skills/agents
# never load at runtime. They are distributed as REAL copies by scripts/sync-shared.sh.
# This script wires only the symlink-safe categories: hooks (invoked by path → symlinks work)
# and rules. (Rules-via-symlink loading is unverified; if rules show the same issue, move them
# to sync-shared too.)
set -euo pipefail

CATEGORIES=(rules hooks)
die() { echo "ERROR: $*" >&2; exit 1; }

REPO=""; MODE="exclude"
for arg in "$@"; do
  case "$arg" in
    --mode=*) MODE="${arg#--mode=}" ;;
    -*) die "unknown flag: $arg" ;;
    *)  REPO="$arg" ;;
  esac
done
[ -n "$REPO" ] || die "usage: setup-symlinks.sh <repo-path> [--mode=exclude|commit]"
[ "$MODE" = "exclude" ] || [ "$MODE" = "commit" ] || die "mode must be exclude|commit"

REPO="$(cd "$REPO" && pwd)"
ORG_DIR="$(dirname "$REPO")"
MASTER="$ORG_DIR/dev-tooling"
[ -d "$MASTER" ] || die "dev-tooling not found at $MASTER (repo must be a sibling of dev-tooling)"
{ [ -d "$REPO/.git" ] || [ -f "$REPO/.git" ]; } || die "$REPO is not a git repo"
mkdir -p "$REPO/.claude"

EXCLUDE_FILE="$REPO/.git/info/exclude"
add_exclude() {
  [ "$MODE" = "exclude" ] || return 0
  mkdir -p "$(dirname "$EXCLUDE_FILE")"; touch "$EXCLUDE_FILE"
  grep -qxF "$1" "$EXCLUDE_FILE" || echo "$1" >> "$EXCLUDE_FILE"
}
link() {  # link <relative-target> <absolute-linkpath>
  local target="$1" linkpath="$2"
  if [ -L "$linkpath" ]; then
    [ "$(readlink "$linkpath")" = "$target" ] && return 0
    rm "$linkpath"
  elif [ -e "$linkpath" ]; then
    die "refusing to overwrite non-symlink (local overlay): $linkpath"
  fi
  mkdir -p "$(dirname "$linkpath")"
  ln -s "$target" "$linkpath"
}

for cat in "${CATEGORIES[@]}"; do
  master_cat="$MASTER/$cat"; [ -d "$master_cat" ] || continue
  repo_cat="$REPO/.claude/$cat"
  if { [ -e "$repo_cat" ] && [ ! -L "$repo_cat" ]; } || [ "$MODE" = "commit" ]; then
    # Real local category dir, or commit mode (Alpha) → per-item overlay so locals coexist.
    # Carry-forward #4: if repo_cat is a whole-dir symlink (from a prior exclude-mode
    # run), remove it before per-item linking so we don't write through it into the Master.
    if [ -L "$repo_cat" ]; then rm "$repo_cat"; fi
    mkdir -p "$repo_cat"
    for item in "$master_cat"/*; do
      [ -e "$item" ] || continue
      name="$(basename "$item")"; linkpath="$repo_cat/$name"
      if [ -e "$linkpath" ] && [ ! -L "$linkpath" ]; then
        echo "skip (local overrides global): .claude/$cat/$name"; continue
      fi
      link "../../../dev-tooling/$cat/$name" "$linkpath"
      add_exclude ".claude/$cat/$name"
      echo "linked .claude/$cat/$name"
    done
  else
    # No local items → whole-dir symlink.
    link "../../dev-tooling/$cat" "$repo_cat"
    add_exclude ".claude/$cat"
    echo "linked .claude/$cat (whole dir)"
  fi
done

SETTINGS="$REPO/.claude/settings.json"
if [ ! -e "$SETTINGS" ]; then
  link "../../dev-tooling/settings/base.settings.json" "$SETTINGS"
  add_exclude ".claude/settings.json"
  echo "linked .claude/settings.json"
else
  echo "settings.json exists (overlay) — left as-is; reconcile against base.settings.json manually"
fi

echo "done: wired $REPO (mode=$MODE)"
