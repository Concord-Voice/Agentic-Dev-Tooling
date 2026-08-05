---
name: gh-token-scope
description: GitHub Projects v2 mutations require `project` scope; detect INSUFFICIENT_SCOPES and surface the fix
metadata:
  type: project
---

GitHub CLI (`gh`) auth tokens do not include the `project` scope by default. Any Projects v2 GraphQL mutation — `updateProjectV2ItemFieldValue`, `addProjectV2ItemById`, field-value writes — will fail with `INSUFFICIENT_SCOPES` when the scope is absent.

**Why:** The `gh auth login` flow does not request `project` scope unless explicitly asked. The token works for issue/PR operations (`gh issue create`, `gh api`) but silently lacks the extra OAuth scope required for the Projects v2 GraphQL surface. When scope is missing every project field mutation fails, leaving fields unset with no obvious error unless you inspect the GraphQL response body.

**How to apply:**
- Wrap all Projects v2 GraphQL mutations in error handling that checks for `INSUFFICIENT_SCOPES` in the response.
- When that error is detected, surface the exact remedy to the user: `gh auth refresh -s project` (interactive, opens browser) — then retry.
- Fall through to issue-level operations (`gh issue create`, `gh issue edit`, `gh api POST /issues/*/sub_issues`) which use a different auth path and work regardless of `project` scope.
- Before writing any skill that drives Project v2 field mutations, verify scope is present with `gh auth status --show-token` or confirm a test mutation succeeds; do not assume it carries over from prior sessions.
