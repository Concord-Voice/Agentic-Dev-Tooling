#!/usr/bin/env bash
# Test harness for drift-check-shared.sh — temp Master + consumer; asserts OK when in sync,
# and DRIFT when content-divergent, symlinked, or missing.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/drift-check-shared.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/master"/{skills/ci-status,agents}
echo "M" > "$TMP/master/skills/ci-status/SKILL.md"
echo "A" > "$TMP/master/agents/code-reviewer.md"
cat > "$TMP/master/shared-manifest.json" <<'JSON'
{ "shared_skills": ["ci-status"], "shared_agents": ["code-reviewer"] }
JSON
mkdir -p "$TMP/repo"; git -C "$TMP/repo" init -q

rc() { SHARED_MASTER="$TMP/master" "$SCRIPT" "$TMP/repo" >/dev/null 2>&1; echo $?; }

# (a) In sync (real copies) → OK, exit 0.
mkdir -p "$TMP/repo/.claude/skills/ci-status" "$TMP/repo/.claude/agents"
echo "M" > "$TMP/repo/.claude/skills/ci-status/SKILL.md"
echo "A" > "$TMP/repo/.claude/agents/code-reviewer.md"
[ "$(rc)" = "0" ] || fail "in-sync should exit 0"

# (b) Content drift → exit 1.
echo "DRIFTED" > "$TMP/repo/.claude/skills/ci-status/SKILL.md"
[ "$(rc)" = "1" ] || fail "content drift should exit 1"
echo "M" > "$TMP/repo/.claude/skills/ci-status/SKILL.md"

# (c) Symlinked shared item → flagged as symlink drift, exit 1.
rm -f "$TMP/repo/.claude/agents/code-reviewer.md"
ln -s "../../../master/agents/code-reviewer.md" "$TMP/repo/.claude/agents/code-reviewer.md"
out="$(SHARED_MASTER="$TMP/master" "$SCRIPT" "$TMP/repo" 2>&1 || true)"
echo "$out" | grep -qi "symlink" || fail "symlinked shared item must be flagged as symlink drift"
[ "$(rc)" = "1" ] || fail "symlinked shared item should exit 1"
rm -f "$TMP/repo/.claude/agents/code-reviewer.md"; echo "A" > "$TMP/repo/.claude/agents/code-reviewer.md"

# (d) Missing shared item → exit 1.
rm -rf "$TMP/repo/.claude/skills/ci-status"
[ "$(rc)" = "1" ] || fail "missing shared item should exit 1"
mkdir -p "$TMP/repo/.claude/skills/ci-status"; echo "M" > "$TMP/repo/.claude/skills/ci-status/SKILL.md"

# (e) Whole-dir category symlink → flagged as drift (not a false OK from diffing Master vs itself).
rm -rf "$TMP/repo/.claude/skills"
ln -s "../../master/skills" "$TMP/repo/.claude/skills"
out="$(SHARED_MASTER="$TMP/master" "$SCRIPT" "$TMP/repo" 2>&1 || true)"
echo "$out" | grep -qi "category dir is a symlink" || fail "whole-dir symlinked category must be flagged as drift"
[ "$(rc)" = "1" ] || fail "whole-dir symlinked category should exit 1"
rm -f "$TMP/repo/.claude/skills"; mkdir -p "$TMP/repo/.claude/skills/ci-status"; echo "M" > "$TMP/repo/.claude/skills/ci-status/SKILL.md"

# (f) Malformed manifest → hard error (exit != 0), not a misleading OK.
badm="$TMP/badm"; mkdir -p "$badm/skills/ci-status"; echo "M" > "$badm/skills/ci-status/SKILL.md"; echo "{bad" > "$badm/shared-manifest.json"
if SHARED_MASTER="$badm" "$SCRIPT" "$TMP/repo" >/dev/null 2>&1; then fail "malformed manifest should fail"; fi

