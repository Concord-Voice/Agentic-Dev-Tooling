# CAPABILITIES.md

`install.sh <platform>` compiles this repo's Claude-native source tree into
each target platform's own format. Claude Code is served directly; Codex,
Copilot, Gemini CLI, and Antigravity are served through a pinned compiler,
[rulesync](https://github.com/dyoshikawa/rulesync) `16.7.0` (MIT, by
dyoshikawa). This document is the honest result of actually running that
pipeline against this repo's real content — not the original design
assumptions. Where a cell says "converted" or "native", it was verified by
running `install.sh` against a scratch target and inspecting the output — every
deviation that verification turned up is written into the "Known non-portables"
section below rather than left in a side document.

## Platform × layer matrix

| | Skills | Instructions | Subagents | Hooks | MCP | Commands |
|---|---|---|---|---|---|---|
| **Claude Code** | native — `.claude/skills` | native — path-scoped rules docs at `.claude/rules/` (`--project` only); `CLAUDE.md` is a seeded root doc used to stage the other platforms | native — `.claude/agents` | full — `.claude/settings.json`, merged non-destructively | **manual, opt-in template** — `config/sonarqube.mcp.json` (secret-free) is never installed automatically; copy it into `.mcp.json` yourself | native (skills double as commands) |
| **Codex** | raw-copied — `.agents/skills/<name>/` (not rulesync-transformed) | `AGENTS.md` (rulesync-generated) | **none** — not converted | converted — `.codex/hooks.json` (rulesync) | **not emitted at all** — `.codex/config.toml` carries permissions only, no `[mcp_servers]` section; configure `~/.codex/config.toml` by hand | — (Codex has no separate command layer here) |
| **GitHub Copilot** | not copied by `install.sh copilot` itself — Copilot reads `.claude/skills` and `.agents/skills` natively, so skills only reach it if `install.sh claude` and/or `install.sh codex`/`antigravity` was also run against the same root | `.github/copilot-instructions.md` (rulesync) | **none** — not converted | **partial** — only `UserPromptSubmit`-shaped hooks survive; `PreToolUse`/`PostToolUse` guardrails (destructive-commands, protect-env-files, protect-sensitive, auto-format, test-reminder) are dropped | **empty scaffold only** — `.vscode/mcp.json` is written as `{"servers": {}}`; populate it by hand per Copilot's MCP docs | — |
| **Gemini CLI** | not installed by this platform target | `GEMINI.md` only — direct copy of the seeded root doc, **not** rulesync-generated | **none** | **none** | **none** | **none** |
| **Antigravity** | raw-copied — `.agents/skills/<name>/` (not rulesync-transformed) | `AGENTS.md` (rulesync-generated; no non-root `.agents/rules/` content shipped yet) | **none** — not converted | **partial** — `beforeSubmitPrompt`/`UserPromptSubmit` (detect-secrets.sh) is dropped; `PreToolUse`/`PostToolUse` guardrails (destructive-commands, protect-env-files, protect-sensitive, auto-format, test-reminder) convert and are retained | **empty scaffold only** — `.agents/mcp_config.json` is written as `{"mcpServers": {}}`; populate it by hand per Antigravity's MCP docs | — |

Legend: "native" = the platform reads this repo's Claude-native files
directly, no compilation step. "converted" = rulesync transforms it.
"raw-copied" = installed via a plain file copy, not rulesync's importer.
"—" = platform has no equivalent layer this installer targets.

None of the five MCP cells above ship a real, populated server list for any
platform — `config/sonarqube.mcp.json` is the one example template in this
repo, and it's Claude-only and manual. See "Future work" below.

## Known non-portables

These are disclosed deliberately, not silently dropped. `install.sh` prints a
matching `NOTE:` at install time for every item below that's runtime-visible,
and `doctor` summarizes them in one line.

