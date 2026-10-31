# Agentic AI Controls: Risk-Tiered HITL Framework

| Field          | Value      |
|----------------|------------|
| Effective Date | 2026-04-03 |
| Last Reviewed  | 2026-08-28 |
| Version        | 1.1        |
| Review Cadence | Quarterly  |
| Tracking Issue | #458       |

## Purpose

AI agents (Claude Code, Copilot Agent mode, Codex CLI) operate autonomously — reading files, executing commands, making API calls, and modifying code. Per OWASP's Top 10 for Agentic AI (Dec 2025), AI agents should be treated as untrusted third parties with the same controls applied to external contractors: least privilege, mandatory review, comprehensive audit logging, and strict data access restrictions.

This document defines the risk-tiered action framework, permission controls, and fail-safe mechanisms for agentic AI tools used in Concord development.

## Risk-Tiered Action Framework

| Risk Level | Action Type | Examples | HITL Requirement |
|---|---|---|---|
| **LOW** | Read operations | Read file, search code, grep, glob, list directory, git status/log/diff | Auto-approve |
| **MEDIUM** | Write operations, builds | Edit file, write file, run tests, npm run build, git commit | Prompt for approval |
| **HIGH** | External communication, data modification | Git push, create PR/issue, post to external services, modify CI config | Require explicit approval |
| **CRITICAL** | Irreversible or security-sensitive | Force push, delete branch, modify auth/crypto/E2EE code, access production credentials | **Blocked or require explicit approval + review** |

## Claude Code Permission Configuration

Project-level permissions are defined in `.claude/settings.json` (committed to the repo). These apply to all developers using Claude Code on Concord.

### Denied (CRITICAL — always blocked)

These commands are denied at the project level and cannot be overridden:

- `git push --force`, `git push -f` — destructive rewrite of remote history
- `git reset --hard` — discards uncommitted work
- `git checkout -- .` — discards all unstaged changes
- `git clean -f` — deletes untracked files
- `rm -rf`, `rm -r` — recursive deletion
- Read/Edit access to `~/.ssh/`, `~/.aws/`, `~/.config/gcloud/`, `~/.kube/` — credential and cluster config stores
- `Edit(~/.claude/plugins/**)`, `Write(~/.claude/plugins/**)`, and `Bash(./scripts/reapply-plugin-cache-customizations.py*)` — the plugin-cache write barrier added by #2665. A cache-resident skill file is code Claude Code executes, so an agent write there is a self-modification path; the `Bash(...)` entry closes the same path when it is taken through the recovery script rather than a direct `Edit`. See `.claude/rules/plugin-cache-customization.md` § Threat model. Two caveats from that file: `Read(~/.claude/plugins/**)` is **deliberately not** denied, because agents must read plugin `SKILL.md` files and denying reads would break skill loading for no security benefit; and the `Bash(...)` rule is keyed on the script path, so renaming or moving the script silently reopens the gap — move the deny rule in the same commit as any rename.

### Auto-approved (LOW — read-only operations)

These commands are auto-approved to avoid friction on safe operations:

- `git status`, `git log`, `git diff`, `git branch`, `git show`, `git blame`
- `ls`, `cat`, `head`, `tail`, `wc`, `find`, `which`
- `semgrep` (local SAST scanning)

