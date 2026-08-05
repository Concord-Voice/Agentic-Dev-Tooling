---
name: github-closes-multi-issue
description: GitHub PR/commit auto-close only picks up the first issue from a comma-separated Closes list; each issue needs its own Closes keyword
metadata:
  type: project
---

GitHub's PR/commit auto-close only picks up the **first** issue from a comma-separated `Closes #X, #Y, #Z` list. Verified on a merged PR where the squash body included a comma-separated list of six issues — `gh pr view --json closingIssuesReferences` returned ONLY the first issue, and after merge only that first issue auto-closed; the rest stayed open.

**Why:** The first issue was also covered by the branch-name autolink (branch was `feature/<N>-...` so GitHub populated `closingIssuesReferences` independently). Whether the `Closes #X, #Y` text contributed at all is unclear — the autolink alone would have closed the first issue.

**How to apply:** For multi-issue closure in a bundled PR:

  - **Best:** Use separate `Closes` keywords per issue:
    ```
    Closes #N
    Closes #M
    Closes #P
    ```
  - **Also works:** `Closes #N, closes #M, closes #P` (keyword for each, comma-separated)
  - **Does NOT work:** `Closes #N, #M, #P` (only first counted)
  - **Backup plan:** After merge, verify via `gh issue view <N> --json state` and use `gh issue close <N> --comment "..."` for any that stayed open.

Branch-name autolink (`feature/<N>-...`) is a separate mechanism that still works for the first issue number in the branch name.

This is independent of any `--add-issue` flag — `gh pr merge` doesn't accept such a flag; auto-close is purely commit-message-keyword driven.
