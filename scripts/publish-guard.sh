#!/usr/bin/env bash
# Publish guard: fail if any deny-listed pattern appears in the tree.
# Baseline: config/denylist.public.txt. Private additions: file named by
# $PUBLISH_GUARD_DENYLIST (kept OUTSIDE this repo; CI injects via secret).
set -euo pipefail
ROOT="${1:-$(git rev-parse --show-toplevel)}"
BASE="$(cd "$(dirname "$0")/.." && pwd)"
patterns=$(cat "$BASE/config/denylist.public.txt")
if [ -n "${PUBLISH_GUARD_DENYLIST:-}" ] && [ -f "$PUBLISH_GUARD_DENYLIST" ]; then
  patterns=$(printf '%s\n%s' "$patterns" "$(cat "$PUBLISH_GUARD_DENYLIST")")
fi
rc=0
TMPHITS=$(mktemp); trap 'rm -f "$TMPHITS"' EXIT
# repo-config.example.json deliberately ships two placeholder ProjectV2
# node/field ids that reuse GitHub's real id-prefix shape (see
# config/denylist.public.txt) so the example reads as realistic.
#
# Suppression is CONTENT-granular, not file-granular and not line-granular:
# each hit line has the sanctioned literals REDACTED out of it, then the denied
# pattern is re-matched against whatever remains. A line explained entirely by
# a sanctioned literal drops out; a line that ALSO carries a real id still
# flags, and so does every other occurrence anywhere in the tree. Dropping
# whole matched lines instead would let a real leak hide by sharing a line with
# a placeholder. For the same reason this script needs no self-exclusion: its
# own mention of the literals below is fully redacted by the same rule.
#
# test-publish-guard.sh needs no exclusion either. It used to carry one, which
# blinded the guard to that whole file; instead its fixture ids are now assembled
# from fragments at runtime, so the denied patterns never appear contiguously in
# its source. No file in this tree is exempt from the scan.
SANCTIONED_LITERALS=('PVTSSF_EXAMPLE00000000' 'PVT_EXAMPLE000000000')
redact=''
for lit in "${SANCTIONED_LITERALS[@]}"; do redact+="s|${lit}||g;"; done

# Path list for the NAME scan, gathered once (relative to $ROOT, so the ambient
# path of a scratch checkout can never itself trip a pattern).
names=$(cd "$ROOT" && find . \( -name .git -o -name .superpowers \) -prune -o -print)

while IFS= read -r p; do
  [ -z "$p" ] && continue

  # (1) CONTENT scan.
  # -I skips binary files. KNOWN LIMITATION, deliberate: a denied string embedded in a
  # committed binary (an archive, image metadata, a compiled artifact) is NOT caught by
  # this guard. grep cannot report an actionable line for one, and a byte offset tells a
  # human nothing. Keep binaries out of the published tree, or scan them with a separate
  # tool before publishing.
  matches=$(grep -rniI --exclude-dir=.git --exclude-dir=.superpowers --exclude="denylist.public.txt" -- "$p" "$ROOT" || true)
  if [ -n "$matches" ]; then
    matches=$(printf '%s\n' "$matches" | sed "$redact" | grep -i -- "$p" || true)
  fi

  # (2) NAME scan. A leak lives in a PATH as readily as in file content — a file or
  # directory named after an internal project, customer, or host discloses it just by
  # existing, and the content scan would never see it. sed does not add or remove lines,
  # so line N of the redacted list is still line N of the original: match on the redacted
  # copy (same sanctioned-literal suppression as content), then report the real paths.
  nhits=''
  nlines=$(printf '%s\n' "$names" | sed "$redact" | grep -in -- "$p" | cut -d: -f1 || true)
  if [ -n "$nlines" ]; then
    nhits=$(printf '%s\n' "$names" | awk -v L="$nlines" \
      'BEGIN { n = split(L, a, "\n"); for (i = 1; i <= n; i++) want[a[i]] = 1 } NR in want')
  fi

  if [ -n "$matches" ] || [ -n "$nhits" ]; then
    { [ -n "$matches" ] && printf '%s\n' "$matches" | cut -d: -f1; true; } > "$TMPHITS"
    { [ -n "$nhits" ] && printf '%s\n' "$nhits"; true; } >> "$TMPHITS"
    echo "DENY[$p]:"; sort -u "$TMPHITS"; rc=1
  fi
done <<< "$patterns"
exit $rc
