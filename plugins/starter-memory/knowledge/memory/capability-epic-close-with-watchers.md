---
name: capability-epic-close-with-watchers
description: When a capability epic has all actionable children closed but a long-horizon watcher child remains open, detach the watcher and close the epic via the 4-step sequence
metadata:
  type: feedback
---

When a **capability epic** (titled "Epic: do \<X\>") has all actionable children CLOSED but a long-horizon passive watcher child remains OPEN, do NOT leave the epic open indefinitely waiting for the watcher to resolve.

**Why:** GitHub's parent-child sub-issue links are tree-shaped because the data model is, not because all parent-child relationships represent "blocking" semantics. A watcher attached as a REST sub-issue structurally blocks epic closure under any "epic closes when all children close" convention and distorts the epic's open-children count on the project dashboard. Capability epics close when their actionable scope is structurally complete, regardless of passive observers. This is distinct from **version epics**, which follow release-tracking discipline gated on a version tag.

**How to apply:** Run the 4-step sequence:

1. **Detach the watcher** via `DELETE /repos/{owner}/{repo}/issues/{epic}/sub_issue` (singular `sub_issue`, not plural; body param `sub_issue_id` requires the internal numeric id from `GET /repos/{owner}/{repo}/issues/{epic}/sub_issues`).
2. **PATCH the epic body** to add a "Long-horizon Follow-up Watchers" section that links to the watcher informationally (URL-only reference, not `#NNN`, to avoid triggering `pr-body-mention-autoclose`-style linkage).
3. **Post a retrospective comment** on the epic with "What shipped / What slipped / What we learned" structure.
4. **`gh issue close`** with a reference to the retro comment.

The watcher then operates as a standalone tracking artifact. When it eventually triggers (upstream event, abandonment cutoff), a successor implementation child can be filed against whatever version epic is active at that time — not retroactively re-parented to the now-closed capability epic.

**Capability vs. version epic distinction:** Capability epics close on scope completion. Version epics follow Planning → In Progress → Released → Retrospected → Closed, gated on the version tag.
