# Prompt Template: Authentication / Authorization Code

Use this template when asking AI tools to generate auth-related code for Concord Voice.

## Pre-filled Constraints

Include these constraints in your prompt or verify them in the output:

- [ ] **OWASP ASVS Level 2+** compliance for auth/session/access-control
- [ ] **Constant-time comparison** for tokens, session IDs, and password hashes (`crypto/subtle.ConstantTimeCompare` in Go, `timingSafeEqual` in Node.js)
- [ ] **Rate limiting** applied (per-IP and per-user) for login, registration, password reset, and MFA endpoints
- [ ] **Session invalidation** on password change, MFA enrollment/removal, and privilege escalation
- [ ] **JWT** — 15-minute access tokens, HttpOnly 30-day refresh tokens, ticket-based WebSocket auth (30s single-use)
- [ ] **Input validation** on all user-supplied fields (email format, password strength, username constraints)
- [ ] **Generic error messages** — "invalid credentials" not "user not found" or "wrong password"
- [ ] **No hardcoded secrets** — JWT secrets, API keys, and credentials from environment variables only
- [ ] **Parameterized queries** — no string concatenation for SQL
- [ ] **Argon2id** for password hashing (t=3, m=64MB, p=4) — never bcrypt, scrypt, or PBKDF2 for new code
- [ ] **Atomic operations** — token revocation, password changes, and MFA changes in database transactions

## Example Prompt

```
Generate a [password reset / MFA enrollment / session management] endpoint for Concord Voice.

Requirements:
- Go (Gin framework) handler with dependency injection pattern
- Parameterized PostgreSQL queries
- Rate limiting (per-IP + per-user)
- Constant-time token comparison
- Atomic session invalidation on success
- Generic error messages (no information disclosure)
- Tests with happy path + error cases

Follow OWASP ASVS Level 2 and the project's auth conventions in CLAUDE.md.
Apply the RCI self-review pattern before presenting the code.
```

## Related

- [RCI Workflow](../rci-workflow.md)
- CLAUDE.md — "AI Code Generation Security Constraints" > "Go Constraints"
- Go Backend Instructions
