#!/usr/bin/env bash
# Test harness for new-repo.sh — builds a temp org layout and asserts onboarding behavior:
# rules/hooks/settings symlinked (setup-symlinks), skills/agents copied as REAL files
# (sync-shared), and repo-config.json seeded.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/new-repo.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Fake Master with one item per category + a shared-manifest declaring the shared skill/agent.
mkdir -p "$TMP/dev-tooling"/{skills/ci-status,agents,rules,hooks,settings}
echo "skill" > "$TMP/dev-tooling/skills/ci-status/SKILL.md"
echo "agent" > "$TMP/dev-tooling/agents/code-reviewer.md"
echo "rule"  > "$TMP/dev-tooling/rules/labels.md"
echo "hook"  > "$TMP/dev-tooling/hooks/destructive-commands.sh"
echo "{}"    > "$TMP/dev-tooling/settings/base.settings.json"
printf '{"shared_skills":["ci-status"],"shared_agents":["code-reviewer"]}\n' > "$TMP/dev-tooling/shared-manifest.json"

# Target repo: a fresh git repo that is a sibling of dev-tooling.
mkdir -p "$TMP/newrepo"; git -C "$TMP/newrepo" init -q

# --- Test 1: wiring (symlinks for hooks/rules/settings, REAL copies for skills/agents) + repo-config seed ---
"$SCRIPT" "$TMP/newrepo"

# Symlink-safe categories are symlinked.
[ -L "$TMP/newrepo/.claude/hooks" ]   || fail "T1: .claude/hooks not a symlink"
[ -L "$TMP/newrepo/.claude/rules" ]   || fail "T1: .claude/rules not a symlink"
[ -L "$TMP/newrepo/.claude/settings.json" ] || fail "T1: .claude/settings.json not a symlink"

# Skills/agents are REAL copies (not symlinks), with the Master's content.
[ -d "$TMP/newrepo/.claude/skills/ci-status" ] && [ ! -L "$TMP/newrepo/.claude/skills/ci-status" ] || fail "T1: skills/ci-status should be a real dir (sync-shared)"
[ "$(cat "$TMP/newrepo/.claude/skills/ci-status/SKILL.md")" = "skill" ] || fail "T1: ci-status content not copied"
[ -f "$TMP/newrepo/.claude/agents/code-reviewer.md" ] && [ ! -L "$TMP/newrepo/.claude/agents/code-reviewer.md" ] || fail "T1: agents/code-reviewer.md should be a real file (sync-shared)"

# repo-config.json seeded as {}.
[ -f "$TMP/newrepo/.claude/repo-config.json" ] || fail "T1: .claude/repo-config.json not created"
jq -e '. == {}' "$TMP/newrepo/.claude/repo-config.json" > /dev/null || fail "T1: repo-config.json not equal to {}"

# --- Test 2: idempotency ---
"$SCRIPT" "$TMP/newrepo"
[ -d "$TMP/newrepo/.claude/skills/ci-status" ] && [ ! -L "$TMP/newrepo/.claude/skills/ci-status" ] || fail "T2: ci-status not a real dir after second run"
jq -e '. == {}' "$TMP/newrepo/.claude/repo-config.json" > /dev/null || fail "T2: repo-config.json changed on second run"

# --- Test 3: existing repo-config.json is NOT clobbered ---
echo '{"default_branch":"trunk"}' > "$TMP/newrepo/.claude/repo-config.json"
"$SCRIPT" "$TMP/newrepo"
jq -e '.default_branch == "trunk"' "$TMP/newrepo/.claude/repo-config.json" > /dev/null || fail "T3: existing repo-config.json was clobbered"

echo "ALL PASS"
