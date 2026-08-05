---
name: github-env-rule-api-anomaly
description: "`gh api -X PUT environments/{name}` can return HTTP 422 'billing plan does not support' despite an active paid plan — unresolved anomaly"
metadata:
  type: project
---

`gh api -X PUT /repos/{owner}/{repo}/environments/{name}` with `wait_timer` or `required_reviewers` fields can return HTTP 422 with the message "Failed to create the environment protection rule. Please ensure the billing plan supports the wait timer protection rule" — even on accounts with an active paid GitHub plan and even when the UI lists those features as included.

**Why:** Root cause is unresolved. Possible explanations include:
- GitHub-side billing-state propagation lag for the env-rule API specifically (distinct from the billing UI cache).
- The `gh` CLI token (`gho_*`) missing `read:user` scope; `gh api /user --jq '.plan'` returning `null` may cause the env-rule endpoint to fall back to a "no plan info → assume free tier" path.
- A GitHub-side bug where the billing-state cache used by the env-rule API differs from the one surfacing in the billing UI.

Existing `branch_policy` configurations on the same repo's environments prove environment protection is at least partially operational, so this is a partial-surface anomaly, not a blanket rejection.

**How to apply:**
- Do not block a task on programmatic env-rule creation if it returns 422. Treat it as a known unresolved anomaly and document it.
- Workarounds (in order of ease): (a) configure the protection rule via the web UI at the repo's Settings → Environments page — the UI sometimes succeeds when the API fails; (b) generate a fresh PAT with broader scopes including `read:user`; (c) file a ticket with GitHub Support.
- Secrets scoped to an environment work fine even when protection rules fail to apply — keep those two concerns separate.
- If you hit this on a different repo or account, record the new error message and repro context alongside this note; more data points may reveal the root cause.
