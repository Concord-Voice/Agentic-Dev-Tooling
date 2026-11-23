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
| Antigravity | `AGENTS.md` | `.agents/skills/` | Markdown under `.agents/agents/` for code review, documentation, test authoring and feedback analysis. The test writer returns its validation command to the caller for execution. |
| GitHub Copilot | `.github/copilot-instructions.md` | The Copilot target leaves skill installation to the other project targets. Copilot can discover skills in the resulting `.claude/skills/` or `.agents/skills/`. | `.github/agents/code-reviewer.agent.md` for PR review and analysis of supplied CI or tooling failure evidence. |
| Gemini CLI | `GEMINI.md` | — | — |

The `--agents-only` install works offline with Bash, jq and Python 3. It supports the four clients with specialist profiles. It installs the selected profiles and records their hashes. Claude receives the portable Codex roster in this mode. Install or provision any project rules and skills referenced by a profile before assigning work that requires them.

For a standalone checkout, keep project files and referenced resources available inside the checkout or provision them when the environment is built. Claude supports project skill directories that are symlinks when their targets exist. An absolute link into one developer's machine cannot supply that skill to a fresh cloud checkout. [Claude skill discovery](https://code.claude.com/docs/en/skills#choose-where-skills-load) · [Antigravity discovery](https://antigravity.google/docs/customization-discovery/)

## Pinned fleet workflows

An enrolled host can resolve a fleet workflow from a verified tooling checkout with
`python3 -I -B "$ADT/scripts/resolve-fleet-workflow.py" --cache "$PRIVATE_CACHE" --skill dev-lifecycle`.
The single output path identifies the verified skill. Resolve every nested workflow, shared role table and packaged helper in the same edition. This lane retains the lifecycle stages, authoring checkpoints, exact-head review and post-merge monitoring. Security changes use static defensive review and benign regression tests. A missing required role, host restriction, source mismatch or unverified review keeps the corresponding step pending. Private overlays may supply independently verified, read-only defensive specialists under the shared role contract.

When an enrolled Claude or Codex project has an authored role with the same name, the enrollment process can install the public role under `fleet-ROLE` while preserving the authored one. The public renderer accepts `--fleet-alias ROLE` for specific ordinary roles in an empty owner-only staging directory. Use `python3 -I -B "$ADT/scripts/resolve-fleet-workflow.py" --select-role ROLE --platform CLIENT --project "$(pwd -P)"` to obtain the verified native name and path. Dispatch that native name only after confirming the host bound the same file. For the host-reported source path, run `python3 -I -B "$ADT/scripts/resolve-fleet-workflow.py" --verify-role ROLE --platform CLIENT --profile ABSOLUTE_PATH`. A successful digest verifies the installed bytes. Confirm active host capabilities and import provenance separately.

The resolver accepts the nine core lifecycle skills and weekly-deps. Bundled source hashes in `config/fleet-workflows/sources.json` lock each reviewed source and its line edits together. Re-review the edition when updating those source files. Each complete edition is stored under an owner-controlled cache. The standalone package continues to expose its independently selected workflows.

Fleet issue creation reads `issue_creation.sub_issue_linkage` from the intake repository’s default-branch `.claude/repo-config.json`. An omitted setting or `"tasklist"` uses the existing parent-tasklist workflow. Set it to `"native_rest"` to attach children using GitHub’s sub-issue API and update the parent’s plain-bullet index after all requested links verify. A move between parents requires confirmation for that child. An invalid setting or an unreadable configuration stops intake before any write.

## Dispatch and permissions

Use the host's native dispatch operation and the installed role name. For feedback classification, pass the sanitized report payload to `feedback-analyst` in an analysis session provisioned for that data. The Claude profile uses an explicit empty tool list, which Claude Code documents as a tool-free launch. [Claude tool-list behavior](https://code.claude.com/docs/en/errors#agent-would-be-spawned-with-zero-tools)

When a policy requires credential isolation, verify the host's actual credentials and tool access before dispatch. In particular, a Codex custom agent inherits its parent's permissions and MCP servers. Its supported feature switches can disable specific capabilities. A role file cannot independently enforce a read-only identity. [Codex custom agents](https://learn.chatgpt.com/docs/agent-configuration/subagents) · [Antigravity tool and permission inheritance](https://antigravity.google/docs/subagents/)

For untrusted PRs, Codex review requires an independent worker before the caller collects the diff. Use Python 3.11+ and the trusted Codex CLI on a host with working filesystem confinement. Resolve `ADT` to the verified tooling checkout outside the PR. For example, the following checks the review environment before a trusted collector stages the requested PR.

```bash
set -eu
worker="$ADT/scripts/codex-isolated-review.py"
python3 -I -B "$worker" --role code-reviewer --check
review_dir="$(mktemp -d)"
gh pr diff "$pr_number" --repo "$target_repo" --color=never > "$review_dir/input.diff"
python3 -I -B "$worker" --role code-reviewer --input "$review_dir/input.diff"
```

The helper starts a separate Codex app server in an empty directory and checks its effective filesystem policy, approvals and MCP inventory before opening the input. It stages no repository checkout, hooks or connectors. The sandbox probe verifies that workspace writes and reads of a private sibling file are denied. The review uses the source role's model and effort with an existing ChatGPT subscription login. The preflight performs no inference. A failed check leaves the reviewer pending. The helper accepts six defensive reviewer names listed by `--help`; research with Context7 and payload-only feedback classification require their own independently verified capabilities.

The independent reviewer returns a validated JSON object containing a completion status and up to 40 findings. Each finding identifies a severity, a diagnostic category and an inclusive line range in the staged input, counted from one at LF boundaries. The caller can show the reviewer role and those codes to the maintainer, who can inspect that range in the original diff. The example keeps the private staged file for that inspection. Remove the temporary directory after disposition. Unsupported fields, free text, duplicate entries and invalid locations block the review. A finding by itself never authorizes a mutation.

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
