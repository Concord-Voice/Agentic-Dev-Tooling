#!/usr/bin/env bash
# Test harness for install.sh — claude path + doctor.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

# No args -> usage message on stderr, exit 2.
set +e
out="$("$HERE/install.sh" 2>&1)"; rc=$?
set -e
[ "$rc" = 2 ] || fail "no-args should exit 2, got $rc"
printf '%s\n' "$out" | grep -q "^usage:" || fail "no-args should print a usage line"

# --user is only meaningful for the claude subcommand (it targets $HOME/.claude); none of the
# rulesync-compiled platforms have a user-scope target, so --user there must fail fast rather
# than silently install somewhere nothing reads from.
set +e
out="$("$HERE/install.sh" codex --user 2>&1)"; rc=$?
set -e
[ "$rc" = 2 ] || fail "codex --user should exit 2, got $rc"
printf '%s\n' "$out" | grep -qF -- "--user is only supported for the claude subcommand" || \
  fail "codex --user did not print the expected fail-fast message"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q

"$HERE/install.sh" claude --project "$tmp"

[ -f "$tmp/scripts/repo-config.sh" ] || fail "repo-config.sh not installed"
[ -f "$tmp/.claude/repo-config.reference.md" ] || fail "repo-config.reference.md not installed"
[ -f "$tmp/.claude/repo-config.example.json" ] || fail "repo-config.example.json not installed"
[ -d "$tmp/.claude/skills/dev-lifecycle" ] || fail "skills not installed"
[ -d "$tmp/.claude/agents" ] || fail "agents not installed"
jq -e '.hooks | length > 0' "$tmp/.claude/settings.json" >/dev/null || fail "hooks not wired"
[ ! -d "$tmp/.claude/skills/supervise" ] || fail "fleet installed without --with-fleet"
[ -f "$tmp/.claude/skills/verify-quality-gate/SKILL.md" ] || fail "verify-quality-gate skill not installed"

# Upstream updates reach files the adopter never touched; hand-edited ones are kept.
up="$tmp/upstream"; mkdir -p "$up"; cp -R "$HERE/install.sh" "$HERE/plugins" "$HERE/config" "$HERE/scripts" "$HERE/docs" "$up/"
proj="$tmp/locked"; git -C "$tmp" init -q "$proj" 2>/dev/null || git init -q "$proj"
"$up/install.sh" claude --project "$proj" >/dev/null
[ -f "$proj/.claude/.agentic-dev-tooling.lock" ] || fail "install did not write its lock"
echo "UPSTREAM-v2" >> "$up/plugins/core-lifecycle/skills/ci-status/SKILL.md"
"$up/install.sh" claude --project "$proj" >/dev/null
grep -q UPSTREAM-v2 "$proj/.claude/skills/ci-status/SKILL.md" || fail "upstream update did not reach an untouched install"
echo "LOCAL-EDIT" >> "$proj/.claude/skills/ci-status/SKILL.md"
echo "UPSTREAM-v3" >> "$up/plugins/core-lifecycle/skills/ci-status/SKILL.md"
"$up/install.sh" claude --project "$proj" >/dev/null
grep -q LOCAL-EDIT "$proj/.claude/skills/ci-status/SKILL.md" || fail "hand-edited install was overwritten"
if grep -q UPSTREAM-v3 "$proj/.claude/skills/ci-status/SKILL.md"; then fail "hand-edited install took the upstream change"; fi
# A symlink the adopter added is a local change too, so the next update must not delete it.
ln -s SKILL.md "$proj/.claude/skills/pr-creation/local-notes"
echo "UPSTREAM-v2" >> "$up/plugins/core-lifecycle/skills/pr-creation/SKILL.md"
"$up/install.sh" claude --project "$proj" >/dev/null
[ -L "$proj/.claude/skills/pr-creation/local-notes" ] || fail "upstream update deleted an adopter-added symlink"

