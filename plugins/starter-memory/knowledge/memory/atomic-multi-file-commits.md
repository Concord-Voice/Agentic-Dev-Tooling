---
name: atomic-multi-file-commits
description: Use the git tree API (blobs + trees + commits = 1 push) instead of sequential contents PUTs when applying multi-file fixes via `gh api`
metadata:
  type: feedback
---

When pushing multi-file changes to a PR branch via `gh api` (without a local working-tree), use the git tree API to create ONE atomic commit, not sequential per-file `contents/<path>` PUTs.

**Why:** Each `gh api -X PUT contents/<path>` creates its own commit and triggers its own push event. N file changes = N commits = N push events = N CI check-suites = N potential bot review triggers. Bots (code reviewers, SAST tools, etc.) may post review comments against partial state mid-batch, producing noise and extra review cycles. One atomic commit produces one push event and one bot pass against the consolidated change.

**How to apply:**

```bash
BRANCH_HEAD=$(gh api "/repos/${REPO}/git/refs/heads/${BRANCH}" --jq '.object.sha')
BASE_TREE=$(gh api "/repos/${REPO}/git/commits/${BRANCH_HEAD}" --jq '.tree.sha')

# Create one blob per file change
BLOB1=$(gh api -X POST "/repos/${REPO}/git/blobs" \
  -f "content=$(base64 -i /tmp/file1 | tr -d '\n')" \
  -f encoding=base64 --jq '.sha')
BLOB2=$(gh api -X POST "/repos/${REPO}/git/blobs" \
  -f "content=$(base64 -i /tmp/file2 | tr -d '\n')" \
  -f encoding=base64 --jq '.sha')

# Single tree referencing all blobs (preserves modes — 100755 for executables)
NEW_TREE=$(gh api -X POST "/repos/${REPO}/git/trees" --input - <<JSON | jq -r '.sha'
{
  "base_tree": "$BASE_TREE",
  "tree": [
    {"path": "path/to/file1", "mode": "100644", "type": "blob", "sha": "$BLOB1"},
    {"path": "path/to/file2", "mode": "100755", "type": "blob", "sha": "$BLOB2"}
  ]
}
JSON
)

# One commit, one ref-update, one push event
NEW_COMMIT=$(gh api -X POST "/repos/${REPO}/git/commits" \
  -f message="..." -f tree="$NEW_TREE" -F "parents[]=$BRANCH_HEAD" --jq '.sha')

gh api -X PATCH "/repos/${REPO}/git/refs/heads/${BRANCH}" -f sha="$NEW_COMMIT"
```

**FOOTGUN — empty-blob bug:** create blob content ONLY via the variable form `-f content="$(base64 < file | tr -d '\n')"`. Do NOT use `-f content=@-` with stdin piping — `-f` does not honor `@-` as stdin (that is `-F` semantics), so it silently produces an **empty blob** (`e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` — the well-known empty-file SHA). The empty-blob SHA is a non-empty string so a `[ -z "$VAR" ]` check will NOT catch it.

**Always verify each blob SHA before building the tree:**
```bash
[ "$BLOB1" = "$(git hash-object /tmp/file1)" ] || { echo "blob mismatch — aborting"; exit 1; }
```
This is cheap insurance, especially when the PR's CI does not run the affected test suite due to path gating.

**Recovery** if you push a bad tree: rebuild the commit with correct blobs (parent = original good HEAD) and `gh api .../git/refs/heads/$BRANCH -X PATCH -F sha=$GOOD_SHA -F force=true`.

**When NOT to use:** single-file fixes (just use `gh api -X PUT contents/<path>` — same outcome, simpler call).
