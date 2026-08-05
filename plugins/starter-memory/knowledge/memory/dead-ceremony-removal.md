---
name: dead-ceremony-removal
description: For compliance stubs against non-functional features, prefer immediate single-PR removal over formal deprecation windows
metadata:
  type: feedback
---

When a compliance-ceremony endpoint or stub exists solely for a feature that is already non-functional (e.g., a GDPR erasure handler for telemetry that was never emitted, deprecation stubs around removed subsystems), skip formal two-phase deprecation windows and remove outright in a single PR.

**Why:** The canonical rationale for formal deprecation — giving external integrators or auditors signal before removal — is empty when the target feature was already inert in production. Ceremony without a subject is just dead code that must be removed later anyway. A deprecation window adds overhead and leaves misleading code in the repository for no benefit.

**How to apply:**
- Default to single-PR immediate removal when the feature being "complied against" was never actively serving real traffic or was already removed.
- Reserve formal two-phase deprecation (e.g., returning a deprecation header, then removal in a later PR) for cases where the endpoint is or was recently answering real requests from real integrators.
- When unsure, check production logs or usage data — zero traffic means zero signal loss from abrupt removal.
- Frame the PR as cleanup rather than deprecation to set accurate expectations for reviewers.
