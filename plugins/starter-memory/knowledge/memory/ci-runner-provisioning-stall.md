---
name: ci-runner-provisioning-stall
description: Fully-stalled CI with queued runs, runner_name null, and healthy budget/status is a transient GitHub-side runner-provisioning issue — self-clears; do not chase quota first
metadata:
  type: project
---

When all CI runs are stalled, the diagnostic signature distinguishes a transient GitHub platform-side runner-provisioning stall (self-healing, no action needed) from quota/code/settings problems.

**Diagnostic signature — all must be true simultaneously:**
- Many runs `queued`, **zero `in_progress`** (rules out concurrency exhaustion, which shows N running at cap).
- A stuck job's API record: `runner_name: null` on a standard label (e.g., `ubuntu-latest`).
- `githubstatus.com` all-green (no global incident).
- Actions budget has headroom and overage bills successfully (rules out quota/payment block).
- Same workflows ran fine hours earlier with no code change.
- Bonus tell: the Actions **cancel API returns HTTP 500** (GitHub scheduler degraded, not just runner pool empty).

**Refutation order (fastest → conclusive):** check `in_progress` count + `runner_name` on a stuck job + `githubstatus` → then check Settings→Billing (budget AND payment health), org Actions policy, runner groups → if all healthy, it is GitHub-side; re-poll, don't patch.

**Why:** High accumulated Linux-minute usage can look like quota exhaustion from the billing API, but the spending-limit budget field refutes it. A self-recovery confirms GitHub-side.

**How to apply:** When CI is fully stalled, FIRST establish `in_progress=0` + `runner_name:null` + green status + budget headroom. If that holds, conclude transient GitHub-side and re-poll (it self-heals, typically within ~90 min). Escalate to GitHub Support only if it persists for hours. Do NOT chase quota or code first.
