---
name: sonarcloud-pr-not-found-race
description: SonarCloud scanner exit-3 failures have three distinct shapes — PR-decoration webhook race, org/projectKey config drift, and scan-duration timeout — each with a different fix
metadata:
  type: project
---

The SonarCloud scanner fails in three shapes that look similar but require completely different fixes. **Read the actual error line before acting.**

## Shape A — PR-decoration webhook race (exit-3, ~20-30 s)

The scanner exits with code 3 almost immediately after starting PR decoration. Log signature:

```
INFO  Auto-configuring pull request <N>
ERROR Could not find the pullrequest with key '<N>'
INFO  EXECUTION FAILURE
INFO  Total time: ~19s
##[error]Action failed: sonar-scanner failed with exit code 3
```

**Why:** SonarCloud's PR-decoration index is event-driven via webhook. There is a brief window (seconds to minutes) where the scanner's API lookup races the webhook ingestion of the new HEAD SHA.

**Fix:** `gh run rerun <run-id> --failed`. Wait ~1-2 min before rerunning. No code change is appropriate.

**Confirms this shape:** job duration is very short (~30 s); a previous attempt on a different commit in the same PR succeeded.

## Shape B — org/projectKey config drift (exit-3, ~20 s, rerun always fails)

Same fast exit-3 signature as Shape A, but the real error is one line deeper:

```
INFO  Detected project binding: NONEXISTENT
ERROR Error during SonarScanner Engine execution
Caused by: HttpException: Error 404 ... {"errors":[{"msg":"Organization key '<org>' does not exist."}]}
```

**Why:** `sonar.organization` or `sonar.projectKey` in `sonar-project.properties` is stale — typically after a repo or org rename. `gh run rerun --failed` fails identically forever.

**Fix:** correct the config in `sonar-project.properties` on the default branch, then rebase or merge the fix into the affected branch. The key tell: Shape B PRs have NEVER passed the Sonar check (all-new config is broken for all of them), whereas Shape A PRs previously passed on an earlier commit.

## Shape C — scan-duration timeout (~20 min, job CANCELLED)

The job runs to the full `timeout-minutes` value, then is cancelled mid-analysis (`ANALYSIS SUCCESSFUL` never appears). This is NOT an exit-3 failure.

Signature:
- Job runs the full timeout then `##[error]The operation was canceled.` + Java process killed.
- CI check shows `cancelled`; `gh pr checks` aggregate reads "pending".
- **Intermittent** — timing-boundary variance of ±30 s causes some runs to squeak under.

**Why:** A single slow sensor (often a security taint-analysis sensor) dominates scan time on a cold analysis cache. The cache is cold when the repo only runs Sonar on PRs (no main-push analysis to populate a base cache), so every PR re-analyzes the full tree.

**Fix:** do not grind reruns (coin-flip). Real fix: warm the analysis cache by also running Sonar on main-branch pushes (enables incremental analysis); scope the slow sensor to changed files only; raise `timeout-minutes` as an interim band-aid. Quality Gate verdict is typically OK — this is scan duration, not quality.

**How to apply:** When a SonarCloud job fails, identify the shape from job duration + the exact error line before choosing a remediation path. Shape A → rerun. Shape B → fix config + rebase. Shape C → raise timeout / warm cache.
