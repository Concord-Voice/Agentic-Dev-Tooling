#!/usr/bin/env bash
# Test harness for sync-shared.sh — temp Master + consumer; asserts shared items are
# copied as REAL files, local overlays (not in the manifest) are untouched, idempotent.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/sync-shared.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Fake Master: one SHARED skill (ci-status) + one NON-shared/overlay skill (dev-lifecycle) + a shared agent.
mkdir -p "$TMP/master"/{skills/ci-status,skills/dev-lifecycle,agents}
echo "SHARED-ci"  > "$TMP/master/skills/ci-status/SKILL.md"
echo "GENERIC-dl" > "$TMP/master/skills/dev-lifecycle/SKILL.md"
echo "SHARED-cr"  > "$TMP/master/agents/code-reviewer.md"
cat > "$TMP/master/shared-manifest.json" <<'JSON'
{ "shared_skills": ["ci-status"], "shared_agents": ["code-reviewer"] }
JSON

# Consumer: a LOCAL overlay skill (dev-lifecycle, richer) + a stale SYMLINK for the shared ci-status.
mkdir -p "$TMP/consumer/.claude/skills/dev-lifecycle"; git -C "$TMP/consumer" init -q
echo "LOCAL-dl" > "$TMP/consumer/.claude/skills/dev-lifecycle/SKILL.md"
ln -s "../../../master/skills/ci-status" "$TMP/consumer/.claude/skills/ci-status"

SHARED_MASTER="$TMP/master" "$SCRIPT" "$TMP/consumer" >/dev/null

# Internal checkouts also contain a public mirror; their root manifest wins.
mkdir -p "$TMP/master/config"
printf '{"shared_skills":["missing-public-mirror"],"shared_agents":[]}\n' > "$TMP/master/config/shared-manifest.json"
SHARED_MASTER="$TMP/master" "$SCRIPT" "$TMP/consumer" >/dev/null || fail "Internal manifest did not take precedence"

# Shared skill: now a REAL dir (not a symlink) with the Master's content.
[ -d "$TMP/consumer/.claude/skills/ci-status" ] && [ ! -L "$TMP/consumer/.claude/skills/ci-status" ] || fail "ci-status should be a real dir"
[ "$(cat "$TMP/consumer/.claude/skills/ci-status/SKILL.md")" = "SHARED-ci" ] || fail "ci-status content not synced from Master"
# Shared agent: real file with Master content.
[ -f "$TMP/consumer/.claude/agents/code-reviewer.md" ] && [ ! -L "$TMP/consumer/.claude/agents/code-reviewer.md" ] || fail "code-reviewer should be a real file"
[ "$(cat "$TMP/consumer/.claude/agents/code-reviewer.md")" = "SHARED-cr" ] || fail "code-reviewer content not synced"
# Local overlay (NOT in manifest): untouched.
[ "$(cat "$TMP/consumer/.claude/skills/dev-lifecycle/SKILL.md")" = "LOCAL-dl" ] || fail "local overlay dev-lifecycle was clobbered"

# Master must not be mutated (no write-through a former symlink).
[ "$(cat "$TMP/master/skills/ci-status/SKILL.md")" = "SHARED-ci" ] || fail "Master ci-status was mutated"

# Local edits must not be mistaken for stale managed copies.
echo "DRIFTED" > "$TMP/consumer/.claude/skills/ci-status/SKILL.md"
if SHARED_MASTER="$TMP/master" "$SCRIPT" "$TMP/consumer" >/dev/null 2>&1; then fail "local customization should block synchronization"; fi
[[ "$(cat "$TMP/consumer/.claude/skills/ci-status/SKILL.md")" = "DRIFTED" ]] || fail "local customization was overwritten"
# A verified managed copy can adopt a newer Master revision automatically.
echo "SHARED-ci" > "$TMP/consumer/.claude/skills/ci-status/SKILL.md"
echo "SHARED-ci-v2" > "$TMP/master/skills/ci-status/SKILL.md"
SHARED_MASTER="$TMP/master" "$SCRIPT" "$TMP/consumer" >/dev/null
[ "$(cat "$TMP/consumer/.claude/skills/ci-status/SKILL.md")" = "SHARED-ci-v2" ] || fail "managed copy did not advance"

