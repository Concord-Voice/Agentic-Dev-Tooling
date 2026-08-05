#!/usr/bin/env bash
# new-repo.sh — onboarding helper: wire a new org repo to the Master and seed repo-config.json.
# Usage: new-repo.sh <repo-path>
#   Calls setup-symlinks.sh (default exclude mode) and creates .claude/repo-config.json if absent.
# <repo-path> must be a git repo and a sibling of dev-tooling (same parent directory).
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

[ "${1:-}" ] || die "usage: new-repo.sh <repo-path>"

REPO="$(cd "$1" && pwd)"
ORG_DIR="$(dirname "$REPO")"
MASTER="$ORG_DIR/dev-tooling"
[ -d "$MASTER" ] || die "dev-tooling not found at $MASTER (repo must be a sibling of dev-tooling)"
{ [ -d "$REPO/.git" ] || [ -f "$REPO/.git" ]; } || die "$REPO is not a git repo"

# Step 1: wire symlinks via setup-symlinks.sh (default exclude mode).
SETUP="$(dirname "$0")/setup-symlinks.sh"
[ -x "$SETUP" ] || die "setup-symlinks.sh not found or not executable at $SETUP"
"$SETUP" "$REPO"

# Step 1b: copy shared skills/agents as REAL files (Claude Code can't discover symlinked skills/agents).
SYNC="$(dirname "$0")/sync-shared.sh"
[ -x "$SYNC" ] || die "sync-shared.sh not found or not executable at $SYNC (needed to install shared skills/agents)"
SHARED_MASTER="$MASTER" "$SYNC" "$REPO"

# Step 2: seed .claude/repo-config.json only if it does not already exist.
REPO_CONFIG="$REPO/.claude/repo-config.json"
if [ ! -e "$REPO_CONFIG" ]; then
  echo "{}" > "$REPO_CONFIG"
  echo "created $REPO_CONFIG — see knowledge/repo-config.reference.md to populate it"
else
  echo "repo-config.json already exists — left untouched"
fi

echo "done: onboarded $REPO"
