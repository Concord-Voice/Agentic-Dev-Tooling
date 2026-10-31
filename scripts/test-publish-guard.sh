#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
fails=0
t() { local desc=$1 want=$2; shift 2
  if "$@" >/dev/null 2>&1; then got=0; else got=1; fi
  [ "$got" = "$want" ] && echo "ok: $desc" || { echo "FAIL: $desc (want exit $want, got $got)"; fails=1; }; }

# This file is NOT excluded from the guard's own tree-wide scan (it used to be, which
# blinded the guard to everything in here). To keep it scannable, every fixture id below
# is ASSEMBLED FROM FRAGMENTS -- `NODE_PFX` / `FIELD_PFX` plus the rest -- so no denied
# pattern from config/denylist.public.txt ever appears as a contiguous literal in this
# source, while the runtime strings written into the fixtures are byte-exact. Keep it that
# way: pasting a whole id inline here, even inside a comment, makes this file a guard hit.
NODE_PFX='PVT_'                 # + kwHO... => the denied ProjectV2 node-id prefix
FIELD_PFX='PVTSSF'; FIELD_PFX="${FIELD_PFX}_"   # => the denied ProjectV2 field-id prefix

tmp=$(mktemp -d)
echo "clean content" > "$tmp/ok.md"
t "clean tree passes" 0 bash scripts/publish-guard.sh "$tmp"
echo "ProjectV2 id ${NODE_PFX}kwHOAAAA" > "$tmp/bad.md"
t "node-id leak fails" 1 bash scripts/publish-guard.sh "$tmp"
rm "$tmp/bad.md"; echo "see ${FIELD_PFX}field" > "$tmp/bad2.md"
t "field-id leak fails" 1 bash scripts/publish-guard.sh "$tmp"
rm -rf "$tmp"

# ---- I2: the sanctioned repo-config.example.json placeholders don't blind
# the whole FILE — a real-shaped field-id leak in a file with that exact
# name still fails, even though the sanctioned literal itself is exempt.
tmp2=$(mktemp -d)
echo "field id ${FIELD_PFX}lAHOAhRealShape leaked here" > "$tmp2/repo-config.example.json"
t "real-shaped id in a repo-config.example.json fixture still fails" 1 bash scripts/publish-guard.sh "$tmp2"
rm -rf "$tmp2"

# ---- Suppression is CONTENT-granular, not line-granular: a real-shaped id
# that SHARES A LINE with a sanctioned placeholder must still fail. Dropping
# whole matched lines (rather than redacting the placeholder and re-matching)
# would let exactly this leak through.
tmp3=$(mktemp -d)
echo "{\"status_field\":\"${FIELD_PFX}EXAMPLE00000000\",\"project_id\":\"${NODE_PFX}kwHOAbCdEf01\"}" > "$tmp3/mixed.json"
t "real id sharing a line with a sanctioned placeholder still fails" 1 bash scripts/publish-guard.sh "$tmp3"
rm -rf "$tmp3"

# ---- m13: FILE NAMES are scanned too. A leak in a path discloses just as much as one in
# content, and the content scan never sees it — the file below is empty.
tmp4=$(mktemp -d)
: > "$tmp4/${NODE_PFX}kwHOAAAA-notes.md"
t "denied pattern in a FILE NAME fails (empty file, name-only hit)" 1 bash scripts/publish-guard.sh "$tmp4"
out4="$(bash scripts/publish-guard.sh "$tmp4" 2>&1 || true)"
printf '%s\n' "$out4" | grep -qF -- "-notes.md" \
  || { echo "FAIL: name-scan hit did not report the offending path"; fails=1; }
rm -rf "$tmp4"

# A denied pattern in a DIRECTORY name must fail too, not just a leaf file name.
tmp5=$(mktemp -d)
mkdir -p "$tmp5/${FIELD_PFX}internal/sub"; echo "clean" > "$tmp5/${FIELD_PFX}internal/sub/x.md"
t "denied pattern in a DIRECTORY name fails" 1 bash scripts/publish-guard.sh "$tmp5"
rm -rf "$tmp5"

# The name scan must not fire on a sanctioned literal either — same redaction rule as
# content, so a placeholder-named file is not a false positive.
tmp6=$(mktemp -d)
: > "$tmp6/${FIELD_PFX}EXAMPLE00000000.json"
t "sanctioned literal in a file NAME does not fire" 0 bash scripts/publish-guard.sh "$tmp6"
rm -rf "$tmp6"

# ---- Private allowlist ($PUBLISH_GUARD_ALLOWLIST): an exact literal is redacted
# before the re-match, like SANCTIONED_LITERALS. The same denied word anywhere
# else still fails, and regex characters in an entry match only themselves.
tmp7=$(mktemp -d)
printf 'acmecorp\n' > "$tmp7/deny.txt"
printf 'badge.project=acmecorp_tools\n' > "$tmp7/allow.txt"
mkdir "$tmp7/tree"
echo "![b](https://x/badge.project=acmecorp_tools&m=1)" > "$tmp7/tree/README.md"
t "allowlisted literal passes" 0 env PUBLISH_GUARD_DENYLIST="$tmp7/deny.txt" PUBLISH_GUARD_ALLOWLIST="$tmp7/allow.txt" bash scripts/publish-guard.sh "$tmp7/tree"
t "same literal fails without the allowlist" 1 env PUBLISH_GUARD_DENYLIST="$tmp7/deny.txt" bash scripts/publish-guard.sh "$tmp7/tree"
echo "made by acmecorp" >> "$tmp7/tree/README.md"
t "denied word outside the literal still fails, same file" 1 env PUBLISH_GUARD_DENYLIST="$tmp7/deny.txt" PUBLISH_GUARD_ALLOWLIST="$tmp7/allow.txt" bash scripts/publish-guard.sh "$tmp7/tree"
echo "![b](https://x/badgeXproject=acmecorp_tools)" > "$tmp7/tree/README.md"
t "allowlist entry is a fixed string, not a regex" 1 env PUBLISH_GUARD_DENYLIST="$tmp7/deny.txt" PUBLISH_GUARD_ALLOWLIST="$tmp7/allow.txt" bash scripts/publish-guard.sh "$tmp7/tree"
rm -rf "$tmp7"

# ---- I2: the real repo's own repo-config.example.json (sanctioned
# placeholders only) keeps passing the full-tree scan. This also covers the
# guard scanning ITSELF and THIS FILE (neither is excluded any more): the
# guard's SANCTIONED_LITERALS line must redact to nothing, and this file's
# fragment-assembled ids must never form a contiguous denied pattern. ----
t "real repo tree (incl. repo-config.example.json, the guard, and this test) passes" 0 bash scripts/publish-guard.sh

exit $fails
