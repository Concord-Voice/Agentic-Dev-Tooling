---
name: skill-steps-mandatory
description: Never skip an imperative skill step on equivalent-coverage reasoning — fresh-context review surfaces different findings than prior partial reviews
metadata:
  type: feedback
---

When a skill mandates a step with imperative language ("Run X", "Dispatch Y", "Invoke Z"), that step is mandatory. Do not skip it because:

- "Prior subagent reviews already covered this lens"
- "It would be redundant cycles"
- "I already have equivalent coverage from earlier work"

**Why:** The skill author built the step in deliberately. A fresh-context review of the merged whole-PR diff surfaces different findings than per-commit reviews, because the reviewer sees the cumulative change, not its parts. Specialist reviewers triggered by file patterns may have been skipped in piecemeal reviews and only fire correctly when reviewing the complete diff.

**How to apply:** If a skill numbers a step and uses imperative language, execute that step verbatim. If genuinely confident the step is redundant in a specific case, surface that concern to the user BEFORE skipping — never decide unilaterally. The default bias is: execute-the-step-as-written, document-the-result, then triage. New findings can always emerge; wasted cycles are recoverable; missed findings are not.
