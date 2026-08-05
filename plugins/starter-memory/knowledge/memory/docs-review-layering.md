---
name: docs-review-layering
description: Multi-artifact docs PRs need both a subagent pre-PR pass (main-deliverable correctness) and a bot post-ready pass (plan/spec drift) — the two layers catch different things
metadata:
  type: feedback
---

For documentation PRs that ship multiple artifacts (main document + implementation plan + design spec), run both review layers:

1. **Pre-PR subagent pass** — scoped to the main deliverable. Catches content correctness, schema alignment, domain accuracy, completeness, and technical correctness.

2. **Post-ready automated review** — reviews every changed file equally, including plan and spec files. Catches drift introduced when post-review fix commits update the main deliverable but leave the plan or spec still describing the pre-fix content.

**Why:** The two layers have nearly zero overlap in the NEW findings they produce. Subagents focus on the main deliverable's domain correctness; automated tools catch structural drift across artifacts. Running only one layer leaves a predictable blind spot. Convergent findings (both layers flag the same issue) carry the highest signal.

**How to apply:**
- For docs PRs that include plan + spec + main file: do not skip the automated review pass even after a clean subagent pre-PR pass. Plan/spec drift is predictable and automated tools catch it reliably.
- For single-file docs PRs with no plan or spec: the subagent pass plus automated review is still valuable but the ROI from the automated pass is lower.
- Always cross-reference findings from both layers before acting — convergent findings are highest confidence; non-overlapping findings are still real and should each be triaged.
