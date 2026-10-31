# Agentic-Dev-Tooling

<a href="https://sonarcloud.io/summary/new_code?id=Concord-Voice_Agentic-Dev-Tooling"><img align="right" src="https://sonarcloud.io/api/project_badges/quality_gate?project=Concord-Voice_Agentic-Dev-Tooling" alt="Quality gate" /></a>

[![Lines of Code](https://sonarcloud.io/api/project_badges/measure?project=Concord-Voice_Agentic-Dev-Tooling&metric=ncloc)](https://sonarcloud.io/summary/new_code?id=Concord-Voice_Agentic-Dev-Tooling)
[![Security Rating](https://sonarcloud.io/api/project_badges/measure?project=Concord-Voice_Agentic-Dev-Tooling&metric=security_rating)](https://sonarcloud.io/summary/new_code?id=Concord-Voice_Agentic-Dev-Tooling)
[![Reliability Rating](https://sonarcloud.io/api/project_badges/measure?project=Concord-Voice_Agentic-Dev-Tooling&metric=reliability_rating)](https://sonarcloud.io/summary/new_code?id=Concord-Voice_Agentic-Dev-Tooling)
[![Maintainability Rating](https://sonarcloud.io/api/project_badges/measure?project=Concord-Voice_Agentic-Dev-Tooling&metric=sqale_rating)](https://sonarcloud.io/summary/new_code?id=Concord-Voice_Agentic-Dev-Tooling)
[![ci](https://github.com/Concord-Voice/Agentic-Dev-Tooling/actions/workflows/ci.yml/badge.svg)](https://github.com/Concord-Voice/Agentic-Dev-Tooling/actions/workflows/ci.yml)
[![static-analysis](https://github.com/Concord-Voice/Agentic-Dev-Tooling/actions/workflows/static-analysis.yml/badge.svg)](https://github.com/Concord-Voice/Agentic-Dev-Tooling/actions/workflows/static-analysis.yml)

[![AI Code Assurance](https://sonarcloud.io/api/project_badges/ai_code_assurance?project=Concord-Voice_Agentic-Dev-Tooling)](https://sonarcloud.io/summary/new_code?id=Concord-Voice_Agentic-Dev-Tooling)
[![license](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)
[![security](https://img.shields.io/badge/security-policy-green)](https://github.com/Concord-Voice/.github/blob/main/SECURITY.md)
[![platforms](https://img.shields.io/badge/platforms-Claude%20Code%20%7C%20Codex%20%7C%20Copilot%20%7C%20Antigravity-blue)](./CAPABILITIES.md)
[![SonarQube Cloud](https://sonarcloud.io/images/project_badges/sonarcloud-dark.svg)](https://sonarcloud.io/summary/new_code?id=Concord-Voice_Agentic-Dev-Tooling)

A portable library of AI development tools: skills, agents, hooks, and guardrails.

**Website:** [www.concordvoice.com](https://www.concordvoice.com) | **Wiki:** [Agentic-Dev-Tooling wiki](https://github.com/Concord-Voice/Agentic-Dev-Tooling/wiki) | **Security:** security@concordvoice.com

---

## Introduction

Concord Voice is a privacy-first place to talk with your friends, your community, or your team. It gives you voice calls, video, screen sharing, and chat. Your device encrypts each message before it leaves, so our servers store your messages only as scrambled data that we cannot read. You can use our hosted service, or you can run the same software on your own hardware.

Concord Voice uses AI coding assistants every day. This repository shares the tools that keep those assistants safe and consistent.
Anyone can use them.

One source tree installs into several AI coding tools. Each tool supports a different subset, and [CAPABILITIES.md](CAPABILITIES.md) lists the gaps honestly.
Read it before you trust a hook to survive the trip to another platform.

For guides and background, see the [Agentic-Dev-Tooling wiki](https://github.com/Concord-Voice/Agentic-Dev-Tooling/wiki).

---

## Technical overview

A portable, attributed library of AI dev-tooling — skills, agents, hooks,
guardrail scripts, MCP config templates, and an installer — refined over
months of real use running a multi-service product's development lifecycle,
and generalized here for any team to adopt. One canonical Claude-native
source tree compiles to Claude Code, OpenAI Codex, GitHub Copilot, Google
Gemini CLI, and Google Antigravity via `install.sh`. Every layer's actual,
verified per-platform coverage — including the gaps — is documented in
[`CAPABILITIES.md`](CAPABILITIES.md); read it before you rely on a hook or
subagent surviving conversion to a non-Claude platform.

### Quickstart

Clone the repo, `cd` into it, then run one `install.sh` command per platform
you use. Every command accepts `--project <path>` (default: current
directory); `claude` additionally accepts `--user` for a user-scope install
into `$HOME/.claude` (the other subcommands have no user-scope target and
exit 2 if you pass `--user` to them). Every install is safe to re-run: files
that already match are left alone, files you've hand-edited are skipped
unless you pass `--force`.

```bash
./install.sh claude      [--project <path>|--user] [--with-fleet] [--force]
# installs skills, agents, hooks, and repo-config docs natively into .claude/;
# merges hook wiring into settings.json non-destructively. --with-fleet adds
# the Claude-desktop-only multi-session supervision pack.

./install.sh codex       [--project <path>] [--force]
# compiles via rulesync into AGENTS.md, .agents/skills/, .codex/hooks.json,
# config.toml.

./install.sh copilot     [--project <path>] [--force]
# compiles via rulesync into .github/copilot-instructions.md and hooks (only
# UserPromptSubmit-shaped hooks survive); .vscode/mcp.json is written as an
# empty scaffold ({"servers": {}}) — populate it by hand (see CAPABILITIES.md).

./install.sh gemini      [--project <path>] [--force]
# writes GEMINI.md directly (no rulesync target exists for Gemini CLI, which
# was sunset for consumer use in 2026-06). Prefer antigravity unless you're
# on Gemini Enterprise Code Assist.

./install.sh antigravity [--project <path>] [--force]
# compiles via rulesync into AGENTS.md, .agents/skills/, .agents/hooks.json
# (partial — one hook event dropped), and an empty MCP scaffold; project-scope
# permissions are dropped entirely (see CAPABILITIES.md).

./install.sh imports
# prints fetch-from-source instructions for third-party marketplace plugins
# (superpowers, mattpocock-skills, pr-review-toolkit, ponytail) and the
# graphify CLI; if the claude CLI is present, it also prints the
# marketplace-add/install commands to run — it does not execute them for you.

./install.sh doctor
# checks prerequisites (git, jq, gh, npx) and prints a summary of key
# capability gaps.
```

Claude Code users can alternatively add this repo as a plugin marketplace
(`.claude-plugin/marketplace.json`) and install individual packs — see "What's
inside" below. That route covers **skills, agents, and hooks** (each pack's
hooks register from its own `hooks/hooks.json`, with no `settings.json` edit).
It does **not** deliver the two project-level pieces `install.sh claude`
installs: `scripts/repo-config.sh` (the `rc_get`/`rc_has` helper skills source
to read `.claude/repo-config.json`) and the path-scoped rules docs that land in
`.claude/rules/`. If you go marketplace-only, run `install.sh claude` as well,
or copy `scripts/repo-config.sh` and `docs/rules/*.md` into your repo by hand —
otherwise the config-driven steps degrade to their defaults and rules-file
references resolve to nothing.

#### Keeping a repo current

`install.sh claude` records what it wrote in `.claude/.agentic-dev-tooling.lock`. Commit
that file with the install. On a later run, a file that still matches the lock takes the
upstream update, and a file you edited is skipped (`--force` overrides). A repo installed
before the lock existed has no record, so every file that differs is skipped: run
`install.sh claude --force` once on a clean tree, review the diff, and commit the lock. To re-run it on a
schedule, copy [`templates/sync-tooling.yml`](templates/sync-tooling.yml) into your repo's
`.github/workflows/`. It opens one draft PR when something changed, using a GitHub App token it
mints at runtime (`SYNC_APP_CLIENT_ID` variable, `SYNC_APP_PRIVATE_KEY` secret).

### What's inside

Seven themed plugins, installable individually via the Claude Code
marketplace or in combination via `install.sh`:

| Plugin | Contents |
|---|---|
| `core-lifecycle` | The `/dev-lifecycle` orchestrator plus `/issue-creation`, `/pr-creation`, `/enhanced-pr-review`, `/ci-status`, `/review-pr`, `/issue-brief`, `/reproduce-then-fix`, `/verify-quality-gate`, the generic agent roster (architect, reviewers, developers), and the design-panel workflow. |
| `guardrails` | Safety hooks: destructive-command gate, env/secret protection, sensitive-path protection, secret detection, auto-format, test reminders, issue-creation nudge, applied-migration protection. |
| `release-ops` | `/release-notes`, `/release-checklist`, `/weekly-deps`, `/phase-status`, `/feedback-triage`. |
| `reviewer-packs` | Specialist reviewers: `migration-reviewer`, the `red-team` exploit-construction methodology, plus fill-in templates for RBAC, crypto, and deployment-config reviewers you complete for your own stack. |
| `fleet` | Multi-session supervision (`/supervise` + session handshake). Requires the Claude Code desktop session-management MCP; degrades to a no-op elsewhere. Opt-in via `--with-fleet`. |
| `writing` | `/ste-writing` (ASD-STE100 plain technical English), `/i-have-adhd` (opt-in action-first output style for ADHD readers; "stop adhd mode" ends it), `/ipc-channel-audit`, `/create-migration`. |
| `starter-memory` | Optional curated pack of generic facts about `gh`/git/CI/subagent workflows, useful as a seed for your own project memory. Not auto-loaded — see [`plugins/starter-memory/README.md`](plugins/starter-memory/README.md) for how to consume it. |

Full per-pack descriptions live in
[`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json).

### Configuration

Most skills read an optional `.claude/repo-config.json` at your repo's root —
the portability seam between this generic tooling and your project's
specifics (project-board IDs, label taxonomy, migration directory,
docs-drift mapping, weekly-deps tiers, and more). It is entirely optional:
every key, and the file itself, can be absent. Skills read it through
`scripts/repo-config.sh`'s `rc_get '<jq-filter>' [default]` / `rc_has
'<jq-filter>'` helpers, which **degrade gracefully** on any missing key or
missing file — a skill never errors because you haven't configured it, it
just skips that feature. `install.sh claude` copies both
`config/repo-config.example.json` (a filled-in sample) and
[`config/repo-config.reference.md`](config/repo-config.reference.md) (the
full key-by-key reference) into your `.claude/` directory.

MCP servers follow the same "secret-free template, opt-in" pattern.
[`config/sonarqube.mcp.json`](config/sonarqube.mcp.json) is the example:
a stdio MCP server definition with no secrets committed — `SONARQUBE_TOKEN`
and `SONARQUBE_ORG` are pulled from your environment via `${VAR}` expansion
at runtime, and Claude Code refuses to start the server until they're
exported. It is never installed automatically; copy it into your own
`.mcp.json` when you want SonarQube-backed skills, and gate them behind
`quality_gate.enabled` in `repo-config.json`. See
[`config/mcp-README.md`](config/mcp-README.md) for setup.

### Third-party & attribution

Nothing here is vendored except where a confirmed redistribution license
allows it — `plugins/writing/skills/ste-writing` and
`plugins/writing/skills/i-have-adhd` are the two exceptions, each kept with its
upstream `LICENSE.upstream` beside the tree. Everything else in the
launch roster (`superpowers`, `mattpocock-skills`, `pr-review-toolkit`,
`ponytail`, `graphify`, and `rulesync` itself) is fetched from its own
upstream source at use time — via `install.sh imports`, a Claude Code
marketplace add, or the tool's own install instructions — never copied into
this repo. Every item, including this repo's own original content, carries
an attribution record. The source of truth is
[`imports/attributions.json`](imports/attributions.json); the human-readable
render is [`ATTRIBUTIONS.md`](ATTRIBUTIONS.md) (regenerate with
`scripts/generate-attributions.sh`, never hand-edit it). Fetch instructions
for every third-party import live in
[`imports/README.md`](imports/README.md).

### Maintenance note

This public repo is the upstream. A private internal tooling repo imports
from it, so edits made here flow down. Most of `plugins/` is generated
content rather than hand-edited, so a PR against a file that looks generated
may be superseded by the next regeneration rather than a true merge conflict — PRs are
most durable when they target `install.sh`, the templates under
`plugins/reviewer-packs/templates/` and `*.template` files, or genuinely
repo-local content like this README. Every publish is scrubbed through
`scripts/publish-guard.sh` against a deny-list of org-internal identifiers
before it ships (a private allow-list names the few exact strings, such as
badge URLs, that may still appear), so open an issue rather than a PR if you spot something that
looks like it leaked.

Contributors: run `git config core.hooksPath .githooks` once after cloning to
activate the local pre-commit publish guard.

### Static analysis
CI (`.github/workflows/static-analysis.yml`) runs two blocking jobs:

- **ShellCheck** (pinned v0.11.0) via `.github/scripts/lint-shell.sh`, over every
  tracked shell script. It blocks on errors and warnings, plus SC2251
  (a bare `! cmd` that `set -e` ignores, which silently disables a test
  assertion). Other info/style notes are advisory.
- **Semgrep** (pinned 1.180.0; `r/bash`, `p/python`, `p/github-actions`,
  `p/security-audit`, `p/secrets`) fails on WARNING and ERROR findings.

Fix findings rather than suppress them. A genuine false positive gets an
instance-level `# shellcheck disable=SCxxxx # reason` or
`# nosemgrep: <rule-id> -- reason`; never disable a rule repository-wide. Run
`.github/scripts/lint-shell.sh` locally before pushing shell changes.

---

## Security

Report a vulnerability by email to security@concordvoice.com. Do not open a public issue for it. The [security policy](https://github.com/Concord-Voice/.github/blob/main/SECURITY.md) describes the disclosure process.

---

## Contributing

We welcome help. Read the [contributing guide](https://github.com/Concord-Voice/.github/blob/main/CONTRIBUTING.md) and the [code of conduct](https://github.com/Concord-Voice/.github/blob/main/CODE_OF_CONDUCT.md) before you open a pull request. Report bugs and request features in our [feedback repository](https://github.com/Concord-Voice/Concord-Voice/issues).

---

## License

MIT. See [LICENSE](LICENSE). Third-party imports keep their own upstream licenses, as [Third-party & attribution](#third-party--attribution) describes.

---

## Contact

- **Website:** [www.concordvoice.com](https://www.concordvoice.com)
- **Security:** security@concordvoice.com
- **Privacy:** privacy@concordvoice.com
- **General:** contact-us@concordvoice.com
