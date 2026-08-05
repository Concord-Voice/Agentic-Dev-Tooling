---
name: pr-body-mention-autoclose
description: A Projects v2 workflow can auto-link from a bare `#NNN` or `[#NNN](url)` mention in a PR body; squash-merge then auto-closes even with no closing keyword — use URL-only references for tracking-placeholder PRs
metadata:
  type: project
---

When a PR body contains `#NNN` references to an issue — either bare `#NNN` or markdown-linked `[#NNN](url)` — and the repo's Projects v2 board has a "Pull request linked to issue" workflow enabled, project automation auto-links the issue to the PR. Once that link exists, the squash-merge fires the linked-issue auto-close, independent of whether the PR body uses closing keywords and independent of whether the branch name matches any auto-link pattern.

**Why:** This is a **third auto-close path** distinct from the closing-keyword path and the `branch-name-autolink-autoclose` pattern. The "Pull request linked to issue" Projects v2 workflow links issues based on `#NNN` mentions in the PR body — and that linkage acts as a closing reference at merge time. Even explicit prose in the PR body saying "do not close on merge" is ignored; GitHub does not parse human-written instructions.

**How to apply:**

- When filing a PR alongside a tracking-placeholder issue you want to keep OPEN, **never use `#NNN` or `[#NNN](url)` references in the PR body.** Use only the full URL form (`https://github.com/<owner>/<repo>/issues/NNN`) without the `#NNN` prefix.
- The markdown-linked form `[#NNN](url)` triggers auto-link too — do not assume the link wrap provides protection. Only the URL-only form (no `#` prefix) is safe.
- After any PR merge that references a tracking issue, verify the tracking issue is still OPEN: `gh issue view NNN --json state,stateReason`. Do not trust the PR body's "do not close" prose.
- **If auto-closed:**
  1. Post a comment on the issue FIRST explaining the reopen (per `board-done-autoclose`).
  2. `gh issue reopen NNN`
  3. Reset project board Status from `Done` → the appropriate in-flight value via `updateProjectV2ItemFieldValue` GraphQL mutation.
- **Defensive PR-body template for tracking-placeholder PRs:**
  > Tracked alongside the placeholder issue at https://github.com/\<owner\>/\<repo\>/issues/NNN (do not close on merge — preserved for re-entry).

**Connects with:** `board-done-autoclose` (the underlying Status→Done mechanism), `branch-name-autolink-autoclose` (branch-name auto-link path), `tasklist-autolink-unreliable` (same auto-link/auto-close pattern family).
