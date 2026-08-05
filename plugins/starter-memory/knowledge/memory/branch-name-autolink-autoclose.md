---
name: branch-name-autolink-autoclose
description: "`feature/<N>-...` branches populate closingIssuesReferences for #N — on merge the Projects v2 board auto-close fires even with 'Refs' not 'Closes'; use a non-matching branch name or post-merge reopen for PR≠done epics"
metadata:
  type: project
---

When a branch is named `feature/<N>-<topic>`, GitHub auto-detects issue `#N` as a closing reference for any PR opened from that branch. This populates `closingIssuesReferences` with `#N` even if the PR body uses `Refs #N` rather than `Closes #N`. On merge, the Projects v2 board automation moves `#N`'s Status field to `Done`, which triggers the `board-done-autoclose` pattern: `#N` auto-closes with `stateReason=COMPLETED`.

**Why:** GitHub infers the closing relationship from the branch name pattern, not only from body keywords. The `closingIssuesReferences` field is populated silently at PR creation — "Refs" in the body correctly documents intent but does not prevent the auto-link. Combined with a Projects v2 "PR merged → Status=Done" workflow, this creates an auto-close path that bypasses keyword discipline entirely.

**How to apply:** Whenever a PR's parent issue must remain open after merge (parent-epic patterns where work continues in child issues):

1. **After opening the PR**, check `gh pr view <PR> --json closingIssuesReferences`. If non-empty, the auto-link has already fired.
2. **Two mitigation options:**
   - **(a) Use a branch name that does not match `feature/<N>-...`** (e.g., `feature/spec-and-plan` or `docs/system-design-topic`). Auto-link will not fire.
   - **(b) Accept the auto-close, then post-merge reopen** via `gh issue reopen <N>` plus an explanatory comment and project board Status reset. The recovery is mechanical but adds steps to the merge workflow.
3. **Post-merge recovery sequence (if auto-close fires):**
   - Post an explanatory comment on the issue BEFORE changing Status (per `board-done-autoclose`).
   - `gh issue reopen <N>`
   - Reset project board Status back to the appropriate in-flight value via `updateProjectV2ItemFieldValue` GraphQL mutation.
4. **For PR body:** continue using `Refs` not `Closes` — it correctly documents the intent for future readers even though it does not prevent the auto-link.

**Connects with:** `board-done-autoclose` (the underlying Status→Done mechanism), `pr-body-mention-autoclose` (a third auto-close path via PR body mentions).
