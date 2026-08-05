---
name: gitar-agent-md-filename
description: "Gitar (SonarSource) reads singular lowercase `agent.md`, distinct from the `AGENTS.md` cross-tool convention; case matters on Linux"
metadata:
  type: project
---

The Gitar coding agent reads `agent.md` at the repo root for repo-level custom instructions — singular, lowercase. This is distinct from the dominant `AGENTS.md` cross-tool convention used by OpenAI Codex, Cursor, Aider, Gemini CLI, GitHub Copilot, and GitLab Duo. The two filenames are **not the same file** on case-sensitive filesystems (Linux CI, Gitar runners).

**Why:** Direct evidence from Gitar's configuration UI — the literal text "agent.md" appears in their org-global "Custom instructions" field description: *"Similar to an agent.md file at the repo level, but global. Repo-level agent.md files still apply on top of these instructions."* Web search snippets claiming "Gitar uses AGENTS.md" contradict this direct UI evidence and should be distrusted. On macOS APFS (case-insensitive by default), `agent.md` and `AGENTS.md` resolve to the same path, so the difference is invisible locally — but Gitar runs on Linux infrastructure where it matters.

**How to apply:**
- When integrating Gitar with any repo: create `agent.md` (singular, lowercase) at the repo root, NOT `AGENTS.md`.
- If the repo already has an `AGENTS.md` for other tools (Claude, Copilot, etc.), leave it in place — it serves a different audience. Create `agent.md` alongside it.
- Trust direct UI evidence (the product's own settings screen) over web snippets when documentation conflicts.
- SonarSource acquired Gitar in late 2025; future versions may converge with the dominant `AGENTS.md` convention. Re-verify filename discovery whenever upgrading the Gitar integration.
