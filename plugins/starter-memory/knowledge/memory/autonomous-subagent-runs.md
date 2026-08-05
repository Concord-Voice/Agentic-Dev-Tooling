---
name: autonomous-subagent-runs
description: For long multi-subagent runs, offer A/B/C cadence but expect B (fully autonomous); respect hard-block and in-plan checkpoint exceptions; apply plan-size and fix-commit budget heuristics
metadata:
  type: feedback
---

When presenting cadence options on a long subagent-driven-development run (many tasks, multi-hour wall-clock), offer **A/B/C** and expect the user to pick **B (fully autonomous)** when the plan is well-specified and review loops are subagent-driven.

- **A** = phase-boundary check-ins
- **B** = fully autonomous until done
- **C** = task-by-task approval

**Why:** Phase-boundary reports add overhead without protecting work that is already being reviewed by spec-compliance and code-quality reviewer subagents. The user trusts the review mechanism inside the skill. Only genuine hard-blocks or externally-visible actions justify interrupting the chain.

**How to apply:**
- Present the cadence choice proactively for runs with more than ~10 tasks or more than ~1 hour estimated wall-clock.
- Honour B by not inserting routine phase-boundary updates during execution.
- Always surface hard-blocks (subagent reports BLOCKED, verification a subagent cannot resolve, externally-visible actions like creating issues or PRs) — those are not cadence overhead.
- Explicit in-plan human-approval checkpoints always stand regardless of cadence choice.

**Plan-size budget for single-session cadence-B runs:**
Each task in the subagent-driven-development skill costs approximately 3–5 subagent dispatches (implementer + spec reviewer + code-quality reviewer + occasional fix dispatch). Each dispatch returns several hundred to a few thousand tokens of summary into the controller's context. For plans with roughly 10 or more tasks, single-session execution will hit context pressure before completion.

- When dispatching execution of a plan with ≥10 tasks, expect to span multiple sessions. Don't pretend single-session is feasible.
- After the first task completes (one full impl + spec + code-quality cycle), surface a calibration offer: "Continue here?" vs. "stop now and resume in a fresh session." Each task's git commit on the feature branch is durable state — there is no continuity penalty for stopping mid-execution.
- Prefer stopping cleanly over degrading review discipline to push through in one session.

**Fix-commit budget — guideline, not hard rule:**
The standard "maximum 2 fix commits per review cycle" is a default to prevent mechanical nitpick spirals, not a ceiling. When a new reviewer finding (second bot round, quality gate flip) surfaces a real bug or security issue after the budget is used, surface it and ask. The user will generally confirm to continue. On the 3rd+ fix commit, surface context: what the finding is, whether it is a real bug vs. cosmetic, estimated blast radius — but do not assume the answer.
