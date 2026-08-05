---
name: branch-protection-discipline
description: Never `gh pr merge --admin` past a legitimate blocking bot review; commit-cap guidelines are soft, branch protection is not
metadata:
  type: feedback
---

When a bot review posts `CHANGES_REQUESTED` or otherwise causes `mergeStateStatus: BLOCKED` on a PR, the block is intentional infrastructure — not background noise. Never use `gh pr merge --admin` to circumvent it.

**Key distinction:** a "max N fix commits per review cycle" guideline (common in review-flow skills) is a soft heuristic for noise prevention. It does NOT apply when:
- A bot's review blocks merge via branch protection
- A finding is critical / high-severity / security-relevant
- A finding is structurally correct and in-scope

In those cases, keep iterating until the block is resolved properly. A 3rd or 4th fix commit on a legitimate merge-blocking finding is exactly the right behavior.

**`gh pr merge --admin` is NOT an escape hatch for "I don't want to make another fix commit."** Admin override exists for genuine emergencies (security incident response, broken-CI recovery) and explicit per-PR developer authorization. Using it to circumvent a legitimate bot `CHANGES_REQUESTED` defeats the purpose of provisioning the bot in the first place.

**How to apply:**
1. When `mergeStateStatus: BLOCKED` appears, investigate WHY. Do not reach for `--admin`.
2. Read the bot's most recent review carefully. If the bot's `CHANGES_REQUESTED` state is from a previous commit and the bot has not re-reviewed yet, wait for re-review.
3. If the bot's most recent review identifies a real finding → fix it and push. The soft commit-cap guideline does not apply.
4. If the finding is a false positive → reply with empirical evidence (test output, demonstration, doc citation) and ask the developer to dismiss the review.
5. If the finding is genuinely out-of-scope → use the deferral gate with a tracked follow-up issue and explicit developer dismissal.
6. **Never use `--admin` without explicit per-PR developer authorization for that specific bypass.**
