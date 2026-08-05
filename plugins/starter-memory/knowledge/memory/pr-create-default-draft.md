---
name: pr-create-default-draft
description: "`gh pr create` defaults to Ready; pass `--draft` for human-review ordering; AI bots may review drafts quickly so don't rely on --draft to defer them"
metadata:
  type: feedback
---

`gh pr create` defaults to opening the PR as **Ready for Review**, not Draft. To open a draft PR, pass `--draft` (or `-d`) explicitly.

**Bot review trigger behavior:** Some AI code-review bots do NOT review draft PRs — they fire only when the PR transitions to Ready (via `gh pr ready <PR>` or the web UI). Do not assume a bot has reviewed a draft and found nothing; the absence of findings may simply mean it has not been triggered yet.

What `--draft` buys you:
- Visible work-in-progress signal to human reviewers
- Defers bot reviews until you mark Ready (for bots that respect draft state)
- Blocks auto-merge automation that requires Ready state
- Keeps the PR out of some dashboard counts

**Why:** Opening a PR as Ready immediately exposes it to bot reviewers and auto-merge triggers before CI has completed or self-checks have passed, disrupting intended phase ordering.

**How to apply:**
- Pass `--draft` for fresh PRs that follow a staged review flow.
- After CI completes and self-checks pass, explicitly call `gh pr ready <PR>` to transition. That transition is the trigger for bots that gate on Ready state.
- Do NOT assume a bot has reviewed a draft and is satisfied. If a draft PR shows no bot review threads, it is because the PR is still draft, not because the bot approved it.
- Follow the skill's phase order: confirm CI green → mark Ready → wait for bots → reconcile.
