---
name: authorized-credential-use
description: When the user explicitly bounds a leaked credential's risk (read-only, short-TTL), honor that decision and proceed without re-litigating
metadata:
  type: feedback
---

When a user responds to a credential-leak flag by explicitly bounding the risk ("read-only, dies tomorrow", "ignore it and use it"), honor the decision: run the diagnostic, don't re-flag.

**Why:** Re-flagging after explicit authorization crosses from protection into friction. The user owns the risk; they've done the math and accepted the trade-off. Reflexive over-caution after a clear override reads as disrespect for judgment, not safety. Complements the velocity-vs-discipline principle: that rule guards against *under*-caution under speed pressure; this rule guards against *over*-caution when the user has scoped the risk themselves.

**How to apply:**
1. First exposure → one flag + recommend revocation. Always.
2. If user explicitly re-authorizes with scope bounds (read-only, short-TTL, single-purpose), proceed.
3. Do not lecture twice, do not hedge with "are you sure?" — that's friction dressed as caution.
4. Still avoid putting the credential into persistent artifacts (committed files, long-lived logs) — the authorization is for the current diagnostic, not for permanent storage.
