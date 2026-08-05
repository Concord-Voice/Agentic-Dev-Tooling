---
name: getlatestrelease-prerelease-404
description: GET /repos/releases/latest 404s repo-wide when a repo ships only Pre-releases; use listReleases and take the most-recent non-draft entry instead
metadata:
  type: project
---

`GET /repos/{owner}/{repo}/releases/latest` (and SDK equivalents such as `github.rest.repos.getLatestRelease()`) return only the latest **full** (non-prerelease, non-draft) release. If a repository publishes all releases as GitHub **Pre-releases**, this endpoint **404s repo-wide** — not just for specific tags, but for the entire repo. Any CI step or script querying "the latest version" via this endpoint silently fails.

**Fix:** Use `listReleases` (`GET /repos/{owner}/{repo}/releases`, or `gh release list`), take the most-recent entry that is not a draft (prereleases included), and strip any tag prefix (e.g., `v`, `desktop-v`) to get the bare version string for comparison.

**Why:** The GitHub API docs describe `getLatestRelease` as returning "the latest published full release" — "full" explicitly excludes prereleases and drafts. Repositories that use only prerelease tagging have no qualifying release for this endpoint.

**How to apply:** In any release-querying tooling (CI version checks, release-notes scripts, deploy scripts, version comparison), avoid `getLatestRelease` / `releases/latest` unless the repo is known to publish full releases. Default to `listReleases` + filter, which works regardless of release type. Applies to any repo that uses pre-release tagging conventions.
