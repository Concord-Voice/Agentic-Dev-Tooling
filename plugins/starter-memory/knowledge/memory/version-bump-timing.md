---
name: version-bump-timing
description: Batch a forced version/metadata bump onto already-pending CI re-runs (e.g. during the review loop) rather than at PR-open
metadata:
  type: feedback
---

For PRs that require a forced version or metadata bump (e.g. because CI tooling — such as a release classifier — flags that the change type mandates one), defer that bump until the review-loop phase rather than applying it at PR-open or during the initial CI pass.

**Why:** Bumping early triggers a fresh full CI run. But the review loop (responding to subagent findings, applying fixes) will trigger its own CI re-run anyway. Bundling the version bump alongside review-loop fix commits piggybacks on a CI cycle that was already going to happen — saving at least one full CI run per PR. Bumping at PR-open or mid-flow creates a "double-shot CI" pattern: one run on the pre-bump commit, then another on the bump commit, when both were wasteful given the review cycle's re-run was inevitable.

**How to apply:**
- Do NOT bump immediately when CI tooling flags it during the initial phase.
- Do NOT bump at PR-open as a "preventive" measure.
- Defer the bump to the review-loop fix commit batch — bundle alongside whatever fixes the review subagents produce.
- If the review loop produces no fix commits, bump as a standalone commit at the end of review — that single CI re-run is unavoidable but minimal compared to mid-flow cycles.
- Mention the deferred bump in the PR body so reviewers know it is coming.
