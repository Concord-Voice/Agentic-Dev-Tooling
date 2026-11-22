# Platform capabilities

Choose a target for each client that will open the consumer checkout. Use a full project install for the skills and their dependencies. Use `--agents-only` to refresh the portable specialist profiles in a checkout that already supplies its own skills, rules and hooks.

```sh
./install.sh codex --project ../my-project
./install.sh copilot --agents-only --project ../my-project
```

## Platform × layer matrix

| Target | Project instructions | Skills | Specialist profiles |
|---|---|---|---|
| Claude Code | Project rules in `.claude/rules/` | `.claude/skills/` | Markdown under `.claude/agents/`. The full install includes the Claude pack roster. |
| Codex | `AGENTS.md` | `.agents/skills/` | TOML under `.codex/agents/` for design, implementation, defensive review, read-only research, documentation and feedback analysis. |
| Antigravity | `AGENTS.md` | `.agents/skills/` | Markdown under `.agents/agents/` for code review, documentation, test writing and feedback analysis. |
| GitHub Copilot | `.github/copilot-instructions.md` | The Copilot target leaves skill installation to the other project targets. Copilot can discover skills in the resulting `.claude/skills/` or `.agents/skills/`. | `.github/agents/code-reviewer.agent.md` for PR review and analysis of supplied CI or tooling failure evidence. |
| Gemini CLI | `GEMINI.md` | — | — |

The `--agents-only` install works offline with Bash, jq and Python 3. It supports the four clients with specialist profiles. It installs the selected profiles and records their hashes. Claude receives the portable Codex roster in this mode. Install or provision any project rules and skills referenced by a profile before assigning work that requires them.

For a standalone checkout, keep project files and referenced resources available inside the checkout or provision them when the environment is built. Claude supports project skill directories that are symlinks when their targets exist. An absolute link into one developer's machine cannot supply that skill to a fresh cloud checkout. [Claude skill discovery](https://code.claude.com/docs/en/skills#choose-where-skills-load) · [Antigravity discovery](https://antigravity.google/docs/customization-discovery/)

## Dispatch and permissions

Use the host's native dispatch operation and the installed role name. For feedback classification, pass the sanitized report payload to `feedback-analyst` in an analysis session provisioned for that data. The Claude profile uses an explicit empty tool list, which Claude Code documents as a tool-free launch. [Claude tool-list behavior](https://code.claude.com/docs/en/errors#agent-would-be-spawned-with-zero-tools)

When a policy requires credential isolation, verify the host's actual credentials and tool access before dispatch. In particular, a Codex custom agent inherits its parent's permissions and MCP servers. Its supported feature switches can disable specific capabilities. A role file cannot independently enforce a read-only identity. [Codex custom agents](https://learn.chatgpt.com/docs/agent-configuration/subagents) · [Antigravity tool and permission inheritance](https://antigravity.google/docs/subagents/)

The GitHub review profile uses read and search tools. Supply a PR diff or relevant job failure evidence for the requested investigation. Automatic PR review is controlled by GitHub rulesets, and a failed workflow needs a configured trigger. Installing the profile alone schedules zero jobs. [GitHub custom agents](https://docs.github.com/en/copilot/concepts/customizations/custom-agents) · [GitHub automations](https://docs.github.com/en/copilot/concepts/agent-capabilities/agent-powered-workflows-and-operations/about-automations)

Codex profiles translate the Claude source model and effort using the literal model and effort table rows. The renderer resolves starred model families against the reviewed Codex CLI 0.171.0 catalog snapshot so an offline install produces the same pins. Update the snapshot from `codex debug models --bundled` when releasing new family versions. A missing model or unsupported effort on the target account makes that role unavailable. The GitHub custom review agent retains the source Opus class with the `claude-opus-5.5` ID listed by Copilot CLI 1.0.115-5. GitHub controls the model and billing for its separate automatic PR review service. Antigravity’s bounded roles select its native `flash` tier and inherit the host’s supported effort. [Model equivalence table](plugins/core-lifecycle/skills/_shared/model-equivalence.md) · [GitHub cloud model availability](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/cloud-agent/changing-the-ai-model) · [Antigravity agent configuration](https://antigravity.google/docs/subagents/)

## Hooks and MCP

| Target | Hook registration from a full install | MCP configuration from the installer |
|---|---|---|
| Claude Code | `.claude/settings.json` merges the base wiring with existing project hooks. `--with-fleet` adds the desktop supervision pack. | Optional SonarQube template in `config/sonarqube.mcp.json`. |
| Codex | rulesync emits `.codex/hooks.json`. | The generated `.codex/config.toml` contains permission configuration. Configure required servers or connectors for the trusted project or user. |
| Antigravity | `.agents/hooks.json` retains the converted pre- and post-tool hooks. The `antigravity-cli` target drops the prompt-submit hook and supports permission generation at global scope only. | Empty `.agents/mcp_config.json` scaffold. |
| GitHub Copilot | rulesync retains the prompt-submit hook. It drops pre- and post-tool matcher hooks. | Empty `.vscode/mcp.json` scaffold for local use. GitHub cloud review has its own repository MCP configuration. |
| Gemini CLI | — | — |

The installer supplies the scripts under `.claude/hooks/` that the generated hook configurations call. An installed script only runs when its event and matcher survive conversion and the host accepts the configuration. For the optional fleet pack, the desktop session also needs the session-management MCP. For SonarQube, configure the template and runtime environment variables using the setup guide. For Context7-dependent work, confirm the active client exposes both the library-resolution and documentation-query operations. [SonarQube setup](config/mcp-README.md) · [Codex MCP](https://learn.chatgpt.com/docs/extend/mcp) · [Copilot MCP](https://docs.github.com/en/copilot/concepts/customizations/mcp)

## Installation and updates

The Claude pack sources live under `plugins/`. The full installer stages a temporary Claude project and uses pinned rulesync 16.7.0 for rules, hook wiring and supported permission output. Gemini receives the staged root instruction document directly. The converted instructions can inline rules that Claude would apply only to matching paths. The installer writes selected agent profiles in the client’s own format, independently of rulesync's agent importer. [rulesync](https://github.com/dyoshikawa/rulesync)

Codex and Antigravity receive complete skill directories, including referenced files under `_shared/`. The installer skips authoring templates that only contain `SKILL.md.template`. Project resources such as `scripts/repo-config.sh` support config-driven steps. Each host determines which skill metadata it recognizes.

Commit the installed assets and lock files together. Claude uses `.claude/.agentic-dev-tooling.lock`. The other project targets track their output under `.claude/.agentic-dev-tooling.<platform>.lock`. On refresh, the installer updates unchanged managed files and reports local edits. The `--force` option can replace local edits. Paths reserved in `.claude/agentic-protected-paths.json` retain their protection during a force install. [Installer](install.sh)

The platform smoke test installs into separate temporary repositories, verifies the expected files and exercises protection of local changes. To confirm activation on a particular host, start a fresh session in the installed checkout and inspect its available profiles, tools and hook trust. [Platform smoke test](scripts/test-install-platforms.sh)
