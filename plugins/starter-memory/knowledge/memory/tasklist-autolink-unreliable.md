---
name: tasklist-autolink-unreliable
description: GitHub `- [ ] #N` tasklist auto-detect often fails on programmatic body edits; run REST POST /sub_issues as the PRIMARY path, not a fallback
metadata:
  type: feedback
---

When updating a parent epic's `## Sub-Issues` tasklist via `gh issue edit --body-file <file>`, GitHub's auto-detection of `- [ ] #NNN` lines as native sub-issue links often does NOT fire. The GraphQL `repository.issue.parent` query returns null/empty for the new child despite the tasklist edit landing cleanly in the parent body.

**Why:** GitHub's web UI triggers the auto-link on save; programmatic body-replacement via `gh issue edit` likely bypasses whatever debounce/event the web UI emits. Tasklist-only linkage is text; native sub-issue linkage is data. A child without a native parent link does not appear in the parent's `subIssues` GraphQL query, does not show in dashboards that read native links, and does not auto-update the parent's `sub_issues_summary` count.

**How to apply:**

- Treat the REST `POST /repos/{owner}/{repo}/issues/{parent}/sub_issues` endpoint as the **primary** mechanism for establishing parent-child links, not a fallback. It is idempotent — safe to call even if the link already exists.
- Run GraphQL verification AFTER the REST call for confirmation, not BEFORE to decide whether to call REST.
- Skip any conditional "if tasklist auto-detect missed it, then fall back to REST" branch — just always run the REST force-link. This saves one API round-trip and avoids the silent-failure case where auto-detect ran and missed.

**Related:** `verify-full-ancestry-chain` (verifying all levels of a multi-level hierarchy), `pr-body-mention-autoclose` (same auto-link pattern family).