# Whole-dir category links can expose additional local skills, so do not remove them.
rm -rf "$TMP/consumer/.claude/skills"
ln -s "../../master/skills" "$TMP/consumer/.claude/skills"
if SHARED_MASTER="$TMP/master" "$SCRIPT" "$TMP/consumer" >/dev/null 2>&1; then fail "whole-directory link requires migration"; fi
[[ -d "$TMP/master/skills/ci-status" ]] && [[ "$(cat "$TMP/master/skills/ci-status/SKILL.md")" = "SHARED-ci-v2" ]] || fail "Master skills/ci-status destroyed via whole-dir symlink"
[[ -L "$TMP/consumer/.claude/skills" ]] && [[ -d "$TMP/consumer/.claude/skills/dev-lifecycle" ]] || fail "whole-directory link or its extra skills were removed"
rm "$TMP/consumer/.claude/skills"
mkdir "$TMP/consumer/.claude/skills"
SHARED_MASTER="$TMP/master" "$SCRIPT" "$TMP/consumer" >/dev/null

# An explicit reservation wins even when the installer has a managed copy.
printf '{"paths":[".claude/skills/ci-status/SKILL.md"]}\n' > "$TMP/consumer/.claude/agentic-protected-paths.json"
echo "CUSTOM" > "$TMP/consumer/.claude/skills/ci-status/SKILL.md"
SHARED_MASTER="$TMP/master" "$SCRIPT" "$TMP/consumer" >/dev/null
[[ "$(cat "$TMP/consumer/.claude/skills/ci-status/SKILL.md")" = CUSTOM ]] || fail "protected descendant was overwritten"
rm "$TMP/consumer/.claude/agentic-protected-paths.json"

# Unowned links must survive; no later item may be changed on a failed preflight.
rm -rf "$TMP/consumer/.claude/skills/ci-status"
mkdir -p "$TMP/foreign"; echo foreign > "$TMP/foreign/SKILL.md"
ln -s "$TMP/foreign" "$TMP/consumer/.claude/skills/ci-status"
echo "new agent" > "$TMP/master/agents/code-reviewer.md"
if SHARED_MASTER="$TMP/master" "$SCRIPT" "$TMP/consumer" >/dev/null 2>&1; then fail "foreign symlink should block synchronization"; fi
[[ -L "$TMP/consumer/.claude/skills/ci-status" ]] && [[ "$(cat "$TMP/foreign/SKILL.md")" = foreign ]] || fail "foreign symlink was changed"
[[ "$(cat "$TMP/consumer/.claude/agents/code-reviewer.md")" = SHARED-cr ]] || fail "preflight did not prevent partial update"

# A ledger that Git will ignore cannot protect the next clone or CI checkout.
ignored="$TMP/ignored"; mkdir -p "$ignored"; git -C "$ignored" init -q
printf '.claude/*\n' > "$ignored/.gitignore"
if SHARED_MASTER="$TMP/master" "$SCRIPT" "$ignored" >/dev/null 2>&1; then fail "ignored provenance ledger should block synchronization"; fi
[[ ! -e "$ignored/.claude/skills/ci-status" ]] || fail "ignored ledger led to a partial sync"

# Malformed manifest → fail loudly (no silent success).
badm="$TMP/badm"; mkdir -p "$badm/skills/ci-status"; echo "x" > "$badm/skills/ci-status/SKILL.md"
echo "{ not valid json" > "$badm/shared-manifest.json"
if SHARED_MASTER="$badm" "$SCRIPT" "$TMP/consumer" >/dev/null 2>&1; then fail "malformed manifest should fail"; fi

# Manifest entry absent from the Master → fail loudly (canonical manifest must be correct).
miss="$TMP/missm"; mkdir -p "$miss/skills/ci-status"; echo "x" > "$miss/skills/ci-status/SKILL.md"
printf '{"shared_skills":["ci-status","does-not-exist"],"shared_agents":[]}\n' > "$miss/shared-manifest.json"
if SHARED_MASTER="$miss" "$SCRIPT" "$TMP/consumer" >/dev/null 2>&1; then fail "missing-in-Master manifest entry should fail"; fi

# Bad shape (shared_skills not an array) → fail.
shp="$TMP/shp"; mkdir -p "$shp/skills/ci-status"; echo "x" > "$shp/skills/ci-status/SKILL.md"
printf '{"shared_skills":"ci-status","shared_agents":[]}\n' > "$shp/shared-manifest.json"
if SHARED_MASTER="$shp" "$SCRIPT" "$TMP/consumer" >/dev/null 2>&1; then fail "non-array shared_skills should fail"; fi

