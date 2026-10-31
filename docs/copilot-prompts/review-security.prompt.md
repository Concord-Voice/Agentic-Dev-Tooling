---
agent: "ask"
description: "Security-focused code review against OWASP Top 10 and project security policies"
---

Review this code for security vulnerabilities. Check against:

## OWASP Top 10 — Key Categories for Concord Voice
The project standard is the OWASP Top 10:2025 edition. Category names are used without
A-numbers here, because the A-numbering differs between editions and the same number maps to
different categories in each.

- **Injection** — SQL injection, command injection, XSS
- **Identification and Authentication Failures** — weak tokens, missing MFA, session fixation
- **Cryptographic Failures** — plaintext secrets, missing encryption, weak algorithms
- **Broken Access Control** — privilege escalation, IDOR, missing RBAC checks
- **Security Misconfiguration** — debug enabled, default credentials, permissive CORS

## Concord Voice Security Standards
- Parameterized queries only (`$1, $2` in Go, never `fmt.Sprintf`)
- `crypto/subtle.ConstantTimeCompare` for auth comparisons
- Argon2id for password hashing (t=3, m=64MB, p=4)
- AES-256-GCM for E2EE, RSA-OAEP 4096-bit for key wrapping
- No `eval()`, `dangerouslySetInnerHTML`, `innerHTML` without sanitization
- No `any` type in security-critical code paths
- No `@electron/remote`, `nodeIntegration`, disabled `contextIsolation`
- JWT access tokens: 15min TTL, refresh: 30d HttpOnly
- WebSocket: ticket-based auth (30s single-use)

## Review Output
For each finding, report:
1. **Severity** (CRITICAL / HIGH / MEDIUM / LOW)
2. **CWE ID** if applicable
3. **File and line**
4. **Description** of the vulnerability
5. **Fix recommendation**

Reference: `docs/policies/ai-generated-code-policy.md`, `docs/ai-workflows/rci-workflow.md`
