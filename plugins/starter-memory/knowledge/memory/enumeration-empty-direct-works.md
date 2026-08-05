---
name: enumeration-empty-direct-works
description: "List/enumerate APIs return empty while by-ID/key works (GitHub code/secret-scanning lists, project-board items, SonarCloud issues); capture IDs at creation and act by ID"
metadata:
  type: project
---

A recurring failure mode across multiple platforms: **enumeration / list queries return empty results while direct-by-ID or direct-by-key queries return real data.** Observed independently across:

- **GitHub code-scanning / secret-scanning** — `GET .../alerts?state=open` LIST returns empty, but `GET .../alerts/{n}` direct by ID returns the real, open alert.
- **GitHub Projects v2** — `repository.issue(n).projectItems` and `repository.pullRequest(n).projectItems` GraphQL return empty `nodes`, but the item does exist on the board (it was added and had fields set at creation time).
- **SonarCloud** — `search_sonar_issues_in_projects` and project-list endpoints return `total:0`, but `get_project_quality_gate_status(projectKey)` and direct REST API calls with an explicit project key return real data.

**Why:** Likely caused by eventual-consistency propagation lag, scoping mismatches between list and direct endpoints, or org-rename artifacts in the enumeration path. The direct-handle lookup bypasses whatever index or cache the enumeration path relies on.

**How to apply:**
- Never treat an empty list result as ground truth. When a list returns empty, follow up with a direct-by-ID or direct-by-key query (or check the UI) before concluding the resource doesn't exist.
- **Capture IDs at creation time.** When you create a resource (issue, PR, project item, alert), record the ID returned in the creation response. Use that ID for subsequent mutations rather than relying on enumeration to find it later.
- This pattern generalizes across GitHub APIs and SonarCloud — assume it can affect any list/search endpoint on any of these platforms.
