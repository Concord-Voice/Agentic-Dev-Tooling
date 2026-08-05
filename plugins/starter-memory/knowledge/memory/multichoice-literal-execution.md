---
name: multichoice-literal-execution
description: When the user picks A/B/C, execute that exact option's mechanics — don't substitute an adjacent option that seemed similar in spirit
metadata:
  type: feedback
---

When presenting numbered or lettered multi-choice options (A/B/C, 1/2/3), the user's selection is a precise instruction. Do NOT execute an adjacent option that seemed similar in spirit.

**Why:** Options that share verbs ("do it now") but differ in mechanics ("this session" vs. "separate branch + PR") are different choices. The user picked one for a reason — often because the mechanical difference matters to them in ways that are not visible from the outside (e.g., stacking commits on the current branch vs. isolating them in a new PR has downstream implications for merge order, review scope, and PR scope).

**How to apply:** When the user picks a letter or number from a multi-choice prompt, re-read the exact wording of that option before acting. If options share high-level verbs but differ in mechanics, those mechanics ARE the choice. If genuinely unsure which precise mechanic the user intends, re-state your understanding in one sentence before executing: "Confirming B = adding commits to the current branch, not a new branch — yes?" Then proceed once confirmed. Never silently substitute an adjacent option and assume the user will not notice.
