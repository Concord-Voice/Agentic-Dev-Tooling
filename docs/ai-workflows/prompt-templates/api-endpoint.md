# Prompt Template: API Endpoint

Use this template when asking AI tools to generate REST API endpoints for this project.

## Pre-filled Constraints

Include these constraints in your prompt or verify them in the output:

- [ ] **Input validation** on all user-supplied fields — use Gin binding tags (`binding:"required"`, `binding:"email"`, etc.)
- [ ] **Parameterized queries** — `$1`, `$2` placeholders, never `fmt.Sprintf` for SQL
- [ ] **Rate limiting** — apply per-IP and per-user rate limits for public-facing endpoints
- [ ] **Authentication** — verify the JWT via auth middleware, then check the appropriate RBAC permissions
- [ ] **Error handling** — generic error messages to clients. Log the detailed error server-side only. No fail-open patterns
- [ ] **No sensitive data in responses** — never return password hashes, private keys, session tokens, or internal IDs in API responses
- [ ] **CORS** — the endpoint respects the existing CORS middleware, with no CORS bypass
- [ ] **HTTP method** — use appropriate method (GET for reads, POST for creates, PUT/PATCH for updates, DELETE for deletes)
- [ ] **Status codes** — correct HTTP status codes (201 Created, 400 Bad Request, 401 Unauthorized, 403 Forbidden, 404 Not Found, 409 Conflict, 500 Internal Server Error)
- [ ] **Transaction safety** — multi-step mutations in database transactions with proper rollback on error
- [ ] **Idempotency** — PUT/DELETE operations should be idempotent where possible

## Example Prompt

```
Generate a [resource CRUD / action] endpoint for the backend.

Requirements:
- Go (Gin framework) handler with dependency injection
- Auth middleware + RBAC permission check (e.g., manage_channels)
- Input validation via Gin binding tags
- Parameterized PostgreSQL queries in a transaction
- Rate limiting applied
- Generic error messages (no internal details to client)
- Tests with happy path + auth failure + validation failure + DB error cases

Follow the project's API conventions in its CLAUDE.md and backend instructions.
Apply the RCI self-review pattern before presenting the code.
```

## Related

- [RCI Workflow](../rci-workflow.md)
- CLAUDE.md — "AI Code Generation Security Constraints" > "Go Constraints"
- Go Backend Instructions
