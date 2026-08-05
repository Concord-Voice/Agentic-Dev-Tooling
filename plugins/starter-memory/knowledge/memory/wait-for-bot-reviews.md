---
name: wait-for-bot-reviews
description: After marking a PR ready, enumerate the repo's expected bot reviewers and WAIT for all to arrive before concluding "all clear"
metadata:
  type: feedback
---

After marking a PR Ready for Review, do NOT immediately run a final review reconciliation pass. First confirm that all expected bot reviews for this PR have arrived.

**Why:** If a reconciliation pass runs before bots have posted, the table may show zero findings, which reads as "all clear — proceed to merge." That is the exact failure mode where a real finding gets missed by jumping the gun. The reconciliation pass also tends to "consume" the review checkpoint mentally — if it ran clean once, there is pressure not to re-run it when a late-arriving bot surfaces a real finding.

**How to apply:**

1. **Bot reviews only come AFTER marking Ready** — never wait for reviews while the PR is still in draft. Marking Ready is the trigger.
2. **Identify the expected bot set for THIS PR.** Build a list based on currently-active bots and PR characteristics. For each expected bot, know: (a) the CI check name it posts, and (b) whether it also posts a conversation comment.
3. **Wait signals (in order of strength):**
   - CI check is `pending` / `in_progress` → bot is reviewing; wait
   - CI check is `success` / `failure` / `neutral` → bot has finished
   - Conversation comment posted by the bot → bot has finished
   - No CI check AND no comment after ~5–10 min after marking Ready → flag and STOP; investigate whether the bot is actually configured for this PR
4. **What STOP means:** do NOT proceed to final reconciliation. Surface to the developer: "Expected bot `<name>` has not started review. Investigate before proceeding."

**Per-PR override:** the developer may explicitly authorize skipping the wait. Treat that as a per-invocation override, not a license to skip the wait by default on future PRs.
