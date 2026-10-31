#!/usr/bin/env bash
# upstream-import.sh UPSTREAM_DIR — replay a public upstream's changes into a
# private downstream repo without ever overwriting what the downstream owns.
#
# Run from the downstream repo's root, on a clean branch. UPSTREAM_DIR is a
# full clone of the upstream with the commit to import checked out.
#
# The downstream declares, in .github/upstream-sync.json:
#   {"upstream": "Org/Public-Repo",
#    "import":  ["services/", "client/admin/", "LICENSE"],   # path prefixes upstream owns
#    "private": [".github/workflows/deploy-", "CLAUDE.md"],   # prefixes never touched
#    "scrub":   ["[internal]"]}   # optional: fixed strings an added line must not hold
# and records the last imported upstream commit in .github/upstream-sync.lock.
#
# What it does:
#   1. Diffs upstream from the locked commit to HEAD, limited to `import`
#      prefixes, and applies that diff with `git apply --3way`. Files the
#      downstream edited keep their edits; only upstream's changed lines move.
#      Both sides changing the same lines is a conflict for a person, never a
#      silent overwrite.
#   2. Refuses, before applying anything, when: an `import` prefix overlaps a
#      `private` one; the new upstream commit doesn't descend from the lock; an
#      added line holds one of the `scrub` strings, i.e. damage from the public
#      repo's scrub coming back.
#   3. Writes the new lock and stages everything. The caller commits and opens
#      the pull request; nothing here pushes. A diff git rejects without
#      leaving conflicts is refused, and the lock stays put.
#
# Prints the imported and skipped (outside `import`) paths. Exit 0 = staged
# (or nothing to import), 1 = refused, 2 = conflicts left in the index.
set -euo pipefail

CONFIG=.github/upstream-sync.json
LOCK=.github/upstream-sync.lock

fail() { echo "::error::upstream-import: $1" >&2; exit 1; }
[[ $# -eq 1 && -d "$1/.git" ]] || fail "usage: $0 UPSTREAM_DIR"
up=$1
[[ -f "$CONFIG" && -f "$LOCK" ]] || fail "missing $CONFIG or $LOCK"
command -v jq >/dev/null || fail "jq is required"
jq -e . "$CONFIG" >/dev/null 2>&1 || fail "$CONFIG is not valid JSON"
if ! git diff --quiet || ! git diff --cached --quiet; then fail "working tree is not clean"; fi

mapfile -t import < <(jq -r '.import[]' "$CONFIG")
mapfile -t private < <(jq -r '.private[]? // empty' "$CONFIG")
mapfile -t scrubs < <(jq -r '.scrub[]? // empty' "$CONFIG")
(( ${#import[@]} )) || fail "$CONFIG lists no import prefixes"
for i in "${import[@]}"; do
  for p in "${private[@]}"; do
    [[ "$i" == "$p"* || "$p" == "$i"* ]] && fail "import prefix '$i' overlaps private prefix '$p'"
  done
done

old=$(tr -d '[:space:]' < "$LOCK")
new=$(git -C "$up" rev-parse HEAD)
[[ "$old" =~ ^[0-9a-f]{40}$ ]] || fail "$LOCK does not hold a commit SHA"
[[ "$old" != "$new" ]] || { echo "Nothing to import: already at $new."; exit 0; }
git -C "$up" merge-base --is-ancestor "$old" "$new" || fail "upstream $new does not descend from the locked $old"

owned() { local f=$1 p; for p in "${private[@]}"; do [[ "$f" == "$p"* ]] && return 1; done
          for p in "${import[@]}"; do [[ "$f" == "$p"* ]] && return 0; done; return 1; }
paths=() skipped=()
while IFS= read -r -d '' f; do
  if owned "$f"; then paths+=("$f"); else skipped+=("$f"); fi
done < <(git -C "$up" diff --name-only -z --no-renames "$old" "$new")

printf 'Skipped (outside import): %s\n' "${skipped[@]:-none}"
if (( ${#paths[@]} == 0 )); then
  echo "$new" > "$LOCK"; git add "$LOCK"
  echo "No imported paths changed; lock moved to $new."; exit 0
fi

# --3way needs upstream's preimage blobs locally; this adds objects, no refs.
git fetch -q --no-tags "$up" HEAD
patch=$(mktemp); trap 'rm -f "$patch"' EXIT
# Literal pathspecs: a filename with glob characters must not widen the patch
# past what owned() accepted.
updiff() { git --literal-pathspecs -C "$up" diff --no-renames "$old" "$new" "$@" -- "${paths[@]}"; }
updiff --binary > "$patch"
if (( ${#scrubs[@]} )); then
  # A distinct marker for added lines, so `+++` headers never mask content.
  scrub=$(updiff --output-indicator-new='>' | grep -E '^>' | cut -c2- | grep -F "${scrubs[@]/#/-e}" || true)
  [[ -z "$scrub" ]] || fail "the upstream diff adds scrub markers; fix them upstream first:
$scrub"
fi

printf 'Imported: %s\n' "${paths[@]}"
if ! git apply --3way --index "$patch"; then
  if [[ -z "$(git ls-files -u)" ]]; then
    # Rejected outright (e.g. upstream edits a file downstream deleted): no
    # conflict to resolve, so undo and keep the lock where it was.
    git reset -q --hard
    fail "upstream diff does not apply and left no conflicts to resolve; port it by hand"
  fi
  echo "$new" > "$LOCK"; git add "$LOCK"
  echo "::warning::upstream-import: conflicts; resolve them in the files git lists as unmerged." >&2
  exit 2
fi
echo "$new" > "$LOCK"; git add "$LOCK"
echo "Staged $old..$new."
