---
name: org-tooling-router
description: Use for organization- or repository-level work in Codex, especially when a task touches shared AI tooling, migrated Claude assets, hooks, MCP config, policies, or repo-local agent instructions.
---

<!-- TEMPLATE: copy this directory out of imports/, rename it and this skill for
     your organization, and complete every FILL slot before use. -->

# Organization Tooling Router

This skill does not carry project knowledge. It tells Codex where the
authoritative instructions live, so it reads them instead of guessing.

## 1. Start from the nearest agent instructions

Start from the active repository's nearest `AGENTS.md`. Treat the project
instructions it imports as the authoritative project contract for Codex work.

<!-- FILL: your AGENTS.md locations and what each one imports. One line per
     repository (or one line per tier if you use an org-level file plus
     per-repo files). State explicitly which file is the org-wide root and
     which repo-local files override it. Example shape — replace with yours:
       - `<org-workspace>/AGENTS.md` — org-wide root; imports the org CLAUDE.md
       - `<org-workspace>/<flagship-repo>/AGENTS.md` — imports that repo's
         CLAUDE.md; the authoritative contract for work in that repo -->

## 2. Prefer the shared tooling master

Use the shared tooling master as the source of truth for organization-wide AI
assets. Prefer reusing or syncing an existing shared asset over creating a
repo-local copy.

<!-- FILL: your master repository path (the checkout that owns the shared
     skills, agents, hooks, and rules) and how consumers reach it — the sync
     script to run, and the manifest that declares what is shared. See
     docs/org-tooling-distribution.md for the distribution mechanics this
     routing assumes. -->

## 3. Rules for migrated Claude assets

<!-- FILL: this section names Codex as the second agent runtime because that is
     the case it was written for. If your second runtime is something else,
     rewrite it in that runtime's terms — its agent-definition format and
     directory, its hooks manifest, its config file, and its MCP config path.
     The rule that survives any runtime: one source of truth in `.claude/`,
     with the other runtime's files POINTING at it rather than copying it. If
     Claude Code is your only runtime, delete this section entirely. -->

When working on assets shared between Claude Code and Codex:

- Keep Claude-owned source assets in `.claude/` unless a Codex-specific format
  is genuinely required.
- Keep Codex agent files pointed at the existing `.claude/rules/`,
  `.claude/skills/`, and `.claude/hooks/` assets rather than duplicating their
  content.
  <!-- FILL: your Codex surface paths — the agent-definition directory and
       format, the hooks manifest, and the Codex config file. -->
- Keep MCP allowlists and credential guidance aligned with the organization's
  MCP policy whenever an MCP config file changes.
  <!-- FILL: the path to your MCP server policy doc, and every MCP config file
       it governs (per-repo, editor-local, and Codex config). -->
- After changing any Codex migration surface, run the verification script that
  checks the migration is still coherent.
  <!-- FILL: that script's path, or delete this bullet if you have no such
       check — and note that an unverified migration surface drifts silently. -->
