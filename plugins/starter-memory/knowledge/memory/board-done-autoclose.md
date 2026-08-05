---
name: board-done-autoclose
description: A Projects v2 board can auto-close the linked issue when Status→Done; speculative Done moves are destructive — post comments before the status change
metadata:
  type: project
---

A GitHub Projects v2 board may have an automation rule that auto-closes the linked issue when an item's `Status` field is set to `Done`. Setting Status→Done is therefore a **destructive, one-way trigger** — the issue closes immediately, including its visibility in default views.

**Why:** The status change → issue close is unidirectional. The reverse (closing an issue via `gh issue close`) does not appear to auto-set Status=Done. Only the Done→close direction is destructive. When a Status change fires before a comment can be posted, `gh issue close --comment` becomes a no-op because the issue is already closed.

**How to apply:**
- Never set `Status=Done` for a board item unless the underlying issue is already closed OR you intend to close it. Speculative Done moves auto-close the issue.
- If you want to post an explanatory comment alongside the close, post the comment FIRST (as a standalone `gh issue comment`), then change Status to Done. `gh issue close --comment` will silently no-op if the auto-close has already fired.
- The automation always sets `stateReason=COMPLETED`. If the truth is "not planned / invalidated," the board automation doesn't differentiate — note the semantic mismatch in a comment.
- When recovering from an unintended auto-close: post a comment explaining the reopen, then `gh issue reopen`, then reset Status on the board to the appropriate in-flight value.
