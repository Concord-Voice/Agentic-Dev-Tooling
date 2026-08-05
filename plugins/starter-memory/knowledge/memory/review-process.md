---
name: review-process
description: Preferred PR lifecycle — Draft PR → CI → Ready → bot reviews → Claude review → merge; always verify bot findings technically before acting
metadata:
  type: feedback
---

The preferred PR lifecycle follows a strict sequence: Draft PR → CI validation (static analysis, secret scanning, tests) → mark Ready → automated code-review bot auto-triggers → Claude reviews bot feedback and runs its own review → finalize.

**Why:** Automated review tools produce some false positives and context-blind suggestions. Accepting bot feedback without technical verification leads to unnecessary changes or missed real issues. A fresh-context review of the whole-PR diff can surface findings that per-commit reviews missed.

**How to apply:** Always verify bot comments technically before acting on them. Use the `/superpowers:receiving-code-review` discipline. Push back with evidence when a bot finding is wrong. Reply to every automated comment individually with accept/pushback plus a commit reference. Never skip the Claude review step on the basis that the bot review "already covered it" — the two layers catch different things.