# I9: the path-scoped rules docs must land at .claude/rules/<name>.md -- that is the path
# skills and agents cite ("see .claude/rules/labels.md"), so a missing install makes every
# one of those references dangle.
[ -d "$tmp/.claude/rules" ] || fail "docs/rules not installed to .claude/rules/"
for r in "$HERE/docs/rules"/*.md; do
  [ -f "$tmp/.claude/rules/$(basename "$r")" ] || fail "rules doc not installed: $(basename "$r")"
done

# I5: both previously-orphaned hooks must be wired, not just shipped as files. They existed
# in plugins/guardrails/hooks/ but no settings entry ever invoked them.
wired="$(jq -r '[.hooks[][].hooks[].command] | .[]' "$tmp/.claude/settings.json")"
printf '%s\n' "$wired" | grep -qx ".claude/hooks/issue-creation-nudge.sh" \
  || fail "issue-creation-nudge.sh is installed but not wired (UserPromptSubmit)"
printf '%s\n' "$wired" | grep -qx ".claude/hooks/protect-applied-migrations.sh" \
  || fail "protect-applied-migrations.sh is installed but not wired (PreToolUse Edit)"
jq -e '[.hooks.UserPromptSubmit[].hooks[].command] | index(".claude/hooks/issue-creation-nudge.sh") != null' \
  "$tmp/.claude/settings.json" >/dev/null || fail "issue-creation-nudge.sh wired to the wrong event"
jq -e '[.hooks.PreToolUse[] | select(.matcher | test("Edit")) | .hooks[].command] | index(".claude/hooks/protect-applied-migrations.sh") != null' \
  "$tmp/.claude/settings.json" >/dev/null || fail "protect-applied-migrations.sh wired without an Edit matcher"

# I6a: the marketplace route registers hooks from each plugin's own hooks/hooks.json, not
# from settings.json. Every command there must name a script that ships in the same plugin.
for pj in "$HERE/plugins"/*/hooks/hooks.json; do
  [ -e "$pj" ] || continue
  jq -e '.hooks | length > 0' "$pj" >/dev/null || fail "$pj declares no hook events"
  while IFS= read -r cmd; do
    script="${cmd##*/}"; script="${script%\"}"
    [ -f "$(dirname "$pj")/$script" ] || fail "$pj references a missing script: $script"
  done < <(jq -r '[.hooks[][].hooks[].command] | .[]' "$pj")
done

# Skill hygiene: scaffold-* dirs hold only SKILL.md.template (no real SKILL.md) and must be
# skipped by the installer. _shared has no SKILL.md either but IS a real dependency (several
# skills reference it via relative links, e.g. dev-lifecycle -> ../_shared/dispatchable-skills.md)
# so it must still be installed.
[ ! -d "$tmp/.claude/skills/scaffold-component" ] || fail "scaffold-component (template-only) should not be installed"
[ ! -d "$tmp/.claude/skills/scaffold-endpoint" ] || fail "scaffold-endpoint (template-only) should not be installed"
[ -d "$tmp/.claude/skills/_shared" ] || fail "_shared (real skill dependency, no SKILL.md) should still be installed"
[ -f "$tmp/.claude/skills/_shared/dispatchable-skills.md" ] || fail "_shared contents missing"