# Path-traversal entry name → fail before any copy (must not escape the consumer dir).
trav="$TMP/trav"; mkdir -p "$trav/skills/ci-status"; echo "x" > "$trav/skills/ci-status/SKILL.md"
printf '{"shared_skills":["../../etc"],"shared_agents":[]}\n' > "$trav/shared-manifest.json"
if SHARED_MASTER="$trav" "$SCRIPT" "$TMP/consumer" >/dev/null 2>&1; then fail "path-traversal manifest entry should fail"; fi

# ---- PATH-FORM entries (the current layout: content lives under plugins/*/skills and
# plugins/*/agents, not <master>/skills). The entry is used AS GIVEN to find the source; the
# consumer still receives it FLAT at .claude/<cat>/<basename>. The bare-name cases above stay
# in place: both forms must keep resolving (legacy Masters still use bare names).
pm="$TMP/pathmaster"
mkdir -p "$pm/plugins/core-lifecycle/skills/ci-status" "$pm/plugins/core-lifecycle/agents"
echo "PATH-ci" > "$pm/plugins/core-lifecycle/skills/ci-status/SKILL.md"
echo "PATH-cr" > "$pm/plugins/core-lifecycle/agents/code-reviewer.md"
printf '{"shared_skills":["plugins/core-lifecycle/skills/ci-status"],"shared_agents":["plugins/core-lifecycle/agents/code-reviewer"]}\n' > "$pm/shared-manifest.json"
pc="$TMP/pathconsumer"; mkdir -p "$pc"; git -C "$pc" init -q
SHARED_MASTER="$pm" "$SCRIPT" "$pc" >/dev/null
[ "$(cat "$pc/.claude/skills/ci-status/SKILL.md")" = "PATH-ci" ] || fail "path-form skill entry did not sync flat to .claude/skills/<basename>"
[ "$(cat "$pc/.claude/agents/code-reviewer.md")" = "PATH-cr" ] || fail "path-form agent entry did not sync flat to .claude/agents/<basename>.md"
[ ! -e "$pc/.claude/skills/plugins" ] || fail "path-form entry recreated its Master directory tree inside the consumer"

# Path-form entry absent from the Master → still fails loudly (canonical-manifest rule).
pmiss="$TMP/pathmiss"; mkdir -p "$pmiss/plugins/core-lifecycle/skills/ci-status"
echo "x" > "$pmiss/plugins/core-lifecycle/skills/ci-status/SKILL.md"
printf '{"shared_skills":["plugins/core-lifecycle/skills/nope"],"shared_agents":[]}\n' > "$pmiss/shared-manifest.json"
if SHARED_MASTER="$pmiss" "$SCRIPT" "$pc" >/dev/null 2>&1; then fail "missing path-form entry should fail"; fi

# Traversal INSIDE a path entry → rejected before any copy (slashes are legal now, `..` is not).
ptrav="$TMP/pathtrav"; mkdir -p "$ptrav/plugins/x/skills/y"; echo "x" > "$ptrav/plugins/x/skills/y/SKILL.md"
printf '{"shared_skills":["plugins/../../etc"],"shared_agents":[]}\n' > "$ptrav/shared-manifest.json"
if SHARED_MASTER="$ptrav" "$SCRIPT" "$pc" >/dev/null 2>&1; then fail "path-traversal inside a path-form entry should fail"; fi

# ---- Real-repo smoke: the SHIPPED config/shared-manifest.json must resolve against this
# Master. Regression: entries were resolved as <master>/skills/<name> while the content
# actually lives at plugins/*/skills/<name>, so every real invocation died in pre-flight.
real="$TMP/realconsumer"; mkdir -p "$real"; git -C "$real" init -q
if "$SCRIPT" "$real" >"$TMP/real-output" 2>&1; then
  [ -f "$real/.claude/skills/ci-status/SKILL.md" ] || fail "real manifest did not deliver skills/ci-status"
  [ -f "$real/.claude/skills/ste-writing/SKILL.md" ] || fail "real manifest did not deliver skills/ste-writing (cross-plugin entry)"
  [ -f "$real/.claude/agents/code-reviewer.md" ] || fail "real manifest did not deliver agents/code-reviewer.md"
else
  # An Internal mirror being reconciled must refuse the whole copy, not ship stale overrides.
  [[ -f "$HERE/../.github/skill-overrides.lock.json" ]] || fail "the repo's own shared-manifest.json failed to sync"
  grep -q 'requires reconciliation' "$TMP/real-output" || fail "real sync failed for a reason other than pending reconciliation"
  [[ ! -e "$real/.claude/skills/ci-status" ]] || fail "stale override caused a partial real sync"
fi

echo "ALL PASS"