- **Subagents never convert, on any non-Claude platform.** rulesync's
  `import --targets claudecode` hard-fails (exit 1) on this repo's real
  `.claude/agents/*.md` frontmatter — any `description:` containing `": "`
  inside an unquoted YAML scalar (e.g. `researcher.md`) breaks rulesync's
  strict parser. Since the install pipeline chains commands with `&&`, a
  failing subagent import would abort the whole run, so subagent import is
  excluded entirely. Codex, Copilot, Gemini, and Antigravity installs ship
  **no** subagent layer.
- **Skills also hard-fail rulesync's importer** on real content, for two
  independent reasons: `.claude/skills/_shared` has no `SKILL.md` by design
  (a real cross-skill dependency, not a template — several skills reference
  it via relative links), which rulesync's importer requires and aborts
  without; and several skills (`ci-status`, `dev-lifecycle`,
  `reproduce-then-fix`, `review-pr`, ...) use an unquoted
  `argument-hint: [foo]`, which YAML parses as a one-element array where
  rulesync's schema requires a string. Skills are therefore installed by
  plain directory copy into `.agents/skills/<name>/` for Codex and
  Antigravity — the verified native skills path for both — rather than
  through rulesync's transform. Codex's actual frontmatter tolerance for
  Claude-specific extra keys (`allowed-tools`, `argument-hint`, etc.) is
  unverified beyond this, since the Codex CLI itself was not run against the
  output.