# (g) Manifest entry absent from the Master → hard error.
miss="$TMP/missm"; mkdir -p "$miss/skills/ci-status" "$miss/agents"; echo "M" > "$miss/skills/ci-status/SKILL.md"
printf '{"shared_skills":["ci-status","nope"],"shared_agents":[]}\n' > "$miss/shared-manifest.json"
if SHARED_MASTER="$miss" "$SCRIPT" "$TMP/repo" >/dev/null 2>&1; then fail "missing-in-Master entry should fail"; fi

# (h) Bad shape (shared_skills not an array) → hard error.
shp="$TMP/shp"; mkdir -p "$shp/skills/ci-status"; echo "M" > "$shp/skills/ci-status/SKILL.md"
printf '{"shared_skills":"ci-status","shared_agents":[]}\n' > "$shp/shared-manifest.json"
if SHARED_MASTER="$shp" "$SCRIPT" "$TMP/repo" >/dev/null 2>&1; then fail "non-array shared_skills should fail"; fi

# (i) Path-traversal entry name → hard error.
trav="$TMP/trav"; mkdir -p "$trav/skills/ci-status"; echo "M" > "$trav/skills/ci-status/SKILL.md"
printf '{"shared_skills":["../../etc"],"shared_agents":[]}\n' > "$trav/shared-manifest.json"
if SHARED_MASTER="$trav" "$SCRIPT" "$TMP/repo" >/dev/null 2>&1; then fail "path-traversal manifest entry should fail"; fi

# (j) PATH-FORM entries (current layout: plugins/*/skills, plugins/*/agents). Source is found
# at the entry path as given; the consumer copy is still compared FLAT at .claude/<cat>/<base>.
# The bare-name cases (a)-(i) above stay in place — both forms must keep resolving.
pm="$TMP/pathmaster"
mkdir -p "$pm/plugins/core-lifecycle/skills/ci-status" "$pm/plugins/core-lifecycle/agents"
echo "M" > "$pm/plugins/core-lifecycle/skills/ci-status/SKILL.md"
echo "A" > "$pm/plugins/core-lifecycle/agents/code-reviewer.md"
printf '{"shared_skills":["plugins/core-lifecycle/skills/ci-status"],"shared_agents":["plugins/core-lifecycle/agents/code-reviewer"]}\n' > "$pm/shared-manifest.json"
pr="$TMP/pathrepo"; mkdir -p "$pr/.claude/skills/ci-status" "$pr/.claude/agents"; git -C "$pr" init -q
echo "M" > "$pr/.claude/skills/ci-status/SKILL.md"
echo "A" > "$pr/.claude/agents/code-reviewer.md"
SHARED_MASTER="$pm" "$SCRIPT" "$pr" >/dev/null 2>&1 || fail "path-form entries in sync should exit 0"
echo "DRIFTED" > "$pr/.claude/skills/ci-status/SKILL.md"
if SHARED_MASTER="$pm" "$SCRIPT" "$pr" >/dev/null 2>&1; then fail "path-form content drift should exit 1"; fi

# (k) Traversal INSIDE a path entry → hard error (slashes are legal now, `..` is not).
ptrav="$TMP/pathtrav"; mkdir -p "$ptrav/plugins/x/skills/y"; echo "M" > "$ptrav/plugins/x/skills/y/SKILL.md"
printf '{"shared_skills":["plugins/../../etc"],"shared_agents":[]}\n' > "$ptrav/shared-manifest.json"
if SHARED_MASTER="$ptrav" "$SCRIPT" "$pr" >/dev/null 2>&1; then fail "path-traversal inside a path-form entry should fail"; fi

# (l) Real-repo smoke: the SHIPPED config/shared-manifest.json must resolve against this
# Master, and a freshly synced consumer must read as OK. Regression: entries resolved as
# <master>/skills/<name> while content lives at plugins/*/skills/<name>.
realrepo="$TMP/realrepo"; mkdir -p "$realrepo"; git -C "$realrepo" init -q
"$HERE/sync-shared.sh" "$realrepo" >/dev/null || fail "sync of the repo's own manifest failed"
"$SCRIPT" "$realrepo" >/dev/null 2>&1 || fail "drift-check of a freshly synced consumer should exit 0"

echo "ALL PASS"
