# Recursive Criticism and Improvement (RCI) Workflow

After generating security-sensitive code, AI tools should review their own output for vulnerabilities before presenting it. Combined with security-focused prompting, this pattern is expected to raise secure code generation rates substantially (see the directional estimates in `model-security-baselines.md`).

## When to Apply

RCI is mandatory when generating or modifying:

- Authentication/authorization code (auth, sessions, JWT, MFA, RBAC)
- Cryptographic code (key generation, encryption, decryption, hashing, signing)
- E2EE implementation (key exchange, message encryption, key derivation)
- Code handling PII, financial data, or compliance-regulated content
- Security middleware (CORS, rate limiting, input validation)
- Electron IPC handlers and preload bridge code
- Database migrations affecting security-sensitive tables (users, sessions, keys, permissions)

## The RCI Pattern

1. **Generate** the code as requested.

2. **Review** the generated code against:
   - OWASP Top 10:2025 categories (injection, broken auth, sensitive data exposure, etc.)
   - CWE/SANS Top 25 most dangerous software weaknesses
   - Hardcoded secrets or credentials
   - Injection flaws (SQL, XSS, command injection, log injection)
   - Project-specific constraints from CLAUDE.md "AI Code Generation Security Constraints" section

3. **Fix** any issues found.

4. **Iterate** — for complex security code (auth flows, crypto, E2EE), perform at least one additional review-and-fix cycle.

5. **Present** the reviewed code with a brief note on what you checked.

## SAST Simulation

When generating code, mentally simulate running the project's static analysis tools:

- **ESLint** — no `eval`, no `dangerouslySetInnerHTML`, no `innerHTML`, no `any` in security paths
- **golangci-lint (gosec)** — SQL injection, hardcoded credentials, weak crypto, unhandled errors
- **SonarQube** — cognitive complexity, code smells, security hotspots, coverage gaps
- **Custom Semgrep rules** — project-specific patterns (kept in the consuming project's Semgrep config)

## Example

```
Developer: "Add a password reset endpoint"

AI generates endpoint code, then self-reviews:
  - [x] Rate limiting applied? Yes — per-IP and per-user
  - [x] Token expiry? Yes — 15-minute single-use reset token
  - [x] Constant-time comparison? Yes — crypto/subtle.ConstantTimeCompare
  - [x] Hardcoded secrets? None found
  - [x] SQL injection? Using parameterized queries ($1, $2)
  - [x] Error messages? Generic "invalid or expired token" — no info leak
  - [x] Fail-open? No — denies by default on any error
  
AI presents code: "Generated password reset endpoint. Self-reviewed for
OWASP Top 10 and CWE Top 25. Rate limited, constant-time token comparison,
parameterized queries, generic error messages."
```

## Related Documents

- CLAUDE.md — "AI Code Generation Security Constraints" section
- Your project's AI-generated code policy
- [Model Security Baselines](model-security-baselines.md)
