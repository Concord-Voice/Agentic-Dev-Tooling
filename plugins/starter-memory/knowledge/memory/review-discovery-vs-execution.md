---
name: review-discovery-vs-execution
description: Separate review DISCOVERY from EXECUTION; present the findings/defer table and WAIT for approval before applying any fixes; dispatch a docs reviewer if docs changed
metadata:
  type: feedback
---

When running a PR review pass, two disciplines are non-optional:

**1. Every deferral must be defended in writing.**
For each finding you propose to defer rather than fix in-PR:
- Assign it exactly one category from the closed deferral allowlist the review skill defines
- Answer all causality-radius questions in writing — anything in-scope cannot be deferred on an "out of scope" basis alone
- Show what the in-PR fix would look like (even briefly) before claiming deferral is justified
- Use the required format token (e.g. `Defer (category: X, radius: in|out, issue: #NNN, fix-size: <N lines>)`)

Writing "Defer — see issue" without the gate work is a structural rationalization, not a valid deferral.

**2. The reconciliation table is a checkpoint, not a checklist.**
After building the full triage table:
- Present every action and every defer with its full written defense
- Then **STOP**
- Do not start editing files
- Literally write "Reply with go-ahead or per-row corrections" and wait for the developer's explicit approval

**Why:** The developer is the final judge on which findings to fix in-PR vs defer vs dismiss. Pre-emptively editing files mixes "discovery" and "execution" — they need to be separable so the developer can correct any rationalization or scope misjudgment before it lands.

**Docs reviewer:** if any documentation files were changed in the PR, dispatch a dedicated docs-reviewer agent as part of the review pass. Do not skip it on the assumption that doc changes are low-risk.

**How to apply:** Run the review subagents. Build the complete triage table, writing the full deferral defense inline in the Notes column for each defer candidate. Present the table to the developer. Wait. Do not run a single Edit or Write until the developer approves the table.