**`git branch` is a glob, not a read-only claim.** The live rule is `Bash(git branch*)`, so it also matches the destructive delete form (`-D`). The permission layer auto-approves that form; what actually blocks it is the `destructive-commands.sh` hook described below. A per-invocation `env CLAUDE_HOOK_ALLOW_BRANCH_DELETE=1 ` prefix opts a single bare branch-delete command out of that block (#674). The hook detects that prefix in the command *text*, not in its own environment, so an exported variable grants nothing and the bypass cannot reach beyond the one command it prefixes.

### Everything else (MEDIUM/HIGH — prompted)

All other commands prompt for developer approval, including:

- File edits and writes
- `git commit`, `git push` (non-force)
- Build and test commands (`npm run`, `go test`, `go build`)
- PR/issue creation (`gh pr create`, `gh issue create`)
- MCP tool invocations

### Hook layer (`.claude/hooks/`)

`.claude/settings.json` matches on command and path patterns only. Six `PreToolUse` hooks are wired in the same file and run before the tool call, so they inspect the full tool input and block (exit 2) on conditions a deny glob cannot express. They are a second enforcement layer, not documentation:

| Hook | Matcher | What it blocks |
|------|---------|----------------|
| `protect-sensitive.sh` | `Edit` \| `Write` | Edits and writes to files matching `.hooks.protected_patterns[]` in `.claude/repo-config.json` (crypto, auth, MFA, RBAC, sessions, security/CORS/ratelimit middleware, Electron preload + IPC, provisioning scripts), unless the relative path is listed in the per-branch marker file `.claude/state/hook-bypass/<branch>.txt` |
| `destructive-commands.sh` | `Bash` | Destructive SQL statements, branch deletion, `git stash drop`, `git reflog expire`, `pkill`, and `killall` — the patterns the `settings.json` deny list does not catch |
| `protect-env-files.sh` | `Read` \| `Edit` \| `Write` | `.env` files (`.env.example` allowed), `credentials.json`, `*.pem`, `*.key` |
| `protect-applied-migrations.sh` | `Edit` | Edits to existing files under `services/control-plane/migrations/`. `Write` is deliberately not blocked, so a new migration can still be created |
| `graphify hook-guard search` | `Bash` \| `Grep` | Knowledge-graph query guard; a no-op when the `graphify` CLI is absent |
| `graphify hook-guard read` | `Read` \| `Glob` | The same guard on the read path |

The first four **fail closed**: a missing `jq`, malformed hook input, or an unresolvable repository root blocks the tool call instead of allowing it. The two scoped bypasses — the `protect-sensitive.sh` marker file and the `destructive-commands.sh` command prefix — are the only documented ways past them. See `.claude/hooks/README.md` § Scoped bypass channels.

### Personal Overrides

Developers can add personal preferences in `.claude/settings.local.json` (gitignored). Personal settings can be **more restrictive** but should not weaken project-level deny rules.

## Least Privilege and Credential Isolation

1. **No production credentials** — AI tools must never have access to production database credentials, API keys, TLS certificates, or signing keys.
2. **Scoped development credentials** — when AI tools need credentials for testing, use dedicated development credentials with no access to production or staging.
3. **Environment isolation** — AI tools operate in development/local environments only. Never run agentic tools against production or staging infrastructure.
4. **MCP server credential scoping** — MCP servers receive minimum necessary credentials. No shared "god token." See `docs/policies/mcp-server-policy.md`.

## Fail-Safe Behavior (NSA/CISA Guidance)

Per NSA/CISA joint guidance on AI data security, robust guardrails must ensure a malfunctioning or compromised AI model cannot unilaterally make or persist dangerous decisions:

1. **Manual override** — all AI tool actions can be interrupted, reverted, or overridden by the developer at any point. Claude Code supports Ctrl+C to cancel any operation.
2. **Scope limitation** — `.claude/settings.json` denies access to credential stores (`~/.ssh`, `~/.aws`, `~/.config/gcloud`, `~/.kube`), and the `protect-env-files.sh` PreToolUse hook additionally blocks `.env` files, `credentials.json`, `*.pem`, and `*.key` on read as well as on write (see [Hook layer](#hook-layer-claudehooks)). AI tools operate only within the project working directory.
3. **Network egress** — MCP servers that require network access are restricted to allowlisted endpoints (see MCP server policy). Claude Code itself communicates only with Anthropic's API.
4. **Timeout enforcement** — long-running operations have built-in timeouts. Claude Code Bash commands default to 120s timeout.
5. **Rollback capability** — all file modifications made by AI tools are tracked by git and revertible. No out-of-repo side effects should persist on failure.

## Audit and Observability

1. **Co-Authored-By trailers** — all AI-assisted commits include a `Co-Authored-By` trailer for traceability (see `docs/policies/ai-generated-code-policy.md`).
2. **Claude Code conversation logs** — retained locally for 90 days minimum for security-relevant sessions. This is **not** what the tool does by default: Claude Code expires session transcripts after 30 days unless `cleanupPeriodDays` is raised. See `docs/policies/audit-log-retention.md`.
3. **SonarQube scan history** — all PR scans archived in SonarQube Cloud.
4. **Semgrep CI comments** — every PR receives a Semgrep findings comment with severity-tiered results.
5. **Quarterly audit** — review AI-assisted commits touching security-sensitive paths during the quarterly AI security review (see `.github/ISSUE_TEMPLATE/quarterly-ai-review.md`).

## Tool-Specific Notes

| Tool | Permission Controls | Guardrail Mechanism |
|------|-------------------|-------------------|
| **Claude Code** | `.claude/settings.json` (project-level, deny/allow rules) **plus** the six `.claude/hooks/` PreToolUse hooks | Strongest — deny rules enforced by the runtime, with the hook layer above catching what a deny glob cannot express |
| **GitHub Copilot** | No project-level permission config | Instruction-file only (`.github/copilot-instructions.md`) |
| **OpenAI Codex** | `.codex/config.toml` (workspace sandbox and network policy) | Runtime sandbox/approval controls plus `.codex/hooks.json`, which executes self-contained `.codex/hooks/*.sh` copies generated from the current project and shared tooling sources |

Copilot lacks equivalent project-level runtime controls. Codex combines its runtime sandbox and approval policy with repository-declared hooks; `.github/instructions/codex-instructions.md` remains the human-readable policy reference. Hook support is runtime-dependent, so CI pipeline controls (Phase 3) remain the final enforcement backstop for every agent.

## GitHub Actions

Workflow actions extend our CI/CD pipeline's trust boundary. Each repository-qualified `uses:` reference delegates execution privilege to externally maintained code — a supply-chain risk equivalent in scope to the agent-side controls above. A compromised maintainer who force-pushes a version tag (`@v3`) can silently rewrite our workflow surface; a SHA-pinned reference is immutable.

**Pin posture (universal rule per #847):**

- **Every repository-qualified action** referenced in `.github/workflows/**`, `.github/actions/**`, or the public-mirror overlay MUST be pinned by full commit SHA, including GitHub-owned `actions/*` and `github/*`. Keep a trailing, bare `# vX.Y.Z` version comment. Example: `uses: dorny/paths-filter@fbd0ab8f3e69293af611ebaee6363fc25e6d187d # v4.0.1`. GitHub Actions ignores the comment, but Dependabot and reviewers rely on its exact bare form when updating and auditing the pin.
- **Local actions** (`./.github/actions/<name>`) are first-party by construction — they live in this repo and are reviewed via the same PR process as application code. No pinning required.
- **Enforcement** of the two bullets above is described in `.claude/rules/electron.md` § Supply-chain hardening — the rule id, the pack that carries it, and the gate path. This policy states the requirement; that section states the mechanism, and is the place to look when asking "what would actually stop a mutable ref from merging?" (#2426).

**Why this matters for agentic AI safety:** the agentic-AI framework above treats AI agents as untrusted third parties subject to least-privilege, audit, and review controls. GitHub Actions sit in the same category — externally maintained code with privileged access to the build pipeline, secrets, and signing material. Tag-pinning an action delegates that privilege to whatever commit its maintainer chooses to point the tag at — including post-publication. SHA-pinning binds the delegation to a specific commit reviewed at PR-time.

**Upgrade procedure:** see `docs/runbooks/upgrade-sha-pinned-action.md`. The runbook covers when to upgrade, pre-flight checks, SHA resolution via `gh api`, provenance verification (matching the SHA across at least two sources), the `supply-chain upgrade` PR label contract, smoke-dispatch path per action category, and rollback procedure.

Do not upgrade SHA-pinned actions speculatively. Each upgrade is a supply-chain trust delegation; the operational cost of "staying current" is non-trivial.

## Related Documents

- [AI-Generated Code Policy](ai-generated-code-policy.md)
- [MCP Server Policy](mcp-server-policy.md)
- Audit Log Retention
- CVE Watchlist
- CLAUDE.md — "Agentic Safety Constraints" section
- `.claude/settings.json` — project-level permission configuration
- SHA-Pinned Action Upgrade Runbook — operational procedure for upgrading SHA-pinned actions
- `.claude/rules/electron.md` — Supply-chain hardening section (path-scoped rule mirror of this policy)
