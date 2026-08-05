---
name: pr-ci-merge-ref-race
description: Within ~30 s of PR creation, actions/checkout may fail to fetch the merge ref with a misleading "could not read Username" error; fix is gh run rerun --failed, not a code change
metadata:
  type: project
---

CI workflows that trigger on `pull_request` events and use `actions/checkout` with `fetch-depth: 0` can fail within the first ~30 seconds of PR creation. The failure occurs because GitHub computes the merge SHA asynchronously — there is a window (~10-30 s, sometimes more) where the merge ref exists in the workflow context but is not yet fetchable from the runner.

**Error signature:**

```
fatal: could not read Username for 'https://github.com': terminal prompts disabled
The process '/usr/bin/git' failed with exit code 128
```

`actions/checkout` retries 3 times (13 s, 20 s, 30 s waits = ~63 s total). If the race window extends past 63 s, all retries fail and the job exits red.

**Why the job name is misleading:** The failing step is "Run actions/checkout" — the actual script the job was created to run never executes. Diagnostics that read only the job name will misreport the failure as the job's domain (e.g., "SPA contract failed") when the real cause is the merge-ref race. **Always read `gh run view <id> --log-failed` and identify which STEP failed**, not just which job.

**Fix:**

```bash
gh run rerun <run-id> --failed
```

Wait ~30 s to 1 min after PR creation before rerunning so the merge ref stabilizes. No code change is appropriate — the race is in GitHub's merge-ref replication.

**Confirm this shape (vs. a real failure in the job's domain):**

1. Failed STEP is `Run actions/checkout`, not the job's own script.
2. Error string is `could not read Username for 'https://github.com'`.
3. PR was created within ~30 s of the failed run's start time (`gh pr view <N> --json createdAt` vs `gh run view <id> --json startedAt`).

**How to apply:** When a workflow job fails immediately after PR creation with a git authentication error, check the step name before diagnosing the job's business logic. One rerun after a short wait resolves the race.