# Wired hook commands must resolve to a script that actually exists at the installed location
# (root/.claude/hooks/<name>.sh) -- not a stale $CLAUDE_PROJECT_DIR/hooks/... path.
hookcmds="$(jq -r '[.hooks[][].hooks[].command] | .[]' "$tmp/.claude/settings.json")"
printf '%s\n' "$hookcmds" | grep -q 'CLAUDE_PROJECT_DIR/hooks/' && fail "hook command still points at an unadapted \$CLAUDE_PROJECT_DIR/hooks/ path"
while IFS= read -r cmd; do
  case "$cmd" in
    .claude/hooks/*)
      script="${cmd#.claude/hooks/}"
      [ -f "$tmp/.claude/hooks/$script" ] || fail "wired hook command has no installed script: $cmd"
      ;;
    *) fail "unexpected hook command shape: $cmd" ;;
  esac
done <<EOF
$hookcmds
EOF

hooks_before="$(jq -c '.hooks' "$tmp/.claude/settings.json")"
pretooluse_before="$(jq '.hooks.PreToolUse | length' "$tmp/.claude/settings.json")"

# Idempotency: re-running claude install must not error and must not duplicate hook entries.
"$HERE/install.sh" claude --project "$tmp"

hooks_after="$(jq -c '.hooks' "$tmp/.claude/settings.json")"
pretooluse_after="$(jq '.hooks.PreToolUse | length' "$tmp/.claude/settings.json")"
[ "$hooks_before" = "$hooks_after" ] || fail "re-running install.sh claude changed hook wiring"
[ "$pretooluse_before" = "$pretooluse_after" ] || fail "re-running install.sh claude duplicated PreToolUse hook entries ($pretooluse_before -> $pretooluse_after)"

# copy() must never run `cp -R` against an existing destination directory (GNU/coreutils cp
# nests the source inside it there, unlike BSD cp with a trailing-slash source -- reproduced on
# coreutils 9.11). After two installs onto the same target, dev-lifecycle must not contain a
# nested copy of itself, and its SKILL.md must still be directly at depth 1.
nested="$(find "$tmp/.claude/skills/dev-lifecycle" -mindepth 1 -maxdepth 1 -name dev-lifecycle)"
[ -z "$nested" ] || fail "copy() nested dev-lifecycle into itself: $nested"
[ -f "$tmp/.claude/skills/dev-lifecycle/SKILL.md" ] || fail "SKILL.md missing at depth 1 after re-run (nested copy?)"

doctor_out="$("$HERE/install.sh" doctor)" || fail "doctor errored"
printf '%s\n' "$doctor_out" | grep -q "^ok: git" || fail "doctor did not report git as ok"
printf '%s\n' "$doctor_out" | grep -q "^ok: jq" || fail "doctor did not report jq as ok"
printf '%s\n' "$doctor_out" | grep -qE "^(ok|warn): gh" || fail "doctor did not report gh ok/warn"

# CRITICAL 1 regression: jq's `*` deep-merge replaces (doesn't union) array-valued keys, so a
# naive merge would silently drop every adopter-authored hook the moment they had ANY existing
# hooks.PreToolUse entry. Pre-seed a target with one custom hook and confirm install unions
# rather than clobbers: both the custom hook and destructive-commands.sh must survive.
custom_target="$tmp/custom-hooks-target"
mkdir -p "$custom_target/.claude"; git -C "$custom_target" init -q
cat > "$custom_target/.claude/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"my-custom-hook.sh"}]}]}}
JSON
"$HERE/install.sh" claude --project "$custom_target" >/dev/null
merged_cmds="$(jq -r '[.hooks.PreToolUse[].hooks[].command] | .[]' "$custom_target/.claude/settings.json")"
printf '%s\n' "$merged_cmds" | grep -qx "my-custom-hook.sh" || fail "adopter's pre-existing custom hook was dropped by the merge"
printf '%s\n' "$merged_cmds" | grep -qx ".claude/hooks/destructive-commands.sh" || fail "base guardrail hook was dropped by the merge"

# IMPORTANT 3: --user scope hook commands must be absolute, not the relative ".claude/hooks/..."
# form used for --project -- a relative command in ~/.claude/settings.json resolves against
# whatever project is active at hook-run time, not $HOME, so it would be inert. Override HOME to
# a throwaway dir for this check; never touch the real $HOME.
fake_home="$tmp/fake-home"; mkdir -p "$fake_home"
user_out="$(HOME="$fake_home" "$HERE/install.sh" claude --user)"

# m14: --user must NOT install the project-level pieces. `$HOME/scripts/repo-config.sh` is
# never resolved (skills source it as a repo-relative path), and $HOME/.claude/rules would
# apply one repo's path scoping to every repo. Both are skipped, with a note saying so.
[ ! -f "$fake_home/scripts/repo-config.sh" ] || fail "--user installed scripts/repo-config.sh into \$HOME (never resolved there)"
[ ! -d "$fake_home/.claude/rules" ] || fail "--user installed .claude/rules into \$HOME (project-scoped rules)"
printf '%s\n' "$user_out" | grep -q "user scope skips" || fail "--user did not disclose the skipped project-level copies"
# The user-scope pieces that DO make sense still install.
[ -f "$fake_home/.claude/repo-config.reference.md" ] || fail "--user should still install the repo-config reference"
[ -d "$fake_home/.claude/skills/dev-lifecycle" ] || fail "--user should still install skills"

user_hookcmds="$(jq -r '[.hooks[][].hooks[].command] | .[]' "$fake_home/.claude/settings.json")"
while IFS= read -r cmd; do
  case "$cmd" in
    "$fake_home"/.claude/hooks/*) [ -f "$cmd" ] || fail "--user hook command points at a nonexistent script: $cmd" ;;
    .claude/hooks/*) fail "--user scope left a relative hook command (inert outside \$HOME's active-project cwd): $cmd" ;;
    *) fail "unexpected --user hook command shape: $cmd" ;;
  esac
done <<EOF
$user_hookcmds
EOF
# A second --user run must not duplicate hooks (earlier commands are absolute, base ones relative).
n1="$(jq '[.hooks[][].hooks[]] | length' "$fake_home/.claude/settings.json")"
HOME="$fake_home" "$HERE/install.sh" claude --user >/dev/null
n2="$(jq '[.hooks[][].hooks[]] | length' "$fake_home/.claude/settings.json")"
[ "$n1" = "$n2" ] || fail "--user re-run duplicated hooks ($n1 -> $n2)"

# IMPORTANT 4: --with-fleet positive path -- a fresh target should get the fleet skill/hook and
# the session-management MCP note (the earlier test only checked fleet is ABSENT without the flag).
fleet_target="$tmp/fleet-target"; mkdir -p "$fleet_target"; git -C "$fleet_target" init -q
fleet_out="$("$HERE/install.sh" claude --project "$fleet_target" --with-fleet)"
[ -d "$fleet_target/.claude/skills/supervise" ] || fail "--with-fleet did not install skills/supervise"
[ -f "$fleet_target/.claude/hooks/session-handshake.sh" ] || fail "--with-fleet did not install hooks/session-handshake.sh"
printf '%s\n' "$fleet_out" | grep -q "mcp__ccd_session_mgmt" || fail "--with-fleet output missing the session-management MCP note"

echo ok
