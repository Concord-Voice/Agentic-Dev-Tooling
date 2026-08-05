---
name: commit-message-format
description: The commit-msg hook rejects parenthesized scopes — use bare `type:` not `type(scope):`; squash PR titles bypass the local hook
metadata:
  type: project
---

The project's `commit-msg` pre-commit hook enforces a stricter Conventional Commits format than the full spec allows: commit messages must match `<type>: <description>` with no parenthesized scope.

**Valid:**
- `feat: add username validation`
- `fix: resolve race condition in websocket hub`
- `docs: add runbook for key compromise`
- `chore: update pre-commit hook configuration`

**Invalid (rejected by hook):**
- `feat(auth): add username validation`
- `fix(rbac): resolve race condition`
- `docs(specs): add runbook`

**Why:** The project convention chose simplicity over the full Conventional Commits scope syntax — keeps commit log scanning consistent and avoids scope-naming debates on a small team.

**How to apply:**
- Use one of the allowed types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `style`, `perf`, `ci`, `revert`.
- Omit any `(scope)` — put scope information in the description body if it matters.
- If a commit attempt is rejected by this hook, the commit did NOT happen — retry with a NEW commit, do NOT `--amend`.

**Squash-PR-title caveat:** GitHub squash merges use the PR title verbatim and do NOT run local pre-commit hooks. A PR title like `docs(runbook): foo` lands on the main branch even though the local hook would reject it. PR-title validation requires a separate CI workflow (not enforced by the local hook alone).
