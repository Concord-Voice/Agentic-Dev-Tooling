---
name: project-auto-add-unreliable
description: "GitHub Projects v2 auto-add silently skips items; the filter is UI-only and API-invisible — use a manual-add fallback and verify membership"
metadata:
  type: project
---

GitHub Projects v2 "Auto-add to project" workflows occasionally fail to add individual issues or PRs even when the workflow is enabled and the item visually matches the expected criteria. The workflow's filter (which gates which items get added) is configured in the project's Workflows UI and is **not exposed via the API** — `ProjectV2Workflow` GraphQL only surfaces `id`, `name`, `enabled`, and `number`. A missed auto-add leaves the item created cleanly but absent from the board with no error signal.

**Why:** GitHub Projects v2 automation has known reliability gaps on user-account projects. A UI-only filter can silently exclude items, and individual auto-add events can fail server-side with no notification. The enumeration-vs-direct-query gap (see `enumeration-empty-direct-works`) makes the miss hard to detect programmatically.

**How to apply:**
- Always include a manual-add fallback after creating an issue/PR: call `gh project item-add <number> --owner <owner> --url <item-url>`. The call is idempotent — if auto-add already fired, it is a no-op.
- After any `gh issue create` or `gh pr create`, verify project membership before attempting field mutations (e.g., setting Priority). If the item is not on the board, the manual-add call will place it there so subsequent mutations can proceed.
- When debugging "item missing from board": first check whether the workflow is still `enabled: true` via the GraphQL API. If it is, the item likely tripped a UI-only filter or hit GitHub-side flakiness — inspect the Workflows UI manually.
- A UI-only filter change can silently break automation with no API signal. If multiple consecutive items miss auto-add, check the Workflows filter in the UI before assuming widespread workflow drift.
