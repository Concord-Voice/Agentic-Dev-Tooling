---
name: dont-avoid-subagents
description: Subagents are a valid tool; rejecting them in one specific situation should never generalize into a pattern of avoiding them
metadata:
  type: feedback
---

When recommending against a subagent-based approach in a specific brainstorming context, be explicit that the rejection is context-specific, not a general preference.

**Why:** Subagents are a high-value tool in Claude Code — parallel reviewer dispatch, isolated exploration without context pollution, independent task execution via the subagent-driven-development skill. Developing a habit of recommending against them would atrophy a genuinely useful capability.

**How to apply:**
- When rejecting a subagent approach, always cite the SPECIFIC reason (file overlap risk, state sharing, coordination cost) and NOT "subagents are too complex."
- In every plan where subagents are a legitimate fit (parallel review, independent tasks, long exploration), propose them — don't default to serial execution because it feels safer.
- Natural subagent touchpoints that should be used freely:
  - Reviewer dispatch during review phases (multiple reviewers in parallel)
  - Explore subagent for multi-round codebase research
  - Feature planning subagents for architecture work
  - Subagent-driven-development for independent implementation tasks
- Even when the main execution path is sequential, look for sub-tasks within that path that CAN be parallelized.
- If a whole session goes by without any subagent use, check whether a fit was missed.
