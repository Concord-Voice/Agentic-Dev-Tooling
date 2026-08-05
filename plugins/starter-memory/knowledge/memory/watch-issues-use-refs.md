---
name: watch-issues-use-refs
description: For long-horizon watch issues (vendor renewals, prebuild watches, scheduled-routine trackers) the mechanism-shipping PR is one milestone, not the terminus; use `Refs #N` so auto-close doesn't fire on merge
metadata:
  type: feedback
---

For long-horizon watch issues, the PR that ships the automation or mechanism should use `Refs #N`, not `Closes #N`.

**Why:** Watch issues often have explicit close conditions defined in the body (e.g., "Close when EITHER (a) upstream ships X, OR (b) abandoned after N months"). The PR that ships the mechanism powering the watch is ONE milestone in the issue's lifecycle, not its terminus. Using `Closes` triggers GitHub's auto-close at merge time, which is semantically wrong for an issue that should remain the canonical destination for ongoing activity (poll comments, status updates, trigger events).

**How to apply:**
- Before drafting the PR body, re-read the issue's "Goal / Definition of Done" section.
- If the close conditions describe an EVENT EXTERNAL to the PR (upstream behavior change, time-based abandonment, vendor response, scheduled trigger), use `Refs #N`.
- If the close conditions describe the PR's own deliverable (feature implemented, bug fixed), use `Closes #N`.
- This pattern applies to: scheduled-routine implementation PRs (the watch keeps running after merge), vendor-renewal trackers, deprecation-window trackers, upstream-dependency watches, anything with quarterly/yearly poll cadence.
- After merging a PR that uses `Refs #N`, verify the referenced issue is still OPEN: `gh issue view N --json state`.

**Related:** `pr-body-mention-autoclose` (the broader auto-close behavior of `#NNN` mentions in PR bodies).