- **Copilot hooks are partial, not absent.** rulesync 16.7.0 does support
  Copilot hook conversion, but only for hooks shaped like `UserPromptSubmit`
  (Copilot's `userPromptSubmitted`). `PreToolUse`/`PostToolUse` matcher hooks
  — every guardrail in `plugins/guardrails` (destructive-command gate,
  env/secret protection, sensitive-path protection, auto-format, test
  reminders) — are skipped with a warning printed to stderr by rulesync
  (`Skipped matcher hook(s) for copilot (not supported): postToolUse,
  preToolUse`) and are not present in the installed Copilot output at all.
- **Antigravity hooks are also partial.** The `UserPromptSubmit`-mapped hook
  (`detect-secrets.sh`, mapped from `beforeSubmitPrompt`) is unsupported by
  rulesync's `antigravity-cli` target and is dropped silently by rulesync
  (stderr-only warning); other hook events convert normally.
- **Antigravity's permissions layer is global-scope only.** rulesync reports
  `Target 'antigravity-cli' supports the feature 'permissions' only in global
  scope` and skips it. A `--project`-scoped install therefore never writes
  Antigravity permissions; only a `--global` rulesync invocation would (this
  installer does not expose that flag).
- **Gemini CLI has no rulesync target at all**, consistent with the consumer
  Gemini CLI's 2026-06 sunset — rulesync's supported-tools table lists only
  the two Antigravity targets under the Gemini config-tree family, no plain
  Gemini CLI id. `install.sh gemini` therefore bypasses rulesync entirely and
  writes `GEMINI.md` as a direct copy of the same seeded root doc used to
  stage the Claude import — a real but minimal instructions file, not a
  rulesync-rendered one. Skills, hooks, MCP, and commands are not installed
  for this target. Use `antigravity` instead unless you're specifically on
  Gemini Enterprise Code Assist.
- **`fleet/` pack is Claude-desktop only**, opt-in via `--with-fleet`. It
  depends on the Claude Code desktop session-management MCP
  (`mcp__ccd_session_mgmt`) and is a no-op without that host — it is never
  installed for non-Claude platforms, and is skipped on Claude installs
  unless `--with-fleet` is passed.
- **graphify is an external CLI, fetch-only.** It is not a skill or agent
  tree bundled in this repo; `red-team` pairs well with a graphify-style
  external scanner when your setup provides one, but ships with none
  declared. See `imports/README.md` for fetch instructions.
- **Copilot never receives skills from `install.sh copilot` alone.** Copilot's
  native ability to read `.claude/skills` and `.agents/skills` only helps if
  one of those directories already exists on the target root — which means
  running `install.sh claude` (writes `.claude/skills`) and/or
  `install.sh codex` or `antigravity` (writes `.agents/skills`) against the
  same `--project` path first. `install.sh copilot` by itself installs
  instructions and (partial) hooks; the MCP file it writes is an empty
  scaffold, not real server config.
- **Hook script paths only resolve when `install.sh claude` also targets the
  same root.** The generated `.codex/hooks.json` and Antigravity's
  `.agents/hooks.json` still reference `.claude/hooks/*.sh` relative paths.
  If you install `codex` or `antigravity` into a project that never received
  `install.sh claude` against the same root, those hook commands point at
  files that don't exist.
- **`.agents/rules/` (non-root rule docs) is unpopulated for every
  platform.** `install.sh claude` stages the path-scoped rules docs into
  `.claude/rules/`, and rulesync does import them — but it renders them
  *inlined into the root file* (`AGENTS.md` / `GEMINI.md`) rather than as
  separate non-root detail docs. So the rules content does reach every
  rulesync-compiled platform; what is lost is the path scoping (the
  `paths:` frontmatter that makes a rule apply only to matching files),
  which becomes always-on prose. Non-Claude platforms therefore carry a
  larger root instructions file than Claude Code does.
- **SonarQube MCP is opt-in and inert by default.** `config/sonarqube.mcp.json`
  is a secret-free template (`${SONARQUBE_TOKEN}` etc. via env expansion); it
  is not installed automatically by any platform target and is gated behind
  `quality_gate.enabled` in `repo-config.json` for the skills that use it.

## Future work

- **MCP seeding from a shared source.** No platform target currently emits a
  populated MCP server list — Codex gets none at all, Copilot and Antigravity
  get empty `{}` scaffolds, and Claude's `config/sonarqube.mcp.json` template
  is copy-by-hand only. A follow-up could seed rulesync's staged import with
  this repo's MCP templates so `generate` renders them per platform, instead
  of leaving every non-Claude platform's MCP file empty. Tracked as a gap,
  not silently left out.

## How the compilation works

1. **Stage.** `install_claude` runs once into a throwaway `mktemp -d`
   directory (`$stage`), producing a Claude-native tree: `.claude/skills`,
   `.claude/agents`, `.claude/hooks`, `.claude/rules`, plus a seeded minimal
   root `CLAUDE.md` (this repo ships no root doc by default, and rulesync's
   importer reports "No rule files found" and imports nothing without one).
2. **Convert.** For non-Claude platforms, `npx rulesync@16.7.0 import
   --targets claudecode -f rules,mcp,hooks,permissions` reads `$stage` (rules,
   MCP, hooks, and permissions only — subagents and skills are excluded per
   the non-portables above), then `rulesync generate --targets <id>
   --output-roots <second tmp dir>` renders the platform-specific files into
   a **second** throwaway staging directory (`$genout`) — never directly into
   the adopter's project. Gemini bypasses this step and writes `GEMINI.md`
   directly from the staged root doc. **`$stage` never contains an MCP source
   file** (`install_claude` doesn't seed one), so the `mcp` feature has
   nothing real to import or render — this is why every generated MCP output
   is empty or absent rather than populated; see "Future work" below.
3. **Install via `copy()`, no-clobber.** Every file under `$genout` (and, for
   Claude, every file staged directly) is installed into the real target
   through the same `copy()` function: if the destination doesn't exist, it's
   created; if it exists and is byte-identical, nothing happens; if it exists
   and differs, the install is **skipped** with `skip (local changes, use
   --force): <path>` unless `--force` is passed, which overwrites it. This
   makes every platform's install idempotent and safe to re-run without
   destroying hand-edits — verified by hand-editing a generated `AGENTS.md`,
   re-running the installer, and confirming the edit survives until `--force`
   is passed.
4. **Report.** Any degradation the compiler applied (Copilot's dropped
   guardrail hooks, Antigravity's dropped `beforeSubmitPrompt` hook and
   global-only permissions, Gemini's non-rulesync path, the fleet pack's host
   dependency) is echoed as a `NOTE:` line on stdout during install, and
   summarized again by `install.sh doctor`.
