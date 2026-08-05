#!/usr/bin/env bash
# Test harness for setup-symlinks.sh — wires only the symlink-safe categories (rules, hooks)
# + settings.json. Skills/agents are NOT symlinked (Claude Code can't discover symlinked
# skills/agents; they go through sync-shared.sh). Builds a temp org layout and asserts wiring.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/setup-symlinks.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Fake Master: one item per category (skills/agents included to prove they are NOT linked).
mkdir -p "$TMP/dev-tooling"/{skills/ci-status,agents,rules,hooks,settings}
echo "skill" > "$TMP/dev-tooling/skills/ci-status/SKILL.md"
echo "agent" > "$TMP/dev-tooling/agents/code-reviewer.md"
echo "rule"  > "$TMP/dev-tooling/rules/labels.md"
echo "hook"  > "$TMP/dev-tooling/hooks/destructive-commands.sh"
echo "{}"    > "$TMP/dev-tooling/settings/base.settings.json"

# Thin repo (no local items) — whole-dir symlinks for rules+hooks, settings linked, clean git.
mkdir -p "$TMP/thin"; git -C "$TMP/thin" init -q
"$SCRIPT" "$TMP/thin"
[ -L "$TMP/thin/.claude/hooks" ] || fail "thin: hooks not a symlink"
[ "$(readlink "$TMP/thin/.claude/hooks")" = "../../dev-tooling/hooks" ] || fail "thin: hooks target wrong"
[ -L "$TMP/thin/.claude/rules" ] || fail "thin: rules not a symlink"
[ -L "$TMP/thin/.claude/settings.json" ] || fail "thin: settings.json not linked"
[ -f "$TMP/thin/.claude/hooks/destructive-commands.sh" ] || fail "thin: hook symlink does not resolve"
# skills/agents must NOT be wired by setup-symlinks (they go via sync-shared)
[ ! -e "$TMP/thin/.claude/skills" ] || fail "thin: skills should NOT be wired by setup-symlinks"
[ ! -e "$TMP/thin/.claude/agents" ] || fail "thin: agents should NOT be wired by setup-symlinks"
grep -qxF ".claude/hooks" "$TMP/thin/.git/info/exclude" || fail "thin: hooks not excluded"
[ -z "$(git -C "$TMP/thin" status --porcelain)" ] || fail "thin: git tree not clean"

# Overlay repo (LOCAL rule) — per-item symlinks, local kept, commit mode (no excludes).
mkdir -p "$TMP/overlay/.claude/rules"; git -C "$TMP/overlay" init -q
echo "LOCAL" > "$TMP/overlay/.claude/rules/labels.md"
"$SCRIPT" "$TMP/overlay" --mode=commit
[ "$(cat "$TMP/overlay/.claude/rules/labels.md")" = "LOCAL" ] || fail "overlay: local rule clobbered"
[ -L "$TMP/overlay/.claude/hooks/destructive-commands.sh" ] || fail "overlay: global hook not per-item linked"
[ "$(readlink "$TMP/overlay/.claude/hooks/destructive-commands.sh")" = "../../../dev-tooling/hooks/destructive-commands.sh" ] || fail "overlay: per-item target wrong"
[ ! -e "$TMP/overlay/.claude/skills" ] || fail "overlay: skills should NOT be wired"
! grep -qsxF ".claude/hooks/destructive-commands.sh" "$TMP/overlay/.git/info/exclude" || fail "overlay: commit mode should not exclude"

# Carry-forward: exclude-mode whole-dir hooks symlink → commit-mode per-item conversion; Master untouched.
mkdir -p "$TMP/convert"; git -C "$TMP/convert" init -q
"$SCRIPT" "$TMP/convert"
[ -L "$TMP/convert/.claude/hooks" ] || fail "convert: expected whole-dir hooks symlink after exclude run"
"$SCRIPT" "$TMP/convert" --mode=commit
[ ! -L "$TMP/convert/.claude/hooks" ] || fail "convert: .claude/hooks should no longer be a whole-dir symlink"
[ -L "$TMP/convert/.claude/hooks/destructive-commands.sh" ] || fail "convert: per-item link missing"
[ "$(ls "$TMP/dev-tooling/hooks" | wc -l | tr -d ' ')" = "1" ] || fail "convert: Master hooks dir was mutated"

# Idempotency.
"$SCRIPT" "$TMP/thin"
"$SCRIPT" "$TMP/overlay" --mode=commit
echo "ALL PASS"
