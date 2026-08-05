---
name: subagent-factual-replacements
description: Doc-rewriting subagents may invent aspirational architecture; demand factual descriptions of what the live code actually does
metadata:
  type: feedback
---

When prompting a subagent to rewrite documentation references to a removed system, the replacement MUST describe what the live code actually does. Do not allow subagents to substitute aspirational architecture.

**Why:** Given latitude like "rewrite references to the old system in terms of the new approach," a subagent may extrapolate to a detailed description of a pipeline that does not exist. The actual code may emit simple log lines while the rewritten doc describes structured fields, fingerprints, and aggregation pipelines operators will never find. Operators reading the rewrite may build dashboards or alerts against fields that were never emitted.

**How to apply:**
1. Have the subagent grep the actual implementation file(s) FIRST and quote the exact log messages, API shapes, or observable behaviors before writing a single word of replacement prose.
2. Constrain their replacement to "what the code emits today" — never "what an idealized system would emit."
3. If the removed system was the ONLY source of a documented behavior, the replacement should say "we no longer have X" rather than inventing a substitute. "We no longer emit structured telemetry for this event; observe via raw console logs" is more useful than a fictional structured-logging description.
4. For runbook updates specifically, emphasize that operators will literally execute the described procedure — fabricated steps are operationally dangerous, not just a documentation quality issue.
