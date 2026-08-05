#!/usr/bin/env bash
# sync-shared.sh — copy the dev-tooling Master's shared-as-is skills/agents into a consumer
# repo as REAL files.
#
# Why copies (not symlinks): Claude Code's skill/agent discovery walks REAL directories and
# does NOT follow symlinks, so a symlinked .claude/skills/<name> or .claude/agents/<name>.md
# is never discovered. Hooks are different — they're invoked by path, so they stay symlinked
# (see setup-symlinks.sh). The shared set is declared in shared-manifest.json; consumer-local
# items (Bucket B/C overlays, rules, anything not in the manifest) are never touched.
#
# Usage: sync-shared.sh <consumer-repo-path>
# Test seam: SHARED_MASTER overrides the Master root (default = the repo this script lives in).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MASTER="${SHARED_MASTER:-$(cd "$HERE/.." && pwd)}"
# The manifest lives under config/ (org reorg); fall back to the pre-reorg root location so
# an older or externally-supplied Master checkout still resolves.
MANIFEST="$MASTER/config/shared-manifest.json"
[ -f "$MANIFEST" ] || MANIFEST="$MASTER/shared-manifest.json"
die() { echo "sync-shared: $*" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || die "jq required"
[ -f "$MANIFEST" ] || die "manifest not found: $MANIFEST"
jq empty "$MANIFEST" 2>/dev/null || die "manifest is not valid JSON: $MANIFEST"
# Validate shape: shared_skills/shared_agents must be arrays of strings (not just valid JSON).
jq -e '((.shared_skills // []) | type=="array") and ((.shared_agents // []) | type=="array") and ([(.shared_skills // [])[], (.shared_agents // [])[]] | all(type=="string"))' "$MANIFEST" >/dev/null 2>&1 \
  || die "manifest: shared_skills and shared_agents must be arrays of strings"
# Validate entry names. Entries are repo-relative PATHS into the Master, so `/` is allowed —
# but every segment must be a plain name: no `..`, no `.`, no empty segment, no absolute path.
# Defense in depth even though the manifest is trusted: the basename becomes a consumer path.
unsafe="$(jq -r '[.shared_skills[]?, .shared_agents[]?] | map(select(
    (test("^[A-Za-z0-9._/-]+$") | not)
    or startswith("/")
    or (split("/") | any(. == "" or . == "." or . == ".."))
  )) | .[]?' "$MANIFEST")"
[ -z "$unsafe" ] || die "unsafe manifest entry name(s) (segments must match ^[A-Za-z0-9._-]+\$, no . or .. or absolute paths): $unsafe"

# Resolve a manifest entry to its source path in the Master.
# Entries are repo-relative paths (e.g. "plugins/core-lifecycle/skills/ci-status") since
# skills/agents moved under plugins/. COMPATIBILITY: a bare name with no slash still resolves
# against the pre-plugins layout (<master>/skills/<name>, <master>/agents/<name>.md), so an
# older or externally-supplied Master checkout — and the manifests consumers already have —
# keep working unchanged.
resolve_src() { # resolve_src <category> <manifest-entry> <suffix>
  case "$2" in
    */*) printf '%s' "$MASTER/$2$3" ;;
    *)   printf '%s' "$MASTER/$1/$2$3" ;;
  esac
}

REPO="${1:-}"; [ -n "$REPO" ] || die "usage: sync-shared.sh <consumer-repo-path>"
REPO="$(cd "$REPO" 2>/dev/null && pwd)" || die "consumer repo not found: ${1}"
{ [ -d "$REPO/.git" ] || [ -f "$REPO/.git" ]; } || die "$REPO is not a git repo"

# Pre-flight: the manifest is canonical, so every entry MUST exist in the Master. Fail loudly
# (before mutating the consumer) rather than silently leaving the consumer incomplete.
missing=""
while IFS= read -r e; do [ -n "$e" ] && { [ -e "$(resolve_src skills "$e" "")" ]    || missing="$missing skills:$e"; }; done \
  < <(jq -r '.shared_skills[]?' "$MANIFEST")
while IFS= read -r e; do [ -n "$e" ] && { [ -e "$(resolve_src agents "$e" ".md")" ] || missing="$missing agents:$e"; }; done \
  < <(jq -r '.shared_agents[]?' "$MANIFEST")
[ -z "$missing" ] || die "manifest entries not found in Master (fix shared-manifest.json):$missing"

# Pre-migration safety: if a category dir is itself a whole-dir symlink into the Master (the old
# thin-repo wiring), drop the symlink FIRST. Otherwise the per-item rm -rf / cp below would
# resolve *through* it and delete/overwrite the Master's real content. (setup-symlinks.sh has the
# same guard for its per-item linking; sync-shared must replicate it.)
for cat in skills agents; do
  if [ -L "$REPO/.claude/$cat" ]; then echo "  removed pre-migration whole-dir symlink: .claude/$cat"; rm -f "$REPO/.claude/$cat"; fi
done

sync_one() { # sync_one <category> <manifest-entry> <suffix>
  local cat="$1" entry="$2" suf="$3" src name dst
  src="$(resolve_src "$cat" "$entry" "$suf")"
  # The consumer layout is always FLAT — .claude/skills/<name> / .claude/agents/<name>.md —
  # regardless of how deep the entry sits in the Master, because that is where Claude Code's
  # loader looks. So only the basename carries over.
  name="$(basename "$entry")$suf"
  dst="$REPO/.claude/$cat/$name"
  mkdir -p "$REPO/.claude/$cat"
  rm -rf "$dst"          # drop any prior per-item symlink or stale copy (rm of a symlink leaves its target intact)
  cp -a "$src" "$dst"
  echo "  synced $cat/$name"
}

echo "sync-shared: Master=$MASTER -> consumer=$REPO"
while IFS= read -r s; do [ -n "$s" ] && sync_one skills "$s" "";    done < <(jq -r '.shared_skills[]?' "$MANIFEST")
while IFS= read -r a; do [ -n "$a" ] && sync_one agents "$a" ".md"; done < <(jq -r '.shared_agents[]?' "$MANIFEST")
echo "sync-shared: done."
