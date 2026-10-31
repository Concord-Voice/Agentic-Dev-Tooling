---
agent: "ask"
description: "Generate tests following the project's testing conventions for Go and TypeScript"
---

Generate tests for the provided code following the project's conventions.

## Go Test Conventions

- **Framework:** stdlib `testing` + `stretchr/testify` (assert, require)
- **File naming:** `*_test.go` in the same package
- **Subtests:** `t.Run("descriptive case", func(t *testing.T) { ... })`
- **Preconditions:** `require` (stops on failure), **Checks:** `assert` (continues)
- **Race detection:** tests run with `-race` in CI
- **Integration tests:** use real PostgreSQL + Redis via Docker in CI

### Required Test Cases
1. Happy path — valid input produces correct output
2. Validation error — bad input returns appropriate error
3. Auth error — missing/invalid credentials
4. Permission error — insufficient RBAC permissions
5. Not found — resource doesn't exist
6. Edge cases — empty input, max length, concurrent access

## TypeScript/React Test Conventions

- **Framework:** Vitest + @testing-library/react
- **File naming:** `*.test.ts` or `*.test.tsx` in `tests/unit/`
- **State reset:** Always `resetAllStores()` in `beforeEach`
- **Auth setup:** `useAuthStore.getState().setAccessToken('mock-token')`
- **API mocking:** Prefer MSW (Mock Service Worker) for API calls; stub global `fetch` only when MSW isn't applicable
- **Fixtures:** Use factory functions (`mockUser`, `mockServer`)
- **Selectors:** Prefer `getByRole`, `getByText` over `getByTestId`

### Coverage Requirements
- Coverage provider: Istanbul (not v8)
- SonarQube enforces >= 80% on new code
- Every new source file needs a corresponding test file
- Every new function: at least one happy-path and one error-path test

Reference: your project's test rule and instruction files, if it has them
