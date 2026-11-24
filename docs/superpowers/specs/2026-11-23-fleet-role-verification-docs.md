# Fleet role verification handoff

On a Claude or Codex role collision, selection returns an enrolled alias such as `fleet-architect`. Verification accepts the canonical role and uses the selected physical profile to identify the alias. The shared instructions must preserve both values. The verifier, role permissions, source pinning, and host attestation stay in place.

Acceptance requires a selected alias to verify from the documented commands with the same path and digest on both clients.
