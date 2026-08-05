#!/usr/bin/env bash
# drift-check-shared.sh — verify a consumer's COPIES of the Master's shared skills/agents
# still match the Master. Because they're copies (Claude Code can't load symlinked skills),
# they can drift; this flags any that are missing, symlinked (won't load), or content-divergent.
# Usage: drift-check-shared.sh <consumer-repo-path>
# Test seam: SHARED_MASTER overrides the Master root (default = the repo this script lives in).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MASTER="${SHARED_MASTER:-$(cd "$HERE/.." && pwd)}"
# The manifest lives under config/ (org reorg); fall back to the pre-reorg root location so
# an older or externally-supplied Master checkout still resolves.
MANIFEST="$MASTER/config/shared-manifest.json"
[ -f "$MANIFEST" ] || MANIFEST="$MASTER/shared-manifest.json"
die() { echo "drift-check-shared: $*" >&2; exit 2; }
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

# Resolve a manifest entry to its source path in the Master. Entries are repo-relative paths
# (e.g. "plugins/core-lifecycle/skills/ci-status") since skills/agents moved under plugins/.
# COMPATIBILITY: a bare name with no slash still resolves against the pre-plugins layout
# (<master>/skills/<name>, <master>/agents/<name>.md), so an older or externally-supplied
# Master checkout — and the manifests consumers already have — keep working unchanged.
# Must stay in sync with the identical helper in sync-shared.sh.
resolve_src() { # resolve_src <category> <manifest-entry> <suffix>
  case "$2" in
    */*) printf '%s' "$MASTER/$2$3" ;;
    *)   printf '%s' "$MASTER/$1/$2$3" ;;
  esac
}
REPO="${1:-}"; [ -n "$REPO" ] || die "usage: drift-check-shared.sh <consumer-repo-path>"
REPO="$(cd "$REPO" 2>/dev/null && pwd)" || die "consumer repo not found: ${1}"

# Pre-flight: the manifest is canonical — every entry must exist in the Master, else the manifest
# itself is broken. Fail fast rather than returning a misleading OK.
missing=""
while IFS= read -r e; do [ -n "$e" ] && { [ -e "$(resolve_src skills "$e" "")" ]    || missing="$missing skills:$e"; }; done \
  < <(jq -r '.shared_skills[]?' "$MANIFEST")
while IFS= read -r e; do [ -n "$e" ] && { [ -e "$(resolve_src agents "$e" ".md")" ] || missing="$missing agents:$e"; }; done \
  < <(jq -r '.shared_agents[]?' "$MANIFEST")
[ -z "$missing" ] || die "manifest entries not found in Master (fix shared-manifest.json):$missing"

drift=0
check_one() { # check_one <category> <manifest-entry> <suffix> — caller guarantees the category dir is not a whole-dir symlink
  local cat="$1" entry="$2" suf="$3" src name dst
  src="$(resolve_src "$cat" "$entry" "$suf")"
  # The consumer layout is FLAT (see sync-shared.sh) no matter how deep the Master entry sits.
  name="$(basename "$entry")$suf"
  dst="$REPO/.claude/$cat/$name"
  if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then echo "DRIFT missing in consumer: .claude/$cat/$name"; drift=1; return 0; fi
  if [ -L "$dst" ]; then echo "DRIFT symlink (Claude Code won't load it — must be a real copy): .claude/$cat/$name"; drift=1; return 0; fi
  if ! diff -rq "$src" "$dst" >/dev/null 2>&1; then echo "DRIFT differs from Master (run sync-shared.sh): .claude/$cat/$name"; drift=1; fi
}

# A whole-dir category symlink (old thin-repo wiring) makes per-item paths resolve back into the
# Master, so a naive per-item diff would compare the Master against itself and miss the drift.
# Flag the symlinked category once and skip its per-item checks.
check_category() { # check_category <category> <manifest-array> <suffix>
  local cat="$1" arr="$2" suf="$3"
  if [ -L "$REPO/.claude/$cat" ]; then
    echo "DRIFT category dir is a symlink (Claude Code won't load it): .claude/$cat"; drift=1; return 0
  fi
  while IFS= read -r n; do [ -n "$n" ] && check_one "$cat" "$n" "$suf"; done < <(jq -r ".${arr}[]?" "$MANIFEST")
}

check_category skills shared_skills ""
check_category agents shared_agents ".md"

[ "$drift" -eq 0 ] && echo "OK: all shared skills/agents in $REPO match the Master (real copies)"
exit "$drift"
