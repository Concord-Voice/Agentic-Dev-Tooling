#!/usr/bin/env bash
# Test harness for migrate-claude-memory.sh — uses CLAUDE_PROJECTS_DIR seam (never touches real ~/.claude).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/migrate-claude-memory.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PROJECTS_DIR="$TMP/projects"
OLD="/Users/x/Dev/foo"; NEW="/Users/x/Dev/example-org/foo"
OLD_SLUG="-Users-x-Dev-foo"; NEW_SLUG="-Users-x-Dev-example-org-foo"
mkdir -p "$CLAUDE_PROJECTS_DIR/$OLD_SLUG/memory"
echo "m" > "$CLAUDE_PROJECTS_DIR/$OLD_SLUG/memory/MEMORY.md"

# Dry-run must NOT move anything.
out="$("$SCRIPT" "$OLD" "$NEW")"
grep -q "DRY-RUN" <<<"$out" || fail "dry-run banner missing"
[ -d "$CLAUDE_PROJECTS_DIR/$OLD_SLUG" ] || fail "dry-run moved data"
[ ! -d "$CLAUDE_PROJECTS_DIR/$NEW_SLUG" ] || fail "dry-run created destination"

# Slug computation correctness (dot + slash → dash).
out="$("$SCRIPT" "/Users/x/example-org-.github" "/Users/x/Dev/example-org/.github")"
grep -q -- "-Users-x-example-org--github" <<<"$out" || fail "slug dot-handling wrong"

# Apply must back up and move.
"$SCRIPT" "$OLD" "$NEW" --apply
[ -d "$CLAUDE_PROJECTS_DIR/$NEW_SLUG/memory" ] || fail "apply did not move to new slug"
[ -n "$(find "$CLAUDE_PROJECTS_DIR" -maxdepth 1 -name "${OLD_SLUG}.bak.*" -type d)" ] || fail "apply did not back up"

# Missing source is a graceful no-op (exit 0).
"$SCRIPT" "/Users/x/Dev/nonexistent" "/Users/x/Dev/example-org/nonexistent" --apply || fail "missing source should exit 0"

echo "ALL PASS"
